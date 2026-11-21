% Visualizations.m -- ExitArch crowd-evacuation metrics & heatmaps
% Runs all 9 scenario combos (3 density x 3 panic), collects time-series
% data from exitArchRun, then renders:
%   Fig 1: time-series grid  (density cols x metric rows, panic overlaid)
%   Fig 2: spatial heatmaps  (density & crush-risk at Level C)
%   Fig 3: summary bar chart (evac time & total crushed across all combos)
%
% Adapted from Nicole's Visualizations.m; Okabe-Ito palette preserved.
% Run with:  Visualizations
function Visualizations()
clc; close all;

simTime = 120;                                    % seconds per run
outDir = fullfile(fileparts(mfilename('fullpath')), 'figures');
if ~exist(outDir, 'dir'), mkdir(outDir); end

% Okabe-Ito colorblind-safe line palette (one per panic level)
pal.cat  = [0 114 178; 213 94 0; 0 158 115] / 255;   % A=blue, B=orange, C=green
t = linspace(0, 1, 256)';
pal.density = (1-t)*[247 251 255]/255 + t*[8 48 107]/255;
pal.crush   = (1-t)*[255 245 240]/255 + t*[103 0 13]/255;

densNames  = {'Baseline', 'Dense', 'Crush Risk'};
panicNames = {'Level A',  'Level B', 'Level C'};
panicLabels = {'Level A (0.00-0.49)', 'Level B (0.50-0.79)', 'Level C (0.80-1.00)'};

% ---- run all 9 combos ----
fprintf('Running 9 scenario combos (%d s each)...\n', simTime);
R = cell(3, 3);                                   % R{density, panic}
heatData = cell(3, 3);
for di = 1:3
    for pi = 1:3
        fprintf('  %s + %s ... ', densNames{di}, panicNames{pi});
        P = exitArchParams('densityScenario', densNames{di}, ...
                           'panicLevel', panicNames{pi}, 'seed', 42);
        result = exitArchRun(P, simTime);
        R{di, pi} = result;
        heatData{di, pi} = collectHeat(result.final, P);
        fprintf('done (evac %.1f s, crushed %d)\n', ...
            result.summary.evacTime, result.summary.crushedAgents);
    end
end

% ---- Figure 1: time-series grid ----
plotTimeSeries(R, densNames, panicLabels, pal, outDir);

% ---- Figure 2: heatmaps at Level C ----
plotHeatmaps(heatData(:, 3), densNames, pal, outDir);

% ---- Figure 3: summary bars ----
plotSummary(R, densNames, panicNames, pal, outDir);

fprintf('All figures saved to: %s\n', outDir);
end


% ======================= DATA COLLECTION =======================
function H = collectHeat(S, P)
% Spatial density and crush-risk from final sim state's accumulated data.
% Uses the same grid as the sim (1 m^2 cells).
nx = ceil(P.L); ny = ceil(P.H);
H.density = zeros(ny, nx);
H.crush   = zeros(ny, nx);
H.L = P.L; H.H = P.H;
H.stage = [];
if P.concertScenario
    H.stage = [P.stageDepth, P.stageYMin, P.stageYMax];
end
H.obstacle = [];
if P.centralObstacle
    H.obstacle = [P.obstacleXMin, P.obstacleYMin, P.obstacleXMax, P.obstacleYMax];
end
% accumulate from final state positions
N = size(S.pos, 1);
if N > 0
    cix = max(1, min(nx, ceil(S.pos(:,1))));
    ciy = max(1, min(ny, ceil(S.pos(:,2))));
    lin = sub2ind([ny nx], ciy, cix);
    H.density = reshape(accumarray(lin, 1, [ny*nx 1]), [ny nx]);
    H.crush   = reshape(accumarray(lin, S.load, [ny*nx 1]), [ny nx]);
end
end


% ======================= FIGURE 1: TIME SERIES =======================
function plotTimeSeries(R, densNames, panicLabels, pal, outDir)
metrics = {'meanSpeed', 'Avg Speed',      'speed (m/s)'; ...
           'exited',    'Evacuated',       'cumulative count'; ...
           'crushed',   'Crushed (live)',   'agent count'; ...
           'peakLoad',  'Peak Load',       'force (N)'};
nM = size(metrics, 1);
nD = numel(densNames);

f = figure('Color', 'w', 'Position', [40 40 380*nD+80 300*nM]);
for m = 1:nM
    for d = 1:nD
        subplot(nM, nD, (m-1)*nD + d); hold on;
        for p = 1:3
            ts = R{d, p}.series;
            plot(ts.t, ts.(metrics{m,1}), 'Color', pal.cat(p,:), 'LineWidth', 1.8);
        end
        grid on; set(gca, 'GridAlpha', 0.15, 'Box', 'off');
        xlabel('time (s)'); ylabel(metrics{m,3});
        if m == 1
            title(densNames{d}, 'FontWeight', 'bold', 'FontSize', 12);
        end
        if d == 1
            yl = get(gca, 'YLabel');
            yl.String = [metrics{m,2} '  —  ' yl.String];
            yl.FontWeight = 'bold';
        end
        if m == 1 && d == nD
            legend(panicLabels, 'Location', 'best', 'Box', 'off', 'FontSize', 8);
        end
    end
