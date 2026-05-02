# Swivel Demo Architecture Audit

> **Date:** January 25, 2026
> **Status:** Violations Identified - Awaiting Remediation
> **Component:** `src/Warren/Demos/Swivel_Demo.lua`

---

## 1. Proper Design (Reference Architecture)

### 1.1 Core Principles

The Warren v2 framework follows a **signal-driven architecture** with these non-negotiable rules:

1. **Nodes communicate ONLY through signals** - Never direct method calls between nodes
2. **Wiring is declarative** - Connections defined in configuration, not code
3. **Orchestrator manages routing** - Intercepts `Out.Fire` and delivers to `In.handler`
4. **Nodes don't know about each other** - They respond to signals on their pins
5. **Nodes are pure black boxes** - No public methods for state queries or control
6. **State is broadcast, not queried** - If external nodes need state info, emit it via Out signals

### 1.2 The Black Box Principle

Nodes have exactly two interfaces with the outside world:

```
┌─────────────────────────────────────────────────────────────┐
│                         NODE                                 │
│                                                              │
│   IN (Receive)                    OUT (Broadcast)           │
│   ┌─────────────────┐             ┌─────────────────┐       │
│   │ onSignalA       │             │ signalX         │       │
│   │ onSignalB       │    ───►     │ signalY         │       │
│   │ onSignalC       │  internal   │ signalZ         │       │
│   └─────────────────┘   state     └─────────────────┘       │
│                                                              │
│   ✗ NO public methods                                        │
│   ✗ NO state queries (getCurrentAngle, isRunning, etc.)     │
│   ✗ NO exposed internals (getHinge, getConnection, etc.)    │
│                                                              │
│   Think: RSS feed. Nodes publish, subscribers receive.      │
└─────────────────────────────────────────────────────────────┘
```

**If you need state externally:**
- WRONG: `local angle = swivel:getCurrentAngle()`
- RIGHT: Subscribe to `Swivel.Out.rotated` signal, track angle yourself

**If you need to control a node:**
- WRONG: `controller:rotateForward()`
- RIGHT: Send signal `controller.In.onRotateCommand(controller, { direction = "forward" })`

### 1.2 Correct Demo Structure

A properly architected demo should:

```
┌─────────────────────────────────────────────────────────────────┐
│                        ORCHESTRATOR                              │
│                                                                  │
│  Manages:                                                        │
│  ┌──────────────┐              ┌──────────────┐                 │
│  │  Controller  │              │    Swivel    │                 │
│  │              │   wiring     │              │                 │
│  │  Out.rotate ─┼──────────────┼─► In.onRotate│                 │
│  │  Out.stop   ─┼──────────────┼─► In.onStop  │                 │
│  │              │              │              │                 │
│  │ In.onRotated◄┼──────────────┼─ Out.rotated │                 │
│  └──────────────┘              └──────────────┘                 │
│                                                                  │
│  Wiring Config:                                                  │
│  { from: "Controller", signal: "rotate", to: "Swivel", ... }    │
└─────────────────────────────────────────────────────────────────┘
```

### 1.3 System API Exception

Nodes MAY call System API methods directly:

```lua
-- OK: System is infrastructure, not part of node graph
System.Debug.info(self.id, "Starting rotation")
System.Asset.spawn("Projectile", position)
System.Store.get("playerData")
```

But System talks TO nodes via signals, not methods. System has its own built-in orchestrator for lifecycle management (init, cleanup, mode changes).

### 1.4 Correct Implementation Pattern: Extended Orchestrator

**WRONG: Ad-hoc Orchestrator configuration**
```lua
-- Don't do this - creates ad-hoc configuration in demo code
local orchestrator = Orchestrator:new({ id = "Demo" })
orchestrator.In.onConfigure(orchestrator, {
    nodes = { ... },
    wiring = { ... },
})
```

