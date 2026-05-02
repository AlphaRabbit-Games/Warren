--[[
    Warren Framework v2
    EntityUtils.lua - Shared Entity Helper Functions

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    Common utility functions for working with entities (Models, Parts).
    Used by Zone, Checkpoint, PathedConveyor, and other detection components.
--]]

local CollectionService = game:GetService("CollectionService")

local EntityUtils = {}

--[[
    Get the entity (Model or Part) from a part.
    If the part is inside a Model, returns the Model.
    Otherwise returns the part itself.

    @param part BasePart - The part to get entity from
    @return Model|BasePart|nil
--]]
function EntityUtils.getEntityFromPart(part)
    -- If part is in a Model, return the Model
    local model = part:FindFirstAncestorOfClass("Model")
    if model and model ~= workspace then
        return model
    end
    -- Otherwise return the part itself
    return part
end

--[[
    Get the position of an entity.

    @param entity Model|BasePart - The entity
    @return Vector3
--]]
function EntityUtils.getPosition(entity)
    if entity:IsA("Model") then
        if entity.PrimaryPart then
            return entity.PrimaryPart.Position
        else
            local part = entity:FindFirstChildWhichIsA("BasePart")
            if part then
                return part.Position
            end
        end
    elseif entity:IsA("BasePart") then
        return entity.Position
    end
    return Vector3.new(0, 0, 0)
end

--[[
    Get the primary part of an entity for physics operations.

    @param entity Model|BasePart - The entity
    @return BasePart|nil
--]]
function EntityUtils.getPrimaryPart(entity)
    if entity:IsA("Model") then
        return entity.PrimaryPart or entity:FindFirstChildWhichIsA("BasePart")
    elseif entity:IsA("BasePart") then
        return entity
    end
    return nil
end

--[[
    Get an ID for an entity.
    Checks NodeId attribute, then AssetId attribute, then Name.

    @param entity Instance - The entity
    @return string
--]]
function EntityUtils.getId(entity)
    return entity:GetAttribute("NodeId")
        or entity:GetAttribute("AssetId")
        or entity.Name
end

--[[
    Check if an entity passes a filter.
    Supports standard filter schema with class, tag, spawnSource, and custom.

    @param entity Instance - The entity to check
    @param filter table|nil - The filter configuration
    @return boolean
--]]
function EntityUtils.passesFilter(entity, filter)
    if not filter then
        return true
    end

    -- Class filter
    if filter.class then
        local entityClass = entity:GetAttribute("NodeClass") or entity.Name
        if entityClass ~= filter.class then
            return false
        end
    end

    -- Tag filter
    if filter.tag then
        if not CollectionService:HasTag(entity, filter.tag) then
            return false
        end
    end

    -- SpawnSource filter
    if filter.spawnSource then
        local source = entity:GetAttribute("SpawnSource")
        if source ~= filter.spawnSource then
            return false
        end
    end

    -- Custom filter function
    if filter.custom and type(filter.custom) == "function" then
        if not filter.custom(entity) then
            return false
        end
    end

    return true
end

--[[
    Check if an entity is a player character.

    @param entity Instance - The entity to check
    @return boolean
--]]
function EntityUtils.isPlayer(entity)
    if entity:IsA("Model") then
        local humanoid = entity:FindFirstChildOfClass("Humanoid")
        if humanoid then
            local Players = game:GetService("Players")
            local player = Players:GetPlayerFromCharacter(entity)
            return player ~= nil
        end
    end
    return false
end

return EntityUtils
