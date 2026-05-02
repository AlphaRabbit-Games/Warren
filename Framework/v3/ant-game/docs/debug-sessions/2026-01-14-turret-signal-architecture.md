# Debug Session: Turret System & Signal Architecture
**Date:** 2026-01-14
**Status:** Partial - Needs continuation in new chat

## Summary

This session focused on debugging the Turret System demo and uncovered a critical architectural violation pattern throughout the codebase: direct handler calls instead of signal-based communication.

## Key Discovery: Signal Architecture Violations

### The Rule (NON-NEGOTIABLE)
Components must communicate via signals (`Out:Fire()`), not direct handler calls.

```lua
-- WRONG
swivel.In.onRotate(swivel, { direction = "forward" })

-- CORRECT
controller.Out:Fire("rotate", { direction = "forward" })
```

### Why It Matters
1. Decoupling between components
2. IPC routing across server/client boundaries
3. Sync mode support (blocking signals with ack)
4. Observable/debuggable communication flow
5. Explicit wiring configuration

## Work Completed

### 1. Sync Mode Implementation (Node.lua)
Added sync mode to `OutChannel:Fire`:
- `Out:Fire("signal", data, { sync = true })` blocks until receiver acknowledges
- Adds `_sync` metadata (correlation ID, replyTo) to signal data
- Uses `waitForSignal("_onAck", timeout)` to wait for matching ack

### 2. Auto-Ack in IPC (System.lua)
After IPC delivers a signal to an In handler:
- If `data._sync` exists, fires `_ack` event back through IPC
- Uses `task.defer` to avoid blocking the handler chain
- Fully event-driven (no direct handler calls)

### 3. Turret Demo Refactored (Turret_Demo.lua)
Fixed to use proper signal architecture:
- Created `TurretController` node that fires signals via `Out:Fire()`
- Manual wiring routes signals to Swivel `In` handlers (simulates IPC)
- Swivels emit `Out:Fire("rotated", ...)` signals
- Geometry updates triggered by catching Swivel output signals

### 4. Architecture Documentation (ARCHITECTURE.md)
Created explicit documentation of the signal architecture rules.

## Issues Found - Need Fixing

### Files with Direct Handler Call Violations

**Demos (runtime communication violations):**
- `Swivel_Demo.lua` - Control functions call handlers directly
- `Targeter_Demo.lua` - Control functions call handlers directly
- `Launcher_Demo.lua` - Control functions call handlers directly
- `Conveyor_Demo.lua` - Automated sequence calls handlers directly

**Component Docstrings (example code violations):**
- `Swivel.lua` - Usage examples show direct calls
- `Targeter.lua` - Usage examples show direct calls
- `Launcher.lua` - Usage examples show direct calls
- `PathedConveyor.lua` - Usage examples show direct calls
- `Dropper.lua` - Usage examples show direct calls
- `NodePool.lua` - Usage examples show direct calls
- `Checkpoint.lua` - Usage examples show direct calls
- `Orchestrator.lua` - Usage examples show direct calls

**Tests (may be acceptable for unit testing, but should review):**
- `Dropper_Tests.lua` - Many direct calls
- `Checkpoint_Tests.lua` - Many direct calls
- `Hatcher_Tests.lua` - Many direct calls
- `IPC_Node_Tests.lua` - Many direct calls
- `ConveyorBelt_Tests.lua` - Direct calls

### Acceptable Direct Calls (per ARCHITECTURE.md)
- `node.Sys.onInit(node)` - Lifecycle initialization
- `node.In.onConfigure(node, {...})` - Initial configuration before IPC wiring
- Test files calling handlers directly for unit testing (debatable)

## Turret Demo Issues Debugged

### Original Problems
1. Projectiles firing in wrong direction
2. Turret not tracking targets
3. Choppy motion
4. Targeter not locking on

### Root Causes Found
1. **Yaw angle sign mismatch** - `atan2` returns positive for right, but `CFrame.Angles` rotates left for positive
2. **Multiple Heartbeat connections** - Swivel internal Heartbeat + control loop Heartbeat causing timing issues
3. **Direct handler calls every frame** - Calling `onRotate`/`onStop` every frame instead of using signals
4. **Raycast hitting debug beam** - AimBeam not excluded from Targeter's raycast filter

### Solution Applied
- Used `CFrame.lookAt()` for direct tracking (confirmed geometry math is correct)
- Refactored to signal-based architecture with TurretController node
- Used `onSetAngle` for direct positioning instead of continuous rotation
- Proper signal wiring between components

## Files Modified This Session

1. `Framework/v2/src/Warren/Node.lua` - Added sync mode to OutChannel:Fire
2. `Framework/v2/src/Warren/System.lua` - Added auto-ack in IPC dispatch
3. `Framework/v2/src/Warren/Demos/Turret_Demo.lua` - Complete refactor to signal architecture
4. `Framework/v2/src/Warren/Components/Launcher.lua` - Fixed anti-gravity (BodyForce instead of AssemblyGravityModifier)
5. `Framework/v2/ARCHITECTURE.md` - Created signal architecture documentation

## Next Steps (New Chat)

1. **Refactor all demos** to use signal-based architecture:
   - Swivel_Demo.lua
   - Targeter_Demo.lua
   - Launcher_Demo.lua
   - Conveyor_Demo.lua

2. **Update component docstrings** to show correct signal patterns

3. **Review test files** - Decide if direct calls are acceptable for unit testing

4. **Consider creating a "DemoController" base pattern** that other demos can follow

## Testing Commands

```lua
-- Run the turret demo
local Demos = require(game.ReplicatedStorage.Lib.Demos)
local demo = Demos.Turret.run()

-- Cleanup
demo.cleanup()
```

## Technical Notes

### Sync Mode Flow
```
1. Controller calls Out:Fire("setAngle", data, { sync = true })
2. OutChannel adds _sync metadata: { id = correlationId, replyTo = controllerId }
3. OutChannel calls _ipcSend (or wiring routes to target)
4. IPC delivers to Swivel.In.onSetAngle
5. Handler executes
6. IPC detects _sync, fires _ack back to replyTo
7. Controller's waitForSignal receives ack
8. Out:Fire returns { success = true, ackData = ... }
```

### Proper Demo Wiring Pattern
```lua
-- Create controller node
local controller = TurretController:new({ id = "Controller" })

-- Wire controller output to component input
controller.Out = {
    Fire = function(self, signal, data)
        if signal == "setYawAngle" then
            -- Route to swivel (this simulates IPC routing)
            yawSwivel.In.onSetAngle(yawSwivel, data)
        end
    end,
}

-- Wire component output back
yawSwivel.Out = {
    Fire = function(self, signal, data)
        if signal == "rotated" then
            -- Handle rotation complete
        end
    end,
}
```
