# Factory & GeometrySpec - Declarative Geometry System

Warren Framework v2

## Overview

Factory is a declarative system for building Roblox geometry from Lua tables. Define your maps, structures, and node geometry as data - the framework handles instantiation, styling, and optimization.

**Primary API:** `Lib.Factory`
**Legacy wrapper:** `Lib.GeometrySpec` (delegates to Factory)

**Use cases:**
- **Map layouts** - Buildings, landscapes, game zones
- **Node geometry** - Turrets, launchers, any node with generated parts
- **Rapid prototyping** - Describe structures in natural language, generate layouts

Think of it as a stylesheet for 3D parts - define geometry as data, apply classes for shared styling, compile for production.

**Architecture:** Factory uses the generic Resolver pattern - a formula solver that computes values in dependency order. See [RESOLVER.md](RESOLVER.md) for the mental model.

## Quick Start

```lua
local Lib = require(game.ReplicatedStorage.Lib)
local Factory = Lib.Factory

-- Build from a saved layout
local mansion = Factory.geometry(Lib.Layouts.BeverlyMansion)

-- Build from inline spec
local turret = Factory.geometry({
    name = "Turret",
    spec = {
        bounds = {4, 6, 4},
        parts = {
            { id = "base", class = "frame", size = {4, 2, 4}, position = {0, 0, 0} },
            { id = "barrel", class = "accent", size = {0.5, 0.5, 3}, position = {0, 2.5, 1.5} },
        },
        classes = {
            frame = { Material = "DiamondPlate", Color = {80, 80, 85} },
            accent = { Material = "Metal", Color = {40, 40, 40} },
        },
    },
})

-- Access built parts via registry
local base = Factory.getInstance("base")

-- Optimize for production
local stats = Factory.compile(mansion, { strategy = "class" })
print("Reduced to", stats.compiledUnions, "unions")
```

## Spec Format

### Layouts (Saved Files)

Stored in `Lib/Layouts/*.lua` with name metadata:

```lua
-- Lib/Layouts/DefenseZone.lua
return {
    name = "DefenseZone",
    spec = {
        bounds = {40, 12, 30},
        origin = "corner",

        base = {
            part = { CanCollide = true },
        },

        classes = {
            concrete = { Material = "Concrete", Color = {180, 175, 165} },
        },

        parts = {
            { id = "floor", class = "concrete", position = {20, 0, 15}, size = {40, 0.5, 30} },
        },

        mounts = {
            { id = "turret1", position = {10, 0.5, 5}, facing = {0, 0, 1} },
        },
    },
}
```

### Inline Specs

For node components, use raw spec format:

```lua
local turretSpec = {
    bounds = {4, 6, 4},
    parts = { ... },
    classes = { ... },
}
local container = Factory.geometry({ name = "Turret", spec = turretSpec })
```

## Part Containers

`Factory.geometry()` returns a **Part** (not a Model) that:
- Has `Size` matching the spec's `bounds`
- Is invisible (`Transparency = 1`) and non-collidable
- Contains all child geometry as children
- Preserves bounding volume information

All child parts are **Anchored = true** by default (built into `base.part`).

## Shapes

Four primitive shapes are supported:

### Block (default)

```lua
{ id = "wall", position = {0, 5, 0}, size = {10, 10, 1} }
```

### Cylinder

```lua
{ id = "pillar", shape = "cylinder", position = {0, 5, 0}, height = 10, radius = 2 }
```

Cylinders are oriented vertically (height along Y axis).

### Sphere

```lua
{ id = "dome", shape = "sphere", position = {0, 10, 0}, radius = 5 }
```

### Wedge

```lua
{ id = "ramp", shape = "wedge", position = {0, 2, 0}, size = {4, 4, 8}, rotation = {0, 90, 0} }
```

Wedges support `rotation = {rx, ry, rz}` in degrees.

## Origin Modes

Control how `{0, 0, 0}` is interpreted:

```lua
{
    bounds = {20, 10, 20},
    origin = "corner",  -- default
}
```

| Origin | Description | Use Case |
|--------|-------------|----------|
| `"corner"` | `{0,0,0}` at min corner | Map layouts, buildings |
| `"center"` | `{0,0,0}` at volume center | Symmetric objects |
| `"floor-center"` | `{0,0,0}` at XZ center, Y=0 at floor | Characters, vehicles |

## Class-Based Styling

