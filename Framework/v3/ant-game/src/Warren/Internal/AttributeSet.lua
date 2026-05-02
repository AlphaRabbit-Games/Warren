--[[
    Warren Framework v2
    AttributeSet.lua - Reactive Attribute/Modifier System

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    AttributeSet provides a reactive attribute system with:
    - Base values with schema validation (type, min, max, default)
    - Modifier stacking (additive, multiplicative, override)
    - Derived/computed values with dependency tracking
    - Subscription system for change notifications
    - Selective client replication flag

    ============================================================================
    SCHEMA FORMAT
    ============================================================================

    ```lua
    local schema = {
        health = {
            type = "number",
            default = 100,
            min = 0,
            max = 1000,
            replicate = true,
        },
        effectiveDefense = {
            type = "number",
            derived = true,
            dependencies = { "baseDefense" },
            replicate = true,
            compute = function(values, modifiers)
                local base = values.baseDefense
                local add = modifiers.additive or 0
                local mult = modifiers.multiplicative or 1
                return (base + add) * mult
            end,
        },
    }
    ```

    ============================================================================
    MODIFIER AGGREGATION
    ============================================================================

    Default aggregation order:
    1. Start with base value
    2. Apply all "additive" modifiers (sum)
    3. Apply all "multiplicative" modifiers (product)
    4. Apply "override" if present (highest priority wins)
    5. Clamp to min/max if defined

    Stacking rule: Sum all modifiers (even from same source).

--]]

local AttributeSet = {}
AttributeSet.__index = AttributeSet

--------------------------------------------------------------------------------
-- CONSTRUCTOR
--------------------------------------------------------------------------------

--[[
    Create a new AttributeSet with the given schema.

    @param schema table - Attribute definitions
    @return AttributeSet
--]]
function AttributeSet.new(schema)
    local self = setmetatable({}, AttributeSet)

    self._schema = schema or {}
    self._baseValues = {}           -- attrName -> base value
    self._modifiers = {}            -- attrName -> { additive = {}, multiplicative = {}, override = {} }
    self._computedValues = {}       -- attrName -> cached computed value
    self._subscriptions = {}        -- attrName -> { callback, ... }
    self._allSubscriptions = {}     -- callbacks for any attribute change
    self._nextModifierId = 1
    self._modifierById = {}         -- modifierId -> { attribute, operation, ... }
    self._dependencyOrder = {}      -- Topologically sorted attribute names
    self._dependents = {}           -- attrName -> { dependent attrs that use this }

    -- Initialize
    self:_buildDependencyGraph()
    self:_initializeValues()

    return self
end

--------------------------------------------------------------------------------
-- DEPENDENCY GRAPH
--------------------------------------------------------------------------------

--[[
    Build the dependency graph and compute topological order.
    Called once during construction.
--]]
function AttributeSet:_buildDependencyGraph()
    -- Find all base attributes (no dependencies)
    local baseAttrs = {}
    local derivedAttrs = {}

    for attrName, def in pairs(self._schema) do
        self._dependents[attrName] = {}

        if def.derived and def.dependencies then
            table.insert(derivedAttrs, attrName)
        else
            table.insert(baseAttrs, attrName)
        end
    end

    -- Build reverse dependency map (what depends on me)
    for attrName, def in pairs(self._schema) do
        if def.derived and def.dependencies then
            for _, depName in ipairs(def.dependencies) do
                if self._dependents[depName] then
                    table.insert(self._dependents[depName], attrName)
                end
            end
        end
    end

    -- Topological sort using Kahn's algorithm
    local inDegree = {}
    for attrName, def in pairs(self._schema) do
        if def.derived and def.dependencies then
            inDegree[attrName] = #def.dependencies
        else
            inDegree[attrName] = 0
        end
    end

    local queue = {}
    for attrName, degree in pairs(inDegree) do
        if degree == 0 then
            table.insert(queue, attrName)
        end
    end

    local sorted = {}
    while #queue > 0 do
        local current = table.remove(queue, 1)
        table.insert(sorted, current)

        for _, dependent in ipairs(self._dependents[current] or {}) do
            inDegree[dependent] = inDegree[dependent] - 1
            if inDegree[dependent] == 0 then
                table.insert(queue, dependent)
            end
        end
    end

    -- Check for cycles
    if #sorted ~= self:_countAttributes() then
        error("[AttributeSet] Circular dependency detected in schema")
    end

    self._dependencyOrder = sorted
