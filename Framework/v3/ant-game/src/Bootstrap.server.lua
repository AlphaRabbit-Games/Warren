--[[
    Ant Game — Server Bootstrap
    Warren Framework v2

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    This is the server entry point. It:
    1. Requires the Warren framework
    2. Configures system subsystems
    3. Initializes the Colony mode

--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Wait for Warren to be available (Rojo sync)
local Lib = require(ReplicatedStorage:WaitForChild("Warren"))
local Debug = Lib.System.Debug

--------------------------------------------------------------------------------
-- STUDIO CLI ACCESS
--------------------------------------------------------------------------------

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

Debug.configure({
    level = "info",
})

local Log = Lib.System.Log
Log.configure({
    backend = "Memory",
})

--------------------------------------------------------------------------------
-- BOOTSTRAP
--------------------------------------------------------------------------------

Debug.info("Bootstrap", "Warren v" .. Lib._VERSION)
Debug.info("Bootstrap", "Server starting...")

Log.init()

--------------------------------------------------------------------------------
-- ASSET REGISTRATION
--------------------------------------------------------------------------------

local Asset = Lib.System.Asset
local IPC = Lib.System.IPC

local Game = require(ReplicatedStorage:WaitForChild("Game"))

-- Register Game-level nodes
IPC.registerNode(Game.GameClock)
IPC.registerNode(Game.TimeHUD)
IPC.registerNode(Game.ColonyNode)
IPC.registerNode(Game.FoodHopperNode)
IPC.registerNode(Game.EggClutchNode)
IPC.registerNode(Game.PantryHUD)
IPC.registerNode(Game.ClutchHUD)
IPC.registerNode(Game.WorkerHUD)
IPC.registerNode(Game.CommandManagerNode)
IPC.registerNode(Game.CommandMenuHUD)
IPC.registerNode(Game.FoodSourceNode)
IPC.registerNode(Game.FoodSourceHUD)
IPC.registerNode(Game.GameManagerNode)
IPC.registerNode(Game.XPHUD)
IPC.registerNode(Game.SurfaceWorldNode)
IPC.registerNode(Game.WorkerRenderNode)
IPC.registerNode(Game.ScoreNode)
IPC.registerNode(Game.ScoreHUD)

Asset.buildInheritanceTree()

--------------------------------------------------------------------------------
-- MODE DEFINITION
--------------------------------------------------------------------------------

IPC.defineMode("Colony", {
    nodes = {
        "GameClock", "TimeHUD",
        "ColonyNode", "FoodHopperNode", "EggClutchNode",
        "FoodSourceNode", "FoodSourceHUD",
        "PantryHUD", "ClutchHUD", "WorkerHUD",
        "CommandManagerNode", "CommandMenuHUD",
        "GameManagerNode", "XPHUD",
        "SurfaceWorldNode", "WorkerRenderNode",
        "ScoreNode", "ScoreHUD",
    },
    wiring = {
        GameClock = { "TimeHUD", "ColonyNode", "EggClutchNode", "FoodSourceNode", "ScoreNode" },
        ColonyNode = { "FoodSourceNode", "FoodHopperNode", "EggClutchNode", "WorkerHUD", "CommandManagerNode", "GameManagerNode", "WorkerRenderNode", "ScoreNode" },
        ScoreNode = { "ScoreHUD" },
        FoodSourceNode = { "ColonyNode", "FoodHopperNode", "FoodSourceHUD", "CommandManagerNode", "SurfaceWorldNode", "WorkerRenderNode" },
        FoodHopperNode = { "ColonyNode", "PantryHUD", "CommandManagerNode" },
        EggClutchNode = { "ClutchHUD", "ColonyNode", "CommandManagerNode", "GameManagerNode" },
        WorkerHUD = { "CommandMenuHUD", "CommandManagerNode" },
        CommandManagerNode = { "CommandMenuHUD", "ColonyNode", "GameManagerNode" },
        CommandMenuHUD = { "CommandManagerNode" },
        GameManagerNode = { "FoodSourceNode", "ColonyNode", "XPHUD" },
        XPHUD = { "GameManagerNode" },
    },
})

--------------------------------------------------------------------------------
-- IPC INITIALIZATION
--------------------------------------------------------------------------------

IPC.init()
IPC.switchMode("Colony")
IPC.start()

--------------------------------------------------------------------------------
-- INSTANCE CREATION
--------------------------------------------------------------------------------

-- CommandManager first so chambers can register on start
IPC.createInstance("GameManagerNode", { id = "GameManager" })
IPC.createInstance("CommandManagerNode", { id = "CommandManager" })
IPC.createInstance("GameClock", { id = "GameClock_Server" })
IPC.createInstance("SurfaceWorldNode", { id = "SurfaceWorld" })
IPC.createInstance("WorkerRenderNode", { id = "WorkerRender" })
IPC.createInstance("ScoreNode", { id = "Score" })
IPC.createInstance("FoodSourceNode", { id = "FoodSources" })
IPC.createInstance("FoodHopperNode", { id = "FoodHopper" })
IPC.createInstance("EggClutchNode", { id = "EggClutch" })
IPC.createInstance("ColonyNode", { id = "Colony" })

-- Spawn queen and starting worker
IPC.sendTo("Colony", "spawnQueen", {})
IPC.sendTo("Colony", "spawnWorker", {})

Debug.info("Bootstrap", "Colony started — 1 queen, 1 worker, pantry empty")

--------------------------------------------------------------------------------
-- CLEANUP ON SHUTDOWN
--------------------------------------------------------------------------------

game:BindToClose(function()
    Debug.info("Bootstrap", "Server shutting down...")
    Lib.System.stopAll()
    Log.shutdown()
    Debug.info("Bootstrap", "Server shutdown complete")
end)

Debug.info("Bootstrap", "Server ready")
