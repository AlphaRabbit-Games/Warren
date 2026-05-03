--[[
    Ant Colony Simulation — ColonyNode
    Server-side unified ant colony manager.

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    Manages all ants in the colony — queen and workers alike. Every ant shares
    the same base model: energy, metabolism, bite cycle, starvation. Class
    determines available commands.

    Energy drains each tick (metabolism). Idle ants eat from the pantry on a
    bite cycle to replenish. When energy hits 0, starvation counter starts.
    At threshold the ant dies. Queen death = game over.

    All timing is driven by GameClock tick pulses — no background threads.

    ============================================================================
    ANT CLASSES
    ============================================================================

    queen:
        - Commands: "layEggs" (eats + gestates), idle (eats only)
        - Death = game over

    worker:
        - Commands: "gather", "dig", "upgrade", "upgradePantry", idle
        - Death = removed from colony

    ============================================================================
    SIGNALS
    ============================================================================

    IN (receives):
        onTick(data)
            - Clock pulse. Drives metabolism, eating, tasks, starvation.

        onEggHatched({ ... })
            - Spawn a new worker ant.

        onSpawnWorker({})
            - Spawn a worker directly (starting ant).

        onAssignTask({ antId, task, targetId })
            - Validated command from CommandManager.

        onIdleWorkers({ task, targetId })
            - CommandManager says this task/target is no longer valid.

        onFoodDispensed({ energy })
            - Food received from pantry for colony eating.

    OUT (sends):
        colonyStatus({ ants })
            - Full colony state, fired every tick.

        colonyBite({ count })
            - Colony requests food from pantry. count = hungry ants.

        eggLaid({ eggCount })
            - Queen laid an egg.

        foodGathered({ energy })
            - Worker completed a gather task.

        clutchUpgrade({ amount })
            - Worker completed a clutch upgrade.

        pantryUpgrade({ amount })
            - Worker completed a pantry upgrade.

        tunnelDug({})
            - Worker completed a dig task.

        queenDied({ eggCount })
            - Queen starved. Game over.

        antDied({ name, id, class })
            - An ant died.

--]]

local Warren = require(game:GetService("ReplicatedStorage").Warren)
local Node = Warren.Node

--------------------------------------------------------------------------------
-- CONSTANTS
--------------------------------------------------------------------------------

local CLASS_DATA = {
    queen = {
        energyCap = 100,
        metabolismRate = 1,      -- energy drained per tick
        biteRate = 3,            -- ticks between bites when idle/eating
        starvationThreshold = 10,
        -- Egg laying
        eggEnergyCost = 50,
        eggInterval = 10,        -- ticks of gestation per egg
    },
    worker = {
        energyCap = 60,
        metabolismRate = 1,
        biteRate = 5,
        starvationThreshold = 10,
        maxRange = 30,
    },
}

local TASK_DEFS = {
    layEggs       = { duration = 0, cooldown = 10 },  -- continuous, cooldown between eggs
    explore       = { duration = 0, cooldown = 5 },   -- duration set by FoodSourceNode
    gatherClosest = { duration = 0, cooldown = 5 },   -- duration set by FoodSourceNode
    gatherLargest = { duration = 0, cooldown = 5 },
    gatherBest    = { duration = 0, cooldown = 5 },
    dig           = { duration = 30, cooldown = 5 },
    upgrade       = { duration = 25, cooldown = 5 },
    upgradePantry = { duration = 25, cooldown = 5 },
}

local DEFAULT_COOLDOWN = 5

--------------------------------------------------------------------------------
-- COLONY NODE
--------------------------------------------------------------------------------

