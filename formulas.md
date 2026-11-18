# Formulas Used in CrowdSimulation.m

This document lists every formula used in the simulation, what it does in plain English, and which paper it comes from.


## 1. Core Movement Equation (Helbing's Social Force Model)

**Source:** Helbing, Farkas & Vicsek, "Simulating dynamical features of escape panic," *Nature* 407, 2000.

The main equation that drives every agent:

```
acceleration = (desiredVelocity - currentVelocity) / relaxationTime + totalForce / mass
```

Each agent tries to reach their desired walking speed. How quickly they adjust depends on the relaxation time (tau). On top of that, forces from other agents and walls push them around.

**Code variable:** `accelerationX`, `accelerationY` (line ~495)


## 2. Social Repulsion Force (Agent-to-Agent)

**Source:** Helbing et al., *Nature* 407, 2000 (Equation 2, first term).

```
socialRepulsionForce = A * exp((contactDiameter - distance) / B)
```

Where:
- `A` = `socialRepulsionStrength` = 200 N (how strong the personal space push is)
- `B` = `socialRepulsionRange` = 0.3 m (how far personal space extends)
- `contactDiameter` = 2 * agentRadius = 0.5 m (distance at which two agents touch)
- `distance` = actual distance between two agents

Even before physically touching, people push away from each other. The closer someone gets, the stronger the push. This force drops off exponentially with distance.

**Note:** Original Helbing uses A=2000, B=0.08. We use scaled-down values because our time step (dt=0.05s) is much larger than what the originals assume (dt~0.001s).


## 3. Body Compression Force (Agent-to-Agent)

**Source:** Helbing et al., *Nature* 407, 2000 (Equation 2, second term).

```
bodyCompressionForce = k * max(0, contactDiameter - distance)
```

Where:
- `k` = `bodyCompressionStiffness` = 3000 kg/s^2
- `max(0, contactDiameter - distance)` = overlap (how much two bodies are squished into each other; zero if not touching)

When two agents physically overlap (bodies squished together), there is a spring-like push-back. The more you compress two bodies together, the harder they resist. This only activates when agents are actually touching.

**Note:** Original Helbing uses k=1.2e5, scaled down here for dt=0.05 stability.


## 4. Sliding Friction Force (Agent-to-Agent)

**Source:** Helbing et al., *Nature* 407, 2000 (Equation 2, third term).

```
frictionForce = kappa * overlap * tangentialVelocityDifference
```

Where:
- `kappa` = `slidingFrictionCoeff` = 1500 kg/(m*s)
- `overlap` = same as in body compression (how much agents are squished together)
- `tangentialVelocityDifference` = how fast one agent slides sideways relative to the other

When two people are pressed together and one tries to slide past the other, there is a friction drag. Think of trying to squeeze through a packed crowd — people's bodies resist your sideways movement. This force acts along the tangent direction (perpendicular to the line connecting the two agents).

**Note:** Original Helbing uses kappa=2.4e4, scaled down here for dt=0.05 stability.


## 5. Wall and Obstacle Forces

**Source:** Helbing et al., *Nature* 407, 2000 (Equation 3).

The same three forces (social repulsion, body compression, sliding friction) also apply between agents and walls/obstacles, but with one difference:

```
wallRepulsion = A * exp((agentRadius - wallDistance) / B)
wallCompression = k * max(0, agentRadius - wallDistance)
wallFriction = kappa * wallOverlap * agentTangentialSpeed
```

Walls push agents away just like other agents do, but the contact threshold is `agentRadius` (0.25 m) instead of `contactDiameter` (0.5 m) because the wall has no body of its own.

The nearest point on each wall segment is computed using a projection formula. The wall tangent direction is perpendicular to the wall normal.


## 6. Desired Speed (Density-Dependent)

**Source (density decay):** Weidmann, "Transporttechnik der Fussganger," 1993 (fundamental diagram).
**Source (panic interpolation):** Li et al., "Simulation of bi-directional pedestrian flow," *Sustainability* 10(2), 2018.

