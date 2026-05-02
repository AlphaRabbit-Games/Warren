# Navigation System & Mega Map Specification

## Context

This is a Roblox game built on Warren—a signal-driven, node-based architecture with strict encapsulation. The game is an infinite procedurally generated dungeon with exploration-based gameplay.

### Existing Architecture

**Layout Manager** (single source of truth):
- Manages all map/room data and state
- Tracks topology: hubs (3-5 portals), throughs (2 portals), spurs (1 portal)
- Handles portal connections between maps
- Knows which rooms are explored, discovered (adjacent to explored), or unknown
- Server-authoritative, query-based interface

**Room/Map Structure**:
- Each map contains multiple rooms
- Rooms have internal volume parts (collision, detection, minimap reference)
- Portals connect maps; first use generates a new destination map
- Portals track: destination map, whether used/unused, bidirectional linking

**Existing Minimap System**:
- Full-screen tactical overlay (touchpad toggle, pauses gameplay)
- 3D model built from room geometry at 1:100 scale
- Controller navigation: Right stick (rotate), L1/R1 (zoom), L2/R2 (jog through rooms)
- Room states: current (highlighted), explored (orange), adjacent unexplored (grey)
- Shows portal info: destination name or "???" if unused
- HUD displays current map/room name, room counts (total/explored/discovered)

---

## Feature 1: Map Table View

### Purpose
A searchable/sortable list interface for all explored maps. Complements the 3D minimap—better for "I know what I'm looking for by name" vs spatial memory.

### UI Layout
```
+--------------------------------------------------+
|  EXPLORED MAPS                        [Sort ▼]   |
+--------------------------------------------------+
|  Map Name       | Rooms | Explored | Portals     |
+--------------------------------------------------+
|  The Foundry    | 12    | 12/12    | 3 (Hub)     |
|  Crystal Caves  | 8     | 5/8      | 2 (Through) |
|  Dead End Alley | 4     | 4/4      | 1 (Spur)    |
|  The Nexus      | 15    | 10/15    | 5 (Hub)     |
|  ...            |       |          |             |
+--------------------------------------------------+
|  [Select]  [Set Destination]  [View on Map]      |
+--------------------------------------------------+
```

### Data Per Map Entry
- Map name (procedurally generated or themed)
- Total room count
- Explored room count
- Discovery status (fully explored, partially explored, just discovered)
- Portal count and map type classification (hub/through/spur)
- List of connected maps (portal destinations)
- First visited timestamp (for sorting)
- Last visited timestamp (for sorting)

### Interactions
- **Scroll/Navigate**: D-pad or left stick
- **Sort Options**: By name, by discovery order, by completion %, by portal count
- **Filter Options**: Show all, show incomplete, show hubs only, etc.
- **Select Map**: Opens detail view or highlights on 3D map
- **Set Destination**: Initiates navigation mode to this map

### Detail View (Per Map)
When a map is selected, show:
```
+--------------------------------------------------+
|  THE FOUNDRY                                     |
+--------------------------------------------------+
|  Type: Hub (3 portals)                           |
|  Rooms: 12/12 explored                           |
|  First visited: 5 minutes ago                    |
|  Last visited: 2 minutes ago                     |
|                                                  |
|  PORTALS:                                        |
|  → Crystal Caves (explored)                      |
|  → The Nexus (explored)                          |
|  → ??? (unused)                                  |
|                                                  |
|  [Navigate Here]  [View on Map]  [Back]          |
+--------------------------------------------------+
```

---

## Feature 2: Navigation Mode

### Purpose
GPS-style pathfinding through the dungeon. Player selects a destination, system plots the route, provides turn-by-turn guidance.

### Activation
- From Map Table: "Set Destination" on any explored map
- From 3D Minimap: Jog to a room, press button to set as destination
- Quick access: "Navigate to last location" option

### Pathfinding

**Algorithm**: BFS or Dijkstra over the map/portal graph
- Nodes = Maps (or rooms, depending on granularity)
- Edges = Portal connections
- Weight = 1 per portal (or could factor in room count per map for "shortest walk")

**Data Structure**:
```lua
Route = {
    destination = MapId,
    steps = {
        { mapId = "map_001", portalId = "portal_003", nextMap = "map_002" },
        { mapId = "map_002", portalId = "portal_007", nextMap = "map_005" },
        -- ...
    },
    totalSteps = 5,
    currentStepIndex = 1,
}
```

