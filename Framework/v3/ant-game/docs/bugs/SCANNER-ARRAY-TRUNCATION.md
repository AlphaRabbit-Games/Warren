# Bug: Scanner Array Truncation

**Status:** Open
**Severity:** Low (cosmetic - only affects debug output)
**Component:** `Geometry.scan()` / `Geometry.scanPrint()`

## Description

The scanner's code generation truncates geometry arrays, omitting values and producing invalid output.

## Expected Output

```lua
["exterior.WallCarportEast"] = {
    geometry = {
        origin = {19.5, 0.5, 40},
        scale = {0.5, 10, 20},
    },
    ...
}
```

## Actual Output

```lua
["exterior.WallCarportEast"] = {
    geometry = {
        origin = {40},
        scale = {10, 20},
    },
    ...
}
```

## Analysis

Arrays are losing elements during serialization. Suspected locations:

1. **`tableToCode()`** - Array detection logic using `pairs()` may not correctly identify array length
2. **`valueToCode()`** - Number formatting may have edge cases
3. **Trailing zero handling** - Values of `0` may be incorrectly omitted

### Relevant Code (Geometry.lua ~line 1437)

```lua
tableToCode = function(tbl, indent)
    -- Array detection
    local isArray = true
    local maxIndex = 0
    for k, _ in pairs(tbl) do
        if type(k) == "number" and k == math.floor(k) and k > 0 then
            maxIndex = math.max(maxIndex, k)
        else
            isArray = false
            break
        end
    end
    -- Gap check
    if isArray and maxIndex > 0 then
        for i = 1, maxIndex do
            if tbl[i] == nil then
                isArray = false
                break
            end
        end
    end
    ...
end
```

## Impact

- **Geometry building:** NOT affected (works correctly)
- **Debug output:** Produces invalid/incomplete Lua code
- **Round-trip:** Cannot use scanned output to recreate layouts

## Workaround

Use `Geometry.toTSV()` for debugging - TSV format may not have this issue, or inspect parts directly in Studio.

## Reproduction

```lua
local Geometry = require(game.ReplicatedStorage.Lib.Factory.Geometry)
local houseModule = game.ReplicatedStorage.Lib.Layouts.AtomicRanch.House
Geometry.scanPrint(require(houseModule))
```

## Notes

Low priority since core functionality works. Fix when scanner/round-trip becomes important.
