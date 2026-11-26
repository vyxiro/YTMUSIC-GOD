// LGCrossfade.m : Crash-free equal-power crossfade state machine.
// All AVPlayer creation/control and UI/queue advance happen exclusively on the main queue.
#import "LGCrossfade.h"
#import <MediaPlayer/MediaPlayer.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#include <math.h>

static inline double LGXClamp(double x, double lo, double hi) { return MAX(lo, MIN(hi, x)); }

@implementation LGCrossfade {
    dispatch_queue_t _q;
    dispatch_source_t _tick, _ramp;
    NSString *_key, *_liveTrackID, *_firedKey, *_prepKey, *_status;
    double _elapsed0, _rate, _total;
    CFTimeInterval _wall0, _fadeOutStartWall, _fadeInDeadline;
    BOOL _busy, _inDipFadeOut, _inOverlap, _needFadeIn, _incomingTrackActivated;

    // Main-thread only tail overlap player state:
    AVPlayer *_tail;
    BOOL _tailPreparing;
    BOOL _tailReady;
    NSString *_tailKey;
}

+ (LGCrossfade *)shared {
    static LGCrossfade *s;
    static dispatch_once_t o;
    dispatch_once(&o, ^{ s = [LGCrossfade new]; });
    return s;
}

- (instancetype)init {
    if ((self = [super init])) {
        _q = dispatch_queue_create("lg.xfade", DISPATCH_QUEUE_SERIAL);
        _status = @"idle";
    }
    return self;
}

- (BOOL)enabled {
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    id explicitVal = [d objectForKey:@"LG_xfade"];
    if (explicitVal) return [explicitVal boolValue];
    NSDictionary *ytmu = [d dictionaryForKey:@"YTMUltimate"];
    return ytmu[@"appleCrossfade"] ? [ytmu[@"appleCrossfade"] boolValue] : NO;
}

- (NSTimeInterval)seconds {
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    id v = [d objectForKey:@"LG_xfade_secs"];
    if (!v) {
        NSDictionary *ytmu = [d dictionaryForKey:@"YTMUltimate"];
        v = ytmu[@"appleCrossfadeDuration"];
    }
    return LGXClamp(v ? [v doubleValue] : 6.0, 1.0, 12.0);
}

- (LGXfadeMode)mode {
    if (!self.enabled || !self.setNativeGain) return LGXfadeOff;
    return (self.advanceToNext && self.currentStreamURL) ? LGXfadeOverlap : LGXfadeDip;
}

- (NSString *)status {
    NSString *st;
    @synchronized(self) { st = _status ?: @"idle"; }
    return [NSString stringWithFormat:@"Crossfade %@ (%.1fs) | gain %@  next %@  stream %@ | %@",
            @[@"off", @"dip", @"overlap"][self.mode],
            self.seconds,
            self.setNativeGain ? @"yes" : @"NO",
            self.advanceToNext ? @"yes" : @"NO",
            self.currentStreamURL ? @"yes" : @"NO",
            st];
}

- (void)setStatusText:(NSString *)s {
    @synchronized(self) { _status = [s copy]; }
}

- (void)applyGainMain:(float)gain {
    void (^setter)(float) = self.setNativeGain;
    if (!setter) return;
    if ([NSThread isMainThread]) {
        setter(gain);
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{
            setter(gain);
        });
    }
}

#pragma mark - Inputs

- (void)noteNowPlayingInfo:(NSDictionary *)info {
    if (![info isKindOfClass:NSDictionary.class]) return;
    NSString *title = info[MPMediaItemPropertyTitle] ?: @"";
    NSString *artist = info[MPMediaItemPropertyArtist] ?: @"";
    NSString *key = [NSString stringWithFormat:@"%@|%@", title, artist];
    if (key.length <= 1) return;

    double el = [info[MPNowPlayingInfoPropertyElapsedPlaybackTime] doubleValue];
    double tot = [info[MPMediaItemPropertyPlaybackDuration] doubleValue];
    NSNumber *rn = info[MPNowPlayingInfoPropertyPlaybackRate];
    double rate = rn ? rn.doubleValue : 1.0;

    dispatch_async(_q, ^{
        BOOL newTrack = (self->_key && ![key isEqualToString:self->_key]);
        self->_key = key;
        if (tot > 0) self->_total = tot;
        if (el >= 0) {
            self->_elapsed0 = el;
            self->_wall0 = CACurrentMediaTime();
        }
        self->_rate = rate;
        if (newTrack) {
            [self handleTrackChangedFromSource:@"MPNowPlaying"];
        } else if (self->_needFadeIn && el < 3.0 && rate > 0 && !self->_busy) {
            [self fadeInNative];
        } else if (rate <= 0 && !self->_busy && !self->_needFadeIn) {
            [self applyGainMain:1.0f];
        }
        [self startTick];
    });
}

