function [p, ok] = exitArchPlace(G, pos, rad, rNew, box, nTry)
%EXITARCHPLACE  Find a free spot for a body of radius rNew inside box.
%   box = [xmin xmax ymin ymax]. Returns ok = false (and the spot with the
%   most clearance) if no overlap-free spot was found in nTry attempts.

if nargin < 6, nTry = 200; end
best = []; bestClear = -inf;
for t = 1:nTry
    x = box(1) + rand*(box(2) - box(1));
    y = box(3) + rand*(box(4) - box(3));
    if ~G.walkable(x, y, rNew), continue; end
    if isempty(pos)
        clearance = inf;
    else
        clearance = min(hypot(pos(:,1) - x, pos(:,2) - y) - rad - rNew);
    end
    if clearance >= 0.02
        p = [x y]; ok = true; return;
    end
    if clearance > bestClear
        bestClear = clearance; best = [x y];
    end
end
ok = false;
p = best;
if isempty(p)
    p = [mean(box(1:2)) mean(box(3:4))];
end
end
