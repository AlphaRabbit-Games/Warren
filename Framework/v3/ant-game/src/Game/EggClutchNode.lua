--[[
    Ant Colony Simulation — EggClutchNode
    Server-side egg chamber with capacity and hatching.

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    A chamber that holds eggs laid by the queen. Has a capacity that can be
    upgraded by workers up to a maximum. If the queen lays an egg and the
    clutch is full, the egg is discarded.

    Each tick from GameClock advances hatch progress on all eggs. When an
    egg's progress reaches the threshold it hatches — removed from the clutch
    and capacity increases by 1 (the hatched ant frees its slot).

    ============================================================================
    SIGNALS
    ============================================================================

    IN (receives):
        onTick(data)
            - Clock pulse from GameClock. Advances hatch progress on all eggs.

        onEggLaid({ ... })
            - Queen laid an egg. Stored if capacity allows, discarded if full.

        onUpgrade({ amount })
            - Workers expand capacity by `amount` (clamped to maxCapacity).

    OUT (sends):
        clutchStatus({ eggs, capacity, maxCapacity, discarded, hatched,
                       nearestHatchProgress, nearestHatchThreshold })
            - Current state after any change.

        eggDiscarded({ eggs, capacity, discarded })
            - Fired when an egg is lost due to full capacity.

        eggHatched({ hatched, eggs, capacity })
            - Fired when an egg completes hatching.

--]]

local Warren = require(game:GetService("ReplicatedStorage").Warren)
local Node = Warren.Node

--------------------------------------------------------------------------------
-- DEFAULTS
--------------------------------------------------------------------------------

local DEFAULT_CAPACITY = 5
local DEFAULT_MAX_CAPACITY = 5
local DEFAULT_HATCH_THRESHOLD = 120  -- ticks to hatch

--------------------------------------------------------------------------------
-- EGG CLUTCH NODE
--------------------------------------------------------------------------------

local EggClutchNode = Node.extend(function(parent)
    local instanceStates = {}

    local function getState(self)
        if not instanceStates[self.id] then
            instanceStates[self.id] = {
                eggSlots = {},  -- array of { progress = 0 }
                capacity = DEFAULT_CAPACITY,
                maxCapacity = DEFAULT_MAX_CAPACITY,
                hatchThreshold = DEFAULT_HATCH_THRESHOLD,
                discarded = 0,
                hatched = 0,
            }
        end
        return instanceStates[self.id]
    end

    local function cleanupState(self)
        instanceStates[self.id] = nil
    end

    local function fireStatus(self)
        local state = getState(self)

        -- Find nearest-to-hatching egg for HUD
        local nearestProgress = 0
        for _, egg in ipairs(state.eggSlots) do
            if egg.progress > nearestProgress then
                nearestProgress = egg.progress
            end
        end

        self.Out:Fire("clutchStatus", {
            eggs = #state.eggSlots,
            capacity = state.capacity,
            maxCapacity = state.maxCapacity,
            discarded = state.discarded,
            hatched = state.hatched,
            nearestHatchProgress = nearestProgress,
            nearestHatchThreshold = state.hatchThreshold,
        })
    end

    return {
        name = "EggClutchNode",
        domain = "server",

        Sys = {
            onInit = function(self)
                local state = getState(self)
                local System = self._System
                if System and System.Debug then
                    System.Debug.info("EggClutchNode", string.format(
                        "Initialized — capacity %d/%d, hatch at %d ticks",
                        state.capacity, state.maxCapacity, state.hatchThreshold
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
                if #state.eggSlots == 0 then return end

                -- Advance all eggs and collect hatched indices (reverse order)
                local hatchedIndices = {}
                for i, egg in ipairs(state.eggSlots) do
                    egg.progress = egg.progress + 1
                    if egg.progress >= state.hatchThreshold then
                        hatchedIndices[#hatchedIndices + 1] = i
                    end
                end

                -- Process hatches (remove from end to preserve indices)
                for j = #hatchedIndices, 1, -1 do
                    local idx = hatchedIndices[j]
                    table.remove(state.eggSlots, idx)
                    state.hatched = state.hatched + 1

                    self.Out:Fire("eggHatched", {
                        hatched = state.hatched,
                        eggs = #state.eggSlots,
                        capacity = state.capacity,
                    })

                    local System = self._System
                    if System and System.Debug then
                        System.Debug.info("EggClutchNode", string.format(
                            "Egg hatched (#%d) — %d eggs remain, capacity now %d",
                            state.hatched, #state.eggSlots, state.capacity
                        ))
                    end
                end

                fireStatus(self)
            end,

            onEggLaid = function(self, data)
                local state = getState(self)
                local System = self._System

                if #state.eggSlots >= state.capacity then
                    state.discarded = state.discarded + 1

                    if System and System.Debug then
                        System.Debug.warn("EggClutchNode", string.format(
                            "Egg discarded — clutch full %d/%d (total lost: %d)",
                            #state.eggSlots, state.capacity, state.discarded
                        ))
                    end

                    self.Out:Fire("eggDiscarded", {
                        eggs = #state.eggSlots,
                        capacity = state.capacity,
                        discarded = state.discarded,
                    })
                else
                    state.eggSlots[#state.eggSlots + 1] = { progress = 0 }

                    if System and System.Debug then
                        System.Debug.info("EggClutchNode", string.format(
                            "Egg stored — %d/%d",
                            #state.eggSlots, state.capacity
                        ))
                    end
                end

                fireStatus(self)
            end,

            onUpgrade = function(self, data)
                if not data or not data.amount then return end

                local state = getState(self)
                local before = state.capacity
                state.capacity = math.min(state.capacity + data.amount, state.maxCapacity)

                local System = self._System
                if System and System.Debug then
                    System.Debug.info("EggClutchNode", string.format(
                        "Upgraded — capacity %d → %d (max %d)",
                        before, state.capacity, state.maxCapacity
                    ))
                end

                fireStatus(self)
            end,
        },

        Out = {
            clutchStatus = {},
            eggDiscarded = {},
            eggHatched = {},
        },
    }
end)

return EggClutchNode
