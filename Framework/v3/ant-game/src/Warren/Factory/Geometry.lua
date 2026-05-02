--[[
    Warren Framework v2
    Geometry.lua - Geometry Adapter for the Resolver System

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    Geometry is an adapter that uses the generic Resolver pattern to build
    Roblox Parts from declarative definitions.

    The Resolver is a formula solver:
        1. Create stubs (workspace for solutions)
        2. Order by dependency (solve parents first)
        3. Apply cascade formula (compute properties)
        4. Resolve references (substitute values)

    See docs/RESOLVER.md for the full mental model.

    ============================================================================
    BUILD PHASES
    ============================================================================

    RESOLVE Phase 1: Create stubs for all parts
    RESOLVE Phase 2: Populate values in tree order
    INSTANTIATE:     Create Roblox Parts from resolved table

    ============================================================================
    CASCADE FORMULA
    ============================================================================

    Properties are computed using ClassResolver:
        parent → defaults → base[type] → classes → id → inline

    Tree inheritance (parent → child) is handled here.
    Per-element cascade is delegated to ClassResolver.

    ============================================================================
    REFERENCES
    ============================================================================

    Function-based layouts enable references between parts:

        return function(parts, parent)
            return {
                parts = {
                    Floor1 = {
                        geometry = { origin = {0, 0, 0}, scale = {80, 18, 65} },
                    },
                    Floor2 = {
                        parent = "Floor1",
                        geometry = {
                            -- Use parent.Size for direct parent reference
                            origin = {0, parent.Size[2], 0},
                            scale = {80, 18, 65},
                        },
                    },
                    -- Siblings can reference each other by name
                    Floor3 = {
                        parent = "Floor1",
                        geometry = {
                            origin = {0, parts.Floor2.Size[2] * 2, 0},
                            scale = {80, 18, 65},
                        },
                    },
                },
            }
        end

    Available references:
        parent.Size[1|2|3]          - Parent's scale X/Y/Z (requires parent field)
        parent.Position[1|2|3]      - Parent's origin X/Y/Z
        parent.Rotation[1|2|3]      - Parent's rotation X/Y/Z
        parts.{id}.Size[1|2|3]      - Named part's scale X/Y/Z
        parts.{id}.Position[1|2|3]  - Named part's origin X/Y/Z
        parts.{id}.Rotation[1|2|3]  - Named part's rotation X/Y/Z

    Arithmetic supported:
        parent.Size[2] + 10
        parts.Wall.Size[1] * 0.5

    ============================================================================
    ARRAYS
    ============================================================================

    Generate multiple copies of a part at regular intervals:

    Linear array (single direction):
        { id = "pillar", position = {0, 0, 0}, size = {2, 10, 2},
          array = { count = 4, offset = {10, 0, 0} }
        }
        -- Generates: pillar_1, pillar_2, pillar_3, pillar_4

    Grid array (multiple axes):
        { id = "tile", position = {0, 0, 0}, size = {4, 1, 4},
          array = {
            x = { count = 5, spacing = 4 },
            z = { count = 3, spacing = 4 }
          }
        }
        -- Generates: tile_1_1 through tile_5_3 (15 tiles)

    3D grid:
        { id = "cube", position = {0, 0, 0}, size = {2, 2, 2},
          array = {
            x = { count = 3, spacing = 4 },
            y = { count = 2, spacing = 4 },
            z = { count = 3, spacing = 4 }
          }
        }
        -- Generates: cube_1_1_1 through cube_3_2_3 (18 cubes)

    ============================================================================
    XREF (LAYOUT COMPOSITION)
    ============================================================================

    Import another layout as a child, applying transforms:

        local SuburbanHouse = require(path.to.Layouts.SuburbanHouse)

        parts = {
            { id = "house1", xref = SuburbanHouse, position = {0, 0, 0} },
            { id = "house2", xref = SuburbanHouse, position = {30, 0, 0}, rotation = {0, 180, 0} },
        }

    Results in:
        house1           - Container (invisible transform node)
        house1.Foundation - Imported part
        house1.Walls      - Imported part
        house1.Roof       - Imported part
        house2           - Container (rotated 180 degrees)
        house2.Foundation - Inherits rotation from container
        ...

    Properties cascade from container to imported parts (parent provides base,
    children override). If container has class = "weathered", imported parts
    inherit that class (combined with their own classes).

    Xrefs can be nested - an imported layout can itself contain xrefs.

--]]

--##############################################################################
-- PHASE 1: LOAD
--##############################################################################

local Geometry = {}

-- State
local registry = {}
local Styles = nil
local ClassResolver = nil

-- Forward declarations (defined in PHASE 2)
local getStyles
local getClassResolver
local merge
local deepCopy
local normalizeVector
local buildTreeOrder
local resolvePartProperties
local resolvePartGeometry
local resolveReferences
local toColor3
local applyProperties
local createPart
local registerPart
local valueToCode
local tableToCode
local createRefMarker
local createPropertyProxy
local createPartStub

--##############################################################################
-- PHASE 2: DEFINE
--##############################################################################

--------------------------------------------------------------------------------
-- Dependencies
--------------------------------------------------------------------------------

getStyles = function()
    if not Styles then
        local success, result = pcall(function()
            return require(script.Parent.Parent.Styles)
        end)
        if success then
            Styles = result
        else
            warn("[Geometry] Could not load Styles:", result)
            Styles = { base = {}, classes = {}, ids = {} }
        end
    end
    return Styles
end

getClassResolver = function()
    if not ClassResolver then
        local success, result = pcall(function()
            return require(script.Parent.Parent.ClassResolver)
        end)
        if success then
            ClassResolver = result
        else
            warn("[Geometry] Could not load ClassResolver:", result)
            ClassResolver = nil
        end
    end
    return ClassResolver
end

--------------------------------------------------------------------------------
-- Utilities
--------------------------------------------------------------------------------

merge = function(target, source)
    if not source then return target end
    for k, v in pairs(source) do
        target[k] = v
    end
    return target
end

deepCopy = function(t)
    if type(t) ~= "table" then return t end
    local copy = {}
    for k, v in pairs(t) do
        copy[k] = deepCopy(v)
    end
    return copy
end

parseClasses = function(classStr)
    if not classStr or classStr == "" then return {} end
    local classes = {}
    for class in classStr:gmatch("%S+") do
        table.insert(classes, class)
    end
    return classes
end

normalizeVector = function(v)
    if not v then return {0, 0, 0} end
    if v.x then
        return {v.x, v.y, v.z}
    end
    return {v[1] or 0, v[2] or 0, v[3] or 0}
end

--------------------------------------------------------------------------------
-- Reference System (metatables for lazy property access)
--------------------------------------------------------------------------------

--[[
    Reference markers capture property access for deferred resolution.

    Usage in layouts:
        return function(parts)
            return {
                parts = {
                    Floor2 = {
                        geometry = {
                            origin = {0, parts.Floor1.Size[2], 0},  -- Reference!
                        },
                    },
                },
            }
        end

    When parts.Floor1.Size[2] is accessed, it returns a marker:
        { __isRef = true, partId = "Floor1", property = "Size", index = 2 }

    During resolution, markers are replaced with actual values.
--]]

-- Expression marker for arithmetic on references
local ExprMT = {}

local function createExprMarker(op, left, right)
    return setmetatable({
        __isExpr = true,
        op = op,
        left = left,
        right = right,
    }, ExprMT)
end

