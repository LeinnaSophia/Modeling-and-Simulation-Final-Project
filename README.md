# Crowd Escape Simulation (MATLAB)

A small simulation of people trying to get out of a crowded room through an exit.
This is ran three times across three different scenarios and compare how well people
get out, how fast they move, and how badly they get squished.

---

## The idea in one minute

- The room is a **10 m x 10 m square**.
- People ("agents") are scattered randomly across the room.
- Everyone wants to walk toward the **exit on the right wall** at about 1.3 m/s.
- While walking, people **push each other apart** (nobody can stand inside someone else).
- Panicked people **wander off course** and **push harder**.
- When someone reaches the exit, they are **removed** from the simulation.
- We run **300 steps of 0.05 s = 15 seconds** and record what happened.

Each agent is just three things:

| Property   | Stored in  | Meaning                              |
|------------|------------|--------------------------------------|
| position   | `pos`      | `(x, y)` in meters                   |
| velocity   | `vel`      | `(vx, vy)` in m/s                    |
| panic      | `panicArr` | 0 = calm ... 1 = maximum panic       |

---

## 1. The room and the grid

```
 y
10 +---+---+---+---+---+---+---+---+---+---+
   |   |   |   |   |   |   |   |   |   |   |  i = 10
 9 +---+---+---+---+---+---+---+---+---+---+
   |   |   |   |   |   |   |   |   |   |   |  i = 9
 8 +---+---+---+---+---+---+---+---+---+---+
   |   |   |   |   |   |   |   |   |   |   |  i = 8
 7 +---+---+---+---+---+---+---+---+---+---+
   |   |   |   |   |   |   |   |   |   |   |  i = 7
 6 +---+---+---+---+---+---+---+---+---+---+
   |   |   |   |   |   |   |   |   |   |   |  i = 6
 5 +---+---+---+---+---+---+---+---+---+---+ <== EXIT at (10, 5)
   |   |   |   |   |   |   |   |   |   |   |  i = 5
 4 +---+---+---+---+---+---+---+---+---+---+
   |   |   |   |   |   |   |   |   |   |   |  i = 4
 3 +---+---+---+---+---+---+---+---+---+---+
   |   |   |   |   |   |   |   |   |   |   |  i = 3
 2 +---+---+---+---+---+---+---+---+---+---+
   |   |   |   |   |   |   |   |   |   |   |  i = 2
 1 +---+---+---+---+---+---+---+---+---+---+
   |   |   |   |   |   |   |   |   |   |   |  i = 1
 0 +---+---+---+---+---+---+---+---+---+---+
   0   1   2   3   4   5   6   7   8   9  10   x
     j=1 j=2 j=3 j=4 j=5 j=6 j=7 j=8 j=9 j=10
```

```matlab
L = 10; W = 10;               % room is 10m x 10m
nx = 10; ny = 10;             % 10x10 grid
dx = L/nx; dy = W/ny;         % each cell is 1m x 1m
exitX = L; exitY = W/2;       % exit at right wall, middle
v0 = 1.3;                     % desired walking speed (m/s)
```

The grid is **only used to place people at the start**. It does not affect the movement.

**Watch out for the index convention, the i is the row and the j is the column. So, think (y,x):**
- `i` is the **row** and controls **y** (counts upward)
- `j` is the **column** and controls **x** (counts rightward)

So cell `(i, j)` covers `x` from `j-1` to `j`, and `y` from `i-1` to `i`:

```
          x = j-1        x = j
             |             |
  y = i  ----+-------------+----
             |             |
             |   cell      |
             |   (i, j)    |
             |             |
  y = i-1 ---+-------------+----
```

---

## 2. The three scenarios

Each scenario is a row of `[min people per cell, max people per cell, panic]`.

```matlab
panicLevels = [0.0, 0.5, 0.8];

scenarioSettings = [
    1  3  panicLevels(1);    % Baseline
    4  4  panicLevels(2);    % Active
    6 10  panicLevels(3);    % Erratic
];
```

