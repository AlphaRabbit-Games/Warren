# MAJOR REFACTOR: Closure-Based Node Privacy

## Problem

Currently, private methods are marked with `_` prefix convention:
```lua
self._internalState = {}
self:_privateMethod()
```

This is easily bypassed - nothing prevents external code from calling:
```lua
node:_privateMethod()  -- Works, even though it shouldn't
```

This has led to repeated violations where AI assistants (and humans) accidentally call private methods directly instead of using the signal architecture.

## Solution

Replace `_` convention with **closures** that truly encapsulate private state and methods. External code literally cannot access them.

```lua
local MyNode = Node.extend(function()
    -- Private state (inaccessible from outside)
    local internalState = {}
    local counter = 0

    -- Private methods (inaccessible from outside)
    local function processInternal(data)
        counter = counter + 1
        -- ...
    end

    -- Return the public interface
    return {
        name = "MyNode",
        domain = "server",

        Sys = {
            onInit = function(self)
                -- Can access closure variables
                internalState = {}
            end,
        },

        In = {
            onProcess = function(self, data)
                -- Uses private function - this is OK
                processInternal(data)
                -- Fires public signal
                self.Out:Fire("processed", { count = counter })
            end,
        },

        Out = {
            processed = {},
        },
    }
end)
```

## Benefits

1. **True encapsulation**: Private methods don't exist on the object at all
2. **Compiler-enforced**: Can't accidentally call `node:_method()` because it doesn't exist
3. **Clear public interface**: Only In/Out/Sys handlers are accessible
4. **Prevents architecture violations**: Forces signal-driven communication

## Implementation Plan

1. Update `Node.extend()` to accept a function that returns the definition
2. Migrate existing nodes one by one
3. Update tests
4. Update documentation

## Priority

HIGH - This is a fundamental architectural improvement that prevents the class of bugs we've been fighting today.