### HUD During Navigation

**Minimal Display** (always visible when nav active):
```
+---------------------------+
|  🧭 The Foundry           |
|  Portal: East Door        |
|  Progress: 80% (4/5)      |
+---------------------------+
```

**Elements**:
- Destination name
- Current instruction (which portal to use)
- Progress indicator (percentage or step count)
- Optional: Distance in rooms

### In-World Guidance

**Option A: Portal Highlighting**
- The correct portal in current room gets a visual indicator
- Glow, outline, arrow, particle effect—something noticeable but not obnoxious
- Clears when you're not in a room with a route portal

**Option B: Directional Indicator**
- HUD arrow pointing toward the correct portal
- Updates as player moves/rotates
- Works even when portal isn't visible

**Option C: Breadcrumb Trail** (more complex)
- Visual trail on the ground showing the path
- Could be room-by-room or more granular
- Higher implementation cost, but very clear

**Recommendation**: Start with Option A (portal highlighting) + the HUD ticker. Add Option B if players get lost. Option C is nice-to-have.

### Route Recalculation

**Trigger**: Player enters a room/map that is NOT on the current route

**Behavior**:
```
+----------------------------------+
|  You've left the route.          |
|                                  |
|  [Recalculate]  [Exit Nav Mode]  |
+----------------------------------+
```

**Smart Detection**:
- If player is 1 room off-route: Don't prompt immediately, they might be checking a corner
- If player is 2+ rooms off-route: Prompt for recalculate/exit
- If player enters a room that IS on the route (just not the next step): No prompt, they might be skipping ahead—update currentStepIndex accordingly

### Arrival

When player enters destination map:
```
+----------------------------------+
|  ✓ Arrived at The Foundry        |
|                                  |
|  [OK]                            |
+----------------------------------+
```

Navigation mode automatically ends. Optional: chime or visual flourish.

---

## Feature 3: Mega Map

### Purpose
A massive, seamless view of the entire explored dungeon. All maps rendered together, connected by portal lines. Zoomable from high-level topology down to room-level detail.

### Scale Levels

| Zoom Level | Scale | Detail Shown |
|------------|-------|--------------|
| Region     | 1:400 | Map blobs, portal lines only |
| Cluster    | 1:200 | Map shapes visible, no room detail |
| Map        | 1:100 | Individual rooms visible (current minimap level) |
| Room       | 1:50  | Room detail, portal markers, current position |

### Rendering Strategy

**Dynamic LOD (Level of Detail)**:
- Only render detail appropriate to current zoom
- At 1:400, maps are simplified shapes or icons
- At 1:100, switch to actual room geometry (same as current minimap)
- Hybrid: rooms at edge of view can be lower LOD than rooms at center

**Culling**:
- Don't instantiate geometry for maps outside camera view
- Stream in/out as camera pans
- Keep layout data in memory, geometry is ephemeral

**Data Structure**:
```lua
MegaMapLayout = {
    maps = {
        ["map_001"] = {
            position = Vector3.new(0, 0, 0),  -- world position in mega map space
            rotation = 0,  -- if maps can rotate
            bounds = { min = Vector3, max = Vector3 },
            rooms = { ... },  -- room data for detailed view
        },
        ["map_002"] = {
            position = Vector3.new(150, 0, 0),  -- offset from connected map
            ...
        },
    },
    connections = {
        { from = "map_001", to = "map_002", portalId = "portal_003" },
        ...
    },
}
```

### Layout Algorithm

Maps need positions in mega map space. Options:

**Option A: Tree Layout**
- First map at origin
- Each connected map positioned relative to parent
- Offset based on portal direction + map size
- Problem: Can create overlaps with loops/backtracking

**Option B: Force-Directed**
- Treat maps as nodes with repulsion
- Portals as springs with attraction
- Simulate until stable
- Cleaner layout, but more complex

**Option C: Grid Snapping**
- Assign maps to grid cells
- Connected maps try to be adjacent
- Simple, predictable, but less organic

**Recommendation**: Start with Option A (tree layout) with overlap detection. If overlap detected, offset the map until clear. Good enough for MVP, can upgrade later.

### Controls

Same pattern as current minimap, extended:
- **Right Stick**: Rotate view
- **Left Stick**: Pan camera across mega map
- **L1/R1**: Zoom in/out (smooth, triggers LOD changes)
- **L2/R2**: Jog through maps (not rooms—too many at this scale)
- **A/X Button**: Select map for detail view or navigation

