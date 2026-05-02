# Room Node CSG Shell Refactor Plan

**Date:** 2026-02-01
**Status:** Implemented

## Problem with Current Approach

The current Room node builder:
1. Takes a room volume
2. Shrinks it by `wallThickness` on each side
3. Builds 6 wall slabs around the shrunken interior
4. Result: 7 parts per room (6 slabs + zone)

**Issues:**
- **Math bug:** Shrinking reduces interior space incorrectly. A 20x20 designed room becomes 18x18 inside. The room volume should define interior space, walls should go *outside*.
- **Part count:** 7 parts per room × 30 rooms = 210 parts
- **Doorway complexity:** Must find and cut 2+ wall slabs per doorway

## New CSG Shell Approach

### Concept
Instead of building 6 separate wall slabs, create a hollow shell using CSG subtraction:

```
Inner volume: original room dims (this IS the interior)
Outer volume: inner + (wallThickness * 2) on each axis
Shell = Outer:SubtractAsync({Inner})
```

### Part Count
- **New:** 2 parts per room (shell + zone)
- 30 rooms: 60 parts (vs 210)

### Why This Works
1. Box-minus-box is the simplest CSG operation
2. Subtraction happens at generation time, not runtime
3. Resulting PartOperation is static - no ongoing CSG cost
4. Doorway cutting becomes simpler (cut 1 shell vs 2+ slabs)
5. CollisionFidelity on simple hollow boxes is efficient

## Interior Surface Mounting

**Challenge:** After CSG subtract, inner surfaces exist visually but aren't addressable Part faces. Room nodes need to mount lights, decorations, furniture to walls.

**Solution:** Use the inner volume (zone Part) as mounting reference.

The inner volume's surfaces ARE the interior walls:
```
+Z face = North wall interior
-Z face = South wall interior
+X face = East wall interior
-X face = West wall interior
+Y face = Ceiling interior
-Y face = Floor interior
```

### Mounting Example
```lua
local zone = room:getZonePart()
local size = zone.Size
local cf = zone.CFrame

-- Mount torch on North wall interior
local northWallCF = cf * CFrame.new(0, 0, size.Z/2)  -- +Z face
local torchCF = northWallCF * CFrame.new(0, 2, -0.5)  -- offset inward + up
torch.CFrame = torchCF
```

### Dual-Purpose Inner Volume
1. **Zone detector:** CanCollide=false, CanTouch=true for entity tracking
2. **Mounting reference:** CFrame math against real Part surfaces

## Implementation Plan

### Phase 1: Update Room.lua buildRoom()
1. Keep inner volume at original dims (don't shrink)
2. Create outer volume = inner + (wallThickness × 2) per axis
3. Use `outer:SubtractAsync({inner})` to create shell
4. Set shell properties (Anchored, Material, Color, CollisionFidelity)
5. Parent shell to room container
6. Keep inner as zone (CanCollide=false, CanTouch=true)

### Phase 2: Update DoorwayCutter
1. Doorway cutter now cuts 1 shell part instead of finding slabs
2. Simplify wall detection (find shell part by name or reference)
3. Keep CollisionFidelity = PreciseConvexDecomposition

### Phase 3: Add Mounting Helpers to Room
```lua
function Room:getWallCFrame(face)  -- "N", "S", "E", "W", "U", "D"
function Room:getWallSize(face)
function Room:mountToWall(face, offset, object)
```

### Phase 4: Update PathGraph_Demo
1. Test shell generation
2. Verify doorway cutting still works
3. Test mounting (add lights using new helpers)

## Files to Modify
- `Framework/v2/src/Warren/Components/Room.lua`
- `Framework/v2/src/Warren/Components/DoorwayCutter.lua`
- `Framework/v2/src/Warren/Demos/PathGraph_Demo.lua`

## Notes
- Don't union rooms together - keep as separate shells for flexibility
- Inner volume becomes source of truth for interior geometry
- Shell is just the rendered/collidable representation

## Known Issues

### Room Volume Overlap (Unresolved)
The current PathGraph approach generates rooms along path segments, which leads to
overlap issues when paths curve back or rooms on different branches get close.
Attempted fixes (horizon scanning, overlap checking with position shifting) reduce
but don't eliminate the problem.

**Root cause:** Path-first generation couples room placement to path topology,
making it hard to guarantee non-overlapping volumes.

## Future Architecture: Volume-First Generation

A cleaner approach separates room placement from connectivity:

### Current Approach (Path-First)
1. Generate path points sequentially
2. Create room volumes at each point (try to avoid overlap)
3. Connections determined by path order
4. Cut doorways between path-connected rooms

### Proposed Approach (Volume-First)
1. **Place room volumes first** - scatter/cluster in space with collision avoidance
2. **Build connectivity graph** - pathfind through volumes to determine adjacency
3. **Cut doorways** - where paths cross room boundaries

### Benefits
- Room placement is purely spatial (no path constraints)
- Connectivity is flexible (can use MST, Delaunay, A*, etc.)
- Doorways placed based on actual adjacency, not path order
- Easier to guarantee non-overlapping volumes
- Can support different room clustering strategies (grid, organic, etc.)

### Room Sizing with Base Unit
Room dimensions should be expressed as base unit × scale factors:
```
baseUnit = 15
room dims = 15 * [3, 3, 7] = 45 x 45 x 105 studs
```
The scale factors (3, 3, 7) provide variation while keeping dimensions
as clean multiples of the base unit for interior tiling.

## Implementation Summary (Completed)

### Room.lua Changes
1. Replaced `buildSlabs()` with `buildShell()` using CSG `SubtractAsync`
2. Source part now defines INTERIOR dimensions (no more shrinking)
3. Zone part made invisible (Transparency=1) but functional
4. Added mounting helpers:
   - `getWallCFrame(face)` - Get CFrame for interior wall face
   - `getWallSize(face)` - Get Vector2 (width, height) of wall face
   - `mountToWall(face, offset, object)` - Mount object to wall
5. State tracks `shell` instead of `slabs`
6. Added `getShell()` public method

### DoorwayCutter.lua Changes
1. Replaced `findWallsToCut()` with `findShellsToCut()`
2. Renamed `cutWall()` to `cutShell()`
3. Removed `removeOverlappingWall()` (no longer needed with shells)
4. Updated debug logging to count shells instead of slabs

### Part Count Reduction
- **Before:** 7 parts per room (6 slabs + 1 zone)
- **After:** 2 parts per room (1 shell + 1 zone)
- For 30 rooms: 60 parts instead of 210
