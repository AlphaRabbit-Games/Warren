> **Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC**
>
> This software, its architecture, and associated documentation are proprietary
> and confidential. All rights reserved.
>
> Unauthorized copying, modification, distribution, or use of this software,
> in whole or in part, is strictly prohibited without prior written permission.

---

# Turret System - Implementation Plan

> Status: APPROVED FOR IMPLEMENTATION
> Created: 2026-01-14

## Overview

A composable multi-component system for turrets, searchlights, and similar aiming/firing mechanisms. Uses physics-based projectiles rather than code-controlled movement.

**Design Principles:**
- Each component does one thing well
- Direction comes from geometry (surface orientation), not configuration
- Physics handles projectile flight after launch
- Components wire together via Orchestrator

---

## Architecture

```
Turret (Orchestrator wiring)
├── Swivel (yaw)
│   └── Swivel (pitch)
│       ├── Targeter (raycast scanner)
│       └── Launcher (muzzle)
```

The Targeter and Launcher mount to the same surface (inner swivel), so they share orientation. The controller orchestrates: Targeter acquires → Controller processes → Swivels aim → Launcher fires.

---

## Component 1: Swivel

Single-axis rotation control. Like a servo motor.

### Modes

| Mode | Behavior | Use Case |
|------|----------|----------|
| **continuous** | Rotates while signal active, stops on `onStop` | Smooth tracking, introduces play |
| **stepped** | Fixed increment per `onRotate` signal | Precise positioning |

### Attributes

| Attribute | Type | Default | Description |
|-----------|------|---------|-------------|
| Axis | string | "Y" | Rotation axis: "X", "Y", or "Z" |
| Mode | string | "continuous" | "continuous" or "stepped" |
| Speed | number | 90 | Degrees per second (continuous mode) |
| StepSize | number | 5 | Degrees per pulse (stepped mode) |
| MinAngle | number | -180 | Lower rotation limit |
| MaxAngle | number | 180 | Upper rotation limit |

### Signals

```
IN (receives):
    onRotate({ direction: "forward" | "reverse" })
        - Continuous: starts rotating until onStop
        - Stepped: rotates one StepSize increment

    onSetAngle({ degrees: number })
        - Direct positioning (both modes)
        - Clamps to MinAngle/MaxAngle

    onStop({})
        - Stops continuous rotation
        - No effect in stepped mode

OUT (emits):
    rotated({ angle: number })
        - Current angle after movement

    limitReached({ limit: "min" | "max" })
        - Hit rotation boundary
```

### Implementation Notes

- Uses `CFrame` rotation on Heartbeat (continuous) or immediate (stepped)
- Rotates the attached Part/Model around its pivot
- Child objects rotate with parent (standard Roblox hierarchy)

---

## Component 2: Targeter

Raycast-based target detection. Mounts to a surface, casts in LookVector direction.

### Beam Modes

| Mode | Behavior | Use Case |
|------|----------|----------|
| **pinpoint** | Single ray from surface center | Precise targeting |
| **cylinder** | Parallel rays in radius | Wide beam detection |
| **cone** | Rays spread outward from origin | Expanding search pattern |

### Scan Modes

| Mode | Behavior | Use Case |
|------|----------|----------|
| **continuous** | Scans every Heartbeat | Real-time tracking |
| **interval** | Scans every N seconds | Performance optimization |
| **pulse** | Scans only on `onScan` signal | Manual control |

### Tracking Modes

| Mode | Behavior | Use Case |
|------|----------|----------|
| **once** | Emits `acquired` when targets found, nothing while maintained | Fire-and-forget detection |
| **lock** | Emits `tracking` continuously while targets in beam | Target lock behavior |

### Attributes

| Attribute | Type | Default | Description |
|-----------|------|---------|-------------|
| BeamMode | string | "pinpoint" | "pinpoint", "cylinder", "cone" |
| BeamRadius | number | 1 | Radius in studs (cylinder/cone) |
| Range | number | 100 | Max raycast distance |
| ScanMode | string | "continuous" | "continuous", "interval", "pulse" |
| Interval | number | 0.5 | Seconds between scans (interval mode) |
| TrackingMode | string | "once" | "once" or "lock" |
| Filter | table | {} | Standard filter schema |

### Signals

```
IN (receives):
    onEnable({})
        - Start scanning (continuous/interval modes)

    onDisable({})
        - Stop scanning

    onScan({})
        - Manual scan trigger (pulse mode)

    onConfigure({ filter?, range?, beamMode?, ... })
        - Update configuration

OUT (emits):
    acquired({ targets: Array<{ target: Instance, position: Vector3, normal: Vector3, distance: number }> })
        - Targets detected, sorted by distance (closest first)
        - In "once" mode: fires when targets first detected
        - In "lock" mode: fires on first detection

    tracking({ targets: Array<...> })
        - Continuous signal while targets in beam (lock mode only)
        - Same payload format as acquired

    lost({})
        - Had targets, now none (lock mode only)
```

### Implementation Notes

