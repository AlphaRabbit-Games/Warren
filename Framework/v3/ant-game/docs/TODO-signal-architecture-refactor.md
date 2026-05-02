# TODO: Signal Architecture Refactor

**Priority:** HIGH - Architectural consistency
**Created:** 2026-01-14

## The Rule

**ALL runtime component communication MUST use signals via `Out:Fire()`, NOT direct handler calls.**

See `ARCHITECTURE.md` for full documentation.

## Tasks

### 1. Refactor Demos to Signal Architecture

Each demo needs a controller node that fires signals instead of calling handlers directly.

- [ ] **Swivel_Demo.lua**
  - Create SwivelDemoController node
  - Wire Out signals to Swivel In handlers
  - Update control functions to fire signals

- [ ] **Targeter_Demo.lua**
  - Create TargeterDemoController node
  - Wire Out signals to Targeter In handlers
  - Update control functions to fire signals

- [ ] **Launcher_Demo.lua**
  - Create LauncherDemoController node
  - Wire Out signals to Launcher In handlers
  - Update control functions to fire signals

- [ ] **Conveyor_Demo.lua**
  - Create ConveyorDemoController node
  - Wire Out signals to Dropper/PathFollower In handlers
  - Update automated sequence to fire signals

### 2. Update Component Docstrings

Update usage examples in component headers to show signal patterns:

- [ ] Swivel.lua
- [ ] Targeter.lua
- [ ] Launcher.lua
- [ ] PathedConveyor.lua
- [ ] Dropper.lua
- [ ] NodePool.lua
- [ ] Checkpoint.lua
- [ ] Orchestrator.lua
- [ ] PathFollower.lua
- [ ] Zone.lua

### 3. Review Test Files

Decide policy for test files:
- [ ] Are direct handler calls acceptable for unit testing?
- [ ] Should tests also use signal patterns?
- [ ] Document decision in ARCHITECTURE.md

### 4. Consider Shared Patterns

- [ ] Create a DemoController base class or pattern
- [ ] Create helper for manual wiring in demos
- [ ] Document demo wiring pattern

## Pattern Reference

### Before (WRONG)
```lua
function controls.rotateForward()
    swivel.In.onRotate(swivel, { direction = "forward" })
end
```

### After (CORRECT)
```lua
-- Controller fires signal
function controls.rotateForward()
    controller.Out:Fire("rotate", { direction = "forward" })
end

-- Wiring routes to handler
controller.Out = {
    Fire = function(self, signal, data)
        if signal == "rotate" then
            swivel.In.onRotate(swivel, data)
        end
    end,
}
```

## Validation

After refactoring, grep should show minimal direct calls:
```bash
grep -r "\.In\.on[A-Z]" --include="*.lua" src/Warren/Demos/
```

Acceptable matches:
- `Sys.onInit` - Lifecycle
- `In.onConfigure` - Initial setup before wiring
- Inside wiring `Fire` functions - This IS the routing layer
