// LGCrossfade.m : Apple Music-style equal-power Overlap + Smart Dip crossfade state machine.
// Pre-buffers & silent-sync-spins outgoing AVPlayer tail (~16s before fade), unmutes at fade start,
// advances native queue to incoming track, and mixes both streams with equal-power cos/sin curves.
#import "LGCrossfade.h"
#import <MediaPlayer/MediaPlayer.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#include <math.h>

static inline double LGXClamp(double x, double lo, double hi) { return MAX(lo, MIN(hi, x)); }

@implementation LGCrossfade {
    dispatch_queue_t _q;
    dispatch_source_t _tick, _ramp;
    NSString *_key, *_liveTrackID, *_firedKey, *_prepKey, *_syncKey, *_status;
    double _elapsed0, _rate, _total;
    CFTimeInterval _wall0, _fadeInDeadline;
    BOOL _busy, _inDipFadeOut, _inOverlap, _needFadeIn, _incomingTrackActivated;

    // Main-thread only tail overlap player state:
    AVPlayer *_tail;
    BOOL _tailReady;
    BOOL _tailSpinning;
    NSString *_tailKey;
    NSString *_tailStreamKind;
    BOOL _nativeMultiPlayerActive;
    NSString *_nativeStatusDetail;
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
        _tailStreamKind = @"none";
        _nativeStatusDetail = @"initializing";
    }
    return self;
}

- (void)setNativeMultiPlayerActive:(BOOL)active {
    @synchronized(self) { _nativeMultiPlayerActive = active; }
}

- (BOOL)nativeMultiPlayerActive {
    @synchronized(self) { return _nativeMultiPlayerActive; }
}

- (void)setNativeStatusDetail:(NSString *)detail {
    @synchronized(self) { _nativeStatusDetail = [detail copy]; }
}

- (NSString *)nativeStatusDetail {
    @synchronized(self) { return _nativeStatusDetail ?: @"ready"; }
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
    if (!self.enabled) return LGXfadeOff;
    if (self.nativeMultiPlayerActive) return LGXfadeOverlap;
    if (!self.setNativeGain) return LGXfadeOff;
    return (self.advanceToNext && self.currentStreamURL) ? LGXfadeOverlap : LGXfadeDip;
}

- (NSString *)status {
    NSString *st;
    NSString *kind;
    BOOL nativeActive;
    NSString *nativeDet;
    @synchronized(self) {
        st = _status ?: @"idle";
        kind = _tailStreamKind ?: @"none";
        nativeActive = _nativeMultiPlayerActive;
        nativeDet = _nativeStatusDetail ?: @"ready";
    }
    if (!self.enabled) {
        return [NSString stringWithFormat:@"Crossfade off (%.1fs)", self.seconds];
    }
    if (nativeActive) {
        return [NSString stringWithFormat:@"Crossfade Native Dual-Deck (%.1fs) | %@", self.seconds, nativeDet];
    }
    return [NSString stringWithFormat:@"Crossfade %@ (%.1fs) [%@] | %@",
            @[@"off", @"dip", @"overlap"][self.mode],
            self.seconds,
            kind,
            st];
}

- (void)setStatusText:(NSString *)s {
    @synchronized(self) { _status = [s copy]; }
}

