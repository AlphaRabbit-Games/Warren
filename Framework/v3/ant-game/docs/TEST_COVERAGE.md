# Warren v2 - Test Coverage

## Running Tests

In Roblox Studio Command Bar (after game starts):

```lua
-- Run all tests
_G.Lib.Tests.IPC.runAll()

-- Run specific group
_G.Lib.Tests.IPC.runGroup("Node")
_G.Lib.Tests.IPC.runGroup("IPC Messaging")

-- Run single test
_G.Lib.Tests.IPC.run("Node.extend creates class with name")

-- List available groups
_G.Lib.Tests.IPC.list()
```

Or using require:

```lua
local Tests = require(game.ReplicatedStorage.Lib.Tests)
Tests.IPC.runAll()
```

---

## Test Groups & Coverage

### Node (11 tests)
Core Node class functionality.

| Test | What It Validates |
|------|-------------------|
| Node.extend creates class with name | Basic extend works |
| Node.extend requires name | Validation |
| Node.extend requires definition | Validation |
| Node.extend sets default domain to shared | Default domain |
| Node.extend respects custom domain | Custom domain |
| Node.extend inherits required from Node | Contract inheritance |
| Node.extend merges custom required | Contract merging |
| Node.extend inherits defaults from Node | Default inheritance |
| Node.extend copies Sys handlers | Handler copying |
| Node.extend copies In handlers | Handler copying |
| Extended node can extend further | Chain inheritance |
| Child inherits parent handlers | Handler inheritance |
| Child can override parent handlers | Handler override |

### Node Instance (13 tests)
Node instantiation and instance methods.

| Test | What It Validates |
|------|-------------------|
| Node:new creates instance with id | Basic instantiation |
| Node:new requires id | Validation |
| Node:new sets class name | Metadata |
| Node:new creates Out channel | Pin creation |
| Node:new creates Err channel | Pin creation |
| Node:new injects default handlers | Default injection |
| Node:new respects custom Sys handlers | Custom handlers |
| Node:getAttribute returns nil for missing | Attribute get |
| Node:setAttribute and getAttribute work | Attribute set/get |
| Node:getAttributes returns all | Attribute enumeration |
| Node:hasHandler finds Sys handlers | Handler check |
| Node:hasHandler finds In handlers | Handler check |
| Node:hasHandler returns false for missing | Handler check |

### IPC Registration (5 tests)
Node registration with IPC system.

| Test | What It Validates |
|------|-------------------|
| IPC.registerNode accepts valid node | Basic registration |
| IPC.registerNode requires name | Validation |
| IPC.registerNode validates contract | Contract validation |
| IPC.registerNode accepts node with defaults fulfilling required | Default fulfillment |
| IPC.getNodeClasses returns registered | Class enumeration |

### IPC Instances (8 tests)
Instance creation and management.

| Test | What It Validates |
|------|-------------------|
| IPC.createInstance creates instance | Basic creation |
| IPC.createInstance requires registered class | Validation |
| IPC.createInstance requires id | Validation |
| IPC.createInstance rejects duplicate id | Duplicate prevention |
| IPC.getInstance returns created instance | Instance lookup |
| IPC.getInstance returns nil for missing | Missing handling |
| IPC.getInstancesByClass returns all of class | Class lookup |
| IPC.getInstanceCount returns correct count | Count tracking |
| IPC.despawn removes instance | Instance removal |

### IPC Modes (7 tests)
Mode definition and switching.

| Test | What It Validates |
|------|-------------------|
| IPC.defineMode stores config | Mode storage |
| IPC.defineMode requires name | Validation |
| IPC.getMode returns nil before switch | Initial state |
| IPC.switchMode sets current mode | Mode switching |
| IPC.switchMode requires defined mode | Validation |
| IPC.switchMode applies attributes | Attribute application |
| IPC.getModes returns all defined modes | Mode enumeration |

### IPC Lifecycle (9 tests)
Lifecycle hooks and state management.