-- Arithmetic metamethods for expressions
ExprMT.__add = function(a, b) return createExprMarker("+", a, b) end
ExprMT.__sub = function(a, b) return createExprMarker("-", a, b) end
ExprMT.__mul = function(a, b) return createExprMarker("*", a, b) end
ExprMT.__div = function(a, b) return createExprMarker("/", a, b) end
ExprMT.__unm = function(a) return createExprMarker("*", a, -1) end

-- Reference marker with arithmetic support
local RefMT = {}
RefMT.__add = function(a, b) return createExprMarker("+", a, b) end
RefMT.__sub = function(a, b) return createExprMarker("-", a, b) end
RefMT.__mul = function(a, b) return createExprMarker("*", a, b) end
RefMT.__div = function(a, b) return createExprMarker("/", a, b) end
RefMT.__unm = function(a) return createExprMarker("*", a, -1) end

createRefMarker = function(partId, property, index)
    return setmetatable({
        __isRef = true,
        partId = partId,
        property = property,  -- "Size", "Position", "Rotation"
        index = index,        -- 1, 2, 3 (X, Y, Z)
    }, RefMT)
end

createPropertyProxy = function(partId, property)
    -- Returns a proxy that captures index access (e.g., Size[2])
    return setmetatable({}, {
        __index = function(_, index)
            if type(index) == "number" and index >= 1 and index <= 3 then
                return createRefMarker(partId, property, index)
            end
            return nil
        end,
    })
end

createPartStub = function(partId)
    -- Returns a stub that captures property access (e.g., Floor1.Size)
    return setmetatable({}, {
        __index = function(_, property)
            -- Mirror Roblox property names
            if property == "Size" or property == "Position" or property == "Rotation" then
                return createPropertyProxy(partId, property)
            end
            return nil
        end,
    })
end

function Geometry.createPartsProxy()
    -- Returns a proxy table that generates part stubs on access
    return setmetatable({}, {
        __index = function(t, partId)
            local stub = createPartStub(partId)
            rawset(t, partId, stub)  -- Cache for repeated access
            return stub
        end,
    })
end

function Geometry.createParentProxy()
    -- Returns a proxy that captures parent property access
    -- parent.Size[2] returns marker { __isRef = true, partId = "__parent__", property = "Size", index = 2 }
    -- The "__parent__" is resolved to actual parent ID during resolution phase
    return setmetatable({}, {
        __index = function(_, property)
            if property == "Size" or property == "Position" or property == "Rotation" then
                return createPropertyProxy("__parent__", property)
            end
            return nil
        end,
    })
end

resolveReferences = function(value, resolvedParts, parentId)
    if type(value) ~= "table" then
        return value
    end

    -- Check if this is a reference marker
    if value.__isRef then
        -- Resolve __parent__ to actual parent ID
        local targetId = value.partId
        if targetId == "__parent__" then
            if not parentId or parentId == "root" then
                warn("[Geometry] Cannot use parent reference - part has no parent")
                return 0
            end
            targetId = parentId
        end

        local target = resolvedParts[targetId]
        if not target then
            warn("[Geometry] Unresolved reference to part:", targetId)
            return 0
        end

        local prop = value.property
        local idx = value.index

        if prop == "Size" then
            return target.geometry.scale[idx] or 0
        elseif prop == "Position" then
            return target.geometry.origin[idx] or 0
        elseif prop == "Rotation" then
            return target.geometry.rotation[idx] or 0
        end

        warn("[Geometry] Unknown reference property:", prop)
        return 0
    end

    -- Check if this is an expression marker
    if value.__isExpr then
        local left = resolveReferences(value.left, resolvedParts, parentId)
        local right = resolveReferences(value.right, resolvedParts, parentId)

        if value.op == "+" then return left + right end
        if value.op == "-" then return left - right end
        if value.op == "*" then return left * right end
        if value.op == "/" then return left / right end

        warn("[Geometry] Unknown expression operator:", value.op)
        return 0
    end

    -- Recurse into table
    local result = {}
    for k, v in pairs(value) do
        result[k] = resolveReferences(v, resolvedParts, parentId)
    end
    return result
end

--------------------------------------------------------------------------------
-- Registry
--------------------------------------------------------------------------------

registerPart = function(id, instance, entry)
    if not id then return end
    registry[id] = {
        id = id,
        instance = instance,
        entry = entry,
    }
end

function Geometry.get(selector)
    if not selector then return nil end
    local id = selector:match("^#?(.+)$")
    return registry[id]
end

function Geometry.getInstance(selector)
    local entry = Geometry.get(selector)
    return entry and entry.instance or nil
end

function Geometry.clear()
    registry = {}
end

--------------------------------------------------------------------------------
-- Resolve: Build Tree Order
--------------------------------------------------------------------------------

buildTreeOrder = function(parts)
    local depths = {}

    local function getDepth(id, visited)
        if depths[id] then return depths[id] end
        if visited[id] then
            warn("[Geometry] Circular parent reference:", id)
            return 0
        end

        visited[id] = true
        local part = parts[id]
        if not part or not part.parent or part.parent == "root" then
            depths[id] = 0
            return 0
        end

        local parentDepth = getDepth(part.parent, visited)
        depths[id] = parentDepth + 1
        return depths[id]
    end

    for id, _ in pairs(parts) do
        getDepth(id, {})
    end

    local order = {}
    for id, depth in pairs(depths) do
        table.insert(order, {id = id, depth = depth})
    end
    table.sort(order, function(a, b) return a.depth < b.depth end)

    return order
end

--------------------------------------------------------------------------------
-- Resolve: Properties Cascade
--------------------------------------------------------------------------------

--[[
    Properties cascade uses ClassResolver for per-element resolution.
    Tree inheritance (parent → child) is handled here.

    Full cascade order:
        1. parent properties (tree inheritance)
        2. defaults (applied to all)
        3. base[type] (by element type)
        4. classes (in order)
        5. id (by element ID)
        6. inline properties
--]]
resolvePartProperties = function(partDef, parentResolved, styles)
    local resolved = {}

    -- 1. Inherit from parent (tree-level, handled here)
    if parentResolved and parentResolved.properties then
        merge(resolved, deepCopy(parentResolved.properties))
    end

    -- 2-6. Use ClassResolver for the rest of the cascade
    local resolver = getClassResolver()
    if resolver then
        -- Build definition for ClassResolver
        local definition = {
            type = partDef.shape == "wedge" and "WedgePart" or "Part",
            class = partDef.class,
            id = partDef.id,
        }

        -- Add inline properties (non-reserved keys from partDef)
        if partDef.properties then
            for k, v in pairs(partDef.properties) do
                definition[k] = v
            end
        end

        -- Resolve using ClassResolver
        local cascaded = resolver.resolve(definition, styles, {
            reservedKeys = {
                -- Geometry-specific reserved keys
                parent = true,
                geometry = true,
                shape = true,
                class = true,
                id = true,
                type = true,
                name = true,
                properties = true,
            }
        })

        merge(resolved, cascaded)
    else
        -- Fallback: manual cascade if ClassResolver not available
        local partType = partDef.shape == "wedge" and "WedgePart" or "Part"
        if styles.base and styles.base[partType] then
            merge(resolved, deepCopy(styles.base[partType]))
        end

        if partDef.class then
            for class in partDef.class:gmatch("%S+") do
                if styles.classes and styles.classes[class] then
                    merge(resolved, deepCopy(styles.classes[class]))
                end
            end
        end

        if partDef.id and styles.ids and styles.ids[partDef.id] then
            merge(resolved, deepCopy(styles.ids[partDef.id]))
        end

        if partDef.properties then
            merge(resolved, deepCopy(partDef.properties))
        end
    end

    return resolved
