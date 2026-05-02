--[[
    Warren Framework v2
    GeometryDef.lua - Shared Geometry Definition (Layout DOM)

    Copyright (c) 2026 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    GeometryDef is the single source of truth for layout data. It acts like a
    DOM - each planner node reads existing data and adds its own nodes.

    The def starts empty (or partially filled for predefined layouts) and gets
    progressively enriched as it passes through the pipeline:

        RoomPlanner → DoorPlanner → TrussPlanner → LightPlanner → PadPlanner
                                        ↓
                            ShellBuilder / TerrainBuilder

    ============================================================================
    USAGE
    ============================================================================

    -- Create empty def (for procedural generation)
    local def = GeometryDef.new({ seed = 12345, regionNum = 1 })

    -- Create partial def (for predefined layouts)
    local def = GeometryDef.new({
        regionNum = 0,
        rooms = { ... },  -- predefined
        doors = { ... },  -- predefined
    })

    -- Planners add nodes
    def:addRoom({ id = 1, position = {...}, dims = {...} })
    def:addDoor({ id = 1, fromRoom = 1, toRoom = 2, ... })

    -- Query existing nodes
    local rooms = def:getRooms()
    local room = def:getRoom(1)
    local hasDoors = def:hasDoors()

--]]

local GeometryDef = {}
GeometryDef.__index = GeometryDef

--------------------------------------------------------------------------------
-- CONSTRUCTOR
--------------------------------------------------------------------------------

function GeometryDef.new(initial)
    initial = initial or {}

    local self = setmetatable({}, GeometryDef)

    -- Config
    self.seed = initial.seed or 0
    self.regionNum = initial.regionNum or 1

    -- Start with defaults, then merge user overrides
    self.config = {
        wallThickness = 1,
        doorSize = 12,
        floorThreshold = 5,
        material = "Brick",
        color = { 140, 110, 90 },
    }
    if initial.config then
        for k, v in pairs(initial.config) do
            self.config[k] = v
        end
    end

    -- Node collections (can be pre-populated)
    self.rooms = initial.rooms or {}
    self.doors = initial.doors or {}
    self.trusses = initial.trusses or {}
    self.lights = initial.lights or {}
    self.pads = initial.pads or {}
    self.spawn = initial.spawn or nil

    -- Counters for auto-incrementing IDs
    self._nextRoomId = 1
    self._nextDoorId = 1
    self._nextTrussId = 1
    self._nextLightId = 1
    self._nextPadId = 1

    -- Initialize counters based on existing data
    for id, _ in pairs(self.rooms) do
        if type(id) == "number" and id >= self._nextRoomId then
            self._nextRoomId = id + 1
        end
    end
    for _, door in ipairs(self.doors) do
        if door.id and door.id >= self._nextDoorId then
            self._nextDoorId = door.id + 1
        end
    end

    return self
end

--------------------------------------------------------------------------------
-- ROOM NODES
--------------------------------------------------------------------------------

function GeometryDef:hasRooms()
    return next(self.rooms) ~= nil
end

function GeometryDef:getRooms()
    return self.rooms
end

function GeometryDef:getRoom(id)
    return self.rooms[id]
end

function GeometryDef:getRoomCount()
    local count = 0
    for _ in pairs(self.rooms) do
        count = count + 1
    end
    return count
end

function GeometryDef:addRoom(room)
    local id = room.id or self._nextRoomId
    room.id = id
    self.rooms[id] = room
    if id >= self._nextRoomId then
        self._nextRoomId = id + 1
    end
    return id
end

--------------------------------------------------------------------------------
-- DOOR NODES
--------------------------------------------------------------------------------

function GeometryDef:hasDoors()
    return #self.doors > 0
end

function GeometryDef:getDoors()
    return self.doors
end

function GeometryDef:addDoor(door)
    local id = door.id or self._nextDoorId
    door.id = id
    table.insert(self.doors, door)
    if id >= self._nextDoorId then
        self._nextDoorId = id + 1
    end
    return id
end

function GeometryDef:getDoorsForRoom(roomId)
    local result = {}
    for _, door in ipairs(self.doors) do
        if door.fromRoom == roomId or door.toRoom == roomId then
            table.insert(result, door)
        end
    end
    return result
end

-- Alias for LayoutContext compatibility
function GeometryDef:getConfig()
    return self.config
end

--------------------------------------------------------------------------------
-- TRUSS NODES
--------------------------------------------------------------------------------

function GeometryDef:hasTrusses()
    return #self.trusses > 0
end

function GeometryDef:getTrusses()
    return self.trusses
end

function GeometryDef:addTruss(truss)
    local id = truss.id or self._nextTrussId
    truss.id = id
    table.insert(self.trusses, truss)
    if id >= self._nextTrussId then
        self._nextTrussId = id + 1
    end
    return id
end

--------------------------------------------------------------------------------
-- LIGHT NODES
--------------------------------------------------------------------------------

function GeometryDef:hasLights()
    return #self.lights > 0
end

function GeometryDef:getLights()
    return self.lights
end

function GeometryDef:addLight(light)
    local id = light.id or self._nextLightId
    light.id = id
    table.insert(self.lights, light)
    if id >= self._nextLightId then
        self._nextLightId = id + 1
    end
    return id
end

--------------------------------------------------------------------------------
-- PAD NODES
--------------------------------------------------------------------------------

