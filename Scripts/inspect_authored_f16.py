import bpy
import sys
from pathlib import Path

args = sys.argv[sys.argv.index('--') + 1:]
f16_path = Path(args[0])
afterburner_path = Path(args[1])
out_path = Path(args[2])


def clear_scene():
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)
    for action in list(bpy.data.actions):
        bpy.data.actions.remove(action)


def fmt_vec(v):
    return f'({v.x:.6f}, {v.y:.6f}, {v.z:.6f})'


def inspect_fbx(path, title):
    clear_scene()
    bpy.ops.import_scene.fbx(filepath=str(path), use_anim=True)
    lines = [f'## {title}', f'file={path}', '']
    for obj in sorted(bpy.context.scene.objects, key=lambda o: o.name.lower()):
        lines.append(f'OBJECT {obj.name} type={obj.type} parent={obj.parent.name if obj.parent else "-"}')
        lines.append(f'  location={fmt_vec(obj.location)} rotation={fmt_vec(obj.rotation_euler)} scale={fmt_vec(obj.scale)}')
        if obj.type == 'MESH':
            mesh = obj.data
            lines.append(f'  mesh vertices={len(mesh.vertices)} polygons={len(mesh.polygons)} materials={[m.name for m in mesh.materials]}')
            if obj.vertex_groups:
                group_counts = []
                for group in obj.vertex_groups:
                    count = 0
                    weight_sum = 0.0
                    for vertex in mesh.vertices:
                        for g in vertex.groups:
                            if g.group == group.index and g.weight > 0.001:
                                count += 1
                                weight_sum += g.weight
                    group_counts.append((group.name, count, weight_sum))
                for name, count, weight_sum in sorted(group_counts):
                    lines.append(f'  VG {name} vertices={count} weight_sum={weight_sum:.3f}')
            world_corners = [obj.matrix_world @ __import__('mathutils').Vector(corner) for corner in obj.bound_box]
            mins = [min(v[i] for v in world_corners) for i in range(3)]
            maxs = [max(v[i] for v in world_corners) for i in range(3)]
            lines.append(f'  world_bounds min=({mins[0]:.6f},{mins[1]:.6f},{mins[2]:.6f}) max=({maxs[0]:.6f},{maxs[1]:.6f},{maxs[2]:.6f})')
        elif obj.type == 'ARMATURE':
            lines.append(f'  armature bones={len(obj.data.bones)}')
            for bone in obj.data.bones:
                basis = bone.matrix_local.to_3x3()
                local_x = basis.col[0].normalized()
                local_y = basis.col[1].normalized()
                local_z = basis.col[2].normalized()
                lines.append(
                    f'  BONE {bone.name} parent={bone.parent.name if bone.parent else "-"} '
                    f'head={fmt_vec(bone.head_local)} tail={fmt_vec(bone.tail_local)} '
                    f'localX={fmt_vec(local_x)} localY={fmt_vec(local_y)} localZ={fmt_vec(local_z)}'
                )

    for action in sorted(bpy.data.actions, key=lambda a: a.name):
        lines.append(f'ACTION {action.name} frames={tuple(round(v, 4) for v in action.frame_range)}')
        for curve in sorted(action.fcurves, key=lambda f: (f.data_path, f.array_index)):
            if 'pose.bones' not in curve.data_path:
                continue
            values = ', '.join(f'{kp.co.x:.3f}:{kp.co.y:.6f}' for kp in curve.keyframe_points)
            lines.append(f'  FCURVE {curve.data_path}[{curve.array_index}] {values}')
    lines.append('')
    return lines

lines = ['# vazgriz/FlightSim_F16 authored asset inspection', '']
lines += inspect_fbx(f16_path, 'F16.fbx')
lines += inspect_fbx(afterburner_path, 'afterburner.fbx')
out_path.parent.mkdir(parents=True, exist_ok=True)
out_path.write_text('\n'.join(lines), encoding='utf-8')
print('\n'.join(lines))