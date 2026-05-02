# Orchestrator Component Design

> Status: IMPLEMENTED
> Created: 2026-01-13
> Implemented: 2026-01-14

## Overview

The Orchestrator is a Node component that provides declarative wiring between components with schema-validated message contracts. It replaces manual signal wiring with a table-based configuration.

## Goals

1. **Declarative Composition**: Define component graphs via Lua tables
2. **Message Contracts**: Schema definitions for signal payloads
3. **Security**: Validate client→server messages to prevent spoofing
4. **Developer Ergonomics**: Clear contracts, better debugging, IDE hints

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        ORCHESTRATOR                              │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────┐  │
│  │   Wiring    │  │   Schema    │  │   IPC Validator         │  │
│  │   Table     │──│   Registry  │──│   (client→server)       │  │
│  └─────────────┘  └─────────────┘  └─────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
         │                                      │
         ▼                                      ▼
   ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐
   │ Dropper  │  │ PathPool │  │   Zone   │  │  Other   │
   │  [I/O]   │  │  [I/O]   │  │  [I/O]   │  │  [I/O]   │
   └──────────┘  └──────────┘  └──────────┘  └──────────┘
```

## Configuration Format

### Basic Wiring

```lua
local Orchestrator = Lib.Components.Orchestrator

local graph = Orchestrator:new({
    id = "ConveyorOrchestrator",

    -- Component instances to manage
    nodes = {
        Dropper = { class = "Dropper", config = { interval = 2, maxActive = 10 } },
        PathPool = { class = "NodePool", config = { nodeClass = "PathFollower", poolMode = "elastic" } },
        EndZone = { class = "Zone", config = { filter = { spawnSource = "Dropper" } } },
    },

    -- Signal routing
    wiring = {
        {
            from = "Dropper",
            signal = "spawned",
            to = "PathPool",
            handler = "onCheckout",
        },
        {
            from = "EndZone",
            signal = "entityEntered",
            to = "Dropper",
            handler = "onReturn",
        },
    },
})
```

### With Schema Validation

```lua
local graph = Orchestrator:new({
    id = "SecureOrchestrator",

    -- Schema definitions (reusable)
    schemas = {
        SpawnedPayload = {
            entity = { type = "Instance", required = true },
            entityId = { type = "string", required = true },
            assetId = { type = "string", required = true },
        },
        ReturnPayload = {
            assetId = { type = "string", required = true },
        },
        HatchRequest = {
            player = { type = "Player", required = true },
            eggType = { type = "string", required = true, enum = { "Common", "Rare", "Legendary" } },
            quantity = { type = "number", required = false, range = { min = 1, max = 10 } },
        },
    },

    wiring = {
        {
            from = "Dropper",
            signal = "spawned",
            to = "PathPool",
            handler = "onCheckout",
            schema = "SpawnedPayload",  -- Reference by name
        },
        {
            from = "EndZone",
            signal = "entityEntered",
            to = "Dropper",
            handler = "onReturn",
            schema = "ReturnPayload",
        },
        {
            from = "Client",              -- Special: client→server
            signal = "requestHatch",
            to = "Hatcher",
            handler = "onHatch",
            schema = "HatchRequest",
            validate = true,              -- Enforce validation (reject invalid)
        },
    },
})
```

### Inline Schema

```lua
{
    from = "Zone",
    signal = "entityEntered",
    to = "Dropper",
    handler = "onReturn",
    schema = {
        assetId = { type = "string", required = true },
    },
}
```

## Schema Field Types

| Type | Description | Example |
|------|-------------|---------|
| `string` | Lua string | `{ type = "string" }` |
| `number` | Lua number | `{ type = "number", range = { min = 0, max = 100 } }` |
| `boolean` | Lua boolean | `{ type = "boolean" }` |
| `table` | Lua table | `{ type = "table" }` |
| `Instance` | Roblox Instance | `{ type = "Instance" }` |
| `Player` | Roblox Player | `{ type = "Player" }` |
| `Model` | Roblox Model | `{ type = "Model" }` |
| `Part` | Roblox BasePart | `{ type = "Part" }` |
| `Vector3` | Roblox Vector3 | `{ type = "Vector3" }` |
| `CFrame` | Roblox CFrame | `{ type = "CFrame" }` |

## Schema Field Options

| Option | Type | Description |
|--------|------|-------------|
| `type` | string | Required. The expected type |
| `required` | boolean | Whether field must be present (default: false) |
| `enum` | string[] | Allowed values for strings |
| `range` | { min?, max? } | Valid range for numbers |
| `default` | any | Default value if not provided |
| `validator` | function | Custom validation: `function(value, field, payload) -> boolean, error?` |

## Validation Behavior

### By Message Direction

| Direction | Default Behavior | Notes |
|-----------|------------------|-------|
| Server→Server | Trust (no validation) | Same execution context |
| Client→Server | **Validate** | Security critical |
| Server→Client | Trust (no validation) | Informational only |
| Client→Client | Trust (no validation) | Same execution context |

### Validation Modes

```lua
{
    from = "Client",
    signal = "purchaseItem",
    to = "Shop",
    handler = "onPurchase",
    schema = "PurchasePayload",
    validate = true,        -- Enforce: reject invalid payloads
    -- OR
    validate = "warn",      -- Log warning but allow through
    -- OR
    validate = false,       -- Skip validation
}
```

### On Validation Failure

1. Log warning with details (field, expected, received)
2. Fire `Err` signal with validation error
3. Do NOT call the handler (for `validate = true`)

## Mode-Based Wiring

Support different wiring configurations per game mode:

```lua
local graph = Orchestrator:new({
    modes = {
        lobby = {
            wiring = {
                -- Minimal wiring for lobby
            },
        },
        gameplay = {
            wiring = {
                -- Full game wiring
            },
        },
        postgame = {
            wiring = {
                -- Results/rewards wiring
            },
        },
    },
})