| Test | What It Validates |
|------|-------------------|
| IPC.init calls onInit on instances | Init lifecycle |
| IPC.init sets initialized flag | State tracking |
| IPC.start calls onStart on instances | Start lifecycle |
| IPC.start requires init first | Order validation |
| IPC.start sets started flag | State tracking |
| IPC.stop calls onStop on instances | Stop lifecycle |
| IPC.switchMode calls onModeChange | Mode change lifecycle |
| IPC.spawn calls lifecycle hooks | Dynamic spawn |
| IPC.despawn calls lifecycle hooks | Dynamic despawn |

### IPC Messaging (6 tests)
Message routing and delivery.

| Test | What It Validates |
|------|-------------------|
| IPC.getMessageId returns incrementing ids | ID generation |
| IPC.sendTo delivers message to instance | Direct delivery |
| IPC.sendTo requires started | State check |
| IPC.send routes through wiring | Wiring routing |
| IPC.broadcast delivers to all instances Sys | Broadcast delivery |
| Cycle detection prevents infinite loops | Cycle prevention |

### Error Handling (2 tests)
Error catching and propagation.

| Test | What It Validates |
|------|-------------------|
| Handler errors are caught and reported | Error catching |
| Err channel fires on handler error | Error propagation |

### Mode Pins (2 tests)
Mode-specific pin resolution.

| Test | What It Validates |
|------|-------------------|
| Mode-specific In handlers are called | Mode override |
| Falls back to default In when mode has no handler | Fallback behavior |

### IPC Utilities (1 test)
Utility functions.

| Test | What It Validates |
|------|-------------------|
| IPC.reset clears all state | State reset |

---

## Summary

| Group | Tests |
|-------|-------|
| Node | 13 |
| Node Instance | 13 |
| IPC Registration | 5 |
| IPC Instances | 8 |
| IPC Modes | 7 |
| IPC Lifecycle | 9 |
| IPC Messaging | 6 |
| Error Handling | 2 |
| Mode Pins | 2 |
| IPC Utilities | 1 |
| **IPC Subtotal** | **66** |

---

## SchemaValidator Tests (50 tests)

Run with: `Tests.SchemaValidator.runAll()`

### Type Checking (14 tests)
Type checker functions for all supported types.

| Test | What It Validates |
|------|-------------------|
| getTypeChecker returns function for valid types | Function retrieval |
| getTypeChecker returns nil for unknown types | Unknown handling |
| isValidType returns true for valid types | Type validation |
| isValidType returns false for invalid types | Invalid handling |
| string/number/boolean/table type checkers | Lua types |
| any type checker accepts everything | Any type |
| Vector3/CFrame/Instance/Part/Model checkers | Roblox types |

### Field Validation (12 tests)
Individual field validation logic.

| Test | What It Validates |
|------|-------------------|
| validateField passes/fails type checks | Type enforcement |
| validateField handles required fields | Required enforcement |
| validateField validates enum values | Enum constraint |
| validateField validates number ranges | Range constraint |
| validateField runs custom validators | Custom logic |

### Schema Validation (6 tests)
Full schema validation.

| Test | What It Validates |
|------|-------------------|
| validate passes valid payloads | Happy path |
| validate fails missing required | Required detection |
| validate fails wrong types | Type detection |
| validate collects multiple errors | Error aggregation |

### Validate and Process (3 tests)
Validation with default injection.

| Test | What It Validates |
|------|-------------------|
| validateAndProcess injects defaults | Default injection |
| validateAndProcess preserves values | No overwrite |
| validateAndProcess validates after defaults | Post-default validation |

### Sanitize (3 tests)
Payload sanitization for security.

| Test | What It Validates |
|------|-------------------|
| sanitize removes undeclared fields | Field whitelist |
| sanitize injects defaults | Default injection |
| sanitize handles nil inputs | Edge cases |

### Schema Definition (6 tests)
Schema definition validation.

