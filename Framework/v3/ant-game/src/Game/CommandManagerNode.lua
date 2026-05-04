--[[
    Ant Colony Simulation — CommandManagerNode
    Server-side command validation and routing.

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    Central node that aggregates chamber statuses, tracks worker assignments,
    and builds the list of available commands. Validates commands before
    forwarding to WorkerNode. Idles workers when their task becomes invalid
    (e.g. clutch reaches max capacity).

    ============================================================================
    SIGNALS
    ============================================================================

    IN (receives):
        onClutchStatus({ eggs, capacity, maxCapacity, ... })
            - From EggClutchNode instances. Tracks upgrade availability.

        onWorkerStatus({ workers })
            - From WorkerNode. Tracks current assignments for slot counting.

        onAssignTask({ workerId, task, targetId })
            - From CommandMenuHUD via client. Validates and forwards.

    OUT (sends):
        availableCommands({ commands })
            - List of valid commands for the HUD to display.

        assignTask({ workerId, task, targetId })
            - Validated command forwarded to WorkerNode.

        idleWorkers({ task, targetId })
            - Tell WorkerNode to idle workers on an invalid task/target.

--]]

local Warren = require(game:GetService("ReplicatedStorage").Warren)
local ClassTree = require(script.Parent.ClassTree)
local Node = Warren.Node

--------------------------------------------------------------------------------
-- DEFAULTS
--------------------------------------------------------------------------------

local RECLASS_BASE_COST = 1
local RECLASS_COST_GROWTH = 1.25

local function getReclassCost(reclassCount)
    return math.ceil(RECLASS_BASE_COST * RECLASS_COST_GROWTH ^ reclassCount)
end

local TASK_CAPS = {
    explore = 999,
    gatherClosest = 999,
    gatherLargest = 999,
    gatherBest = 999,
    gatherEfficiency = 999,
    gatherEndurance = 999,
    gatherEggBuff = 999,
    dig = 999,
    layEggs = 999,
    upgrade = 2,
    upgradePantry = 2,
}

--------------------------------------------------------------------------------
-- COMMAND MANAGER NODE
--------------------------------------------------------------------------------

