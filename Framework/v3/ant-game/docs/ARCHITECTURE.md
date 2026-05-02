# Warren Framework v2 - Architecture

## Overview

Warren is a Roblox game framework designed for developer ergonomics. It follows an **Arduino-like model** where games are composed of modular components wired together through a unified messaging bus.

## Design Principles

1. **Single ModuleScript per system** - All subsystem code lives in nested modules within one file
2. **No code runs on load** - Bootstrap script controls execution order
3. **Explicit registration** - Declarative manifest defines components and wiring (no auto-discovery)
4. **Closure-protected internals** - Public API surface, private implementation via local functions
5. **Singleton/Factory pattern** - Each system module acts as singleton or factory
6. **Minimal dependencies** - Systems are isolated, communicate via IPC

## Package Structure

```
Warren/
├── src/
│   ├── Lib/
│   │   ├── init.lua              <- Main entry (exports System, Node, Components)
│   │   ├── System.lua            <- Core subsystems (Debug, IPC, Asset, etc.)
│   │   ├── Node.lua              <- Base class + Registry for all components
│   │   ├── Components/           <- Reusable component library
│   │   │   ├── init.lua
│   │   │   ├── PathFollower.lua  <- Waypoint navigation
│   │   │   ├── PathedConveyor.lua <- Physics-based conveyor belt
│   │   │   ├── Dropper.lua       <- Interval-based spawning
│   │   │   ├── Hatcher.lua       <- Gacha/egg mechanics
│   │   │   ├── Zone.lua          <- Region detection
│   │   │   ├── Checkpoint.lua    <- Direction-aware threshold
│   │   │   ├── NodePool.lua      <- Generic node pooling
│   │   │   └── Orchestrator.lua  <- Declarative composition & wiring
│   │   ├── Internal/             <- Internal utilities (not public API)
│   │   │   ├── init.lua
│   │   │   ├── SpawnerCore.lua   <- Shared spawn/despawn mechanics
│   │   │   ├── PathFollowerCore.lua <- Shared path infrastructure
│   │   │   ├── EntityUtils.lua   <- Common entity helpers
│   │   │   └── SchemaValidator.lua <- Payload validation for Orchestrator
│   │   └── Tests/
│   │       ├── IPC_Node_Tests.lua
│   │       ├── Hatcher_Tests.lua
│   │       ├── Zone_Tests.lua
│   │       ├── Dropper_Tests.lua
│   │       ├── PathedConveyor_Tests.lua
│   │       ├── Checkpoint_Tests.lua
│   │       ├── ConveyorBelt_Tests.lua  <- Visual composition demo
│   │       ├── SchemaValidator_Tests.lua
│   │       └── Orchestrator_Tests.lua
│   ├── Game/                     <- Game-specific nodes
│   │   └── init.lua
│   └── Bootstrap/
│       ├── Bootstrap.server.lua
│       └── Bootstrap.client.lua
├── docs/
│   ├── ARCHITECTURE.md           <- This file
│   └── IPC_NODE_SPEC.md          <- Detailed node/IPC specification
└── Logs/
    └── COMPONENT_REGISTRY.md     <- Master component catalog
```

Games using this library (separate repos):
```
SomeGame/
├── src/
│   ├── Manifest.lua         <- Structure + wiring
│   └── Style.lua            <- Presentation
├── wally.toml               <- Depends on Warren
└── default.project.json
```

## The Arduino Model

Each asset module is like a sensor/motor with standardized I/O:

```
┌─────────────────────────────────────────────────────────────┐
│                      ORCHESTRATOR                           │
│                    (main logic board)                       │
└─────────────────┬───────────────────┬───────────────────────┘
                  │                   │
        ┌─────────▼─────────┐ ┌───────▼─────────┐
        │   WaveController  │ │   Scoreboard    │  <- Asset Modules
        │  [In] [Out] [Dbg] │ │ [In] [Out] [Dbg]│     (ICUs)
        └─────────┬─────────┘ └───────┬─────────┘
                  │                   │
    ┌─────────────▼───────────────────▼─────────────┐
    │                  IPC BUS                       │  <- Routes signals
    │          (context-aware routing)               │     by runtime state
    └──┬──────────┬──────────┬──────────┬───────────┘
       │          │          │          │
   ┌───▼───┐  ┌───▼───┐  ┌───▼───┐  ┌───▼───┐
   │Dropper│  │Dropper│  │Dropper│  │Dropper│  <- Asset Modules
   │  [I/O]│  │  [I/O]│  │  [I/O]│  │  [I/O]│     (sensors/motors)
   └───────┘  └───────┘  └───────┘  └───────┘
```

