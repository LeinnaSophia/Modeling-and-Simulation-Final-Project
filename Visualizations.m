% Visualizations.m -- crowd-escape metrics over time + density / crush-risk heatmaps
% for both the simple (FinalDraft) and advanced (CrowdSimulation) models.
% Run with:  Visualizations
function Visualizations()
clc; close all;

panicToPlot = 3;                              % advanced model: 1=A, 2=B, 3=C
outDir = fullfile(pwd, 'figures');
if ~exist(outDir, 'dir'), mkdir(outDir); end

% Okabe-Ito colorblind-safe line colors; single-hue sequential heatmap maps
pal.cat     = [0 114 178; 213 94 0; 0 158 115] / 255;
t = linspace(0, 1, 256)';
pal.density = (1-t)*[247 251 255]/255 + t*[8 48 107]/255;    % light -> dark blue
pal.crush   = (1-t)*[255 245 240]/255 + t*[103 0 13]/255;    % light -> dark red

% ---- simple model ----
fprintf('Running simple model...\n');
S = runSimple();
plotSeries(S.t, S.scen, S.names, pal, outDir, 'simple_timeseries', ...
    'Simple model (FinalDraft): crowd metrics over time', [2 2], ...
    {'speed',   'Average speed',  'speed (m/s)'; ...
     'stuck',   'Stuck fraction', 'fraction nearly stuck'; ...
     'polar',   'Polarization',   'alignment (0-1)'; ...
     'overlap', 'Compression',    'avg body overlap (m)'});
plotHeat(S.scen, S.names, pal, outDir, 'simple_heatmaps', ...
    'Simple model (FinalDraft): density & crush-risk heatmaps', []);

% ---- advanced model ----
fprintf('Running advanced model...\n');
A = runAdvanced();
d = A.combo(:, panicToPlot);
pn = A.panicNames{panicToPlot};
plotSeries(A.t, d, A.names, pal, outDir, ['advanced_timeseries_' pn], ...
    sprintf('Advanced model: metrics over time [panic %s]', pn), [2 3], ...
    {'speed',    'Average speed',         'speed (m/s)'; ...
     'overlap',  'Compression (overlap)', 'total body overlap (m)'; ...
     'pressure', 'Crowd pressure',        'peak pressure'; ...
     'entropy',  'Direction entropy',     'disorder (0-1)'; ...
     'evac',     'Evacuated',             'people out (cumulative)'; ...
     'casualty', 'Casualties (fallen)',   'people down (cumulative)'});
plotHeat(d, A.names, pal, outDir, ['advanced_heatmaps_' pn], ...
    sprintf('Advanced model: density & crush-risk heatmaps [panic %s]', pn), A.stage);

fprintf('All figures rendered. PNGs saved to: %s\n', outDir);
end


% ======================= SIMPLE MODEL =======================
function S = runSimple()
rng(42);
L = 10; W = 10; nx = 10; ny = 10; dx = L/nx; dy = W/ny;
nSteps = 300; dt = 0.05; exitX = L; exitY = W/2; v0 = 1.3; r = 0.25; tau = 0.5;
settings = [1 3 0.0; 4 4 0.5; 6 10 0.8];          % [min max panic] per scenario
S.names = {'Baseline','Active','Erratic'};
S.t = (1:nSteps) * dt;