end

--------------------------------------------------------------------------------
-- Resolve: Geometry Transform
--------------------------------------------------------------------------------

resolvePartGeometry = function(partDef, parentResolved, resolvedParts, parentId)
    -- Support both formats:
    --   1. geometry = { origin = {...}, scale = {...} }  (function-based layouts)
    --   2. position = {...}, size = {...}  (array-based layouts like BeverlyMansion)
    local geom = partDef.geometry or {}

    -- Merge in position/size/rotation if using array format
    if partDef.position then
        geom = {
            origin = partDef.position,
            scale = partDef.size,
            rotation = partDef.rotation,
            -- Also support cylinder/sphere dimensions
            height = partDef.height,
            radius = partDef.radius,
        }
    end

    -- Resolve any reference markers in geometry values
    -- Pass parentId so parent.Size[2] references work
    local resolvedGeom = resolveReferences(geom, resolvedParts, parentId)

    local origin = normalizeVector(resolvedGeom.origin)
    local scale = normalizeVector(resolvedGeom.scale or resolvedGeom.dims)
    local rotation = normalizeVector(resolvedGeom.rotation)

    -- Handle cylinder/sphere dimensions
    if resolvedGeom.height or resolvedGeom.radius then
        local height = resolvedGeom.height or 4
        local radius = resolvedGeom.radius or 2
        -- Cylinder: Size is (height, diameter, diameter) in Roblox
        -- Sphere: Size is (diameter, diameter, diameter)
        if partDef.shape == "sphere" then
            scale = {radius * 2, radius * 2, radius * 2}
        elseif partDef.shape == "cylinder" then
            scale = {height, radius * 2, radius * 2}
        end
    end

    if scale[1] == 0 and scale[2] == 0 and scale[3] == 0 then
        scale = {4, 4, 4}
    end

    -- Accumulate origin from parent
    if parentResolved and parentResolved.geometry then
        local parentOrigin = parentResolved.geometry.origin or {0, 0, 0}
        origin = {
            origin[1] + parentOrigin[1],
            origin[2] + parentOrigin[2],
            origin[3] + parentOrigin[3],
        }
    end

    return {
        origin = origin,
        scale = scale,
        rotation = rotation,
    }
end

--------------------------------------------------------------------------------
-- Parts Format Normalization
--------------------------------------------------------------------------------

--[[
    Normalize parts table to keyed format.

    Handles two input formats:
        Array:  { { id = "Floor", ... }, { id = "Ceiling", ... } }
        Keyed:  { Floor = {...}, Ceiling = {...} }

    Always returns keyed format: { Floor = {...}, Ceiling = {...} }

    @param parts: Parts table (array or keyed)
    @return: Keyed parts table
--]]
local function normalizeParts(parts)
    if not parts then return {} end

    -- Check if it's already keyed format (first key is not a number)
    local firstKey = next(parts)
    if type(firstKey) == "string" then
        return parts  -- Already keyed
    end

    -- Convert array format to keyed format
    local keyed = {}
    for _, partDef in ipairs(parts) do
        local id = partDef.id
        if id then
            keyed[id] = partDef
        else
            -- Generate ID if missing
            local genId = "part_" .. tostring(_)
            partDef.id = genId
            keyed[genId] = partDef
        end
    end
    return keyed
end

--------------------------------------------------------------------------------
-- Container Flattening (Hierarchical Organization)
--------------------------------------------------------------------------------

--[[
    Flatten containers with children into a flat parts table.

    Containers are organizational nodes with no geometry:
        { id = "GroundFloor", type = "container", position = {0, 0, 0},
          children = {
              { id = "Floor", class = "foundation", ... },
              { id = "Walls", type = "container", children = { ... } },
          }}

    Becomes:
        GroundFloor = { _isContainer = true, position = {0, 0, 0} }
        GroundFloor.Floor = { parent = "GroundFloor", class = "foundation", ... }
        GroundFloor.Walls = { _isContainer = true, parent = "GroundFloor" }
        GroundFloor.Walls.Wall_South = { parent = "GroundFloor.Walls", ... }

    Position offsets are NOT accumulated here - that's handled by resolvePartGeometry
    which walks the tree and accumulates parent origins.

    @param parts: Keyed parts table (from normalizeParts)
    @param parentId: Parent container ID (for recursion)
    @param parentClass: Parent class to cascade
    @return: Flattened keyed parts table
--]]
local function flattenContainers(parts, parentId, parentClass)
    local flattened = {}

    for id, partDef in pairs(parts) do
        local fullId = parentId and (parentId .. "." .. id) or id
        local isContainer = partDef.type == "container"
        local children = partDef.children

        -- Cascade class from parent if not specified
        local class = partDef.class or parentClass

        if isContainer and children then
            -- Create container node (no geometry)
            local containerNode = {}
            for k, v in pairs(partDef) do
                if k ~= "children" and k ~= "type" then
                    containerNode[k] = v
                end
            end
            containerNode._isContainer = true
            -- Keep position as-is - tree accumulation handles offsets
            if parentId then
                containerNode.parent = parentId
            end
            flattened[fullId] = containerNode

            -- Recursively flatten children
            local childrenKeyed = normalizeParts(children)
            local flattenedChildren = flattenContainers(childrenKeyed, fullId, class)
            for childId, childDef in pairs(flattenedChildren) do
                flattened[childId] = childDef
            end
        else
            -- Regular part - copy as-is
            local partNode = {}
            for k, v in pairs(partDef) do
                if k ~= "type" then
                    partNode[k] = v
                end
            end
            -- Keep position as-is - tree accumulation handles offsets
            if class and not partNode.class then
                partNode.class = class
            end
            if parentId then
                partNode.parent = parentId
            end
            flattened[fullId] = partNode
        end
    end

    return flattened
end

--------------------------------------------------------------------------------
-- Xref Expansion (Layout Composition)
--------------------------------------------------------------------------------

--[[
    Deep copy a table.
--]]
local function deepCopyForXref(t)
    if type(t) ~= "table" then
        return t
    end
    local copy = {}
    for k, v in pairs(t) do
        copy[k] = deepCopyForXref(v)
    end
    return copy
end

--[[
    Extract parts, classes, and openings from a layout reference.
    Handles both formats:
        - { name = "...", spec = { parts = {...}, classes = {...}, openings = {...} } }
        - { parts = {...}, classes = {...}, openings = {...} }
        - function(parts, parent) return {...} end

    @param layoutRef: Layout table or function
    @return: Parts table, classes table, openings table (all may be nil if invalid)
--]]
local function extractFromLayout(layoutRef)
    local rawParts = nil
    local classes = nil
    local openings = nil

    if type(layoutRef) == "function" then
        -- Function-based layout - call it with dummy proxies
        -- Note: References won't work across xref boundaries (by design)
        local dummyParts = setmetatable({}, {
            __index = function() return setmetatable({}, {
                __index = function() return setmetatable({}, {
                    __index = function() return 0 end
                }) end
            }) end
        })
        local dummyParent = setmetatable({}, {
            __index = function() return setmetatable({}, {
                __index = function() return 0 end
            }) end
        })
        local result = layoutRef(dummyParts, dummyParent)
        if result then
            local spec = result.spec or result
            rawParts = spec.parts
            classes = spec.classes
            openings = spec.openings
        end
    elseif type(layoutRef) == "table" then
        -- Table-based layout
        local spec = layoutRef.spec or layoutRef
        rawParts = spec.parts
        classes = spec.classes
        openings = spec.openings
    end

    -- Normalize parts to keyed format
    return normalizeParts(rawParts), classes, openings
