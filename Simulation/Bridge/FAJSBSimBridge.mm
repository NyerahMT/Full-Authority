#import "FAJSBSimBridge.h"

#include <FGFDMExec.h>
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

@implementation FAJSBSimBridge {
    std::unique_ptr<JSBSim::FGFDMExec> _exec;
    BOOL _modelLoaded;
}

- (instancetype)initWithRootPath:(NSString *)rootPath {
    self = [super init];
    if (self) {
        _exec = std::make_unique<JSBSim::FGFDMExec>();
        _exec->SetRootDir(SGPath(std::string(rootPath.UTF8String)));
        _exec->SetAircraftPath(SGPath("aircraft"));
        _exec->SetEnginePath(SGPath("engine"));
        _exec->SetSystemsPath(SGPath("systems"));
        _exec->Setdt(1.0 / 120.0);
        _modelLoaded = NO;
    }
    return self;
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
    return _exec ? _exec->GetDeltaT() : 0.0;
}

- (void)setDeltaTime:(double)deltaTime {
    if (_exec && deltaTime > 0.0) {
        _exec->Setdt(deltaTime);
    }
}

- (BOOL)loadModel:(NSString *)modelName error:(NSError **)error {
    if (!_exec) {
        SetBridgeError(error, @"JSBSim executive is not available.");
        return NO;
    }

    try {
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
