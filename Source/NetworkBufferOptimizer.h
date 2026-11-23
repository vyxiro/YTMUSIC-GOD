#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface NetworkBufferOptimizer : NSObject

@property (nonatomic, assign) BOOL deepBufferEnabled; // 120s buffer window
@property (nonatomic, assign) BOOL prefetchNextEnabled; // Pre-cache next 1-2 tracks at 15% playhead

+ (instancetype)sharedInstance;

- (void)loadSettings;
- (void)saveSettings;

// Streaming & player buffer tuning
- (void)optimizePlayerItem:(AVPlayerItem *)item;
- (void)tuneSessionConfiguration:(NSURLSessionConfiguration *)config;

// Real-time playhead monitoring for 15% threshold pre-fetch
- (void)trackProgressDidChangeCurrent:(NSTimeInterval)current total:(NSTimeInterval)total;
- (void)notifyNewTrackLoadedWithVideoID:(nullable NSString *)videoID;
- (void)prefetchUpcomingTrackURL:(nullable NSURL *)streamURL videoID:(nullable NSString *)videoID;

// Cache maintenance
- (NSString *)formattedCacheSize;
- (void)clearCache;

@end

NS_ASSUME_NONNULL_END
