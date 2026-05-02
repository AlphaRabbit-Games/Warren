--[[
    Warren Framework v2
    GeometrySpec - Backwards Compatibility Wrapper

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    DEPRECATION NOTICE
    ============================================================================

    GeometrySpec is now a thin wrapper around Factory.geometry().

    Prefer using Factory directly:
        local Factory = require(Lib.Factory)
        local zone = Factory.geometry(spec)

    This module exists for backwards compatibility.

--]]

local Factory = require(script.Parent.Factory)

local GeometrySpec = {
    _VERSION = "2.0.0",
}

-- Expose submodules for backwards compatibility
GeometrySpec.ClassResolver = require(script.Parent.ClassResolver)
GeometrySpec.Scanner = Factory.Scanner

--------------------------------------------------------------------------------
-- DELEGATE TO FACTORY.GEOMETRY
--------------------------------------------------------------------------------

function GeometrySpec.build(layout, parent)
    return Factory.geometry(layout, parent)
end

function GeometrySpec.clear()
    return Factory.Geometry.clear()
end

function GeometrySpec.get(selector)
    return Factory.Geometry.get(selector)
end

function GeometrySpec.getInstance(selector)
    return Factory.Geometry.getInstance(selector)
end

function GeometrySpec.parseScale(scaleValue)
    return Factory.Geometry.parseScale(scaleValue)
end

function GeometrySpec.getScale()
    return Factory.Geometry.getScale()
end

function GeometrySpec.toStuds(value)
    return Factory.Geometry.toStuds(value)
end

--------------------------------------------------------------------------------
-- SCANNER API (delegate to Factory)
--------------------------------------------------------------------------------

function GeometrySpec.scan(container, options)
    return Factory.scan(container, options)
end

function GeometrySpec.scanToTable(container, options)
    return Factory.Scanner.scan(container, options)
end

function GeometrySpec.scanArea(areaName, container, options)
    return Factory.scanArea(areaName, container, options)
end

function GeometrySpec.mirror(areaName, container, options)
    return Factory.mirror(areaName, container, options)
end

function GeometrySpec.listAreas(container)
    return Factory.listAreas(container)
end

return GeometrySpec
