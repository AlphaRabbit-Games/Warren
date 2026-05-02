--[[
    Warren Framework v2
    LayoutBuilder.lua - Procedural Layout Generation

    Copyright (c) 2026 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    LayoutBuilder generates a complete Layout table from a seed and config.
    It performs all the procedural planning but creates NO parts - only data.

    This separates "what to build" from "building it", enabling:
    - Serialize layouts for persistence
    - Reload without regeneration
    - Inspect/debug layout data
    - Modify layouts before instantiation

    ============================================================================
    USAGE
    ============================================================================

    ```lua
    local LayoutBuilder = require(...)
    local layout = LayoutBuilder.generate({
        seed = 12345,
        origin = { 0, 20, 0 },
        mainPathLength = 8,
        spurCount = 4,
        -- ... other config
    })
    ```

--]]

local LayoutSchema = require(script.Parent.LayoutSchema)
local LayoutContext = require(script.Parent.LayoutContext)

local LayoutBuilder = {}

--------------------------------------------------------------------------------
-- FACE DEFINITIONS
--------------------------------------------------------------------------------

local FACES = {
    { axis = 1, dir =  1, name = "E" },  -- +X
    { axis = 1, dir = -1, name = "W" },  -- -X
    { axis = 2, dir =  1, name = "U" },  -- +Y (up)
    { axis = 2, dir = -1, name = "D" },  -- -Y (down)
    { axis = 3, dir =  1, name = "N" },  -- +Z
    { axis = 3, dir = -1, name = "S" },  -- -Z
}

local H_FACES = {
    { axis = 1, dir =  1, name = "E" },
    { axis = 1, dir = -1, name = "W" },
    { axis = 3, dir =  1, name = "N" },
    { axis = 3, dir = -1, name = "S" },
}

local V_FACES = {
    { axis = 2, dir =  1, name = "U" },
    { axis = 2, dir = -1, name = "D" },
}

local OPPOSITE_FACE = {
    N = "S", S = "N", E = "W", W = "E", U = "D", D = "U"
}

--------------------------------------------------------------------------------
-- GEOMETRY UTILITIES
--------------------------------------------------------------------------------

local function shuffle(arr)
    for i = #arr, 2, -1 do
        local j = math.random(1, i)
        arr[i], arr[j] = arr[j], arr[i]
    end
end

local function shellsOverlap(posA, dimsA, posB, dimsB, wallThickness)
    local shellA = {
        dimsA[1] + 2 * wallThickness,
        dimsA[2] + 2 * wallThickness,
        dimsA[3] + 2 * wallThickness,
    }
    local shellB = {
        dimsB[1] + 2 * wallThickness,
        dimsB[2] + 2 * wallThickness,
        dimsB[3] + 2 * wallThickness,
    }

    for axis = 1, 3 do
        local minA = posA[axis] - shellA[axis] / 2
        local maxA = posA[axis] + shellA[axis] / 2
        local minB = posB[axis] - shellB[axis] / 2
        local maxB = posB[axis] + shellB[axis] / 2

        local epsilon = 0.01
        if maxA <= minB + epsilon or maxB <= minA + epsilon then
            return false
        end
    end

    return true
end

local function overlapsAny(pos, dims, rooms, excludeId, wallThickness)
    for id, room in pairs(rooms) do
        if id ~= excludeId then
            if shellsOverlap(pos, dims, room.position, room.dims, wallThickness) then
                return true, id
            end
        end
    end
    return false
end

local function calculateAttachmentPosition(parentPos, parentDims, newDims, face, wallThickness)
    local newPos = { parentPos[1], parentPos[2], parentPos[3] }
    newPos[face.axis] = parentPos[face.axis] +
        face.dir * (parentDims[face.axis]/2 + newDims[face.axis]/2 + 2 * wallThickness)
    return newPos
end