for s = 1:3
    pos = []; vel = []; panic = [];
    for i = 1:ny
        for j = 1:nx
            n = randi(settings(s,1:2));
            pos   = [pos;   (j-1)*dx + rand(n,1)*dx, (i-1)*dy + rand(n,1)*dy];
            vel   = [vel;   zeros(n,2)];
            panic = [panic; settings(s,3)*ones(n,1)];
        end
    end
    N = size(pos,1); N0 = N;
    h = struct('speed',zeros(nSteps,1),'stuck',zeros(nSteps,1), ...
               'polar',zeros(nSteps,1),'overlap',zeros(nSteps,1));
    dens = zeros(ny,nx); crush = zeros(ny,nx); stepsDone = 0;

    for k = 1:nSteps
        if N == 0, break; end

        % direction to exit + panic wobble (in-place dirX update kept as in source)
        toX = exitX - pos(:,1); toY = exitY - pos(:,2);
        len = sqrt(toX.^2 + toY.^2) + 1e-9;
        dirX = toX./len; dirY = toY./len;
        ang = panic .* pi .* randn(N,1);
        dirX = cos(ang).*dirX - sin(ang).*dirY;
        dirY = sin(ang).*dirX + cos(ang).*dirY;

        % forces
        [Fx, Fy, ovAgent, ovTotal] = pairForcesSimple(pos, N, r, ...
            2.0*(1+mean(panic)), 0.3, 50*(1+2*mean(panic)));

        % integrate
        vel(:,1) = vel(:,1) + (dirX*v0 - vel(:,1))/tau*dt + Fx*dt/80;
        vel(:,2) = vel(:,2) + (dirY*v0 - vel(:,2))/tau*dt + Fy*dt/80;
        pos = pos + vel*dt;
        pos = min(max(pos, 0.1), L-0.1);

        % exit
        out = pos(:,1) >= L - 0.2;
        pos(out,:) = []; vel(out,:) = []; panic(out) = []; ovAgent(out) = [];
        N = size(pos,1);
        stepsDone = k;
        if N == 0, continue; end

        % metrics
        sp = sqrt(sum(vel.^2, 2));
        h.speed(k) = mean(sp);
        h.stuck(k) = mean(sp < 0.2*v0);
        if any(sp > 1e-6)
            u = vel ./ (sp + 1e-9);
            h.polar(k) = norm(mean(u, 1));
        end
        h.overlap(k) = ovTotal / N;
        [dens, crush] = accumCells(dens, crush, pos, ovAgent, dx, dy, nx, ny);
    end
    h.density = dens / max(stepsDone,1);
    h.crush   = crush;
    S.scen(s,1) = h;
end
end


function [Fx, Fy, ovAgent, ovTotal] = pairForcesSimple(pos, N, r, A, B, kBody)
% dist<2r: linear contact spring; 2r<=dist<1: exponential personal space
Fx = zeros(N,1); Fy = zeros(N,1); ovAgent = zeros(N,1); ovTotal = 0;
if N < 2, return; end
dx = pos(:,1)' - pos(:,1); dy = pos(:,2)' - pos(:,2);
dist = sqrt(dx.^2 + dy.^2); dist(1:N+1:end) = inf;
contact = dist < 2*r;
social  = dist < 1 & ~contact;
mag = zeros(N);
mag(social)  = A * exp((2*r - dist(social))/B);
mag(contact) = kBody * (2*r - dist(contact));
Fx = -sum(mag.*dx./dist, 2);
Fy = -sum(mag.*dy./dist, 2);
ov = max(0, 2*r - dist);
ovAgent = sum(ov, 2);
ovTotal = sum(ov(:))/2;
end


% ======================= ADVANCED MODEL =======================
function A = runAdvanced()
rng(42);
L = 10; W = 10; nx = 10; ny = 10; dx = L/nx; dy = W/ny; cellArea = dx*dy;
exits = [L W/2 3; 0 W/2 3];                     % [x y width]
obs = [3.5 4.0 6.5 6.0];                        % stage: [xa ya xb yb]
nSteps = 300; dt = 0.05; settleSteps = 30;

R = 0.25; D = 2*R; mass = 80;
vLow = 0.8; vMax = 1.8; vPanic = 2.0; vCap = 3.0;
Arep = 200; Brep = 0.3; kBody = 3000; kFric = 1500;
rhoDrop = 5.4; range = 2.0; fMax = 2000; fallForce = 1500;

