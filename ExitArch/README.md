# Exit Arch (MATLAB)

A MATLAB version of the "Exit Arch" crowd simulation from [Simulate It Now](https://simulateitnow.com/sim/exitArch).
A crowd presses through a door. When people push harder, their bodies lock into arches across
the opening and the measured outflow drops even though everyone is trying to go faster.
This is the "faster is slower" effect.

The code is our own implementation of the social-force model in
Helbing, Farkas & Vicsek, *Simulating dynamical features of escape panic*, Nature 407 (2000).

![app](results/exitArchApp.png)

## Files

| File | What it does |
|------|--------------|
| `exitArchApp.m`    | Interactive window: play/pause, layouts, sliders, overlays, live readouts |
| `exitArchParams.m` | All parameters and their defaults |
| `exitArchInit.m`   | Builds the room for the chosen layout and places the crowd |
| `exitArchStep.m`   | One time step of the physics, exits, loads and status |
| `exitArchRun.m`    | Headless run that returns metrics over time and a summary |
| `exitArchSweep.m`  | Sweeps the desired speed v0 and saves `results/exitArchSweep.{csv,png}` |
| `exitArchPlace.m`  | Finds an overlap-free spot for a new person |

## How to run

```matlab
cd ExitArch
exitArchApp              % interactive simulation
exitArchSweep            % faster-is-slower sweep (about 5 minutes)

% one headless run
P = exitArchParams('layout', 'Pillar', 'v0', 3, 'seed', 1);
R = exitArchRun(P, 40, 'warmup', 10);
R.summary                % flow, longestStall, peakLoad, crushedAgents, ...
plot(R.series.t, R.series.outflow)
```

## Controls

Same tabs as the original:

- **Setup**
  - **Layout:** Single Door, Pillar (a column in front of the door), Twin Doors, or Funnel.
  - **Scenario:** Steady Stream or Evacuation. In Steady Stream, people who leave are put back
    in at the far wall, so the crowd size stays constant and the flow can be measured.
    Evacuation empties the room once and reports the evacuation time.
  - **Door Width** and **Pillar Distance** (door to pillar centre).
- **Crowd:** Desired Speed v0, Crowd size, Body Friction κ, Relaxation τ.
- **View:** Time Scale, Overlay (Force Chains or None), Density (None or Heatmap).

Changing the room or the crowd size restarts the run. v0, κ, τ and the View options apply live.

People are coloured **Walking** (at least half of v0), **Slowed**, **Stuck** (below 10% of v0)
or **Crushed** (see the crush-load bullet below).

The cards under the room show these readouts:
- **Outflow:** people out per second over the last 5 s.
- **Longest stall:** the longest gap between two exits, which is how long an arch held the door shut.
- **Peak load:** the highest crush load on any one person, in kN/m.

## The model

Each person is a disc with radius 0.25 to 0.35 m and mass 80 kg:

```
m dv_i/dt = m (v0 e_i - v_i) / tau                               (wants to walk to the door)
          + sum_j [ A exp((r_ij - d_ij)/B) + k g(r_ij - d_ij) ] n_ij   (keeps distance, body compression)
          + sum_j kappa g(r_ij - d_ij) (dv_ji . t_ij) t_ij            (sliding friction between bodies)
          + the same terms for walls, door jambs and the pillar
```

- `g(x) = max(x, 0)`, so the compression and friction terms only act when bodies touch.
- A = 2000 N, B = 0.08 m, k = 1.2e5 kg/s², κ = 2.4e5 kg/(m s), τ = 0.5 s. These are the values
  from Helbing et al.
- `e_i` points at the closest point of the nearest door that the body fits through. People
  whose straight path is blocked by the pillar aim to pass beside it.
- Time step is 0.005 s with semi-implicit Euler. The friction coefficient is capped so the
  explicit step stays stable.
- **Crush load** is the body-compression force on a person (the `k g` terms only) divided by
  their circumference. Above 1600 N/m we mark them Crushed, the threshold Helbing et al. used
  for injuries. Like the overlap in `FinalDraft.m`, this is a crush-risk proxy, not an injury
  prediction.

Arches form because friction (κ) lets bodies lean on each other across the door opening.
A higher v0 presses them harder into that arch.

## Results

`exitArchSweep` runs Steady Stream with 200 people and a 1.2 m door: 40 s per run, the first 10 s
ignored, 3 seeds per point.

![sweep](results/exitArchSweep.png)

- **Single door.** Outflow peaks at about 2.7 people/s around v0 = 1.2 m/s. It falls to about
  1.5 people/s by v0 = 3.6 to 4.4 m/s: pushing harder gets fewer people out. Over the same range
  the longest stall grows from about 1 s to about 3 s, and the peak crush load rises from about
  2 kN/m to over 15 kN/m.
- **Pillar 1.3 m in front of the door.** It lowers the peak crush load at high v0, but in this
  setup it also lowers the outflow. How much a pillar helps depends on its distance and size,
  which is worth sweeping with the Pillar Distance parameter.

The raw numbers are in `results/exitArchSweep.csv`.

## Differences from the website

- 2D top-down view instead of the 3D render.
- The website's sliders use their own scales (for example κ = 0.50). Here every slider is in
  the model's physical units (κ in 10^5 kg/(m s), default 2.4).
- Everything (parameters, geometry, metrics) is open, so it can be used for the report.
