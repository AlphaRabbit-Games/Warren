--[[
    Warren Framework v2
    Client Bootstrap

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    This is the client entry point. It mirrors the server bootstrap but:
    - Uses Memory backend for Log (DataStore is server-only)
    - Only creates client-domain node instances
    - Runs in StarterPlayerScripts

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
    _G.View = Lib.System.View
end

--------------------------------------------------------------------------------
-- CONFIGURATION
--------------------------------------------------------------------------------

-- Configure debug output
Debug.configure({
    level = "info",  -- "error", "warn", "info", "trace"
})

-- Configure persistent logging (Memory only on client)
local Log = Lib.System.Log
Log.configure({
    backend = "Memory",  -- Always Memory on client (DataStore is server-only)
})

--------------------------------------------------------------------------------
-- BOOTSTRAP
--------------------------------------------------------------------------------

Debug.info("Bootstrap", "Warren v" .. Lib._VERSION)
Debug.info("Bootstrap", "Client starting...")

-- Initialize Log subsystem (generates session ID, starts auto-flush)
Log.init()

-- Initialize IPC subsystem
local IPC = Lib.System.IPC

-- Wait for Game module (game-specific node implementations)
local Game = require(ReplicatedStorage:WaitForChild("Game"))

--------------------------------------------------------------------------------
-- NODE REGISTRATION
--------------------------------------------------------------------------------
-- Register client-domain nodes and define modes here before IPC.init()

-- Register ScreenTransition for screen fade effects during teleportation
IPC.registerNode(Lib.Components.ScreenTransition)

-- Register AreaHUD for area/room display
IPC.registerNode(Lib.Components.AreaHUD)

-- Register MiniMap for full-screen map view
IPC.registerNode(Lib.Components.MiniMap)

-- Register TimeHUD for game time display
IPC.registerNode(Game.TimeHUD)

-- Also register server-side nodes for wiring resolution (they won't create instances)
IPC.registerNode(Lib.Components.JumpPad)
IPC.registerNode(Lib.Components.RegionManager)
IPC.registerNode(Game.GameClock)

--------------------------------------------------------------------------------
-- MODE DEFINITION
--------------------------------------------------------------------------------
-- Define same modes as server for cross-domain wiring to work

IPC.defineMode("Dungeon", {
    nodes = { "JumpPad", "RegionManager", "ScreenTransition", "AreaHUD", "MiniMap" },
    wiring = {
        JumpPad = { "RegionManager" },
        RegionManager = { "ScreenTransition", "AreaHUD", "MiniMap" },
        ScreenTransition = { "RegionManager" },
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
-- INSTANCE CREATION
--------------------------------------------------------------------------------

-- Create ScreenTransition instance (one per client)
IPC.createInstance("ScreenTransition", { id = "ScreenTransition_Local" })

-- Create AreaHUD instance (displays current area/room)
IPC.createInstance("AreaHUD", { id = "AreaHUD_Local" })

-- Create MiniMap instance (full-screen map view)
IPC.createInstance("MiniMap", { id = "MiniMap_Local" })

-- Create TimeHUD instance (displays game time from GameClock)
IPC.createInstance("TimeHUD", { id = "TimeHUD_Local" })

-- Initialize IPC (calls onInit on all registered client instances)
IPC.init()

-- Switch to Dungeon mode (must match server)
IPC.switchMode("Dungeon")

-- Start IPC (enables routing, calls onStart on all instances)
IPC.start()

-- TODO: Initialize other subsystems in order
-- Lib.System.State.init()
-- Lib.System.View.init()

--------------------------------------------------------------------------------
-- CLEANUP ON SHUTDOWN
--------------------------------------------------------------------------------
-- Ensure all nodes are properly stopped when the client disconnects.
-- This disconnects all RunService connections and cleans up state.

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

-- Cleanup when local player is removed (game closing or leaving)
if LocalPlayer then
    LocalPlayer.AncestryChanged:Connect(function(_, parent)
        if not parent then
            Debug.info("Bootstrap", "Client shutting down...")
            Lib.System.stopAll()
            Debug.info("Bootstrap", "Client shutdown complete")
        end
    end)
end

-- Note: game:BindToClose is server-only. For client cleanup, rely on:
-- 1. LocalPlayer.AncestryChanged (fires when player leaves)
-- 2. Node's auto-cleanup when model is destroyed
-- 3. Manual Tests.stopAll() or System.stopAll() before running tests

Debug.info("Bootstrap", "Client ready")

--------------------------------------------------------------------------------
-- DEMOS AUTO-INITIALIZATION
--------------------------------------------------------------------------------
-- Load Demos module which auto-detects and initializes any active demos
-- This enables demos to work in Team Test mode without manual client setup

local Demos = require(ReplicatedStorage:WaitForChild("Warren"):WaitForChild("Demos"))
Debug.info("Bootstrap", "Demos module loaded (auto-init enabled)")
