--[[
    Ant Colony Simulation — FoodSourceHUD
    Client-side discovered food sources display.

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    Displays discovered food sources on the right side below the clutch HUD.
    Shows type, energy per gather, remaining pile size, and distance.

    ============================================================================
    SIGNALS
    ============================================================================

    IN (receives):
        onFoodSourceStatus({ discovered, undiscoveredCount })

--]]

local Players = game:GetService("Players")

local Warren = require(game:GetService("ReplicatedStorage").Warren)
local Node = Warren.Node

--------------------------------------------------------------------------------
-- FOOD SOURCE HUD NODE
--------------------------------------------------------------------------------

local FoodSourceHUD = Node.extend(function(parent)
    local instanceStates = {}

    local function getState(self)
        if not instanceStates[self.id] then
            instanceStates[self.id] = {
                screenGui = nil,
                container = nil,
                listFrame = nil,
                sourceRows = {},
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
    local ROW_HEIGHT = 38
    local ROW_GAP = 2
    local CONTAINER_WIDTH = 140
    local LIST_HEIGHT = 180

    local TYPE_COLORS = {
        crumb = Color3.fromRGB(160, 140, 100),
        seed = Color3.fromRGB(140, 180, 80),
        insect = Color3.fromRGB(180, 100, 100),
        fruit = Color3.fromRGB(200, 140, 60),
        honeydew = Color3.fromRGB(220, 200, 60),
    }

    local TYPE_BUFFS = {
        crumb    = "Eff:50%",
        seed     = "End:40%",
        insect   = "All:30%",
        fruit    = "Egg:20%",
        honeydew = "—",
    }

    local function createUI(self)
        local state = getState(self)
        local player = Players.LocalPlayer
        if not player then return end

        local playerGui = player:WaitForChild("PlayerGui")

        if state.screenGui then
            state.screenGui:Destroy()
        end
        local existing = playerGui:FindFirstChild("FoodSourceHUD")
        if existing then
            existing:Destroy()
        end

        local screenGui = Instance.new("ScreenGui")
        screenGui.Name = "FoodSourceHUD"
        screenGui.ResetOnSpawn = false
        screenGui.DisplayOrder = 10
        screenGui.Parent = playerGui

        -- Position below ClutchHUD
        local container = Instance.new("Frame")
        container.Name = "Container"
        container.AnchorPoint = Vector2.new(1, 0)
        container.Position = UDim2.new(1, -10, 0, 296)
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
        title.Text = "FOOD SOURCES"
        title.TextColor3 = Color3.fromRGB(200, 180, 100)
        title.TextSize = 12
        title.Font = Enum.Font.GothamBold
        title.TextXAlignment = Enum.TextXAlignment.Right
        title.Parent = container
        y = y + 16 + ROW_GAP

        -- Undiscovered count
        local undiscLabel = Instance.new("TextLabel")
        undiscLabel.Name = "UndiscoveredLabel"
        undiscLabel.Size = UDim2.new(1, -PADDING * 2, 0, 14)
        undiscLabel.Position = UDim2.new(0, PADDING, 0, y)
        undiscLabel.BackgroundTransparency = 1
        undiscLabel.Text = "Undiscovered: ?"
        undiscLabel.TextColor3 = Color3.fromRGB(120, 120, 120)
        undiscLabel.TextSize = 11
        undiscLabel.Font = Enum.Font.Gotham
        undiscLabel.TextXAlignment = Enum.TextXAlignment.Right
        undiscLabel.Parent = container
        y = y + 14 + PADDING

        -- Scrolling list
        local listFrame = Instance.new("ScrollingFrame")
        listFrame.Name = "SourceList"
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

    local function renderSources(self, discovered, undiscoveredCount)
        local state = getState(self)
        if not state.listFrame then return end

        -- Update undiscovered label
        local undiscLabel = state.container and state.container:FindFirstChild("UndiscoveredLabel")
        if undiscLabel then
            undiscLabel.Text = string.format("Undiscovered: %d", undiscoveredCount)
        end

        -- Clear existing rows
        for _, row in pairs(state.sourceRows) do
            row:Destroy()
        end
        state.sourceRows = {}

        if #discovered == 0 then
            -- Empty state
            local emptyLabel = Instance.new("TextLabel")
            emptyLabel.Name = "Empty"
            emptyLabel.Size = UDim2.new(1, -4, 0, 20)
            emptyLabel.Position = UDim2.new(0, 2, 0, 4)
            emptyLabel.BackgroundTransparency = 1
            emptyLabel.Text = "None found yet"
            emptyLabel.TextColor3 = Color3.fromRGB(100, 100, 100)
            emptyLabel.TextSize = 10
            emptyLabel.Font = Enum.Font.Gotham
            emptyLabel.TextXAlignment = Enum.TextXAlignment.Center
            emptyLabel.Parent = state.listFrame
            state.sourceRows[0] = emptyLabel
            state.listFrame.CanvasSize = UDim2.new(0, 0, 0, 28)
            return
        end

        local y = 2
        for _, s in ipairs(discovered) do
            local row = Instance.new("Frame")
            row.Name = "Source_" .. s.id
            row.Size = UDim2.new(1, -4, 0, ROW_HEIGHT)
            row.Position = UDim2.new(0, 2, 0, y)
            row.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
            row.BackgroundTransparency = 0.3
            row.BorderSizePixel = 0
            row.Parent = state.listFrame

            local rowCorner = Instance.new("UICorner")
            rowCorner.CornerRadius = UDim.new(0, 3)
            rowCorner.Parent = row

            -- Type name
            local typeLabel = Instance.new("TextLabel")
            typeLabel.Name = "Type"
            typeLabel.Size = UDim2.new(1, -6, 0, 12)
            typeLabel.Position = UDim2.new(0, 4, 0, 2)
            typeLabel.BackgroundTransparency = 1
            typeLabel.Text = s.type:upper()
            typeLabel.TextColor3 = TYPE_COLORS[s.type] or Color3.fromRGB(200, 200, 200)
            typeLabel.TextSize = 10
            typeLabel.Font = Enum.Font.GothamBold
            typeLabel.TextXAlignment = Enum.TextXAlignment.Left
            typeLabel.Parent = row

            -- Stats line (energy, pile size, distance)
            local statsLabel = Instance.new("TextLabel")
            statsLabel.Name = "Stats"
            statsLabel.Size = UDim2.new(1, -6, 0, 10)
            statsLabel.Position = UDim2.new(0, 4, 0, 14)
            statsLabel.BackgroundTransparency = 1
            statsLabel.Text = string.format("E:%d  x%d  D:%d",
                s.energyPerGather, s.remaining, s.distance)
            statsLabel.TextColor3 = Color3.fromRGB(160, 160, 160)
            statsLabel.TextSize = 9
            statsLabel.Font = Enum.Font.Gotham
            statsLabel.TextXAlignment = Enum.TextXAlignment.Left
            statsLabel.Parent = row

            -- Buff line
            local buffLabel = Instance.new("TextLabel")
            buffLabel.Name = "Buff"
            buffLabel.Size = UDim2.new(1, -6, 0, 10)
            buffLabel.Position = UDim2.new(0, 4, 0, 25)
            buffLabel.BackgroundTransparency = 1
            buffLabel.Text = "Buff: " .. (TYPE_BUFFS[s.type] or "—")
            buffLabel.TextColor3 = Color3.fromRGB(120, 200, 160)
            buffLabel.TextSize = 9
            buffLabel.Font = Enum.Font.Gotham
            buffLabel.TextXAlignment = Enum.TextXAlignment.Left
            buffLabel.Parent = row

            state.sourceRows[s.id] = row
            y = y + ROW_HEIGHT + ROW_GAP
        end

        state.listFrame.CanvasSize = UDim2.new(0, 0, 0, y)
    end

    return {
        name = "FoodSourceHUD",
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
            onFoodSourceStatus = function(self, data)
                if not data then return end
                renderSources(self, data.discovered or {}, data.undiscoveredCount or 0)
            end,
        },

        Out = {},
    }
end)

return FoodSourceHUD
