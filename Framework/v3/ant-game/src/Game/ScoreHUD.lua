--[[
    Ant Colony Simulation — ScoreHUD
    Client-side score display.

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    Top-center score readout. Receives scoreChanged broadcasts and updates the
    big yellow number. Briefly flashes red on a starvation penalty.

    ============================================================================
    SIGNALS
    ============================================================================

    IN (receives):
        onScoreChanged({ score, delta, reason })

--]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Warren = require(game:GetService("ReplicatedStorage").Warren)
local Node = Warren.Node

--------------------------------------------------------------------------------
-- SCORE HUD NODE
--------------------------------------------------------------------------------

local NORMAL_COLOR = Color3.fromRGB(255, 220, 100)
local PENALTY_COLOR = Color3.fromRGB(255, 90, 90)
local FLASH_TIME = 0.6

local ScoreHUD = Node.extend(function(parent)
    local instanceStates = {}

    local function getState(self)
        if not instanceStates[self.id] then
            instanceStates[self.id] = {
                screenGui = nil,
                scoreLabel = nil,
                flashTween = nil,
            }
        end
        return instanceStates[self.id]
    end

    local function cleanupState(self)
        local state = instanceStates[self.id]
        if state and state.screenGui then
            state.screenGui:Destroy()
        end
        instanceStates[self.id] = nil
    end

    local function createUI(self)
        local state = getState(self)
        local player = Players.LocalPlayer
        if not player then return end

        local playerGui = player:WaitForChild("PlayerGui")

        if state.screenGui then state.screenGui:Destroy() end
        local existing = playerGui:FindFirstChild("ScoreHUD")
        if existing then existing:Destroy() end

        local screenGui = Instance.new("ScreenGui")
        screenGui.Name = "ScoreHUD"
        screenGui.ResetOnSpawn = false
        screenGui.DisplayOrder = 10
        screenGui.Parent = playerGui

        local container = Instance.new("Frame")
        container.Name = "Container"
        container.Size = UDim2.new(0, 200, 0, 60)
        container.AnchorPoint = Vector2.new(0.5, 0)
        container.Position = UDim2.new(0.5, 0, 0, 10)
        container.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
        container.BackgroundTransparency = 0.5
        container.BorderSizePixel = 0
        container.Parent = screenGui

        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 6)
        corner.Parent = container

        local header = Instance.new("TextLabel")
        header.Name = "Header"
        header.Size = UDim2.new(1, 0, 0, 14)
        header.Position = UDim2.new(0, 0, 0, 6)
        header.BackgroundTransparency = 1
        header.Text = "SCORE"
        header.TextColor3 = Color3.fromRGB(180, 180, 180)
        header.TextSize = 11
        header.Font = Enum.Font.Gotham
        header.Parent = container

        local scoreLabel = Instance.new("TextLabel")
        scoreLabel.Name = "Score"
        scoreLabel.Size = UDim2.new(1, 0, 0, 32)
        scoreLabel.Position = UDim2.new(0, 0, 0, 22)
        scoreLabel.BackgroundTransparency = 1
        scoreLabel.Text = "0"
        scoreLabel.TextColor3 = NORMAL_COLOR
        scoreLabel.TextSize = 28
        scoreLabel.Font = Enum.Font.GothamBold
        scoreLabel.Parent = container

        state.screenGui = screenGui
        state.scoreLabel = scoreLabel
    end

    local function flashPenalty(self)
        local state = getState(self)
        if not state.scoreLabel then return end

        if state.flashTween then state.flashTween:Cancel() end

        state.scoreLabel.TextColor3 = PENALTY_COLOR
        state.flashTween = TweenService:Create(
            state.scoreLabel,
            TweenInfo.new(FLASH_TIME, Enum.EasingStyle.Linear),
            { TextColor3 = NORMAL_COLOR }
        )
        state.flashTween:Play()
    end

    return {
        name = "ScoreHUD",
        domain = "client",

        Sys = {
            onInit = function(self)
                createUI(self)
            end,

            onStop = function(self)
                cleanupState(self)
            end,
        },

        In = {
            onScoreChanged = function(self, data)
                if not data then return end

                local state = getState(self)
                if state.scoreLabel then
                    state.scoreLabel.Text = string.format("%d", data.score or 0)
                end

                if data.reason == "starvation" then
                    flashPenalty(self)
                end
            end,
        },

        Out = {},
    }
end)

return ScoreHUD
