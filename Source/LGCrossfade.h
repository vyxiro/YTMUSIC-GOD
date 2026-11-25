// LGCrossfade.h : Apple Music-style crossfade engine (equal-power, 1-12 s, default 6 s).
// Settings keys: LG_xfade (BOOL), LG_xfade_secs (double 1...12, default 6).
#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

typedef NS_ENUM(NSInteger, LGXfadeMode) { LGXfadeOff = 0, LGXfadeDip = 1, LGXfadeOverlap = 2 };

@interface LGCrossfade : NSObject
@property (class, readonly) LGCrossfade *shared;
@property (nonatomic, readonly) BOOL enabled;
@property (nonatomic, readonly) NSTimeInterval seconds;
@property (nonatomic, readonly) LGXfadeMode mode;
@property (nonatomic, readonly) NSString *status;     // for a live status row in Settings

// ---- adapters. All are called on a background queue: hop to main yourself if needed. ----
@property (nonatomic, copy) void (^setNativeGain)(float gain);
@property (nonatomic, copy) BOOL (^advanceToNext)(void);
@property (nonatomic, copy) AVURLAsset *(^currentTrackAsset)(void);

// Call from the MPNowPlayingInfoCenter hook (LGHooks.x). The engine extrapolates elapsed time itself.
- (void)noteNowPlayingInfo:(NSDictionary *)info;
- (void)cancel;                                       // restore gain, stop ramps, drop the tail player
@end
