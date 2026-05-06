--[[
    Ant Colony Simulation — WorkerRenderNode
    Server-side visual layer for worker ants on the surface playfield.

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    Listens to ColonyNode and FoodSourceNode broadcasts and animates a black
    box Part for each living worker. Pure visual — does not affect the sim.

    Movement model:
      - idle / cooldown / pending / non-trip tasks → ant sits at nest entrance.
      - explore / gather* (status="working") → tween between nest and the
        target food pile based on taskProgress / taskDuration:
          progress 0   → 0.5: outbound (nest → source)
          progress 0.5 → 1.0: return   (source → nest)

    Tween duration matches the GameClock tick rate (1s) so each per-tick target
    blends seamlessly into the next without snapping.

    Queens are skipped — they live underground and don't render here.

    ============================================================================
    SIGNALS
    ============================================================================

    IN (receives):
        onColonyStatus({ ants })
            - Per-tick snapshot of all living ants. Reconciles parts.

        onFoodSourceStatus({ discovered, undiscovered, ... })
            - Caches polar→cartesian source positions for trip targets.

--]]

local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Warren = require(game:GetService("ReplicatedStorage").Warren)
local Node = Warren.Node

--------------------------------------------------------------------------------
-- VISUAL CONFIG
--------------------------------------------------------------------------------

local ANT_SIZE = Vector3.new(0.48, 0.2, 0.6)
local ANT_COLOR = Color3.fromRGB(15, 15, 15)
local ANT_Y = ANT_SIZE.Y / 2

local NEST_POS = Vector3.new(0, ANT_Y, 0)
local TICK_DURATION = 1.0  -- matches GameClock cadence

local TWEEN_INFO = TweenInfo.new(
    TICK_DURATION,
    Enum.EasingStyle.Linear,
    Enum.EasingDirection.InOut
)

local GATHER_TASKS = {
    gatherClosest = true, gatherLargest = true, gatherBest = true,
    gatherEfficiency = true, gatherEndurance = true, gatherEggBuff = true,
}

local function isTripTask(taskName)
    return taskName == "explore" or GATHER_TASKS[taskName] == true
end

--------------------------------------------------------------------------------
-- WORKER RENDER NODE
--------------------------------------------------------------------------------

local WorkerRenderNode = Node.extend(function(parent)
    local instanceStates = {}

    local function getState(self)
        if not instanceStates[self.id] then
            instanceStates[self.id] = {
                folder = nil,
                ants = {},     -- antId -> { part = Part, tween = Tween? }
                sources = {},  -- sourceId -> Vector3 (xz on ground)
            }
        end
        return instanceStates[self.id]
    end

    local function cleanupState(self)
        local state = instanceStates[self.id]
        if state and state.folder then
            state.folder:Destroy()
        end
        instanceStates[self.id] = nil
    end

    --------------------------------------------------------------------------
    -- ANT LIFECYCLE
    --------------------------------------------------------------------------

    local function ensureFolder(self)
        local state = getState(self)
        if state.folder and state.folder.Parent then
            return state.folder
        end

        local surface = Workspace:FindFirstChild("Surface")
        local folder = Instance.new("Folder")
        folder.Name = "Ants"
        folder.Parent = surface or Workspace
        state.folder = folder
        return folder
    end

    local function spawnAnt(self, antId)
        local state = getState(self)
        if state.ants[antId] then return state.ants[antId] end

        local folder = ensureFolder(self)

        local part = Instance.new("Part")
        part.Name = "Ant_" .. tostring(antId)
        part.Size = ANT_SIZE
        part.Color = ANT_COLOR
        part.Material = Enum.Material.SmoothPlastic
        part.Anchored = true
        part.CanCollide = false
        part.TopSurface = Enum.SurfaceType.Smooth
        part.BottomSurface = Enum.SurfaceType.Smooth
        part.Position = NEST_POS
        part.Parent = folder

        local entry = { part = part, tween = nil }
        state.ants[antId] = entry
        return entry
    end

    local function despawnAnt(self, antId)
        local state = getState(self)
        local entry = state.ants[antId]
        if not entry then return end
        if entry.tween then entry.tween:Cancel() end
        if entry.part then entry.part:Destroy() end
        state.ants[antId] = nil
    end

    local function tweenTo(entry, targetPos)
        if entry.tween then entry.tween:Cancel() end
        entry.tween = TweenService:Create(entry.part, TWEEN_INFO, { Position = targetPos })
        entry.tween:Play()
    end

    --------------------------------------------------------------------------
    -- TARGET COMPUTATION
    --------------------------------------------------------------------------

    local function computeAntTarget(ant, sources)
        if ant.status == "working" and isTripTask(ant.task) then
            local sourceId = ant.pendingSourceId or ant.targetId
            local sourcePos = sourceId and sources[sourceId]
            if not sourcePos or not ant.taskDuration or ant.taskDuration <= 0 then
                return NEST_POS
            end

            local progress = math.clamp(ant.taskProgress / ant.taskDuration, 0, 1)
            if progress < 0.5 then
                return NEST_POS:Lerp(sourcePos, progress * 2)
            else
                return sourcePos:Lerp(NEST_POS, (progress - 0.5) * 2)
            end
        end

        return NEST_POS
    end

    return {
        name = "WorkerRenderNode",
        domain = "server",

        Sys = {
            onInit = function(self)
                local System = self._System
                if System and System.Debug then
                    System.Debug.info("WorkerRenderNode", "Initialized")
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
                state.sources = {}

                local function cache(list)
                    if not list then return end
                    for _, src in ipairs(list) do
                        local x = math.cos(src.angle) * src.distance
                        local z = math.sin(src.angle) * src.distance
                        state.sources[src.id] = Vector3.new(x, ANT_Y, z)
                    end
                end

                cache(data.discovered)
                cache(data.undiscovered)
            end,

            onColonyStatus = function(self, data)
                if not data or not data.ants then return end

                local state = getState(self)
                local seen = {}

                for _, ant in ipairs(data.ants) do
                    if ant.class ~= "queen" then
                        seen[ant.id] = true
                        local entry = state.ants[ant.id] or spawnAnt(self, ant.id)
                        if entry then
                            tweenTo(entry, computeAntTarget(ant, state.sources))
                        end
                    end
                end

                for antId in pairs(state.ants) do
                    if not seen[antId] then
                        despawnAnt(self, antId)
                    end
                end
            end,
        },

        Out = {},
    }
end)

return WorkerRenderNode
