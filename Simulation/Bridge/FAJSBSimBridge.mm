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
#include <cstdint>
#include <fstream>
#include <vector>
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

class FATerrainGrid;
extern FATerrainGrid gTerrainGrid;
extern "C" double FATerrainHeightMeters(double eastMeters, double northMeters);

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

struct FATerrainGrid {
    bool loaded = false;
    uint32_t width = 0;
    uint32_t height = 0;
    float cell = 50.0f;
    float minX = 0.0f;
    float minZ = 0.0f;
    float referenceElevation = 0.0f;
    std::vector<float> samples;

    bool Load(const std::string& path) {
        std::ifstream stream(path, std::ios::binary);
        if (!stream) return false;
        char magic[4] = {};
        uint32_t version = 0;
        stream.read(magic, 4);
        stream.read(reinterpret_cast<char*>(&version), sizeof(version));
        stream.read(reinterpret_cast<char*>(&width), sizeof(width));
        stream.read(reinterpret_cast<char*>(&height), sizeof(height));
        stream.read(reinterpret_cast<char*>(&cell), sizeof(cell));
        stream.read(reinterpret_cast<char*>(&minX), sizeof(minX));
        stream.read(reinterpret_cast<char*>(&minZ), sizeof(minZ));
        stream.read(reinterpret_cast<char*>(&referenceElevation), sizeof(referenceElevation));
        if (!stream || std::string(magic, 4) != "FAM2" || version != 1 || width < 2 || height < 2 || cell <= 0.0f) {
            loaded = false;
            return false;
        }
        samples.resize(static_cast<size_t>(width) * static_cast<size_t>(height));
        stream.read(reinterpret_cast<char*>(samples.data()), static_cast<std::streamsize>(samples.size() * sizeof(float)));
        loaded = static_cast<bool>(stream);
        return loaded;
    }

    double Height(double eastMeters, double northMeters) const {
        if (!loaded || samples.empty()) return 0.0;
        const double gx = (eastMeters - minX) / cell;
        const double gz = (northMeters - minZ) / cell;
        const int ix = std::clamp(static_cast<int>(std::floor(gx)), 0, static_cast<int>(width) - 2);
        const int iz = std::clamp(static_cast<int>(std::floor(gz)), 0, static_cast<int>(height) - 2);
        const double tx = std::clamp(gx - ix, 0.0, 1.0);
        const double tz = std::clamp(gz - iz, 0.0, 1.0);
        const size_t i00 = static_cast<size_t>(iz) * width + static_cast<size_t>(ix);
        const size_t i10 = i00 + 1;
        const size_t i01 = static_cast<size_t>(iz + 1) * width + static_cast<size_t>(ix);
        const size_t i11 = i01 + 1;
        const double h00 = samples[i00];
        const double h10 = samples[i10];
        const double h01 = samples[i01];
        const double h11 = samples[i11];
        if (tx + tz <= 1.0) {
            return h00 + tx * (h10 - h00) + tz * (h01 - h00);
        }
        return h11 + (1.0 - tz) * (h10 - h11) + (1.0 - tx) * (h01 - h11);
    }
};

FATerrainGrid gTerrainGrid;

extern "C" double FATerrainHeightMeters(double eastMeters, double northMeters) {
    return gTerrainGrid.Height(eastMeters, northMeters);
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
        // Stage 024 benchmark ground is derived from the same City of Helsinki
        // reality mesh rendered by RealityKit. It is terrain-only and intentionally
        // ignores scanned rooftops/vehicles so JSBSim does not collide with scenery.
        const std::string terrainPath = std::string(_rootPath.UTF8String ?: "") + "/visuals/world/helsinki/helsinki_ground.bin";
        gTerrainGrid.Load(terrainPath);
        [self rebuildExecutive];
    }
    return self;
}

- (void)rebuildExecutive {
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
