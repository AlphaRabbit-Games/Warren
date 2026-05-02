# Warren v2 Architecture

## CRITICAL: Event-Driven Signal Architecture

**THIS IS NON-NEGOTIABLE.**

### The Rule

Components communicate via **signals**, not direct API calls.

```lua
-- WRONG: Direct handler call
swivel.In.onRotate(swivel, { direction = "forward" })

-- CORRECT: Fire signal through Out channel
controller.Out:Fire("rotate", { direction = "forward" })
```

### Why This Matters

1. **Decoupling** - Components don't need direct references to each other
2. **IPC Routing** - Signals can be routed across network boundaries (server/client)
3. **Sync Mode** - Signals can block and wait for acknowledgment
4. **Debugging** - All communication flows through observable channels
5. **Wiring** - Connections between components are explicit and configurable

### Signal Flow

```
┌─────────────┐    Out:Fire()    ┌─────────┐    In.onSignal()    ┌─────────────┐
│  Component  │ ──────────────► │   IPC   │ ─────────────────► │  Component  │
│      A      │                  │ Router  │                     │      B      │
└─────────────┘                  └─────────┘                     └─────────────┘
```

### Node Pin Architecture

Every Node has four pin types:

- **Sys** - Lifecycle signals (onInit, onStart, onStop)
- **In** - Input handlers (receive signals)
- **Out** - Output emitters (fire signals)
- **Err** - Error channel (propagate errors)

### Correct Patterns

```lua
-- Emitting a signal
self.Out:Fire("targetAcquired", { position = pos, distance = dist })

-- Sync signal (blocks until ack)
local success, ackData = self.Out:Fire("fire", { target = t }, { sync = true })

-- Wiring (done by IPC or manually for demos)
nodeA.Out = {
    Fire = function(self, signal, data)
        if signal == "rotate" then
            -- Route to nodeB's In handler
            nodeB.In.onRotate(nodeB, data)
        end
    end,
}
```

### Anti-Patterns (NEVER DO THIS)

```lua
-- WRONG: Direct handler invocation from outside the node
otherNode.In.onFire(otherNode, data)

-- WRONG: Reaching into another node's state
local angle = otherNode._currentAngle

-- WRONG: Calling methods directly instead of signals
otherNode:rotate("forward")
```

### Exception: Lifecycle Initialization

The ONLY acceptable direct calls are for lifecycle setup before IPC is running:

```lua
-- OK during setup (before IPC routing is active)
local node = MyNode:new({ id = "foo", model = part })
node.Sys.onInit(node)
node.In.onConfigure(node, { ... })  -- Initial config before wiring
```

Once nodes are wired and running, ALL communication must be via signals.

---

## CRITICAL: Animation & Motion - Use Physics or Tweens, Never Frame-by-Frame CFrame

**THIS IS NON-NEGOTIABLE.**

### The Rule

All visual motion must use **physics constraints** (HingeConstraint, etc.) or **TweenService**. Never set CFrame directly every frame.

```lua
-- WRONG: Stop-frame CFrame animation (choppy, bypasses physics)
RunService.Heartbeat:Connect(function(dt)
    part.CFrame = part.CFrame * CFrame.Angles(0, dt * speed, 0)
end)

-- WRONG: Direct CFrame assignment every frame
part.CFrame = targetCFrame

-- CORRECT: Physics-based servo motor (smooth, physics-driven)
local hinge = Instance.new("HingeConstraint")
hinge.ActuatorType = Enum.ActuatorType.Servo
hinge.TargetAngle = targetAngle  -- Physics interpolates smoothly

-- CORRECT: TweenService for non-physics animation
local tween = TweenService:Create(part, TweenInfo.new(0.5), {
    CFrame = targetCFrame
})
tween:Play()
```

### Why This Matters

1. **Smoothness** - Physics/tweens interpolate between frames; CFrame assignment is choppy
2. **Frame Rate Independence** - Physics and tweens work correctly at any frame rate
3. **Physics Integration** - Constraint-based motion respects collisions and other physics
4. **Performance** - Engine-level interpolation is more efficient than Lua frame loops
5. **Network Replication** - Physics constraints replicate better than CFrame spam

### Preferred Methods (in order)

1. **HingeConstraint / Servo** - Best for rotating parts (turrets, doors, etc.)
2. **AlignPosition / AlignOrientation** - Best for following targets
3. **TweenService** - Best for UI and scripted animations
4. **SpringConstraint / RopeConstraint** - Best for physical connections

### Anti-Patterns (NEVER DO THIS)

```lua
-- WRONG: Manual CFrame rotation every frame
connection = RunService.Heartbeat:Connect(function()
    part.CFrame = CFrame.new(pos) * CFrame.Angles(0, angle, 0)
    angle = angle + 0.01
end)

-- WRONG: Lerping CFrame manually each frame
connection = RunService.Heartbeat:Connect(function()
    part.CFrame = part.CFrame:Lerp(targetCFrame, 0.1)
end)

-- WRONG: Setting Position/Orientation properties each frame
connection = RunService.Heartbeat:Connect(function()
    part.Position = targetPosition
end)
```

### Exception: Camera and Non-Physical Objects

Direct CFrame manipulation is acceptable for:
- Camera positioning (CurrentCamera.CFrame)
- UI elements that don't exist in 3D space
- Debug visualization that needs instant updates
