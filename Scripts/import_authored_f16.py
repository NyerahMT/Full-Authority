import bpy
import json
import shutil
import sys
from pathlib import Path
from mathutils import Vector

args = sys.argv[sys.argv.index('--') + 1:]
source_fbx = Path(args[0])
afterburner_fbx = Path(args[1])
source_texture = Path(args[2])
afterburner_texture = Path(args[3])
out_dir = Path(args[4])
license_path = Path(args[5])

PARTS = [
    'Root',
    'LeftFlaperon', 'RightFlaperon',
    'LeftStabliator', 'RightStabliator',
    'Rudder',
    'Airbrake_L_U', 'Airbrake_L_L', 'Airbrake_R_U', 'Airbrake_R_L',
]
FILE_NAMES = {
    'Root': 'f16_static.obj',
    'LeftFlaperon': 'left_flaperon.obj',
    'RightFlaperon': 'right_flaperon.obj',
    'LeftStabliator': 'left_stabilator.obj',
    'RightStabliator': 'right_stabilator.obj',
    'Rudder': 'rudder.obj',
    'Airbrake_L_U': 'airbrake_left_upper.obj',
    'Airbrake_L_L': 'airbrake_left_lower.obj',
    'Airbrake_R_U': 'airbrake_right_upper.obj',
    'Airbrake_R_L': 'airbrake_right_lower.obj',
}


def clear_scene():
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)


def to_fa(v):
    return Vector((v.x, v.z, v.y))


def normal_to_fa(v):
    n = to_fa(v)
    return n.normalized() if n.length > 1e-9 else Vector((0, 1, 0))


def dominant_group(mesh_obj, vertex_index):
    groups = mesh_obj.data.vertices[vertex_index].groups
    if not groups:
        return 'Root'
    best = max(groups, key=lambda g: g.weight)
    return mesh_obj.vertex_groups[best.group].name


def validate_partition(mesh_obj):
    mesh = mesh_obj.data
    mesh.calc_loop_triangles()
    mixed = []
    counts = {part: 0 for part in PARTS}
    for tri in mesh.loop_triangles:
        groups = [dominant_group(mesh_obj, i) for i in tri.vertices]
        if len(set(groups)) != 1:
            mixed.append((tuple(tri.vertices), tuple(groups)))
            continue
        if groups[0] not in counts:
            raise RuntimeError(f'Unexpected vertex group {groups[0]}')
        counts[groups[0]] += 1
    if mixed:
        raise RuntimeError(f'{len(mixed)} mixed-group triangles found; first five: {mixed[:5]}')
    return counts


def write_part_obj(mesh_obj, part_name, path, pivot_source):
    mesh = mesh_obj.data
    mesh.calc_loop_triangles()
    pivot = to_fa(pivot_source)
    triangles = []
    for tri in mesh.loop_triangles:
        if all(dominant_group(mesh_obj, i) == part_name for i in tri.vertices):
            triangles.append(tri)
    if not triangles:
        raise RuntimeError(f'No triangles found for {part_name}')

    positions, uvs, normals, faces = [], [], [], []
    uv_layer = mesh.uv_layers.active.data if mesh.uv_layers.active else None
    for tri in triangles:
        face = []
        for loop_index in tri.loops:
            loop = mesh.loops[loop_index]
            positions.append(to_fa(mesh.vertices[loop.vertex_index].co) - pivot)
            uv = uv_layer[loop_index].uv if uv_layer else (0.0, 0.0)
            uvs.append((float(uv[0]), float(uv[1])))
            normals.append(normal_to_fa(loop.normal))
            face.append(len(positions))
        # to_fa() swaps Y/Z and therefore flips handedness. Reverse the
        # triangle winding so exported OBJ front faces remain outward-facing.
        faces.append([face[0], face[2], face[1]])

    with path.open('w', encoding='utf-8') as f:
        f.write('# Authored F-16 mesh extracted from vazgriz/FlightSim_F16 (MIT)\n')
        f.write(f'o {part_name}\n')
        for v in positions:
            f.write(f'v {v.x:.7f} {v.y:.7f} {v.z:.7f}\n')
        for uv in uvs:
            f.write(f'vt {uv[0]:.7f} {uv[1]:.7f}\n')
        for n in normals:
            f.write(f'vn {n.x:.7f} {n.y:.7f} {n.z:.7f}\n')
        for face in faces:
            f.write('f ' + ' '.join(f'{i}/{i}/{i}' for i in face) + '\n')

    return {'vertices_emitted': len(positions), 'triangles': len(faces), 'pivot': list(pivot)}