```
desiredSpeed = ((1 - panic) * baseSpeed + panic * maxPanicSpeed) * exp(-localDensity / densityForSpeedDrop)
```

Where:
- `panic` = agent's individual panic level (0.0 to 1.0)
- `baseSpeed` = agent's normal walking speed (random between 0.8 and 1.8 m/s)
- `maxPanicSpeed` = 2.0 m/s (fastest desired speed at full panic)
- `localDensity` = how many people per square meter in the agent's cell
- `densityForSpeedDrop` = 5.4 ped/m^2 (density at which speed drops to 37% of free speed)

Your desired speed has two parts.
1. **Panic interpolation:** calm agents walk at their normal speed, panicked agents want to go faster (up to 2.0 m/s). This is a linear blend based on panic level.
2. **Density reduction:** the more crowded it is around you, the slower you can actually move. At 5.4 people per square meter, your desired speed drops to about 37% of what you'd want. This comes from Weidmann's observed relationship between crowd density and walking speed.


## 7. Relaxation Time (Panic-Dependent)

**Source:** Liang et al., "Simulation for crowd crush in Seoul Halloween celebration," *PLOS ONE* 19(7), 2024.

```
relaxationTime = 0.5 * panic + 5.0 * (1 - panic)
```

Where:
- At panic = 0 (calm): tau = 5.0 seconds (slow adjustment, patient walking)
- At panic = 1 (full panic): tau = 0.5 seconds (snap to desired speed immediately)

Relaxation time controls how aggressively an agent accelerates toward their desired speed. Calm people gradually drift to their pace. Panicked people lunge toward the exit as fast as possible. This aggressive acceleration in panic is what causes the "faster is slower" effect — everyone lunging at the exit at once creates a jam that slows everyone down.


## 8. Direction Jitter (Panic-Induced)

**Source:** Helbing et al., *Nature* 407, 2000 (mentioned as noise term in nervous crowds).

```
jitterAngle = panic * pi * randn()
jitteredDirection = rotate(directionToExit, jitterAngle)
```

Panicked people don't walk straight toward the exit. They veer off randomly. The more panicked they are, the bigger the random deviation. At full panic, the random angle can swing up to ~180 degrees. This creates the chaotic movement patterns seen in real stampedes.

The rotation uses a 2D rotation matrix with temp variables to avoid a bug where overwriting the X component before computing Y would cause directional drift.


## 9. Crowd Pressure Metric

**Source:** Helbing, Johansson & Al-Abideen, "Dynamics of crowd disasters: an empirical study," *Physical Review E* 75, 2007.
**Applied in:** Liang et al., *PLOS ONE* 19(7), 2024 (Seoul Halloween crowd crush analysis).

```
crowdPressure = cellDensity * velocityVariance
```

Where:
- `cellDensity` = number of agents in the cell / cell area (ped/m^2)
- `velocityVariance` = mean of squared velocity deviations from cell mean

Crowd pressure measures how dangerous a spot is. It is high when there are both many people AND they are moving in different directions (pushing against each other). A dense crowd moving together (like a marching band) has low pressure. A dense crowd where everyone pushes in different directions (like near a bottleneck) has high pressure. The Seoul Halloween study used this metric to identify where the crush happened.


## 10. Velocity Entropy (Direction Chaos)

**Source:** Zhao et al., "Quantitative analysis of crowd panic based on direction entropy," *Physica A* 522, 2019.

```
directionEntropy = -sum(p_k * log2(p_k)) / log2(8)
```

Where:
- Divide the full 360 degrees into 8 bins of 45 degrees each
- `p_k` = fraction of moving agents in each bin
- Divided by `log2(8)` to normalize to the range [0, 1]

Entropy measures how chaotic the movement directions are within a cell.
- **Entropy = 0:** everyone is moving in exactly the same direction (orderly flow)
- **Entropy = 1:** agents are moving in all 8 directions equally (total chaos)

Values above 0.5 indicate significant disorder. This metric helps identify panic zones even before the density gets dangerously high.


