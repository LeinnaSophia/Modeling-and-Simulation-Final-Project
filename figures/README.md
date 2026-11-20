# Crowd Escape Simulation: Figure Guide

This guide explains the figures produced by `Visualizations.m`. Run `Visualizations` at the MATLAB prompt and the PNGs are written to `figures/`. All runs use `rng(42)`, so results are reproducible.

| File | Model | Content |
|---|---|---|
| `simple_timeseries.png` | Simple (FinalDraft) | 4 metrics over time |
| `simple_heatmaps.png` | Simple (FinalDraft) | Density and crush-risk heatmaps |
| `advanced_timeseries_LevelC.png` | Advanced (CrowdSimulation) | 6 metrics over time (panic level C) |
| `advanced_heatmaps_LevelC.png` | Advanced (CrowdSimulation) | Density and crush-risk heatmaps (panic level C) |

## Setup

Both models simulate a 10 m x 10 m room divided into a 10 x 10 grid of 1 m² cells, for 300 steps of 0.05 s (15 s total).

**Simple model.** One exit on the right wall. Each scenario varies crowd size and panic:

| Scenario | People per cell | Panic |
|---|---|---|
| Baseline | 1–3 | 0.0 |
| Active | 4 | 0.5 |
| Erratic | 6–10 | 0.8 |

**Advanced model.** Two 3 m exits (left and right walls, centered at y = 5 m) and a central "STAGE" obstacle. Agents have individual speeds and panic values, slow down in dense areas, and fall when compression force exceeds a threshold. The figures show panic level C (panic 0.8–1.0).

| Scenario | People per cell |
|---|---|
| Baseline | 1–3 |
| Dense | 4 |
| Densest | 5–10 |

## Metric glossary

| Metric | Meaning |
|---|---|
| Average speed | Mean speed of everyone still in the room (m/s) |
| Stuck fraction | Share of people moving slower than 20% of the free-walking speed |
| Polarization | How aligned everyone's movement direction is (1 = all the same way, 0 = random) |
| Compression / overlap | Body overlap between people. Simple model: average per person. Advanced model: total across the crowd |
| Crowd pressure | Highest value across cells of (local density x velocity variance) |
| Direction entropy | Highest value across cells of the disorder in movement directions (0 = ordered, 1 = fully random) |
| Evacuated | Cumulative number of people who have left through an exit |
| Casualties | Cumulative number of people who fell due to compression |
| Density heatmap | Mean people per m² in each cell, averaged over all time steps |
| Crush-risk heatmap | Body overlap accumulated in each cell, summed over all time steps |

---

## Simple model

### `simple_timeseries.png`

![Simple model metrics over time](figures/simple_timeseries.png)

- **Baseline** (blue) walks almost freely. Speed reaches about 1.28 m/s within 2 s and stays there, polarization climbs to about 0.95 (everyone heads to the exit), and the room is empty at about 8.5 s. The drop to zero after that is just "nobody left", not a real speed of 0. The compression spike just before it comes from the last few people bunching up at the exit.
- **Active** (orange) is held to about 0.4 m/s. About 20–30% of people are nearly stuck, polarization slowly decays from about 0.7 to 0.5, and compression rises steadily. Nobody finishes within 15 s.
- **Erratic** (green) is the worst case. Polarization stays around 0.1–0.2 (movement is close to random), about 35% of people are nearly stuck, and compression grows to nearly 1 m per person, meaning heavy overlap.

### `simple_heatmaps.png`

![Simple model heatmaps](figures/simple_heatmaps.png)

Top row is density, bottom row is crush risk. Color scales are shared across the three scenarios in each row.

- **Baseline:** low density everywhere, with a small hotspot at the exit (right wall, y = 4–6 m) and almost no crush risk.
- **Active:** people pile up along the top and bottom walls, mostly toward the right half, with moderate crush risk there.
- **Erratic:** dense bands run along the entire top and bottom walls (up to about 22 people/m²) and carry the highest crush risk by a wide margin.

---

## Advanced model (panic level C)

### `advanced_timeseries_LevelC.png`

![Advanced model metrics over time](figures/advanced_timeseries_LevelC.png)

- **Baseline** (blue) has a low, steady speed (about 0.25–0.3 m/s), almost no overlap or pressure, no casualties, and about 77 people evacuated by 15 s.
- **Dense** (orange) moves fastest early on (about 0.8 m/s at 2 s), has the highest pressure peak (about 20 at around 1.5 s), then slows and relaxes as the crowd thins. Overlap fades to about 0, there are no casualties, and about 220 people are evacuated, the most of any scenario.
- **Densest** (green) is a locked jam. Speed is about 0.05 m/s, total overlap stays at about 185 m, and pressure sits at about 10–15. Roughly 535 people fall almost immediately, rising to about 615, and nobody escapes.
- **Direction entropy** is jumpy and takes only a few discrete values, because it is the maximum over cells with few moving people each. Treat it as a rough indicator.

### `advanced_heatmaps_LevelC.png`

![Advanced model heatmaps](figures/advanced_heatmaps_LevelC.png)

Green bars mark the exits and the box marks the stage. Both are empty by construction.

- **Baseline** and **Dense:** density is low and fairly even (about 1–2 and 3–4 people/m²), and crush risk is close to zero.
- **Densest:** density is high everywhere (about 7–9 people/m²) and crush risk is high across the whole room, because the crowd never thins out. The cells next to the stage are the only low spots.

---

## Reading the figures

- **Crush risk is cumulative.** It is a sum over time, not an average, so it depends on how long the crowd stays packed. Scales are shared across scenarios within a figure, but not between figures: the simple model peaks around 17,000 and the advanced model around 1,600, so don't compare numbers across the two models.
- **Density is a time average.** It is diluted as people leave, so a room that empties quickly shows lower density.
- **Evacuated and casualties are counts, not percentages.** Scenarios start with different crowd sizes, so compare with that in mind.
- **Erratic speed and polarization end at about 5.3 s** in `simple_timeseries.png`, while its other metrics continue. This probably means those two values became NaN (numerical instability) after that point. Check this before drawing conclusions about Erratic late in the run.