end

--[[
    Count total attributes in schema.
--]]
function AttributeSet:_countAttributes()
    local count = 0
    for _ in pairs(self._schema) do
        count = count + 1
    end
    return count
end

--------------------------------------------------------------------------------
-- INITIALIZATION
--------------------------------------------------------------------------------

--[[
    Initialize all values from schema defaults.
--]]
function AttributeSet:_initializeValues()
    -- Initialize modifier tables for each attribute
    for attrName in pairs(self._schema) do
        self._modifiers[attrName] = {
            additive = {},
            multiplicative = {},
            override = {},
        }
        self._subscriptions[attrName] = {}
    end

    -- Set base values from defaults (in dependency order)
    for _, attrName in ipairs(self._dependencyOrder) do
        local def = self._schema[attrName]
        if not def.derived then
            self._baseValues[attrName] = def.default or 0
        end
    end

    -- Compute all values (in dependency order)
    for _, attrName in ipairs(self._dependencyOrder) do
        self._computedValues[attrName] = self:_computeValue(attrName)
    end
end

--------------------------------------------------------------------------------
-- VALUE COMPUTATION
--------------------------------------------------------------------------------

--[[
    Compute the final value for an attribute.

    @param attrName string - Attribute name
    @return any - Computed value
--]]
function AttributeSet:_computeValue(attrName)
    local def = self._schema[attrName]
    if not def then
        return nil
    end

    local mods = self._modifiers[attrName] or {}

    -- Derived attribute: use compute function
    if def.derived and def.compute then
        -- Build values table for compute function
        local values = {}
        for name, _ in pairs(self._schema) do
            values[name] = self._computedValues[name] or self._baseValues[name]
        end

        -- Build modifiers summary for this attribute
        local modSummary = self:_aggregateModifiers(mods)

        return def.compute(values, modSummary)
    end

    -- Base attribute: aggregate modifiers on base value
    local base = self._baseValues[attrName] or def.default or 0

    -- Apply modifiers
    local modSummary = self:_aggregateModifiers(mods)

    -- Override takes precedence
    if modSummary.override ~= nil then
        base = modSummary.override
    else
        -- Additive first, then multiplicative
        base = base + (modSummary.additive or 0)
        base = base * (modSummary.multiplicative or 1)
    end

    -- Clamp to min/max
    if def.min ~= nil and base < def.min then
        base = def.min
    end
    if def.max ~= nil and base > def.max then
        base = def.max
    end

    return base
end

--[[
    Aggregate all modifiers into summary values.

    @param mods table - { additive = {...}, multiplicative = {...}, override = {...} }
    @return table - { additive = sum, multiplicative = product, override = value|nil }
--]]
function AttributeSet:_aggregateModifiers(mods)
    local result = {
        additive = 0,
        multiplicative = 1,
        override = nil,
    }

    -- Sum all additive modifiers
    for _, mod in ipairs(mods.additive or {}) do
        result.additive = result.additive + mod.value
    end

    -- Multiply all multiplicative modifiers
    for _, mod in ipairs(mods.multiplicative or {}) do
        result.multiplicative = result.multiplicative * mod.value
    end

    -- Find highest priority override
    local highestPriority = -math.huge
    for _, mod in ipairs(mods.override or {}) do
        local priority = mod.priority or 0
        if priority > highestPriority then
            highestPriority = priority
            result.override = mod.value
        end
    end

    return result
end

