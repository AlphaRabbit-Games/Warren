--[[
    Warren Framework v2
    ClassResolver.lua - Unified Style Resolution System

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    Domain-agnostic style resolution using a CSS-like cascade. Works with any
    declarative system that uses class-based styling (GUI, geometry, layouts).

    Cascade order (lowest to highest priority):
        1. defaults  - Applied to all elements
        2. base      - Applied by element type (e.g., "TextLabel", "Part")
        3. classes   - Applied by class name (space-separated, in order)
        4. ids       - Applied by element ID
        5. inline    - Direct properties on the definition

    ============================================================================
    USAGE
    ============================================================================

    Basic (GeometrySpec-style):
    ```lua
    local spec = {
        defaults = { Anchored = true },
        classes = {
            frame = { Material = "DiamondPlate" },
        },
        parts = {
            { id = "base", class = "frame", size = {4, 2, 4} },
        },
    }
    local resolved = ClassResolver.resolve(partDef, spec)
    ```

    Full cascade (GUI-style):
    ```lua
    local styles = {
        defaults = { BackgroundTransparency = 0 },
        base = {
            TextLabel = { Font = "GothamBold", TextColor3 = {255, 255, 255} },
        },
        classes = {
            ["hud-text"] = { TextScaled = true },
            gold = { TextColor3 = {255, 215, 0} },
        },
        ids = {
            score = { TextSize = 24 },
        },
    }
    local resolved = ClassResolver.resolve(definition, styles)
    ```

    With responsive breakpoints:
    ```lua
    local styles = {
        classes = {
            ["hud-text"] = { TextSize = 18 },
            ["hud-text@tablet"] = { TextSize = 14 },
            ["hud-text@phone"] = { TextSize = 12 },
        },
    }
    local resolved = ClassResolver.resolve(definition, styles, { breakpoint = "tablet" })
    ```

    With custom reserved keys:
    ```lua
    local resolved = ClassResolver.resolve(definition, styles, {
        reservedKeys = { type = true, children = true, ref = true },
    })
    ```

--]]

local ClassResolver = {}

--------------------------------------------------------------------------------
-- DEFAULT RESERVED KEYS
--------------------------------------------------------------------------------

-- Keys that should never be treated as style properties
-- Domains can override with options.reservedKeys
local DEFAULT_RESERVED_KEYS = {
    -- Identity
    id = true,
    class = true,
    type = true,

    -- Structure
    children = true,
    parts = true,
    mounts = true,

    -- Geometry
    position = true,
    size = true,
    height = true,
    radius = true,
    rotation = true,
    shape = true,
    facing = true,
    holes = true,
    array = true,
    xref = true,

    -- GUI
    ref = true,
    actions = true,
    onHover = true,
    onActive = true,
    onClick = true,
}

--------------------------------------------------------------------------------
-- INTERNAL HELPERS
--------------------------------------------------------------------------------

--[[
    Shallow merge source table into target table.
    Later values override earlier ones.

    @param target: Table to merge into
    @param source: Table to merge from
    @return: The target table
--]]
local function merge(target, source)
    if not source then
        return target
    end

    for key, value in pairs(source) do
        target[key] = value
    end

    return target
end

--[[
    Parse class string into array of class names.
    "frame accent metal" -> {"frame", "accent", "metal"}

    @param classString: Space-separated class names
    @return: Array of class name strings
--]]
local function parseClasses(classString)
    if not classString or classString == "" then
        return {}
    end

    local classes = {}
    for class in classString:gmatch("%S+") do
        table.insert(classes, class)
    end
    return classes
end

--[[
    Extract inline styles from definition (non-reserved keys).

    @param definition: Element definition table
    @param reservedKeys: Table of keys to exclude
    @return: Table of inline style properties
--]]
local function extractInlineStyles(definition, reservedKeys)
    local inline = {}

    for key, value in pairs(definition) do
        if not reservedKeys[key] then
            inline[key] = value
        end
    end

    return inline
end

--[[
    Apply styles from a bucket with optional responsive variant.

    @param resolved: Target table to merge into
    @param bucket: Style bucket (e.g., spec.classes)
    @param key: Key to look up (e.g., "frame")
    @param breakpoint: Optional breakpoint name (e.g., "tablet")
--]]
local function applyFromBucket(resolved, bucket, key, breakpoint)
    if not bucket or not key then
        return
    end

    -- Base style
    if bucket[key] then
        merge(resolved, bucket[key])
    end

    -- Responsive variant (e.g., "frame@tablet")
    if breakpoint then
        local responsiveKey = key .. "@" .. breakpoint
        if bucket[responsiveKey] then
            merge(resolved, bucket[responsiveKey])
        end
    end
end

--------------------------------------------------------------------------------
-- PUBLIC API
--------------------------------------------------------------------------------

