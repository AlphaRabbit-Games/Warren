--[[
    IGW v2 Pipeline — PassageNode
    Creates door assemblies (frame + sliding panels) in door holes.
    Manages blocked/open state per door.

    Pipeline signal: onSpawnPassages(payload) — reads payload.doors, clones
    a frame model from ReplicatedStorage.Assets and creates two sliding
    door panels per door hole.

    Door types (determined by door.type in payload, default "auto"):
      auto          — green, opens automatically on player proximity
      keyed         — blue, requires key item selected + interact (E)
      shootThrough  — red, requires weapon item selected + interact (E)
      destructible  — orange, requires bomb item selected + interact (E)

    Each door is a runtime DoorInstance with:
    - blocked/open state
    - canResolve(interaction) → boolean
    - resolve(interaction) → opens the door if canResolve passes
    - open() / close() — direct state control (panels slide apart/together)
    - autoClose support (seconds until re-close, 0 = stays open)
    - onStateChanged callback registration

    Room orchestrator owns placement — this node reads door positions
    from payload.doors (computed by DoorPlanner).
--]]

local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Capture module reference for requiring BackpackStub at runtime
local _components = script.Parent.Parent

--------------------------------------------------------------------------------
-- FRAME TEMPLATE CACHE
--------------------------------------------------------------------------------

local _frameTemplate = nil
local _frameTemplateName = nil

local function getFrameTemplate(modelName)
    if not modelName then return nil end
    if modelName == _frameTemplateName then return _frameTemplate end

    local assets = ReplicatedStorage:FindFirstChild("Assets")
    if not assets then
        warn("[PassageNode] ReplicatedStorage.Assets not found — frame skipped")
        return nil
    end
    local template = assets:FindFirstChild(modelName)
    if not template then
        warn("[PassageNode] Frame model not found: " .. modelName)
        return nil
    end

    _frameTemplate = template
    _frameTemplateName = modelName
    return template
end

--------------------------------------------------------------------------------
-- DOOR TYPE PROFILES
--------------------------------------------------------------------------------

local DOOR_TYPES = {
    auto = {
        color = BrickColor.new("Dark stone grey"),
        proximityOpen = true,
        requiredItem = nil,
    },
    keyed = {
        color = BrickColor.new("Sand blue"),
        proximityOpen = false,
        requiredItem = "key",
        promptText = "Unlock",
        consumeItem = true,
    },
    shootThrough = {
        color = BrickColor.new("Rust"),
        proximityOpen = false,
        requiredItem = "weapon",
        promptText = "Break",
        consumeItem = false,
    },
    destructible = {
        color = BrickColor.new("Deep orange"),
        proximityOpen = false,
        requiredItem = "bomb",
        promptText = "Destroy",
        consumeItem = true,
    },
}

--------------------------------------------------------------------------------
-- DOOR INSTANCE — runtime state for a single door
--------------------------------------------------------------------------------

local DoorInstance = {}
DoorInstance.__index = DoorInstance

local _registry = {}  -- doorId → DoorInstance

function DoorInstance.new(doorData, config)
    local self = setmetatable({}, DoorInstance)
    self.id = doorData.id
    self.doorData = doorData
    self.doorType = config.doorType or "auto"
    self.state = "blocked"
    self.autoClose = config.autoClose or 0
    self.topPanel = config.topPanel
    self.botPanel = config.botPanel
    self._frame = config.frame
    self._topOrigPos = config.topPanel and config.topPanel.Position
    self._botOrigPos = config.botPanel and config.botPanel.Position
    self._panelHeight = doorData.height / 2
    self._closeThread = nil
    self._callbacks = {}
    self._connections = {}
    self._zone = nil
    _registry[self.id] = self
    return self
end

--- Returns true if this door can be opened by the given interaction.
function DoorInstance:canResolve(interaction)
    local profile = DOOR_TYPES[self.doorType]
    if not profile then return false end
    if profile.proximityOpen then return true end
    if profile.requiredItem then
        return interaction and interaction.item == profile.requiredItem
    end
    return false
