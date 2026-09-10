#import "FAJSBSimBridge.h"

// Xcode's Debug configuration defines DEBUG=1, while JSBSim uses DEBUG as an
// enum member (LogLevel::DEBUG). Keep that app-level macro out of this C++
// translation unit before including JSBSim headers.
#ifdef DEBUG
#undef DEBUG
#endif

#include <FGFDMExec.h>
#include <initialization/FGTrim.h>
#include <input_output/FGGroundCallback.h>
#include <math/FGColumnVector3.h>
#include <math/FGLocation.h>
#include <models/FGInertial.h>
#include <simgear/misc/sg_path.hxx>

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <exception>
#include <memory>
#include <string>

#include "Stage022MaltaTerrain.inc"

namespace {
NSString * const FAJSBSimErrorDomain = @"com.nyerahworks.FullAuthority.JSBSim";

constexpr double kMetersToFeet = 3.280839895013123;
constexpr double kEarthRadiusMeters = 6371000.0;
constexpr double kTerrainSampleMeters = 20.0;

void SetBridgeError(NSError **error, NSString *message) {
    if (!error) return;
    *error = [NSError errorWithDomain:FAJSBSimErrorDomain
                                 code:1
                             userInfo:@{NSLocalizedDescriptionKey: message}];
}

double SmoothStep(double value) {
    const double t = std::clamp(value, 0.0, 1.0);
    return t * t * (3.0 - 2.0 * t);
}

// Stage 022 expands the baked Terrarium heightfield to the complete Malta/Gozo/Comino
// rectangle at the same 125 m spacing. Airfield flattening is still applied once here
// so JSBSim, the rendered terrain and OSM2World scenery share one contact surface.
double SampleStage022TerrainMeters(double eastMeters, double northMeters) {
    const double gridX = (eastMeters - kFAStage022TerrainMinXMeters) /
        kFAStage022TerrainSpacingMeters;
    const double gridZ = (northMeters - kFAStage022TerrainMinZMeters) /
        kFAStage022TerrainSpacingMeters;

    if (gridX < 0.0 || gridZ < 0.0 ||
        gridX > static_cast<double>(kFAStage022TerrainResolutionX - 1) ||
        gridZ > static_cast<double>(kFAStage022TerrainResolutionZ - 1)) {
        return kFAStage022SeaLevelMeters - 24.0;
    }

    const int x0 = std::clamp(
        static_cast<int>(std::floor(gridX)),
        0,
        kFAStage022TerrainResolutionX - 1
    );
    const int z0 = std::clamp(
        static_cast<int>(std::floor(gridZ)),
        0,
        kFAStage022TerrainResolutionZ - 1
    );
    const int x1 = std::min(x0 + 1, kFAStage022TerrainResolutionX - 1);
    const int z1 = std::min(z0 + 1, kFAStage022TerrainResolutionZ - 1);
    const double tx = gridX - static_cast<double>(x0);
    const double tz = gridZ - static_cast<double>(z0);

    const auto sample = [](int x, int z) {
        const int index = z * kFAStage022TerrainResolutionX + x;
        return static_cast<double>(kFAStage022TerrainDecimeters[index]) * 0.1;
    };

    const double h00 = sample(x0, z0);
    const double h10 = sample(x1, z0);
    const double h01 = sample(x0, z1);
    const double h11 = sample(x1, z1);
    const double h0 = h00 + (h10 - h00) * tx;
    const double h1 = h01 + (h11 - h01) * tx;
    return h0 + (h1 - h0) * tz;
}

double TerrainHeightMeters(double eastMeters, double northMeters) {
    const double rawHeight = SampleStage022TerrainMeters(eastMeters, northMeters);

    // Full Authority's authored airbase sits over Luqa RWY 31. Keep the runway,
    // parallel taxiway and apron genuinely flat, then blend into Malta's real relief.
    const double dx = std::max(std::abs(eastMeters) - 900.0, 0.0);
    const double dz = std::max(std::abs(northMeters - 1800.0) - 2500.0, 0.0);
    const double distanceOutsideAirfield = std::hypot(dx, dz);
    const double terrainBlend = SmoothStep(distanceOutsideAirfield / 650.0);
    return rawHeight * terrainBlend;
}

class FATerrainGroundCallback final : public JSBSim::FGGroundCallback {
public:
    FATerrainGroundCallback(double semiMajor, double semiMinor)
        : a(semiMajor), b(semiMinor) {}