- (void)setStreamKind:(NSString *)k {
    @synchronized(self) { _tailStreamKind = [k copy]; }
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
        if (tot > 0 && self->_total <= 0) self->_total = tot;
        if (el >= 0 && fabs(el - (self->_elapsed0 + (CACurrentMediaTime() - self->_wall0))) > 1.2) {
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

#pragma mark - State Machine

- (NSString *)activeTrackToken {
    return _liveTrackID.length ? _liveTrackID : (_key ?: @"");
}

- (void)handleTrackChangedFromSource:(NSString *)src {
    if (_inOverlap) {
        _incomingTrackActivated = YES;
        return;
    }
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
    if (self.nativeMultiPlayerActive) {
        // Native MLHAMMultiPlayer + YTPersistentAudioFadeController handles dual-deck hardware crossfade cleanly.
        if (_busy || _tail) {
            [self cancel];
        }
        return;
    }
    if (_needFadeIn && CACurrentMediaTime() > _fadeInDeadline) {
        _needFadeIn = NO;
        [self applyGainMain:1.0f];
        [self setStatusText:@"recovered (timeout)"];
    }
    if (!self.enabled || !self.setNativeGain || _rate <= 0 || _total <= 0 || _busy) return;

    double N = self.seconds;
    if (_total < N + 4.0) return;

    double elapsed = _elapsed0 + (CACurrentMediaTime() - _wall0) * _rate;
    double remaining = _total - elapsed;
    NSString *tok = [self activeTrackToken];

    if (remaining > N + 20.0) {
        _firedKey = nil;
        _prepKey = nil;
        _syncKey = nil;
        if (_needFadeIn) [self fadeInNative];
        return;
    }

    // Phase 1: Preload & buffer tail AVPlayer ~ (N + 16s) before end
    if (remaining <= N + 18.0 && remaining > N + 2.5 &&
        self.mode == LGXfadeOverlap && ![_prepKey isEqualToString:tok]) {
        _prepKey = tok;
        double seekPos = MAX(0.0, _total - N - 3.0);
        [self prepareTailForTrack:tok seekTo:seekPos];
    }

    // Phase 2: Silent Sync Pre-Roll ~ (N + 1.8s) before end so _tail is actively spinning at 0ms latency
    if (remaining <= N + 2.0 && remaining > N + 0.25 &&
        self.mode == LGXfadeOverlap && ![_syncKey isEqualToString:tok]) {
        _syncKey = tok;
        [self silentSpinTailForTrack:tok targetElapsed:elapsed];
    }

    // Phase 3: Fire equal-power transition at remaining <= N
    if (remaining <= N && remaining > 0.25 && ![_firedKey isEqualToString:tok]) {
        _firedKey = tok;
        [self fireTransitionWithRemaining:remaining trackToken:tok elapsed:elapsed];
    }
}

#pragma mark - Tail Preload, Silent Sync Spin & Overlap Transition

// Extract audio-only sub-playlist URL from YouTube HLS master manifest if needed
static NSURL *LGResolveAudioOnlyURLIfHLS(NSURL *url, NSString **outKind) {
    if (!url) return nil;
    NSString *abs = url.absoluteString ?: @"";
    if ([abs containsString:@"mime=audio"] || [abs containsString:@"itag=140"] || [abs containsString:@"itag=139"]) {
        if (outKind) *outKind = @"mp4-audio";
        return url;
    }
    if ([abs containsString:@".m3u8"] || [abs containsString:@"hls_playlist"]) {
        NSData *data = [NSData dataWithContentsOfURL:url];
        if (data.length > 0) {
            NSString *txt = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            for (NSString *groupID in @[@"234", @"233"]) {
                for (NSString *line in [txt componentsSeparatedByString:@"\n"]) {
                    NSString *marker = [NSString stringWithFormat:@"TYPE=AUDIO,GROUP-ID=\"%@\"", groupID];
                    if ([line containsString:marker]) {
                        NSRange sr = [line rangeOfString:@"https://"];
                        NSRange er = [line rangeOfString:@"index.m3u8"];
                        if (sr.location != NSNotFound && er.location != NSNotFound && NSMaxRange(er) > sr.location) {
                            NSString *sub = [line substringWithRange:NSMakeRange(sr.location, NSMaxRange(er) - sr.location)];
                            if (outKind) *outKind = @"hls-audio";
                            return [NSURL URLWithString:sub];
                        }
                    }
                }
            }
        }
        if (outKind) *outKind = @"hls-master";
        return url;
    }
    if (outKind) *outKind = @"stream";
    return url;
}

- (void)prepareTailForTrack:(NSString *)tok seekTo:(double)seekPos {
    NSURL *(^urlBlock)(void) = self.currentStreamURL;
    if (!urlBlock) return;
    __weak LGCrossfade *w = self;

    dispatch_async(dispatch_get_main_queue(), ^{
        LGCrossfade *s = w;
        if (!s) return;
        NSURL *rawURL = urlBlock();
        if (!rawURL) {
            [s setStreamKind:@"none"];
            [s setStatusText:@"no stream URL -> will dip"];
            return;
        }
        [s setStatusText:@"resolving stream for tail..."];

        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            NSString *kind = @"stream";
            NSURL *audioURL = LGResolveAudioOnlyURLIfHLS(rawURL, &kind);
            [s setStreamKind:kind];

            dispatch_async(dispatch_get_main_queue(), ^{
                if (!s || ![[s activeTrackToken] isEqualToString:tok]) return;
                [s teardownTailSyncOnMain];
                s->_tailReady = NO;
                s->_tailSpinning = NO;
                s->_tailKey = [tok copy];

                AVURLAsset *asset = [AVURLAsset URLAssetWithURL:audioURL options:nil];
                AVPlayerItem *item = [AVPlayerItem playerItemWithAsset:asset];
                if (@available(iOS 10.0, *)) {
                    item.preferredForwardBufferDuration = 30.0;
                }
                AVPlayer *p = [AVPlayer playerWithPlayerItem:item];
                p.automaticallyWaitsToMinimizeStalling = YES;
                objc_setAssociatedObject(p, "LGTailPlayer", @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                p.muted = YES;
                p.volume = 0.0f;
                [p pause];
                s->_tail = p;

                [s setStatusText:[NSString stringWithFormat:@"buffering %@ @ %.1fs", kind, seekPos]];
                [s pollAndSeekTailPlayer:p item:item seekPos:seekPos attemptsLeft:24];
            });
        });
    });
}

- (void)pollAndSeekTailPlayer:(AVPlayer *)p item:(AVPlayerItem *)item seekPos:(double)seekPos attemptsLeft:(int)attempts {
    if (_tail != p || attempts <= 0) return;
    if (item.status == AVPlayerItemStatusFailed) {
        [self setStatusText:[NSString stringWithFormat:@"tail failed (%@)", item.error.localizedDescription ?: @"err"]];
        return;
    }
    if (item.status == AVPlayerItemStatusReadyToPlay) {
        CMTime target = CMTimeMakeWithSeconds(seekPos, 600);
        CMTime tol = CMTimeMakeWithSeconds(0.4, 600);
        [p seekToTime:target toleranceBefore:tol toleranceAfter:tol completionHandler:^(BOOL finished) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (self->_tail == p && item.status == AVPlayerItemStatusReadyToPlay) {
                    self->_tailReady = YES;
                    [self setStatusText:[NSString stringWithFormat:@"tail ready @ %.1fs (ok=%d)", seekPos, finished]];
                }
            });
        }];
        return;
    }
    __weak LGCrossfade *w = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(250 * NSEC_PER_MSEC)), dispatch_get_main_queue(), ^{
        [w pollAndSeekTailPlayer:p item:item seekPos:seekPos attemptsLeft:(attempts - 1)];
    });
}