CSS-like cascade using ClassResolver. The cascade is a formula - each step merges into the result:

```
result = merge(parent, defaults, base[type], classes..., id, inline)
```

```lua
{
    -- Applied to all parts
    defaults = {
        Material = "SmoothPlastic",
    },

    -- Applied by element type
    -- base.part is built-in with { Anchored = true }
    base = {
        part = { CanCollide = true },
    },

    -- Named style classes
    classes = {
        metal = { Material = "DiamondPlate", Color = {80, 80, 85} },
        glass = { Material = "Glass", Color = {200, 220, 235}, Transparency = 0.3 },
        danger = { Material = "Neon", Color = {255, 60, 40} },
    },

    parts = {
        { id = "frame", class = "metal", ... },
        { id = "window", class = "glass", ... },
        -- Inline properties override everything
        { id = "custom", class = "metal", Color = {255, 0, 0}, ... },
    },
}
```

**Resolution order (the formula):**
1. Inherit from parent (tree-level)
2. Apply `defaults` (applied to all)
3. Apply `base[type]` (by element type)
4. Merge each class (space-separated, left to right)
5. Apply `ids[id]` (by element ID)
6. Merge inline properties (highest priority)

This is handled by ClassResolver - see [RESOLVER.md](RESOLVER.md) for details.

## Function-Based Layouts (References)

For layouts where parts reference each other's dimensions, use function syntax:

```lua
return function(parts, parent)
    return {
        name = "Shop",
        parts = {
            Floor1 = {
                parent = "root",
                class = "stucco",
                geometry = {
                    origin = {0, 0, 0},
                    scale = {80, 18, 65},
                },
            },
            Floor2 = {
                parent = "Floor1",
                class = "stucco_cream",
                geometry = {
                    -- Stack on top of parent using parent reference
                    origin = {0, parent.Size[2], 0},
                    scale = {80, 18, 65},
                },
            },
            Roof = {
                parent = "Floor2",
                class = "roof_slate",
                shape = "wedge",
                geometry = {
                    -- Stack on top of parent (chain accumulates)
                    origin = {0, parent.Size[2], 0},
                    scale = {80, 16, 65},
                },
            },
        },
    }
end
```

**Available references:**
- `parent.Size[1|2|3]` - Direct parent's scale X/Y/Z
- `parent.Position[1|2|3]` - Direct parent's origin X/Y/Z
- `parent.Rotation[1|2|3]` - Direct parent's rotation X/Y/Z
- `parts.{id}.Size[1|2|3]` - Named part's scale X/Y/Z
- `parts.{id}.Position[1|2|3]` - Named part's origin X/Y/Z
- `parts.{id}.Rotation[1|2|3]` - Named part's rotation X/Y/Z

**Arithmetic supported:**
```lua
origin = {0, parent.Size[2] + 10, 0}
origin = {parts.Wall.Size[1] * 0.5, 0, 0}
```

This follows the Logo/Turtle paradigm - each part positions relative to its parent in the chain, and origins accumulate automatically.

## Arrays

Generate multiple copies of a part at regular intervals. Useful for fences, pillars, grids, and any repeating geometry.

### Linear Array

Repeat along a single direction:

```lua
{ id = "pillar", class = "column", position = {0, 0, 0}, size = {2, 10, 2},
  array = { count = 4, offset = {10, 0, 0} }
}
-- Generates: pillar_1, pillar_2, pillar_3, pillar_4
-- Positioned at X = 0, 10, 20, 30
```

### Grid Array (Per-Axis)

Repeat along multiple axes for 2D or 3D grids:

```lua
{ id = "tile", class = "floor", position = {0, 0, 0}, size = {4, 1, 4},
  array = {
    x = { count = 5, spacing = 4 },
    z = { count = 3, spacing = 4 }
  }
}
-- Generates: tile_1_1 through tile_5_3 (15 tiles)
-- Forms a 5x3 grid
```

### 3D Grid

```lua
{ id = "cube", class = "crystal", position = {0, 0, 0}, size = {2, 2, 2},
  array = {
    x = { count = 3, spacing = 4 },
    y = { count = 2, spacing = 4 },
    z = { count = 3, spacing = 4 }
  }
}
-- Generates: cube_1_1_1 through cube_3_2_3 (18 cubes)
```

### Generated IDs

