#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Thin Objective-C++ boundary around JSBSim. Swift should never need to know
/// about JSBSim's C++ types or coordinate conventions directly.
@interface FAJSBSimBridge : NSObject

@property (nonatomic, readonly, copy) NSString *version;
@property (nonatomic, readonly, getter=isModelLoaded) BOOL modelLoaded;
@property (nonatomic, readonly) double deltaTime;

- (instancetype)initWithRootPath:(NSString *)rootPath;
- (void)setDeltaTime:(double)deltaTime;
- (BOOL)loadModel:(NSString *)modelName error:(NSError * _Nullable * _Nullable)error;
- (BOOL)runInitialConditions:(NSError * _Nullable * _Nullable)error;
- (BOOL)trimFull:(NSError * _Nullable * _Nullable)error;
- (BOOL)step:(NSError * _Nullable * _Nullable)error;
- (void)setProperty:(NSString *)property value:(double)value;
- (double)valueForProperty:(NSString *)property;

@end

NS_ASSUME_NONNULL_END
