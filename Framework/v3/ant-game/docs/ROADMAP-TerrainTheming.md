# Terrain Theming System for Infinite Dungeon

## Context

This is a Roblox game built on a custom framework called Warren—a signal-driven, node-based architecture with strict encapsulation. The game is an infinite procedurally generated dungeon with exploration-based gameplay.

### Existing Architecture

**Layout Manager** (single source of truth):
- Manages all map/room data and state
- Tracks topology: hubs (3-5 portals), throughs (2 portals), spurs (1 portal)
- Handles portal connections between maps
- Server-authoritative, queries only—no direct mutation from other systems

**Room Structure**:
- Each room has an internal volume part used for:
  - Wall shell generation
  - Player detection (knowing which room they're in)
  - Minimap rendering (scaled 1:100)
- Rooms are built from standardized dimensions (critical for theme swapping)
- Currently rendered as brick parts with color variations per map

**Minimap System**:
- Full-screen tactical overlay (touchpad toggle, pauses gameplay)
- 3D model built from actual room geometry at 1:100 scale
- Queries layout manager for state, renders as a pure view
- Fog of war: adjacent unexplored = grey, explored = orange, current = highlighted

## Feature Request: Terrain-Based Theming System

### Goal

Add visual variety to dungeons using Roblox's terrain system alongside existing part geometry. The part geometry remains the source of truth for collision, detection, and minimap. Terrain is a visual layer painted based on that geometry.

### How Roblox Terrain Works

- Single global voxel grid (4x4x4 stud cells)
- Materials: Grass, Rock, Slate, Sand, Mud, Water, Ice, Snow, etc.
- Manipulated via `Workspace.Terrain` methods:
  - `FillBlock(cframe, size, material)` - fill a box region
  - `FillBall(position, radius, material)` - fill a sphere
  - `ReadVoxels()` / `WriteVoxels()` - fine-grained control
- Clear terrain by filling with `Enum.Material.Air`
- Terrain is global/persistent within session—must be manually cleared on room despawn
- Terrain doesn't attach to parts; it exists independently in world space
- Water material has built-in swimming/buoyancy behavior

### Design Principles

1. **Parts remain authoritative**: Room volumes define collision, player detection, minimap geometry. Terrain is decoration only.

2. **Declarative recipes**: Each room or theme defines a terrain recipe as data. The terrain system executes recipes on spawn, clears on despawn.

3. **Geometry as reference**: Use part positions/sizes/orientations as guides for where to apply terrain. Example: a wall part at position X with size Y means "fill this region with rock voxels."

4. **Convention over configuration**: Standardized room dimensions mean theme packs are plug-and-play.

5. **Vibes over detail**: The 4-stud voxel grid is chunky. Lean into stylized aesthetic, not realism.

### Terrain Recipe Structure

```lua
-- Example recipe schema
TerrainRecipe = {
    -- Floor treatment
    floor = {
        material = Enum.Material.Grass,  -- or Rock, Sand, Mud, etc.
        -- Optional: depth below floor plane (default 4 studs / 1 voxel)
        depth = 4,
    },

    -- Wall treatment (optional—can keep parts visible instead)
    walls = {
        material = Enum.Material.Rock,
        hideOriginal = true,  -- set part transparency to 1
    },

    -- Ceiling treatment (optional)
    ceiling = {
        material = Enum.Material.Rock,
        hideOriginal = true,
    },

    -- Feature placements (relative to room origin/bounds)
    features = {
        {
            type = "pool",  -- water-filled depression
            offset = Vector3.new(10, 0, 10),  -- relative to room center
            radius = 8,
            depth = 4,
        },
        {
            type = "mound",  -- raised terrain
            offset = Vector3.new(-5, 0, 5),
            size = Vector3.new(6, 4, 6),
            material = Enum.Material.Rock,
        },
        {
            type = "scatter",  -- random small features
            material = Enum.Material.Rock,
            count = 5,
            sizeRange = {min = 2, max = 4},
            bounds = "floor",  -- scatter within floor area
        },
    },
}
```

### Theme Pack Examples

**Cave Theme**:
```lua
CaveTheme = {
    floor = { material = Enum.Material.Rock },
    walls = { material = Enum.Material.Rock, hideOriginal = true },
    ceiling = { material = Enum.Material.Rock, hideOriginal = true },
    features = {
        { type = "scatter", material = Enum.Material.Rock, count = 3, sizeRange = {min = 2, max = 5} },
    },
    -- Part materials for any visible parts
    partMaterial = Enum.Material.Slate,
    -- Lighting preset
    lighting = {
        ambient = Color3.fromRGB(40, 35, 50),
        brightness = 0.3,
        fogEnd = 100,
        fogColor = Color3.fromRGB(20, 15, 25),
    },
}
```

**Forest/Outdoor Theme**:
```lua
ForestTheme = {
    floor = { material = Enum.Material.Grass },
    walls = { material = nil, hideOriginal = true },  -- invisible walls for "outdoor" feel
    ceiling = { material = nil, hideOriginal = true },  -- no ceiling
    features = {
        { type = "pool", offset = Vector3.new(8, 0, 8), radius = 6, depth = 3 },
        { type = "scatter", material = Enum.Material.Rock, count = 4, sizeRange = {min = 1, max = 3} },
    },
    lighting = {
        ambient = Color3.fromRGB(135, 160, 130),
        brightness = 2,
        fogEnd = 300,
    },
}
```

**Swamp Theme**:
```lua
SwampTheme = {
    floor = { material = Enum.Material.Mud },
    walls = { material = nil, hideOriginal = true },
    features = {
        { type = "scatter", material = Enum.Material.Water, count = 6, sizeRange = {min = 3, max = 8} },
    },
    lighting = {
        ambient = Color3.fromRGB(80, 90, 60),
        fogEnd = 80,
        fogColor = Color3.fromRGB(60, 70, 40),
    },
}
```

### Implementation Approach

**TerrainManager Module**:
- Receives room volume reference and terrain recipe
- Calculates world-space regions from room geometry
- Applies terrain fills based on recipe
- Tracks what regions have been filled for cleanup

**Spawn Flow**:
1. Room parts spawn as usual (layout manager)
2. TerrainManager receives the room and its assigned theme
3. TerrainManager reads room volume CFrame/Size
4. For each recipe element:
   - Calculate world-space position/size relative to room
   - Call appropriate Terrain method (FillBlock, FillBall, etc.)
5. Apply part visibility/material changes per recipe
6. Apply lighting preset if specified

**Despawn Flow**:
1. Layout manager signals room despawn
2. TerrainManager calculates bounding region for room
3. Fill entire region with `Enum.Material.Air`
4. Reset any lighting changes if needed

**Key Functions Needed**:

```lua
-- Apply a recipe to a room
TerrainManager:ApplyTheme(roomVolume: BasePart, recipe: TerrainRecipe)

-- Clear terrain for a room
TerrainManager:ClearRoom(roomVolume: BasePart)

-- Helpers
TerrainManager:FillFloor(roomVolume, material, depth)
TerrainManager:FillWalls(roomVolume, material, thickness)
TerrainManager:PlaceFeature(roomVolume, featureConfig)
```

### Using Room Geometry as Reference

The room volume part provides:
- `CFrame` - position and orientation
- `Size` - dimensions (X = width, Y = height, Z = depth)

To fill the floor:
```lua
local floorCFrame = roomVolume.CFrame * CFrame.new(0, -roomVolume.Size.Y/2 + depth/2, 0)
local floorSize = Vector3.new(roomVolume.Size.X, depth, roomVolume.Size.Z)
Workspace.Terrain:FillBlock(floorCFrame, floorSize, material)
```

To fill a wall (example: back wall, -Z face):
```lua
local wallCFrame = roomVolume.CFrame * CFrame.new(0, 0, -roomVolume.Size.Z/2 + thickness/2)
local wallSize = Vector3.new(roomVolume.Size.X, roomVolume.Size.Y, thickness)
Workspace.Terrain:FillBlock(wallCFrame, wallSize, material)
```

### Performance Considerations

- Terrain writes are relatively cheap but not free
- Batch operations where possible
- For rapid portal transitions, consider:
  - Slight delay on terrain fill (after geometry loads)
  - Pre-clearing destination region before filling
- Profile with 10+ room transitions in quick succession

### Things NOT To Do

- Don't try to "texture" parts with terrain—they're separate systems
- Don't store terrain state—it's derived from recipes, regenerate on demand
- Don't couple terrain logic to layout manager internals
- Don't forget to clear terrain on despawn (it persists otherwise)

### Integration Points

The terrain system should:
- Subscribe to room spawn/despawn events from layout manager
- Query room data (volume reference, assigned theme) from layout manager
- NOT modify layout manager state
- NOT affect minimap rendering (minimap reads part geometry, ignores terrain)

### Future Extensions

Once the base system works:
- Per-room theme overrides (special rooms get unique treatment)
- Biome transitions at boundaries (blend themes at portal rooms)
- Theme unlocks/purchases for player-claimed rooms
- Seasonal theme variants

---

## Summary

Build a TerrainManager that:
1. Takes room geometry as spatial reference
2. Reads declarative theme recipes
3. Paints terrain voxels accordingly
4. Cleans up on despawn

Keep it simple, keep it declarative, keep parts as the source of truth. Terrain is just another view layer.