| Test | What It Validates |
|------|-------------------|
| validateSchema passes valid schema | Happy path |
| validateSchema fails missing type | Required type |
| validateSchema fails unknown type | Type validation |
| validateSchema fails enum on non-string | Constraint matching |
| validateSchema fails range on non-number | Constraint matching |
| validateSchema fails non-function validator | Validator type |

### Utilities (4 tests)
Utility functions.

| Test | What It Validates |
|------|-------------------|
| mergeSchemas combines schemas | Schema composition |
| formatErrors creates readable string | Error formatting |
| getSupportedTypes returns types | Type enumeration |

### Sender Validation (2 tests)
Client→Server security.

| Test | What It Validates |
|------|-------------------|
| validateSender passes matching player | Valid sender |
| validateSender fails non-table payload | Input validation |

---

## Orchestrator Tests (24 tests)

Run with: `Tests.Orchestrator.runAll()`

### Basics (3 tests)
Core Orchestrator functionality.

| Test | What It Validates |
|------|-------------------|
| Orchestrator extends Node | Inheritance |
| Orchestrator creates instance | Instantiation |
| Orchestrator initializes internal state | State setup |

### Configuration (6 tests)
Configuration handling.

| Test | What It Validates |
|------|-------------------|
| onConfigure accepts empty config | Empty handling |
| onConfigure registers schemas | Schema storage |
| onConfigure rejects invalid schema | Schema validation |
| onConfigure spawns nodes | Node creation |
| onConfigure rejects unknown class | Class validation |
| onConfigure fires configured signal | Signal emission |

### Node Management (4 tests)
Dynamic node management.

| Test | What It Validates |
|------|-------------------|
| onAddNode adds single node | Dynamic add |
| onRemoveNode removes node | Dynamic remove |
| getNodeIds returns all node IDs | Node enumeration |
| nodes receive onInit during configuration | Lifecycle |

### Wiring (3 tests)
Signal routing.

| Test | What It Validates |
|------|-------------------|
| wiring routes signals between nodes | Signal routing |
| wiring validates config structure | Config validation |
| enable/disable controls routing | Routing toggle |

### Schema Validation (3 tests)
Payload validation on wiring.

| Test | What It Validates |
|------|-------------------|
| wiring validates payload against schema | Schema enforcement |
| strict validation blocks invalid payload | Strict mode |
| inline schema works | Inline schemas |

### Mode System (3 tests)
Mode-based wiring.

| Test | What It Validates |
|------|-------------------|
| onSetMode switches modes | Mode switching |
| mode switch fires modeChanged signal | Signal emission |
| mode-specific wiring adds to default | Additive wiring |

### Error Handling (2 tests)
Error detection.

| Test | What It Validates |
|------|-------------------|
| errors on invalid config data | Config validation |
| errors on missing target node | Target validation |

---

## Full Test Summary

| Suite | Tests |
|-------|-------|
| IPC & Node | 66 |
| SchemaValidator | 50 |
| Orchestrator | 24 |
| **Total** | **140** |

---

## What's NOT Tested (Manual Testing Required)

1. **Domain filtering** - Server/client domain checks require actual server/client context
2. **Model integration** - Node attachment to Roblox Instances
3. **Cross-context routing** - Server→client messaging via RemoteEvents
4. **Studio CLI** - _G.Node, _G.IPC availability
5. **Performance** - Message throughput under load
6. **Memory** - Leak detection over extended use

---

## Expected Output

Successful run:
```
═══════════════════════════════════════════════════════
  Warren v2 - IPC & Node Test Suite
═══════════════════════════════════════════════════════

▶ Node
  ✓ Node.extend creates class with name
  ✓ Node.extend requires name
  ...

▶ IPC Messaging
  ✓ IPC.getMessageId returns incrementing ids
  ✓ IPC.sendTo delivers message to instance
  ...

───────────────────────────────────────────────────────
  Results: 66/66 passed  |  ALL PASSED
───────────────────────────────────────────────────────
```

Failed run shows:
```
  ✗ Test name here
       Error: expected X, got Y
```
