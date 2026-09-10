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
#include <fstream>
#include <memory>
#include <string>
#include <vector>

namespace {
NSString * const FAJSBSimErrorDomain = @"com.nyerahworks.FullAuthority.JSBSim";

constexpr double kMetersToFeet = 3.280839895013123;
constexpr double kEarthRadiusMeters = 6371000.0;
constexpr double kTerrainNormalSampleMeters = 24.0;

// Fixed Worldsmith seed-1337 theater. The source artwork/heightfield is authored
// offline; the app only samples the baked 1025^2 RAW16 asset shipped in JSBSim.
constexpr int kWorldsmithResolution = 1025;
constexpr double kWorldsmithTheaterMeters = 150000.0;
constexpr double kWorldsmithSiteU = 0.3712567;
constexpr double kWorldsmithSiteV = 0.4103772;
constexpr double kWorldsmithMapHeadingRadians = 1.038470904936626; // 59.5 deg
constexpr double kWorldsmithRunwayCenterNorthMeters = 1800.0;
constexpr double kWorldsmithBaselineNormalized = 0.49768830303526773;
constexpr double kWorldsmithSeaLevelNormalized = 0.465;
constexpr double kWorldsmithVerticalScaleMeters = 4500.0;
constexpr double kOutsideMapNormalized = kWorldsmithSeaLevelNormalized - 0.14;

std::vector<uint16_t> gWorldsmithTerrain;

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

bool LoadWorldsmithTerrain(const std::string& rootPath) {
    constexpr std::size_t expectedSamples =
        static_cast<std::size_t>(kWorldsmithResolution) * kWorldsmithResolution;
    if (gWorldsmithTerrain.size() == expectedSamples) return true;

    std::string path = rootPath;
    if (!path.empty() && path.back() != '/') path.push_back('/');
    path += "visuals/world/worldsmith_1337_height_1025.r16";

    std::ifstream file(path, std::ios::binary | std::ios::ate);
    if (!file) return false;

    const std::streamsize byteCount = file.tellg();
    const std::streamsize expectedBytes =
        static_cast<std::streamsize>(expectedSamples * sizeof(uint16_t));
    if (byteCount != expectedBytes) return false;

    file.seekg(0, std::ios::beg);
    std::vector<uint8_t> bytes(static_cast<std::size_t>(byteCount));
    if (!file.read(reinterpret_cast<char *>(bytes.data()), byteCount)) return false;

    gWorldsmithTerrain.resize(expectedSamples);
    for (std::size_t i = 0; i < expectedSamples; ++i) {
        const std::size_t offset = i * 2;
        gWorldsmithTerrain[i] = static_cast<uint16_t>(bytes[offset]) |
            (static_cast<uint16_t>(bytes[offset + 1]) << 8);
    }
    return true;
}

bool WorldsmithTerrainReady() {
    return gWorldsmithTerrain.size() ==
        static_cast<std::size_t>(kWorldsmithResolution) * kWorldsmithResolution;
}

void WorldToMapUV(double eastMeters, double northMeters, double& u, double& v) {
    const double localNorth = northMeters - kWorldsmithRunwayCenterNorthMeters;
    const double c = std::cos(kWorldsmithMapHeadingRadians);
    const double s = std::sin(kWorldsmithMapHeadingRadians);

    // Rotate Full Authority's +Z runway direction onto the selected valley in
    // the authored map. Map north is up, while image V increases downward.
    const double mapEast = c * eastMeters + s * localNorth;
    const double mapNorth = -s * eastMeters + c * localNorth;
    u = kWorldsmithSiteU + mapEast / kWorldsmithTheaterMeters;
    v = kWorldsmithSiteV - mapNorth / kWorldsmithTheaterMeters;
}

double SampleWorldsmithNormalized(double eastMeters, double northMeters) {
    if (!WorldsmithTerrainReady()) return kWorldsmithBaselineNormalized;

    double u = 0.0;
    double v = 0.0;
    WorldToMapUV(eastMeters, northMeters, u, v);
    if (u < 0.0 || v < 0.0 || u > 1.0 || v > 1.0) {
        return kOutsideMapNormalized;
    }

    const double gridX = u * static_cast<double>(kWorldsmithResolution - 1);
    const double gridY = v * static_cast<double>(kWorldsmithResolution - 1);
    const int x0 = std::clamp(static_cast<int>(std::floor(gridX)), 0, kWorldsmithResolution - 1);
    const int y0 = std::clamp(static_cast<int>(std::floor(gridY)), 0, kWorldsmithResolution - 1);
    const int x1 = std::min(x0 + 1, kWorldsmithResolution - 1);
    const int y1 = std::min(y0 + 1, kWorldsmithResolution - 1);
    const double tx = gridX - static_cast<double>(x0);
    const double ty = gridY - static_cast<double>(y0);

    const auto sample = [](int x, int y) {
        const std::size_t index = static_cast<std::size_t>(y) * kWorldsmithResolution + x;
        return static_cast<double>(gWorldsmithTerrain[index]) / 65535.0;
    };

    const double h00 = sample(x0, y0);
    const double h10 = sample(x1, y0);
    const double h01 = sample(x0, y1);
    const double h11 = sample(x1, y1);
    const double h0 = h00 + (h10 - h00) * tx;
    const double h1 = h01 + (h11 - h01) * tx;
    return h0 + (h1 - h0) * ty;
}

double TerrainHeightMeters(double eastMeters, double northMeters) {
    const double normalized = SampleWorldsmithNormalized(eastMeters, northMeters);
    const double rawHeight =
        (normalized - kWorldsmithBaselineNormalized) * kWorldsmithVerticalScaleMeters;

    // Keep the sortie airfield genuinely flat, then blend back into the selected
    // valley. JSBSim and RealityKit both call this function, so wheels, runway
    // visuals and terrain remain on exactly one contact surface.
    const double dx = std::max(std::abs(eastMeters) - 900.0, 0.0);
    const double dz = std::max(
        std::abs(northMeters - kWorldsmithRunwayCenterNorthMeters) - 2500.0,
        0.0
    );
    const double distanceOutsideAirfield = std::hypot(dx, dz);
    const double terrainBlend = SmoothStep(distanceOutsideAirfield / 750.0);
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
            TerrainHeightMeters(eastMeters + kTerrainNormalSampleMeters, northMeters) -
            TerrainHeightMeters(eastMeters - kTerrainNormalSampleMeters, northMeters)
        ) / (2.0 * kTerrainNormalSampleMeters);
        const double dhdn = (
            TerrainHeightMeters(eastMeters, northMeters + kTerrainNormalSampleMeters) -
            TerrainHeightMeters(eastMeters, northMeters - kTerrainNormalSampleMeters)
        ) / (2.0 * kTerrainNormalSampleMeters);

