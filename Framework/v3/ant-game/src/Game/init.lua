--[[
    Warren Framework v2
    Game Module Index

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    This module contains game-specific node implementations that extend
    the base classes defined in Lib.

    STRUCTURE
    ---------

    Game/
    ├── init.lua              (this file)
    ├── MarshmallowBag.lua    (extends Lib.Dispenser)
    ├── Camper.lua            (extends Lib.Evaluator)
    └── ...

    USAGE
    -----

    ```lua
    local Game = require(game.ReplicatedStorage.Game)
    local Asset = Lib.System.Asset

    -- Register game-specific nodes
    Asset.register(Game.MarshmallowBag)
    Asset.register(Game.Camper)
    ```

    INHERITANCE
    -----------

    Node (System)
      └── Dispenser (Lib)
            └── MarshmallowBag (Game)

    Game nodes extend Lib nodes, which extend the base Node class.
    Each layer can add required handlers, provide defaults, and override behavior.

--]]

local Game = {}

-- Game-specific node implementations
Game.GameClock = require(script.GameClock)
Game.TimeHUD = require(script.TimeHUD)
Game.ColonyNode = require(script.ColonyNode)
Game.FoodHopperNode = require(script.FoodHopperNode)
Game.EggClutchNode = require(script.EggClutchNode)
Game.PantryHUD = require(script.PantryHUD)
Game.ClutchHUD = require(script.ClutchHUD)
Game.WorkerHUD = require(script.WorkerHUD)
Game.CommandManagerNode = require(script.CommandManagerNode)
Game.CommandMenuHUD = require(script.CommandMenuHUD)
Game.FoodSourceNode = require(script.FoodSourceNode)
Game.FoodSourceHUD = require(script.FoodSourceHUD)
Game.ClassTree = require(script.ClassTree)
Game.GameManagerNode = require(script.GameManagerNode)
Game.XPHUD = require(script.XPHUD)
Game.SurfaceWorldNode = require(script.SurfaceWorldNode)
Game.WorkerRenderNode = require(script.WorkerRenderNode)
Game.ScoreNode = require(script.ScoreNode)
Game.ScoreHUD = require(script.ScoreHUD)

return Game
