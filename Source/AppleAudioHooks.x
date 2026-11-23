#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import "AudioCrossfadeManager.h"
#import "NetworkBufferOptimizer.h"
#import "ThemeManager.h"
#import "AmbientView.h"
#import "Headers/YTPlayerViewController.h"
#import "Headers/YTPlayerResponse.h"
#import "Headers/YTIPlayerResponse.h"
#import "Headers/YTIStreamingData.h"
#import "Headers/YTIFormatStream.h"
#import "Headers/YTMNowPlayingViewController.h"

// Forward declarations
@interface HAMChunkBuffer : NSObject
- (double)targetBufferDuration;
- (double)maxBufferDuration;
- (double)minBufferDuration;
@end

@interface HAMDataLoader : NSObject
@end

@interface YTPlaybackController : NSObject
@end

@interface YTPivotBarItemView : UIView
@property (nonatomic, assign) BOOL selected;
- (void)setTintColor:(UIColor *)color;
@end

static __weak YTPlayerViewController *gCurrentPlayerVC = nil;
static AmbientView *gSharedAmbientView = nil;

#pragma mark - Playback Controller & Crossfade Hooks

%hook YTPlayerViewController

- (void)viewDidLoad {
    %orig;
    gCurrentPlayerVC = self;
    [[AudioCrossfadeManager sharedInstance] registerPlayerViewController:self];
}

- (void)playbackController:(id)arg1 didActivateVideo:(id)arg2 withPlaybackData:(id)arg3 {
    %orig;
    gCurrentPlayerVC = self;
    NSString *videoID = [self currentVideoID];
    [[AudioCrossfadeManager sharedInstance] registerPlayerViewController:self];
    [[AudioCrossfadeManager sharedInstance] notifyTrackActivatedWithVideoID:videoID player:nil];
    [[NetworkBufferOptimizer sharedInstance] notifyNewTrackLoadedWithVideoID:videoID];
}

- (void)singleVideo:(id)video currentVideoTimeDidChange:(id)time {
    %orig;
    CGFloat current = [self currentVideoMediaTime];
    CGFloat total = [self currentVideoTotalMediaTime];
    if (total > 0) {
        [[AudioCrossfadeManager sharedInstance] didUpdatePlaybackTime:current duration:total];
        [[NetworkBufferOptimizer sharedInstance] trackProgressDidChangeCurrent:current total:total];
    }
}

- (void)potentiallyMutatedSingleVideo:(id)video currentVideoTimeDidChange:(id)time {
    %orig;
    CGFloat current = [self currentVideoMediaTime];
    CGFloat total = [self currentVideoTotalMediaTime];
    if (total > 0) {
        [[AudioCrossfadeManager sharedInstance] didUpdatePlaybackTime:current duration:total];
        [[NetworkBufferOptimizer sharedInstance] trackProgressDidChangeCurrent:current total:total];
    }
}

- (void)seekToTime:(CGFloat)time {
    [[AudioCrossfadeManager sharedInstance] notifyManualSkipOccurred];
    %orig(time);
}

%end

%hook YTMNowPlayingViewController

- (void)viewDidLoad {
    %orig;
    if (!gSharedAmbientView) {
        gSharedAmbientView = [[AmbientView alloc] initWithFrame:self.view.bounds];
        gSharedAmbientView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self.view insertSubview:gSharedAmbientView atIndex:0];
    }
}

- (void)viewDidLayoutSubviews {
    %orig;
    if (gSharedAmbientView) {
        gSharedAmbientView.frame = self.view.bounds;
        [self.view sendSubviewToBack:gSharedAmbientView];
    }
}

- (void)didTapNextButton {
    [[AudioCrossfadeManager sharedInstance] notifyManualSkipOccurred];
    %orig;
}

- (void)didTapPrevButton {
    [[AudioCrossfadeManager sharedInstance] notifyManualSkipOccurred];
    %orig;
}

%end

// Feed album artwork to AmbientView
%hook UIImageView

- (void)setImage:(UIImage *)image {
    %orig(image);

    if (image && gSharedAmbientView && gSharedAmbientView.glowEnabled) {
        CGSize sz = image.size;
        if (sz.width >= 120 && sz.height >= 120 && fabs(sz.width - sz.height) < 40) {
            [gSharedAmbientView updateWithArtworkImage:image animated:YES];
        }
    }
}

%end

#pragma mark - AVFoundation Layer Hooks

%hook AVPlayer

- (void)play {
    %orig;
    [[AudioCrossfadeManager sharedInstance] registerActivePlayer:self];
}

- (void)replaceCurrentItemWithPlayerItem:(AVPlayerItem *)item {
    %orig(item);
    if (item) {
        [[NetworkBufferOptimizer sharedInstance] optimizePlayerItem:item];
        [[AudioCrossfadeManager sharedInstance] registerActivePlayer:self];
    }
}

%end

%hook AVPlayerItem

