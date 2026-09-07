from pathlib import Path


def replace_once(path, old, new):
    p = Path(path)
    text = p.read_text()
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{path}: expected 1 match for {old[:100]!r}, got {count}")
    p.write_text(text.replace(old, new, 1))

state_path = "Simulation/AircraftState.swift"
replace_once(
    state_path,
    "    var engineFuelFlowPoundsPerSecond: Float = 0\n",
    "    var engineFuelFlowPoundsPerSecond: Float = 0\n"
    "    var aircraftMassKg: Float = 9_500\n"
)

sim_path = "Simulation/FlightSimulation.swift"
replace_once(
    sim_path,
    '        state.engineFuelFlowPoundsPerSecond = max(0, finiteFloat("propulsion/engine[0]/fuel-flow-rate-pps", fallback: 0))',
    '        state.engineFuelFlowPoundsPerSecond = max(0, finiteFloat("propulsion/engine[0]/fuel-flow-rate-pps", fallback: 0))\n'
    '        state.aircraftMassKg = max(1, finiteFloat("inertia/weight-lbs", fallback: 20_944) * 0.45359237)'
)