local function hasSufficientDoorOverlap(posA, dimsA, posB, dimsB, touchAxis, doorSize)
    local margin = 2
    local requiredOverlap = doorSize + 2 * margin

    for axis = 1, 3 do
        if axis ~= touchAxis then
            local minA = posA[axis] - dimsA[axis] / 2
            local maxA = posA[axis] + dimsA[axis] / 2
            local minB = posB[axis] - dimsB[axis] / 2
            local maxB = posB[axis] + dimsB[axis] / 2

            local overlapMin = math.max(minA, minB)
            local overlapMax = math.min(maxA, maxB)
            local overlap = overlapMax - overlapMin

            if overlap < requiredOverlap then
                return false
            end
        end
    end

    return true
end

--------------------------------------------------------------------------------
-- ROOM PLANNING
--------------------------------------------------------------------------------

local function randomScale(config)
    local range = config.scaleRange
    return {
        math.random(range.min, range.max) * config.baseUnit,
        math.random(range.minY or range.min, range.maxY or range.max) * config.baseUnit,
        math.random(range.min, range.max) * config.baseUnit,
    }
end

local function getAttachmentFaces(verticalChance)
    local faces = {}

    for _, face in ipairs(H_FACES) do
        table.insert(faces, { axis = face.axis, dir = face.dir, name = face.name })
    end

    if math.random(1, 100) <= verticalChance then
        for _, face in ipairs(V_FACES) do
            table.insert(faces, { axis = face.axis, dir = face.dir, name = face.name })
        end
    end

    shuffle(faces)
    return faces
end

local function tryAttachRoom(rooms, parentRoom, newDims, face, config)
    local newPos = calculateAttachmentPosition(
        parentRoom.position, parentRoom.dims, newDims, face, config.wallThickness
    )

    if not hasSufficientDoorOverlap(
        parentRoom.position, parentRoom.dims,
        newPos, newDims,
        face.axis, config.doorSize
    ) then
        return nil
    end

    local overlaps = overlapsAny(newPos, newDims, rooms, parentRoom.id, config.wallThickness)
    if overlaps then
        return nil
    end

    return newPos
end

local function planRooms(config)
    local rooms = {}
    local roomOrder = {}  -- Track order for parent relationships

    -- Use domain-specific seed for rooms
    math.randomseed(config.seeds and config.seeds.rooms or config.seed)

    local roomId = 1
    local verticalCount = 0
    local totalRooms = config.mainPathLength + config.spurCount

    -- Plan all room dimensions first
    local inventory = {}
    for i = 1, config.mainPathLength do
        table.insert(inventory, {
            id = roomId,
            dims = randomScale(config),
            pathType = "main",
            parentIdx = i > 1 and (i - 1) or nil,
        })
        roomId = roomId + 1
    end

    for i = 1, config.spurCount do
        local branchFromIdx = math.random(1, config.mainPathLength)
        table.insert(inventory, {
            id = roomId,
            dims = randomScale(config),
            pathType = "spur",
            parentIdx = branchFromIdx,
        })
        roomId = roomId + 1
    end

    -- Place rooms
    for i, entry in ipairs(inventory) do
        if entry.parentIdx == nil then
            -- First room at origin
            local room = {
                id = entry.id,
                position = { config.origin[1], config.origin[2], config.origin[3] },
                dims = entry.dims,
                parentId = nil,
                attachFace = nil,
            }
            rooms[entry.id] = room
            table.insert(roomOrder, entry.id)
        else
            -- Attach to parent
            local parentId = roomOrder[entry.parentIdx]
            local parentRoom = rooms[parentId]

            if parentRoom then
                -- Determine if we need to force vertical
                local forceVertical = false
                local roomsRemaining = #inventory - i + 1
                local minRequired = math.ceil(totalRooms * config.minVerticalRatio)
                local verticalsNeeded = minRequired - verticalCount

                if verticalsNeeded > 0 and verticalsNeeded >= roomsRemaining then
                    forceVertical = true
                end

                -- Get faces to try
                local faces
                if forceVertical then
                    faces = {}
                    for _, face in ipairs(V_FACES) do
                        table.insert(faces, { axis = face.axis, dir = face.dir, name = face.name })
                    end
                    shuffle(faces)
                else
                    faces = getAttachmentFaces(config.verticalChance)
                end

                -- Try each face
                local placed = false
                for _, face in ipairs(faces) do
                    local newPos = tryAttachRoom(rooms, parentRoom, entry.dims, face, config)
                    if newPos then
                        local room = {
                            id = entry.id,
                            position = newPos,
                            dims = entry.dims,
                            parentId = parentId,
                            attachFace = face.name,
                        }
                        rooms[entry.id] = room
                        table.insert(roomOrder, entry.id)

                        if face.name == "U" or face.name == "D" then
                            verticalCount = verticalCount + 1
                        end

                        placed = true
                        break
                    end
                end

                -- Fallback to horizontal if vertical forced but failed
                if not placed and forceVertical then
                    local hFaces = {}
                    for _, face in ipairs(H_FACES) do
                        table.insert(hFaces, { axis = face.axis, dir = face.dir, name = face.name })
                    end
                    shuffle(hFaces)

                    for _, face in ipairs(hFaces) do
                        local newPos = tryAttachRoom(rooms, parentRoom, entry.dims, face, config)
                        if newPos then
                            local room = {
                                id = entry.id,
                                position = newPos,
                                dims = entry.dims,
                                parentId = parentId,
                                attachFace = face.name,
                            }
                            rooms[entry.id] = room
                            table.insert(roomOrder, entry.id)
                            placed = true
                            break
                        end
                    end
                end

                if not placed then
                    warn("[LayoutBuilder] Failed to place room " .. entry.id)
                end
            end
        end
    end

    return rooms
