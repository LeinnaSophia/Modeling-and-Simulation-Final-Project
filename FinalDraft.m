clear; clc;
rng(42);

L = 10; W = 10;               % room is 10m x 10m
nx = 10; ny = 10;             % 10x10 grid
dx = L/nx; dy = W/ny;         % each cell is 1m x 1m (1 m^2)

     %----------------------

     %---------------------

             %p1  p2
%exit2         %()         %exit 1
             %p3  p4

     %----------------------
%exit width (more than 1 exit)
%dimensions of stadium
%estimate deaths per cell (condition total overlap of coordinates)

nSteps = 300;                 % how many time steps per scenario
dt     = 0.05;                % time per step (seconds)
exitX  = L;                   % exit at right wall
exitY  = W/2;                 % middle of right wall
v0     = 1.3;                 % desired walking speed (m/s)

panicLevels = [0.0, 0.5, 0.8];

%this is [minpercell maxpercell paniclevel]
scenarioSettings = [
    1  3  panicLevels(1);    % Baseline: <4 ppl/m^2, calm
    4  4  panicLevels(2);    % Active:   =4 ppl/m^2, active
    6 10  panicLevels(3);    % Erratic:  6+ ppl/m^2, erratic   
];
scenarioNames = {'Baseline', 'Active', 'Erratic'};

% --- RESULTS STORAGE ---
% One row per scenario, 7 numbers per row:
% [N0, avgSpeed, maxComp, avgPolar, restrictedFrac, density, escapedFrac]
resultsTable = zeros(3, 7);

