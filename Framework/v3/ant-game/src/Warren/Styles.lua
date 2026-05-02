--[[
    Warren Framework v2
    Styles.lua - Universal Style Definitions

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    Central stylesheet for all domains (GUI, Geometry, etc.).
    Used by ClassResolver to compute the cascade formula.

    See docs/RESOLVER.md for the mental model.

    ============================================================================
    CASCADE FORMULA
    ============================================================================

    result = merge(parent, defaults, base[type], classes..., id, inline)

    This file defines:
        - base     : Styles by element type (Part, TextLabel, etc.)
        - classes  : Named style classes
        - ids      : Styles by specific element ID

    ============================================================================
    USAGE
    ============================================================================

    Layouts reference classes by name:
        { id = "wall", class = "brick_red", geometry = {...} }

    Multiple classes applied in order:
        { id = "wall", class = "brick_red weathered", geometry = {...} }

--]]

return {
    -- =========================================================================
    -- BASE STYLES (by element type)
    -- =========================================================================

    base = {
        -- GUI
        TextLabel = {
            backgroundTransparency = 1,
            font = "SourceSans",
            textColor = {255, 255, 255},
        },
        TextButton = {
            backgroundTransparency = 0.2,
            backgroundColor = {60, 60, 60},
            font = "SourceSans",
            textColor = {255, 255, 255},
        },
        Frame = {
            backgroundTransparency = 0.1,
            backgroundColor = {30, 30, 30},
        },

        -- Geometry
        Part = {
            Anchored = true,
            CanCollide = true,
            Material = "SmoothPlastic",
        },
        WedgePart = {
            Anchored = true,
            CanCollide = true,
            Material = "SmoothPlastic",
        },
    },

    -- =========================================================================
    -- CLASS STYLES
    -- =========================================================================

    classes = {
        ------------------------------------------------------------------------
        -- GEOMETRY - Wall Materials
        ------------------------------------------------------------------------

        brick_red = {
            Material = "Brick",
            Color = {180, 130, 100},
        },
        brick_dark = {
            Material = "Brick",
            Color = {150, 100, 75},
        },
        concrete = {
            Material = "Concrete",
            Color = {180, 175, 165},
        },
        stucco = {
            Material = "SmoothPlastic",
            Color = {245, 240, 230},
        },
        stucco_cream = {
            Material = "SmoothPlastic",
            Color = {235, 228, 215},
        },

        ------------------------------------------------------------------------
        -- GEOMETRY - Roof Materials
        ------------------------------------------------------------------------

        roof_slate = {
            Material = "Slate",
            Color = {55, 55, 60},
        },
        roof_terracotta = {
            Material = "Brick",
            Color = {140, 65, 45},
        },
        roof_shingle = {
            Material = "SmoothPlastic",
            Color = {60, 55, 50},
        },

        ------------------------------------------------------------------------
        -- GEOMETRY - Structural
        ------------------------------------------------------------------------

        frame_metal = {
            Material = "DiamondPlate",
            Color = {80, 80, 85},
        },
        glass = {
            Material = "Glass",
            Color = {180, 210, 230},
            Transparency = 0.4,
        },
        wood = {
            Material = "Wood",
            Color = {140, 100, 70},
        },
        wood_dark = {
            Material = "Wood",
            Color = {90, 65, 45},
        },

        ------------------------------------------------------------------------
        -- GEOMETRY - Ground
        ------------------------------------------------------------------------

        ground_grass = {
            Material = "Grass",
            Color = {80, 130, 60},
        },
        ground_cobble = {
            Material = "Cobblestone",
            Color = {140, 135, 130},
        },
        ground_dirt = {
            Material = "Ground",
            Color = {120, 100, 80},
        },

        ------------------------------------------------------------------------
        -- GEOMETRY - Collision/Invisible
        ------------------------------------------------------------------------

        collision = {
            Transparency = 1,
            CanCollide = true,
            CanQuery = true,
        },
        trigger = {
            Transparency = 1,
            CanCollide = false,
            CanQuery = true,
        },

        ------------------------------------------------------------------------
        -- GUI - Typography
        ------------------------------------------------------------------------

        ["hud-text"] = {
            textSize = 24,
            font = "GothamBold",
        },
        ["hud-large"] = {
            textSize = 36,
        },
        ["hud-small"] = {
            textSize = 16,
        },

        ------------------------------------------------------------------------
        -- GUI - Colors
        ------------------------------------------------------------------------

        gold = {
            textColor = {255, 170, 0},
        },
        white = {
            textColor = {255, 255, 255},
        },
        red = {
            textColor = {255, 80, 80},
        },
        green = {
            textColor = {80, 255, 80},
        },
    },

    -- =========================================================================
    -- ID STYLES (highest specificity)
    -- =========================================================================

    ids = {
        -- Example: specific element overrides
    },
}
