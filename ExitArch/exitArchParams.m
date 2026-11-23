function P = exitArchParams(varargin)
%EXITARCHPARAMS  Default parameters for the Exit Arch crowd simulation.
%   P = exitArchParams() returns the defaults.
%   P = exitArchParams('layout', 'Pillar') overrides fields.
%
%   Physics follows the social-force model of Helbing, Farkas & Vicsek,
%   "Simulating dynamical features of escape panic", Nature 407 (2000).

% --- Setup ---
P.layout     = 'Single Door';   % 'Single Door' | 'Pillar' | 'Twin Doors' | 'Funnel'
P.scenario   = 'Evacuation';    % always Evacuation (room empties, no respawn)
P.doorWidth  = 1.00;            % m
P.pillarDist = 1.30;            % m, door to pillar centre (Pillar layout)
P.pillarRadius = 0.35;          % m

% --- Density scenario (sets agent count in exitArchInit) ---
P.densityScenario = 'Baseline'; % 'Baseline' | 'Dense' | 'High Density'

% --- Panic level (sets panic range in exitArchInit, independent of density) ---
P.panicLevel = 'Level A';      % 'Level A' | 'Level B' | 'Level C'

% --- Crowd defaults (v0 range; nAgents and panic overridden in init) ---
P.v0Min    = 0.80;              % m/s, Weidmann 1993 free-flow range
P.v0Max    = 1.30;              % m/s (adjustable via slider)
P.nAgents  = 288;               % overridden per scenario
P.kappa    = 2.4e5;             % body (sliding) friction, kg/(m s) (from Helbing)
P.panicMin = 0.0;
P.panicMax = 0.49;

% --- View ---
P.timeScale = 1.50;             % simulated seconds per wall-clock second (app only)

% --- Fixed room geometry (12 x 8 m = 96 m^2) ---
P.L         = 12;               % m, room length (x); door is on the right wall
P.H         = 8;               % m, room height (y)
P.wallT     = 0.30;             % wall thickness = length of the door channel
P.funnelLen = 4.0;              % funnel depth (Funnel layout)

% --- Concert scenario (stackable with any layout; coords scaled in exitArchInit) ---
P.concertScenario = true;       % true = add the stage on the far left
P.centralObstacle = true;       % true = add obstacle in the center of the room
P.stageDepth = 3.5;             % m, fallback (overridden by init scaling)
P.stageYMin  = 1.7;
P.stageYMax  = 8.3;
P.obstacleXMin = 8.0;
P.obstacleXMax = 10.5;
P.obstacleYMin = 3.75;
P.obstacleYMax = 6.25;

% --- Body / force constants (Helbing et al. 2000) ---
P.mass  = 80;                   % kg
P.A     = 2000;                 % N, social repulsion strength
P.B     = 0.08;                 % m, social repulsion range
P.k     = 1.2e5;                % kg/s^2, body compression
P.rMin  = 0.20;                 % m, body radius range
P.rMax  = 0.24;
P.vMax  = 5.0;                  % m/s, speed cap

% --- Numerics and measurement ---
P.dt         = 0.005;           % s, integration step
P.crushLoad  = 1600;            % N/m, body-compression load per circumference 
P.flowWindow = 5;               % s, sliding window for the outflow readout
P.seed       = [];              % rng seed ([] = do not reseed)

if mod(numel(varargin), 2) ~= 0
    error('exitArchParams:args', 'Use name/value pairs.');
end
for i = 1:2:numel(varargin)
    name = varargin{i};
    if ~isfield(P, name)
        error('exitArchParams:unknown', 'Unknown parameter "%s".', name);
    end
    P.(name) = varargin{i+1};
end
end
