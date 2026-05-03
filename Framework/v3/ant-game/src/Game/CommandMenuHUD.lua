--[[
    Ant Colony Simulation — CommandMenuHUD
    Client-side command assignment popup.

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    Center-screen popup that appears when a worker ant is selected in the
    WorkerHUD. Shows a dynamic list of available commands from CommandManager.
    Hidden when no ant is selected or after a command is assigned.

    ============================================================================
    SIGNALS
    ============================================================================

    IN (receives):
        onAvailableCommands({ commands })
            - From CommandManagerNode. List of valid commands.

        onSelectWorker({ workerId, workerName })
            - From WorkerHUD. Opens the menu for this worker.

        onDeselectWorker()
            - From WorkerHUD. Closes the menu.

    OUT (sends):
        assignTask({ workerId, task, targetId })
            - Player chose a command. Sent to CommandManager.

--]]

local Players = game:GetService("Players")

local Warren = require(game:GetService("ReplicatedStorage").Warren)
local Node = Warren.Node

--------------------------------------------------------------------------------
-- COMMAND MENU HUD NODE
--------------------------------------------------------------------------------

local CommandMenuHUD = Node.extend(function(parent)
    local instanceStates = {}

    local function getState(self)
        if not instanceStates[self.id] then
            instanceStates[self.id] = {
                screenGui = nil,
                container = nil,
                titleLabel = nil,
                buttonFrame = nil,
                buttons = {},
                selectedWorkerId = nil,
                selectedWorkerName = nil,
                commands = {},
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

    local PADDING = 12
    local BUTTON_HEIGHT = 32
    local BUTTON_GAP = 4
    local MENU_WIDTH = 260

    local TASK_COLORS = {
        gather = Color3.fromRGB(60, 140, 60),
        dig = Color3.fromRGB(140, 100, 60),
        upgrade = Color3.fromRGB(60, 100, 180),
        upgradePantry = Color3.fromRGB(100, 140, 60),
        layEggs = Color3.fromRGB(180, 120, 60),
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
        local existing = playerGui:FindFirstChild("CommandMenuHUD")
        if existing then
            existing:Destroy()
        end

        local screenGui = Instance.new("ScreenGui")
        screenGui.Name = "CommandMenuHUD"
        screenGui.ResetOnSpawn = false
        screenGui.DisplayOrder = 20  -- above other HUDs
        screenGui.Parent = playerGui

        -- Center container
        local container = Instance.new("Frame")
        container.Name = "Container"
        container.AnchorPoint = Vector2.new(0.5, 0.5)
        container.Position = UDim2.new(0.5, 0, 0.5, 0)
        container.Size = UDim2.new(0, MENU_WIDTH, 0, 100)
        container.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
        container.BackgroundTransparency = 0.15
        container.BorderSizePixel = 0
        container.Visible = false
        container.Parent = screenGui

        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 8)
        corner.Parent = container

        -- Title
        local titleLabel = Instance.new("TextLabel")
        titleLabel.Name = "Title"
        titleLabel.Size = UDim2.new(1, -PADDING * 2, 0, 20)
        titleLabel.Position = UDim2.new(0, PADDING, 0, PADDING)
        titleLabel.BackgroundTransparency = 1
        titleLabel.Text = "ASSIGN COMMAND"
        titleLabel.TextColor3 = Color3.fromRGB(200, 160, 100)
        titleLabel.TextSize = 13
        titleLabel.Font = Enum.Font.GothamBold
        titleLabel.TextXAlignment = Enum.TextXAlignment.Center
        titleLabel.Parent = container

        -- Worker name
        local nameLabel = Instance.new("TextLabel")
        nameLabel.Name = "WorkerName"
        nameLabel.Size = UDim2.new(1, -PADDING * 2, 0, 16)
        nameLabel.Position = UDim2.new(0, PADDING, 0, PADDING + 22)
        nameLabel.BackgroundTransparency = 1
        nameLabel.Text = ""
        nameLabel.TextColor3 = Color3.fromRGB(220, 220, 220)
        nameLabel.TextSize = 12
        nameLabel.Font = Enum.Font.Gotham
        nameLabel.TextXAlignment = Enum.TextXAlignment.Center
        nameLabel.Parent = container

        -- Button area
        local buttonFrame = Instance.new("Frame")
        buttonFrame.Name = "Buttons"
        buttonFrame.Size = UDim2.new(1, 0, 0, 0)
        buttonFrame.Position = UDim2.new(0, 0, 0, PADDING + 44)
        buttonFrame.BackgroundTransparency = 1
        buttonFrame.Parent = container

        -- Idle button (always available)
        local idleBtn = Instance.new("TextButton")
        idleBtn.Name = "IdleBtn"
        idleBtn.Size = UDim2.new(1, -PADDING * 2, 0, 24)
        idleBtn.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
        idleBtn.BackgroundTransparency = 0.3
        idleBtn.BorderSizePixel = 0
        idleBtn.Text = "Set Idle"
        idleBtn.TextColor3 = Color3.fromRGB(200, 200, 200)
        idleBtn.TextSize = 11
        idleBtn.Font = Enum.Font.Gotham
        idleBtn.Parent = container

        local idleCorner = Instance.new("UICorner")
        idleCorner.CornerRadius = UDim.new(0, 4)
        idleCorner.Parent = idleBtn

        idleBtn.MouseButton1Click:Connect(function()
            local s = getState(self)
            if s.selectedWorkerId then
                self.Out:Fire("assignTask", {
                    workerId = s.selectedWorkerId,
                    task = "idle",
                    targetId = nil,
                })
                -- Close menu
                s.selectedWorkerId = nil
                s.container.Visible = false
            end
        end)

        state.screenGui = screenGui
        state.container = container
        state.titleLabel = titleLabel
        state.nameLabel = container:FindFirstChild("WorkerName")
        state.buttonFrame = buttonFrame
        state.idleBtn = idleBtn
    end

    ----------------------------------------------------------------------------
    -- COMMAND RENDERING
    ----------------------------------------------------------------------------

    local function renderCommands(self)
        local state = getState(self)
        if not state.buttonFrame then return end

        -- Clear old buttons
        for _, btn in ipairs(state.buttons) do
            btn:Destroy()
        end
        state.buttons = {}

        if not state.selectedWorkerId then
            state.container.Visible = false
            return
        end

        state.container.Visible = true
        if state.nameLabel then
            state.nameLabel.Text = state.selectedWorkerName or ("Worker #" .. state.selectedWorkerId)
        end

        local y = 0
        for _, cmd in ipairs(state.commands) do
            local btn = Instance.new("TextButton")
            btn.Name = "Cmd_" .. cmd.task .. "_" .. (cmd.targetId or "")
            btn.Size = UDim2.new(1, -PADDING * 2, 0, BUTTON_HEIGHT)
            btn.Position = UDim2.new(0, PADDING, 0, y)
            btn.BackgroundColor3 = TASK_COLORS[cmd.task] or Color3.fromRGB(80, 80, 80)
            btn.BackgroundTransparency = 0.3
            btn.BorderSizePixel = 0
            btn.Text = cmd.label
            btn.TextColor3 = Color3.fromRGB(255, 255, 255)
            btn.TextSize = 11
            btn.Font = Enum.Font.GothamBold
            btn.TextWrapped = true
            btn.Parent = state.buttonFrame

            local btnCorner = Instance.new("UICorner")
            btnCorner.CornerRadius = UDim.new(0, 4)
            btnCorner.Parent = btn

            local task = cmd.task
            local targetId = cmd.targetId
            btn.MouseButton1Click:Connect(function()
                local s = getState(self)
                if s.selectedWorkerId then
                    self.Out:Fire("assignTask", {
                        workerId = s.selectedWorkerId,
                        task = task,
                        targetId = targetId,
                    })
                    -- Close menu after assignment
                    s.selectedWorkerId = nil
                    s.container.Visible = false
                end
            end)

            state.buttons[#state.buttons + 1] = btn
            y = y + BUTTON_HEIGHT + BUTTON_GAP
        end

        -- Position idle button below command buttons
        local idleBtnY = PADDING + 44 + y + BUTTON_GAP
        state.idleBtn.Position = UDim2.new(0, PADDING, 0, idleBtnY)

        -- Resize container to fit
        local totalHeight = idleBtnY + 24 + PADDING
        state.container.Size = UDim2.new(0, MENU_WIDTH, 0, totalHeight)

        state.buttonFrame.Size = UDim2.new(1, 0, 0, y)
    end

    return {
        name = "CommandMenuHUD",
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
            onAvailableCommands = function(self, data)
                if not data then return end

                local state = getState(self)
                state.commands = data.commands or {}
                renderCommands(self)
            end,

            onSelectWorker = function(self, data)
                if not data or not data.workerId then return end

                local state = getState(self)
                state.selectedWorkerId = data.workerId
                state.selectedWorkerName = data.workerName
                renderCommands(self)
            end,

            onDeselectWorker = function(self)
                local state = getState(self)
                state.selectedWorkerId = nil
                state.container.Visible = false
            end,
        },

        Out = {
            assignTask = {},
        },
    }
end)

return CommandMenuHUD