for s = 1:3 %across three scenarios
    fprintf('Running: %s \n', scenarioNames{s});

    perCellMin = scenarioSettings(s,1);
    perCellMax = scenarioSettings(s,2);
    panicLevel = scenarioSettings(s,3);

    %agents with positions 
    pos      = []; %position of agents 
    vel      = []; %walking velocity 
    panicArr = []; %panic levels
    nPerCell = zeros(nx, ny); %agents in a cell. zeros(10,10) 

    for i = 1:nx
        for j = 1:ny
            n = randi([perCellMin, perCellMax]); %number inside between minCell and maxCell
            nPerCell(i,j) = n;

            cellX0 = (j-1)*dx;
            cellY0 = (i-1)*dy;

            newPos = [cellX0 + rand(n,1)*dx,  cellY0 + rand(n,1)*dy];
            pos      = [pos;      newPos];
            vel      = [vel;      zeros(n,2)];
            panicArr = [panicArr; panicLevel*ones(n,1)];
        end
    end

    N  = size(pos,1);
    N0 = N;                          % initial count — for reporting
    density0 = N0 / (L*W);           % initial density — fixed per scenario

    % ---------- PRINT INITIAL STATE ----------
    fprintf('\n--- Agent count per cell (nPerCell) ---\n');
    disp(nPerCell);

    fprintf('Initial N0 = %d\n', N0);
    fprintf('Density   = %.2f ppl/m^2\n', density0);
    fprintf('Size of pos = %d x %d\n', size(pos,1), size(pos,2));
    fprintf('Size of vel = %d x %d\n', size(vel,1), size(vel,2));
    fprintf('Size of panicArr = %d x %d\n', size(panicArr,1), size(panicArr,2));

    fprintf('\nFirst 5 agents (pos | vel | panic):\n');
    for k = 1:min(5, N)
        fprintf('  agent %2d: pos = (%6.3f, %6.3f)  vel = (%6.3f, %6.3f)  panic = %.2f\n', ...
            k, pos(k,1), pos(k,2), vel(k,1), vel(k,2), panicArr(k));
    end

    % ---------- HISTORY ----------
    speedHist = zeros(nSteps,1);
    compHist  = zeros(nSteps,1);
    polarHist = zeros(nSteps,1);
    restrHist = zeros(nSteps,1);

    % ---------- SIMULATION LOOP ----------
    for k = 1:nSteps

        % --- guard: everyone escaped ---
        if N == 0
            if k > 1
                speedHist(k:end) = speedHist(k-1);
                compHist(k:end)  = compHist(k-1);
                polarHist(k:end) = polarHist(k-1);
                restrHist(k:end) = restrHist(k-1);
            end
            break;
        end

        % --- 1. desired direction toward exit, with panic jitter ---
        toExitX = exitX - pos(:,1);
        toExitY = exitY - pos(:,2);
        lenExit = sqrt(toExitX.^2 + toExitY.^2) + 1e-9;
        dirX = toExitX ./ lenExit;
        dirY = toExitY ./ lenExit;

        ang = panicArr .* pi .* randn(N,1);   % jitter angle per agent
        ca  = cos(ang);
        sa  = sin(ang);
        dirX = ca.*dirX - sa.*dirY;
        dirY = sa.*dirX + ca.*dirY;

        % --- 2. repulsion forces between agents ---
        Fx = zeros(N,1);
        Fy = zeros(N,1);
        A_social = 2.0 * (1 + mean(panicArr));
        B        = 0.3;
        k_body   = 50  * (1 + 2*mean(panicArr));
        r        = 0.25;

        for i = 1:N
            for j = i+1:N
                ddx  = pos(j,1) - pos(i,1);
                ddy  = pos(j,2) - pos(i,2);
                dist = sqrt(ddx^2 + ddy^2);
                if dist > 0 && dist < 1.0
                    ux = ddx / dist;
                    uy = ddy / dist;
                    if dist < 2*r
                        mag = k_body * (2*r - dist);
                    else
                        mag = A_social * exp((2*r - dist)/B);
                    end
                    Fx(i) = Fx(i) - mag*ux;   Fy(i) = Fy(i) - mag*uy;
                    Fx(j) = Fx(j) + mag*ux;   Fy(j) = Fy(j) + mag*uy;
                end
            end
        end

        % update velocity and position 
        tau      = 0.5;
        vDesiredX = dirX * v0;
        vDesiredY = dirY * v0;
        vel(:,1) = vel(:,1) + (vDesiredX - vel(:,1))/tau * dt + Fx * dt/80;
        vel(:,2) = vel(:,2) + (vDesiredY - vel(:,2))/tau * dt + Fy * dt/80;
        pos(:,1) = pos(:,1) + vel(:,1) * dt;
        pos(:,2) = pos(:,2) + vel(:,2) * dt;

        % --- 4. clamp to walls ---
        pos(:,1) = min(max(pos(:,1), 0.1), L-0.1);
        pos(:,2) = min(max(pos(:,2), 0.1), W-0.1);

        % --- 4b. agents who reach the exit LEAVE the simulation ---
        reached = pos(:,1) >= L - 0.2;
        if any(reached)
            pos(reached, :)   = [];
            vel(reached, :)   = [];
            panicArr(reached) = [];
            N = size(pos, 1);
        end

        % --- 5. metrics for this step ---
        if N == 0
            speedHist(k) = 0;
            restrHist(k) = 0;
            polarHist(k) = 0;
            compHist(k)  = 0;
            continue;
        end

        speeds = sqrt(vel(:,1).^2 + vel(:,2).^2);
        speedHist(k) = mean(speeds);
        restrHist(k) = mean(speeds < 0.2*v0);

        if any(speeds > 1e-6)
            ux = vel(:,1) ./ (speeds + 1e-9);
            uy = vel(:,2) ./ (speeds + 1e-9);
            polarHist(k) = sqrt(mean(ux)^2 + mean(uy)^2);
        else
            polarHist(k) = 0;
        end

        overlap = 0;
        for i = 1:N
            for j = i+1:N
                dd = sqrt((pos(i,1)-pos(j,1))^2 + (pos(i,2)-pos(j,2))^2);
                if dd < 2*r
                    overlap = overlap + (2*r - dd);
                end
            end
        end
        compHist(k) = overlap / max(N, 1);   % per-agent average
    end

    % print final 
    fprintf('\n--- After %d steps ---\n', nSteps);
    fprintf('Initial N0 = %d, Remaining N = %d, Escaped = %d (%.1f%%)\n', ...
        N0, N, N0 - N, 100*(N0 - N)/N0);
    fprintf('Size of pos = %d x %d\n', size(pos,1), size(pos,2));
    fprintf('Size of vel = %d x %d\n', size(vel,1), size(vel,2));

    if N > 0
        fprintf('\nFirst %d remaining agents:\n', min(5, N));
        for k = 1:min(5, N)
            fprintf('  agent %2d: pos = (%6.3f, %6.3f)  vel = (%6.3f, %6.3f)\n', ...
                k, pos(k,1), pos(k,2), vel(k,1), vel(k,2));
        end
    end

    % time series 
    fprintf('\nMetrics over time:\n');
    fprintf('  speedHist   : first = %.3f, last = %.3f, mean = %.3f\n', ...
        speedHist(1), speedHist(end), mean(speedHist));
    fprintf('  compHist    : first = %.3f, last = %.3f, max  = %.3f\n', ...
        compHist(1), compHist(end), max(compHist));
    fprintf('  polarHist   : first = %.3f, last = %.3f, mean = %.3f\n', ...
        polarHist(1), polarHist(end), mean(polarHist));
    fprintf('  restrHist   : first = %.3f, last = %.3f, mean = %.3f\n', ...
        restrHist(1), restrHist(end), mean(restrHist));

    % results
    warmup = min(20, nSteps);
    escapedFrac = (N0 - N) / N0;

    resultsTable(s,:) = [N0, ...
                         mean(speedHist(warmup:end)), ...
                         max(compHist), ...
                         mean(polarHist(warmup:end)), ...
                         mean(restrHist(warmup:end)), ...
                         density0, ...
                         escapedFrac];
end

% final comparison
fprintf('=== SCENARIO COMPARISON TABLE ===\n');
fprintf('%-12s %6s %8s %10s %10s %12s %12s %10s\n', ...
    'Scenario','N0','Density','AvgSpeed','MaxComp','Polarization','Restricted%','Escaped%');
for s = 1:3
    r = resultsTable(s,:);
    fprintf('%-12s %6d %8.2f %10.3f %10.3f %12.3f %12.1f %10.1f\n', ...
        scenarioNames{s}, r(1), r(6), r(2), r(3), r(4), 100*r(5), 100*r(7));
end

% raw matrix 
fprintf('\nresultsTable (raw matrix):\n');
fprintf('  columns: [N0, avgSpeed, maxComp, avgPolar, restrictedFrac, density, escapedFrac]\n');
disp(resultsTable);