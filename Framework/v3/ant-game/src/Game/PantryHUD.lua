--[[
    Ant Colony Simulation — PantryHUD
    Client-side pantry status display.

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    Displays pantry stock and capacity below the game timer (top-right).

    ============================================================================
    SIGNALS
    ============================================================================

    IN (receives):
        onHopperStatus({ stock, capacity, maxCapacity, energyPerBite })

--]]

local Players = game:GetService("Players")

local Warren = require(game:GetService("ReplicatedStorage").Warren)
local Node = Warren.Node

--------------------------------------------------------------------------------
-- PANTRY HUD NODE
--------------------------------------------------------------------------------

local PantryHUD = Node.extend(function(parent)
    local instanceStates = {}

    local function getState(self)
        if not instanceStates[self.id] then
            instanceStates[self.id] = {
                screenGui = nil,
                stockFill = nil,
                stockLabel = nil,
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

    local PADDING = 8
    local ROW_HEIGHT = 16
    local ROW_GAP = 4
    local CONTAINER_WIDTH = 140

    local function createLabel(parentFrame, name, yOffset, text, color, font)
        local label = Instance.new("TextLabel")
        label.Name = name
        label.Size = UDim2.new(1, -PADDING * 2, 0, ROW_HEIGHT)
        label.Position = UDim2.new(0, PADDING, 0, yOffset)
        label.BackgroundTransparency = 1
        label.Text = text
        label.TextColor3 = color or Color3.fromRGB(200, 200, 200)
        label.TextSize = 12
        label.Font = font or Enum.Font.Gotham
        label.TextXAlignment = Enum.TextXAlignment.Right
        label.Parent = parentFrame
        return label
    end

    local function createUI(self)
        local state = getState(self)
        local player = Players.LocalPlayer
        if not player then return end

        local playerGui = player:WaitForChild("PlayerGui")

        if state.screenGui then
            state.screenGui:Destroy()
        end
        local existing = playerGui:FindFirstChild("PantryHUD")
        if existing then
            existing:Destroy()
        end

        local screenGui = Instance.new("ScreenGui")
        screenGui.Name = "PantryHUD"
        screenGui.ResetOnSpawn = false
        screenGui.DisplayOrder = 10
        screenGui.Parent = playerGui

        -- Position below TimeHUD (50 + 10 top + 8 gap = 68)
        local container = Instance.new("Frame")
        container.Name = "Container"
        container.AnchorPoint = Vector2.new(1, 0)
        container.Position = UDim2.new(1, -10, 0, 68)
        container.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
        container.BackgroundTransparency = 0.5
        container.BorderSizePixel = 0
        container.Parent = screenGui

        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 6)
        corner.Parent = container

        local y = PADDING

        -- Title
        createLabel(container, "Title", y, "PANTRY", Color3.fromRGB(160, 200, 120), Enum.Font.GothamBold)
        y = y + ROW_HEIGHT + ROW_GAP

        -- Stock bar background
        local barBg = Instance.new("Frame")
        barBg.Name = "StockBarBg"
        barBg.Size = UDim2.new(1, -PADDING * 2, 0, 10)
        barBg.Position = UDim2.new(0, PADDING, 0, y)
        barBg.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
        barBg.BorderSizePixel = 0
        barBg.Parent = container

        local barCorner = Instance.new("UICorner")
        barCorner.CornerRadius = UDim.new(0, 3)
        barCorner.Parent = barBg

        local stockFill = Instance.new("Frame")
        stockFill.Name = "StockFill"
        stockFill.Size = UDim2.new(0, 0, 1, 0)
        stockFill.BackgroundColor3 = Color3.fromRGB(160, 200, 120)
        stockFill.BorderSizePixel = 0
        stockFill.Parent = barBg

        local fillCorner = Instance.new("UICorner")
        fillCorner.CornerRadius = UDim.new(0, 3)
        fillCorner.Parent = stockFill

        state.stockFill = stockFill
        y = y + 10 + ROW_GAP

        -- Stock label
        state.stockLabel = createLabel(container, "StockLabel", y, "Stock: 0/200")
        y = y + ROW_HEIGHT + PADDING

        container.Size = UDim2.new(0, CONTAINER_WIDTH, 0, y)
        state.screenGui = screenGui
    end

    return {
        name = "PantryHUD",
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
            onHopperStatus = function(self, data)
                if not data then return end

                local state = getState(self)

                if state.stockFill and data.stock and data.capacity and data.capacity > 0 then
                    local pct = math.clamp(data.stock / data.capacity, 0, 1)
                    state.stockFill.Size = UDim2.new(pct, 0, 1, 0)

                    if pct > 0.5 then
                        state.stockFill.BackgroundColor3 = Color3.fromRGB(160, 200, 120)
                    elseif pct > 0.2 then
                        state.stockFill.BackgroundColor3 = Color3.fromRGB(220, 180, 40)
                    else
                        state.stockFill.BackgroundColor3 = Color3.fromRGB(220, 60, 40)
                    end
                end

                if state.stockLabel and data.stock and data.capacity then
                    state.stockLabel.Text = string.format("Stock: %d/%d", data.stock, data.capacity)
                end
            end,
        },

        Out = {},
    }
end)

return PantryHUD
