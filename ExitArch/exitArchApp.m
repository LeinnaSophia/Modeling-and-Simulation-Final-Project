function exitArchApp()
%EXITARCHAPP  Interactive crowd simulation for concert evacuation scenarios.
%
%   Run:  cd ExitArch; exitArchApp
%
%   Three density scenarios set the crowd count.  Three panic levels set
%   the urgency independently.  All agents spawn at t=0 and evacuate.

P = exitArchParams();
S = exitArchInit(P);
running = false;

NV = 16; th = (0:NV-1)*2*pi/NV; CX = cos(th); CY = sin(th);
UI = [0.97 0.97 0.98];

COL = [0.64 0.80 0.92;    % walking
       0.38 0.60 0.84;    % slowed
       0.18 0.29 0.49;    % stuck
       0.92 0.46 0.29];   % crushed

% ---------------------------------------------------------------- figure
fig = figure('Name', 'Exit Arch', 'NumberTitle', 'off', 'Color', UI, ...
    'Position', [40 40 1200 700], 'MenuBar', 'figure', 'ToolBar', 'figure', ...
    'CloseRequestFcn', @onClose);
try theme(fig, 'light'); catch, end

hTitle = uicontrol(fig, 'Style', 'text', 'Units', 'normalized', ...
    'Position', [0.02 0.93 0.64 0.06], 'String', 'Concert Scenario', ...
    'FontSize', 22, 'FontWeight', 'bold', 'BackgroundColor', UI, ...
    'HorizontalAlignment', 'left', 'Visible', onOff(P.concertScenario));

ax = axes('Parent', fig, 'Units', 'normalized', 'Position', [0.02 0.20 0.64 0.72], ...
    'Color', [0.90 0.90 0.89], 'XTick', [], 'YTick', [], 'Box', 'on', ...
    'XColor', [0.8 0.8 0.8], 'YColor', [0.8 0.8 0.8]);