--[[
    Resolve all styles for a definition using the cascade.

    Cascade order (lowest to highest priority):
        1. spec.defaults  - Applied to all elements
        2. spec.base[type] - Applied by element type
        3. spec.classes[className] - Applied by class (in order)
        4. spec.ids[id] - Applied by element ID
        5. inline properties - Direct properties on definition

    @param definition: The element definition table
    @param spec: Style specification { defaults?, base?, classes?, ids? }
    @param options: Optional settings
        - breakpoint: Responsive breakpoint name (e.g., "tablet")
        - reservedKeys: Custom reserved keys table (overrides defaults)
    @return: Merged properties table
--]]
function ClassResolver.resolve(definition, spec, options)
    options = options or {}
    local reservedKeys = options.reservedKeys or DEFAULT_RESERVED_KEYS
    local breakpoint = options.breakpoint

    local resolved = {}

    -- Safety check
    if not spec then
        return extractInlineStyles(definition, reservedKeys)
    end

    -- 1. Apply defaults (applied to all elements)
    if spec.defaults then
        merge(resolved, spec.defaults)
        -- Responsive defaults
        if breakpoint and spec.defaults["@" .. breakpoint] then
            merge(resolved, spec.defaults["@" .. breakpoint])
        end
    end

    -- 2. Apply base styles (by element type)
    local elementType = definition.type
    if elementType and spec.base then
        applyFromBucket(resolved, spec.base, elementType, breakpoint)
    end

    -- 3. Apply class styles (in order from class attribute)
    if definition.class and spec.classes then
        local classList = parseClasses(definition.class)
        for _, className in ipairs(classList) do
            applyFromBucket(resolved, spec.classes, className, breakpoint)
        end
    end

    -- 4. Apply ID styles
    if definition.id and spec.ids then
        applyFromBucket(resolved, spec.ids, definition.id, breakpoint)
    end

    -- 5. Apply inline styles (highest priority)
    local inlineStyles = extractInlineStyles(definition, reservedKeys)
    merge(resolved, inlineStyles)

    return resolved
end

--[[
    Check if a definition has a specific class.

    @param definition: Element definition table
    @param className: Class name to check for
    @return: boolean
--]]
function ClassResolver.hasClass(definition, className)
    if not definition.class then
        return false
    end

    for class in definition.class:gmatch("%S+") do
        if class == className then
            return true
        end
    end

    return false
end

--[[
    Get all classes from a definition as an array.

    @param definition: Element definition table
    @return: Array of class name strings
--]]
function ClassResolver.getClasses(definition)
    return parseClasses(definition.class)
end

--[[
    Add a class to a definition's class string.
    No-op if class already exists.

    @param definition: Element definition table
    @param className: Class name to add
--]]
function ClassResolver.addClass(definition, className)
    if ClassResolver.hasClass(definition, className) then
        return
    end

    if definition.class and definition.class ~= "" then
        definition.class = definition.class .. " " .. className
    else
        definition.class = className
    end
end

--[[
    Remove a class from a definition's class string.

    @param definition: Element definition table
    @param className: Class name to remove
--]]
function ClassResolver.removeClass(definition, className)
    if not definition.class then
        return
    end

    local classes = parseClasses(definition.class)
    local newClasses = {}

    for _, class in ipairs(classes) do
        if class ~= className then
            table.insert(newClasses, class)
        end
    end

    definition.class = table.concat(newClasses, " ")
end

--[[
    Toggle a class on a definition.

    @param definition: Element definition table
    @param className: Class name to toggle
    @param force: Optional boolean to force add (true) or remove (false)
    @return: boolean - whether class is now present
--]]
function ClassResolver.toggleClass(definition, className, force)
    local hasIt = ClassResolver.hasClass(definition, className)

    if force == true or (force == nil and not hasIt) then
        ClassResolver.addClass(definition, className)
        return true
    else
        ClassResolver.removeClass(definition, className)
        return false
    end
end

--[[
    Create a domain-specific resolver with preset options.
    Useful for creating GUI.resolve() or Geometry.resolve() helpers.

    @param defaultOptions: Options to apply to all resolve calls
    @return: Function with signature (definition, spec, options?) -> resolved
--]]
function ClassResolver.createResolver(defaultOptions)
    return function(definition, spec, options)
        -- Merge options (call-time options override defaults)
        local mergedOptions = {}
        if defaultOptions then
            for k, v in pairs(defaultOptions) do
                mergedOptions[k] = v
            end
        end
        if options then
            for k, v in pairs(options) do
                mergedOptions[k] = v
            end
        end
        return ClassResolver.resolve(definition, spec, mergedOptions)
    end
end

--[[
    Get the default reserved keys table.
    Useful for extending rather than replacing.

    @return: Copy of default reserved keys
--]]
function ClassResolver.getDefaultReservedKeys()
    local copy = {}
    for k, v in pairs(DEFAULT_RESERVED_KEYS) do
        copy[k] = v
    end
    return copy
end

return ClassResolver
