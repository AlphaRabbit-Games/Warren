--[[
    Warren Framework v2
    LayoutSchema.lua - Layout Type Definitions and Validation

    Copyright (c) 2026 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    Defines the Layout data structure and provides validation utilities.
    A Layout is a complete description of a dungeon region that can be:
    - Generated from a seed (via LayoutBuilder)
    - Instantiated into parts (via LayoutInstantiator)
    - Serialized for storage (via LayoutSerializer)

    ============================================================================
    SCHEMA VERSION
    ============================================================================

    Version 1: Initial schema

--]]

local LayoutSchema = {}

--------------------------------------------------------------------------------
-- SCHEMA VERSION
--------------------------------------------------------------------------------

LayoutSchema.VERSION = 1

--------------------------------------------------------------------------------
-- TYPE DEFINITIONS (for documentation)
--------------------------------------------------------------------------------

--[[
    Vec3 = { [1]: number, [2]: number, [3]: number }  -- {x, y, z}

    Room = {
        id: number,
        position: Vec3,          -- Center of interior space
        dims: Vec3,              -- Interior dimensions {w, h, d}
        parentId: number?,       -- nil for first room
        attachFace: string?,     -- "N"|"S"|"E"|"W"|"U"|"D", nil for first room
    }

    Door = {
        id: number,
        fromRoom: number,        -- Room ID
        toRoom: number,          -- Room ID
        center: Vec3,            -- Center of door opening
        width: number,           -- Door width (horizontal)
        height: number,          -- Door height
        axis: number,            -- 1=X, 2=Y, 3=Z (which axis door faces)
        widthAxis: number,       -- Axis along which width is measured
    }

    Truss = {
        id: number,
        doorId: number,          -- Associated door
        position: Vec3,          -- Center of truss
        size: Vec3,              -- Truss dimensions
        type: string,            -- "wall"|"ceiling"
    }

    Light = {
        id: number,
        roomId: number,
        position: Vec3,          -- Center of light fixture
        size: Vec3,              -- Fixture dimensions
        wall: string,            -- "N"|"S"|"E"|"W" - which wall it's on
    }

    Pad = {
        id: string,              -- "pad_1", "pad_2", etc.
        roomId: number,
        position: Vec3,
    }

    Spawn = {
        position: Vec3,
        roomId: number,
    }

    Config = {
        wallThickness: number,
        material: string,        -- Enum.Material name
        color: Vec3,             -- {r, g, b} 0-255
        doorSize: number,
    }

    Layout = {
        version: number,
        seed: number,
        regionNum: number,           -- Region/area number (1, 2, 3...)
        rooms: { [number]: Room },
        doors: { Door },
        trusses: { Truss },
        lights: { Light },
        pads: { Pad },
        spawn: Spawn,
        config: Config,
    }
--]]

--------------------------------------------------------------------------------
-- FACTORY
--------------------------------------------------------------------------------

-- Create an empty layout structure
function LayoutSchema.createEmpty()
    return {
        version = LayoutSchema.VERSION,
        seed = 0,
        regionNum = 1,
        rooms = {},
        doors = {},
        trusses = {},
        lights = {},
        pads = {},
        spawn = nil,
        config = {
            wallThickness = 1,
            material = "Brick",
            color = { 140, 110, 90 },
            doorSize = 12,
        },
    }
end

--------------------------------------------------------------------------------
-- VALIDATION
--------------------------------------------------------------------------------

local function validateVec3(v, name)
    if type(v) ~= "table" then
        return false, name .. " must be a table"
    end
    if type(v[1]) ~= "number" or type(v[2]) ~= "number" or type(v[3]) ~= "number" then
        return false, name .. " must have 3 numbers"
    end
    return true
end

