--[[
    Warren Framework v2
    PathFollowerCore.lua - Shared Path Infrastructure

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    Internal utility module providing shared path management for:
    - PathedController (active entity movement)
    - PathedConveyor (physics-based conveyor)

    This module handles:
    - Waypoint storage and validation
    - Segment management (pairs of waypoints)
    - Per-segment speed configuration
    - Direction and distance calculations
    - Path traversal helpers

    NOT a Node - pure utility class used via composition.

    ============================================================================
    USAGE
    ============================================================================

    ```lua
    local PathFollowerCore = require(path.to.Internal.PathFollowerCore)

    -- Create a path instance
    local path = PathFollowerCore.new()

    -- Set waypoints (Parts or Vector3s)
    path:setWaypoints({ part1, part2, part3 })

    -- Configure per-segment speeds
    path:setSegmentSpeed(1, 20)  -- Segment 1 at 20 studs/sec
    path:setSegmentSpeed(2, 10)  -- Segment 2 at 10 studs/sec

    -- Or set all segments at once
    path:setAllSpeeds(15)

    -- Query path info
    local dir = path:getDirection(1)      -- Direction vector for segment 1
    local len = path:getSegmentLength(1)  -- Length of segment 1
    local total = path:getTotalLength()   -- Total path length
    local pos = path:getWaypointPosition(1)  -- Position of waypoint 1
    ```

--]]

local PathFollowerCore = {}
PathFollowerCore.__index = PathFollowerCore

--------------------------------------------------------------------------------
-- CONSTRUCTOR
--------------------------------------------------------------------------------

function PathFollowerCore.new(config)
    config = config or {}

    local self = setmetatable({}, PathFollowerCore)

    -- Waypoint storage
    self._waypoints = {}           -- Array of Parts or Vector3s
    self._waypointPositions = {}   -- Cached Vector3 positions

    -- Segment configuration
    self._segmentSpeeds = {}       -- { [segmentIndex] = speed }
    self._defaultSpeed = config.defaultSpeed or 16

    -- Traversal state
    self._currentIndex = 0
    self._direction = 1            -- 1 = forward, -1 = reverse

    return self
end

--------------------------------------------------------------------------------
-- WAYPOINT MANAGEMENT
--------------------------------------------------------------------------------

--[[
    Set the waypoints for this path.

    @param waypoints table - Array of Parts or Vector3s
    @return boolean, string? - Success and optional error message
--]]
function PathFollowerCore:setWaypoints(waypoints)
    if not waypoints or type(waypoints) ~= "table" then
        return false, "Waypoints must be a table"
    end

    if #waypoints < 2 then
        return false, "Path requires at least 2 waypoints"
    end

    self._waypoints = waypoints
    self._waypointPositions = {}
    self._segmentSpeeds = {}
    self._currentIndex = 0

    -- Cache positions
    for i, wp in ipairs(waypoints) do
        self._waypointPositions[i] = self:_resolvePosition(wp)
    end

    return true
end

--[[
    Get the waypoints array.

    @return table - Array of waypoints
--]]
function PathFollowerCore:getWaypoints()
    return self._waypoints
end

--[[
    Get the number of waypoints.

    @return number
--]]
function PathFollowerCore:getWaypointCount()
    return #self._waypoints
end

