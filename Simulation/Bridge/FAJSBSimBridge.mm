#import "FAJSBSimBridge.h"

// Xcode's Debug configuration defines DEBUG=1, while JSBSim uses DEBUG as an
// enum member (LogLevel::DEBUG). Keep that app-level macro out of this C++
// translation unit before including JSBSim headers.
#ifdef DEBUG
#undef DEBUG
#endif

#include <FGFDMExec.h>
#include <initialization/FGTrim.h>
#include <simgear/misc/sg_path.hxx>

#include <exception>
#include <memory>
#include <string>

namespace {
NSString * const FAJSBSimErrorDomain = @"com.nyerahworks.FullAuthority.JSBSim";

void SetBridgeError(NSError **error, NSString *message) {
    if (!error) return;
    *error = [NSError errorWithDomain:FAJSBSimErrorDomain
                                 code:1
                             userInfo:@{NSLocalizedDescriptionKey: message}];
}
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
    // FGFDMExec::LoadModel is fine for an initial model load, but reusing the
    // same executive for a full aircraft reload can leave FGInitialCondition
    // holding references into models that were torn down by the previous load.
    // Always rebuild the executive for an explicit aircraft load/restart so the
    // inertial model, IC object, propulsion, FCS and property tree share one
    // clean lifetime.
    _exec = std::make_unique<JSBSim::FGFDMExec>();
    _exec->SetRootDir(SGPath(std::string(_rootPath.UTF8String ?: "")));
    _exec->SetAircraftPath(SGPath("aircraft"));
    _exec->SetEnginePath(SGPath("engine"));
    _exec->SetSystemsPath(SGPath("systems"));
    _exec->Setdt(_deltaTime);
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
        // A model load is a complete simulation reset. Recreate FGFDMExec first
        // instead of asking a previously initialized executive to replace its
        // aircraft graph in place.
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
