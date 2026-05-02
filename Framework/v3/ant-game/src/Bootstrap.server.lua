--[[
    Warren Framework v2
    Server Bootstrap

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    This is the server entry point. It:
    1. Requires the Lib module
    2. Configures system subsystems
    3. Initializes the framework in the correct order

    Nothing in the framework runs until this script explicitly calls it.

--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Wait for Lib to be available (Rojo sync)
local Lib = require(ReplicatedStorage:WaitForChild("Warren"))
local Debug = Lib.System.Debug

--------------------------------------------------------------------------------
-- STUDIO CLI ACCESS
--------------------------------------------------------------------------------
-- Expose globals for command bar testing in Studio
-- These are stripped in production (non-Studio) builds

if RunService:IsStudio() then
    _G.Warren = Lib
    _G.Node = Lib.Node
    _G.Debug = Lib.System.Debug
    _G.Log = Lib.System.Log
    _G.IPC = Lib.System.IPC
    _G.State = Lib.System.State
    _G.Asset = Lib.System.Asset
    _G.Store = Lib.System.Store
    _G.View = Lib.System.View
end

--------------------------------------------------------------------------------
-- CONFIGURATION
--------------------------------------------------------------------------------

-- Groups are defined in Lib/Config.lua (shared by all contexts).
-- Uncomment below to override at runtime:
-- Lib.System.setGroups({
--     Core = { "System.*", "Bootstrap", "Log" },
--     Gameplay = { "Combat.*", "Economy.*", "Inventory.*" },
-- })

-- Configure debug output (defaults from Config.lua, override here if needed)
Debug.configure({
    level = "info",  -- "error", "warn", "info", "trace"
    -- show = { "@Core" },  -- Use @GroupName to reference groups
    -- hide = { "*.Tick" },
    -- solo = {},  -- If non-empty, ONLY these patterns show
})

-- Configure persistent logging (defaults from Config.lua, override here if needed)
local Log = Lib.System.Log
Log.configure({
    backend = "Memory",  -- "Memory", "DataStore", "None"
    -- capture = { "@Gameplay" },  -- Use @GroupName to capture specific groups
    -- ignore = { "*.Tick" },
})

--------------------------------------------------------------------------------
-- BOOTSTRAP
--------------------------------------------------------------------------------

Debug.info("Bootstrap", "Warren v" .. Lib._VERSION)
Debug.info("Bootstrap", "Server starting...")

-- Initialize Log subsystem (generates session ID, starts auto-flush)
Log.init()

--------------------------------------------------------------------------------
-- ASSET REGISTRATION
--------------------------------------------------------------------------------
-- Register node classes from Lib and Game before IPC initialization.
-- This builds the inheritance tree and validates contracts.

local Asset = Lib.System.Asset
local IPC = Lib.System.IPC

-- Wait for Game module (game-specific node implementations)
local Game = require(ReplicatedStorage:WaitForChild("Game"))

-- Register Lib-level nodes (base classes)
-- Example:
--   Asset.register(require(Lib.Dispenser))
--   Asset.register(require(Lib.Evaluator))

-- Register dungeon nodes with IPC
IPC.registerNode(Lib.Components.JumpPad)
IPC.registerNode(Lib.Components.RegionManager)
IPC.registerNode(Lib.Components.ScreenTransition)  -- Client-side, but registered for wiring
IPC.registerNode(Lib.Components.AreaHUD)           -- Client-side, but registered for wiring
IPC.registerNode(Lib.Components.MiniMap)           -- Client-side, but registered for wiring

-- Register Game-level nodes (game-specific implementations)
IPC.registerNode(Game.GameClock)
IPC.registerNode(Game.TimeHUD)            -- Client-side, but registered for wiring

-- Verify all expected classes are registered
-- Asset.verify({ "Dispenser", "MarshmallowBag", "Evaluator", "Camper" })

-- Build inheritance tree (for introspection/debugging)
Asset.buildInheritanceTree()

--------------------------------------------------------------------------------
-- MODE DEFINITION
--------------------------------------------------------------------------------
-- Define run modes with wiring configurations.
-- Each mode specifies which nodes are active and how they're connected.

-- Dungeon mode: JumpPad signals route to RegionManager, screen transitions cross client/server
IPC.defineMode("Dungeon", {
    nodes = { "JumpPad", "RegionManager", "ScreenTransition", "AreaHUD", "MiniMap" },
    wiring = {
        -- Server-side: JumpPad → RegionManager
        JumpPad = { "RegionManager" },
        -- Cross-domain: RegionManager (server) → ScreenTransition, AreaHUD, MiniMap (client)
        RegionManager = { "ScreenTransition", "AreaHUD", "MiniMap" },
        -- Cross-domain: ScreenTransition (client) → RegionManager (server)
        ScreenTransition = { "RegionManager" },
        -- Cross-domain: MiniMap (client) → RegionManager (server)
        MiniMap = { "RegionManager" },
    },
})

-- Colony mode: GameClock drives time for the ant colony simulation
IPC.defineMode("Colony", {
    nodes = { "GameClock", "TimeHUD" },
    wiring = {
        -- Cross-domain: GameClock (server) → TimeHUD (client)
        GameClock = { "TimeHUD" },
    },
})

--------------------------------------------------------------------------------
-- IPC INITIALIZATION
--------------------------------------------------------------------------------

-- Initialize IPC (calls onInit on all registered instances)
IPC.init()

-- Switch to Dungeon mode (enables wiring)
IPC.switchMode("Dungeon")

-- Start IPC (enables routing, calls onStart on all instances)
IPC.start()

--------------------------------------------------------------------------------
-- GAME CLOCK
--------------------------------------------------------------------------------
-- Create the server-side game clock instance for the ant colony simulation.

IPC.createInstance("GameClock", { id = "GameClock_Server" })

--------------------------------------------------------------------------------
-- ASSET SPAWNING
--------------------------------------------------------------------------------
-- Spawn node instances for models in Workspace.
-- Models must have a NodeClass attribute specifying which class to use.

-- Example: Spawn all models in RuntimeAssets container
-- local RuntimeAssets = workspace:FindFirstChild("RuntimeAssets")
-- if RuntimeAssets then
--     Asset.spawnAll(RuntimeAssets)
-- end

-- TODO: Initialize other subsystems in order
-- Lib.System.State.init()
-- Lib.System.Store.init()

--------------------------------------------------------------------------------
-- INFINITE DUNGEON SYSTEM
--------------------------------------------------------------------------------
-- Manages infinite dungeon with region-based generation and teleportation
--
-- TODO: This is a temporary hack. Should be its own script in ServerScriptService.
-- See: src/Game/DungeonServer/_ServerScriptService/DungeonStartup.server.lua
--
-- KNOWN ISSUES:
-- [ ] Lighting is slow to load on first play. Bootstrap should wait for all
--     lighting and shaders to complete before showing environment to player.
--     Consider using a loading screen or ContentProvider:PreloadAsync().
--------------------------------------------------------------------------------

local function startInfiniteDungeon()
    -- Set dark/nighttime lighting
    local Lighting = game:GetService("Lighting")
    Lighting.ClockTime = 0  -- Midnight
    Lighting.Brightness = 0  -- No ambient light
    Lighting.OutdoorAmbient = Color3.fromRGB(0, 0, 0)
    Lighting.Ambient = Color3.fromRGB(20, 20, 25)  -- Slight ambient for visibility
    Lighting.FogEnd = 1000
    Lighting.FogColor = Color3.fromRGB(0, 0, 0)
    Lighting.GlobalShadows = false  -- Disable shadows for performance

    -- Create region manager via IPC (handles init/start automatically)
    local regionManager = IPC.createInstance("RegionManager", {
        id = "InfiniteDungeon",
    })

    -- Store globally for debugging (IPC handles lifecycle)
    -- Note: Both _G and shared for command bar compatibility in different Studio contexts
    _G.RegionManager = regionManager
    shared.RegionManager = regionManager

    -- Configure
    -- Note: material/color use serializable formats (string/array) for DataStore compatibility
    regionManager:configure({
        baseUnit = 5,
        wallThickness = 1,
        doorSize = 12,
        floorThreshold = 6.5,  -- Height diff before truss is placed
        mainPathLength = 8,
        spurCount = 4,
        loopCount = 1,
        verticalChance = 30,
        minVerticalRatio = 0.2,
        scaleRange = {
            min = 4,
            max = 12,
            minY = 4,
            maxY = 8,
        },
        material = "Brick",  -- String for serialization
        color = { 140, 110, 90 },  -- RGB array for serialization
        -- Map type distribution (deterministic pattern)
        hubInterval = 4,          -- Guarantee a hub every N regions
        hubPadRange = { min = 3, max = 4 },  -- Pads in hub regions
        origin = { 0, 20, 0 },
    })

    -- Wait for first player to load/create dungeon
    local Players = game:GetService("Players")
    local dungeonOwner = nil  -- First player to join owns the dungeon
    local dungeonReady = false
    local layout = nil

    local function startDungeonForPlayer(player)
        if dungeonReady then return end
        dungeonReady = true
        dungeonOwner = player

        Debug.info("Bootstrap", "Starting dungeon for", player.Name)
        local regionId = regionManager:startFirstRegion(player)

        -- Log layout info for debugging
        local region = regionManager:getRegion(regionId)
        if region and region.layout then
            layout = region.layout
            local roomCount = 0
            for _ in pairs(layout.rooms) do roomCount = roomCount + 1 end

            Debug.info("Bootstrap", string.format(
                "Layout: %d rooms, %d doors, %d trusses, %d lights, %d pads",
                roomCount,
                #layout.doors,
                #layout.trusses,
                #layout.lights,
                #layout.pads
            ))

            if layout.spawn then
                local pos = layout.spawn.position
                Debug.info("Bootstrap", string.format(
                    "Spawn at (%.1f, %.1f, %.1f) in room %d",
                    pos[1], pos[2], pos[3], layout.spawn.roomId
                ))
            end
        end

        Debug.info("Bootstrap", "Dungeon ready for", player.Name)
    end

    -- Safety net: check if player spawns outside room volumes and relocate

    local function isInsideAnyRoom(position)
        if not layout then return false end
        for _, room in pairs(layout.rooms) do
            local minX = room.position[1] - room.dims[1] / 2
            local maxX = room.position[1] + room.dims[1] / 2
            local minY = room.position[2] - room.dims[2] / 2
            local maxY = room.position[2] + room.dims[2] / 2
            local minZ = room.position[3] - room.dims[3] / 2
            local maxZ = room.position[3] + room.dims[3] / 2

            if position.X >= minX and position.X <= maxX and
               position.Y >= minY and position.Y <= maxY and
               position.Z >= minZ and position.Z <= maxZ then
                return true
            end
        end
        return false
    end

    local function onCharacterAdded(character, player)
        -- Wait for character to fully load and settle
        task.wait(0.5)

        local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
        if not humanoidRootPart then return end

        local pos = humanoidRootPart.Position
        if not isInsideAnyRoom(pos) then
            -- Player spawned outside - teleport to room 1 center
            local room1 = layout and layout.rooms[1]
            if room1 then
                local targetPos = Vector3.new(
                    room1.position[1],
                    room1.position[2] - room1.dims[2] / 2 + 3,  -- Floor + 3
                    room1.position[3]
                )
                humanoidRootPart.CFrame = CFrame.new(targetPos)
                Debug.info("Bootstrap", string.format(
                    "Player spawned outside rooms at (%.1f, %.1f, %.1f), relocated to (%.1f, %.1f, %.1f)",
                    pos.X, pos.Y, pos.Z,
                    targetPos.X, targetPos.Y, targetPos.Z
                ))
            end
        else
            Debug.info("Bootstrap", string.format(
                "Player spawned inside room at (%.1f, %.1f, %.1f)",
                pos.X, pos.Y, pos.Z
            ))
        end

        -- Send initial area info to client (room 1 on spawn)
        regionManager:sendInitialAreaInfo(player, 1)
    end

    local function onPlayerAdded(player)
        -- First player starts/loads the dungeon
        if not dungeonReady then
            startDungeonForPlayer(player)
        end

        if player.Character then
            onCharacterAdded(player.Character, player)
        end
        player.CharacterAdded:Connect(function(character)
            onCharacterAdded(character, player)
        end)
    end

    -- Save dungeon data when owner leaves
    Players.PlayerRemoving:Connect(function(player)
        if player == dungeonOwner then
            Debug.info("Bootstrap", "Dungeon owner leaving, saving data...")
            regionManager:saveData(player)
        end
    end)

    Players.PlayerAdded:Connect(onPlayerAdded)
    for _, player in ipairs(Players:GetPlayers()) do
        onPlayerAdded(player)
    end
end

--------------------------------------------------------------------------------
-- CLEANUP ON SHUTDOWN
--------------------------------------------------------------------------------
-- Ensure all nodes are properly stopped when the game closes.
-- This disconnects all RunService connections and cleans up state.

game:BindToClose(function()
    Debug.info("Bootstrap", "Server shutting down...")

    -- Despawn region manager via IPC (handles all dungeon cleanup)
    IPC.despawn("InfiniteDungeon")

    Lib.System.stopAll()
    Log.shutdown()
    Debug.info("Bootstrap", "Server shutdown complete")
end)

Debug.info("Bootstrap", "Server ready")

-- Start dungeon AFTER bootstrap complete (all systems initialized)
startInfiniteDungeon()