| Dimensionality | ID Format | Example |
|----------------|-----------|---------|
| Linear (1 axis) | `{id}_{n}` | `pillar_1`, `pillar_2` |
| 2D grid | `{id}_{x}_{z}` | `tile_1_1`, `tile_2_3` |
| 3D grid | `{id}_{x}_{y}_{z}` | `cube_1_1_1`, `cube_2_2_2` |

Arrays are expanded during the resolve phase, before references are resolved. This means you cannot reference individual array elements by their generated IDs in the same layout - use arrays for final leaf geometry.

## Xref (Layout Composition)

Import another layout as a child using `xref`. This enables modular, reusable building blocks.

### Basic Usage

```lua
local SuburbanHouse = require(game.ReplicatedStorage.Lib.Layouts.SuburbanHouse)
local GarageLayout = require(game.ReplicatedStorage.Lib.Layouts.Garage)

return {
    name = "Neighborhood",
    spec = {
        parts = {
            { id = "house1", xref = SuburbanHouse, position = {0, 0, 0} },
            { id = "house2", xref = SuburbanHouse, position = {30, 0, 0}, rotation = {0, 180, 0} },
            { id = "garage", xref = GarageLayout, position = {-15, 0, 0} },
        }
    }
}
```

### How It Works

When the resolver encounters `xref`:

1. **Creates a container** - The xref node becomes an invisible transform node
2. **Imports child parts** - All parts from the referenced layout are imported
3. **Namespaces IDs** - Imported parts get prefixed: `house1.Foundation`, `house1.Roof`
4. **Sets parent** - Imported parts become children of the container
5. **Inherits transforms** - Position/rotation from container applies to all children

### Generated Structure

```
house1                  -- Container (invisible, transform only)
├── house1.Foundation   -- Imported, parent = house1
├── house1.Walls        -- Imported, parent = house1
└── house1.Roof         -- Imported, parent = house1
house2                  -- Container (rotated 180°)
├── house2.Foundation   -- Inherits rotation from house2
├── house2.Walls
└── house2.Roof
```

### Property Cascade

Properties on the xref container cascade to imported parts:

```lua
{ id = "abandoned", xref = SuburbanHouse,
  class = "weathered",  -- All imported parts inherit this class
  position = {100, 0, 0}
}
```

The cascade follows normal rules: parent provides base values, children can override. If the imported layout's Roof has `class = "shingles"`, the final class becomes `"weathered shingles"` (both apply, imported wins conflicts).

### Nested Xrefs

Xrefs can be nested - an imported layout can itself contain xrefs:

```lua
-- Layouts/House.lua
return {
    name = "House",
    spec = {
        parts = {
            { id = "building", ... },
            { id = "attached_garage", xref = GarageLayout, position = {-10, 0, 0} },
        }
    }
}

-- Layouts/Neighborhood.lua
-- Using House imports GarageLayout transitively
{ id = "house1", xref = House, position = {0, 0, 0} }
-- Creates: house1, house1.building, house1.attached_garage,
--          house1.attached_garage.door, etc.
```

## Scale

Convert spec units to studs:

```lua
{
    scale = "4:1",    -- 4 studs per 1 spec unit
    bounds = {5, 3, 5},  -- 20x12x20 studs
}
```

Useful for working in meters (4 studs ≈ 1 meter).

## Mount Points

Named positions for attaching child nodes:

```lua
mounts = {
    { id = "turret1", position = {5, 0, 5}, facing = {0, 0, 1} },
    { id = "spawn", position = {10, 0, -5} },
}
```

Mounts don't create geometry - they're positions in the registry for orchestrator coordination.

## Properties

Standard Roblox Part properties are supported:

| Property | Type | Example |
|----------|------|---------|
| `Color` | `{r, g, b}` or string | `{255, 0, 0}` or `"Bright red"` |
| `Material` | string | `"DiamondPlate"`, `"Neon"`, `"Glass"` |
| `Transparency` | number | `0.5` |
| `CanCollide` | boolean | `false` |
| `CanTouch` | boolean | `false` |
| `CanQuery` | boolean | `false` |
| `Reflectance` | number | `0.5` |
| `CastShadow` | boolean | `false` |
| `Massless` | boolean | `true` |

Colors can be:
- RGB table `{255, 128, 0}` (0-255 range)
- Normalized table `{1, 0.5, 0}` (0-1 range, auto-detected)
- BrickColor name `"Bright red"`

---

# Compiler - Geometry Optimization

## Overview

`Factory.compile()` merges parts into unions, reducing draw calls for production maps.

