--[[
    Ant Colony Simulation — QueenHUD
    Client-side queen status display.

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    Displays queen status below the game timer in the top-right corner:
    - Energy bar with numeric value
    - Bite countdown
    - Egg gestation progress (or "STARVING" when energy too low)
    - Total eggs laid

    ============================================================================
    SIGNALS
    ============================================================================

    IN (receives):
        onQueenStatus({ energy, energyCap, biteCounter, biteRate,
                        eggCounter, eggInterval, eggEnergyCost,
                        eggCount, gestating })

--]]

local Players = game:GetService("Players")

local Warren = require(game:GetService("ReplicatedStorage").Warren)
local Node = Warren.Node

--------------------------------------------------------------------------------
-- QUEEN HUD NODE
--------------------------------------------------------------------------------

local QueenHUD = Node.extend(function(parent)
    local instanceStates = {}

    local function getState(self)
        if not instanceStates[self.id] then
            instanceStates[self.id] = {
                screenGui = nil,
                energyBar = nil,
                energyFill = nil,
                energyLabel = nil,
                biteLabel = nil,
                eggProgressLabel = nil,
                eggCountLabel = nil,
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

    local function createLabel(parent, name, yOffset, text, color, font)
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
        label.Parent = parent
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
        local existing = playerGui:FindFirstChild("QueenHUD")
        if existing then
            existing:Destroy()
        end

        local screenGui = Instance.new("ScreenGui")
        screenGui.Name = "QueenHUD"
        screenGui.ResetOnSpawn = false
        screenGui.DisplayOrder = 10
        screenGui.Parent = playerGui

        -- Position below TimeHUD (which is 50px tall + 10px top margin)
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

        -- Row layout
        local y = PADDING

        -- Title
        createLabel(container, "Title", y, "QUEEN", Color3.fromRGB(255, 220, 100), Enum.Font.GothamBold)
        y = y + ROW_HEIGHT + ROW_GAP

        -- Energy bar background
        local energyBarBg = Instance.new("Frame")
        energyBarBg.Name = "EnergyBarBg"
        energyBarBg.Size = UDim2.new(1, -PADDING * 2, 0, 10)
        energyBarBg.Position = UDim2.new(0, PADDING, 0, y)
        energyBarBg.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
        energyBarBg.BorderSizePixel = 0
        energyBarBg.Parent = container

        local barCorner = Instance.new("UICorner")
        barCorner.CornerRadius = UDim.new(0, 3)
        barCorner.Parent = energyBarBg

        -- Energy bar fill
        local energyFill = Instance.new("Frame")
        energyFill.Name = "EnergyFill"
        energyFill.Size = UDim2.new(0, 0, 1, 0)
        energyFill.BackgroundColor3 = Color3.fromRGB(80, 200, 80)
        energyFill.BorderSizePixel = 0
        energyFill.Parent = energyBarBg

        local fillCorner = Instance.new("UICorner")
        fillCorner.CornerRadius = UDim.new(0, 3)
        fillCorner.Parent = energyFill

        state.energyBar = energyBarBg
        state.energyFill = energyFill
        y = y + 10 + ROW_GAP

        -- Energy numeric
        state.energyLabel = createLabel(container, "EnergyLabel", y, "Energy: 0/100")
        y = y + ROW_HEIGHT + ROW_GAP

        -- Bite countdown
        state.biteLabel = createLabel(container, "BiteLabel", y, "Bite: 0/3")
        y = y + ROW_HEIGHT + ROW_GAP

        -- Egg progress
        state.eggProgressLabel = createLabel(container, "EggProgress", y, "Egg: --")
        y = y + ROW_HEIGHT + ROW_GAP

        -- Egg count
        state.eggCountLabel = createLabel(container, "EggCount", y, "Eggs: 0", Color3.fromRGB(255, 220, 100), Enum.Font.GothamBold)
        y = y + ROW_HEIGHT + PADDING

        -- Size container to fit content
        container.Size = UDim2.new(0, CONTAINER_WIDTH, 0, y)

        state.screenGui = screenGui
    end

    return {
        name = "QueenHUD",
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
            onQueenStatus = function(self, data)
                if not data then return end

                local state = getState(self)

                -- Energy bar
                if state.energyFill and data.energy and data.energyCap and data.energyCap > 0 then
                    local pct = math.clamp(data.energy / data.energyCap, 0, 1)
                    state.energyFill.Size = UDim2.new(pct, 0, 1, 0)

                    -- Color: green when healthy, yellow mid, red low
                    if pct > 0.5 then
                        state.energyFill.BackgroundColor3 = Color3.fromRGB(80, 200, 80)
                    elseif pct > 0.25 then
                        state.energyFill.BackgroundColor3 = Color3.fromRGB(220, 180, 40)
                    else
                        state.energyFill.BackgroundColor3 = Color3.fromRGB(220, 60, 40)
                    end
                end

                -- Energy numeric
                if state.energyLabel and data.energy and data.energyCap then
                    state.energyLabel.Text = string.format("Energy: %d/%d", data.energy, data.energyCap)
                end

                -- Bite countdown
                if state.biteLabel and data.biteCounter and data.biteRate then
                    state.biteLabel.Text = string.format("Bite: %d/%d", data.biteCounter, data.biteRate)
                end

                -- Egg progress
                if state.eggProgressLabel then
                    if data.gestating then
                        state.eggProgressLabel.Text = string.format("Egg: %d/%d", data.eggCounter, data.eggInterval)
                        state.eggProgressLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
                    else
                        state.eggProgressLabel.Text = "Egg: STARVING"
                        state.eggProgressLabel.TextColor3 = Color3.fromRGB(220, 60, 40)
                    end
                end

                -- Egg count
                if state.eggCountLabel and data.eggCount then
                    state.eggCountLabel.Text = "Eggs: " .. tostring(data.eggCount)
                end

                -- Starvation warning
                if data.starvationTicks and data.starvationThreshold then
                    if data.starvationTicks > 0 then
                        if state.energyLabel then
                            state.energyLabel.Text = string.format("STARVING %d/%d",
                                data.starvationTicks, data.starvationThreshold)
                            state.energyLabel.TextColor3 = Color3.fromRGB(220, 60, 40)
                        end
                    else
                        if state.energyLabel then
                            state.energyLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
                        end
                    end
                end

                -- Dead
                if data.alive == false then
                    if state.energyLabel then
                        state.energyLabel.Text = "DEAD"
                        state.energyLabel.TextColor3 = Color3.fromRGB(255, 0, 0)
                    end
                end
            end,
        },

        Out = {},
    }
end)

return QueenHUD
