# Layout Generation Process

A step-by-step guide for AI-assisted building layout generation using Factory/GeometrySpec.

## Philosophy

**Modular composition over monolithic generation.** Break buildings into layers that can be mixed, matched, and iterated independently:

```
Building = BaseShell + Openings + Facade + Attachments
```

This approach:
- Gets 80-90% right on first pass
- Enables fast iteration on specific layers
- Creates reusable templates
- Keeps layouts maintainable

---

## Layer Breakdown

### 1. BaseShell
The structural skeleton: footprint, rooms, walls, roof massing.

**Contains:**
- Floor plan / room layout
- Exterior wall positions (no openings yet)
- Interior walls with doorway openings
- Roof structure and overhangs
- Foundation/slab

**Does NOT contain:**
- Windows or exterior doors
- Material choices
- Decorative elements
- Attachments (garage, carport)

### 2. Openings
Window and exterior door placements as hole definitions.

**Contains:**
- Window holes (position, size per wall)
- Exterior door holes
- Slider/glass door holes
- Clerestory/skylight positions

**Variations:**
- `Openings_Modern` - Large sliders, picture windows, clerestory strips
- `Openings_Traditional` - Double-hung, smaller, symmetrical
- `Openings_Minimal` - Few small windows, privacy-focused

### 3. Facade
Materials and exterior styling.

**Contains:**
- Exterior wall materials and colors
- Roof materials
- Trim/fascia styling
- Accent materials (stone, brick sections)

**Variations:**
- `Facade_DesertModern` - Smooth stucco, flat roof, minimal trim
- `Facade_Craftsman` - Wood siding, exposed rafters, stone accents
- `Facade_MidCentury` - Mixed materials, bold accent colors

### 4. Attachments
Modular add-ons with standard connection points.

**Types:**
- `Attachment_Carport` - Open covered parking
- `Attachment_1CarGarage` - Enclosed single
- `Attachment_2CarGarage` - Enclosed double
- `Attachment_Patio` - Covered outdoor space
- `Attachment_Pool` - Pool + deck area

---

## Phase 1: Research

Before generating anything, gather reference information to understand the building type. This research informs all subsequent generation steps.

### Research Sources

- **Web search** - Architectural history, style guides, floor plan examples
- **Image references** - Exterior photos, interior photos, aerial views
- **Floor plans** - Published plans from the era/style
- **Real estate listings** - Modern examples with dimensions
- **Architectural books/articles** - Style-defining characteristics

### Architectural Data to Extract

Fill in as much as possible for your target building:

#### 1. Style Identity
```
Style Name:
Era/Period:
Region/Origin:
Key Architects/Builders:
Related Styles:
Defining Philosophy:
```

**Example:**
```
Style Name: Atomic Ranch / Mid-Century Modern Ranch
Era/Period: 1950-1965
Region/Origin: California, spreading nationwide
Key Architects/Builders: Cliff May, Eichler Homes, Palmer & Krisel
Related Styles: California Ranch, Post-and-Beam, Desert Modern
Defining Philosophy: Indoor-outdoor living, informal open plans,
                     integration with landscape, optimistic modernism
```

#### 2. Massing & Footprint
```
Typical Square Footage:
Stories:
Footprint Shape:
Length-to-Width Ratio:
Roof Type:
Roof Pitch:
Roof Overhang:
Foundation Type:
```

**Example:**
```
Typical Square Footage: 1,200 - 2,400 sq ft
Stories: Single story (defining characteristic)
Footprint Shape: L-shape, U-shape, or linear with wings
Length-to-Width Ratio: Long and low (2:1 to 3:1)
Roof Type: Low-pitched gable or flat
Roof Pitch: 2:12 to 4:12 (very low) or flat
Roof Overhang: Deep overhangs (2-4 feet) for shade
Foundation Type: Slab-on-grade (no basement)
```

#### 3. Dimensions & Proportions
```
Ceiling Height:
Wall Height (exterior):
Standard Door Size:
Entry Door Style:
Window Sill Height:
Typical Window Sizes:
Wall Thickness:
```