- (void)silentSpinTailForTrack:(NSString *)tok targetElapsed:(double)elapsed {
    dispatch_async(dispatch_get_main_queue(), ^{
        AVPlayer *tail = self->_tail;
        if (!tail || ![self->_tailKey isEqualToString:tok] || !self->_tailReady) return;
        if (tail.currentItem.status != AVPlayerItemStatusReadyToPlay) return;

        CMTime syncPos = CMTimeMakeWithSeconds(MAX(0.0, elapsed + 0.12), 600);
        CMTime tol = CMTimeMakeWithSeconds(0.15, 600);
        [tail seekToTime:syncPos toleranceBefore:tol toleranceAfter:tol completionHandler:^(__unused BOOL ok) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (self->_tail == tail && !self->_inOverlap) {
                    tail.muted = YES;
                    tail.volume = 0.0f;
                    [tail play];
                    self->_tailSpinning = YES;
                    [self setStatusText:@"tail synced & spinning"];
                }
            });
        }];
    });
}

- (void)fireTransitionWithRemaining:(double)remaining trackToken:(NSString *)tok elapsed:(double)elapsed {
    _busy = YES;
    double N = LGXClamp(remaining, 1.0, self.seconds);
    BOOL (^advanceBlock)(void) = self.advanceToNext;

    dispatch_async(dispatch_get_main_queue(), ^{
        AVPlayer *tail = self->_tail;
        BOOL canOverlap = (tail && [self->_tailKey isEqualToString:tok] &&
                           self->_tailReady &&
                           tail.currentItem.status == AVPlayerItemStatusReadyToPlay &&
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
        [self setStatusText:@"overlap handoff..."];
    });

    void (^startMix)(void) = ^{
        if (self->_tail != tail) return;
        // 1. Bring spun-up tail up cleanly while briefly holding native audio (60ms handoff -> zero click/gap)
        tail.muted = NO;
        tail.volume = 1.0f;
        if (tail.rate <= 0.01f) [tail play];

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(70 * NSEC_PER_MSEC)), dispatch_get_main_queue(), ^{
            if (self->_tail != tail) return;
            // 2. Silence outgoing native renderer & trigger YouTube Music to advance to Track B
            [self applyGainMain:0.0f];
            BOOL advanced = advanceBlock ? advanceBlock() : NO;
            [self setStatusText:advanced ? @"crossfading (overlap)" : @"overlap (advance blocked)"];

            CFTimeInterval advanceStart = CACurrentMediaTime();
            __block CFTimeInterval inStartWall = 0.0;

            dispatch_async(self->_q, ^{
                [self rampOver:duration step:^(double t) {
                    float outGain = (float)cos(t * M_PI_2);

                    BOOL trackBReady = self->_incomingTrackActivated || ((CACurrentMediaTime() - advanceStart) > 1.25);
                    float inGain = 0.0f;
                    if (trackBReady) {
                        if (inStartWall <= 0.0) inStartWall = CACurrentMediaTime();
                        double remDur = MAX(0.8, duration - (inStartWall - advanceStart));
                        double inT = MIN(1.0, (CACurrentMediaTime() - inStartWall) / remDur);
                        inGain = (float)sin(inT * M_PI_2);
                    }

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
    };

    if (_tailSpinning && tail.rate > 0.01f) {
        startMix();
    } else {
        CMTime exactPos = CMTimeMakeWithSeconds(MAX(0.0, elapsed + 0.08), 600);
        CMTime tol = CMTimeMakeWithSeconds(0.2, 600);
        [tail seekToTime:exactPos toleranceBefore:tol toleranceAfter:tol completionHandler:^(__unused BOOL ok) {
            dispatch_async(dispatch_get_main_queue(), startMix);
        }];
    }
}

- (void)beginDipFadeOut:(double)remaining {
    _inDipFadeOut = YES;
    [self setStatusText:@"fading out (dip)"];

    double fadeDur = LGXClamp(remaining * 0.90, 0.5, self.seconds);
    BOOL (^advanceBlock)(void) = self.advanceToNext;
    __block BOOL didTriggerAdvance = NO;

    [self rampOver:fadeDur step:^(double t) {
        [self applyGainMain:(float)cos(t * M_PI_2)];
        if (t >= 0.92 && !didTriggerAdvance && advanceBlock) {
            didTriggerAdvance = YES;
            dispatch_async(dispatch_get_main_queue(), ^{
                advanceBlock();
            });
        }
    } done:^{
        self->_inDipFadeOut = NO;
        [self applyGainMain:0.0f];
        self->_needFadeIn = YES;
        self->_fadeInDeadline = CACurrentMediaTime() + 10.0;
        self->_busy = NO;
        [self setStatusText:@"waiting for next track"];
    }];
}

- (void)fadeInNative {
    _needFadeIn = NO;
    _inDipFadeOut = NO;
    _busy = YES;
    [self setStatusText:@"fading in"];
    double inDur = LGXClamp(self.seconds * 0.60, 0.8, 4.0);
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
    _tailReady = NO;
    _tailSpinning = NO;
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
