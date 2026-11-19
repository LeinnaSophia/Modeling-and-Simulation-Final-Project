function P = exitArchParams(varargin)
%EXITARCHPARAMS  Default parameters for the Exit Arch crowd simulation.
%   P = exitArchParams() returns the defaults.
%   P = exitArchParams('v0', 3, 'layout', 'Pillar') overrides fields.
%
%   Physics follows the social-force model of Helbing, Farkas & Vicsek,
%   "Simulating dynamical features of escape panic", Nature 407 (2000).

% --- Setup ---
P.layout     = 'Single Door';   % 'Single Door' | 'Pillar' | 'Twin Doors' | 'Funnel'
P.scenario   = 'Steady Stream'; % 'Steady Stream' (exits respawn at the back) | 'Evacuation'
P.doorWidth  = 1.20;            % m
P.pillarDist = 1.30;            % m, door to pillar centre (Pillar layout)
P.pillarRadius = 0.35;          % m

% --- Crowd (range-based: each agent gets a random value within the range) ---
P.v0Min    = 0.80;              % slowest desired speed in the crowd, m/s
P.v0Max    = 2.40;              % fastest desired speed in the crowd, m/s
P.nAgents  = 260;               % people in the room
P.kappa    = 2.4e5;             % body (sliding) friction, kg/(m s)
P.panicMin = 0.0;               % lowest panic level (0 = calm)
P.panicMax = 0.49;              % highest panic level (1 = full panic)

% --- View ---
P.timeScale = 1.50;             % simulated seconds per wall-clock second (app only)

% --- Room geometry ---
P.L         = 20;               % room length (x), door is on the right wall
P.H         = 10;               % room width (y), more rectangular than before
P.wallT     = 0.30;             % wall thickness = length of the door channel
P.funnelLen = 4.0;              % funnel depth (Funnel layout)

% --- Stage (obstacle on the far left of the room) ---
P.stageDepth = 4.0;             % how far the stage sticks out from the left wall (m)
P.stageYMin  = 2.0;             % stage bottom edge y (m)
P.stageYMax  = 8.0;             % stage top edge y (m)

% --- Concert scenario (stage + optional central obstacle, stackable with any layout) ---
P.concertScenario = true;       % true = add the stage on the far left
P.centralObstacle = true;       % true = add obstacle in the center of the room
P.obstacleXMin = 8.0;           % obstacle left edge x
P.obstacleXMax = 12.0;          % obstacle right edge x
P.obstacleYMin = 3.5;           % obstacle bottom edge y
P.obstacleYMax = 6.5;           % obstacle top edge y

% --- Body / force constants (Helbing et al. 2000) ---
P.mass  = 80;                   % kg
P.A     = 2000;                 % N, social repulsion strength
P.B     = 0.08;                 % m, social repulsion range
P.k     = 1.2e5;                % kg/s^2, body compression
P.rMin  = 0.25;                 % m, body radius range
P.rMax  = 0.35;
P.vMax  = 5.0;                  % m/s, speed cap

% --- Density-dependent speed (Weidmann 1993) ---
P.rhoCrit = 5.4;                % ped/m^2 where desired speed drops to 37%

% --- Numerics and measurement ---
P.dt         = 0.005;           % s, integration step
P.crushLoad  = 1600;            % N/m, body-compression load per circumference counted as "crushed"
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
