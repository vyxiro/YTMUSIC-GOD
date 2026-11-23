#import "AudioCrossfadeManager.h"
#import <math.h>

static NSString * const kCrossfadePrefsKey = @"YTMAppleStyleEnhancer_CrossfadePrefs";
static NSString * const kCrossfadeEnabledKey = @"crossfadeEnabled";
static NSString * const kCrossfadeDurationKey = @"crossfadeDuration";
static NSString * const kLowNetworkBufferingKey = @"lowNetworkBufferingEnabled";

@interface AudioCrossfadeManager ()

@property (nonatomic, weak) AVPlayer *activePlayer;
@property (nonatomic, weak) id activePlayerVC;
@property (nonatomic, strong) CADisplayLink *fadeDisplayLink;
@property (nonatomic, assign) NSTimeInterval fadeStartTime;
@property (nonatomic, assign) BOOL isFadingOut;
@property (nonatomic, assign) BOOL isFadingIn;
@property (nonatomic, assign) float originalVolume;
@property (nonatomic, assign, readwrite) BOOL isCrossfading;
@property (nonatomic, copy, nullable) NSString *currentTrackID;
@property (nonatomic, strong) NSURLSession *prefetchSession;

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
        self.originalVolume = 1.0f;
        [self loadPreferences];
        [self setupPrefetchSession];
    }
    return self;
}

- (void)loadPreferences {
    NSDictionary *prefs = [[NSUserDefaults standardUserDefaults] dictionaryForKey:kCrossfadePrefsKey];
    if (prefs) {
        self.crossfadeEnabled = prefs[kCrossfadeEnabledKey] ? [prefs[kCrossfadeEnabledKey] boolValue] : YES;
        self.crossfadeDuration = prefs[kCrossfadeDurationKey] ? [prefs[kCrossfadeDurationKey] floatValue] : 5.0f;
        self.lowNetworkBufferingEnabled = prefs[kLowNetworkBufferingKey] ? [prefs[kLowNetworkBufferingKey] boolValue] : YES;
    } else {
        self.crossfadeEnabled = YES;
        self.crossfadeDuration = 5.0f;
        self.lowNetworkBufferingEnabled = YES;
        [self savePreferences];
    }
}

- (void)savePreferences {
    NSMutableDictionary *prefs = [NSMutableDictionary dictionary];
    prefs[kCrossfadeEnabledKey] = @(self.crossfadeEnabled);
    prefs[kCrossfadeDurationKey] = @(self.crossfadeDuration);
    prefs[kLowNetworkBufferingKey] = @(self.lowNetworkBufferingEnabled);
    [[NSUserDefaults standardUserDefaults] setObject:prefs forKey:kCrossfadePrefsKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)setupPrefetchSession {
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    config.timeoutIntervalForRequest = 45.0;
    config.timeoutIntervalForResource = 300.0;
    config.waitsForConnectivity = YES;
    config.allowsExpensiveNetworkAccess = YES;
    config.allowsConstrainedNetworkAccess = YES;
    config.HTTPMaximumConnectionsPerHost = 6;
    self.prefetchSession = [NSURLSession sessionWithConfiguration:config];
}

#pragma mark - Audio Registration & Hooks

- (void)registerActivePlayer:(AVPlayer *)player {
    if (!player) return;
    self.activePlayer = player;
}

- (void)registerPlayerViewController:(id)playerVC {
    self.activePlayerVC = playerVC;
}

- (void)optimizePlayerItemForLowNetwork:(AVPlayerItem *)item {
    if (!item || !self.lowNetworkBufferingEnabled) return;

    // Apple AVPlayerItem aggressive forward caching (120 seconds ahead)
    if (@available(iOS 10.0, *)) {
        item.preferredForwardBufferDuration = 120.0;
        item.canUseNetworkResourcesForLiveStreamingWhilePaused = YES;
    }
    if (@available(iOS 13.0, *)) {
        item.automaticallyPreservesTimeOffsetFromLive = NO;
    }
}

- (void)prefetchUpcomingTrackURL:(nullable NSURL *)url {
    if (!url || !self.lowNetworkBufferingEnabled) return;
    
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    // Request initial audio chunk (first 1 MB) to warm up cache and TCP/TLS socket
    [request setValue:@"bytes=0-1048576" forHTTPHeaderField:@"Range"];
    
    NSURLSessionDataTask *task = [self.prefetchSession dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        // Pre-cached audio headers and starting samples successfully into memory/disk
    }];
    [task resume];
}

