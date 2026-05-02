--[[
    Ant Colony Simulation — GameClock
    Server-side compressed game clock node.

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    Drives time-dependent mechanics (egg hatching, queen laying, food
    consumption, ant lifecycle) via a compressed game clock.
    Default: 1 real second = 1 game hour.

    Time math uses os.clock() delta tracking so the clock stays accurate
    even when Roblox overshoots task.wait() intervals.

    ============================================================================
    TIME REFERENCE (at defaults)
    ============================================================================

    | Real time    | Game time |
    |--------------|-----------|
    | 1 second     | 1 hour   |
    | 24 seconds   | 1 day    |
    | 1 minute     | 2.5 days |

    ============================================================================
    SIGNALS
    ============================================================================

    IN (receives):
        onConfigure({ realSecondsPerGameHour?, tickIntervalSeconds? })
            - Reconfigure time scale and/or tick interval at runtime

        onPause()
            - Pause time advancement

        onResume()
            - Resume time advancement without time jump

        onSetTime({ day?, hour?, minute? })
            - Hard override of the current game time

    OUT (sends):
        tick({ gameDay, gameHour, gameMinute, totalGameHours, isPaused })
            - Fires every tickIntervalSeconds with current game time

        hourChanged({ gameHour, previousHour, gameDay, totalGameHours })
            - Fires on hour transition

        dayChanged({ gameDay, previousDay, gameHour, totalGameHours })
            - Fires on day transition

--]]

local Warren = require(game:GetService("ReplicatedStorage").Warren)
local Node = Warren.Node

--------------------------------------------------------------------------------
-- DEFAULTS
--------------------------------------------------------------------------------

local DEFAULT_REAL_SECONDS_PER_GAME_HOUR = 1
local MIN_REAL_SECONDS_PER_GAME_HOUR = 0.01

local DEFAULT_TICK_INTERVAL = 1
local MIN_TICK_INTERVAL = 0.1

--------------------------------------------------------------------------------
-- GAMECLOCK NODE
--------------------------------------------------------------------------------

