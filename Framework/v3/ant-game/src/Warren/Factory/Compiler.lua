--[[
    Warren Framework v2
    Factory/Compiler.lua - Geometry Optimization

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    Compiles Factory geometry by merging parts into unions.
    Reduces draw calls while preserving visual appearance and registry.
--]]

local Compiler = {}

-- Services
local GeometryService = game:GetService("GeometryService")

--------------------------------------------------------------------------------
-- CONSTANTS
--------------------------------------------------------------------------------

-- Triangle estimates per shape type
local TRIANGLE_COUNTS = {
    Block = 12,
    Ball = 128,      -- Sphere approximation
    Cylinder = 32,
    Wedge = 8,
}

-- Safe triangle limit (buffer below 20K hard limit)
local MAX_TRIANGLES_PER_UNION = 15000

-- Collision fidelity mapping
local COLLISION_FIDELITY = {
    Hull = Enum.CollisionFidelity.Hull,
    Box = Enum.CollisionFidelity.Box,
    Precise = Enum.CollisionFidelity.PreciseConvexDecomposition,
    Default = Enum.CollisionFidelity.Default,
}

--------------------------------------------------------------------------------
-- HELPERS
--------------------------------------------------------------------------------

--[[
    Generate a grouping key for a part based on strategy.
    Parts with the same key can be unioned together.
--]]
local function getGroupKey(part, strategy)
    local material = tostring(part.Material)
    local transparency = math.floor(part.Transparency * 100) -- Round to avoid float issues
    local canCollide = part.CanCollide and "1" or "0"

    if strategy == "class" then
        -- Group by FactoryClass attribute (safest, semantically meaningful)
        local class = part:GetAttribute("FactoryClass") or "unclassed"
        return string.format("%s|%s", class, canCollide)
    elseif strategy == "aggressive" then
        -- Group by material + transparency only (colors will be lost)
        return string.format("%s|%d|%s", material, transparency, canCollide)
    else
        -- Default "material" strategy: include color
        local color = string.format("%d,%d,%d",
            math.floor(part.Color.R * 255),
            math.floor(part.Color.G * 255),
            math.floor(part.Color.B * 255)
        )
        return string.format("%s|%s|%d|%s", material, color, transparency, canCollide)
    end
end

--[[
    Get grid cell key for spatial grouping.
--]]
local function getSpatialKey(part, chunkSize)
    local pos = part.Position
    local cx = math.floor(pos.X / chunkSize)
    local cy = math.floor(pos.Y / chunkSize)
    local cz = math.floor(pos.Z / chunkSize)
    return string.format("%d,%d,%d", cx, cy, cz)
end

--[[
    Estimate triangle count for a part.
--]]
local function estimatePartTriangles(part)
    if part:IsA("WedgePart") then
        return TRIANGLE_COUNTS.Wedge
    elseif part:IsA("Part") then
        local shape = part.Shape
        if shape == Enum.PartType.Block then
            return TRIANGLE_COUNTS.Block
        elseif shape == Enum.PartType.Ball then
            return TRIANGLE_COUNTS.Ball
        elseif shape == Enum.PartType.Cylinder then
            return TRIANGLE_COUNTS.Cylinder
        end
    elseif part:IsA("UnionOperation") or part:IsA("PartOperation") then
        -- Already a union, estimate based on size
        local volume = part.Size.X * part.Size.Y * part.Size.Z
        return math.min(500, math.floor(volume / 10))
    end
    return TRIANGLE_COUNTS.Block -- Default fallback
end

--[[
    Estimate total triangles for a group of parts.
--]]
function Compiler.estimateTriangles(parts)
    local total = 0
    for _, part in ipairs(parts) do
        total = total + estimatePartTriangles(part)
    end
    return total
end

--------------------------------------------------------------------------------
-- GROUPING
--------------------------------------------------------------------------------

