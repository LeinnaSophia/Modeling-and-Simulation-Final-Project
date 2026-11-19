function S = exitArchInit(P)
%EXITARCHINIT  Build the room and place the crowd. Returns the sim state S.

if ~isempty(P.seed), rng(P.seed); end

G = buildGeometry(P);
N = round(P.nAgents);

S.P = P;
S.G = G;
S.r   = P.rMin + (P.rMax - P.rMin)*rand(N,1);
S.pos = zeros(N,2);
if P.concertScenario
    placeBox = [P.stageDepth + 0.5, G.L - 1.0, 0, G.H];
else
    placeBox = [0.5, G.L - 1.0, 0, G.H];
end
for i = 1:N
    S.pos(i,:) = exitArchPlace(G, S.pos(1:i-1,:), S.r(1:i-1), S.r(i), placeBox, 300);
end
S.vel = zeros(N,2);

%per-agent desired speed (random within range, not one value for everyone)
S.v0 = P.v0Min + (P.v0Max - P.v0Min)*rand(N,1);

%per-agent panic level (random within range)
S.panic = P.panicMin + (P.panicMax - P.panicMin)*rand(N,1);

%per-agent relaxation time derived from panic
%calm (panic=0) -> tau=5s (patient), panicked (panic=1) -> tau=0.5s (lunging)
S.tau = 0.5 * S.panic + 5.0 * (1 - S.panic);

S.t            = 0;
S.exitTimes    = zeros(0,1);
S.lastExit     = NaN;
S.longestStall = 0;
S.load         = zeros(N,1);
S.peakLoadNow  = 0;
S.peakLoad     = 0;
S.everCrushed  = false(N,1);
S.nCrushedGone = 0;
S.status       = ones(N,1);  % 1 walking, 2 slowed, 3 stuck, 4 crushed
S.contacts     = zeros(0,3);
S.localDensity = zeros(N,1);
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
doors = [L*ones(numel(centres),1), centres - w/2, centres + w/2];

walls = [0 0 L 0;          % bottom
         0 H L H;          % top
         0 0 0 H];         % left
edges = [0; reshape(doors(:,2:3).', [], 1); H];
for k = 1:2:numel(edges)
    if edges(k+1) - edges(k) > 1e-9
        walls(end+1,:) = [L edges(k) L edges(k+1)]; %#ok<AGROW>
    end
end
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

hasStage    = P.concertScenario;
hasObstacle = P.centralObstacle;

stagePolys = {};
if hasStage
    sd = P.stageDepth;
    sy1 = P.stageYMin; sy2 = P.stageYMax;
    walls(end+1,:) = [0   sy1 sd  sy1];
    walls(end+1,:) = [sd  sy1 sd  sy2];
    walls(end+1,:) = [sd  sy2 0   sy2];
    stagePolys = {[0 sy1; sd sy1; sd sy2; 0 sy2]};
end

obstPolys = {};
if hasObstacle
    ox1 = P.obstacleXMin; oy1 = P.obstacleYMin;
    ox2 = P.obstacleXMax; oy2 = P.obstacleYMax;
    walls(end+1,:) = [ox1 oy1 ox2 oy1];
    walls(end+1,:) = [ox2 oy1 ox2 oy2];
    walls(end+1,:) = [ox2 oy2 ox1 oy2];
    walls(end+1,:) = [ox1 oy2 ox1 oy1];
    obstPolys = {[ox1 oy1; ox2 oy1; ox2 oy2; ox1 oy2]};
end

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
for q = 1:numel(stagePolys)
    polys{end+1} = stagePolys{q}; %#ok<AGROW>
end
for q = 1:numel(obstPolys)
    polys{end+1} = obstPolys{q}; %#ok<AGROW>
end

G.L = L; G.H = H; G.wallT = T;
G.doors   = doors;
G.walls   = walls;
G.corners = corners;
G.pillars = pillars;
G.polys   = polys;
G.exitX   = L + T + 0.4;
if hasStage
    G.spawnBox = [P.stageDepth + 0.5, 3 + P.stageDepth, 0, H];
else
    G.spawnBox = [0.5, 3.5, 0, H];
end
G.walkable = @(x, y, rr) walkable(x, y, rr, L, H, F, doors, pillars, P);
end

% -------------------------------------------------------------------------
function ok = walkable(x, y, rr, L, H, F, doors, pillars, P)
ok = x > rr & x < L - rr & y > rr & y < H - rr;
if F > 0
    ylo = doors(1,2); yhi = doors(1,3);
    nl = hypot(F, ylo); nu = hypot(F, H - yhi);
    sLow = ((x - (L-F))*(-ylo) + y*F) / nl;
    sUp  = ((x - (L-F))*(yhi - H) + (y - H)*(-F)) / nu;
    ok = ok & sLow > rr & sUp > rr;
end
for k = 1:size(pillars,1)
    ok = ok & hypot(x - pillars(k,1), y - pillars(k,2)) > pillars(k,3) + rr;
end
hasStage    = P.concertScenario;
hasObstacle = P.centralObstacle;
if hasStage
    sd = P.stageDepth; sy1 = P.stageYMin; sy2 = P.stageYMax;
    ok = ok & ~(x < sd + rr & y > sy1 - rr & y < sy2 + rr);
end
if hasObstacle
    ox1 = P.obstacleXMin; oy1 = P.obstacleYMin;
    ox2 = P.obstacleXMax; oy2 = P.obstacleYMax;
    ok = ok & ~(x > ox1 - rr & x < ox2 + rr & y > oy1 - rr & y < oy2 + rr);
end
end
