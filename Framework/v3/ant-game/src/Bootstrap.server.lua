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
    3. Initializes the Colony mode (GameClock + TimeHUD)

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
IPC.registerNode(Game.QueenNode)
IPC.registerNode(Game.FoodHopperNode)
IPC.registerNode(Game.EggClutchNode)
IPC.registerNode(Game.QueenHUD)
IPC.registerNode(Game.ClutchHUD)

Asset.buildInheritanceTree()

--------------------------------------------------------------------------------
-- MODE DEFINITION
--------------------------------------------------------------------------------

-- Colony mode: GameClock pulse drives queen feeding/egg cycle
IPC.defineMode("Colony", {
    nodes = { "GameClock", "TimeHUD", "QueenNode", "FoodHopperNode", "EggClutchNode", "QueenHUD", "ClutchHUD" },
    wiring = {
        GameClock = { "TimeHUD", "QueenNode", "EggClutchNode" },
        QueenNode = { "FoodHopperNode", "EggClutchNode", "QueenHUD" },
        FoodHopperNode = { "QueenNode" },
        EggClutchNode = { "ClutchHUD" },
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

IPC.createInstance("GameClock", { id = "GameClock_Server" })
IPC.createInstance("QueenNode", { id = "Queen" })
IPC.createInstance("FoodHopperNode", { id = "FoodHopper" })
IPC.createInstance("EggClutchNode", { id = "EggClutch" })

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
