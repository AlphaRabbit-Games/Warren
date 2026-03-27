"""
Door Frame mesh for IT GETS WORSE
Beveled rectangular housing that sits in the doorway.
24x24 stud opening, 4 studs deep, with border detail.

Run: blender --background --python door_frame.py
Output: ../meshes/door_frame.fbx
"""

import bpy
import os

# Clear scene
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete()

# Constants (in studs — 1 stud = 1 Blender unit)
OPENING_W = 24
OPENING_H = 24
DEPTH = 4           # wall thickness * 2
BORDER = 3          # frame border width around opening
BEVEL = 0.8         # bevel on outer edges
INNER_LIP = 0.5     # small lip/channel where panels sit
RECESS_DEPTH = 0.6  # how deep the inner channel is recessed

# Outer dimensions
outer_w = OPENING_W + BORDER * 2
outer_h = OPENING_H + BORDER * 2

# Create outer block
bpy.ops.mesh.primitive_cube_add(size=1)
frame = bpy.context.active_object
frame.name = "DoorFrame"
frame.scale = (outer_w, DEPTH, outer_h)
bpy.ops.object.transform_apply(scale=True)

# Add boolean cutter for the main opening
bpy.ops.mesh.primitive_cube_add(size=1)
cutter = bpy.context.active_object
cutter.name = "OpeningCutter"
cutter.scale = (OPENING_W, DEPTH + 2, OPENING_H)
bpy.ops.object.transform_apply(scale=True)

# Boolean difference to cut the opening
bpy.context.view_layer.objects.active = frame
mod = frame.modifiers.new(name="CutOpening", type='BOOLEAN')
mod.operation = 'DIFFERENCE'
mod.object = cutter
bpy.ops.object.modifier_apply(modifier="CutOpening")

# Delete cutter
bpy.data.objects.remove(cutter, do_unlink=True)

# Add inner channel/recess where panels slide
bpy.ops.mesh.primitive_cube_add(size=1)
channel = bpy.context.active_object
channel.name = "ChannelCutter"
channel.scale = (OPENING_W + INNER_LIP * 2, RECESS_DEPTH, OPENING_H + INNER_LIP * 2)
channel.location = (0, DEPTH / 2 - RECESS_DEPTH / 2, 0)
bpy.ops.object.transform_apply(scale=True, location=True)

# Cut channel recess on front face
bpy.context.view_layer.objects.active = frame
mod = frame.modifiers.new(name="CutChannel", type='BOOLEAN')
mod.operation = 'DIFFERENCE'
mod.object = channel
bpy.ops.object.modifier_apply(modifier="CutChannel")

bpy.data.objects.remove(channel, do_unlink=True)

# Same channel on back face
bpy.ops.mesh.primitive_cube_add(size=1)
channel_back = bpy.context.active_object
channel_back.name = "ChannelCutterBack"
channel_back.scale = (OPENING_W + INNER_LIP * 2, RECESS_DEPTH, OPENING_H + INNER_LIP * 2)
channel_back.location = (0, -(DEPTH / 2 - RECESS_DEPTH / 2), 0)
bpy.ops.object.transform_apply(scale=True, location=True)

bpy.context.view_layer.objects.active = frame
mod = frame.modifiers.new(name="CutChannelBack", type='BOOLEAN')
mod.operation = 'DIFFERENCE'
mod.object = channel_back
bpy.ops.object.modifier_apply(modifier="CutChannelBack")

bpy.data.objects.remove(channel_back, do_unlink=True)

# Bevel the outer edges
bpy.context.view_layer.objects.active = frame
mod = frame.modifiers.new(name="Bevel", type='BEVEL')
mod.width = BEVEL
mod.segments = 2
mod.limit_method = 'ANGLE'
mod.angle_limit = 0.785  # 45 degrees
bpy.ops.object.modifier_apply(modifier="Bevel")

# Clean up geometry
bpy.ops.object.select_all(action='DESELECT')
frame.select_set(True)
bpy.context.view_layer.objects.active = frame
bpy.ops.object.editmode_toggle()
bpy.ops.mesh.select_all(action='SELECT')
bpy.ops.mesh.remove_doubles(threshold=0.01)
bpy.ops.mesh.normals_make_consistent(inside=False)
bpy.ops.object.editmode_toggle()

# Center origin
bpy.ops.object.origin_set(type='ORIGIN_GEOMETRY', center='BOUNDS')
frame.location = (0, 0, 0)

# Export
out_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'meshes')
os.makedirs(out_dir, exist_ok=True)
out_path = os.path.join(out_dir, 'door_frame.fbx')

bpy.ops.object.select_all(action='DESELECT')
frame.select_set(True)
bpy.ops.export_scene.fbx(
    filepath=out_path,
    use_selection=True,
    apply_scale_options='FBX_SCALE_UNITS',
    mesh_smooth_type='FACE',
)

print(f"Exported: {out_path}")
print(f"Verts: {len(frame.data.vertices)}, Faces: {len(frame.data.polygons)}")
