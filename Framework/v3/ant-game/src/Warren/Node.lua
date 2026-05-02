--[[
    Warren Framework v2
    Node.lua - Base Node Class

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    Nodes are self-contained units of game logic with standard I/O pins.
    They communicate via events routed through the IPC system.

    Analogy: Nodes are like integrated circuits (ICUs) on a breadboard.
    The IPC system provides the wiring between them based on the active run mode.

    ============================================================================
    PIN MODEL
    ============================================================================

    Every node has these standard pins:

        Sys.In  - Control signals from system (lifecycle)
        In      - Game signals from other nodes (via wiring)
        Out     - Outbound signals to other nodes (via wiring)
        Err     - Error propagation back to system

    Nodes can also have mode-specific pins:

        Tutorial.In   - Tutorial mode input handlers
        Tutorial.Out  - Tutorial mode output (documentation)
        Playing.In    - Playing mode input handlers

    ============================================================================
    USAGE
    ============================================================================

    ```lua
    local Node = require(game.ReplicatedStorage.Warren.Node)

    -- Define a node type
    local Dropper = Node.extend({
        name = "Dropper",
        domain = "server",

        Sys = {
            onInit = function(self)
                self:setAttribute("Remaining", self:getAttribute("MaxItems") or 10)
            end,
            onStart = function(self) end,
            onStop = function(self) end,
        },

        In = {
            onDrop = function(self, data)
                local remaining = self:getAttribute("Remaining")
                if remaining > 0 then
                    self:setAttribute("Remaining", remaining - 1)
                    self.Out:Fire("dropped", { count = remaining - 1 })
                end
            end,
        },
    })

    -- Create an instance
    local instance = Dropper:new({
        id = "Dropper_1",
        model = workspace.Dropper_1,
    })
    ```

    ============================================================================
    INHERITANCE
    ============================================================================

    Nodes support prototype inheritance via extend():

    ```lua
    -- Base dispenser (in Lib)
    local Dispenser = Node.extend({
        name = "Dispenser",
        required = { In = { "onDispense" } },
        defaults = {
            In = {
                onRefill = function(self, count) ... end,
            },
        },
    })

    -- Game-specific implementation
    local MarshmallowBag = Dispenser.extend({
        name = "MarshmallowBag",
        In = {
            onDispense = function(self) ... end,  -- Required
            -- onRefill uses Dispenser default
        },
    })
    ```

--]]

local Node = {}
Node.__index = Node

--------------------------------------------------------------------------------
-- DEFAULTS
--------------------------------------------------------------------------------
-- These are injected into nodes that don't provide their own implementations.

Node.defaults = {
    Sys = {
        onInit = function(self) end,
        onStart = function(self) end,
        onStop = function(self) end,
        onModeChange = function(self, oldMode, newMode) end,
        onSpawned = function(self) end,
        onDespawning = function(self) end,
    },
    In = {
        -- Internal ack handler for sync signals
        -- This is called when a sync signal's ack is received
        _onAck = function(self, data)
            -- This is handled by waitForSignal, but we define it here
            -- so the handler exists and can be invoked
        end,
    },
}

Node.required = {
    Sys = { "onInit", "onStart", "onStop" },
}

--------------------------------------------------------------------------------
-- OUT CHANNEL
--------------------------------------------------------------------------------
-- Stub that will be connected to IPC routing when IPC.init() is called.

local OutChannel = {}
OutChannel.__index = OutChannel

-- Correlation ID counter for sync signals
local _correlationCounter = 0
local function generateCorrelationId()
    _correlationCounter = _correlationCounter + 1
    return "sync_" .. _correlationCounter .. "_" .. tostring(os.clock()):gsub("%.", "")
end

function OutChannel.new(node)
    local self = setmetatable({}, OutChannel)
    self._node = node
    return self
end

--[[
    Fire a signal to connected nodes.

    @param signal string - Signal name
    @param data table? - Signal payload
    @param options table? - Options:
        - sync: boolean - If true, block until receiver acknowledges
        - timeout: number - Sync timeout in seconds (default 5)
    @return boolean, any - Success and ack data (for sync mode)
--]]
function OutChannel:Fire(signal, data, options)
    data = data or {}
    options = options or {}

    local System = self._node._System
    if System and System.Debug then
        System.Debug.trace(self._node.id or "Node", "Out:Fire", signal, options.sync and "(sync)" or "")
    end

    -- Sync mode: add correlation metadata and wait for ack
    if options.sync then
        local correlationId = generateCorrelationId()
        data._sync = {
            id = correlationId,
            replyTo = self._node.id,
        }

        -- Fire the signal
        if self._node._ipcSend then
            self._node._ipcSend(self._node.id, signal, data)
        end

        -- Wait for ack
        local timeout = options.timeout or 5
        local ackData = self._node:waitForSignal("_onAck", timeout)

        -- Check if ack matches our correlation ID
        if ackData and ackData._correlationId == correlationId then
            return true, ackData
        else
            -- Timeout or mismatched ack
            return false, nil
        end
    else
        -- Async mode: fire and forget
        if self._node._ipcSend then
            self._node._ipcSend(self._node.id, signal, data)
        end
        return true
    end
