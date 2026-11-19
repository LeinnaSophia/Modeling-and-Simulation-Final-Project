function T = exitArchSweep(varargin)
%EXITARCHSWEEP  "Faster is slower": sweep the desired speed v0 and measure
%   the steady outflow through the door, the longest stall between exits
%   and the peak crush load.
%
%   T = exitArchSweep() runs the default sweep and saves
%       results/exitArchSweep.csv and results/exitArchSweep.png
%   T = exitArchSweep('layouts', {'Single Door','Pillar'}, 'seeds', 1:3, ...
%                     'v0List', 0.8:0.4:4.8, 'simTime', 60, 'warmup', 15)

opt.layouts   = {'Single Door', 'Pillar'};
opt.v0MaxList = [0.8 1.2 1.6 2.0 2.4 3.0 3.6 4.4];
opt.seeds     = 1:3;
opt.simTime   = 40;      % s per run
opt.warmup    = 10;      % s ignored before measuring
opt.nAgents   = 200;
opt.doorWidth = 1.2;
opt.outDir    = fullfile(fileparts(mfilename('fullpath')), 'results');
for i = 1:2:numel(varargin), opt.(varargin{i}) = varargin{i+1}; end

rows = {};
for li = 1:numel(opt.layouts)
    for v0Max = opt.v0MaxList
        for sd = opt.seeds
            P = exitArchParams('layout', opt.layouts{li}, 'scenario', 'Steady Stream', ...
                'v0Max', v0Max, 'nAgents', opt.nAgents, 'doorWidth', opt.doorWidth, 'seed', sd);
            R = exitArchRun(P, opt.simTime, 'warmup', opt.warmup);
            s = R.summary;
            rows(end+1,:) = {opt.layouts{li}, v0Max, sd, s.flow, s.longestStall, s.peakLoad, s.crushedAgents}; %#ok<AGROW>
            fprintf('%-11s v0Max=%.1f seed=%d  flow %.2f/s  stall %.2f s  peak %.0f N/m\n', ...
                opt.layouts{li}, v0Max, sd, s.flow, s.longestStall, s.peakLoad);
        end
    end
end
T = cell2table(rows, 'VariableNames', ...
    {'layout','v0Max','seed','flow','longestStall','peakLoad','crushedAgents'});

if ~exist(opt.outDir, 'dir'), mkdir(opt.outDir); end
writetable(T, fullfile(opt.outDir, 'exitArchSweep.csv'));

% --- plot mean +/- std across seeds ---
fig = figure('Visible', 'off', 'Color', 'w', 'Position', [100 100 1200 380]);
try theme(fig, 'light'); catch, end   % keep the saved plot readable under a dark desktop theme
tl = tiledlayout(fig, 1, 3, 'TileSpacing', 'compact', 'Padding', 'compact');
metrics = {'flow', 'Outflow (people/s)'; 'longestStall', 'Longest stall (s)'; ...
           'peakLoad', 'Peak crush load (N/m)'};
colors = [0.20 0.45 0.75; 0.90 0.47 0.25; 0.30 0.65 0.40; 0.55 0.35 0.70];
for m = 1:3
    ax = nexttile(tl); hold(ax, 'on'); grid(ax, 'on');
    for li = 1:numel(opt.layouts)
        sel = strcmp(T.layout, opt.layouts{li});
        [g, v] = findgroups(T.v0Max(sel));
        y = T.(metrics{m,1})(sel);
        mu = splitapply(@mean, y, g); sdv = splitapply(@std, y, g);
        errorbar(ax, v, mu, sdv, '-o', 'LineWidth', 1.5, 'MarkerFaceColor', 'w', ...
            'Color', colors(li,:), 'DisplayName', opt.layouts{li});
    end
    if m == 3
        yline(ax, 1600, '--', 'injury threshold 1600 N/m', 'Color', [0.6 0.1 0.1], ...
            'HandleVisibility', 'off', 'LabelHorizontalAlignment', 'left');
    end
    xlabel(ax, 'Max desired speed v_{0,max} (m/s)'); ylabel(ax, metrics{m,2});
    if m == 1, legend(ax, 'Location', 'best'); end
end
title(tl, sprintf('Faster is slower: door %.1f m, %d people, mean \\pm std over %d seeds', ...
    opt.doorWidth, opt.nAgents, numel(opt.seeds)));
exportgraphics(fig, fullfile(opt.outDir, 'exitArchSweep.png'), 'Resolution', 150);
close(fig);
fprintf('Saved %s\n', fullfile(opt.outDir, 'exitArchSweep.{csv,png}'));
end