- (void)noteLiveTime:(double)elapsed total:(double)total trackID:(NSString *)trackID {
    if (total <= 0 || elapsed < 0) return;
    dispatch_async(_q, ^{
        BOOL newID = (trackID.length > 0 && self->_liveTrackID && ![trackID isEqualToString:self->_liveTrackID]);
        if (trackID.length > 0) {
            self->_liveTrackID = trackID;
            if (!self->_key.length) self->_key = trackID;
        }
        self->_elapsed0 = elapsed;
        self->_total = total;
        self->_rate = 1.0;
        self->_wall0 = CACurrentMediaTime();
        if (newID) {
            [self handleTrackChangedFromSource:@"YTPlayerLive"];
        }
        [self startTick];
    });
}

- (void)noteTrackActivated:(NSString *)trackID {
    dispatch_async(_q, ^{
        self->_incomingTrackActivated = YES;
        BOOL newID = (trackID.length > 0 && ![trackID isEqualToString:self->_liveTrackID]);
        if (trackID.length > 0) self->_liveTrackID = trackID;
        if (self->_inOverlap) {
            // Track B just became active during overlap: let incoming sine gain rise normally
            return;
        }
        if (newID || self->_needFadeIn || self->_inDipFadeOut) {
            [self handleTrackChangedFromSource:@"TrackActivated"];
        }
    });
}

- (void)startTick {
    if (_tick) return;
    _tick = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, _q);
    dispatch_source_set_timer(_tick, DISPATCH_TIME_NOW, 100 * NSEC_PER_MSEC, 15 * NSEC_PER_MSEC);
    __weak LGCrossfade *w = self;
    dispatch_source_set_event_handler(_tick, ^{ [w evaluate]; });
    dispatch_resume(_tick);
}

#pragma mark - State Machine (serialized on _q)

- (NSString *)activeTrackToken {
    return _liveTrackID.length ? _liveTrackID : (_key ?: @"");
}

- (void)handleTrackChangedFromSource:(NSString *)src {
    // Ignore duplicate events within the active overlap ramp
    if (_inOverlap) {
        _incomingTrackActivated = YES;
        return;
    }

    // If a Dip fade-out was still winding down as Track B already started, seamlessly switch into Fade-In!
    if (_inDipFadeOut) {
        if (_ramp) { dispatch_source_cancel(_ramp); _ramp = nil; }
        _inDipFadeOut = NO;
        _busy = NO;
        _needFadeIn = YES;
    }

    if (_busy) return;
    if (_ramp) { dispatch_source_cancel(_ramp); _ramp = nil; }
    [self teardownTail];

    if (_needFadeIn) {
        [self fadeInNative];
    } else {
        [self applyGainMain:1.0f];
        [self setStatusText:@"idle"];
    }
}

- (void)evaluate {
    if (_needFadeIn && CACurrentMediaTime() > _fadeInDeadline) {
        _needFadeIn = NO;
        [self applyGainMain:1.0f];
        [self setStatusText:@"recovered (timeout)"];
    }
    if (!self.enabled || !self.setNativeGain || _rate <= 0 || _total <= 0 || _busy) return;

    double N = self.seconds;
    if (_total < 2 * N + 2) return;

    double elapsed = _elapsed0 + (CACurrentMediaTime() - _wall0) * _rate;
    double remaining = _total - elapsed;
    NSString *tok = [self activeTrackToken];

    if (remaining > N + 16.0) {
        _firedKey = nil;
        _prepKey = nil;
        if (_needFadeIn) [self fadeInNative];
        return;
    }

    // Preload outgoing tail AVPlayer ~ (N + 12s) before end when Overlap adapters are available
    if (remaining <= N + 14.0 && remaining > N + 1.0 &&
        self.mode == LGXfadeOverlap && ![_prepKey isEqualToString:tok]) {
        _prepKey = tok;
        double seekPos = MAX(0.0, _total - N - 1.5);
        [self prepareTailForTrack:tok seekTo:seekPos];
    }

    if (remaining <= N && remaining > 0.25 && ![_firedKey isEqualToString:tok]) {
        _firedKey = tok;
        [self fireTransitionWithRemaining:remaining trackToken:tok elapsed:elapsed];
    }
}