local CommandManagerNode = Node.extend(function(parent)
    local instanceStates = {}

    local function getState(self)
        if not instanceStates[self.id] then
            instanceStates[self.id] = {
                -- Chamber registry: targetId -> { type, status }
                chambers = {},
                -- Current ant list from ColonyNode
                ants = {},
                -- Currently selected ant info
                selectedAntClass = nil,
                selectedWorkerClass = nil,
                selectedClassLocked = false,
                selectedReclassCount = 0,
                -- Food source tracking
                hasDiscoveredSources = false,
                discoveredSourceCount = 0,
                undiscoveredSourceCount = 0,
            }
        end
        return instanceStates[self.id]
    end

    local function cleanupState(self)
        instanceStates[self.id] = nil
    end

    --------------------------------------------------------------------------
    -- ASSIGNMENT COUNTING
    --------------------------------------------------------------------------

    local function countAssignments(state, task, targetId)
        local count = 0
        for _, a in ipairs(state.ants) do
            if a.task == task and a.status ~= "idle" then
                if targetId == nil or a.targetId == targetId then
                    count = count + 1
                end
            end
        end
        return count
    end

    --------------------------------------------------------------------------
    -- COMMAND BUILDING
    --------------------------------------------------------------------------

    -- Check if a gather command is available (needs discovered sources)
    local function isGatherCommandAvailable(state, task)
        if task == "gatherClosest" or task == "gatherLargest" or task == "gatherBest"
            or task == "gatherEfficiency" or task == "gatherEndurance" or task == "gatherEggBuff" then
            return state.hasDiscoveredSources
        end
        return true
    end

    local function buildCommands(self)
        local state = getState(self)
        local commands = {}

        -- Queen commands
        if state.selectedAntClass == "queen" then
            commands[#commands + 1] = {
                task = "layEggs",
                targetId = nil,
                label = "Lay Eggs",
            }
            return commands
        end

        -- Worker commands — driven by class tree
        if state.selectedAntClass == "worker" and state.selectedClassId then
            local classDef = ClassTree.get(state.selectedClassId)

            if classDef then
                -- Primary action: the command for this class
                local cmd = classDef.command
                if cmd and isGatherCommandAvailable(state, cmd) then
                    local assigned = countAssignments(state, cmd, nil)
                    commands[#commands + 1] = {
                        task = cmd,
                        targetId = nil,
                        label = string.format("%s — %s (%d ants)",
                            classDef.name, cmd, assigned),
                    }
                end

                -- Rebirth options: show children of current class
                local rebirthOptions = ClassTree.getChildren(state.selectedClassId)
                for _, child in ipairs(rebirthOptions) do
                    -- Check if ant meets requirements
                    local reqParts = {}
                    for stat, val in pairs(child.statReqs) do
                        reqParts[#reqParts + 1] = string.format("%s≥%s", stat, tostring(val))
                    end
                    local reqStr = #reqParts > 0 and table.concat(reqParts, ", ") or "none"

                    -- Find the selected ant to check eligibility
                    local canDo = false
                    for _, a in ipairs(state.ants) do
                        if a.id == state.selectedAntId then
                            canDo = ClassTree.canRebirth(a, child.id)
                            break
                        end
                    end

                    commands[#commands + 1] = {
                        task = child.command,
                        rebirthTo = child.id,
                        targetId = nil,
                        label = string.format("↳ Rebirth: %s [%d XP]\n  %s (%s)",
                            child.name, child.rebirthCost,
                            child.description, reqStr),
                        isRebirth = true,
                        available = canDo,
                        rebirthCost = child.rebirthCost,
                    }
                end
            end

            -- Reclass options: show tier 1 classes that aren't the current base
            local baseClass = ClassTree.getBaseClass(state.selectedClassId)
            local tier1Classes = ClassTree.getTier1Classes()
            local reclassCost = getReclassCost(state.selectedReclassCount)

            for _, cls in ipairs(tier1Classes) do
                if not baseClass or cls.id ~= baseClass.id then
                    local costLabel = state.selectedClassLocked
                        and string.format("[Reclass: %d XP]", reclassCost)
                        or "[Free]"

                    commands[#commands + 1] = {
                        task = cls.command,
                        reclassTo = cls.id,
                        targetId = nil,
                        label = string.format("⟲ %s %s\n  %s",
                            cls.name, costLabel, cls.description),
                        isReclass = true,
                        reclassCost = state.selectedClassLocked and reclassCost or 0,
                    }
                end
            end
        end

        return commands
    end

    local function broadcastCommands(self)
        local commands = buildCommands(self)
        self.Out:Fire("availableCommands", { commands = commands })
    end

    --------------------------------------------------------------------------
    -- INVALIDATION
    --------------------------------------------------------------------------

    local function checkInvalidations(self)
        local state = getState(self)

        for targetId, chamber in pairs(state.chambers) do
            if chamber.type == "clutch" then
                if chamber.status.capacity >= chamber.status.maxCapacity then
                    self.Out:Fire("idleWorkers", {
                        task = "upgrade",
                        targetId = targetId,
                    })
                end
            elseif chamber.type == "hopper" then
                if chamber.status.capacity >= chamber.status.maxCapacity then
                    self.Out:Fire("idleWorkers", {
                        task = "upgradePantry",
                        targetId = targetId,
                    })
                end
            end
        end
    end

    return {
        name = "CommandManagerNode",
        domain = "server",

        Sys = {
            onInit = function(self)
                local System = self._System
                if System and System.Debug then
                    System.Debug.info("CommandManager", "Initialized")
                end
            end,

            onStart = function(self) end,

            onStop = function(self)
                cleanupState(self)
            end,
        },

        In = {
            onClutchStatus = function(self, data)
                if not data then return end

                local state = getState(self)
                -- Use a stable targetId — for now single clutch
                local targetId = "EggClutch"
                state.chambers[targetId] = {
                    type = "clutch",
                    status = {
                        capacity = data.capacity,
                        maxCapacity = data.maxCapacity,
                        eggs = data.eggs,
                    },
                }

                checkInvalidations(self)
                broadcastCommands(self)
            end,

            onHopperStatus = function(self, data)
                if not data then return end

                local state = getState(self)
                local targetId = "FoodHopper"
                state.chambers[targetId] = {
                    type = "hopper",
                    status = data,
                }

                checkInvalidations(self)
                broadcastCommands(self)
            end,

            onFoodSourceStatus = function(self, data)
                if not data then return end

                local state = getState(self)
                state.discoveredSourceCount = data.discovered and #data.discovered or 0
                state.undiscoveredSourceCount = data.undiscoveredCount or 0
                state.hasDiscoveredSources = state.discoveredSourceCount > 0
                broadcastCommands(self)
            end,

            onColonyStatus = function(self, data)
                if not data or not data.ants then return end

                local state = getState(self)
                state.ants = data.ants
                broadcastCommands(self)
            end,

            onSelectWorker = function(self, data)
                if not data then return end
                local state = getState(self)

                if data.workerId then
                    state.selectedAntId = data.workerId
                    state.selectedAntClass = nil
                    state.selectedClassId = nil
                    state.selectedClassLocked = false
                    state.selectedReclassCount = 0
                    for _, a in ipairs(state.ants) do
                        if a.id == data.workerId then
                            state.selectedAntClass = a.class
                            state.selectedClassId = a.classId
                            state.selectedClassLocked = a.classLocked or false
                            state.selectedReclassCount = a.reclassCount or 0
                            break
                        end
                    end
                else
                    state.selectedAntId = nil
                    state.selectedAntClass = nil
                    state.selectedClassId = nil
                end

                broadcastCommands(self)
            end,

            onDeselectWorker = function(self)
                local state = getState(self)
                state.selectedAntClass = nil
                state.selectedWorkerClass = nil
                broadcastCommands(self)
            end,

            onAssignTask = function(self, data)
                if not data or not data.workerId or not data.task then return end

                -- Idle bypasses validation
                if data.task == "idle" then
                    self.Out:Fire("assignTask", {
                        antId = data.workerId,
                        task = "idle",
                        targetId = nil,
                    })
                    return
                end

                -- layEggs bypasses slot validation
                if data.task == "layEggs" then
                    self.Out:Fire("assignTask", {
                        antId = data.workerId,
                        task = "layEggs",
                        targetId = nil,
                    })
                    return
                end

                local state = getState(self)
                local targetId = data.targetId or "colony"

                -- Validate: check slot availability
                local cap = TASK_CAPS[data.task] or 2
                local assigned = countAssignments(state, data.task, targetId)
                if assigned >= cap then
                    local System = self._System
                    if System and System.Debug then
                        System.Debug.warn("CommandManager", string.format(
                            "Rejected — %s on %s is full (%d/%d)",
                            data.task, targetId, assigned, cap
                        ))
                    end
                    return
                end

                -- Validate: check chamber-specific constraints
                if data.task == "upgrade" or data.task == "upgradePantry" then
                    local chamber = state.chambers[targetId]
                    if chamber and chamber.status.capacity >= chamber.status.maxCapacity then
                        local System = self._System
                        if System and System.Debug then
                            System.Debug.warn("CommandManager", string.format(
                                "Rejected — %s is at max capacity", targetId
                            ))
                        end
                        return
                    end
                end

                -- Handle rebirth
                if data.rebirthTo then
                    local cls = ClassTree.get(data.rebirthTo)
                    if cls then
                        self.Out:Fire("deductXP", { amount = cls.rebirthCost, reason = "rebirth:" .. data.rebirthTo })
                    end

                    self.Out:Fire("assignTask", {
                        antId = data.workerId,
                        task = data.task,
                        targetId = targetId,
                        rebirthTo = data.rebirthTo,
                    })
                    return
                end

                -- Handle reclass
                if data.reclassTo then
                    local ant = nil
                    for _, a in ipairs(state.ants) do
                        if a.id == data.workerId then ant = a; break end
                    end

                    if ant and ant.classLocked then
                        local cost = getReclassCost(ant.reclassCount or 0)
                        self.Out:Fire("deductXP", { amount = cost, reason = "reclass:" .. data.reclassTo })
                    end

                    self.Out:Fire("assignTask", {
                        antId = data.workerId,
                        task = data.task,
                        targetId = targetId,
                        reclassTo = data.reclassTo,
                    })
                    return
                end

                -- Forward normal command
                self.Out:Fire("assignTask", {
                    antId = data.workerId,
                    task = data.task,
                    targetId = targetId,
                })

                local System = self._System
                if System and System.Debug then
                    System.Debug.info("CommandManager", string.format(
                        "Assigned ant %d → %s on %s",
                        data.workerId, data.task, targetId
                    ))
                end
            end,
        },

        Out = {
            availableCommands = {},
            assignTask = {},
            idleWorkers = {},
            deductXP = {},
        },
    }
end)

return CommandManagerNode
