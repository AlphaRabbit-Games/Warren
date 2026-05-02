--[[
    Warren Framework v2
    System.lua - Core System Module

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    System is the core module containing all framework subsystems. Each subsystem
    is a nested module with its own public API and closure-protected internals.

    Subsystems:
        - Debug     Console logging and diagnostics
        - Log       Persistent telemetry and analytics
        - IPC       Inter-process communication (events, networking)
        - State     Shared state management
        - Asset     Template registry and spawning (server)
        - Store     Persistent storage (server)
        - View      Presentation layer (client)

    ============================================================================
    USAGE
    ============================================================================

    ```lua
    local Lib = require(game.ReplicatedStorage.Warren)
    local System = Lib.System

    -- Configure debug output
    System.Debug.configure({
        level = "info",
        groups = { Core = { "System.*", "IPC.*" } },
        show = { "@Core" },
    })

    -- Log messages
    System.Debug.info("MyModule", "Hello world")
    ```

    ============================================================================
    DESIGN PRINCIPLES
    ============================================================================

    1. CLOSURE-PROTECTED INTERNALS
       Private state and functions are local variables, inaccessible from outside.
       Only the returned API table is public.

    2. SINGLETON PATTERN
       Each subsystem is initialized once and maintains state across requires.

    3. DECLARATIVE CONFIGURATION
       Subsystems are configured via Lua tables, not imperative method calls.

    4. NO CODE ON LOAD
       Requiring this module does nothing. Bootstrap explicitly initializes.

--]]

local RunService = game:GetService("RunService")

local System = {}

--------------------------------------------------------------------------------
-- CONTEXT DETECTION
--------------------------------------------------------------------------------
-- Captured once at module load for efficient branching throughout subsystems.

System.isServer = RunService:IsServer()
System.isClient = RunService:IsClient()
System.isStudio = RunService:IsStudio()

--------------------------------------------------------------------------------
-- SHARED CONFIG
--------------------------------------------------------------------------------
-- Load shared configuration from ReplicatedFirst. This provides defaults for
-- groups and subsystem settings that both server and client can use.
-- ReplicatedFirst ensures config is available before any other scripts load.

local ReplicatedFirst = game:GetService("ReplicatedFirst")
local Config = require(ReplicatedFirst:WaitForChild("Config"))

--------------------------------------------------------------------------------
-- SHARED GROUPS
--------------------------------------------------------------------------------
-- Groups are defined once and shared across all subsystems (Debug, Log, etc.).
-- Initialized from Config.groups; can be overridden via System.setGroups().

System.groups = Config.groups or {}

function System.setGroups(newGroups)
    System.groups = newGroups or {}
end

--[[
    ============================================================================
    SHARED UTILITIES (used by multiple subsystems)
    ============================================================================

    These pattern-matching utilities are shared between Debug and Log subsystems.
    They're defined at module scope so both closures can reference them.

--]]

local Utils = {}

--[[
    Convert a glob pattern to a Lua pattern.

    Glob syntax:
        *   matches any sequence of characters
        ?   matches any single character (if we want to support it)

    Example:
        "System.*" -> "^System%..*$"
        "*.Tick"   -> "^.*%.Tick$"

    @param glob string - The glob pattern
    @return string - Lua pattern for string.match()
--]]
function Utils.globToPattern(glob)
    -- Escape Lua magic characters except *
    local pattern = glob
        :gsub("([%.%+%-%^%$%(%)%%])", "%%%1")  -- Escape: . + - ^ $ ( ) %
        :gsub("%*", ".*")                       -- Convert * to .*

    -- Anchor the pattern
    return "^" .. pattern .. "$"
end

--[[
    Check if a source matches a pattern (exact match or glob).

    @param source string - The source to test (e.g., "Dropper.Spawn")
    @param pattern string - Pattern to match against (e.g., "Dropper.*")
    @return boolean
--]]
function Utils.matchesPattern(source, pattern)
    -- Exact match
    if source == pattern then
        return true
    end

    -- Glob match (only if pattern contains *)
    if pattern:find("%*") then
        local luaPattern = Utils.globToPattern(pattern)
        return source:match(luaPattern) ~= nil
    end

    return false
end

--[[
    Expand a pattern that might be a @GroupName reference.

    @param pattern string - Pattern or @GroupName
    @param groups table - Groups dictionary to look up
    @return table - Array of patterns (expanded if group, single-element if not)
--]]
function Utils.expandPattern(pattern, groups)
    -- Check for @GroupName syntax
    if pattern:sub(1, 1) == "@" then
        local groupName = pattern:sub(2)
        local group = groups[groupName]
        if group then
            return group
        else
            -- Group not found, return empty
            return {}
        end
    end

    -- Not a group reference, return as single-element array
    return { pattern }
end

--[[
    Check if source matches any pattern in a list.
    Handles @GroupName expansion.

    @param source string - The source to test
    @param patterns table - Array of patterns (may include @GroupName)
    @param groups table - Groups dictionary for @GroupName expansion
    @return boolean
--]]
function Utils.matchesAny(source, patterns, groups)
    for _, pattern in ipairs(patterns) do
        local expanded = Utils.expandPattern(pattern, groups)
        for _, p in ipairs(expanded) do
            if Utils.matchesPattern(source, p) then
                return true
            end
        end
    end
    return false
end

--[[
    Generate a unique session ID.

    Uses a combination of timestamp, random numbers, and place/server info
    to create a reasonably unique identifier.

    @return string - Session ID (e.g., "1704067200-A7F3-B2C1")
--]]
function Utils.generateSessionId()
    local timestamp = os.time()
    local random1 = string.format("%04X", math.random(0, 65535))
    local random2 = string.format("%04X", math.random(0, 65535))
    return string.format("%d-%s-%s", timestamp, random1, random2)
end

--[[
    Deep copy a table (for safe data storage).

    @param t table - Table to copy
    @return table - Deep copy
--]]
function Utils.deepCopy(t)
    if type(t) ~= "table" then
        return t
    end

    local copy = {}
    for k, v in pairs(t) do
        copy[k] = Utils.deepCopy(v)
    end
    return copy
end

--[[
    Merge configuration from source into target.
    Only copies non-nil values from source.

    @param target table - Config table to update
    @param source table - New values to merge in
--]]
function Utils.mergeConfig(target, source)
    for k, v in pairs(source) do
        if v ~= nil then
            target[k] = v
        end
    end
end

--[[
    ============================================================================
    DEBUG SUBSYSTEM
    ============================================================================

    Centralized logging with configurable filtering. Supports:
    - Four log levels: error, warn, info, trace
    - Named groups for toggling related modules together
    - Glob patterns for flexible filtering
    - Solo mode for focused debugging

    CONFIGURATION
    -------------

    ```lua
    -- Define groups once at System level (shared by Debug and Log)
    System.setGroups({
        Spawning = { "Dropper", "ArrayPlacer", "WaveController" },
        Core = { "System.*", "IPC.*" },
    })

    Debug.configure({
        -- Minimum level to display: "error", "warn", "info", "trace"
        -- Messages below this threshold are hidden
        level = "info",

        -- What to show: patterns, exact names, or @GroupName references
        -- If empty, everything above level threshold shows (default behavior)
        show = {
            "@Core",           -- Show entire Core group
            "Orchestrator",    -- Show exact match
            "Asset.*",         -- Show glob pattern
        },

        -- What to hide: overrides 'show', same syntax
        hide = {
            "*.Tick",          -- Hide anything ending in .Tick
        },

        -- Solo mode: if non-empty, ONLY these patterns show
        -- Useful for focused debugging of specific modules
        -- Ignores 'show' and 'hide' when active
        solo = {},
    })
    ```

    RESOLUTION ORDER
    ----------------

    1. Check level threshold - below threshold = hidden
    2. Check solo - if non-empty, only solo patterns show
    3. Check hide - if matches, hidden
    4. Check show - if non-empty and doesn't match, hidden
    5. Default: show

    LOG METHODS
    -----------

    All methods take (source, ...) where source identifies the calling module.

    - error(source, ...)  -- Something broke, always shown unless explicitly hidden
    - warn(source, ...)   -- Something's wrong but recoverable
    - info(source, ...)   -- Normal operation messages (default threshold)
    - trace(source, ...)  -- Detailed debugging, noisy

--]]

System.Debug = (function()
    ---------------------------------------------------------------------------
    -- PRIVATE STATE (closure-protected)
    ---------------------------------------------------------------------------

    -- Log level priority (higher number = higher priority)
    local LEVELS = {
        trace = 1,
        info = 2,
        warn = 3,
        error = 4,
    }

    -- Current configuration (set via configure())
    -- Note: groups are defined at System.groups, not here
    local config = {
        level = "info",
        show = {},
        hide = {},
        solo = {},
    }

    ---------------------------------------------------------------------------
    -- PRIVATE FUNCTIONS (closure-protected)
    ---------------------------------------------------------------------------

    --[[
        Determine if a message should be logged based on current config.

        @param source string - Message source (e.g., "Orchestrator")
        @param level string - Message level ("error", "warn", "info", "trace")
        @return boolean - True if message should be displayed
    --]]
    local function shouldLog(source, level)
        -- Check level threshold
        local msgPriority = LEVELS[level] or LEVELS.info
        local thresholdPriority = LEVELS[config.level] or LEVELS.info

        if msgPriority < thresholdPriority then
            return false
        end

        -- Check solo mode (if active, only solo patterns show)
        if #config.solo > 0 then
            return Utils.matchesAny(source, config.solo, System.groups)
        end

        -- Check hide list (overrides show)
        if Utils.matchesAny(source, config.hide, System.groups) then
            return false
        end

        -- Check show list (if non-empty, must match to show)
        if #config.show > 0 then
            return Utils.matchesAny(source, config.show, System.groups)
        end

        -- Default: show
        return true
    end

    --[[
        Format message arguments into a single string.

        @param ... any - Values to format
        @return string - Space-separated string representation
    --]]
    local function formatMessage(...)
        local args = {...}
        local parts = {}
        for i, v in ipairs(args) do
            parts[i] = tostring(v)
        end
        return table.concat(parts, " ")
    end

    --[[
        Output a log message with appropriate formatting.

        @param level string - Log level
        @param source string - Message source
        @param message string - Formatted message
    --]]
    local function output(level, source, message)
        local prefix = string.format("[%s] %s:", level:upper(), source)

        if level == "error" then
            -- Use warn() for visibility (red in output)
            warn("[ERROR] " .. source .. ": " .. message)
        elseif level == "warn" then
            warn(prefix .. " " .. message)
        else
            print(prefix .. " " .. message)
        end
    end

    ---------------------------------------------------------------------------
    -- PUBLIC API
    ---------------------------------------------------------------------------

    local Debug = {}

    --[[
        Configure the debug system.

        Call this early in bootstrap before other modules initialize.
        Can be called multiple times to update configuration.

        @param newConfig table - Configuration table (see module header for schema)
    --]]
    function Debug.configure(newConfig)
        Utils.mergeConfig(config, newConfig)
    end

    --[[
        Log an error message.

        Use for: Failures, exceptions, things that broke.
        Always shown unless explicitly hidden via 'hide' or below 'error' level.

        @param source string - Calling module identifier (e.g., "Orchestrator")
        @param ... any - Message values (will be concatenated with spaces)
    --]]
    function Debug.error(source, ...)
        if shouldLog(source, "error") then
            output("error", source, formatMessage(...))
        end
    end

    --[[
        Log a warning message.

        Use for: Non-fatal issues, deprecation notices, unexpected but handled cases.
        Shown at 'warn' level and above.

        @param source string - Calling module identifier
        @param ... any - Message values
    --]]
    function Debug.warn(source, ...)
        if shouldLog(source, "warn") then
            output("warn", source, formatMessage(...))
        end
    end

    --[[
        Log an info message.

        Use for: Normal operation, state changes, lifecycle events.
        This is the default threshold - shown at 'info' level and above.

        @param source string - Calling module identifier
        @param ... any - Message values
    --]]
    function Debug.info(source, ...)
        if shouldLog(source, "info") then
            output("info", source, formatMessage(...))
        end
    end

    --[[
        Log a trace message.

        Use for: Detailed debugging, step-by-step execution, verbose output.
        Only shown at 'trace' level. Use liberally - it's hidden by default.

        @param source string - Calling module identifier
        @param ... any - Message values
    --]]
    function Debug.trace(source, ...)
        if shouldLog(source, "trace") then
            output("trace", source, formatMessage(...))
        end
    end

    --[[
        Get current configuration (for debugging the debugger).

        @return table - Current config (copy, not reference)
    --]]
    function Debug.getConfig()
        return {
            level = config.level,
            show = config.show,
            hide = config.hide,
            solo = config.solo,
        }
    end

    return Debug
end)()

