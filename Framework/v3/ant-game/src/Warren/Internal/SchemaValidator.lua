--[[
    Warren Framework v2
    SchemaValidator.lua - Schema-Based Payload Validation

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    SchemaValidator provides declarative validation for message payloads.
    Used by Orchestrator to validate signals between components and
    especially for Client->Server message security.

    ============================================================================
    SCHEMA FORMAT
    ============================================================================

    A schema is a table mapping field names to field definitions:

    ```lua
    local schema = {
        entity = { type = "Instance", required = true },
        entityId = { type = "string", required = true },
        count = { type = "number", range = { min = 1, max = 100 }, default = 1 },
        rarity = { type = "string", enum = { "Common", "Rare", "Epic", "Legendary" } },
        customCheck = { type = "any", validator = function(v) return v ~= nil end },
    }
    ```

    ============================================================================
    SUPPORTED TYPES
    ============================================================================

    Lua types:
        - "string"
        - "number"
        - "boolean"
        - "table"
        - "function"
        - "any" (accepts anything non-nil, or nil if not required)

    Roblox types:
        - "Instance" (any Roblox Instance)
        - "Player" (Player object)
        - "Model" (Model instance)
        - "Part" (BasePart instance)
        - "Vector3"
        - "CFrame"
        - "Color3"
        - "BrickColor"
        - "Enum" (any Enum value)
        - "EnumItem" (specific EnumItem)

    ============================================================================
    FIELD OPTIONS
    ============================================================================

    type: string (required)
        The expected type name

    required: boolean (default false)
        If true, field must be present and non-nil

    enum: string[] (optional)
        For string type, list of allowed values

    range: { min?: number, max?: number } (optional)
        For number type, valid range

    default: any (optional)
        Default value injected if field is missing

    validator: function(value, fieldName, payload) -> boolean, error? (optional)
        Custom validation function

    ============================================================================
    USAGE
    ============================================================================

    ```lua
    local SchemaValidator = require(Lib.Internal.SchemaValidator)

    local schema = {
        playerId = { type = "number", required = true },
        itemId = { type = "string", required = true },
        quantity = { type = "number", range = { min = 1, max = 99 }, default = 1 },
    }

    local payload = { playerId = 12345, itemId = "sword" }

    -- Validate
    local valid, errors = SchemaValidator.validate(payload, schema)
    if not valid then
        for _, err in ipairs(errors) do
            print(err.field, err.message)
        end
    end

    -- Validate and inject defaults
    local valid, errors, processed = SchemaValidator.validateAndProcess(payload, schema)
    -- processed.quantity == 1 (injected default)

    -- Whitelist only declared fields (security)
    local sanitized = SchemaValidator.sanitize(payload, schema)
    ```

--]]

local Players = game:GetService("Players")

local SchemaValidator = {}

--------------------------------------------------------------------------------
-- TYPE CHECKERS
--------------------------------------------------------------------------------

local TYPE_CHECKERS = {
    -- Lua types
    string = function(v) return type(v) == "string" end,
    number = function(v) return type(v) == "number" end,
    boolean = function(v) return type(v) == "boolean" end,
    table = function(v) return type(v) == "table" end,
    ["function"] = function(v) return type(v) == "function" end,
    any = function(v) return true end,  -- Any type allowed

    -- Roblox types
    Instance = function(v) return typeof(v) == "Instance" end,
    Player = function(v) return typeof(v) == "Instance" and v:IsA("Player") end,
    Model = function(v) return typeof(v) == "Instance" and v:IsA("Model") end,
    Part = function(v) return typeof(v) == "Instance" and v:IsA("BasePart") end,
    Vector3 = function(v) return typeof(v) == "Vector3" end,
    CFrame = function(v) return typeof(v) == "CFrame" end,
    Color3 = function(v) return typeof(v) == "Color3" end,
    BrickColor = function(v) return typeof(v) == "BrickColor" end,
    Enum = function(v) return typeof(v) == "Enum" end,
    EnumItem = function(v) return typeof(v) == "EnumItem" end,
}

--[[
    Get a type checker function for a type name.

    @param typeName string - The type name
    @return function|nil - Type checker function or nil if unknown
--]]
function SchemaValidator.getTypeChecker(typeName)
    return TYPE_CHECKERS[typeName]
end

--[[
    Check if a type name is supported.

    @param typeName string - The type name
    @return boolean
--]]
function SchemaValidator.isValidType(typeName)
    return TYPE_CHECKERS[typeName] ~= nil
end