**RIGHT: Extended Orchestrator with encapsulated config**
```lua
-- Create a proper component that extends Orchestrator
local SwivelDemoOrchestrator = Orchestrator.extend(function(parent)
    return {
        name = "SwivelDemoOrchestrator",
        domain = "server",

        Sys = {
            onInit = function(self)
                -- Parent handles orchestrator infrastructure
                parent.Sys.onInit(self)

                -- Our specific configuration is encapsulated here
                self.In.onConfigure(self, {
                    nodes = {
                        Swivel = {
                            class = "Swivel",
                            model = self.model,  -- Passed in at instantiation
                            config = {
                                anchor = self.anchor,
                                axis = "Y",
                                mode = "continuous",
                                speed = 60,
                                minAngle = -90,
                                maxAngle = 90,
                            },
                        },
                    },

                    wiring = {
                        -- External -> Swivel (orchestrator receives, routes to Swivel)
                        { from = "External", signal = "rotate",   to = "Swivel", handler = "onRotate" },
                        { from = "External", signal = "stop",     to = "Swivel", handler = "onStop" },
                        { from = "External", signal = "setAngle", to = "Swivel", handler = "onSetAngle" },

                        -- Swivel -> External (Swivel emits, orchestrator broadcasts out)
                        { from = "Swivel", signal = "rotated",      to = "External", handler = "onRotated" },
                        { from = "Swivel", signal = "limitReached", to = "External", handler = "onLimitReached" },
                        { from = "Swivel", signal = "stopped",      to = "External", handler = "onStopped" },
                    },
                })
            end,

            onStart = function(self)
                parent.Sys.onStart(self)
            end,

            onStop = function(self)
                parent.Sys.onStop(self)
            end,
        },

        -- Orchestrator's In handlers become the external interface
        -- Signals sent here get routed to managed nodes via wiring
        In = {
            onRotate = function(self, data)
                -- Routed to Swivel.In.onRotate via wiring
            end,
            onStop = function(self, data)
                -- Routed to Swivel.In.onStop via wiring
            end,
            onSetAngle = function(self, data)
                -- Routed to Swivel.In.onSetAngle via wiring
            end,
        },

        -- Orchestrator's Out signals are fed by managed nodes
        Out = {
            rotated = {},       -- Fed by Swivel.Out.rotated
            limitReached = {},  -- Fed by Swivel.Out.limitReached
            stopped = {},       -- Fed by Swivel.Out.stopped
        },
    }
end)

-- Usage in demo:
local function setupDemo()
    local orchestrator = SwivelDemoOrchestrator:new({
        id = "Demo_SwivelOrchestrator",
        model = turretHead,
        anchor = base,
    })
    orchestrator.Sys.onInit(orchestrator)
    orchestrator.Sys.onStart(orchestrator)

    -- Demo sends signals to orchestrator's In handlers
    -- Orchestrator routes to Swivel internally
    return orchestrator
end
```

**Benefits of Extended Orchestrator:**
1. Configuration is encapsulated, not scattered in demo code
2. Reusable - same orchestrator can be used in multiple demos/games
3. Follows closure-based privacy pattern
4. Orchestrator becomes the "facade" - external code talks to it, not managed nodes
5. Testable as a unit

---

## 2. Current Implementation Violations

### 2.1 Violation #1: Manual Out Channel Replacement

**Location:** `Swivel_Demo.lua` lines 215-250

**What it does:**
```lua
-- WRONG: Completely replaces the Out channel object
controller.Out = {
    Fire = function(self, signal, data)
        if signal == "rotate" then
            swivel.In.onRotate(swivel, data)  -- Direct handler call!
        elseif signal == "stop" then
            swivel.In.onStop(swivel)
        -- ...
    end,
}
```

**Why it's wrong:**
1. **Destroys the Node's OutChannel** - Node.lua creates a proper `OutChannel` object with `_ipcSend` support (Node.lua:448). This overwrites it entirely.
2. **Hardcodes routing** - The routing logic is embedded in code, not declarative config.
3. **Creates tight coupling** - The controller now directly knows about `swivel.In.onRotate`, violating node isolation.
4. **Bypasses IPC infrastructure** - No message IDs, no cycle detection, no schema validation.
5. **Not reusable** - Can't change wiring without modifying code.