end

--------------------------------------------------------------------------------
-- ERR CHANNEL
--------------------------------------------------------------------------------
-- Propagates errors to IPC.ErrIn for centralized handling.

local ErrChannel = {}
ErrChannel.__index = ErrChannel

function ErrChannel.new(node)
    local self = setmetatable({}, ErrChannel)
    self._node = node
    return self
end

function ErrChannel:Fire(errorData)
    -- Add node context
    local enriched = {
        node = self._node.id,
        class = self._node.class,
        timestamp = os.time(),
    }

    -- Merge error data
    if type(errorData) == "table" then
        for k, v in pairs(errorData) do
            enriched[k] = v
        end
    else
        enriched.error = tostring(errorData)
    end

    -- Route to IPC error handler (if connected)
    if self._node._ipcError then
        self._node._ipcError(enriched)
    else
        -- Fallback to Debug.error if IPC not connected
        local System = self._node._System
        if System and System.Debug then
            System.Debug.error(self._node.id or "Node", "Unhandled error:", enriched.error or "unknown")
        end
    end
end

--------------------------------------------------------------------------------
-- EXTEND (Factory Pattern)
--------------------------------------------------------------------------------
--[[
    Factory function that creates extend functions with correct parent capture.

    This pattern ensures each class gets its own extend function with the
    correct parent class captured in the closure. Without this, child classes
    would share the same extend function and use the wrong parent reference.

    @param parent table - Parent class to extend from
    @return function - extend function for the parent class
--]]
local function makeExtendFunction(parent)
    return function(definitionOrFactory)
        local definition

        -- Support both table and factory function patterns
        -- Factory pattern: Node.extend(function(parent) return { name = "...", ... } end)
        -- Table pattern:   Node.extend({ name = "...", ... })
        if type(definitionOrFactory) == "function" then
            definition = definitionOrFactory(parent)
        else
            definition = definitionOrFactory
        end

        -- Validate definition
        if not definition then
            error("[Node.extend] Definition required")
        end
        if not definition.name then
            error("[Node.extend] Definition must have a name")
        end

        -- Create new class with prototype chain to parent
        local NewClass = setmetatable({}, { __index = parent })
        NewClass.__index = NewClass

        -- Store class metadata
        NewClass.name = definition.name
        NewClass.domain = definition.domain or parent.domain or "shared"
        NewClass._parent = parent
        NewClass._definition = definition

        -- Merge required handlers from parent
        NewClass.required = {}
        if parent.required then
            for pin, handlers in pairs(parent.required) do
                NewClass.required[pin] = {}
                for _, handler in ipairs(handlers) do
                    table.insert(NewClass.required[pin], handler)
                end
            end
        end
        if definition.required then
            for pin, handlers in pairs(definition.required) do
                NewClass.required[pin] = NewClass.required[pin] or {}
                for _, handler in ipairs(handlers) do
                    -- Avoid duplicates
                    local exists = false
                    for _, existing in ipairs(NewClass.required[pin]) do
                        if existing == handler then
                            exists = true
                            break
                        end
                    end
                    if not exists then
                        table.insert(NewClass.required[pin], handler)
                    end
                end
            end
        end

        -- Merge defaults from parent
        NewClass.defaults = {}
        if parent.defaults then
            for pin, handlers in pairs(parent.defaults) do
                NewClass.defaults[pin] = NewClass.defaults[pin] or {}
                for name, fn in pairs(handlers) do
                    NewClass.defaults[pin][name] = fn
                end
            end
        end
        if definition.defaults then
            for pin, handlers in pairs(definition.defaults) do
                NewClass.defaults[pin] = NewClass.defaults[pin] or {}
                for name, fn in pairs(handlers) do
                    NewClass.defaults[pin][name] = fn
                end
            end
        end

        -- Copy Sys handlers (merge with parent)
        NewClass.Sys = {}
        if parent.Sys then
            for name, fn in pairs(parent.Sys) do
                NewClass.Sys[name] = fn
            end
        end
        if definition.Sys then
            for name, fn in pairs(definition.Sys) do
                NewClass.Sys[name] = fn
            end
        end

        -- Copy In handlers (merge with parent)
        NewClass.In = {}
        if parent.In then
            for name, value in pairs(parent.In) do
                NewClass.In[name] = value
            end
        end
        if definition.In then
            for name, value in pairs(definition.In) do
                NewClass.In[name] = value
            end
        end

        -- Copy Out schema
        if definition.Out then
            NewClass.Out = definition.Out
        elseif parent.Out then
            NewClass.Out = parent.Out
        end

        -- Copy mode-specific handlers
        for key, value in pairs(definition) do
            if type(value) == "table" and key ~= "Sys" and key ~= "In" and key ~= "Out" and key ~= "Err"
                and key ~= "required" and key ~= "defaults" and key ~= "name" and key ~= "domain" then
                -- Assume this is a mode-specific handler table (e.g., Tutorial = { In = {...} })
                NewClass[key] = value
            end
        end

        -- Copy private methods (functions not in reserved keys)
        for key, value in pairs(definition) do
            if type(value) == "function" and key ~= "Sys" and key ~= "In" and key ~= "Out" and key ~= "Err" then
                NewClass[key] = value
            end
        end

        -- Copy Controls table (for InputCapture integration)
        if definition.Controls then
            NewClass.Controls = definition.Controls
        end

        -- Create a fresh extend function for this new class
        -- This ensures grandchildren correctly reference NewClass as parent
        NewClass.extend = makeExtendFunction(NewClass)

        return NewClass
    end