end

--------------------------------------------------------------------------------
-- DOOR PLANNING
--------------------------------------------------------------------------------

local function calculateDoorPosition(roomA, roomB, config)
    -- Find which axis they touch on
    local touchAxis = nil
    local touchDir = nil

    for axis = 1, 3 do
        local shellEdgeA = roomA.position[axis] + roomA.dims[axis] / 2 + config.wallThickness
        local shellEdgeB = roomB.position[axis] - roomB.dims[axis] / 2 - config.wallThickness

        if math.abs(shellEdgeA - shellEdgeB) < 0.1 then
            touchAxis = axis
            touchDir = 1
            break
        end

        shellEdgeA = roomA.position[axis] - roomA.dims[axis] / 2 - config.wallThickness
        shellEdgeB = roomB.position[axis] + roomB.dims[axis] / 2 + config.wallThickness

        if math.abs(shellEdgeA - shellEdgeB) < 0.1 then
            touchAxis = axis
            touchDir = -1
            break
        end
    end

    if not touchAxis then
        return nil
    end

    -- Calculate overlap region on perpendicular axes
    local center = { 0, 0, 0 }
    local minWidth = config.doorSize
    local minHeight = config.doorSize

    -- Door center is at the wall boundary
    center[touchAxis] = roomA.position[touchAxis] +
        touchDir * (roomA.dims[touchAxis] / 2 + config.wallThickness)

    -- For perpendicular axes, find overlap center
    local widthAxis, heightAxis
    if touchAxis == 2 then
        -- Vertical connection: door is in floor/ceiling
        widthAxis = 1
        heightAxis = 3
    else
        -- Horizontal connection: door is in wall
        heightAxis = 2
        if touchAxis == 1 then
            widthAxis = 3
        else
            widthAxis = 1
        end
    end

    -- Calculate overlap on width axis
    local minA = roomA.position[widthAxis] - roomA.dims[widthAxis] / 2
    local maxA = roomA.position[widthAxis] + roomA.dims[widthAxis] / 2
    local minB = roomB.position[widthAxis] - roomB.dims[widthAxis] / 2
    local maxB = roomB.position[widthAxis] + roomB.dims[widthAxis] / 2
    local overlapMin = math.max(minA, minB)
    local overlapMax = math.min(maxA, maxB)
    center[widthAxis] = (overlapMin + overlapMax) / 2
    local width = math.min(overlapMax - overlapMin - 4, config.doorSize)  -- 2 margin each side

    -- Calculate overlap on height axis
    minA = roomA.position[heightAxis] - roomA.dims[heightAxis] / 2
    maxA = roomA.position[heightAxis] + roomA.dims[heightAxis] / 2
    minB = roomB.position[heightAxis] - roomB.dims[heightAxis] / 2
    maxB = roomB.position[heightAxis] + roomB.dims[heightAxis] / 2
    overlapMin = math.max(minA, minB)
    overlapMax = math.min(maxA, maxB)
    local height = math.min(overlapMax - overlapMin - 4, config.doorSize)

    local doorBottom = nil
    if touchAxis ~= 2 then
        -- Wall door: position at floor level (higher floor + small margin)
        doorBottom = overlapMin + 1
        center[heightAxis] = doorBottom + height / 2
    else
        -- Ceiling door: center in overlap
        center[heightAxis] = (overlapMin + overlapMax) / 2
    end

    return {
        center = center,
        width = width,
        height = height,
        axis = touchAxis,
        widthAxis = widthAxis,
        bottom = doorBottom,
    }
