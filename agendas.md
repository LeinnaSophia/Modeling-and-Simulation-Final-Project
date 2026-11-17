# Next Agendas

## 1. Stadium setting with physical barriers

Implement the grid-based model in a more realistic stadium setting by adding physical obstacles along the crowd's path, like a stage.

If we stay with the Cartesian approach, an obstacle just means there is a region of the space that is "outside" the movement space. For a rectangular stage, that region is the box between its corner points:

```
       p3 ________ p4
         |        |
         | STAGE  |
       p1 ________ p2
```

Points where `x1 < x < x2` and `y1 < y < y2` are excluded, and the agents are expected to avoid them. Two things make this happen:

- **A repulsive force** from the nearest point on the stage edge, using the same contact and personal-space force shapes as the person-to-person forces.
- **A hard push-out** as a safety net, so nobody ends up inside the stage after a strong shove.

The stage also changes how the crowd moves. The stage doesn't move, so a person pressed against it gets pushed back with no give, while the people behind keep pushing forward. That is where compression builds up, and we can read it off the overlap between bodies. (Between two agents i and j, the forces are equal and opposite, as in Newton's third law. That is not the same as being in equilibrium. A person is only in equilibrium when the *total* force on them is zero, and the stage and the crowd behind them break that.) Less free space also means more close overlaps are possible.

The overlap is a **crush proxy**, not a prediction of injuries or deaths. It tells us where crushing is more likely, not how bad it would be.

## 2. Exit width

Add a width to the exits, so an exit is a gap in a wall instead of a single point. Bottlenecks at the exits, and people being pressed along the walls nearby, may change how the crowd moves.

Note: right now the walls are a hard clamp, with no wall force. People pressed against a wall are stopped, but only the person-to-person overlap shows the squeeze. Adding a wall repulsion, like the stage force, would make the crush along the walls more realistic.

## 3. Same thresholds, with a panic range per scenario

We keep the same thresholds (time step, speeds, force reach, warm-up, stuck threshold).

What changes is the panic level. Instead of one value for everyone, each agent gets a **random panic level drawn from a range**, and each scenario has its own range. The scenarios are defined by density:

| Scenario | Density           | Panic range (example, to be justified) |
|----------|-------------------|----------------------------------------|
| Baseline | fewer than 4 / m² | 0.0 to 0.2                             |
| Active   | 4 / m²            | 0.3 to 0.6                             |
| Erratic  | 6 or more / m²    | 0.6 to 1.0                             |

Things to keep in mind:
- Panic stays between 0 and 1.
- The forces currently use the **mean** panic of the crowd, while the direction wobble uses each agent's **own** panic. That's fine to keep for simplicity.
- The current scenarios skip 5 people per m². Decide whether that gap matters.

## 4. Visualizations

- **Graphs** of the collected data over time: average speed, stuck fraction, polarization, and compression.
- **Heatmaps** for the crowd. Two different ones are useful:
  - *Density*: people per m² in each cell, to see where the crowd gathers.
  - *Crush risk*: overlap per cell, to see where bodies are squeezed.

## 5. Animation

An animated depiction of the crowd moving: draw the agents each step (for example, colored by speed or panic), with the stage and exits shown. It can be saved as a video or GIF.
