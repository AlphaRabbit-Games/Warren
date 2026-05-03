--[[
    Ant Colony Simulation — FoodSourceNode
    Server-side food source manager.

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    Manages all food sources in the world — discovered and undiscovered.
    Generates initial inventory at game start, handles explore/gather requests.

    Explore: picks nearest undiscovered source, returns distance for travel time.
    Gather:  picks source by strategy (closest/largest/best), returns info.
    Sources have finite pile sizes and are removed when exhausted.
    New sources spawn periodically over time.

    ============================================================================
    SIGNALS
    ============================================================================

    IN (receives):
        onTick(data)
            - Clock pulse. Spawns new sources over time.

        onExploreRequest({ antId })
            - Ant wants to explore. Returns nearest undiscovered source info.

        onGatherRequest({ antId, strategy })
            - Ant wants to gather. strategy = "closest"|"largest"|"best"

        onGatherComplete({ antId, sourceId })
            - Ant returned from gathering. Decrements pile, deposits food.

    OUT (sends):
        exploreAssigned({ antId, distance, sourceId })
            - Tells ColonyNode how long the explore trip takes.

        exploreFailed({ antId })
            - No undiscovered sources in range.

        sourceDiscovered({ sourceId, type, energyPerGather, remaining, distance })
            - A source was found.

        gatherAssigned({ antId, sourceId, distance, energyPerGather })
            - Tells ColonyNode which source and trip duration.

        gatherFailed({ antId })
            - No discovered sources available for strategy.

        foodGathered({ energy })
            - Food delivered to pantry.

        foodSourceStatus({ discovered, undiscovered })
            - Full status for HUD and CommandManager.

        sourceExhausted({ sourceId })
            - A pile ran out.

--]]

local Warren = require(game:GetService("ReplicatedStorage").Warren)
local Node = Warren.Node

--------------------------------------------------------------------------------
-- FOOD TYPE DEFINITIONS
--------------------------------------------------------------------------------

-- Food type definitions (energyPerGather computed from formula at spawn time)
-- nutritionTier: multiplier on base energy (higher tier = more nutritious)
local FOOD_TYPES = {
    { type = "crumb",    nutritionTier = 1, pileRange = { 10, 15 }, distanceRange = { 5, 15 },   weight = 30, buffStat = "efficiency",     buffPower = 0.50 },
    { type = "seed",     nutritionTier = 2, pileRange = { 10, 20 }, distanceRange = { 10, 25 },  weight = 25, buffStat = "endurance",       buffPower = 0.40 },
    { type = "insect",   nutritionTier = 3, pileRange = { 10, 25 }, distanceRange = { 20, 45 },  weight = 20, buffStat = "all",             buffPower = 0.30 },
    { type = "fruit",    nutritionTier = 4, pileRange = { 10, 30 }, distanceRange = { 35, 70 },  weight = 15, buffStat = "eggProduction",   buffPower = 0.20 },
    { type = "honeydew", nutritionTier = 5, pileRange = { 10, 35 }, distanceRange = { 50, 100 }, weight = 10, buffStat = "none",            buffPower = 0.00 },
}

-- Lookup buff power by food type name
local BUFF_POWER_BY_TYPE = {}
for _, ft in ipairs(FOOD_TYPES) do
    BUFF_POWER_BY_TYPE[ft.type] = { stat = ft.buffStat, power = ft.buffPower }
end

-- Break-even formula:
--   energyPerGather = colonySize * metabolismRate * (distance * 2 + cooldown) * difficultyMultiplier * nutritionTier
-- We use a baseline colony size of 2 (starting colony) and metabolismRate of 1.
local DIFFICULTY_MULTIPLIER = 3.0   -- >1 = easier, 1 = break-even, <1 = impossible
local BASELINE_COLONY_SIZE = 2
local BASELINE_METABOLISM = 1
local BASELINE_COOLDOWN = 5

local INITIAL_SOURCE_COUNT = 10
local SPAWN_INTERVAL = 120
local MAX_SOURCES = 30

--------------------------------------------------------------------------------
-- HELPERS
--------------------------------------------------------------------------------

local function weightedRandom(rng)
    local totalWeight = 0
    for _, ft in ipairs(FOOD_TYPES) do
        totalWeight = totalWeight + ft.weight
    end

    local roll = rng:NextNumber() * totalWeight
    local cumulative = 0
    for _, ft in ipairs(FOOD_TYPES) do
        cumulative = cumulative + ft.weight
        if roll <= cumulative then
            return ft
        end
    end
    return FOOD_TYPES[1]
end

local function randomInRange(rng, min, max)
    return math.floor(rng:NextNumber() * (max - min + 1)) + min
