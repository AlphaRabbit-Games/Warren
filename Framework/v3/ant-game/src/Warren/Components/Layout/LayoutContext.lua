--[[
    Warren Framework v2
    LayoutContext.lua - Central Layout Data Context

    Copyright (c) 2026 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    LayoutContext is the central, authoritative data store for layout planning.
    All planners read from and write to this context, ensuring:

    - Single source of truth for all geometry data
    - Read-only access for position calculations
    - Conflict detection (e.g., spawn vs door positions)
    - Clear data flow and dependencies

    ============================================================================
    USAGE
    ============================================================================

    ```lua
    local ctx = LayoutContext.new(config)

    -- Planners write their results
    ctx:setRooms(rooms)
    ctx:setDoors(doors)

    -- Planners read existing data for positioning decisions
    local doors = ctx:getDoors()
    local hasConflict = ctx:positionConflictsWithDoor(pos, radius)

    -- Export final layout
    local layout = ctx:toLayout()
    ```

--]]

local LayoutContext = {}
LayoutContext.__index = LayoutContext

--------------------------------------------------------------------------------
-- CONSTRUCTOR
--------------------------------------------------------------------------------

function LayoutContext.new(config)
    local self = setmetatable({}, LayoutContext)

    self.config = config or {}
    self.rooms = {}
    self.doors = {}
    self.trusses = {}
    self.lights = {}
    self.pads = {}
    self.spawn = nil

    return self
end

--------------------------------------------------------------------------------
-- SETTERS (for planners to write results)
--------------------------------------------------------------------------------

function LayoutContext:setRooms(rooms)
    self.rooms = rooms
end

function LayoutContext:setDoors(doors)
    self.doors = doors
end

function LayoutContext:setTrusses(trusses)
    self.trusses = trusses
end

function LayoutContext:setLights(lights)
    self.lights = lights
end

function LayoutContext:setPads(pads)
    self.pads = pads
end

function LayoutContext:setSpawn(spawn)
    self.spawn = spawn
end

--------------------------------------------------------------------------------
-- GETTERS (read-only access for planners)
--------------------------------------------------------------------------------

function LayoutContext:getConfig()
    return self.config
end

function LayoutContext:getRooms()
    return self.rooms
end

function LayoutContext:getRoom(roomId)
    return self.rooms[roomId]
end

function LayoutContext:getRoomCount()
    local count = 0
    for _ in pairs(self.rooms) do
        count = count + 1
    end
    return count
end

function LayoutContext:getDoors()
    return self.doors
end

function LayoutContext:getTrusses()
    return self.trusses
end

function LayoutContext:getLights()
    return self.lights
end

function LayoutContext:getPads()
    return self.pads
end

function LayoutContext:getSpawn()
    return self.spawn
end

--------------------------------------------------------------------------------
-- QUERY HELPERS (for conflict detection)
--------------------------------------------------------------------------------

-- Get all doors connected to a specific room
function LayoutContext:getDoorsForRoom(roomId)
    local result = {}
    for _, door in ipairs(self.doors) do
        if door.fromRoom == roomId or door.toRoom == roomId then
            table.insert(result, door)
        end
    end
    return result
end

