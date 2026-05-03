--[[
    Ant Colony Simulation — XPHUD
    Client-side XP and queen attribute display.

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    Shows XP pool and queen attributes. Player clicks attribute buttons
    to spend XP and level up.

    ============================================================================
    SIGNALS
    ============================================================================

    IN (receives):
        onXpStatus({ xp, totalXpEarned, attributes })

    OUT (sends):
        spendXP({ attribute })

--]]

local Players = game:GetService("Players")

local Warren = require(game:GetService("ReplicatedStorage").Warren)
local Node = Warren.Node

--------------------------------------------------------------------------------
-- XP HUD NODE
--------------------------------------------------------------------------------

local XPHUD = Node.extend(function(parent)
    local instanceStates = {}

    local function getState(self)
        if not instanceStates[self.id] then
            instanceStates[self.id] = {
                screenGui = nil,
                container = nil,
                xpLabel = nil,
                attrButtons = {},
                lastData = nil,
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
    local ROW_HEIGHT = 28
    local ROW_GAP = 3
    local CONTAINER_WIDTH = 160

    local ATTR_COLORS = {
        eggRate = Color3.fromRGB(180, 120, 60),
        eggEfficiency = Color3.fromRGB(180, 160, 60),
        hatchEndurance = Color3.fromRGB(60, 140, 140),
        hatchEfficiency = Color3.fromRGB(100, 180, 80),
    }

    local ATTR_ORDER = { "eggRate", "eggEfficiency", "hatchEndurance", "hatchEfficiency" }

    local function createUI(self)
        local state = getState(self)
        local player = Players.LocalPlayer
        if not player then return end

        local playerGui = player:WaitForChild("PlayerGui")

        if state.screenGui then
            state.screenGui:Destroy()
        end
        local existing = playerGui:FindFirstChild("XPHUD")
        if existing then
            existing:Destroy()
        end

        local screenGui = Instance.new("ScreenGui")
        screenGui.Name = "XPHUD"
        screenGui.ResetOnSpawn = false
        screenGui.DisplayOrder = 10
        screenGui.Parent = playerGui

        -- Bottom-right, above chat
        local container = Instance.new("Frame")
        container.Name = "Container"
        container.AnchorPoint = Vector2.new(1, 1)
        container.Position = UDim2.new(1, -10, 1, -10)
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
        title.Text = "QUEEN XP"
        title.TextColor3 = Color3.fromRGB(255, 220, 100)
        title.TextSize = 12
        title.Font = Enum.Font.GothamBold
        title.TextXAlignment = Enum.TextXAlignment.Right
        title.Parent = container
        y = y + 16 + ROW_GAP

        -- XP counter
        local xpLabel = Instance.new("TextLabel")
        xpLabel.Name = "XPLabel"
        xpLabel.Size = UDim2.new(1, -PADDING * 2, 0, 14)
        xpLabel.Position = UDim2.new(0, PADDING, 0, y)
        xpLabel.BackgroundTransparency = 1
        xpLabel.Text = "XP: 0"
        xpLabel.TextColor3 = Color3.fromRGB(255, 220, 100)
        xpLabel.TextSize = 13
        xpLabel.Font = Enum.Font.GothamBold
        xpLabel.TextXAlignment = Enum.TextXAlignment.Right
        xpLabel.Parent = container
        state.xpLabel = xpLabel
        y = y + 14 + PADDING

        -- Attribute buttons
        for _, attr in ipairs(ATTR_ORDER) do
            local btn = Instance.new("TextButton")
            btn.Name = "Attr_" .. attr
            btn.Size = UDim2.new(1, -PADDING * 2, 0, ROW_HEIGHT)
            btn.Position = UDim2.new(0, PADDING, 0, y)
            btn.BackgroundColor3 = ATTR_COLORS[attr] or Color3.fromRGB(80, 80, 80)
            btn.BackgroundTransparency = 0.4
            btn.BorderSizePixel = 0
            btn.Text = attr
            btn.TextColor3 = Color3.fromRGB(255, 255, 255)
            btn.TextSize = 10
            btn.Font = Enum.Font.GothamBold
            btn.TextWrapped = true
            btn.Parent = container

            local btnCorner = Instance.new("UICorner")
            btnCorner.CornerRadius = UDim.new(0, 4)
            btnCorner.Parent = btn

            local attrName = attr
            btn.MouseButton1Click:Connect(function()
                self.Out:Fire("spendXP", { attribute = attrName })
            end)

            state.attrButtons[attr] = btn
            y = y + ROW_HEIGHT + ROW_GAP
        end

        y = y + PADDING - ROW_GAP
        container.Size = UDim2.new(0, CONTAINER_WIDTH, 0, y)
        state.container = container
        state.screenGui = screenGui
    end

    local function renderAttributes(self, data)
        local state = getState(self)
        if not data or not data.attributes then return end

        if state.xpLabel then
            state.xpLabel.Text = "XP: " .. tostring(data.xp or 0)
        end

        for _, attr in ipairs(ATTR_ORDER) do
            local btn = state.attrButtons[attr]
            local info = data.attributes[attr]
            if btn and info then
                -- Build stat preview string
                local statParts = {}
                if info.currentValues then
                    for stat, val in pairs(info.currentValues) do
                        local nextVal = info.nextValues and info.nextValues[stat]
                        local shortName = stat
                            :gsub("eggInterval", "Int")
                            :gsub("eggEnergyCost", "Cost")
                            :gsub("maxRange", "Rng")
                            :gsub("energyCap", "Cap")
                            :gsub("metabolismRate", "Met")
                        if nextVal and nextVal ~= val then
                            statParts[#statParts + 1] = string.format("%s:%s→%s",
                                shortName,
                                tostring(math.floor(val * 10) / 10),
                                tostring(math.floor(nextVal * 10) / 10))
                        else
                            statParts[#statParts + 1] = string.format("%s:%s",
                                shortName, tostring(math.floor(val * 10) / 10))
                        end
                    end
                end
                local statsStr = table.concat(statParts, " ")

                local costStr = info.canAfford
                    and string.format("[%d XP]", info.cost)
                    or string.format("(%d XP)", info.cost)
                btn.Text = string.format("%s Lv%d %s\n%s",
                    info.label, info.level, costStr, statsStr)
                btn.BackgroundTransparency = info.canAfford and 0.3 or 0.7
            end
        end
    end

    return {
        name = "XPHUD",
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
            onXpStatus = function(self, data)
                if not data then return end
                local state = getState(self)
                state.lastData = data
                renderAttributes(self, data)
            end,
        },

        Out = {
            spendXP = {},
        },
    }
end)

return XPHUD