end

--[[
    Expand xref definitions by inlining referenced layouts.

    Usage:
        { id = "house1", xref = SuburbanHouse, position = {10, 0, 0} }

    Becomes:
        house1 = { _isContainer = true, position = {10, 0, 0} }
        house1.Foundation = { parent = "house1", ... }
        house1.Walls = { parent = "house1", ... }

    Properties on the xref node cascade to imported parts (parent → child).

    @param parts: Table of part definitions (keyed by id)
    @param collectedClasses: Optional table to collect classes from xref'd layouts
    @param collectedOpenings: Optional table to collect openings from xref'd layouts
    @param parentOffset: Offset from parent container {x, y, z}
    @return: Expanded parts table, collected classes, collected openings
--]]
local function expandXrefs(parts, collectedClasses, collectedOpenings, parentOffset)
    local expanded = {}
    collectedClasses = collectedClasses or {}
    collectedOpenings = collectedOpenings or {}
    parentOffset = parentOffset or {0, 0, 0}

    for id, partDef in pairs(parts) do
        local xref = partDef.xref

        if not xref then
            -- No xref, keep as-is
            expanded[id] = partDef
        else
            -- Extract parts, classes, and openings from referenced layout
            local importedParts, importedClasses, importedOpenings = extractFromLayout(xref)

            -- CRITICAL: Flatten containers in imported layout
            -- The imported layout may have containers with children arrays that need
            -- to be converted into flat parts with parent references before we can
            -- properly namespace and parent them under our xref container
            importedParts = flattenContainers(importedParts, nil, nil)

            -- Collect classes from imported layout
            if importedClasses then
                for className, classDef in pairs(importedClasses) do
                    -- Don't override existing classes (parent wins)
                    if not collectedClasses[className] then
                        collectedClasses[className] = deepCopyForXref(classDef)
                    end
                end
            end

            -- Calculate offset for this xref container
            local containerPos = partDef.position or {0, 0, 0}
            local xrefOffset = {
                parentOffset[1] + (containerPos[1] or 0),
                parentOffset[2] + (containerPos[2] or 0),
                parentOffset[3] + (containerPos[3] or 0),
            }

            -- Collect openings from imported layout (with offset applied)
            if importedOpenings then
                for _, opening in ipairs(importedOpenings) do
                    local offsetOpening = deepCopyForXref(opening)
                    -- Apply container offset to opening position
                    if offsetOpening.position then
                        offsetOpening.position = {
                            (offsetOpening.position[1] or 0) + xrefOffset[1],
                            (offsetOpening.position[2] or 0) + xrefOffset[2],
                            (offsetOpening.position[3] or 0) + xrefOffset[3],
                        }
                    end
                    table.insert(collectedOpenings, offsetOpening)
                end
            end

            if not importedParts then
                warn("[Geometry] xref could not resolve layout for:", id)
                expanded[id] = partDef
            else
                -- Create container node (transform-only, invisible)
                local container = {}
                for k, v in pairs(partDef) do
                    if k ~= "xref" then
                        container[k] = deepCopyForXref(v)
                    end
                end
                container._isContainer = true
                expanded[id] = container

                -- Recursively expand any nested xrefs in imported layout
                local expandedImports = expandXrefs(importedParts, collectedClasses, collectedOpenings, xrefOffset)

                -- Import each part with namespaced ID
                for importId, importDef in pairs(expandedImports) do
                    local namespacedId = id .. "." .. importId
                    local importedPart = deepCopyForXref(importDef)

                    -- Set parent to container (or namespace the existing parent)
                    if importedPart.parent and importedPart.parent ~= "root" then
                        -- Nested parent - namespace it
                        importedPart.parent = id .. "." .. importedPart.parent
                    else
                        -- Top-level part in imported layout - parent is container
                        importedPart.parent = id
                    end

                    -- Inherit class from container if not overridden
                    -- (cascade: container class provides base, imported class overrides)
                    if container.class and not importedPart.class then
                        importedPart.class = container.class
                    elseif container.class and importedPart.class then
                        -- Combine classes: container first, then imported (imported wins in cascade)
                        importedPart.class = container.class .. " " .. importedPart.class
                    end

                    expanded[namespacedId] = importedPart
                end
            end
        end
    end

    return expanded, collectedClasses, collectedOpenings
end

--------------------------------------------------------------------------------
-- Array Expansion
--------------------------------------------------------------------------------

