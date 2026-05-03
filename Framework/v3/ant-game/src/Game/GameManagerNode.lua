--[[
    Ant Colony Simulation — GameManagerNode
    Server-side game state manager.

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    Manages global game state: difficulty scaling, XP, queen attributes,
    and game over conditions.

    XP: earned 1 per completed explore/gather trip. Spent on queen attributes
    that affect egg production and hatchling stats. Level cost increases
    25% per level: baseCost * 1.25^(level - 1).

    ============================================================================
    QUEEN ATTRIBUTES
    ============================================================================

    eggRate:         reduces queen's eggInterval (faster laying)
    eggEfficiency:   reduces queen's eggEnergyCost (cheaper eggs)
    hatchEndurance:  increases worker maxRange and energyCap
    hatchEfficiency: reduces worker metabolismRate

    ============================================================================
    SIGNALS
    ============================================================================

    IN (receives):
        onTripComplete({ antId })
            - A worker completed an explore or gather. +1 XP.

        onEggHatched({ ... })
            - Recalculate difficulty.

        onQueenDied({ eggCount })
            - Game over.

        onAntDied({ name, id, class })
            - Track colony losses.

        onSpendXP({ attribute })
            - Player spends XP on a queen attribute.

    OUT (sends):
        difficultyChanged({ multiplier, hatchCount })
            - Sent to FoodSourceNode.

        xpStatus({ xp, attributes, nextCosts })
            - Full XP state for HUD.

        queenStatsChanged({ queenStats, hatchlingStats })
            - Updated stats sent to ColonyNode.

        gameOver({ reason, eggCount })
            - Game has ended.

--]]

local Warren = require(game:GetService("ReplicatedStorage").Warren)
local Node = Warren.Node

--------------------------------------------------------------------------------
-- CONSTANTS
--------------------------------------------------------------------------------

local STARTING_MULTIPLIER = 3.0
local DECAY_PER_HATCH = 0.75
local MINIMUM_MULTIPLIER = 0.5

local BASE_XP_COST = 2
local COST_GROWTH = 1.25  -- 25% more per level

-- Base stats (level 0)
local BASE_QUEEN_STATS = {
    eggInterval = 10,
    eggEnergyCost = 50,
}

local BASE_HATCHLING_STATS = {
    maxRange = 30,
    energyCap = 60,
    metabolismRate = 1,
}

-- Per-level bonus
local ATTRIBUTE_DEFS = {
    eggRate = {
        label = "Egg Rate",
        description = "Faster egg laying",
        perLevel = { eggInterval = -1 },  -- reduce by 1 per level
        minValues = { eggInterval = 3 },   -- floor
    },
    eggEfficiency = {
        label = "Egg Efficiency",
        description = "Cheaper eggs",
        perLevel = { eggEnergyCost = -5 },
        minValues = { eggEnergyCost = 10 },
    },
    hatchEndurance = {
        label = "Hatch Endurance",
        description = "Tougher workers (range + energy)",
        perLevel = { maxRange = 5, energyCap = 10 },
        maxValues = { maxRange = 100, energyCap = 200 },
    },
    hatchEfficiency = {
        label = "Hatch Efficiency",
        description = "Workers burn less energy",
        perLevel = { metabolismRate = -0.1 },
        minValues = { metabolismRate = 0.2 },
    },
}

--------------------------------------------------------------------------------
-- GAME MANAGER NODE
--------------------------------------------------------------------------------

