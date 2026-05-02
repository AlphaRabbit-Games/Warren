# Procedural Dungeon / Rescue Metroidvania – Design Recap

## Core Insight

What began as a **Dracula / vampire castle dungeon** evolved into the realization that multiple ideas (Dracula dungeon, Martian prison escape, Lemmings-style rescue) all share **the same core gameplay loop**.
The theme is interchangeable; the **systems are the game**.

This unlocks:

* Procedural replayability
* Strong player agency
* A scalable, reskinnable framework

---

## High-Level Game Concept

A **procedural, infinite (or very large) dungeon** built from modular rooms, streamed at runtime. The dungeon is an **obstacle course with booby traps** - a deadly maze that must be navigated and prepared.

Two potential modes:

### Mode A: Rescue Mission
The player's goal is **rescuing fragile NPCs** who cannot navigate hazards on their own. Success is measured by **how many NPCs you save**, not whether you save everyone.

### Mode B: Solo Survival / Speedrun
The player navigates the dungeon themselves, avoiding/disabling traps, finding the exit. Success is measured by **floors cleared** or **time to completion**.

Both modes use the same procedural dungeon system - only the win condition differs.

---

## Core Gameplay Loop (Stripped of Theme)

### The Setup
1. The dungeon is generated from a **seeded layout**
2. **Fragile NPCs** (Martians / prisoners / villagers) are trapped in cells **scattered throughout the maze**
3. These NPCs are helpless:
   * Cannot jump
   * Cannot avoid traps
   * Cannot navigate obstacles
   * **If they know a path**, they follow it toward the exit
   * **If they don't know where to go**, they wander aimlessly and die

### Player Actions (Any Order, But Consequences)

The player can do these in any order:

* **Explore** - scout the maze, find cells, find the exit, identify hazards
* **Define paths** - place beacons/waypoints so NPCs know where to go
* **Disable defenses** - take out guards, turrets, traps
* **Build infrastructure** - bridges, jam doors, seal shafts
* **Free NPCs** - open cells, NPCs start moving
* **Defend** - protect NPCs in real-time during their escape

**But order matters through consequences:**
* Free NPCs before defining a path? They wander and die.
* Free NPCs before clearing hazards? They walk into traps and die.
* Define a path but miss a hazard? They die when they reach it.
* Do everything right? They escape.

The game doesn't enforce phases - the **systems teach you** through failure.

### The Recovery Loop
* **More NPCs exist than required**: e.g., 20 available, only 10 needed to pass
* If some die:
  * Adapt your strategy
  * Find other cells
  * Prepare different routes
  * Try again with remaining NPCs
* Success = saved enough NPCs to pass the level
* Next level = deeper dungeon, harder layout

### Why This Works
* **Exploration first** - player must scout, learn the layout, find the exit
* **Preparation matters** - define paths, pre-disable what you can
* **Active execution** - constant defense/escort during the escape
* **Recoverable failure** - some deaths aren't game over, adapt and try with remaining NPCs
* **Replayable** - procedural layouts mean fresh problems every run

The player is **explorer, engineer, and defender** all in one run.

---

## Why This Works Especially Well with Procedural Generation

Traditional proc-gen struggles with:

* Hand-authored puzzles
* Narrative pacing

This design **embraces uncertainty**:

* There is no single correct solution
* Success is probabilistic and strategic
* Layout randomness becomes part of the challenge

The dungeon does not need perfect puzzle design — it needs **fair systems**.

---

## Dungeon Generation Architecture

### Phase 1: Generate the Spine (3-Axis Path)

Start by procedurally generating a **segmented 3-axis path (XYZ)**:

1. Generate the **main path** as connected segments in X, Y, Z
2. Vary **segment count** and **switchbacks** to control difficulty
3. Y-axis changes create vertical transitions (stairs, shafts, drops)
4. The spine is abstract - no geometry yet, just direction and length

**Difficulty scaling:**
* More segments = longer path
* More switchbacks = more disorienting
* More vertical changes = harder navigation
* Tighter segments = more cramped spaces

### Phase 2: Branch False Paths

After the spine exists:

1. Define **dead end paths** branching off core segments
2. Define **loop paths** that reconnect to the spine elsewhere
3. False paths increase maze complexity without extending true length
4. Loops create navigation choices and backtracking opportunities

### Phase 3: Assign Rooms and Halls

Map abstract path segments to concrete spaces:

1. Define **halls and rooms** for the main path segments
2. Do the same for false paths (dead ends, loops)
3. **Adjust segment lengths** as needed to fit room/hall template sizes
4. Select room templates based on:
   * Segment direction (horizontal vs vertical)
   * Connection count (dead end vs throughway vs junction)
   * Difficulty zone (early = simpler, late = complex)

### Phase 4: Room Composition (Templates)

Rooms are **standardized templates** with:

