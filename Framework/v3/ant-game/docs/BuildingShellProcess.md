# Building Shell Construction Process

A repeatable multi-step process for constructing modular, reusable building shells using the GeometrySpec declarative system.

## Overview

Building shells are constructed in layers, from the ground up. Each step builds on the previous, creating a hierarchical structure that can be composed, varied, and reused.

**Coordinate System:**
- Origin (0,0,0) at **southwest corner, ground level**
- +X = East (width/frontage)
- +Z = North (depth)
- +Y = Up (height)
- All positions are **corner-based** (southwest/bottom corner of each part)

## Process Steps

### Step 1: Define Footprint

Establish the building's ground-level dimensions.

```lua
local W = 40            -- Width (X, street frontage)
local D = 40            -- Depth (Z)
local WALL = 1          -- Wall thickness
```

The footprint defines the outer boundary. All subsequent geometry references these dimensions.

**Considerations:**
- Street frontage vs depth ratio
- Lot constraints
- Interior space requirements

---

### Step 2: Trace Footprint for Wall Runs

Identify wall placement based on the perimeter. Walls follow the four edges:

| Wall | Position | Size |
|------|----------|------|
| South (front) | X=0 to W, Z=0 | W × H × WALL |
| North (back) | X=0 to W, Z=D-WALL | W × H × WALL |
| West (left) | X=0, Z=0 to D | WALL × H × D |
| East (right) | X=W-WALL, Z=0 to D | WALL × H × D |

**Corner handling:** Walls overlap at corners. The N/S walls span full width; E/W walls span full depth. This creates solid corners without gaps.

---

### Step 3: Build Outer Walls

Create exterior walls as a container with children.

```lua
{ id = "GroundFloor", type = "container", position = {0, 0, 0},
  children = {
      -- Foundation/floor slab
      { id = "Floor", class = "foundation",
        position = {0, 0, 0},
        size = {W, 1, D} },

      -- Walls sit on floor (Y=1)
      { id = "Wall_South", class = "exterior",
        position = {0, 1, 0},
        size = {W, GF_H, WALL} },

      { id = "Wall_North", class = "exterior",
        position = {0, 1, D - WALL},
        size = {W, GF_H, WALL} },

      { id = "Wall_West", class = "exterior",
        position = {0, 1, 0},
        size = {WALL, GF_H, D} },

      { id = "Wall_East", class = "exterior",
        position = {W - WALL, 1, 0},
        size = {WALL, GF_H, D} },
  }}
```

**Key points:**
- Floor slab is 1 stud thick at Y=0
- Walls start at Y=1 (on top of floor)
- Use `class = "exterior"` for consistent material/color

---

### Step 4: Block Out Interior Logical Areas

Before building interior walls, define the logical spaces conceptually:

```
Ground Floor Layout (top-down view):
+------------------------------------------+
|                                          |
|              STORAGE                     | North
|                                          |
+------------------------------+-----------+
|                              | STAIRWELL |
|              SHOP            |           |
|                              |           |
+------------------------------+-----------+
        South (Street Front)
```

Define key dimensions:
```lua
local SHOP_D = 26       -- Shop depth (front area)
local STAIR_W = 10      -- Stairwell width (east side)
```

This planning phase prevents wall conflicts with openings and ensures logical flow.

---

### Step 5: Build Interior Walls

Add divider walls between logical areas. Interior walls:
- Start inside the exterior shell (offset by WALL thickness)
- Use `class = "interior"` for different material/color
- Run between logical boundaries

```lua
-- Shop/Back divider: runs E-W at Z=SHOP_D
{ id = "Wall_ShopBack", class = "interior",
  position = {WALL, 1, SHOP_D},
  size = {W - WALL*2, GF_H, WALL} },

-- Stairwell/Storage divider: runs N-S
{ id = "Wall_StairStorage", class = "interior",
  position = {W - WALL - STAIR_W, 1, SHOP_D + WALL},
  size = {WALL, GF_H, D - SHOP_D - WALL*2} },
```

**Positioning notes:**
- Subtract wall thickness from ends to avoid overlap with exterior
- Interior walls start at `WALL` (inside exterior) not `0`

---

### Step 6: Build Ceiling

The ceiling caps the current floor and becomes the next floor's foundation.

```lua
{ id = "Ceiling", class = "foundation",
  position = {0, 1 + GF_H, 0},
  size = {W, 1, D} },
```

