# Stage 022 — Main Menu / Attract Mode

## Intent

Replace the immediate prototype-style briefing launch with a real front-end that presents Full Authority as a finished game before the player starts a sortie.

The menu is a live RealityKit scene, not a prerecorded video. It reuses the same world, HDR sky/environment lighting, F-16 geometry, atmosphere, and Stage 021 transonic vapor assets that the player sees in flight.

## Startup flow

1. App starts on a black NyerahWorks splash.
2. The menu RealityView is constructed asynchronously underneath the splash.
3. The splash remains visible for at least 1.35 seconds and never dismisses before the menu scene reports ready.
4. The splash fades directly into the live runway-side scene.

Apple documents the iOS/macOS RealityView `make` closure as asynchronous specifically so content can load without freezing the UI, with placeholder UI shown while that work completes. Stage 022 uses the same pattern, but with the branded NyerahWorks splash as the loading cover.

## Attract scene

- Fixed camera approximately 188 m east of the runway, looking toward runway 36.
- No cinematic orbiting, FOV pumping, shake, or menu-only color filter.
- Scripted F-16 takeoff event begins shortly after entering the menu and then recurs on a 47–61 second cadence.
- The takeoff aircraft accelerates along the actual runway coordinate system, rotates, climbs, retracts gear, and uses the existing warm Stage 021 burner.
- At approximately two minutes a second F-16 performs a low ~340 m/s pass along the runway. Only the existing transonic shell/halo is enabled around closest approach; maneuver-vapor streamers remain disabled.
- Menu audio is procedural and lightweight: low ambient airfield noise plus event-driven takeoff and flyby pressure/rumble layers. No bundled third-party audio is introduced.

## UI

Primary menu actions:
- FLY
- CONTROLS
- CREDITS

The menu keeps Full Authority's existing restrained white/black military presentation. Controls and credits are functional overlays rather than disabled placeholder buttons.

## Source / reference notes

- Apple RealityKit `RealityView` documentation: asynchronous scene construction and placeholder/loading behavior.
- FlightGear's open-source splash-screen guidance was reviewed as a reference for using loading time honestly and keeping splash imagery representative of the actual simulator rather than heavily post-processed marketing art.
- No new external art/audio assets are added in Stage 022; the scene is constructed from already-audited in-repository assets and generated audio.
