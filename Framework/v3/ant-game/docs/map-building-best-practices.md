# Map Building Best Practices

Lessons learned from building the Lichtervelde Cathedral using Factory/GeometrySpec.

## What Went Right

### 1. Declarative Geometry System
- Constants at the top for dimensions made iteration easy
- Changing `NAVE_LENGTH` propagated everywhere automatically
- Classes for consistent materials/colors across parts

### 2. CSG Holes (SubtractAsync)
- Window and door cutouts worked well
- `CollisionFidelity.PreciseConvexDecomposition` gave accurate walkable collision
- Holes defined relative to part center - intuitive positioning

### 3. Hollow Construction
- Building the tower as 4 walls instead of a solid block with holes cut through
- Easier to reason about, more reliable CSG results

### 4. WedgeParts for Roofs
- Simple and effective for pitched roofs
- Rotation rules: high edge at local +Z, low edge at local -Z

### 5. Quick Iteration Loop
```lua
if workspace:FindFirstChild("Name") then workspace.Name:Destroy() end
local Lib = require(game.ReplicatedStorage.Lib)
Lib.Layouts.clearCache()
local model = Lib.Factory.geometry(Lib.Layouts.LayoutName)
```

### 6. Compiler for Performance
- Grouped parts by class, reduced draw calls
- Strategy "class" preserves semantic meaning while optimizing

---

## What Went Wrong

### 1. Thin Parts Break CSG
- Parts under ~1 stud thick cause `UnionAsync` to fail with "Unable to cast to Array"
- **Fix:** Keep all parts at least 1-2 studs thick

### 2. WedgeParts Can't Be Compiled
- `UnionAsync` fails on WedgeParts
- **Fix:** Compiler now skips WedgeParts automatically

### 3. Y Offset Positioning
- Tried multiple approaches to raise cathedral onto grass mound
- Adding offset to spec, baking into positions, setting CFrame - none worked reliably
- **Fix:** Manual positioning in Studio, then scan to capture

### 4. Terrain Positioning
- `FillBlock` filled terrain inside the church (both at Y=0)
- Confusing coordinate system
- **Fix:** Use parts with Grass material instead of Terrain for small areas

### 5. Overcomplicated Lawn
- My 40-part lawn with cylinders everywhere vs user's 6-part solution
- **Lesson:** Simple > Complex. Start minimal, add only what's needed

### 6. Trim Through Interior
- Positioned trim at wall coordinates instead of exterior
- **Fix:** Think about exterior footprint, position trim outside wall faces

### 7. Rojo Sync Issues
- Changes not always reflected in Studio
- **Fix:** `Lib.Layouts.clearCache()` + destroy existing model + restart Rojo if stuck

---

## Best Practices

### Design Phase
1. **Gather reference images** - Top-down and elevations help
2. **Define constants first** - Dimensions, colors, materials at top of file
3. **Use `floor-center` origin** - Most intuitive for buildings
4. **Plan hollow construction** - Don't rely on cutting through solid blocks

### Building Phase
1. **Minimum 1-2 stud thickness** - For CSG compatibility
2. **Use classes** - Consistent styling, easy to change later
3. **Test frequently** - Use the quick iteration loop above
4. **Build incrementally** - Walls first, then roofs, then details

### Organic/Landscape Elements
1. **Manual Studio work** - Better for irregular shapes like lawns
2. **Keep it simple** - A cylinder + 2 wedges beats 40 parts
3. **Scan when done** - Capture manual work into layout files

### Optimization
1. **Compile structural elements** - Walls, trim benefit most
2. **Skip decorative elements** - WedgeParts (roofs) can't be compiled anyway
3. **Use `dryRun` first** - See what compiler will do before committing

### Positioning
1. **Don't fight the system** - If code positioning isn't working, do it manually
2. **Scan to capture** - `GeometrySpec.scanArea()` captures final positions
3. **Use absolute Y** - Bake elevation into layout rather than offsetting at runtime

---

## Code Patterns

### Layout File Structure
```lua
--[[
    LayoutName
    Description
--]]

-- Constants
local WIDTH = 100
local HEIGHT = 50
local COLOR_WALL = {180, 130, 100}

return {
    name = "LayoutName",
    spec = {
        origin = "floor-center",
        bounds = {WIDTH, HEIGHT, DEPTH},

        classes = {
            wall = { Color = COLOR_WALL, Material = "Brick" },
        },

        parts = {
            { id = "Wall_1", class = "wall",
              position = {0, HEIGHT/2, 0},
              size = {4, HEIGHT, 100} },
        },
    },
}
```

### Holes Definition
```lua
{ id = "Wall_With_Window", class = "wall",
  position = {0, 25, 0},
  size = {4, 50, 100},
  holes = {
    { position = {0, 5, 0}, size = {6, 20, 10} },  -- relative to part center
  }},
```

### Test Command Template
```lua
if workspace:FindFirstChild("MODEL") then workspace.MODEL:Destroy() end
local Lib = require(game.ReplicatedStorage.Lib)
Lib.Layouts.clearCache()
local model = Lib.Factory.geometry(Lib.Layouts.LAYOUT)
-- Optional: compile
local stats = Lib.Factory.Compiler.compile(model, { strategy = "class" })
print("Compiled:", stats.originalParts, "->", stats.compiledUnions)
```

---

## Tools Comparison

| Task | Use Factory | Use Studio |
|------|-------------|------------|
| Structural walls | ✓ | |
| Repetitive elements | ✓ | |
| Precise dimensions | ✓ | |
| Organic shapes | | ✓ |
| Terrain/landscaping | | ✓ |
| Fine-tuning positions | | ✓ |
| Quick prototyping | | ✓ |
| Final production assets | ✓ (scan from Studio) | |

---

## Debugging Tips

1. **Parts not appearing:** Check Y position - might be underground
2. **CSG failing:** Check part thickness, remove thin parts
3. **Collision not working:** Set `CanCollide = true` in class, use PreciseConvexDecomposition
4. **Changes not reflected:** Clear cache, destroy model, restart Rojo
5. **Roofs wrong orientation:** WedgePart high edge is at +Z local