--[[
    Get all supported type names.

    @return string[]
--]]
function SchemaValidator.getSupportedTypes()
    local types = {}
    for typeName in pairs(TYPE_CHECKERS) do
        table.insert(types, typeName)
    end
    return types
end

--------------------------------------------------------------------------------
-- FIELD VALIDATION
--------------------------------------------------------------------------------

--[[
    Validate a single field value against a field definition.

    @param value any - The value to validate
    @param fieldDef table - The field definition
    @param fieldName string - The field name (for error messages)
    @param payload table - The full payload (for custom validators)
    @return boolean, string? - Valid flag and optional error message
--]]
function SchemaValidator.validateField(value, fieldDef, fieldName, payload)
    -- Check required
    if value == nil then
        if fieldDef.required then
            return false, string.format("Field '%s' is required", fieldName)
        end
        -- Not required and nil is OK
        return true, nil
    end

    -- Get type checker
    local typeName = fieldDef.type
    if not typeName then
        return false, string.format("Field '%s' has no type definition", fieldName)
    end

    local checker = TYPE_CHECKERS[typeName]
    if not checker then
        return false, string.format("Field '%s' has unknown type '%s'", fieldName, typeName)
    end

    -- Type check
    if not checker(value) then
        local actualType = typeof(value)
        return false, string.format(
            "Field '%s' expected type '%s', got '%s'",
            fieldName, typeName, actualType
        )
    end

    -- Enum check (for strings)
    if fieldDef.enum and typeName == "string" then
        local found = false
        for _, allowed in ipairs(fieldDef.enum) do
            if value == allowed then
                found = true
                break
            end
        end
        if not found then
            return false, string.format(
                "Field '%s' value '%s' not in allowed values: %s",
                fieldName, tostring(value), table.concat(fieldDef.enum, ", ")
            )
        end
    end

    -- Range check (for numbers)
    if fieldDef.range and typeName == "number" then
        local min = fieldDef.range.min
        local max = fieldDef.range.max

        if min and value < min then
            return false, string.format(
                "Field '%s' value %s is below minimum %s",
                fieldName, tostring(value), tostring(min)
            )
        end

        if max and value > max then
            return false, string.format(
                "Field '%s' value %s is above maximum %s",
                fieldName, tostring(value), tostring(max)
            )
        end
    end

    -- Custom validator
    if fieldDef.validator and type(fieldDef.validator) == "function" then
        local valid, customError = fieldDef.validator(value, fieldName, payload)
        if not valid then
            return false, customError or string.format(
                "Field '%s' failed custom validation",
                fieldName
            )
        end
    end

    return true, nil
end

--------------------------------------------------------------------------------
-- SCHEMA VALIDATION
--------------------------------------------------------------------------------

--[[
    Validate a payload against a schema.

    Returns validation result and array of error objects.

    @param payload table - The payload to validate
    @param schema table - The schema definition
    @return boolean, table - Valid flag and array of errors
--]]
function SchemaValidator.validate(payload, schema)
    if type(payload) ~= "table" then
        return false, {{ field = "_payload", message = "Payload must be a table" }}
    end

    if type(schema) ~= "table" then
        return false, {{ field = "_schema", message = "Schema must be a table" }}
    end

    local errors = {}

    for fieldName, fieldDef in pairs(schema) do
        local value = payload[fieldName]
        local valid, errMsg = SchemaValidator.validateField(value, fieldDef, fieldName, payload)

        if not valid then
            table.insert(errors, {
                field = fieldName,
                message = errMsg,
                expected = fieldDef.type,
                received = value ~= nil and typeof(value) or "nil",
            })
        end
    end

    return #errors == 0, errors
end

--[[
    Validate a payload and process it (inject defaults).

    Returns the processed payload with defaults injected.

    @param payload table - The payload to validate
    @param schema table - The schema definition
    @return boolean, table, table - Valid flag, errors, and processed payload
--]]
function SchemaValidator.validateAndProcess(payload, schema)
    if type(payload) ~= "table" then
        return false, {{ field = "_payload", message = "Payload must be a table" }}, {}
    end

    if type(schema) ~= "table" then
        return false, {{ field = "_schema", message = "Schema must be a table" }}, {}
    end

    local errors = {}
    local processed = {}

    -- Copy existing payload values
    for k, v in pairs(payload) do
        processed[k] = v
    end

    -- Validate and inject defaults
    for fieldName, fieldDef in pairs(schema) do
        local value = payload[fieldName]

        -- Inject default if missing
        if value == nil and fieldDef.default ~= nil then
            processed[fieldName] = fieldDef.default
            value = fieldDef.default
        end

        local valid, errMsg = SchemaValidator.validateField(value, fieldDef, fieldName, payload)

        if not valid then
            table.insert(errors, {
                field = fieldName,
                message = errMsg,
                expected = fieldDef.type,
                received = value ~= nil and typeof(value) or "nil",
            })
        end
    end

    return #errors == 0, errors, processed