end

local function planDoors(rooms, config)
    local doors = {}
    local doorId = 1

    for id, room in pairs(rooms) do
        if room.parentId then
            local parentRoom = rooms[room.parentId]
            if parentRoom then
                local doorData = calculateDoorPosition(parentRoom, room, config)
                if doorData then
                    table.insert(doors, {
                        id = doorId,
                        fromRoom = room.parentId,
                        toRoom = id,
                        center = doorData.center,
                        width = doorData.width,
                        height = doorData.height,
                        axis = doorData.axis,
                        widthAxis = doorData.widthAxis,
                        bottom = doorData.bottom,
                    })
                    doorId = doorId + 1
                end
            end
        end
    end

    return doors
end

--------------------------------------------------------------------------------
-- TRUSS PLANNING
--------------------------------------------------------------------------------

local function planTrusses(rooms, doors, config)
    local trusses = {}
    local trussId = 1

    print(string.format("[Truss] Planning trusses for %d doors, threshold=%.1f", #doors, config.floorThreshold))

    for _, door in ipairs(doors) do
        local roomA = rooms[door.fromRoom]
        local roomB = rooms[door.toRoom]

        if roomA and roomB then
        if door.axis == 2 then
            -- Ceiling hole - truss from lower room floor to upper room floor
            local lowerRoom, upperRoom
            if roomA.position[2] < roomB.position[2] then
                lowerRoom = roomA
                upperRoom = roomB
            else
                lowerRoom = roomB
                upperRoom = roomA
            end

            local lowerFloor = lowerRoom.position[2] - lowerRoom.dims[2] / 2
            local upperFloor = upperRoom.position[2] - upperRoom.dims[2] / 2
            local trussHeight = upperFloor - lowerFloor

            -- Place at -X edge of hole, inside the box
            local trussX = door.center[1] - door.width / 2 + 1  -- +1 for truss half-width

            table.insert(trusses, {
                id = trussId,
                doorId = door.id,
                position = { trussX, lowerFloor + trussHeight / 2, door.center[3] },
                size = { 2, trussHeight, 2 },
                type = "ceiling",
            })
            trussId = trussId + 1

            print(string.format("[Truss] Ceiling: door %d, lowerFloor=%.1f, upperFloor=%.1f, height=%.1f",
                door.id, lowerFloor, upperFloor, trussHeight))
        else
            -- Wall hole - check both sides independently
            local roomsToCheck = {
                { room = roomA, id = door.fromRoom },
                { room = roomB, id = door.toRoom },
            }

            for _, entry in ipairs(roomsToCheck) do
                local room = entry.room
                local wallBottom = room.position[2] - room.dims[2] / 2
                local holeBottom = door.bottom
                local dist = holeBottom - wallBottom

                if dist > config.floorThreshold then
                    local trussPos = { door.center[1], wallBottom + dist / 2, door.center[3] }

                    local dirToRoom = room.position[door.axis] > door.center[door.axis] and 1 or -1
                    trussPos[door.axis] = door.center[door.axis] + dirToRoom * (config.wallThickness / 2 + 1)

                    table.insert(trusses, {
                        id = trussId,
                        doorId = door.id,
                        position = trussPos,
                        size = { 2, dist, 2 },
                        type = "wall",
                    })
                    trussId = trussId + 1

                    print(string.format("[Truss] Wall: door %d, room %d, wallBottom=%.1f, holeBottom=%.1f, dist=%.1f",
                        door.id, entry.id, wallBottom, holeBottom, dist))
                end
            end
        end
        end  -- if roomA and roomB
    end

    return trusses
end

--------------------------------------------------------------------------------
-- LIGHT PLANNING
--------------------------------------------------------------------------------

local WALL_ORDER = { "N", "S", "E", "W" }

local function planLights(rooms, doors, config)
    local lights = {}
    local lightId = 1

    -- Build door faces map per room
    local roomDoorFaces = {}
    for _, door in ipairs(doors) do
        local roomA = rooms[door.fromRoom]
        local roomB = rooms[door.toRoom]

        if roomA and roomB then
            -- Determine which face the door is on for each room
            if door.axis == 1 then  -- X axis
                if roomA.position[1] < roomB.position[1] then
                    roomDoorFaces[door.fromRoom] = roomDoorFaces[door.fromRoom] or {}
                    roomDoorFaces[door.fromRoom]["E"] = true
                    roomDoorFaces[door.toRoom] = roomDoorFaces[door.toRoom] or {}
                    roomDoorFaces[door.toRoom]["W"] = true
                else
                    roomDoorFaces[door.fromRoom] = roomDoorFaces[door.fromRoom] or {}
                    roomDoorFaces[door.fromRoom]["W"] = true
                    roomDoorFaces[door.toRoom] = roomDoorFaces[door.toRoom] or {}
                    roomDoorFaces[door.toRoom]["E"] = true
                end
            elseif door.axis == 3 then  -- Z axis
                if roomA.position[3] < roomB.position[3] then
                    roomDoorFaces[door.fromRoom] = roomDoorFaces[door.fromRoom] or {}
                    roomDoorFaces[door.fromRoom]["N"] = true
                    roomDoorFaces[door.toRoom] = roomDoorFaces[door.toRoom] or {}
                    roomDoorFaces[door.toRoom]["S"] = true
                else
                    roomDoorFaces[door.fromRoom] = roomDoorFaces[door.fromRoom] or {}
                    roomDoorFaces[door.fromRoom]["S"] = true
                    roomDoorFaces[door.toRoom] = roomDoorFaces[door.toRoom] or {}
                    roomDoorFaces[door.toRoom]["N"] = true
                end
            end
            -- Y axis doors (ceiling/floor) don't affect wall lights
        end
    end

    for id, room in pairs(rooms) do
        local doorFaces = roomDoorFaces[id] or {}

        -- Pick a wall without a door
        local chosenWall = nil
        for _, wallName in ipairs(WALL_ORDER) do
            if not doorFaces[wallName] then
                chosenWall = wallName
                break
            end
        end
        chosenWall = chosenWall or "N"  -- Fallback

        -- Calculate light position and size
        local wallDef = {
            N = { axis = 3, dir = 1, sizeAxis = 1 },
            S = { axis = 3, dir = -1, sizeAxis = 1 },
            E = { axis = 1, dir = 1, sizeAxis = 3 },
            W = { axis = 1, dir = -1, sizeAxis = 3 },
        }
        local wall = wallDef[chosenWall]

        local wallWidth = room.dims[wall.sizeAxis]
        local stripWidth = math.clamp(wallWidth * 0.5, 4, 12)

        local lightPos = {
            room.position[1],
            room.position[2] + room.dims[2] / 2 - 2,  -- Near ceiling
            room.position[3],
        }
        lightPos[wall.axis] = room.position[wall.axis] + wall.dir * (room.dims[wall.axis] / 2 - 0.1)

        local lightSize
        if wall.sizeAxis == 1 then
            lightSize = { stripWidth, 1, 0.3 }
        else
            lightSize = { 0.3, 1, stripWidth }
        end

        table.insert(lights, {
            id = lightId,
            roomId = id,
            position = lightPos,
            size = lightSize,
            wall = chosenWall,
        })
        lightId = lightId + 1
    end

    return lights
end

--------------------------------------------------------------------------------
-- PAD PLANNING
--------------------------------------------------------------------------------

local function planPads(ctx)
    local pads = {}
    local config = ctx:getConfig()
    local roomCount = ctx:getRoomCount()

    -- Use direct padCount if provided, otherwise calculate from roomsPerPad
    local padCount = config.padCount or (1 + math.floor(roomCount / config.roomsPerPad))

    -- Select rooms for pads (start from room 2, room 1 is spawn)
    local step = math.max(1, math.floor((roomCount - 1) / padCount))
    local roomId = 2
    local padNum = 1

    -- Debug: show ceiling trusses that will create exclusion zones
    local ceilingTrusses = 0
    for _, truss in ipairs(ctx:getTrusses()) do
        if truss.type == "ceiling" then
            ceilingTrusses = ceilingTrusses + 1
        end
    end
    print(string.format("[LayoutBuilder] Pad planning: %d ceiling trusses creating exclusion zones", ceilingTrusses))

    for i = 1, padCount do
        if roomId <= roomCount then
            local room = ctx:getRoom(roomId)
            if room then
                -- Use context to find safe position (avoids doors, trusses, lights)
                local safePos = ctx:findSafeFloorPosition(roomId)

                if safePos then
                    -- Adjust Y to be slightly above floor for pad
                    safePos[2] = safePos[2] + 0.1

                    table.insert(pads, {
                        id = "pad_" .. padNum,
                        roomId = roomId,
                        position = safePos,
                        isSpawn = false,
                    })
                    print(string.format("[LayoutBuilder] Placed pad_%d in room %d at (%.1f, %.1f, %.1f)",
                        padNum, roomId, safePos[1], safePos[2], safePos[3]))
                    padNum = padNum + 1
                else
                    -- No safe position - skip this room and try next
                    warn(string.format("[LayoutBuilder] No safe position for pad in room %d (has %d doors, checking ceiling trusses)",
                        roomId, #ctx:getDoorsForRoom(roomId)))
                    -- Try the next room instead
                    roomId = roomId + 1
                    if roomId <= roomCount then
                        room = ctx:getRoom(roomId)
                        if room then
                            safePos = ctx:findSafeFloorPosition(roomId)
                            if safePos then
                                safePos[2] = safePos[2] + 0.1
                                table.insert(pads, {
                                    id = "pad_" .. padNum,
                                    roomId = roomId,
                                    position = safePos,
                                    isSpawn = false,
                                })
                                print(string.format("[LayoutBuilder] Placed pad_%d in fallback room %d at (%.1f, %.1f, %.1f)",
                                    padNum, roomId, safePos[1], safePos[2], safePos[3]))
                                padNum = padNum + 1
                            end
                        end
                    end
                end
            end
            roomId = roomId + step
        end
    end

    return pads
end

--------------------------------------------------------------------------------
-- PUBLIC API
--------------------------------------------------------------------------------

--[[
    Converts a string to a numeric seed using a simple hash.
    Same string always produces the same seed.

    Examples:
        "BeverlyMansion" → 1234567890
        "tutorial_1" → 9876543210
--]]
local function stringToSeed(str)
    if type(str) == "number" then
        return str  -- Already a number
    end
    if type(str) ~= "string" then
        return 0
    end

    -- DJB2 hash algorithm - fast and good distribution
    local hash = 5381
    for i = 1, #str do
        local char = string.byte(str, i)
        hash = ((hash * 33) + char) % 2147483647  -- Keep in 32-bit range
    end
    return hash
end

--[[
    Generates domain-specific seeds from a master seed.
    Each domain gets a unique seed derived from the master.
    This allows each planning phase to have independent randomness.

    Master seed can be a number or string (strings are hashed).
--]]
local function generateSeeds(masterSeed)
    -- Convert string to number if needed
    if type(masterSeed) == "string" then
        masterSeed = stringToSeed(masterSeed)
    end
    -- Use the master seed to generate domain seeds
    -- Each domain gets a different offset to ensure unique sequences
    return {
        rooms = masterSeed,                    -- Room positions, sizes, connectivity
        doors = masterSeed + 10000,            -- Future: door styles, sizes
        trusses = masterSeed + 20000,          -- Future: truss variations
        lights = masterSeed + 30000,           -- Future: light placement
    }
end

function LayoutBuilder.generate(config)
    -- Merge with defaults
    local masterSeed = config.seed or os.time()
    local cfg = {
        seed = masterSeed,
        seeds = generateSeeds(masterSeed),     -- Domain-specific seeds
        regionNum = config.regionNum or 1,
        origin = config.origin or { 0, 20, 0 },
        baseUnit = config.baseUnit or 5,
        wallThickness = config.wallThickness or 1,
        doorSize = config.doorSize or 12,
        floorThreshold = config.floorThreshold or 5,
        verticalChance = config.verticalChance or 30,
        minVerticalRatio = config.minVerticalRatio or 0.2,
        mainPathLength = config.mainPathLength or 8,
        spurCount = config.spurCount or 4,
        loopCount = config.loopCount or 1,
        scaleRange = config.scaleRange or { min = 4, max = 12, minY = 4, maxY = 8 },
        material = config.material or "Brick",
        color = config.color or { 140, 110, 90 },
        padCount = config.padCount,  -- Direct pad count (overrides roomsPerPad if set)
        roomsPerPad = config.roomsPerPad or 25,
    }

    -- Create central context for all planners to read/write
    local ctx = LayoutContext.new(cfg)

    -- Plan rooms (writes to context)
    ctx:setRooms(planRooms(cfg))

    -- Plan doors between connected rooms (reads rooms, writes doors)
    ctx:setDoors(planDoors(ctx:getRooms(), cfg))

    -- Plan trusses at doors that need them (reads rooms + doors)
    ctx:setTrusses(planTrusses(ctx:getRooms(), ctx:getDoors(), cfg))
    print("[LayoutBuilder] Planned " .. #ctx:getTrusses() .. " trusses for " .. #ctx:getDoors() .. " doors")

    -- Plan lights in each room (reads rooms + doors for wall avoidance)
    ctx:setLights(planLights(ctx:getRooms(), ctx:getDoors(), cfg))
    print("[LayoutBuilder] Planned " .. #ctx:getLights() .. " lights for " .. ctx:getRoomCount() .. " rooms")

    -- Plan teleport pads (reads rooms, doors, trusses for safe positioning)
    ctx:setPads(planPads(ctx))

    -- Set spawn at room 1's floor level + 3 studs
    local room1 = ctx:getRoom(1)
    if room1 then
        local floorY = room1.position[2] - room1.dims[2] / 2 + 3
        ctx:setSpawn({
            position = { room1.position[1], floorY, room1.position[3] },
            roomId = 1,
        })
        print(string.format("[LayoutBuilder] Spawn at room 1 floor: (%.1f, %.1f, %.1f)",
            room1.position[1], floorY, room1.position[3]))
    end

    -- Export to layout format
    local layout = ctx:toLayout()

    -- Validate
    local ok, err = LayoutSchema.validate(layout)
    if not ok then
        warn("[LayoutBuilder] Generated invalid layout: " .. err)
    end

    return layout
end

return LayoutBuilder
