--[[
    Warren Core Framework
    Main Entry Point

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    Warren is a Roblox game framework designed for developer ergonomics.
    It follows an Arduino-like model where games are composed of modular
    components wired together through a unified messaging bus.

    This is the CORE package. It provides the system-level framework that
    game projects build against. Game-specific components, demos, tests,
    and layout data live in the game project repo.

    This module (Lib) is the main entry point. It exposes:
        - System: Core framework subsystems (Debug, IPC, State, Asset, Store, View)
        - Node: Base class for all game components
        - Factory: Declarative instance builder (geometry, gui)
        - GeometrySpec: Backwards compatibility wrapper
        - ClassResolver: CSS-like style cascade system
        - Styles: Base style definitions
        - Layout: Data-driven layout builder/schema/serializer
        - Layouts: Lazy-loader infrastructure (game projects populate with data)

    ============================================================================
    USAGE
    ============================================================================

    ```lua
    local Lib = require(game.ReplicatedStorage.Warren)

    -- Access system subsystems
    local Debug = Lib.System.Debug
    local IPC = Lib.System.IPC

    -- Configure debug
    Debug.configure({ level = "trace" })

    -- Log messages
    Debug.info("MyModule", "Framework loaded")
    ```

    ============================================================================
    ARCHITECTURE
    ============================================================================

    See docs/ARCHITECTURE.md for full documentation.

    Key principles:
    - Single ModuleScript per system with nested submodules
    - No code runs on load - Bootstrap controls execution
    - Declarative manifest defines structure and wiring
    - Closure-protected internals with public API surface
    - Singleton/Factory pattern for each subsystem

--]]

local Lib = {
    _VERSION = "2.0.0-dev",
}

-- Core system module (Debug, IPC, State, Asset, Store, View)
Lib.System = require(script.System)

-- Node base class for game components
Lib.Node = require(script.Node)

-- Factory: Declarative instance builder (geometry, gui)
Lib.Factory = require(script.Factory)

-- GeometrySpec: Backwards compatibility wrapper (prefer Lib.Factory)
Lib.GeometrySpec = require(script.GeometrySpec)

-- ClassResolver: CSS-like style cascade system
Lib.ClassResolver = require(script.ClassResolver)

-- Styles: Base style definitions
Lib.Styles = require(script.Styles)

-- Layout: Data-driven layout builder/schema/serializer
Lib.Layout = require(script.Components.Layout)

-- Standalone map layouts (lazy-loader infrastructure)
-- Game projects populate this with their own layout data files
Lib.Layouts = require(script.Layouts)

return Lib
