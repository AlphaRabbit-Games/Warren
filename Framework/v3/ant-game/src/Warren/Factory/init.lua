--[[
    Warren Framework v2
    Factory - Declarative Instance Builder

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    Factory builds Roblox instances from declarative specs. It supports multiple
    domains:

    - geometry: 3D Parts (map zones, turret bodies, static structures)
    - gui: 2D GuiObjects (HUD, menus, dialogs) [planned]

    All domains share the same spec format and ClassResolver cascade.

    ============================================================================
    USAGE
    ============================================================================

    ```lua
    local Lib = require(game.ReplicatedStorage.Warren)
    local Factory = Lib.Factory

    -- Build geometry from a layout
    local zone = Factory.geometry(Lib.Layouts.DefenseZone)

    -- Build geometry from inline spec
    local turret = Factory.geometry({
        name = "Turret",
        spec = {
            bounds = {4, 6, 4},
            parts = { ... },
            classes = { ... },
        },
    })

    -- Access built parts
    local base = Factory.Geometry.getInstance("base")
    ```

    ============================================================================
    SPEC FORMAT
    ============================================================================

    Layout format (recommended for saved layouts):
    ```lua
    {
        name = "MyLayout",
        spec = { bounds, parts, classes, ... }
    }
    ```

    Raw spec format (for inline use):
    ```lua
    {
        bounds = {w, h, d},
        parts = { ... },
        classes = { ... },
    }
    ```

--]]

local Factory = {
    _VERSION = "1.0.0",
}

-- Domain modules
Factory.Geometry = require(script.Geometry)

-- Scanner for visual → config workflow
Factory.Scanner = require(script.Scanner)

-- Compiler for geometry optimization
Factory.Compiler = require(script.Compiler)

--------------------------------------------------------------------------------
-- PUBLIC API
--------------------------------------------------------------------------------

--[[
    Build 3D geometry from a spec.

    @param layout: Layout { name, spec } or raw spec
    @param parent: Optional parent (default: workspace)
    @return: Part container with child geometry
--]]
function Factory.geometry(layout, parent)
    return Factory.Geometry.build(layout, parent)
end

--[[
    Build GUI from a spec. [Planned]

    @param layout: Layout { name, spec } or raw spec
    @param parent: Optional parent (default: PlayerGui)
    @return: ScreenGui or Frame
--]]
function Factory.gui(layout, parent)
    error("[Factory] GUI domain not yet implemented")
end

--[[
    Compile geometry by merging parts into unions.
    Reduces draw calls while preserving visual appearance.

    @param container: Part container from Factory.geometry()
    @param options: {
        strategy = "class" | "material" | "aggressive" | "spatial",
        chunkSize = number (for spatial strategy),
        preserveRegistry = boolean (default true),
        collisionFidelity = "Hull" | "Box" | "Precise",
        dryRun = boolean (preview without modifying),
    }
    @return: Stats table {
        originalParts = number,
        compiledUnions = number,
        ungroupedParts = number,
        triangleEstimate = number,
    }

    Strategies:
    - "class": Group by FactoryClass. Safest - classes already define properties.
    - "material": Group by Material + Color + Transparency. Default.
    - "aggressive": Group by Material + Transparency. Loses color variety.
    - "spatial": Grid chunking + material. Good for streaming.
--]]
function Factory.compile(container, options)
    return Factory.Compiler.compile(container, options)
end

--------------------------------------------------------------------------------
-- REGISTRY ACCESS (shortcuts)
--------------------------------------------------------------------------------

--[[
    Clear all registries.
--]]
function Factory.clear()
    Factory.Geometry.clear()
    -- Factory.GUI.clear() -- when implemented
end

--[[
    Get a built element by ID from any domain.

    @param selector: ID string (with or without # prefix)
    @param domain: Optional domain hint ("geometry", "gui")
    @return: Registry entry or nil
--]]
function Factory.get(selector, domain)
    if domain == "gui" then
        -- return Factory.GUI.get(selector)
        return nil
    end
    -- Default to geometry
    return Factory.Geometry.get(selector)
end

--[[
    Get the Roblox instance for an element.

    @param selector: ID string
    @param domain: Optional domain hint
    @return: Instance or nil
--]]
function Factory.getInstance(selector, domain)
    local entry = Factory.get(selector, domain)
    return entry and entry.instance or nil
end

--------------------------------------------------------------------------------
-- SCANNER API (delegate to Scanner)
--------------------------------------------------------------------------------

--[[
    Scan geometry and output layout code.

    Automatically resolves the original layout from Lib.Layouts using
    the container's name for round-trip diffing:
        Factory.scan(model)  -- Looks up Lib.Layouts[model.Name]

    Or pass layout/classes explicitly:
        Factory.scan(model, { layout = myLayout })
        Factory.scan(model, { classes = myClasses })

    @param container: Model or Part containing geometry
    @param options: {
        layout = nil,   -- Original layout (auto-resolved from name if nil)
        classes = nil,  -- Or pass classes directly
    }
--]]
function Factory.scan(container, options)
    options = options or {}

    -- Auto-resolve layout from Lib.Layouts if not provided
    if not options.layout and not options.classes then
        local success, Layouts = pcall(function()
            return require(script.Parent.Layouts)
        end)
        if success and Layouts then
            local layoutName = container.Name
            if Layouts[layoutName] then
                options.layout = Layouts[layoutName]
            end
        end
    end

    local code = Factory.Scanner.scanToCode(container, options)

    print("\n" .. string.rep("=", 70))
    print("-- Factory Scanner Output for: " .. container.Name)
    print("-- Paste into: Lib/Layouts/" .. container.Name .. ".lua")
    print(string.rep("=", 70))
    print(code)
    print(string.rep("=", 70) .. "\n")

    return code
end

--[[
    Scan a named area and output layout code.
--]]
function Factory.scanArea(areaName, container, options)
    container = container or workspace
    options = options or {}

    local config = Factory.Scanner.scanArea(areaName, container, options)
    if not config then
        return nil
    end

    local code = Factory.Scanner.generateCode(config, options)

    print("\n" .. string.rep("=", 70))
    print("-- Factory Scanner Output for area: " .. areaName)
    print("-- Paste into: Lib/Layouts/" .. areaName .. ".lua")
    print(string.rep("=", 70))
    print(code)
    print(string.rep("=", 70) .. "\n")

    return code
end

--[[
    Mirror an area for preview.
--]]
function Factory.mirror(areaName, container, options)
    return Factory.Scanner.mirrorArea(areaName, container, options)
end

--[[
    List all scannable areas.
--]]
function Factory.listAreas(container)
    local areas = Factory.Scanner.findAreas(container or workspace)

    print("\n=== Scannable Areas ===")
    if #areas == 0 then
        print("  No areas found.")
        print("  Tag a part with GeometrySpecTag = 'area'")
    else
        for _, area in ipairs(areas) do
            local size = area.part.Size
            print(string.format("  %s: bounds {%.1f, %.1f, %.1f} at %s",
                area.name,
                size.X, size.Y, size.Z,
                tostring(area.part.Position)
            ))
        end
    end
    print("=======================\n")

    return areas
end

return Factory
