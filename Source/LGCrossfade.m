// LGCrossfade.m : Equal-power crossfade state machine (main-thread safe gain dispatching).
#import "LGCrossfade.h"
#import <MediaPlayer/MediaPlayer.h>
#import <QuartzCore/QuartzCore.h>
#include <math.h>

static inline double LGXClamp(double x, double lo, double hi) { return MAX(lo, MIN(hi, x)); }

@implementation LGCrossfade {
    dispatch_queue_t _q;
    dispatch_source_t _tick, _ramp;
    NSString *_key, *_firedKey, *_prepKey, *_status;
    double _elapsed0, _rate, _total;
    CFTimeInterval _wall0;
    BOOL _busy, _needFadeIn;
    CFTimeInterval _fadeInDeadline;
    AVPlayer *_tail;
    int _tailStage;
    double _tailSeekPos;
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
    return (self.advanceToNext && self.currentTrackAsset) ? LGXfadeOverlap : LGXfadeDip;
}

- (NSString *)status {
    NSString *st;
    @synchronized(self) { st = _status ?: @"idle"; }
    return [NSString stringWithFormat:@"Crossfade %@ | gain %@  next %@  track URL %@ | %@",
            @[@"off", @"dip (no overlap)", @"overlap"][self.mode],
            self.setNativeGain ? @"yes" : @"NO",
            self.advanceToNext ? @"yes" : @"NO",
            self.currentTrackAsset ? @"yes" : @"NO",
            st];
}

- (void)setStatusText:(NSString *)s {
    @synchronized(self) { _status = [s copy]; }
}

- (void)applyGainSafe:(float)gain {
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

#pragma mark - input

- (void)noteNowPlayingInfo:(NSDictionary *)info {
    if (![info isKindOfClass:NSDictionary.class]) return;
    NSString *key = [NSString stringWithFormat:@"%@|%@", info[MPMediaItemPropertyTitle] ?: @"", info[MPMediaItemPropertyArtist] ?: @""];
    double el = [info[MPNowPlayingInfoPropertyElapsedPlaybackTime] doubleValue];
    double tot = [info[MPMediaItemPropertyPlaybackDuration] doubleValue];
    NSNumber *rn = info[MPNowPlayingInfoPropertyPlaybackRate];
    double rate = rn ? rn.doubleValue : 1.0;
    dispatch_async(_q, ^{
        BOOL newTrack = ![key isEqualToString:self->_key];
        self->_key = key;
        self->_elapsed0 = el;
        self->_total = tot;
        self->_rate = rate;
        self->_wall0 = CACurrentMediaTime();
        if (newTrack) {
            [self onNewTrack];
        } else if (self->_needFadeIn && el < 3.0 && rate > 0 && !self->_busy) {
            [self fadeInNative];
        } else if (rate <= 0 && !self->_busy && !self->_needFadeIn) {
            [self applyGainSafe:1.0f];
        }
        [self startTick];
    });
}

- (void)startTick {
    if (_tick) return;
    _tick = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, _q);
    dispatch_source_set_timer(_tick, DISPATCH_TIME_NOW, 50 * NSEC_PER_MSEC, 5 * NSEC_PER_MSEC);
    __weak LGCrossfade *w = self;
    dispatch_source_set_event_handler(_tick, ^{ [w evaluate]; });
    dispatch_resume(_tick);
}

#pragma mark - state machine (all on _q)

- (void)onNewTrack {
    if (_busy) return;
    if (_ramp) { dispatch_source_cancel(_ramp); _ramp = nil; }
    [self teardownTail];
    if (_needFadeIn) [self fadeInNative];
    else [self applyGainSafe:1.0f];
}

- (void)evaluate {
    if (_needFadeIn && CACurrentMediaTime() > _fadeInDeadline) {
        _needFadeIn = NO;
        [self applyGainSafe:1.0f];
        [self setStatusText:@"recovered (next track timeout)"];
    }
    if (!self.enabled || !self.setNativeGain || _rate <= 0 || _total <= 0 || _busy) return;
    double N = self.seconds;
    if (_total < 2 * N + 2) return;
    double elapsed = _elapsed0 + (CACurrentMediaTime() - _wall0) * _rate;
    double remaining = _total - elapsed;
    if (remaining > N + 5) {
        _firedKey = nil;
        _prepKey = nil;
        if (_needFadeIn) [self fadeInNative];
        return;
    }
    if (remaining <= N && remaining > 0.15 && ![_firedKey isEqualToString:_key]) {
        [self fireDip:remaining];
    }
}

- (void)fireDip:(double)remaining {
    _firedKey = _key;
    _busy = YES;
    [self setStatusText:@"fading out"];
    [self rampOver:LGXClamp(remaining, 0.5, self.seconds) step:^(double t) {
        [self applyGainSafe:(float)cos(t * M_PI_2)];
    } done:^{
        [self applyGainSafe:0.0f];
        self->_needFadeIn = YES;
        self->_fadeInDeadline = CACurrentMediaTime() + 15.0;
        self->_busy = NO;
        [self setStatusText:@"waiting for next track"];
    }];
}

- (void)fadeInNative {
    _needFadeIn = NO;
    _busy = YES;
    [self setStatusText:@"fading in"];
    [self rampOver:LGXClamp(self.seconds / 2.0, 0.5, 3.0) step:^(double t) {
        [self applyGainSafe:(float)sin(t * M_PI_2)];
    } done:^{
        [self applyGainSafe:1.0f];
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
            if (done) done();
        }
    });
    _ramp = tm;
    dispatch_resume(tm);
}

- (void)teardownTail {
    AVPlayer *p = _tail;
    _tail = nil;
    _tailStage = 0;
    if (p) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [p pause];
            [p replaceCurrentItemWithPlayerItem:nil];
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
        self->_needFadeIn = NO;
        [self applyGainSafe:1.0f];
        [self setStatusText:@"idle"];
    });
}

@end
