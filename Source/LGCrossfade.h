// LGCrossfade.h : Apple Music-style equal-power crossfade engine (1-12s, default 6s).
// Preloads & sync-spins outgoing tail AVPlayer silently before fade point for zero-gap true Overlap,
// with automatic smart Dip fallback if stream URL is unavailable.
#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

typedef NS_ENUM(NSInteger, LGXfadeMode) { LGXfadeOff = 0, LGXfadeDip = 1, LGXfadeOverlap = 2 };

@interface LGCrossfade : NSObject
@property (class, readonly) LGCrossfade *shared;
@property (nonatomic, readonly) BOOL enabled;
@property (nonatomic, readonly) NSTimeInterval seconds;
@property (nonatomic, readonly) LGXfadeMode mode;
@property (nonatomic, readonly) NSString *status;
@property (nonatomic, assign) BOOL nativeMultiPlayerActive;
@property (nonatomic, copy) NSString *nativeStatusDetail;

// ---- adapters ----
@property (nonatomic, copy) void (^setNativeGain)(float gain);
@property (nonatomic, copy) BOOL (^advanceToNext)(void);
@property (nonatomic, copy) NSURL *(^currentStreamURL)(void);

// Input feeds: MPNowPlayingInfoCenter hook + live YTPlayerViewController time observer.
- (void)noteNowPlayingInfo:(NSDictionary *)info;
- (void)noteLiveTime:(double)elapsed total:(double)total trackID:(NSString *)trackID;
- (void)noteTrackActivated:(NSString *)trackID;
- (void)cancel;
@end
