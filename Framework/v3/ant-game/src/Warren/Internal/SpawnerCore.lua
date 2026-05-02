--[[
    Warren Framework v2
    SpawnerCore.lua - Internal Spawn Mechanics Module

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    Internal utility module for spawning and tracking game instances.
    Used by Hatcher, Dropper, Dispenser, and other spawning components.

    This module handles:
    - Template lookup and cloning
    - Unique asset ID assignment
    - Instance tracking for garbage collection
    - Cleanup and despawn operations

    NOT a Node - pure utility module used via composition.

    ============================================================================
    USAGE
    ============================================================================

    ```lua
    local SpawnerCore = require(path.to.Internal.SpawnerCore)

    -- Initialize with template sources
    SpawnerCore.init({
        templates = game.ReplicatedStorage.Templates,
    })

    -- Spawn an instance
    local result = SpawnerCore.spawn({
        templateName = "CommonPet",
        parent = workspace.Pets,
        position = Vector3.new(0, 5, 0),
        attributes = { Rarity = "Common" },
    })
    -- result = { instance = Model, assetId = "spawn_1" }

    -- Later, despawn it
    SpawnerCore.despawn(result.assetId)
    ```

--]]

local SpawnerCore = {}

--------------------------------------------------------------------------------
-- STATE
--------------------------------------------------------------------------------

local _initialized = false
local _templateSources = {}  -- Array of Folder instances to search for templates
local _spawnedInstances = {} -- { [assetId] = { instance: Instance, metadata: table } }
local _nextAssetId = 1
local _assetIdPrefix = "spawn_"

--------------------------------------------------------------------------------
-- INITIALIZATION
--------------------------------------------------------------------------------

function SpawnerCore.init(config)
    config = config or {}

    -- Template sources (folders to search for templates)
    if config.templates then
        if typeof(config.templates) == "Instance" then
            _templateSources = { config.templates }
        elseif typeof(config.templates) == "table" then
            _templateSources = config.templates
        end
    end

    -- Custom asset ID prefix
    if config.assetIdPrefix then
        _assetIdPrefix = config.assetIdPrefix
    end

    _initialized = true
end

function SpawnerCore.isInitialized()
    return _initialized
end

--------------------------------------------------------------------------------
-- TEMPLATE RESOLUTION
--------------------------------------------------------------------------------

function SpawnerCore.resolveTemplate(templateName)
    if not templateName then
        return nil, "Template name is required"
    end

    -- Search through template sources in order
    for _, source in ipairs(_templateSources) do
        local template = source:FindFirstChild(templateName)
        if template then
            return template
        end

        -- Also check nested folders (one level deep)
        for _, child in ipairs(source:GetChildren()) do
            if child:IsA("Folder") then
                local nested = child:FindFirstChild(templateName)
                if nested then
                    return nested
                end
            end
        end
    end

    -- Fallback: check ReplicatedStorage.Templates directly
    local replicatedStorage = game:GetService("ReplicatedStorage")
    local defaultTemplates = replicatedStorage:FindFirstChild("Templates")
    if defaultTemplates then
        local template = defaultTemplates:FindFirstChild(templateName)
        if template then
            return template
        end
    end

    return nil, string.format("Template '%s' not found", templateName)
end

--------------------------------------------------------------------------------
-- ASSET ID GENERATION
--------------------------------------------------------------------------------

local function generateAssetId()
    local id = _assetIdPrefix .. tostring(_nextAssetId)
    _nextAssetId = _nextAssetId + 1
    return id
end

--------------------------------------------------------------------------------
-- SPAWN
--------------------------------------------------------------------------------

function SpawnerCore.spawn(config)
    config = config or {}

    -- Validate required fields
    if not config.templateName and not config.template then
        return nil, "Either templateName or template is required"
    end

    -- Resolve template
    local template = config.template
    if not template then
        local err
        template, err = SpawnerCore.resolveTemplate(config.templateName)
        if not template then
            return nil, err
        end
    end

    -- Clone the template
    local instance = template:Clone()

    -- Generate asset ID
    local assetId = config.assetId or generateAssetId()
    instance.Name = config.name or assetId

    -- Set asset ID attribute
    instance:SetAttribute("AssetId", assetId)

    -- Apply additional attributes
    if config.attributes then
        for key, value in pairs(config.attributes) do
            instance:SetAttribute(key, value)
        end
    end

    -- Position the instance
    if config.position then
        if instance:IsA("Model") then
            if instance.PrimaryPart then
                instance:PivotTo(CFrame.new(config.position))
            else
                -- Try to find a suitable part to position
                local rootPart = instance:FindFirstChild("HumanoidRootPart")
                    or instance:FindFirstChildWhichIsA("BasePart")
                if rootPart then
                    local offset = rootPart.Position - instance:GetBoundingBox().Position
                    instance:PivotTo(CFrame.new(config.position + offset))
                end
            end
        elseif instance:IsA("BasePart") then
            instance.Position = config.position
        end
    end

    -- Apply CFrame if provided (overrides position)
    if config.cframe then
        if instance:IsA("Model") then
            instance:PivotTo(config.cframe)
        elseif instance:IsA("BasePart") then
            instance.CFrame = config.cframe
        end
    end

    -- Parent the instance
    if config.parent then
        instance.Parent = config.parent
    end

    -- Track the instance
    _spawnedInstances[assetId] = {
        instance = instance,
        templateName = config.templateName or template.Name,
        spawnTime = os.clock(),
        metadata = config.metadata or {},
    }

    return {
        instance = instance,
        assetId = assetId,
    }
