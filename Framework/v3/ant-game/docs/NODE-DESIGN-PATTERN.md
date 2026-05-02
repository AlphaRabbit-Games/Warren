# Node Design Pattern

Warren Framework v2 - Canonical Node Architecture

## Overview

All nodes in the framework follow a consistent design pattern that ensures:
- True encapsulation (no architectural violations possible)
- Signal-only inter-node communication (full IPC)
- Deterministic discovery and composition
- Clean lifecycle management

## Core Principles

### 1. Closure-Based Privacy

Private state is truly private - it doesn't exist on the node instance at all.

```lua
local MyNode = Node.extend(function(parent)
    -- PRIVATE SCOPE - nothing here exists on the instance
    local instanceStates = {}

    local function getState(self)
        if not instanceStates[self.id] then
            instanceStates[self.id] = {
                -- All private state here
                internalValue = 0,
                connections = {},
            }
        end
        return instanceStates[self.id]
    end

    local function cleanupState(self)
        instanceStates[self.id] = nil
    end

    -- Private functions (not on instance)
    local function doSomethingPrivate(self, data)
        local state = getState(self)
        -- ...
    end

    -- PUBLIC INTERFACE - only this is exposed
    return {
        name = "MyNode",
        domain = "server",
        Sys = { ... },
        In = { ... },
        Out = { ... },
    }
end)
```

**Why**: Prevents architectural violations. Claude (or any developer) cannot call `node._privateMethod()` because it doesn't exist.

### 2. Signal-Only IPC

Nodes communicate exclusively through signals. No direct method calls between nodes.

```lua
-- WRONG: Direct method call
otherNode:doSomething(data)

-- CORRECT: Signal emission
self.Out:Fire("requestSomething", { data = data })
-- Wiring delivers to: otherNode.In.onRequestSomething
```

**Why**:
- Decouples nodes completely
- Enables declarative wiring
- Makes data flow explicit and traceable
- Allows orchestrators to intercept/transform/validate

### 3. Discovery Handshake Pattern

Nodes discover external dependencies during `onStart` via synchronous handshake signals.

```lua
Sys = {
    onStart = function(self)
        local state = getState(self)

        -- Discovery: check if external component is wired
        state.hasExternalDependency = false
        self.Out:Fire("discoverDependency", { nodeId = self.id })
        -- If wired, handler sets hasExternalDependency = true synchronously

        -- Now we know whether to use internal or external
        if not state.hasExternalDependency then
            initializeInternalDefault(self)
        end
    end,
},

In = {
    -- Called synchronously if dependency responds
    onDependencyPresent = function(self, data)
        local state = getState(self)
        state.hasExternalDependency = true
        state.externalId = data.dependencyId
    end,
}
```

**Why**:
- No config flags needed (`useExternalX = true`)
- Wiring is frozen by `onStart`, so handshake is deterministic
- Self-documenting: wiring table shows all relationships

### 4. Component Composition Pattern

Every component follows this pattern:

1. **Internal defaults work out of the box** - No config required
2. **Declarative config for customization** - Attributes/config override defaults
3. **External component gets full authority** - When wired, internal is bypassed

```lua
-- Launcher has internal ammo tracking by default
-- If Magazine is wired, Magazine owns all ammo state

onStart = function(self)
    state.hasExternalMagazine = false
    self.Out:Fire("discoverMagazine", { launcherId = self.id })

    -- After handshake, we know which mode we're in
    if not state.hasExternalMagazine then
        -- Use internal ammo (self-contained operation)
        state.currentAmmo = self:getAttribute("MagazineCapacity")
    end
    -- If external, Magazine owns ammo - we just request/receive
end
```

### 5. Orchestrator Two-Phase Startup

When an Orchestrator manages multiple nodes, it MUST:

1. **Phase 1: Wire ALL nodes** - Intercept `Out.Fire` for routing
2. **Phase 2: Start ALL nodes** - Call `onStart` after all wiring is in place

```lua
enableRouting = function(self)
    state.enabled = true

    -- Phase 1: Wire all nodes (intercept Out.Fire)
    for nodeId in pairs(state.nodes) do
        wireNode(self, nodeId)
    end

    -- Phase 2: Start all nodes (now all wiring is in place)
    for nodeId in pairs(state.nodes) do
        startNode(self, nodeId)
    end
end
```

