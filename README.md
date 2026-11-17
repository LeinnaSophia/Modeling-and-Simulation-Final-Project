

## What the code means

The simulation models **people (agents) trying to escape a 10m × 10m room** through an exit on the right wall. It runs **three scenarios** (calm, active, panicked) and measures how the crowd behaves.

Each agent has:
- A **position** `(x, y)`
- A **velocity** `(vx, vy)`
- A **panic level** (0 = calm, 1 = max panic)

The loop does 300 time steps of 0.05 seconds each (15 seconds total). Every step, agents move toward the exit, push away from each other, and get removed if they escape.

---

## Section 1: Setup — room, grid, exit

*Sets the room dimensions, grid size, exit location, and desired walking speed.*

```matlab
L = 10; W = 10;               % room is 10m x 10m
nx = 10; ny = 10;             % 10x10 grid
dx = L/nx; dy = W/ny;         % each cell is 1m x 1m
exitX = L; exitY = W/2;       % exit at right wall, middle
v0 = 1.3;                     % desired walking speed (m/s)
```

**What this means:**

- The room is 10×10 metres, split into 10×10 = **100 cells**, each **1m × 1m**.
- `dx = 1`, `dy = 1` — each cell is 1 metre wide and tall.
- The exit is at `(10, 5)` — the middle of the right wall.
- `v0 = 1.3 m/s` — everyone *wants* to walk at this speed.

**Grid convention (important):**
- `i` = row number (counts **up**, drives **y**)
- `j` = column number (counts **right**, drives **x**)

So cell `(i, j)` covers `x ∈ [(j-1), j]` and `y ∈ [(i-1), i]`.

---

## Section 2: Scenarios

*Defines three test cases with different crowd densities and panic levels.*

```matlab
panicLevels = [0.0, 0.5, 0.8];

scenarioSettings = [
    1  3  panicLevels(1);    % Baseline: <4 ppl/m^2, calm
    4  4  panicLevels(2);    % Active:   =4 ppl/m^2, active
    6 10  panicLevels(3);    % Erratic:  6+ ppl/m^2, erratic
];
```

Each row is `[min agents per cell, max agents per cell, panic level]`:

| Scenario | Agents per cell | Panic | Meaning |
|---|---|---|---|
| Baseline | 1 to 3 | 0.0 | calm, sparse |
| Active | exactly 4 | 0.5 | dense, moderately panicked |
| Erratic | 6 to 10 | 0.8 | very dense, highly panicked |

The `randi([min, max])` in the placement loop uses these to decide how many agents go in each cell.

---

## Section 3: Placing agents

*Scatters agents randomly inside each of the 100 grid cells, building the initial position, velocity, and panic lists.*

```matlab
for i = 1:nx
    for j = 1:ny
        n = randi([perCellMin, perCellMax]);
        nPerCell(i,j) = n;

        cellX0 = (j-1)*dx;
        cellY0 = (i-1)*dy;

        newPos = [cellX0 + rand(n,1)*dx,  cellY0 + rand(n,1)*dy];
        pos      = [pos;      newPos];
        vel      = [vel;      zeros(n,2)];
        panicArr = [panicArr; panicLevel*ones(n,1)];
    end
end
```

**What happens, cell by cell (100 cells):**

1. **Pick `n`** — a random number of agents for this cell.
2. **Find the cell's corner**: `cellX0 = (j-1)*dx`, `cellY0 = (i-1)*dy`.
3. **Place `n` agents inside the cell**:
   - `rand(n,1)` returns **n random numbers** (one per agent).
   - `cellX0 + rand(n,1)*dx` = a random x inside the cell.
   - `cellY0 + rand(n,1)*dy` = a random y inside the cell.
   - `newPos` is an **n × 2** matrix — one row per agent.
4. **Append to the lists**:
   - `pos = [pos; newPos]` → add the n new positions.
   - `vel = [vel; zeros(n,2)]` → n new agents with **zero velocity**.
   - `panicArr = [panicArr; panicLevel*ones(n,1)]` → n new agents with the scenario's panic.

**Key idea:** `rand(n,1)` is a **column of n numbers**, so each agent gets its own random position. No inner loop needed.

**After all 100 cells**, the three lists all have **N rows** (one per agent):
- `pos` → N × 2 (positions)
- `vel` → N × 2 (velocities, all zero)
- `panicArr` → N × 1 (panic levels, all equal)

---

## Section 4: Counts and density

