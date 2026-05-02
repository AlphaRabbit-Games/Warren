--[[
    Ant Colony Simulation — TimeHUD
    Client-side game time display HUD.

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    TimeHUD is a client-side node that displays the current game day and time
    in a simple HUD in the top-left corner of the screen.

    It receives tick signals from GameClock via IPC cross-domain wiring.

    ============================================================================
    SIGNALS
    ============================================================================

    IN (receives):
        onTick({ gameDay, gameHour, gameMinute, totalGameHours, isPaused })
            - Updates the HUD with current day, time, and pause state

--]]

local Players = game:GetService("Players")

local Warren = require(game:GetService("ReplicatedStorage").Warren)
local Node = Warren.Node

--------------------------------------------------------------------------------
-- TIMEHUD NODE
--------------------------------------------------------------------------------

local TimeHUD = Node.extend(function(parent)
    ----------------------------------------------------------------------------
    -- PRIVATE STATE
    ----------------------------------------------------------------------------

    local instanceStates = {}

    local function getState(self)
        if not instanceStates[self.id] then
            instanceStates[self.id] = {
                screenGui = nil,
                dayLabel = nil,
                timeLabel = nil,
                pauseLabel = nil,
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
    -- UI CREATION
    ----------------------------------------------------------------------------

    local PADDING = 8

    local function createUI(self)
        local state = getState(self)
        local player = Players.LocalPlayer
        if not player then return end

        local playerGui = player:WaitForChild("PlayerGui")

        -- Clean up existing
        if state.screenGui then
            state.screenGui:Destroy()
        end
        local existing = playerGui:FindFirstChild("TimeHUD")
        if existing then
            existing:Destroy()
        end

        -- Create ScreenGui
        local screenGui = Instance.new("ScreenGui")
        screenGui.Name = "TimeHUD"
        screenGui.ResetOnSpawn = false
        screenGui.DisplayOrder = 10
        screenGui.Parent = playerGui

        -- Create container frame (top-left corner)
        local container = Instance.new("Frame")
        container.Name = "Container"
        container.Size = UDim2.new(0, 100, 0, 50)
        container.AnchorPoint = Vector2.new(1, 0)
        container.Position = UDim2.new(1, -10, 0, 10)
        container.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
        container.BackgroundTransparency = 0.5
        container.BorderSizePixel = 0
        container.Parent = screenGui

        -- Corner rounding
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 6)
        corner.Parent = container

        -- Day label (row 1)
        local dayLabel = Instance.new("TextLabel")
        dayLabel.Name = "DayLabel"
        dayLabel.Size = UDim2.new(1, -PADDING * 2, 0, 18)
        dayLabel.Position = UDim2.new(0, PADDING, 0, PADDING)
        dayLabel.BackgroundTransparency = 1
        dayLabel.Text = "DAY 1"
        dayLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
        dayLabel.TextSize = 14
        dayLabel.Font = Enum.Font.GothamBold
        dayLabel.TextXAlignment = Enum.TextXAlignment.Right
        dayLabel.Parent = container

        -- Time label (row 2)
        local timeLabel = Instance.new("TextLabel")
        timeLabel.Name = "TimeLabel"
        timeLabel.Size = UDim2.new(1, -PADDING * 2, 0, 18)
        timeLabel.Position = UDim2.new(0, PADDING, 0, PADDING + 22)
        timeLabel.BackgroundTransparency = 1
        timeLabel.Text = "00:00"
        timeLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
        timeLabel.TextSize = 14
        timeLabel.Font = Enum.Font.Gotham
        timeLabel.TextXAlignment = Enum.TextXAlignment.Right
        timeLabel.Parent = container

        -- Pause indicator (overlaid, hidden by default)
        local pauseLabel = Instance.new("TextLabel")
        pauseLabel.Name = "PauseLabel"
        pauseLabel.Size = UDim2.new(1, -PADDING * 2, 0, 18)
        pauseLabel.Position = UDim2.new(0, PADDING, 0, PADDING + 22)
        pauseLabel.BackgroundTransparency = 1
        pauseLabel.Text = "PAUSED"
        pauseLabel.TextColor3 = Color3.fromRGB(255, 100, 50)
        pauseLabel.TextSize = 14
        pauseLabel.Font = Enum.Font.GothamBold
        pauseLabel.TextXAlignment = Enum.TextXAlignment.Right
        pauseLabel.Visible = false
        pauseLabel.Parent = container

        state.screenGui = screenGui
        state.dayLabel = dayLabel
        state.timeLabel = timeLabel
        state.pauseLabel = pauseLabel
    end

    ----------------------------------------------------------------------------
    -- PUBLIC INTERFACE
    ----------------------------------------------------------------------------

    return {
        name = "TimeHUD",
        domain = "client",

        Sys = {
            onInit = function(self)
                createUI(self)
            end,

            onStart = function(self)
                -- No polling needed - we receive signals
            end,

            onStop = function(self)
                cleanupState(self)
            end,
        },

        In = {
            --[[
                Handle tick signal from GameClock.
                Updates the day, time, and pause indicator labels.

                @param data table:
                    gameDay: number - Current game day (1-based)
                    gameHour: number - Current hour (0-23)
                    gameMinute: number - Current minute (0-59)
                    totalGameHours: number - Total elapsed game hours
                    isPaused: boolean - Whether the clock is paused
            --]]
            onTick = function(self, data)
                if not data then return end

                local state = getState(self)

                if state.dayLabel and data.gameDay then
                    state.dayLabel.Text = "DAY " .. tostring(data.gameDay)
                end

                if state.timeLabel and data.gameHour and data.gameMinute then
                    state.timeLabel.Text = string.format("%02d:%02d", data.gameHour, data.gameMinute)
                end

                if state.pauseLabel then
                    state.pauseLabel.Visible = data.isPaused == true
                    -- Hide time label when paused, show pause label instead
                    if state.timeLabel then
                        state.timeLabel.Visible = not data.isPaused
                    end
                end
            end,
        },

        Out = {},
    }
end)

return TimeHUD