**Position:** Y = floor_base + floor_height (e.g., 1 + 16 = 17)

The ceiling mirrors the footprint dimensions exactly.

---

### Step 7: Repeat for Additional Floors

Each floor is a separate container with its own local coordinate system.

```lua
local GF_H = 16         -- Ground floor height
local F2_H = 12         -- Second floor height
local F2_Y = 1 + GF_H + 1  -- Second floor base (18)

{ id = "Floor2", type = "container", position = {0, F2_Y, 0},
  children = {
      -- Walls use local Y=0 (relative to container)
      { id = "Wall_South", class = "exterior",
        position = {0, 0, 0},
        size = {W, F2_H, WALL} },

      -- Interior walls for this floor's layout
      { id = "Wall_Bedrooms", class = "interior",
        position = {W/2, 0, WALL},
        size = {WALL, F2_H, SHOP_D - WALL} },

      -- Ceiling
      { id = "Ceiling", class = "foundation",
        position = {0, F2_H, 0},
        size = {W, 1, D} },
  }}
```

**Container benefits:**
- Local coordinates (Y=0 is floor level, not ground level)
- Logical grouping in hierarchy
- Position cascade handles absolute positioning automatically

---

### Step 8: Build Roof

Roofs are typically separate layouts for reusability. Common roof types:

#### Hip Roof Structure

```
Top-down view:
+------------------------------------------+
|  NW Corner    Slope_N (wedge)   NE Corner|
|    (CW)                           (CW)   |
+----------+--------------------+----------+
|          |                    |          |
| Slope_W  |    RIDGE BOX       | Slope_E  |
| (wedge)  |                    | (wedge)  |
|          |                    |          |
+----------+--------------------+----------+
|  SW Corner    Slope_S (wedge)   SE Corner|
|    (CW)                           (CW)   |
+------------------------------------------+
```

**Components:**
1. **Ridge box** - Central horizontal box
2. **Slope wedges** - N/S/E/W faces (WedgePart)
3. **Corner wedges** - Diagonal corners (CornerWedgePart)

```lua
-- Ridge box
{ id = "Ridge", class = "roof",
  position = {ROOF_INSET, 0, ROOF_INSET},
  size = {W - ROOF_INSET*2, RIDGE_H, D - ROOF_INSET*2} },

-- South slope (front)
{ id = "Slope_S", class = "roof", shape = "wedge",
  position = {ROOF_INSET, 0, 0},
  size = {W - ROOF_INSET*2, RIDGE_H, ROOF_INSET},
  rotation = {0, 0, 0} },
```

**Wedge rotation gotchas:**
- Roblox wedges have specific orientation defaults
- Test rotations visually and compare scan outputs
- Document working rotation values for each orientation

---

### Step 9: Create Opening Geometry

Window and door openings are defined as separate geometry that will cut holes in walls.

```lua
-- Opening definitions (bright red for visualization)
classes = {
    opening = { Material = "Neon", Color = {255, 0, 0} },
},

parts = {
    -- Ground floor shop window
    { id = "GF_Window_1", class = "opening",
      position = {4, GF_Y + SILL_H, -0.5},  -- Z=-0.5 extends through wall
      size = {WIN_W, WIN_H, WALL + 1} },    -- Depth exceeds wall thickness

    -- Door (no sill)
    { id = "GF_Door", class = "opening",
      position = {30, GF_Y, -0.5},
      size = {DOOR_W, DOOR_H, WALL + 1} },
}
```

**Opening placement:**
- Position openings to intersect target walls
- Z position slightly outside wall (-0.5) ensures clean cut
- Depth (Z size) exceeds wall thickness to cut completely through
- Sill height raises windows above floor level

**Variation strategy:** Create multiple opening layouts (Front_A, Front_B) that can be swapped via xref.

---

### Step 10: Cut CSG Holes

Use Roblox CSG to subtract opening geometry from walls.