--[[
    ============================================================================
    LOG SUBSYSTEM
    ============================================================================

    Persistent telemetry and analytics logging. Unlike Debug (which outputs to
    console), Log captures structured events for post-mortem analysis, metrics
    collection, and player behavior tracking.

    RELATIONSHIP TO DEBUG
    ---------------------

    | Debug                  | Log                           |
    |------------------------|-------------------------------|
    | Console output         | Persistent storage            |
    | Runtime visibility     | Post-mortem analysis          |
    | Developer-facing       | Analytics/metrics             |
    | Immediate              | Batched for efficiency        |
    | Level-based filtering  | Pattern-based capture         |

    CONFIGURATION
    -------------

    ```lua
    -- Groups are shared via System.setGroups() (see Debug docs)

    Log.configure({
        -- Patterns to capture (empty = capture all)
        -- Uses same glob/@GroupName syntax as Debug
        capture = {
            "Combat.*",         -- All combat events
            "Economy.*",        -- All economy events
            "@PlayerActions",   -- Named group
        },

        -- Patterns to ignore (overrides capture)
        ignore = {
            "*.Tick",           -- Don't capture tick events
        },

        -- Storage backend
        --   "Memory"    - In-memory only (for testing, lost on shutdown)
        --   "DataStore" - Roblox DataStore (persistent, rate-limited, SERVER ONLY)
        --   "None"      - Disabled (no capture, for production optimization)
        -- NOTE: DataStore is forced to Memory on client (DataStore is server-only)
        backend = "Memory",

        -- Auto-flush settings (only applies to DataStore backend)
        flushInterval = 30,     -- Seconds between auto-flush (0 = manual only)
        maxBatchSize = 100,     -- Max events before force-flush
    })
    ```

    EVENT STRUCTURE
    ---------------

    Each captured event has this structure:

    ```lua
    {
        timestamp = 1704067200,          -- os.time() when captured
        session = "1704067200-A7F3-B2C1", -- Unique session ID
        source = "Combat",                -- Module source
        event = "damage_dealt",           -- Event name
        data = {                          -- Custom event data
            playerId = 12345,
            amount = 50,
            weapon = "Sword",
        },
    }
    ```

    USAGE
    -----

    ```lua
    -- Initialize in Bootstrap (generates session ID, starts auto-flush)
    Log.init()

    -- Capture structured events
    Log.event("Combat", "damage_dealt", {
        playerId = player.UserId,
        amount = damage,
        weapon = weaponName,
    })

    Log.event("Economy", "purchase", {
        playerId = player.UserId,
        item = "SpeedBoost",
        price = 100,
    })

    -- Force flush (e.g., before shutdown)
    Log.flush()

    -- Get session info
    local session = Log.getSession()
    print(session.id, session.eventCount)
    ```

    DATASTORE STORAGE
    -----------------

    When using DataStore backend, events are stored with keys:
        Log_{PlaceId}_{SessionId}

    Each key stores an array of events. The system respects DataStore limits:
        - Batches writes to stay under 6 requests/min per key
        - Chunks large batches if they exceed size limits

    IMPORTANT: DataStore backend requires the game to be published and have
    API access enabled. Use "Memory" backend for local testing.

    ============================================================================
    FUTURE CONSIDERATIONS (v2.x+)
    ============================================================================

    Roblox DataStore has hard limits that make raw event storage unsustainable
    at scale:
        - 4MB max per key
        - 6 writes/min per key (UpdateAsync)
        - ~60 + (players × 10) requests/min total

    PRODUCTION STRATEGIES TO CONSIDER:

    1. SAMPLING
       Capture only a percentage of events, extrapolate in analysis.
       ```lua
       Log.configure({ sampleRate = 0.1 })  -- 10% of events
       ```

    2. AGGREGATION
       Store summaries instead of raw events. Track counts, sums, averages.
       ```lua
       -- Instead of 100 "damage_dealt" events, store:
       { source = "Combat", metric = "total_damage", value = 5000, count = 100 }
       ```

    3. PRIORITY TIERS
       Only persist critical events (errors, milestones, purchases).
       ```lua
       Log.event("Economy", "purchase", data, "critical")  -- persisted
       Log.event("Combat", "hit", data, "debug")           -- discarded
       ```

    4. EXTERNAL WEBHOOK
       Push batches to external analytics (PlayFab, GameAnalytics, custom).
       ```lua
       Log.configure({ webhookUrl = "https://analytics.example.com/ingest" })
       ```

    5. RING BUFFER
       Keep only the last N events, discard old.
       ```lua
       Log.configure({ maxStoredEvents = 1000 })
       ```

    POTENTIAL THIRD LAYER: TELEMETRY

    A future subsystem could handle high-volume normalized metrics separately:

    | Debug     | Log              | Telemetry (future)        |
    |-----------|------------------|---------------------------|
    | Console   | Structured events| Raw normalized metrics    |
    | Immediate | Batched          | Streaming/sampled         |
    | Developer | Analytics        | Data pipeline             |
    | Verbose   | Selective        | High-volume               |

    Telemetry would focus on:
        - Numeric time-series (FPS, latency, memory usage)
        - Player behavior streams (position, input frequency)
        - Automatic instrumentation (function call counts, timing)
        - Export to external data pipelines

    For now, Log with Memory backend is sufficient for development.
    These enhancements will be added as production needs arise.

--]]