panicRanges = [0 0.49; 0.5 0.79; 0.8 1.0];
settings = [1 3; 4 4; 5 10];
A.names = {'Baseline','Dense','Densest'};
A.panicNames = {'LevelA','LevelB','LevelC'};
A.t = (1:nSteps) * dt;
A.stage = struct('obs',obs,'exits',exits,'L',L);

% wall segments (with exit gaps) + obstacle edges
h1 = exits(1,3)/2; c1 = exits(1,2); h2 = exits(2,3)/2; c2 = exits(2,2);
walls = [0 0 L 0; 0 W L W; L 0 L c1-h1; L c1+h1 L W; 0 0 0 c2-h2; 0 c2+h2 0 W];
xa = obs(1); ya = obs(2); xb = obs(3); yb = obs(4);
walls = [walls; xa ya xb ya; xb ya xb yb; xb yb xa yb; xa yb xa ya];

for sc = 1:3
    for pl = 1:3
        % ---- initial crowd (agents inside the stage are dropped) ----
        pos = []; panic = []; base = [];
        for cy = 1:ny
            for cx = 1:nx
                n  = randi(settings(sc,:));
                px = (cx-1)*dx + rand(n,1)*dx;
                py = (cy-1)*dy + rand(n,1)*dy;
                pk = panicRanges(pl,1) + rand(n,1)*diff(panicRanges(pl,:));
                sp = vLow + rand(n,1)*(vMax-vLow);
                keep = ~(px>=xa & px<=xb & py>=ya & py<=yb);
                pos = [pos; px(keep) py(keep)];
                panic = [panic; pk(keep)];
                base = [base; sp(keep)];
            end
        end
        N = size(pos,1); N0 = N;
        vel = zeros(N,2); fallen = false(N,1);

        % ---- settling: relax overlaps, no desired motion ----
        for ss = 1:settleSteps
            if N < 2, break; end
            [fx, fy] = agentForces(pos, zeros(N,2), N, D, Arep, Brep, kBody, kFric, range);
            [wx, wy] = wallForces(pos, zeros(N,2), walls, R, Arep, Brep, kBody, kFric);
            fx = fx + wx; fy = fy + wy;
            [fx, fy] = capForce(fx, fy, fMax);
            vel = vel*0.5 + [fx fy]/mass*dt;
            pos = pos + vel*dt;
            pos = min(max(pos, R), [L W]-R);
            pos = pushOutObstacles(pos, obs, R);
        end
        vel = zeros(N,2);

        h = struct('speed',zeros(nSteps,1),'pressure',zeros(nSteps,1), ...
                   'entropy',zeros(nSteps,1),'overlap',zeros(nSteps,1), ...
                   'evac',zeros(nSteps,1),'casualty',zeros(nSteps,1));
        dens = zeros(ny,nx); crush = zeros(ny,nx);
        nEvac = 0; nCas = 0; stepsDone = 0;

        for step = 1:nSteps
            if N == 0, break; end

            % direction to nearest exit + panic jitter
            dE = [hypot(exits(1,1)-pos(:,1), exits(1,2)-pos(:,2)), ...
                  hypot(exits(2,1)-pos(:,1), exits(2,2)-pos(:,2))];
            [~, ne] = min(dE, [], 2);
            tx = exits(ne,1) - pos(:,1); ty = exits(ne,2) - pos(:,2);
            dd = max(sqrt(tx.^2 + ty.^2), 1e-9);
            tx = tx./dd; ty = ty./dd;
            jit = panic .* pi .* randn(N,1);
            jx = cos(jit).*tx - sin(jit).*ty;
            jy = sin(jit).*tx + cos(jit).*ty;

            % local density (people / m^2 in own cell) slows agents down
            cell = cellIndex(pos, dx, dy, nx, ny);                  % [ix iy]
            counts = accumarray(cell, 1, [nx ny]);
            rho = counts(sub2ind([nx ny], cell(:,1), cell(:,2))) / cellArea;
            vDes = ((1-panic).*base + panic*vPanic) .* exp(-rho/rhoDrop);
            vDes(fallen) = 0;
            relax = 0.5*panic + 5.0*(1-panic);

            % forces: agents + walls/obstacle
            [fx, fy, bodyF, ovAgent] = agentForces(pos, vel, N, D, Arep, Brep, kBody, kFric, range);
            [wx, wy, wBody] = wallForces(pos, vel, walls, R, Arep, Brep, kBody, kFric);
            fx = fx + wx; fy = fy + wy; bodyF = bodyF + wBody;
            [fx, fy] = capForce(fx, fy, fMax);

            % falling
            newFall = ~fallen & (bodyF > fallForce);
            fallen(newFall) = true;
            nCas = nCas + sum(newFall);
            vel(newFall,:) = 0;

            % integrate
            vel = vel + ([vDes.*jx vDes.*jy] - vel)./relax*dt + [fx fy]/mass*dt;
            vel(fallen,:) = vel(fallen,:)*0.1;
            sp = sqrt(sum(vel.^2, 2));
            fast = sp > vCap;
            vel(fast,:) = vel(fast,:) .* (vCap./sp(fast));
            pos = pos + vel*dt;

            % exits (right exit at x = L, left exit at x = 0)
            esc = false(N,1);
            for e = 1:2
                inGap = pos(:,2) >= exits(e,2)-exits(e,3)/2 & pos(:,2) <= exits(e,2)+exits(e,3)/2;
                if exits(e,1) >= L, atX = pos(:,1) >= L-R; else, atX = pos(:,1) <= R; end
                esc = esc | (~fallen & atX & inGap);
            end
            if any(esc)
                nEvac = nEvac + sum(esc);
                k = ~esc;
                pos = pos(k,:); vel = vel(k,:); panic = panic(k);
                base = base(k); fallen = fallen(k); ovAgent = ovAgent(k);
                N = size(pos,1);
            end
            if N > 0
                pos = min(max(pos, R), [L W]-R);
                pos = pushOutObstacles(pos, obs, R);
            end

            h.evac(step) = nEvac; h.casualty(step) = nCas; stepsDone = step;

            % metrics
            if N >= 1
                h.speed(step) = mean(sqrt(sum(vel.^2, 2)));
            end
            if N > 1
                cell = cellIndex(pos, dx, dy, nx, ny);
                for cX = 1:nx
                    for cY = 1:ny
                        in = cell(:,1)==cX & cell(:,2)==cY;
                        nC = sum(in);
                        if nC < 2, continue; end
                        vx = vel(in,1); vy = vel(in,2);
                        % pressure = density * velocity variance
                        h.pressure(step) = max(h.pressure(step), ...
                            (nC/cellArea) * mean((vx-mean(vx)).^2 + (vy-mean(vy)).^2));
                        % entropy of movement directions (8 bins, normalized)
                        mv = sqrt(vx.^2 + vy.^2) > 0.01;
                        if sum(mv) >= 2
                            cnt = histcounts(atan2(vy(mv), vx(mv)), -pi:pi/4:pi);
                            p = cnt(cnt>0) / sum(mv);
                            h.entropy(step) = max(h.entropy(step), -sum(p.*log2(p))/log2(8));
                        end
                    end
                end
                md = sqrt((pos(:,1)'-pos(:,1)).^2 + (pos(:,2)'-pos(:,2)).^2);
                md(1:N+1:end) = inf;
                h.overlap(step) = sum(max(0, D-md), 'all')/2;
            end
            if N >= 1
                [dens, crush] = accumCells(dens, crush, pos, ovAgent, dx, dy, nx, ny);
            end
        end
        h.density = dens / max(stepsDone,1);
        h.crush   = crush;
        A.combo(sc,pl) = h;
    end