#pragma mark - Tail Preloader & Dual Transition (Main Thread Safe)

- (void)prepareTailForTrack:(NSString *)tok seekTo:(double)seekPos {
    NSURL *(^urlBlock)(void) = self.currentStreamURL;
    if (!urlBlock) return;
    __weak LGCrossfade *w = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        LGCrossfade *s = w;
        if (!s) return;
        NSURL *url = urlBlock();
        if (!url) {
            [s setStatusText:@"tail skipped (no stream URL, will dip)"];
            return;
        }
        [s teardownTailSyncOnMain];
        s->_tailPreparing = YES;
        s->_tailReady = NO;
        s->_tailKey = [tok copy];

        AVURLAsset *asset = [AVURLAsset URLAssetWithURL:url options:nil];
        AVPlayerItem *item = [AVPlayerItem playerItemWithAsset:asset];
        if (@available(iOS 10.0, *)) {
            item.preferredForwardBufferDuration = 30.0;
        }
        AVPlayer *p = [AVPlayer playerWithPlayerItem:item];
        objc_setAssociatedObject(p, "LGTailPlayer", @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        p.volume = 0.0f;
        p.muted = YES;
        [p pause];
        s->_tail = p;

        CMTime target = CMTimeMakeWithSeconds(seekPos, 600);
        CMTime tol = CMTimeMakeWithSeconds(0.5, 600);
        [p seekToTime:target toleranceBefore:tol toleranceAfter:tol completionHandler:^(BOOL finished) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (s->_tail == p) {
                    s->_tailPreparing = NO;
                    s->_tailReady = (finished && item.status != AVPlayerItemStatusFailed);
                    if (s->_tailReady) {
                        [s setStatusText:[NSString stringWithFormat:@"tail buffered @ %.1fs", seekPos]];
                    } else {
                        [s setStatusText:@"tail preload failed (will dip)"];
                    }
                }
            });
        }];
    });
}

- (void)fireTransitionWithRemaining:(double)remaining trackToken:(NSString *)tok elapsed:(double)elapsed {
    _busy = YES;
    double N = LGXClamp(remaining, 0.8, self.seconds);
    BOOL (^advanceBlock)(void) = self.advanceToNext;

    dispatch_async(dispatch_get_main_queue(), ^{
        BOOL canOverlap = (self->_tail && [self->_tailKey isEqualToString:tok] &&
                           self->_tailReady &&
                           self->_tail.currentItem.status == AVPlayerItemStatusReadyToPlay &&
                           advanceBlock != nil);

        if (canOverlap) {
            [self beginOverlapRampOnMain:N elapsed:elapsed advanceBlock:advanceBlock];
        } else {
            [self teardownTailSyncOnMain];
            dispatch_async(self->_q, ^{
                [self beginDipFadeOut:N];
            });
        }
    });
}

- (void)beginOverlapRampOnMain:(double)duration elapsed:(double)elapsed advanceBlock:(BOOL (^)(void))advanceBlock {
    AVPlayer *tail = _tail;
    if (!tail) {
        dispatch_async(_q, ^{ [self beginDipFadeOut:duration]; });
        return;
    }

    dispatch_async(_q, ^{
        self->_inOverlap = YES;
        self->_incomingTrackActivated = NO;
        [self setStatusText:@"crossfading (overlap)"];
    });

    CMTime exactPos = CMTimeMakeWithSeconds(MAX(0.0, elapsed), 600);
    CMTime tol = CMTimeMakeWithSeconds(0.2, 600);
    [tail seekToTime:exactPos toleranceBefore:tol toleranceAfter:tol completionHandler:^(__unused BOOL ok) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self->_tail != tail) return;
            tail.muted = NO;
            tail.volume = 1.0f;
            [tail play];

            // Mute outgoing native player cleanly, then trigger next track on main thread
            [self applyGainMain:0.0f];
            BOOL advanced = advanceBlock ? advanceBlock() : NO;
            if (!advanced) {
                // If advance failed, gracefully fall back to letting tail fade out
                [self setStatusText:@"overlap advance failed -> fade out"];
            }

            CFTimeInterval advanceStart = CACurrentMediaTime();
            dispatch_async(self->_q, ^{
                [self rampOver:duration step:^(double t) {
                    float outGain = (float)cos(t * M_PI_2);
                    float inGain = (self->_incomingTrackActivated || (CACurrentMediaTime() - advanceStart) > 0.45)
                        ? (float)sin(t * M_PI_2)
                        : 0.0f;
                    dispatch_async(dispatch_get_main_queue(), ^{
                        if (self->_tail == tail) tail.volume = outGain;
                    });
                    [self applyGainMain:inGain];
                } done:^{
                    [self applyGainMain:1.0f];
                    [self teardownTail];
                    self->_inOverlap = NO;
                    self->_needFadeIn = NO;
                    self->_busy = NO;
                    [self setStatusText:@"idle"];
                }];
            });
        });
    }];
}