### Visual Elements

**Maps**:
- Rendered as 3D room geometry (at appropriate LOD)
- Color-coded by exploration status or theme/biome
- Current map highlighted distinctly

**Portal Lines**:
- Lines connecting maps showing portal relationships
- Could be straight lines or curved arcs
- Unused portals shown as dashed or dimmed
- Used portals solid

**Player Position**:
- Clear indicator of current location
- Visible at all zoom levels (scales up when zoomed out)

**Fog of War**:
- Only explored maps rendered
- Unexplored portals show "???" or a mystery icon
- No peeking at undiscovered areas

### Performance Considerations

**At 100+ maps**:
- Don't render all geometry simultaneously
- Use impostor/billboard for distant maps
- Hybrid 2D/3D: very distant maps become 2D icons
- Limit particle effects, shadows, etc. in mega map view

**Memory**:
- Layout data (positions, connections) is cheap—keep all in memory
- Geometry is expensive—stream based on camera
- Consider pooling room geometry objects

**Frame Budget**:
- Mega map rendering shouldn't exceed minimap budget significantly
- Profile with 50, 100, 200 maps
- Degrade gracefully (simplify LOD earlier if needed)

---

## Feature 4: Integration Points

### Navigation + Minimap
- When nav mode active, current minimap shows route overlay
- Next portal highlighted
- Route line drawn through rooms (optional)

### Navigation + Mega Map
- Full route visible as highlighted path across maps
- Destination map pulsing or marked
- "You are here" and "destination" both visible when zoomed out

### Map Table + Minimap
- "View on Map" jumps minimap camera to that map
- Selected map highlighted

### Map Table + Mega Map
- Same as minimap: selection highlights on mega map
- Could auto-zoom to show selected map in context

### Navigation + Map Table
- Active route shown in table (maybe a "Currently Navigating" banner)
- Route steps could be expandable list

---

## Implementation Phases

### Phase 1: Map Table (Foundation)
1. Design data schema for map metadata
2. Build table UI component
3. Implement sorting/filtering
4. Add detail view per map
5. Connect to layout manager queries

### Phase 2: Navigation Core
1. Implement pathfinding (BFS over portal graph)
2. Build route data structure
3. Create nav mode state machine (active, paused, arrived, off-route)
4. Add HUD elements for active navigation

### Phase 3: Navigation UX
1. Portal highlighting in-world
2. Off-route detection and recalculation prompt
3. Arrival notification
4. Integration with minimap (route overlay)

### Phase 4: Mega Map Foundation
1. Design mega map layout algorithm
2. Build camera system (pan, zoom, rotate)
3. Implement basic rendering (all maps at fixed LOD)
4. Portal line rendering

### Phase 5: Mega Map Polish
1. Dynamic LOD based on zoom
2. Culling and streaming
3. Performance optimization
4. Integration with navigation (route visualization)
5. Integration with map table (selection sync)

---

## Open Questions

1. **Room-level vs Map-level navigation?**
   - Current design: Navigate to a map, not a specific room
   - Could extend to room-level later if needed

2. **Navigation in unexplored areas?**
   - Current design: Only navigate to explored maps
   - Could allow "navigate toward nearest unexplored" as a feature

3. **Mega map persistence?**
   - Does mega map layout persist between sessions?
   - Or recalculated each time from layout manager data?
   - Recommendation: Recalculate—layout manager is source of truth

4. **Multiplayer considerations?**
   - Does navigation work in co-op?
   - Do players share exploration state?
   - Out of scope for MVP, but worth noting

5. **Bookmarks/Pins?**
   - Allow players to mark favorite locations?
   - Would enhance navigation ("take me to my pinned spot")
   - Nice-to-have, not MVP

---

## Summary

Three interconnected systems:
1. **Map Table**: List-based interface for explored maps, detail views, sorting/filtering
2. **Navigation**: GPS-style pathfinding with route plotting, turn-by-turn guidance, recalculation
3. **Mega Map**: Seamless zoomable view of entire dungeon, dynamic LOD, route visualization

All three query the layout manager as source of truth. All three are view layers—no game state mutation. All three integrate with existing minimap patterns and controller UX.

Build in phases: Table → Nav Core → Nav UX → Mega Map → Polish.
