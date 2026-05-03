--[[
    Ant Colony Simulation — WorkerHUD
    Client-side colony list display.

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    Displays the worker colony list on the left side of the screen.
    Clicking a worker selects it and opens the CommandMenuHUD.
    Clicking the selected worker again deselects it.

    ============================================================================
    SIGNALS
    ============================================================================

    IN (receives):
        onWorkerStatus({ workers })
            - Full colony state from WorkerNode.

    OUT (sends):
        selectWorker({ workerId, workerName })
            - Player selected a worker. Opens CommandMenuHUD.

        deselectWorker()
            - Player deselected. Closes CommandMenuHUD.

--]]

local Players = game:GetService("Players")

local Warren = require(game:GetService("ReplicatedStorage").Warren)
local Node = Warren.Node

--------------------------------------------------------------------------------
-- WORKER HUD NODE
--------------------------------------------------------------------------------

local WorkerHUD = Node.extend(function(parent)
    local instanceStates = {}

    local function getState(self)
        if not instanceStates[self.id] then
            instanceStates[self.id] = {
                screenGui = nil,
                container = nil,
                listFrame = nil,
                workerRows = {},
                selectedId = nil,
                lastWorkers = {},
            }
        end
        return instanceStates[self.id]
    end

    local function cleanupState(self)
        local state = instanceStates[self.id]
        if state then
            if state.screenGui then
                state.screenGui:Destroy()
            end
        end
        instanceStates[self.id] = nil
    end

    ----------------------------------------------------------------------------
    -- CONSTANTS
    ----------------------------------------------------------------------------

    local PADDING = 8
    local ROW_HEIGHT = 32
    local ROW_GAP = 2
    local CONTAINER_WIDTH = 170
    local LIST_HEIGHT = 300

    local STATUS_COLORS = {
        idle = Color3.fromRGB(120, 120, 120),
        working = Color3.fromRGB(80, 200, 80),
        cooldown = Color3.fromRGB(200, 180, 60),
    }

    local TASK_LABELS = {
        explore = "Exploring",
        gatherClosest = "Gather Near",
        gatherLargest = "Gather Big",
        gatherBest = "Gather Best",
        dig = "Digging",
        upgrade = "Upgrading",
        upgradePantry = "Upgrading Pantry",
        layEggs = "Laying Eggs",
    }

    ----------------------------------------------------------------------------
    -- UI CREATION
    ----------------------------------------------------------------------------

    local function createUI(self)
        local state = getState(self)
        local player = Players.LocalPlayer
        if not player then return end

        local playerGui = player:WaitForChild("PlayerGui")

        if state.screenGui then
            state.screenGui:Destroy()
        end
        local existing = playerGui:FindFirstChild("WorkerHUD")
        if existing then
            existing:Destroy()
        end

        local screenGui = Instance.new("ScreenGui")
        screenGui.Name = "WorkerHUD"
        screenGui.ResetOnSpawn = false
        screenGui.DisplayOrder = 10
        screenGui.Parent = playerGui

        -- Left side of screen
        local container = Instance.new("Frame")
        container.Name = "Container"
        container.AnchorPoint = Vector2.new(0, 0)
        container.Position = UDim2.new(0, 10, 0.3, 0)
        container.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
        container.BackgroundTransparency = 0.5
        container.BorderSizePixel = 0
        container.Parent = screenGui

        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 6)
        corner.Parent = container

        local y = PADDING

        -- Title
        local title = Instance.new("TextLabel")
        title.Name = "Title"
        title.Size = UDim2.new(1, -PADDING * 2, 0, 16)
        title.Position = UDim2.new(0, PADDING, 0, y)
        title.BackgroundTransparency = 1
        title.Text = "COLONY"
        title.TextColor3 = Color3.fromRGB(200, 160, 100)
        title.TextSize = 12
        title.Font = Enum.Font.GothamBold
        title.TextXAlignment = Enum.TextXAlignment.Left
        title.Parent = container
        y = y + 16 + ROW_GAP

        -- Colony count
        local countLabel = Instance.new("TextLabel")
        countLabel.Name = "CountLabel"
        countLabel.Size = UDim2.new(1, -PADDING * 2, 0, 14)
        countLabel.Position = UDim2.new(0, PADDING, 0, y)
        countLabel.BackgroundTransparency = 1
        countLabel.Text = "Workers: 0"
        countLabel.TextColor3 = Color3.fromRGB(160, 160, 160)
        countLabel.TextSize = 11
        countLabel.Font = Enum.Font.Gotham
        countLabel.TextXAlignment = Enum.TextXAlignment.Left
        countLabel.Parent = container
        y = y + 14 + PADDING

        -- Scrolling list frame
        local listFrame = Instance.new("ScrollingFrame")
        listFrame.Name = "WorkerList"
        listFrame.Size = UDim2.new(1, -PADDING * 2, 0, LIST_HEIGHT)
        listFrame.Position = UDim2.new(0, PADDING, 0, y)
        listFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
        listFrame.BackgroundTransparency = 0.5
        listFrame.BorderSizePixel = 0
        listFrame.ScrollBarThickness = 4
        listFrame.ScrollBarImageColor3 = Color3.fromRGB(100, 100, 100)
        listFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
        listFrame.Parent = container

        local listCorner = Instance.new("UICorner")
        listCorner.CornerRadius = UDim.new(0, 4)
        listCorner.Parent = listFrame

        state.listFrame = listFrame
        y = y + LIST_HEIGHT + PADDING

        container.Size = UDim2.new(0, CONTAINER_WIDTH, 0, y)
        state.container = container
        state.screenGui = screenGui
    end

    ----------------------------------------------------------------------------
    -- LIST RENDERING
    ----------------------------------------------------------------------------

    local function renderWorkerList(self, workers)
        local state = getState(self)
        if not state.listFrame then return end

        -- Clear existing rows
        for _, row in pairs(state.workerRows) do
            row:Destroy()
        end
        state.workerRows = {}

        local y = 2
        for _, w in ipairs(workers) do
            local isSelected = (state.selectedId == w.id)

            local row = Instance.new("TextButton")
            row.Name = "Worker_" .. w.id
            row.Size = UDim2.new(1, -4, 0, ROW_HEIGHT)
            row.Position = UDim2.new(0, 2, 0, y)
            row.BackgroundColor3 = isSelected
                and Color3.fromRGB(60, 60, 80)
                or Color3.fromRGB(30, 30, 30)
            row.BackgroundTransparency = 0.3
            row.BorderSizePixel = 0
            row.Text = ""
            row.Parent = state.listFrame

            local rowCorner = Instance.new("UICorner")
            rowCorner.CornerRadius = UDim.new(0, 3)
            rowCorner.Parent = row

            -- Name
            local nameLabel = Instance.new("TextLabel")
            nameLabel.Name = "Name"
            nameLabel.Size = UDim2.new(1, -6, 0, 14)
            nameLabel.Position = UDim2.new(0, 4, 0, 2)
            nameLabel.BackgroundTransparency = 1
            nameLabel.Text = w.name
            local isQueen = w.class == "queen"
            nameLabel.TextColor3 = isSelected
                and Color3.fromRGB(255, 220, 100)
                or (isQueen and Color3.fromRGB(255, 180, 60) or Color3.fromRGB(220, 220, 220))
            nameLabel.TextSize = 11
            nameLabel.Font = Enum.Font.GothamBold
            nameLabel.TextXAlignment = Enum.TextXAlignment.Left
            nameLabel.Parent = row

            -- Status line
            local statusText
            local statusColor = STATUS_COLORS[w.status] or STATUS_COLORS.idle

            if w.status == "idle" then
                statusText = string.format("Idle  E:%d/%d", w.energy or 0, w.energyCap or 0)
            elseif w.status == "working" then
                local label = TASK_LABELS[w.task] or w.task
                if w.task == "layEggs" then
                    -- Show egg gestation progress
                    local gestating = (w.energy or 0) >= (w.eggEnergyCost or 1)
                    if gestating then
                        statusText = string.format("%s %d/%d  E:%d", label, w.eggCounter or 0, w.eggInterval or 0, w.energy or 0)
                    else
                        statusText = string.format("%s (hungry)  E:%d", label, w.energy or 0)
                    end
                else
                    statusText = string.format("%s %d/%d  E:%d", label, w.taskProgress, w.taskDuration, w.energy or 0)
                end
            elseif w.status == "cooldown" then
                statusText = string.format("Rest %d/%d  E:%d", w.cooldownProgress, w.cooldownDuration, w.energy or 0)
            end

            local statusLabel = Instance.new("TextLabel")
            statusLabel.Name = "Status"
            statusLabel.Size = UDim2.new(1, -6, 0, 12)
            statusLabel.Position = UDim2.new(0, 4, 0, 17)
            statusLabel.BackgroundTransparency = 1
            statusLabel.Text = statusText
            statusLabel.TextColor3 = statusColor
            statusLabel.TextSize = 10
            statusLabel.Font = Enum.Font.Gotham
            statusLabel.TextXAlignment = Enum.TextXAlignment.Left
            statusLabel.TextTruncate = Enum.TextTruncate.AtEnd
            statusLabel.Parent = row

            -- Click to select/deselect
            local workerId = w.id
            local workerName = w.name
            row.MouseButton1Click:Connect(function()
                local s = getState(self)
                if s.selectedId == workerId then
                    -- Deselect
                    s.selectedId = nil
                    self.Out:Fire("deselectWorker", {})
                else
                    -- Select
                    s.selectedId = workerId
                    self.Out:Fire("selectWorker", {
                        workerId = workerId,
                        workerName = workerName,
                    })
                end
                -- Re-render to update highlight
                if s.lastWorkers then
                    renderWorkerList(self, s.lastWorkers)
                end
            end)

            state.workerRows[w.id] = row
            y = y + ROW_HEIGHT + ROW_GAP
        end

        state.listFrame.CanvasSize = UDim2.new(0, 0, 0, y)

        -- Update count label
        local countLabel = state.container and state.container:FindFirstChild("CountLabel")
        if countLabel then
            countLabel.Text = "Workers: " .. #workers
        end
    end

    return {
        name = "WorkerHUD",
        domain = "client",

        Sys = {
            onInit = function(self)
                createUI(self)
            end,

            onStart = function(self) end,

            onStop = function(self)
                cleanupState(self)
            end,
        },

        In = {
            onColonyStatus = function(self, data)
                if not data or not data.ants then return end

                local state = getState(self)
                state.lastWorkers = data.ants
                renderWorkerList(self, data.ants)
            end,
        },

        Out = {
            selectWorker = {},
            deselectWorker = {},
        },
    }
end)

return WorkerHUD