```lua
-- Find walls and openings
local walls = {}
local openings = {}

for _, part in ipairs(building:GetDescendants()) do
    if part:IsA("BasePart") then
        if part.Name:find("Wall_South") then
            table.insert(walls, part)
        elseif part.Name:find("Window") or part.Name:find("Door") then
            table.insert(openings, part)
        end
    end
end

-- Cut each opening from intersecting walls
for _, opening in ipairs(openings) do
    for i, wall in ipairs(walls) do
        -- Check intersection (Y overlap)
        if opening intersects wall then
            local success, result = pcall(function()
                return wall:SubtractAsync({opening})
            end)

            if success and result then
                result.Name = wall.Name
                result.Parent = wall.Parent
                wall:Destroy()
                walls[i] = result  -- Update reference
            end
        end
    end
    opening:Destroy()  -- Clean up after cutting
end
```

**CSG considerations:**
- `SubtractAsync` is asynchronous - wrap in pcall
- Update wall references after subtraction for subsequent openings
- Copy attributes (FactoryId, FactoryClass) to result
- Destroy opening parts after cutting

---

## Modular Composition

### Layout Structure

Separate concerns into individual layout files:

```
Layouts/
  FlemishShop1.lua           -- Master package (composes all)
  FlemishShop1_BaseShell.lua -- GF + F2 structure
  FlemishShop1_Roof_Hip.lua  -- Hip roof
  FlemishShop1_Openings_Front.lua    -- Facade variation A
  FlemishShop1_Openings_Front_B.lua  -- Facade variation B
```

### Master Layout with xrefs

```lua
local BaseShell = require(script.Parent.FlemishShop1_BaseShell)
local Roof_Hip = require(script.Parent.FlemishShop1_Roof_Hip)
local Openings = require(script.Parent.FlemishShop1_Openings_Front)

return {
    name = "FlemishShop1",
    spec = {
        origin = "corner",
        parts = {
            { id = "Shell", xref = BaseShell, position = {0, 0, 0} },
            { id = "Roof", xref = Roof_Hip, position = {0, ROOF_Y, 0} },
            { id = "Openings", xref = Openings, position = {0, 0, 0} },
        },
    },
}
```

### Swapping Components

Create variations by changing xrefs:

```lua
-- Shop with hip roof and facade A
{ id = "Openings", xref = Openings_Front }

-- Shop with facade B (more windows, no door)
{ id = "Openings", xref = Openings_Front_B }

-- Shop with gable roof
{ id = "Roof", xref = Roof_Gable, position = {0, ROOF_Y, 0} }
```

---

## Class-Based Styling

Define material and color classes for consistency:

```lua
classes = {
    foundation = { Material = "Concrete", Color = {140, 135, 130} },
    exterior = { Material = "SmoothPlastic", Color = {180, 175, 165} },
    interior = { Material = "SmoothPlastic", Color = {220, 215, 205} },
    roof = { Material = "SmoothPlastic", Color = {80, 60, 50} },
    opening = { Material = "Neon", Color = {255, 0, 0} },  -- Debug visibility
},
```

Classes cascade: parent → defaults → base[type] → classes → id → inline

---

## Common Dimensions Reference

| Element | Typical Value | Notes |
|---------|---------------|-------|
| Wall thickness | 1 stud | Consistent throughout |
| Floor slab | 1 stud | Foundation and ceilings |
| GF height | 14-18 studs | Commercial spaces taller |
| Upper floor height | 10-14 studs | Residential shorter |
| Window sill | 2-4 studs | Above floor level |
| Door height | 8-10 studs | Full height from floor |
| Roof inset | 2-4 studs | Overhang distance |

---

## Debugging Tips

1. **Scan layouts** to see resolved values:
   ```lua
   Factory.Geometry.scanPrint(Lib.Layouts.FlemishShop1)
   ```

2. **Use neon material** for opening placeholders during development

3. **Build incrementally** - test each floor before adding the next

4. **Compare scans** - scan both layout and built model to catch discrepancies

5. **Check parent chains** - xref issues often stem from incorrect parent references

---

## Process Summary

1. **Footprint** → Define W, D, WALL constants
2. **Wall runs** → Map perimeter to wall positions
3. **Outer walls** → Container with floor + 4 exterior walls
4. **Interior blocking** → Plan room layout, define divider positions
5. **Interior walls** → Build dividers between logical areas
6. **Ceiling** → Cap floor at Y = base + height
7. **Additional floors** → Repeat steps 3-6 in new container
8. **Roof** → Build as separate layout, attach via xref
9. **Openings** → Define window/door geometry in separate layout
10. **CSG holes** → Subtract openings from walls

This process scales from simple single-room structures to complex multi-story buildings with varied facades and roof styles.