**Same violation for Swivel.Out:** lines 230-250
```lua
-- WRONG: Same pattern in reverse
swivel.Out = {
    Fire = function(self, signal, data)
        if signal == "rotated" then
            controller.In.onRotated(controller, data)  -- Direct call!
        -- ...
    end,
}
```

### 2.2 Violation #2: No Orchestrator Usage

**What's missing:**
- No Orchestrator instance created
- No declarative wiring configuration
- No schema validation
- No mode-based wiring support

**Impact:**
- Demo cannot be reconfigured without code changes
- Cannot add additional listeners to signals
- Cannot switch between wiring modes
- No validation of signal payloads

### 2.3 Violation #3: Inline Node Definition (Minor)

**Location:** `Swivel_Demo.lua` lines 42-102

**What it does:**
```lua
-- Defines SwivelController inline in the demo file
local SwivelController = Node.extend({
    name = "SwivelController",
    -- ...
})
```

**Why it's problematic:**
- Controller should be a reusable component in `Components/`
- Uses old `Node.extend({...})` pattern instead of closure-based privacy
- Has `self._currentAngle` using underscore convention (not closure-protected)

**Note:** For demos, inline nodes may be acceptable if they're demo-specific. But the pattern should still use closure-based privacy.

### 2.4 Violation #4: Direct Lifecycle Calls

**Location:** `Swivel_Demo.lua` lines 194-198

```lua
-- These are OK for setup phase per ARCHITECTURE.md
swivel.Sys.onInit(swivel)
swivel.Sys.onStart(swivel)
swivel.In.onConfigure(swivel, { ... })  -- Setup phase call - acceptable
```

**Note:** Direct `Sys` lifecycle calls and initial `onConfigure` during setup are **acceptable** per ARCHITECTURE.md. The violation is in the ongoing signal routing, not initial setup.

### 2.5 Violation #5: Public Query Methods on Swivel Component

**Location:** `Swivel.lua` lines 585-620

**What it does:**
```lua
-- WRONG: Exposes internal state for direct querying
getCurrentAngle = function(self)
    local state = getState(self)
    return state.hinge.CurrentAngle
end,

isRotating = function(self)
    local state = getState(self)
    return state.rotating
end,

isAtTarget = function(self)
    local state = getState(self)
    return math.abs(state.hinge.CurrentAngle - state.targetAngle) < 1
end,

getHinge = function(self)  -- Exposes implementation detail!
    local state = getState(self)
    return state.hinge
end,
```

**Why it's wrong:**
1. **Breaks black box principle** - Nodes should be pure signal I/O, no public methods
2. **Enables architecture bypass** - Other code can query state instead of subscribing to signals
3. **Exposes implementation** - `getHinge()` reveals we use HingeConstraint internally
4. **Creates coupling** - Callers depend on method signatures, not signal contracts
5. **Redundant** - `Out.rotated` already broadcasts `{ angle: number }`, subscribers should track it

**Correct approach:**
- Remove all four methods
- External nodes subscribe to `Out.rotated`, `Out.stopped`, `Out.limitReached`
- Each subscriber maintains its own state from the signal stream

### 2.6 Violation #6: Public Control Methods on Demo Controller

**Location:** `Swivel_Demo.lua` lines 75-101

**What it does:**
```lua
-- WRONG: Exposes control via public methods
rotateForward = function(self)
    self.Out:Fire("rotate", { direction = "forward" })
end,

rotateReverse = function(self)
    self.Out:Fire("rotate", { direction = "reverse" })
end,

stopRotation = function(self)
    self.Out:Fire("stop", {})
end,
```

**Why it's wrong:**
1. **Methods are not signals** - External code calls `controller:rotateForward()` instead of sending a signal
2. **Breaks signal-only interface** - The demo calls methods, not signals
3. **Inconsistent model** - Node receives signals but is controlled via methods

**Correct approach:**
- Controller should have In handlers: `onRotateCommand`, `onStopCommand`, etc.
- Demo (or parent orchestrator) sends signals to controller's In handlers
- Controller's In handlers fire Out signals to Swivel

---

## 3. Pattern Comparison: Wrong vs Right

### 3.1 Signal Routing