end

--------------------------------------------------------------------------------
-- DESPAWN
--------------------------------------------------------------------------------

function SpawnerCore.despawn(assetId)
    local record = _spawnedInstances[assetId]
    if not record then
        return false, string.format("No instance found with assetId '%s'", assetId)
    end

    -- Destroy the instance
    if record.instance and record.instance.Parent then
        record.instance:Destroy()
    end

    -- Remove from tracking
    _spawnedInstances[assetId] = nil

    return true
end

--------------------------------------------------------------------------------
-- BATCH DESPAWN
--------------------------------------------------------------------------------

--[[
    Despawn multiple instances from a list.

    Accepts an array of:
    - assetId strings (direct lookup)
    - Node objects (extracts AssetId from node.model)
    - Roblox Instances (extracts AssetId attribute)

    Designed to work with Node.Registry.query() results:

    ```lua
    -- Despawn all Campers spawned by Tent_1
    local campers = Node.Registry.query({ class = "Camper", spawnSource = "Tent_1" })
    SpawnerCore.despawnAll(campers)

    -- Or with direct assetIds
    SpawnerCore.despawnAll({ "spawn_1", "spawn_2", "spawn_3" })
    ```

    @param items table - Array of assetIds, Nodes, or Instances
    @return number - Count of successfully despawned instances
--]]
function SpawnerCore.despawnAll(items)
    if not items or #items == 0 then
        return 0
    end

    local count = 0

    for _, item in ipairs(items) do
        local assetId = nil

        -- Determine assetId from item type
        if type(item) == "string" then
            -- Direct assetId string
            assetId = item
        elseif type(item) == "table" and item.model then
            -- Node object - get AssetId from model
            if typeof(item.model) == "Instance" then
                assetId = item.model:GetAttribute("AssetId")
            end
        elseif typeof(item) == "Instance" then
            -- Roblox Instance - get AssetId attribute
            assetId = item:GetAttribute("AssetId")
        end

        -- Despawn if we found an assetId
        if assetId and SpawnerCore.despawn(assetId) then
            count = count + 1
        end
    end

    return count
end

--[[
    Get assetId from a Node or Instance.

    @param item table|Instance - Node object or Roblox Instance
    @return string? - The assetId, or nil if not found
--]]
function SpawnerCore.getAssetId(item)
    if type(item) == "string" then
        return item
    elseif type(item) == "table" and item.model then
        if typeof(item.model) == "Instance" then
            return item.model:GetAttribute("AssetId")
        end
    elseif typeof(item) == "Instance" then
        return item:GetAttribute("AssetId")
    end
    return nil
end

--[[
    Check if an instance is tracked by SpawnerCore.

    @param item string|table|Instance - assetId, Node, or Instance
    @return boolean - True if tracked
--]]
function SpawnerCore.isTracked(item)
    local assetId = SpawnerCore.getAssetId(item)
    return assetId ~= nil and _spawnedInstances[assetId] ~= nil
end

--------------------------------------------------------------------------------
-- INSTANCE ACCESS
--------------------------------------------------------------------------------

function SpawnerCore.getInstance(assetId)
    local record = _spawnedInstances[assetId]
    return record and record.instance
end

function SpawnerCore.getRecord(assetId)
    return _spawnedInstances[assetId]
end

function SpawnerCore.getAllInstances()
    local instances = {}
    for assetId, record in pairs(_spawnedInstances) do
        instances[assetId] = record.instance
    end
    return instances
end

function SpawnerCore.getInstanceCount()
    local count = 0
    for _ in pairs(_spawnedInstances) do
        count = count + 1
    end
    return count
end

--------------------------------------------------------------------------------
-- CLEANUP
--------------------------------------------------------------------------------

function SpawnerCore.cleanup()
    for assetId, record in pairs(_spawnedInstances) do
        if record.instance and record.instance.Parent then
            record.instance:Destroy()
        end
    end
    _spawnedInstances = {}
end

function SpawnerCore.reset()
    SpawnerCore.cleanup()
    _nextAssetId = 1
    _templateSources = {}
    _initialized = false
end

--------------------------------------------------------------------------------
-- ITERATION
--------------------------------------------------------------------------------

function SpawnerCore.forEach(callback)
    for assetId, record in pairs(_spawnedInstances) do
        callback(assetId, record.instance, record)
    end
end

--------------------------------------------------------------------------------
-- TEMPLATE SOURCE MANAGEMENT
--------------------------------------------------------------------------------

function SpawnerCore.addTemplateSource(folder)
    if typeof(folder) == "Instance" and folder:IsA("Folder") then
        table.insert(_templateSources, folder)
        return true
    end
    return false
end

function SpawnerCore.getTemplateSources()
    return _templateSources
end

return SpawnerCore
