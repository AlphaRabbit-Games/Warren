--[[
    Ant Colony Simulation — FoodHopperNode (Pantry)
    Server-side food storage chamber with blended nutrition.

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    A pantry that stores food by type. Energy per bite is a weighted average
    of all food types in the pantry, divided by colony size. This means a
    pantry full of high-quality food feeds more per bite, and larger colonies
    get less per bite (pressure to gather more).

    ============================================================================
    SIGNALS
    ============================================================================

    IN (receives):
        onColonyBite({ count, colonySize })
            - Colony requests food. Dispenses blended energy.

        onFoodGathered({ energy, foodType })
            - Worker deposits food from a gather task.

        onPantryUpgrade({ amount })
            - Worker completed an upgrade. Increases max capacity.

    OUT (sends):
        foodDispensed({ energy })
            - Energy delivered to the colony.

        hopperStatus({ stock, capacity, maxCapacity, energyPerBite, contents })
            - Current state, fired after any change.

--]]

local Warren = require(game:GetService("ReplicatedStorage").Warren)
local Node = Warren.Node

--------------------------------------------------------------------------------
-- DEFAULTS
--------------------------------------------------------------------------------

local DEFAULT_CAPACITY = 200
local DEFAULT_MAX_CAPACITY = 1000

--------------------------------------------------------------------------------
-- BUFF DEFINITIONS
--------------------------------------------------------------------------------
-- Buff power is inverse to nutrition tier: crumbs buff hard, honeydew barely.
-- Each food type buffs specific stats. Insect buffs all stats at medium power.
-- Max buff per stat is capped at the buffPower value (0.0 - 1.0 scale after
-- weighting by pantry ratio).

local FOOD_BUFFS = {
    crumb    = { buffPower = 0.50, stats = { efficiency = 1.0 } },
    seed     = { buffPower = 0.40, stats = { endurance = 1.0 } },
    insect   = { buffPower = 0.30, stats = { efficiency = 0.33, endurance = 0.33, eggProduction = 0.34 } },
    fruit    = { buffPower = 0.20, stats = { eggProduction = 1.0 } },
    honeydew = { buffPower = 0.10, stats = {} },
}

--------------------------------------------------------------------------------
-- FOOD HOPPER NODE
--------------------------------------------------------------------------------

local FoodHopperNode = Node.extend(function(parent)
    local instanceStates = {}

    local function getState(self)
        if not instanceStates[self.id] then
            instanceStates[self.id] = {
                -- Stock per food type: { [foodType] = energy }
                contents = {},
                totalStock = 0,
                capacity = DEFAULT_CAPACITY,
                maxCapacity = DEFAULT_MAX_CAPACITY,
                colonySize = 1,
            }
        end
        return instanceStates[self.id]
    end

    local function cleanupState(self)
        instanceStates[self.id] = nil
    end

    --------------------------------------------------------------------------
    -- STOCK HELPERS
    --------------------------------------------------------------------------

    local function recalcTotal(state)
        local total = 0
        for _, amount in pairs(state.contents) do
            total = total + amount
        end
        state.totalStock = total
    end

    -- Weighted average energy across all food types, divided by colony size
    local function computeEnergyPerBite(state)
        if state.totalStock <= 0 or state.colonySize <= 0 then
            return 0
        end
        -- The total stock IS the total energy. Per bite = total / colony size.
        -- But we cap it so one bite doesn't drain everything.
        return math.max(1, math.floor(state.totalStock / state.colonySize))
    end

    -- Drain `amount` energy from contents proportionally
    local function drainProportional(state, amount)
        if state.totalStock <= 0 then return 0 end

        local actual = math.min(amount, state.totalStock)
        local ratio = actual / state.totalStock

        for foodType, stored in pairs(state.contents) do
            local drain = stored * ratio
            state.contents[foodType] = stored - drain
            if state.contents[foodType] < 0.01 then
                state.contents[foodType] = nil
            end
        end

        recalcTotal(state)
        return actual
    end

    -- Compute buff profile from pantry food mix
    local function computeBuffProfile(state)
        local buffs = { efficiency = 0, endurance = 0, eggProduction = 0 }

        if state.totalStock <= 0 then return buffs end

        for foodType, amount in pairs(state.contents) do
            local def = FOOD_BUFFS[foodType]
            if def then
                local ratio = amount / state.totalStock  -- fraction of pantry this type represents
                for stat, weight in pairs(def.stats) do
                    buffs[stat] = buffs[stat] + (ratio * def.buffPower * weight)
                end
            end
        end

        return buffs
    end

    local function fireStatus(self)
        local state = getState(self)

        -- Build contents summary for HUD
        local contentsList = {}
        for foodType, amount in pairs(state.contents) do
            if amount > 0 then
                contentsList[#contentsList + 1] = {
                    type = foodType,
                    amount = math.floor(amount),
                }
            end
        end

        self.Out:Fire("hopperStatus", {
            stock = math.floor(state.totalStock),
            capacity = state.capacity,
            maxCapacity = state.maxCapacity,
            energyPerBite = computeEnergyPerBite(state),
            contents = contentsList,
            buffProfile = computeBuffProfile(state),
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
                        "Initialized — stock %d/%d (blended pantry)",
                        state.totalStock, state.capacity
                    ))
                end
            end,

            onStart = function(self)
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

                -- Update colony size for bite calculation
                if data and data.colonySize then
                    state.colonySize = data.colonySize
                end

                if state.totalStock <= 0 then
                    self.Out:Fire("foodDispensed", { energy = 0 })
                    return
                end

                local perBite = computeEnergyPerBite(state)
                local totalDispensed = 0

                for _ = 1, count do
                    if state.totalStock <= 0 then break end
                    local amount = drainProportional(state, perBite)
                    totalDispensed = totalDispensed + amount
                end

                self.Out:Fire("foodDispensed", {
                    energy = math.floor(totalDispensed),
                    buffProfile = computeBuffProfile(state),
                })
                if totalDispensed > 0 then
                    fireStatus(self)
                end
            end,

            onFoodGathered = function(self, data)
                if not data or not data.energy then return end

                local state = getState(self)
                local foodType = data.foodType or "unknown"
                local spaceLeft = state.capacity - state.totalStock

                if spaceLeft <= 0 then
                    local System = self._System
                    if System and System.Debug then
                        System.Debug.warn("FoodHopperNode", "Pantry full — food wasted!")
                    end
                    return
                end

                local deposited = math.min(data.energy, spaceLeft)
                state.contents[foodType] = (state.contents[foodType] or 0) + deposited
                recalcTotal(state)

                local System = self._System
                if System and System.Debug then
                    System.Debug.info("FoodHopperNode", string.format(
                        "Deposited %d %s — stock %d/%d, bite value %d",
                        deposited, foodType,
                        math.floor(state.totalStock), state.capacity,
                        computeEnergyPerBite(state)
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
