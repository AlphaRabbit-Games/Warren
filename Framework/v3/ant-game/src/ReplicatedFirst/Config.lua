--[[
    Warren Framework v2
    Config.lua - Shared Configuration

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    This module contains shared configuration used by both server and client.
    Edit this file to configure groups, defaults, and other shared settings.

    Since this lives in ReplicatedStorage (via Lib), both contexts can require
    it and get the same configuration. System.lua reads this at load time.

    ============================================================================
    USAGE
    ============================================================================

    Configuration is applied automatically when System.lua loads. To override
    at runtime, use System.setGroups() in your Bootstrap script.

--]]

local Config = {}

--------------------------------------------------------------------------------
-- GROUPS
--------------------------------------------------------------------------------
-- Named groups for Debug and Log filtering.
-- Reference in show/hide/capture/ignore with @GroupName syntax.

Config.groups = {
    Core = { "System.*", "Bootstrap", "Log" },
    Gameplay = { "Combat.*", "Economy.*", "Inventory.*" },
}

--------------------------------------------------------------------------------
-- DEBUG DEFAULTS
--------------------------------------------------------------------------------
-- Default Debug configuration (can be overridden via Debug.configure)

Config.debug = {
    level = "info",
    show = {},
    hide = {},
    solo = {},
}

--------------------------------------------------------------------------------
-- LOG DEFAULTS
--------------------------------------------------------------------------------
-- Default Log configuration (can be overridden via Log.configure)

Config.log = {
    capture = {},
    ignore = {},
    backend = "Memory",
    flushInterval = 30,
    maxBatchSize = 100,
}

return Config
