--[[
    Ant Game — Client Bootstrap
    Warren Framework v2

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    This is the client entry point. It mirrors the server bootstrap but:
    - Uses Memory backend for Log (DataStore is server-only)
    - Only creates client-domain node instances
    - Runs in StarterPlayerScripts

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
Debug.info("Bootstrap", "Client starting...")

Log.init()

local IPC = Lib.System.IPC
local Game = require(ReplicatedStorage:WaitForChild("Game"))

--------------------------------------------------------------------------------
-- NODE REGISTRATION
--------------------------------------------------------------------------------

-- Client-side nodes
IPC.registerNode(Game.TimeHUD)
IPC.registerNode(Game.QueenHUD)
IPC.registerNode(Game.ClutchHUD)

-- Server-side nodes registered for cross-domain wiring resolution
IPC.registerNode(Game.GameClock)
IPC.registerNode(Game.QueenNode)
IPC.registerNode(Game.EggClutchNode)

--------------------------------------------------------------------------------
-- MODE DEFINITION
--------------------------------------------------------------------------------

IPC.defineMode("Colony", {
    nodes = { "GameClock", "TimeHUD", "QueenNode", "QueenHUD", "EggClutchNode", "ClutchHUD" },
    wiring = {
        GameClock = { "TimeHUD", "QueenNode", "EggClutchNode" },
        QueenNode = { "QueenHUD" },
        EggClutchNode = { "ClutchHUD" },
    },
})

--------------------------------------------------------------------------------
-- INSTANCE CREATION
--------------------------------------------------------------------------------

IPC.createInstance("TimeHUD", { id = "TimeHUD_Local" })
IPC.createInstance("QueenHUD", { id = "QueenHUD_Local" })
IPC.createInstance("ClutchHUD", { id = "ClutchHUD_Local" })

IPC.init()
IPC.switchMode("Colony")
IPC.start()

--------------------------------------------------------------------------------
-- CLEANUP ON SHUTDOWN
--------------------------------------------------------------------------------

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

if LocalPlayer then
    LocalPlayer.AncestryChanged:Connect(function(_, parent)
        if not parent then
            Debug.info("Bootstrap", "Client shutting down...")
            Lib.System.stopAll()
            Debug.info("Bootstrap", "Client shutdown complete")
        end
    end)
end

Debug.info("Bootstrap", "Client ready")
