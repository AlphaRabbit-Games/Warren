--[[
    Ant Colony Simulation — ClassTree
    Worker class progression tree.

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    Data-driven class tree for worker ant specialization. Each node defines
    a class with its command, stat requirements, and rebirth cost.

    Adding new classes = adding rows to CLASSES. No code changes needed.

    Tree structure (Tiers 1-2):

    worker (base, no command)
    ├── explorer (explore)
    │   ├── scout (explore — longer range bonus)
    │   └── tracker (explore — faster travel bonus)
    ├── gatherer (gatherClosest)
    │   ├── forager (gatherClosest — carry bonus)
    │   ├── harvester (gatherLargest)
    │   └── selector (gatherBest)
    └── builder (upgrade)
        ├── digger (dig)
        ├── mason (upgrade — clutch specialist)
        └── stockpiler (upgradePantry)

    ============================================================================
    USAGE
    ============================================================================

    local ClassTree = require(script.Parent.ClassTree)

    local classDef = ClassTree.get("forager")
    local children = ClassTree.getChildren("gatherer")
    local canRebirth = ClassTree.canRebirth(ant, "harvester")

--]]

local ClassTree = {}

--------------------------------------------------------------------------------
-- CLASS DEFINITIONS
--------------------------------------------------------------------------------
-- Each class:
--   id:             unique string identifier
--   name:           display name
--   parent:         parent class id (nil for root)
--   tier:           0 = base, 1 = base classes, 2 = specializations
--   command:        task command this class performs (nil = no command)
--   statReqs:       minimum ant stats to unlock rebirth { endurance = N, ... }
--   rebirthCost:    XP cost to rebirth into this class
--   bonuses:        stat bonuses applied when reborn into this class
--   description:    short description for HUD

local CLASSES = {
    -- Tier 0: base worker (every ant starts here or at a tier 1 class)
    {
        id = "worker",
        name = "Worker",
        parent = nil,
        tier = 0,
        command = nil,
        statReqs = {},
        rebirthCost = 0,
        bonuses = {},
        description = "Unspecialized worker",
    },

    -- Tier 1: base classes
    {
        id = "explorer",
        name = "Explorer",
        parent = "worker",
        tier = 1,
        command = "explore",
        statReqs = {},
        rebirthCost = 2,
        bonuses = { maxRange = 5 },
        description = "Scouts for food sources",
    },
    {
        id = "gatherer",
        name = "Gatherer",
        parent = "worker",
        tier = 1,
        command = "gatherClosest",
        statReqs = {},
        rebirthCost = 2,
        bonuses = {},
        description = "Collects nearest food",
    },
    {
        id = "builder",
        name = "Builder",
        parent = "worker",
        tier = 1,
        command = "upgrade",
        statReqs = {},
        rebirthCost = 2,
        bonuses = {},
        description = "Upgrades clutch capacity",
    },

    -- Tier 2: Explorer specializations
    {
        id = "scout",
        name = "Scout",
        parent = "explorer",
        tier = 2,
        command = "explore",
        statReqs = { maxRange = 40 },
        rebirthCost = 5,
        bonuses = { maxRange = 15 },
        description = "Extended range explorer",
    },
    {
        id = "tracker",
        name = "Tracker",
        parent = "explorer",
        tier = 2,
        command = "explore",
        statReqs = { energyCap = 80 },
        rebirthCost = 5,
        bonuses = { metabolismRate = -0.2 },
        description = "Energy-efficient explorer",
    },

    -- Tier 2: Gatherer specializations
    {
        id = "forager",
        name = "Forager",
        parent = "gatherer",
        tier = 2,
        command = "gatherClosest",
        statReqs = { energyCap = 80 },
        rebirthCost = 5,
        bonuses = { energyCap = 20 },
        description = "Carries more per trip",
    },
    {
        id = "harvester",
        name = "Harvester",
        parent = "gatherer",
        tier = 2,
        command = "gatherLargest",
        statReqs = { maxRange = 40 },
        rebirthCost = 5,
        bonuses = { maxRange = 10 },
        description = "Targets largest piles",
    },
    {
        id = "selector",
        name = "Selector",
        parent = "gatherer",
        tier = 2,
        command = "gatherBest",
        statReqs = { maxRange = 50, energyCap = 90 },
        rebirthCost = 8,
        bonuses = { maxRange = 5, energyCap = 10 },
        description = "Targets richest food",
    },

    -- Tier 2: Builder specializations
    {
        id = "digger",
        name = "Digger",
        parent = "builder",
        tier = 2,
        command = "dig",
        statReqs = { energyCap = 80 },
        rebirthCost = 5,
        bonuses = { energyCap = 15 },
        description = "Digs new tunnels",
    },
    {
        id = "mason",
        name = "Mason",
        parent = "builder",
        tier = 2,
        command = "upgrade",
        statReqs = { energyCap = 70 },
        rebirthCost = 5,
        bonuses = { metabolismRate = -0.15 },
        description = "Efficient clutch builder",
    },
    {
        id = "stockpiler",
        name = "Stockpiler",
        parent = "builder",
        tier = 2,
        command = "upgradePantry",
        statReqs = { energyCap = 70 },
        rebirthCost = 5,
        bonuses = { metabolismRate = -0.15 },
        description = "Pantry expansion expert",
    },
}

