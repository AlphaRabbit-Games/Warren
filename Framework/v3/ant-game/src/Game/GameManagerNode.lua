--[[
    Ant Colony Simulation — GameManagerNode
    Server-side game state manager.

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    Manages global game state: difficulty scaling, game over conditions.
    The difficulty multiplier starts high (easy) and decreases by 25% each
    time an egg hatches, making the game progressively harder.

    Broadcasts the current multiplier to FoodSourceNode so newly spawned
    food sources use the updated difficulty.

    ============================================================================
    SIGNALS
    ============================================================================

    IN (receives):
        onEggHatched({ ... })
            - An egg hatched. Recalculate difficulty.

        onQueenDied({ eggCount })
            - Queen starved. Game over.

        onAntDied({ name, id, class })
            - An ant died. Track colony losses.

    OUT (sends):
        difficultyChanged({ multiplier, hatchCount })
            - New difficulty multiplier. Sent to FoodSourceNode.

        gameOver({ reason, eggCount })
            - Game has ended.

--]]

local Warren = require(game:GetService("ReplicatedStorage").Warren)
local Node = Warren.Node

--------------------------------------------------------------------------------
-- DEFAULTS
--------------------------------------------------------------------------------

local STARTING_MULTIPLIER = 3.0
local DECAY_PER_HATCH = 0.75       -- multiply by 0.75 each hatch (lose 25%)
local MINIMUM_MULTIPLIER = 0.5     -- floor so it never becomes impossible

--------------------------------------------------------------------------------
-- GAME MANAGER NODE
--------------------------------------------------------------------------------

local GameManagerNode = Node.extend(function(parent)
    local instanceStates = {}

    local function getState(self)
        if not instanceStates[self.id] then
            instanceStates[self.id] = {
                multiplier = STARTING_MULTIPLIER,
                hatchCount = 0,
                isGameOver = false,
            }
        end
        return instanceStates[self.id]
    end

    local function cleanupState(self)
        instanceStates[self.id] = nil
    end

    return {
        name = "GameManagerNode",
        domain = "server",

        Sys = {
            onInit = function(self)
                local System = self._System
                if System and System.Debug then
                    System.Debug.info("GameManager", string.format(
                        "Initialized — difficulty %.2f, decay %.0f%% per hatch, floor %.2f",
                        STARTING_MULTIPLIER, (1 - DECAY_PER_HATCH) * 100, MINIMUM_MULTIPLIER
                    ))
                end
            end,

            onStart = function(self)
                -- Broadcast initial multiplier
                local state = getState(self)
                self.Out:Fire("difficultyChanged", {
                    multiplier = state.multiplier,
                    hatchCount = state.hatchCount,
                })
            end,

            onStop = function(self)
                cleanupState(self)
            end,
        },

        In = {
            onEggHatched = function(self, data)
                local state = getState(self)
                if state.isGameOver then return end

                state.hatchCount = state.hatchCount + 1
                local before = state.multiplier
                state.multiplier = math.max(
                    MINIMUM_MULTIPLIER,
                    state.multiplier * DECAY_PER_HATCH
                )

                local System = self._System
                if System and System.Debug then
                    System.Debug.info("GameManager", string.format(
                        "Egg #%d hatched — difficulty %.2f → %.2f",
                        state.hatchCount, before, state.multiplier
                    ))
                end

                self.Out:Fire("difficultyChanged", {
                    multiplier = state.multiplier,
                    hatchCount = state.hatchCount,
                })
            end,

            onQueenDied = function(self, data)
                local state = getState(self)
                if state.isGameOver then return end

                state.isGameOver = true

                local System = self._System
                if System and System.Debug then
                    System.Debug.warn("GameManager", string.format(
                        "GAME OVER — Queen died after %d eggs",
                        data and data.eggCount or 0
                    ))
                end

                self.Out:Fire("gameOver", {
                    reason = "queenDied",
                    eggCount = data and data.eggCount or 0,
                })
            end,

            onAntDied = function(self, data)
                local state = getState(self)
                if state.isGameOver then return end

                local System = self._System
                if System and System.Debug then
                    System.Debug.info("GameManager", string.format(
                        "%s (%s) died", data and data.name or "?", data and data.class or "?"
                    ))
                end
            end,
        },

        Out = {
            difficultyChanged = {},
            gameOver = {},
        },
    }
end)

return GameManagerNode
