--[[
    Warren Framework v2
    Layout/init.lua - Layout Module Index

    Copyright (c) 2026 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    The Layout module provides a data-driven approach to dungeon generation:

    - LayoutSchema: Type definitions and validation
    - LayoutBuilder: Generate layouts from seed (data only, no parts)
    - LayoutInstantiator: Create parts from layout data
    - LayoutSerializer: Encode/decode for storage

    ============================================================================
    USAGE
    ============================================================================

    ```lua
    local Layout = require(Lib.Components.Layout)

    -- Generate a new layout from seed
    local layout = Layout.Builder.generate({
        seed = 12345,
        origin = { 0, 20, 0 },
        mainPathLength = 8,
        spurCount = 4,
    })

    -- Instantiate parts in world
    local result = Layout.Instantiator.instantiate(layout, {
        name = "Region_1",
    })

    -- Serialize for storage
    local encoded = Layout.Serializer.encode(layout)

    -- Later: decode and reinstantiate
    local restored = Layout.Serializer.decode(encoded)
    local result2 = Layout.Instantiator.instantiate(restored)
    ```

    ============================================================================
    ARCHITECTURE
    ============================================================================

    Generation Phase (once per new region):
        Seed + Config → LayoutBuilder → Layout Table

    Instantiation Phase (on load/rebuild):
        Layout Table → LayoutInstantiator → Parts

    Persistence:
        Layout Table ↔ LayoutSerializer ↔ String (DataStore/sharing)

--]]

local Layout = {}

Layout.Schema = require(script.LayoutSchema)
Layout.Context = require(script.LayoutContext)
Layout.Builder = require(script.LayoutBuilder)
Layout.Instantiator = require(script.LayoutInstantiator)
Layout.Serializer = require(script.LayoutSerializer)
Layout.GeometryDef = require(script.GeometryDef)

-- Convenience re-exports
Layout.VERSION = Layout.Schema.VERSION
Layout.generate = Layout.Builder.generate
Layout.enrich = Layout.Builder.enrich  -- Composable enrichment of GeometryDef
Layout.instantiate = Layout.Instantiator.instantiate
Layout.encode = Layout.Serializer.encode
Layout.decode = Layout.Serializer.decode

return Layout
