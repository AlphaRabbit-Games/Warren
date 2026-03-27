"""
Door Panel mesh for IT GETS WORSE
One half of the door. 24 studs wide, 12 studs tall.
Used twice (second mirrored vertically) — panels open by sliding apart.

Run: blender --background --python door_panel.py
Output: ../meshes/door_panel.fbx
"""

import bpy
import bmesh
import os

# Clear scene
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete()

# Constants (studs)
PANEL_W = 24
PANEL_H = 12         # half of 24 — top and bottom panels
PANEL_DEPTH = 1.5    # thin slab
INSET_MARGIN = 1.5   # margin from edge for the inset detail
INSET_DEPTH = 0.3    # how deep the inset panel is
EDGE_BEVEL = 0.3     # subtle bevel on panel edges
CENTER_LINE_W = 0.4  # width of the center glow line groove
CENTER_LINE_D = 0.2  # depth of center line groove

# Create base panel slab
bpy.ops.mesh.primitive_cube_add(size=1)
panel = bpy.context.active_object
panel.name = "DoorPanel"
panel.scale = (PANEL_W, PANEL_DEPTH, PANEL_H)
bpy.ops.object.transform_apply(scale=True)

# Cut inset detail on front face — recessed rectangle
inset_w = PANEL_W - INSET_MARGIN * 2
inset_h = PANEL_H - INSET_MARGIN * 2

bpy.ops.mesh.primitive_cube_add(size=1)
inset_cutter = bpy.context.active_object
inset_cutter.name = "InsetCutter"
inset_cutter.scale = (inset_w, INSET_DEPTH, inset_h)
inset_cutter.location = (0, PANEL_DEPTH / 2 - INSET_DEPTH / 2 + 0.01, 0)
bpy.ops.object.transform_apply(scale=True, location=True)

bpy.context.view_layer.objects.active = panel
mod = panel.modifiers.new(name="CutInset", type='BOOLEAN')
mod.operation = 'DIFFERENCE'
mod.object = inset_cutter
bpy.ops.object.modifier_apply(modifier="CutInset")

bpy.data.objects.remove(inset_cutter, do_unlink=True)

# Same inset on back face
bpy.ops.mesh.primitive_cube_add(size=1)
inset_back = bpy.context.active_object
inset_back.name = "InsetCutterBack"
inset_back.scale = (inset_w, INSET_DEPTH, inset_h)
inset_back.location = (0, -(PANEL_DEPTH / 2 - INSET_DEPTH / 2 + 0.01), 0)
bpy.ops.object.transform_apply(scale=True, location=True)

bpy.context.view_layer.objects.active = panel
mod = panel.modifiers.new(name="CutInsetBack", type='BOOLEAN')
mod.operation = 'DIFFERENCE'
mod.object = inset_back
bpy.ops.object.modifier_apply(modifier="CutInsetBack")

bpy.data.objects.remove(inset_back, do_unlink=True)

# Center horizontal groove (where the glow strip goes)
# This runs across the full width at the meeting edge (bottom of top panel)
bpy.ops.mesh.primitive_cube_add(size=1)
groove = bpy.context.active_object
groove.name = "GrooveCutter"
groove.scale = (PANEL_W + 0.1, CENTER_LINE_D, CENTER_LINE_W)
groove.location = (0, PANEL_DEPTH / 2 - CENTER_LINE_D / 2 + 0.01, -PANEL_H / 2 + INSET_MARGIN / 2)
bpy.ops.object.transform_apply(scale=True, location=True)

bpy.context.view_layer.objects.active = panel
mod = panel.modifiers.new(name="CutGroove", type='BOOLEAN')
mod.operation = 'DIFFERENCE'
mod.object = groove
bpy.ops.object.modifier_apply(modifier="CutGroove")

bpy.data.objects.remove(groove, do_unlink=True)

# Vertical center groove
bpy.ops.mesh.primitive_cube_add(size=1)
vgroove = bpy.context.active_object
vgroove.name = "VGrooveCutter"
vgroove.scale = (CENTER_LINE_W, CENTER_LINE_D, inset_h + 0.1)
vgroove.location = (0, PANEL_DEPTH / 2 - CENTER_LINE_D / 2 + 0.01, 0)
bpy.ops.object.transform_apply(scale=True, location=True)

bpy.context.view_layer.objects.active = panel
mod = panel.modifiers.new(name="CutVGroove", type='BOOLEAN')
mod.operation = 'DIFFERENCE'
mod.object = vgroove
bpy.ops.object.modifier_apply(modifier="CutVGroove")

bpy.data.objects.remove(vgroove, do_unlink=True)

# Subtle bevel on outer edges
bpy.context.view_layer.objects.active = panel
mod = panel.modifiers.new(name="Bevel", type='BEVEL')
mod.width = EDGE_BEVEL
mod.segments = 1
mod.limit_method = 'ANGLE'
mod.angle_limit = 0.785
bpy.ops.object.modifier_apply(modifier="Bevel")

# Clean up
bpy.ops.object.select_all(action='DESELECT')
panel.select_set(True)
bpy.context.view_layer.objects.active = panel
bpy.ops.object.editmode_toggle()
bpy.ops.mesh.select_all(action='SELECT')
bpy.ops.mesh.remove_doubles(threshold=0.01)
bpy.ops.mesh.normals_make_consistent(inside=False)
bpy.ops.object.editmode_toggle()

# Set origin to top edge center (the meeting edge when mirrored)
# Panel opens from center, so origin at the seam makes animation easier
bpy.ops.object.origin_set(type='ORIGIN_GEOMETRY', center='BOUNDS')
panel.location = (0, 0, 0)

# Export
out_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'meshes')
os.makedirs(out_dir, exist_ok=True)
out_path = os.path.join(out_dir, 'door_panel.fbx')

bpy.ops.object.select_all(action='DESELECT')
panel.select_set(True)
bpy.ops.export_scene.fbx(
    filepath=out_path,
    use_selection=True,
    apply_scale_options='FBX_SCALE_UNITS',
    mesh_smooth_type='FACE',
)

print(f"Exported: {out_path}")
print(f"Verts: {len(panel.data.vertices)}, Faces: {len(panel.data.polygons)}")
