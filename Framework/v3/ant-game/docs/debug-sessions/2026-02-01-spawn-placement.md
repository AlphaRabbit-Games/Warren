# Debug Session: Spawn Point Placement Issues

**Date:** 2026-02-01
**Status:** In Progress - pick up tomorrow

## Summary

Spawn point placement is unreliable. Sometimes spawns in floor holes, sometimes floating in mid-air, sometimes outside the room bounds entirely.

## What We Fixed

- **Ceiling hole trusses** now extend from lower room floor to upper room floor (not just to lower ceiling). This allows climbing all the way through vertical connections.

## Current Problems

### Spawn Point Placement

The spawn point placement logic has gone through several iterations, all broken:

1. **Original approach (door-based):** Built a set of rooms with floor holes by checking `door.axis == 2`. Failed intermittently (1 in 10 runs) - spawn placed in rooms with floor holes.

2. **Geometric check:** Tried detecting floor holes by checking if another room exists directly below. Wrong approach - vertical adjacency doesn't mean there's a door/hole.

3. **BFS + findSafeFloorPosition:** Combined room traversal with safe position finding. Still produced wrong positions.

4. **Raycast from room center:** Moved logic to instantiation, raycast down to find floor. Issues:
   - If planned X/Z is outside room bounds, ray hits nothing
   - Raycast filter logic may be wrong
   - Still producing floating spawn points or spawn points outside rooms

### Observed Symptoms

- Spawn point floating 9 studs above floor (grey square below ceiling hole)
- Spawn point outside room bounds (player spawns outside map)
- Spawn point not visible from inside room (placed just outside walls)

## Root Cause Analysis

Claude struggles with 3D spatial reasoning and coordinate transformations. Multiple "fixes" introduced new bugs rather than solving the core issue.

## Proposed Solution

**Use the same approach as teleport pads** - they always place correctly.

Pads work because:
1. `planPads()` uses `ctx:findSafeFloorPosition(roomId)`
2. `createPad()` just places at the planned position
3. Simple, one code path, tested

For spawn:
1. Remove all the complicated raycast/BFS logic from LayoutInstantiator
2. Plan spawn position same way as pads - `findSafeFloorPosition(roomId)` for room 1 (or first valid room)
3. Create SpawnLocation at that position during instantiation

Essentially: spawn is just a special pad.

## Files Modified

- `Framework/v2/src/Warren/Components/Layout/LayoutBuilder.lua`
  - `planTrusses()` - fixed ceiling truss height calculation
  - `planSpawn()` - multiple iterations, currently uses door-based + BFS

- `Framework/v2/src/Warren/Components/Layout/LayoutInstantiator.lua`
  - `createSpawn()` - currently has raycast logic that should be removed
  - `findSpawnPosition()` - added raycast-based room iteration, should be removed

## TODO for Next Session

1. Revert LayoutInstantiator spawn logic to simple placement
2. In LayoutBuilder, plan spawn like a pad:
   - Find room without vertical holes at center
   - Use `findSafeFloorPosition()` for that room
3. Test extensively with multiple seeds
4. Also fix "buggyness with jump points" (user mentioned)

## Notes

- Truss placement is working but is placeholder - will eventually be ramps, elevators, etc.
- The teleport pad system works reliably and should be the model for spawn placement