end
end


function [Fx, Fy, bodyF, ovAgent] = agentForces(pos, vel, N, D, Arep, Brep, kBody, kFric, range)
% Agent-agent: exponential repulsion + body compression + sliding friction
Fx = zeros(N,1); Fy = zeros(N,1); bodyF = zeros(N,1); ovAgent = zeros(N,1);
if N < 2, return; end
dx = pos(:,1)' - pos(:,1); dy = pos(:,2)' - pos(:,2);
dist = sqrt(dx.^2 + dy.^2); dist(1:N+1:end) = inf;
nX = dx./dist; nY = dy./dist; tX = -nY; tY = nX;
ov   = max(0, D - dist);
rep  = Arep*exp((D-dist)/Brep); rep(dist > range) = 0;
comp = kBody*ov;
fric = kFric * ov .* ((vel(:,1)'-vel(:,1)).*tX + (vel(:,2)'-vel(:,2)).*tY);
Fx = sum(-(rep+comp).*nX + fric.*tX, 2);
Fy = sum(-(rep+comp).*nY + fric.*tY, 2);
bodyF = sum(comp, 2);
ovAgent = sum(ov, 2);
end


function [Fx, Fy, bodyF] = wallForces(pos, vel, walls, R, Arep, Brep, kBody, kFric)
N = size(pos,1);
Fx = zeros(N,1); Fy = zeros(N,1); bodyF = zeros(N,1);
for w = 1:size(walls,1)
    [wd, nX, nY] = distToSegment(pos(:,1), pos(:,2), walls(w,:));
    ok  = wd > 1e-6;
    wov = max(0, R - wd);
    wr  = Arep*exp((R-wd)/Brep);
    wc  = kBody*wov;
    tX = -nY; tY = nX;
    wf  = kFric*wov .* (vel(:,1).*tX + vel(:,2).*tY);
    Fx = Fx + ((wr+wc).*nX - wf.*tX).*ok;
    Fy = Fy + ((wr+wc).*nY - wf.*tY).*ok;
    bodyF = bodyF + wc.*ok;
