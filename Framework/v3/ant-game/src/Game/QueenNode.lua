--[[
    Ant Colony Simulation — QueenNode
    Server-side queen ant node.

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    The queen consumes food to build energy, then spends energy to lay eggs.
    All timing is driven by GameClock tick pulses — no background threads.

    Bite cycle:  every `biteRate` ticks, if energy < cap → fire onBite.
    Egg cycle:   only ticks while energy >= eggEnergyCost. After `eggInterval`
                 ticks → deduct cost, fire onEggLaid. Pauses when starving.

    ============================================================================
    SIGNALS
    ============================================================================

    IN (receives):
        onTick(data)
            - Clock pulse from GameClock. Drives bite and egg counters.

        onFoodDispensed({ energy })
            - Energy received from FoodHopper after a bite.

    OUT (sends):
        bite()
            - Requests food from the hopper.

        eggLaid({ energy, energyCap, eggCount })
            - An egg has been produced.

--]]

local Warren = require(game:GetService("ReplicatedStorage").Warren)
local Node = Warren.Node

--------------------------------------------------------------------------------
-- LEVEL DATA
--------------------------------------------------------------------------------

local LEVEL_DATA = {
    [1] = { energyCap = 100, biteRate = 3, eggEnergyCost = 50, eggInterval = 10 },
}

local function getLevelData(level)
    return LEVEL_DATA[level] or LEVEL_DATA[1]
end

--------------------------------------------------------------------------------
-- QUEEN NODE
--------------------------------------------------------------------------------

local QueenNode = Node.extend(function(parent)
    local instanceStates = {}

    local function getState(self)
        if not instanceStates[self.id] then
            local data = getLevelData(1)
            instanceStates[self.id] = {
                level = 1,
                energy = 0,
                energyCap = data.energyCap,
                biteRate = data.biteRate,
                eggEnergyCost = data.eggEnergyCost,
                eggInterval = data.eggInterval,

                -- Tick accumulators
                biteCounter = 0,
                eggCounter = 0,

                -- Stats
                eggCount = 0,
            }
        end
        return instanceStates[self.id]
    end

    local function cleanupState(self)
        instanceStates[self.id] = nil
    end

    return {
        name = "QueenNode",
        domain = "server",

        Sys = {
            onInit = function(self)
                local state = getState(self)
                local System = self._System
                if System and System.Debug then
                    System.Debug.info("QueenNode", string.format(
                        "Initialized — level %d, energyCap %d, biteRate %d, eggCost %d, eggInterval %d",
                        state.level, state.energyCap, state.biteRate,
                        state.eggEnergyCost, state.eggInterval
                    ))
                end
            end,

            onStart = function(self) end,

            onStop = function(self)
                cleanupState(self)
            end,
        },

        In = {
            onTick = function(self, data)
                if not data or data.isPaused then return end

                local state = getState(self)

                -- Bite cycle
                state.biteCounter = state.biteCounter + 1
                if state.biteCounter >= state.biteRate then
                    state.biteCounter = 0
                    if state.energy < state.energyCap then
                        self.Out:Fire("bite", {})
                    end
                end

                -- Egg cycle (only ticks when energy is sufficient)
                local gestating = state.energy >= state.eggEnergyCost
                if gestating then
                    state.eggCounter = state.eggCounter + 1
                    if state.eggCounter >= state.eggInterval then
                        state.eggCounter = 0
                        state.energy = state.energy - state.eggEnergyCost
                        state.eggCount = state.eggCount + 1

                        self.Out:Fire("eggLaid", {
                            energy = state.energy,
                            energyCap = state.energyCap,
                            eggCount = state.eggCount,
                        })

                        local System = self._System
                        if System and System.Debug then
                            System.Debug.info("QueenNode", string.format(
                                "Egg #%d laid — energy %d/%d",
                                state.eggCount, state.energy, state.energyCap
                            ))
                        end
                    end
                end

                -- Broadcast status for HUD
                self.Out:Fire("queenStatus", {
                    energy = state.energy,
                    energyCap = state.energyCap,
                    biteCounter = state.biteCounter,
                    biteRate = state.biteRate,
                    eggCounter = state.eggCounter,
                    eggInterval = state.eggInterval,
                    eggEnergyCost = state.eggEnergyCost,
                    eggCount = state.eggCount,
                    gestating = gestating,
                })
            end,

            onFoodDispensed = function(self, data)
                if not data or not data.energy then return end

                local state = getState(self)
                local before = state.energy
                state.energy = math.min(state.energy + data.energy, state.energyCap)

                local System = self._System
                if System and System.Debug then
                    System.Debug.trace("QueenNode", string.format(
                        "Fed +%d energy → %d/%d",
                        data.energy, state.energy, state.energyCap
                    ))
                end
            end,
        },

        Out = {
            bite = {},
            eggLaid = {},
            queenStatus = {},
        },
    }
end)

return QueenNode
