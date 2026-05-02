# Resolver System

## Overview

The Resolver is a generic computation engine for hierarchical definitions with inherited properties. It's not specific to geometry or GUIs - it's a formula solver that computes values in dependency order.

## Mental Model

Think of it like solving a system of equations:

1. **Workspace** - Create empty stubs for all unknowns
2. **Dependency Order** - Determine which equations to solve first
3. **Apply Formulas** - Compute each value using the cascade formula
4. **Solutions Table** - The resolved table holds all computed values

```
┌─────────────────────────────────────────────────────────────────┐
│  PHASE 1: Create Stubs (define the unknowns)                    │
│                                                                 │
│    stubs = {                                                    │
│      Floor1:  { properties: nil, geometry: nil }                │
│      Floor2:  { properties: nil, geometry: nil }                │
│      Roof:    { properties: nil, geometry: nil }                │
│    }                                                            │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│  PHASE 2: Populate Values (solve in dependency order)           │
│                                                                 │
│    for each node in tree_order:                                 │
│      node.properties = cascade(parent, base, class, id, inline) │
│      node.geometry = resolve_refs(geometry_def, stubs)          │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│  OUTPUT: Resolved Table (solutions workspace)                   │
│                                                                 │
│    resolved = {                                                 │
│      Floor1:  { properties: {...}, geometry: {...} }            │
│      Floor2:  { properties: {...}, geometry: {...} }            │
│      Roof:    { properties: {...}, geometry: {...} }            │
│    }                                                            │
└─────────────────────────────────────────────────────────────────┘
```

## The Cascade Formula

The cascade is just a formula for computing final values. Order matters - later values override earlier ones:

```
result = merge(
  parent.properties,   -- Inherit from parent node
  defaults,            -- Applied to all nodes
  base[type],          -- Applied by node type (Part, TextLabel, etc.)
  class[1],            -- Classes applied in order
  class[2],
  ...
  id[node.id],         -- Applied by ID
  inline               -- Direct properties on the definition
)
```

This is like PEMDAS - a defined order of operations. Each step of the formula is computed in sequence.

## References

References allow nodes to use values from other nodes:

```lua
Floor2 = {
  geometry = {
    origin = {0, parts.Floor1.Size[2], 0},  -- "Put me on top of Floor1"
  }
}
```

When we evaluate `parts.Floor1.Size[2]`:
1. Look up Floor1 in the stubs table
2. Get its resolved geometry.scale[2] value
3. Substitute that number into the expression

This works because:
- All stubs exist before we start solving
- Tree order ensures Floor1 is solved before Floor2

Arithmetic is supported:
```lua
origin = {0, parts.Floor1.Size[2] + parts.Floor2.Size[2], 0}
```

This builds an expression tree that's evaluated during resolution.

## Domain Adapters

The Resolver produces a table of computed values. Adapters consume this table to create domain-specific outputs:

| Domain   | Input              | Output          |
|----------|-------------------|-----------------|
| Geometry | resolved table    | Roblox Parts    |
| GUI      | resolved table    | Roblox Frames   |
| Config   | resolved table    | Settings table  |

Adapters are thin - they just map resolved properties to instance properties.

## File Structure

```
Lib/
  Styles.lua           -- Style definitions (base, classes, ids)
  ClassResolver.lua    -- Per-element cascade formula
  Factory/
    Geometry.lua       -- Tree resolver + Part adapter
    Scanner.lua        -- Reverse: Parts → definitions
    Compiler.lua       -- Optimization: Parts → Unions
```

## Key Principles

1. **Separation of Concerns**
   - Resolver computes values (domain-agnostic)
   - Adapters create instances (domain-specific)

2. **Two-Phase Resolution**
   - Phase 1: Create all stubs (define workspace)
   - Phase 2: Populate values (solve equations)

3. **Dependency Order**
   - Parents before children
   - Referenced nodes before referencing nodes

4. **Cascade is a Formula**
   - Defined order of operations
   - Each step merges into the result
   - Later values override earlier ones

5. **Stubs are the Workspace**
   - All unknowns exist before solving begins
   - Solutions are written as we compute them
   - References can look up any solved value
