#import "NetworkBufferOptimizer.h"

static NSString * const kYTMUltimateKey = @"YTMUltimate";
static NSString * const kDeepBufferKey = @"appleDeepBuffer";
static NSString * const kPrefetchNextKey = @"applePrefetchNext";
static NSString * const kCacheSubdir = @"YTMAppleAudioCache";

@interface NetworkBufferOptimizer ()

@property (nonatomic, copy) NSString *cacheDirectoryPath;
@property (nonatomic, strong) NSURLSession *prefetchSession;
@property (nonatomic, assign) BOOL hasPrefetchedForCurrentTrack;
@property (nonatomic, copy, nullable) NSString *currentVideoID;
@property (nonatomic, strong) NSMutableSet<NSString *> *prefetchedVideoIDs;

@end

@implementation NetworkBufferOptimizer

+ (instancetype)sharedInstance {
    static NetworkBufferOptimizer *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[NetworkBufferOptimizer alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        self.prefetchedVideoIDs = [NSMutableSet set];
        [self setupCacheDirectory];
        [self loadSettings];
        [self setupPrefetchSession];
    }
    return self;
}

- (void)setupCacheDirectory {
    NSString *caches = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject;
    self.cacheDirectoryPath = [caches stringByAppendingPathComponent:kCacheSubdir];

    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:self.cacheDirectoryPath]) {
        [fm createDirectoryAtPath:self.cacheDirectoryPath withIntermediateDirectories:YES attributes:nil error:nil];
    }
}

- (void)setupPrefetchSession {
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    config.timeoutIntervalForRequest = 45.0;
    config.timeoutIntervalForResource = 300.0;
    config.waitsForConnectivity = YES;
    config.allowsCellularAccess = YES;
    config.allowsExpensiveNetworkAccess = YES;
    config.allowsConstrainedNetworkAccess = YES;
    config.HTTPMaximumConnectionsPerHost = 8;
    self.prefetchSession = [NSURLSession sessionWithConfiguration:config];
}

- (void)loadSettings {
    NSDictionary *dict = [[NSUserDefaults standardUserDefaults] dictionaryForKey:kYTMUltimateKey];
    if (dict) {
        self.deepBufferEnabled = dict[kDeepBufferKey] ? [dict[kDeepBufferKey] boolValue] : YES;
        self.prefetchNextEnabled = dict[kPrefetchNextKey] ? [dict[kPrefetchNextKey] boolValue] : YES;
    } else {
        self.deepBufferEnabled = YES;
        self.prefetchNextEnabled = YES;
        [self saveSettings];
    }
}

- (void)saveSettings {
    NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithDictionary:[[NSUserDefaults standardUserDefaults] dictionaryForKey:kYTMUltimateKey]];
    dict[kDeepBufferKey] = @(self.deepBufferEnabled);
    dict[kPrefetchNextKey] = @(self.prefetchNextEnabled);
    [[NSUserDefaults standardUserDefaults] setObject:dict forKey:kYTMUltimateKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

#pragma mark - Buffer & Stream Configuration

- (void)optimizePlayerItem:(AVPlayerItem *)item {
    if (!item || !self.deepBufferEnabled) return;

    // Apple Music style deep forward buffering: 120 seconds ahead of current playhead
    if (@available(iOS 10.0, *)) {
        item.preferredForwardBufferDuration = 120.0;
        item.canUseNetworkResourcesForLiveStreamingWhilePaused = YES;
    }
    if (@available(iOS 13.0, *)) {
        item.automaticallyPreservesTimeOffsetFromLive = NO;
    }
}

- (void)tuneSessionConfiguration:(NSURLSessionConfiguration *)config {
    if (!config || !self.deepBufferEnabled) return;

    config.timeoutIntervalForRequest = 45.0;
    config.timeoutIntervalForResource = 300.0;
    config.waitsForConnectivity = YES;
    config.allowsCellularAccess = YES;
    config.allowsExpensiveNetworkAccess = YES;
    config.allowsConstrainedNetworkAccess = YES;
    config.HTTPMaximumConnectionsPerHost = 8;
}

#pragma mark - 15% Playhead Monitoring & Pre-Fetching

- (void)notifyNewTrackLoadedWithVideoID:(nullable NSString *)videoID {
    self.currentVideoID = videoID;
    self.hasPrefetchedForCurrentTrack = NO;
}

- (void)trackProgressDidChangeCurrent:(NSTimeInterval)current total:(NSTimeInterval)total {
    if (!self.prefetchNextEnabled || self.hasPrefetchedForCurrentTrack || total <= 0) return;

    double progress = current / total;
    // As soon as track passes 15% playback progress, trigger proactive pre-fetching of next queue items
    if (progress >= 0.15) {
        self.hasPrefetchedForCurrentTrack = YES;
        [self initiateNextTracksPrefetch];
    }
}

- (void)initiateNextTracksPrefetch {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        // Trigger notification that listener hooks (in AppleAudioHooks.x) intercept to resolve queue items
        [[NSNotificationCenter defaultCenter] postNotificationName:@"YTMAppleTriggerQueuePrefetch" object:self];
    });
}

- (void)prefetchUpcomingTrackURL:(nullable NSURL *)streamURL videoID:(nullable NSString *)videoID {
    if (!streamURL || !self.prefetchNextEnabled) return;
    if (videoID && [self.prefetchedVideoIDs containsObject:videoID]) return;

    if (videoID) {
        [self.prefetchedVideoIDs addObject:videoID];
    }

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:streamURL];
    // Request first 2 MB of audio stream to buffer initial packets, metadata, and codec tables
    [request setValue:@"bytes=0-2097152" forHTTPHeaderField:@"Range"];

    NSURLSessionDownloadTask *task = [self.prefetchSession downloadTaskWithRequest:request completionHandler:^(NSURL *location, NSURLResponse *response, NSError *error) {
        if (!error && location) {
            NSString *fileName = [NSString stringWithFormat:@"%@_chunk.mp4", videoID ?: [[NSUUID UUID] UUIDString]];
            NSString *destPath = [self.cacheDirectoryPath stringByAppendingPathComponent:fileName];
            [[NSFileManager defaultManager] removeItemAtPath:destPath error:nil];
            [[NSFileManager defaultManager] moveItemAtURL:location toURL:[NSURL fileURLWithPath:destPath] error:nil];
        }
    }];
    [task resume];
}

#pragma mark - Cache Metrics & Cleaning

- (NSString *)formattedCacheSize {
    NSArray *files = [[NSFileManager defaultManager] subpathsOfDirectoryAtPath:self.cacheDirectoryPath error:nil];
    unsigned long long total = 0;
    for (NSString *file in files) {
        NSString *path = [self.cacheDirectoryPath stringByAppendingPathComponent:file];
        NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
        total += [attrs fileSize];
    }
    NSByteCountFormatter *fmt = [[NSByteCountFormatter alloc] init];
    fmt.countStyle = NSByteCountFormatterCountStyleFile;
    return [fmt stringFromByteCount:total];
}

- (void)clearCache {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [[NSFileManager defaultManager] removeItemAtPath:self.cacheDirectoryPath error:nil];
        [self.prefetchedVideoIDs removeAllObjects];
        [self setupCacheDirectory];
    });
}

@end