- Uses `workspace:Raycast()` with RaycastParams
- Cylinder: cast N rays in circle pattern around center
- Cone: cast N rays spreading outward from origin point
- Filter uses `Node.Registry.matches()` for standard filter schema
- All targets returned in single signal, sorted by proximity

---

## Component 3: Launcher

Physics-based projectile firing from a muzzle surface.

### Launch Methods

| Method | Behavior | Use Case |
|--------|----------|----------|
| **impulse** | VectorForce pulse | Quick, simple launch |
| **spring** | SpringConstraint release | More physical feel |

### Attributes

| Attribute | Type | Default | Description |
|-----------|------|---------|-------------|
| ProjectileTemplate | string | nil | Template name for SpawnerCore |
| LaunchForce | number | 100 | Impulse/spring strength |
| LaunchMethod | string | "impulse" | "impulse" or "spring" |
| Cooldown | number | 0.5 | Min seconds between shots |

### Signals

```
IN (receives):
    onFire({ targetPosition?: Vector3 })
        - With targetPosition: calculate direction to coordinates (Mode A)
        - Without: fire in muzzle LookVector direction (Mode B / blind fire)

    onConfigure({ launchForce?, cooldown?, projectileTemplate?, ... })
        - Update configuration

OUT (emits):
    fired({ projectile: Instance, direction: Vector3 })
        - Projectile spawned and launched

Err (detour):
    onCooldown({ remaining: number })
        - Fire attempted before cooldown expired
```

### Implementation Notes

- Uses SpawnerCore to clone projectile template
- Spawns at muzzle surface position
- Sets `Anchored = false`, `CanCollide = true`
- Calculates direction: `(targetPosition - muzzlePosition).Unit` or `muzzle.CFrame.LookVector`
- Applies physics:
  - Impulse: `AssemblyLinearVelocity = direction * LaunchForce`
  - Spring: Create SpringConstraint, set properties, release
- Projectile is now physics-driven (Roblox handles flight)

---

## Wiring Example

```lua
local orch = Orchestrator:new({ id = "BasicTurret" })
orch.In.onConfigure(orch, {
    nodes = {
        YawSwivel = { class = "Swivel", config = { Axis = "Y", Mode = "continuous" } },
        PitchSwivel = { class = "Swivel", config = { Axis = "X", Mode = "continuous" } },
        Scanner = { class = "Targeter", config = { TrackingMode = "lock", Range = 150 } },
        Gun = { class = "Launcher", config = { ProjectileTemplate = "Bullet", Cooldown = 0.2 } },
    },

    wiring = {
        -- Targeter acquires → external controller handles aiming logic
        { from = "Scanner", signal = "acquired", to = "TurretController", handler = "onTargetAcquired" },
        { from = "Scanner", signal = "tracking", to = "TurretController", handler = "onTargetTracking" },
        { from = "Scanner", signal = "lost", to = "TurretController", handler = "onTargetLost" },

        -- Controller drives swivels
        { from = "TurretController", signal = "aim", to = "YawSwivel", handler = "onSetAngle" },
        { from = "TurretController", signal = "aim", to = "PitchSwivel", handler = "onSetAngle" },

        -- Controller triggers fire
        { from = "TurretController", signal = "fire", to = "Gun", handler = "onFire" },
    },
})
```

---

## Searchlight Example (Non-Firing Use)

```lua
-- Targeter without Launcher - just detection
local orch = Orchestrator:new({ id = "Searchlight" })
orch.In.onConfigure(orch, {
    nodes = {
        YawSwivel = { class = "Swivel", config = { Axis = "Y", Mode = "continuous", Speed = 30 } },
        Detector = { class = "Targeter", config = {
            BeamMode = "cone",
            BeamRadius = 5,
            TrackingMode = "once",
            Filter = { tag = "Player" },
        }},
    },

    wiring = {
        { from = "Detector", signal = "acquired", to = "AlarmSystem", handler = "onIntruderDetected" },
    },
})

-- Swivel continuously rotates for sweep pattern
yawSwivel.In.onRotate(yawSwivel, { direction = "forward" })
```

---

## Implementation Order

| # | Component | Priority | Notes |
|---|-----------|----------|-------|
| 1 | **Swivel** | First | Foundation - other components mount to it |
| 2 | **Targeter** | Second | Detection logic, filter integration |
| 3 | **Launcher** | Third | Depends on SpawnerCore for templates |

---

## Open Questions (Deferred)

1. **Projectile impact detection** - Will be handled by projectile, target, or collision manager. TBD.
2. **TurretController** - May be Orchestrator wiring or a dedicated node for complex aim logic.
3. **Visual beam** - Targeter could optionally render the raycast beam for debugging/effects.

---

## Files to Create

| File | Purpose |
|------|---------|
| `Components/Swivel.lua` | Swivel component |
| `Components/Targeter.lua` | Targeter component |
| `Components/Launcher.lua` | Launcher component |
| `Tests/Swivel_Tests.lua` | Swivel tests |
| `Tests/Targeter_Tests.lua` | Targeter tests |
| `Tests/Launcher_Tests.lua` | Launcher tests |
| `Components/init.lua` | Update exports |
| `Tests/init.lua` | Update exports |