--[[
    Group parts by compile key based on strategy.

    @param container: Parent Part containing geometry
    @param strategy: "material" | "aggressive" | "spatial"
    @param options: { chunkSize = number }
    @return: { [key] = { parts = {Part}, material, color, transparency, canCollide } }
--]]
function Compiler.groupParts(container, strategy, options)
    options = options or {}
    local chunkSize = options.chunkSize or 50
    local includeClasses = options.includeClasses  -- nil means all classes

    local groups = {}

    for _, child in ipairs(container:GetChildren()) do
        -- Skip non-geometry
        if not (child:IsA("BasePart") or child:IsA("PartOperation")) then
            continue
        end

        -- Skip transparent container (it's the bounding box)
        if child.Transparency >= 1 then
            continue
        end

        -- Skip WedgeParts - UnionAsync doesn't handle them well
        if child:IsA("WedgePart") then
            continue
        end

        -- Filter by class if specified
        if includeClasses then
            local partClass = child:GetAttribute("FactoryClass")
            local included = false
            for _, c in ipairs(includeClasses) do
                if partClass == c then
                    included = true
                    break
                end
            end
            if not included then
                continue
            end
        end

        -- Build group key
        local key = getGroupKey(child, strategy)

        -- Add spatial prefix for spatial strategy
        if strategy == "spatial" then
            local spatialKey = getSpatialKey(child, chunkSize)
            key = spatialKey .. "|" .. key
        end

        -- Initialize group if needed
        if not groups[key] then
            groups[key] = {
                parts = {},
                material = child.Material,
                color = child.Color,
                transparency = child.Transparency,
                canCollide = child.CanCollide,
            }
        end

        table.insert(groups[key].parts, child)
    end

    return groups
end

--------------------------------------------------------------------------------
-- CHUNKING
--------------------------------------------------------------------------------

--[[
    Split a group into chunks that fit within triangle limit.

    @param group: { parts = {Part}, ... }
    @param maxTriangles: Maximum triangles per chunk
    @return: Array of chunk groups
--]]
function Compiler.chunkGroup(group, maxTriangles)
    maxTriangles = maxTriangles or MAX_TRIANGLES_PER_UNION

    local chunks = {}
    local currentChunk = {
        parts = {},
        material = group.material,
        color = group.color,
        transparency = group.transparency,
        canCollide = group.canCollide,
        triangles = 0,
    }

    for _, part in ipairs(group.parts) do
        local partTriangles = estimatePartTriangles(part)

        -- Start new chunk if this part would exceed limit
        if currentChunk.triangles + partTriangles > maxTriangles and #currentChunk.parts > 0 then
            table.insert(chunks, currentChunk)
            currentChunk = {
                parts = {},
                material = group.material,
                color = group.color,
                transparency = group.transparency,
                canCollide = group.canCollide,
                triangles = 0,
            }
        end

        table.insert(currentChunk.parts, part)
        currentChunk.triangles = currentChunk.triangles + partTriangles
    end

    -- Add final chunk
    if #currentChunk.parts > 0 then
        table.insert(chunks, currentChunk)
    end

    return chunks
end

--------------------------------------------------------------------------------
-- UNION OPERATIONS
--------------------------------------------------------------------------------

--[[
    Union a group of parts into a single PartOperation.

    @param group: { parts = {Part}, material, color, transparency, canCollide }
    @param options: { collisionFidelity = string }
    @return: PartOperation or nil if failed
--]]
function Compiler.unionGroup(group, options)
    options = options or {}
    local parts = group.parts

    -- Need at least 2 parts to union
    if #parts < 2 then
        return nil
    end

    -- Get collision fidelity
    local fidelity = COLLISION_FIDELITY[options.collisionFidelity] or COLLISION_FIDELITY.Hull

    -- Collect part IDs for attribution
    local partIds = {}
    for _, part in ipairs(parts) do
        local id = part:GetAttribute("FactoryId")
        if id then
            table.insert(partIds, id)
        end
    end

    -- Attempt union
    local success, result = pcall(function()
        return GeometryService:UnionAsync(parts, {
            CollisionFidelity = fidelity,
            RenderFidelity = Enum.RenderFidelity.Precise,
            SplitApart = false,
        })
    end)

    if not success then
        warn("[Factory.Compiler] UnionAsync failed:", result)
        return nil
    end

    -- UnionAsync returns an array, get first result
    local union = result[1]
    if not union then
        warn("[Factory.Compiler] UnionAsync returned empty result")
        return nil
    end

    -- Apply properties
    union.Material = group.material
    union.Color = group.color
    union.Transparency = group.transparency
    union.CanCollide = group.canCollide
    union.Anchored = true

    -- Store original part IDs as attribute
    if #partIds > 0 then
        union:SetAttribute("FactoryCompiledIds", table.concat(partIds, ","))
    end
    union:SetAttribute("FactoryCompiled", true)

    return union
end

--------------------------------------------------------------------------------
-- MAIN COMPILE FUNCTION
--------------------------------------------------------------------------------

--[[
    Compile a container's geometry by merging parts into unions.

    @param container: Part container from Factory.geometry()
    @param options: {
        strategy = "class" | "material" | "aggressive" | "spatial",
        chunkSize = number (for spatial),
        preserveRegistry = boolean,
        collisionFidelity = "Hull" | "Box" | "Precise",
        dryRun = boolean,
    }
    @return: Stats table {
        originalParts = number,
        compiledUnions = number,
        ungroupedParts = number,
        triangleEstimate = number,
        groups = table (if dryRun),
    }

    Strategies:
    - "class": Group by FactoryClass attribute. Safest and most semantic.
    - "material": Group by Material + Color + Transparency. Preserves appearance.
    - "aggressive": Group by Material + Transparency only. Maximum compression.
    - "spatial": Grid-based chunking + material. Good for streaming/LOD.
--]]
function Compiler.compile(container, options)
    options = options or {}
    local strategy = options.strategy or "material"
    local preserveRegistry = options.preserveRegistry ~= false
    local dryRun = options.dryRun or false

    -- Stats tracking
    local stats = {
        originalParts = 0,
        compiledUnions = 0,
        ungroupedParts = 0,
        triangleEstimate = 0,
        groups = {},
    }

    -- Count original parts (excluding wedges which can't be unioned)
    local skippedWedges = 0
    for _, child in ipairs(container:GetChildren()) do
        if child:IsA("BasePart") or child:IsA("PartOperation") then
            if child.Transparency < 1 then -- Skip container bounding box
                if child:IsA("WedgePart") then
                    skippedWedges = skippedWedges + 1
                else
                    stats.originalParts = stats.originalParts + 1
                end
            end
        end
    end
    stats.skippedWedges = skippedWedges

    -- Group parts
    local groups = Compiler.groupParts(container, strategy, options)

    -- Process each group
    local unionsToCreate = {}
    local partsToRemove = {}

    for key, group in pairs(groups) do
        local triangles = Compiler.estimateTriangles(group.parts)
        stats.triangleEstimate = stats.triangleEstimate + triangles

        -- Store group info for stats
        table.insert(stats.groups, {
            key = key,
            partCount = #group.parts,
            triangles = triangles,
        })

        -- Skip single-part groups (nothing to union)
        if #group.parts < 2 then
            stats.ungroupedParts = stats.ungroupedParts + 1
            continue
        end

        -- Chunk if needed
        local chunks = Compiler.chunkGroup(group, MAX_TRIANGLES_PER_UNION)

        for _, chunk in ipairs(chunks) do
            if #chunk.parts < 2 then
                stats.ungroupedParts = stats.ungroupedParts + 1
            else
                table.insert(unionsToCreate, {
                    chunk = chunk,
                    options = options,
                })

                -- Mark parts for removal
                for _, part in ipairs(chunk.parts) do
                    table.insert(partsToRemove, part)
                end

                stats.compiledUnions = stats.compiledUnions + 1
            end
        end
    end

    -- If dry run, return stats without modifying
    if dryRun then
        return stats
    end

    -- Get reference to Geometry module for registry updates
    local Geometry = require(script.Parent.Geometry)

    -- Create unions and update registry
    for _, unionData in ipairs(unionsToCreate) do
        local union = Compiler.unionGroup(unionData.chunk, unionData.options)

        if union then
            union.Parent = container

            -- Update registry entries if preserving
            if preserveRegistry then
                for _, part in ipairs(unionData.chunk.parts) do
                    local id = part:GetAttribute("FactoryId")
                    if id then
                        Geometry.updateInstance(id, union, true)
                    end
                end
            end
        else
            -- Union failed, keep original parts
            stats.compiledUnions = stats.compiledUnions - 1
            for i = #partsToRemove, 1, -1 do
                for _, part in ipairs(unionData.chunk.parts) do
                    if partsToRemove[i] == part then
                        table.remove(partsToRemove, i)
                        break
                    end
                end
            end
        end
    end

    -- Remove original parts that were successfully unioned
    for _, part in ipairs(partsToRemove) do
        part:Destroy()
    end

    return stats
end

return Compiler
