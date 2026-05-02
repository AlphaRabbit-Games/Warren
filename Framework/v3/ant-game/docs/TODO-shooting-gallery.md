# ShootingGallery Demo - Shelved

## Current State (2026-01-14)

The turret system works:
- Client input capture (WASD + Space)
- Cross-domain IPC (client → server signals)
- Physics-based HingeConstraint servos for yaw/pitch
- Projectile firing with hit detection

The target system is NOT working:
- 3 Dropper instances are created and configured
- Signal wiring is in place (Manager ↔ Droppers)
- Targets are not spawning when round starts

## What Needs To Be Done

1. **Create standalone demo first**: Build a simple Dropper → PathFollower → despawn circuit in isolation (like Conveyor_Demo pattern) to verify the signal flow works.

2. **Debug the signal chain**: The `startDroppers` signal should trigger `Dropper.In.onStart`, which should start the spawn loop, which should fire `Out.spawned`, which should trigger `Manager.In.onTargetSpawned`.

3. **Verify SpawnerCore**: Ensure templates are registered correctly and SpawnerCore can spawn them.

## Architecture Notes

The refactor moved from internal method calls to signal-driven:

**Before (WRONG):**
```lua
self:_startRow(row)
self:_spawnTargetForRow(row)
```

**After (CORRECT):**
```lua
self.Out:Fire("startDroppers", {})
-- Routed via wiring to:
dropper.In.onStart(dropper)
-- Dropper fires:
dropper.Out:Fire("spawned", data)
-- Routed via wiring to:
manager.In.onTargetSpawned(manager, data)
```

## Resume Point

When resuming work:
1. First build `TargetRow_Demo.lua` - simple standalone circuit
2. Once working, integrate back into ShootingGallery
3. The Dropper, PathFollower, and signal patterns are established in Conveyor_Demo - use that as reference