-- Check if a position conflicts with any door opening
function LayoutContext:positionConflictsWithDoor(pos, radius)
    radius = radius or 3  -- Default check radius

    for _, door in ipairs(self.doors) do
        local dx = math.abs(pos[1] - door.center[1])
        local dy = math.abs(pos[2] - door.center[2])
        local dz = math.abs(pos[3] - door.center[3])

        -- Check if within door bounds + radius
        local halfW = door.width / 2 + radius
        local halfH = door.height / 2 + radius

        if door.axis == 2 then
            -- Ceiling hole - check XZ overlap (ignore Y, we don't want to place anything in the hole)
            if dx < halfW and dz < halfH then
                return true, door
            end
        else
            -- Horizontal door (wall)
            if door.axis == 1 then
                -- X-axis door
                if dz < halfW and dy < halfH and dx < radius then
                    return true, door
                end
            else
                -- Z-axis door
                if dx < halfW and dy < halfH and dz < radius then
                    return true, door
                end
            end
        end
    end

    return false, nil
end

-- Check if a position conflicts with any placed object
-- For floor placement, also checks XZ overlap with vertical trusses (ceiling holes)
function LayoutContext:positionConflictsWithObject(pos, radius)
    radius = radius or 2

    -- Check trusses
    for _, truss in ipairs(self.trusses) do
        local dx = math.abs(pos[1] - truss.position[1])
        local dy = math.abs(pos[2] - truss.position[2])
        local dz = math.abs(pos[3] - truss.position[3])

        -- Standard 3D overlap check
        if dx < truss.size[1]/2 + radius and
           dy < truss.size[2]/2 + radius and
           dz < truss.size[3]/2 + radius then
            return true, "truss", truss
        end

        -- Additional check for ceiling trusses: XZ overlap only
        -- A ceiling truss (type="ceiling") spans vertically, so we want to avoid
        -- placing floor objects directly under it, even if Y doesn't overlap
        if truss.type == "ceiling" then
            -- Larger XZ exclusion zone for ceiling trusses (ladder access area)
            local ceilingRadius = radius + 2
            if dx < truss.size[1]/2 + ceilingRadius and
               dz < truss.size[3]/2 + ceilingRadius then
                return true, "truss_ceiling", truss
            end
        end
    end

    -- Check pads
    for _, pad in ipairs(self.pads) do
        local dx = math.abs(pos[1] - pad.position[1])
        local dz = math.abs(pos[3] - pad.position[3])
        if dx < 3 + radius and dz < 3 + radius then
            return true, "pad", pad
        end
    end

    -- Check lights
    for _, light in ipairs(self.lights) do
        local dx = math.abs(pos[1] - light.position[1])
        local dy = math.abs(pos[2] - light.position[2])
        local dz = math.abs(pos[3] - light.position[3])
        if dx < light.size[1]/2 + radius and
           dy < light.size[2]/2 + radius and
           dz < light.size[3]/2 + radius then
            return true, "light", light
        end
    end

    return false, nil, nil
end

-- Find a safe position in a room (away from doors and objects)
-- Returns nil if no safe position can be found
function LayoutContext:findSafeFloorPosition(roomId, preferredOffset)
    local room = self.rooms[roomId]
    if not room then return nil end

    preferredOffset = preferredOffset or { 0, 0, 0 }
    local floorY = room.position[2] - room.dims[2] / 2 + 0.5

    -- Try positions: center, then corners, then edges
    -- Using smaller fractions to avoid door areas which are typically at walls
    local candidates = {
        { room.position[1], floorY, room.position[3] },  -- Center
        { room.position[1] - room.dims[1]/4, floorY, room.position[3] - room.dims[3]/4 },  -- Corner 1
        { room.position[1] + room.dims[1]/4, floorY, room.position[3] - room.dims[3]/4 },  -- Corner 2
        { room.position[1] - room.dims[1]/4, floorY, room.position[3] + room.dims[3]/4 },  -- Corner 3
        { room.position[1] + room.dims[1]/4, floorY, room.position[3] + room.dims[3]/4 },  -- Corner 4
        { room.position[1] - room.dims[1]/3, floorY, room.position[3] },  -- Edge 1
        { room.position[1] + room.dims[1]/3, floorY, room.position[3] },  -- Edge 2
        { room.position[1], floorY, room.position[3] - room.dims[3]/3 },  -- Edge 3
        { room.position[1], floorY, room.position[3] + room.dims[3]/3 },  -- Edge 4
        -- Additional interior positions for larger rooms
        { room.position[1] - room.dims[1]/6, floorY, room.position[3] - room.dims[3]/6 },
        { room.position[1] + room.dims[1]/6, floorY, room.position[3] - room.dims[3]/6 },
        { room.position[1] - room.dims[1]/6, floorY, room.position[3] + room.dims[3]/6 },
        { room.position[1] + room.dims[1]/6, floorY, room.position[3] + room.dims[3]/6 },
    }

    -- Use radius of 4 to account for pad size (6x6) plus margin
    local checkRadius = 4

    for _, pos in ipairs(candidates) do
        local conflictsDoor = self:positionConflictsWithDoor(pos, checkRadius)
        local conflictsObj = self:positionConflictsWithObject(pos, checkRadius)

        if not conflictsDoor and not conflictsObj then
            return pos
        end
    end

    -- No safe position found - return nil so caller can handle appropriately
    return nil
end

-- Get the floor Y position for a room
function LayoutContext:getRoomFloorY(roomId)
    local room = self.rooms[roomId]
    if not room then return nil end
    return room.position[2] - room.dims[2] / 2
end

--------------------------------------------------------------------------------
-- EXPORT
--------------------------------------------------------------------------------

function LayoutContext:toLayout()
    local LayoutSchema = require(script.Parent.LayoutSchema)

    local layout = LayoutSchema.createEmpty()
    layout.seed = self.config.seed or 0
    layout.regionNum = self.config.regionNum or 1
    layout.config = {
        wallThickness = self.config.wallThickness or 1,
        material = self.config.material or "Brick",
        color = self.config.color or { 140, 110, 90 },
        doorSize = self.config.doorSize or 12,
    }

    -- Store domain-specific seeds for future regeneration
    -- Each domain can be regenerated independently
    layout.seeds = self.config.seeds or {
        rooms = layout.seed,
        doors = layout.seed + 10000,
        trusses = layout.seed + 20000,
        lights = layout.seed + 30000,
    }

    layout.rooms = self.rooms
    layout.doors = self.doors
    layout.trusses = self.trusses
    layout.lights = self.lights
    layout.pads = self.pads
    layout.spawn = self.spawn

    return layout
end

return LayoutContext