**Example:**
```
Ceiling Height: 8-9 ft (flat), up to 12 ft (vaulted/cathedral)
Wall Height (exterior): 8-10 ft
Standard Door Size: 3'0" x 6'8" (interior), 3'0" x 6'8" (entry)
Entry Door Style: Solid wood slab, often painted bold color
Window Sill Height: 2-3 ft (view windows), 6-7 ft (clerestory)
Typical Window Sizes: Large fixed panes, sliding glass 6-8 ft wide
Wall Thickness: 4-6 inches (wood frame)
```

#### 4. Fenestration (Windows & Doors)
```
Window Pattern/Philosophy:
Primary Window Types:
Glass-to-Wall Ratio:
Signature Window Features:
Entry Configuration:
Rear/Garden Access:
```

**Example:**
```
Window Pattern/Philosophy: Walls of glass facing private areas (rear/court),
                          minimal windows facing street for privacy
Primary Window Types: Fixed picture windows, sliding glass doors,
                     clerestory strips, floor-to-ceiling glass
Glass-to-Wall Ratio: High (30-50% on rear elevation)
Signature Window Features: Clerestory windows under roofline,
                          corner windows, window walls
Entry Configuration: Often recessed or in courtyard, not prominent
Rear/Garden Access: Large sliders opening to patio, indoor-outdoor flow
```

#### 5. Room Layout
```
Typical Room Count:
Public/Private Zoning:
Room Adjacencies:
Circulation Pattern:
Signature Spaces:
```

**Example:**
```
Typical Room Count: 3 bed, 2 bath, living/dining/kitchen
Public/Private Zoning: Bedrooms in one wing, living in another (separated)
Room Adjacencies: Kitchen open to dining/living, master separated from kids
Circulation Pattern: Central hallway spine, or flow through open areas
Signature Spaces: Open living/dining, courtyard/atrium, covered patio
```

#### 6. Materials Palette
```
Exterior Walls:
Interior Walls:
Roofing:
Flooring:
Trim/Fascia:
Accent Materials:
Era-Specific Materials:
```

**Example:**
```
Exterior Walls: Stucco, vertical wood siding, brick (partial), block
Interior Walls: Drywall (painted), wood paneling (accent walls)
Roofing: Built-up tar and gravel (flat), wood shake, composition
Flooring: Concrete slab (exposed/stained), terrazzo, VCT, carpet
Trim/Fascia: Painted wood, exposed beams, minimal trim
Accent Materials: Slumpstone, flagstone, Roman brick, lava rock
Era-Specific Materials: Post-and-beam construction, glass curtain walls
```

#### 7. Exterior Features
```
Entry Approach:
Garage/Parking:
Outdoor Living:
Landscaping Integration:
Fencing/Privacy:
```

**Example:**
```
Entry Approach: Courtyard entry, recessed, or covered walkway
Garage/Parking: Attached carport (open), or integrated garage wing
Outdoor Living: Covered patio, outdoor room, pool area common
Landscaping Integration: Desert/xeriscape, atrium gardens, mature trees
Fencing/Privacy: Block walls, wood fencing for rear privacy
```

#### 8. Distinguishing Details
```
Signature Elements:
What Makes It Recognizable:
Common Variations:
Regional Differences:
Budget vs Luxury Versions:
```

**Example:**
```
Signature Elements: Low-slung roofline, deep overhangs, post-and-beam,
                   glass walls, clerestory windows, integrated planter boxes
What Makes It Recognizable: Horizontal emphasis, flat/low roof,
                           glass-to-garden connection, open floor plan
Common Variations: With/without courtyard, carport vs garage,
                  flat roof vs low gable
Regional Differences: CA: more glass, stucco. Southwest: block, desert colors.
                     Midwest: brick, steeper roof for snow
Budget vs Luxury Versions: Basic box vs multiple wings, tract vs custom
```

### Research Output Template

Compile research into a structured brief:

