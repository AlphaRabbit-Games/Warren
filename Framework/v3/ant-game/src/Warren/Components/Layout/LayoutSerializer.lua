--[[
    Warren Framework v2
    LayoutSerializer.lua - Layout Encoding/Decoding

    Copyright (c) 2026 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    LayoutSerializer encodes Layout tables to strings for storage (DataStore,
    file export, sharing) and decodes them back.

    ============================================================================
    USAGE
    ============================================================================

    ```lua
    local LayoutSerializer = require(...)

    -- Encode for storage
    local encoded = LayoutSerializer.encode(layout)

    -- Decode from storage
    local layout = LayoutSerializer.decode(encoded)
    ```

--]]

local HttpService = game:GetService("HttpService")
local LayoutSchema = require(script.Parent.LayoutSchema)

local LayoutSerializer = {}

--------------------------------------------------------------------------------
-- JSON ENCODING/DECODING
--------------------------------------------------------------------------------

function LayoutSerializer.encode(layout)
    -- Validate before encoding
    local ok, err = LayoutSchema.validate(layout)
    if not ok then
        warn("[LayoutSerializer] Encoding invalid layout: " .. err)
    end

    -- Convert to JSON
    local success, json = pcall(function()
        return HttpService:JSONEncode(layout)
    end)

    if not success then
        warn("[LayoutSerializer] Failed to encode layout: " .. tostring(json))
        return nil
    end

    return json
end

function LayoutSerializer.decode(encoded)
    if type(encoded) ~= "string" then
        warn("[LayoutSerializer] Expected string, got " .. type(encoded))
        return nil
    end

    -- Parse JSON
    local success, layout = pcall(function()
        return HttpService:JSONDecode(encoded)
    end)

    if not success then
        warn("[LayoutSerializer] Failed to decode layout: " .. tostring(layout))
        return nil
    end

    -- Validate after decoding
    local ok, err = LayoutSchema.validate(layout)
    if not ok then
        warn("[LayoutSerializer] Decoded invalid layout: " .. err)
        -- Still return it, let caller decide what to do
    end

    return layout
end

--------------------------------------------------------------------------------
-- COMPACT ENCODING (for DataStore efficiency)
--------------------------------------------------------------------------------

-- Shorten common keys for smaller JSON
local KEY_MAP = {
    version = "v",
    seed = "s",
    rooms = "r",
    doors = "d",
    trusses = "t",
    lights = "l",
    pads = "p",
    spawn = "sp",
    config = "c",
    position = "pos",
    dims = "dim",
    center = "ctr",
    width = "w",
    height = "h",
    size = "sz",
    parentId = "pid",
    attachFace = "af",
    fromRoom = "fr",
    toRoom = "tr",
    roomId = "rid",
    doorId = "did",
    wallThickness = "wt",
    material = "mat",
    color = "col",
    doorSize = "ds",
}

local KEY_UNMAP = {}
for long, short in pairs(KEY_MAP) do
    KEY_UNMAP[short] = long
end

local function shortenKeys(t)
    if type(t) ~= "table" then return t end

    local result = {}
    for k, v in pairs(t) do
        local newKey = KEY_MAP[k] or k
        result[newKey] = shortenKeys(v)
    end
    return result
end

local function expandKeys(t)
    if type(t) ~= "table" then return t end

    local result = {}
    for k, v in pairs(t) do
        local newKey = KEY_UNMAP[k] or k
        result[newKey] = expandKeys(v)
    end
    return result
end

function LayoutSerializer.encodeCompact(layout)
    local shortened = shortenKeys(layout)

    local success, json = pcall(function()
        return HttpService:JSONEncode(shortened)
    end)

    if not success then
        warn("[LayoutSerializer] Failed to encode compact layout: " .. tostring(json))
        return nil
    end

    return json
end

function LayoutSerializer.decodeCompact(encoded)
    if type(encoded) ~= "string" then
        warn("[LayoutSerializer] Expected string, got " .. type(encoded))
        return nil
    end

    local success, shortened = pcall(function()
        return HttpService:JSONDecode(encoded)
    end)

    if not success then
        warn("[LayoutSerializer] Failed to decode compact layout: " .. tostring(shortened))
        return nil
    end

    local layout = expandKeys(shortened)

    local ok, err = LayoutSchema.validate(layout)
    if not ok then
        warn("[LayoutSerializer] Decoded invalid layout: " .. err)
    end

    return layout
end

--------------------------------------------------------------------------------
-- SIZE ESTIMATION
--------------------------------------------------------------------------------

function LayoutSerializer.estimateSize(layout)
    local encoded = LayoutSerializer.encode(layout)
    if encoded then
        return #encoded
    end
    return 0
end

function LayoutSerializer.estimateCompactSize(layout)
    local encoded = LayoutSerializer.encodeCompact(layout)
    if encoded then
        return #encoded
    end
    return 0
end

return LayoutSerializer
