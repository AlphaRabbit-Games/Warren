# Terrain Implementation Postmortem - Attempt 1

**Date:** 2026-02-03  
**Outcome:** Rolled back to bd3d1fd

## Summary

Attempted to add terrain voxel coating to dungeon walls/floors. After multiple iterations of fixes, the cascading complexity made the implementation unmaintainable. Decided to roll back and approach with better architecture.

## Issues Encountered

### 1. Studio Lag on Exit
- Creating new `RaycastParams` per raycast (800+ objects)
- **Fix:** Reuse single RaycastParams at module scope
- **Status:** Simple fix, would keep

### 2. Voxel Size Constraints
- Roblox terrain voxels are minimum 4 studs
- Cannot do fractional sizes
- Must design around this constraint

### 3. Wall Thickness vs Voxel Alignment
- Started with 1-stud walls, 4-stud voxels
- Changed wallThickness to 4 to match voxels
- Cascaded into door cutter, room gap, and clearing issues

### 4. Door Cutter Depth Failures
- Original formula `wt * 8` designed for wt=1
- With wt=4, cutter was 32 studs - cutting adjacent walls
- Multiple formula attempts, each broke something else

### 5. Terrain Doorway Clearing
- Separate system from CSG wall cutting
- Floor terrain extended UP into doorways, blocking walking
- Attempts to clear floor terrain cut holes in room floors

### 6. Room Sizing Cascades
- Added terrainPadding to compensate for terrain in rooms
- Changed baseUnit 5→15→10, each change broke other things
- Lights too far from center in larger rooms

### 7. Wall Gap Visibility
- With wallThickness=4, gap = 8 studs (2×wt)
- Created visible seams between rooms

## Root Causes

### 1. No Single Source of Truth for Dimensions
All these values are mathematically related but defined separately:
- wallThickness
- terrainThickness  
- cutterDepth
- clearingDepth
- room gap
- terrainPadding

Change one → manually update others → miss one → breakage

### 2. Voxel Grid vs Part Grid Mismatch
- Parts: arbitrary sizes
- Terrain: locked to 4-stud grid
- Precise alignment is fragile

### 3. Compound Offset Calculations
- Door center = room position + dims + wallThickness
- Terrain clearing = door center + wallThickness + terrainThickness
- Each layer adds complexity, errors compound

### 4. Dual Clearing Systems
- CSG cuts wall parts
- FillBlock(Air) clears terrain
- Both need identical geometry but calculated separately

## Path Forward

Implement a **Geometry System** as the single source of truth for:
- Querying and manipulating rendered 3D objects
- Tracking margins, padding, and offsets
- Derived values that auto-update when base values change
- Centralized API so nodes don't roll their own offset calculations

This requires architectural work before re-attempting terrain.
