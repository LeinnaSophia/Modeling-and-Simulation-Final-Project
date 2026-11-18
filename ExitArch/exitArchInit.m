function S = exitArchInit(P)
%EXITARCHINIT  Build the room and place the crowd. Returns the sim state S.

if ~isempty(P.seed), rng(P.seed); end

G = buildGeometry(P);
N = round(P.nAgents);

S.P = P;
S.G = G;
S.r   = P.rMin + (P.rMax - P.rMin)*rand(N,1);
S.pos = zeros(N,2);
placeBox = [0, G.L - 1.0, 0, G.H];   % keep the first metre in front of the door clear
for i = 1:N
    S.pos(i,:) = exitArchPlace(G, S.pos(1:i-1,:), S.r(1:i-1), S.r(i), placeBox, 300);
end
S.vel = zeros(N,2);

S.t            = 0;
S.exitTimes    = zeros(0,1);
S.lastExit     = NaN;
S.longestStall = 0;          % longest gap between consecutive exits, s
S.load         = zeros(N,1); % radial contact load per circumference, N/m
S.peakLoadNow  = 0;
S.peakLoad     = 0;          % max over the run
S.everCrushed  = false(N,1);
S.nCrushedGone = 0;          % crushed-at-some-point agents that have since left
S.status       = ones(N,1);  % 1 walking, 2 slowed, 3 stuck, 4 crushed
S.contacts     = zeros(0,3); % [i j radialForce] for touching pairs
S.done         = false;
S.evacTime     = NaN;
end

% -------------------------------------------------------------------------
function G = buildGeometry(P)
L = P.L; H = P.H; T = P.wallT; w = P.doorWidth;

switch P.layout
    case 'Twin Doors'
        centres = [H/3; 2*H/3];
    otherwise
        centres = H/2;
end
doors = [L*ones(numel(centres),1), centres - w/2, centres + w/2];   % [x ylo yhi]

% Wall faces the crowd can touch, as segments [x1 y1 x2 y2].
walls = [0 0 L 0;          % bottom
         0 H L H;          % top
         0 0 0 H];         % left
% Right wall: solid pieces between doors.
edges = [0; reshape(doors(:,2:3).', [], 1); H];
for k = 1:2:numel(edges)
    if edges(k+1) - edges(k) > 1e-9
        walls(end+1,:) = [L edges(k) L edges(k+1)]; %#ok<AGROW>
    end
end
% Door channel sides (jambs) and their convex corners.
corners = zeros(0,2);
for k = 1:size(doors,1)
    walls(end+1,:) = [L doors(k,2) L+T doors(k,2)]; %#ok<AGROW>
    walls(end+1,:) = [L doors(k,3) L+T doors(k,3)]; %#ok<AGROW>
    corners = [corners; L doors(k,2); L doors(k,3); L+T doors(k,2); L+T doors(k,3)]; %#ok<AGROW>
end

pillars = zeros(0,3);
F = 0;
if strcmp(P.layout, 'Pillar')
    pillars = [L - P.pillarDist, H/2, P.pillarRadius];
end
if strcmp(P.layout, 'Funnel')
    F = P.funnelLen;
    walls(end+1,:) = [L-F 0 L doors(1,2)];
    walls(end+1,:) = [L-F H L doors(1,3)];
end

% Wall bodies for drawing (polygons, each a cell of [x y]).
polys = {[-T -T; L+T -T; L+T 0; -T 0], ...
         [-T H; L+T H; L+T H+T; -T H+T], ...
         [-T 0; 0 0; 0 H; -T H]};
for k = 1:2:numel(edges)
    if edges(k+1) - edges(k) > 1e-9
        polys{end+1} = [L edges(k); L+T edges(k); L+T edges(k+1); L edges(k+1)]; %#ok<AGROW>
    end
end
if F > 0
    polys{end+1} = [L-F 0; L 0; L doors(1,2)];
    polys{end+1} = [L-F H; L H; L doors(1,3)];
end

G.L = L; G.H = H; G.wallT = T;
G.doors   = doors;
G.walls   = walls;
G.corners = corners;
G.pillars = pillars;
G.polys   = polys;
G.exitX   = L + T + 0.4;                 % past this an agent has left the room
G.spawnBox = [0, 3, 0, H];               % where Steady Stream re-inserts people
G.walkable = @(x, y, rr) walkable(x, y, rr, L, H, F, doors, pillars);
end

% -------------------------------------------------------------------------
function ok = walkable(x, y, rr, L, H, F, doors, pillars)
ok = x > rr & x < L - rr & y > rr & y < H - rr;
if F > 0
    ylo = doors(1,2); yhi = doors(1,3);
    nl = hypot(F, ylo); nu = hypot(F, H - yhi);
    sLow = ((x - (L-F))*(-ylo) + y*F) / nl;            % >0 above the lower funnel wall
    sUp  = ((x - (L-F))*(yhi - H) + (y - H)*(-F)) / nu; % >0 below the upper funnel wall
    ok = ok & sLow > rr & sUp > rr;
end
for k = 1:size(pillars,1)
    ok = ok & hypot(x - pillars(k,1), y - pillars(k,2)) > pillars(k,3) + rr;
end
end
