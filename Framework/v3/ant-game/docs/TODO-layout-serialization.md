# TODO: Custom Layout Serialization

## Problem

Current seed-based persistence has data integrity risks:
- Algorithm changes would break old saves
- RNG behavior could vary across Roblox versions
- Floating point drift across platforms
- DataStore JSON serialization mangles numeric table keys

## Requirement

Pre-save and post-load data must be **literally identical** - not regenerated equivalents.

## Chosen Approach: Custom String Serialization (Option 3)

Define our own deterministic format with full control over roundtrip integrity.

### Example Format (TBD)
```
room:1:pos:0,20,0:dims:30,20,30|room:2:pos:50,20,0:dims:25,15,25|door:1:from:1:to:2:center:25,15,0...
```

### Benefits
- Full control over serialization
- Guaranteed identical roundtrip
- No DataStore mangling issues
- Can version the format if needed

### Implementation Notes
- Create `LayoutSerializer` module in `Lib/Components/Layout/`
- Functions: `serialize(layout) -> string`, `deserialize(string) -> layout`
- Include format version header for future-proofing
- Validate roundtrip in tests: `assert(deepEquals(layout, deserialize(serialize(layout))))`

### Migration
- Detect old seed-based saves, regenerate once, save in new format
- Or: keep seed as fallback, prefer serialized if present

## Architecture Note

**This should be a full framework subsystem** - not just something bolted onto RegionManager.

Consider creating `Lib.System.Store` or `Lib.System.Persistence`:
- Generic serialization/deserialization
- DataStore abstraction layer
- Schema versioning and migration
- Cross-system persistence (not just layouts - player prefs, inventory, etc.)
- Consistent API for all game systems that need persistence

RegionManager would then use this subsystem rather than implementing its own DataStore logic.

## Status

**Not started** - documented for future implementation.

## Related
- `RegionManager.lua` - savePlayerData/loadPlayerData
- `LayoutBuilder.lua` - current seed-based generation
- `LayoutSchema.lua` - layout structure definition