    double GetAGLevel(double,
                      const JSBSim::FGLocation& location,
                      JSBSim::FGLocation& contact,
                      JSBSim::FGColumnVector3& normal,
                      JSBSim::FGColumnVector3& velocity,
                      JSBSim::FGColumnVector3& angularVelocity) const override {
        velocity.InitMatrix();
        angularVelocity.InitMatrix();

        JSBSim::FGLocation local = location;
        local.SetEllipse(a, b);

        const double latitude = local.GetGeodLatitudeRad();
        const double longitude = local.GetLongitude();
        const double eastMeters = longitude * kEarthRadiusMeters;
        const double northMeters = latitude * kEarthRadiusMeters;
        const double heightMeters = TerrainHeightMeters(eastMeters, northMeters);

        const double dhde = (
            TerrainHeightMeters(eastMeters + kTerrainSampleMeters, northMeters) -
            TerrainHeightMeters(eastMeters - kTerrainSampleMeters, northMeters)
        ) / (2.0 * kTerrainSampleMeters);
        const double dhdn = (
            TerrainHeightMeters(eastMeters, northMeters + kTerrainSampleMeters) -
            TerrainHeightMeters(eastMeters, northMeters - kTerrainSampleMeters)
        ) / (2.0 * kTerrainSampleMeters);

        const double cosLat = std::cos(latitude);
        const double sinLat = std::sin(latitude);
        const double cosLon = std::cos(longitude);
        const double sinLon = std::sin(longitude);

        const JSBSim::FGColumnVector3 up(
            cosLat * cosLon,
            cosLat * sinLon,
            sinLat
        );
        const JSBSim::FGColumnVector3 east(
            -sinLon,
            cosLon,
            0.0
        );
        const JSBSim::FGColumnVector3 north(
            -sinLat * cosLon,
            -sinLat * sinLon,
            cosLat
        );

        normal = up - east * dhde - north * dhdn;
        normal.Normalize();

        contact.SetEllipse(a, b);
        contact.SetPositionGeodetic(
            longitude,
            latitude,
            heightMeters * kMetersToFeet
        );

        return local.GetGeodAltitude() - heightMeters * kMetersToFeet;
    }

private:
    double a;
    double b;
};
}

extern "C" double FATerrainHeightMeters(double eastMeters, double northMeters) {
    return TerrainHeightMeters(eastMeters, northMeters);
}

extern "C" double FATerrainSeaLevelMeters(void) {
    return kFAStage022SeaLevelMeters;
}

@interface FAJSBSimBridge ()
- (void)rebuildExecutive;
@end

@implementation FAJSBSimBridge {
    std::unique_ptr<JSBSim::FGFDMExec> _exec;
    BOOL _modelLoaded;
    NSString *_rootPath;
    double _deltaTime;
}

- (instancetype)initWithRootPath:(NSString *)rootPath {
    self = [super init];
    if (self) {
        _rootPath = [rootPath copy];
        _deltaTime = 1.0 / 120.0;
        [self rebuildExecutive];
    }
    return self;
}

- (void)rebuildExecutive {
    // A complete aircraft reset gets a complete JSBSim executive. That keeps
    // the inertial model, IC object, propulsion, FCS, property tree and custom
    // terrain callback on one coherent lifetime.
    _exec = std::make_unique<JSBSim::FGFDMExec>();
    _exec->SetRootDir(SGPath(std::string(_rootPath.UTF8String ?: "")));
    _exec->SetAircraftPath(SGPath("aircraft"));
    _exec->SetEnginePath(SGPath("engine"));
    _exec->SetSystemsPath(SGPath("systems"));
    _exec->Setdt(_deltaTime);

    auto inertial = _exec->GetInertial();
    if (inertial) {
        inertial->SetGroundCallback(new FATerrainGroundCallback(
            inertial->GetSemimajor(),
            inertial->GetSemiminor()
        ));
    }

    _modelLoaded = NO;
}

