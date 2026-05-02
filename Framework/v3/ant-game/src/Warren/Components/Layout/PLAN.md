# Layout-Based Dungeon Architecture

## Overview

Refactor from "regenerate from seed" to "serialize layout, instantiate from data".

**Current Flow:**
```
Seed → VolumeBuilder → ShellBuilder → DoorCutter → TrussBuilder → LightBuilder → Parts
       (recalculate everything on every load)
```

**New Flow:**
```
GENERATION (once per new region):
Seed + Config → LayoutBuilder → Layout Table

INSTANTIATION (on load/rebuild):
Layout Table → LayoutInstantiator → Parts

PERSISTENCE:
Layout Table ↔ LayoutSerializer ↔ String (for DataStore/sharing)
```

## Layout Schema

```lua
Layout = {
    -- Metadata
    version = 1,
    seed = 12345,

    -- Room volumes (interior space)
    rooms = {
        [1] = {
            id = 1,
            position = { 0, 20, 0 },
            dims = { 30, 25, 40 },
            parentId = nil,
            attachFace = nil,
        },
        [2] = {
            id = 2,
            position = { 47, 20, 0 },
            dims = { 25, 20, 35 },
            parentId = 1,
            attachFace = "E",
        },
    },

    -- Door openings (pre-calculated positions)
    doors = {
        {
            id = 1,
            fromRoom = 1,
            toRoom = 2,
            center = { 32, 20, 0 },
            width = 12,
            height = 12,
            axis = 1,  -- 1=X, 2=Y, 3=Z
        },
    },

    -- Climbing trusses
    trusses = {
        {
            id = 1,
            doorId = 1,
            position = { 32, 15, 0 },
            size = { 2, 10, 2 },
        },
    },

    -- Light fixtures
    lights = {
        {
            id = 1,
            roomId = 1,
            position = { 0, 32, 15 },
            size = { 8, 1, 0.3 },
            wall = "N",
        },
    },

    -- Teleport pads
    pads = {
        {
            id = "pad_1",
            roomId = 2,
            position = { 47, 10.5, 0 },
            -- Links are stored separately in RegionManager (cross-region concern)
        },
    },

    -- Spawn point
    spawn = {
        position = { 0, 10.5, 0 },
        roomId = 1,
    },

    -- Build config (for reference/debugging)
    config = {
        wallThickness = 1,
        material = "Brick",
        color = { 140, 110, 90 },
    },
}
```

## New Components

### LayoutBuilder.lua

Runs procedural generation, outputs a Layout table (no parts created).

```lua
-- Signals
In = {
    onGenerate = { seed, config, origin },
}
Out = {
    complete = { layout },
    failed = { reason },
}

-- Methods
:generate(seed, config, origin) → Layout
```

**Implementation:**
- Uses VolumeBuilder internally to plan room placement
- Calculates door positions (no CSG, just math)
- Calculates truss positions based on door/room data
- Calculates light positions based on room/door data
- Calculates pad positions based on room selection
- Returns pure data table

### LayoutInstantiator.lua

Takes a Layout table, creates all parts.

```lua
-- Signals
In = {
    onInstantiate = { layout, container },
    onClear = {},
}
Out = {
    complete = { container, partCount },
    failed = { reason },
}

-- Methods
:instantiate(layout, container) → Model
:getSpawnPoint() → SpawnLocation
:getPads() → { [padId] = Part }
```

**Implementation:**
- Creates room shells (walls, floor, ceiling)
- Cuts doors using CSG at stored positions (deterministic)
- Creates trusses at stored positions
- Creates lights at stored positions
- Creates pads at stored positions
- Creates spawn point at stored position

### LayoutSerializer.lua

Encodes/decodes layouts for storage.

```lua
-- Methods
:encode(layout) → string
:decode(string) → Layout
:compress(layout) → string  -- Optional: smaller for DataStore
:decompress(string) → Layout
```

