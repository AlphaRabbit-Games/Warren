# Post-Refactor Demo Issues

**Date**: 2026-01-25
**Status**: Unresolved - Fresh rebuild needed

## Context

This session continued from a previous conversation where we completed the closure-based privacy refactor (Phases 0-5) for all 14 components. The refactor converted underscore-prefix private methods to closure-scoped local functions to enforce architectural privacy at the language level.

## Work Completed This Session

1. **Committed Swivel_Demo.lua changes** - Updated auto-demo to run by default with 6-phase showcase
2. **Read current component implementations** - Reviewed Swivel.lua and Launcher.lua

## Issues Discovered

When testing demos after the refactor, multiple issues were observed:

### Swivel Component
- **Symptom**: Swivel components aren't moving visually, or movement is choppy
- **Expected**: Smooth tween-like rotation
- **Observed**: Choppy movement that looks like manual CFrame manipulation
- **Note**: Current Swivel.lua uses HingeConstraint physics (Servo/Motor actuators), not TweenService

### Launcher Component
- **Symptom**: Projectiles affected by gravity
- **Expected**: Straight-line tracer behavior (no gravity)
- **Current Code**: Has BodyForce anti-gravity (lines 163-171 in Launcher.lua) but not working as expected

### General
- User reported "too many problems to list concisely" - would take 500+ words
- No error messages, just incorrect visual behavior
- Issues appeared after the closure-based privacy refactor

## Root Cause Hypothesis

The closure-based privacy refactor may have introduced subtle bugs in how:
- State is initialized or accessed via `getState(self)`
- RunService connections are managed
- Physics constraints are created and configured

The refactor changed the privacy pattern but should not have changed behavior. However, something about the state management or initialization order may have been affected.

## Decision

Rather than spend hours debugging the refactor's secondary effects, user decided to **start fresh** with the demos. This means:

1. Rebuild Swivel_Demo.lua from scratch
2. Test component behavior in isolation
3. If component is broken, fix the component
4. If component works but demo is wrong, fix the demo

## Files Involved

- `src/Warren/Components/Swivel.lua` - Physics-based rotation (HingeConstraint)
- `src/Warren/Components/Launcher.lua` - Projectile firing with anti-gravity
- `src/Warren/Demos/Swivel_Demo.lua` - Demo to be rebuilt
- `src/Warren/Demos/Launcher_Demo.lua` - May also need fixes

## Next Steps (Fresh Session)

1. Start fresh chat after this commit
2. Rebuild Swivel_Demo.lua from scratch - minimal, clean implementation
3. Test if Swivel component produces smooth rotation
4. If not smooth, investigate whether component needs TweenService instead of HingeConstraint
5. Apply same approach to Launcher_Demo if needed

## Key Question to Resolve

**Should Swivel use TweenService or HingeConstraint physics?**

- Current: HingeConstraint with Servo/Motor actuators (physics-driven)
- User expectation: Smooth tween-like interpolation
- These are fundamentally different approaches

The component header says "physics-based" but user expects tween smoothness. This architectural decision needs to be clarified before rebuilding.