end

--[[
    Sanitize a payload to only include fields declared in schema.

    Used for security to prevent extra fields from being passed through.

    @param payload table - The payload to sanitize
    @param schema table - The schema definition
    @return table - Sanitized payload with only declared fields
--]]
function SchemaValidator.sanitize(payload, schema)
    if type(payload) ~= "table" or type(schema) ~= "table" then
        return {}
    end

    local sanitized = {}

    for fieldName, fieldDef in pairs(schema) do
        local value = payload[fieldName]

        if value ~= nil then
            sanitized[fieldName] = value
        elseif fieldDef.default ~= nil then
            sanitized[fieldName] = fieldDef.default
        end
    end

    return sanitized
end

--------------------------------------------------------------------------------
-- SCHEMA UTILITIES
--------------------------------------------------------------------------------

--[[
    Validate a schema definition itself.

    Checks that all field definitions are valid.

    @param schema table - The schema to validate
    @return boolean, string? - Valid flag and optional error message
--]]
function SchemaValidator.validateSchema(schema)
    if type(schema) ~= "table" then
        return false, "Schema must be a table"
    end

    for fieldName, fieldDef in pairs(schema) do
        if type(fieldDef) ~= "table" then
            return false, string.format("Field '%s' definition must be a table", fieldName)
        end

        if not fieldDef.type then
            return false, string.format("Field '%s' must have a type", fieldName)
        end

        if not TYPE_CHECKERS[fieldDef.type] then
            return false, string.format(
                "Field '%s' has unknown type '%s'",
                fieldName, fieldDef.type
            )
        end

        if fieldDef.enum and fieldDef.type ~= "string" then
            return false, string.format(
                "Field '%s' has enum but type is not 'string'",
                fieldName
            )
        end

        if fieldDef.range and fieldDef.type ~= "number" then
            return false, string.format(
                "Field '%s' has range but type is not 'number'",
                fieldName
            )
        end

        if fieldDef.validator and type(fieldDef.validator) ~= "function" then
            return false, string.format(
                "Field '%s' validator must be a function",
                fieldName
            )
        end
    end

    return true, nil
end

--[[
    Merge two schemas together.

    Fields from second schema override first schema.

    @param base table - Base schema
    @param extension table - Extension schema
    @return table - Merged schema
--]]
function SchemaValidator.mergeSchemas(base, extension)
    local merged = {}

    -- Copy base
    if type(base) == "table" then
        for k, v in pairs(base) do
            merged[k] = v
        end
    end

    -- Override with extension
    if type(extension) == "table" then
        for k, v in pairs(extension) do
            merged[k] = v
        end
    end

    return merged
end

--[[
    Format errors into a human-readable string.

    @param errors table - Array of error objects
    @return string - Formatted error message
--]]
function SchemaValidator.formatErrors(errors)
    if not errors or #errors == 0 then
        return "No errors"
    end

    local lines = {}
    for i, err in ipairs(errors) do
        table.insert(lines, string.format("%d. %s", i, err.message or "Unknown error"))
    end

    return table.concat(lines, "\n")
end

--------------------------------------------------------------------------------
-- CLIENT VALIDATION HELPERS
--------------------------------------------------------------------------------

--[[
    Validate that a Player field matches the actual sender.

    Used for Client->Server message security.

    @param payload table - The payload
    @param playerFieldName string - Name of the field containing Player
    @param actualPlayer Player - The actual player who sent the message
    @return boolean, string? - Valid flag and optional error message
--]]
function SchemaValidator.validateSender(payload, playerFieldName, actualPlayer)
    if not payload or type(payload) ~= "table" then
        return false, "Payload must be a table"
    end

    local claimedPlayer = payload[playerFieldName]

    if claimedPlayer == nil then
        -- No player field, could be optional
        return true, nil
    end

    if typeof(claimedPlayer) ~= "Instance" or not claimedPlayer:IsA("Player") then
        return false, string.format("Field '%s' must be a Player", playerFieldName)
    end

    if claimedPlayer ~= actualPlayer then
        return false, string.format(
            "Field '%s' player mismatch: claimed %s but actual sender is %s",
            playerFieldName,
            claimedPlayer.Name,
            actualPlayer.Name
        )
    end

    return true, nil
end

return SchemaValidator
