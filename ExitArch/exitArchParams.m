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

% --- Crowd ---
P.v0       = 2.40;              % desired speed, m/s (urgency)
P.nAgents  = 260;               % people in the room
P.kappa    = 2.4e5;             % body (sliding) friction, kg/(m s)
P.tau      = 0.50;              % relaxation time, s

% --- View ---
P.timeScale = 1.50;             % simulated seconds per wall-clock second (app only)

% --- Room geometry ---
P.L         = 14;               % room length (x), door is on the right wall
P.H         = 12;               % room width (y)
P.wallT     = 0.30;             % wall thickness = length of the door channel
P.funnelLen = 4.0;              % funnel depth (Funnel layout)

% --- Body / force constants (Helbing et al. 2000) ---
P.mass  = 80;                   % kg
P.A     = 2000;                 % N, social repulsion strength
P.B     = 0.08;                 % m, social repulsion range
P.k     = 1.2e5;                % kg/s^2, body compression
P.rMin  = 0.25;                 % m, body radius range
P.rMax  = 0.35;
P.vMax  = 5.0;                  % m/s, speed cap

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