def export_aircraft():
    clear_scene()
    bpy.ops.import_scene.fbx(filepath=str(source_fbx), use_anim=True)
    mesh_obj = bpy.data.objects.get('F16')
    armature = bpy.data.objects.get('Armature')
    if mesh_obj is None or armature is None:
        raise RuntimeError('F16 mesh/Armature not found')

    for vertex in mesh_obj.data.vertices:
        weighted = [(mesh_obj.vertex_groups[g.group].name, g.weight) for g in vertex.groups if g.weight > 0.001]
        if len(weighted) != 1 or abs(weighted[0][1] - 1.0) > 1e-4:
            raise RuntimeError(f'Vertex {vertex.index} has ambiguous weights: {weighted}')

    partition_counts = validate_partition(mesh_obj)
    manifest = {
        'source': 'vazgriz/FlightSim_F16',
        'source_revision': 'df9a4162f0afbdae92bf386ed9503737e0edbecd',
        'license': 'MIT',
        'source_axes': '+X right, +Y nose, +Z up',
        'full_authority_axes': '+X right, +Y up, +Z nose',
        'parts': {},
    }
    for part in PARTS:
        bone = armature.data.bones.get(part)
        if bone is None:
            raise RuntimeError(f'Missing authored bone {part}')
        pivot_source = bone.head_local if part != 'Root' else Vector((0, 0, 0))
        info = write_part_obj(mesh_obj, part, out_dir / FILE_NAMES[part], pivot_source)
        basis = bone.matrix_local.to_3x3()
        # The source animation curves rotate all authored moving surfaces around
        # their local quaternion X component. Convert that rest-space local-X
        # direction into Full Authority coordinates and store it explicitly.
        axis = normal_to_fa(basis.col[0])
        info.update({
            'source_bone': part,
            'bone_head_source': list(bone.head_local),
            'bone_tail_source': list(bone.tail_local),
            'rotation_axis': list(axis),
            'source_triangles': partition_counts[part],
        })
        manifest['parts'][part] = info

    coords = [to_fa(v.co) for v in mesh_obj.data.vertices]
    manifest['bounds'] = {
        'min': [min(v[i] for v in coords) for i in range(3)],
        'max': [max(v[i] for v in coords) for i in range(3)],
    }
    (out_dir / 'manifest.json').write_text(json.dumps(manifest, indent=2), encoding='utf-8')


def export_afterburner():
    clear_scene()
    bpy.ops.import_scene.fbx(filepath=str(afterburner_fbx), use_anim=False)
    mesh_obj = next((o for o in bpy.context.scene.objects if o.type == 'MESH'), None)
    if mesh_obj is None:
        raise RuntimeError('Afterburner mesh not found')
    mesh = mesh_obj.data
    mesh.calc_loop_triangles()
    positions, normals, uvs, faces = [], [], [], []
    uv_layer = mesh.uv_layers.active.data if mesh.uv_layers.active else None
    for tri in mesh.loop_triangles:
        face = []
        for loop_index in tri.loops:
            loop = mesh.loops[loop_index]
            src = mesh.vertices[loop.vertex_index].co
            positions.append(Vector((src.x, src.z, src.y)))
            uv = uv_layer[loop_index].uv if uv_layer else (0.0, 0.0)
            uvs.append((float(uv[0]), float(uv[1])))
            normals.append(normal_to_fa(loop.normal))
            face.append(len(positions))
        # to_fa() swaps Y/Z and therefore flips handedness. Reverse the
        # triangle winding so exported OBJ front faces remain outward-facing.
        faces.append([face[0], face[2], face[1]])
    path = out_dir / 'afterburner_plume.obj'
    with path.open('w', encoding='utf-8') as f:
        f.write('# Authored afterburner envelope from vazgriz/FlightSim_F16 (MIT)\n')
        f.write('o afterburner_plume\n')
        for v in positions:
            f.write(f'v {v.x:.7f} {v.y:.7f} {v.z:.7f}\n')
        for uv in uvs:
            f.write(f'vt {uv[0]:.7f} {uv[1]:.7f}\n')
        for n in normals:
            f.write(f'vn {n.x:.7f} {n.y:.7f} {n.z:.7f}\n')
        for face in faces:
            f.write('f ' + ' '.join(f'{i}/{i}/{i}' for i in face) + '\n')


out_dir.mkdir(parents=True, exist_ok=True)
export_aircraft()
export_afterburner()
shutil.copy2(source_texture, out_dir / 'f16.png')
shutil.copy2(afterburner_texture, out_dir / 'afterburner.png')
shutil.copy2(license_path, out_dir / 'LICENSE-FlightSim_F16.txt')
print('Exported authored F-16 assets to', out_dir)