end
sgtitle('ExitArch: evacuation metrics over time', 'FontWeight', 'bold', 'FontSize', 14);
saveFig(f, outDir, 'exitarch_timeseries');
end


% ======================= FIGURE 2: HEATMAPS =======================
function plotHeatmaps(heatCells, densNames, pal, outDir)
nD = numel(densNames);
f = figure('Color', 'w', 'Position', [40 40 400*nD 600]);

rows = {'density', pal.density, 'agents / cell',       'density'; ...
        'crush',   pal.crush,   'body compression (N)', 'crush risk'};
for r = 1:2
    cmax = max(eps, max(cellfun(@(h) max(h.(rows{r,1})(:)), heatCells)));
    for d = 1:nD
        subplot(2, nD, (r-1)*nD + d);
        H = heatCells{d};
        xc = 0.5 : H.L - 0.5;
        yc = 0.5 : H.H - 0.5;
        imagesc(xc, yc, H.(rows{r,1})); axis xy equal tight;
        colormap(gca, rows{r,2}); caxis([0 cmax]);
        overlayGeometry(H);
        title([densNames{d} ' — ' rows{r,4}], 'FontWeight', 'bold');
        xlabel('x (m)'); ylabel('y (m)');
        cb = colorbar; cb.Label.String = rows{r,3};
    end
end
sgtitle('ExitArch: spatial maps at Level C (highest panic)', ...
    'FontWeight', 'bold', 'FontSize', 14);
saveFig(f, outDir, 'exitarch_heatmaps');
end


function overlayGeometry(H)
hold on;
if ~isempty(H.stage)
    rectangle('Position', [0 H.stage(2) H.stage(1) H.stage(3)-H.stage(2)], ...
        'EdgeColor', [0.25 0.25 0.25], 'LineWidth', 1.5);
    text(H.stage(1)/2, mean(H.stage(2:3)), 'STAGE', 'Color', [0.2 0.2 0.2], ...
        'HorizontalAlignment', 'center', 'FontSize', 8, 'FontWeight', 'bold');
end
if ~isempty(H.obstacle)
    o = H.obstacle;
    rectangle('Position', [o(1) o(2) o(3)-o(1) o(4)-o(2)], ...
        'EdgeColor', [0.25 0.25 0.25], 'LineWidth', 1.5, 'LineStyle', '--');
end
plot(H.L, H.H/2, 'v', 'Color', [0 0.5 0], 'MarkerSize', 10, ...
    'MarkerFaceColor', [0 0.5 0]);
text(H.L - 0.3, H.H/2, 'EXIT', 'Color', [0 0.5 0], ...
    'HorizontalAlignment', 'right', 'FontSize', 8, 'FontWeight', 'bold');
hold off;
end


% ======================= FIGURE 3: SUMMARY BARS =======================
function plotSummary(R, densNames, panicNames, pal, outDir)
nD = numel(densNames); nP = numel(panicNames);
evacTime = zeros(nD, nP);
totalCrushed = zeros(nD, nP);
peakLoad = zeros(nD, nP);

for d = 1:nD
    for p = 1:nP
        s = R{d, p}.summary;
        evacTime(d, p) = s.evacTime;
        totalCrushed(d, p) = s.crushedAgents;
        peakLoad(d, p) = s.peakLoad;
    end
end

f = figure('Color', 'w', 'Position', [60 60 1200 380]);
metrics = {evacTime,     'Evacuation Time (s)',   'time (s)'; ...
           totalCrushed, 'Total Ever Crushed',    'agent count'; ...
           peakLoad,     'Peak Load',             'force (N)'};
for m = 1:3
    subplot(1, 3, m);
    b = bar(metrics{m,1});
    for p = 1:nP
        b(p).FaceColor = 'flat';
        b(p).CData = repmat(pal.cat(p,:), nD, 1);
    end
    set(gca, 'XTickLabel', densNames, 'Box', 'off');
    ylabel(metrics{m,3}); title(metrics{m,2}, 'FontWeight', 'bold');
    if m == 3
        legend(panicNames, 'Location', 'best', 'Box', 'off');
    end
    grid on; set(gca, 'GridAlpha', 0.15);
end
sgtitle('ExitArch: scenario comparison summary', 'FontWeight', 'bold', 'FontSize', 14);
saveFig(f, outDir, 'exitarch_summary');
end


% ======================= SAVE HELPER =======================
function saveFig(f, outDir, name)
fn = fullfile(outDir, [name '.png']);
try, exportgraphics(f, fn, 'Resolution', 150);
catch, print(f, fn, '-dpng', '-r150'); end
fprintf('  saved %s\n', fn);
end