--[[
    Expand array definitions into individual parts.

    Supports two formats:

    Linear array (single direction):
        array = { count = 4, offset = {10, 0, 0} }

    Grid array (per-axis):
        array = {
            x = { count = 5, spacing = 4 },
            y = { count = 2, spacing = 10 },
            z = { count = 3, spacing = 4 }
        }

    @param parts: Table of part definitions (keyed by id)
    @return: Expanded parts table with arrays replaced by individual parts
--]]
local function expandArrays(parts)
    local expanded = {}

    for id, partDef in pairs(parts) do
        local arrayDef = partDef.array

        if not arrayDef then
            -- No array, keep as-is
            expanded[id] = partDef
        else
            -- Determine array format and extract counts/spacing
            local xCount, yCount, zCount = 1, 1, 1
            local xSpacing, ySpacing, zSpacing = 0, 0, 0
            local handled = false  -- Flag to skip grid generation for diagonal arrays

            if arrayDef.count and arrayDef.offset then
                -- Linear format: { count = N, offset = {x, y, z} }
                local count = arrayDef.count
                local offset = arrayDef.offset

                -- Handle diagonal offsets (multiple non-zero axes)
                -- In this case, count applies to all non-zero axes together (linear diagonal)
                local nonZeroAxes = 0
                if offset[1] ~= 0 then nonZeroAxes = nonZeroAxes + 1 end
                if offset[2] ~= 0 then nonZeroAxes = nonZeroAxes + 1 end
                if offset[3] ~= 0 then nonZeroAxes = nonZeroAxes + 1 end

                if nonZeroAxes > 1 then
                    -- Diagonal array: generate count items along the offset vector
                    for i = 0, count - 1 do
                        local newId = id .. "_" .. (i + 1)
                        local newDef = {}

                        -- Copy all fields except array
                        for k, v in pairs(partDef) do
                            if k ~= "array" then
                                if type(v) == "table" then
                                    newDef[k] = {}
                                    for kk, vv in pairs(v) do
                                        newDef[k][kk] = vv
                                    end
                                else
                                    newDef[k] = v
                                end
                            end
                        end

                        -- Calculate offset position
                        local pos = newDef.position or (newDef.geometry and newDef.geometry.origin) or {0, 0, 0}
                        if newDef.position then
                            newDef.position = {
                                pos[1] + offset[1] * i,
                                pos[2] + offset[2] * i,
                                pos[3] + offset[3] * i,
                            }
                        elseif newDef.geometry then
                            newDef.geometry.origin = {
                                pos[1] + offset[1] * i,
                                pos[2] + offset[2] * i,
                                pos[3] + offset[3] * i,
                            }
                        else
                            newDef.position = {
                                pos[1] + offset[1] * i,
                                pos[2] + offset[2] * i,
                                pos[3] + offset[3] * i,
                            }
                        end

                        expanded[newId] = newDef
                    end
                    handled = true
                else
                    -- Single-axis linear array - use grid logic below
                    if math.abs(offset[1]) > 0 then
                        xCount = count
                        xSpacing = offset[1]
                    elseif math.abs(offset[2]) > 0 then
                        yCount = count
                        ySpacing = offset[2]
                    elseif math.abs(offset[3]) > 0 then
                        zCount = count
                        zSpacing = offset[3]
                    end
                end

            elseif arrayDef.x or arrayDef.y or arrayDef.z then
                -- Grid format: { x = {count, spacing}, y = {count, spacing}, z = {count, spacing} }
                if arrayDef.x then
                    xCount = arrayDef.x.count or 1
                    xSpacing = arrayDef.x.spacing or 0
                end
                if arrayDef.y then
                    yCount = arrayDef.y.count or 1
                    ySpacing = arrayDef.y.spacing or 0
                end
                if arrayDef.z then
                    zCount = arrayDef.z.count or 1
                    zSpacing = arrayDef.z.spacing or 0
                end
            end

            -- Generate grid of parts (unless already handled by diagonal logic)
            if not handled then
                local totalAxes = 0
                if xCount > 1 then totalAxes = totalAxes + 1 end
                if yCount > 1 then totalAxes = totalAxes + 1 end
                if zCount > 1 then totalAxes = totalAxes + 1 end

                for xi = 0, xCount - 1 do
                    for yi = 0, yCount - 1 do
                        for zi = 0, zCount - 1 do
                            -- Generate ID based on dimensionality
                            local newId
                            if totalAxes <= 1 then
                                -- Linear: id_1, id_2, ...
                                local idx = xi + yi + zi + 1
                                newId = id .. "_" .. idx
                            elseif totalAxes == 2 then
                                -- 2D grid: id_1_1, id_1_2, ...
                                local idx1 = (xCount > 1 and xi or (yCount > 1 and yi or zi)) + 1
                                local idx2 = (zCount > 1 and zi or (yCount > 1 and yi or xi)) + 1
                                newId = id .. "_" .. idx1 .. "_" .. idx2
                            else
                                -- 3D grid: id_1_1_1, ...
                                newId = id .. "_" .. (xi + 1) .. "_" .. (yi + 1) .. "_" .. (zi + 1)
                            end

                            local newDef = {}

                            -- Deep copy all fields except array
                            for k, v in pairs(partDef) do
                                if k ~= "array" then
                                    if type(v) == "table" then
                                        newDef[k] = {}
                                        for kk, vv in pairs(v) do
                                            newDef[k][kk] = vv
                                        end
                                    else
                                        newDef[k] = v
                                    end
                                end
                            end

                            -- Calculate offset position
                            local pos = newDef.position or (newDef.geometry and newDef.geometry.origin) or {0, 0, 0}
                            local offsetPos = {
                                pos[1] + xSpacing * xi,
                                pos[2] + ySpacing * yi,
                                pos[3] + zSpacing * zi,
                            }

                            if newDef.position then
                                newDef.position = offsetPos
                            elseif newDef.geometry then
                                newDef.geometry.origin = offsetPos
                            else
                                newDef.position = offsetPos
                            end

                            expanded[newId] = newDef
                        end
                    end
                end
            end
        end
    end

    return expanded
end

--------------------------------------------------------------------------------
-- Resolve: Main (Two-Phase)
--------------------------------------------------------------------------------