| Aspect | WRONG (Current) | RIGHT (Orchestrator) |
|--------|-----------------|----------------------|
| Wiring location | Embedded in code | Declarative config table |
| Out.Fire behavior | Replaced entirely | Intercepted, original preserved |
| Coupling | Controller knows Swivel internals | Nodes isolated, Orchestrator routes |
| Adding listeners | Modify code | Add wiring entry |
| Schema validation | None | Orchestrator validates |
| Message tracking | None | IPC message IDs |

### 3.2 Code Examples

**WRONG - Direct handler invocation:**
```lua
-- Controller fires signal
controller.Out:Fire("rotate", { direction = "forward" })

-- But Out was replaced to call handler directly:
swivel.In.onRotate(swivel, data)  -- Bypasses architecture!
```

**RIGHT - Orchestrator routing:**
```lua
-- Controller fires signal
controller.Out:Fire("rotate", { direction = "forward" })

-- Orchestrator intercepts and routes via wiring config:
-- 1. Looks up: "Controller.rotate" -> [{ to: "Swivel", handler: "onRotate" }]
-- 2. Validates payload against schema (if defined)
-- 3. Calls: swivel.In.onRotate(swivel, data)
-- 4. Also calls original Out.Fire for IPC propagation
```

### 3.3 Adding a New Listener

**WRONG - Must modify code:**
```lua
-- Want to add UI updates when swivel rotates?
// Must edit the Fire replacement:
swivel.Out = {
    Fire = function(self, signal, data)
        if signal == "rotated" then
            controller.In.onRotated(controller, data)
            uiNode.In.onAngleUpdate(uiNode, data)  -- Added manually
        end
    end,
}
```

**RIGHT - Add wiring entry:**
```lua
wiring = {
    { from = "Swivel", signal = "rotated", to = "Controller", handler = "onRotated" },
    { from = "Swivel", signal = "rotated", to = "UI", handler = "onAngleUpdate" },  -- Just add this
}
```

---

## 4. Root Cause Analysis

### 4.1 Why This Happened

1. **Path of least resistance** - Direct Out replacement is simpler than setting up Orchestrator
2. **Demo isolation mentality** - "It's just a demo" led to shortcuts
3. **Missing demo patterns** - No established template for proper demo structure
4. **Closure refactor focus** - Recent work focused on component privacy, not demo wiring

### 4.2 Impact

1. **Demos don't validate architecture** - They bypass it, so bugs in the real wiring system go untested
2. **Bad examples propagate** - Future demos/code may copy this pattern
3. **AI assistants learn wrong patterns** - Claude Code sees these patterns and reproduces them
4. **Refactoring difficulty** - When IPC changes, demos break in different ways than production

---

## 5. Remediation Requirements

### 5.1 For Swivel.lua (Component)

1. **Remove all public query methods:**
   - `getCurrentAngle()` - Delete, angle is broadcast via `Out.rotated`
   - `isRotating()` - Delete, state change broadcast via `Out.rotated`/`Out.stopped`
   - `isAtTarget()` - Delete, subscribers can compute from `Out.rotated` data
   - `getHinge()` - Delete, implementation detail should never be exposed

2. **Verify signal coverage** - Ensure Out signals provide all state info subscribers need:
   - `Out.rotated({ angle })` - Current angle after movement
   - `Out.stopped({})` - Rotation has stopped
   - `Out.limitReached({ limit })` - Hit min/max boundary

### 5.2 For Swivel_Demo.lua

1. **Remove manual Out replacement** - Delete lines 215-250

2. **Remove inline SwivelController** - No separate controller node needed

3. **Create extended Orchestrator** - `SwivelDemoOrchestrator` extends `Orchestrator`:
   - Encapsulates node configuration (Swivel setup)
   - Encapsulates wiring configuration
   - Exposes In handlers as external interface (`onRotate`, `onStop`, `onSetAngle`)
   - Exposes Out signals fed by managed Swivel (`rotated`, `stopped`, `limitReached`)

4. **Demo interacts with Orchestrator only**:
   - Creates `SwivelDemoOrchestrator` instance
   - Sends signals to orchestrator's In handlers
   - Subscribes to orchestrator's Out signals for UI updates
   - Never accesses managed Swivel directly

