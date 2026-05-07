--[[
    Ant Colony Simulation — ScoreNode
    Server-side score tracker.

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    Awards score per tick based on living workers and applies a penalty when
    any ant dies. Pure tracking node — does not affect the sim.

    Award:    +5 per worker per tick (queens excluded).
    Penalty:  -10% of current score, rounded to nearest 5, on antDied.
              Score is clamped to 0 from below.

    ============================================================================
    SIGNALS
    ============================================================================

    IN (receives):
        onTick({ isPaused, ... })            - Awards points per worker
        onColonyStatus({ ants })              - Caches worker count
        onAntDied({ name, id, class })        - Applies starvation penalty

    OUT (sends):
        scoreChanged({ score, delta, reason }) - On any score change

--]]

local Warren = require(game:GetService("ReplicatedStorage").Warren)
local Node = Warren.Node

--------------------------------------------------------------------------------
-- CONFIG
--------------------------------------------------------------------------------

local POINTS_PER_WORKER_PER_TICK = 5
local STARVE_PENALTY_PCT = 0.10
local PENALTY_ROUND_TO = 5

local function roundToNearest(value, multiple)
    return math.floor(value / multiple + 0.5) * multiple
end

--------------------------------------------------------------------------------
-- SCORE NODE
--------------------------------------------------------------------------------

local ScoreNode = Node.extend(function(parent)
    local instanceStates = {}

    local function getState(self)
        if not instanceStates[self.id] then
            instanceStates[self.id] = {
                score = 0,
                workerCount = 0,
            }
        end
        return instanceStates[self.id]
    end

    local function cleanupState(self)
        instanceStates[self.id] = nil
    end

    local function broadcast(self, delta, reason)
        local state = getState(self)
        self.Out:Fire("scoreChanged", {
            score = state.score,
            delta = delta or 0,
            reason = reason,
        })
    end

    return {
        name = "ScoreNode",
        domain = "server",

        Sys = {
            onInit = function(self)
                local System = self._System
                if System and System.Debug then
                    System.Debug.info("ScoreNode", "Initialized — 0 points")
                end
            end,

            onStart = function(self)
                broadcast(self, 0, "init")
            end,

            onStop = function(self)
                cleanupState(self)
            end,
        },

        In = {
            onTick = function(self, data)
                if not data or data.isPaused then return end

                local state = getState(self)
                if state.workerCount <= 0 then return end

                local award = state.workerCount * POINTS_PER_WORKER_PER_TICK
                state.score = state.score + award
                broadcast(self, award, "tick")
            end,

            onColonyStatus = function(self, data)
                if not data or not data.ants then return end

                local count = 0
                for _, ant in ipairs(data.ants) do
                    if ant.class ~= "queen" then
                        count = count + 1
                    end
                end

                local state = getState(self)
                state.workerCount = count
            end,

            onAntDied = function(self, data)
                if not data then return end

                local state = getState(self)
                local penalty = roundToNearest(state.score * STARVE_PENALTY_PCT, PENALTY_ROUND_TO)
                if penalty <= 0 then return end

                state.score = math.max(0, state.score - penalty)
                broadcast(self, -penalty, "starvation")

                local System = self._System
                if System and System.Debug then
                    System.Debug.info("ScoreNode", string.format(
                        "%s died — -%d penalty (score now %d)",
                        data.name or "ant", penalty, state.score
                    ))
                end
            end,
        },

        Out = {
            scoreChanged = {},
        },
    }
end)

return ScoreNode