- (void)beginDipFadeOut:(double)remaining {
    _inDipFadeOut = YES;
    _fadeOutStartWall = CACurrentMediaTime();
    [self setStatusText:@"fading out (dip)"];

    // Reserve a tiny margin so we reach ~0 right as track ends instead of 2s early silence
    double fadeDur = LGXClamp(remaining * 0.90, 0.5, self.seconds);
    BOOL (^advanceBlock)(void) = self.advanceToNext;
    __block BOOL didTriggerAdvance = NO;

    [self rampOver:fadeDur step:^(double t) {
        [self applyGainMain:(float)cos(t * M_PI_2)];
        // Trigger queue advance smoothly near the end of fade-out so Track B starts immediately with no long gap
        if (t >= 0.94 && !didTriggerAdvance && advanceBlock) {
            didTriggerAdvance = YES;
            dispatch_async(dispatch_get_main_queue(), ^{
                advanceBlock();
            });
        }
    } done:^{
        self->_inDipFadeOut = NO;
        [self applyGainMain:0.0f];
        self->_needFadeIn = YES;
        self->_fadeInDeadline = CACurrentMediaTime() + 12.0;
        self->_busy = NO;
        [self setStatusText:@"waiting for next track"];
    }];
}

- (void)fadeInNative {
    _needFadeIn = NO;
    _inDipFadeOut = NO;
    _busy = YES;
    [self setStatusText:@"fading in"];
    double inDur = LGXClamp(self.seconds * 0.55, 0.6, 3.5);
    [self rampOver:inDur step:^(double t) {
        [self applyGainMain:(float)sin(t * M_PI_2)];
    } done:^{
        [self applyGainMain:1.0f];
        self->_busy = NO;
        [self setStatusText:@"idle"];
    }];
}

- (void)rampOver:(NSTimeInterval)d step:(void (^)(double))step done:(void (^)(void))done {
    if (_ramp) dispatch_source_cancel(_ramp);
    CFTimeInterval t0 = CACurrentMediaTime();
    dispatch_source_t tm = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, _q);
    dispatch_source_set_timer(tm, DISPATCH_TIME_NOW, 20 * NSEC_PER_MSEC, 2 * NSEC_PER_MSEC);
    dispatch_source_set_event_handler(tm, ^{
        double t = MIN(1.0, (CACurrentMediaTime() - t0) / MAX(d, 0.05));
        if (step) step(t);
        if (t >= 1.0) {
            dispatch_source_cancel(tm);
            if (self->_ramp == tm) self->_ramp = nil;
            if (done) done();
        }
    });
    _ramp = tm;
    dispatch_resume(tm);
}

- (void)teardownTailSyncOnMain {
    AVPlayer *p = _tail;
    _tail = nil;
    _tailPreparing = NO;
    _tailReady = NO;
    _tailKey = nil;
    if (p) {
        @try {
            [p pause];
            [p replaceCurrentItemWithPlayerItem:nil];
        } @catch (__unused NSException *e) {}
    }
}

- (void)teardownTail {
    if ([NSThread isMainThread]) {
        [self teardownTailSyncOnMain];
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self teardownTailSyncOnMain];
        });
    }
}

- (void)cancel {
    dispatch_async(_q, ^{
        if (self->_ramp) {
            dispatch_source_cancel(self->_ramp);
            self->_ramp = nil;
        }
        [self teardownTail];
        self->_busy = NO;
        self->_inOverlap = NO;
        self->_inDipFadeOut = NO;
        self->_needFadeIn = NO;
        [self applyGainMain:1.0f];
        [self setStatusText:@"idle"];
    });
}

@end