* Fixed dimensions (small, medium, large, etc.)
* Pre-marked **entry/attachment points (sockets)**
* Socket compatibility rules (which sockets connect to which)
* Rotation support (0°, 90°, 180°, 270°)

The system builds maps by:

1. Selecting appropriate templates for each graph node
2. Rotating templates to align sockets
3. Composing/stitching at attachment points
4. Validating no overlaps or impossible connections

**No freeform geometry.** Everything is composed from prefab templates.

---

## Streaming / Infinite Dungeon Strategy

### Seed-Based Layout

* The **entire dungeon topology is generated upfront** from a seed
* The seed determines:
  * Spine path shape
  * Branch locations
  * Room template selections
  * Hazard placements
* Same seed = identical dungeon every time

### Progressive Geometry Building

* **Start**: Build only the first room + immediately adjoining rooms
* **As player travels**: Generate rooms they're approaching
* **Behind player**: Despawn distant rooms (unless they have persistent state)
* Geometry is built **room by room, on demand**

### What Gets Stored

* Seed (regenerates topology)
* Player position
* Persistent state (opened doors, disabled traps, dead NPCs)
* Explored room flags (for minimap)

### Benefits

* Infinite or arbitrarily large dungeons
* Stable memory/performance regardless of total size
* Deterministic - can share seeds for competitive runs
* Fast initial load (only first room)

---

## NPC (Martian / Prisoner) Design Contract

NPCs are intentionally limited:

* Follow beacons / defined paths only
* No obstacle avoidance
* No jumping
* No rerouting
* Panic or wander if path breaks

**Critical rule:**

> The player can never directly escort or micromanage NPCs.

The challenge is **environmental engineering**, not babysitting AI.

---

## Path Definition System

The player defines a **safe traversal path** using tools such as:

* Beacons
* Light trails
* Energy rails
* Sound emitters
* Painted routes
* Ropes or cables

Rules:

* Path must be continuous
* Path must be hazard-free
* Path must connect cell → exit

NPCs will blindly trust it.

---

## Environmental Preparation Tools

Before releasing NPCs, the player can:

* Disable turrets
* Jam doors open
* Build bridges
* Raise platforms
* Fill pits
* Seal vertical shafts
* Slow crushers
* Redirect patrols

Once NPCs are released, the player is mostly a spectator — success or failure is already decided.

---

## Difficulty Scaling

Difficulty increases by:

* Longer main paths
* More branches and false routes
* Higher trap density
* More vertical hazards
* Increased "trap budget" per room

Not just maze complexity — **execution pressure**.

---

## Save Condition Philosophy

* You are never required to save everyone
* Loss is expected and recoverable
* Players adapt rather than restart
* Encourages exploration, scouting, and risk management

This avoids soft-locks and frustration while preserving stakes.

---

## Theme as a Skin (Major Insight)

The same systems support many themes:

| Theme   | NPC       | Hazards          |
| ------- | --------- | ---------------- |
| Dracula | Villagers | Traps, monsters  |
| Prison  | Inmates   | Guards, turrets  |
| Martian | Colonists | Alien tech       |
| Sewer   | Workers   | Floods, grinders |
| Factory | Robots    | Crushers, lasers |

Only **presentation changes** — topology and logic remain identical.

---

## Why This Is a Strong "Killer Loop"

* Procedural but readable
* Skill-based, not memorization
* High tension without twitch combat
* Emergent stories ("I almost saved them…")
* Perfect for replay, streaming, and iteration

You are not a hero — you are a **systems engineer under pressure**.

---

## Current State of the Idea

* Dungeon layout system is already being prototyped via SVG → geometry
* Procedural generation concept is coherent and feasible
* Core loop is unified across multiple past ideas
* Clear next steps exist (AI behavior, beacon system, hazard contracts)

---

## Case Study: Castle Dracula (Hand-Authored)

Built 5 floors (L0-L4) manually to validate the geometry system:

### What Worked
* Declarative layout tables: `{id, position, size, class}`
* `geometry = "negate"` for CSG door holes (auto-AABB detection)
* xref composition for modular floor stacking
* Vertical tower stacks continuing through multiple floors
* SVG map → layout table conversion workflow

### What Needs Work
* Door/corridor alignment edge cases causing geometry bugs
* Wall-to-wall mating at room boundaries
* Corridor width vs door opening size coordination
* Some CSG operations failing silently

### Learnings for Procedural System
* Room templates need well-defined socket positions
* Corridors should be part of the room template, not separate
* Door openings should be auto-calculated from socket definitions
* Standard room sizes reduce edge case complexity
* The bugs found are valuable - they define what the procedural system must handle automatically

---

## Potential Next Steps

* Condense into a **one-page design pitch**
* Convert to a **technical spec**
* Formalize as a **procedural generation library** reusable across games

This is a *real* game idea, not just a thought experiment.
