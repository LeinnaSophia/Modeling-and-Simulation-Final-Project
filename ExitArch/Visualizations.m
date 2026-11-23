% Visualizations.m -- ExitArch crowd-evacuation metrics & heatmaps
% Runs all 9 scenario combos (3 density x 3 panic), collects time-series
% and spatial data, then renders:
%   Fig 1: time-series grid  (density cols x metric rows, panic overlaid)
%   Fig 2: spatial heatmaps  (peak density & crush-risk at Level C)
%   Fig 3: summary bar chart (evac time & total crushed across all combos)
%
% Run with:  Visualizations
function Visualizations()
clc; close all;

simTime = 300;                                    % seconds per run (stops early when empty)
outDir = fullfile(fileparts(mfilename('fullpath')), 'figures');
if ~exist(outDir, 'dir'), mkdir(outDir); end

% Okabe-Ito colorblind-safe line palette (one per panic level)
pal.cat  = [0 114 178; 213 94 0; 0 158 115] / 255;   % A=blue, B=orange, C=green
t = linspace(0, 1, 256)';
pal.density = (1-t)*[247 251 255]/255 + t*[8 48 107]/255;
pal.crush   = (1-t)*[255 245 240]/255 + t*[103 0 13]/255;

densNames  = {'Baseline', 'Dense', 'High Density'};
panicNames = {'Level A',  'Level B', 'Level C'};
panicLabels = {'Level A (0.00-0.49)', 'Level B (0.50-0.79)', 'Level C (0.80-1.00)'};
v0Ranges   = [0.80 1.30; 1.40 2.20; 2.80 4.00];   % matches Panic Level presets in exitArchApp

% ---- run all 9 combos ----
fprintf('Running 9 scenario combos (up to %d s each)...\n', simTime);
R = cell(3, 3);                                   % R{density, panic}
heatData = cell(3, 3);
for di = 1:3
    for pi = 1:3
        fprintf('  %s + %s ... ', densNames{di}, panicNames{pi});
        P = exitArchParams('densityScenario', densNames{di}, ...
                           'panicLevel', panicNames{pi}, ...
                           'v0Min', v0Ranges(pi,1), 'v0Max', v0Ranges(pi,2), ...
                           'seed', 42);
        [result, H] = collectRunAndHeat(P, simTime);
        R{di, pi} = result;
        heatData{di, pi} = H;
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
function [R, H] = collectRunAndHeat(P, simTime)
% Runs the simulation and tracks peak spatial density & crush-risk across the
% evacuation using the same 1 m^2 cell grid (so maps stay populated after exit).
S = exitArchInit(P);
P = S.P;                                          % use scaled stage/obstacle coords
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

sampleEvery = 0.1;
nMax = floor(simTime/sampleEvery) + 1;
t = nan(nMax,1); inside = t; exited = t; outflow = t;
stuckFrac = t; meanSpeed = t; peakLoad = t; crushed = t;
k = 0; nextSample = 0; maxLoadSeen = 0;

while S.t < simTime - 1e-9 && ~S.done
    S = exitArchStep(S);
    maxLoadSeen = max(maxLoadSeen, S.peakLoadNow);
    if S.t >= nextSample - 1e-9 || S.done
        k = k + 1;
        N = size(S.pos, 1);
        t(k) = S.t; inside(k) = N; exited(k) = numel(S.exitTimes);
        win = min(P.flowWindow, S.t);
        outflow(k) = sum(S.exitTimes > S.t - win)/max(win, eps);
        if N > 0
            spd = sqrt(sum(S.vel.^2, 2));
            stuckFrac(k) = mean(S.status == 3 | S.status == 4);
            meanSpeed(k) = mean(spd);
            peakLoad(k)  = S.peakLoadNow;
            crushed(k)   = sum(S.status == 4);

            cix = max(1, min(nx, ceil(S.pos(:,1))));
            ciy = max(1, min(ny, ceil(S.pos(:,2))));
            lin = sub2ind([ny nx], ciy, cix);
            dGrid = reshape(accumarray(lin, 1,      [ny*nx 1]), [ny nx]);
            cGrid = reshape(accumarray(lin, S.load, [ny*nx 1], @max, 0), [ny nx]);
            H.density = max(H.density, dGrid);
            H.crush   = max(H.crush, cGrid);
        else
            stuckFrac(k) = 0; meanSpeed(k) = 0; peakLoad(k) = 0; crushed(k) = 0;
        end
        nextSample = nextSample + sampleEvery;
    end