```markdown
# [Building Type] Design Brief

## Overview
- **Style:** [Name and era]
- **Target Size:** [Sq footage]
- **Configuration:** [Beds/baths/key spaces]
- **Site Assumptions:** [Orientation, lot size]

## Key Dimensions
| Element | Dimension | Notes |
|---------|-----------|-------|
| Total sq ft | | |
| Ceiling height | | |
| Wall height | | |
| Roof pitch | | |
| Overhang depth | | |
| Door sizes | | |
| Window sizes | | |

## Massing
- Footprint shape:
- Length/width ratio:
- Roof type:
- Stories:

## Fenestration Strategy
- Street-facing:
- Rear/private:
- Signature window types:
- Entry configuration:

## Materials
- Exterior walls:
- Roof:
- Accents:
- Trim:

## Room Relationships
- [Diagram or description of room adjacencies]
- Zoning (public vs private):
- Circulation:

## Signature Elements
- Must-have features:
- Period-appropriate details:
- What to avoid (anachronisms):

## Reference Images
- [Links or descriptions of key reference images]
```

---

## Phase 2: Generation

With research complete, proceed to generation steps.

### Step 1: Define Requirements

Using your research brief, establish specific requirements:

```markdown
**Building Type:** Single-family ranch house
**Era/Style:** 1960s Atomic Ranch / Mid-Century Modern
**Approximate Size:** 1,800 sq ft living + 400 sq ft garage
**Rooms:** 3 bed, 2 bath, open living/dining/kitchen
**Site Orientation:** Street to north, backyard to south
**Key Features:** Indoor-outdoor flow, carport, courtyard entry
```

### Step 2: Generate BaseShell

**Prompt template:**

```
Generate a BaseShell layout for a [building type] in GeometrySpec format.

Requirements:
- [Size and room list]
- [Site orientation]
- [Key spatial relationships]

Coordinate system:
- Origin (0,0,0) at southwest corner
- +X = East, +Z = North, +Y = Up
- All dimensions in studs (4 studs ≈ 1 meter)

Output format:
- Exterior walls as solid parts (no openings yet)
- Interior walls with doorway holes
- Include ceiling and roof structure
- Use placeholder classes: exterior, interior, roof, foundation

Do NOT include:
- Windows or exterior doors (added in Openings layer)
- Specific materials (added in Facade layer)
- Garage/carport (added as Attachment)
```

**Review checklist:**
- [ ] Room sizes feel right
- [ ] Traffic flow works
- [ ] Wall positions are clean numbers
- [ ] Roof covers entire footprint with overhang

### Step 3: Generate Openings

**Prompt template:**

```
Generate an Openings template for the following BaseShell.

Style: [Modern / Traditional / Minimal]

Guidelines for [style]:
- [Window size preferences]
- [Placement patterns]
- [Special features like clerestory]

Output format:
- List of holes to add to each exterior wall
- Use the `holes` array format: { position = {x, y, z}, size = {w, h, d} }
- Position is relative to wall center
- Include comments noting what each opening is for

Walls to add openings to:
[List wall IDs from BaseShell]
```

**Review checklist:**
- [ ] Windows placed at appropriate heights (sill height ~3 studs)
- [ ] Openings don't conflict with interior walls
- [ ] South-facing glass for passive solar (if applicable)
- [ ] Privacy maintained on street-facing walls

### Step 4: Generate Facade

**Prompt template:**

```
Generate a Facade template (classes block) for [style name].

Style reference: [Description or era]

Output format - classes block:
- exterior: Main wall material and color
- interior: Interior wall finish
- roof: Roofing material
- fascia: Trim/fascia material
- accent: Feature material (stone, brick, etc.)
- door: Entry door color
- [any additional classes needed]

Use realistic Roblox materials: SmoothPlastic, Concrete, Brick, Wood, Slate, Metal, Glass, etc.
Use RGB colors as {r, g, b} arrays.
```

**Review checklist:**
- [ ] Materials are era-appropriate
- [ ] Color palette is cohesive
- [ ] Accent materials add visual interest
- [ ] Contrast between elements (trim vs walls)

### Step 5: Generate Attachments

**Prompt template:**

```
Generate an Attachment module for [type: carport/garage/patio].

Connection point: [Location relative to main house]
Style: Match [facade style name]

Output format:
- Separate layout that can be xref'd into main building
- Include connection/transition elements
- Use same class names as main Facade

Dimensions:
- [Size requirements]
- [Clearance requirements]
```

