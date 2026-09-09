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
#include <exception>
#include <memory>
#include <string>

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

// This function is intentionally mirrored in Stage2TerrainProfile on the Swift
// side. JSBSim owns contact with the mathematical surface; RealityKit renders
// the same surface so the airplane can no longer fly through decorative hills.
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
        const double heightMeters = FATerrainHeightMeters(eastMeters, northMeters);

        const double dhde = (
            FATerrainHeightMeters(eastMeters + kTerrainSampleMeters, northMeters) -
            FATerrainHeightMeters(eastMeters - kTerrainSampleMeters, northMeters)
        ) / (2.0 * kTerrainSampleMeters);
        const double dhdn = (
            FATerrainHeightMeters(eastMeters, northMeters + kTerrainSampleMeters) -
            FATerrainHeightMeters(eastMeters, northMeters - kTerrainSampleMeters)
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
    // Stage 023 single source of truth. RealityKit calls this exact function
    // through the Swift bridging header, and JSBSim's ground callback calls it
    // directly. There is no second approximated terrain formula anymore.
    double base =
        78.0 * std::sin(northMeters / 2750.0) * std::cos(eastMeters / 3500.0) +
        52.0 * std::sin((eastMeters + northMeters) / 1820.0) +
        36.0 * std::cos((eastMeters - 0.45 * northMeters) / 2250.0) +
        19.0 * std::sin((1.25 * eastMeters + 0.72 * northMeters) / 820.0) +
        12.0 * std::cos((0.65 * eastMeters - 1.10 * northMeters) / 510.0) +
        6.5 * std::sin((1.80 * eastMeters + 1.35 * northMeters) / 285.0);

    const double ridge1East = (eastMeters + 6500.0) / 2350.0;
    const double ridge1North = (northMeters - 9000.0) / 3300.0;
    base += 245.0 * std::exp(-0.5 * (ridge1East * ridge1East + ridge1North * ridge1North));

    const double ridge2East = (eastMeters - 7200.0) / 2500.0;
    const double ridge2North = (northMeters - 6500.0) / 2750.0;
    base += 185.0 * std::exp(-0.5 * (ridge2East * ridge2East + ridge2North * ridge2North));

    const double ridge3East = (eastMeters + 10500.0) / 3200.0;
    const double ridge3North = (northMeters + 2500.0) / 2600.0;
    base += 210.0 * std::exp(-0.5 * (ridge3East * ridge3East + ridge3North * ridge3North));

    const double valleyEast = (eastMeters - 4200.0) / 2300.0;
    const double valleyNorth = (northMeters - 9800.0) / 5000.0;
    base -= 92.0 * std::exp(-0.5 * (valleyEast * valleyEast + valleyNorth * valleyNorth));

    const double dx = std::max(std::abs(eastMeters) - 1000.0, 0.0);
    const double dz = std::max(std::abs(northMeters - 2000.0) - 3600.0, 0.0);
    const double distanceOutsideAirfield = std::hypot(dx, dz);
    const double terrainBlend = SmoothStep(distanceOutsideAirfield / 1250.0);
    return base * terrainBlend;
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
