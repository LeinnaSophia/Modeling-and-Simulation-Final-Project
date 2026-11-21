function S = exitArchStep(S)
%EXITARCHSTEP  Advance the crowd by one time step S.P.dt.
%
%   Each person i obeys (Helbing, Farkas & Vicsek 2000)
%
%     m dv_i/dt = m (v0_i e_i - v_i)/tau_i                      driving force
%               + sum_j [A exp((r_ij-d_ij)/B) + k g(r_ij-d_ij)] n_ij
%               + sum_j  kappa g(r_ij-d_ij) (dv_ji . t_ij) t_ij  body friction
%               + same terms for walls, door jambs and pillars
%
%   v0_i and tau_i are per-agent (speed range + panic-based relaxation).
%   Slowdown in dense areas is emergent from contact forces, not imposed.
%   Direction is jittered by panic (Helbing noise term).

P = S.P; G = S.G; dt = P.dt;
N = size(S.pos,1);
if N == 0
    S.t = S.t + dt;
    return;
end

X = S.pos(:,1); Y = S.pos(:,2); V = S.vel; r = S.r;
cMax = 0.45*P.mass/dt;

% --- local density per agent (grid-based, O(N) instead of O(N^2)) ---
localDensity = zeros(N, 1);
if N > 1
    cellSz = 1.0;
    nCX = ceil(G.L / cellSz); nCY = ceil(G.H / cellSz);
    cix = max(1, min(nCX, ceil(X / cellSz)));
    ciy = max(1, min(nCY, ceil(Y / cellSz)));
    cellCnt = accumarray([ciy cix], 1, [nCY nCX]);
    kern = [0.075 0.124 0.075; 0.124 0.206 0.124; 0.075 0.124 0.075];
    smoothed = conv2(cellCnt, kern, 'same');
    localDensity = smoothed(sub2ind([nCY nCX], ciy, cix));
end
S.localDensity = localDensity;

% --- desired direction toward the exit ---
E = desiredDirection(X, Y, r, G);

% panic jitter: rotate desired direction by a random angle scaled by panic
jitterAngle = S.panic .* pi .* randn(N, 1);
cosA = cos(jitterAngle);
sinA = sin(jitterAngle);
jitteredX = cosA .* E(:,1) - sinA .* E(:,2);
jitteredY = sinA .* E(:,1) + cosA .* E(:,2);
E = [jitteredX, jitteredY];

% --- driving force (per-agent speed and tau) ---
% v0 is the full desired speed; slowdown in dense areas is emergent from
% contact forces (Helbing 2000), not imposed by Weidmann decay.
F = P.mass*(S.v0.*E - V)./S.tau;
load = zeros(N,1);

% --- person-person forces ---
contacts = zeros(0,3);
if N > 1
    dX = X - X.'; dY = Y - Y.';
    D2 = dX.^2 + dY.^2;
    Rs = r + r.';
    mask = triu(D2 < (Rs + 1.0).^2, 1);
    idx = find(mask);
    if ~isempty(idx)
        [I, J] = ind2sub([N N], idx(:));
        I = I(:); J = J(:);
        d  = max(sqrt(D2(idx)), 1e-6);
        nx = dX(idx)./d; ny = dY(idx)./d;
        g  = max(Rs(idx) - d, 0);
        fn = P.A*exp((Rs(idx) - d)/P.B) + P.k*g;
        tx = -ny; ty = nx;
        dvt = (V(J,1) - V(I,1)).*tx + (V(J,2) - V(I,2)).*ty;
        ft  = min(P.kappa*g, cMax).*dvt;
        fx = fn.*nx + ft.*tx;
        fy = fn.*ny + ft.*ty;
        F(:,1) = F(:,1) + accumarray(I, fx, [N 1]) - accumarray(J, fx, [N 1]);
        F(:,2) = F(:,2) + accumarray(I, fy, [N 1]) - accumarray(J, fy, [N 1]);
        c = find(g > 0);
        if ~isempty(c)
            fb = P.k*g(c);
            load = load + accumarray(I(c), fb, [N 1]) + accumarray(J(c), fb, [N 1]);
            contacts = [I(c) J(c) fb];
        end
    end
end