-- Switch modes
graph.In.onSetMode(graph, { mode = "gameplay" })
```

## IPC Integration

The Orchestrator integrates with System.IPC to intercept and validate messages:

```lua
-- In IPC.send():
function IPC.send(target, signal, data)
    -- Check if Orchestrator has a schema for this route
    local schema = Orchestrator.getSchema(target, signal)
    if schema and shouldValidate(source, target) then
        local valid, errors = validatePayload(data, schema)
        if not valid then
            -- Reject or warn based on configuration
            return handleValidationFailure(errors)
        end
    end

    -- Proceed with normal send
    ...
end
```

## Signals

### In

| Signal | Payload | Description |
|--------|---------|-------------|
| onConfigure | { nodes, wiring, schemas } | Configure the orchestrator |
| onSetMode | { mode } | Switch to a different wiring mode |
| onEnable | - | Enable all wiring |
| onDisable | - | Disable all wiring |

### Out

| Signal | Payload | Description |
|--------|---------|-------------|
| configured | { nodeCount, wireCount } | Fired after configuration |
| modeChanged | { from, to } | Fired on mode switch |
| validationFailed | { from, signal, errors } | Fired when validation fails |

### Err

| Signal | Payload | Description |
|--------|---------|-------------|
| invalidSchema | { schemaName, reason } | Schema definition error |
| invalidWiring | { index, reason } | Wiring definition error |
| validationError | { from, signal, to, field, expected, received } | Payload validation failed |

## Example: Secure Gacha System

```lua
local gachaGraph = Orchestrator:new({
    id = "GachaOrchestrator",

    schemas = {
        -- Client requests a hatch
        HatchRequest = {
            eggId = { type = "string", required = true },
            quantity = { type = "number", range = { min = 1, max = 10 }, default = 1 },
        },
        -- Server confirms cost
        CostConfirmation = {
            approved = { type = "boolean", required = true },
            player = { type = "Player", required = true },
        },
        -- Hatch result
        HatchResult = {
            player = { type = "Player", required = true },
            result = { type = "string", required = true },
            rarity = { type = "string", required = true, enum = { "Common", "Rare", "Epic", "Legendary" } },
            assetId = { type = "string", required = true },
            pityTriggered = { type = "boolean", default = false },
        },
    },

    nodes = {
        Hatcher = { class = "Hatcher", config = { ... } },
        Currency = { class = "Currency", config = { ... } },
        Inventory = { class = "Inventory", config = { ... } },
    },

    wiring = {
        -- Client requests hatch (VALIDATED)
        {
            from = "Client",
            signal = "requestHatch",
            to = "Hatcher",
            handler = "onHatch",
            schema = "HatchRequest",
            validate = true,
        },
        -- Hatcher asks Currency to validate cost
        {
            from = "Hatcher",
            signal = "costCheck",
            to = "Currency",
            handler = "onCheck",
        },
        -- Currency responds to Hatcher
        {
            from = "Currency",
            signal = "costResult",
            to = "Hatcher",
            handler = "onCostConfirmed",
            schema = "CostConfirmation",
        },
        -- Hatcher sends result to Inventory
        {
            from = "Hatcher",
            signal = "hatched",
            to = "Inventory",
            handler = "onAddItem",
            schema = "HatchResult",
        },
        -- Notify client of result
        {
            from = "Hatcher",
            signal = "hatched",
            to = "Client",
            handler = "onHatchResult",
            schema = "HatchResult",
        },
    },
})
```

## Implementation Phases

### Phase 1: Core Orchestrator
- Node instantiation from config
- Basic wiring (no schemas)
- Signal routing

### Phase 2: Schema System
- Schema definition and registry
- Payload validation logic
- Field type validators

### Phase 3: IPC Integration
- Client→Server validation hook
- Validation failure handling
- Logging and debugging

### Phase 4: Mode System
- Multiple wiring modes
- Mode switching
- Conditional routing

## Files to Create

| File | Purpose |
|------|---------|
| `Lib/Components/Orchestrator.lua` | Main component |
| `Lib/Internal/SchemaValidator.lua` | Validation logic |
| `Lib/Tests/Orchestrator_Tests.lua` | Unit tests |
| `Lib/Tests/SchemaValidator_Tests.lua` | Validation tests |

## Security Considerations

1. **Whitelist fields**: Only declared schema fields pass through
2. **Type coercion**: Never coerce types - reject mismatches
3. **Instance validation**: Verify Instance types (IsA checks)
4. **Player validation**: Confirm Player is the actual sender
5. **Rate limiting**: Consider adding rate limits per signal (future)

## Open Questions

1. Should schemas be shareable across Orchestrators?
2. Auto-generate schema from component Out definitions?
3. Support for nested object schemas?
4. TypeScript-style definition export for IDE support?

---

*Implementation completed 2026-01-14. See `Lib/Components/Orchestrator.lua` and `Lib/Internal/SchemaValidator.lua`.*