end

--- Attempt to open the door via an interaction.
-- Checks canResolve first; does nothing if it returns false.
function DoorInstance:resolve(interaction)
    if self.state ~= "blocked" then return end
    if not self:canResolve(interaction) then return end

    local profile = DOOR_TYPES[self.doorType]
    if profile and profile.consumeItem and interaction and interaction.consume then
        interaction.consume()
    end

    self:open()
end

--- Open the door. Top panel slides up, bottom panel slides down.
function DoorInstance:open()
    if self.state == "open" then return end
    local oldState = self.state
    self.state = "open"

    if self._closeThread then
        task.cancel(self._closeThread)
        self._closeThread = nil
    end

    local slideDist = self._panelHeight
    local tweenInfo = TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

    if self.topPanel then
        local topTarget = self._topOrigPos + Vector3.new(0, slideDist, 0)
        TweenService:Create(self.topPanel, tweenInfo, {
            Position = topTarget,
        }):Play()
    end

    if self.botPanel then
        local botTarget = self._botOrigPos + Vector3.new(0, -slideDist, 0)
        local tween = TweenService:Create(self.botPanel, tweenInfo, {
            Position = botTarget,
        })
        tween:Play()
        tween.Completed:Once(function()
            if self.topPanel then self.topPanel.CanCollide = false end
            if self.botPanel then self.botPanel.CanCollide = false end
        end)
    end

    self:_fireStateChanged(oldState, "open")
end