### Module Channels (Pin Model)

Every node has 4 standardized channels (pins):

| Pin | Direction | Purpose |
|-----|-----------|---------|
| **Sys.In** | System → Node | Lifecycle signals (init, start, stop, modeChange) |
| **In** | Node → Node | Game signals from other nodes via wiring |
| **Out** | Node → Node | Outbound signals to other nodes via wiring |
| **Err** | Node → System/Handlers | Detour/exception signals for non-linear flow |

#### The Err Channel (Detour Pattern)

The Err channel is NOT just for errors - it's a **detour/exception channel** for handling non-linear flow:

```
Normal flow:    In → process → Out
Detour flow:    In → process → [unexpected condition] → Err → different handler
```

Use cases:
- Collision during navigation → Err with collision info
- Timeout waiting for acknowledgment → Err with timeout info
- Resource unavailable → Err with fallback options

This is similar to try/catch exception patterns - routing variant conditions without nested if/else logic. Err signals can be wired to different handlers per mode.

## Two Declarative Files (Game-Side)

### Manifest (Structure + Wiring)
Like an HTML document - defines what components exist and how they connect:
- Component instances
- Input/Output wiring between modules
- Runtime context rules (when connections are active)

### Style (Presentation)
Defines visual properties:
- 3D transforms and arrangement
- GUI layouts and styling
- Audio properties
- Tween configurations

## System Submodules

All system code lives in `System.lua` as nested modules:

| Submodule | Purpose | Client | Server |
|-----------|---------|--------|--------|
| **Debug** | Logging, telemetry, dev tools | ✓ | ✓ |
| **IPC** | Unified messaging bus, routing, context-aware transport | ✓ | ✓ |
| **State** | Shared state with client/server boundaries | ✓ | ✓ |
| **Asset** | Template registry, spawning, lifecycle | - | ✓ |
| **Store** | DataStore abstraction, persistence | - | ✓ |
| **View** | Presentation (GUI, 3D, audio, tweens) | ✓ | - |
| **InputCapture** | Exclusive input focus, declarative control mapping | ✓ | - |

### IPC Details

The IPC subsystem provides unified messaging that abstracts:
- **BindableEvent** - Same-context communication (server↔server, client↔client)
- **RemoteEvent** - Cross-boundary communication (client↔server)

Same grammar/API regardless of transport. Context-aware routing under the hood.

### View Details

The View subsystem handles all presentation:
- ScreenGui / BillboardGui creation
- Model/Part transforms and visibility
- TweenService integration
- SoundService integration
- Lighting/atmosphere (future)

### InputCapture Details

The InputCapture subsystem (client-only) provides exclusive input focus with a claim/release pattern. Only one consumer can claim input at a time.

#### Basic Usage (Raw Input)

```lua
local InputCapture = Lib.System.InputCapture

local claim = InputCapture.claim({
    onInputBegan = function(input, gameProcessed)
        if input.KeyCode == Enum.KeyCode.Space then
            -- Handle space press
        end
    end,
    onInputEnded = function(input, gameProcessed) end,
    onInputChanged = function(input, gameProcessed) end,  -- Analog input
    onRelease = function() end,  -- Called if forcibly released
}, { disableCharacter = true })  -- Freezes player movement

-- Later:
claim:release()
```

#### Declarative Control Mapping (Recommended)

For nodes with complex input requirements, use declarative control mappings:

```lua
local TurretController = Node.extend({
    name = "TurretController",
    domain = "client",

    -- Declarative control mapping
    Controls = {
        aimUp = {
            keys = { Enum.KeyCode.Up },
            buttons = { Enum.KeyCode.DPadUp },
            axis = { stick = "Thumbstick1", direction = "Y+", deadzone = 0.2 },
        },
        fire = {
            keys = { Enum.KeyCode.Space },
            buttons = { Enum.KeyCode.ButtonA, Enum.KeyCode.ButtonR2 },
        },
        exit = {
            keys = { Enum.KeyCode.E },
            buttons = { Enum.KeyCode.ButtonY },
            holdDuration = 1.5,  -- Hold-to-trigger
        },
    },

    In = {
        onActionBegan = function(self, action)
            if action == "fire" then self:fire() end
        end,
        onActionEnded = function(self, action) end,
        onActionHeld = function(self, action, progress) end,  -- 0.0-1.0
        onActionTriggered = function(self, action) end,       -- Hold complete
        onControlReleased = function(self) end,               -- Forcibly released
    },
})

-- Claim input with declarative mapping
local claim = InputCapture.claimForNode(controller, { disableCharacter = true })
```