**Implementation:**
- JSONEncode/JSONDecode for basic serialization
- Handle Roblox types (Color3 → {r,g,b}, Enum → string)
- Optional compression for DataStore limits

## Refactored RegionManager

```lua
-- Region data structure changes
regions = {
    [regionId] = {
        id = "region_1",
        seed = 12345,
        layout = { ... },  -- Full layout table (source of truth)
        padLinks = { ... },  -- Cross-region links
        isActive = false,

        -- Runtime only (not serialized)
        container = nil,  -- Model in workspace
        spawnPoint = nil,  -- SpawnLocation reference
        pads = {},  -- Pad part references
    },
}

-- New flow for creating region
function createNewRegion(...)
    -- Generate layout ONCE
    local layout = LayoutBuilder:generate(seed, config, origin)

    -- Store layout (this is the source of truth)
    region.layout = layout

    -- Instantiate parts
    local container = LayoutInstantiator:instantiate(layout)
    region.container = container
end

-- New flow for loading region
function loadRegion(regionId)
    local region = regions[regionId]

    -- Just instantiate from stored layout (no regeneration!)
    local container = LayoutInstantiator:instantiate(region.layout)
    region.container = container
end
```

## Migration Path

### Phase 1: LayoutBuilder
1. Create `Layout/LayoutBuilder.lua`
2. Extract room planning from VolumeBuilder (data only)
3. Extract door calculation from DoorCutter (data only)
4. Extract truss calculation from TrussBuilder (data only)
5. Extract light calculation from LightBuilder (data only)
6. Extract pad/spawn calculation
7. Test: verify layout table is complete and accurate

### Phase 2: LayoutInstantiator
1. Create `Layout/LayoutInstantiator.lua`
2. Implement shell building (walls from room data)
3. Implement door cutting (CSG at stored positions)
4. Implement truss creation
5. Implement light creation
6. Implement pad creation
7. Implement spawn creation
8. Test: verify instantiated geometry matches current system

### Phase 3: Integration
1. Update RegionManager to use new components
2. Store layout in region data instead of just seed
3. Use LayoutInstantiator for loading instead of regeneration
4. Test: verify region switching works correctly

### Phase 4: Serialization
1. Create `Layout/LayoutSerializer.lua`
2. Implement encode/decode
3. Add DataStore persistence (optional)
4. Test: verify round-trip serialization

### Phase 5: Cleanup
1. Remove old generation components or mark as internal
2. Update DungeonOrchestrator to use LayoutBuilder
3. Document new architecture

## File Structure

```
src/Warren/Components/
├── Layout/
│   ├── init.lua              -- Exports all layout components
│   ├── LayoutBuilder.lua     -- Generates layout from seed
│   ├── LayoutInstantiator.lua -- Creates parts from layout
│   ├── LayoutSerializer.lua  -- Encode/decode for storage
│   └── LayoutSchema.lua      -- Type definitions, validation
├── RegionManager.lua         -- Updated to use layouts
└── ... (existing components, some become internal)
```

## Benefits

1. **Reliability**: Spawn at {0,10,0}. Always. No recalculation.
2. **Performance**: Skip procedural pipeline on reload
3. **Debuggability**: Print/inspect layout table
4. **Persistence**: Save to DataStore, resume later
5. **Sharing**: Encode layout string, share with friends
6. **Editing**: Modify layout table for custom dungeons
7. **Testing**: Unit test with known layout data

## Open Questions

1. **CSG on instantiation**: Still use CSG for doors, or pre-split walls?
   - CSG at fixed positions should be reliable
   - Pre-split walls = more data but no CSG dependency

2. **Layout size**: How big are serialized layouts?
   - Estimate: ~50 rooms × ~200 bytes = ~10KB
   - DataStore limit: 4MB per key (plenty of room)

3. **Versioning**: How to handle schema changes?
   - Store version number, migrate on load if needed

4. **Partial updates**: Can we update just part of a layout?
   - Yes, but need to track dependencies (door positions depend on room positions)