**Review checklist:**
- [ ] Roofline relates to main house
- [ ] Materials match facade
- [ ] Proportions feel right
- [ ] Connection point aligns with main structure

### Step 6: Assemble Final Layout

Combine layers into final layout:

```lua
return {
    name = "AtomicRanch_Modern",
    spec = {
        origin = "corner",

        -- From Facade layer
        classes = {
            exterior = { Material = "SmoothPlastic", Color = {240, 235, 225} },
            interior = { Material = "SmoothPlastic", Color = {250, 248, 245} },
            roof = { Material = "SmoothPlastic", Color = {90, 85, 80} },
            -- ...
        },

        -- From BaseShell + Openings merged
        parts = {
            -- Walls with holes from Openings layer
            { id = "WallSouth", class = "exterior",
              position = {...}, size = {...},
              holes = {
                  -- From Openings_Modern template
                  { position = {...}, size = {...} },  -- Picture window
                  { position = {...}, size = {...} },  -- Slider
              }},
            -- ...
        },

        -- Attachments via xref
        -- { id = "carport", xref = Attachment_Carport, position = {...} },
    },
}
```

### Step 7: Build and Review

```lua
local house = Factory.geometry(Lib.Layouts.AtomicRanch_Modern)
```

**In-Studio review:**
- Walk through at player scale
- Check sightlines and flow
- Verify window placements feel right
- Test lighting at different times

### Step 8: Iterate

Make adjustments in Studio, then scan back:

```lua
Factory.scan(house)  -- Outputs updated layout code
```

Or request targeted changes:

```
Adjust the Openings for WallSouth:
- Make the picture window 2 studs wider
- Move the slider 4 studs east
- Add a small window above the slider (clerestory)
```

---

## Best Practices

### Dimensions
- Use clean numbers (multiples of 4 preferred)
- Standard wall height: 9-10 studs (ranch), 10-12 studs (two-story)
- Standard door: 3.5w x 7h
- Standard window: 4w x 4h
- Slider door: 8w x 7h
- Wall thickness: 0.5 studs (exterior), 0.33 studs (interior)

### Positioning
- Y values are CENTER of part (Roblox convention)
- Position walls so edges align (account for thickness)
- Holes are positioned relative to wall CENTER

### Naming
- Descriptive IDs: `WallSouth`, `WallKitchenNorth`, `RoofMain`
- Consistent naming across templates
- Prefix attachments: `Carport_Roof`, `Carport_Post`

### Classes
- Keep class names generic: `exterior`, `roof`, `accent`
- This allows Facade swapping without changing parts
- Use inline properties only for one-off overrides

---

## Template Library Structure

```
Lib/Layouts/
├── BaseShells/
│   ├── Ranch_3Bed.lua
│   ├── Ranch_4Bed.lua
│   ├── TwoStory_Colonial.lua
│   └── ...
├── Openings/
│   ├── Modern.lua
│   ├── Traditional.lua
│   ├── Minimal.lua
│   └── ...
├── Facades/
│   ├── DesertModern.lua
│   ├── MidCentury.lua
│   ├── Craftsman.lua
│   └── ...
├── Attachments/
│   ├── Carport.lua
│   ├── Garage_1Car.lua
│   ├── Garage_2Car.lua
│   ├── Patio_Covered.lua
│   └── ...
└── Assembled/
    ├── AtomicRanch_Modern.lua      -- Ranch_3Bed + Modern + MidCentury + Carport
    ├── AtomicRanch_Traditional.lua  -- Ranch_3Bed + Traditional + Craftsman + Garage_2Car
    └── ...
```

---

## Quick Reference: Prompting Tips

**Be specific about coordinate system:**
> Origin at southwest corner, +X=East, +Z=North, +Y=Up

**Request clean numbers:**
> Use whole numbers, prefer multiples of 4 for dimensions

**Separate concerns:**
> "Generate walls only, no windows yet"
> "Add openings to these walls: WallSouth, WallEast..."

**Reference the style:**
> "1960s Atomic Ranch style - low-slung, flat roof, large glass areas"

**Specify what NOT to include:**
> "Do not include garage - will be added as attachment"

**Request format explicitly:**
> "Output as GeometrySpec format with classes block and parts array"
