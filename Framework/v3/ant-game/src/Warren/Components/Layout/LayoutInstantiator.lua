--[[
    Warren Framework v2
    LayoutInstantiator.lua - Create Parts from Layout Data

    Copyright (c) 2026 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    LayoutInstantiator takes a Layout table and creates all the parts in the
    world. No procedural logic - just data-driven instantiation.

    This separates "building" from "what to build", enabling:
    - Reload regions from stored layouts (no regeneration)
    - Deterministic part creation from fixed data
    - Easy testing with known layout data

    ============================================================================
    USAGE
    ============================================================================

    ```lua
    local LayoutInstantiator = require(...)
    local result = LayoutInstantiator.instantiate(layout, {
        container = workspace,
        name = "Region_1",
    })
    -- result.container, result.spawnPoint, result.pads
    ```

--]]

local LayoutInstantiator = {}

--------------------------------------------------------------------------------
-- MATERIAL/COLOR CONVERSION
--------------------------------------------------------------------------------

local function getMaterial(materialName)
    if type(materialName) == "string" then
        return Enum.Material[materialName] or Enum.Material.Brick
    end
    return materialName or Enum.Material.Brick
end

local function getColor(colorData)
    if type(colorData) == "table" then
        return Color3.fromRGB(colorData[1], colorData[2], colorData[3])
    end
    return colorData or Color3.fromRGB(140, 110, 90)
end

--------------------------------------------------------------------------------
-- SHELL BUILDING
--------------------------------------------------------------------------------

local function createWallPart(name, position, size, material, color, parent)
    local part = Instance.new("Part")
    part.Name = name
    part.Size = Vector3.new(size[1], size[2], size[3])
    part.Position = Vector3.new(position[1], position[2], position[3])
    part.Anchored = true
    part.Material = material
    part.Color = color
    part.Parent = parent
    return part
end

local function buildShell(room, config, container)
    local pos = room.position
    local dims = room.dims
    local wt = config.wallThickness
    local material = getMaterial(config.material)
    local color = getColor(config.color)

    local roomContainer = Instance.new("Model")
    roomContainer.Name = "Room_" .. room.id
    roomContainer.Parent = container

    local walls = {}

    -- Floor
    walls.Floor = createWallPart(
        "Floor",
        { pos[1], pos[2] - dims[2]/2 - wt/2, pos[3] },
        { dims[1] + 2*wt, wt, dims[3] + 2*wt },
        material, color, roomContainer
    )

    -- Ceiling
    walls.Ceiling = createWallPart(
        "Ceiling",
        { pos[1], pos[2] + dims[2]/2 + wt/2, pos[3] },
        { dims[1] + 2*wt, wt, dims[3] + 2*wt },
        material, color, roomContainer
    )

    -- North (+Z)
    walls.N = createWallPart(
        "Wall_N",
        { pos[1], pos[2], pos[3] + dims[3]/2 + wt/2 },
        { dims[1] + 2*wt, dims[2], wt },
        material, color, roomContainer
    )

    -- South (-Z)
    walls.S = createWallPart(
        "Wall_S",
        { pos[1], pos[2], pos[3] - dims[3]/2 - wt/2 },
        { dims[1] + 2*wt, dims[2], wt },
        material, color, roomContainer
    )

    -- East (+X)
    walls.E = createWallPart(
        "Wall_E",
        { pos[1] + dims[1]/2 + wt/2, pos[2], pos[3] },
        { wt, dims[2], dims[3] },
        material, color, roomContainer
    )

    -- West (-X)
    walls.W = createWallPart(
        "Wall_W",
        { pos[1] - dims[1]/2 - wt/2, pos[2], pos[3] },
        { wt, dims[2], dims[3] },
        material, color, roomContainer
    )

    return roomContainer, walls
end

--------------------------------------------------------------------------------
-- DOOR CUTTING
--------------------------------------------------------------------------------