--[[
    Recompute an attribute and all its dependents.
    Fires change notifications as needed.

    @param attrName string - Starting attribute
--]]
function AttributeSet:_recomputeAndNotify(attrName)
    -- Find all attributes that need recomputation (in order)
    local toRecompute = { attrName }
    local visited = { [attrName] = true }

    -- BFS to find all dependents
    local queue = { attrName }
    while #queue > 0 do
        local current = table.remove(queue, 1)
        for _, dependent in ipairs(self._dependents[current] or {}) do
            if not visited[dependent] then
                visited[dependent] = true
                table.insert(toRecompute, dependent)
                table.insert(queue, dependent)
            end
        end
    end

    -- Sort toRecompute by dependency order
    local orderIndex = {}
    for i, name in ipairs(self._dependencyOrder) do
        orderIndex[name] = i
    end
    table.sort(toRecompute, function(a, b)
        return (orderIndex[a] or 0) < (orderIndex[b] or 0)
    end)

    -- Recompute and notify
    for _, name in ipairs(toRecompute) do
        local oldValue = self._computedValues[name]
        local newValue = self:_computeValue(name)

        if oldValue ~= newValue then
            self._computedValues[name] = newValue
            self:_notifyChange(name, newValue, oldValue)
        end
    end
end

--------------------------------------------------------------------------------
-- NOTIFICATIONS
--------------------------------------------------------------------------------

--[[
    Notify subscribers of an attribute change.

    @param attrName string
    @param newValue any
    @param oldValue any
--]]
function AttributeSet:_notifyChange(attrName, newValue, oldValue)
    -- Specific subscriptions
    for _, callback in ipairs(self._subscriptions[attrName] or {}) do
        task.spawn(callback, newValue, oldValue, attrName)
    end

    -- All subscriptions
    for _, callback in ipairs(self._allSubscriptions) do
        task.spawn(callback, attrName, newValue, oldValue)
    end
end

--------------------------------------------------------------------------------
-- PUBLIC API: GET/SET
--------------------------------------------------------------------------------

--[[
    Get the computed value of an attribute.

    @param attrName string
    @return any
--]]
function AttributeSet:get(attrName)
    return self._computedValues[attrName]
end

--[[
    Get the base value of an attribute (before modifiers).

    @param attrName string
    @return any
--]]
function AttributeSet:getBase(attrName)
    return self._baseValues[attrName]
end

--[[
    Set the base value of an attribute.
    Triggers recomputation and notifications.

    @param attrName string
    @param value any
--]]
function AttributeSet:setBase(attrName, value)
    local def = self._schema[attrName]
    if not def then
        warn("[AttributeSet] Unknown attribute:", attrName)
        return
    end

    if def.derived then
        warn("[AttributeSet] Cannot set base value of derived attribute:", attrName)
        return
    end

    self._baseValues[attrName] = value
    self:_recomputeAndNotify(attrName)
end

--[[
    Get all computed values as a table.

    @return table
--]]
function AttributeSet:getAll()
    local result = {}
    for attrName, value in pairs(self._computedValues) do
        result[attrName] = value
    end
    return result
end

--[[
    Get schema definition for an attribute.

    @param attrName string
    @return table|nil
--]]
function AttributeSet:getSchema(attrName)
    return self._schema[attrName]
end

--[[
    Check if an attribute should replicate to clients.

    @param attrName string
    @return boolean
--]]
function AttributeSet:shouldReplicate(attrName)
    local def = self._schema[attrName]
    return def and def.replicate == true
end

--[[
    Get all attributes that should replicate.

    @return table - { attrName = value, ... }
--]]
function AttributeSet:getReplicatedValues()
    local result = {}
    for attrName, value in pairs(self._computedValues) do
        if self:shouldReplicate(attrName) then
            result[attrName] = value
        end
    end
    return result
end

--------------------------------------------------------------------------------
-- PUBLIC API: MODIFIERS
--------------------------------------------------------------------------------

