#import "AudioCrossfadeManager.h"
#import <math.h>

static NSString * const kYTMUltimateKey = @"YTMUltimate";
static NSString * const kCrossfadeKey = @"appleCrossfade";
static NSString * const kCrossfadeDurationKey = @"appleCrossfadeDuration";
static NSString * const kGaplessBypassKey = @"appleCrossfadeGaplessBypass";

@interface AudioCrossfadeManager ()

@property (nonatomic, weak) AVPlayer *activePlayer;
@property (nonatomic, weak) id activePlayerVC;
@property (nonatomic, strong) CADisplayLink *displayLink;
@property (nonatomic, assign) NSTimeInterval fadeStartTime;
@property (nonatomic, assign) BOOL isFadingOut;
@property (nonatomic, assign) BOOL isFadingIn;
@property (nonatomic, assign) float baseVolume;
@property (nonatomic, assign, readwrite) BOOL isCrossfading;
@property (nonatomic, assign, readwrite) BOOL isManualSkip;
@property (nonatomic, copy, nullable) NSString *currentVideoID;
@property (nonatomic, assign) NSTimeInterval lastObservedDuration;

@end

@implementation AudioCrossfadeManager

+ (instancetype)sharedInstance {
    static AudioCrossfadeManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[AudioCrossfadeManager alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        self.baseVolume = 1.0f;
        [self loadSettings];
    }
    return self;
}

- (void)loadSettings {
    NSDictionary *dict = [[NSUserDefaults standardUserDefaults] dictionaryForKey:kYTMUltimateKey];
    if (dict) {
        self.crossfadeEnabled = dict[kCrossfadeKey] ? [dict[kCrossfadeKey] boolValue] : YES;
        self.crossfadeDuration = dict[kCrossfadeDurationKey] ? [dict[kCrossfadeDurationKey] floatValue] : 5.0f;
        self.gaplessBypassEnabled = dict[kGaplessBypassKey] ? [dict[kGaplessBypassKey] boolValue] : YES;
    } else {
        self.crossfadeEnabled = YES;
        self.crossfadeDuration = 5.0f;
        self.gaplessBypassEnabled = YES;
        [self saveSettings];
    }
}

- (void)saveSettings {
    NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithDictionary:[[NSUserDefaults standardUserDefaults] dictionaryForKey:kYTMUltimateKey]];
    dict[kCrossfadeKey] = @(self.crossfadeEnabled);
    dict[kCrossfadeDurationKey] = @(self.crossfadeDuration);
    dict[kGaplessBypassKey] = @(self.gaplessBypassEnabled);
    [[NSUserDefaults standardUserDefaults] setObject:dict forKey:kYTMUltimateKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

#pragma mark - Registration & State Management

- (void)registerActivePlayer:(AVPlayer *)player {
    if (!player) return;
    self.activePlayer = player;
}

- (void)registerPlayerViewController:(id)playerVC {
    if (!playerVC) return;
    self.activePlayerVC = playerVC;
}

- (void)notifyManualSkipOccurred {
    self.isManualSkip = YES;
    [self resetFaders];
    
    // Reset manual skip flag shortly after transition settles
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        self.isManualSkip = NO;
    });
}

- (void)notifyTrackActivatedWithVideoID:(nullable NSString *)videoID player:(nullable AVPlayer *)player {
    if (player) {
        self.activePlayer = player;
    }
    self.currentVideoID = videoID;

    // If manual skip was triggered, resume full volume immediately without crossfade in
    if (self.isManualSkip || !self.crossfadeEnabled) {
        if (self.activePlayer) {
            self.activePlayer.volume = self.baseVolume;
        }
        [self resetFaders];
        return;
    }

    // Begin Apple Music-style equal-power fade-in on incoming audio stream
    if (self.activePlayer) {
        self.activePlayer.volume = 0.0f;
        self.isFadingOut = NO;
        self.isFadingIn = YES;
        self.isCrossfading = YES;
        self.fadeStartTime = CACurrentMediaTime();

        [self stopDisplayLink];
        self.displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(handleFadeTick:)];
        [self.displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    }
}

#pragma mark - Playback Time Tracking & Equal-Power Crossfade

- (void)didUpdatePlaybackTime:(NSTimeInterval)currentTime duration:(NSTimeInterval)duration {
    if (!self.crossfadeEnabled || duration <= 0 || self.isCrossfading || self.isManualSkip) return;

    self.lastObservedDuration = duration;
    NSTimeInterval remaining = duration - currentTime;
    NSTimeInterval window = MAX(1.0, (NSTimeInterval)self.crossfadeDuration);

    // Trigger fade-out when reaching the configured remaining duration window
    if (remaining > 0 && remaining <= window && !self.isFadingOut) {
        [self startFadeOut];
    }
}

- (void)startFadeOut {
    if (!self.activePlayer || self.isFadingOut || self.isManualSkip) return;

    self.isCrossfading = YES;
    self.isFadingOut = YES;
    self.isFadingIn = NO;
    self.baseVolume = (self.activePlayer.volume > 0.01f) ? self.activePlayer.volume : 1.0f;
    self.fadeStartTime = CACurrentMediaTime();

    [self stopDisplayLink];
    self.displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(handleFadeTick:)];
    [self.displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}

- (void)handleFadeTick:(CADisplayLink *)displayLink {
    if (!self.activePlayer) {
        [self resetFaders];
        return;
    }

    NSTimeInterval elapsed = CACurrentMediaTime() - self.fadeStartTime;
    CGFloat duration = MAX(1.0f, self.crossfadeDuration);
    CGFloat progress = (CGFloat)(elapsed / duration);

    if (self.isFadingOut) {
        if (progress >= 1.0f) {
            self.activePlayer.volume = 0.0f;
            self.isFadingOut = NO;
            [self stopDisplayLink];
            [self triggerQueueAdvance];
        } else {
            // Equal-Power Fade Out: cos(progress * pi / 2)
            float gain = (float)cos(progress * M_PI_2);
            self.activePlayer.volume = self.baseVolume * gain;
        }
    } else if (self.isFadingIn) {
        if (progress >= 1.0f) {
            self.activePlayer.volume = self.baseVolume;
            self.isFadingIn = NO;
            self.isCrossfading = NO;
            [self stopDisplayLink];
        } else {
            // Equal-Power Fade In: sin(progress * pi / 2)
            float gain = (float)sin(progress * M_PI_2);
            self.activePlayer.volume = self.baseVolume * gain;
        }
    }
}

- (void)triggerQueueAdvance {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.activePlayerVC && [self.activePlayerVC respondsToSelector:@selector(didTapNextButton)]) {
            [self.activePlayerVC performSelector:@selector(didTapNextButton)];
        }
    });
}

- (void)resetFaders {
    [self stopDisplayLink];
    self.isFadingOut = NO;
    self.isFadingIn = NO;
    self.isCrossfading = NO;
    if (self.activePlayer) {
        self.activePlayer.volume = self.baseVolume;
    }
}

- (void)stopDisplayLink {
    if (self.displayLink) {
        [self.displayLink invalidate];
        self.displayLink = nil;
    }
}

@end