--- Close the door. Panels slide back together.
function DoorInstance:close()
    if self.state == "blocked" then return end
    local oldState = self.state
    self.state = "blocked"

    -- Clear ref (may be the thread calling us — can't cancel self)
    self._closeThread = nil

    -- Restore collision immediately
    if self.topPanel then self.topPanel.CanCollide = true end
    if self.botPanel then self.botPanel.CanCollide = true end

    local tweenInfo = TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

    if self.topPanel then
        TweenService:Create(self.topPanel, tweenInfo, {
            Position = self._topOrigPos,
        }):Play()
    end

    if self.botPanel then
        TweenService:Create(self.botPanel, tweenInfo, {
            Position = self._botOrigPos,
        }):Play()
    end

    self:_fireStateChanged(oldState, "blocked")
end

--- Register a callback for state changes: callback(oldState, newState, doorInstance)
function DoorInstance:onStateChanged(callback)
    table.insert(self._callbacks, callback)
end

function DoorInstance:_fireStateChanged(oldState, newState)
    for _, cb in ipairs(self._callbacks) do
        task.spawn(cb, oldState, newState, self)
    end
end

function DoorInstance:destroy()
    if self._closeThread then
        task.cancel(self._closeThread)
        self._closeThread = nil
    end
    for _, conn in ipairs(self._connections) do
        conn:Disconnect()
    end
    self._connections = {}
    if self._zone and self._zone.Parent then
        self._zone:Destroy()
    end
    _registry[self.id] = nil
    -- Frame model contains panels — destroying it cleans up everything
    if self._frame and self._frame.Parent then
        self._frame:Destroy()
    end
end

--------------------------------------------------------------------------------
-- PROXIMITY + INTERACTION SETUP
--------------------------------------------------------------------------------

local _backpackStub = nil

local function getBackpackStub()
    if _backpackStub then return _backpackStub end
    local mod = _components:FindFirstChild("Backpack")
    if mod then
        _backpackStub = require(mod)
        _backpackStub.serverInit()
    end
    return _backpackStub
end

--- Create invisible detection zone for auto-open doors.
-- Opens on player enter, schedules close when all players leave.
local function setupProximityZone(doorInst, container)
    local door = doorInst.doorData
    local padding = 10
    local position = Vector3.new(door.center[1], door.center[2], door.center[3])

    local zoneSize
    if door.axis == 2 then
        zoneSize = Vector3.new(door.width + padding, 16, door.height + padding)
    elseif door.widthAxis == 1 then
        zoneSize = Vector3.new(door.width + padding, door.height, 16)
    else
        zoneSize = Vector3.new(16, door.height, door.width + padding)
    end

    local zone = Instance.new("Part")
    zone.Name = "PassageZone_" .. door.id
    zone.Size = zoneSize
    zone.Position = position
    zone.Anchored = true
    zone.CanCollide = false
    zone.Transparency = 1
    zone.CanQuery = false
    zone.Parent = container or workspace
    doorInst._zone = zone

    -- Track which players are inside the zone
    local playersInZone = {}

    local touchConn = zone.Touched:Connect(function(hit)
        local player = Players:GetPlayerFromCharacter(hit.Parent)
        if not player then return end
        playersInZone[player] = true

        -- Cancel pending close
        if doorInst._closeThread then
            task.cancel(doorInst._closeThread)
            doorInst._closeThread = nil
        end

        if doorInst.state == "blocked" then
            doorInst:open()
        end
    end)
    table.insert(doorInst._connections, touchConn)

    local endConn = zone.TouchEnded:Connect(function(hit)
        local player = Players:GetPlayerFromCharacter(hit.Parent)
        if not player then return end
        playersInZone[player] = nil

        -- If no players remain, schedule close
        if doorInst.state == "open" and not next(playersInZone) then
            if doorInst._closeThread then
                task.cancel(doorInst._closeThread)
            end
            doorInst._closeThread = task.delay(doorInst.autoClose, function()
                doorInst:close()
            end)
        end
    end)
    table.insert(doorInst._connections, endConn)
end

--- Create ProximityPrompt for interactive doors (keyed, shoot, bomb)
local function setupProximityPrompt(doorInst)
    local profile = DOOR_TYPES[doorInst.doorType]
    if not profile or not profile.requiredItem then return end

    -- Attach prompt to top panel (visible, reachable)
    local promptParent = doorInst.topPanel or doorInst.botPanel
    if not promptParent then return end

    local prompt = Instance.new("ProximityPrompt")
    prompt.ObjectText = profile.promptText or "Interact"
    prompt.ActionText = profile.promptText or "Interact"
    prompt.MaxActivationDistance = 12
    prompt.HoldDuration = 0
    prompt.RequiresLineOfSight = false
    prompt.KeyboardKeyCode = Enum.KeyCode.E
    prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
    prompt.Parent = promptParent

    local conn = prompt.Triggered:Connect(function(player)
        if doorInst.state ~= "blocked" then return end

        local backpack = getBackpackStub()
        if not backpack then return end

        local selectedItem = backpack.getSelectedItem(player)
        local interaction = {
            player = player,
            item = selectedItem,
            consume = function()
                backpack.consumeItem(player, profile.requiredItem)
            end,
        }

        doorInst:resolve(interaction)
    end)
    table.insert(doorInst._connections, conn)
end

--------------------------------------------------------------------------------
-- PUBLIC API — other nodes access doors via PassageNode.API
--------------------------------------------------------------------------------

local PassageAPI = {}

function PassageAPI.getDoor(doorId)
    return _registry[doorId]
end

function PassageAPI.getAllDoors()
    return _registry
end

function PassageAPI.getDoorCount()
    local count = 0
    for _ in pairs(_registry) do count = count + 1 end
    return count
end

--------------------------------------------------------------------------------
-- PIPELINE NODE
--------------------------------------------------------------------------------

return {
    name = "PassageNode",
    domain = "server",

    API = PassageAPI,
    DoorInstance = DoorInstance,
    DOOR_TYPES = DOOR_TYPES,

    Sys = {
        onInit = function(self) end,
        onStart = function(self) end,
        onStop = function(self)
            for _, door in pairs(_registry) do
                door:destroy()
            end
        end,
    },

    In = {
        onSpawnPassages = function(self, payload)
            local doors = payload.doors or {}
            local wt = self:getAttribute("wallThickness") or 2
            local autoClose = self:getAttribute("autoClose") or 0
            local frameModelName = self:getAttribute("frameModel")
            local frameBorder = self:getAttribute("frameBorder") or 3
            local container = payload.container

            if #doors == 0 then
                print("[PassageNode] No doors to spawn")
                self.Out:Fire("nodeComplete", payload)
                return
            end

            -- Initialize backpack for interactive doors
            getBackpackStub()

            local template = getFrameTemplate(frameModelName)
            local count = 0
            local typeCounts = {}

            for _, door in ipairs(doors) do
                local doorType = door.type or "auto"
                local profile = DOOR_TYPES[doorType] or DOOR_TYPES.auto
                typeCounts[doorType] = (typeCounts[doorType] or 0) + 1

                local depth = wt * 2
                local position = Vector3.new(
                    door.center[1],
                    door.center[2],
                    door.center[3]
                )

                -- Orient based on door axis
                local cf
                if door.axis == 2 then
                    cf = CFrame.new(position) * CFrame.Angles(math.rad(90), 0, 0)
                elseif door.widthAxis == 1 then
                    cf = CFrame.new(position)
                else
                    cf = CFrame.new(position) * CFrame.Angles(0, math.rad(90), 0)
                end

                local outerW = door.width + frameBorder * 2
                local outerH = door.height + frameBorder * 2

                local frameModel = nil
                local topPanel = nil
                local botPanel = nil

                if template and template:IsA("Model") then
                    frameModel = template:Clone()
                    frameModel.Name = "Passage_" .. door.id

                    -- Size and position the frame mesh
                    local doorFrame = frameModel:FindFirstChild("DoorFrame")
                    if doorFrame then
                        doorFrame.Size = Vector3.new(outerW, outerH, depth)
                        doorFrame.CFrame = cf
                        doorFrame.Anchored = true
                        doorFrame.CanCollide = false
                    end

                    -- Remove the panel template from the clone
                    local panelTpl = frameModel:FindFirstChild("DoorPanel")
                    if panelTpl then panelTpl:Destroy() end

                    -- Create two sliding panels from the original template
                    local origPanel = template:FindFirstChild("DoorPanel")
                    if origPanel then
                        local panelH = door.height / 2
                        local panelW = door.width
                        local panelD = origPanel.Size.Z

                        -- Top panel — upper half of opening
                        topPanel = origPanel:Clone()
                        topPanel.Name = "PanelTop"
                        topPanel.Size = Vector3.new(panelW, panelH, panelD)
                        topPanel.CFrame = cf * CFrame.new(0, panelH / 2, 0)
                        topPanel.Anchored = true
                        topPanel.CanCollide = true
                        topPanel.BrickColor = profile.color
                        topPanel.Parent = frameModel

                        -- Bottom panel — mirrored vertically
                        botPanel = origPanel:Clone()
                        botPanel.Name = "PanelBottom"
                        botPanel.Size = Vector3.new(panelW, panelH, panelD)
                        botPanel.CFrame = cf
                            * CFrame.new(0, -panelH / 2, 0)
                            * CFrame.Angles(math.rad(180), 0, 0)
                        botPanel.Anchored = true
                        botPanel.CanCollide = true
                        botPanel.BrickColor = profile.color
                        botPanel.Parent = frameModel
                    end

                    frameModel.Parent = container or workspace
                end

                local doorInst = DoorInstance.new(door, {
                    autoClose = autoClose,
                    doorType = doorType,
                    topPanel = topPanel,
                    botPanel = botPanel,
                    frame = frameModel,
                })

                -- Set up runtime behavior based on type
                if profile.proximityOpen then
                    setupProximityZone(doorInst, container)
                elseif profile.requiredItem then
                    setupProximityPrompt(doorInst)
                end

                count = count + 1
            end

            -- Summary log
            local parts = {}
            for t, c in pairs(typeCounts) do
                table.insert(parts, t .. "=" .. c)
            end
            table.sort(parts)
            print(string.format("[PassageNode] Spawned %d passages (%s) autoClose=%s",
                count, table.concat(parts, " "), tostring(autoClose)))
            self.Out:Fire("nodeComplete", payload)
        end,
    },
}