*Locks in the total agent count, a frozen starting count, and the starting density.*

```matlab
N  = size(pos,1);              % total agents
N0 = N;                        % frozen starting count
density0 = N0 / (L*W);         % starting density
```

- **`N`** = number of rows in `pos` = total agents.
- **`N0`** = a **copy** of `N`, taken **before anyone escapes**. `N` shrinks later, but `N0` stays fixed.
- **`density0`** = `N0 / 100 m²` = starting agents per square metre.

**Why keep `N0`:** to compute the escaped fraction later: `(N0 - N) / N0`.

---

## Section 5: History arrays

*Pre-allocates one storage slot per time step for each of the four metrics.*

```matlab
speedHist = zeros(nSteps,1);
compHist  = zeros(nSteps,1);
polarHist = zeros(nSteps,1);
restrHist = zeros(nSteps,1);
```

Four **300 × 1** columns. Each slot `k` will hold one metric at time step `k`:

- `speedHist(k)` = average crowd speed
- `compHist(k)` = average body overlap
- `polarHist(k)` = direction alignment
- `restrHist(k)` = fraction nearly stuck

---

## Section 6: The simulation loop — one step at a time

*Begins the 300-step time loop; each iteration advances the crowd by 0.05 s.*

```matlab
for k = 1:nSteps
```

`k` = time step number (1 → 300). Each iteration is `dt = 0.05 s`.

### Guard: everyone escaped

*If no agents remain, fills the remaining history slots with the last real value and stops the loop early.*

```matlab
if N == 0
    if k > 1
        speedHist(k:end) = speedHist(k-1);
        ...
    end
    break;
end
```