**Why**: Discovery handshakes fire during `onStart`. If Node A fires `discoverB` but Node B isn't wired yet, B's response won't be routed and the handshake fails.

### 6. Lifecycle Responsibilities

#### `onInit`
- Create instance state via `getState(self)`
- Set default attributes
- Do NOT fire signals
- Do NOT start runtime behavior

#### `onStart`
- Fire discovery handshake signals
- Initialize runtime behavior (loops, connections)
- Safe to fire signals (wiring is in place)

#### `onStop`
- Stop all runtime behavior (loops, connections)
- Call `cleanupState(self)` - CRITICAL for memory
- Do NOT fire signals

```lua
Sys = {
    onInit = function(self)
        local state = getState(self)

        -- Set defaults
        if self:getAttribute("Speed") == nil then
            self:setAttribute("Speed", 10)
        end
    end,

    onStart = function(self)
        local state = getState(self)

        -- Discovery handshakes
        self.Out:Fire("discoverDependency", {})

        -- Start runtime
        state.updateConnection = RunService.Heartbeat:Connect(function(dt)
            update(self, dt)
        end)
    end,

    onStop = function(self)
        local state = getState(self)

        -- Stop runtime
        if state.updateConnection then
            state.updateConnection:Disconnect()
        end

        -- CRITICAL: Clean up state
        cleanupState(self)
    end,
}
```

## Orchestrator as IC (Integrated Circuit)

Orchestrators present a simple external interface while managing internal complexity:

```lua
-- External view: simple In/Out
orchestrator.In.onFire(orchestrator, { target = pos })
-- Internally: routes to Launcher, which requests from Magazine, etc.

-- Declarative wiring with special targets
wiring = {
    -- Internal routing between managed nodes
    { from = "Launcher", signal = "requestAmmo", to = "Magazine", handler = "onDispense" },

    -- "Out": Forward to orchestrator's own Out (for external consumers)
    { from = "Launcher", signal = "fired", to = "Out" },
    { from = "Magazine", signal = "ammoChanged", to = "Out" },

    -- "Self": Route to orchestrator's own In handlers (for internal handling)
    { from = "Spawner", signal = "spawned", to = "Self", handler = "onTargetSpawned" },
}
```

### Orchestrator Wiring Targets

| Target | Purpose | Handler |
|--------|---------|---------|
| `"NodeId"` | Route to managed node's In | Required - e.g., `"onConfigure"` |
| `"Out"` | Forward to orchestrator's Out | Optional - defaults to signal name |
| `"Self"` | Route to orchestrator's own In | Required - e.g., `"onTargetSpawned"` |
| `"Client"` | Reserved for client replication | N/A |

**When to use "Self":**
- Orchestrator needs to handle signals from its managed nodes internally
- Processing spawned entities (configure, track, wire their signals)
- Aggregating data before forwarding to Out
- Implementing orchestrator-level business logic

## Signal Naming Conventions

### Input Handlers (`In`)
- Prefix: `on`
- Examples: `onFire`, `onConfigure`, `onMagazinePresent`, `onAmmoReceived`

### Output Signals (`Out`)
- No prefix, past tense or noun
- Examples: `fired`, `configured`, `ammoChanged`, `discoverMagazine`

### Discovery Signals
- Output: `discover{Thing}` - "I'm looking for a Thing"
- Input: `on{Thing}Present` - "I am the Thing you're looking for"

## Standard Signal Pairs

### Handshake (discovery)
```
NodeA.Out.discoverB     → NodeB.In.onDiscoverB (optional, if B needs data)
NodeB.Out.bPresent      → NodeA.In.onBPresent
```

### Request/Response
```
NodeA.Out.requestThing  → NodeB.In.onRequestThing
NodeB.Out.thingReady    → NodeA.In.onThingReady
```

### State Change Notification
```
NodeA.Out.stateChanged  → (any subscriber)
```

## File Template

