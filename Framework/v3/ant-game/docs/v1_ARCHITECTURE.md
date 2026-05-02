> **Copyright (c) 2025 Adam Stearns / Pure Fiction Records LLC**
>
> This software, its architecture, and associated documentation are proprietary
> and confidential. All rights reserved.
>
> Unauthorized copying, modification, distribution, or use of this software,
> in whole or in part, is strictly prohibited without prior written permission.

---

# Warren Framework Architecture

## Current: Stage-Wait Boot System with Dependency Resolution (v1.1)

A staged boot system where `System.Script` is the only script that runs immediately. All other scripts wait for the appropriate boot stage before executing.

### Server Boot Stages

```lua
Stages = {
    SYNC        = 1,  -- Assets cloned to RuntimeAssets, folders extracted
    EVENTS      = 2,  -- All BindableEvents/RemoteEvents created
    MODULES     = 3,  -- ModuleScripts deployed and requireable
    REGISTER    = 4,  -- Server modules register
    INIT        = 5,  -- All module:init() called
    START       = 6,  -- All module:start() called
    ORCHESTRATE = 7,  -- Orchestrator applies initial mode config
    READY       = 8,  -- Full boot complete, clients can interact
}
```

### Client Boot Stages (Deterministic Discovery)

```lua
ClientStages = {
    WAIT     = 1,  -- Wait for server READY signal
    DISCOVER = 2,  -- System discovers all client ModuleScripts
    INIT     = 3,  -- All client module:init() (topologically sorted)
    START    = 4,  -- All client module:start() (topologically sorted)
    READY    = 5,  -- Client fully ready
}
```

### Key Components

1. **System.lua** - Stage constants, `WaitForStage()` helper, module discovery, topological sort
2. **Debug.lua** - Separate debug module, bootstrapped first as infrastructure
3. **System.BootStage** (BindableEvent) - Server scripts listen for stage transitions
4. **System.ClientBoot** (RemoteEvent) - Client ping-pong protocol (server waits for READY before responding)
5. **CharacterAutoLoads = false** - Prevent player spawning until READY

### Client Module Discovery & Dependency Resolution

The client boot system uses **explicit discovery** instead of self-registration:

1. **Discovery**: System finds all ModuleScripts in PlayerScripts and PlayerGui descendants
2. **Dependency Declaration**: Modules declare dependencies via `dependencies` array
3. **Topological Sort**: Kahn's algorithm orders modules so dependencies init/start first
4. **Two-Phase Init**: `init()` creates state, `start()` connects events

```lua
-- Client module pattern (ModuleScript, not LocalScript)
return {
    dependencies = { "GUI.Script", "GUI.Transition" },  -- Must init before this module

    init = function(self)
        -- Phase 1: Create events/state, no connections to other modules
    end,

    start = function(self)
        -- Phase 2: Connect events, safe to use dependencies
    end,
}
```

**No timing hacks required.** The system guarantees dependencies are ready before `start()` is called.

### Critical Design Decision: No Spawning Until Ready

**Problem discovered:** Even with staged boot, players could spawn before scripts finished initializing, causing race conditions.

**Solution:** Disable character auto-loading at the very start of System.Script:

```lua
-- FIRST LINE of System.Script
Players.CharacterAutoLoads = false

-- ... bootstrap all stages ...

-- After READY stage fires:
for _, player in Players:GetPlayers() do
    player:LoadCharacter()
end
Players.CharacterAutoLoads = true  -- Re-enable for respawns
```

This ensures NO player exists until the entire system is ready. Eliminates all timing hacks.

### Server Script Pattern

```lua
-- After name guard (if present)
local System = require(ReplicatedStorage:WaitForChild("System.System"))
System:WaitForStage(System.Stages.SCRIPTS)

-- Rest of initialization (guaranteed all events exist)
```

### Client Module Pattern (v1.1)

Client modules are **ModuleScripts** (not LocalScripts) discovered by System:

```lua
-- Camera/StarterPlayerScripts/Script.lua (ModuleScript)
return {
    dependencies = { "GUI.Transition" },  -- Camera needs TransitionCovered event

    init = function(self)
        -- Get references, create state
        self.camera = workspace.CurrentCamera
        self.pendingStyle = nil
    end,

    start = function(self)
        -- Connect to events from dependencies (guaranteed to exist)
        local transitionCovered = ReplicatedStorage:FindFirstChild("Camera.TransitionCovered")
        transitionCovered.Event:Connect(function()
            self:applyPendingCamera()
        end)
    end,
}
```

**Key differences from old pattern:**
- No name guard needed (System controls loading)
- No `WaitForStage` (System calls at correct time)
- No `RegisterClientModule` (discovery is automatic)
- Dependencies declared, not implicit

---

## Historical: Simple Bootstrap (v0)

The original system used a single-pass deployment where `System.Script` extracts service folders in order. Scripts used `WaitForChild` and timing hacks to wait for dependencies.

**Limitations (now fixed):**
- Race conditions between scripts and events
- Timing hacks (`task.wait(0.5)`, `task.wait(2.0)`)
- Self-registration caused non-deterministic ordering

---

## Future: Full Server-Side Dependency Resolution (v2)