local function cutDoor(door, roomContainers, config)
    local wt = config.wallThickness

    -- Create cutter part
    local cutterDepth = wt * 8  -- Deep enough to cut through walls
    local cutterSize

    if door.axis == 2 then
        -- Vertical door (ceiling/floor hole)
        cutterSize = Vector3.new(door.width, cutterDepth, door.height)
    else
        -- Horizontal door (wall hole)
        if door.widthAxis == 1 then
            cutterSize = Vector3.new(door.width, door.height, cutterDepth)
        else
            cutterSize = Vector3.new(cutterDepth, door.height, door.width)
        end
    end

    local cutter = Instance.new("Part")
    cutter.Size = cutterSize
    cutter.Position = Vector3.new(door.center[1], door.center[2], door.center[3])
    cutter.Anchored = true
    cutter.CanCollide = false
    cutter.Transparency = 1

    -- Find walls to cut in both rooms
    local roomsToCheck = { door.fromRoom, door.toRoom }

    for _, roomId in ipairs(roomsToCheck) do
        local roomContainer = roomContainers[roomId]
        if roomContainer then
            for _, child in ipairs(roomContainer:GetChildren()) do
                if child:IsA("BasePart") and (
                   child.Name:match("^Wall") or
                   child.Name == "Floor" or
                   child.Name == "Ceiling"
                ) then
                    -- Check if this wall intersects the cutter
                    local wallPos = child.Position
                    local wallSize = child.Size

                    local intersects = true
                    for axis = 1, 3 do
                        local wMin = wallPos[axis == 1 and "X" or axis == 2 and "Y" or "Z"] - wallSize[axis == 1 and "X" or axis == 2 and "Y" or "Z"] / 2
                        local wMax = wallPos[axis == 1 and "X" or axis == 2 and "Y" or "Z"] + wallSize[axis == 1 and "X" or axis == 2 and "Y" or "Z"] / 2
                        local cMin = cutter.Position[axis == 1 and "X" or axis == 2 and "Y" or "Z"] - cutter.Size[axis == 1 and "X" or axis == 2 and "Y" or "Z"] / 2
                        local cMax = cutter.Position[axis == 1 and "X" or axis == 2 and "Y" or "Z"] + cutter.Size[axis == 1 and "X" or axis == 2 and "Y" or "Z"] / 2

                        if wMax <= cMin or cMax <= wMin then
                            intersects = false
                            break
                        end
                    end

                    if intersects then
                        -- Perform CSG subtraction
                        local success, result = pcall(function()
                            return child:SubtractAsync({ cutter })
                        end)

                        if success and result then
                            result.Name = child.Name
                            result.Parent = roomContainer
                            child:Destroy()
                        end
                    end
                end
            end
        end
    end

    cutter:Destroy()
end

--------------------------------------------------------------------------------
-- TRUSS CREATION
--------------------------------------------------------------------------------

local function createTruss(truss, container)
    local part = Instance.new("TrussPart")
    part.Name = "Truss_" .. truss.id
    part.Size = Vector3.new(truss.size[1], truss.size[2], truss.size[3])
    part.Position = Vector3.new(truss.position[1], truss.position[2], truss.position[3])
    part.Anchored = true
    part.Parent = container
    return part
end

--------------------------------------------------------------------------------
-- LIGHT CREATION
--------------------------------------------------------------------------------

local function createLight(light, roomContainers)
    local roomContainer = roomContainers[light.roomId]
    if not roomContainer then
        roomContainer = workspace
    end

    local fixture = Instance.new("Part")
    fixture.Name = "Light_" .. light.id
    fixture.Size = Vector3.new(light.size[1], light.size[2], light.size[3])
    fixture.Position = Vector3.new(light.position[1], light.position[2], light.position[3])
    fixture.Anchored = true
    fixture.CanCollide = false
    fixture.Material = Enum.Material.Neon
    fixture.Color = Color3.fromRGB(255, 250, 240)
    fixture.Parent = roomContainer

    local pointLight = Instance.new("PointLight")
    pointLight.Name = "PointLight"
    pointLight.Brightness = 0.75
    pointLight.Range = 60
    pointLight.Color = Color3.fromRGB(255, 245, 230)
    pointLight.Shadows = false
    pointLight.Parent = fixture

    return fixture
end

--------------------------------------------------------------------------------
-- PAD CREATION
--------------------------------------------------------------------------------