local GameClock = Node.extend(function(parent)
    local instanceStates = {}

    local function getState(self)
        if not instanceStates[self.id] then
            instanceStates[self.id] = {
                -- Configuration
                realSecondsPerGameHour = DEFAULT_REAL_SECONDS_PER_GAME_HOUR,
                tickIntervalSeconds = DEFAULT_TICK_INTERVAL,

                -- Time state
                totalGameHours = 0,
                isPaused = false,

                -- Delta tracking
                lastClockTime = nil,

                -- Derived (cached for change detection)
                lastGameDay = 1,
                lastGameHour = 0,

                -- Tick loop thread
                tickThread = nil,
            }
        end
        return instanceStates[self.id]
    end

    local function cleanupState(self)
        local state = instanceStates[self.id]
        if state then
            if state.tickThread then
                task.cancel(state.tickThread)
                state.tickThread = nil
            end
        end
        instanceStates[self.id] = nil
    end

    --------------------------------------------------------------------------
    -- TIME DERIVATION
    --------------------------------------------------------------------------

    local function deriveTime(totalGameHours)
        -- Day 1 starts at hour 0. Each 24-hour period increments the day.
        local gameDay = math.floor(totalGameHours / 24) + 1
        local gameHour = math.floor(totalGameHours % 24)
        local fractionalHour = totalGameHours % 1
        local gameMinute = math.floor(fractionalHour * 60) % 60
        return gameDay, gameHour, gameMinute
    end

    --------------------------------------------------------------------------
    -- TICK LOOP
    --------------------------------------------------------------------------

    local function startTickLoop(self)
        local state = getState(self)

        -- Cancel existing tick thread if any
        if state.tickThread then
            task.cancel(state.tickThread)
            state.tickThread = nil
        end

        state.lastClockTime = os.clock()

        state.tickThread = task.spawn(function()
            while true do
                task.wait(state.tickIntervalSeconds)

                local now = os.clock()
                local realDelta = now - state.lastClockTime
                state.lastClockTime = now

                -- Advance game time if not paused
                if not state.isPaused then
                    local gameHoursElapsed = realDelta / state.realSecondsPerGameHour
                    local previousTotalHours = state.totalGameHours
                    state.totalGameHours = state.totalGameHours + gameHoursElapsed

                    -- Derive current time
                    local gameDay, gameHour, gameMinute = deriveTime(state.totalGameHours)
                    local previousDay, previousHour = state.lastGameDay, state.lastGameHour

                    -- Check for hour transition
                    if gameHour ~= previousHour then
                        self.Out:Fire("hourChanged", {
                            gameHour = gameHour,
                            previousHour = previousHour,
                            gameDay = gameDay,
                            totalGameHours = state.totalGameHours,
                        })
                    end

                    -- Check for day transition
                    if gameDay ~= previousDay then
                        self.Out:Fire("dayChanged", {
                            gameDay = gameDay,
                            previousDay = previousDay,
                            gameHour = gameHour,
                            totalGameHours = state.totalGameHours,
                        })
                    end

                    -- Update cached derived values
                    state.lastGameDay = gameDay
                    state.lastGameHour = gameHour
                end

                -- Fire tick every interval regardless of pause state
                local gameDay, gameHour, gameMinute = deriveTime(state.totalGameHours)
                self.Out:Fire("tick", {
                    gameDay = gameDay,
                    gameHour = gameHour,
                    gameMinute = gameMinute,
                    totalGameHours = state.totalGameHours,
                    isPaused = state.isPaused,
                })
            end
        end)
    end

    --------------------------------------------------------------------------
    -- PUBLIC INTERFACE
    --------------------------------------------------------------------------

    return {
        name = "GameClock",
        domain = "server",

        Sys = {
            onInit = function(self) end,

            onStart = function(self)
                startTickLoop(self)

                local System = self._System
                if System and System.Debug then
                    local state = getState(self)
                    System.Debug.info("GameClock", "Started — 1 real second = "
                        .. state.realSecondsPerGameHour .. "s per game hour")
                end
            end,

            onStop = function(self)
                cleanupState(self)
            end,
        },

        In = {
            onConfigure = function(self, data)
                if not data then return end
                local state = getState(self)

                if data.realSecondsPerGameHour then
                    state.realSecondsPerGameHour = math.max(
                        MIN_REAL_SECONDS_PER_GAME_HOUR,
                        data.realSecondsPerGameHour
                    )
                end

                if data.tickIntervalSeconds then
                    state.tickIntervalSeconds = math.max(
                        MIN_TICK_INTERVAL,
                        data.tickIntervalSeconds
                    )
                end

                local System = self._System
                if System and System.Debug then
                    System.Debug.info("GameClock", string.format(
                        "Reconfigured — %.2fs/game-hour, %.2fs tick interval",
                        state.realSecondsPerGameHour,
                        state.tickIntervalSeconds
                    ))
                end

                -- Restart tick loop to pick up new interval
                if state.tickThread then
                    startTickLoop(self)
                end
            end,

            onPause = function(self)
                local state = getState(self)
                if state.isPaused then return end
                state.isPaused = true

                local System = self._System
                if System and System.Debug then
                    local gameDay, gameHour, gameMinute = deriveTime(state.totalGameHours)
                    System.Debug.info("GameClock", string.format(
                        "Paused at day %d, %02d:%02d",
                        gameDay, gameHour, gameMinute
                    ))
                end
            end,

            onResume = function(self)
                local state = getState(self)
                if not state.isPaused then return end
                state.isPaused = false

                -- Reset clock reference so pause duration is not counted
                state.lastClockTime = os.clock()

                local System = self._System
                if System and System.Debug then
                    local gameDay, gameHour, gameMinute = deriveTime(state.totalGameHours)
                    System.Debug.info("GameClock", string.format(
                        "Resumed at day %d, %02d:%02d",
                        gameDay, gameHour, gameMinute
                    ))
                end
            end,

            onSetTime = function(self, data)
                if not data then return end
                local state = getState(self)

                -- Derive current time as baseline
                local currentDay, currentHour, currentMinute = deriveTime(state.totalGameHours)

                local newDay = data.day or currentDay
                local newHour = data.hour or currentHour
                local newMinute = data.minute or currentMinute

                -- Reconstruct totalGameHours from components
                local previousTotalHours = state.totalGameHours
                state.totalGameHours = (newDay - 1) * 24 + newHour + newMinute / 60

                -- Update cached derived values
                local gameDay, gameHour, gameMinute = deriveTime(state.totalGameHours)
                local previousDay = state.lastGameDay
                local previousHour = state.lastGameHour
                state.lastGameDay = gameDay
                state.lastGameHour = gameHour

                -- Fire transitions if the jump crossed boundaries
                if gameHour ~= previousHour then
                    self.Out:Fire("hourChanged", {
                        gameHour = gameHour,
                        previousHour = previousHour,
                        gameDay = gameDay,
                        totalGameHours = state.totalGameHours,
                    })
                end

                if gameDay ~= previousDay then
                    self.Out:Fire("dayChanged", {
                        gameDay = gameDay,
                        previousDay = previousDay,
                        gameHour = gameHour,
                        totalGameHours = state.totalGameHours,
                    })
                end

                -- Reset clock reference to prevent jump accumulation
                state.lastClockTime = os.clock()

                local System = self._System
                if System and System.Debug then
                    System.Debug.info("GameClock", string.format(
                        "Time set to day %d, %02d:%02d (%.2f total hours)",
                        gameDay, gameHour, gameMinute, state.totalGameHours
                    ))
                end
            end,
        },

        Out = {
            tick = {},
            hourChanged = {},
            dayChanged = {},
        },
    }
end)

return GameClock