end

-- Initialize Node.extend with the factory
Node.extend = makeExtendFunction(Node)

--------------------------------------------------------------------------------
-- NEW (Instance Creation)
--------------------------------------------------------------------------------
-- ID GENERATION (for Node:new when id not provided)
--------------------------------------------------------------------------------
local _classCounters = {}  -- { [className] = nextNumber }

local function generateNodeId(className)
    _classCounters[className] = (_classCounters[className] or 0) + 1
    return className .. "_" .. _classCounters[className]
end

--------------------------------------------------------------------------------
--[[
    Create a new instance of a node class.

    @param config table - Instance configuration
        id: string (optional) - Unique instance ID (auto-generated if nil)
        model: Instance (optional) - Associated Roblox Instance
        attributes: table (optional) - Initial attributes

    @return table - Node instance with pins and methods
--]]
function Node:new(config)
    config = config or {}

    -- Auto-generate ID if not provided
    local className = self.name or "Node"
    local id = config.id or generateNodeId(className)

    local instance = setmetatable({}, self)

    -- Instance metadata
    instance.id = id
    instance.class = self.name or "Node"
    instance.domain = self.domain or "shared"
    instance.model = config.model
    instance._attributes = config.attributes or {}
    instance._System = nil  -- Will be set by IPC

    -- Create output channels
    instance.Out = OutChannel.new(instance)
    instance.Err = ErrChannel.new(instance)

    -- Copy Sys handlers (with default injection)
    instance.Sys = {}
    -- First, apply defaults
    if self.defaults and self.defaults.Sys then
        for name, fn in pairs(self.defaults.Sys) do
            instance.Sys[name] = fn
        end
    end
    -- Then, override with class handlers
    if self.Sys then
        for name, fn in pairs(self.Sys) do
            instance.Sys[name] = fn
        end
    end

    -- Copy In handlers (with default injection)
    instance.In = {}
    -- First, apply defaults
    if self.defaults and self.defaults.In then
        for name, value in pairs(self.defaults.In) do
            instance.In[name] = value
        end
    end
    -- Then, override with class handlers
    if self.In then
        for name, value in pairs(self.In) do
            instance.In[name] = value
        end
    end

    -- Copy mode-specific handlers
    for key, value in pairs(self) do
        if type(value) == "table" and key ~= "Sys" and key ~= "In" and key ~= "Out" and key ~= "Err"
            and key ~= "required" and key ~= "defaults" and key ~= "__index" and key ~= "_parent"
            and key ~= "_definition" and key ~= "name" and key ~= "domain" and key ~= "Controls" then
            -- Deep copy mode-specific handlers
            instance[key] = {}
            for subKey, subValue in pairs(value) do
                if type(subValue) == "table" then
                    instance[key][subKey] = {}
                    for k, v in pairs(subValue) do
                        instance[key][subKey][k] = v
                    end
                else
                    instance[key][subKey] = subValue
                end
            end
        end
    end

    -- Auto-register with Node.Registry for global lifecycle management
    -- This ensures all nodes can be stopped via Registry.stopAll()
    Node.Registry.register(instance)

    -- Auto-cleanup when model is destroyed
    -- This ensures nodes stop gracefully when their model is removed from workspace
    if instance.model and typeof(instance.model) == "Instance" then
        instance._modelConnection = instance.model.AncestryChanged:Connect(function(_, parent)
            if not parent then
                -- Model was destroyed - stop the node
                if instance.Sys and instance.Sys.onStop then
                    instance.Sys.onStop(instance)
                end
                -- Disconnect this connection
                if instance._modelConnection then
                    instance._modelConnection:Disconnect()
                    instance._modelConnection = nil
                end
                -- Unregister from Registry
                Node.Registry.unregister(instance.id)
            end
        end)
    end

    return instance
end

--------------------------------------------------------------------------------
-- INHERITANCE CHAIN
--------------------------------------------------------------------------------
--[[
    Get the full inheritance chain for this node class.

    Used for contract validation - walks up the prototype chain
    to collect all required handlers from all ancestors.

    @return table - Array of ancestor classes (oldest first)
--]]
function Node:getInheritanceChain()
    local chain = {}
    local current = self

    while current do
        table.insert(chain, 1, current)  -- Insert at beginning (oldest first)
        current = current._parent
    end

    return chain
end