| Scenario | People per cell | Approx. density | Panic | Feel                   |
|----------|-----------------|-----------------|-------|------------------------|
| Baseline | 1 to 3          | about 2 / m^2   | 0.0   | calm, sparse           |
| Active   | exactly 4       | 4 / m^2         | 0.5   | busy, a bit anxious    |
| Erratic  | 6 to 10         | about 8 / m^2   | 0.8   | packed, very panicked  |

Since each cell is 1 m^2, "people per cell" is the same as "people per m^2".

---

## 3. Placing the agents

For each of the 100 cells we pick a random head count `n`, then drop `n` people at
random spots inside that cell.

```matlab
for i = 1:nx
    for j = 1:ny
        n = randi([perCellMin, perCellMax]);   % how many people in this cell
        nPerCell(i,j) = n;

        cellX0 = (j-1)*dx;                     % cell's bottom-left corner
        cellY0 = (i-1)*dy;

        newPos = [cellX0 + rand(n,1)*dx,  cellY0 + rand(n,1)*dy];
        pos      = [pos;      newPos];
        vel      = [vel;      zeros(n,2)];
        panicArr = [panicArr; panicLevel*ones(n,1)];
    end
end
```

Picture one cell with `n = 3`. `rand(n,1)` gives 3 random numbers between 0 and 1 at (1,1) (the starting point or reference point is the origin (0,0)),
one per person, which we scale to the cell size and shift to the cell's corner:

```
  cellY0+1 +-----------------+
           |        o        |
           |   o             |
           |             o   |
  cellY0   +-----------------+
         cellX0           cellX0+1
```

After the loops, there is one row per person in each list:

```
  pos       N x 2    [ x  y ]      where everyone is
  vel       N x 2    [ vx vy ]     all zeros at the start (nobody is moving yet)
  panicArr  N x 1    [ p ]         same panic for everyone in a scenario
```

### Counting

```matlab
N  = size(pos,1);              % people currently in the room (shrinks as people leave)
N0 = N;                        % people at the start (frozen)
density0 = N0 / (L*W);         % starting people per m^2
```

We keep `N0` because `N` goes down as people escape, and we need the original
number later: `escaped fraction = (N0 - N) / N0`.

### Where we save results over time

```matlab
speedHist = zeros(nSteps,1);   % average speed at each step
compHist  = zeros(nSteps,1);   % body overlap at each step
polarHist = zeros(nSteps,1);   % direction alignment at each step
restrHist = zeros(nSteps,1);   % fraction nearly stuck at each step
```

Four empty columns of 300 slots. Slot `k` holds the value at time step `k`.

---

## 4. The main loop: what happens in ONE time step

```
  +---------------------------------------------------+
  |  1. Everyone picks a direction toward the exit    |
  |     (panicked people get a random wobble)         |
  +---------------------------------------------------+
                          |
                          v
  +---------------------------------------------------+
  |  2. Every close pair of people pushes each other  |
  |     apart  ->  a force on each person             |
  +---------------------------------------------------+
                          |
                          v
  +---------------------------------------------------+
  |  3. Update velocity (steer + forces), then move   |
  +---------------------------------------------------+
                          |
                          v
  +---------------------------------------------------+
  |  4. Keep people inside the walls                  |
  |     Remove anyone who reached the exit            |
  +---------------------------------------------------+
                          |
                          v
  +---------------------------------------------------+
  |  5. Measure the crowd (speed, stuck, aligned,     |
  |     squished) and store it in the history arrays  |
  +---------------------------------------------------+
                          |
                          v
                  repeat 300 times
```

If the room empties early, the loop stops and the remaining history slots are filled
with the last real value, so empty slots don't drag the averages down.

```matlab
if N == 0
    if k > 1
        speedHist(k:end) = speedHist(k-1);   % copy last real value forward
        ...
    end
    break;
end
```

### Step 1: aim at the exit

For each person we want a **direction arrow of length 1** pointing at the exit.