function GeometryDef:hasPads()
    return #self.pads > 0
end

function GeometryDef:getPads()
    return self.pads
end

function GeometryDef:addPad(pad)
    local id = pad.id or ("pad_" .. self._nextPadId)
    pad.id = id
    table.insert(self.pads, pad)
    self._nextPadId = self._nextPadId + 1
    return id
end

--------------------------------------------------------------------------------
-- SPAWN
--------------------------------------------------------------------------------

function GeometryDef:hasSpawn()
    return self.spawn ~= nil
end

function GeometryDef:getSpawn()
    return self.spawn
end

function GeometryDef:setSpawn(spawn)
    self.spawn = spawn
end

--------------------------------------------------------------------------------
-- CONFLICT DETECTION (for placement)
--------------------------------------------------------------------------------

function GeometryDef:positionConflictsWithDoor(pos, radius)
    radius = radius or 3

    for _, door in ipairs(self.doors) do
        if door.center then
            local dx = math.abs(pos[1] - door.center[1])
            local dy = math.abs(pos[2] - door.center[2])
            local dz = math.abs(pos[3] - door.center[3])

            local halfW = (door.width or 12) / 2 + radius
            local halfH = (door.height or 12) / 2 + radius

            if door.axis == 2 then
                -- Ceiling hole
                if dx < halfW and dz < halfH then
                    return true, door
                end
            else
                -- Wall door
                if door.axis == 1 then
                    if dz < halfW and dy < halfH and dx < radius then
                        return true, door
                    end
                else
                    if dx < halfW and dy < halfH and dz < radius then
                        return true, door
                    end
                end
            end
        end
    end

    return false, nil
end

function GeometryDef:positionConflictsWithTruss(pos, radius)
    radius = radius or 2

    for _, truss in ipairs(self.trusses) do
        local dx = math.abs(pos[1] - truss.position[1])
        local dy = math.abs(pos[2] - truss.position[2])
        local dz = math.abs(pos[3] - truss.position[3])

        if dx < truss.size[1]/2 + radius and
           dy < truss.size[2]/2 + radius and
           dz < truss.size[3]/2 + radius then
            return true, truss
        end
    end

    return false, nil
end

--[[
    Find a safe floor position in a room (away from doors and trusses).
    Returns nil if no safe position can be found.
--]]
function GeometryDef:findSafeFloorPosition(roomId)
    local room = self.rooms[roomId]
    if not room then return nil end

    local floorY = room.position[2] - room.dims[2] / 2 + 0.5

    -- Try positions: center, then corners, then edges
    local candidates = {
        { room.position[1], floorY, room.position[3] },  -- Center
        { room.position[1] - room.dims[1]/4, floorY, room.position[3] - room.dims[3]/4 },
        { room.position[1] + room.dims[1]/4, floorY, room.position[3] - room.dims[3]/4 },
        { room.position[1] - room.dims[1]/4, floorY, room.position[3] + room.dims[3]/4 },
        { room.position[1] + room.dims[1]/4, floorY, room.position[3] + room.dims[3]/4 },
        { room.position[1] - room.dims[1]/3, floorY, room.position[3] },
        { room.position[1] + room.dims[1]/3, floorY, room.position[3] },
        { room.position[1], floorY, room.position[3] - room.dims[3]/3 },
        { room.position[1], floorY, room.position[3] + room.dims[3]/3 },
        { room.position[1] - room.dims[1]/6, floorY, room.position[3] - room.dims[3]/6 },
        { room.position[1] + room.dims[1]/6, floorY, room.position[3] - room.dims[3]/6 },
        { room.position[1] - room.dims[1]/6, floorY, room.position[3] + room.dims[3]/6 },
        { room.position[1] + room.dims[1]/6, floorY, room.position[3] + room.dims[3]/6 },
    }

    local checkRadius = 4  -- Account for pad size plus margin

    for _, pos in ipairs(candidates) do
        local conflictsDoor = self:positionConflictsWithDoor(pos, checkRadius)
        local conflictsTruss = self:positionConflictsWithTruss(pos, checkRadius)

        if not conflictsDoor and not conflictsTruss then
            return pos
        end
    end

    return nil
end

--------------------------------------------------------------------------------
-- EXPORT TO LAYOUT FORMAT (for LayoutInstantiator compatibility)
--------------------------------------------------------------------------------

function GeometryDef:toLayout()
    return {
        version = 1,
        seed = self.seed,
        regionNum = self.regionNum,
        config = self.config,
        rooms = self.rooms,
        doors = self.doors,
        trusses = self.trusses,
        lights = self.lights,
        pads = self.pads,
        spawn = self.spawn,
    }
end

--------------------------------------------------------------------------------
-- DEBUG
--------------------------------------------------------------------------------

function GeometryDef:debugPrint()
    print(string.format("[GeometryDef] Region %d, Seed %d", self.regionNum, self.seed))
    print(string.format("  Rooms: %d", self:getRoomCount()))
    print(string.format("  Doors: %d", #self.doors))
    print(string.format("  Trusses: %d", #self.trusses))
    print(string.format("  Lights: %d", #self.lights))
    print(string.format("  Pads: %d", #self.pads))
    print(string.format("  Spawn: %s", self.spawn and "yes" or "no"))
end

return GeometryDef
