import bpy
import math
import sys
from pathlib import Path
from mathutils import Vector

args = sys.argv[sys.argv.index('--') + 1:]
f16_path = Path(args[0])
afterburner_path = Path(args[1])
out_path = Path(args[2])

CONTROL_BONES = [
    'LeftFlaperon', 'RightFlaperon',
    'LeftStabliator', 'RightStabliator',
    'Rudder',
]
AIRBRAKE_BONES = [
    'Airbrake_L_U', 'Airbrake_L_L', 'Airbrake_R_U', 'Airbrake_R_L',
]


def clear_scene():
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)
    for action in list(bpy.data.actions):
        bpy.data.actions.remove(action)


def fmt_vec(v):
    return f'({v.x:.6f}, {v.y:.6f}, {v.z:.6f})'


def to_fa(v):
    # Authored source coordinates -> Full Authority mesh-local coordinates.
    return Vector((v.x, v.z, v.y))


def animation_delta_lines(armature):
    lines = ['ANIMATION_DELTAS']

    def record(name, neutral_frame, deflected_frame):
        pose = armature.pose.bones.get(name)
        if pose is None:
            lines.append(f'  {name}: MISSING')
            return

        bpy.context.scene.frame_set(neutral_frame)
        neutral = pose.matrix.copy()
        bpy.context.scene.frame_set(deflected_frame)
        deflected = pose.matrix.copy()

        delta = deflected @ neutral.inverted()
        rotation = delta.to_quaternion()
        angle = rotation.angle
        axis = rotation.axis.copy()
        if angle > math.pi:
            angle -= 2 * math.pi
            axis.negate()

        axis_fa = to_fa(axis).normalized()
        pivot_source = armature.data.bones[name].head_local.copy()
        pivot_fa = to_fa(pivot_source)
        lines.append(
            f'  {name} neutral={neutral_frame} deflected={deflected_frame} '
            f'angleRad={angle:.8f} angleDeg={math.degrees(angle):.5f} '
            f'axisSource={fmt_vec(axis)} axisFA={fmt_vec(axis_fa)} '
            f'pivotFA={fmt_vec(pivot_fa)}'
        )

    for name in CONTROL_BONES:
        record(name, 41, 71)
    for name in AIRBRAKE_BONES:
        record(name, 1, 71)

    bpy.context.scene.frame_set(1)
    return lines


def inspect_fbx(path, title):
    clear_scene()
    bpy.ops.import_scene.fbx(filepath=str(path), use_anim=True)
    lines = [f'## {title}', f'file={path}', '']
    armature = None

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
            world_corners = [obj.matrix_world @ Vector(corner) for corner in obj.bound_box]
            mins = [min(v[i] for v in world_corners) for i in range(3)]
            maxs = [max(v[i] for v in world_corners) for i in range(3)]
            lines.append(f'  world_bounds min=({mins[0]:.6f},{mins[1]:.6f},{mins[2]:.6f}) max=({maxs[0]:.6f},{maxs[1]:.6f},{maxs[2]:.6f})')
        elif obj.type == 'ARMATURE':
            armature = obj
            lines.append(f'  armature bones={len(obj.data.bones)}')
            for bone in obj.data.bones:
                lines.append(
                    f'  BONE {bone.name} parent={bone.parent.name if bone.parent else "-"} '
                    f'head={fmt_vec(bone.head_local)} tail={fmt_vec(bone.tail_local)}'
                )

    if armature is not None and title == 'F16.fbx':
        lines.extend(animation_delta_lines(armature))

    for action in sorted(bpy.data.actions, key=lambda a: a.name):
        lines.append(f'ACTION {action.name} frames={tuple(round(v, 4) for v in action.frame_range)}')
    lines.append('')
    return lines


lines = ['# vazgriz/FlightSim_F16 authored asset inspection', '']
lines += inspect_fbx(f16_path, 'F16.fbx')
lines += inspect_fbx(afterburner_path, 'afterburner.fbx')
out_path.parent.mkdir(parents=True, exist_ok=True)
out_path.write_text('\n'.join(lines), encoding='utf-8')
print('\n'.join(lines))