function Geometry.resolve(layout)
    local globalStyles = getStyles()

    -- Support function-based layouts for reference resolution
    local layoutData = layout
    if type(layout) == "function" then
        local partsProxy = Geometry.createPartsProxy()
        local parentProxy = Geometry.createParentProxy()
        layoutData = layout(partsProxy, parentProxy)
    end

    -- Handle both layout formats:
    --   1. { parts = {...} }  (simple format)
    --   2. { name = "...", spec = { parts = {...} } }  (full format)
    local spec = layoutData.spec or layoutData
    local rawParts = spec.parts or layoutData.parts

    -- Merge layout-specific classes into styles
    -- Layout classes override global classes
    local styles = {
        base = globalStyles.base or {},
        classes = {},
        ids = globalStyles.ids or {},
        defaults = spec.defaults or {},
    }

    -- Start with global classes
    if globalStyles.classes then
        for k, v in pairs(globalStyles.classes) do
            styles.classes[k] = deepCopy(v)
        end
    end

    -- Override with layout-specific classes
    if spec.classes then
        for k, v in pairs(spec.classes) do
            styles.classes[k] = deepCopy(v)
        end
    end

    local parts = normalizeParts(rawParts or {})

    --------------------------------------------------------------------------
    -- PHASE 0: Flatten containers (hierarchical organization)
    --------------------------------------------------------------------------
    parts = flattenContainers(parts, nil, nil)

    --------------------------------------------------------------------------
    -- PHASE 0a: Expand xrefs (layout composition)
    --------------------------------------------------------------------------
    local xrefClasses = {}
    local xrefOpenings = {}
    parts, xrefClasses, xrefOpenings = expandXrefs(parts, xrefClasses, xrefOpenings, {0, 0, 0})

    -- Merge classes from xref'd layouts (xref classes don't override parent/layout classes)
    for className, classDef in pairs(xrefClasses) do
        if not styles.classes[className] then
            styles.classes[className] = classDef
        end
    end

    -- Collect openings from main layout spec (if any)
    local allOpenings = {}
    if spec.openings then
        for _, opening in ipairs(spec.openings) do
            table.insert(allOpenings, deepCopy(opening))
        end
    end
    -- Add openings collected from xrefs
    for _, opening in ipairs(xrefOpenings) do
        table.insert(allOpenings, opening)
    end

    --------------------------------------------------------------------------
    -- PHASE 0b: Expand arrays into individual parts
    --------------------------------------------------------------------------
    parts = expandArrays(parts)

    --------------------------------------------------------------------------
    -- PHASE 0c: Extract negate parts into openings list
    --------------------------------------------------------------------------
    local negateParts = {}
    for id, partDef in pairs(parts) do
        if partDef.geometry == "negate" then
            -- Convert to opening format
            table.insert(allOpenings, {
                id = id,
                position = partDef.position or {0, 0, 0},
                size = partDef.size or {1, 1, 1},
            })
            table.insert(negateParts, id)
        end
    end
    -- Remove negate parts from main parts table (they don't become instances)
    for _, id in ipairs(negateParts) do
        parts[id] = nil
    end

    --------------------------------------------------------------------------
    -- PHASE 1: Define tree (create empty stubs for all parts)
    --------------------------------------------------------------------------
    local stubs = {}
    for id, partDef in pairs(parts) do
        stubs[id] = {
            id = id,
            name = partDef.name or id,
            parent = partDef.parent,
            shape = partDef.shape or "block",
            geometry = nil,
            properties = nil,
            _isContainer = partDef._isContainer or false,
            _def = partDef,  -- Keep reference to definition for phase 2
        }
    end

    --------------------------------------------------------------------------
    -- PHASE 2: Populate values (tree order, parents before children)
    --------------------------------------------------------------------------
    local order = buildTreeOrder(parts)

    for _, entry in ipairs(order) do
        local id = entry.id
        local stub = stubs[id]
        local partDef = stub._def

        local parentStub = nil
        local parentId = partDef.parent
        if parentId and parentId ~= "root" then
            parentStub = stubs[parentId]
        end

        -- Resolve geometry (references can now look up any stub)
        -- Pass parentId so parent.Size[2] references work
        stub.geometry = resolvePartGeometry(partDef, parentStub, stubs, parentId)

        -- Resolve properties (cascade from parent)
        stub.properties = resolvePartProperties(partDef, parentStub, styles)

        -- Preserve class and id for round-trip scanning
        -- These are stored as attributes on built parts so Scanner can reconstruct
        -- the original class-based styling instead of flattening to inline properties
        stub.class = partDef.class
        stub.id = partDef.id

        -- Preserve holes for CSG subtraction
        if partDef.holes then
            stub.holes = partDef.holes
        end

        -- Clean up definition reference
        stub._def = nil
    end

    -- Attach metadata for scanner/debug
    stubs._meta = {
        name = layoutData.name,
        openings = allOpenings,  -- Global openings for instantiate
        classes = styles.classes,  -- Preserve for round-trip scanning
    }

    return stubs
end

--------------------------------------------------------------------------------
-- Instantiate: Helpers
--------------------------------------------------------------------------------

toColor3 = function(color)
    if not color then return nil end
    if typeof(color) == "Color3" then return color end
    if type(color) == "table" then
        local max = math.max(color[1] or 0, color[2] or 0, color[3] or 0)
        if max > 1 then
            return Color3.fromRGB(color[1] or 0, color[2] or 0, color[3] or 0)
        else
            return Color3.new(color[1] or 0, color[2] or 0, color[3] or 0)
        end
    end
    if type(color) == "string" then
        return BrickColor.new(color).Color
    end
    return nil
end

applyProperties = function(part, properties)
    for key, value in pairs(properties) do
        if key == "Color" then
            local color = toColor3(value)
            if color then part.Color = color end
        elseif key == "Material" then
            if type(value) == "string" then
                local success = pcall(function()
                    part.Material = Enum.Material[value]
                end)
                if not success then
                    warn("[Geometry] Unknown material:", value)
                end
            else
                part.Material = value
            end
        else
            local success = pcall(function()
                part[key] = value
            end)
            if not success then
                part:SetAttribute(key, value)
            end
        end
    end
end

createPart = function(entry, scaleFactor)
    scaleFactor = scaleFactor or 1
    local geom = entry.geometry
    local shape = entry.shape
    local isContainer = entry._isContainer

    local part
    if shape == "wedge" then
        part = Instance.new("WedgePart")
    elseif shape == "cornerwedge" then
        part = Instance.new("CornerWedgePart")
    elseif shape == "cylinder" then
        part = Instance.new("Part")
        part.Shape = Enum.PartType.Cylinder
    elseif shape == "sphere" then
        part = Instance.new("Part")
        part.Shape = Enum.PartType.Ball
    else
        part = Instance.new("Part")
    end

    part.Name = entry.name or entry.id

    -- Apply scale factor to geometry
    local scaledOrigin = {
        geom.origin[1] * scaleFactor,
        geom.origin[2] * scaleFactor,
        geom.origin[3] * scaleFactor
    }
    local scaledSize = {
        geom.scale[1] * scaleFactor,
        geom.scale[2] * scaleFactor,
        geom.scale[3] * scaleFactor
    }

    -- Container nodes are transform-only (invisible, non-collidable)
    if isContainer then
        part.Size = Vector3.new(1, 1, 1)  -- Minimal size
        part.Transparency = 1
        part.CanCollide = false
        part.CanQuery = false
        part.CanTouch = false
    else
        part.Size = Vector3.new(scaledSize[1], scaledSize[2], scaledSize[3])
    end

    if isContainer then
        -- Containers are transform nodes - position directly at origin
        part.Position = Vector3.new(scaledOrigin[1], scaledOrigin[2], scaledOrigin[3])
    else
        -- Corner-based origin: position is bottom-left-back corner
        -- Convert to Roblox center-based positioning by adding half the size
        part.Position = Vector3.new(
            scaledOrigin[1] + scaledSize[1]/2,
            scaledOrigin[2] + scaledSize[2]/2,
            scaledOrigin[3] + scaledSize[3]/2
        )
    end

    -- Rotate cylinders to be vertical (Roblox cylinders are horizontal by default)
    if shape == "cylinder" then
        part.CFrame = part.CFrame * CFrame.Angles(0, 0, math.rad(90))
    end

    if geom.rotation then
        local rot = geom.rotation
        part.CFrame = part.CFrame * CFrame.Angles(
            math.rad(rot[1] or 0),
            math.rad(rot[2] or 0),
            math.rad(rot[3] or 0)
        )
    end

    -- Apply properties (skip for pure containers unless overridden)
    if not isContainer or (entry.properties and next(entry.properties)) then
        applyProperties(part, entry.properties)
    end

    -- Preserve class and id as attributes for round-trip scanning
    -- Scanner uses these to reconstruct class-based styling instead of inline properties
    if entry.class and entry.class ~= "" then
        part:SetAttribute("FactoryClass", entry.class)
    end
    if entry.id and entry.id ~= "" then
        part:SetAttribute("FactoryId", entry.id)
    end

    return part
end

--------------------------------------------------------------------------------
-- Instantiate: AABB Intersection Test
--------------------------------------------------------------------------------

--[[
    Check if two axis-aligned bounding boxes intersect.
    Each box is defined by corner position and size.

    @param pos1, size1: First box (corner-based)
    @param pos2, size2: Second box (corner-based)
    @return: true if boxes intersect
--]]
local function aabbIntersects(pos1, size1, pos2, size2)
    -- Calculate min/max for each box
    local min1 = {pos1[1], pos1[2], pos1[3]}
    local max1 = {pos1[1] + size1[1], pos1[2] + size1[2], pos1[3] + size1[3]}

    local min2 = {pos2[1], pos2[2], pos2[3]}
    local max2 = {pos2[1] + size2[1], pos2[2] + size2[2], pos2[3] + size2[3]}

    -- Check for overlap on all three axes
    return min1[1] < max2[1] and max1[1] > min2[1]
       and min1[2] < max2[2] and max1[2] > min2[2]
       and min1[3] < max2[3] and max1[3] > min2[3]
end

--[[
    Find all openings that intersect with a part's geometry.

    @param partGeom: Part geometry {origin, scale}
    @param openings: Array of opening definitions
    @return: Array of openings that intersect this part
--]]
local function findIntersectingOpenings(partGeom, openings)
    if not openings or #openings == 0 then
        return {}
    end

    local intersecting = {}
    local partPos = partGeom.origin
    local partSize = partGeom.scale

    for _, opening in ipairs(openings) do
        local openPos = opening.position or {0, 0, 0}
        local openSize = opening.size or {1, 1, 1}

        if aabbIntersects(partPos, partSize, openPos, openSize) then
            table.insert(intersecting, opening)
        end
    end

    return intersecting
end

--------------------------------------------------------------------------------
-- Instantiate: CSG Hole Cutting
--------------------------------------------------------------------------------

local function cutHoles(part, holes, partCenter)
    if not holes or #holes == 0 then
        return part
    end

    local GeometryService = game:GetService("GeometryService")

    -- Parts must be parented for SubtractAsync to work
    local originalParent = part.Parent
    if not originalParent then
        part.Parent = workspace
    end

    -- Create negate parts for each hole (must be parented for SubtractAsync)
    local negateParts = {}
    for _, hole in ipairs(holes) do
        local holePart = Instance.new("Part")
        holePart.Size = Vector3.new(hole.size[1], hole.size[2], hole.size[3])

        -- Hole position is relative to part center
        local holePos = Vector3.new(
            partCenter.X + (hole.position[1] or 0),
            partCenter.Y + (hole.position[2] or 0),
            partCenter.Z + (hole.position[3] or 0)
        )
        holePart.Position = holePos
        holePart.Anchored = true
        holePart.Parent = workspace  -- Must be parented for SubtractAsync

        table.insert(negateParts, holePart)
    end

    -- Perform subtraction
    local success, result = pcall(function()
        return GeometryService:SubtractAsync(part, negateParts, {
            CollisionFidelity = Enum.CollisionFidelity.PreciseConvexDecomposition,
            RenderFidelity = Enum.RenderFidelity.Precise,
            SplitApart = false,
        })
    end)

    -- Clean up negate parts
    for _, np in ipairs(negateParts) do
        np:Destroy()
    end

    if not success then
        warn("[Geometry] SubtractAsync failed:", result)
        return part
    end

    -- SubtractAsync returns an array
    local subtracted = result[1]
    if not subtracted then
        warn("[Geometry] SubtractAsync returned empty result")
        return part
    end

    -- Copy properties from original
    subtracted.Name = part.Name
    subtracted.Anchored = part.Anchored
    subtracted.CanCollide = part.CanCollide
    subtracted.Material = part.Material
    subtracted.Color = part.Color
    subtracted.Transparency = part.Transparency

    -- Destroy original and return subtracted
    part:Destroy()
    return subtracted
end

--------------------------------------------------------------------------------
-- Instantiate: Main
--------------------------------------------------------------------------------

function Geometry.instantiate(resolved, parent, options)
    parent = parent or workspace
    options = options or {}
    local scaleFactor = options.scale or 1

    -- Calculate bounds (skip _meta and containers)
    local minX, minY, minZ = math.huge, math.huge, math.huge
    local maxX, maxY, maxZ = -math.huge, -math.huge, -math.huge

    for id, entry in pairs(resolved) do
        if id ~= "_meta" and not entry._isContainer then
            local g = entry.geometry
            local o, s = g.origin, g.scale
            -- Apply scale factor to geometry
            local scaledO = {o[1] * scaleFactor, o[2] * scaleFactor, o[3] * scaleFactor}
            local scaledS = {s[1] * scaleFactor, s[2] * scaleFactor, s[3] * scaleFactor}
            minX = math.min(minX, scaledO[1])
            minY = math.min(minY, scaledO[2])
            minZ = math.min(minZ, scaledO[3])
            maxX = math.max(maxX, scaledO[1] + scaledS[1])
            maxY = math.max(maxY, scaledO[2] + scaledS[2])
            maxZ = math.max(maxZ, scaledO[3] + scaledS[3])
        end
    end

    local bounds = {maxX - minX, maxY - minY, maxZ - minZ}

    -- Create container (Model has no physics/collision)
    local container = Instance.new("Model")
    container.Name = resolved._meta and resolved._meta.name or "GeometryContainer"

    -- Create a PrimaryPart for positioning (invisible, non-collidable)
    local primaryPart = Instance.new("Part")
    primaryPart.Name = "PrimaryPart"
    primaryPart.Size = Vector3.new(1, 1, 1)
    primaryPart.Position = Vector3.new(
        (minX + maxX) / 2,
        (minY + maxY) / 2,
        (minZ + maxZ) / 2
    )
    primaryPart.Anchored = true
    primaryPart.CanCollide = false
    primaryPart.CanQuery = false
    primaryPart.Transparency = 1
    primaryPart.Parent = container
    container.PrimaryPart = primaryPart

    -- Get global openings from metadata and apply scale
    local rawOpenings = (resolved._meta and resolved._meta.openings) or {}
    local globalOpenings = {}
    for _, op in ipairs(rawOpenings) do
        table.insert(globalOpenings, {
            id = op.id,
            position = {
                op.position[1] * scaleFactor,
                op.position[2] * scaleFactor,
                op.position[3] * scaleFactor
            },
            size = {
                op.size[1] * scaleFactor,
                op.size[2] * scaleFactor,
                op.size[3] * scaleFactor
            }
        })
    end

    -- Create parts (skip _meta)
    for id, entry in pairs(resolved) do
        if id ~= "_meta" then
            local part = createPart(entry, scaleFactor)
            local partCenter = part.Position

            -- Skip containers for CSG operations
            if not entry._isContainer then
                -- Find global openings that intersect this part (using scaled geometry)
                local scaledGeometry = {
                    origin = {
                        entry.geometry.origin[1] * scaleFactor,
                        entry.geometry.origin[2] * scaleFactor,
                        entry.geometry.origin[3] * scaleFactor
                    },
                    scale = {
                        entry.geometry.scale[1] * scaleFactor,
                        entry.geometry.scale[2] * scaleFactor,
                        entry.geometry.scale[3] * scaleFactor
                    }
                }
                local intersectingOpenings = findIntersectingOpenings(scaledGeometry, globalOpenings)

                if #intersectingOpenings > 0 then

                    -- Convert openings to hole format (center-relative positions)
                    local holes = {}
                    for _, opening in ipairs(intersectingOpenings) do
                        -- Opening is corner-based, convert to center-relative
                        -- Opening center = opening.position + opening.size/2
                        -- Relative to part center = opening_center - part_center
                        local openingCenter = {
                            opening.position[1] + opening.size[1] / 2,
                            opening.position[2] + opening.size[2] / 2,
                            opening.position[3] + opening.size[3] / 2,
                        }
                        local relativePos = {
                            openingCenter[1] - partCenter.X,
                            openingCenter[2] - partCenter.Y,
                            openingCenter[3] - partCenter.Z,
                        }
                        table.insert(holes, {
                            position = relativePos,
                            size = opening.size,
                        })
                    end

                    part = cutHoles(part, holes, partCenter)
                end

                -- Also cut per-part holes if defined (legacy support) - scale them
                if entry.holes and #entry.holes > 0 then
                    local scaledHoles = {}
                    for _, hole in ipairs(entry.holes) do
                        table.insert(scaledHoles, {
                            position = {
                                hole.position[1] * scaleFactor,
                                hole.position[2] * scaleFactor,
                                hole.position[3] * scaleFactor
                            },
                            size = {
                                hole.size[1] * scaleFactor,
                                hole.size[2] * scaleFactor,
                                hole.size[3] * scaleFactor
                            }
                        })
                    end
                    part = cutHoles(part, scaledHoles, partCenter)
                end
            end

            part.Parent = container
            registerPart(id, part, entry)
        end
    end

    container.Parent = parent
    return container
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

function Geometry.build(layout, parent, options)
    parent = parent or workspace
    options = options or {}

    -- Get layout name for cleanup
    local layoutData = type(layout) == "function" and layout(Geometry.createPartsProxy(), Geometry.createParentProxy()) or layout
    local spec = layoutData.spec or layoutData
    local name = spec.name or layoutData.name or "GeometryContainer"

    -- Destroy existing geometry with same name (prevents duplicates)
    local existing = parent:FindFirstChild(name)
    if existing then
        existing:Destroy()
    end

    local resolved = Geometry.resolve(layout)
    return Geometry.instantiate(resolved, parent, options)
end

-- Fresh build that bypasses module cache (for development)
-- Pass the ModuleScript instance, not the required result
-- Options: { scale = number } - multiplier for all geometry (default 1)
function Geometry.freshBuild(layoutModule, parent, options)
    -- Clone module to bust require cache
    local clone = layoutModule:Clone()
    clone.Name = layoutModule.Name .. "_fresh"
    clone.Parent = layoutModule.Parent

    local layout = require(clone)
    clone:Destroy()

    return Geometry.build(layout, parent, options)
end

function Geometry.debug(layout)
    local resolved = Geometry.resolve(layout)

    print("=== RESOLVED LAYOUT ===")
    for id, entry in pairs(resolved) do
        if id ~= "_meta" then
            print(string.format("  %s:", id))
            print(string.format("    parent: %s", entry.parent or "root"))
            print(string.format("    geometry: origin={%s} scale={%s}",
                table.concat(entry.geometry.origin, ","),
                table.concat(entry.geometry.scale, ",")))
            for k, v in pairs(entry.properties) do
                print(string.format("    %s = %s", k, tostring(v)))
            end
        end
    end
    print("=======================")

    return resolved
end

--------------------------------------------------------------------------------
-- Scanner: Code Generation
--------------------------------------------------------------------------------

valueToCode = function(value, indent)
    indent = indent or ""
    local t = type(value)

    if t == "string" then
        return string.format('"%s"', value)
    elseif t == "number" then
        -- Clean up floats
        if value == math.floor(value) then
            return tostring(math.floor(value))
        else
            return string.format("%.2f", value):gsub("%.?0+$", "")
        end
    elseif t == "boolean" then
        return tostring(value)
    elseif t == "table" then
        return tableToCode(value, indent)
    else
        return tostring(value)
    end
end

tableToCode = function(tbl, indent)
    indent = indent or ""
    local nextIndent = indent .. "    "
    local lines = {}

    -- Check if array-like (sequential integer keys starting at 1)
    local isArray = true
    local maxIndex = 0
    for k, _ in pairs(tbl) do
        if type(k) == "number" and k == math.floor(k) and k > 0 then
            maxIndex = math.max(maxIndex, k)
        else
            isArray = false
            break
        end
    end
    if isArray and maxIndex > 0 then
        -- Check for gaps
        for i = 1, maxIndex do
            if tbl[i] == nil then
                isArray = false
                break
            end
        end
    end

    if isArray and maxIndex > 0 then
        -- Array format: {1, 2, 3}
        local values = {}
        for i = 1, maxIndex do
            table.insert(values, valueToCode(tbl[i], nextIndent))
        end
        -- Short arrays on one line
        local oneLine = "{" .. table.concat(values, ", ") .. "}"
        if #oneLine < 60 then
            return oneLine
        end
        -- Long arrays multiline
        table.insert(lines, "{")
        for i, v in ipairs(values) do
            table.insert(lines, nextIndent .. v .. ",")
        end
        table.insert(lines, indent .. "}")
        return table.concat(lines, "\n")
    else
        -- Dictionary format
        table.insert(lines, "{")

        -- Sort keys for consistent output
        local keys = {}
        for k, _ in pairs(tbl) do
            table.insert(keys, k)
        end
        table.sort(keys, function(a, b)
            return tostring(a) < tostring(b)
        end)

        for _, k in ipairs(keys) do
            local v = tbl[k]
            local keyStr
            if type(k) == "string" and k:match("^[%a_][%w_]*$") then
                keyStr = k
            else
                keyStr = "[" .. valueToCode(k, nextIndent) .. "]"
            end
            local valStr = valueToCode(v, nextIndent)
            table.insert(lines, nextIndent .. keyStr .. " = " .. valStr .. ",")
        end

        table.insert(lines, indent .. "}")
        return table.concat(lines, "\n")
    end
end

function Geometry.scan(layout)
    local resolved = Geometry.resolve(layout)

    -- Get name from metadata or fallback
    local layoutName = (resolved._meta and resolved._meta.name)
        or (type(layout) == "table" and layout.name)
        or "ScannedLayout"

    -- Build output structure matching layout format
    local output = {
        name = layoutName,
        parts = {},
    }

    for id, entry in pairs(resolved) do
        -- Skip metadata
        if id ~= "_meta" then
            output.parts[id] = {
                parent = entry.parent or "root",
                shape = entry.shape ~= "block" and entry.shape or nil,
                geometry = {
                    origin = entry.geometry.origin,
                    scale = entry.geometry.scale,
                    rotation = (entry.geometry.rotation[1] ~= 0 or
                               entry.geometry.rotation[2] ~= 0 or
                               entry.geometry.rotation[3] ~= 0)
                               and entry.geometry.rotation or nil,
                },
                properties = entry.properties,
            }
        end
    end

    -- Generate code
    local code = "--[[\n"
    code = code .. "    " .. layoutName .. "\n"
    code = code .. "    Generated by Geometry.scan()\n"
    code = code .. "    All values resolved - no class references\n"
    code = code .. "--]]\n\n"
    code = code .. "return " .. tableToCode(output)

    return code
end

function Geometry.scanPrint(layout)
    local code = Geometry.scan(layout)

    print("\n" .. string.rep("=", 70))
    print("-- Geometry Scanner Output")
    print(string.rep("=", 70))
    print(code)
    print(string.rep("=", 70) .. "\n")

    return code
end

--------------------------------------------------------------------------------
-- Scanner: CSV/TSV Export
--------------------------------------------------------------------------------

function Geometry.toTSV(layout)
    local resolved = Geometry.resolve(layout)

    -- Collect all property keys (skip _meta)
    local propKeys = {}
    local propKeysSet = {}
    for id, entry in pairs(resolved) do
        if id ~= "_meta" and entry.properties then
            for k, _ in pairs(entry.properties) do
                if not propKeysSet[k] then
                    propKeysSet[k] = true
                    table.insert(propKeys, k)
                end
            end
        end
    end
    table.sort(propKeys)

    -- Build header
    local headers = {
        "id", "parent", "shape",
        "origin_x", "origin_y", "origin_z",
        "scale_x", "scale_y", "scale_z",
        "rot_x", "rot_y", "rot_z",
    }
    for _, k in ipairs(propKeys) do
        table.insert(headers, k)
    end

    local lines = { table.concat(headers, "\t") }

    -- Sort entries by id for consistent output (skip _meta)
    local ids = {}
    for id, _ in pairs(resolved) do
        if id ~= "_meta" then
            table.insert(ids, id)
        end
    end
    table.sort(ids)

    -- Build rows
    for _, id in ipairs(ids) do
        local entry = resolved[id]
        local g = entry.geometry
        local row = {
            id,
            entry.parent or "root",
            entry.shape or "block",
            g.origin[1], g.origin[2], g.origin[3],
            g.scale[1], g.scale[2], g.scale[3],
            g.rotation[1], g.rotation[2], g.rotation[3],
        }

        -- Add properties
        for _, k in ipairs(propKeys) do
            local v = entry.properties[k]
            if v == nil then
                table.insert(row, "")
            elseif type(v) == "table" then
                -- Format arrays like {255,128,0}
                local parts = {}
                for _, val in ipairs(v) do
                    table.insert(parts, tostring(val))
                end
                if #parts > 0 then
                    table.insert(row, "{" .. table.concat(parts, ",") .. "}")
                else
                    table.insert(row, "{}")
                end
            else
                table.insert(row, tostring(v))
            end
        end

        table.insert(lines, table.concat(row, "\t"))
    end

    return table.concat(lines, "\n")
end

function Geometry.toTSVPrint(layout)
    local tsv = Geometry.toTSV(layout)

    print("\n" .. string.rep("=", 70))
    print("-- Geometry TSV Export (paste into spreadsheet)")
    print(string.rep("=", 70))
    print(tsv)
    print(string.rep("=", 70) .. "\n")

    return tsv
end

--##############################################################################
-- PHASE 3: RETURN
--##############################################################################

return Geometry