```lua
--[[
    Warren Framework v2
    {ComponentName}.lua - {Brief Description}

    Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC
    All rights reserved.

    ============================================================================
    OVERVIEW
    ============================================================================

    {What this component does, its purpose in the system}

    ============================================================================
    SIGNALS
    ============================================================================

    IN (receives):
        on{Signal}({ param1, param2 })
            - Description

    OUT (emits):
        {signal}({ param1, param2 })
            - Description

    ============================================================================
    ATTRIBUTES
    ============================================================================

    {AttributeName}: {type} (default {value})
        Description

--]]

local Node = require(script.Parent.Parent.Node)

local {ComponentName} = Node.extend(function(parent)
    -- Per-instance state registry
    local instanceStates = {}

    local function getState(self)
        if not instanceStates[self.id] then
            instanceStates[self.id] = {
                -- Private state
            }
        end
        return instanceStates[self.id]
    end

    local function cleanupState(self)
        instanceStates[self.id] = nil
    end

    -- Private functions

    return {
        name = "{ComponentName}",
        domain = "server",  -- or "client" or "shared"

        Sys = {
            onInit = function(self)
                local state = getState(self)
                -- Set default attributes
            end,

            onStart = function(self)
                local state = getState(self)
                -- Discovery handshakes
                -- Start runtime
            end,

            onStop = function(self)
                local state = getState(self)
                -- Stop runtime
                cleanupState(self)
            end,
        },

        In = {
            onConfigure = function(self, data)
                -- Handle configuration
            end,
        },

        Out = {
            -- Signal declarations
        },
    }
end)

return {ComponentName}
```

## Hierarchical Orchestrator Composition

**This is a core design imperative for ALL complex/nested node hierarchies.**

### The Problem

When building complex systems, you need to combine multiple subsystems. A naive approach creates a flat orchestrator that directly manages all primitives:

```
❌ WRONG: Flat Orchestrator (anti-pattern)

TurretOrchestrator (flat)
  -> yawSwivel (primitive)
  -> pitchSwivel (primitive)
  -> launcher (primitive)
  -> magazine (primitive)
  -> battery (primitive)
```

This violates separation of concerns:
- The turret orchestrator must understand how swivels work together
- It must understand how launcher/magazine/battery interact
- Adding features requires modifying the main orchestrator
- No reusability of subsystem logic

### The Solution: Hierarchical Composition

Complex orchestrators compose sub-orchestrators, not primitives:

```
✅ CORRECT: Hierarchical Orchestrators

SwivelLauncherOrchestrator (main)
  ├── SwivelOrchestrator (sub)
  │     ├── Yaw Swivel (primitive)
  │     └── Pitch Swivel (primitive)
  └── LauncherOrchestrator (sub)
        ├── Launcher (primitive)
        ├── Magazine/Dropper (primitive)
        └── Battery (primitive)
```

### Core Rules

#### Rule 1: Orchestrators Control Sub-Orchestrators, Not Primitives

A parent orchestrator NEVER directly accesses a child orchestrator's primitives.

```lua
-- ❌ WRONG: Parent accessing child's primitives
local yawSwivel = state.swivelOrchestrator._yawSwivel
yawSwivel.In.onRotate(yawSwivel, data)

-- ✅ CORRECT: Parent sends signal to child orchestrator
state.swivelOrchestrator.In.onRotateYaw(state.swivelOrchestrator, data)
```

**Why**: Each orchestrator encapsulates its internal structure. The parent doesn't need to know (or care) how the child implements its functionality.

#### Rule 2: Signals Cascade Down the Tree

Input signals flow from parent → child → grandchild → primitive:

```
User calls: turret.In.onRotateYaw(data)
     │
     ▼
SwivelLauncherOrchestrator.In.onRotateYaw
     │ (forwards to sub-orchestrator)
     ▼
SwivelOrchestrator.In.onRotateYaw
     │ (forwards to primitive)
     ▼
YawSwivel.In.onRotate
```

```lua
-- Parent orchestrator
In = {
    onRotateYaw = function(self, data)
        local state = getState(self)
        -- Forward to sub-orchestrator (not primitive!)
        state.swivelOrchestrator.In.onRotateYaw(state.swivelOrchestrator, data)
    end,
}
```

#### Rule 3: Signals Bubble Up the Tree

Output signals flow from primitive → child → parent → external consumer:

```
Launcher.Out.fired
     │
     ▼
LauncherOrchestrator intercepts, forwards up
     │
     ▼
SwivelLauncherOrchestrator.Out.fired
     │
     ▼
External consumer (HUD, game logic, etc.)
```

