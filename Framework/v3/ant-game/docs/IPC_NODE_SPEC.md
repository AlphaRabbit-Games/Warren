# Warren Framework v2 - IPC & Node Architecture Specification

> **Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC**
> All rights reserved.

**Version:** 1.0.0-draft
**Date:** January 11, 2026
**Status:** Design Complete, Pending Implementation

---

## Table of Contents

1. [Overview](#1-overview)
2. [Core Concepts](#2-core-concepts)
3. [Node Architecture](#3-node-architecture)
4. [IPC System](#4-ipc-system)
5. [Run Modes & Wiring](#5-run-modes--wiring)
6. [Contract System](#6-contract-system)
7. [Message Routing](#7-message-routing)
8. [Error Handling](#8-error-handling)
9. [Instance Management](#9-instance-management)
10. [Server/Client Context](#10-serverclient-context)
11. [State Persistence](#11-state-persistence)
12. [Lifecycle](#12-lifecycle)
13. [API Reference](#13-api-reference)
14. [Implementation Checklist](#14-implementation-checklist)

---

## 1. Overview

### 1.1 Purpose

The IPC (Inter-Process Communication) and Node system provides a decoupled, event-driven architecture for game component communication. It enables:

- **Reusability**: Nodes are self-contained, portable units
- **Portability**: Zero hard dependencies between nodes
- **Ease of use**: Declarative wiring, sensible defaults
- **Testability**: Test nodes in isolation

### 1.2 Design Philosophy

The architecture draws from hardware electronics:

| Electronics | System |
|-------------|--------|
| Integrated Circuit (ICU) | Node |
| Breadboard | Run Mode (wiring configuration) |
| Traces/Wires | Message routes |
| Voltage Input | Active mode |
| Control Pins (Enable) | Sys.In channel |
| Signal Pins | In/Out channels |
| Logic Gate | IPC Router |

**Key Principle**: Nodes don't know about each other. They respond to signals on their pins. The wiring configuration determines system behavior.

### 1.3 Communication Rules

| From | To | Method |
|------|-----|--------|
| Node | Node | Events via IPC (Out → wiring → In) |
| Node | System Service | Direct API calls |
| System | Node | Broadcasts via Sys.In |
| Node | System (errors) | Err channel → IPC.ErrIn |

---

## 2. Core Concepts

### 2.1 The Breadboard Model

Run modes are conceptually like breadboards in electronics:

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        SYSTEM (Power Supply)                            │
│                              │                                          │
│                         ┌────▼────┐                                     │
│                         │  SWITCH │  ← Active Run Mode                  │
│                         └────┬────┘                                     │
│              ┌───────────────┼───────────────┐                          │
│              ▼               ▼               ▼                          │
│   ┌──────────────┐  ┌──────────────┐  ┌──────────────┐                 │
│   │  TUTORIAL    │  │   PLAYING    │  │   RESULTS    │                 │
│   │  (Breadboard)│  │  (Breadboard)│  │  (Breadboard)│                 │
│   │              │  │              │  │              │                 │
│   │ [Dropper]────│  │ [Dropper]────│  │              │                 │
│   │      │       │  │      │       │  │ [Scoreboard] │                 │
│   │      ▼       │  │      ▼       │  │      │       │                 │
│   │ [SimpleUI]   │  │ [Evaluator]──│  │      ▼       │                 │
│   │              │  │      │       │  │ [Leaderboard]│                 │
│   │              │  │      ▼       │  │              │                 │
│   │              │  │ [Scoreboard] │  │              │                 │
│   └──────────────┘  └──────────────┘  └──────────────┘                 │
│                                                                         │
│   Same ICUs (Nodes), different wiring per mode                          │
└─────────────────────────────────────────────────────────────────────────┘
```

- **Nodes are mode-agnostic**: They respond to signals on their pins
- **Wiring is declarative**: Each mode defines connections
- **Mode switch = rewire**: IPC activates different wiring config
- **Broadcasts follow wires**: Signals only reach nodes in active config

### 2.2 Inheritance Model

Nodes use Lua prototypes for inheritance:

```
Node (System)              ← Base: defines pinouts, lifecycle hooks
    │
    ▼ extends (metatables)
DispenserBase (Lib)        ← Interface + default behavior
    │
    ▼ extends
MarshmallowBag (Game)      ← Game-specific implementation
    │
    ▼ instantiate
Runtime Instance           ← Active in workspace with unique ID
```

---

## 3. Node Architecture

### 3.1 Pin Model

Every node has these standard pins:

```
┌─────────────────────────────────────────────────────────────────┐
│                          NODE                                    │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  CONTROL (from system)                                          │
│  ┌─────────┐                                                    │
│  │  Sys.In │  ← lifecycle signals (init, start, stop, mode)    │
│  └─────────┘                                                    │
│                                                                  │
│  GAME I/O (wired per mode)                                      │
│  ┌─────────┐  ┌─────────┐                                      │
│  │   In    │  │   Out   │  ← game signals between nodes        │
│  └─────────┘  └─────────┘                                      │
│                                                                  │
│  ERROR (back to system)                                         │
│  ┌─────────┐                                                    │
│  │   Err   │  → error propagation to IPC                       │
│  └─────────┘                                                    │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 3.2 Mode-Specific Pins

Nodes can define mode-specific I/O for different behavior per mode:

```
┌─────────────────────────────────────────────────────────────────┐
│                         DROPPER NODE                            │
├─────────────────────────────────────────────────────────────────┤
│  DEFAULT (fallback when mode has no dedicated pins)             │
│  ┌─────────┐  ┌─────────┐                                      │
│  │   In    │  │   Out   │                                      │
│  └─────────┘  └─────────┘                                      │
├─────────────────────────────────────────────────────────────────┤
│  TUTORIAL (dedicated pins + handlers)                           │
│  ┌─────────────┐  ┌─────────────┐                              │
│  │ Tutorial.In │  │ Tutorial.Out│                              │
│  └─────────────┘  └─────────────┘                              │
├─────────────────────────────────────────────────────────────────┤
│  PLAYING (uses default - no override needed)                    │
└─────────────────────────────────────────────────────────────────┘
```

**Resolution order:**
1. Check `{Mode}.In` - if exists, use it
2. Check base mode (if mode has inheritance) - if exists, use it
3. Fall back to `In`

### 3.3 Mode Cascading

Mode-specific handlers can delegate to other modes:

```lua
Dropper = Node.extend({
    -- Default behavior
    In = {
        onDrop = function(self, item)
            self:drop(item)
            self.Out:Fire("dropped", item)
        end
    },

    -- Tutorial wraps default with hints
    Tutorial = {
        In = {
            onDrop = function(self, item)
                self:showHint("Drop it in the zone!")
                self.In.onDrop(self, item)  -- cascade to default
                self:showFeedback("Great job!")
            end
        },
    },
})
```

### 3.4 Node Definition Structure

```lua
NodeName = Node.extend({
    -- Metadata
    name = "NodeName",
    domain = "server",  -- "server", "client", or "shared"

    -- Contract requirements (for extensions)
    required = {
        In = { "onSomeHandler" },
    },

    -- Default implementations
    defaults = {
        In = {
            onOptionalHandler = function(self) ... end,
        },
    },

    -- System lifecycle handlers
    Sys = {
        onInit = function(self) ... end,
        onStart = function(self) ... end,
        onStop = function(self) ... end,
        onModeChange = function(self, oldMode, newMode) ... end,
    },

    -- Game signal handlers (default mode)
    In = {
        onSomeSignal = function(self, data) ... end,
    },

    -- Outbound signals (documentation)
    Out = {
        -- "signalName" = { schema }
    },

    -- Mode-specific handlers
    Tutorial = {
        In = { ... },
        Out = { },
    },
})
```

---

## 4. IPC System

### 4.1 Responsibilities

The IPC system is the central nervous system:

1. **Node Registration**: Track all nodes and instances
2. **Wiring Management**: Define and switch mode configurations
3. **Message Routing**: Route signals through active wiring
4. **Lifecycle Broadcasts**: Send init/start/stop to Sys.In
5. **Error Collection**: Receive errors from Err channels
6. **Message Ordering**: Assign unique, linear message IDs
7. **Payload Validation**: Validate signals against declared schemas
8. **Cycle Detection**: Prevent infinite routing loops

### 4.2 Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                           IPC                                    │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                   NODE REGISTRY                          │   │
│  │  { id → instance, class → definition, ... }              │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                  WIRING CONFIGS                          │   │
│  │  { "Tutorial" → {...}, "Playing" → {...}, ... }         │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                  ACTIVE STATE                            │   │
│  │  currentMode = "Playing"                                 │   │
│  │  messageCounter = 12345                                  │   │
│  │  seenMessages = { [msgId] = { nodesSeen } }             │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                   ERROR INPUT                            │   │
│  │  ErrIn ← All Node.Err channels                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 4.3 Message IDs

Every message gets a unique, linear ID:

```lua
-- Request a message ID (blocking, ensures ordering)
local msgId = IPC.getMessageId()

-- Fire signal with ID
self.Out:Fire("dropped", {
    _msgId = msgId,
    item = item
})
```

**Properties:**
- Unique integer, monotonically increasing
- Blocking API ensures one ID at a time
- Used for ordering and cycle detection
- A message ID can only pass through any node once

### 4.4 Context Handling

IPC abstracts server/client under a unified API:

```lua
-- Same code works on both contexts
self.Out:Fire("dropped", item)

-- IPC routes appropriately:
-- - Server node → server targets via BindableEvent
-- - Cross-context → RemoteEvent under the hood
-- - Client node → client targets via BindableEvent
```

Nodes declare their domain but don't check context:

```lua
Dropper = Node.extend({
    domain = "server",  -- IPC only routes to this on server
    ...
})
```

---

## 5. Run Modes & Wiring

### 5.1 Mode Definition

Run modes are named wiring configurations:

```lua
IPC.defineMode("Tutorial", {
    -- Base mode (inherits wiring if not overridden)
    base = "Playing",

    -- Nodes active in this mode
    nodes = { "Dropper", "Evaluator", "HintUI" },

    -- Wiring: source.Out → targets.In
    wiring = {
        Dropper = { "Evaluator", "HintUI" },
        Evaluator = { "Scoreboard" },
    },

    -- Mode-specific attributes applied to nodes
    attributes = {
        Dropper = { DropSpeed = 0.5 },
    },
})

IPC.defineMode("Playing", {
    base = nil,  -- Root mode
    nodes = { "Dropper", "Evaluator", "Scoreboard" },
    wiring = {
        Dropper = { "Evaluator" },
        Evaluator = { "Scoreboard" },
    },
})
```

### 5.2 Mode Inheritance

Modes can inherit from other modes:

```
Playing (root)
    │
    └── Tutorial (extends Playing, adds hints)
    │
    └── HardMode (extends Playing, faster timing)
```

Tutorial gets Playing's wiring plus its own additions/overrides.

### 5.3 Mode Switching

```lua
-- Switch mode (triggers lifecycle)
IPC.switchMode("Playing")

-- Flow:
-- 1. Broadcast onModeChange(oldMode, newMode) to all active nodes
-- 2. Nodes save state/cleanup if needed
-- 3. IPC activates new wiring config
-- 4. Any pending signals processed with new wiring
```

### 5.4 Targeted Routing

Signals can target specific instances:

```lua
-- Broadcast to all wired targets
self.Out:Fire("reset")

-- Target specific instance
self.Out:Fire("reset", { _target = "MarshmallowBag_2" })
```

---

## 6. Contract System

### 6.1 Layered Requirements

Contracts are inherited through the extension chain:

```lua
-- System level: ALL nodes must implement
Node = {
    required = {
        Sys = { "onInit", "onStart", "onStop" },
    },
    defaults = {
        Sys = {
            onInit = function(self) end,  -- Stub
            onStart = function(self) end,
            onStop = function(self) end,
        },
    },
}

-- Lib level: Dispensers must implement
Dispenser = Node.extend({
    required = {
        In = { "onDispense" },  -- No default = MUST implement
    },
    defaults = {
        In = {
            onRefill = function(self, count)
                -- Generic refill logic
            end,
        },
    },
})

-- Game level: Implements requirements
MarshmallowBag = Dispenser.extend({
    In = {
        onDispense = function(self)
            -- Game-specific logic (required, no default)
        end,
        -- onRefill: uses Dispenser default
    },
})
```

### 6.2 Contract Types

| Handler | Required | Default | Result |
|---------|----------|---------|--------|
| Sys.onInit | Yes | Stub provided | Works (stub if not overridden) |
| In.onDispense | Yes | **None** | **Must implement or boot error** |
| In.onRefill | No | Provided | Optional to override |

### 6.3 Bootstrap Validation

At load time, IPC validates all nodes:

```lua
function validateNode(node)
    local missing = {}

    -- Walk inheritance chain
    for _, ancestor in ipairs(node:getInheritanceChain()) do
        for pin, handlers in pairs(ancestor.required or {}) do
            for _, handler in ipairs(handlers) do
                if not node:hasHandler(pin, handler) then
                    table.insert(missing, {
                        handler = pin .. "." .. handler,
                        requiredBy = ancestor.name,
                    })
                end
            end
        end
    end

    if #missing > 0 then
        error(formatMissingHandlersError(node.name, missing))
    end
end
```

**Error output:**
```
[BOOT ERROR] Node 'MyDispenser' missing required handlers:
  - In.onDispense (required by: Dispenser, no default provided)
Game will not run.
```

### 6.4 Payload Contracts

Nodes declare expected payload schemas:

```lua
Dropper = Node.extend({
    In = {
        onDrop = {
            handler = function(self, data) ... end,
            schema = {
                item = "Instance",  -- Required
                position = "Vector3?",  -- Optional
            },
        },
    },
    Out = {
        dropped = {
            schema = {
                item = "Instance",
                dropTime = "number",
            },
        },
    },
})
```

IPC validates payloads and drops/handles invalid ones.

---

## 7. Message Routing

### 7.1 Routing Flow

```
┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐
│  Node A  │    │   IPC    │    │  Wiring  │    │  Node B  │
│          │    │          │    │  Config  │    │          │
│  Out:Fire├───►│ Receive  ├───►│  Lookup  ├───►│  In:Fire │
│          │    │ Validate │    │  Route   │    │  Handler │
└──────────┘    └──────────┘    └──────────┘    └──────────┘
```

### 7.2 Resolution Steps

1. **Get message ID**: Assign unique linear ID
2. **Validate payload**: Check against declared schema
3. **Check cycle**: Has this msgId visited this node before?
4. **Resolve targets**: Look up wiring for current mode
5. **Resolve pins**: Use `{Mode}.In` or fall back to `In`
6. **Dispatch**: Fire on target pins
7. **Track**: Record msgId as seen by each target

### 7.3 Cycle Prevention

```lua
-- IPC tracks seen messages per node
seenMessages = {
    [msgId] = { "NodeA", "NodeB" },  -- Nodes this msg has visited
}

function routeMessage(msg, targetNode)
    local msgId = msg._msgId

    if seenMessages[msgId] and
       table.find(seenMessages[msgId], targetNode) then
        Debug.warn("IPC", "Cycle detected: msgId", msgId, "already visited", targetNode)
        return  -- Drop the message
    end

    -- Track and route
    seenMessages[msgId] = seenMessages[msgId] or {}
    table.insert(seenMessages[msgId], targetNode)

    -- Dispatch to target
    ...
end
```

**Rule**: If recursion is needed, do it inside the node with traditional loops, not by routing messages in a circle.

---

## 8. Error Handling

### 8.1 Error Flow

```
┌──────────┐         ┌──────────┐         ┌──────────┐
│  Node    │         │   IPC    │         │  Debug   │
│          │         │          │         │  System  │
│ Handler  │         │          │         │          │
│   throws ├────────►│  ErrIn   ├────────►│  Output  │
│          │  Err    │  Collect │         │          │
└──────────┘         │  Handle  │         └──────────┘
                     └──────────┘
```

### 8.2 Handler Execution

All handlers are wrapped in protected calls:

```lua
function executeHandler(node, pin, handler, data)
    local success, err = pcall(function()
        node[pin][handler](node, data)
    end)

    if not success then
        -- Send to node's Err channel
        node.Err:Fire({
            handler = pin .. "." .. handler,
            error = err,
            data = data,
            timestamp = os.time(),
        })
    end
end
```

### 8.3 IPC Error Input

IPC collects all errors:

```lua
-- All Node.Err channels connect to IPC.ErrIn
function IPC.handleError(errorData)
    -- Log via Debug system
    Debug.error("IPC", string.format(
        "Handler error in %s.%s: %s",
        errorData.node,
        errorData.handler,
        errorData.error
    ))

    -- Optional: notify interested nodes
    -- Optional: trigger recovery logic
    -- Optional: record to Log system for analytics
end
```

### 8.4 Logging vs Error Propagation

| Need | Mechanism |
|------|-----------|
| Log a debug message | `Debug.info("MyNode", "message")` |
| Trace execution | `Debug.trace("MyNode", "step")` |
| Propagate error to system | `self.Err:Fire(errorData)` |

Nodes don't handle their own errors. System handles all error logic centrally.

---

## 9. Instance Management

### 9.1 Node Instances

Each node instance has a unique ID:

```lua
-- Registration creates instance
local instance = IPC.createInstance("MarshmallowBag", {
    id = "MarshmallowBag_1",  -- Unique ID
    model = workspace.RuntimeAssets.MarshmallowBag_1,
    attributes = { MaxItems = 10 },
})

-- Registry structure
IPC.instances = {
    ["MarshmallowBag_1"] = { instance data },
    ["MarshmallowBag_2"] = { instance data },
}

IPC.nodesByClass = {
    ["MarshmallowBag"] = { "MarshmallowBag_1", "MarshmallowBag_2" },
}
```

### 9.2 Lookup API

```lua
-- Get instance by ID
local bag1 = IPC.getInstance("MarshmallowBag_1")

-- Get all instances of a class
local allBags = IPC.getInstancesByClass("MarshmallowBag")

-- Get all instances in current mode
local activeNodes = IPC.getActiveInstances()
```

### 9.3 Spawn/Despawn

Lifecycle managed by system events:

```lua
-- Spawn: create instance, register, init
IPC.spawn("MarshmallowBag", {
    id = "MarshmallowBag_3",
    model = newModel,
})
-- Flow: create → register → onInit → onStart (if mode active)

-- Despawn: cleanup, unregister, destroy
IPC.despawn("MarshmallowBag_3")
-- Flow: onStop → cleanup hook → unregister → destroy model
```

Nodes can provide hooks:

```lua
Sys = {
    onSpawned = function(self)
        -- Called after spawn, before start
    end,
    onDespawning = function(self)
        -- Called before despawn, opportunity to cleanup
    end,
}
```

---

## 10. Server/Client Context

### 10.1 Unified API

IPC provides a single API that works on both contexts:

```lua
-- Works on server or client
self.Out:Fire("dropped", item)
IPC.broadcast("lifecycle:start")
```

### 10.2 Domain Specification

Nodes declare their domain:

```lua
ServerDropper = Node.extend({
    domain = "server",  -- Only exists on server
    ...
})

ClientParticles = Node.extend({
    domain = "client",  -- Only exists on client
    ...
})

SharedCounter = Node.extend({
    domain = "shared",  -- Exists on both (rare)
    ...
})
```

### 10.3 Cross-Context Routing

IPC handles server/client communication transparently:

```lua
-- Server node fires to client node
-- IPC automatically uses RemoteEvent under the hood
ServerDropper.Out → IPC → RemoteEvent → IPC (client) → ClientParticles.In
```

The node author never deals with RemoteEvents directly.

### 10.4 Context Detection

System provides context flags (already implemented):

```lua
System.isServer  -- true on server
System.isClient  -- true on client
System.isStudio  -- true in Studio
```

Nodes generally don't check these. IPC routes based on declared domain.

---

## 11. State Persistence

### 11.1 State Storage

Node state is held in persistent storage via System.Store API:

```lua
-- In node handler
function onScoreUpdate(self, data)
    -- Save to persistent store
    System.Store.set(self.id .. ".score", data.score)
end

function onInit(self)
    -- Restore from persistent store
    local savedScore = System.Store.get(self.id .. ".score")
    if savedScore then
        self:setAttribute("Score", savedScore)
    end
end
```

### 11.2 Mode Transition State

Nodes can save/restore state during mode changes:

```lua
Sys = {
    onModeChange = function(self, oldMode, newMode)
        -- Save current state before mode change
        self._savedState = {
            position = self.model:GetPivot(),
            attributes = self:getAttributes(),
        }
    end,

    onStart = function(self)
        -- Restore state if available
        if self._savedState then
            self.model:PivotTo(self._savedState.position)
            self:setAttributes(self._savedState.attributes)
            self._savedState = nil
        end
    end,
}
```

### 11.3 Store API (To Be Implemented)

```lua
System.Store.get(key)              -- Get value
System.Store.set(key, value)       -- Set value
System.Store.delete(key)           -- Delete key
System.Store.getAsync(key)         -- Async get (for DataStore)
System.Store.setAsync(key, value)  -- Async set
System.Store.flush()               -- Force persist to DataStore
```

---

## 12. Lifecycle

### 12.1 Boot Sequence

```
1. LOAD
   - System.lua loaded
   - Config.lua loaded from ReplicatedFirst

2. REGISTER
   - Node definitions loaded
   - Contracts validated
   - Instances created
   - Wiring configs validated

3. INIT
   - IPC.broadcast("lifecycle:init")
   - All Sys.onInit handlers called
   - Nodes create resources, connect internal events

4. START
   - IPC.switchMode(initialMode)
   - IPC.broadcast("lifecycle:start")
   - All Sys.onStart handlers called
   - Nodes begin processing signals

5. READY
   - Game is playable
   - Signals flow through wiring
```

### 12.2 Mode Change Sequence

```
1. IPC.switchMode("NewMode") called

2. NOTIFY
   - Broadcast onModeChange(oldMode, newMode) to all nodes
   - Nodes save state, cleanup mode-specific resources

3. SWITCH
   - IPC activates new wiring config
   - New mode's nodes become active

4. RESUME
   - Nodes in new mode receive signals through new wiring
```

### 12.3 Shutdown Sequence

```
1. STOP
   - IPC.broadcast("lifecycle:stop")
   - All Sys.onStop handlers called
   - Nodes cleanup, disconnect events

2. PERSIST
   - System.Store.flush()
   - System.Log.flush()

3. CLEANUP
   - Instances unregistered
   - Connections disconnected
   - Memory released
```

### 12.4 Lifecycle Hooks Summary

| Hook | When | Use For |
|------|------|---------|
| onInit | After registration | Create resources, setup |
| onStart | Mode activated | Begin processing |
| onStop | Mode deactivated / shutdown | Cleanup, save state |
| onModeChange | Before mode switch | Save state, prepare for transition |
| onSpawned | After dynamic spawn | Instance-specific init |
| onDespawning | Before dynamic despawn | Instance cleanup |

---

## 13. API Reference

### 13.1 IPC API

```lua
-- Node Management
IPC.registerNode(definition)                    -- Register node definition
IPC.createInstance(class, config)              -- Create node instance
IPC.getInstance(id)                            -- Get instance by ID
IPC.getInstancesByClass(class)                 -- Get all instances of class
IPC.spawn(class, config)                       -- Dynamic spawn
IPC.despawn(id)                                -- Dynamic despawn

-- Mode Management
IPC.defineMode(name, config)                   -- Define wiring config
IPC.switchMode(name)                           -- Activate mode
IPC.getMode()                                  -- Get current mode name
IPC.getModeConfig(name)                        -- Get mode definition

-- Messaging
IPC.getMessageId()                             -- Get unique message ID (blocking)
IPC.send(sourceId, signal, data)               -- Send through wiring
IPC.broadcast(signal, data)                    -- Broadcast to all Sys.In
IPC.sendTo(targetId, signal, data)             -- Direct to specific instance

-- Lifecycle
IPC.init()                                     -- Initialize IPC system
IPC.start()                                    -- Start message processing
IPC.stop()                                     -- Stop and cleanup
```

### 13.2 Node API

```lua
-- Instance Properties
self.id                     -- Unique instance ID
self.class                  -- Node class name
self.model                  -- Associated Roblox Instance
self.domain                 -- "server", "client", "shared"

-- Pins
self.Sys                    -- System handlers table
self.In                     -- Input handlers table
self.Out                    -- Output channel
self.Err                    -- Error channel

-- Mode-specific pins
self.Tutorial.In            -- Tutorial mode input
self.Tutorial.Out           -- Tutorial mode output

-- Methods
self:getAttribute(name)     -- Get instance attribute
self:setAttribute(name, v)  -- Set instance attribute
self:getAttributes()        -- Get all attributes
self:hasHandler(pin, name)  -- Check if handler exists
self:getInheritanceChain()  -- Get ancestor list
```

### 13.3 Node.extend API

```lua
MyNode = Node.extend({
    -- Required fields
    name = "MyNode",

    -- Optional fields
    domain = "server",
    required = { ... },
    defaults = { ... },

    -- Handlers
    Sys = { ... },
    In = { ... },
    Out = { ... },

    -- Mode-specific
    Tutorial = { ... },
})
```

---

## 14. Implementation Checklist

### Phase 1: Core Infrastructure
- [ ] Node base class with extend()
- [ ] Pin model (Sys, In, Out, Err)
- [ ] Contract validation at registration
- [ ] Default handler injection
- [ ] Inheritance chain resolution

### Phase 2: IPC Core
- [ ] Node registry
- [ ] Instance management (create, get, spawn, despawn)
- [ ] Message ID generation (blocking)
- [ ] Basic signal routing

### Phase 3: Wiring System
- [ ] Mode definition API
- [ ] Wiring configuration storage
- [ ] Mode switching
- [ ] Mode inheritance resolution
- [ ] Pin resolution (mode-specific → default)

### Phase 4: Message Routing
- [ ] Payload validation against schemas
- [ ] Cycle detection via message ID tracking
- [ ] Target resolution (broadcast vs targeted)
- [ ] Cross-context routing (RemoteEvent abstraction)

### Phase 5: Error Handling
- [ ] pcall wrapper for handlers
- [ ] Err channel collection
- [ ] IPC.ErrIn processing
- [ ] Integration with Debug system

### Phase 6: Lifecycle
- [ ] Boot sequence implementation
- [ ] Lifecycle broadcasts
- [ ] Mode change sequence
- [ ] Shutdown sequence
- [ ] Spawn/despawn hooks

### Phase 7: Integration
- [ ] Integration with existing System.Debug
- [ ] Integration with existing System.Log
- [ ] Integration with System.Store (stub if not implemented)
- [ ] Bootstrap.server.lua updates
- [ ] Bootstrap.client.lua creation

### Phase 8: Validation & Testing
- [ ] Unit tests for Node.extend
- [ ] Unit tests for contract validation
- [ ] Unit tests for message routing
- [ ] Integration test with sample nodes
- [ ] Performance validation

---

## Appendix A: Example Node Definitions

### A.1 Minimal Node

```lua
MyNode = Node.extend({
    name = "MyNode",

    Sys = {
        onInit = function(self)
            Debug.info(self.id, "initialized")
        end,
    },

    In = {
        onSignal = function(self, data)
            self.Out:Fire("response", { received = true })
        end,
    },
})
```

### A.2 Dispenser Pattern

```lua
-- Lib: Base dispenser
Dispenser = Node.extend({
    name = "Dispenser",
    domain = "server",

    required = {
        In = { "onDispense" },
    },

    defaults = {
        In = {
            onRefill = function(self, count)
                self:setAttribute("Remaining", count or self:getAttribute("MaxItems"))
                self.Out:Fire("refilled", { count = self:getAttribute("Remaining") })
            end,
            onReset = function(self)
                self.In.onRefill(self)
            end,
        },
    },

    Sys = {
        onInit = function(self)
            self:setAttribute("Remaining", self:getAttribute("MaxItems") or 10)
        end,
    },
})

-- Game: Marshmallow bag
MarshmallowBag = Dispenser.extend({
    name = "MarshmallowBag",

    In = {
        onDispense = function(self)
            local remaining = self:getAttribute("Remaining")
            if remaining <= 0 then
                self.Out:Fire("empty")
                return
            end

            local marshmallow = self:createMarshmallow()
            self:setAttribute("Remaining", remaining - 1)
            self.Out:Fire("dispensed", { item = marshmallow })

            if remaining - 1 <= 0 then
                self.Out:Fire("empty")
            end
        end,
    },

    -- Private methods
    createMarshmallow = function(self)
        -- Game-specific marshmallow creation
    end,
})
```

### A.3 Mode-Specific Behavior

```lua
Dropper = Node.extend({
    name = "Dropper",
    domain = "server",

    -- Default behavior
    In = {
        onDrop = function(self, data)
            local speed = self:getAttribute("DropSpeed") or 1.0
            self:dropItem(data.item, speed)
            self.Out:Fire("dropped", { item = data.item })
        end,
    },

    -- Tutorial: slower with hints
    Tutorial = {
        In = {
            onDrop = function(self, data)
                self:showHint("Watch the item drop!")
                self:setAttribute("DropSpeed", 0.3)
                self.In.onDrop(self, data)  -- Cascade to default
                self:showFeedback("Great!")
            end,
        },
    },

    -- Playing: uses default (no override)
    -- Results: disabled (not in nodes list for that mode)
})
```

---

## Appendix B: Example Wiring Configuration

```lua
-- Define modes
IPC.defineMode("Playing", {
    nodes = {
        "MarshmallowBag",
        "Campfire",
        "Evaluator",
        "Scoreboard",
        "Timer",
    },
    wiring = {
        MarshmallowBag = { "Evaluator" },
        Campfire = { "Evaluator" },
        Evaluator = { "Scoreboard" },
        Timer = { "Orchestrator" },
    },
})

IPC.defineMode("Tutorial", {
    base = "Playing",
    nodes = {
        "MarshmallowBag",
        "Campfire",
        "Evaluator",
        "Scoreboard",
        "Timer",
        "HintUI",  -- Additional node
    },
    wiring = {
        -- Inherits Playing wiring, plus:
        MarshmallowBag = { "Evaluator", "HintUI" },
        Evaluator = { "Scoreboard", "HintUI" },
    },
    attributes = {
        Timer = { Duration = 120 },  -- Longer time for tutorial
        MarshmallowBag = { MaxItems = 5 },  -- Fewer items
    },
})

IPC.defineMode("Results", {
    nodes = { "Scoreboard", "Leaderboard" },
    wiring = {
        Scoreboard = { "Leaderboard" },
    },
})
```

---

**End of Specification**