% --- walls (segment interiors), convex corners, pillars ---
for s = 1:size(G.walls,1)
    w = G.walls(s,:);
    wax = w(3) - w(1); way = w(4) - w(2);
    u = ((X - w(1))*wax + (Y - w(2))*way)/(wax^2 + way^2);
    m = u > 0 & u < 1;
    if ~any(m), continue; end
    ddx = X(m) - (w(1) + u(m)*wax);
    ddy = Y(m) - (w(2) + u(m)*way);
    [F, load] = obstacleForce(F, load, m, ddx, ddy, 0, r, V, P, cMax);
end
for c = 1:size(G.corners,1)
    m = abs(X - G.corners(c,1)) < 1 & abs(Y - G.corners(c,2)) < 1;
    if ~any(m), continue; end
    [F, load] = obstacleForce(F, load, m, X(m) - G.corners(c,1), Y(m) - G.corners(c,2), 0, r, V, P, cMax);
end
for c = 1:size(G.pillars,1)
    pc = G.pillars(c,:);
    m = hypot(X - pc(1), Y - pc(2)) < pc(3) + 1.5;
    if ~any(m), continue; end
    [F, load] = obstacleForce(F, load, m, X(m) - pc(1), Y(m) - pc(2), pc(3), r, V, P, cMax);
end

% --- force cap per agent (CrowdSimulation.m: maxForcePerAgent = 2000) ---
fMag = sqrt(sum(F.^2, 2));
tooBig = fMag > P.maxForce;
if any(tooBig), F(tooBig,:) = F(tooBig,:) .* (P.maxForce./fMag(tooBig)); end

% --- integrate (semi-implicit Euler) ---
V = V + F/P.mass*dt;
sp = sqrt(sum(V.^2, 2));
fast = find(sp > P.vMax);
if ~isempty(fast)
    V(fast,:) = V(fast,:)./sp(fast)*P.vMax;
end
pos = S.pos + V*dt;
inRoom = pos(:,1) < G.L;
pos(inRoom,2) = min(max(pos(inRoom,2), 0.02), G.H - 0.02);
pos(:,1) = max(pos(:,1), 0.02);

% hard-clamp: push agents out of stage, obstacle, pillar, and funnel
if P.concertScenario
    sd = P.stageDepth; sy1 = P.stageYMin; sy2 = P.stageYMax;
    inside = pos(:,1) < sd & pos(:,2) > sy1 & pos(:,2) < sy2;
    if any(inside)
        pos(inside,1) = sd + r(inside)*0.5;
        V(inside,:) = 0;
    end
end
if P.centralObstacle
    ox1 = P.obstacleXMin; oy1 = P.obstacleYMin;
    ox2 = P.obstacleXMax; oy2 = P.obstacleYMax;
    inside = pos(:,1) > ox1 & pos(:,1) < ox2 & pos(:,2) > oy1 & pos(:,2) < oy2;
    if any(inside)
        dL = pos(inside,1) - ox1; dR = ox2 - pos(inside,1);
        dB = pos(inside,2) - oy1; dT = oy2 - pos(inside,2);
        [~, side] = min([dL dR dB dT], [], 2);
        idx = find(inside);
        for q = 1:numel(idx)
            switch side(q)
                case 1, pos(idx(q),1) = ox1 - r(idx(q))*0.5;
                case 2, pos(idx(q),1) = ox2 + r(idx(q))*0.5;
                case 3, pos(idx(q),2) = oy1 - r(idx(q))*0.5;
                case 4, pos(idx(q),2) = oy2 + r(idx(q))*0.5;
            end
        end
        V(inside,:) = 0;
    end
end
if strcmp(P.layout, 'Pillar')
    px = G.L - P.pillarDist; py = G.H / 2; pr = P.pillarRadius;
    d = hypot(pos(:,1) - px, pos(:,2) - py);
    inside = d < pr + r * 0.5;
    if any(inside)
        dc = max(d(inside), 1e-6);
        push = (pr + r(inside)*0.5) ./ dc;
        pos(inside,1) = px + (pos(inside,1) - px) .* push;
        pos(inside,2) = py + (pos(inside,2) - py) .* push;
        V(inside,:) = 0;
    end