--------------------------------------------------------------------------------
-- HANDLER CHECKS
--------------------------------------------------------------------------------
--[[
    Check if this node has a handler for a given pin and name.

    Looks in both the class definition and defaults.

    @param pin string - Pin name ("Sys", "In", etc.)
    @param handlerName string - Handler name (e.g., "onInit")
    @return boolean - True if handler exists
--]]
function Node:hasHandler(pin, handlerName)
    -- Check instance handler
    if self[pin] and self[pin][handlerName] then
        return true
    end

    -- Check defaults
    if self.defaults and self.defaults[pin] and self.defaults[pin][handlerName] then
        return true
    end

    return false
end

--------------------------------------------------------------------------------
-- PIN RESOLUTION
--------------------------------------------------------------------------------
--[[
    Resolve the appropriate pin handlers for a given mode.

    Resolution order:
    1. Check {Mode}.In - if exists, use it
    2. Fall back to In

    @param mode string - Current run mode (e.g., "Tutorial", "Playing")
    @param pinType string - Pin type ("In" or "Out")
    @return table - Handler table to use
--]]
function Node:resolvePin(mode, pinType)
    -- Check mode-specific pin
    if mode and self[mode] and self[mode][pinType] then
        return self[mode][pinType]
    end

    -- Fall back to default pin
    return self[pinType] or {}
end

--------------------------------------------------------------------------------
-- ATTRIBUTES
--------------------------------------------------------------------------------
--[[
    Get an attribute value.

    First checks the associated model (if any), then falls back to
    internal attribute storage.

    @param name string - Attribute name
    @return any - Attribute value or nil
--]]
function Node:getAttribute(name)
    -- Try model attributes first
    if self.model and typeof(self.model) == "Instance" then
        local success, value = pcall(function()
            return self.model:GetAttribute(name)
        end)
        if success and value ~= nil then
            return value
        end
    end

    -- Fall back to internal storage
    return self._attributes[name]
end

--[[
    Set an attribute value.

    Sets on both the model (if any) and internal storage.

    @param name string - Attribute name
    @param value any - Attribute value
--]]
function Node:setAttribute(name, value)
    -- Store internally
    self._attributes[name] = value

    -- Also set on model if available
    if self.model and typeof(self.model) == "Instance" then
        pcall(function()
            self.model:SetAttribute(name, value)
        end)
    end
end

--[[
    Get all attributes.

    Merges model attributes with internal storage.

    @return table - All attribute key-value pairs
--]]
function Node:getAttributes()
    local result = {}

    -- Copy internal attributes
    for k, v in pairs(self._attributes) do
        result[k] = v
    end

    -- Merge model attributes (overwrite internals if conflict)
    if self.model and typeof(self.model) == "Instance" then
        local success, attrs = pcall(function()
            return self.model:GetAttributes()
        end)
        if success and attrs then
            for k, v in pairs(attrs) do
                result[k] = v
            end
        end
    end

    return result
end

--------------------------------------------------------------------------------
-- LOCKING & SIGNAL WAITING
--------------------------------------------------------------------------------
--[[
    Check if this node is currently locked (waiting for a signal).

    When locked, IPC will queue incoming messages instead of dispatching them.

    @return boolean - True if node is locked
--]]
function Node:isLocked()
    return self._locked == true
end

--[[
    Wait for a specific signal to be received.

    Automatically locks the node during the wait, causing IPC to queue
    other incoming messages. When the signal is received or timeout occurs,
    the node unlocks and queued messages are flushed.

    @param signalName string - The In handler to wait for (e.g., "onAck")
    @param timeout number - Maximum seconds to wait (default 5)
    @return any - The data received with the signal, or nil on timeout
--]]
function Node:waitForSignal(signalName, timeout)
    timeout = timeout or 5

    -- Create internal signal mechanism
    local received = false
    local receivedData = nil
    local waitEvent = Instance.new("BindableEvent")

    -- Store the original handler (if any)
    local originalHandler = self.In and self.In[signalName]

    -- Install temporary handler that captures the signal
    self.In = self.In or {}
    self.In[signalName] = function(selfRef, data)
        receivedData = data
        received = true
        waitEvent:Fire()
    end

    -- Lock the node
    self._locked = true
    self._messageQueue = self._messageQueue or {}

    -- Wait with timeout
    local startTime = os.clock()
    local connection
    connection = waitEvent.Event:Connect(function() end)

    -- Timeout loop
    task.spawn(function()
        while not received and (os.clock() - startTime) < timeout do
            task.wait(0.1)
        end
        if not received then
            waitEvent:Fire()  -- Unblock on timeout
        end
    end)

    -- Block until signal or timeout
    waitEvent.Event:Wait()

    -- Cleanup
    connection:Disconnect()
    waitEvent:Destroy()

    -- Restore original handler
    if originalHandler then
        self.In[signalName] = originalHandler
    else
        self.In[signalName] = nil
    end

    -- Unlock and flush queue
    self._locked = false
    self:_flushMessageQueue()

    -- Return result
    if received then
        return receivedData
    else
        return nil  -- Timeout
    end
end