end

--------------------------------------------------------------------------------
-- FOOD SOURCE NODE
--------------------------------------------------------------------------------

local FoodSourceNode = Node.extend(function(parent)
    local instanceStates = {}

    local function getState(self)
        if not instanceStates[self.id] then
            instanceStates[self.id] = {
                sources = {},
                nextSourceId = 1,
                rng = Random.new(),
                spawnCounter = 0,
                difficultyMultiplier = DIFFICULTY_MULTIPLIER,
            }
        end
        return instanceStates[self.id]
    end

    local function cleanupState(self)
        instanceStates[self.id] = nil
    end

    --------------------------------------------------------------------------
    -- SOURCE GENERATION
    --------------------------------------------------------------------------

    local function generateSource(state)
        local ft = weightedRandom(state.rng)
        local id = state.nextSourceId
        state.nextSourceId = id + 1

        local distance = randomInRange(state.rng, ft.distanceRange[1], ft.distanceRange[2])
        local gatherCycle = distance * 2 + BASELINE_COOLDOWN
        local energy = math.floor(
            BASELINE_COLONY_SIZE * BASELINE_METABOLISM * gatherCycle
            * state.difficultyMultiplier * ft.nutritionTier
        )

        local source = {
            id = id,
            type = ft.type,
            energyPerGather = energy,
            remaining = randomInRange(state.rng, ft.pileRange[1], ft.pileRange[2]),
            distance = distance,
            discovered = false,
            buffStat = ft.buffStat,
            buffPower = ft.buffPower,
        }

        state.sources[#state.sources + 1] = source
        return source
    end

    --------------------------------------------------------------------------
    -- SOURCE LOOKUP
    --------------------------------------------------------------------------

    local function findNearestUndiscovered(state, maxRange)
        local best = nil
        for _, s in ipairs(state.sources) do
            if not s.discovered and s.remaining > 0 then
                if not maxRange or s.distance <= maxRange then
                    if not best or s.distance < best.distance then
                        best = s
                    end
                end
            end
        end
        return best
    end

    local function findByStrategy(state, strategy, maxRange)
        local best = nil
        -- Buff strategies target specific buff stats
        local targetBuffStat = nil
        if strategy == "efficiency" then targetBuffStat = "efficiency"
        elseif strategy == "endurance" then targetBuffStat = "endurance"
        elseif strategy == "eggbuff" then targetBuffStat = "eggProduction"
        end

        for _, s in ipairs(state.sources) do
            if s.discovered and s.remaining > 0 then
                if not maxRange or s.distance <= maxRange then
                    if not best then
                        best = s
                    elseif strategy == "closest" then
                        if s.distance < best.distance then best = s end
                    elseif strategy == "largest" then
                        if s.remaining > best.remaining then best = s end
                    elseif strategy == "best" then
                        if s.energyPerGather > best.energyPerGather then best = s end
                    elseif targetBuffStat then
                        -- Pick source with highest buff power for target stat
                        local sBuff = (s.buffStat == targetBuffStat or s.buffStat == "all") and s.buffPower or 0
                        local bestBuff = (best.buffStat == targetBuffStat or best.buffStat == "all") and best.buffPower or 0
                        if sBuff > bestBuff then best = s end
                    end
                end
            end
        end
        return best
    end

    local function countDiscovered(state)
        local count = 0
        for _, s in ipairs(state.sources) do
            if s.discovered and s.remaining > 0 then
                count = count + 1
            end
        end
        return count
    end

    --------------------------------------------------------------------------
    -- STATUS BROADCAST
    --------------------------------------------------------------------------

    local function fireStatus(self)
        local state = getState(self)

        local discovered = {}
        local undiscoveredCount = 0

        for _, s in ipairs(state.sources) do
            if s.remaining > 0 then
                if s.discovered then
                    discovered[#discovered + 1] = {
                        id = s.id,
                        type = s.type,
                        energyPerGather = s.energyPerGather,
                        remaining = s.remaining,
                        distance = s.distance,
                    }
                else
                    undiscoveredCount = undiscoveredCount + 1
                end
            end
        end

        self.Out:Fire("foodSourceStatus", {
            discovered = discovered,
            undiscoveredCount = undiscoveredCount,
        })
    end

    return {
        name = "FoodSourceNode",
        domain = "server",

        Sys = {
            onInit = function(self)
                local state = getState(self)

                -- Generate initial sources
                for _ = 1, INITIAL_SOURCE_COUNT do
                    generateSource(state)
                end

                local System = self._System
                if System and System.Debug then
                    System.Debug.info("FoodSourceNode", string.format(
                        "Initialized — %d sources generated", #state.sources
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
            onTick = function(self, data)
                if not data or data.isPaused then return end

                local state = getState(self)

                -- Spawn new sources over time
                state.spawnCounter = state.spawnCounter + 1
                if state.spawnCounter >= SPAWN_INTERVAL then
                    state.spawnCounter = 0

                    -- Count active sources
                    local activeCount = 0
                    for _, s in ipairs(state.sources) do
                        if s.remaining > 0 then activeCount = activeCount + 1 end
                    end

                    if activeCount < MAX_SOURCES then
                        local source = generateSource(state)
                        local System = self._System
                        if System and System.Debug then
                            System.Debug.info("FoodSourceNode", string.format(
                                "New %s spawned at distance %d (%d remaining, %d active)",
                                source.type, source.distance, source.remaining, activeCount + 1
                            ))
                        end
                        fireStatus(self)
                    end
                end
            end,

            onExploreRequest = function(self, data)
                if not data or not data.antId then return end

                local state = getState(self)
                local maxRange = data.maxRange or 30
                local source = findNearestUndiscovered(state, maxRange)

                if not source then
                    self.Out:Fire("exploreFailed", { antId = data.antId })
                    return
                end

                -- Don't discover yet — just assign the trip
                self.Out:Fire("exploreAssigned", {
                    antId = data.antId,
                    distance = source.distance,
                    sourceId = source.id,
                })
            end,

            onExploreComplete = function(self, data)
                if not data or not data.sourceId then return end

                local state = getState(self)

                -- Find and discover the source
                for _, s in ipairs(state.sources) do
                    if s.id == data.sourceId and not s.discovered then
                        s.discovered = true

                        self.Out:Fire("sourceDiscovered", {
                            sourceId = s.id,
                            type = s.type,
                            energyPerGather = s.energyPerGather,
                            remaining = s.remaining,
                            distance = s.distance,
                        })

                        local System = self._System
                        if System and System.Debug then
                            System.Debug.info("FoodSourceNode", string.format(
                                "Discovered %s #%d at distance %d (%d gathers, %d energy each)",
                                s.type, s.id, s.distance, s.remaining, s.energyPerGather
                            ))
                        end

                        fireStatus(self)
                        break
                    end
                end
            end,

            onGatherRequest = function(self, data)
                if not data or not data.antId or not data.strategy then return end

                local state = getState(self)
                local maxRange = data.maxRange or 30
                local source = findByStrategy(state, data.strategy, maxRange)

                if not source then
                    self.Out:Fire("gatherFailed", { antId = data.antId })
                    return
                end

                self.Out:Fire("gatherAssigned", {
                    antId = data.antId,
                    sourceId = source.id,
                    distance = source.distance,
                    energyPerGather = source.energyPerGather,
                })
            end,

            onGatherComplete = function(self, data)
                if not data or not data.sourceId then return end

                local state = getState(self)

                for _, s in ipairs(state.sources) do
                    if s.id == data.sourceId then
                        if s.remaining <= 0 then return end

                        s.remaining = s.remaining - 1
                        local energy = s.energyPerGather

                        -- Deposit into pantry
                        self.Out:Fire("foodGathered", { energy = energy, foodType = s.type })

                        local System = self._System
                        if System and System.Debug then
                            System.Debug.info("FoodSourceNode", string.format(
                                "Gathered from %s #%d — %d energy, %d remaining",
                                s.type, s.id, energy, s.remaining
                            ))
                        end

                        if s.remaining <= 0 then
                            self.Out:Fire("sourceExhausted", { sourceId = s.id })

                            if System and System.Debug then
                                System.Debug.info("FoodSourceNode", string.format(
                                    "%s #%d exhausted", s.type, s.id
                                ))
                            end
                        end

                        fireStatus(self)
                        break
                    end
                end
            end,

            onDifficultyChanged = function(self, data)
                if not data or not data.multiplier then return end

                local state = getState(self)
                local before = state.difficultyMultiplier
                state.difficultyMultiplier = data.multiplier

                local System = self._System
                if System and System.Debug then
                    System.Debug.info("FoodSourceNode", string.format(
                        "Difficulty updated — %.2f → %.2f (hatch #%d)",
                        before, data.multiplier, data.hatchCount or 0
                    ))
                end
            end,
        },

        Out = {
            exploreAssigned = {},
            exploreFailed = {},
            sourceDiscovered = {},
            gatherAssigned = {},
            gatherFailed = {},
            foodGathered = {},
            foodSourceStatus = {},
            sourceExhausted = {},
        },
    }
end)

return FoodSourceNode