end
if strcmp(P.layout, 'Funnel')
    F = P.funnelLen;
    doorBot = G.H/2 - P.doorWidth/2;
    doorTop = G.H/2 + P.doorWidth/2;
    inRegion = pos(:,1) > G.L - F;
    if any(inRegion)
        idx = find(inRegion);
        t = (pos(idx,1) - (G.L - F)) / F;
        yLow  = t * doorBot;
        yHigh = G.H - t * (G.H - doorTop);
        belowWall = pos(idx,2) < yLow;
        aboveWall = pos(idx,2) > yHigh;
        if any(belowWall)
            bi = idx(belowWall);
            pos(bi,2) = yLow(belowWall) + r(bi)*0.5;
            V(bi,:) = 0;
        end
        if any(aboveWall)
            ai = idx(aboveWall);
            pos(ai,2) = yHigh(aboveWall) - r(ai)*0.5;
            V(ai,:) = 0;
        end
    end
end

S.t   = S.t + dt;
S.pos = pos; S.vel = V;
S.contacts = contacts;

% --- loads, status ---
S.load = load;
S.everCrushed = S.everCrushed | load > P.crushLoad;
S.peakLoadNow = max(load);
S.peakLoad = max(S.peakLoad, S.peakLoadNow);
spd = sqrt(sum(V.^2, 2));
meanV0 = mean(S.v0);
st = ones(N,1);
st(spd < 0.5*meanV0) = 2;
st(spd < max(0.1*meanV0, 0.05)) = 3;
st(load > P.crushLoad) = 4;
S.status = st;

% --- exits ---
out = find(S.pos(:,1) > G.exitX);
if ~isempty(out)
    for q = 1:numel(out)
        if ~isnan(S.lastExit)
            S.longestStall = max(S.longestStall, S.t - S.lastExit);
        end
        S.lastExit = S.t;
    end
    S.exitTimes = [S.exitTimes; S.t*ones(numel(out),1)];
    S.nCrushedGone = S.nCrushedGone + sum(S.everCrushed(out));
    keep = true(N,1); keep(out) = false;
    S.pos = S.pos(keep,:); S.vel = S.vel(keep,:); S.r = S.r(keep);
    S.load = S.load(keep); S.everCrushed = S.everCrushed(keep); S.status = S.status(keep);
    S.v0 = S.v0(keep); S.panic = S.panic(keep); S.tau = S.tau(keep);
    S.localDensity = S.localDensity(keep);
    newIdx = cumsum(keep);
    nc = size(S.contacts,1);
    cKeep = all(reshape(keep(S.contacts(:,1:2)), nc, 2), 2);
    S.contacts = S.contacts(cKeep,:);
    S.contacts(:,1:2) = reshape(newIdx(S.contacts(:,1:2)), [], 2);
    if isempty(S.pos)
        S.done = true;
        S.evacTime = S.t;
    end
end
end

% -------------------------------------------------------------------------
function [F, load] = obstacleForce(F, load, m, ddx, ddy, R, r, V, P, cMax)
dc = max(hypot(ddx, ddy), 1e-6);
nx = ddx./dc; ny = ddy./dc;
d  = dc - R;
rm = r(m);
g  = max(rm - d, 0);
fn = P.A*exp((rm - d)/P.B) + P.k*g;
tx = -ny; ty = nx;
vt = V(m,1).*tx + V(m,2).*ty;
ft = -min(P.kappa*g, 2*cMax).*vt;
F(m,1) = F(m,1) + fn.*nx + ft.*tx;
F(m,2) = F(m,2) + fn.*ny + ft.*ty;
load(m) = load(m) + P.k*g;
end

% -------------------------------------------------------------------------
function E = desiredDirection(X, Y, ~, G)
res = G.distRes;
dist = G.distField;
[gridNy, gridNx] = size(dist);

ix = max(2, min(gridNx-1, ceil(X / res)));
iy = max(2, min(gridNy-1, ceil(Y / res)));

gx = dist(sub2ind([gridNy gridNx], iy, ix+1)) ...
   - dist(sub2ind([gridNy gridNx], iy, ix-1));
gy = dist(sub2ind([gridNy gridNx], iy+1, ix)) ...
   - dist(sub2ind([gridNy gridNx], iy-1, ix));

bad = isnan(gx) | isnan(gy) | isinf(gx) | isinf(gy);
gx(bad) = 1; gy(bad) = 0;

len = max(hypot(gx, gy), 1e-9);
E = [-gx./len, -gy./len];

past = X > G.exitX - 0.5;
E(past, 1) = 1;
E(past, 2) = 0;

unreachable = isinf(dist(sub2ind([gridNy gridNx], iy, ix)));
E(unreachable, 1) = 1;
E(unreachable, 2) = 0;
end