Benefits:
- **Device-agnostic**: Keyboard, gamepad, thumbstick map to same actions
- **Declarative**: Control schema on node class, not imperative if/else chains
- **Remappable**: Change bindings without touching node logic (future)
- **Hold-to-trigger**: Built-in support for hold-duration actions

## Boot Stages

Simplified from v1's 8 stages to 3:

| Stage | What Happens |
|-------|--------------|
| **INIT** | Create state, events. No connections yet. |
| **START** | Connect events, begin logic. |
| **READY** | Everything live, game playable. |

Bootstrap script calls each stage in order. Modules register via manifest and are initialized according to dependency order (topological sort).

## Client/Server Separation

- **Shared code** where possible (same module, context-aware behavior)
- **Server-authoritative** game state (anti-cheat)
- **Client-side** visuals and most physics
- Server receives physics state reports where gameplay requires validation

## Dependency Resolution

Modules declare dependencies. System performs topological sort to determine initialization order. This scales as the library grows without manual tracking.

## Component Library

Reusable game components live in `Lib/Components/`. These extend the Node base class and follow the pin model.

### Available Components

| Component | Purpose | Status |
|-----------|---------|--------|
| **PathFollower** | Navigate entities through waypoints (Humanoid or Tween) | Implemented |
| **PathedConveyor** | Physics-based conveyor belt with per-segment speeds | Implemented |
| **Dropper** | Interval-based entity spawning with pool/capacity support | Implemented |
| **Hatcher** | Gacha/egg mechanics with weighted rarity and pity | Implemented |
| **Zone** | Region detection with declarative filtering | Implemented |
| **Checkpoint** | Direction-aware threshold detection (6-face box) | Implemented |
| **NodePool** | Generic node pooling (fixed or elastic mode) | Implemented |
| **Orchestrator** | Declarative component composition with schema validation | Implemented |
| **HealthSystem** | Damage, healing, death | Planned |
| **Currency** | Player economy tracking | Planned |

See `Logs/COMPONENT_REGISTRY.md` for the full catalog of planned components.

### Internal Modules

Internal utilities live in `Lib/Internal/`. These are NOT part of the public API:

| Module | Purpose |
|--------|---------|
| **SpawnerCore** | Template lookup, cloning, asset ID tracking, despawn |
| **PathFollowerCore** | Waypoints, segments, per-segment speeds, direction calculation |
| **EntityUtils** | Common entity helpers (getPosition, getId, passesFilter, isPlayer) |
| **SchemaValidator** | Payload validation with type checking, enum, range, custom validators |

SpawnerCore is used by Dropper, Hatcher, and future spawning components.
PathFollowerCore is used by PathFollower and PathedConveyor for shared path infrastructure.
EntityUtils is used by Zone, Checkpoint, PathedConveyor for entity detection helpers.
SchemaValidator is used by Orchestrator for message contract validation.

### Usage

```lua
local Lib = require(game.ReplicatedStorage.Lib)
local PathFollower = Lib.Components.PathFollower

-- Register with Asset system
Lib.System.Asset.register(PathFollower)

-- Create instance via IPC
local pf = Lib.System.IPC.createInstance("PathFollower", {
    id = "PathFollower_1",
    attributes = { Speed = 16, CollisionMode = "physics" },
})
```

### Creating Custom Components

Extend Node for game-specific components:

```lua
local Node = require(game.ReplicatedStorage.Lib).Node

local MyComponent = Node.extend({
    name = "MyComponent",
    domain = "server",  -- or "client", "shared"

    Sys = {
        onInit = function(self) end,
        onStart = function(self) end,
        onStop = function(self) end,
    },

    In = {
        onSomeSignal = function(self, data)
            -- Handle input
            self.Out:Fire("response", { result = true })
        end,
    },

    Out = {
        response = {},  -- Schema documentation
    },
})
```

## Node Locking (Sync Behavior)

Nodes can block waiting for a signal using `waitForSignal()`. During the wait:
- Node is automatically locked
- IPC queues incoming messages instead of dispatching
- On signal received or timeout, node unlocks and queued messages replay

```lua
-- In a node handler:
local ack = self:waitForSignal("onAck", 5)  -- Wait up to 5 seconds
if not ack then
    self.Err:Fire({ reason = "ack_timeout" })
    return
end
-- Continue processing...
```

This enables synchronous request/response patterns while keeping the IPC architecture async.

## Node Registry