```lua
-- In parent orchestrator's onInit
local launcherOriginalFire = state.launcherOrchestrator.Out.Fire
state.launcherOrchestrator.Out.Fire = function(outSelf, signal, data)
    -- Forward signals up to parent's Out
    if signal == "fired" or signal == "ammoChanged" then
        self.Out:Fire(signal, data)
    end
    launcherOriginalFire(outSelf, signal, data)
end
```

#### Rule 4: Each Orchestrator Owns Its Primitives Exclusively

The orchestrator that creates a primitive is solely responsible for:
- Initializing it (`onInit`)
- Starting it (`onStart`)
- Stopping it (`onStop`)
- Wiring its signals

```lua
-- LauncherOrchestrator owns launcher, magazine, battery
Sys = {
    onInit = function(self)
        state.launcher = Launcher:new(...)
        state.launcher.Sys.onInit(state.launcher)

        state.magazine = Dropper:new(...)
        state.magazine.Sys.onInit(state.magazine)

        -- Wire them together (internal to this orchestrator)
        -- ...
    end,

    onStop = function(self)
        -- Stop everything we created
        state.launcher.Sys.onStop(state.launcher)
        state.magazine.Sys.onStop(state.magazine)
        cleanupState(self)
    end,
}
```

#### Rule 5: Parent Creates Physical "Glue" Between Subsystems

When subsystems need physical connections (welds, attachments), the parent orchestrator creates the connecting parts:

```lua
-- SwivelLauncherOrchestrator creates the muzzle that connects
-- the swivel subsystem to the launcher subsystem
onInit = function(self)
    -- Create muzzle (this is the "glue" part)
    local muzzle = Instance.new("Part")
    muzzle.Name = self.id .. "_Muzzle"

    -- Weld to pitch swivel (from swivel subsystem)
    local weld = Instance.new("WeldConstraint")
    weld.Part0 = pitchPart
    weld.Part1 = muzzle
    weld.Parent = muzzle

    state.muzzlePart = muzzle

    -- Swivel orchestrator uses provided parts
    state.swivelOrchestrator = SwivelOrchestrator:new({
        model = yawPart,
        attributes = { pitchModel = pitchPart },
    })

    -- Launcher orchestrator uses the muzzle we created
    state.launcherOrchestrator = LauncherOrchestrator:new({
        model = muzzle,  -- Connected to swivel via weld
    })
end
```

#### Rule 6: Sub-Orchestrators Must Expose Complete Interfaces

If parent needs functionality, child MUST expose it as a signal:

```lua
-- ❌ WRONG: Parent accesses child's internal state
local pitchSwivel = state.swivelOrchestrator._pitchSwivel
pitchSwivel.In.onSetAngle(pitchSwivel, data)

-- ✅ CORRECT: Child exposes signal for parent to use
-- In SwivelOrchestrator:
In = {
    onSetPitchAngle = function(self, data)
        local state = getState(self)
        state.pitchSwivel.In.onSetAngle(state.pitchSwivel, data)
    end,
}

-- Parent uses the exposed signal:
state.swivelOrchestrator.In.onSetPitchAngle(state.swivelOrchestrator, data)
```

### Scaling to Deeper Hierarchies

The pattern scales to any depth. A game might have:

```
GameOrchestrator
  ├── PlayerOrchestrator
  │     ├── MovementOrchestrator
  │     │     ├── WalkController (primitive)
  │     │     └── JumpController (primitive)
  │     └── CombatOrchestrator
  │           ├── SwivelLauncherOrchestrator (sub-orchestrator!)
  │           │     ├── SwivelOrchestrator
  │           │     └── LauncherOrchestrator
  │           └── HealthOrchestrator
  │                 ├── EntityStats (primitive)
  │                 └── DamageCalculator (primitive)
  └── WorldOrchestrator
        ├── SpawnerOrchestrator
        └── ZoneOrchestrator
```

Each level follows the same rules:
- Control sub-orchestrators via signals
- Never reach into grandchildren
- Forward signals up/down appropriately

### Complete Example: SwivelLauncherOrchestrator