end
end


function [dist, nX, nY] = distToSegment(aX, aY, s)
% distance from points to segment s=[x1 y1 x2 y2] and outward unit normal
sx = s(3)-s(1); sy = s(4)-s(2); L2 = sx^2 + sy^2;
if L2 < 1e-12
    cx = s(1)*ones(size(aX)); cy = s(2)*ones(size(aX));
else
    t = max(0, min(1, ((aX-s(1))*sx + (aY-s(2))*sy)/L2));
    cx = s(1) + t*sx; cy = s(2) + t*sy;
end
gx = aX - cx; gy = aY - cy;
dist = sqrt(gx.^2 + gy.^2);
nz = dist > 1e-12;
nX = zeros(size(aX)); nY = zeros(size(aX));
nX(nz) = gx(nz)./dist(nz); nY(nz) = gy(nz)./dist(nz);
end


function [fx, fy] = capForce(fx, fy, fMax)
m = sqrt(fx.^2 + fy.^2); big = m > fMax;
fx(big) = fx(big).*fMax./m(big);
fy(big) = fy(big).*fMax./m(big);
end


function pos = pushOutObstacles(pos, obs, R)
xa = obs(1); ya = obs(2); xb = obs(3); yb = obs(4);
for a = find(pos(:,1)>xa & pos(:,1)<xb & pos(:,2)>ya & pos(:,2)<yb)'
    [~, side] = min([pos(a,1)-xa, xb-pos(a,1), pos(a,2)-ya, yb-pos(a,2)]);
    switch side
        case 1, pos(a,1) = xa - R;
        case 2, pos(a,1) = xb + R;
        case 3, pos(a,2) = ya - R;
        case 4, pos(a,2) = yb + R;
    end
end
end