--------------------------------------------------------------------------------
-- INDEX BUILDING
--------------------------------------------------------------------------------

local byId = {}
local childrenOf = {}

for _, cls in ipairs(CLASSES) do
    byId[cls.id] = cls
    if cls.parent then
        childrenOf[cls.parent] = childrenOf[cls.parent] or {}
        childrenOf[cls.parent][#childrenOf[cls.parent] + 1] = cls
    end
end

--------------------------------------------------------------------------------
-- PUBLIC API
--------------------------------------------------------------------------------

-- Get a class definition by id
function ClassTree.get(classId)
    return byId[classId]
end

-- Get all children of a class
function ClassTree.getChildren(classId)
    return childrenOf[classId] or {}
end

-- Get the tier 1 ancestor of any class (explorer/gatherer/builder)
function ClassTree.getBaseClass(classId)
    local cls = byId[classId]
    while cls and cls.tier > 1 do
        cls = byId[cls.parent]
    end
    return cls
end

-- Check if an ant meets the stat requirements for rebirth
function ClassTree.canRebirth(ant, targetClassId)
    local cls = byId[targetClassId]
    if not cls then return false, "Unknown class" end

    -- Must be a child of the ant's current class
    local parentCls = byId[cls.parent]
    if not parentCls then return false, "No parent class" end
    if ant.classId ~= cls.parent then
        return false, "Must be " .. parentCls.name .. " first"
    end

    -- Check stat requirements
    for stat, minVal in pairs(cls.statReqs) do
        local antVal = 0
        if stat == "maxRange" then antVal = ant.baseMaxRange or 0
        elseif stat == "energyCap" then antVal = ant.baseEnergyCap or 0
        elseif stat == "metabolismRate" then antVal = ant.baseMetabolismRate or 1
        end

        if stat == "metabolismRate" then
            -- Lower is better for metabolism
            if antVal > minVal then
                return false, string.format("%s too high (%.1f > %.1f)", stat, antVal, minVal)
            end
        else
            if antVal < minVal then
                return false, string.format("%s too low (%d < %d)", stat, antVal, minVal)
            end
        end
    end

    return true, nil
end

-- Get all available rebirth options for an ant
function ClassTree.getRebirthOptions(ant)
    local children = childrenOf[ant.classId] or {}
    local options = {}
    for _, cls in ipairs(children) do
        local canDo, reason = ClassTree.canRebirth(ant, cls.id)
        options[#options + 1] = {
            id = cls.id,
            name = cls.name,
            description = cls.description,
            tier = cls.tier,
            command = cls.command,
            rebirthCost = cls.rebirthCost,
            statReqs = cls.statReqs,
            bonuses = cls.bonuses,
            available = canDo,
            reason = reason,
        }
    end
    return options
end

-- Get all tier 1 classes (for class reassignment)
function ClassTree.getTier1Classes()
    local result = {}
    for _, cls in ipairs(CLASSES) do
        if cls.tier == 1 then
            result[#result + 1] = cls
        end
    end
    return result
end

-- Get the command for a class
function ClassTree.getCommand(classId)
    local cls = byId[classId]
    return cls and cls.command or nil
end

return ClassTree
