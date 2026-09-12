# NATO F-16 visual asset

Full Authority uses a runtime-optimized adaptation of **F-16 Fighting Falcon | NATO | GameReady** by **Pan_Ar4ik**, distributed under **Creative Commons Attribution (CC BY)**.

Source: Sketchfab model page for `F-16 Fighting Falcon | NATO | GameReady` by Pan_Ar4ik.

The original FBX is not required at runtime. The checked-in runtime archive contains only the converted meshes and PBR textures needed by Full Authority. The conversion:

- scales the aircraft to a 15.06 m F-16 length;
- maps source axes `+X nose, +Y span/right, +Z up` into Full Authority axes `+X right, +Y up, +Z nose`;
- preserves the modeled cockpit and canopy;
- separates the left and right all-moving horizontal stabilators for JSBSim-driven animation;
- omits the source GBU-10 and AIM-120 static stores;
- adds tangent vectors for RealityKit normal mapping;
- uses a compact `FAM2` little-endian runtime mesh format.

## Source audit

The supplied FBX contains **no armature/deformer objects, no animation stacks, and no pilot mesh**. The detailed cockpit, ejection seat, canopy, exterior airframe, and PBR textures are authored geometry. Full Authority therefore does not claim source animations or a pilot that are not present in the actual file.

## Runtime archive

Expected repository path:

`Assets/F16NATO/f16_nato_runtime_assets.zip`

SHA-256:

`7d6a5af9854f39dceb1b3c041e60eeb48da4920b0f2ad96dabbf0aed097e843d`

`scripts/install-f16-nato-assets.sh` validates and expands that archive into the build-time `Assets/JSBSim/visuals/f16_nato/` resource directory.

Keep this attribution with redistributions of the adapted asset as required by CC BY.
