# Warren Core Framework

## Repository Location
~/Warren-Core

## What This Is
The reusable system-level framework extracted from Warren. Game projects pull this in as a submodule and build their own components on top.

## Core Modules
- `Node.lua` — Base class for all game components
- `System.lua` — 7 subsystems (Debug, Log, IPC, State, Asset, Store, View)
- `Factory/` — Declarative instance builder (Geometry, Scanner, Compiler)
- `GeometrySpec/` — Backwards compat wrapper for Factory
- `ClassResolver.lua` — CSS-like style cascade system
- `Styles.lua` — Base style definitions
- `Internal/` — Shared utilities (AttributeSet, SchemaValidator, PathFollowerCore, SpawnerCore, EntityUtils)
- `Components/Layout/` — Data-driven layout builder/schema/serializer
- `Layouts/init.lua` — Lazy-loader infrastructure (game projects add their own data files)

## Relationship to Warren
This repo is used as a git submodule in ~/Warren at `Framework/v2/core/`.
Game-specific content (Components, Demos, Tests, Admin, layout data) lives in the game repo.

## Rules
- Core must have **zero dependencies** on game content (Components, Demos, Admin, Tests).
- All `require()` paths in Core must be relative to `script` or to `game.ReplicatedStorage.Warren`.
