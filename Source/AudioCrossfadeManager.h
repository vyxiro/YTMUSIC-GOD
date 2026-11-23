#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface AudioCrossfadeManager : NSObject

@property (nonatomic, assign) BOOL crossfadeEnabled;
@property (nonatomic, assign) CGFloat crossfadeDuration; // 1.0s to 12.0s (default: 5.0s)
@property (nonatomic, assign) BOOL gaplessBypassEnabled;
@property (nonatomic, readonly) BOOL isCrossfading;
@property (nonatomic, readonly) BOOL isManualSkip;

+ (instancetype)sharedInstance;

- (void)loadSettings;
- (void)saveSettings;

// Player lifecycle & observation
- (void)registerActivePlayer:(AVPlayer *)player;
- (void)registerPlayerViewController:(id)playerVC;
- (void)didUpdatePlaybackTime:(NSTimeInterval)currentTime duration:(NSTimeInterval)duration;
- (void)notifyManualSkipOccurred;
- (void)notifyTrackActivatedWithVideoID:(nullable NSString *)videoID player:(nullable AVPlayer *)player;
- (void)resetFaders;

@end

NS_ASSUME_NONNULL_END