function c = cellIndex(pos, dx, dy, nx, ny)
% [ix iy] grid cell of each agent, clamped to the grid
c = [min(max(floor(pos(:,1)/dx)+1, 1), nx), min(max(floor(pos(:,2)/dy)+1, 1), ny)];
end


function [dens, crush] = accumCells(dens, crush, pos, ovAgent, dx, dy, nx, ny)
% Accumulate occupancy and body overlap per cell (grid is row = y, col = x)
c = cellIndex(pos, dx, dy, nx, ny);
lin = sub2ind([ny nx], c(:,2), c(:,1));
dens  = dens  + reshape(accumarray(lin, 1,       [ny*nx 1]), [ny nx]);
crush = crush + reshape(accumarray(lin, ovAgent, [ny*nx 1]), [ny nx]);
end


% ======================= PLOTTING =======================
function plotSeries(t, d, names, pal, outDir, file, ttl, layout, specs)
f = figure('Color','w','Position',[80 60 380*layout(2)+100 360*layout(1)]);
for p = 1:size(specs,1)
    subplot(layout(1), layout(2), p); hold on;
    for s = 1:numel(names)
        plot(t, d(s).(specs{p,1}), 'Color', pal.cat(s,:), 'LineWidth', 2);
    end
    grid on; set(gca,'GridAlpha',0.15,'Box','off');
    title(specs{p,2},'FontWeight','bold'); xlabel('time (s)'); ylabel(specs{p,3});
    xlim([t(1) t(end)]);
    if p == 1, legend(names,'Location','best','Box','off'); end
end
sgtitle(ttl,'FontWeight','bold','FontSize',13);
saveFig(f, outDir, file);
end


function plotHeat(d, names, pal, outDir, file, ttl, stage)
% Top row: density; bottom row: crush risk. Color scales shared across scenarios.
nS = numel(names);
xc = 0.5:9.5;
f = figure('Color','w','Position',[40 40 400*nS 660]);
rows = {'density', pal.density, 'mean people / m^2',   'density'; ...
        'crush',   pal.crush,   'accumulated overlap', 'crush risk'};
for r = 1:2
    cmax = max(eps, max(arrayfun(@(s) max(d(s).(rows{r,1})(:)), 1:nS)));
    for s = 1:nS
        subplot(2, nS, (r-1)*nS + s);
        imagesc(xc, xc, d(s).(rows{r,1})); axis xy equal tight;
        colormap(gca, rows{r,2}); caxis([0 cmax]);
        if ~isempty(stage), overlayStage(stage); end
        title([names{s} ' - ' rows{r,4}],'FontWeight','bold');
        xlabel('x (m)'); ylabel('y (m)');
        cb = colorbar; cb.Label.String = rows{r,3};
    end
end
sgtitle(ttl,'FontWeight','bold','FontSize',13);
saveFig(f, outDir, file);
end


function overlayStage(st)
% stage obstacle (grey box) and exit gaps (green)
hold on;
o = st.obs;
rectangle('Position',[o(1) o(2) o(3)-o(1) o(4)-o(2)], ...
    'EdgeColor',[0.25 0.25 0.25],'LineWidth',1.5);
text(mean(o([1 3])), mean(o([2 4])), 'STAGE', 'Color',[0.2 0.2 0.2], ...
    'HorizontalAlignment','center','FontSize',8,'FontWeight','bold');
for e = 1:size(st.exits,1)
    x = st.exits(e,1) * (st.exits(e,1) >= st.L);   % 0 or L
    plot([x x], st.exits(e,2) + st.exits(e,3)/2*[-1 1], '-', 'Color',[0 0.5 0], 'LineWidth',3);
end
hold off;
end


function saveFig(f, outDir, name)
fn = fullfile(outDir, [name '.png']);
try, exportgraphics(f, fn, 'Resolution', 150);
catch, print(f, fn, '-dpng', '-r150'); end
fprintf('  saved %s\n', fn);
end