--[[
    Flush queued messages that arrived while node was locked.

    Called automatically by waitForSignal() after unlocking.
    Messages are dispatched in order they were received.
--]]
function Node:_flushMessageQueue()
    if not self._messageQueue or #self._messageQueue == 0 then
        return
    end

    local System = self._System
    if not System or not System.IPC then
        self._messageQueue = {}
        return
    end

    -- Process queued messages
    local queue = self._messageQueue
    self._messageQueue = {}

    for _, msg in ipairs(queue) do
        local signal, data, msgId = msg[1], msg[2], msg[3]
        -- Re-dispatch through IPC
        System.IPC.sendTo(self.id, signal, data)
    end
end

--------------------------------------------------------------------------------
-- NODE REGISTRY
--------------------------------------------------------------------------------
--[[
    NodeRegistry wraps CollectionService to provide Node-specific instance
    tracking with queryable metadata.

    Features:
    - Auto-generates unique IDs when not provided
    - Tracks Node objects alongside their Roblox Model (if any)
    - Tags Models via CollectionService for efficient queries
    - Stores metadata: class, inheritanceChain, spawnSource, status, etc.
    - Query by class, tag, spawnSource, or custom filters

    Usage:
    ```lua
    local Node = require(path.to.Node)
    local Registry = Node.Registry

    -- Register a node (auto-generates ID if not provided)
    local id = Registry.register(myNode, {
        spawnSource = "Tent_1",
        status = "awaiting_path",
    })

    -- Query nodes
    local campers = Registry.getByClass("Camper")
    local fromTent1 = Registry.getBySpawnSource("Tent_1")
    local needingPath = Registry.query({ status = "awaiting_path" })

    -- Update status
    Registry.setStatus(id, "pathing")

    -- Unregister when done
    Registry.unregister(id)
    ```
--]]

local CollectionService = game:GetService("CollectionService")

