--[[
    Ant Colony Simulation — SurfaceWorldNode
    Server-side world geometry for the top-down surface view.

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    Builds the surface playfield: ground plane, nest entrance, and food piles.
    Listens to FoodSourceNode broadcasts and reconciles a folder of pile parts
    in workspace.Surface.FoodPiles.

    Pile position from polar source data: (cos(angle)*distance, sin(angle)*distance).

    ============================================================================
    SIGNALS
    ============================================================================

    IN (receives):
        onFoodSourceStatus({ discovered, undiscovered, undiscoveredCount })
            - Reconciles pile parts against the union of discovered + undiscovered.
              (Fog-of-war disabled for now — all piles render.)

--]]

local Workspace = game:GetService("Workspace")

local Warren = require(game:GetService("ReplicatedStorage").Warren)
local Node = Warren.Node

--------------------------------------------------------------------------------
-- VISUAL CONFIG
--------------------------------------------------------------------------------

local PLAYFIELD_SIZE = 200
local GROUND_THICKNESS = 1
local NEST_DIAMETER = 6
local NEST_THICKNESS = 0.4

local GROUND_COLOR = Color3.fromRGB(110, 90, 65)
local NEST_COLOR = Color3.fromRGB(20, 15, 10)

local FOOD_VISUALS = {
    crumb    = { shape = "Block", size = Vector3.new(1.25, 0.75, 1.25), color = Color3.fromRGB(200, 160, 100) },
    seed     = { shape = "Ball",  size = Vector3.new(1.5, 1.5, 1.5),    color = Color3.fromRGB(140, 90, 60) },
    insect   = { shape = "Block", size = Vector3.new(2, 0.75, 2),       color = Color3.fromRGB(60, 40, 40) },
    fruit    = { shape = "Ball",  size = Vector3.new(2, 2, 2),          color = Color3.fromRGB(220, 60, 60) },
    honeydew = { shape = "Ball",  size = Vector3.new(2.5, 2.5, 2.5),    color = Color3.fromRGB(240, 220, 80) },
}

--------------------------------------------------------------------------------
-- SURFACE WORLD NODE
--------------------------------------------------------------------------------

local SurfaceWorldNode = Node.extend(function(parent)
    local instanceStates = {}

    local function getState(self)
        if not instanceStates[self.id] then
            instanceStates[self.id] = {
                surfaceFolder = nil,
                pilesFolder = nil,
                piles = {},  -- sourceId -> Part
            }
        end
        return instanceStates[self.id]
    end

    local function cleanupState(self)
        local state = instanceStates[self.id]
        if state and state.surfaceFolder then
            state.surfaceFolder:Destroy()
        end
        instanceStates[self.id] = nil
    end

    --------------------------------------------------------------------------
    -- WORLD BUILDERS
    --------------------------------------------------------------------------

    local function buildWorld(self)
        local state = getState(self)

        local folder = Instance.new("Folder")
        folder.Name = "Surface"
        folder.Parent = Workspace
        state.surfaceFolder = folder

        local ground = Instance.new("Part")
        ground.Name = "Ground"
        ground.Size = Vector3.new(PLAYFIELD_SIZE, GROUND_THICKNESS, PLAYFIELD_SIZE)
        ground.Position = Vector3.new(0, -GROUND_THICKNESS / 2, 0)
        ground.Anchored = true
        ground.TopSurface = Enum.SurfaceType.Smooth
        ground.BottomSurface = Enum.SurfaceType.Smooth
        ground.Color = GROUND_COLOR
        ground.Material = Enum.Material.Ground
        ground.Parent = folder

        -- Nest entrance: cylinder with axis rotated to vertical (top-down: dark disk)
        local nest = Instance.new("Part")
        nest.Name = "NestEntrance"
        nest.Shape = Enum.PartType.Cylinder
        nest.Size = Vector3.new(NEST_THICKNESS, NEST_DIAMETER, NEST_DIAMETER)
        nest.CFrame = CFrame.new(0, NEST_THICKNESS / 2 - 0.05, 0)
            * CFrame.Angles(0, 0, math.rad(90))
        nest.Anchored = true
        nest.Color = NEST_COLOR
        nest.Material = Enum.Material.Slate
        nest.Parent = folder

        local piles = Instance.new("Folder")
        piles.Name = "FoodPiles"
        piles.Parent = folder
        state.pilesFolder = piles
    end

    --------------------------------------------------------------------------
    -- PILE LIFECYCLE
    --------------------------------------------------------------------------

    local function spawnPile(self, source)
        local state = getState(self)
        if state.piles[source.id] then return end

        local visual = FOOD_VISUALS[source.type] or FOOD_VISUALS.crumb

        local part = Instance.new("Part")
        part.Name = string.format("Pile_%d_%s", source.id, source.type)
        part.Shape = (visual.shape == "Ball") and Enum.PartType.Ball or Enum.PartType.Block
        part.Size = visual.size
        part.Color = visual.color
        part.Material = Enum.Material.SmoothPlastic
        part.Anchored = true
        part.TopSurface = Enum.SurfaceType.Smooth
        part.BottomSurface = Enum.SurfaceType.Smooth

        local x = math.cos(source.angle) * source.distance
        local z = math.sin(source.angle) * source.distance
        part.Position = Vector3.new(x, visual.size.Y / 2, z)

        part.Parent = state.pilesFolder
        state.piles[source.id] = part
    end

    local function despawnPile(self, sourceId)
        local state = getState(self)
        local part = state.piles[sourceId]
        if part then
            part:Destroy()
            state.piles[sourceId] = nil
        end
    end

    return {
        name = "SurfaceWorldNode",
        domain = "server",

        Sys = {
            onInit = function(self)
                buildWorld(self)

                local System = self._System
                if System and System.Debug then
                    System.Debug.info("SurfaceWorldNode", string.format(
                        "Surface built — %d×%d ground, nest at origin",
                        PLAYFIELD_SIZE, PLAYFIELD_SIZE
                    ))
                end
            end,

            onStop = function(self)
                cleanupState(self)
            end,
        },

        In = {
            onFoodSourceStatus = function(self, data)
                if not data then return end

                local state = getState(self)
                local seen = {}

                local function reconcile(list)
                    if not list then return end
                    for _, src in ipairs(list) do
                        seen[src.id] = true
                        if not state.piles[src.id] then
                            spawnPile(self, src)
                        end
                    end
                end

                reconcile(data.discovered)
                reconcile(data.undiscovered)

                for sourceId in pairs(state.piles) do
                    if not seen[sourceId] then
                        despawnPile(self, sourceId)
                    end
                end
            end,
        },

        Out = {},
    }
end)

return SurfaceWorldNode
