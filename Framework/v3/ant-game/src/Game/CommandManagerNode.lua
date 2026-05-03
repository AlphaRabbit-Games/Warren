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
local Node = Warren.Node

--------------------------------------------------------------------------------
-- DEFAULTS
--------------------------------------------------------------------------------

local TASK_CAPS = {
    explore = 999,
    gatherClosest = 999,
    gatherLargest = 999,
    gatherBest = 999,
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
                -- Currently selected ant (for class-based commands)
                selectedAntClass = nil,
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

    local function buildCommands(self)
        local state = getState(self)
        local commands = {}

        -- Lay Eggs — queen only
        if state.selectedAntClass == "queen" then
            commands[#commands + 1] = {
                task = "layEggs",
                targetId = nil,
                label = "Lay Eggs",
            }
        end

        -- Explore
        local exploreAssigned = countAssignments(state, "explore", nil)
        if exploreAssigned < TASK_CAPS.explore then
            commands[#commands + 1] = {
                task = "explore",
                targetId = nil,
                label = string.format("Explore (%d ants, %d undiscovered)",
                    exploreAssigned, state.undiscoveredSourceCount),
            }
        end

        -- Gather strategies — only when discovered sources exist
        if state.hasDiscoveredSources then
            local closestAssigned = countAssignments(state, "gatherClosest", nil)
            if closestAssigned < TASK_CAPS.gatherClosest then
                commands[#commands + 1] = {
                    task = "gatherClosest",
                    targetId = nil,
                    label = string.format("Gather Closest (%d ants)", closestAssigned),
                }
            end

            local largestAssigned = countAssignments(state, "gatherLargest", nil)
            if largestAssigned < TASK_CAPS.gatherLargest then
                commands[#commands + 1] = {
                    task = "gatherLargest",
                    targetId = nil,
                    label = string.format("Gather Largest (%d ants)", largestAssigned),
                }
            end

            local bestAssigned = countAssignments(state, "gatherBest", nil)
            if bestAssigned < TASK_CAPS.gatherBest then
                commands[#commands + 1] = {
                    task = "gatherBest",
                    targetId = nil,
                    label = string.format("Gather Best (%d ants)", bestAssigned),
                }
            end
        end

        -- Dig tunnel
        local digAssigned = countAssignments(state, "dig", "colony")
        if digAssigned < TASK_CAPS.dig then
            commands[#commands + 1] = {
                task = "dig",
                targetId = "colony",
                label = string.format("Dig Tunnel (%d ants)", digAssigned),
            }
        end

        -- Chamber-dependent commands
        for targetId, chamber in pairs(state.chambers) do
            if chamber.type == "clutch" then
                if chamber.status.capacity < chamber.status.maxCapacity then
                    local assigned = countAssignments(state, "upgrade", targetId)
                    if assigned < TASK_CAPS.upgrade then
                        commands[#commands + 1] = {
                            task = "upgrade",
                            targetId = targetId,
                            label = string.format("Upgrade Clutch (%d/%d cap, %d/%d ants)",
                                chamber.status.capacity, chamber.status.maxCapacity,
                                assigned, TASK_CAPS.upgrade),
                        }
                    end
                end
            elseif chamber.type == "hopper" then
                if chamber.status.capacity < chamber.status.maxCapacity then
                    local upgradeAssigned = countAssignments(state, "upgradePantry", targetId)
                    if upgradeAssigned < TASK_CAPS.upgradePantry then
                        commands[#commands + 1] = {
                            task = "upgradePantry",
                            targetId = targetId,
                            label = string.format("Upgrade Pantry (%d/%d cap, %d/%d ants)",
                                chamber.status.capacity, chamber.status.maxCapacity,
                                upgradeAssigned, TASK_CAPS.upgradePantry),
                        }
                    end
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

                -- Find ant class for the selected ant
                if data.workerId then
                    state.selectedAntClass = nil
                    for _, a in ipairs(state.ants) do
                        if a.id == data.workerId then
                            state.selectedAntClass = a.class
                            break
                        end
                    end
                else
                    state.selectedAntClass = nil
                end

                broadcastCommands(self)
            end,

            onDeselectWorker = function(self)
                local state = getState(self)
                state.selectedAntClass = nil
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

                -- Forward validated command
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
        },
    }
end)

return CommandManagerNode