--[[
    Apply a modifier to an attribute.

    @param attrName string - Attribute to modify
    @param modifier table - { operation, value, source, priority? }
    @return number - Modifier ID for removal
--]]
function AttributeSet:applyModifier(attrName, modifier)
    local def = self._schema[attrName]
    if not def then
        warn("[AttributeSet] Unknown attribute:", attrName)
        return nil
    end

    local operation = modifier.operation or "additive"
    local mods = self._modifiers[attrName]
    if not mods[operation] then
        warn("[AttributeSet] Unknown operation:", operation)
        return nil
    end

    -- Create modifier entry
    local modId = self._nextModifierId
    self._nextModifierId = self._nextModifierId + 1

    local entry = {
        id = modId,
        value = modifier.value,
        source = modifier.source or "unknown",
        priority = modifier.priority or 0,
    }

    -- Store in operation list
    table.insert(mods[operation], entry)

    -- Store by ID for removal
    self._modifierById[modId] = {
        attribute = attrName,
        operation = operation,
        entry = entry,
    }

    -- Recompute
    self:_recomputeAndNotify(attrName)

    return modId
end

--[[
    Remove a modifier by ID.

    @param modId number - Modifier ID
    @return boolean - Success
--]]
function AttributeSet:removeModifier(modId)
    local info = self._modifierById[modId]
    if not info then
        return false
    end

    local mods = self._modifiers[info.attribute]
    local opList = mods[info.operation]

    -- Find and remove
    for i, entry in ipairs(opList) do
        if entry.id == modId then
            table.remove(opList, i)
            break
        end
    end

    self._modifierById[modId] = nil
    self:_recomputeAndNotify(info.attribute)

    return true
end

--[[
    Remove all modifiers from a specific source.

    @param source string - Source identifier
    @return number - Count of modifiers removed
--]]
function AttributeSet:removeModifiersFromSource(source)
    local toRemove = {}

    for modId, info in pairs(self._modifierById) do
        if info.entry.source == source then
            table.insert(toRemove, modId)
        end
    end

    for _, modId in ipairs(toRemove) do
        self:removeModifier(modId)
    end

    return #toRemove
end

--[[
    Get all active modifiers for an attribute.

    @param attrName string
    @return table - { additive = {...}, multiplicative = {...}, override = {...} }
--]]
function AttributeSet:getModifiers(attrName)
    return self._modifiers[attrName]
end

--[[
    Get all modifier IDs from a specific source.

    @param source string
    @return table - Array of modifier IDs
--]]
function AttributeSet:getModifiersBySource(source)
    local result = {}
    for modId, info in pairs(self._modifierById) do
        if info.entry.source == source then
            table.insert(result, modId)
        end
    end
    return result
end

--------------------------------------------------------------------------------
-- PUBLIC API: SUBSCRIPTIONS
--------------------------------------------------------------------------------

--[[
    Subscribe to changes on a specific attribute.

    @param attrName string
    @param callback function(newValue, oldValue, attrName)
    @return function - Unsubscribe function
--]]
function AttributeSet:subscribe(attrName, callback)
    if not self._subscriptions[attrName] then
        self._subscriptions[attrName] = {}
    end

    table.insert(self._subscriptions[attrName], callback)

    -- Return unsubscribe function
    return function()
        local subs = self._subscriptions[attrName]
        if subs then
            for i, cb in ipairs(subs) do
                if cb == callback then
                    table.remove(subs, i)
                    break
                end
            end
        end
    end
end

--[[
    Subscribe to changes on any attribute.

    @param callback function(attrName, newValue, oldValue)
    @return function - Unsubscribe function
--]]
function AttributeSet:subscribeAll(callback)
    table.insert(self._allSubscriptions, callback)

    -- Return unsubscribe function
    return function()
        for i, cb in ipairs(self._allSubscriptions) do
            if cb == callback then
                table.remove(self._allSubscriptions, i)
                break
            end
        end
    end
end

--------------------------------------------------------------------------------
-- UTILITY
--------------------------------------------------------------------------------

--[[
    Get debug info about the attribute set.

    @return table
--]]
function AttributeSet:getDebugInfo()
    local modifierCount = 0
    for _ in pairs(self._modifierById) do
        modifierCount = modifierCount + 1
    end

    return {
        attributeCount = self:_countAttributes(),
        modifierCount = modifierCount,
        dependencyOrder = self._dependencyOrder,
        baseValues = self._baseValues,
        computedValues = self._computedValues,
    }
end

return AttributeSet