- (instancetype)initWithURL:(NSURL *)URL {
    AVPlayerItem *item = %orig(URL);
    if (item) {
        [[NetworkBufferOptimizer sharedInstance] optimizePlayerItem:item];
    }
    return item;
}

- (instancetype)initWithAsset:(AVAsset *)asset {
    AVPlayerItem *item = %orig(asset);
    if (item) {
        [[NetworkBufferOptimizer sharedInstance] optimizePlayerItem:item];
    }
    return item;
}

%end

#pragma mark - Network Layer & Buffer Hooks

%hook NSURLSessionConfiguration

+ (NSURLSessionConfiguration *)defaultSessionConfiguration {
    NSURLSessionConfiguration *config = %orig;
    [[NetworkBufferOptimizer sharedInstance] tuneSessionConfiguration:config];
    return config;
}

+ (NSURLSessionConfiguration *)ephemeralSessionConfiguration {
    NSURLSessionConfiguration *config = %orig;
    [[NetworkBufferOptimizer sharedInstance] tuneSessionConfiguration:config];
    return config;
}

%end

%hook HAMChunkBuffer

- (double)targetBufferDuration {
    if ([NetworkBufferOptimizer sharedInstance].deepBufferEnabled) {
        return 120.0; // 120 seconds read-ahead window
    }
    return %orig;
}

- (double)maxBufferDuration {
    if ([NetworkBufferOptimizer sharedInstance].deepBufferEnabled) {
        return 180.0; // 3 minutes maximum cache headroom
    }
    return %orig;
}

- (double)minBufferDuration {
    if ([NetworkBufferOptimizer sharedInstance].deepBufferEnabled) {
        return 30.0; // 30 seconds minimum buffer before playback begins
    }
    return %orig;
}

%end

#pragma mark - Dynamic Theme Accent Hooks

%hook UISlider

- (void)didMoveToWindow {
    %orig;
    if (self.window && [ThemeManager sharedManager].themePreset != YTMThemePresetDefaultRed) {
        UIColor *accent = [[ThemeManager sharedManager] currentAccentColor];
        self.minimumTrackTintColor = accent;
        self.thumbTintColor = accent;
    }
}

%end

%hook YTPivotBarItemView

- (void)layoutSubviews {
    %orig;
    if (self.selected && [ThemeManager sharedManager].themePreset != YTMThemePresetDefaultRed) {
        UIColor *accent = [[ThemeManager sharedManager] currentAccentColor];
        [self setTintColor:accent];
    }
}

- (void)setSelected:(BOOL)selected {
    %orig(selected);
    if (selected && [ThemeManager sharedManager].themePreset != YTMThemePresetDefaultRed) {
        UIColor *accent = [[ThemeManager sharedManager] currentAccentColor];
        [self setTintColor:accent];
    }
}

%end

#pragma mark - Queue Pre-fetch Listener

static void handleQueuePrefetchNotification(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    if (!gCurrentPlayerVC) return;

    dispatch_async(dispatch_get_main_queue(), ^{
        YTPlayerResponse *response = gCurrentPlayerVC.playerResponse;
        if (!response) return;

        NSString *hlsURL = response.playerData.streamingData.hlsManifestURL;
        if (hlsURL.length > 0) {
            [[NetworkBufferOptimizer sharedInstance] prefetchUpcomingTrackURL:[NSURL URLWithString:hlsURL] videoID:gCurrentPlayerVC.contentVideoID];
        } else if (response.playerData.streamingData.adaptiveFormatsArray.count > 0) {
            YTIFormatStream *firstFormat = response.playerData.streamingData.adaptiveFormatsArray.firstObject;
            if (firstFormat.URL.length > 0) {
                [[NetworkBufferOptimizer sharedInstance] prefetchUpcomingTrackURL:[NSURL URLWithString:firstFormat.URL] videoID:gCurrentPlayerVC.contentVideoID];
            }
        }
    });
}

%ctor {
    NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithDictionary:[[NSUserDefaults standardUserDefaults] dictionaryForKey:@"YTMUltimate"]];
    if (dict[@"appleCrossfade"] == nil) dict[@"appleCrossfade"] = @(1);
    if (dict[@"appleCrossfadeDuration"] == nil) dict[@"appleCrossfadeDuration"] = @(5.0f);
    if (dict[@"appleCrossfadeGaplessBypass"] == nil) dict[@"appleCrossfadeGaplessBypass"] = @(1);
    if (dict[@"appleDeepBuffer"] == nil) dict[@"appleDeepBuffer"] = @(1);
    if (dict[@"applePrefetchNext"] == nil) dict[@"applePrefetchNext"] = @(1);
    [[NSUserDefaults standardUserDefaults] setObject:dict forKey:@"YTMUltimate"];

    [[NSNotificationCenter defaultCenter] addObserverForName:@"YTMAppleTriggerQueuePrefetch" object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification * _Nonnull note) {
        handleQueuePrefetchNotification(NULL, NULL, NULL, NULL, NULL);
    }];
}