System.Log = (function()
    ---------------------------------------------------------------------------
    -- SERVICES (captured once for performance)
    ---------------------------------------------------------------------------

    local RunService = game:GetService("RunService")  -- For Heartbeat connection
    local DataStoreService = nil  -- Lazy-loaded when needed (server only)

    ---------------------------------------------------------------------------
    -- PRIVATE STATE (closure-protected)
    ---------------------------------------------------------------------------

    -- Current configuration
    -- Note: groups are defined at System.groups, not here
    local config = {
        capture = {},           -- Patterns to capture (empty = all)
        ignore = {},            -- Patterns to ignore
        backend = "Memory",     -- "Memory", "DataStore", "None"
        flushInterval = 30,     -- Seconds between auto-flush
        maxBatchSize = 100,     -- Max events before force-flush
    }

    -- Session metadata (set on init)
    local session = {
        id = nil,               -- Unique session ID
        startTime = nil,        -- os.time() when session started
        placeId = nil,          -- game.PlaceId
        gameId = nil,           -- game.GameId
        serverId = nil,         -- game.JobId (server instance)
        isStudio = false,       -- RunService:IsStudio()
        eventCount = 0,         -- Total events captured this session
    }

    -- Event buffer (pending events awaiting flush)
    local buffer = {}

    -- Auto-flush state
    local flushConnection = nil     -- Heartbeat connection
    local lastFlushTime = 0         -- os.time() of last flush
    local isInitialized = false     -- Prevents double-init

    -- Memory backend storage (for testing)
    local memoryStore = {}

    ---------------------------------------------------------------------------
    -- PRIVATE FUNCTIONS (closure-protected)
    ---------------------------------------------------------------------------

    --[[
        Determine if an event should be captured based on source pattern.

        @param source string - Event source (e.g., "Combat")
        @return boolean - True if event should be captured
    --]]
    local function shouldCapture(source)
        -- Check ignore list first (overrides capture)
        if Utils.matchesAny(source, config.ignore, System.groups) then
            return false
        end

        -- If capture list is empty, capture everything
        if #config.capture == 0 then
            return true
        end

        -- Check capture list
        return Utils.matchesAny(source, config.capture, System.groups)
    end

    --[[
        Write events to the memory backend (for testing).

        @param events table - Array of event objects
    --]]
    local function writeToMemory(events)
        for _, event in ipairs(events) do
            table.insert(memoryStore, event)
        end
    end

    --[[
        Write events to DataStore backend.

        @param events table - Array of event objects
        @return boolean, string - Success flag and error message if failed
    --]]
    local function writeToDataStore(events)
        -- Lazy-load DataStoreService
        if not DataStoreService then
            local success, service = pcall(function()
                return game:GetService("DataStoreService")
            end)
            if not success then
                return false, "DataStoreService unavailable"
            end
            DataStoreService = service
        end

        -- Build the key
        local key = string.format("Log_%d_%s", session.placeId or 0, session.id)

        -- Get or create the DataStore
        local success, store = pcall(function()
            return DataStoreService:GetDataStore("Warren_Logs")
        end)

        if not success then
            return false, "Failed to get DataStore: " .. tostring(store)
        end

        -- Update the stored data (append events)
        local updateSuccess, updateError = pcall(function()
            store:UpdateAsync(key, function(oldData)
                oldData = oldData or { events = {} }
                for _, event in ipairs(events) do
                    table.insert(oldData.events, event)
                end
                return oldData
            end)
        end)

        if not updateSuccess then
            return false, "Failed to write to DataStore: " .. tostring(updateError)
        end

        return true, nil
    end

    --[[
        Flush buffered events to the configured backend.

        @return number - Number of events flushed
    --]]
    local function flushBuffer()
        if #buffer == 0 then
            return 0
        end

        local eventsToFlush = buffer
        buffer = {}  -- Clear buffer immediately to prevent double-flush

        if config.backend == "None" then
            -- Discard events (logging disabled)
            return #eventsToFlush
        elseif config.backend == "Memory" then
            writeToMemory(eventsToFlush)
        elseif config.backend == "DataStore" then
            local success, err = writeToDataStore(eventsToFlush)
            if not success then
                -- On failure, put events back in buffer for retry
                for _, event in ipairs(eventsToFlush) do
                    table.insert(buffer, event)
                end
                System.Debug.warn("Log", "DataStore flush failed:", err)
                return 0
            end
        end

        lastFlushTime = os.time()
        return #eventsToFlush
    end

    --[[
        Auto-flush handler (called on Heartbeat).

        Flushes if:
        - Buffer exceeds maxBatchSize
        - Time since last flush exceeds flushInterval
    --]]
    local function onHeartbeat()
        -- Check batch size trigger
        if #buffer >= config.maxBatchSize then
            flushBuffer()
            return
        end

        -- Check interval trigger
        if config.flushInterval > 0 then
            local elapsed = os.time() - lastFlushTime
            if elapsed >= config.flushInterval then
                flushBuffer()
            end
        end
    end

    ---------------------------------------------------------------------------
    -- PUBLIC API
    ---------------------------------------------------------------------------

    local Log = {}

    --[[
        Configure the log system.

        Call this in Bootstrap before Log.init().
        Can be called multiple times to update configuration.

        @param newConfig table - Configuration table (see module header for schema)
    --]]
    function Log.configure(newConfig)
        Utils.mergeConfig(config, newConfig)

        -- DataStore backend is server-only; force Memory on client
        if System.isClient and config.backend == "DataStore" then
            System.Debug.warn("Log", "DataStore backend unavailable on client, using Memory")
            config.backend = "Memory"
        end
    end

    --[[
        Initialize the log system.

        Call this once in Bootstrap after configure(). This:
        - Generates a unique session ID
        - Captures session metadata
        - Starts the auto-flush timer (if enabled)

        Safe to call multiple times (subsequent calls are no-ops).
    --]]
    function Log.init()
        if isInitialized then
            System.Debug.warn("Log", "Already initialized, ignoring duplicate init()")
            return
        end

        -- Generate session info
        session.id = Utils.generateSessionId()
        session.startTime = os.time()
        session.placeId = game.PlaceId
        session.gameId = game.GameId
        session.serverId = game.JobId
        session.isStudio = System.isStudio
        session.eventCount = 0

        -- Start auto-flush timer (if interval > 0 and backend isn't None)
        if config.flushInterval > 0 and config.backend ~= "None" then
            lastFlushTime = os.time()
            flushConnection = RunService.Heartbeat:Connect(onHeartbeat)
        end

        isInitialized = true
        System.Debug.info("Log", "Initialized session:", session.id)
    end

    --[[
        Capture a structured event.

        Events are buffered and periodically flushed to the backend.
        If the source doesn't match capture patterns (or matches ignore),
        the event is silently discarded.

        @param source string - Module/system source (e.g., "Combat", "Economy")
        @param eventName string - Descriptive event name (e.g., "damage_dealt")
        @param data table - Custom event data (will be deep-copied)

        Example:
            Log.event("Combat", "damage_dealt", {
                playerId = player.UserId,
                amount = 50,
                weapon = "Sword",
            })
    --]]
    function Log.event(source, eventName, data)
        -- Skip if backend is disabled
        if config.backend == "None" then
            return
        end

        -- Check capture filters
        if not shouldCapture(source) then
            return
        end

        -- Build event object
        local event = {
            timestamp = os.time(),
            session = session.id or "uninitialized",
            source = source,
            event = eventName,
            data = data and Utils.deepCopy(data) or {},
        }

        -- Add to buffer
        table.insert(buffer, event)
        session.eventCount = session.eventCount + 1

        -- Immediate flush if buffer is full (handled by Heartbeat, but safety check)
        if #buffer >= config.maxBatchSize then
            flushBuffer()
        end
    end

    --[[
        Force flush all buffered events to the backend.

        Call this:
        - Before server shutdown
        - Before important checkpoints
        - When you need data persisted immediately

        @return number - Number of events flushed
    --]]
    function Log.flush()
        return flushBuffer()
    end

    --[[
        Get current session information.

        @return table - Session metadata (copy, not reference)
    --]]
    function Log.getSession()
        return {
            id = session.id,
            startTime = session.startTime,
            placeId = session.placeId,
            gameId = session.gameId,
            serverId = session.serverId,
            isStudio = session.isStudio,
            eventCount = session.eventCount,
            bufferSize = #buffer,
        }
    end

    --[[
        Get current configuration.

        @return table - Current config (copy, not reference)
    --]]
    function Log.getConfig()
        return {
            capture = config.capture,
            ignore = config.ignore,
            backend = config.backend,
            flushInterval = config.flushInterval,
            maxBatchSize = config.maxBatchSize,
        }
    end

    --[[
        Get buffered events (for debugging/testing).

        @return table - Array of pending events (copy, not reference)
    --]]
    function Log.getBuffer()
        local copy = {}
        for i, event in ipairs(buffer) do
            copy[i] = Utils.deepCopy(event)
        end
        return copy
    end

    --[[
        Get all events from memory store (Memory backend only).

        @return table - Array of all stored events, or empty if not using Memory
    --]]
    function Log.getMemoryStore()
        if config.backend ~= "Memory" then
            return {}
        end

        local copy = {}
        for i, event in ipairs(memoryStore) do
            copy[i] = Utils.deepCopy(event)
        end
        return copy
    end

    --[[
        Clear the memory store (Memory backend only).
        Useful for testing.
    --]]
    function Log.clearMemoryStore()
        memoryStore = {}
    end

    --[[
        Shutdown the log system.

        Flushes remaining events and disconnects auto-flush timer.
        Call this before server shutdown for clean exit.
    --]]
    function Log.shutdown()
        if flushConnection then
            flushConnection:Disconnect()
            flushConnection = nil
        end

        -- Final flush
        local flushed = flushBuffer()
        System.Debug.info("Log", "Shutdown complete. Flushed", flushed, "events.")

        isInitialized = false
    end

    return Log
end)()

--[[
    ============================================================================
    IPC SUBSYSTEM
    ============================================================================

    Inter-Process Communication (IPC) is the central nervous system for node
    communication. It manages:

    - Node registration and lifecycle
    - Run modes and wiring configurations
    - Message routing between nodes
    - Error collection and handling

    DESIGN
    ------

    IPC follows the "breadboard" model: nodes are like integrated circuits (ICUs)
    that don't know about each other. They respond to signals on their pins.
    The wiring configuration (defined per run mode) determines system behavior.

    COMMUNICATION RULES
    -------------------

    | From | To | Method |
    |------|-----|--------|
    | Node | Node | Events via IPC (Out → wiring → In) |
    | Node | System Service | Direct API calls |
    | System | Node | Broadcasts via Sys.In |
    | Node | System (errors) | Err channel → IPC.handleError |

    USAGE
    -----

    ```lua
    local IPC = Lib.System.IPC
    local Node = require(Lib.Node)

    -- Define a node
    local MyNode = Node.extend({
        name = "MyNode",
        In = {
            onPing = function(self, data)
                self.Out:Fire("pong", { reply = data.msg })
            end
        },
    })

    -- Register and create instance
    IPC.registerNode(MyNode)
    local inst = IPC.createInstance("MyNode", { id = "mynode1" })

    -- Define mode with wiring
    IPC.defineMode("Playing", {
        nodes = { "MyNode" },
        wiring = { MyNode = { "MyNode" } },  -- Self-loop for demo
    })

    -- Initialize and start
    IPC.init()
    IPC.switchMode("Playing")
    IPC.start()

    -- Send message
    IPC.sendTo("mynode1", "ping", { msg = "hello" })
    ```

--]]

System.IPC = (function()
    ---------------------------------------------------------------------------
    -- PRIVATE STATE (closure-protected)
    ---------------------------------------------------------------------------

    local nodeDefinitions = {}   -- { className → NodeClass }
    local instances = {}         -- { instanceId → instance }
    local nodesByClass = {}      -- { className → { instanceId, ... } }
    local modeConfigs = {}       -- { modeName → config }
    local currentMode = nil      -- Current active mode name
    local messageCounter = 0     -- Linear message ID counter (prefixed with domain)
    local seenMessages = {}      -- { "S:1" | "C:1" → { nodeId → true } }
    local isInitialized = false
    local isStarted = false

    -- Message ID domain prefix (like area codes for phone numbers)
    -- Local messages: "S:1", "S:2" (server) or "C:1", "C:2" (client)
    -- Cross-domain messages retain their origin prefix when received
    local MESSAGE_DOMAIN_PREFIX = System.isServer and "S:" or "C:"

    -- Cross-domain routing state
    local crossDomainRemote = nil           -- RemoteEvent for client/server signals
    local nodeDomains = {}                  -- { className → "server"|"client"|"shared" }
    local crossDomainClasses = {}           -- Classes that exist on the other domain
    local CROSS_DOMAIN_REMOTE_NAME = "LibPF_IPC_CrossDomain"

    -- Forward declarations (for functions used before definition)
    local sendCrossDomain

    ---------------------------------------------------------------------------
    -- PRIVATE FUNCTIONS (closure-protected)
    ---------------------------------------------------------------------------

    --[[
        Validate that a node class satisfies its contract requirements.

        Walks the inheritance chain and checks that all required handlers
        are present (either as implementations or defaults).

        @param NodeClass table - The node class to validate
        @return boolean, string - Success flag and error message if failed
    --]]
    local function validateContract(NodeClass)
        local missing = {}

        -- Get all required handlers from the class (already merged from chain)
        local required = NodeClass.required or {}

        for pin, handlers in pairs(required) do
            for _, handler in ipairs(handlers) do
                -- Check if handler exists in class or defaults
                local hasHandler = false

                -- Check class handler
                if NodeClass[pin] and NodeClass[pin][handler] then
                    hasHandler = true
                end

                -- Check defaults
                if not hasHandler and NodeClass.defaults and NodeClass.defaults[pin]
                    and NodeClass.defaults[pin][handler] then
                    hasHandler = true
                end

                if not hasHandler then
                    table.insert(missing, {
                        handler = pin .. "." .. handler,
                        requiredBy = NodeClass.name,
                    })
                end
            end
        end

        if #missing > 0 then
            local parts = {}
            for _, m in ipairs(missing) do
                table.insert(parts, string.format("  - %s (required by: %s, no default provided)",
                    m.handler, m.requiredBy))
            end
            local msg = string.format("[BOOT ERROR] Node '%s' missing required handlers:\n%s\nGame will not run.",
                NodeClass.name, table.concat(parts, "\n"))
            return false, msg
        end

        return true, nil
    end

    --[[
        Wire up an instance's Out and Err channels to IPC routing.

        @param instance table - The node instance to wire
    --]]
    local function wireInstance(instance)
        -- Give instance access to System
        instance._System = System

        -- Wire Out:Fire to IPC.send
        instance._ipcSend = function(sourceId, signal, data)
            if isStarted then
                -- Route through IPC
                local IPC = System.IPC
                IPC.send(sourceId, signal, data)
            end
        end

        -- Wire Err:Fire to IPC.handleError
        instance._ipcError = function(errorData)
            local IPC = System.IPC
            IPC.handleError(errorData)
        end
    end

    --[[
        Resolve wiring for a mode, including inheritance from base modes.

        @param modeName string - Mode name to resolve
        @return table - Merged wiring configuration
    --]]
    local function resolveWiring(modeName)
        local config = modeConfigs[modeName]
        if not config then
            return {}
        end

        local wiring = {}

        -- First, resolve base mode wiring (if any)
        if config.base and modeConfigs[config.base] then
            local baseWiring = resolveWiring(config.base)
            for source, targets in pairs(baseWiring) do
                wiring[source] = {}
                for _, target in ipairs(targets) do
                    table.insert(wiring[source], target)
                end
            end
        end

        -- Then, merge this mode's wiring (overrides base)
        if config.wiring then
            for source, targets in pairs(config.wiring) do
                wiring[source] = {}
                for _, target in ipairs(targets) do
                    table.insert(wiring[source], target)
                end
            end
        end

        return wiring
    end

    --[[
        Resolve target instances for a signal from a source.

        @param sourceId string - Source instance ID
        @param signal string - Signal name
        @param targetSpec any - Optional specific target (instanceId or table)
        @return table - Array of target instance IDs
    --]]
    local function resolveTargets(sourceId, signal, targetSpec)
        -- If specific target provided, use it
        if type(targetSpec) == "string" then
            return { targetSpec }
        elseif type(targetSpec) == "table" and targetSpec._target then
            return { targetSpec._target }
        end

        -- Otherwise, use wiring
        if not currentMode then
            return {}
        end

        local wiring = resolveWiring(currentMode)
        local sourceInstance = instances[sourceId]
        if not sourceInstance then
            return {}
        end

        local sourceClass = sourceInstance.class
        local targetClasses = wiring[sourceClass] or {}
        local targets = {}

        for _, targetClass in ipairs(targetClasses) do
            local classInstances = nodesByClass[targetClass] or {}
            for _, instanceId in ipairs(classInstances) do
                table.insert(targets, instanceId)
            end
        end

        return targets
    end

    --[[
        Execute a handler on an instance with error protection.

        @param instance table - Node instance
        @param pin string - Pin name ("In", "Sys", etc.)
        @param handlerName string - Handler name (e.g., "onInit")
        @param data any - Data to pass to handler
        @return boolean, any - Success flag and result or error
    --]]
    local function executeHandler(instance, pin, handlerName, data)
        local handler = nil

        -- Resolve handler (check mode-specific first for In/Out)
        if pin == "In" and currentMode then
            local modePin = instance:resolvePin(currentMode, "In")
            handler = modePin[handlerName]
        end

        -- Fall back to regular pin
        if not handler and instance[pin] then
            handler = instance[pin][handlerName]
        end

        if not handler then
            return false, string.format("Handler not found: %s.%s", pin, handlerName)
        end

        -- Execute with pcall protection
        local success, result = pcall(function()
            return handler(instance, data)
        end)

        if not success then
            -- Error occurred - fire on Err channel
            instance.Err:Fire({
                handler = pin .. "." .. handlerName,
                error = tostring(result),
                data = data,
            })
            return false, result
        end

        return true, result
    end

    --[[
        Dispatch a signal to a target instance.

        @param targetId string - Target instance ID
        @param signal string - Signal name
        @param data table - Signal payload
        @param msgId string - Message ID for cycle detection (e.g., "S:1", "C:2")
        @return boolean - True if dispatched successfully
    --]]
    local function dispatchToTarget(targetId, signal, data, msgId)
        local instance = instances[targetId]
        if not instance then
            System.Debug.warn("IPC", "Target not found:", targetId)
            return false
        end

        -- Lock check: if node is locked, queue the message for later
        if instance.isLocked and instance:isLocked() then
            instance._messageQueue = instance._messageQueue or {}
            table.insert(instance._messageQueue, { signal, data, msgId })
            System.Debug.trace("IPC", "Node locked, queuing message:", targetId, signal)
            return false  -- Not dispatched yet, queued
        end

        -- Cycle detection: check if this message already visited this node
        if msgId and seenMessages[msgId] and seenMessages[msgId][targetId] then
            System.Debug.warn("IPC", "Cycle detected: msgId", msgId, "already visited", targetId)
            return false
        end

        -- Track this visit
        if msgId then
            seenMessages[msgId] = seenMessages[msgId] or {}
            seenMessages[msgId][targetId] = true
        end

        -- Determine handler name (signal → onSignal)
        local handlerName = "on" .. signal:sub(1, 1):upper() .. signal:sub(2)

        -- Execute the handler
        local success, err = executeHandler(instance, "In", handlerName, data)

        if not success then
            System.Debug.trace("IPC", "Handler", handlerName, "not found or failed on", targetId)
        end

        -- Auto-ack for sync mode: if handler succeeded and signal has sync metadata,
        -- send ack event back to the sender through IPC
        if success and data._sync and data._sync.replyTo then
            local ackData = {
                _correlationId = data._sync.id,
                _ackFor = signal,
                targetId = targetId,
            }
            -- Use deferred dispatch to avoid blocking
            task.defer(function()
                if instances[data._sync.replyTo] then
                    local ackMsgId = nextMessageId
                    nextMessageId = nextMessageId + 1
                    dispatchToTarget(data._sync.replyTo, "_ack", ackData, ackMsgId)
                end
            end)
            System.Debug.trace("IPC", "Auto-ack sent for sync signal:", signal, "->", data._sync.replyTo)
        end

        return success
    end

    ---------------------------------------------------------------------------
    -- PUBLIC API
    ---------------------------------------------------------------------------

    local IPC = {}

    ---------------------------------------------------------------------------
    -- NODE REGISTRATION
    ---------------------------------------------------------------------------

    --[[
        Register a node class with IPC.

        Validates the contract and stores the definition for instance creation.

        @param NodeClass table - Node class (result of Node.extend)
        @return boolean - True if registration successful
    --]]
    function IPC.registerNode(NodeClass)
        if not NodeClass or not NodeClass.name then
            error("[IPC.registerNode] Node class must have a name")
        end

        -- Validate contract
        local valid, err = validateContract(NodeClass)
        if not valid then
            error(err)
        end

        -- Store definition
        nodeDefinitions[NodeClass.name] = NodeClass
        nodesByClass[NodeClass.name] = nodesByClass[NodeClass.name] or {}

        -- Track domain for cross-domain routing
        local domain = NodeClass.domain or "shared"
        nodeDomains[NodeClass.name] = domain

        System.Debug.trace("IPC", "Registered node:", NodeClass.name, "(domain:", domain, ")")
        return true
    end

    --[[
        Create an instance of a registered node class.

        @param className string - Name of the registered node class
        @param config table - Instance configuration (id, model, attributes)
        @return table - Node instance
    --]]
    function IPC.createInstance(className, config)
        local NodeClass = nodeDefinitions[className]
        if not NodeClass then
            error(string.format("[IPC.createInstance] Node class '%s' not registered", className))
        end

        config = config or {}
        if not config.id then
            error("[IPC.createInstance] Instance must have an id")
        end

        -- Check domain compatibility
        if NodeClass.domain == "server" and System.isClient then
            System.Debug.trace("IPC", "Skipping server node on client:", className)
            return nil
        end
        if NodeClass.domain == "client" and System.isServer then
            System.Debug.trace("IPC", "Skipping client node on server:", className)
            return nil
        end

        -- Check for duplicate ID
        if instances[config.id] then
            error(string.format("[IPC.createInstance] Instance '%s' already exists", config.id))
        end

        -- Create instance
        local instance = NodeClass:new(config)

        -- Wire up IPC channels
        wireInstance(instance)

        -- Register in lookup tables
        instances[config.id] = instance
        table.insert(nodesByClass[className], config.id)

        -- If IPC is already initialized/started, call lifecycle handlers on new instance
        if isInitialized then
            executeHandler(instance, "Sys", "onInit", {})
            System.Debug.trace("IPC", "Called onInit on late-created instance:", config.id)
        end
        if isStarted then
            executeHandler(instance, "Sys", "onStart", {})
            System.Debug.trace("IPC", "Called onStart on late-created instance:", config.id)
        end

        System.Debug.trace("IPC", "Created instance:", config.id, "of", className)
        return instance
    end

    --[[
        Get an instance by ID.

        @param id string - Instance ID
        @return table|nil - Instance or nil if not found
    --]]
    function IPC.getInstance(id)
        return instances[id]
    end

    --[[
        Get all instances of a class.

        @param className string - Class name
        @return table - Array of instances
    --]]
    function IPC.getInstancesByClass(className)
        local result = {}
        local ids = nodesByClass[className] or {}
        for _, id in ipairs(ids) do
            if instances[id] then
                table.insert(result, instances[id])
            end
        end
        return result
    end

    --[[
        Spawn a new instance dynamically (create + lifecycle hooks).

        @param className string - Class name
        @param config table - Instance configuration
        @return table - New instance
    --]]
    function IPC.spawn(className, config)
        local instance = IPC.createInstance(className, config)
        if not instance then
            return nil
        end

        -- Call lifecycle hooks
        if isInitialized then
            executeHandler(instance, "Sys", "onSpawned", {})
            executeHandler(instance, "Sys", "onInit", {})
        end

        if isStarted then
            executeHandler(instance, "Sys", "onStart", {})
        end

        return instance
    end

    --[[
        Despawn an instance (cleanup + destroy).

        @param instanceId string - Instance ID to despawn
    --]]
    function IPC.despawn(instanceId)
        local instance = instances[instanceId]
        if not instance then
            System.Debug.warn("IPC", "Cannot despawn: instance not found:", instanceId)
            return
        end

        -- Call lifecycle hooks
        executeHandler(instance, "Sys", "onStop", {})
        executeHandler(instance, "Sys", "onDespawning", {})

        -- Remove from lookup tables
        instances[instanceId] = nil

        local className = instance.class
        local classInstances = nodesByClass[className]
        if classInstances then
            for i, id in ipairs(classInstances) do
                if id == instanceId then
                    table.remove(classInstances, i)
                    break
                end
            end
        end

        System.Debug.trace("IPC", "Despawned instance:", instanceId)
    end

    ---------------------------------------------------------------------------
    -- MODE MANAGEMENT
    ---------------------------------------------------------------------------

    --[[
        Define a run mode with its wiring configuration.

        @param name string - Mode name
        @param config table - Mode configuration
            base: string (optional) - Base mode to inherit from
            nodes: table - Array of node class names active in this mode
            wiring: table - { SourceClass = { "TargetClass", ... } }
            attributes: table (optional) - { ClassName = { attr = value } }
    --]]
    function IPC.defineMode(name, config)
        if not name then
            error("[IPC.defineMode] Mode must have a name")
        end

        config = config or {}
        config.nodes = config.nodes or {}
        config.wiring = config.wiring or {}
        config.attributes = config.attributes or {}

        modeConfigs[name] = config
        System.Debug.trace("IPC", "Defined mode:", name)
    end

    --[[
        Switch to a new run mode.

        @param name string - Mode name to switch to
    --]]
    function IPC.switchMode(name)
        if not modeConfigs[name] then
            error(string.format("[IPC.switchMode] Mode '%s' not defined", name))
        end

        local oldMode = currentMode
        local newMode = name

        -- Notify all instances of mode change
        for id, instance in pairs(instances) do
            executeHandler(instance, "Sys", "onModeChange", {
                oldMode = oldMode,
                newMode = newMode,
            })
        end

        -- Apply mode-specific attributes
        local config = modeConfigs[name]
        if config.attributes then
            for className, attrs in pairs(config.attributes) do
                local classInstances = IPC.getInstancesByClass(className)
                for _, instance in ipairs(classInstances) do
                    for attrName, attrValue in pairs(attrs) do
                        instance:setAttribute(attrName, attrValue)
                    end
                end
            end
        end

        currentMode = name
        System.Debug.info("IPC", "Switched to mode:", name)
    end

    --[[
        Get the current mode name.

        @return string|nil - Current mode name
    --]]
    function IPC.getMode()
        return currentMode
    end

    --[[
        Get a mode's configuration.

        @param name string - Mode name
        @return table|nil - Mode configuration
    --]]
    function IPC.getModeConfig(name)
        return modeConfigs[name]
    end

    ---------------------------------------------------------------------------
    -- MESSAGING
    ---------------------------------------------------------------------------

    --[[
        Get a unique message ID.

        Returns a domain-prefixed ID (e.g., "S:1" for server, "C:1" for client).
        This prevents cross-domain message ID collisions, like area codes for
        phone numbers or domestic vs international mail.

        @return string - Unique message ID with domain prefix
    --]]
    function IPC.getMessageId()
        messageCounter = messageCounter + 1
        return MESSAGE_DOMAIN_PREFIX .. messageCounter
    end

    --[[
        Send a signal from a source through the wiring to targets.

        @param sourceId string - Source instance ID
        @param signal string - Signal name
        @param data table - Signal payload
    --]]
    function IPC.send(sourceId, signal, data)
        if not isStarted then
            System.Debug.warn("IPC", "Cannot send: IPC not started")
            return
        end

        data = data or {}

        -- Get or create message ID
        local msgId = data._msgId or IPC.getMessageId()
        data._msgId = msgId

        -- Get source instance and class
        local sourceInstance = instances[sourceId]
        if not sourceInstance then
            System.Debug.warn("IPC", "Source instance not found:", sourceId)
            return
        end

        local sourceClass = sourceInstance.class
        local currentDomain = System.isServer and "server" or "client"

        -- Resolve targets from wiring (class-based)
        if not currentMode then
            return
        end

        local wiring = resolveWiring(currentMode)
        local targetClasses = wiring[sourceClass] or {}

        local localTargetCount = 0
        local crossDomainSent = false

        for _, targetClass in ipairs(targetClasses) do
            local targetDomain = nodeDomains[targetClass] or "shared"

            -- Determine if target is cross-domain
            local isCrossDomain = false
            if targetDomain == "server" and currentDomain == "client" then
                isCrossDomain = true
            elseif targetDomain == "client" and currentDomain == "server" then
                isCrossDomain = true
            end

            if isCrossDomain then
                -- Send via RemoteEvent (once per target domain)
                if not crossDomainSent then
                    sendCrossDomain(sourceClass, signal, data, targetDomain)
                    crossDomainSent = true
                end
            else
                -- Local dispatch - find all instances of this class
                local classInstances = nodesByClass[targetClass] or {}
                for _, instanceId in ipairs(classInstances) do
                    dispatchToTarget(instanceId, signal, data, msgId)
                    localTargetCount = localTargetCount + 1
                end
            end
        end

        System.Debug.trace("IPC", "Sent", signal, "from", sourceId,
            "- local:", localTargetCount, "cross-domain:", crossDomainSent and "yes" or "no")
    end

    --[[
        Send a signal directly to a specific instance.

        @param targetId string - Target instance ID
        @param signal string - Signal name
        @param data table - Signal payload
    --]]
    function IPC.sendTo(targetId, signal, data)
        if not isStarted then
            System.Debug.warn("IPC", "Cannot sendTo: IPC not started")
            return
        end

        data = data or {}
        local msgId = data._msgId or IPC.getMessageId()
        data._msgId = msgId

        System.Debug.trace("IPC", "SendTo", targetId, signal)
        dispatchToTarget(targetId, signal, data, msgId)
    end

    --[[
        Broadcast a signal to all instances' Sys.In.

        Used for lifecycle signals (init, start, stop).

        @param signal string - Signal name
        @param data table - Signal payload
    --]]
    function IPC.broadcast(signal, data)
        data = data or {}
        local msgId = IPC.getMessageId()
        data._msgId = msgId

        System.Debug.trace("IPC", "Broadcasting", signal, "to all instances")

        -- Determine handler name
        local handlerName = "on" .. signal:sub(1, 1):upper() .. signal:sub(2)

        for id, instance in pairs(instances) do
            executeHandler(instance, "Sys", handlerName, data)
        end
    end

    ---------------------------------------------------------------------------
    -- ERROR HANDLING
    ---------------------------------------------------------------------------

    --[[
        Handle an error from a node's Err channel.

        @param errorData table - Error information
            node: string - Node ID
            class: string - Node class
            handler: string - Handler that failed
            error: string - Error message
            data: any - Data that caused error
            timestamp: number - When error occurred
    --]]
    function IPC.handleError(errorData)
        -- Log via Debug system
        System.Debug.error("IPC", string.format(
            "Handler error in %s.%s: %s",
            errorData.node or "unknown",
            errorData.handler or "unknown",
            errorData.error or "unknown error"
        ))

        -- Record to Log system for analytics
        System.Log.event("IPC", "handler_error", {
            node = errorData.node,
            class = errorData.class,
            handler = errorData.handler,
            error = errorData.error,
        })
    end

    ---------------------------------------------------------------------------
    -- CROSS-DOMAIN ROUTING
    ---------------------------------------------------------------------------

    --[[
        Dispatch a cross-domain signal received from RemoteEvent.

        @param sourceClass string - Source node class name
        @param signal string - Signal name
        @param data table - Signal payload
        @param player Player? - Player who sent (server only, for validation)
    --]]
    local function dispatchCrossDomainSignal(sourceClass, signal, data, player)
        if not isStarted then
            System.Debug.warn("IPC", "Cross-domain signal received but IPC not started")
            return
        end

        -- Resolve targets from wiring (same as normal routing)
        if not currentMode then
            return
        end

        local wiring = resolveWiring(currentMode)
        local targetClasses = wiring[sourceClass] or {}

        -- Use the original msgId from the sending domain
        -- With prefixed IDs (e.g., "S:1" vs "C:1"), there's no collision risk
        local msgId = data._msgId

        System.Debug.trace("IPC", "Cross-domain signal from", sourceClass, ":", signal, "msgId:", msgId, "to", #targetClasses, "target classes")

        -- Dispatch to all instances of target classes in this context
        for _, targetClass in ipairs(targetClasses) do
            local targetDomain = nodeDomains[targetClass] or "shared"
            local currentDomain = System.isServer and "server" or "client"

            -- Only dispatch to nodes that exist in this context
            if targetDomain == currentDomain or targetDomain == "shared" then
                local classInstances = nodesByClass[targetClass] or {}
                for _, instanceId in ipairs(classInstances) do
                    dispatchToTarget(instanceId, signal, data, msgId)
                end
            end
        end
    end

    --[[
        Setup cross-domain RemoteEvent infrastructure.

        Server creates the RemoteEvent, client waits for it.
        Both sides set up listeners to receive cross-domain signals.
    --]]
    -- Track if we've connected event handlers (to avoid duplicate connections)
    local serverEventConnected = false
    local clientEventConnected = false

    local function setupCrossDomain()
        local ReplicatedStorage = game:GetService("ReplicatedStorage")

        if System.isServer then
            -- Server creates or reuses the RemoteEvent
            local existing = ReplicatedStorage:FindFirstChild(CROSS_DOMAIN_REMOTE_NAME)
            if existing then
                -- Reuse existing (don't destroy - clients may have references)
                crossDomainRemote = existing
                System.Debug.trace("IPC", "Cross-domain RemoteEvent reused (server)")
            else
                -- Create new
                crossDomainRemote = Instance.new("RemoteEvent")
                crossDomainRemote.Name = CROSS_DOMAIN_REMOTE_NAME
                crossDomainRemote.Parent = ReplicatedStorage
                System.Debug.trace("IPC", "Cross-domain RemoteEvent created (server)")
            end

            -- Server listens for client → server signals (only connect once)
            if not serverEventConnected then
                crossDomainRemote.OnServerEvent:Connect(function(player, sourceClass, signal, data)
                    System.Debug.trace("IPC", "Received cross-domain from client:", sourceClass, signal)
                    dispatchCrossDomainSignal(sourceClass, signal, data, player)
                end)
                serverEventConnected = true
                System.Debug.trace("IPC", "OnServerEvent handler connected")
            end
        else
            -- Client waits for or reuses the RemoteEvent
            if not crossDomainRemote or not crossDomainRemote.Parent then
                crossDomainRemote = ReplicatedStorage:WaitForChild(CROSS_DOMAIN_REMOTE_NAME, 10)
            end

            if crossDomainRemote then
                -- Client listens for server → client signals (only connect once)
                if not clientEventConnected then
                    crossDomainRemote.OnClientEvent:Connect(function(sourceClass, signal, data)
                        System.Debug.trace("IPC", "Received cross-domain from server:", sourceClass, signal)
                        dispatchCrossDomainSignal(sourceClass, signal, data, nil)
                    end)
                    clientEventConnected = true
                    System.Debug.trace("IPC", "OnClientEvent handler connected")
                end
            else
                System.Debug.warn("IPC", "Cross-domain RemoteEvent not found - cross-domain routing disabled")
            end
        end
    end

    --[[
        Send a signal across the client/server boundary.

        @param sourceClass string - Source node class name
        @param signal string - Signal name
        @param data table - Signal payload
        @param targetDomain string - "server" or "client"
    --]]
    sendCrossDomain = function(sourceClass, signal, data, targetDomain)
        if not crossDomainRemote then
            System.Debug.warn("IPC", "Cross-domain remote not available")
            return false
        end

        if targetDomain == "server" and not System.isServer then
            -- Client sending to server
            crossDomainRemote:FireServer(sourceClass, signal, data)
            System.Debug.trace("IPC", "Sent cross-domain to server:", sourceClass, signal)
            return true
        elseif targetDomain == "client" and System.isServer then
            -- Server sending to client(s)
            -- Check for player-specific targeting via _targetPlayer in data
            local targetPlayer = data and data._targetPlayer
            if targetPlayer and typeof(targetPlayer) == "Instance" and targetPlayer:IsA("Player") then
                -- Send to specific player
                crossDomainRemote:FireClient(targetPlayer, sourceClass, signal, data)
                System.Debug.trace("IPC", "Sent cross-domain to player:", targetPlayer.Name, sourceClass, signal)
            else
                -- Broadcast to all clients
                crossDomainRemote:FireAllClients(sourceClass, signal, data)
                System.Debug.trace("IPC", "Sent cross-domain to all clients:", sourceClass, signal)
            end
            return true
        end

        return false
    end

    ---------------------------------------------------------------------------
    -- LIFECYCLE
    ---------------------------------------------------------------------------

    --[[
        Initialize the IPC system.

        Calls onInit on all registered instances.
    --]]
    function IPC.init()
        if isInitialized then
            System.Debug.warn("IPC", "Already initialized")
            return
        end

        System.Debug.info("IPC", "Initializing...")

        -- Setup cross-domain routing infrastructure
        setupCrossDomain()

        -- Call onInit on all instances
        for id, instance in pairs(instances) do
            executeHandler(instance, "Sys", "onInit", {})
        end

        isInitialized = true
        System.Debug.info("IPC", "Initialized", IPC.getInstanceCount(), "instances")
    end

    --[[
        Start the IPC system.

        Enables message routing and calls onStart on all instances.
    --]]
    function IPC.start()
        if not isInitialized then
            error("[IPC.start] Must call IPC.init() first")
        end

        if isStarted then
            System.Debug.warn("IPC", "Already started")
            return
        end

        System.Debug.info("IPC", "Starting...")

        -- Call onStart on all instances
        for id, instance in pairs(instances) do
            executeHandler(instance, "Sys", "onStart", {})
        end

        isStarted = true
        System.Debug.info("IPC", "Started, routing enabled")
    end

    --[[
        Stop the IPC system.

        Disables routing and calls onStop on all instances.
    --]]
    function IPC.stop()
        if not isStarted then
            System.Debug.warn("IPC", "Not started")
            return
        end

        System.Debug.info("IPC", "Stopping...")

        -- Call onStop on all instances
        for id, instance in pairs(instances) do
            executeHandler(instance, "Sys", "onStop", {})
        end

        isStarted = false
        isInitialized = false

        System.Debug.info("IPC", "Stopped")
    end

    ---------------------------------------------------------------------------
    -- UTILITIES
    ---------------------------------------------------------------------------

    --[[
        Get count of registered instances.

        @return number - Instance count
    --]]
    function IPC.getInstanceCount()
        local count = 0
        for _ in pairs(instances) do
            count = count + 1
        end
        return count
    end

    --[[
        Get all registered node class names.

        @return table - Array of class names
    --]]
    function IPC.getNodeClasses()
        local result = {}
        for name in pairs(nodeDefinitions) do
            table.insert(result, name)
        end
        return result
    end

    --[[
        Get all defined mode names.

        @return table - Array of mode names
    --]]
    function IPC.getModes()
        local result = {}
        for name in pairs(modeConfigs) do
            table.insert(result, name)
        end
        return result
    end

    --[[
        Check if IPC is initialized.

        @return boolean
    --]]
    function IPC.isInitialized()
        return isInitialized
    end

    --[[
        Check if IPC is started.

        @return boolean
    --]]
    function IPC.isStarted()
        return isStarted
    end

    --[[
        Clear all state (for testing).
    --]]
    function IPC.reset()
        nodeDefinitions = {}
        instances = {}
        nodesByClass = {}
        modeConfigs = {}
        currentMode = nil
        messageCounter = 0
        seenMessages = {}
        isInitialized = false
        isStarted = false

        -- Clean up cross-domain state
        nodeDomains = {}
        crossDomainClasses = {}
        -- Note: Don't destroy crossDomainRemote here as it may be needed
        -- for other demos/systems running. It will be recreated on next init.

        System.Debug.info("IPC", "Reset complete")
    end

    return IPC
end)()

--[[
    ============================================================================
    ASSET SUBSYSTEM
    ============================================================================

    Asset manages node class registration, inheritance tree building, and
    model-first spawning. It bridges Node definitions with Roblox Instances.

    INHERITANCE MODEL
    -----------------

    Node (System default)
      └── Dispenser (Lib - reusable interface + defaults)
            └── MarshmallowBag (Game - specific implementation)

    Each layer can:
    - Add required handlers (contract enforcement)
    - Provide defaults (fallback implementations)
    - Override parent handlers (specialization)

    SPAWNING MODEL
    --------------

    Model-first: Workspace models have a NodeClass attribute that determines
    which node class to instantiate.

    ```lua
    -- Model in Workspace has attribute: NodeClass = "MarshmallowBag"
    Asset.spawn(model)  -- Creates MarshmallowBag instance attached to model
    ```

    BOOTSTRAP FLOW
    --------------

    1. Lib modules register: Asset.register(require(Lib.Dispenser))
    2. Game modules register: Asset.register(require(Game.MarshmallowBag))
    3. Verify all expected: Asset.verify({ "Dispenser", "MarshmallowBag" })
    4. Build tree: Asset.buildInheritanceTree()
    5. IPC.init() / IPC.start()

    USAGE
    -----

    ```lua
    local Asset = Lib.System.Asset

    -- Registration (in Bootstrap)
    Asset.register(require(Lib.Dispenser))
    Asset.register(require(Game.MarshmallowBag))

    -- Verification
    Asset.verify({ "Dispenser", "MarshmallowBag" })

    -- Build inheritance tree (for introspection/debugging)
    Asset.buildInheritanceTree()

    -- Model-first spawning (runtime)
    local model = workspace.RuntimeAssets.MarshmallowBag_1
    local instance = Asset.spawn(model)

    -- Despawn
    Asset.despawn(model)
    ```

--]]

System.Asset = (function()
    ---------------------------------------------------------------------------
    -- PRIVATE STATE (closure-protected)
    ---------------------------------------------------------------------------

    local registry = {}           -- { className → NodeClass }
    local modelToInstance = {}    -- { model → instanceId }
    local instanceToModel = {}    -- { instanceId → model }
    local inheritanceTree = {}    -- Built by buildInheritanceTree()
    local isTreeBuilt = false

    ---------------------------------------------------------------------------
    -- PRIVATE FUNCTIONS
    ---------------------------------------------------------------------------

    --[[
        Get the parent class name from a NodeClass.

        @param NodeClass table - The node class
        @return string|nil - Parent class name or nil if Node (root)
    --]]
    local function getParentClassName(NodeClass)
        local parent = NodeClass._parent
        if not parent or not parent.name then
            return nil
        end
        -- "Node" is the root, don't include it as a named parent
        if parent.name == nil and parent == System.Node then
            return nil
        end
        return parent.name
    end

    --[[
        Build the inheritance chain for a class (bottom-up).

        @param className string - Class name
        @return table - Array of class names from root to leaf
    --]]
    local function buildChain(className)
        local chain = {}
        local current = registry[className]

        while current do
            table.insert(chain, 1, current.name or "Node")
            current = current._parent
            -- Stop at Node base
            if current and not current.name then
                table.insert(chain, 1, "Node")
                break
            end
        end

        return chain
    end

    ---------------------------------------------------------------------------
    -- PUBLIC API
    ---------------------------------------------------------------------------

    local Asset = {}

    ---------------------------------------------------------------------------
    -- REGISTRATION
    ---------------------------------------------------------------------------

    --[[
        Register a node class with the Asset system.

        The class must have been created via Node.extend() and have a name.
        Registration also registers with IPC for instance management.

        @param NodeClass table - Node class (result of Node.extend)
        @return boolean - True if registration successful
    --]]
    function Asset.register(NodeClass)
        if not NodeClass then
            error("[Asset.register] NodeClass required")
        end

        if not NodeClass.name then
            error("[Asset.register] NodeClass must have a name")
        end

        local name = NodeClass.name

        if registry[name] then
            System.Debug.warn("Asset", "Class already registered:", name)
            return false
        end

        -- Register with Asset
        registry[name] = NodeClass

        -- Also register with IPC for instance management
        System.IPC.registerNode(NodeClass)

        System.Debug.trace("Asset", "Registered:", name)
        return true
    end

    --[[
        Get a registered node class by name.

        @param className string - Class name
        @return table|nil - NodeClass or nil if not found
    --]]
    function Asset.get(className)
        return registry[className]
    end

    --[[
        Get all registered class names.

        @return table - Array of class names
    --]]
    function Asset.getAll()
        local result = {}
        for name in pairs(registry) do
            table.insert(result, name)
        end
        return result
    end

    --[[
        Check if a class is registered.

        @param className string - Class name
        @return boolean
    --]]
    function Asset.isRegistered(className)
        return registry[className] ~= nil
    end

    ---------------------------------------------------------------------------
    -- VERIFICATION
    ---------------------------------------------------------------------------

    --[[
        Verify that all expected classes are registered.

        Call this after all registrations to catch missing modules early.
        Throws an error listing all missing classes.

        @param expectedClasses table - Array of expected class names
        @return boolean - True if all present (or throws error)
    --]]
    function Asset.verify(expectedClasses)
        if not expectedClasses or #expectedClasses == 0 then
            return true
        end

        local missing = {}

        for _, className in ipairs(expectedClasses) do
            if not registry[className] then
                table.insert(missing, className)
            end
        end

        if #missing > 0 then
            local msg = string.format(
                "[BOOT ERROR] Missing required node classes:\n  - %s\n\nEnsure these modules are required and registered in Bootstrap.",
                table.concat(missing, "\n  - ")
            )
            error(msg)
        end

        System.Debug.info("Asset", "Verified", #expectedClasses, "classes")
        return true
    end

    ---------------------------------------------------------------------------
    -- INHERITANCE TREE
    ---------------------------------------------------------------------------

    --[[
        Build the inheritance tree for all registered classes.

        Creates a tree structure showing parent-child relationships.
        Call this after all registrations for introspection/debugging.

        @return table - Tree structure { Node = { children = { Dispenser = { children = { ... } } } } }
    --]]
    function Asset.buildInheritanceTree()
        inheritanceTree = { name = "Node", children = {} }

        -- Build chains for all registered classes
        local chains = {}
        for className in pairs(registry) do
            chains[className] = buildChain(className)
        end

        -- Insert each chain into the tree
        for className, chain in pairs(chains) do
            local current = inheritanceTree

            for i, nodeName in ipairs(chain) do
                if nodeName ~= "Node" then  -- Skip root
                    -- Find or create child
                    local found = nil
                    for _, child in ipairs(current.children) do
                        if child.name == nodeName then
                            found = child
                            break
                        end
                    end

                    if not found then
                        found = { name = nodeName, children = {} }
                        table.insert(current.children, found)
                    end

                    current = found
                end
            end
        end

        isTreeBuilt = true
        System.Debug.info("Asset", "Built inheritance tree for", #Asset.getAll(), "classes")

        return inheritanceTree
    end

    --[[
        Get the inheritance tree.

        @return table - Tree structure (call buildInheritanceTree first)
    --]]
    function Asset.getInheritanceTree()
        if not isTreeBuilt then
            Asset.buildInheritanceTree()
        end
        return inheritanceTree
    end

    --[[
        Get the inheritance chain for a specific class.

        @param className string - Class name
        @return table - Array from root to leaf, e.g., { "Node", "Dispenser", "MarshmallowBag" }
    --]]
    function Asset.getChain(className)
        if not registry[className] then
            return {}
        end
        return buildChain(className)
    end

    --[[
        Print the inheritance tree to output (for debugging).
    --]]
    function Asset.printTree()
        if not isTreeBuilt then
            Asset.buildInheritanceTree()
        end

        local function printNode(node, indent)
            indent = indent or 0
            local prefix = string.rep("  ", indent)
            print(prefix .. (indent > 0 and "└── " or "") .. node.name)
            for _, child in ipairs(node.children) do
                printNode(child, indent + 1)
            end
        end

        print("\n=== Inheritance Tree ===")
        printNode(inheritanceTree)
        print("========================\n")
    end

    ---------------------------------------------------------------------------
    -- SPAWNING (Model-First)
    ---------------------------------------------------------------------------

    --[[
        Spawn a node instance for a Roblox model.

        Reads the "NodeClass" attribute from the model to determine which
        class to instantiate. The instance is registered with IPC.

        @param model Instance - Roblox model with NodeClass attribute
        @param config table (optional) - Additional config to merge
        @return table|nil - Node instance or nil if failed
    --]]
    function Asset.spawn(model)
        if not model then
            error("[Asset.spawn] Model required")
        end

        -- Check if already spawned
        if modelToInstance[model] then
            System.Debug.warn("Asset", "Model already spawned:", model:GetFullName())
            return System.IPC.getInstance(modelToInstance[model])
        end

        -- Read NodeClass attribute
        local className = model:GetAttribute("NodeClass")
        if not className then
            System.Debug.warn("Asset", "Model missing NodeClass attribute:", model:GetFullName())
            return nil
        end

        -- Check if class is registered
        if not registry[className] then
            System.Debug.warn("Asset", "Unknown NodeClass:", className, "on", model:GetFullName())
            return nil
        end

        -- Generate instance ID from model
        local instanceId = model.Name .. "_" .. tostring(model:GetAttribute("InstanceId") or model:GetDebugId())

        -- Create instance via IPC.spawn (handles lifecycle)
        local instance = System.IPC.spawn(className, {
            id = instanceId,
            model = model,
        })

        if instance then
            -- Track model ↔ instance mapping
            modelToInstance[model] = instanceId
            instanceToModel[instanceId] = model

            System.Debug.trace("Asset", "Spawned", className, "for", model.Name, "as", instanceId)
        end

        return instance
    end

    --[[
        Despawn a node instance by its model.

        @param model Instance - The Roblox model
    --]]
    function Asset.despawn(model)
        if not model then
            return
        end

        local instanceId = modelToInstance[model]
        if not instanceId then
            System.Debug.warn("Asset", "No instance found for model:", model:GetFullName())
            return
        end

        -- Despawn via IPC (handles lifecycle)
        System.IPC.despawn(instanceId)

        -- Clean up mappings
        modelToInstance[model] = nil
        instanceToModel[instanceId] = nil

        System.Debug.trace("Asset", "Despawned instance for", model.Name)
    end

    --[[
        Get the instance for a model.

        @param model Instance - The Roblox model
        @return table|nil - Node instance or nil
    --]]
    function Asset.getInstanceForModel(model)
        local instanceId = modelToInstance[model]
        if not instanceId then
            return nil
        end
        return System.IPC.getInstance(instanceId)
    end

    --[[
        Get the model for an instance.

        @param instanceId string - Instance ID
        @return Instance|nil - Roblox model or nil
    --]]
    function Asset.getModelForInstance(instanceId)
        return instanceToModel[instanceId]
    end

    --[[
        Spawn all models under a container that have NodeClass attribute.

        @param container Instance - Container to scan (e.g., workspace.RuntimeAssets)
        @return table - Array of spawned instances
    --]]
    function Asset.spawnAll(container)
        local spawned = {}

        for _, child in ipairs(container:GetDescendants()) do
            if child:GetAttribute("NodeClass") then
                local instance = Asset.spawn(child)
                if instance then
                    table.insert(spawned, instance)
                end
            end
        end

        System.Debug.info("Asset", "Spawned", #spawned, "instances from", container.Name)
        return spawned
    end

    --[[
        Despawn all tracked instances.
    --]]
    function Asset.despawnAll()
        local count = 0
        for model in pairs(modelToInstance) do
            Asset.despawn(model)
            count = count + 1
        end
        System.Debug.info("Asset", "Despawned", count, "instances")
    end

    ---------------------------------------------------------------------------
    -- UTILITIES
    ---------------------------------------------------------------------------

    --[[
        Get count of spawned instances.

        @return number
    --]]
    function Asset.getSpawnedCount()
        local count = 0
        for _ in pairs(modelToInstance) do
            count = count + 1
        end
        return count
    end

    --[[
        Reset all state (for testing).
    --]]
    function Asset.reset()
        -- Despawn all first
        for model in pairs(modelToInstance) do
            local instanceId = modelToInstance[model]
            if instanceId then
                System.IPC.despawn(instanceId)
            end
        end

        registry = {}
        modelToInstance = {}
        instanceToModel = {}
        inheritanceTree = {}
        isTreeBuilt = false

        System.Debug.info("Asset", "Reset complete")
    end

    return Asset
end)()

--[[
    ============================================================================
    INPUTCAPTURE SUBSYSTEM
    ============================================================================

    InputCapture is a client-side service that manages raw input capture with
    exclusive focus. Only one consumer can "claim" input at a time.

    This is the system-level input routing layer. It captures raw inputs from
    UserInputService and routes them to the current claimant.

    DESIGN
    ------

    InputCapture follows a "claim/release" model:
    - A consumer calls claim() to take exclusive input focus
    - While claimed, all inputs are routed to the claimant's handlers
    - The claimant calls release() when done
    - Only one claim can be active at a time

    This is intentionally low-level. Higher-level abstractions (like
    InputTranslator component) can build on top of this.

    USAGE
    -----

    ```lua
    local InputCapture = Lib.System.InputCapture

    -- Claim input focus
    local claim = InputCapture.claim({
        onInputBegan = function(input, gameProcessed)
            if input.KeyCode == Enum.KeyCode.Space then
                print("Space pressed!")
            end
        end,
        onInputEnded = function(input, gameProcessed)
            -- Handle key release
        end,
        onInputChanged = function(input, gameProcessed)
            -- Handle analog input (thumbsticks, mouse movement)
        end,
    })

    -- Later, release the claim
    claim:release()

    -- Or check status
    if InputCapture.hasClaim() then
        print("Something has input focus")
    end
    ```

    CLIENT-ONLY
    -----------

    This subsystem only runs on clients. On server, all methods are no-ops
    that return nil or false.

--]]

System.InputCapture = (function()
    ---------------------------------------------------------------------------
    -- SERVICES
    ---------------------------------------------------------------------------

    local UserInputService = game:GetService("UserInputService")
    local Players = game:GetService("Players")

    ---------------------------------------------------------------------------
    -- PRIVATE STATE (closure-protected)
    ---------------------------------------------------------------------------

    local currentClaim = nil          -- Current active claim object
    local claimIdCounter = 0          -- Unique ID generator
    local connections = {}            -- UserInputService connections
    local savedControlsState = nil    -- Saved player controls state for restoration

    -- Control mapping state (for claimForNode)
    local mappingLookups = nil        -- Built from Node.Controls
    local activeActions = {}          -- actionName -> true/false
    local holdState = {}              -- actionName -> { startTime = number }
    local heartbeatConnection = nil   -- For hold-action progress updates
    local mappedNode = nil            -- Node instance receiving action callbacks

    ---------------------------------------------------------------------------
    -- PRIVATE FUNCTIONS
    ---------------------------------------------------------------------------

    --[[
        Set up UserInputService connections when first claim is made.
    --]]
    --[[
        Disable player movement controls.
        Saves state for restoration later.
    --]]
    local function disablePlayerControls()
        if System.isServer then
            System.Debug.info("InputCapture", "disablePlayerControls: skipping (server)")
            return
        end

        local player = Players.LocalPlayer
        if not player then
            System.Debug.info("InputCapture", "disablePlayerControls: no LocalPlayer")
            return
        end

        local character = player.Character
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")

        -- Save original speeds and set to 0
        if humanoid then
            savedControlsState = {
                walkSpeed = humanoid.WalkSpeed,
                jumpPower = humanoid.JumpPower,
                jumpHeight = humanoid.JumpHeight,
                humanoid = humanoid,
            }
            humanoid.WalkSpeed = 0
            humanoid.JumpPower = 0
            humanoid.JumpHeight = 0
            System.Debug.info("InputCapture", "Player movement disabled (WalkSpeed=0)")
        else
            System.Debug.info("InputCapture", "disablePlayerControls: no Humanoid found")
        end
    end

    --[[
        Restore player movement controls.
    --]]
    local function enablePlayerControls()
        if System.isServer then return end

        if savedControlsState and savedControlsState.humanoid then
            local humanoid = savedControlsState.humanoid
            if humanoid and humanoid.Parent then
                humanoid.WalkSpeed = savedControlsState.walkSpeed or 16
                humanoid.JumpPower = savedControlsState.jumpPower or 50
                humanoid.JumpHeight = savedControlsState.jumpHeight or 7.2
                System.Debug.info("InputCapture", "Player movement restored")
            end
            savedControlsState = nil
        end
    end

    local function setupConnections()
        if #connections > 0 then
            return  -- Already connected
        end

        -- InputBegan (key/button press)
        connections[1] = UserInputService.InputBegan:Connect(function(input, gameProcessed)
            System.Debug.info("InputCapture", "InputBegan:", input.KeyCode.Name, "hasClaim:", currentClaim ~= nil)
            if currentClaim and currentClaim.handlers.onInputBegan then
                currentClaim.handlers.onInputBegan(input, gameProcessed)
            end
        end)

        -- InputEnded (key/button release)
        connections[2] = UserInputService.InputEnded:Connect(function(input, gameProcessed)
            if currentClaim and currentClaim.handlers.onInputEnded then
                currentClaim.handlers.onInputEnded(input, gameProcessed)
            end
        end)

        -- InputChanged (analog input: thumbsticks, mouse movement)
        connections[3] = UserInputService.InputChanged:Connect(function(input, gameProcessed)
            if currentClaim and currentClaim.handlers.onInputChanged then
                currentClaim.handlers.onInputChanged(input, gameProcessed)
            end
        end)

        System.Debug.info("InputCapture", "Connections established")
    end

    --[[
        Tear down UserInputService connections when no claims exist.
    --]]
    local function teardownConnections()
        for _, connection in ipairs(connections) do
            if connection then
                connection:Disconnect()
            end
        end
        connections = {}
        System.Debug.trace("InputCapture", "Connections torn down")
    end

    ---------------------------------------------------------------------------
    -- CONTROL MAPPING SYSTEM
    ---------------------------------------------------------------------------

    --[[
        Build reverse lookup tables from a Controls mapping.

        @param controls table - Control mapping from Node.Controls
        @return table - { keyToActions, buttonToActions, axisConfigs, holdActions }

        Example input:
            {
                aimUp = {
                    keys = { Enum.KeyCode.Up },
                    buttons = { Enum.KeyCode.DPadUp },
                    axis = { stick = "Thumbstick1", direction = "Y+", deadzone = 0.2 },
                },
                fire = {
                    keys = { Enum.KeyCode.Space },
                    buttons = { Enum.KeyCode.ButtonA },
                },
                exit = {
                    keys = { Enum.KeyCode.E },
                    holdDuration = 1.5,
                },
            }
    --]]
    local function buildMappingLookups(controls)
        local keyToActions = {}      -- KeyCode -> { actionName, ... }
        local buttonToActions = {}   -- KeyCode -> { actionName, ... }
        local axisConfigs = {}       -- "Thumbstick1" -> { { action, axis, direction, deadzone }, ... }
        local holdActions = {}       -- actionName -> holdDuration

        for actionName, config in pairs(controls) do
            -- Keys (keyboard)
            if config.keys then
                for _, keyCode in ipairs(config.keys) do
                    keyToActions[keyCode] = keyToActions[keyCode] or {}
                    table.insert(keyToActions[keyCode], actionName)
                end
            end

            -- Buttons (gamepad)
            if config.buttons then
                for _, buttonCode in ipairs(config.buttons) do
                    buttonToActions[buttonCode] = buttonToActions[buttonCode] or {}
                    table.insert(buttonToActions[buttonCode], actionName)
                end
            end

            -- Axis (analog stick)
            if config.axis then
                local axisConfig = config.axis
                local stick = axisConfig.stick or "Thumbstick1"
                local direction = axisConfig.direction or "Y+"
                local deadzone = axisConfig.deadzone or 0.2

                -- Parse direction: "X+", "X-", "Y+", "Y-"
                local axisLetter = direction:sub(1, 1)  -- "X" or "Y"
                local axisSign = direction:sub(2, 2)    -- "+" or "-"

                axisConfigs[stick] = axisConfigs[stick] or {}
                table.insert(axisConfigs[stick], {
                    action = actionName,
                    axis = axisLetter,
                    positive = (axisSign == "+"),
                    deadzone = deadzone,
                })
            end

            -- Hold duration
            if config.holdDuration then
                holdActions[actionName] = config.holdDuration
            end
        end

        return {
            keyToActions = keyToActions,
            buttonToActions = buttonToActions,
            axisConfigs = axisConfigs,
            holdActions = holdActions,
        }
    end

    ---------------------------------------------------------------------------
    -- CLAIM OBJECT
    ---------------------------------------------------------------------------

    --[[
        Create a claim object that represents ownership of input focus.

        @param id number - Unique claim ID
        @param handlers table - Handler functions
        @return table - Claim object with :release() method
    --]]
    local function createClaimObject(id, handlers)
        local claim = {
            id = id,
            handlers = handlers,
            active = true,
        }

        --[[
            Release this claim, giving up input focus.

            Safe to call multiple times (subsequent calls are no-ops).
        --]]
        function claim:release()
            if not self.active then
                return  -- Already released
            end

            self.active = false

            -- Only clear if this is still the current claim
            if currentClaim and currentClaim.id == self.id then
                currentClaim = nil

                -- Restore player controls if we disabled them
                if self.disabledCharacter then
                    enablePlayerControls()
                end

                -- Call onRelease handler if provided
                if self.handlers.onRelease then
                    self.handlers.onRelease()
                end

                System.Debug.info("InputCapture", "Claim released:", self.id)

                -- Note: We keep connections alive for efficiency
                -- They'll be cleaned up if InputCapture.shutdown() is called
            end
        end

        --[[
            Check if this claim is still active.

            @return boolean
        --]]
        function claim:isActive()
            return self.active and currentClaim and currentClaim.id == self.id
        end

        return claim
    end

    ---------------------------------------------------------------------------
    -- PUBLIC API
    ---------------------------------------------------------------------------

    local InputCapture = {}

    --[[
        Claim exclusive input focus.

        Only one claim can be active at a time. If another claim exists,
        it will be forcibly released before the new claim takes over.

        @param handlers table - Handler functions:
            onInputBegan(input, gameProcessed) - Called on key/button press
            onInputEnded(input, gameProcessed) - Called on key/button release
            onInputChanged(input, gameProcessed) - Called on analog input
            onRelease() - Called when this claim is released
        @param options table (optional) - Options:
            disableCharacter: boolean - Disable player movement while claimed
        @return table|nil - Claim object with :release() method, or nil on server
    --]]
    function InputCapture.claim(handlers, options)
        -- Client-only
        if System.isServer then
            System.Debug.info("InputCapture", "Claim ignored on server")
            return nil
        end

        System.Debug.info("InputCapture", "Claiming input focus...")

        handlers = handlers or {}
        options = options or {}

        -- If there's an existing claim, release it first
        if currentClaim then
            System.Debug.info("InputCapture", "Releasing existing claim:", currentClaim.id)
            currentClaim:release()
        end

        -- Ensure connections are set up
        setupConnections()

        -- Create new claim
        claimIdCounter = claimIdCounter + 1
        local claim = createClaimObject(claimIdCounter, handlers)
        claim.disabledCharacter = options.disableCharacter or false
        currentClaim = claim

        -- Disable player controls if requested
        if claim.disabledCharacter then
            disablePlayerControls()
        end

        -- Call onClaim handler if provided
        if handlers.onClaim then
            handlers.onClaim()
        end

        System.Debug.info("InputCapture", "New claim established:", claim.id, "disableCharacter:", claim.disabledCharacter)
        return claim
    end

    --[[
        Claim exclusive input focus for a Node with declarative Controls mapping.

        The node must have a Controls table defined. InputCapture will translate
        raw inputs to named actions and call the node's In handlers:
            - In.onActionBegan(self, actionName)
            - In.onActionEnded(self, actionName)
            - In.onActionHeld(self, actionName, progress)  -- for hold-duration actions
            - In.onActionTriggered(self, actionName)       -- when hold-duration reached
            - In.onControlReleased(self)                   -- if forcibly released

        @param node table - Node instance with Controls table
        @param options table (optional) - Options:
            disableCharacter: boolean - Disable player movement while claimed
        @return table|nil - Claim object with :release() method, or nil on server/error
    --]]
    function InputCapture.claimForNode(node, options)
        -- Client-only
        if System.isServer then
            System.Debug.info("InputCapture", "claimForNode ignored on server")
            return nil
        end

        -- Validate node has Controls
        local controls = node.Controls or (node._definition and node._definition.Controls)
        if not controls then
            System.Debug.warn("InputCapture", "claimForNode: node has no Controls table")
            return nil
        end

        System.Debug.info("InputCapture", "claimForNode for:", node.id or node.name or "unknown")

        options = options or {}

        -- Build mapping lookups
        mappingLookups = buildMappingLookups(controls)
        mappedNode = node

        -- Reset action state
        activeActions = {}
        holdState = {}

        -- Internal handlers that translate raw input to actions
        local function handleInputBegan(input, gameProcessed)
            local keyCode = input.KeyCode

            -- Check keys and buttons
            local actions = mappingLookups.keyToActions[keyCode]
                or mappingLookups.buttonToActions[keyCode]

            if actions then
                for _, actionName in ipairs(actions) do
                    if not activeActions[actionName] then
                        activeActions[actionName] = true

                        -- Start hold tracking if this is a hold-action
                        if mappingLookups.holdActions[actionName] then
                            holdState[actionName] = { startTime = tick() }
                        end

                        -- Call node's onActionBegan
                        if mappedNode.In and mappedNode.In.onActionBegan then
                            mappedNode.In.onActionBegan(mappedNode, actionName)
                        end
                    end
                end
            end
        end

        local function handleInputEnded(input, gameProcessed)
            local keyCode = input.KeyCode

            -- Check keys and buttons
            local actions = mappingLookups.keyToActions[keyCode]
                or mappingLookups.buttonToActions[keyCode]

            if actions then
                for _, actionName in ipairs(actions) do
                    if activeActions[actionName] then
                        activeActions[actionName] = false

                        -- Clear hold state
                        holdState[actionName] = nil

                        -- Call node's onActionEnded
                        if mappedNode.In and mappedNode.In.onActionEnded then
                            mappedNode.In.onActionEnded(mappedNode, actionName)
                        end
                    end
                end
            end
        end

        local function handleInputChanged(input, gameProcessed)
            local keyCode = input.KeyCode

            -- Check for thumbstick input
            local stickName = nil
            if keyCode == Enum.KeyCode.Thumbstick1 then
                stickName = "Thumbstick1"
            elseif keyCode == Enum.KeyCode.Thumbstick2 then
                stickName = "Thumbstick2"
            end

            if stickName and mappingLookups.axisConfigs[stickName] then
                local pos = input.Position

                for _, axisConfig in ipairs(mappingLookups.axisConfigs[stickName]) do
                    local actionName = axisConfig.action
                    local deadzone = axisConfig.deadzone
                    local axisValue = (axisConfig.axis == "X") and pos.X or pos.Y

                    -- Check if axis is past deadzone in the correct direction
                    local isActive = false
                    if axisConfig.positive then
                        isActive = axisValue > deadzone
                    else
                        isActive = axisValue < -deadzone
                    end

                    -- Handle state change
                    local wasActive = activeActions[actionName]
                    if isActive and not wasActive then
                        activeActions[actionName] = true

                        -- Start hold tracking if this is a hold-action
                        if mappingLookups.holdActions[actionName] then
                            holdState[actionName] = { startTime = tick() }
                        end

                        if mappedNode.In and mappedNode.In.onActionBegan then
                            mappedNode.In.onActionBegan(mappedNode, actionName)
                        end
                    elseif not isActive and wasActive then
                        activeActions[actionName] = false
                        holdState[actionName] = nil

                        if mappedNode.In and mappedNode.In.onActionEnded then
                            mappedNode.In.onActionEnded(mappedNode, actionName)
                        end
                    end
                end
            end
        end

        -- Set up Heartbeat for hold-action progress
        local RunService = game:GetService("RunService")
        if heartbeatConnection then
            heartbeatConnection:Disconnect()
        end

        heartbeatConnection = RunService.Heartbeat:Connect(function(dt)
            if not mappedNode then return end

            for actionName, state in pairs(holdState) do
                local holdDuration = mappingLookups.holdActions[actionName]
                if holdDuration and state.startTime then
                    local elapsed = tick() - state.startTime
                    local progress = math.clamp(elapsed / holdDuration, 0, 1)

                    -- Call onActionHeld with progress
                    if mappedNode.In and mappedNode.In.onActionHeld then
                        mappedNode.In.onActionHeld(mappedNode, actionName, progress)
                    end

                    -- Check if hold duration reached
                    if elapsed >= holdDuration and not state.triggered then
                        state.triggered = true

                        if mappedNode.In and mappedNode.In.onActionTriggered then
                            mappedNode.In.onActionTriggered(mappedNode, actionName)
                        end
                    end
                end
            end
        end)

        -- Create handlers for base claim
        local handlers = {
            onInputBegan = handleInputBegan,
            onInputEnded = handleInputEnded,
            onInputChanged = handleInputChanged,
            onRelease = function()
                -- Clean up mapping state
                if heartbeatConnection then
                    heartbeatConnection:Disconnect()
                    heartbeatConnection = nil
                end

                mappingLookups = nil
                activeActions = {}
                holdState = {}

                -- Call node's onControlReleased
                if mappedNode and mappedNode.In and mappedNode.In.onControlReleased then
                    mappedNode.In.onControlReleased(mappedNode)
                end

                mappedNode = nil
            end,
        }

        -- Use base claim() to handle connections and player controls
        return InputCapture.claim(handlers, options)
    end

    --[[
        Check if there is an active claim.

        @return boolean
    --]]
    function InputCapture.hasClaim()
        return currentClaim ~= nil and currentClaim.active
    end

    --[[
        Get the current claim object (if any).

        @return table|nil - Current claim or nil
    --]]
    function InputCapture.getCurrentClaim()
        return currentClaim
    end

    --[[
        Force release any active claim.

        Use sparingly - prefer letting the claimant release naturally.
    --]]
    function InputCapture.forceRelease()
        if currentClaim then
            currentClaim:release()
        end
    end

    --[[
        Get input device information.

        @return table - { keyboard, mouse, touch, gamepad }
    --]]
    function InputCapture.getDeviceInfo()
        if System.isServer then
            return { keyboard = false, mouse = false, touch = false, gamepad = false }
        end

        return {
            keyboard = UserInputService.KeyboardEnabled,
            mouse = UserInputService.MouseEnabled,
            touch = UserInputService.TouchEnabled,
            gamepad = UserInputService.GamepadEnabled,
        }
    end

    --[[
        Check if a specific key is currently pressed.

        @param keyCode Enum.KeyCode - The key to check
        @return boolean
    --]]
    function InputCapture.isKeyDown(keyCode)
        if System.isServer then
            return false
        end
        return UserInputService:IsKeyDown(keyCode)
    end

    --[[
        Check if a gamepad button is currently pressed.

        @param gamepad Enum.UserInputType - The gamepad (e.g., Gamepad1)
        @param button Enum.KeyCode - The button to check
        @return boolean
    --]]
    function InputCapture.isGamepadButtonDown(gamepad, button)
        if System.isServer then
            return false
        end

        local success, result = pcall(function()
            return UserInputService:IsGamepadButtonDown(gamepad, button)
        end)

        return success and result
    end

    --[[
        Shutdown the InputCapture system.

        Releases any active claim and disconnects all UserInputService listeners.
    --]]
    function InputCapture.shutdown()
        if currentClaim then
            currentClaim:release()
        end
        teardownConnections()
        System.Debug.info("InputCapture", "Shutdown complete")
    end

    --[[
        Reset all state (for testing).
    --]]
    function InputCapture.reset()
        InputCapture.shutdown()
        currentClaim = nil
        claimIdCounter = 0
        System.Debug.info("InputCapture", "Reset complete")
    end

    return InputCapture
end)()

--------------------------------------------------------------------------------
-- SYSTEM.ATTRIBUTE - Reactive Attribute/Modifier System
--------------------------------------------------------------------------------

--[[
    System.Attribute provides a reactive attribute system for entities.

    Features:
    - Base values with schema validation (type, min, max, default)
    - Modifier stacking (additive, multiplicative, override)
    - Derived/computed values with dependency tracking
    - Subscription system for change notifications
    - Selective client replication

    Usage:
    ```lua
    local attrs = System.Attribute.createSet({
        health = { type = "number", default = 100, min = 0, replicate = true },
        defense = { type = "number", default = 10 },
        effectiveDefense = {
            type = "number",
            derived = true,
            dependencies = { "defense" },
            compute = function(values, mods)
                return values.defense + (mods.additive or 0)
            end,
        },
    })

    local modId = attrs:applyModifier("defense", {
        operation = "additive",
        value = 5,
        source = "armor",
    })

    attrs:subscribe("health", function(new, old, name)
        print("Health changed:", old, "→", new)
    end)
    ```
--]]

System.Attribute = (function()
    local Attribute = {}

    -- Internal: Lazy load AttributeSet to avoid circular dependencies
    local AttributeSet = nil
    local function getAttributeSet()
        if not AttributeSet then
            -- During runtime, require from Internal
            local Internal = script.Parent.Internal
            if Internal and Internal:FindFirstChild("AttributeSet") then
                AttributeSet = require(Internal.AttributeSet)
            else
                error("[System.Attribute] AttributeSet module not found")
            end
        end
        return AttributeSet
    end

    -- Track all created attribute sets (for replication, debugging)
    local allSets = {}
    local setIdCounter = 0

    --[[
        Create a new AttributeSet with the given schema.

        @param schema table - Attribute definitions
        @param options table? - Optional settings { id?, entityId? }
        @return AttributeSet
    --]]
    function Attribute.createSet(schema, options)
        options = options or {}

        local AS = getAttributeSet()
        local set = AS.new(schema)

        -- Assign ID for tracking
        setIdCounter = setIdCounter + 1
        local setId = options.id or ("attrset_" .. setIdCounter)

        -- Store metadata
        set._setId = setId
        set._entityId = options.entityId

        -- Track for debugging/replication
        allSets[setId] = set

        System.Debug.trace("Attribute", "Created attribute set:", setId)

        return set
    end

    --[[
        Destroy an attribute set and remove from tracking.

        @param set AttributeSet - The set to destroy
    --]]
    function Attribute.destroySet(set)
        if set and set._setId then
            allSets[set._setId] = nil
            System.Debug.trace("Attribute", "Destroyed attribute set:", set._setId)
        end
    end

    --[[
        Get an attribute set by ID.

        @param setId string - The set ID
        @return AttributeSet|nil
    --]]
    function Attribute.getSet(setId)
        return allSets[setId]
    end

    --[[
        Get all tracked attribute sets.

        @return table - { setId = AttributeSet, ... }
    --]]
    function Attribute.getAllSets()
        return allSets
    end

    --[[
        Get debug information about all attribute sets.

        @return table
    --]]
    function Attribute.getDebugInfo()
        local count = 0
        local totalModifiers = 0
        local totalAttributes = 0

        for setId, set in pairs(allSets) do
            count = count + 1
            local info = set:getDebugInfo()
            totalModifiers = totalModifiers + info.modifierCount
            totalAttributes = totalAttributes + info.attributeCount
        end

        return {
            setCount = count,
            totalModifiers = totalModifiers,
            totalAttributes = totalAttributes,
        }
    end

    --[[
        Reset all state (for testing).
    --]]
    function Attribute.reset()
        allSets = {}
        setIdCounter = 0
        System.Debug.info("Attribute", "Reset complete")
    end

    -- Modifier operation types (for reference)
    Attribute.Operations = {
        ADDITIVE = "additive",
        MULTIPLICATIVE = "multiplicative",
        OVERRIDE = "override",
    }

    return Attribute
end)()

--------------------------------------------------------------------------------
-- PLACEHOLDER SUBSYSTEMS (to be implemented)
--------------------------------------------------------------------------------

System.State = {}    -- Shared state management
System.Store = {}    -- Persistent storage
System.View = {}     -- Presentation layer

--------------------------------------------------------------------------------
-- GLOBAL LIFECYCLE
--------------------------------------------------------------------------------

--[[
    Stop all running nodes across the entire framework.

    This is a convenience function that:
    1. Stops all IPC-managed instances (calls IPC.stop())
    2. Stops all nodes in Node.Registry (calls Registry.stopAll())

    Use this to cleanly shut down everything before running tests,
    switching game modes, or cleaning up demos.

    @return table - { ipcStopped: boolean, registryStopped: number }
--]]
function System.stopAll()
    local result = {
        ipcStopped = false,
        registryStopped = 0,
    }

    -- Stop IPC-managed instances
    if System.IPC then
        local success, err = pcall(function()
            System.IPC.stop()
        end)
        result.ipcStopped = success
        if not success then
            System.Debug.warn("System", "IPC.stop() error:", tostring(err))
        end
    end

    -- Stop all nodes in Registry
    local Node = require(script.Parent.Node)
    if Node and Node.Registry then
        local success, count = pcall(function()
            return Node.Registry.stopAll()
        end)
        if success then
            result.registryStopped = count
        else
            System.Debug.warn("System", "Registry.stopAll() error:", tostring(count))
        end
    end

    System.Debug.info("System", "stopAll complete - IPC:", result.ipcStopped, "Registry:", result.registryStopped)

    return result
end

return System
