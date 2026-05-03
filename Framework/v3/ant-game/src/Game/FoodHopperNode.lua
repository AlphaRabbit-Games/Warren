--[[
    Ant Colony Simulation — FoodHopperNode (Pantry)
    Server-side food storage chamber.

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    A pantry that stores food with finite capacity. Starts empty.
    Workers deposit food via gather tasks. Queen and idle workers
    draw from it via bite signals. Can be upgraded to increase capacity.

    ============================================================================
    SIGNALS
    ============================================================================

    IN (receives):
        onBite()
            - Queen or idle worker requests food. Dispenses if stock > 0.

        onFoodGathered({ energy })
            - Worker deposits food from a gather task.

        onPantryUpgrade({ amount })
            - Worker completed an upgrade. Increases max capacity.

    OUT (sends):
        foodDispensed({ energy })
            - Energy delivered to the requester.

        hopperStatus({ stock, capacity, maxCapacity, energyPerBite })
            - Current state, fired after any change.

--]]

local Warren = require(game:GetService("ReplicatedStorage").Warren)
local Node = Warren.Node

--------------------------------------------------------------------------------
-- DEFAULTS
--------------------------------------------------------------------------------

local DEFAULT_ENERGY_PER_BITE = 20
local DEFAULT_CAPACITY = 200
local DEFAULT_MAX_CAPACITY = 1000

--------------------------------------------------------------------------------
-- FOOD HOPPER NODE
--------------------------------------------------------------------------------

local FoodHopperNode = Node.extend(function(parent)
    local instanceStates = {}

    local function getState(self)
        if not instanceStates[self.id] then
            instanceStates[self.id] = {
                stock = 0,
                capacity = DEFAULT_CAPACITY,
                maxCapacity = DEFAULT_MAX_CAPACITY,
                energyPerBite = DEFAULT_ENERGY_PER_BITE,
            }
        end
        return instanceStates[self.id]
    end

    local function cleanupState(self)
        instanceStates[self.id] = nil
    end

    local function fireStatus(self)
        local state = getState(self)
        self.Out:Fire("hopperStatus", {
            stock = state.stock,
            capacity = state.capacity,
            maxCapacity = state.maxCapacity,
            energyPerBite = state.energyPerBite,
        })
    end

    return {
        name = "FoodHopperNode",
        domain = "server",

        Sys = {
            onInit = function(self)
                local state = getState(self)
                local System = self._System
                if System and System.Debug then
                    System.Debug.info("FoodHopperNode", string.format(
                        "Initialized — stock %d/%d, %d energy per bite",
                        state.stock, state.capacity, state.energyPerBite
                    ))
                end

            end,

            onStart = function(self)
                -- Fire initial status after wiring is connected
                fireStatus(self)
            end,

            onStop = function(self)
                cleanupState(self)
            end,
        },

        In = {
            onColonyBite = function(self, data)
                local state = getState(self)
                local count = (data and data.count) or 1
                local totalDispensed = 0

                for _ = 1, count do
                    if state.stock <= 0 then break end
                    local amount = math.min(state.energyPerBite, state.stock)
                    state.stock = state.stock - amount
                    totalDispensed = totalDispensed + amount
                end

                self.Out:Fire("foodDispensed", { energy = totalDispensed })
                if totalDispensed > 0 then
                    fireStatus(self)
                end
            end,

            onFoodGathered = function(self, data)
                if not data or not data.energy then return end

                local state = getState(self)
                local before = state.stock
                state.stock = math.min(state.stock + data.energy, state.capacity)

                local System = self._System
                if System and System.Debug then
                    System.Debug.info("FoodHopperNode", string.format(
                        "Food deposited — +%d, stock %d → %d/%d",
                        data.energy, before, state.stock, state.capacity
                    ))
                end

                fireStatus(self)
            end,

            onPantryUpgrade = function(self, data)
                if not data or not data.amount then return end

                local state = getState(self)
                local before = state.capacity
                state.capacity = math.min(state.capacity + data.amount, state.maxCapacity)

                local System = self._System
                if System and System.Debug then
                    System.Debug.info("FoodHopperNode", string.format(
                        "Upgraded — capacity %d → %d (max %d)",
                        before, state.capacity, state.maxCapacity
                    ))
                end

                fireStatus(self)
            end,
        },

        Out = {
            foodDispensed = {},
            hopperStatus = {},
        },
    }
end)

return FoodHopperNode
