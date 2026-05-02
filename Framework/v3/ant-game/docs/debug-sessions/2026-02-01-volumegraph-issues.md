# VolumeGraph Demo Issues - 2026-02-01

## Summary
The VolumeGraph procedural dungeon generator has several issues that need investigation with fresh context.

## Working Features
- Room volume generation (rooms adjoin correctly, no overlap)
- Growth-based placement (ClusterStrategies.lua)
- Vertical room connections (15-20% chance for ceiling/floor adjacency)
- Interior neon lights with PointLight
- Spawn point relocation to first room
- Debug output with error handling

## Known Issues

### 1. Door Holes Not Being Cut
**Symptom:** Walls between connected rooms remain solid - no door openings.

**Suspected Cause:** DoorwayCutter.findWallsToSplit() may not be finding the wall parts.

**Investigation Points:**
- Room container naming: Demo creates `roomId = "Room_" .. data.id` (e.g., "Room_1")
- Room.lua creates container: `container.Name = "Room_" .. self.id` = "Room_Room_1"
- DoorwayCutter searches for: `"Room_Room_" .. fromRoomId` and `"Room_" .. fromRoomId`
- `fromRoomId` comes from layout.id which is a NUMBER (1, 2, 3...)
- So it searches for "Room_Room_1" (correct) and "Room_1" (wrong container name)

**Possible Fix:** Ensure naming conventions match between:
- VolumeGraph layout.id (number)
- Demo roomId string construction
- Room container naming
- DoorwayCutter search patterns

### 2. Climbing Aids (TrussParts) Placed Outside Room Volumes
**Symptom:** Ladders and poles appear outside the rooms instead of inside near doorways.

**Suspected Cause:** The climbing aid placement uses `doorX`/`doorZ` calculated as midpoint between room centers, but doesn't account for wall thickness or interior positioning.

**Investigation Points:**
- `doorX = (roomA.position[1] + roomB.position[1]) / 2` gives wall position, not interior
- Need to offset INTO the room interior by wallThickness
- For vertical connections (axis=2), pole placed at `doorX - 3, doorZ - 3` - arbitrary offset
- For horizontal with height diff, ladders placed at wall center, not inset

**Possible Fix:**
- Calculate door center based on shared wall overlap region
- Offset ladder/pole positions inward from wall by at least wallThickness + ladder radius
- Consider which room is lower and place ladder on that side

### 3. Spawn Point Not Relocating (FIXED?)
**Status:** Added to demo but needs verification that it works after door/truss fixes.

## Code Files Involved

### VolumeGraph_Demo.lua
- Main demo orchestration
- Signal wiring for room creation
- Post-generation tasks (doors, lights, climbing aids, spawn)

### DoorwayCutter.lua
- `findWallsToSplit()` - searches for wall parts by room ID
- `splitWall()` - creates door opening by splitting wall into sections
- `processConnections()` - iterates room pairs and cuts doorways

### ClusterStrategies.lua
- Growth-based room placement
- Guarantees room adjacency via attachedTo tracking
- Vertical faces (U/D) with 15-20% probability

### Room.lua
- Creates 6 slab walls around interior volume
- Container naming: "Room_" + node.id
- Wall naming: Floor, Ceiling, North, South, East, West

### VolumeGraph.lua
- Generates room layouts
- Emits roomLayout and complete signals
- layout.id is a NUMBER, not string

## Architecture Notes

### Room ID Flow
1. VolumeGraph creates layout with numeric id (1, 2, 3...)
2. Demo receives layout, creates roomId = "Room_" + layout.id
3. Room:new({ id = roomId }) gets id "Room_1"
4. Room creates container named "Room_" + self.id = "Room_Room_1"
5. DoorwayCutter receives numeric layout.id, searches for "Room_Room_1"

### Wall Adjacency Detection
- Rooms touch when: `|centerDist - (dim1/2 + dim2/2 + 2*wallThickness)| < 1`
- This accounts for shell-touching (outer walls touch, not inner volumes)

### Signal Flow
1. VolumeGraph.In.onGenerate() called
2. ClusterStrategies generates room volumes
3. VolumeGraph emits "roomLayout" for each room
4. Demo creates Room nodes from layouts
5. VolumeGraph emits "complete" with all layouts
6. Demo calls DoorwayCutter.In.onRoomsComplete()
7. Demo adds lights, climbing aids, moves spawn

## Next Steps
1. Fix room ID consistency between VolumeGraph, Demo, Room, and DoorwayCutter
2. Fix climbing aid placement to be inside rooms near doorways
3. Test all strategies (Grid, Poisson, BSP, Organic, Radial)
4. Verify spawn relocation works