## 11. Casualty Model (Compression Threshold + Tumble)

**Source (compression threshold):** Fruin, "The causes and prevention of crowd disasters," 1993.
**Source (tumble concept):** Yi et al., "Simulation of pedestrian evacuation considering the effect of fallen pedestrians," *Physica A* 541, 2020.

```
if bodyForceOnAgent > compressionForceToFall
    agent falls and becomes an immobile obstacle
```

Where:
- `compressionForceToFall` = 1500 N (the force threshold from Fruin 1993)
- `bodyForceOnAgent` = sum of all body compression forces from neighbors + walls

When the total squishing force on a person exceeds about 1500 Newtons (roughly 150 kg of pressure from all sides), they collapse. This is based on Fruin's research on human compression tolerance in crowd crushes.

Once fallen, the agent:
- **Stops moving** on their own (desired speed = 0)
- **Remains as a physical obstacle** that other agents must push around
- **Cannot escape** through exits
- **Still receives forces** (can be pushed slightly by the crowd)

This implements Yi et al.'s "tumble factor" concept: a fallen pedestrian becomes a secondary hazard. Other agents trip over or get stuck behind them, creating a chain reaction. In their model, the probability of falling increases sharply above 4 pedestrians per square meter. Our implementation uses a force threshold instead of a density probability, but achieves the same cascading effect.


## Formula summary

| Formula | What It Does | Source |
|---------|-------------|--------|
| Social Force Model (movement) | Main equation driving agents | Helbing et al. (Nature, 2000) |
| Social repulsion | Personal-space push before contact | Helbing et al. (Nature, 2000) |
| Body compression | Spring push when physically touching | Helbing et al. (Nature, 2000) |
| Sliding friction | Tangential drag between touching bodies | Helbing et al. (Nature, 2000) |
| Wall forces | Same 3 forces but agent-to-wall | Helbing et al. (Nature, 2000) |
| Desired speed (density) | Speed drops in dense crowds | Weidmann (1993), Li et al. (2018) |
| Relaxation time (panic) | Panic makes agents more aggressive | Liang et al. (PLOS ONE, 2024) |
| Direction jitter | Panicked agents veer randomly | Helbing et al. (Nature, 2000) |
| Crowd pressure | Density * velocity variance metric | Helbing et al. (PRE, 2007), Liang et al. (2024) |
| Velocity entropy | Direction chaos (8-bin Shannon entropy) | Zhao et al. (Physica A, 2019) |
| Casualty (compression) | Fall at >1500N body force | Fruin (1993) |
| Casualty (tumble effect) | Fallen agents block others | Yi et al. (Physica A, 2020) |


## References

1. Helbing, D., Farkas, I. & Vicsek, T. (2000). Simulating dynamical features of escape panic. *Nature*, 407, 487-490.
2. Helbing, D., Johansson, A. & Al-Abideen, H.Z. (2007). Dynamics of crowd disasters: An empirical study. *Physical Review E*, 75(4), 046109.
3. Weidmann, U. (1993). Transporttechnik der Fussganger. *Schriftenreihe des IVT*, ETH Zurich.
4. Li, Y., Chen, M., Dou, Z., Zheng, X., Cheng, Y. & Mebarki, A. (2018). A review of cellular automata models for crowd evacuation. *Sustainability*, 10(2), 385.
5. Liang, D. et al. (2024). Simulation for crowd crush in Seoul Halloween celebration: A modified social force model. *PLOS ONE*, 19(7), e0306764.
6. Zhao, R. et al. (2019). Quantitative analysis of the influence of irregular obstacles on crowd panic based on direction entropy. *Physica A*, 522, 169-181.
7. Yi, J., Chen, L., Liu, X. & Li, C. (2020). Simulation of pedestrian evacuation considering the effect of fallen pedestrians. *Physica A*, 541, 123368.
8. Fruin, J.J. (1993). The causes and prevention of crowd disasters. *Engineering for Crowd Safety*, Elsevier.