If no agents remain, fill the remaining history slots with the **last real value** (so averages aren't dragged down by zeros), then **stop the loop**.

`if k > 1` is a safety check: on step 1, there's no `k-1` to copy from.

---

## Section 7: Aim at the exit (with panic jitter)

*Computes each agent's unit direction toward the exit, then rotates it by a random panic angle so panicked agents veer off-course.*

```matlab
toExitX = exitX - pos(:,1);
toExitY = exitY - pos(:,2);
lenExit = sqrt(toExitX.^2 + toExitY.^2) + 1e-9;
dirX = toExitX ./ lenExit;
dirY = toExitY ./ lenExit;
```

**What this computes:** a **unit vector** from each agent to the exit.

1. **`toExitX, toExitY`** — the displacement from each agent to the exit. For an agent at `(0.31, 1.14)`: `toExitX = 10 - 0.31 = 9.69`, `toExitY = 5 - 1.14 = 3.86`.
2. **`lenExit`** — straight-line distance (Pythagoras): `√(9.69² + 3.86²) = 10.43`. The `+1e-9` avoids divide-by-zero.
3. **`dirX, dirY`** — the displacement divided by its length = **unit direction**.

For the example: `dirX = 9.69 / 10.43 = 0.9290`, `dirY = 3.86 / 10.43 = 0.3701`.

This is **SOHCAHTOA**:
- `dirX = adjacent/hypotenuse = cos θ`
- `dirY = opposite/hypotenuse = sin θ`

The angle to the exit is `θ = arctan(3.86/9.69) = 21.72°`.

**Length check:** `0.9290² + 0.3701² = 1.000` ✅

### Panic jitter

*Rotates each agent's heading by a random angle proportional to panic, so panicked agents wander instead of walking straight.*

```matlab
ang = panicArr .* pi .* randn(N,1);   % random rotation angle per agent
ca  = cos(ang);
sa  = sin(ang);
dirX = ca.*dirX - sa.*dirY;
dirY = sa.*dirX + ca.*dirY;
```

**Why:** panicked people don't walk straight — they veer. This **rotates** each agent's heading by a random angle.

- **`randn(N,1)`** — a random number from a bell curve (most values between −2 and +2), one per agent.
- **`ang`** — the rotation angle: `panic × π × randn`. Panic 0 → no rotation; panic 0.8 → large random angles (up to ~±144°).
- **`ca, sa`** — cosine and sine of the rotation angle.

**The rotation formula** (from the angle-addition identities):

$$
x' = x\cos\alpha - y\sin\alpha
$$
$$
y' = y\cos\alpha + x\sin\alpha
$$

which is exactly:

```matlab
dirX = ca.*dirX - sa.*dirY;
dirY = sa.*dirX + ca.*dirY;
```

**Example:** agent at 21.72°, rotation `ang = 0.5 rad (28.65°)`, `ca = 0.8776`, `sa = 0.4794`:

- Intended new direction: `dirX = 0.6379`, `dirY = 0.7702` → angle **50.37°** (21.72 + 28.65) ✅
- Length still 1 ✅

**Note (bug):** the code overwrites `dirX` before using it in the `dirY` line, so `dirY` uses the **new** `dirX`, not the old one. The intended result is `(0.6379, 0.7702)` at 50.37°, but the actual output is `(0.6379, 0.6306)` at 44.68°, length 0.897. To fix it, save `oldDirX = dirX` before overwriting.

---

## Section 8: Repulsion forces between agents

*Computes pairwise pushing forces between nearby agents — a linear spring when bodies overlap, an exponential personal-space force when close but not touching.*

```matlab
Fx = zeros(N,1);
Fy = zeros(N,1);
A_social = 2.0 * (1 + mean(panicArr));
B        = 0.3;
k_body   = 50  * (1 + 2*mean(panicArr));
r        = 0.25;
```

**Constants:**

| Variable | Value | Meaning |
|---|---|---|
| `r` | 0.25 m | body radius → `2r = 0.5 m` personal diameter |
| `A_social` | 2.0 × (1 + mean panic) | strength of personal-space repulsion |
| `B` | 0.3 m | how fast the social force decays with distance |
| `k_body` | 50 × (1 + 2·mean panic) | stiffness of body-contact pushing |

**Panic makes both forces stronger:** `A_social` scales by `(1 + mean panic)`, `k_body` by `(1 + 2·mean panic)`.

**Note:** `A_social = 2.0` and `k_body = 50` are **hand-picked** values (the exponential form is from Helbing's social-force model; the panic scaling is a modeling choice).

### The pair loop

*Visits every unordered pair of agents exactly once.*

```matlab
for i = 1:N
    for j = i+1:N
```

Each **unordered pair** of agents is visited **once**. `j = i+1` avoids double-counting and skips self-pairs.

### Geometry

*Computes the vector and distance between the two agents in the pair.*

```matlab
ddx  = pos(j,1) - pos(i,1);
ddy  = pos(j,2) - pos(i,2);
dist = sqrt(ddx^2 + ddy^2);
```

- `ddx, ddy` = vector **from i to j**.
- `dist` = distance between them.

### The cutoff

*Skips pairs that are too close (divide-by-zero risk) or too far (negligible force).*

```matlab
if dist > 0 && dist < 1.0
```

- `dist > 0` → skip coincident agents (avoids divide-by-zero).
- `dist < 1.0` → beyond 1 m, the force is negligible; skip for speed.

### Direction

*Normalizes the pair vector to a unit vector pointing from i to j.*

```matlab
ux = ddx / dist;
uy = ddy / dist;
```

Unit vector from i to j (length 1).

### The two force regimes

*Chooses a linear spring for body contact, or an exponential personal-space force for close-but-not-touching agents.*

```matlab
if dist < 2*r
    mag = k_body * (2*r - dist);            % body contact
else
    mag = A_social * exp((2*r - dist)/B);   % social repulsion
end
```

**Case 1: `dist < 0.5`** (bodies overlap) — **linear spring**:

$$
\text{mag} = k_\text{body} \cdot (0.5 - \text{dist})
$$

The more they overlap, the harder they push apart. `k_body = 50` is large because contact forces are strong.

**Case 2: `0.5 ≤ dist < 1.0`** (close but not touching) — **exponential personal space**:

$$
\text{mag} = A_\text{social} \cdot e^{(0.5 - \text{dist})/0.3}
$$

`exp` is \(e^x\). When `dist` is small, the exponent is positive → large force. When `dist` is large, the exponent is negative → small force. `B = 0.3` sets the decay rate: every 0.3 m, the force drops by a factor of \(e \approx 2.72\).

**Force vs distance** (with `A_social = 2`):

| `dist` | `mag` |
|---|---|
| 0.5 | 2.00 |
| 0.6 | 1.43 |
| 0.7 | 1.03 |
| 0.8 | 0.74 |
| 1.0 | 0.38 |

### Applying the force (Newton's third law)

*Pushes the two agents apart with equal and opposite force.*

```matlab
Fx(i) = Fx(i) - mag*ux;   Fy(i) = Fy(i) - mag*uy;
Fx(j) = Fx(j) + mag*ux;   Fy(j) = Fy(j) + mag*uy;
```

`(ux, uy)` points **from i to j**. So:

- **Agent i** is pushed **opposite** to `(ux, uy)` → away from j (minus sign).
- **Agent j** is pushed **along** `(ux, uy)` → away from i (plus sign).

Equal and opposite → momentum balanced.

**Example:** i at `(2, 3)`, j at `(2.4, 3)`. `ddx = +0.4`, `ddy = 0`, `dist = 0.4`, `ux = +1`, `uy = 0`.

With panic 0.5 (`k_body = 100`): `mag = 100 × (0.5 - 0.4) = 10`.

- `Fx(i) -= 10×1` → i pushed left
- `Fx(j) += 10×1` → j pushed right

**Note:** `j` here is the **agent number**, not the y-direction. `Fx(j)` = "x-force on agent j."

---

## Section 9: Velocity and position update

*Relaxes each agent's velocity toward its desired velocity, adds force-driven acceleration, then moves the agent by velocity × dt.*

```matlab
tau = 0.5;
vDesiredX = dirX * v0;
vDesiredY = dirY * v0;
vel(:,1) = vel(:,1) + (vDesiredX - vel(:,1))/tau * dt + Fx * dt/80;
vel(:,2) = vel(:,2) + (vDesiredY - vel(:,2))/tau * dt + Fy * dt/80;
pos(:,1) = pos(:,1) + vel(:,1) * dt;
pos(:,2) = pos(:,2) + vel(:,2) * dt;
```

**Velocity update** — two terms:

$$
v_\text{new} = v_\text{old} + \underbrace{\frac{v_\text{desired} - v_\text{old}}{\tau}\,dt}_\text{relax to desired} + \underbrace{\frac{F}{80}\,dt}_\text{force acceleration}
$$

1. **`vDesired = dir × v0`** — the velocity the agent *wants* (1.3 m/s in its heading direction).
2. **`(vDesired - vel)/tau`** — pulls velocity toward desired over `tau = 0.5 s`. Humans take ~0.5 s to adjust speed.
3. **`Fx * dt/80`** — force divided by effective mass `80` = acceleration, times `dt` = velocity change.

**Position update** — basic kinematics:

$$
x_\text{new} = x_\text{old} + v_x \cdot dt
$$

Each step (0.05 s), move by `velocity × time`.

---

## Section 10: Walls and exit

*Keeps agents inside the room, then removes any agent that has reached the exit.*

```matlab
pos(:,1) = min(max(pos(:,1), 0.1), L-0.1);
pos(:,2) = min(max(pos(:,2), 0.1), W-0.1);
```

**Wall clamp:** `max(x, 0.1)` prevents going below 0.1; `min(..., L-0.1)` prevents going above 9.9. Agents can't walk through walls — hard clamp, no force.

```matlab
reached = pos(:,1) >= L - 0.2;
if any(reached)
    pos(reached, :)   = [];
    vel(reached, :)   = [];
    panicArr(reached) = [];
    N = size(pos, 1);
end
```

**Exit removal:** any agent with `x ≥ 9.8` has escaped. Delete its row from all three lists, update `N`.

**Why `L - 0.2`:** a small buffer so agents are clearly past the exit.

---

## Section 11: Metrics (per step)

*Measures crowd speed, fraction stuck, direction alignment, and body compression for this time step.*

### Speed

*Average of every agent's velocity magnitude.*

```matlab
speeds = sqrt(vel(:,1).^2 + vel(:,2).^2);
speedHist(k) = mean(speeds);
```

Each agent's speed = `√(vx² + vy²)`. Average across all agents = **crowd speed**. Low = congested; high = flowing.

### Restricted fraction

*Fraction of agents moving slower than 20% of desired speed.*

```matlab
restrHist(k) = mean(speeds < 0.2*v0);
```

`0.2 × 1.3 = 0.26 m/s`. Fraction of agents moving slower than 0.26 m/s = **how much of the crowd is nearly stuck**. High = jammed.

### Polarization

*Length of the average unit direction — 1 means aligned, 0 means chaotic.*

```matlab
ux = vel(:,1) ./ (speeds + 1e-9);
uy = vel(:,2) ./ (speeds + 1e-9);
polarHist(k) = sqrt(mean(ux)^2 + mean(uy)^2);
```

Normalize each velocity to a **unit direction** (`ux, uy`), then average. The **length** of the average direction:

- ≈ 1 → everyone moving the same way (aligned)
- ≈ 0 → random directions (chaotic)

This is the standard **polarization order parameter** from flocking physics.

### Compression

*Average body overlap per agent — the crush proxy.*

```matlab
overlap = 0;
for i = 1:N
    for j = i+1:N
        dd = sqrt((pos(i,1)-pos(j,1))^2 + (pos(i,2)-pos(j,2))^2);
        if dd < 2*r
            overlap = overlap + (2*r - dd);
        end
    end
end
compHist(k) = overlap / max(N, 1);
```

For every pair closer than `0.5 m`, add `(0.5 - dd)` = **how much they overlap**. Sum = total body squish. Divide by `N` = **average overlap per agent**.

**This is the crush proxy:** high overlap = bodies compressed = crush risk.

---

## Section 12: Final summary

*After 300 steps, stores the headline numbers for this scenario — skipping the first 20 warm-up steps for cleaner averages.*

```matlab
warmup = min(20, nSteps);
escapedFrac = (N0 - N) / N0;

resultsTable(s,:) = [N0, ...
                     mean(speedHist(warmup:end)), ...
                     max(compHist), ...
                     mean(polarHist(warmup:end)), ...
                     mean(restrHist(warmup:end)), ...
                     density0, ...
                     escapedFrac];
```

- **`warmup = 20`** — skip the first 20 steps (transient: agents just placed, velocities settling). Average over steps 21–300 for a clean **steady-state** value.
- **`escapedFrac`** — fraction of the initial crowd that escaped.
- **`max(compHist)`** — peak compression (worst crush moment matters more than average).
- `resultsTable` stores 7 numbers per scenario: `[N0, avgSpeed, maxComp, avgPolar, restrictedFrac, density, escapedFrac]`.

---

## Section 13: Final comparison table

*Prints one row per scenario so you can compare calm, active, and panicked crowds side by side.*

```matlab
for s = 1:3
    r = resultsTable(s,:);
    fprintf('%-12s %6d %8.2f %10.3f %10.3f %12.3f %12.1f %10.1f\n', ...
        scenarioNames{s}, r(1), r(6), r(2), r(3), r(4), 100*r(5), 100*r(7));
end
```

Prints a table comparing all three scenarios:

| Column | Meaning |
|---|---|
| `N0` | starting agent count |
| `Density` | starting agents per m² |
| `AvgSpeed` | average crowd speed (steady state) |
| `MaxComp` | peak compression (crush proxy) |
| `Polarization` | direction alignment (0–1) |
| `Restricted%` | fraction nearly stuck (×100) |
| `Escaped%` | fraction that escaped (×100) |

---

## The big picture

**Physics:** each step, agents
1. Aim at the exit (unit direction) + panic jitter (rotation)
2. Push away from nearby agents (linear spring if overlapping, exponential if close)
3. Relax velocity toward desired + force acceleration
4. Move by `velocity × dt`
5. Clamp to walls
6. Get removed if they reach the exit

**Metrics** measure three failure modes:
- **Speed / restricted** → is the crowd moving? (flow)
- **Polarization** → is the crowd coordinated? (behavior)
- **Compression** → are people squished? (crush)

**Outcome:** `escapedFrac` = did they get out?

---

## Quick reference: all formulas

| Formula | Code | Meaning |
|---|---|---|
| Unit direction | `toExit / lenExit` | SOHCAHTOA: cos θ, sin θ |
| Panic jitter | `panic × π × randn` | random rotation angle |
| Rotation | `x' = cx − sy`, `y' = sx + cy` | angle-addition identities |
| Body force | `k_body × (2r − dist)` | linear spring when overlapping |
| Social force | `A_social × exp((2r − dist)/B)` | exponential personal space |
| Third law | `∓ mag × u` for i, j | equal and opposite |
| Velocity | `v + (vDes − v)/τ·dt + F/m·dt` | relax + force |
| Position | `x + v·dt` | Euler integration |
| Wall clamp | `min(max(x, 0.1), L−0.1)` | hard boundary |
| Speed | `mean(√(vx² + vy²))` | avg crowd speed |
| Restricted | `mean(v < 0.2·v0)` | fraction nearly stuck |
| Polarization | `‖mean(v̂)‖` | direction alignment |
| Compression | `Σ(2r − d)/N` | avg body overlap = crush proxy |
| Escape fraction | `(N0 − N)/N0` | outcome |
