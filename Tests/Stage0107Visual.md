# Stage 010.7 visual validation

Physical-device checks for the Stage 010.7 mesh/effects pass:

- No procedural canopy, radome, nozzle, afterburner ellipsoid, navigation-light spheres, or speedbrake overlays are instantiated on the F-16 exterior.
- Canopy, radome, and exhaust appearance comes from material changes applied to faces of the stock MIT R4 F-16 mesh.
- Left/right flaperon and stabilator selection is derived from one mirrored planform definition so geometry cuts are symmetric.
- Every stabilator triangle must lie fully inside the tail planform/height gate; fuselage/root triangles must remain in the static shell.
- Hinge pivots are exact mirror pairs.
- JSBSim dht-left and dht-right angles are used directly with mirror-correct hinge axes.
- Left aileron presentation follows the mature F-16 convention: JSBSim's mirrored left sign is inverted at the visual hinge while the right side is used directly.
- External CHASE/CLOSE drag orbit and RECENTER remain functional.
- Contrail activation retains the Stage 010.6 atmosphere logic; visible wake geometry uses the Stage 010.7 core/vortex/secondary-wake model.