```lua
local SwivelLauncherOrchestrator = Orchestrator.extend(function(parent)
    local instanceStates = {}

    local function getState(self)
        if not instanceStates[self.id] then
            instanceStates[self.id] = {
                swivelOrchestrator = nil,
                launcherOrchestrator = nil,
                muzzlePart = nil,  -- Physical glue
            }
        end
        return instanceStates[self.id]
    end

    return {
        name = "SwivelLauncherOrchestrator",
        domain = "server",

        Sys = {
            onInit = function(self)
                parent.Sys.onInit(self)
                local config = self._attributes or {}
                local state = getState(self)

                -- Create physical glue (muzzle welded to pitch)
                local muzzle = Instance.new("Part")
                -- ... weld to pitchPart ...
                state.muzzlePart = muzzle

                -- Create sub-orchestrator: Swivel
                state.swivelOrchestrator = SwivelOrchestrator:new({
                    model = self.model,
                    attributes = {
                        pitchModel = config.pitchModel,
                        yawConfig = config.yawConfig,
                        pitchConfig = config.pitchConfig,
                    },
                })
                state.swivelOrchestrator.Sys.onInit(state.swivelOrchestrator)

                -- Create sub-orchestrator: Launcher
                state.launcherOrchestrator = LauncherOrchestrator:new({
                    model = muzzle,
                    attributes = {
                        fireMode = config.fireMode,
                        magazineCapacity = config.magazineCapacity,
                        -- ...
                    },
                })
                state.launcherOrchestrator.Sys.onInit(state.launcherOrchestrator)

                -- Forward Out signals from children to parent's Out
                setupSignalForwarding(self)
            end,

            onStart = function(self)
                parent.Sys.onStart(self)
                local state = getState(self)

                -- Start sub-orchestrators (they start their primitives)
                state.swivelOrchestrator.Sys.onStart(state.swivelOrchestrator)
                state.launcherOrchestrator.Sys.onStart(state.launcherOrchestrator)
            end,

            onStop = function(self)
                local state = getState(self)

                -- Stop sub-orchestrators (they stop their primitives)
                state.launcherOrchestrator.Sys.onStop(state.launcherOrchestrator)
                state.swivelOrchestrator.Sys.onStop(state.swivelOrchestrator)

                -- Cleanup our physical glue
                if state.muzzlePart then
                    state.muzzlePart:Destroy()
                end

                cleanupState(self)
                parent.Sys.onStop(self)
            end,
        },

        In = {
            -- Forward to swivel sub-orchestrator
            onRotateYaw = function(self, data)
                getState(self).swivelOrchestrator.In.onRotateYaw(
                    getState(self).swivelOrchestrator, data
                )
            end,

            -- Forward to launcher sub-orchestrator
            onFire = function(self, data)
                getState(self).launcherOrchestrator.In.onFire(
                    getState(self).launcherOrchestrator, data
                )
            end,
        },

        Out = {
            -- Swivel signals (bubbled up from SwivelOrchestrator)
            yawRotated = {},
            pitchRotated = {},

            -- Launcher signals (bubbled up from LauncherOrchestrator)
            fired = {},
            ammoChanged = {},
        },
    }
end)
```

### Benefits

1. **Separation of Concerns**: Each orchestrator handles one subsystem
2. **Reusability**: `SwivelOrchestrator` can be used in turrets, cameras, doors, etc.
3. **Maintainability**: Changes to swivel logic don't affect launcher code
4. **Testability**: Each orchestrator can be tested in isolation
5. **Scalability**: Unlimited nesting depth with consistent patterns
6. **Encapsulation**: Internal structure hidden from parent

### Anti-Patterns to Avoid

```lua
-- ❌ Flat orchestrator managing all primitives
-- ❌ Parent reaching into child's primitives
-- ❌ Primitives directly referencing each other
-- ❌ Signals skipping levels (grandchild → grandparent directly)
-- ❌ Sub-orchestrator exposing its primitives publicly
```

## Summary

1. **Privacy**: Closure pattern makes violations impossible
2. **Communication**: Signal-only IPC, no direct calls
3. **Discovery**: Handshake pattern in `onStart`, deterministic
4. **Composition**: Internal defaults, config overrides, external authority
5. **Orchestrator**: Two-phase startup (wire all, then start all)
6. **Lifecycle**: Init (state), Start (signals/runtime), Stop (cleanup)
7. **Hierarchy**: Orchestrators compose sub-orchestrators, signals cascade down/up
