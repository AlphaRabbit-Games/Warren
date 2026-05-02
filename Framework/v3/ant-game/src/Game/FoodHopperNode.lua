--[[
    Ant Colony Simulation — FoodHopperNode
    Server-side food storage/dispenser node.

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    Stores food and dispenses energy when bitten. Capacity is infinite for now.
    The energy value per bite depends on the food type loaded.

    ============================================================================
    SIGNALS
    ============================================================================

    IN (receives):
        onBite()
            - Queen requests food. Dispenses energy if food is available.

    OUT (sends):
        foodDispensed({ energy })
            - Energy delivered back to the queen.

--]]

local Warren = require(game:GetService("ReplicatedStorage").Warren)
local Node = Warren.Node

--------------------------------------------------------------------------------
-- FOOD HOPPER NODE
--------------------------------------------------------------------------------

local DEFAULT_ENERGY_PER_BITE = 20

local FoodHopperNode = Node.extend(function(parent)
    local instanceStates = {}

    local function getState(self)
        if not instanceStates[self.id] then
            instanceStates[self.id] = {
                energyPerBite = DEFAULT_ENERGY_PER_BITE,
            }
        end
        return instanceStates[self.id]
    end

    local function cleanupState(self)
        instanceStates[self.id] = nil
    end

    return {
        name = "FoodHopperNode",
        domain = "server",

        Sys = {
            onInit = function(self)
                local System = self._System
                if System and System.Debug then
                    local state = getState(self)
                    System.Debug.info("FoodHopperNode", string.format(
                        "Initialized — %d energy per bite (infinite capacity)",
                        state.energyPerBite
                    ))
                end
            end,

            onStart = function(self) end,

            onStop = function(self)
                cleanupState(self)
            end,
        },

        In = {
            onBite = function(self, data)
                local state = getState(self)
                self.Out:Fire("foodDispensed", {
                    energy = state.energyPerBite,
                })
            end,
        },

        Out = {
            foodDispensed = {},
        },
    }
end)

return FoodHopperNode