hold(ax, 'on'); axis(ax, 'equal');
colormap(ax, [linspace(1, 0.85, 64)', linspace(0.95, 0.15, 64)', linspace(0.6, 0.1, 64)']);
clim(ax, [0 6]);

hHeat   = imagesc(ax, [0 1], [0 1], zeros(2), 'AlphaData', 0, 'Visible', 'off');
geomH   = gobjects(0);
hGround = gobjects(0);
hAgents = patch(ax, 'Faces', [], 'Vertices', zeros(0,2), 'FaceColor', 'flat', ...
    'EdgeColor', [1 1 1], 'LineWidth', 0.25, 'FaceVertexCData', zeros(0,3));
chainCol = [0.95 0.65 0.35; 0.90 0.40 0.20; 0.70 0.10 0.10];
hChains = gobjects(3,1);
for q = 1:3
    hChains(q) = line(ax, NaN, NaN, 'Color', chainCol(q,:), 'LineWidth', 0.8 + 1.2*q);
end

hStatus = text(ax, 0.012, 0.985, '', 'Units', 'normalized', 'VerticalAlignment', 'top', ...
    'FontWeight', 'bold', 'FontSize', 11, 'BackgroundColor', 'w', 'Margin', 5, ...
    'EdgeColor', [0.85 0.85 0.85]);

lh = gobjects(4,1);
for q = 1:4, lh(q) = patch(ax, NaN, NaN, COL(q,:), 'EdgeColor', 'none'); end
legend(ax, lh, {'Walking', 'Slowed', 'Stuck', 'Crushed'}, ...
    'Orientation', 'horizontal', 'Location', 'northoutside', 'Box', 'off', ...
    'FontSize', 9, 'AutoUpdate', 'off');

% metric cards (7 cards in one row under the axes)
cardW = 0.085; nCards = 7; cardGap = 0.007;
totalW = nCards*cardW + (nCards-1)*cardGap;
cardX = 0.02 + 0.64/2 - totalW/2;
cards = gobjects(nCards,1);
cardTitles = {'AGENTS', 'AVG SPEED', 'OUTFLOW', 'EVACUATED', 'CRUSHED', 'STALL', 'PEAK LOAD'};
for q = 1:nCards
    pnl = uipanel(fig, 'Units', 'normalized', ...
        'Position', [cardX + (q-1)*(cardW + cardGap) 0.065 cardW 0.11], ...
        'BackgroundColor', 'w', 'BorderType', 'line', 'HighlightColor', [0.85 0.85 0.88]);
    uicontrol(pnl, 'Style', 'text', 'Units', 'normalized', 'Position', [0 0.60 1 0.28], ...
        'String', cardTitles{q}, 'BackgroundColor', 'w', 'FontSize', 8, ...
        'ForegroundColor', [0.35 0.4 0.5]);
    cards(q) = uicontrol(pnl, 'Style', 'text', 'Units', 'normalized', ...
        'Position', [0 0.08 1 0.48], 'String', '-', 'BackgroundColor', 'w', ...
        'FontSize', 13, 'FontName', 'Menlo', 'FontWeight', 'bold');
end
hInfo = uicontrol(fig, 'Style', 'text', 'Units', 'normalized', ...
    'Position', [0.02 0.015 0.64 0.035], 'String', '', ...
    'BackgroundColor', UI, 'FontSize', 10, 'ForegroundColor', [0.35 0.4 0.5]);

% ---------------------------------------------------------------- controls
side = uipanel(fig, 'Units', 'normalized', 'Position', [0.68 0.02 0.31 0.96], ...
    'BackgroundColor', 'w', 'BorderType', 'line', 'HighlightColor', [0.88 0.88 0.9]);
uicontrol(side, 'Style', 'text', 'Units', 'normalized', ...
    'Position', [0.05 0.94 0.9 0.05], ...
    'String', 'Exit Arch', ...
    'FontSize', 16, 'FontWeight', 'bold', 'BackgroundColor', 'w', ...
    'HorizontalAlignment', 'left');
uicontrol(side, 'Style', 'text', 'Units', 'normalized', ...
    'Position', [0.05 0.83 0.9 0.13], ...
    'String', ['A crowd presses through a door. Push harder and bodies lock into arches ' ...
    'across the opening. Sweep the desired speed and watch measured flow fall as urgency rises. ' ...
    'The dimensions of the room is 12 m by 8 m (96 m^2)'], ...
    'FontSize', 10, 'BackgroundColor', 'w', 'HorizontalAlignment', 'left', ...
    'ForegroundColor', [0.3 0.33 0.4]);

btnPlay = uicontrol(side, 'Style', 'pushbutton', 'Units', 'normalized', ...
    'Position', [0.05 0.755 0.43 0.05], 'String', 'Play', ...
    'FontSize', 12, 'FontWeight', 'bold', 'Callback', @onPlay);
uicontrol(side, 'Style', 'pushbutton', 'Units', 'normalized', ...
    'Position', [0.52 0.755 0.43 0.05], 'String', 'Reset', ...
    'FontSize', 12, 'Callback', @(~,~) doReset());

tg = uitabgroup(side, 'Units', 'normalized', 'Position', [0.03 0.02 0.94 0.72]);
tSetup = uitab(tg, 'Title', 'Setup', 'BackgroundColor', 'w');
tCrowd = uitab(tg, 'Title', 'Crowd', 'BackgroundColor', 'w');
tView  = uitab(tg, 'Title', 'View',  'BackgroundColor', 'w');

% --- Setup tab ---
layouts = {'Single Door', 'Pillar', 'Twin Doors', 'Funnel'};
addPopup(tSetup, 0.86, 'Layout', layouts, find(strcmp(layouts, P.layout)), ...
    @(v) setReset('layout', layouts{v}));
addSlider(tSetup, 0.70, 'Door Width (m)', [0.6 3.0], P.doorWidth, '%.2f', ...
    @(v) setReset('doorWidth', v), false);
sPillar = addSlider(tSetup, 0.56, 'Pillar Distance (m)', [0.6 3.0], P.pillarDist, '%.2f', ...
    @(v) setReset('pillarDist', v), false);
addCheckbox(tSetup, 0.44, 'Concert Scenario (stage)', P.concertScenario, ...
    @(v) setConcert(v));
addCheckbox(tSetup, 0.36, 'Central Obstacle', P.centralObstacle, ...
    @(v) setReset('centralObstacle', v));

% --- Crowd tab: info block then controls ---
densityScenarios = {'Baseline', 'Dense', 'High Density'};
panicLevels      = {'Level A: 0.00 - 0.49', 'Level B: 0.50 - 0.79', 'Level C: 0.80 - 1.00'};
panicKeys        = {'Level A', 'Level B', 'Level C'};

% --- info block (top, values aligned at x=0.38) ---
uicontrol(tCrowd, 'Style', 'text', 'Units', 'normalized', ...
    'Position', [0.06 0.91 0.30 0.05], 'String', 'Density:', ...
    'FontWeight', 'bold', 'FontSize', 10, 'BackgroundColor', 'w', ...
    'HorizontalAlignment', 'left');
hInfoDens = uicontrol(tCrowd, 'Style', 'text', 'Units', 'normalized', ...
    'Position', [0.36 0.91 0.58 0.05], 'String', densText(P.densityScenario), ...
    'FontSize', 10, 'BackgroundColor', 'w', 'HorizontalAlignment', 'left');

uicontrol(tCrowd, 'Style', 'text', 'Units', 'normalized', ...
    'Position', [0.06 0.86 0.30 0.05], 'String', 'Agents:', ...
    'FontWeight', 'bold', 'FontSize', 10, 'BackgroundColor', 'w', ...
    'HorizontalAlignment', 'left');
hInfoAPC = uicontrol(tCrowd, 'Style', 'text', 'Units', 'normalized', ...
    'Position', [0.36 0.86 0.58 0.05], 'String', agentText(P.densityScenario), ...
    'FontSize', 10, 'BackgroundColor', 'w', 'HorizontalAlignment', 'left');

% --- controls below info block ---
addBoldPopup(tCrowd, 0.74, 'Density Scenario:', densityScenarios, ...
    find(strcmp(densityScenarios, P.densityScenario)), @onDensityChange);
addBoldSlider(tCrowd, 0.56, 'Desired Speed v0:', '(m/s)', ...
    [0.80 3.00], P.v0Max, '%.2f', @(v) setReset('v0Max', v), false);
addBoldPopup(tCrowd, 0.40, 'Panic Level:', panicLevels, ...
    find(strcmp(panicKeys, P.panicLevel)), @onPanicChange);
addBoldSlider(tCrowd, 0.22, 'Body Friction Kappa:', '(kg/m s)', ...
    [0 500000], P.kappa, '%.0f', @(v) setLive('kappa', v), true);

% --- View tab ---
addSlider(tView, 0.86, 'Time Scale', [0.25 4], P.timeScale, '%.2f', ...
    @(v) setLive('timeScale', v), true);
popOverlay = addPopup(tView, 0.72, 'Overlay', {'Force Chains', 'None'}, 1, @(~) render());
popDensity = addPopup(tView, 0.58, 'Density', {'None', 'Heatmap'}, 1, @(~) render());
uicontrol(tView, 'Style', 'text', 'Units', 'normalized', ...
    'Position', [0.06 0.05 0.88 0.42], 'BackgroundColor', 'w', ...
    'HorizontalAlignment', 'left', 'FontSize', 9, ...
    'ForegroundColor', [0.35 0.4 0.5], ...
    'String', {['Force chains: lines between bodies in contact, thicker and darker as ' ...
    'the compression force rises (>200 N, >600 N, >1200 N).'], '', ...
    'Density: smoothed people per m^2 (grid kernel), 0 to 6+.', '', ...
    ['Crushed: body-compression force above 1600 N ' ...
    'A crush-risk proxy, not an injury prediction.']});

drawGeometry();
render();

% =================================================================== loop
    function onPlay(~, ~)
        if running
            running = false;
            return;
        end
        if S.done, return; end
        running = true;
        btnPlay.String = 'Pause';
        tWall = tic;
        while running && isvalid(fig)
            el = min(toc(tWall), 0.1); tWall = tic;
            nSub = min(max(1, round(S.P.timeScale*max(el, 1/60)/S.P.dt)), 30);
            for k = 1:nSub
                S = exitArchStep(S);
                if S.done, break; end
            end
            render();
            drawnow limitrate;
            if S.done, running = false; end
        end
        if isvalid(fig), btnPlay.String = 'Play'; drawnow; end
    end

    function onClose(~, ~)
        running = false;
        delete(fig);
    end

% ============================================================ parameters
    function setLive(name, v)
        P.(name) = v;
        S.P.(name) = v;
    end

    function setReset(name, v)
        P.(name) = v;
        doReset();
    end

    function doReset()
        S = exitArchInit(P);
        drawGeometry();
        render();
    end

    function setConcert(v)
        P.concertScenario = v;
        hTitle.Visible = onOff(v);
        doReset();
    end

    function onDensityChange(v)
        P.densityScenario = densityScenarios{v};
        hInfoAPC.String  = agentText(P.densityScenario);
        hInfoDens.String = densText(P.densityScenario);
        doReset();
    end

    function onPanicChange(v)
        P.panicLevel = panicKeys{v};
        doReset();
    end

% ================================================================ drawing
    function drawGeometry()
        delete(geomH(isgraphics(geomH)));
        geomH = gobjects(0);
        G = S.G;
        hGround = patch(ax, [G.L+G.wallT G.L+3 G.L+3 G.L+G.wallT], ...
            [-1 -1 G.H+1 G.H+1], [0.86 0.92 0.86], 'EdgeColor', 'none');
        for q = 1:numel(G.polys)
            pg = G.polys{q};
            geomH(end+1) = patch(ax, pg(:,1), pg(:,2), [0.29 0.33 0.42], ...
                'EdgeColor', [0.2 0.23 0.3]); %#ok<AGROW>
        end
        for q = 1:size(G.pillars,1)
            pc = G.pillars(q,:);
            tt = linspace(0, 2*pi, 40);
            geomH(end+1) = patch(ax, pc(1) + pc(3)*cos(tt), ...
                pc(2) + pc(3)*sin(tt), [0.29 0.33 0.42], ...
                'EdgeColor', [0.2 0.23 0.3]); %#ok<AGROW>
        end
        for q = 1:size(G.doors,1)
            geomH(end+1) = line(ax, [G.L G.L], G.doors(q,2:3), ...
                'Color', [0.30 0.70 0.45], 'LineWidth', 2, ...
                'LineStyle', ':'); %#ok<AGROW>
        end
        geomH(end+1) = hGround;
        uistack(geomH, 'bottom');
        uistack(hHeat, 'bottom');
        uistack(hGround, 'bottom');
        xlim(ax, [-G.wallT - 0.2, G.L + 2.5]);
        ylim(ax, [-G.wallT - 0.2, G.H + G.wallT + 0.2]);
        set(sPillar, 'Enable', onOff(strcmp(P.layout, 'Pillar')));
    end

    function render()
        if ~isvalid(fig), return; end
        N = size(S.pos,1);
        if N > 0
            vx = S.pos(:,1) + S.r.*CX;
            vy = S.pos(:,2) + S.r.*CY;
            set(hAgents, ...
                'Vertices', [reshape(vx.', [], 1), reshape(vy.', [], 1)], ...
                'Faces', reshape(1:N*NV, NV, N).', ...
                'FaceVertexCData', COL(S.status,:));
        else
            set(hAgents, 'Faces', [], 'Vertices', zeros(0,2), ...
                'FaceVertexCData', zeros(0,3));
        end

        % force chains
        showChains = popOverlay.Value == 1 && ~isempty(S.contacts);
        lims = [200 600; 600 1200; 1200 inf];
        for q = 1:3
            if showChains
                c = S.contacts(S.contacts(:,3) >= lims(q,1) & ...
                    S.contacts(:,3) < lims(q,2), :);
            else
                c = zeros(0,3);
            end
            if isempty(c)
                set(hChains(q), 'XData', NaN, 'YData', NaN);
            else
                n = size(c,1);
                xs = [S.pos(c(:,1),1), S.pos(c(:,2),1), nan(n,1)].';
                ys = [S.pos(c(:,1),2), S.pos(c(:,2),2), nan(n,1)].';
                set(hChains(q), 'XData', xs(:), 'YData', ys(:));
            end
        end

        % density heatmap
        if popDensity.Value == 2
            h = 0.2; sg = 0.5; G = S.G;
            xc = h/2:h:G.L; yc = h/2:h:G.H;
            dens = zeros(numel(yc), numel(xc));
            if N > 0
                kx = exp(-(xc - S.pos(:,1)).^2/(2*sg^2));
                ky = exp(-(yc - S.pos(:,2)).^2/(2*sg^2));
                dens = (ky.'*kx)/(2*pi*sg^2);
            end
            set(hHeat, 'XData', xc, 'YData', yc, 'CData', dens, ...
                'AlphaData', 0.8*min(dens/3, 1), 'Visible', 'on');
        else
            set(hHeat, 'Visible', 'off');
        end

        % readouts
        nExited = numel(S.exitTimes);
        win = min(S.P.flowWindow, S.t);
        flow = sum(S.exitTimes > S.t - win)/max(win, eps);
        gapNow = 0;
        if ~isnan(S.lastExit), gapNow = S.t - S.lastExit; end
        stall = max(S.longestStall, gapNow);
        avgSpd = 0;
        if N > 0, avgSpd = mean(sqrt(sum(S.vel.^2, 2))); end
        evacPct = 100 * nExited / max(S.initialAgents, 1);
        crushedNow = sum(S.status == 4);

        cards(1).String = sprintf('%d/%d', N, S.initialAgents);
        cards(2).String = sprintf('%.2f', avgSpd);
        cards(3).String = sprintf('%.2f/s', flow);
        cards(4).String = sprintf('%.1f%%', evacPct);
        cards(5).String = sprintf('%d', crushedNow);
        cards(6).String = sprintf('%.1fs', stall);
        cards(7).String = sprintf('%.0f N/m', S.peakLoad);

        hInfo.String = sprintf('t = %.1f s   |   evacuated %d   |   peak load %.0f N', ...
            S.t, numel(S.exitTimes), S.peakLoad);

        hStatus.String = statusLabel(S, flow, gapNow, crushedNow);
    end

% ================================================================ widgets
    function h = addSlider(parent, y, label, lim, val, fmt, cb, live)
        uicontrol(parent, 'Style', 'text', 'Units', 'normalized', ...
            'Position', [0.06 y+0.05 0.66 0.05], 'String', label, ...
            'HorizontalAlignment', 'left', 'FontSize', 10, ...
            'BackgroundColor', 'w');
        hv = uicontrol(parent, 'Style', 'text', 'Units', 'normalized', ...
            'Position', [0.70 y+0.05 0.24 0.05], ...
            'String', sprintf(fmt, val), 'HorizontalAlignment', 'right', ...
            'FontSize', 10, 'FontWeight', 'bold', 'BackgroundColor', 'w');
        h = uicontrol(parent, 'Style', 'slider', 'Units', 'normalized', ...
            'Position', [0.06 y 0.88 0.045], ...
            'Min', lim(1), 'Max', lim(2), 'Value', val, ...
            'BackgroundColor', 'w');
        h.Callback = @(src, ~) applySlider(src, hv, fmt, cb);
        addlistener(h, 'ContinuousValueChange', ...
            @(src, ~) dragSlider(src, hv, fmt, cb, live));
    end

    function applySlider(src, hv, fmt, cb)
        hv.String = sprintf(fmt, src.Value);
        cb(src.Value);
    end

    function dragSlider(src, hv, fmt, cb, live)
        hv.String = sprintf(fmt, src.Value);
        if live, cb(src.Value); end
    end

    function h = addPopup(parent, y, label, items, val, cb)
        uicontrol(parent, 'Style', 'text', 'Units', 'normalized', ...
            'Position', [0.06 y+0.05 0.88 0.05], 'String', label, ...
            'HorizontalAlignment', 'left', 'FontSize', 10, ...
            'BackgroundColor', 'w');
        h = uicontrol(parent, 'Style', 'popupmenu', 'Units', 'normalized', ...
            'Position', [0.06 y 0.88 0.05], 'String', items, ...
            'Value', val, 'FontSize', 10, ...
            'Callback', @(src, ~) cb(src.Value));
    end

    function addCheckbox(parent, y, label, val, cb)
        uicontrol(parent, 'Style', 'checkbox', 'Units', 'normalized', ...
            'Position', [0.06 y 0.88 0.06], 'String', label, ...
            'Value', val, 'FontSize', 10, 'BackgroundColor', 'w', ...
            'Callback', @(src, ~) cb(logical(src.Value)));
    end

    function h = addBoldPopup(parent, y, label, items, val, cb)
        uicontrol(parent, 'Style', 'text', 'Units', 'normalized', ...
            'Position', [0.06 y+0.05 0.88 0.05], 'String', label, ...
            'HorizontalAlignment', 'left', 'FontSize', 10, ...
            'FontWeight', 'bold', 'BackgroundColor', 'w');
        h = uicontrol(parent, 'Style', 'popupmenu', 'Units', 'normalized', ...
            'Position', [0.06 y 0.88 0.05], 'String', items, ...
            'Value', val, 'FontSize', 10, ...
            'Callback', @(src, ~) cb(src.Value));
    end

    function h = addBoldSlider(parent, y, label, unit, lim, val, fmt, cb, live)
        uicontrol(parent, 'Style', 'text', 'Units', 'normalized', ...
            'Position', [0.06 y+0.10 0.60 0.05], 'String', label, ...
            'HorizontalAlignment', 'left', 'FontSize', 10, ...
            'FontWeight', 'bold', 'BackgroundColor', 'w');
        uicontrol(parent, 'Style', 'text', 'Units', 'normalized', ...
            'Position', [0.06 y+0.05 0.60 0.04], 'String', unit, ...
            'HorizontalAlignment', 'left', 'FontSize', 9, ...
            'ForegroundColor', [0.4 0.4 0.5], 'BackgroundColor', 'w');
        hv = uicontrol(parent, 'Style', 'text', 'Units', 'normalized', ...
            'Position', [0.70 y+0.05 0.24 0.05], ...
            'String', sprintf(fmt, val), 'HorizontalAlignment', 'right', ...
            'FontSize', 10, 'FontWeight', 'bold', 'BackgroundColor', 'w');
        h = uicontrol(parent, 'Style', 'slider', 'Units', 'normalized', ...
            'Position', [0.06 y 0.88 0.045], ...
            'Min', lim(1), 'Max', lim(2), 'Value', val, ...
            'BackgroundColor', 'w');
        h.Callback = @(src, ~) applySlider(src, hv, fmt, cb);
        addlistener(h, 'ContinuousValueChange', ...
            @(src, ~) dragSlider(src, hv, fmt, cb, live));
    end
end

function s = onOff(tf)
if tf, s = 'on'; else, s = 'off'; end
end

function t = agentText(scenario)
switch scenario
    case 'Baseline',    t = '288';
    case 'Dense',       t = '384';
    case 'High Density',  t = '460';
end
end

function t = densText(scenario)
switch scenario
    case 'Baseline',    t = '~3.0 ped/m^2';
    case 'Dense',       t = '~4.0 ped/m^2';
    case 'High Density',  t = '~5.0 ped/m^2';
end
end

function s = statusLabel(S, flow, gapNow, nCrushed)
N = size(S.pos,1);
if S.done
    s = sprintf('EVACUATED IN %.1f s', S.evacTime);
elseif N == 0
    s = 'EMPTY';
elseif isnan(S.lastExit) && S.t < 3
    s = 'MOVING TO THE DOOR';
elseif gapNow > 1.0 && nCrushed > 0
    s = 'LOCKED CRUSH';
elseif gapNow > 1.0
    s = 'ARCH BLOCKING THE DOOR';
elseif nCrushed > 0
    s = 'CRUSH RISK';
elseif mean(S.status >= 3) > 0.25
    s = 'CONGESTED';
elseif flow > 0
    s = 'FLOWING';
else
    s = 'MOVING TO THE DOOR';
end
end

