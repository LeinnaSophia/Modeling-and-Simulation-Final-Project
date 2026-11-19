function exitArchApp()
%EXITARCHAPP  Interactive crowd simulation for concert evacuation scenarios.
%
%   Run:  cd ExitArch; exitArchApp
%
%   Setup / Crowd sliders that change the room or the people restart the
%   run; speed, friction, and the View options apply live.

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
    'Position', [60 60 1400 800], 'MenuBar', 'none', 'ToolBar', 'figure', ...
    'CloseRequestFcn', @onClose);
try theme(fig, 'light'); catch, end

% title label (visible only when Concert Scenario is on)
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
lh = gobjects(4,1);
for q = 1:4, lh(q) = patch(ax, NaN, NaN, COL(q,:), 'EdgeColor', 'none'); end
legend(ax, lh, {'Walking', 'Slowed', 'Stuck', 'Crushed'}, ...
    'Orientation', 'horizontal', 'Location', 'northoutside', 'Box', 'off', ...
    'FontSize', 9, 'AutoUpdate', 'off');

% metric cards (centered under the axes)
cardW = 0.15; cardX = 0.02 + 0.64/2 - 1.5*cardW - 0.01;
cards = gobjects(3,1);
titles = {'OUTFLOW', 'LONGEST STALL', 'PEAK LOAD'};
for q = 1:3
    pnl = uipanel(fig, 'Units', 'normalized', ...
        'Position', [cardX + (q-1)*(cardW + 0.01) 0.065 cardW 0.11], ...
        'BackgroundColor', 'w', 'BorderType', 'line', 'HighlightColor', [0.85 0.85 0.88]);
    uicontrol(pnl, 'Style', 'text', 'Units', 'normalized', 'Position', [0 0.58 1 0.3], ...
        'String', titles{q}, 'BackgroundColor', 'w', 'FontSize', 10, ...
        'ForegroundColor', [0.35 0.4 0.5]);
    cards(q) = uicontrol(pnl, 'Style', 'text', 'Units', 'normalized', ...
        'Position', [0 0.1 1 0.45], 'String', '-', 'BackgroundColor', 'w', ...
        'FontSize', 17, 'FontName', 'Menlo', 'FontWeight', 'bold');
end
hInfo = uicontrol(fig, 'Style', 'text', 'Units', 'normalized', ...
    'Position', [0.02 0.015 0.64 0.035], 'String', '', ...
    'BackgroundColor', UI, 'FontSize', 10, 'ForegroundColor', [0.35 0.4 0.5]);

% ---------------------------------------------------------------- controls
side = uipanel(fig, 'Units', 'normalized', 'Position', [0.68 0.02 0.31 0.96], ...
    'BackgroundColor', 'w', 'BorderType', 'line', 'HighlightColor', [0.88 0.88 0.9]);
uicontrol(side, 'Style', 'text', 'Units', 'normalized', ...
    'Position', [0.05 0.90 0.9 0.08], ...
    'String', ['A crowd presses through a door. Push harder and bodies lock into arches ' ...
    'across the opening. Sweep the desired speed and watch measured flow fall as urgency rises.'], ...
    'FontSize', 10, 'BackgroundColor', 'w', 'HorizontalAlignment', 'left', ...
    'ForegroundColor', [0.3 0.33 0.4]);

btnPlay = uicontrol(side, 'Style', 'pushbutton', 'Units', 'normalized', ...
    'Position', [0.05 0.785 0.43 0.05], 'String', 'Play', ...
    'FontSize', 12, 'FontWeight', 'bold', 'Callback', @onPlay);
uicontrol(side, 'Style', 'pushbutton', 'Units', 'normalized', ...
    'Position', [0.52 0.785 0.43 0.05], 'String', 'Reset', ...
    'FontSize', 12, 'Callback', @(~,~) doReset());

tg = uitabgroup(side, 'Units', 'normalized', 'Position', [0.03 0.02 0.94 0.75]);
tSetup = uitab(tg, 'Title', 'Setup', 'BackgroundColor', 'w');
tCrowd = uitab(tg, 'Title', 'Crowd', 'BackgroundColor', 'w');
tView  = uitab(tg, 'Title', 'View',  'BackgroundColor', 'w');