local function createPad(pad, roomContainers)
    local roomContainer = roomContainers[pad.roomId]
    if not roomContainer then
        roomContainer = workspace
    end

    local part = Instance.new("Part")
    part.Name = pad.id
    part.Size = Vector3.new(6, 1, 6)
    part.Position = Vector3.new(pad.position[1], pad.position[2], pad.position[3])
    part.Anchored = true
    part.CanCollide = true
    part.Material = Enum.Material.Neon
    part.Color = Color3.fromRGB(180, 50, 255)
    part.Parent = roomContainer

    part:SetAttribute("TeleportPad", true)
    part:SetAttribute("PadId", pad.id)
    part:SetAttribute("RoomId", pad.roomId)

    return part
end

local function createSpawn(spawn, container, regionId)
    local spawnPoint = Instance.new("SpawnLocation")
    spawnPoint.Name = "Spawn_" .. (regionId or "default")
    spawnPoint.Size = Vector3.new(6, 1, 6)
    spawnPoint.Position = Vector3.new(spawn.position[1], spawn.position[2], spawn.position[3])
    spawnPoint.Anchored = true
    spawnPoint.CanCollide = false
    spawnPoint.Neutral = true
    spawnPoint.Transparency = 1
    spawnPoint.Parent = container

    print(string.format("[LayoutInstantiator] Spawn at (%.1f, %.1f, %.1f)",
        spawn.position[1], spawn.position[2], spawn.position[3]))

    return spawnPoint
end


--------------------------------------------------------------------------------
-- PUBLIC API
--------------------------------------------------------------------------------

function LayoutInstantiator.instantiate(layout, options)
    options = options or {}

    -- Delete any existing SpawnLocation parts in workspace
    for _, child in ipairs(workspace:GetChildren()) do
        if child:IsA("SpawnLocation") then
            print("[LayoutInstantiator] Removing existing SpawnLocation: " .. child.Name)
            child:Destroy()
        end
    end

    -- Create or use container
    local container
    if options.container then
        container = options.container
    else
        container = Instance.new("Model")
        container.Name = options.name or "Layout"
        container.Parent = workspace
    end

    -- Store region metadata on container
    container:SetAttribute("RegionNum", layout.regionNum or 1)

    local config = layout.config or {
        wallThickness = 1,
        material = "Brick",
        color = { 140, 110, 90 },
    }

    local roomContainers = {}
    local pads = {}

    -- Build all room shells and zone parts
    local roomZones = {}
    for id, room in pairs(layout.rooms) do
        local roomContainer, walls = buildShell(room, config, container)
        roomContainers[id] = roomContainer

        -- Create invisible zone part for player detection
        local zonePart = Instance.new("Part")
        zonePart.Name = "RoomZone_" .. id
        zonePart.Size = Vector3.new(room.dims[1], room.dims[2], room.dims[3])
        zonePart.Position = Vector3.new(room.position[1], room.position[2], room.position[3])
        zonePart.Anchored = true
        zonePart.CanCollide = false
        zonePart.Transparency = 1
        zonePart.Parent = roomContainer
        zonePart:SetAttribute("RoomId", id)
        zonePart:SetAttribute("RegionNum", layout.regionNum or 1)

        roomZones[id] = zonePart
    end

    -- Cut all doors
    for _, door in ipairs(layout.doors) do
        cutDoor(door, roomContainers, config)
    end

    -- Create all trusses
    for _, truss in ipairs(layout.trusses) do
        createTruss(truss, container)
    end

    -- Create all lights
    for _, light in ipairs(layout.lights) do
        createLight(light, roomContainers)
    end

    -- Create all pads
    for _, pad in ipairs(layout.pads) do
        local padPart = createPad(pad, roomContainers)
        pads[pad.id] = {
            part = padPart,
            id = pad.id,
            roomId = pad.roomId,
            position = pad.position,
        }
    end

    -- Create spawn at room 1 center
    local spawnPoint = nil
    if layout.spawn then
        spawnPoint = createSpawn(layout.spawn, container, options.regionId)
    end

    return {
        container = container,
        roomContainers = roomContainers,
        roomZones = roomZones,
        spawnPoint = spawnPoint,
        spawnPosition = layout.spawn and layout.spawn.position,
        pads = pads,
        roomCount = #layout.rooms,
    }
end

return LayoutInstantiator
