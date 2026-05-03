--[[
    Ant Colony Simulation — ClutchHUD
    Client-side egg clutch status display.

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    Displays egg clutch status below the QueenHUD in the top-right corner:
    - Egg count bar with numeric value
    - Capacity info
    - Discarded egg count (if any)

    ============================================================================
    SIGNALS
    ============================================================================

    IN (receives):
        onClutchStatus({ eggs, capacity, maxCapacity, discarded })

--]]

local Players = game:GetService("Players")

local Warren = require(game:GetService("ReplicatedStorage").Warren)
local Node = Warren.Node

--------------------------------------------------------------------------------
-- CLUTCH HUD NODE
--------------------------------------------------------------------------------

local ClutchHUD = Node.extend(function(parent)
    local instanceStates = {}

    local function getState(self)
        if not instanceStates[self.id] then
            instanceStates[self.id] = {
                screenGui = nil,
                eggFill = nil,
                eggLabel = nil,
                hatchLabel = nil,
                hatchedLabel = nil,
                discardedLabel = nil,
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
        local existing = playerGui:FindFirstChild("ClutchHUD")
        if existing then
            existing:Destroy()
        end

        local screenGui = Instance.new("ScreenGui")
        screenGui.Name = "ClutchHUD"
        screenGui.ResetOnSpawn = false
        screenGui.DisplayOrder = 10
        screenGui.Parent = playerGui

        -- Position below PantryHUD (TimeHUD 50+10 + gap 8 + PantryHUD 66 + gap 8 = 142)
        local container = Instance.new("Frame")
        container.Name = "Container"
        container.AnchorPoint = Vector2.new(1, 0)
        container.Position = UDim2.new(1, -10, 0, 142)
        container.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
        container.BackgroundTransparency = 0.5
        container.BorderSizePixel = 0
        container.Parent = screenGui

        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 6)
        corner.Parent = container

        local y = PADDING

        -- Title
        createLabel(container, "Title", y, "EGG CLUTCH", Color3.fromRGB(180, 220, 255), Enum.Font.GothamBold)
        y = y + ROW_HEIGHT + ROW_GAP

        -- Egg bar background
        local eggBarBg = Instance.new("Frame")
        eggBarBg.Name = "EggBarBg"
        eggBarBg.Size = UDim2.new(1, -PADDING * 2, 0, 10)
        eggBarBg.Position = UDim2.new(0, PADDING, 0, y)
        eggBarBg.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
        eggBarBg.BorderSizePixel = 0
        eggBarBg.Parent = container

        local barCorner = Instance.new("UICorner")
        barCorner.CornerRadius = UDim.new(0, 3)
        barCorner.Parent = eggBarBg

        local eggFill = Instance.new("Frame")
        eggFill.Name = "EggFill"
        eggFill.Size = UDim2.new(0, 0, 1, 0)
        eggFill.BackgroundColor3 = Color3.fromRGB(180, 220, 255)
        eggFill.BorderSizePixel = 0
        eggFill.Parent = eggBarBg

        local fillCorner = Instance.new("UICorner")
        fillCorner.CornerRadius = UDim.new(0, 3)
        fillCorner.Parent = eggFill

        state.eggFill = eggFill
        y = y + 10 + ROW_GAP

        -- Egg count
        state.eggLabel = createLabel(container, "EggLabel", y, "Eggs: 0/5")
        y = y + ROW_HEIGHT + ROW_GAP

        -- Hatch progress (nearest egg)
        state.hatchLabel = createLabel(container, "HatchLabel", y, "Hatch: --")
        y = y + ROW_HEIGHT + ROW_GAP

        -- Total hatched
        state.hatchedLabel = createLabel(container, "HatchedLabel", y, "Hatched: 0", Color3.fromRGB(120, 220, 120), Enum.Font.GothamBold)
        y = y + ROW_HEIGHT + ROW_GAP

        -- Discarded (hidden until first discard)
        state.discardedLabel = createLabel(container, "DiscardedLabel", y, "", Color3.fromRGB(220, 60, 40))
        state.discardedLabel.Visible = false
        y = y + ROW_HEIGHT + PADDING

        container.Size = UDim2.new(0, CONTAINER_WIDTH, 0, y)

        state.screenGui = screenGui
    end

    return {
        name = "ClutchHUD",
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
            onClutchStatus = function(self, data)
                if not data then return end

                local state = getState(self)

                -- Egg bar
                if state.eggFill and data.eggs and data.capacity and data.capacity > 0 then
                    local pct = math.clamp(data.eggs / data.capacity, 0, 1)
                    state.eggFill.Size = UDim2.new(pct, 0, 1, 0)

                    -- Color shifts as clutch fills
                    if pct < 0.75 then
                        state.eggFill.BackgroundColor3 = Color3.fromRGB(180, 220, 255)
                    elseif pct < 1 then
                        state.eggFill.BackgroundColor3 = Color3.fromRGB(220, 180, 40)
                    else
                        state.eggFill.BackgroundColor3 = Color3.fromRGB(220, 60, 40)
                    end
                end

                -- Egg count
                if state.eggLabel and data.eggs and data.capacity then
                    state.eggLabel.Text = string.format("Eggs: %d/%d", data.eggs, data.capacity)
                end

                -- Hatch progress (nearest egg)
                if state.hatchLabel then
                    if data.eggs and data.eggs > 0 and data.nearestHatchProgress and data.nearestHatchThreshold then
                        state.hatchLabel.Text = string.format("Hatch: %d/%d", data.nearestHatchProgress, data.nearestHatchThreshold)
                        state.hatchLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
                    else
                        state.hatchLabel.Text = "Hatch: --"
                        state.hatchLabel.TextColor3 = Color3.fromRGB(120, 120, 120)
                    end
                end

                -- Total hatched
                if state.hatchedLabel and data.hatched then
                    state.hatchedLabel.Text = "Hatched: " .. tostring(data.hatched)
                end

                -- Discarded
                if state.discardedLabel and data.discarded then
                    if data.discarded > 0 then
                        state.discardedLabel.Text = string.format("Lost: %d", data.discarded)
                        state.discardedLabel.Visible = true
                    end
                end
            end,
        },

        Out = {},
    }
end)

return ClutchHUD
