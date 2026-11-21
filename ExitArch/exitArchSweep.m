function T = exitArchSweep(varargin)
%EXITARCHSWEEP  "Faster is slower": sweep the desired speed v0 across
%   density scenarios and layouts. Measures outflow, longest stall,
%   peak crush load, and total crushed agents.
%
%   T = exitArchSweep() runs the default sweep and saves
%       results/exitArchSweep.csv and results/exitArchSweep.png
%   T = exitArchSweep('layouts', {'Single Door'}, 'seeds', 1:5, ...
%                     'v0MaxList', 0.8:0.4:3.6, 'simTime', 60)

opt.layouts    = {'Single Door', 'Pillar'};
opt.densities  = {'Baseline', 'Dense', 'Crush Risk'};
opt.v0MaxList  = [0.8 1.2 1.6 2.0 2.4 3.0 3.6];
opt.seeds      = 1:3;
opt.simTime    = 60;
opt.warmup     = 10;
opt.doorWidth  = 1.2;
opt.outDir     = fullfile(fileparts(mfilename('fullpath')), 'results');
for i = 1:2:numel(varargin), opt.(varargin{i}) = varargin{i+1}; end

rows = {};
for li = 1:numel(opt.layouts)
    for di = 1:numel(opt.densities)
        for v0Max = opt.v0MaxList
            for sd = opt.seeds
                P = exitArchParams('layout', opt.layouts{li}, ...
                    'densityScenario', opt.densities{di}, ...
                    'panicLevel', 'Level B', ...
                    'v0Max', v0Max, 'doorWidth', opt.doorWidth, 'seed', sd);
                R = exitArchRun(P, opt.simTime, 'warmup', opt.warmup);
                s = R.summary;
                rows(end+1,:) = {opt.layouts{li}, opt.densities{di}, v0Max, sd, ...
                    s.flow, s.longestStall, s.peakLoad, s.crushedAgents}; %#ok<AGROW>
                fprintf('%-11s %-11s v0Max=%.1f seed=%d  flow %.2f/s  stall %.1f s  peak %.0f N  crushed %d\n', ...
                    opt.layouts{li}, opt.densities{di}, v0Max, sd, ...
                    s.flow, s.longestStall, s.peakLoad, s.crushedAgents);
            end
        end
    end
end
T = cell2table(rows, 'VariableNames', ...
    {'layout','density','v0Max','seed','flow','longestStall','peakLoad','crushedAgents'});

if ~exist(opt.outDir, 'dir'), mkdir(opt.outDir); end
writetable(T, fullfile(opt.outDir, 'exitArchSweep.csv'));

% --- plot mean +/- std across seeds, one row per density scenario ---
nD = numel(opt.densities);
fig = figure('Visible', 'off', 'Color', 'w', 'Position', [60 60 1200 320*nD]);
try theme(fig, 'light'); catch, end
tl = tiledlayout(fig, nD, 3, 'TileSpacing', 'compact', 'Padding', 'compact');
metrics = {'flow', 'Outflow (people/s)'; 'peakLoad', 'Peak crush load (N)'; ...
           'crushedAgents', 'Total crushed'};
colors = [0.20 0.45 0.75; 0.90 0.47 0.25; 0.30 0.65 0.40; 0.55 0.35 0.70];

for di = 1:nD
    for m = 1:3
        ax = nexttile(tl); hold(ax, 'on'); grid(ax, 'on');
        for li = 1:numel(opt.layouts)
            sel = strcmp(T.layout, opt.layouts{li}) & strcmp(T.density, opt.densities{di});
            [g, v] = findgroups(T.v0Max(sel));
            y = T.(metrics{m,1})(sel);
            mu = splitapply(@mean, y, g); sdv = splitapply(@std, y, g);
            errorbar(ax, v, mu, sdv, '-o', 'LineWidth', 1.5, 'MarkerFaceColor', 'w', ...
                'Color', colors(li,:), 'DisplayName', opt.layouts{li});
        end
        if m == 2
            yline(ax, 1600, '--', 'crush threshold', 'Color', [0.6 0.1 0.1], ...
                'HandleVisibility', 'off', 'LabelHorizontalAlignment', 'left');
        end
        xlabel(ax, 'v_{0,max} (m/s)'); ylabel(ax, metrics{m,2});
        if m == 1
            ylabel(ax, {opt.densities{di}, metrics{m,2}}, 'FontWeight', 'bold');
        end
        if di == 1 && m == 1, legend(ax, 'Location', 'best'); end
    end
end
title(tl, sprintf('"Faster is slower" — door %.1f m, panic Level B, mean \\pm std over %d seeds', ...
    opt.doorWidth, numel(opt.seeds)), 'FontWeight', 'bold');
exportgraphics(fig, fullfile(opt.outDir, 'exitArchSweep.png'), 'Resolution', 150);
close(fig);
fprintf('Saved %s\n', fullfile(opt.outDir, 'exitArchSweep.{csv,png}'));
end
