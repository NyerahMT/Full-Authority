# NATO F-16 runtime asset drop

Upload exactly one optimized runtime archive to this branch at:

`Assets/F16NATO/f16_nato_runtime_assets.zip`

Expected SHA-256:

`7d6a5af9854f39dceb1b3c041e60eeb48da4920b0f2ad96dabbf0aed097e843d`

CI runs `scripts/install-f16-nato-assets.sh`, verifies the archive hash, expands it into `Assets/JSBSim/visuals/f16_nato/`, validates the FAM2 meshes, and then builds both the iOS Simulator and unsigned iPhone targets.

Do not upload the 75 MB source FBX here. Upload the optimized runtime ZIP only.