local GameManagerNode = Node.extend(function(parent)
    local instanceStates = {}

    local function getState(self)
        if not instanceStates[self.id] then
            instanceStates[self.id] = {
                -- Difficulty
                multiplier = STARTING_MULTIPLIER,
                hatchCount = 0,
                isGameOver = false,

                -- XP
                xp = 0,
                totalXpEarned = 0,

                -- Attribute levels
                levels = {
                    eggRate = 0,
                    eggEfficiency = 0,
                    hatchEndurance = 0,
                    hatchEfficiency = 0,
                },
            }
        end
        return instanceStates[self.id]
    end

    local function cleanupState(self)
        instanceStates[self.id] = nil
    end

    --------------------------------------------------------------------------
    -- XP COST
    --------------------------------------------------------------------------

    local function getLevelCost(level)
        -- Cost for the NEXT level (from current level)
        return math.ceil(BASE_XP_COST * COST_GROWTH ^ level)
    end

    --------------------------------------------------------------------------
    -- STAT CALCULATION
    --------------------------------------------------------------------------

    local function computeQueenStats(state)
        local stats = {
            eggInterval = BASE_QUEEN_STATS.eggInterval,
            eggEnergyCost = BASE_QUEEN_STATS.eggEnergyCost,
        }

        -- Apply eggRate levels
        local erDef = ATTRIBUTE_DEFS.eggRate
        local erLevel = state.levels.eggRate
        for stat, delta in pairs(erDef.perLevel) do
            stats[stat] = stats[stat] + (delta * erLevel)
            if erDef.minValues and erDef.minValues[stat] then
                stats[stat] = math.max(stats[stat], erDef.minValues[stat])
            end
        end

        -- Apply eggEfficiency levels
        local eeDef = ATTRIBUTE_DEFS.eggEfficiency
        local eeLevel = state.levels.eggEfficiency
        for stat, delta in pairs(eeDef.perLevel) do
            stats[stat] = stats[stat] + (delta * eeLevel)
            if eeDef.minValues and eeDef.minValues[stat] then
                stats[stat] = math.max(stats[stat], eeDef.minValues[stat])
            end
        end

        return stats
    end

    local function computeHatchlingStats(state)
        local stats = {
            maxRange = BASE_HATCHLING_STATS.maxRange,
            energyCap = BASE_HATCHLING_STATS.energyCap,
            metabolismRate = BASE_HATCHLING_STATS.metabolismRate,
        }

        -- Apply hatchEndurance levels
        local heDef = ATTRIBUTE_DEFS.hatchEndurance
        local heLevel = state.levels.hatchEndurance
        for stat, delta in pairs(heDef.perLevel) do
            stats[stat] = stats[stat] + (delta * heLevel)
            if heDef.maxValues and heDef.maxValues[stat] then
                stats[stat] = math.min(stats[stat], heDef.maxValues[stat])
            end
        end

        -- Apply hatchEfficiency levels
        local hiDef = ATTRIBUTE_DEFS.hatchEfficiency
        local hiLevel = state.levels.hatchEfficiency
        for stat, delta in pairs(hiDef.perLevel) do
            stats[stat] = stats[stat] + (delta * hiLevel)
            if hiDef.minValues and hiDef.minValues[stat] then
                stats[stat] = math.max(stats[stat], hiDef.minValues[stat])
            end
        end

        return stats
    end

    --------------------------------------------------------------------------
    -- BROADCASTS
    --------------------------------------------------------------------------

    local function fireXPStatus(self)
        local state = getState(self)

        local queenStats = computeQueenStats(state)
        local hatchStats = computeHatchlingStats(state)

        local attributeInfo = {}
        for attr, level in pairs(state.levels) do
            local def = ATTRIBUTE_DEFS[attr]
            local currentValues = {}
            local nextValues = {}

            -- Compute current and next-level values for each stat this attribute affects
            for stat, delta in pairs(def.perLevel) do
                local base
                if stat == "eggInterval" or stat == "eggEnergyCost" then
                    base = queenStats[stat]
                else
                    base = hatchStats[stat]
                end
                currentValues[stat] = base

                -- Preview next level
                local next = base + delta
                if def.minValues and def.minValues[stat] then
                    next = math.max(next, def.minValues[stat])
                end
                if def.maxValues and def.maxValues[stat] then
                    next = math.min(next, def.maxValues[stat])
                end
                nextValues[stat] = next
            end

            attributeInfo[attr] = {
                label = def.label,
                description = def.description,
                level = level,
                cost = getLevelCost(level),
                canAfford = state.xp >= getLevelCost(level),
                currentValues = currentValues,
                nextValues = nextValues,
            }
        end

        self.Out:Fire("xpStatus", {
            xp = state.xp,
            totalXpEarned = state.totalXpEarned,
            attributes = attributeInfo,
        })
    end

    local function fireQueenStats(self)
        local state = getState(self)
        self.Out:Fire("queenStatsChanged", {
            queenStats = computeQueenStats(state),
            hatchlingStats = computeHatchlingStats(state),
        })
    end

    return {
        name = "GameManagerNode",
        domain = "server",

        Sys = {
            onInit = function(self)
                local System = self._System
                if System and System.Debug then
                    System.Debug.info("GameManager", string.format(
                        "Initialized — difficulty %.2f, XP cost base %d (+%.0f%%/level)",
                        STARTING_MULTIPLIER, BASE_XP_COST, (COST_GROWTH - 1) * 100
                    ))
                end
            end,

            onStart = function(self)
                local state = getState(self)
                self.Out:Fire("difficultyChanged", {
                    multiplier = state.multiplier,
                    hatchCount = state.hatchCount,
                })
                fireQueenStats(self)
                fireXPStatus(self)
            end,

            onStop = function(self)
                cleanupState(self)
            end,
        },

        In = {
            onTripComplete = function(self, data)
                local state = getState(self)
                if state.isGameOver then return end

                state.xp = state.xp + 1
                state.totalXpEarned = state.totalXpEarned + 1

                fireXPStatus(self)
            end,

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

            onSpendXP = function(self, data)
                if not data or not data.attribute then return end

                local state = getState(self)
                if state.isGameOver then return end

                local attr = data.attribute
                local def = ATTRIBUTE_DEFS[attr]
                if not def then return end

                local level = state.levels[attr]
                local cost = getLevelCost(level)

                if state.xp < cost then
                    local System = self._System
                    if System and System.Debug then
                        System.Debug.warn("GameManager", string.format(
                            "Not enough XP for %s (have %d, need %d)",
                            attr, state.xp, cost
                        ))
                    end
                    return
                end

                state.xp = state.xp - cost
                state.levels[attr] = level + 1

                local System = self._System
                if System and System.Debug then
                    System.Debug.info("GameManager", string.format(
                        "%s leveled to %d (cost %d XP, %d remaining)",
                        def.label, state.levels[attr], cost, state.xp
                    ))
                end

                fireQueenStats(self)
                fireXPStatus(self)
            end,

            onQueenDied = function(self, data)
                local state = getState(self)
                if state.isGameOver then return end

                state.isGameOver = true

                local System = self._System
                if System and System.Debug then
                    System.Debug.warn("GameManager", string.format(
                        "GAME OVER — Queen died after %d eggs, %d total XP earned",
                        data and data.eggCount or 0, state.totalXpEarned
                    ))
                end

                self.Out:Fire("gameOver", {
                    reason = "queenDied",
                    eggCount = data and data.eggCount or 0,
                    totalXpEarned = state.totalXpEarned,
                })
            end,

            onAntDied = function(self, data)
                local state = getState(self)
                if state.isGameOver then return end

                local System = self._System
                if System and System.Debug then
                    System.Debug.info("GameManager", string.format(
                        "%s (%s) died",
                        data and data.name or "?", data and data.class or "?"
                    ))
                end
            end,
        },

        Out = {
            difficultyChanged = {},
            xpStatus = {},
            queenStatsChanged = {},
            gameOver = {},
        },
    }
end)

return GameManagerNode