```lua
local mansion = Factory.geometry(Lib.Layouts.BeverlyMansion)
print("Before:", #mansion:GetChildren(), "parts")  -- ~50 parts

local stats = Factory.compile(mansion, { strategy = "class" })
print("After:", #mansion:GetChildren(), "parts")   -- ~12 unions
```

## Strategies

| Strategy | Groups By | Best For |
|----------|-----------|----------|
| `"class"` | FactoryClass attribute | **Recommended.** Semantic, predictable. |
| `"material"` | Material + Color + Transparency | Preserves exact appearance. |
| `"aggressive"` | Material + Transparency only | Maximum compression, loses color variety. |
| `"spatial"` | Grid cell + material | Streaming, LOD systems. |

## Usage

```lua
-- Preview without modifying (dry run)
local preview = Factory.compile(container, { dryRun = true })
print("Would create", preview.compiledUnions, "unions from", preview.originalParts, "parts")

-- Compile with class strategy (recommended)
local stats = Factory.compile(container, { strategy = "class" })

-- Compile with options
local stats = Factory.compile(container, {
    strategy = "class",
    preserveRegistry = true,     -- Update registry with compiled parts (default)
    collisionFidelity = "Hull",  -- "Hull" | "Box" | "Precise"
})
```

## Stats Output

```lua
{
    originalParts = 50,      -- Parts before compile
    compiledUnions = 12,     -- Unions created
    ungroupedParts = 3,      -- Single-part groups (not unioned)
    triangleEstimate = 1200, -- Estimated triangle count
}
```

## Constraints

Unions have Roblox limitations:
- **Same material required** - Parts with different materials cannot be unioned
- **Same transparency required** - Mixing transparent and opaque fails
- **Triangle limit** - Max ~20K triangles per union (compiler chunks automatically)
- **Colors merge** - All parts in a union become one color

The `"class"` strategy is safest because classes already define consistent materials.

## Registry After Compile

Registry entries are updated to point to the compiled unions:

```lua
-- Before compile: returns original Part
local lawn = Factory.getInstance("lawn")

-- After compile: returns the union containing that part
local lawn = Factory.getInstance("lawn")  -- Same API, different instance
```

---

# Scanner - Visual → Config Workflow

## Overview

Build geometry visually in Studio, export to layout code.

**Workflow:**
1. Create parts in Studio (rough placement is fine)
2. Tag the container with `GeometrySpecTag = "area"`
3. Run scanner - get clean Lua config
4. Fine-tune in text editor

## Basic Usage

```lua
-- In Studio command bar
local Lib = require(game.ReplicatedStorage.Lib)
Lib.Factory.scan(workspace.MyZone)
-- Outputs layout code to console
```

## Attributes

Attributes on parts for scanning and round-trip:

| Attribute | Type | Description |
|-----------|------|-------------|
| `FactoryId` | string | Part's `id` (set automatically by Factory.build) |
| `FactoryClass` | string | Part's `class` (set automatically by Factory.build) |
| `GeometrySpecId` | string | Part's `id` in output (legacy) |
| `GeometrySpecClass` | string | Part's `class` in output (legacy) |
| `GeometrySpecIgnore` | boolean | Skip this part during scan |
| `GeometrySpecTag` | string | `"area"` marks scannable area containers |

## Round-Trip Workflow

Factory enables a full round-trip workflow for iterative development:

1. **Build** - `Factory.geometry()` creates parts with `FactoryClass` / `FactoryId` attributes
2. **Edit** - Make manual changes in Studio (adjust positions, sizes, add parts)
3. **Scan** - `Factory.scan()` auto-resolves the layout and reconstructs clean code

```lua
-- Your layout file: Lib/Layouts/Platform.lua
return {
    name = "Platform",
    spec = {
        classes = {
            metal = { Material = "DiamondPlate", Color = {80, 80, 85} },
        },
        parts = {
            { id = "floor", class = "metal", position = {0, 0, 0}, size = {20, 1, 20} },
        },
    },
}
```

```lua
-- Build it
local model = Factory.geometry(Lib.Layouts.Platform)

-- Make changes in Studio...
-- - Move the floor part
-- - Change color on one part to red (override)

-- Scan it back - layout auto-resolved from model name "Platform"
local code = Factory.scan(model)
```