- (NSString *)version {
    if (!_exec) return @"unavailable";
    const std::string version = _exec->GetVersion();
    return [NSString stringWithUTF8String:version.c_str()] ?: @"unknown";
}

- (BOOL)isModelLoaded {
    return _modelLoaded;
}

- (double)deltaTime {
    return _exec ? _exec->GetDeltaT() : _deltaTime;
}

- (void)setDeltaTime:(double)deltaTime {
    if (deltaTime <= 0.0) return;
    _deltaTime = deltaTime;
    if (_exec) {
        _exec->Setdt(deltaTime);
    }
}

- (BOOL)loadModel:(NSString *)modelName error:(NSError **)error {
    try {
        [self rebuildExecutive];

        _modelLoaded = _exec->LoadModel(std::string(modelName.UTF8String), true);
        if (!_modelLoaded) {
            SetBridgeError(error, [NSString stringWithFormat:@"JSBSim could not load aircraft model '%@'.", modelName]);
        }
        return _modelLoaded;
    } catch (const std::exception& exception) {
        SetBridgeError(error, [NSString stringWithUTF8String:exception.what()] ?: @"JSBSim model load failed.");
        _modelLoaded = NO;
        return NO;
    }
}

- (BOOL)runInitialConditions:(NSError **)error {
    if (!_exec || !_modelLoaded) {
        SetBridgeError(error, @"No JSBSim aircraft model is loaded.");
        return NO;
    }

    try {
        const bool success = _exec->RunIC();
        if (!success) SetBridgeError(error, @"JSBSim rejected the initial conditions.");
        return success;
    } catch (const std::exception& exception) {
        SetBridgeError(error, [NSString stringWithUTF8String:exception.what()] ?: @"JSBSim initialization failed.");
        return NO;
    }
}

- (BOOL)trimFull:(NSError **)error {
    if (!_exec || !_modelLoaded) {
        SetBridgeError(error, @"No JSBSim aircraft model is loaded.");
        return NO;
    }

    try {
        JSBSim::FGTrim trim(_exec.get(), JSBSim::tFull);
        trim.SetGammaFallback(true);
        const bool success = trim.DoTrim();
        if (!success) {
            SetBridgeError(error, @"JSBSim could not find a full steady-flight trim for the requested condition.");
        }
        return success;
    } catch (const std::exception& exception) {
        SetBridgeError(error, [NSString stringWithUTF8String:exception.what()] ?: @"JSBSim trim failed.");
        return NO;
    }
}

- (BOOL)trimGround:(NSError **)error {
    if (!_exec || !_modelLoaded) {
        SetBridgeError(error, @"No JSBSim aircraft model is loaded.");
        return NO;
    }

    try {
        JSBSim::FGTrim trim(_exec.get(), JSBSim::tGround);
        const bool success = trim.DoTrim();
        if (!success) {
            SetBridgeError(error, @"JSBSim could not settle the aircraft on the ground.");
        }
        return success;
    } catch (const std::exception& exception) {
        SetBridgeError(error, [NSString stringWithUTF8String:exception.what()] ?: @"JSBSim ground trim failed.");
        return NO;
    }
}

- (BOOL)step:(NSError **)error {
    if (!_exec || !_modelLoaded) {
        SetBridgeError(error, @"No JSBSim aircraft model is loaded.");
        return NO;
    }

    try {
        const bool success = _exec->Run();
        if (!success) SetBridgeError(error, @"JSBSim stopped the simulation.");
        return success;
    } catch (const std::exception& exception) {
        SetBridgeError(error, [NSString stringWithUTF8String:exception.what()] ?: @"JSBSim step failed.");
        return NO;
    }
}

- (void)setProperty:(NSString *)property value:(double)value {
    if (!_exec) return;
    _exec->SetPropertyValue(std::string(property.UTF8String), value);
}

- (double)valueForProperty:(NSString *)property {
    if (!_exec) return 0.0;
    return _exec->GetPropertyValue(std::string(property.UTF8String));
}

@end
