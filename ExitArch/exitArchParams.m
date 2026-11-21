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
P.doorWidth  = 1.20;            % m
P.pillarDist = 1.30;            % m, door to pillar centre (Pillar layout)
P.pillarRadius = 0.35;          % m

% --- Density scenario (sets agent count in exitArchInit) ---
P.densityScenario = 'Baseline'; % 'Baseline' | 'Dense' | 'Crush Risk'

% --- Panic level (sets panic range in exitArchInit, independent of density) ---
P.panicLevel = 'Level A';      % 'Level A' | 'Level B' | 'Level C'

% --- Crowd defaults (v0 range; nAgents and panic overridden in init) ---
P.v0Min    = 0.80;              % m/s, Weidmann 1993 free-flow range
P.v0Max    = 1.80;              % m/s (adjustable via slider)
P.nAgents  = 500;               % overridden per scenario
P.kappa    = 6000;              % body (sliding) friction, kg/(m s)
P.panicMin = 0.0;
P.panicMax = 0.49;

% --- View ---
P.timeScale = 1.50;             % simulated seconds per wall-clock second (app only)

% --- Fixed room geometry (19 x 10 m = 190 m^2) ---
P.L         = 19;               % m, room length (x); door is on the right wall
P.H         = 10;               % m, room height (y)
P.wallT     = 0.30;             % wall thickness = length of the door channel
P.funnelLen = 4.0;              % funnel depth (Funnel layout)

% --- Concert scenario (stackable with any layout; coords scaled in exitArchInit) ---
P.concertScenario = true;       % true = add the stage on the far left
P.centralObstacle = true;       % true = add obstacle in the center of the room
P.stageDepth = 3.0;             % m, fallback (overridden by init scaling)
P.stageYMin  = 2.0;
P.stageYMax  = 7.0;
P.obstacleXMin = 7.0;
P.obstacleXMax = 10.0;
P.obstacleYMin = 3.5;
P.obstacleYMax = 5.5;

% --- Body / force constants (Helbing et al. 2000, tuned for dt=0.025) ---
% Between CrowdSimulation.m (k=3000, too soft) and raw Helbing (k=120000,
% too stiff). Crush triggers at real bottleneck compression, not casual contact.
P.mass  = 80;                   % kg
P.A     = 500;                  % N, social repulsion strength
P.B     = 0.20;                 % m, social repulsion range
P.k     = 15000;                % kg/s^2, body compression
P.rMin  = 0.20;                 % m, body radius range
P.rMax  = 0.30;
P.vMax  = 3.0;                  % m/s, speed cap
P.maxForce = 10000;              % N, force cap per agent to prevent blowup

% --- Numerics and measurement ---
P.dt         = 0.01;           % s, integration step
P.crushLoad  = 1600;            % N, body-compression force threshold
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