local function validateRoom(room, id)
    local prefix = "Room " .. tostring(id)

    if type(room.id) ~= "number" then
        return false, prefix .. ": id must be a number"
    end

    local ok, err = validateVec3(room.position, prefix .. " position")
    if not ok then return false, err end

    ok, err = validateVec3(room.dims, prefix .. " dims")
    if not ok then return false, err end

    -- parentId and attachFace can be nil for first room
    if room.parentId ~= nil and type(room.parentId) ~= "number" then
        return false, prefix .. ": parentId must be a number or nil"
    end

    return true
end

local function validateDoor(door, index)
    local prefix = "Door " .. tostring(index)

    if type(door.fromRoom) ~= "number" then
        return false, prefix .. ": fromRoom must be a number"
    end
    if type(door.toRoom) ~= "number" then
        return false, prefix .. ": toRoom must be a number"
    end

    local ok, err = validateVec3(door.center, prefix .. " center")
    if not ok then return false, err end

    if type(door.width) ~= "number" then
        return false, prefix .. ": width must be a number"
    end
    if type(door.height) ~= "number" then
        return false, prefix .. ": height must be a number"
    end
    if type(door.axis) ~= "number" then
        return false, prefix .. ": axis must be a number"
    end

    return true
end

-- Validate a complete layout
function LayoutSchema.validate(layout)
    if type(layout) ~= "table" then
        return false, "Layout must be a table"
    end

    if type(layout.version) ~= "number" then
        return false, "Layout version must be a number"
    end

    if layout.version > LayoutSchema.VERSION then
        return false, "Layout version " .. layout.version .. " is newer than supported " .. LayoutSchema.VERSION
    end

    if type(layout.seed) ~= "number" then
        return false, "Layout seed must be a number"
    end

    -- Validate rooms
    if type(layout.rooms) ~= "table" then
        return false, "Layout rooms must be a table"
    end
    for id, room in pairs(layout.rooms) do
        local ok, err = validateRoom(room, id)
        if not ok then return false, err end
    end

    -- Validate doors
    if type(layout.doors) ~= "table" then
        return false, "Layout doors must be a table"
    end
    for i, door in ipairs(layout.doors) do
        local ok, err = validateDoor(door, i)
        if not ok then return false, err end
    end

    -- Validate spawn
    if layout.spawn then
        local ok, err = validateVec3(layout.spawn.position, "Spawn position")
        if not ok then return false, err end
    end

    return true
end

--------------------------------------------------------------------------------
-- UTILITIES
--------------------------------------------------------------------------------

-- Deep copy a layout
function LayoutSchema.clone(layout)
    local function deepCopy(t)
        if type(t) ~= "table" then return t end
        local copy = {}
        for k, v in pairs(t) do
            copy[k] = deepCopy(v)
        end
        return copy
    end
    return deepCopy(layout)
end

-- Get room by ID
function LayoutSchema.getRoom(layout, roomId)
    return layout.rooms[roomId]
end

-- Get door between two rooms
function LayoutSchema.getDoorBetween(layout, roomA, roomB)
    for _, door in ipairs(layout.doors) do
        if (door.fromRoom == roomA and door.toRoom == roomB) or
           (door.fromRoom == roomB and door.toRoom == roomA) then
            return door
        end
    end
    return nil
end

-- Get all doors for a room
function LayoutSchema.getDoorsForRoom(layout, roomId)
    local doors = {}
    for _, door in ipairs(layout.doors) do
        if door.fromRoom == roomId or door.toRoom == roomId then
            table.insert(doors, door)
        end
    end
    return doors
end

-- Get light for a room
function LayoutSchema.getLightForRoom(layout, roomId)
    for _, light in ipairs(layout.lights) do
        if light.roomId == roomId then
            return light
        end
    end
    return nil
end

-- Get pad by ID
function LayoutSchema.getPad(layout, padId)
    for _, pad in ipairs(layout.pads) do
        if pad.id == padId then
            return pad
        end
    end
    return nil
end

-- Count rooms
function LayoutSchema.getRoomCount(layout)
    local count = 0
    for _ in pairs(layout.rooms) do
        count = count + 1
    end
    return count
end

return LayoutSchema
