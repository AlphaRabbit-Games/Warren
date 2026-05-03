--[[
    Ant Colony Simulation — WorkerNode
    Server-side worker ant colony manager.

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    Manages all worker ants in the colony. Workers are spawned when eggs hatch
    (or at game start for the initial worker). Each worker can be assigned a
    task (gather, dig, upgrade) targeting a specific chamber instance.

    Idle workers eat from the pantry on a bite cycle. If they can't eat for
    too long, they starve and die.

    ============================================================================
    SIGNALS
    ============================================================================

    IN (receives):
        onTick(data)
            - Clock pulse. Advances tasks, cooldowns, idle eating, starvation.

        onEggHatched({ hatched, eggs, capacity })
            - New worker spawns.

        onSpawnWorker({})
            - Spawn a worker directly (used for starting ant).

        onAssignTask({ workerId, task, targetId })
            - Validated command from CommandManager.

        onIdleWorkers({ task, targetId })
            - CommandManager says this task/target is no longer valid.

        onWorkerFoodDispensed({ energy })
            - Food received from pantry for idle workers.

    OUT (sends):
        workerStatus({ workers })
            - Full colony state, fired every tick.

        workerBite({})
            - Idle workers request food from pantry.

        foodGathered({ energy })
            - Worker completed a gather task.

        clutchUpgrade({ amount })
            - Worker completed an upgrade task.

        pantryUpgrade({ amount })
            - Worker completed a pantry upgrade task.

        tunnelDug({})
            - Worker completed a dig task. Stub for now.

        workerDied({ name, id, colonySize })
            - A worker starved to death.

--]]

local Warren = require(game:GetService("ReplicatedStorage").Warren)
local Node = Warren.Node

--------------------------------------------------------------------------------
-- TASK DEFINITIONS
--------------------------------------------------------------------------------

local TASK_DEFS = {
    gather = {
        duration = 20,
        cooldown = 5,
    },
    dig = {
        duration = 30,
        cooldown = 5,
    },
    upgrade = {
        duration = 25,
        cooldown = 5,
    },
    upgradePantry = {
        duration = 25,
        cooldown = 5,
    },
}

local DEFAULT_FOOD_PER_GATHER = 30
local WORKER_BITE_RATE = 5           -- ticks between bites when idle
local WORKER_STARVATION_THRESHOLD = 40  -- ticks without food before death

--------------------------------------------------------------------------------
-- WORKER NODE
--------------------------------------------------------------------------------