> **Note:** Target architecture for when framework scales beyond ~20 assets.

### Concept

Assets become ModuleScripts with optional lifecycle methods called by System at each boot stage. Enables:
- True concurrency (assets initialize in parallel within each stage)
- Dependency declarations between assets
- Full visibility into boot progress

### Asset Structure

```lua
local Asset = {}

function Asset:onSync(system)
    -- Pre-cache, validate attributes
end

function Asset:onEvents(system)
    -- Create/register events, set up listeners
end

function Asset:onModules(system)
    -- Require dependencies, initialize shared state
end

function Asset:onScripts(system)
    -- Main logic, connect to other assets
end

function Asset:onReady(system)
    -- Enable player interaction
end

-- Optional: declare dependencies
Asset.dependsOn = {"Backpack", "MessageTicker"}

return Asset
```

### System Orchestration

```lua
-- For each stage:
for _, asset in assets do
    if asset["on" .. stageName] then
        task.spawn(function()
            asset["on" .. stageName](asset, system)
            system:markComplete(asset.name, stageName)
        end)
    end
end
system:waitForAllComplete(stageName)
-- Advance to next stage
```

### Benefits Over Stage-Wait
- Concurrent initialization within stages
- Explicit dependency ordering
- Better debugging (know exactly which asset is blocking)
- Code naturally organized by lifecycle phase

### Migration Path
1. Convert asset to ModuleScript
2. Move initialization code into appropriate `onStage` methods
3. Remove boilerplate `WaitForStage` calls
4. Declare dependencies if needed

---

## Message Routing System (v1.2)

### System.Router - Central Message Bus

Assets communicate via a central Router that handles both targeted and static message routing, similar to a network router/firewall.

### Routing Modes

**Targeted Routing:** Messages with a `target` field go directly to `target.Input`:
```lua
System.Router:Send(assetName, {
    target = "MarshmallowBag",
    command = "reset",
})
-- Routes to: MarshmallowBag.Input
```

**Static Wiring Fallback:** Messages without `target` use wiring from GameManifest:
```lua
System.Router:Send(assetName, {
    action = "gameStarted",
})
-- Routes to all destinations wired from assetName.Output in GameManifest
```

### GameManifest Wiring

Static routes defined in `System/ReplicatedStorage/GameManifest.lua`:
```lua
wiring = {
    { from = "Orchestrator.Output", to = "WaveController.Input" },
    { from = "CampPlacer.Output", to = "WaveController.Input" },
    { from = "CampPlacer.Output", to = "Scoreboard.Input" },
}
```

### Context-Based Filtering

Router tracks context for rule-based filtering:
```lua
System.Router:SetContext("gameActive", true)
System.Router:AddRule({
    action = "camperFed",
    condition = function(ctx) return ctx.gameActive end,
})
```

---

## Configurable Anchor System (v1.2)

### The Problem

Assets need an "anchor" point for HUDs, prompts, and positioning. Static assets use a dedicated invisible Anchor part. But Humanoid NPCs need the HUD to follow body parts naturally.

### Resolution Order

`Visibility.resolveAnchor(model)` returns `anchor, isBodyPart`:

1. **AnchorPart attribute** - Explicit body part name (e.g., `"Head"`)
2. **Literal "Anchor" part** - Dedicated invisible anchor
3. **Auto-detect for Humanoids** - Prefers Head, falls back to HumanoidRootPart

### Body Part vs Dedicated Anchor

```lua
local anchor, isBodyPart = Visibility.resolveAnchor(model)

if isBodyPart then
    -- Body part anchor (e.g., Head): keep visible, allow interactions
    anchor.CanTouch = true
else
    -- Dedicated Anchor: make invisible, non-collideable, anchored
    anchor.Anchored = true
    anchor.Transparency = 1
    anchor.CanCollide = false
    anchor.CanTouch = false
end
```

### Benefits

- **Static assets**: Use dedicated "Anchor" part (invisible, anchored)
- **Humanoids**: Auto-detect Head as anchor (visible, follows NPC naturally)
- **Configurable**: Set `AnchorPart` attribute to specify any body part
- **HUD follows NPC**: BillboardGui adorns to Head, which moves with NPC

---

## Lessons Learned

### From v0 → v1 Migration
1. **CharacterAutoLoads is essential** - Stage-wait alone isn't enough; players can spawn during boot
2. **Don't use WaitForChild as a band-aid** - If you need it after a refactor meant to eliminate it, the refactor is broken
3. **Test incrementally** - Don't change 20 files at once; test each stage
4. **Player lifecycle is separate from asset lifecycle** - Boot system controls assets; CharacterAutoLoads controls players

### From v1 → v1.1 Migration (Dependency Resolution)
5. **Self-registration causes race conditions** - Modules registering themselves leads to non-deterministic order
6. **Explicit discovery is better** - System finding and requiring modules gives full control
7. **Topological sort eliminates timing hacks** - Dependencies declared = correct ordering guaranteed
8. **BindableEvents don't cross network** - Client/server have separate event instances; use RemoteEvents for sync
9. **Server should wait for READY before PONG** - Responding to client PING with intermediate stages causes hangs
10. **Wait for character before PlayerGui discovery** - StarterGui clones to PlayerGui on character load