```
   exit (10, 5)
        *
       /|
      / |
     /  | toExitY = 3.86
    /   |
   /θ   |
  o-----+
  (0.31, 1.14)   toExitX = 9.69
```

```matlab
toExitX = exitX - pos(:,1);                    % horizontal distance to exit
toExitY = exitY - pos(:,2);                    % vertical distance to exit
lenExit = sqrt(toExitX.^2 + toExitY.^2) + 1e-9;   % straight-line distance
dirX = toExitX ./ lenExit;                     % divide by length -> arrow of length 1
dirY = toExitY ./ lenExit;
```

Worked example for the person at `(0.31, 1.14)`:

```
toExitX = 10 - 0.31 = 9.69
toExitY =  5 - 1.14 = 3.86
lenExit = sqrt(9.69^2 + 3.86^2) = 10.43

dirX = 9.69 / 10.43 = 0.929     (this is cos θ)
dirY = 3.86 / 10.43 = 0.370     (this is sin θ)
θ = atan(3.86 / 9.69) = 21.7 degrees
```

Dividing by the length is what "normalizes" the arrow: we only keep the *direction*,
and handle the *speed* separately later. (`+1e-9` just prevents dividing by zero.)

### Panic wobble

Calm people walk straight. Panicked people veer. We **rotate** each person's arrow
by a random angle:

```matlab
ang = panicArr .* pi .* randn(N,1);   % random angle, bigger when panic is bigger
```

- `randn` gives a random number from a bell curve (usually between -2 and +2).
- Panic 0.0 gives an angle of 0, so no wobble.
- Panic 0.8 gives a typical angle of about 0.8 x pi = 144 degrees. That is a *huge* swing.
- A new random angle is drawn **every time step**.

Rotating an arrow `(x, y)` by angle `a` uses the standard rotation formula. This is obtained by adding the original angle theta with the jitter angle. The rotation formula is derived from the angle addition identities:

```
x' = x*cos(a) - y*sin(a)
y' = x*sin(a) + y*cos(a)
```

```
              rotated arrow
                  ^
                 /
                /   a
               /  .--.
              /  /
             o------------> original arrow
```

Example: the arrow at 21.7 degrees rotated by 0.5 rad (28.65 degrees):

```
cos(0.5) = 0.8776    sin(0.5) = 0.4794

x' = 0.929*0.8776 - 0.370*0.4794 = 0.638
y' = 0.929*0.4794 + 0.370*0.8776 = 0.770
-> new angle = 21.7 + 28.65 = 50.4 degrees, length still 1
```

### Step 2: people push each other apart

First, some constants:

| Variable   | Value                    | Meaning                                            |
|------------|--------------------------|----------------------------------------------------|
| `r`        | 0.25 m                   | body radius (so a person is 0.5 m wide)            |
| `B`        | 0.3 m                    | how quickly the "personal space" push fades        |
| `A_social` | `2.0 * (1 + mean panic)` | strength of the personal-space push                |
| `k_body`   | `50 * (1 + 2*mean panic)`| stiffness when bodies actually overlap             |

Higher panic means everyone shoves harder. The shape of the force (exponential,
spring) comes from the well-known Helbing social-force model. The specific numbers
(2.0, 50, how panic scales them) are hand-picked modeling choices.

The code checks **every pair** of people once:

```matlab
for i = 1:N
    for j = i+1:N          % j starts after i, so each pair is visited once
```

For a pair `(i, j)`:

```
  i                        j
  o ---------------------> o
  (x_i, y_i)               (x_j, y_j)

  ddx = x_j - x_i
  ddy = y_j - y_i
  dist = sqrt(ddx^2 + ddy^2)
  u = (ddx, ddy) / dist        <- arrow of length 1 pointing from i to j
```

We skip pairs that are exactly on top of each other (`dist > 0`, to avoid dividing
by zero) or farther than 1 m apart (`dist < 1.0`, the push is tiny there anyway).

Then the **size** of the push depends on how close they are:

```
  Case A: bodies overlap (dist < 0.5)        Case B: close, not touching (0.5 <= dist < 1.0)

      (  o  )(  o  )                              (  o  )   (  o  )
        i  <->  j                                   i  <---->  j
        squished                                    personal space

  Hard spring:                                 Soft exponential push:
  mag = k_body * (0.5 - dist)                  mag = A_social * exp((0.5 - dist)/0.3)
```

```matlab
if dist < 2*r
    mag = k_body * (2*r - dist);            % body contact: linear spring
else
    mag = A_social * exp((2*r - dist)/B);   % personal space: exponential
end
```

Case A is like squeezing a spring: the more overlap, the harder it pushes back.
Case B fades quickly: the force drops to about 37% every additional 0.3 m.

Calm-crowd force for case B (`A_social = 2`):

```
  dist (m)   mag
  0.5        2.00   ########################
  0.6        1.43   #################
  0.7        1.03   ############
  0.8        0.74   #########
  1.0        0.38   ####
```

Finally, the two people are pushed in **opposite** directions (Newton's third law). To clear confusion, think i and j as two agents:

```matlab
Fx(i) = Fx(i) - mag*ux;   Fy(i) = Fy(i) - mag*uy;   % i is pushed AWAY from j
Fx(j) = Fx(j) + mag*ux;   Fy(j) = Fy(j) + mag*uy;   % j is pushed AWAY from i
```

Example: `i` at `(2, 3)`, `j` at `(2.4, 3)`, panic 0.5:

```
  i at x=2.0      j at x=2.4
     o <-0.4-> o
  dist = 0.4 (overlapping), u = (+1, 0)
  k_body = 50 * (1 + 2*0.5) = 100
  mag = 100 * (0.5 - 0.4) = 10

  Fx(i) -= 10   -> i pushed left
  Fx(j) += 10   -> j pushed right

     <- o       o ->
```

Reminder: in `Fx(j)`, the `j` is the *person's number*, not a y-coordinate.

### Step 3: update velocity and position

```matlab
tau = 0.5;
vDesiredX = dirX * v0;
vDesiredY = dirY * v0;
vel(:,1) = vel(:,1) + (vDesiredX - vel(:,1))/tau * dt + Fx * dt/80;
vel(:,2) = vel(:,2) + (vDesiredY - vel(:,2))/tau * dt + Fy * dt/80;
pos(:,1) = pos(:,1) + vel(:,1) * dt;
pos(:,2) = pos(:,2) + vel(:,2) * dt;
```

The velocity changes by two things:

```
new velocity = old velocity
             + (wanted velocity - old velocity) / tau * dt     <- "steer toward what I want"
             + force / 80 * dt                                 <- "get shoved by others"
```

- **Wanted velocity** = direction arrow x 1.3 m/s.
- **`tau = 0.5 s`** is the reaction time: people take about half a second to adjust
  their speed, so they don't change velocity instantly.
- **`80`** is the person's mass in kg, so `force / 80` is acceleration.
- Then position moves by `velocity x dt` (distance = speed x time, repeated each step).

### Step 4: walls and the exit

```matlab
pos(:,1) = min(max(pos(:,1), 0.1), L-0.1);
pos(:,2) = min(max(pos(:,2), 0.1), W-0.1);
```

Walls are a hard clamp: nobody can go closer than 0.1 m to any wall. There is no
bounce or force, they just stop.

```matlab
reached = pos(:,1) >= L - 0.2;
if any(reached)
    pos(reached, :)   = [];
    vel(reached, :)   = [];
    panicArr(reached) = [];
    N = size(pos, 1);
end
```

Anyone with `x >= 9.8` or is close to the exit is considered escaped and is deleted from all three lists. We can update this to be more realistic once we factor in exit width.

```
                      exit zone
                          |
   .   .   .   .   .  | x >= 9.8   -> removed
                      |
```


### Step 5: measuring the crowd

**Average speed**: how fast is the crowd moving? Low means congested.
```matlab
speeds = sqrt(vel(:,1).^2 + vel(:,2).^2);
speedHist(k) = mean(speeds);
```

**Restricted fraction**: what share of people are nearly stuck?
```matlab
restrHist(k) = mean(speeds < 0.2*v0);      % slower than 0.26 m/s
```

**Polarization**: is everyone moving the same way?
```matlab
ux = vel(:,1) ./ (speeds + 1e-9);
uy = vel(:,2) ./ (speeds + 1e-9);
polarHist(k) = sqrt(mean(ux)^2 + mean(uy)^2);
```
Turn each velocity into an arrow of length 1, average all the arrows, and take the
length of the result:
```
  everyone going the same way:       going in random directions:

   -> -> -> -> ->                     ->  <-  ^   v  <-
   average arrow = long (about 1)     arrows cancel out (about 0)
```

**Compression**: how squished are people? (the crush proxy)
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
For every pair of bodies that overlap, add up *how much* they overlap, then divide
by the number of people.

---

## 5. Final results

After 300 steps we summarize each scenario:

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

- **Warm-up:** the first 20 steps are skipped because everyone starts at rest and
  needs a moment to get going. Averaging from step 20 on gives a fairer picture.
- **`max(compHist)`** uses the *worst* moment, not the average, since a single crush
  moment is what matters for safety.

The final table prints one row per scenario:

| Column         | Meaning                                        |
|----------------|------------------------------------------------|
| `N0`           | starting number of people                      |
| `Density`      | starting people per m^2                        |
| `AvgSpeed`     | average crowd speed after warm-up              |
| `MaxComp`      | worst moment of body overlap (crush proxy)     |
| `Polarization` | how aligned the crowd's movement is (0 to 1)   |
| `Restricted%`  | share of people moving very slowly             |
| `Escaped%`     | share of the crowd that got out                |

What to expect: as the crowd gets denser and more panicked, speed should go down,
overlap and the stuck fraction should go up, alignment should drop, and fewer
people should escape within 15 seconds.

---

## Things to know before trusting the numbers

1. **Rotation bug** in the panic wobble (see above).
2. **The exit is the whole right wall** (see above).
3. **Panic never changes.** Each person keeps the same panic for the whole run.
4. **It's slow for big crowds.** The pair loops check every pair of people, so the
   work grows with the *square* of the head count. The Erratic scenario (hundreds
   of people, 300 steps) is much slower than Baseline.
5. **Fixed seed:** `rng(42)` makes runs repeatable. Change it (or remove it) to see
   how results vary between random starts.
6. **Hand-picked constants:** `A_social`, `k_body`, `tau`, mass `80`, and the panic
   scaling are modeling choices, not measured values.

---

## Math used 

| What                | Code                                  | In plain words                         |
|---------------------|---------------------------------------|----------------------------------------|
| Direction to exit   | `toExit / lenExit`                    | arrow of length 1 pointing at the exit |
| Panic wobble        | `panic * pi * randn`                  | random rotation angle                  |
| Rotation            | `x' = x cos a - y sin a`, `y' = x sin a + y cos a` | spin the arrow         |
| Body push           | `k_body * (2r - dist)`                | spring when overlapping                |
| Personal space push | `A_social * exp((2r - dist)/B)`       | fades fast with distance               |
| Newton's 3rd law    | `-mag*u` on i, `+mag*u` on j          | equal and opposite                     |
| Velocity update     | `v + (vWant - v)/tau*dt + F/m*dt`     | steer + get shoved                     |
| Position update     | `x + v*dt`                            | move a little each step                |
| Wall clamp          | `min(max(x, 0.1), L-0.1)`             | can't leave the room                   |
| Crowd speed         | `mean(sqrt(vx^2 + vy^2))`             | average speed                          |
| Restricted          | `mean(speed < 0.2*v0)`                | share nearly stuck                     |
| Polarization        | `length of mean(unit velocity)`       | alignment, 0 to 1                      |
| Compression         | `sum(2r - d) / N`                     | average body overlap                   |
| Escape fraction     | `(N0 - N) / N0`                       | share that got out                     |