**Scanned output (clean, not flattened):**
```lua
return {
    name = "Platform",
    spec = {
        classes = {
            metal = { Material = "DiamondPlate", Color = {80, 80, 85} },
        },
        parts = {
            -- Only outputs position (changed) and Color (if overridden)
            -- Does NOT output Material - matches class definition
            { id = "floor", class = "metal", position = {5, 0, 10}, size = {20, 1, 20} },
        },
    },
}
```

**How it works:**
- Model is named "Platform" (from `layout.name`)
- Scanner auto-resolves `Lib.Layouts.Platform` to get class definitions
- Parts have `FactoryClass` attribute → scanner looks up that class
- Only outputs properties that differ from what the class provides

**Workflow benefits:**
- AI generates layout code → you get 80-90% there
- Tweak in Studio or VS Code
- `Factory.scan(model)` captures changes as clean source code
- Source stays maintainable (classes, not flattened inline styles)

## Auto-Cleanup

Scanner automatically snaps imprecise Studio placement:
- Part edges snap to container bounds
- Parts snap to each other
- Sizes round to clean values

## Mirror Preview

Iterative workflow - preview before exporting:

```lua
Lib.Factory.mirror("MyZone", workspace)  -- Creates preview copy
-- Adjust original, run again to refresh
Lib.Factory.scan(workspace.MyZone)       -- Export final config
```

## List Areas

```lua
Lib.Factory.listAreas(workspace)
-- Outputs: MyZone: bounds {40.0, 10.0, 30.0} at (0, 5, 0)
```

---

# AI-Assisted Layout Generation

## Overview

Natural language → geometry. Describe what you want, get walkable layouts.

This workflow emerged from the declarative nature of the spec format - it's structured data that AI can generate from descriptions or reference images.

## Examples

**From description:**
> "Build me a small defensive outpost with corner pillars, windows, and a central console"

```lua
-- AI generates:
return {
    name = "Outpost",
    spec = {
        bounds = {24, 10, 24},
        classes = {
            floor = { Material = "Concrete", Color = {140, 135, 130} },
            wall = { Material = "Brick", Color = {95, 85, 80} },
            -- ...
        },
        parts = {
            { id = "foundation", class = "floor", position = {12, 0.25, 12}, size = {24, 0.5, 24} },
            { id = "pillar_nw", class = "wall", position = {2, 4, 2}, size = {2, 8, 2} },
            -- ...
        },
    },
}
```

**From reference image:**
> "Here's an aerial view of a Belgian village. Create a layout centered on the church."

The AI extracts:
- Spatial relationships (church at center, radiating streets)
- Architectural style (Neo-Gothic church, Flemish houses)
- Materials (red brick, slate roofs, cobblestone)

## Workflow

1. **Describe or provide reference** - Text description, aerial photo, architectural reference
2. **Generate layout** - AI produces declarative spec
3. **Build and preview** - `Factory.geometry(layout)`
4. **Iterate conversationally** - "Move the pool closer", "Add a guest house"
5. **Compile for production** - `Factory.compile(container)`

## Quality Scaling

Detail scales with input:
- **Aerial view** → Layout, massing, positioning
- **Street-level photos** → Facades, materials, architectural details
- **Specific references** → Accurate landmark recreation

## Example Layouts

The `Lib/Layouts/` folder contains AI-generated examples:

| Layout | Description |
|--------|-------------|
| `Outpost` | Small defensive structure with pillars, windows, antenna |
| `BeverlyMansion` | Large mansion with pool, garage, multiple wings |
| `Lichtervelde` | Belgian village centered on Neo-Gothic church |
| `SpaceNeedle` | Seattle landmark with hourglass tripod, flying saucer |

---

# API Reference

## Factory

```lua
-- Building
Factory.geometry(layout, parent)     -- Build geometry, returns Part container
Factory.gui(layout, parent)          -- [Planned] Build GUI

-- Compilation
Factory.compile(container, options)  -- Optimize geometry into unions

-- Registry
Factory.get(id, domain)              -- Get registry entry
Factory.getInstance(id, domain)      -- Get Roblox instance
Factory.clear()                      -- Clear all registries

-- Scanner
Factory.scan(container, options)     -- Print layout code to console
Factory.scanArea(name, container)    -- Scan named area
Factory.mirror(name, container)      -- Create preview copy
Factory.listAreas(container)         -- List scannable areas
```

## Factory.Geometry