Node.lua includes a built-in Registry for tracking and querying active nodes:

```lua
local Node = require(game.ReplicatedStorage.Lib).Node

-- Register a node (automatic on creation)
Node.Registry.register(myNode)

-- Query nodes with filter
local enemies = Node.Registry.query({ class = "Enemy", status = "active" })

-- Get node by ID
local specific = Node.Registry.getById("Enemy_1")

-- Get node by its model (Instance)
local nodeForModel = Node.Registry.getByModel(someInstance)

-- Check if an item matches a filter
if Node.Registry.matches(target, { tag = "hostile" }) then
    -- handle hostile target
end
```

### Standard Filter Schema

The framework uses a unified filter schema across components (Zone, Registry, SpawnerCore):

| Field | Type | Description |
|-------|------|-------------|
| `class` | string \| string[] | Node class name(s) to match |
| `spawnSource` | string | ID of the spawner that created the entity |
| `status` | string | Node status ("active", "paused", etc.) |
| `tag` | string | CollectionService tag on the entity |
| `assetId` | string | Unique asset ID from SpawnerCore |
| `nodeId` | string | Node's unique ID |
| `attribute` | table | `{ name, value, operator }` where operator is "=", "!=", ">", "<", ">=", "<=" |
| `custom` | function | `function(target, meta) -> boolean` for complex logic |

Example filter usage:
```lua
-- Zone: Only detect entities from specific spawner
zone.In.onConfigure(zone, {
    filter = { spawnSource = "EnemyDropper" }
})

-- Registry: Query active enemies with health > 50
local wounded = Node.Registry.query({
    class = "Enemy",
    status = "active",
    attribute = { name = "Health", value = 50, operator = "<=" }
})
```

## Component Composition

Components are designed to be wired together like an ICU/breadboard:

```
Dropper                   NodePool<PathFollower>              Zone
┌─────────┐              ┌──────────────────────┐        ┌──────────┐
│ spawned ├─────────────►│ onCheckout           │        │          │
│         │              │                      │        │          │
│         │              │ (manages pool of     │        │          │
│         │              │  PathFollower nodes) │        │          │
│         │              │                      │        │          │
│onReturn │◄─────────────┤ (auto-release on     │◄───────┤ entered  │
│         │              │  pathComplete)       │        │          │
└─────────┘              └──────────────────────┘        └──────────┘
```

The ConveyorBelt test (`Tests.ConveyorBelt.demo()`) demonstrates this pattern with visual entities spawning, following waypoints, and despawning when they reach the end zone.

## Orchestrator Component

The Orchestrator is a meta-component that manages other components through declarative configuration. It provides:

- **Node instantiation** from configuration tables
- **Signal wiring** between managed nodes
- **Schema validation** on message payloads
- **Mode-based wiring** configurations

### Basic Usage

```lua
local Lib = require(game.ReplicatedStorage.Lib)
local Orchestrator = Lib.Components.Orchestrator

local orch = Orchestrator:new({ id = "GameOrchestrator" })
orch.Sys.onInit(orch)
orch.In.onConfigure(orch, {
    -- Named schemas for payload validation
    schemas = {
        SpawnedPayload = {
            entity = { type = "Instance", required = true },
            entityId = { type = "string", required = true },
        },
    },

    -- Nodes to instantiate
    nodes = {
        Spawner = { class = "Dropper", config = { interval = 2 } },
        EndZone = { class = "Zone" },
    },

    -- Signal wiring
    wiring = {
        {
            from = "Spawner",
            signal = "spawned",
            to = "EndZone",
            handler = "onConfigure",
            schema = "SpawnedPayload",  -- Optional validation
            validate = true,            -- Block invalid payloads
        },
    },

    -- Mode-specific wiring (additive to default)
    modes = {
        tutorial = { wiring = { ... } },
        gameplay = { wiring = { ... } },
    },
})

orch.In.onEnable(orch)  -- Start routing
orch.In.onSetMode(orch, { mode = "gameplay" })  -- Switch modes
```

### Schema Validation

SchemaValidator supports these types:
- **Lua**: string, number, boolean, table, function, any
- **Roblox**: Instance, Player, Model, Part, Vector3, CFrame, Color3

Field options: `type`, `required`, `enum`, `range`, `default`, `validator`

See `docs/ORCHESTRATOR_DESIGN.md` for full specification.

## Licensing

Warren is proprietary software. Games built using this framework under subcontract receive license rights as part of the service agreement.

---

*v2 is a ground-up rewrite of v1, focusing on simplicity, isolation, and developer ergonomics.*
