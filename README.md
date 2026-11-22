# Exit Arch — Crowd Evacuation Simulation (MATLAB)

A crowd-evacuation simulation based on the **Social Force Model** (Helbing, Farkas & Vicsek, *Nature* 407, 2000). Agents in a concert venue push toward an exit while social repulsion, body compression, and sliding friction govern how they interact. The simulation measures evacuation time, crush injuries, and crowd flow across different density and panic scenarios.

---

## How to run

| Command | What it does |
|---------|-------------|
| `exitArchApp` | Launch the interactive GUI |
| `Visualizations` | Run all 9 scenario combos headlessly and produce figures |
| `exitArchSweep` | Sweep desired speed v0 to demonstrate the "faster is slower" effect |

---

## The room

```
  y
 12 +------------------------------------------------------+
    |  STAGE  |                                        | EXIT
    |  (left  |     walkable area        obstacle      | door
    |  wall)  |                          [-----]       | (right
    |         |                                        | wall)
  0 +------------------------------------------------------+
    0         ~3.5                                     22    x
```

- **22 × 12 m** (264 m² total, ~220 m² walkable after stage and obstacle)
- **Stage** on the far left (~16% of room length, spanning middle 50% of height)
- **Central obstacle** (toggleable, centered at ~44% of length)
- **Exit** on the right wall (1.20 m door width by default)
- Four layout options: **Single Door**, **Pillar**, **Twin Doors**, **Funnel**

---

## Physics

Each agent obeys:

```
m dv/dt = m(v0·e - v)/tau          driving force (want to reach exit)
        + social repulsion          A·exp((r_ij - d_ij)/B)·n_ij
        + body compression          k·g(r_ij - d_ij)·n_ij
        + sliding friction          kappa·g(r_ij - d_ij)·(dv·t_ij)·t_ij
        + same terms for walls, door jambs, pillars
```

| Constant | Value | Meaning |
|----------|-------|---------|
| `A` | 2,000 N | Social repulsion strength |
| `B` | 0.08 m | Social repulsion range |
| `k` | 60,000 kg/s² | Body compression stiffness (Helbing/2, scaled for concert scenario) |
| `kappa` | 120,000 kg/(m·s) | Sliding friction |
| `mass` | 80 kg | Agent mass |
| `dt` | 0.005 s | Integration time step |
| `maxForce` | 50,000 N | Safety-net force cap per agent |
| `crushLoad` | 2,500 N | Force threshold for crush injury |

**Emergent slowdown**: Agents always push with their full desired speed v0. Slowdown in dense areas is not imposed — it emerges naturally from body compression and friction forces resisting motion, as in Helbing's original model.

**Direction**: BFS distance field from the exit, with panic-scaled random jitter.

**Per-agent properties**: desired speed v0 (random in range), panic level (random in range), relaxation time tau (derived from panic: `tau = 0.5·panic + 5.0·(1-panic)`).

---

## Scenarios

### Density scenarios (how many agents)

| Scenario | Agents | Walkable density | Character |
|----------|--------|-----------------|-----------|
| Baseline | 250 | ~1.1 ped/m² | Room to move, flow visible |
| Dense | 500 | ~2.3 ped/m² | Crowded, occasional crush at bottlenecks |
| Crush Risk | 800 | ~3.6 ped/m² | Dangerous, crush events at exit |

### Panic levels (how hard agents push)

| Level | Panic range | tau range | Character |
|-------|-------------|-----------|-----------|
| Level A | 0.00–0.49 | 2.6–5.0 s | Calm, orderly |
| Level B | 0.50–0.79 | 1.1–2.5 s | Anxious, pushing |
| Level C | 0.80–1.00 | 0.5–1.0 s | Full panic, shoving |

Density and panic are independent — any combination is valid (9 total).

---

## Agent placement

Agents are placed randomly (not grid-based) using `exitArchPlace.m`: each agent gets a random walkable position with overlap checking (minimum 0.02 m clearance). A 1.5 m clear zone in front of the door ensures agents must flow toward the exit. A settling phase (30 steps of repulsion forces) resolves any remaining overlaps before the simulation starts.

---

## Measurements

| Metric | How it's measured |
|--------|-------------------|
| **Evacuated** | Agents past the door channel |
| **Peak load** | All-time maximum body-compression force on any agent |
| **Crushed** | Agent whose body-compression force exceeds 2,500 N (crushLoad) |
| **Mean speed** | Average velocity magnitude of agents still in the room |
| **Outflow** | Exits per second over a sliding 5 s window |

---

## Files

| File | Purpose |
|------|---------|
| `exitArchApp.m` | Interactive GUI (play/pause, parameter controls, real-time rendering) |
| `exitArchInit.m` | Room geometry, agent placement, settling |
| `exitArchStep.m` | One physics time step (forces, integration, exit detection) |
| `exitArchParams.m` | All default parameters |
| `exitArchPlace.m` | Random walkable placement with overlap checking |
| `exitArchRun.m` | Headless runner, returns time-series and summary |
| `exitArchSweep.m` | "Faster is slower" parameter sweep |
| `Visualizations.m` | Batch analysis: time-series, heatmaps, summary bars for all 9 combos |

---

## Key references

- Helbing, Farkas & Vicsek, "Simulating dynamical features of escape panic", *Nature* 407 (2000)