```lua
Factory.Geometry.build(layout, parent)    -- Core build function
Factory.Geometry.get(selector)            -- Get by ID (supports "#id" prefix)
Factory.Geometry.getInstance(selector)    -- Get instance only
Factory.Geometry.clear()                  -- Clear geometry registry
Factory.Geometry.parseScale(value)        -- Parse "4:1" or number
Factory.Geometry.getScale()               -- Current scale factor
Factory.Geometry.toStuds(value)           -- Convert to studs
Factory.Geometry.updateInstance(id, inst) -- Update registry entry
```

## Factory.Compiler

```lua
Factory.Compiler.compile(container, options)  -- Main compile function
Factory.Compiler.groupParts(container, strategy, options)  -- Group by strategy
Factory.Compiler.estimateTriangles(parts)     -- Triangle count estimate
Factory.Compiler.chunkGroup(group, max)       -- Split large groups
Factory.Compiler.unionGroup(group, options)   -- Create union
```

## Lib.GeometrySpec (Legacy)

Backwards-compatible wrapper - delegates to Factory:

```lua
GeometrySpec.build(layout, parent)   -- → Factory.geometry()
GeometrySpec.get(selector)           -- → Factory.Geometry.get()
GeometrySpec.clear()                 -- → Factory.Geometry.clear()
GeometrySpec.scan(container)         -- → Factory.scan()
```

---

# Module Structure

```
Lib/
├── ClassResolver.lua         -- Per-element cascade formula (domain-agnostic)
├── Styles.lua                -- Universal style definitions
├── Factory/
│   ├── init.lua              -- Public API
│   ├── Geometry.lua          -- Tree resolver + Part adapter
│   ├── Scanner.lua           -- Visual → config export
│   └── Compiler.lua          -- Geometry optimization
├── GeometrySpec/
│   └── init.lua              -- Legacy wrapper (delegates to Factory)
└── Layouts/
    ├── init.lua              -- Lazy loader
    └── *.lua                 -- Layout definitions
```

**Architecture:**
- `ClassResolver` - Generic cascade formula, used by all domains
- `Styles.lua` - Shared style definitions (base, classes, ids)
- `Geometry.lua` - Uses ClassResolver + adds tree resolution + Part instantiation

See [RESOLVER.md](RESOLVER.md) for the full mental model.

---

# Examples

## Minimal Layout

```lua
return {
    name = "Platform",
    spec = {
        bounds = {20, 2, 20},
        parts = {
            { id = "floor", position = {10, 1, 10}, size = {20, 2, 20} },
        },
    },
}
```

## Styled Layout

```lua
return {
    name = "StyledPlatform",
    spec = {
        bounds = {20, 2, 20},

        base = {
            part = { CanCollide = true },
        },

        classes = {
            metal = { Material = "DiamondPlate", Color = {100, 100, 105} },
            glow = { Material = "Neon", Color = {0, 200, 255} },
        },

        parts = {
            { id = "floor", class = "metal", position = {10, 1, 10}, size = {20, 2, 20} },
            { id = "trim", class = "glow", position = {10, 2.1, 10}, size = {18, 0.2, 18} },
        },
    },
}
```

## Multi-Shape Layout

```lua
return {
    name = "Shapes",
    spec = {
        bounds = {20, 10, 20},
        origin = "floor-center",

        classes = {
            stone = { Material = "Granite", Color = {120, 115, 110} },
        },

        parts = {
            { id = "pedestal", class = "stone", position = {0, 1, 0}, size = {6, 2, 6} },
            { id = "column", class = "stone", shape = "cylinder", position = {0, 5, 0}, height = 6, radius = 1.5 },
            { id = "orb", class = "stone", shape = "sphere", position = {0, 9, 0}, radius = 1 },
        },
    },
}
```

## Production Workflow

```lua
local Lib = require(game.ReplicatedStorage.Lib)

-- 1. Build layout
local map = Lib.Factory.geometry(Lib.Layouts.BeverlyMansion)

-- 2. Preview compile (dry run)
local preview = Lib.Factory.compile(map, {
    strategy = "class",
    dryRun = true
})
print(string.format(
    "Compile would reduce %d parts to %d unions (%.0f%% reduction)",
    preview.originalParts,
    preview.compiledUnions,
    (1 - preview.compiledUnions / preview.originalParts) * 100
))

-- 3. Compile for production
local stats = Lib.Factory.compile(map, { strategy = "class" })

-- 4. Registry still works
local lawn = Lib.Factory.getInstance("lawn")
print("Lawn part:", lawn)
```