5. **Demo control pattern**:
   ```lua
   -- Demo sends signal to orchestrator
   orchestrator.In.onRotate(orchestrator, { direction = "forward" })

   -- NOT method calls like:
   -- orchestrator:rotateForward()  -- WRONG
   -- swivel:getCurrentAngle()      -- WRONG
   ```

6. **File organization**:
   - `Components/SwivelDemoOrchestrator.lua` - Extended orchestrator (reusable)
   - `Demos/Swivel_Demo.lua` - Visual setup + signal dispatch to orchestrator

### 5.2 For Future Demos

1. **Establish demo template** - Create `Demos/_TEMPLATE.lua` showing correct pattern
2. **Mandatory Orchestrator usage** - All multi-node demos must use Orchestrator
3. **No Out replacement** - Never overwrite `node.Out` directly
4. **Review checklist** - Add demo architecture check to review process

### 5.3 Documentation Updates

1. **Add to ARCHITECTURE.md** - "Demo Requirements" section
2. **Anti-patterns document** - Explicit "don't do this" examples
3. **Orchestrator usage guide** - Step-by-step for demo authors

---

## 6. Files Requiring Audit

### 6.1 Demos (Likely Same Violations)

| File | Status | Notes |
|------|--------|-------|
| `Swivel_Demo.lua` | ❌ Violated | Documented above |
| `Launcher_Demo.lua` | ⚠️ Needs audit | Likely same pattern |
| `Targeter_Demo.lua` | ⚠️ Needs audit | Likely same pattern |
| `Turret_Demo.lua` | ⚠️ Needs audit | Composite - may be worse |
| `Conveyor_Demo.lua` | ⚠️ Needs audit | Multi-node demo |
| `Combat_Demo.lua` | ⚠️ Needs audit | Complex wiring expected |
| `ShootingGallery_Demo.lua` | ⚠️ Needs audit | Already known broken |

### 6.2 Components (Public Method Violations)

Based on the black box principle, these components need audit for public query/control methods:

| Component | Public Methods | Status |
|-----------|----------------|--------|
| `Swivel.lua` | `getCurrentAngle`, `isRotating`, `isAtTarget`, `getHinge` | ❌ Remove |
| `Orchestrator.lua` | `getNode`, `getNodeIds`, `getSchema`, `getCurrentMode`, `isEnabled` | ⚠️ Review |
| `Dropper.lua` | ⚠️ Needs audit | Check for query methods |
| `Targeter.lua` | ⚠️ Needs audit | Check for query methods |
| `Launcher.lua` | ⚠️ Needs audit | Check for query methods |
| `PathFollower.lua` | ⚠️ Needs audit | Check for query methods |
| `Zone.lua` | ⚠️ Needs audit | Check for query methods |
| `EntityStats.lua` | ⚠️ Needs audit | Check for query methods |
| (all other components) | ⚠️ Needs audit | Check for query methods |

**Note on Orchestrator:** As a meta-component that manages other nodes, Orchestrator may have legitimate need for `getNode()` to retrieve managed instances for wiring. This requires architectural review - either:
1. Remove all query methods, find signal-based alternative
2. Classify Orchestrator as "infrastructure" with different rules
3. Keep for debugging only, mark as non-production API

---

## 7. Sign-off

- [x] Violations documented
- [x] Remediation plan approved
- [x] Swivel.lua fixed (public methods removed)
- [x] SwivelDemoOrchestrator created
- [x] Swivel_Demo.lua rewritten
- [ ] Other demos audited
- [ ] Demo template created
- [ ] Documentation updated

---

**Completed:** January 25, 2026

**Changes Made:**
1. `Swivel.lua` - Removed public query methods (`getCurrentAngle`, `isRotating`, `isAtTarget`, `getHinge`)
2. `Components/SwivelDemoOrchestrator.lua` - New extended Orchestrator for Swivel demo
3. `Components/init.lua` - Added SwivelDemoOrchestrator export
4. `Demos/Swivel_Demo.lua` - Complete rewrite with proper signal architecture
