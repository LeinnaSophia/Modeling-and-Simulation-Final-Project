function R = exitArchRun(P, simTime, varargin)
%EXITARCHRUN  Run the Exit Arch model without graphics and collect metrics.
%   R = exitArchRun(P, simTime) runs for simTime seconds (or until an
%   Evacuation empties the room).
%   R = exitArchRun(P, simTime, 'warmup', 10) ignores the first 10 s when
%   measuring flow and stalls (use it for Steady Stream runs).
%
%   R.summary has: flow (people/s), longestStall (s), peakLoad (N/m),
%   crushedAgents, evacTime (s, Evacuation only), exited.
%   R.series is a table sampled every 0.1 s.

opt.warmup = 0;
opt.sampleEvery = 0.1;
for i = 1:2:numel(varargin), opt.(varargin{i}) = varargin{i+1}; end

S = exitArchInit(P);
nMax = floor(simTime/opt.sampleEvery) + 1;
t = nan(nMax,1); inside = t; exited = t; outflow = t;
stuckFrac = t; meanSpeed = t; peakLoad = t; crushed = t;
k = 0; nextSample = 0; peakAfterWarmup = 0;

while S.t < simTime - 1e-9 && ~S.done
    S = exitArchStep(S);
    if S.t >= opt.warmup
        peakAfterWarmup = max(peakAfterWarmup, S.peakLoadNow);
    end
    if S.t >= nextSample - 1e-9 || S.done
        k = k + 1;
        N = size(S.pos,1);
        t(k) = S.t;
        inside(k) = N;
        exited(k) = numel(S.exitTimes);
        win = min(P.flowWindow, S.t);
        outflow(k) = sum(S.exitTimes > S.t - win)/max(win, eps);
        if N > 0
            spd = sqrt(sum(S.vel.^2, 2));
            stuckFrac(k) = mean(S.status == 3 | S.status == 4);
            meanSpeed(k) = mean(spd);
            peakLoad(k)  = S.peakLoadNow;
            crushed(k)   = sum(S.status == 4);
        else
            stuckFrac(k) = 0; meanSpeed(k) = 0; peakLoad(k) = 0; crushed(k) = 0;
        end
        nextSample = nextSample + opt.sampleEvery;
    end
end
k = min(k, nMax);
R.series = table(t(1:k), inside(1:k), exited(1:k), outflow(1:k), stuckFrac(1:k), ...
    meanSpeed(1:k), peakLoad(1:k), crushed(1:k), 'VariableNames', ...
    {'t','inside','exited','outflow','stuckFrac','meanSpeed','peakLoad','crushed'});

% --- summary over the measurement window [warmup, end] ---
tEnd = S.t;
ex = S.exitTimes(S.exitTimes >= opt.warmup);
R.summary.flow = numel(ex)/max(tEnd - opt.warmup, eps);
gaps = diff([opt.warmup; ex; tEnd]);
if isempty(ex) || S.done
    gaps = diff([opt.warmup; ex]);
end
if isempty(gaps), gaps = tEnd - opt.warmup; end
R.summary.longestStall  = max(gaps);
R.summary.peakLoad      = peakAfterWarmup;
R.summary.crushedAgents = S.nCrushedGone + sum(S.everCrushed);
R.summary.evacTime      = S.evacTime;
R.summary.exited        = numel(S.exitTimes);
R.final = S;
end
