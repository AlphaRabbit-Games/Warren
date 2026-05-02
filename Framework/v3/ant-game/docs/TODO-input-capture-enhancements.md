# TODO: InputCapture Enhancements

**Priority:** MEDIUM - UX polish and composability
**Created:** 2026-01-14

## Completed

- [x] Basic InputCapture claim/release pattern
- [x] Player movement disable via Humanoid.WalkSpeed = 0
- [x] Declarative control mappings (`Controls` table on Node)
- [x] `claimForNode(node, options)` API
- [x] Action state tracking (began, ended, held, triggered)
- [x] Hold-to-trigger with progress callbacks
- [x] Keyboard, gamepad D-pad, and thumbstick support

## Future Enhancements

### 1. IntegratedNodeControl (First-Class Composite)

Turn the manual control pattern into a reusable composite component that can be instantiated as one thing.

**Goal:** Single component that bundles:
- Control seat/interaction point (ProximityPrompt or VehicleSeat)
- Input capture and routing
- Camera control (POV switching)
- Target node connection

**Usage vision:**
```lua
local turretControl = IntegratedNodeControl:new({
    id = "Turret_Control",
    target = turretNode,           -- Node to control
    interactionPoint = seatPart,   -- Where player interacts
    cameraMode = "pov",            -- "pov", "third-person", "orbital"
})
```

**Tasks:**
- [ ] Design IntegratedNodeControl component API
- [ ] Separate interaction (seat/prompt) from input capture
- [ ] Add camera mode options (POV, third-person, orbital)
- [ ] Wire interaction → claim → target node routing
- [ ] Support multiple control points per target (co-op turrets?)

### 2. Target HUD / Crosshair

Add visual targeting overlay when in control mode.

**Features:**
- [ ] Crosshair centered on screen (configurable style)
- [ ] Optional target lock indicator
- [ ] Ammo/cooldown display
- [ ] Exit progress radial indicator

**Implementation:**
- Create as a separate HUD component
- Activated by IntegratedNodeControl when claiming
- Style configurable via Controls table or separate config

### 3. Seat-Based Interaction

Replace ProximityPrompt with VehicleSeat for more natural control capture.

**Benefits:**
- Player visually sits in turret
- Natural exit via jump/dismount
- Camera follows seat orientation
- Built-in Roblox behavior for entering/exiting

**Tasks:**
- [ ] Research VehicleSeat.Occupant detection
- [ ] Wire seat occupancy → InputCapture claim
- [ ] Handle camera transition on sit/stand
- [ ] Support both seat and prompt modes

### 4. Control Remapping (Settings Panel)

Allow players to customize control bindings.

**Tasks:**
- [ ] Design settings UI for control mapping
- [ ] Persist settings to player data
- [ ] Load custom mappings on claim
- [ ] Support per-node-type mappings

### 5. Touch Virtual Controls Auto-Generation

Automatically create touch controls from Control mapping.

**Tasks:**
- [ ] Parse Controls table to generate virtual buttons
- [ ] Layout algorithm for touch-friendly positioning
- [ ] Support axis controls (virtual joystick)
- [ ] Hold-action visual feedback

## Notes

The Turret_Demo serves as the reference implementation for this system. See:
- `Framework/v2/src/Warren/Demos/Turret_Demo.lua` - TurretManualController
- `Framework/v2/src/Warren/System.lua` - InputCapture.claimForNode()