% --- Setup tab ---
layouts   = {'Single Door', 'Pillar', 'Twin Doors', 'Funnel'};
scenarios = {'Steady Stream', 'Evacuation'};
addPopup(tSetup, 0.86, 'Layout', layouts, find(strcmp(layouts, P.layout)), ...
    @(v) setReset('layout', layouts{v}));
addPopup(tSetup, 0.72, 'Scenario', scenarios, find(strcmp(scenarios, P.scenario)), ...
    @(v) setReset('scenario', scenarios{v}));
addSlider(tSetup, 0.56, 'Door Width (m)', [0.6 3.0], P.doorWidth, '%.2f', ...
    @(v) setReset('doorWidth', v), false);
sPillar = addSlider(tSetup, 0.42, 'Pillar Distance (m)', [0.6 3.0], P.pillarDist, '%.2f', ...
    @(v) setReset('pillarDist', v), false);
addCheckbox(tSetup, 0.30, 'Concert Scenario (stage)', P.concertScenario, ...
    @(v) setConcert(v));
addCheckbox(tSetup, 0.22, 'Central Obstacle', P.centralObstacle, ...
    @(v) setReset('centralObstacle', v));

% --- Crowd tab ---
addSlider(tCrowd, 0.86, 'Min Speed (m/s)', [0.3 4.0], P.v0Min, '%.2f', ...
    @(v) setReset('v0Min', v), false);
addSlider(tCrowd, 0.72, 'Max Speed (m/s)', [0.5 5.0], P.v0Max, '%.2f', ...
    @(v) setReset('v0Max', v), false);
addSlider(tCrowd, 0.58, 'Crowd (people)', [20 800], P.nAgents, '%.0f', ...
    @(v) setReset('nAgents', round(v)), false);
addSlider(tCrowd, 0.44, 'Body Friction kappa (x1e5 kg/m s)', [0 4.8], P.kappa/1e5, '%.2f', ...
    @(v) setLive('kappa', v*1e5), true);
addSlider(tCrowd, 0.30, 'Panic Min', [0.0 0.9], P.panicMin, '%.2f', ...
    @(v) setReset('panicMin', v), false);
addSlider(tCrowd, 0.16, 'Panic Max', [0.1 1.0], P.panicMax, '%.2f', ...
    @(v) setReset('panicMax', v), false);

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
    'the compression force rises (>500 N, >2 kN, >5 kN).'], '', ...
    'Density: smoothed people per m^2 (Gaussian kernel, 0.5 m), 0 to 6+.', '', ...
    ['Crushed: body-compression load above 1600 N/m of body circumference ' ...
    '(Helbing et al. 2000). It is a crush-risk proxy, not an injury prediction.']});

drawGeometry();
render();

% =================================================================== loop
    function onPlay(~, ~)
        if running
            running = false;
            return;
        end
        if S.done, doReset(); end
        running = true;
        btnPlay.String = 'Pause';
        tWall = tic;
        while running && isvalid(fig)
            el = min(toc(tWall), 0.1); tWall = tic;
            nSub = min(max(1, round(S.P.timeScale*max(el, 1/60)/S.P.dt)), 80);
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
        lims = [500 2000; 2000 5000; 5000 inf];
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
        win = min(S.P.flowWindow, S.t);
        flow = sum(S.exitTimes > S.t - win)/max(win, eps);
        gapNow = 0;
        if ~isnan(S.lastExit), gapNow = S.t - S.lastExit; end
        stall = max(S.longestStall, gapNow);
        cards(1).String = sprintf('%.2f /s', flow);
        cards(2).String = sprintf('%.1f s', stall);
        cards(3).String = sprintf('%.2f kN/m', S.peakLoadNow/1000);
        nCr = sum(S.status == 4);
        hInfo.String = sprintf('t = %.1f s   |   inside %d   |   exited %d   |   crushed now %d   |   ever crushed %d', ...
            S.t, N, numel(S.exitTimes), nCr, S.nCrushedGone + sum(S.everCrushed));
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
end

function s = onOff(tf)
if tf, s = 'on'; else, s = 'off'; end
end