--[[
    Get the number of segments (waypoints - 1).

    @return number
--]]
function PathFollowerCore:getSegmentCount()
    return math.max(0, #self._waypoints - 1)
end

--[[
    Get a specific waypoint.

    @param index number - 1-based waypoint index
    @return Part|Vector3|nil
--]]
function PathFollowerCore:getWaypoint(index)
    return self._waypoints[index]
end

--[[
    Get the position of a waypoint.

    @param index number - 1-based waypoint index
    @return Vector3|nil
--]]
function PathFollowerCore:getWaypointPosition(index)
    if self._waypointPositions[index] then
        return self._waypointPositions[index]
    end

    local wp = self._waypoints[index]
    if wp then
        return self:_resolvePosition(wp)
    end

    return nil
end

--------------------------------------------------------------------------------
-- SEGMENT SPEED MANAGEMENT
--------------------------------------------------------------------------------

--[[
    Set the speed for a specific segment.

    @param segmentIndex number - 1-based segment index
    @param speed number - Speed in studs/second
--]]
function PathFollowerCore:setSegmentSpeed(segmentIndex, speed)
    if segmentIndex >= 1 and segmentIndex <= self:getSegmentCount() then
        self._segmentSpeeds[segmentIndex] = speed
    end
end

--[[
    Set speed for multiple segments at once.

    @param segments table - Array of { segment = index, speed = value }
--]]
function PathFollowerCore:setSegmentSpeeds(segments)
    for _, config in ipairs(segments) do
        if config.segment and config.speed then
            self:setSegmentSpeed(config.segment, config.speed)
        end
    end
end

--[[
    Set the same speed for all segments.

    @param speed number - Speed in studs/second
--]]
function PathFollowerCore:setAllSpeeds(speed)
    self._defaultSpeed = speed
    self._segmentSpeeds = {}  -- Clear per-segment overrides
end

--[[
    Get the speed for a specific segment.

    @param segmentIndex number - 1-based segment index
    @return number - Speed in studs/second
--]]
function PathFollowerCore:getSegmentSpeed(segmentIndex)
    return self._segmentSpeeds[segmentIndex] or self._defaultSpeed
end

--[[
    Set the default speed (used when no per-segment speed is set).

    @param speed number - Speed in studs/second
--]]
function PathFollowerCore:setDefaultSpeed(speed)
    self._defaultSpeed = speed
end

--[[
    Get the default speed.

    @return number
--]]
function PathFollowerCore:getDefaultSpeed()
    return self._defaultSpeed
end

--------------------------------------------------------------------------------
-- DIRECTION & DISTANCE CALCULATIONS
--------------------------------------------------------------------------------

--[[
    Get the direction vector for a segment.
    Returns normalized direction from waypoint[index] to waypoint[index+1].

    @param segmentIndex number - 1-based segment index
    @return Vector3|nil - Normalized direction vector
--]]
function PathFollowerCore:getDirection(segmentIndex)
    local startPos = self:getWaypointPosition(segmentIndex)
    local endPos = self:getWaypointPosition(segmentIndex + 1)

    if not startPos or not endPos then
        return nil
    end

    local delta = endPos - startPos
    local magnitude = delta.Magnitude

    if magnitude > 0 then
        return delta / magnitude  -- Normalized
    end

    return Vector3.new(0, 0, 0)
end

--[[
    Get the direction vector for a segment, respecting current traversal direction.

    @param segmentIndex number - 1-based segment index
    @return Vector3|nil - Normalized direction vector (negated if reverse)
--]]
function PathFollowerCore:getTraversalDirection(segmentIndex)
    local dir = self:getDirection(segmentIndex)
    if dir and self._direction == -1 then
        return -dir
    end
    return dir
end

--[[
    Get the length of a specific segment.

    @param segmentIndex number - 1-based segment index
    @return number - Length in studs
--]]
function PathFollowerCore:getSegmentLength(segmentIndex)
    local startPos = self:getWaypointPosition(segmentIndex)
    local endPos = self:getWaypointPosition(segmentIndex + 1)

    if not startPos or not endPos then
        return 0
    end

    return (endPos - startPos).Magnitude
end

--[[
    Get the total length of the path.

    @return number - Total length in studs
--]]
function PathFollowerCore:getTotalLength()
    local total = 0
    for i = 1, self:getSegmentCount() do
        total = total + self:getSegmentLength(i)
    end
    return total
end

--[[
    Get the duration to traverse a segment at its configured speed.

    @param segmentIndex number - 1-based segment index
    @return number - Duration in seconds
--]]
function PathFollowerCore:getSegmentDuration(segmentIndex)
    local length = self:getSegmentLength(segmentIndex)
    local speed = self:getSegmentSpeed(segmentIndex)

    if speed > 0 then
        return length / speed
    end

    return 0
end

--[[
    Get the total duration to traverse the entire path.

    @return number - Duration in seconds
--]]
function PathFollowerCore:getTotalDuration()
    local total = 0
    for i = 1, self:getSegmentCount() do
        total = total + self:getSegmentDuration(i)
    end
    return total
end

--------------------------------------------------------------------------------
-- TRAVERSAL STATE
--------------------------------------------------------------------------------

--[[
    Set the current waypoint index (for tracking progress).

    @param index number - 1-based waypoint index
--]]
function PathFollowerCore:setCurrentIndex(index)
    self._currentIndex = index
end

--[[
    Get the current waypoint index.

    @return number
--]]
function PathFollowerCore:getCurrentIndex()
    return self._currentIndex
end

--[[
    Get the current segment index (the segment we're traversing toward).

    @return number - 1-based segment index, or 0 if not started
--]]
function PathFollowerCore:getCurrentSegment()
    if self._currentIndex <= 0 then
        return 0
    end
    return math.min(self._currentIndex, self:getSegmentCount())
end

--[[
    Set the traversal direction.

    @param forward boolean - true for forward, false for reverse
--]]
function PathFollowerCore:setDirection(forward)
    self._direction = forward and 1 or -1
end

--[[
    Get the traversal direction.

    @return number - 1 for forward, -1 for reverse
--]]
function PathFollowerCore:getDirectionMultiplier()
    return self._direction
end

--[[
    Check if traversing forward.

    @return boolean
--]]
function PathFollowerCore:isForward()
    return self._direction == 1
end

--[[
    Reverse the traversal direction.
--]]
function PathFollowerCore:reverse()
    self._direction = -self._direction
end

--[[
    Reset traversal state to beginning.
--]]
function PathFollowerCore:reset()
    self._currentIndex = 0
end

--------------------------------------------------------------------------------
-- POSITION QUERIES
--------------------------------------------------------------------------------

--[[
    Find which segment a position is closest to.
    Returns segment index and the closest point on that segment.

    @param position Vector3 - Position to check
    @return number, Vector3, number - Segment index, closest point, distance to segment
--]]
function PathFollowerCore:findClosestSegment(position)
    local closestSegment = 1
    local closestPoint = self:getWaypointPosition(1) or Vector3.new(0, 0, 0)
    local closestDistance = math.huge

    for i = 1, self:getSegmentCount() do
        local startPos = self:getWaypointPosition(i)
        local endPos = self:getWaypointPosition(i + 1)

        if startPos and endPos then
            local point, dist = self:_closestPointOnSegment(position, startPos, endPos)
            if dist < closestDistance then
                closestDistance = dist
                closestPoint = point
                closestSegment = i
            end
        end
    end

    return closestSegment, closestPoint, closestDistance
end

--[[
    Get the progress along a segment (0 to 1) for a position.

    @param position Vector3 - Position to check
    @param segmentIndex number - Segment to check against
    @return number - Progress from 0 (start) to 1 (end)
--]]
function PathFollowerCore:getProgressOnSegment(position, segmentIndex)
    local startPos = self:getWaypointPosition(segmentIndex)
    local endPos = self:getWaypointPosition(segmentIndex + 1)

    if not startPos or not endPos then
        return 0
    end

    local segmentVector = endPos - startPos
    local positionVector = position - startPos

    local segmentLength = segmentVector.Magnitude
    if segmentLength == 0 then
        return 0
    end

    local projection = positionVector:Dot(segmentVector.Unit)
    return math.clamp(projection / segmentLength, 0, 1)
end

--------------------------------------------------------------------------------
-- PRIVATE HELPERS
--------------------------------------------------------------------------------

--[[
    Resolve a waypoint to a Vector3 position.

    @param waypoint Part|Vector3 - Waypoint to resolve
    @return Vector3
--]]
function PathFollowerCore:_resolvePosition(waypoint)
    if typeof(waypoint) == "Vector3" then
        return waypoint
    elseif typeof(waypoint) == "Instance" then
        if waypoint:IsA("BasePart") then
            return waypoint.Position
        elseif waypoint:IsA("Model") then
            if waypoint.PrimaryPart then
                return waypoint.PrimaryPart.Position
            else
                local part = waypoint:FindFirstChildWhichIsA("BasePart")
                if part then
                    return part.Position
                end
            end
        end
    end
    return Vector3.new(0, 0, 0)
end

--[[
    Find the closest point on a line segment to a given position.

    @param position Vector3 - Position to check
    @param lineStart Vector3 - Start of segment
    @param lineEnd Vector3 - End of segment
    @return Vector3, number - Closest point and distance to it
--]]
function PathFollowerCore:_closestPointOnSegment(position, lineStart, lineEnd)
    local line = lineEnd - lineStart
    local lineLength = line.Magnitude

    if lineLength == 0 then
        return lineStart, (position - lineStart).Magnitude
    end

    local lineDir = line / lineLength
    local toPosition = position - lineStart
    local projection = toPosition:Dot(lineDir)

    -- Clamp to segment
    projection = math.clamp(projection, 0, lineLength)

    local closestPoint = lineStart + lineDir * projection
    local distance = (position - closestPoint).Magnitude

    return closestPoint, distance
end

return PathFollowerCore
