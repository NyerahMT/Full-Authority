# JSBSim reload crash regression

Observed on physical iPhone 15 Pro Max / iOS 27 beta:

- app constructs `FlightSimulation`, which loads and trims `f16`
- tapping **Enter Free Flight** previously called `resetFlight()`
- `resetFlight()` called `loadModel(named:)` a second time on the same `FGFDMExec`
- the second load crashed in `FGInitialCondition::SetTerrainElevationFtIC()` while dereferencing `FGFDMExec::GetInertial()`

The bridge now creates a fresh `FGFDMExec` for every explicit aircraft load/restart, and the first launch only resumes the already-prepared simulation.

Regression checks:

1. Cold launch reaches briefing without a crash.
2. Enter Free Flight does not reload the aircraft.
3. Pause -> Restart performs a full load on a fresh executive.
4. Pause -> Briefing performs a full reset on a fresh executive.
5. Re-entering Free Flight resumes that prepared reset state.