local ColonyNode = Node.extend(function(parent)
    local instanceStates = {}

    local function getState(self)
        if not instanceStates[self.id] then
            instanceStates[self.id] = {
                ants = {},
                nextId = 1,
                eggCount = 0,
                -- Hatchling template (updated by GameManager)
                hatchlingStats = {
                    maxRange = CLASS_DATA.worker.maxRange,
                    energyCap = CLASS_DATA.worker.energyCap,
                    metabolismRate = CLASS_DATA.worker.metabolismRate,
                },
            }
        end
        return instanceStates[self.id]
    end

    local function cleanupState(self)
        instanceStates[self.id] = nil
    end

    --------------------------------------------------------------------------
    -- ANT CREATION
    --------------------------------------------------------------------------

    local function createAnt(state, class)
        local id = state.nextId
        state.nextId = id + 1
        local data = CLASS_DATA[class]

        -- Workers inherit hatchling template stats
        local energyCap = class == "worker" and state.hatchlingStats.energyCap or data.energyCap
        local metabolismRate = class == "worker" and state.hatchlingStats.metabolismRate or data.metabolismRate
        local maxRange = class == "worker" and state.hatchlingStats.maxRange or (data.maxRange or 30)

        local ant = {
            id = id,
            name = class == "queen" and "Queen" or ("Ant #" .. id),
            class = class,
            alive = true,

            -- Energy
            energy = energyCap,  -- start full
            energyCap = energyCap,
            metabolismRate = metabolismRate,

            -- Eating
            biteRate = data.biteRate,
            biteCounter = 0,

            -- Starvation
            starvationTicks = 0,
            starvationThreshold = data.starvationThreshold,

            -- Task
            task = nil,
            targetId = nil,
            status = "idle",    -- "idle"|"working"|"cooldown"
            taskProgress = 0,
            taskDuration = 0,
            cooldownProgress = 0,
            cooldownDuration = 0,
            tasksCompleted = 0,

            -- Class-specific
            maxRange = maxRange,
            eggEnergyCost = data.eggEnergyCost or 0,
            eggInterval = data.eggInterval or 0,
            eggCounter = 0,

            -- Explore/gather state (set by FoodSourceNode)
            pendingSourceId = nil,
            gatherStrategy = nil,
        }

        state.ants[#state.ants + 1] = ant
        return ant
    end

    local function findAnt(state, antId)
        for _, a in ipairs(state.ants) do
            if a.id == antId then return a end
        end
        return nil
    end

    --------------------------------------------------------------------------
    -- TASK MANAGEMENT
    --------------------------------------------------------------------------

    -- Starts a task immediately (for tasks with known duration)
    local function assignTask(ant, taskName, targetId)
        if taskName == "layEggs" then
            ant.task = "layEggs"
            ant.targetId = targetId
            ant.status = "working"
            ant.taskProgress = 0
            ant.taskDuration = 0
            ant.cooldownProgress = 0
            ant.cooldownDuration = 0
            ant.eggCounter = 0
            return
        end

        local def = TASK_DEFS[taskName]
        if not def then return end

        ant.task = taskName
        ant.targetId = targetId
        ant.status = "working"
        ant.taskProgress = 0
        ant.taskDuration = def.duration
        ant.cooldownProgress = 0
        ant.cooldownDuration = def.cooldown
    end

    -- Puts ant in pending state while waiting for FoodSourceNode response
    local function assignPendingTask(ant, taskName)
        ant.task = taskName
        ant.status = "pending"
        ant.taskProgress = 0
        ant.taskDuration = 0
        ant.pendingSourceId = nil
        if taskName == "gatherClosest" or taskName == "gatherLargest" or taskName == "gatherBest" then
            ant.gatherStrategy = taskName:sub(7):lower()  -- "closest"|"largest"|"best"
        end
    end

    -- Called when FoodSourceNode responds with distance — starts the actual trip
    local function startTrip(ant, distance, sourceId)
        ant.status = "working"
        ant.taskProgress = 0
        ant.taskDuration = distance * 2  -- round trip
        ant.pendingSourceId = sourceId
    end

    local function idleAnt(ant)
        ant.task = nil
        ant.targetId = nil
        ant.status = "idle"
        ant.taskProgress = 0
        ant.taskDuration = 0
        ant.pendingSourceId = nil
        ant.gatherStrategy = nil
        ant.cooldownProgress = 0
        ant.cooldownDuration = 0
        ant.eggCounter = 0
    end

    local function startCooldown(ant)
        ant.status = "cooldown"
        ant.cooldownProgress = 0
        local def = TASK_DEFS[ant.task]
        ant.cooldownDuration = (def and def.cooldown) or DEFAULT_COOLDOWN
    end

    --------------------------------------------------------------------------
    -- STATUS BROADCAST
    --------------------------------------------------------------------------

    local function fireStatus(self)
        local state = getState(self)

        local antList = {}
        for _, a in ipairs(state.ants) do
            if a.alive then
                antList[#antList + 1] = {
                    id = a.id,
                    name = a.name,
                    class = a.class,
                    energy = a.energy,
                    energyCap = a.energyCap,
                    starvationTicks = a.starvationTicks,
                    starvationThreshold = a.starvationThreshold,
                    task = a.task,
                    targetId = a.targetId,
                    status = a.status,
                    taskProgress = a.taskProgress,
                    taskDuration = a.taskDuration,
                    cooldownProgress = a.cooldownProgress,
                    cooldownDuration = a.cooldownDuration,
                    tasksCompleted = a.tasksCompleted,
                    -- Queen-specific
                    eggCounter = a.eggCounter,
                    eggInterval = a.eggInterval,
                    eggEnergyCost = a.eggEnergyCost,
                    eggCount = state.eggCount,
                }
            end
        end

        self.Out:Fire("colonyStatus", { ants = antList })
    end

    return {
        name = "ColonyNode",
        domain = "server",

        Sys = {
            onInit = function(self)
                local System = self._System
                if System and System.Debug then
                    System.Debug.info("ColonyNode", "Initialized")
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
                if #state.ants == 0 then return end

                -- Count hungry ants (idle or laying eggs) for bite request
                local hungryCount = 0
                local deadIndices = {}

                for i, ant in ipairs(state.ants) do
                    if not ant.alive then continue end

                    --------------------------------------------------------
                    -- COOLDOWN: timer-based, eat during rest, resume when done
                    --------------------------------------------------------
                    if ant.status == "cooldown" then
                        ant.cooldownProgress = ant.cooldownProgress + 1
                        if ant.cooldownProgress >= ant.cooldownDuration then
                            if not ant.task then
                                ant.status = "idle"
                            elseif ant.task == "explore" then
                                assignPendingTask(ant, "explore")
                                self.Out:Fire("exploreRequest", {
                                    antId = ant.id,
                                    maxRange = ant.maxRange,
                                })
                            elseif ant.task == "gatherClosest" or ant.task == "gatherLargest" or ant.task == "gatherBest" then
                                local strategy = ant.task:sub(7):lower()
                                assignPendingTask(ant, ant.task)
                                self.Out:Fire("gatherRequest", {
                                    antId = ant.id,
                                    strategy = strategy,
                                    maxRange = ant.maxRange,
                                })
                            else
                                assignTask(ant, ant.task, ant.targetId)
                            end
                        end
                    end

                    --------------------------------------------------------
                    -- METABOLISM: energy drains every tick except during cooldown
                    --------------------------------------------------------
                    ant.energy = math.max(0, ant.energy - ant.metabolismRate)

                    --------------------------------------------------------
                    -- STARVATION
                    --------------------------------------------------------
                    if ant.energy <= 0 then
                        ant.starvationTicks = ant.starvationTicks + 1

                        if ant.starvationTicks >= ant.starvationThreshold then
                            ant.alive = false
                            deadIndices[#deadIndices + 1] = i

                            self.Out:Fire("antDied", {
                                name = ant.name,
                                id = ant.id,
                                class = ant.class,
                            })

                            if ant.class == "queen" then
                                self.Out:Fire("queenDied", {
                                    eggCount = state.eggCount,
                                })
                            end

                            local System = self._System
                            if System and System.Debug then
                                System.Debug.warn("ColonyNode", string.format(
                                    "%s starved to death", ant.name
                                ))
                            end
                        end
                    else
                        ant.starvationTicks = 0
                    end

                    if not ant.alive then continue end

                    --------------------------------------------------------
                    -- EATING: idle, cooldown, and laying ants eat
                    --------------------------------------------------------
                    if ant.status == "cooldown" or ant.task == "layEggs" then
                        ant.biteCounter = ant.biteCounter + 1
                        if ant.biteCounter >= ant.biteRate then
                            ant.biteCounter = 0
                            if ant.energy < ant.energyCap then
                                hungryCount = hungryCount + 1
                                local System = self._System
                                if System and System.Debug then
                                    System.Debug.info("ColonyNode", string.format(
                                        "%s hungry — status:%s energy:%d/%d",
                                        ant.name, ant.status, ant.energy, ant.energyCap
                                    ))
                                end
                            end
                        end
                    end

                    --------------------------------------------------------
                    -- TASK EXECUTION
                    --------------------------------------------------------
                    if ant.status == "working" and ant.task then
                        local completed = false

                        if ant.task == "layEggs" then
                            -- Queen egg laying: energy-gated gestation
                            if ant.energy >= ant.eggEnergyCost then
                                ant.eggCounter = ant.eggCounter + 1
                                if ant.eggCounter >= ant.eggInterval then
                                    ant.eggCounter = 0
                                    ant.energy = ant.energy - ant.eggEnergyCost
                                    state.eggCount = state.eggCount + 1
                                    completed = true

                                    self.Out:Fire("eggLaid", {
                                        eggCount = state.eggCount,
                                    })
                                end
                            end
                        elseif ant.task == "explore" then
                            -- Travel-based: duration set by FoodSourceNode
                            ant.taskProgress = ant.taskProgress + 1
                            if ant.taskProgress >= ant.taskDuration then
                                completed = true
                                self.Out:Fire("exploreComplete", {
                                    antId = ant.id,
                                    sourceId = ant.pendingSourceId,
                                })
                                self.Out:Fire("tripComplete", { antId = ant.id })
                            end
                        elseif ant.task == "gatherClosest" or ant.task == "gatherLargest" or ant.task == "gatherBest" then
                            -- Travel-based: duration set by FoodSourceNode
                            ant.taskProgress = ant.taskProgress + 1
                            if ant.taskProgress >= ant.taskDuration then
                                completed = true
                                self.Out:Fire("gatherComplete", {
                                    antId = ant.id,
                                    sourceId = ant.pendingSourceId,
                                })
                                self.Out:Fire("tripComplete", { antId = ant.id })
                            end
                        else
                            -- Duration-based tasks (dig, upgrade, etc)
                            ant.taskProgress = ant.taskProgress + 1
                            if ant.taskProgress >= ant.taskDuration then
                                completed = true

                                if ant.task == "upgrade" then
                                    self.Out:Fire("clutchUpgrade", { amount = 1 })
                                elseif ant.task == "upgradePantry" then
                                    self.Out:Fire("pantryUpgrade", { amount = 50 })
                                elseif ant.task == "dig" then
                                    self.Out:Fire("tunnelDug", {})
                                end
                            end
                        end

                        if completed then
                            ant.tasksCompleted = ant.tasksCompleted + 1
                            startCooldown(ant)

                            local System = self._System
                            if System and System.Debug then
                                System.Debug.info("ColonyNode", string.format(
                                    "%s completed %s (#%d) — resting",
                                    ant.name, ant.task or "?", ant.tasksCompleted
                                ))
                            end
                        end

                    end
                end

                -- Request food for hungry ants
                if hungryCount > 0 then
                    local System = self._System
                    if System and System.Debug then
                        System.Debug.info("ColonyNode", string.format(
                            "Requesting food for %d hungry ants", hungryCount
                        ))
                    end
                    self.Out:Fire("colonyBite", { count = hungryCount, colonySize = #state.ants })
                end

                -- Remove dead ants (reverse order)
                for j = #deadIndices, 1, -1 do
                    table.remove(state.ants, deadIndices[j])
                end

                fireStatus(self)
            end,

            onEggHatched = function(self, data)
                local state = getState(self)
                local ant = createAnt(state, "worker")

                local System = self._System
                if System and System.Debug then
                    System.Debug.info("ColonyNode", string.format(
                        "%s hatched — colony size: %d",
                        ant.name, #state.ants
                    ))
                end

                fireStatus(self)
            end,

            onSpawnWorker = function(self, data)
                local state = getState(self)
                local ant = createAnt(state, "worker")

                local System = self._System
                if System and System.Debug then
                    System.Debug.info("ColonyNode", string.format(
                        "%s spawned — colony size: %d",
                        ant.name, #state.ants
                    ))
                end

                fireStatus(self)
            end,

            onSpawnQueen = function(self, data)
                local state = getState(self)
                local ant = createAnt(state, "queen")

                local System = self._System
                if System and System.Debug then
                    System.Debug.info("ColonyNode", string.format(
                        "Queen spawned — colony size: %d", #state.ants
                    ))
                end

                fireStatus(self)
            end,

            onAssignTask = function(self, data)
                if not data or not data.antId or not data.task then return end

                local state = getState(self)
                local ant = findAnt(state, data.antId)
                if not ant or not ant.alive then return end

                if data.task == "idle" then
                    idleAnt(ant)
                    local System = self._System
                    if System and System.Debug then
                        System.Debug.info("ColonyNode", ant.name .. " set to idle")
                    end
                    fireStatus(self)
                    return
                end

                -- Explore/gather: request from FoodSourceNode (async)
                if data.task == "explore" then
                    assignPendingTask(ant, "explore")
                    self.Out:Fire("exploreRequest", {
                        antId = ant.id,
                        maxRange = ant.maxRange,
                    })
                    fireStatus(self)
                    return
                end

                if data.task == "gatherClosest" or data.task == "gatherLargest" or data.task == "gatherBest" then
                    local strategy = data.task:sub(7):lower()
                    assignPendingTask(ant, data.task)
                    self.Out:Fire("gatherRequest", {
                        antId = ant.id,
                        strategy = strategy,
                        maxRange = ant.maxRange,
                    })
                    fireStatus(self)
                    return
                end

                -- All other tasks start immediately
                assignTask(ant, data.task, data.targetId)

                local System = self._System
                if System and System.Debug then
                    System.Debug.info("ColonyNode", string.format(
                        "%s assigned to %s on %s",
                        ant.name, data.task, data.targetId or "?"
                    ))
                end

                fireStatus(self)
            end,

            onIdleWorkers = function(self, data)
                if not data or not data.task then return end

                local state = getState(self)
                local count = 0

                for _, ant in ipairs(state.ants) do
                    if ant.alive
                        and ant.task == data.task
                        and (not data.targetId or ant.targetId == data.targetId)
                        and ant.status ~= "idle"
                    then
                        idleAnt(ant)
                        count = count + 1
                    end
                end

                if count > 0 then
                    local System = self._System
                    if System and System.Debug then
                        System.Debug.info("ColonyNode", string.format(
                            "Idled %d ants from %s on %s",
                            count, data.task, data.targetId or "all"
                        ))
                    end
                    fireStatus(self)
                end
            end,

            -- FoodSourceNode responses
            onExploreAssigned = function(self, data)
                if not data or not data.antId then return end
                local state = getState(self)
                local ant = findAnt(state, data.antId)
                if not ant or not ant.alive then return end

                startTrip(ant, data.distance, data.sourceId)

                local System = self._System
                if System and System.Debug then
                    System.Debug.info("ColonyNode", string.format(
                        "%s exploring — distance %d, %d ticks round trip",
                        ant.name, data.distance, data.distance * 2
                    ))
                end
                fireStatus(self)
            end,

            onExploreFailed = function(self, data)
                if not data or not data.antId then return end
                local state = getState(self)
                local ant = findAnt(state, data.antId)
                if not ant or not ant.alive then return end

                idleAnt(ant)
                local System = self._System
                if System and System.Debug then
                    System.Debug.info("ColonyNode", string.format(
                        "%s explore failed — nothing in range, idled", ant.name
                    ))
                end
                fireStatus(self)
            end,

            onGatherAssigned = function(self, data)
                if not data or not data.antId then return end
                local state = getState(self)
                local ant = findAnt(state, data.antId)
                if not ant or not ant.alive then return end

                startTrip(ant, data.distance, data.sourceId)

                local System = self._System
                if System and System.Debug then
                    System.Debug.info("ColonyNode", string.format(
                        "%s gathering from source #%d — distance %d, %d ticks",
                        ant.name, data.sourceId, data.distance, data.distance * 2
                    ))
                end
                fireStatus(self)
            end,

            onGatherFailed = function(self, data)
                if not data or not data.antId then return end
                local state = getState(self)
                local ant = findAnt(state, data.antId)
                if not ant or not ant.alive then return end

                idleAnt(ant)
                local System = self._System
                if System and System.Debug then
                    System.Debug.info("ColonyNode", string.format(
                        "%s gather failed — no sources available, idled", ant.name
                    ))
                end
                fireStatus(self)
            end,

            onQueenStatsChanged = function(self, data)
                if not data then return end

                local state = getState(self)

                -- Update hatchling template
                if data.hatchlingStats then
                    state.hatchlingStats.maxRange = data.hatchlingStats.maxRange or state.hatchlingStats.maxRange
                    state.hatchlingStats.energyCap = data.hatchlingStats.energyCap or state.hatchlingStats.energyCap
                    state.hatchlingStats.metabolismRate = data.hatchlingStats.metabolismRate or state.hatchlingStats.metabolismRate
                end

                -- Update queen's egg stats
                if data.queenStats then
                    for _, ant in ipairs(state.ants) do
                        if ant.alive and ant.class == "queen" then
                            ant.eggInterval = data.queenStats.eggInterval or ant.eggInterval
                            ant.eggEnergyCost = data.queenStats.eggEnergyCost or ant.eggEnergyCost
                        end
                    end
                end

                local System = self._System
                if System and System.Debug then
                    System.Debug.info("ColonyNode", string.format(
                        "Queen stats updated — eggInterval:%d, eggCost:%d, hatchRange:%d, hatchCap:%d, hatchMeta:%.1f",
                        data.queenStats and data.queenStats.eggInterval or 0,
                        data.queenStats and data.queenStats.eggEnergyCost or 0,
                        state.hatchlingStats.maxRange,
                        state.hatchlingStats.energyCap,
                        state.hatchlingStats.metabolismRate
                    ))
                end
            end,

            onFoodDispensed = function(self, data)
                local System = self._System
                if System and System.Debug then
                    System.Debug.info("ColonyNode", string.format(
                        "Food received: %d energy", data and data.energy or 0
                    ))
                end

                if not data or not data.energy or data.energy <= 0 then return end

                local state = getState(self)

                -- Collect hungry ants
                local hungryAnts = {}
                for _, ant in ipairs(state.ants) do
                    if ant.alive and (ant.status == "cooldown" or ant.task == "layEggs") then
                        if ant.energy < ant.energyCap then
                            hungryAnts[#hungryAnts + 1] = ant
                        end
                    end
                end

                if #hungryAnts == 0 then return end

                -- Split evenly among hungry ants
                local perAnt = math.floor(data.energy / #hungryAnts)
                local leftover = data.energy - (perAnt * #hungryAnts)

                for i, ant in ipairs(hungryAnts) do
                    local share = perAnt
                    if i <= leftover then
                        share = share + 1  -- distribute remainder
                    end

                    local need = ant.energyCap - ant.energy
                    local amount = math.min(share, need)
                    ant.energy = ant.energy + amount

                    if System and System.Debug then
                        System.Debug.info("ColonyNode", string.format(
                            "Fed %s +%d → %d/%d",
                            ant.name, amount, ant.energy, ant.energyCap
                        ))
                    end
                end
            end,
        },

        Out = {
            colonyStatus = {},
            colonyBite = {},
            eggLaid = {},
            exploreRequest = {},
            exploreComplete = {},
            gatherRequest = {},
            gatherComplete = {},
            tripComplete = {},
            clutchUpgrade = {},
            pantryUpgrade = {},
            tunnelDug = {},
            queenDied = {},
            antDied = {},
        },
    }
end)

return ColonyNode
