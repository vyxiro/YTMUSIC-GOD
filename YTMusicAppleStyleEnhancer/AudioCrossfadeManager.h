#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface AudioCrossfadeManager : NSObject

@property (nonatomic, assign) BOOL crossfadeEnabled;
@property (nonatomic, assign) CGFloat crossfadeDuration; // 1.0 to 12.0 seconds (default: 5.0s)
@property (nonatomic, assign) BOOL lowNetworkBufferingEnabled; // Aggressive forward buffer & prefetching
@property (nonatomic, readonly) BOOL isCrossfading;

+ (instancetype)sharedInstance;

- (void)savePreferences;
- (void)loadPreferences;

// Player hook integration
- (void)registerActivePlayer:(AVPlayer *)player;
- (void)registerPlayerViewController:(id)playerVC;
- (void)didUpdatePlaybackTime:(NSTimeInterval)currentTime duration:(NSTimeInterval)duration;
- (void)willTransitionToNextTrack;
- (void)didStartNewTrackWithPlayer:(AVPlayer *)player;

// Low-network audio asset optimization
- (void)optimizePlayerItemForLowNetwork:(AVPlayerItem *)item;
- (void)prefetchUpcomingTrackURL:(nullable NSURL *)url;

@end

NS_ASSUME_NONNULL_END