end
k = min(k, nMax);
R.series = table(t(1:k), inside(1:k), exited(1:k), outflow(1:k), stuckFrac(1:k), ...
    meanSpeed(1:k), peakLoad(1:k), crushed(1:k), 'VariableNames', ...
    {'t','inside','exited','outflow','stuckFrac','meanSpeed','peakLoad','crushed'});

tEnd = S.t;
ex = S.exitTimes;
R.summary.flow = numel(ex)/max(tEnd, eps);
gaps = diff([0; ex]);
if isempty(gaps), gaps = tEnd; end
R.summary.longestStall  = max(gaps);
R.summary.peakLoad      = maxLoadSeen;
R.summary.crushedAgents = S.nCrushedGone + sum(S.everCrushed);
R.summary.evacTime      = S.evacTime;
R.summary.exited        = numel(S.exitTimes);
R.final = S;
end


% ======================= FIGURE 1: TIME SERIES =======================
function plotTimeSeries(R, densNames, panicLabels, pal, outDir)
f = figure('Visible', 'on', 'Color', 'w', 'Units', 'normalized', 'OuterPosition', [0.05 0.05 0.9 0.88]);
try theme(f, 'light'); catch, end
tl = tiledlayout(f, 4, 3, 'TileSpacing', 'loose', 'Padding', 'normal');

fields = {'meanSpeed', 'exited', 'crushed', 'peakLoad'};
rowLabels = { ...
    {'Avg Speed', '(m/s)'}; ...
    {'Evacuated', '(count)'}; ...
    {'Crushed (live)', '(agents)'}; ...
    {'Peak Load', '(N/m)'} ...
};
shortUnits = {'m/s', 'count', 'agents', 'N/m'};

for r = 1:4
    for c = 1:3
        ax = nexttile(tl); hold(ax, 'on'); grid(ax, 'on');
        ax.FontSize = 10;
        for p = 1:3
            ser = R{c, p}.series;
            plot(ax, ser.t, ser.(fields{r}), 'LineWidth', 1.6, ...
                'Color', pal.cat(p,:), 'DisplayName', panicLabels{p});
        end
        xlim(ax, [0 300]);
        if r == 1
            title(ax, densNames{c}, 'FontSize', 12, 'FontWeight', 'bold');
        end
        if c == 1
            ylabel(ax, rowLabels{r}, 'FontSize', 10, 'FontWeight', 'bold');
        else
            ylabel(ax, shortUnits{r}, 'FontSize', 9);
        end
        if r == 4
            xlabel(ax, 'Time (s)', 'FontSize', 10);
        end
        if r == 1 && c == 3
            legend(ax, 'Location', 'northeast', 'FontSize', 9);
        end
    end
end

title(tl, 'ExitArch: Evacuation Metrics Over Time', 'FontSize', 14, 'FontWeight', 'bold');
saveFig(f, outDir, 'exitarch_timeseries');
end


% ======================= FIGURE 2: HEATMAPS =======================
function plotHeatmaps(heatCells, densNames, pal, outDir)
nD = numel(densNames);
f = figure('Color', 'w', 'Position', [40 40 400*nD 600]);

rows = {'density', pal.density, 'peak agents / cell',     'density'; ...
        'crush',   pal.crush,   'peak compression (N/m)', 'crush risk'};
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

f = figure('Visible', 'on', 'Color', 'w', 'Position', [60 60 1200 380]);
try theme(f, 'light'); catch, end
metrics = {evacTime,     'Evacuation Time (s)',   'time (s)'; ...
           totalCrushed, 'Total Ever Crushed',    'agent count'; ...
           peakLoad,     'Peak Load',             'load (N/m)'};
for m = 1:3
    subplot(1, 3, m);
    b = bar(metrics{m,1});
    for p = 1:nP
        b(p).FaceColor = pal.cat(p,:);
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