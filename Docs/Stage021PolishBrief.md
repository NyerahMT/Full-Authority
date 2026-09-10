# Stage 021 — VFX, Audio, Atmosphere + Rudder Control

Stage 021 builds on the full-game Stage 020 visual reset. The goal is to make motion, weather cues, exhaust, vapor, sound and directional control feel authored and aviation-specific without reintroducing arcade camera behavior or full-screen cinematic filters.

## Non-negotiables

- Chase/close/cockpit camera mechanics remain unchanged.
- No speed lines, FOV pumping, fake lens dirt, chromatic aberration, bloom-heavy glare or global color-grade overlays.
- Effects must be driven by real state where practical: Mach, AoA, load factor, ambient pressure, temperature, humidity, engine state and wind.
- Touch rudder must create a real in-flight sideslip/yaw response while the feet-off-pedals yaw SAS still damps the airplane.
- Keep Stage 020 HDR daylight and matte F-16 presentation.

## Directional-control correction

The Stage 020 yaw-law split unintentionally left lateral-acceleration feedback active during deliberate pedal input, so the SAS could oppose the sideslip the pilot was commanding. NASA lateral/directional control-law material explicitly discusses removing lateral-acceleration feedback when rudder pedals are deflected so the feedback does not resist a desired sideslip maneuver.

Stage 021 therefore:

1. Keeps yaw-rate damping active.
2. Keeps lateral-acceleration feedback with feet centered.
3. Gates lateral-acceleration feedback out when pedal command exceeds a small deadband.
4. Sends pilot pedal into the final rudder scheduler once.
5. Keeps the high-speed yaw-rate schedule modestly stronger than upstream to address the observed weak feet-off-pedals damping.
6. Adds an on-screen commanded-vs-actual rudder readout while the pedal is displaced so the input path can be verified on-device.

## Atmosphere

Use the Stage 020 HDR environment as the authoritative sky and environment light. Add scene-space depth haze rather than a screen-space filter: low-opacity translucent shells at real distances so near terrain stays crisp and distant terrain progressively loses contrast.

## Flight effects

- Contrails: break up the uniform tube silhouette with deterministic age-dependent wander and radius variation while preserving Schmidt-Appleman formation/persistence gating.
- Maneuver vapor: keep it attached to the wing and driven by AoA/load/humidity, but reduce the solid spindle look.
- Transonic vapor: keep the requested conical/flat-base silhouette, but make it more condition-sensitive and less persistent.
- Afterburner: retain the existing geometry hierarchy but tune opacity, envelope and shock-cell presentation against public-domain USAF/DVIDS F-16 references rather than turning it into a sci-fi plume.

## Audio

Keep the existing zero-network procedural engine architecture, but rebalance it against public-domain F-16 burner/test-cell recordings:

- less persistent compressor whine in cockpit,
- more low/mid-frequency exhaust body outside,
- smoother afterburner transition,
- wind/buffet response tied to Mach, AoA and sideslip,
- no broadband white-noise wall.

## References

- NASA lateral/directional control-law material: https://ntrs.nasa.gov/api/citations/19760010067/downloads/19760010067.pdf?attachment=true
- Falcon BMS F-16 FLCS developer notes, yaw section: https://www.falcon-bms.com/wp-content/uploads/2021/08/FM_Developers_Notes_Part_4.pdf
- JSBSim F-16 yaw-channel discussion #814: https://github.com/JSBSim-Team/jsbsim/discussions/814
- NASA contrail lifecycle / Schmidt-Appleman modeling: https://ntrs.nasa.gov/citations/20230014633
- DVIDS F-16 afterburner reference: https://www.dvidshub.net/image/2696034/afterburner
- DVIDS F-16 burner run reference audio/video: https://www.dvidshub.net/video/894291/f-16-burner-run
- Apple RealityKit EnvironmentResource / image-based lighting docs: https://developer.apple.com/documentation/realitykit/environmentresource
- Apple RealityKit scene audio docs: https://developer.apple.com/documentation/realitykit/scene-content-audio