        const double cosLat = std::cos(latitude);
        const double sinLat = std::sin(latitude);
        const double cosLon = std::cos(longitude);
        const double sinLon = std::sin(longitude);

        const JSBSim::FGColumnVector3 up(cosLat * cosLon, cosLat * sinLon, sinLat);
        const JSBSim::FGColumnVector3 east(-sinLon, cosLon, 0.0);
        const JSBSim::FGColumnVector3 north(-sinLat * cosLon, -sinLat * sinLon, cosLat);

        normal = up - east * dhde - north * dhdn;
        normal.Normalize();

        contact.SetEllipse(a, b);
        contact.SetPositionGeodetic(longitude, latitude, heightMeters * kMetersToFeet);
        return local.GetGeodAltitude() - heightMeters * kMetersToFeet;
    }

private:
    double a;
    double b;
};
} // namespace

extern "C" double FATerrainHeightMeters(double eastMeters, double northMeters) {
    return TerrainHeightMeters(eastMeters, northMeters);
}

extern "C" double FATerrainSeaLevelMeters(void) {
    return (kWorldsmithSeaLevelNormalized - kWorldsmithBaselineNormalized) *
        kWorldsmithVerticalScaleMeters;
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
    (void)LoadWorldsmithTerrain(std::string(_rootPath.UTF8String ?: ""));

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

- (BOOL)isModelLoaded { return _modelLoaded; }
- (double)deltaTime { return _exec ? _exec->GetDeltaT() : _deltaTime; }

- (void)setDeltaTime:(double)deltaTime {
    if (deltaTime <= 0.0) return;
    _deltaTime = deltaTime;
    if (_exec) _exec->Setdt(deltaTime);
}

- (BOOL)loadModel:(NSString *)modelName error:(NSError **)error {
    if (!WorldsmithTerrainReady()) {
        SetBridgeError(error, @"The fixed Worldsmith terrain asset is missing or invalid.");
        _modelLoaded = NO;
        return NO;
    }

    try {
        [self rebuildExecutive];
        if (!WorldsmithTerrainReady()) {
            SetBridgeError(error, @"The fixed Worldsmith terrain asset could not be loaded.");
            _modelLoaded = NO;
            return NO;
        }
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
        if (!success) SetBridgeError(error, @"JSBSim could not find a full steady-flight trim for the requested condition.");
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
        if (!success) SetBridgeError(error, @"JSBSim could not settle the aircraft on the ground.");
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
    if (_exec) _exec->SetPropertyValue(std::string(property.UTF8String), value);
}

- (double)valueForProperty:(NSString *)property {
    if (!_exec) return 0.0;
    return _exec->GetPropertyValue(std::string(property.UTF8String));
}

@end
