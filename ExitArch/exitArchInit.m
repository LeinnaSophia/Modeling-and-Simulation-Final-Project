function S = exitArchInit(P)
%EXITARCHINIT  Build the room and place the crowd. Returns the sim state S.
%   Random placement: each agent is placed at a random walkable spot with
%   overlap checking (JC's approach). Agent count set by density scenario.

if ~isempty(P.seed), rng(P.seed); end

% --- density scenario sets total agent count ---
switch P.densityScenario
    case 'Baseline',    P.nAgents = 250;
    case 'Dense',       P.nAgents = 500;
    case 'Crush Risk',  P.nAgents = 800;
end

% --- panic level sets panic range (independent of density) ---
switch P.panicLevel
    case 'Level A', P.panicMin = 0.0;  P.panicMax = 0.49;
    case 'Level B', P.panicMin = 0.50; P.panicMax = 0.79;
    case 'Level C', P.panicMin = 0.80; P.panicMax = 1.00;
end

% scale stage proportionally (depth ~22% of L, spans middle 66% of H)
if P.concertScenario
    P.stageDepth = 0.22 * P.L;
    P.stageYMin  = 0.17 * P.H;
    P.stageYMax  = 0.83 * P.H;
end

% scale obstacle proportionally (centered at 55% of L, 50% of H)
if P.centralObstacle
    cx = 0.55 * P.L; cy = 0.5 * P.H;
    ow = 0.15 * P.L; oh = 0.25 * P.H;
    P.obstacleXMin = cx - ow/2;
    P.obstacleXMax = cx + ow/2;
    P.obstacleYMin = cy - oh/2;
    P.obstacleYMax = cy + oh/2;
end

G = buildGeometry(P);
G = addDistanceField(G, P);

% --- random placement (JC's approach: each agent gets a random walkable spot) ---
% Leave 1.5 m clear in front of the door so agents flow toward it.
N = round(P.nAgents);
rr = P.rMin + (P.rMax - P.rMin)*rand(N,1);
placeBox = [0, P.L - 1.5, 0, P.H];
positions = zeros(N, 2);
for i = 1:N
    positions(i,:) = exitArchPlace(G, positions(1:i-1,:), rr(1:i-1), rr(i), placeBox, 300);
end

S.P = P;
S.G = G;
S.pos = positions;
S.r   = rr;
S.vel = zeros(N,2);

S.v0    = P.v0Min + (P.v0Max - P.v0Min)*rand(N,1);
S.panic = P.panicMin + (P.panicMax - P.panicMin)*rand(N,1);
S.tau   = 0.5 * S.panic + 5.0 * (1 - S.panic);

S.t            = 0;
S.exitTimes    = zeros(0,1);
S.lastExit     = NaN;
S.longestStall = 0;
S.load         = zeros(N,1);
S.peakLoadNow  = 0;
S.peakLoad     = 0;
S.everCrushed  = false(N,1);
S.nCrushedGone = 0;
S.status       = ones(N,1);
S.contacts     = zeros(0,3);
S.localDensity = zeros(N,1);
S.done         = false;
S.evacTime     = NaN;
S.initialAgents = N;

% --- lightweight settling: push overlapping agents apart ---
% Only repulsion + wall forces, no density matrix, no direction-finding.
settleVel = zeros(N, 2);
for step = 1:30
    X = S.pos(:,1); Y = S.pos(:,2); rr = S.r;
    Fs = zeros(N, 2);

    % pairwise repulsion (no friction needed during settling)
    if N > 1
        dX = X - X.'; dY = Y - Y.';
        D2 = dX.^2 + dY.^2;
        Rs = rr + rr.';
        mask = triu(D2 < (Rs + 1.0).^2, 1);
        idx = find(mask);
        if ~isempty(idx)
            [I, J] = ind2sub([N N], idx);
            d = max(sqrt(D2(idx)), 1e-6);
            nx = dX(idx)./d; ny = dY(idx)./d;
            g = max(Rs(idx) - d, 0);
            fn = P.A*exp((Rs(idx) - d)/P.B) + P.k*g;
            Fs(:,1) = Fs(:,1) + accumarray(I, fn.*nx, [N 1]) ...
                              - accumarray(J, fn.*nx, [N 1]);
            Fs(:,2) = Fs(:,2) + accumarray(I, fn.*ny, [N 1]) ...
                              - accumarray(J, fn.*ny, [N 1]);
        end
    end

    % wall repulsion
    for ws = 1:size(G.walls, 1)
        w = G.walls(ws,:);
        wax = w(3)-w(1); way = w(4)-w(2); wl2 = wax^2+way^2;
        u = ((X-w(1))*wax + (Y-w(2))*way) / wl2;
        m = u > 0 & u < 1;
        if ~any(m), continue; end
        ddx = X(m)-(w(1)+u(m)*wax); ddy = Y(m)-(w(2)+u(m)*way);
        dc = max(hypot(ddx,ddy), 1e-6);
        g = max(rr(m)-dc, 0);
        fn = P.A*exp((rr(m)-dc)/P.B) + P.k*g;
        Fs(m,1) = Fs(m,1) + fn.*(ddx./dc);
        Fs(m,2) = Fs(m,2) + fn.*(ddy./dc);
    end

    % pillar repulsion
    for pc = 1:size(G.pillars, 1)
        pp = G.pillars(pc,:);
        m = hypot(X-pp(1), Y-pp(2)) < pp(3) + 1.5;
        if ~any(m), continue; end
        ddx = X(m)-pp(1); ddy = Y(m)-pp(2);
        dc = max(hypot(ddx,ddy), 1e-6);
        d = dc - pp(3);
        g = max(rr(m)-d, 0);
        fn = P.A*exp((rr(m)-d)/P.B) + P.k*g;
        Fs(m,1) = Fs(m,1) + fn.*(ddx./dc);
        Fs(m,2) = Fs(m,2) + fn.*(ddy./dc);
    end

    % force cap (like CrowdSimulation.m) to prevent blowup
    fMag = sqrt(sum(Fs.^2, 2));
    big = fMag > 2000;
    if any(big), Fs(big,:) = Fs(big,:) .* (2000./fMag(big)); end

    % damped integration
    sDt = 0.01;
    settleVel = 0.3*settleVel + Fs/P.mass*sDt;
    sp = sqrt(sum(settleVel.^2, 2));
    fast = sp > 2.0;
    if any(fast), settleVel(fast,:) = settleVel(fast,:)./sp(fast)*2.0; end
    S.pos = S.pos + settleVel*sDt;

    % clamp to room interior
    S.pos(:,1) = max(rr+0.02, min(S.pos(:,1), G.L-0.02));
    S.pos(:,2) = max(rr+0.02, min(S.pos(:,2), G.H-0.02));

    % push out of stage / obstacle
    if P.concertScenario
        sd = P.stageDepth; sy1 = P.stageYMin; sy2 = P.stageYMax;
        ins = S.pos(:,1)<sd & S.pos(:,2)>sy1 & S.pos(:,2)<sy2;
        if any(ins), S.pos(ins,1) = sd+rr(ins)*0.5; settleVel(ins,:) = 0; end
    end
    if P.centralObstacle
        ox1=P.obstacleXMin; oy1=P.obstacleYMin;
        ox2=P.obstacleXMax; oy2=P.obstacleYMax;
        ins = S.pos(:,1)>ox1 & S.pos(:,1)<ox2 & S.pos(:,2)>oy1 & S.pos(:,2)<oy2;
        if any(ins)
            dL=S.pos(ins,1)-ox1; dR=ox2-S.pos(ins,1);
            dB=S.pos(ins,2)-oy1; dT=oy2-S.pos(ins,2);
            [~,side]=min([dL dR dB dT],[],2);
            ii=find(ins);
            for q=1:numel(ii)
                switch side(q)
                    case 1, S.pos(ii(q),1)=ox1-rr(ii(q))*0.5;
                    case 2, S.pos(ii(q),1)=ox2+rr(ii(q))*0.5;
                    case 3, S.pos(ii(q),2)=oy1-rr(ii(q))*0.5;
                    case 4, S.pos(ii(q),2)=oy2+rr(ii(q))*0.5;
                end
            end
            settleVel(ins,:) = 0;
        end
    end
end
S.vel = zeros(N, 2);
end

% -------------------------------------------------------------------------
function G = buildGeometry(P)
L = P.L; H = P.H; T = P.wallT; w = P.doorWidth;

switch P.layout
    case 'Twin Doors'
        centres = [H/3; 2*H/3];
    otherwise
        centres = H/2;
end
doors = [L*ones(numel(centres),1), centres - w/2, centres + w/2];

walls = [0 0 L 0;          % bottom
         0 H L H;          % top
         0 0 0 H];         % left
edges = [0; reshape(doors(:,2:3).', [], 1); H];
for k = 1:2:numel(edges)
    if edges(k+1) - edges(k) > 1e-9
        walls(end+1,:) = [L edges(k) L edges(k+1)]; %#ok<AGROW>
    end
end
corners = zeros(0,2);
for k = 1:size(doors,1)
    walls(end+1,:) = [L doors(k,2) L+T doors(k,2)]; %#ok<AGROW>
    walls(end+1,:) = [L doors(k,3) L+T doors(k,3)]; %#ok<AGROW>
    corners = [corners; L doors(k,2); L doors(k,3); L+T doors(k,2); L+T doors(k,3)]; %#ok<AGROW>
end

pillars = zeros(0,3);
F = 0;
if strcmp(P.layout, 'Pillar')
    pillars = [L - P.pillarDist, H/2, P.pillarRadius];
end
if strcmp(P.layout, 'Funnel')
    F = P.funnelLen;
    walls(end+1,:) = [L-F 0 L doors(1,2)];
    walls(end+1,:) = [L-F H L doors(1,3)];
end

hasStage    = P.concertScenario;
hasObstacle = P.centralObstacle;

stagePolys = {};
if hasStage
    sd = P.stageDepth;
    sy1 = P.stageYMin; sy2 = P.stageYMax;
    walls(end+1,:) = [0   sy1 sd  sy1];
    walls(end+1,:) = [sd  sy1 sd  sy2];
    walls(end+1,:) = [sd  sy2 0   sy2];
    stagePolys = {[0 sy1; sd sy1; sd sy2; 0 sy2]};
end

obstPolys = {};
if hasObstacle
    ox1 = P.obstacleXMin; oy1 = P.obstacleYMin;
    ox2 = P.obstacleXMax; oy2 = P.obstacleYMax;
    walls(end+1,:) = [ox1 oy1 ox2 oy1];
    walls(end+1,:) = [ox2 oy1 ox2 oy2];
    walls(end+1,:) = [ox2 oy2 ox1 oy2];
    walls(end+1,:) = [ox1 oy2 ox1 oy1];
    obstPolys = {[ox1 oy1; ox2 oy1; ox2 oy2; ox1 oy2]};
end

polys = {[-T -T; L+T -T; L+T 0; -T 0], ...
         [-T H; L+T H; L+T H+T; -T H+T], ...
         [-T 0; 0 0; 0 H; -T H]};
for k = 1:2:numel(edges)
    if edges(k+1) - edges(k) > 1e-9
        polys{end+1} = [L edges(k); L+T edges(k); L+T edges(k+1); L edges(k+1)]; %#ok<AGROW>
    end
end
if F > 0
    polys{end+1} = [L-F 0; L 0; L doors(1,2)];
    polys{end+1} = [L-F H; L H; L doors(1,3)];
end
for q = 1:numel(stagePolys)
    polys{end+1} = stagePolys{q}; %#ok<AGROW>
end
for q = 1:numel(obstPolys)
    polys{end+1} = obstPolys{q}; %#ok<AGROW>
end

G.L = L; G.H = H; G.wallT = T;
G.doors   = doors;
G.walls   = walls;
G.corners = corners;
G.pillars = pillars;
G.polys   = polys;
G.exitX   = L + T + 0.4;
if hasStage
    G.spawnBox = [P.stageDepth + 0.5, 3 + P.stageDepth, 0, H];
else
    G.spawnBox = [0.5, 3.5, 0, H];
end
G.walkable = @(x, y, rr) walkable(x, y, rr, L, H, F, doors, pillars, P);
end

% -------------------------------------------------------------------------
function ok = walkable(x, y, rr, L, H, F, doors, pillars, P)
ok = x > rr & x < L - rr & y > rr & y < H - rr;
if F > 0
    ylo = doors(1,2); yhi = doors(1,3);
    nl = hypot(F, ylo); nu = hypot(F, H - yhi);
    sLow = ((x - (L-F))*(-ylo) + y*F) / nl;
    sUp  = ((x - (L-F))*(yhi - H) + (y - H)*(-F)) / nu;
    ok = ok & sLow > rr & sUp > rr;
end
for k = 1:size(pillars,1)
    ok = ok & hypot(x - pillars(k,1), y - pillars(k,2)) > pillars(k,3) + rr;
end
hasStage    = P.concertScenario;
hasObstacle = P.centralObstacle;
if hasStage
    sd = P.stageDepth; sy1 = P.stageYMin; sy2 = P.stageYMax;
    ok = ok & ~(x < sd + rr & y > sy1 - rr & y < sy2 + rr);
end
if hasObstacle
    ox1 = P.obstacleXMin; oy1 = P.obstacleYMin;
    ox2 = P.obstacleXMax; oy2 = P.obstacleYMax;
    ok = ok & ~(x > ox1 - rr & x < ox2 + rr & y > oy1 - rr & y < oy2 + rr);
end
end

% -------------------------------------------------------------------------
function G = addDistanceField(G, P)
res = 0.3;
L = G.L; H = G.H; T = G.wallT;
xc = res/2 : res : (L + T + 1.5);
yc = res/2 : res : H;
nx = numel(xc); ny = numel(yc);
[XX, YY] = meshgrid(xc, yc);

roomOK = G.walkable(XX, YY, 0);
doorOK = false(ny, nx);
for d = 1:size(G.doors, 1)
    doorOK = doorOK | (XX >= L & YY >= G.doors(d,2) & YY <= G.doors(d,3));
end
blocked = ~(roomOK | doorOK);

dist = inf(ny, nx);
queue = zeros(ny * nx, 2);
head = 1; tail = 0;
goalCells = XX > L + T & doorOK;
[gy, gx] = find(goalCells & ~blocked);
for k = 1:numel(gy)
    dist(gy(k), gx(k)) = 0;
    tail = tail + 1;
    queue(tail, :) = [gy(k), gx(k)];
end

dirs = [-1 0; 1 0; 0 -1; 0 1];
while head <= tail
    cy = queue(head, 1); cx = queue(head, 2);
    head = head + 1;
    for d = 1:4
        r2 = cy + dirs(d, 1); c2 = cx + dirs(d, 2);
        if r2 < 1 || r2 > ny || c2 < 1 || c2 > nx, continue; end
        if blocked(r2, c2), continue; end
        nd = dist(cy, cx) + 1;
        if nd < dist(r2, c2)
            dist(r2, c2) = nd;
            tail = tail + 1;
            queue(tail, :) = [r2, c2];
        end
    end
end

G.distField = dist * res;
G.distRes = res;
end
