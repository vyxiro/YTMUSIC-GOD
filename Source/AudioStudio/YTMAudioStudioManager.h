#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface YTMAudioStudioManager : NSObject

+ (instancetype)sharedManager;

@property (nonatomic, assign, getter=isEnabled) BOOL enabled;
@property (nonatomic, assign) BOOL adaptiveLoudnessEnabled;
@property (nonatomic, copy, readonly) NSArray<NSString *> *presetNames;
@property (nonatomic, copy, readonly) NSString *selectedPresetName;
@property (nonatomic, readonly) float preampOffsetDB;
@property (nonatomic, readonly) BOOL limiterEnabled;
@property (nonatomic, readonly) AVAudioUnitEQ *equalizer;

- (float)gainForBand:(NSUInteger)band;
- (float)frequencyForBand:(NSUInteger)band;
- (float)qForBand:(NSUInteger)band;
- (BOOL)isBandBypassed:(NSUInteger)band;
- (void)setGain:(float)gain forBand:(NSUInteger)band;
- (void)setFrequency:(float)frequency q:(float)q forBand:(NSUInteger)band;
- (void)setBandBypassed:(BOOL)bypassed forBand:(NSUInteger)band;
- (void)selectPresetNamed:(NSString *)name;
- (BOOL)importAutoEqProfileFromText:(NSString *)text error:(NSError **)error;
- (void)applyHearingThresholds:(NSDictionary<NSString *, NSNumber *> *)thresholds;
- (NSArray<NSString *> *)outputRouteNames;
- (NSString *)presetNameForCurrentRoute;
- (nullable NSString *)presetNameForRoute:(NSString *)route;
- (void)setPresetName:(NSString *)presetName forRoute:(NSString *)route;
- (void)refreshRoutePreset;
- (void)saveSettings;

@end

NS_ASSUME_NONNULL_END