#pragma mark - Equal-Power Smooth Crossfade Engine

- (void)didUpdatePlaybackTime:(NSTimeInterval)currentTime duration:(NSTimeInterval)duration {
    if (!self.crossfadeEnabled || duration <= 0 || self.isCrossfading) return;

    NSTimeInterval remainingTime = duration - currentTime;
    NSTimeInterval threshold = self.crossfadeDuration;

    // Trigger crossfade when remaining track duration reaches configured threshold
    if (remainingTime > 0 && remainingTime <= threshold && !self.isFadingOut) {
        [self startFadeOut];
    }
}

- (void)startFadeOut {
    if (!self.activePlayer || self.isFadingOut) return;

    self.isCrossfading = YES;
    self.isFadingOut = YES;
    self.originalVolume = (self.activePlayer.volume > 0.01f) ? self.activePlayer.volume : 1.0f;
    self.fadeStartTime = CACurrentMediaTime();

    [self stopDisplayLink];
    self.fadeDisplayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(handleFadeTick:)];
    [self.fadeDisplayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}

- (void)didStartNewTrackWithPlayer:(AVPlayer *)player {
    self.activePlayer = player;
    if (!self.crossfadeEnabled) return;

    // Start incoming track at gain 0.0 and smoothly fade in
    self.activePlayer.volume = 0.0f;
    self.isFadingOut = NO;
    self.isFadingIn = YES;
    self.fadeStartTime = CACurrentMediaTime();

    [self stopDisplayLink];
    self.fadeDisplayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(handleFadeTick:)];
    [self.fadeDisplayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}

- (void)handleFadeTick:(CADisplayLink *)displayLink {
    if (!self.activePlayer) {
        [self stopDisplayLink];
        return;
    }

    NSTimeInterval elapsed = CACurrentMediaTime() - self.fadeStartTime;
    CGFloat duration = MAX(0.5f, self.crossfadeDuration);
    CGFloat progress = (CGFloat)(elapsed / duration);

    if (self.isFadingOut) {
        if (progress >= 1.0f) {
            self.activePlayer.volume = 0.0f;
            self.isFadingOut = NO;
            [self stopDisplayLink];
            [self triggerNextTrackAction];
        } else {
            // Equal-Power Fade Out: cos(progress * PI / 2)
            float gain = (float)cos(progress * M_PI_2);
            self.activePlayer.volume = self.originalVolume * gain;
        }
    } else if (self.isFadingIn) {
        if (progress >= 1.0f) {
            self.activePlayer.volume = self.originalVolume;
            self.isFadingIn = NO;
            self.isCrossfading = NO;
            [self stopDisplayLink];
        } else {
            // Equal-Power Fade In: sin(progress * PI / 2)
            float gain = (float)sin(progress * M_PI_2);
            self.activePlayer.volume = self.originalVolume * gain;
        }
    }
}

- (void)triggerNextTrackAction {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.activePlayerVC && [self.activePlayerVC respondsToSelector:@selector(didTapNextButton)]) {
            [self.activePlayerVC performSelector:@selector(didTapNextButton)];
        }
    });
}

- (void)willTransitionToNextTrack {
    // Called when user manually taps next or queue advances
    if (self.crossfadeEnabled && !self.isFadingIn) {
        [self didStartNewTrackWithPlayer:self.activePlayer];
    }
}

- (void)stopDisplayLink {
    if (self.fadeDisplayLink) {
        [self.fadeDisplayLink invalidate];
        self.fadeDisplayLink = nil;
    }
}

@end
