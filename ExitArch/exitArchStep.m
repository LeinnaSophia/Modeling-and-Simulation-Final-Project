function S = exitArchStep(S)
%EXITARCHSTEP  Advance the crowd by one time step S.P.dt.
%
%   Each person i obeys (Helbing, Farkas & Vicsek 2000)
%
%     m dv_i/dt = m (v0 e_i - v_i)/tau                         driving force
%               + sum_j [A exp((r_ij-d_ij)/B) + k g(r_ij-d_ij)] n_ij
%               + sum_j  kappa g(r_ij-d_ij) (dv_ji . t_ij) t_ij  body friction
%               + same terms for walls, door jambs and pillars
%
%   with g(x) = max(x,0): the body terms only act when people touch.

P = S.P; G = S.G; dt = P.dt;
N = size(S.pos,1);
if N == 0
    S.t = S.t + dt;
    return;
end

X = S.pos(:,1); Y = S.pos(:,2); V = S.vel; r = S.r;
cMax = 0.45*P.mass/dt;      % caps kappa*g so explicit Euler stays stable

% --- driving force toward the exit ---
E = desiredDirection(X, Y, r, G);
F = P.mass*(P.v0*E - V)/P.tau;
load = zeros(N,1);

% --- person-person forces ---
contacts = zeros(0,3);
if N > 1
    dX = X - X.'; dY = Y - Y.';
    D2 = dX.^2 + dY.^2;
    Rs = r + r.';
    mask = triu(D2 < (Rs + 0.6).^2, 1);   % beyond 0.6 m gap the force is < 1 N
    idx = find(mask);
    if ~isempty(idx)
        [I, J] = ind2sub([N N], idx(:));
        I = I(:); J = J(:);
        d  = max(sqrt(D2(idx)), 1e-6);
        nx = dX(idx)./d; ny = dY(idx)./d;  % unit vector from j to i
        g  = max(Rs(idx) - d, 0);          % overlap
        fn = P.A*exp((Rs(idx) - d)/P.B) + P.k*g;
        tx = -ny; ty = nx;
        dvt = (V(J,1) - V(I,1)).*tx + (V(J,2) - V(I,2)).*ty;
        ft  = min(P.kappa*g, cMax).*dvt;
        fx = fn.*nx + ft.*tx;
        fy = fn.*ny + ft.*ty;
        F(:,1) = F(:,1) + accumarray(I, fx, [N 1]) - accumarray(J, fx, [N 1]);
        F(:,2) = F(:,2) + accumarray(I, fy, [N 1]) - accumarray(J, fy, [N 1]);
        % crush load counts body compression only (k*g), not the social push
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
    ax = w(3) - w(1); ay = w(4) - w(2);
    u = ((X - w(1))*ax + (Y - w(2))*ay)/(ax^2 + ay^2);
    m = u > 0 & u < 1;
    if ~any(m), continue; end
    ddx = X(m) - (w(1) + u(m)*ax);
    ddy = Y(m) - (w(2) + u(m)*ay);
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

% --- integrate (semi-implicit Euler) ---
V = V + F/P.mass*dt;
sp = sqrt(sum(V.^2, 2));
fast = find(sp > P.vMax);
if ~isempty(fast)
    V(fast,:) = V(fast,:)./sp(fast)*P.vMax;
end
pos = S.pos + V*dt;
inRoom = pos(:,1) < G.L;                      % safety net against tunnelling
pos(inRoom,2) = min(max(pos(inRoom,2), 0.02), G.H - 0.02);
pos(:,1) = max(pos(:,1), 0.02);

S.t   = S.t + dt;
S.pos = pos; S.vel = V;
S.contacts = contacts;

% --- loads, status ---
S.load = load./(2*pi*r);
S.everCrushed = S.everCrushed | S.load > P.crushLoad;
S.peakLoadNow = max(S.load);
S.peakLoad = max(S.peakLoad, S.peakLoadNow);
spd = sqrt(sum(V.^2, 2));
st = ones(N,1);
st(spd < 0.5*P.v0) = 2;
st(spd < max(0.1*P.v0, 0.05)) = 3;
st(S.load > P.crushLoad) = 4;
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
    if strcmp(P.scenario, 'Steady Stream')
        keep = true(N,1); keep(out) = false;
        for q = out.'
            others = find(keep);
            S.pos(q,:) = exitArchPlace(G, S.pos(others,:), S.r(others), S.r(q), G.spawnBox, 40);
            S.vel(q,:) = 0;
            S.load(q) = 0; S.everCrushed(q) = false; S.status(q) = 1;
            keep(q) = true;
        end
        S.contacts = S.contacts(~any(ismember(S.contacts(:,1:2), out), 2), :);
    else
        keep = true(N,1); keep(out) = false;
        S.pos = S.pos(keep,:); S.vel = S.vel(keep,:); S.r = S.r(keep);
        S.load = S.load(keep); S.everCrushed = S.everCrushed(keep); S.status = S.status(keep);
        % re-index contact list to the surviving agents
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
end

% -------------------------------------------------------------------------
function [F, load] = obstacleForce(F, load, m, ddx, ddy, R, r, V, P, cMax)
% Force from a fixed obstacle on agents m. (ddx,ddy) points from the
% obstacle's centre (or closest point) to the agent; R is its radius.
dc = max(hypot(ddx, ddy), 1e-6);
nx = ddx./dc; ny = ddy./dc;
d  = dc - R;                         % distance from obstacle surface
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
function E = desiredDirection(X, Y, r, G)
% Head for the nearest door, aiming at the closest point of the opening
% that the body fits through; walk around a pillar that blocks the line.
N = numel(X);
best = inf(N,1); tx = zeros(N,1); ty = zeros(N,1);
for k = 1:size(G.doors,1)
    ylo = G.doors(k,2); yhi = G.doors(k,3); yc = (ylo + yhi)/2;
    dd = hypot(G.L - X, yc - Y);
    lo = ylo + r; hi = yhi - r;
    yt = min(max(Y, lo), hi);
    yt(lo > hi) = yc;
    b = dd < best;
    best(b) = dd(b);
    tx(b) = G.L + G.wallT;
    ty(b) = yt(b);
end

for c = 1:size(G.pillars,1)
    pc = G.pillars(c,:);
    up = X < pc(1);
    if ~any(up), continue; end
    % closest approach of the straight path to the pillar centre
    sx = tx - X; sy = ty - Y; s2 = sx.^2 + sy.^2;
    u = min(max(((pc(1) - X).*sx + (pc(2) - Y).*sy)./s2, 0), 1);
    miss = hypot(X + u.*sx - pc(1), Y + u.*sy - pc(2));
    blocked = up & miss < pc(3) + r + 0.1;
    if any(blocked)
        side = sign(Y(blocked) - pc(2));
        side(side == 0) = 1;
        tx(blocked) = pc(1);
        ty(blocked) = pc(2) + side.*(pc(3) + r(blocked) + 0.25);
    end
end

ex = tx - X; ey = ty - Y;
past = X > G.L + G.wallT - 0.05;
ex(past) = 1; ey(past) = 0;
len = max(hypot(ex, ey), 1e-9);
E = [ex./len, ey./len];
end