Node.Registry = (function()
    local Registry = {}

    ---------------------------------------------------------------------------
    -- PRIVATE STATE
    ---------------------------------------------------------------------------

    local nodes = {}           -- { [id] = node }
    local metadata = {}        -- { [id] = { class, spawnSource, status, ... } }
    local classCounters = {}   -- { [className] = nextNumber } for auto-ID
    local TAG_PREFIX = "Node_" -- Prefix for CollectionService tags

    ---------------------------------------------------------------------------
    -- ID GENERATION
    ---------------------------------------------------------------------------

    --[[
        Generate a unique ID for a node class.
        Format: ClassName_1, ClassName_2, etc.
    --]]
    local function generateId(className)
        classCounters[className] = (classCounters[className] or 0) + 1
        return className .. "_" .. classCounters[className]
    end

    ---------------------------------------------------------------------------
    -- COLLECTION SERVICE HELPERS
    ---------------------------------------------------------------------------

    --[[
        Add tags to a model via CollectionService.
        Tags added:
        - Node_{id} (unique instance tag)
        - Node_Class_{className} (class tag)
        - Any custom tags from metadata
    --]]
    local function tagModel(model, id, meta)
        if not model then return end

        -- Unique instance tag
        CollectionService:AddTag(model, TAG_PREFIX .. id)

        -- Class tag
        if meta.class then
            CollectionService:AddTag(model, TAG_PREFIX .. "Class_" .. meta.class)
        end

        -- Inheritance chain tags
        if meta.inheritanceChain then
            for _, ancestor in ipairs(meta.inheritanceChain) do
                CollectionService:AddTag(model, TAG_PREFIX .. "Class_" .. ancestor)
            end
        end

        -- Custom tags
        if meta.tags then
            for _, tag in ipairs(meta.tags) do
                CollectionService:AddTag(model, TAG_PREFIX .. "Tag_" .. tag)
            end
        end
    end

    --[[
        Remove all Node-related tags from a model.
    --]]
    local function untagModel(model, id, meta)
        if not model then return end

        CollectionService:RemoveTag(model, TAG_PREFIX .. id)

        if meta.class then
            CollectionService:RemoveTag(model, TAG_PREFIX .. "Class_" .. meta.class)
        end

        if meta.inheritanceChain then
            for _, ancestor in ipairs(meta.inheritanceChain) do
                CollectionService:RemoveTag(model, TAG_PREFIX .. "Class_" .. ancestor)
            end
        end

        if meta.tags then
            for _, tag in ipairs(meta.tags) do
                CollectionService:RemoveTag(model, TAG_PREFIX .. "Tag_" .. tag)
            end
        end
    end

    ---------------------------------------------------------------------------
    -- PUBLIC API
    ---------------------------------------------------------------------------

    --[[
        Register a node with the registry.

        @param node table - The Node instance
        @param options table? - Optional metadata:
            - id: string? - Explicit ID (auto-generated if nil)
            - spawnSource: string? - ID of node that spawned this
            - status: string? - Initial status
            - tags: string[]? - Additional tags
        @return string - The assigned ID
    --]]
    function Registry.register(node, options)
        options = options or {}

        -- Get or generate ID
        local id = options.id or node.id
        local className = node.class or node.name or "Node"

        if not id then
            id = generateId(className)
        end

        -- Build inheritance chain as names (not class objects)
        local inheritanceNames = {}
        if node.getInheritanceChain then
            for _, ancestorClass in ipairs(node:getInheritanceChain()) do
                local name = ancestorClass.name or "Node"
                table.insert(inheritanceNames, name)
            end
        end

        -- Build metadata
        local meta = {
            class = className,
            inheritanceChain = inheritanceNames,
            spawnSource = options.spawnSource,
            status = options.status,
            tags = options.tags or {},
            model = node.model,
            registeredAt = os.clock(),
        }

        -- Store node and metadata
        nodes[id] = node
        metadata[id] = meta

        -- Assign ID to node if not set
        if not node.id then
            node.id = id
        end

        -- Tag the model if present
        if node.model then
            tagModel(node.model, id, meta)

            -- Also set attributes on the model for query filtering
            node.model:SetAttribute("NodeId", id)
            node.model:SetAttribute("NodeClass", className)
            if options.spawnSource then
                node.model:SetAttribute("NodeSpawnSource", options.spawnSource)
            end
            if options.status then
                node.model:SetAttribute("NodeStatus", options.status)
            end
        end

        return id
    end

    --[[
        Unregister a node from the registry.

        @param id string - The node ID
        @return boolean - True if node was found and removed
    --]]
    function Registry.unregister(id)
        local node = nodes[id]
        local meta = metadata[id]

        if not node then
            return false
        end

        -- Remove tags from model
        if meta and node.model then
            untagModel(node.model, id, meta)
        end

        nodes[id] = nil
        metadata[id] = nil

        return true
    end

    --[[
        Get a node by ID.

        @param id string - The node ID
        @return table? - The node, or nil if not found
    --]]
    function Registry.get(id)
        return nodes[id]
    end

    --[[
        Get metadata for a node.

        @param id string - The node ID
        @return table? - The metadata, or nil if not found
    --]]
    function Registry.getMetadata(id)
        return metadata[id]
    end

    --[[
        Get the model associated with a node.

        @param id string - The node ID
        @return Instance? - The model, or nil
    --]]
    function Registry.getModel(id)
        local node = nodes[id]
        return node and node.model
    end

    --[[
        Get all nodes of a specific class.

        @param className string - The class name
        @return table - Array of nodes
    --]]
    function Registry.getByClass(className)
        local results = {}
        for id, meta in pairs(metadata) do
            if meta.class == className then
                table.insert(results, nodes[id])
            end
        end
        return results
    end

    --[[
        Get all nodes spawned by a specific source.

        @param sourceId string - The spawn source ID
        @return table - Array of nodes
    --]]
    function Registry.getBySpawnSource(sourceId)
        local results = {}
        for id, meta in pairs(metadata) do
            if meta.spawnSource == sourceId then
                table.insert(results, nodes[id])
            end
        end
        return results
    end

    --[[
        Get all nodes with a specific status.

        @param status string - The status to match
        @return table - Array of nodes
    --]]
    function Registry.getByStatus(status)
        local results = {}
        for id, meta in pairs(metadata) do
            if meta.status == status then
                table.insert(results, nodes[id])
            end
        end
        return results
    end

    --[[
        Get all nodes with a specific tag.

        @param tag string - The tag to match
        @return table - Array of nodes
    --]]
    function Registry.getByTag(tag)
        local results = {}
        for id, meta in pairs(metadata) do
            if meta.tags then
                for _, t in ipairs(meta.tags) do
                    if t == tag then
                        table.insert(results, nodes[id])
                        break
                    end
                end
            end
        end
        return results
    end

    --[[
        Query nodes with flexible filter criteria.

        @param filter table - Filter options:
            - class: string? - Match class name
            - spawnSource: string? - Match spawn source
            - status: string? - Match status
            - tag: string? - Must have this tag
            - custom: function(node, meta)? - Custom filter function
        @return table - Array of nodes matching all criteria
    --]]
    function Registry.query(filter)
        filter = filter or {}
        local results = {}

        for id, meta in pairs(metadata) do
            local matches = true

            if filter.class and meta.class ~= filter.class then
                matches = false
            end

            if matches and filter.spawnSource and meta.spawnSource ~= filter.spawnSource then
                matches = false
            end

            if matches and filter.status and meta.status ~= filter.status then
                matches = false
            end

            if matches and filter.tag then
                local hasTag = false
                if meta.tags then
                    for _, t in ipairs(meta.tags) do
                        if t == filter.tag then
                            hasTag = true
                            break
                        end
                    end
                end
                if not hasTag then
                    matches = false
                end
            end

            if matches and filter.custom then
                matches = filter.custom(nodes[id], meta)
            end

            if matches then
                table.insert(results, nodes[id])
            end
        end

        return results
    end

    --[[
        Update the status of a node.

        @param id string - The node ID
        @param status string - The new status
        @return boolean - True if node was found and updated
    --]]
    function Registry.setStatus(id, status)
        local meta = metadata[id]
        if not meta then
            return false
        end

        meta.status = status

        -- Update model attribute if present
        local node = nodes[id]
        if node and node.model then
            node.model:SetAttribute("NodeStatus", status)
        end

        return true
    end

    --[[
        Add a tag to a node.

        @param id string - The node ID
        @param tag string - The tag to add
        @return boolean - True if node was found and tag added
    --]]
    function Registry.addTag(id, tag)
        local meta = metadata[id]
        if not meta then
            return false
        end

        meta.tags = meta.tags or {}

        -- Check if tag already exists
        for _, t in ipairs(meta.tags) do
            if t == tag then
                return true  -- Already has tag
            end
        end

        table.insert(meta.tags, tag)

        -- Update CollectionService if model present
        local node = nodes[id]
        if node and node.model then
            CollectionService:AddTag(node.model, TAG_PREFIX .. "Tag_" .. tag)
        end

        return true
    end

    --[[
        Remove a tag from a node.

        @param id string - The node ID
        @param tag string - The tag to remove
        @return boolean - True if node was found and tag removed
    --]]
    function Registry.removeTag(id, tag)
        local meta = metadata[id]
        if not meta or not meta.tags then
            return false
        end

        for i, t in ipairs(meta.tags) do
            if t == tag then
                table.remove(meta.tags, i)

                -- Update CollectionService if model present
                local node = nodes[id]
                if node and node.model then
                    CollectionService:RemoveTag(node.model, TAG_PREFIX .. "Tag_" .. tag)
                end

                return true
            end
        end

        return false
    end

    --[[
        Iterate over all registered nodes.

        @param callback function(id, node, meta) - Called for each node
        @param filter table? - Optional filter (same as query)
    --]]
    function Registry.forEach(callback, filter)
        if filter then
            local results = Registry.query(filter)
            for _, node in ipairs(results) do
                callback(node.id, node, metadata[node.id])
            end
        else
            for id, node in pairs(nodes) do
                callback(id, node, metadata[id])
            end
        end
    end

    --[[
        Count registered nodes.

        @param filter table? - Optional filter (same as query)
        @return number - Count of matching nodes
    --]]
    function Registry.count(filter)
        if filter then
            return #Registry.query(filter)
        else
            local count = 0
            for _ in pairs(nodes) do
                count = count + 1
            end
            return count
        end
    end

    --[[
        Get all registered node IDs.

        @return table - Array of IDs
    --]]
    function Registry.getAllIds()
        local ids = {}
        for id in pairs(nodes) do
            table.insert(ids, id)
        end
        return ids
    end

    --[[
        Reset the registry (for testing).
    --]]
    function Registry.reset()
        -- Untag all models first
        for id, node in pairs(nodes) do
            local meta = metadata[id]
            if node.model and meta then
                untagModel(node.model, id, meta)
            end
        end

        nodes = {}
        metadata = {}
        classCounters = {}
    end

    --[[
        Stop all registered nodes.

        Calls Sys.onStop on every registered node, then clears the registry.
        Use this to cleanly shut down all nodes (e.g., before running tests).

        @return number - Count of nodes stopped
    --]]
    function Registry.stopAll()
        local count = 0
        local idsToStop = {}

        -- Collect IDs first (avoid modifying during iteration)
        for id in pairs(nodes) do
            table.insert(idsToStop, id)
        end

        -- Stop each node
        for _, id in ipairs(idsToStop) do
            local node = nodes[id]
            if node then
                -- Disconnect model connection first (prevents double-stop from AncestryChanged)
                if node._modelConnection then
                    node._modelConnection:Disconnect()
                    node._modelConnection = nil
                end

                -- Call onStop
                if node.Sys and node.Sys.onStop then
                    local success, err = pcall(function()
                        node.Sys.onStop(node)
                    end)
                    if not success then
                        warn("[Node.Registry.stopAll] Error stopping " .. id .. ": " .. tostring(err))
                    end
                end
                count = count + 1
            end
        end

        -- Clear registry
        Registry.reset()

        return count
    end

    ---------------------------------------------------------------------------
    -- STANDARD FILTER MATCHING
    ---------------------------------------------------------------------------

    --[[
        Standard Filter Schema
        ======================

        Filters provide a declarative way to match Nodes or Roblox Instances.
        Used across Zone detection, SpawnerCore cleanup, and run mode transitions.

        Filter Fields:
            class: string | string[]
                Match NodeClass attribute (single class or array of allowed classes)

            spawnSource: string
                Match NodeSpawnSource attribute (ID of spawner that created it)

            status: string
                Match NodeStatus attribute

            tag: string
                Match CollectionService tag (checks both raw tag and Node_Tag_ prefixed)

            assetId: string
                Match specific AssetId attribute

            nodeId: string
                Match specific NodeId attribute

            attribute: { name: string, value: any, operator?: string }
                Match custom attribute with optional operator
                Operators: "=" (default), "!=", ">", "<", ">=", "<="

            custom: function(target, meta?) -> boolean
                Custom filter function (receives node/instance and optional metadata)

        Usage:
        ```lua
        -- Filter for active Campers spawned by Tent_1
        local filter = {
            class = "Camper",
            spawnSource = "Tent_1",
            status = "active",
        }

        -- Check if entity matches
        if Registry.matches(entity, filter) then
            -- ...
        end

        -- Query matching nodes
        local nodes = Registry.query(filter)

        -- Used in Zone configuration
        zone.In.onConfigure(zone, { filter = filter })
        ```
    --]]

    --[[
        Check if a target (Node or Instance) matches a filter.

        Works with:
        - Node objects (uses internal metadata)
        - Roblox Instances (reads attributes directly)

        @param target table|Instance - Node object or Roblox Instance
        @param filter table - Filter criteria (see Standard Filter Schema)
        @return boolean - True if target matches all filter criteria
    --]]
    function Registry.matches(target, filter)
        if not target or not filter then
            return target ~= nil and (filter == nil or next(filter) == nil)
        end

        -- Determine if target is a Node or Instance
        local isNode = type(target) == "table" and target.class ~= nil
        local isInstance = typeof(target) == "Instance"

        if not isNode and not isInstance then
            return false
        end

        -- Helper to get attribute value from target
        local function getAttr(name)
            if isNode then
                -- Check node metadata first
                local meta = metadata[target.id]
                if name == "NodeClass" then
                    return meta and meta.class or target.class
                elseif name == "NodeSpawnSource" then
                    return meta and meta.spawnSource
                elseif name == "NodeStatus" then
                    return meta and meta.status
                elseif name == "NodeId" then
                    return target.id
                elseif name == "AssetId" then
                    return target.model and target.model:GetAttribute("AssetId")
                end
                -- Check model attributes
                if target.model then
                    return target.model:GetAttribute(name)
                end
                return target._attributes and target._attributes[name]
            else
                -- Instance - read attributes directly
                local success, value = pcall(function()
                    return target:GetAttribute(name)
                end)
                return success and value or nil
            end
        end

        -- Helper to check if target has a tag
        local function hasTag(tagName)
            if isNode then
                -- Check node metadata tags
                local meta = metadata[target.id]
                if meta and meta.tags then
                    for _, t in ipairs(meta.tags) do
                        if t == tagName then
                            return true
                        end
                    end
                end
                -- Check CollectionService on model
                if target.model then
                    return CollectionService:HasTag(target.model, tagName)
                        or CollectionService:HasTag(target.model, TAG_PREFIX .. "Tag_" .. tagName)
                end
                return false
            else
                -- Instance - check CollectionService directly
                return CollectionService:HasTag(target, tagName)
                    or CollectionService:HasTag(target, TAG_PREFIX .. "Tag_" .. tagName)
            end
        end

        -- Filter: class
        if filter.class then
            local targetClass = getAttr("NodeClass")
            if type(filter.class) == "table" then
                -- Array of allowed classes
                local found = false
                for _, allowedClass in ipairs(filter.class) do
                    if targetClass == allowedClass then
                        found = true
                        break
                    end
                end
                if not found then
                    return false
                end
            else
                -- Single class
                if targetClass ~= filter.class then
                    return false
                end
            end
        end

        -- Filter: spawnSource
        if filter.spawnSource then
            local targetSource = getAttr("NodeSpawnSource")
            if targetSource ~= filter.spawnSource then
                return false
            end
        end

        -- Filter: status
        if filter.status then
            local targetStatus = getAttr("NodeStatus")
            if targetStatus ~= filter.status then
                return false
            end
        end

        -- Filter: tag
        if filter.tag then
            if not hasTag(filter.tag) then
                return false
            end
        end

        -- Filter: assetId
        if filter.assetId then
            local targetAssetId = getAttr("AssetId")
            if targetAssetId ~= filter.assetId then
                return false
            end
        end

        -- Filter: nodeId
        if filter.nodeId then
            local targetNodeId = getAttr("NodeId")
            if targetNodeId ~= filter.nodeId then
                return false
            end
        end

        -- Filter: attribute (custom attribute with operator)
        if filter.attribute then
            local attrName = filter.attribute.name
            local attrValue = filter.attribute.value
            local operator = filter.attribute.operator or "="
            local targetValue = getAttr(attrName)

            if targetValue == nil then
                return false
            end

            if operator == "=" then
                if targetValue ~= attrValue then
                    return false
                end
            elseif operator == "!=" then
                if targetValue == attrValue then
                    return false
                end
            elseif operator == ">" then
                if not (targetValue > attrValue) then
                    return false
                end
            elseif operator == "<" then
                if not (targetValue < attrValue) then
                    return false
                end
            elseif operator == ">=" then
                if not (targetValue >= attrValue) then
                    return false
                end
            elseif operator == "<=" then
                if not (targetValue <= attrValue) then
                    return false
                end
            end
        end

        -- Filter: custom function
        if filter.custom then
            local meta = isNode and metadata[target.id] or nil
            if not filter.custom(target, meta) then
                return false
            end
        end

        return true
    end

    --[[
        Find a Node by its associated model Instance.

        @param instance Instance - The Roblox Instance to search for
        @return table?, string? - The Node and its ID, or nil if not found
    --]]
    function Registry.getByModel(instance)
        for id, node in pairs(nodes) do
            if node.model == instance then
                return node, id
            end
        end
        return nil, nil
    end

    return Registry
end)()

return Node