local WorkerNode = Node.extend(function(parent)
    local instanceStates = {}

    local function getState(self)
        if not instanceStates[self.id] then
            instanceStates[self.id] = {
                workers = {},
                nextId = 1,
                -- Shared idle eating state
                idleBiteCounter = 0,
                pendingFeedCount = 0,  -- how many idle workers requested food
            }
        end
        return instanceStates[self.id]
    end

    local function cleanupState(self)
        instanceStates[self.id] = nil
    end

    local function createWorker(state)
        local id = state.nextId
        state.nextId = id + 1

        local worker = {
            id = id,
            name = "Ant #" .. id,
            task = nil,
            targetId = nil,
            status = "idle",
            taskProgress = 0,
            taskDuration = 0,
            cooldownProgress = 0,
            cooldownDuration = 0,
            foodPerGather = DEFAULT_FOOD_PER_GATHER,
            tasksCompleted = 0,
            starvationTicks = 0,
            alive = true,
        }

        state.workers[#state.workers + 1] = worker
        return worker
    end

    local function findWorker(state, workerId)
        for _, w in ipairs(state.workers) do
            if w.id == workerId then
                return w
            end
        end
        return nil
    end

    local function assignTask(worker, taskName, targetId)
        local def = TASK_DEFS[taskName]
        if not def then return end

        worker.task = taskName
        worker.targetId = targetId
        worker.status = "working"
        worker.taskProgress = 0
        worker.taskDuration = def.duration
        worker.cooldownProgress = 0
        worker.cooldownDuration = def.cooldown
    end

    local function idleWorker(worker)
        worker.task = nil
        worker.targetId = nil
        worker.status = "idle"
        worker.taskProgress = 0
        worker.taskDuration = 0
        worker.cooldownProgress = 0
        worker.cooldownDuration = 0
    end

    local function startCooldown(worker)
        worker.status = "cooldown"
        worker.cooldownProgress = 0
    end

    local function fireStatus(self)
        local state = getState(self)

        local workerList = {}
        for _, w in ipairs(state.workers) do
            if w.alive then
                workerList[#workerList + 1] = {
                    id = w.id,
                    name = w.name,
                    task = w.task,
                    targetId = w.targetId,
                    status = w.status,
                    taskProgress = w.taskProgress,
                    taskDuration = w.taskDuration,
                    cooldownProgress = w.cooldownProgress,
                    cooldownDuration = w.cooldownDuration,
                    tasksCompleted = w.tasksCompleted,
                    starvationTicks = w.starvationTicks,
                    starvationThreshold = WORKER_STARVATION_THRESHOLD,
                }
            end
        end

        self.Out:Fire("workerStatus", {
            workers = workerList,
        })
    end

    local function countIdleWorkers(state)
        local count = 0
        for _, w in ipairs(state.workers) do
            if w.alive and w.status == "idle" then
                count = count + 1
            end
        end
        return count
    end

    return {
        name = "WorkerNode",
        domain = "server",

        Sys = {
            onInit = function(self)
                local System = self._System
                if System and System.Debug then
                    System.Debug.info("WorkerNode", "Initialized — colony empty")
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
                if #state.workers == 0 then return end

                -- Process task/cooldown for each worker
                for _, worker in ipairs(state.workers) do
                    if not worker.alive then continue end

                    if worker.status == "working" then
                        worker.taskProgress = worker.taskProgress + 1

                        if worker.taskProgress >= worker.taskDuration then
                            worker.tasksCompleted = worker.tasksCompleted + 1

                            local System = self._System
                            if System and System.Debug then
                                System.Debug.info("WorkerNode", string.format(
                                    "%s completed %s on %s (#%d)",
                                    worker.name, worker.task,
                                    worker.targetId or "?", worker.tasksCompleted
                                ))
                            end

                            if worker.task == "gather" then
                                self.Out:Fire("foodGathered", {
                                    energy = worker.foodPerGather,
                                })
                            elseif worker.task == "upgrade" then
                                self.Out:Fire("clutchUpgrade", {
                                    amount = 1,
                                })
                            elseif worker.task == "upgradePantry" then
                                self.Out:Fire("pantryUpgrade", {
                                    amount = 50,
                                })
                            elseif worker.task == "dig" then
                                self.Out:Fire("tunnelDug", {})
                            end

                            startCooldown(worker)
                        end

                    elseif worker.status == "cooldown" then
                        worker.cooldownProgress = worker.cooldownProgress + 1

                        if worker.cooldownProgress >= worker.cooldownDuration then
                            if worker.task then
                                assignTask(worker, worker.task, worker.targetId)
                            else
                                worker.status = "idle"
                            end
                        end
                    end
                end

                -- Idle worker eating cycle
                local idleCount = countIdleWorkers(state)
                if idleCount > 0 then
                    state.idleBiteCounter = state.idleBiteCounter + 1
                    if state.idleBiteCounter >= WORKER_BITE_RATE then
                        state.idleBiteCounter = 0
                        state.pendingFeedCount = idleCount
                        -- Fire one bite per idle worker
                        for _ = 1, idleCount do
                            self.Out:Fire("workerBite", {})
                        end
                    end
                end

                -- Starvation: idle workers with no food starve
                -- Starvation ticks up every tick for idle workers,
                -- resets when they receive food via onWorkerFoodDispensed
                local deadWorkers = {}
                for i, worker in ipairs(state.workers) do
                    if worker.alive and worker.status == "idle" then
                        worker.starvationTicks = worker.starvationTicks + 1

                        if worker.starvationTicks >= WORKER_STARVATION_THRESHOLD then
                            worker.alive = false
                            deadWorkers[#deadWorkers + 1] = i

                            self.Out:Fire("workerDied", {
                                name = worker.name,
                                id = worker.id,
                            })

                            local System = self._System
                            if System and System.Debug then
                                System.Debug.warn("WorkerNode", string.format(
                                    "%s starved to death", worker.name
                                ))
                            end
                        end
                    elseif worker.alive and worker.status == "working" then
                        -- Working workers don't starve (they're out foraging etc)
                        -- but reset doesn't happen either — they'll starve when idle
                        -- if pantry is empty. Keep starvation ticking slowly.
                        worker.starvationTicks = worker.starvationTicks + 1

                        if worker.starvationTicks >= WORKER_STARVATION_THRESHOLD then
                            worker.alive = false
                            deadWorkers[#deadWorkers + 1] = i

                            self.Out:Fire("workerDied", {
                                name = worker.name,
                                id = worker.id,
                            })

                            local System = self._System
                            if System and System.Debug then
                                System.Debug.warn("WorkerNode", string.format(
                                    "%s starved to death while working", worker.name
                                ))
                            end
                        end
                    end
                end

                -- Remove dead workers (reverse order)
                for j = #deadWorkers, 1, -1 do
                    table.remove(state.workers, deadWorkers[j])
                end

                fireStatus(self)
            end,

            onEggHatched = function(self, data)
                local state = getState(self)
                local worker = createWorker(state)

                local System = self._System
                if System and System.Debug then
                    System.Debug.info("WorkerNode", string.format(
                        "%s hatched — colony size: %d",
                        worker.name, #state.workers
                    ))
                end

                fireStatus(self)
            end,

            onSpawnWorker = function(self, data)
                local state = getState(self)
                local worker = createWorker(state)

                local System = self._System
                if System and System.Debug then
                    System.Debug.info("WorkerNode", string.format(
                        "%s spawned — colony size: %d",
                        worker.name, #state.workers
                    ))
                end

                fireStatus(self)
            end,

            onAssignTask = function(self, data)
                if not data or not data.workerId or not data.task then return end

                local state = getState(self)
                local worker = findWorker(state, data.workerId)
                if not worker or not worker.alive then return end

                if data.task == "idle" then
                    idleWorker(worker)
                    local System = self._System
                    if System and System.Debug then
                        System.Debug.info("WorkerNode", worker.name .. " set to idle")
                    end
                    fireStatus(self)
                    return
                end

                assignTask(worker, data.task, data.targetId)

                local System = self._System
                if System and System.Debug then
                    System.Debug.info("WorkerNode", string.format(
                        "%s assigned to %s on %s (%d ticks)",
                        worker.name, data.task,
                        data.targetId or "?", worker.taskDuration
                    ))
                end

                fireStatus(self)
            end,

            onIdleWorkers = function(self, data)
                if not data or not data.task then return end

                local state = getState(self)
                local count = 0

                for _, worker in ipairs(state.workers) do
                    if worker.alive
                        and worker.task == data.task
                        and (not data.targetId or worker.targetId == data.targetId)
                        and worker.status ~= "idle"
                    then
                        idleWorker(worker)
                        count = count + 1
                    end
                end

                if count > 0 then
                    local System = self._System
                    if System and System.Debug then
                        System.Debug.info("WorkerNode", string.format(
                            "Idled %d workers from %s on %s",
                            count, data.task, data.targetId or "all"
                        ))
                    end
                    fireStatus(self)
                end
            end,

            onWorkerFoodDispensed = function(self, data)
                if not data then return end

                local state = getState(self)
                if data.energy and data.energy > 0 then
                    -- Feed idle workers — reset their starvation
                    for _, worker in ipairs(state.workers) do
                        if worker.alive and worker.status == "idle" then
                            worker.starvationTicks = 0
                        end
                    end
                end
            end,
        },

        Out = {
            workerStatus = {},
            workerBite = {},
            foodGathered = {},
            clutchUpgrade = {},
            pantryUpgrade = {},
            tunnelDug = {},
            workerDied = {},
        },
    }
end)

return WorkerNode
