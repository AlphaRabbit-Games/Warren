# Warren Framework v2

Signal-driven game framework for Roblox. Nodes communicate via `Out:Fire()` -> wiring -> `In.onHandler()` pattern.

**Repository:** https://github.com/purefictiongames/Warren

## Quick Reference

### Core Architecture Rule
**NEVER call internal methods directly to drive node behavior.** Always use signals:

```lua
-- WRONG: Direct method call
node:_internalMethod()

-- CORRECT: Signal-driven
controller.Out:Fire("commandSignal", { data })
-- Routed via wiring to:
node.In.onCommandSignal(node, data)
```

### Node Structure
```lua
local MyNode = Node.extend({
    name = "MyNode",
    domain = "server",  -- or "client" or "shared"

    Sys = {
        onInit = function(self) end,
        onStart = function(self) end,
        onStop = function(self) end,
    },

    In = {
        onSomeSignal = function(self, data) end,
    },

    Out = {
        resultSignal = {},
    },
})
```

---

## File Index

### Core System
| File | Description |
|------|-------------|
| [src/Warren/Node.lua](https://raw.githubusercontent.com/purefictiongames/Warren/refs/heads/main/Framework/v2/src/Warren/Node.lua) | Base node class with signal system |
| [src/Warren/System.lua](https://raw.githubusercontent.com/purefictiongames/Warren/refs/heads/main/Framework/v2/src/Warren/System.lua) | IPC, cross-domain communication, node registry |
| [src/Warren/init.lua](https://raw.githubusercontent.com/purefictiongames/Warren/refs/heads/main/Framework/v2/src/Warren/init.lua) | Library entry point |
| [src/Bootstrap.server.lua](https://raw.githubusercontent.com/purefictiongames/Warren/refs/heads/main/Framework/v2/src/Bootstrap.server.lua) | Server-side initialization |
| [src/Bootstrap.client.lua](https://raw.githubusercontent.com/purefictiongames/Warren/refs/heads/main/Framework/v2/src/Bootstrap.client.lua) | Client-side initialization |

### Components
| File | Description |
|------|-------------|
| [src/Warren/Components/init.lua](https://raw.githubusercontent.com/purefictiongames/Warren/refs/heads/main/Framework/v2/src/Warren/Components/init.lua) | Component index |
| [src/Warren/Components/Dropper.lua](https://raw.githubusercontent.com/purefictiongames/Warren/refs/heads/main/Framework/v2/src/Warren/Components/Dropper.lua) | Spawns entities on interval or signal |
| [src/Warren/Components/PathFollower.lua](https://raw.githubusercontent.com/purefictiongames/Warren/refs/heads/main/Framework/v2/src/Warren/Components/PathFollower.lua) | Moves entities along waypoint paths |
| [src/Warren/Components/PathedConveyor.lua](https://raw.githubusercontent.com/purefictiongames/Warren/refs/heads/main/Framework/v2/src/Warren/Components/PathedConveyor.lua) | Conveyor belt with path following |
| [src/Warren/Components/Checkpoint.lua](https://raw.githubusercontent.com/purefictiongames/Warren/refs/heads/main/Framework/v2/src/Warren/Components/Checkpoint.lua) | Waypoint checkpoints for paths |
| [src/Warren/Components/Swivel.lua](https://raw.githubusercontent.com/purefictiongames/Warren/refs/heads/main/Framework/v2/src/Warren/Components/Swivel.lua) | Physics-based rotation (HingeConstraint servos) |
| [src/Warren/Components/Targeter.lua](https://raw.githubusercontent.com/purefictiongames/Warren/refs/heads/main/Framework/v2/src/Warren/Components/Targeter.lua) | Target acquisition and tracking |
| [src/Warren/Components/Launcher.lua](https://raw.githubusercontent.com/purefictiongames/Warren/refs/heads/main/Framework/v2/src/Warren/Components/Launcher.lua) | Projectile launching |
| [src/Warren/Components/Hatcher.lua](https://raw.githubusercontent.com/purefictiongames/Warren/refs/heads/main/Framework/v2/src/Warren/Components/Hatcher.lua) | Entity lifecycle management |
| [src/Warren/Components/Zone.lua](https://raw.githubusercontent.com/purefictiongames/Warren/refs/heads/main/Framework/v2/src/Warren/Components/Zone.lua) | Spatial zone detection |
| [src/Warren/Components/NodePool.lua](https://raw.githubusercontent.com/purefictiongames/Warren/refs/heads/main/Framework/v2/src/Warren/Components/NodePool.lua) | Object pooling for nodes |
| [src/Warren/Components/Orchestrator.lua](https://raw.githubusercontent.com/purefictiongames/Warren/refs/heads/main/Framework/v2/src/Warren/Components/Orchestrator.lua) | Coordinates multi-node sequences |
| [src/Warren/Components/DamageCalculator.lua](https://raw.githubusercontent.com/purefictiongames/Warren/refs/heads/main/Framework/v2/src/Warren/Components/DamageCalculator.lua) | Damage calculation with modifiers |
| [src/Warren/Components/EntityStats.lua](https://raw.githubusercontent.com/purefictiongames/Warren/refs/heads/main/Framework/v2/src/Warren/Components/EntityStats.lua) | Health, armor, resistance tracking |
| [src/Warren/Components/StatusEffect.lua](https://raw.githubusercontent.com/purefictiongames/Warren/refs/heads/main/Framework/v2/src/Warren/Components/StatusEffect.lua) | Buff/debuff system |

### Internal Utilities
| File | Description |
|------|-------------|
| [src/Warren/Internal/init.lua](https://raw.githubusercontent.com/purefictiongames/Warren/refs/heads/main/Framework/v2/src/Warren/Internal/init.lua) | Internal utilities index |
| [src/Warren/Internal/SpawnerCore.lua](https://raw.githubusercontent.com/purefictiongames/Warren/refs/heads/main/Framework/v2/src/Warren/Internal/SpawnerCore.lua) | Template-based entity spawning |
| [src/Warren/Internal/PathFollowerCore.lua](https://raw.githubusercontent.com/purefictiongames/Warren/refs/heads/main/Framework/v2/src/Warren/Internal/PathFollowerCore.lua) | Core path following logic |
| [src/Warren/Internal/EntityUtils.lua](https://raw.githubusercontent.com/purefictiongames/Warren/refs/heads/main/Framework/v2/src/Warren/Internal/EntityUtils.lua) | Entity helper functions |
| [src/Warren/Internal/SchemaValidator.lua](https://raw.githubusercontent.com/purefictiongames/Warren/refs/heads/main/Framework/v2/src/Warren/Internal/SchemaValidator.lua) | Configuration validation |
| [src/Warren/Internal/AttributeSet.lua](https://raw.githubusercontent.com/purefictiongames/Warren/refs/heads/main/Framework/v2/src/Warren/Internal/AttributeSet.lua) | Attribute management utility |

### Demos
| File | Description |
|------|-------------|
| [src/Warren/Demos/init.lua](https://raw.githubusercontent.com/purefictiongames/Warren/refs/heads/main/Framework/v2/src/Warren/Demos/init.lua) | Demo index |
| [src/Warren/Demos/Conveyor_Demo.lua](https://raw.githubusercontent.com/purefictiongames/Warren/refs/heads/main/Framework/v2/src/Warren/Demos/Conveyor_Demo.lua) | Dropper -> PathFollower -> despawn circuit |
| [src/Warren/Demos/Turret_Demo.lua](https://raw.githubusercontent.com/purefictiongames/Warren/refs/heads/main/Framework/v2/src/Warren/Demos/Turret_Demo.lua) | Client-controlled turret with cross-domain IPC |
| [src/Warren/Demos/Targeter_Demo.lua](https://raw.githubusercontent.com/purefictiongames/Warren/refs/heads/main/Framework/v2/src/Warren/Demos/Targeter_Demo.lua) | Signal-based target acquisition |
| [src/Warren/Demos/Swivel_Demo.lua](https://raw.githubusercontent.com/purefictiongames/Warren/refs/heads/main/Framework/v2/src/Warren/Demos/Swivel_Demo.lua) | Physics-based rotation demo |
| [src/Warren/Demos/Launcher_Demo.lua](https://raw.githubusercontent.com/purefictiongames/Warren/refs/heads/main/Framework/v2/src/Warren/Demos/Launcher_Demo.lua) | Projectile launching demo |
| [src/Warren/Demos/ShootingGallery_Demo.lua](https://raw.githubusercontent.com/purefictiongames/Warren/refs/heads/main/Framework/v2/src/Warren/Demos/ShootingGallery_Demo.lua) | **SHELVED** - Turret + targets (targets not spawning) |
| [src/Warren/Demos/Combat_Demo.lua](https://raw.githubusercontent.com/purefictiongames/Warren/refs/heads/main/Framework/v2/src/Warren/Demos/Combat_Demo.lua) | Combat system demo |

### Tests
| File | Description |
|------|-------------|
| [src/Warren/Tests/init.lua](https://raw.githubusercontent.com/purefictiongames/Warren/refs/heads/main/Framework/v2/src/Warren/Tests/init.lua) | Test runner |
| [src/Warren/Tests/IPC_Node_Tests.lua](https://raw.githubusercontent.com/purefictiongames/Warren/refs/heads/main/Framework/v2/src/Warren/Tests/IPC_Node_Tests.lua) | Cross-domain IPC tests |
| [src/Warren/Tests/Dropper_Tests.lua](https://raw.githubusercontent.com/purefictiongames/Warren/refs/heads/main/Framework/v2/src/Warren/Tests/Dropper_Tests.lua) | Dropper component tests |
| [src/Warren/Tests/Swivel_Tests.lua](https://raw.githubusercontent.com/purefictiongames/Warren/refs/heads/main/Framework/v2/src/Warren/Tests/Swivel_Tests.lua) | Swivel component tests |
| [src/Warren/Tests/Targeter_Tests.lua](https://raw.githubusercontent.com/purefictiongames/Warren/refs/heads/main/Framework/v2/src/Warren/Tests/Targeter_Tests.lua) | Targeter component tests |
| [src/Warren/Tests/Launcher_Tests.lua](https://raw.githubusercontent.com/purefictiongames/Warren/refs/heads/main/Framework/v2/src/Warren/Tests/Launcher_Tests.lua) | Launcher component tests |
| [src/Warren/Tests/PathedConveyor_Tests.lua](https://raw.githubusercontent.com/purefictiongames/Warren/refs/heads/main/Framework/v2/src/Warren/Tests/PathedConveyor_Tests.lua) | PathFollower tests |
| [src/Warren/Tests/Checkpoint_Tests.lua](https://raw.githubusercontent.com/purefictiongames/Warren/refs/heads/main/Framework/v2/src/Warren/Tests/Checkpoint_Tests.lua) | Checkpoint tests |
| [src/Warren/Tests/Zone_Tests.lua](https://raw.githubusercontent.com/purefictiongames/Warren/refs/heads/main/Framework/v2/src/Warren/Tests/Zone_Tests.lua) | Zone tests |
| [src/Warren/Tests/Hatcher_Tests.lua](https://raw.githubusercontent.com/purefictiongames/Warren/refs/heads/main/Framework/v2/src/Warren/Tests/Hatcher_Tests.lua) | Hatcher tests |
| [src/Warren/Tests/Orchestrator_Tests.lua](https://raw.githubusercontent.com/purefictiongames/Warren/refs/heads/main/Framework/v2/src/Warren/Tests/Orchestrator_Tests.lua) | Orchestrator tests |
| [src/Warren/Tests/SchemaValidator_Tests.lua](https://raw.githubusercontent.com/purefictiongames/Warren/refs/heads/main/Framework/v2/src/Warren/Tests/SchemaValidator_Tests.lua) | Schema validation tests |
| [src/Warren/Tests/AttributeSet_Tests.lua](https://raw.githubusercontent.com/purefictiongames/Warren/refs/heads/main/Framework/v2/src/Warren/Tests/AttributeSet_Tests.lua) | AttributeSet tests |
| [src/Warren/Tests/ConveyorBelt_Tests.lua](https://raw.githubusercontent.com/purefictiongames/Warren/refs/heads/main/Framework/v2/src/Warren/Tests/ConveyorBelt_Tests.lua) | Conveyor belt tests |

---

## Architecture Documentation

| File | Description |
|------|-------------|
| [ARCHITECTURE.md](https://raw.githubusercontent.com/purefictiongames/Warren/refs/heads/main/Framework/v2/ARCHITECTURE.md) | Main architecture overview |
| [docs/ARCHITECTURE.md](https://raw.githubusercontent.com/purefictiongames/Warren/refs/heads/main/Framework/v2/docs/ARCHITECTURE.md) | Detailed architecture docs |
| [docs/IPC_NODE_SPEC.md](https://raw.githubusercontent.com/purefictiongames/Warren/refs/heads/main/Framework/v2/docs/IPC_NODE_SPEC.md) | Inter-process communication specification |
| [docs/ORCHESTRATOR_DESIGN.md](https://raw.githubusercontent.com/purefictiongames/Warren/refs/heads/main/Framework/v2/docs/ORCHESTRATOR_DESIGN.md) | Multi-node coordination design |
| [docs/TURRET_SYSTEM_PLAN.md](https://raw.githubusercontent.com/purefictiongames/Warren/refs/heads/main/Framework/v2/docs/TURRET_SYSTEM_PLAN.md) | Turret system implementation plan |
| [docs/TEST_COVERAGE.md](https://raw.githubusercontent.com/purefictiongames/Warren/refs/heads/main/Framework/v2/docs/TEST_COVERAGE.md) | Test coverage documentation |

## TODO / Active Work

| File | Description |
|------|-------------|
| [docs/TODO-shooting-gallery.md](https://raw.githubusercontent.com/purefictiongames/Warren/refs/heads/main/Framework/v2/docs/TODO-shooting-gallery.md) | ShootingGallery resume point (shelved) |
| [docs/TODO-closure-privacy-refactor.md](https://raw.githubusercontent.com/purefictiongames/Warren/refs/heads/main/Framework/v2/docs/TODO-closure-privacy-refactor.md) | **MAJOR** - Replace _ prefix with closures |
| [docs/TODO-signal-architecture-refactor.md](https://raw.githubusercontent.com/purefictiongames/Warren/refs/heads/main/Framework/v2/docs/TODO-signal-architecture-refactor.md) | Signal architecture improvements |
| [docs/TODO-input-capture-enhancements.md](https://raw.githubusercontent.com/purefictiongames/Warren/refs/heads/main/Framework/v2/docs/TODO-input-capture-enhancements.md) | Input system enhancements |

## Debug Sessions / Logs

| File | Description |
|------|-------------|
| [docs/debug-sessions/2026-01-14-turret-signal-architecture.md](https://raw.githubusercontent.com/purefictiongames/Warren/refs/heads/main/Framework/v2/docs/debug-sessions/2026-01-14-turret-signal-architecture.md) | Turret debugging session |
| [Logs/PROJECT_JOURNAL.md](https://raw.githubusercontent.com/purefictiongames/Warren/refs/heads/main/Framework/v2/Logs/PROJECT_JOURNAL.md) | Project development journal |
| [Logs/COMPONENT_REGISTRY.md](https://raw.githubusercontent.com/purefictiongames/Warren/refs/heads/main/Framework/v2/Logs/COMPONENT_REGISTRY.md) | Component registry and status |
| [Logs/SYSTEM_REFERENCE.md](https://raw.githubusercontent.com/purefictiongames/Warren/refs/heads/main/Framework/v2/Logs/SYSTEM_REFERENCE.md) | System API reference |
| [Logs/PROCEDURES.md](https://raw.githubusercontent.com/purefictiongames/Warren/refs/heads/main/Framework/v2/Logs/PROCEDURES.md) | Development procedures |
| [Logs/TOWER_DEFENSE_COMPONENTS.md](https://raw.githubusercontent.com/purefictiongames/Warren/refs/heads/main/Framework/v2/Logs/TOWER_DEFENSE_COMPONENTS.md) | Tower defense component designs |
| [Logs/STYLING_SYSTEM.md](https://raw.githubusercontent.com/purefictiongames/Warren/refs/heads/main/Framework/v2/Logs/STYLING_SYSTEM.md) | UI styling system docs |

## Game Configuration

| File | Description |
|------|-------------|
| [src/Game/init.lua](https://raw.githubusercontent.com/purefictiongames/Warren/refs/heads/main/Framework/v2/src/Game/init.lua) | Game-specific configuration |
| [src/ReplicatedFirst/Config.lua](https://raw.githubusercontent.com/purefictiongames/Warren/refs/heads/main/Framework/v2/src/ReplicatedFirst/Config.lua) | Client-first configuration |

---

## Key Patterns

### Signal Wiring (Manual - for demos)
```lua
-- Sender.Out -> Receiver.In
sender.Out = {
    Fire = function(self, signal, data)
        if signal == "mySignal" then
            receiver.In.onMySignal(receiver, data)
        end
    end,
}
```

### Cross-Domain IPC (Client <-> Server)
```lua
-- Client fires to server
System.fireCrossDomain("MyServerNode", "onClientInput", { key = "W" })

-- Server receives in node's In handler
In = {
    onClientInput = function(self, data, player)
        -- data.key == "W", player is the firing player
    end,
}
```

### Dropper -> PathFollower Circuit
```lua
-- Dropper spawns entity, fires "spawned"
-- Wiring routes to PathFollower.In.onEntityEntered
-- PathFollower moves entity along path, fires "completed"
-- Wiring routes back to Dropper.In.onReturn for pooling
```

---

## Current State (2026-01-14)

**Working:**
- Core node system with signals
- Cross-domain IPC (client <-> server)
- Turret demo (client input -> server physics)
- Swivel, Targeter, Launcher components
- Conveyor demo (Dropper -> PathFollower circuit)

**Shelved:**
- ShootingGallery target spawning (signal chain not triggering)

**Planned:**
- Closure-based privacy refactor (replace _ prefix convention)
- Standalone TargetRow demo for debugging
