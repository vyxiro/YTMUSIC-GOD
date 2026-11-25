#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <MediaPlayer/MediaPlayer.h>
#import <objc/message.h>
#import "AudioCrossfadeManager.h"
#import "LGCrossfade.h"
#import "NetworkBufferOptimizer.h"
#import "LiquidGlass.h"
#import "ThemeManager.h"
#import "AmbientView.h"
#import <objc/runtime.h>
#import "Headers/YTPlayerViewController.h"
#import "Headers/YTPlayerResponse.h"
#import "Headers/YTIPlayerResponse.h"
#import "Headers/YTIVideoDetails.h"
#import "Headers/YTIStreamingData.h"
#import "Headers/YTIFormatStream.h"
#import "Headers/YTIThumbnailDetails.h"
#import "Headers/YTIThumbnailDetails_Thumbnail.h"
#import "Headers/YTMNowPlayingViewController.h"
#import "Headers/YTMBrowseViewController.h"

@interface YTPlaybackController : NSObject
@end

@interface YTPivotBarItemView : UIView
- (id)navigationButton;
@end

@interface YTPivotBarView : UIView
- (UIView *)contentView;
@end

static __weak YTPlayerViewController *gCurrentPlayerVC = nil;
static __weak id gCurrentNowPlayingVC = nil;
static AmbientView *gSharedAmbientView = nil;
static AmbientView *gBrowseAmbientView = nil;

static NSHashTable *gTrackedRenderers = nil;
static NSHashTable *gTrackedPlayers = nil;
static NSHashTable *gTrackedEngines = nil;
static NSString *gAudioLock = @"YTM_AUDIO_LOCK";
static float gCurrentNativeGain = 1.0f;
static BOOL gProgrammaticAdvance = NO;
static NSString *gObservedAudioBackend = @"none yet";

NSString *YTMObservedAudioBackend(void) {
    @synchronized(gAudioLock) {
        return [NSString stringWithFormat:@"%@ (renderers=%lu, players=%lu, engines=%lu, gain=%.2f)",
                gObservedAudioBackend,
                (unsigned long)gTrackedRenderers.count,
                (unsigned long)gTrackedPlayers.count,
                (unsigned long)gTrackedEngines.count,
                gCurrentNativeGain];
    }
}

static void YTMApplyNativeGainToObject(id obj, float gain) {
    if (!obj) return;
    @try {
        if ([obj isKindOfClass:[AVSampleBufferAudioRenderer class]]) {
            ((AVSampleBufferAudioRenderer *)obj).volume = gain;
        } else if ([obj isKindOfClass:[AVPlayer class]]) {
            ((AVPlayer *)obj).volume = gain;
        } else if ([obj isKindOfClass:[AVAudioEngine class]]) {
            ((AVAudioEngine *)obj).mainMixerNode.outputVolume = gain;
        }
    } @catch (__unused NSException *e) {}
}

static void YTMInstallCrossfadeAdapters(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        @synchronized(gAudioLock) {
            if (!gTrackedRenderers) gTrackedRenderers = [NSHashTable weakObjectsHashTable];
            if (!gTrackedPlayers) gTrackedPlayers = [NSHashTable weakObjectsHashTable];
            if (!gTrackedEngines) gTrackedEngines = [NSHashTable weakObjectsHashTable];
        }

        LGCrossfade *xf = LGCrossfade.shared;
        xf.setNativeGain = ^(float gain) {
            NSArray *renderers = nil, *players = nil, *engines = nil;
            @synchronized(gAudioLock) {
                gCurrentNativeGain = gain;
                renderers = gTrackedRenderers.allObjects;
                players = gTrackedPlayers.allObjects;
                engines = gTrackedEngines.allObjects;
            }
            for (id r in renderers) YTMApplyNativeGainToObject(r, gain);
            for (id p in players) YTMApplyNativeGainToObject(p, gain);
            for (id e in engines) YTMApplyNativeGainToObject(e, gain);
        };

        xf.advanceToNext = ^BOOL {
            __block BOOL ok = NO;
            void (^work)(void) = ^{
                id target = gCurrentNowPlayingVC ?: gCurrentPlayerVC.parentViewController;
                if (target && [target respondsToSelector:@selector(didTapNextButton)]) {
                    gProgrammaticAdvance = YES;
                    @try {
                        ((void (*)(id, SEL))objc_msgSend)(target, @selector(didTapNextButton));
                        ok = YES;
                    } @catch (__unused NSException *e) {
                        ok = NO;
                    }
                    gProgrammaticAdvance = NO;
                }
            };
            if ([NSThread isMainThread]) work();
            else dispatch_sync(dispatch_get_main_queue(), work);
            return ok;
        };

        xf.currentTrackAsset = ^AVURLAsset * {
            __block NSString *urlStr = nil;
            void (^fetch)(void) = ^{
                YTPlayerViewController *pvc = gCurrentPlayerVC;
                YTIStreamingData *sd = pvc.playerResponse.playerData.streamingData;
                if (!sd) return;
                for (id fmt in sd.adaptiveFormatsArray) {
                    if ([fmt respondsToSelector:@selector(URL)]) {
                        NSString *u = [fmt URL];
                        if (u.length && ([u containsString:@"mime=audio"] || [u containsString:@"mime%3Daudio"])) {
                            urlStr = u;
                            break;
                        }
                    }
                }
                if (!urlStr.length && sd.hlsManifestURL.length) {
                    urlStr = sd.hlsManifestURL;
                }
            };
            if ([NSThread isMainThread]) fetch();
            else dispatch_sync(dispatch_get_main_queue(), fetch);
            if (!urlStr.length) return nil;
            NSURL *url = [NSURL URLWithString:urlStr];
            return url ? [AVURLAsset URLAssetWithURL:url options:nil] : nil;
        };
    });
}

static void YTMFeedFallbackCrossfadeTime(YTPlayerViewController *pvc, CGFloat current, CGFloat total) {
    if (LGNowPlayingHookCount() > 0 || total <= 0) return;
    static CFTimeInterval sLastFeed = 0;
    CFTimeInterval now = CACurrentMediaTime();
    if (now - sLastFeed < 1.5) return;
    sLastFeed = now;
    YTIVideoDetails *vd = pvc.playerResponse.playerData.videoDetails;
    NSString *title = vd.title ?: pvc.currentVideoID ?: @"";
    NSString *artist = vd.author ?: @"";
    NSDictionary *info = @{
        MPMediaItemPropertyTitle: title,
        MPMediaItemPropertyArtist: artist,
        MPNowPlayingInfoPropertyElapsedPlaybackTime: @(current),
        MPMediaItemPropertyPlaybackDuration: @(total),
        MPNowPlayingInfoPropertyPlaybackRate: @(1.0)
    };
    [[LGCrossfade shared] noteNowPlayingInfo:info];
}

#pragma mark - Playback Controller & Crossfade Hooks

%hook YTPlayerViewController

- (void)viewDidLoad {
    %orig;
    gCurrentPlayerVC = self;
    YTMInstallCrossfadeAdapters();
    @try {
        [[AudioCrossfadeManager sharedInstance] registerPlayerViewController:self];
    } @catch (NSException *e) {}
}

- (void)playbackController:(id)arg1 didActivateVideo:(id)arg2 withPlaybackData:(id)arg3 {
    %orig;
    gCurrentPlayerVC = self;
    YTMInstallCrossfadeAdapters();
    @try {
        NSString *videoID = [self currentVideoID];
        [[AudioCrossfadeManager sharedInstance] registerPlayerViewController:self];
        [[AudioCrossfadeManager sharedInstance] notifyTrackActivatedWithVideoID:videoID player:nil];
        [[NetworkBufferOptimizer sharedInstance] notifyNewTrackLoadedWithVideoID:videoID];
        YTMFeedFallbackCrossfadeTime(self, [self currentVideoMediaTime], [self currentVideoTotalMediaTime]);

        // Safe artwork extraction for Ambient Mode
        YTPlayerResponse *response = self.playerResponse;
        if (response && response.playerData && response.playerData.videoDetails) {
            NSMutableArray *thumbnails = response.playerData.videoDetails.thumbnail.thumbnailsArray;
            if (thumbnails.count > 0) {
                YTIThumbnailDetails_Thumbnail *thumb = [thumbnails lastObject];
                NSString *urlStr = thumb.URL;
                if (urlStr.length > 0) {
                    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                        NSData *data = [NSData dataWithContentsOfURL:[NSURL URLWithString:urlStr]];
                        if (data) {
                            UIImage *img = [UIImage imageWithData:data];
                            if (img) {
                                dispatch_async(dispatch_get_main_queue(), ^{
                                    if (gSharedAmbientView) {
                                        [gSharedAmbientView updateWithArtworkImage:img animated:YES];
                                    }
                                    if (gBrowseAmbientView) {
                                        [gBrowseAmbientView updateWithArtworkImage:img animated:YES];
                                    }
                                    [[NSNotificationCenter defaultCenter] postNotificationName:@"YTMArtworkDidUpdateNotification" object:img];
                                });
                            }
                        }
                    });
                }
            }
        }
    } @catch (NSException *e) {}
}

- (void)singleVideo:(id)video currentVideoTimeDidChange:(id)time {
    %orig;
    @try {
        CGFloat current = [self currentVideoMediaTime];
        CGFloat total = [self currentVideoTotalMediaTime];
        if (total > 0) {
            [[AudioCrossfadeManager sharedInstance] didUpdatePlaybackTime:current duration:total];
            [[NetworkBufferOptimizer sharedInstance] trackProgressDidChangeCurrent:current total:total];
            YTMFeedFallbackCrossfadeTime(self, current, total);
        }
    } @catch (NSException *e) {}
}

- (void)potentiallyMutatedSingleVideo:(id)video currentVideoTimeDidChange:(id)time {
    %orig;
    @try {
        CGFloat current = [self currentVideoMediaTime];
        CGFloat total = [self currentVideoTotalMediaTime];
        if (total > 0) {
            [[AudioCrossfadeManager sharedInstance] didUpdatePlaybackTime:current duration:total];
            [[NetworkBufferOptimizer sharedInstance] trackProgressDidChangeCurrent:current total:total];
            YTMFeedFallbackCrossfadeTime(self, current, total);
        }
    } @catch (NSException *e) {}
}

- (void)seekToTime:(CGFloat)time {
    @try {
        [[AudioCrossfadeManager sharedInstance] notifyManualSkipOccurred];
        [[LGCrossfade shared] cancel];
    } @catch (NSException *e) {}
    %orig(time);
}

%end

#pragma mark - Now Playing Liquid Glass Backdrop

%hook YTMNowPlayingViewController

- (void)viewDidLoad {
    %orig;
    gCurrentNowPlayingVC = self;
    self.view.backgroundColor = [UIColor clearColor];
    [[AudioCrossfadeManager sharedInstance] registerNowPlayingViewController:self];
    if (!gSharedAmbientView) {
        gSharedAmbientView = [[AmbientView alloc] initWithFrame:self.view.bounds];
        gSharedAmbientView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self.view insertSubview:gSharedAmbientView atIndex:0];
    }
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    gCurrentNowPlayingVC = self;
    [[AudioCrossfadeManager sharedInstance] registerNowPlayingViewController:self];
}

- (void)viewDidLayoutSubviews {
    %orig;
    self.view.backgroundColor = [UIColor clearColor];
    if (gSharedAmbientView) {
        gSharedAmbientView.frame = self.view.bounds;
        [self.view sendSubviewToBack:gSharedAmbientView];
    }
    for (UIView *subview in self.view.subviews) {
        // Preserve video playback layers so Video mode is never broken
        if (subview != gSharedAmbientView && ![subview isKindOfClass:%c(YTPlayerView)] && ![subview isKindOfClass:%c(HAMVideoView)]) {
            if ([subview.backgroundColor isEqual:[UIColor blackColor]]) {
                subview.backgroundColor = [UIColor clearColor];
            }
        }
    }
}

- (void)didTapNextButton {
    if (!gProgrammaticAdvance) {
        @try {
            [[AudioCrossfadeManager sharedInstance] notifyManualSkipOccurred];
            [[LGCrossfade shared] cancel];
        } @catch (NSException *e) {}
    }
    %orig;
}

- (void)didTapPrevButton {
    @try {
        [[AudioCrossfadeManager sharedInstance] notifyManualSkipOccurred];
        [[LGCrossfade shared] cancel];
    } @catch (NSException *e) {}
    %orig;
}

%end

#pragma mark - Browse Liquid Glass Backdrop

@interface LGObserverBox : NSObject
@property (nonatomic, strong) id token;
@end
@implementation LGObserverBox
- (void)dealloc {
    if (_token) [[NSNotificationCenter defaultCenter] removeObserver:_token];
}
@end

static char kLGViewObserverKey;
static void LGRegisterViewForPaletteUpdates(UIView *view, void (^onChange)(UIView *v, LGPalette *p, BOOL dark, BOOL staticMode)) {
    if (!view || objc_getAssociatedObject(view, &kLGViewObserverKey)) return;
    LGObserverBox *box = [LGObserverBox new];
    __weak UIView *weakView = view;
    box.token = LGObserveTheme(^(LGPalette *p, BOOL dark, BOOL staticMode) {
        UIView *strongView = weakView;
        if (strongView && onChange) onChange(strongView, p, dark, staticMode);
    });
    objc_setAssociatedObject(view, &kLGViewObserverKey, box, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

@interface YTMActionRowView : UIView
@end

%hook YTMActionRowView
- (void)layoutSubviews {
    %orig;
    LGRegisterViewForPaletteUpdates(self, ^(UIView *v, __unused LGPalette *p, __unused BOOL dark, __unused BOOL staticMode) { [v setNeedsLayout]; });
    LGTheme *t = LGTheme.shared;
    self.backgroundColor = [UIColor clearColor];
    for (UIView *sub in self.subviews) {
        sub.backgroundColor = [UIColor clearColor];
        if ([sub isKindOfClass:[UIScrollView class]]) {
            for (UIView *btn in sub.subviews) {
                if ([btn isKindOfClass:[UIButton class]] || [btn isKindOfClass:%c(MDCButton)]) {
                    if (t.staticMode) {
                        btn.backgroundColor = t.palette.b2;
                        btn.layer.borderWidth = 1.0f;
                        btn.layer.borderColor = [UIColor colorWithWhite:0.5f alpha:0.35f].CGColor;
                    } else {
                        btn.backgroundColor = [UIColor colorWithWhite:1.0f alpha:(t.dark ? 0.09f : 0.55f)];
                        btn.layer.borderWidth = 1.0f;
                        btn.layer.borderColor = [UIColor colorWithWhite:1.0f alpha:(t.dark ? 0.20f : 0.80f)].CGColor;
                    }
                    btn.layer.cornerRadius = 18.0f;
                    btn.clipsToBounds = YES;
                }
            }
        }
    }
}
%end

%hook YTMBrowseViewController

- (void)viewDidLoad {
    %orig;
    AmbientView *ambient = [[AmbientView alloc] initWithFrame:self.view.bounds];
    ambient.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view insertSubview:ambient atIndex:0];
    self.view.backgroundColor = [UIColor clearColor];
}

- (void)viewDidLayoutSubviews {
    %orig;
    self.view.backgroundColor = [UIColor clearColor];
}

%end

#pragma mark - AVFoundation Layer Hooks

%hook AVSampleBufferAudioRenderer

- (instancetype)init {
    id obj = %orig;
    if (obj) {
        YTMInstallCrossfadeAdapters();
        @synchronized(gAudioLock) {
            [gTrackedRenderers addObject:obj];
            gObservedAudioBackend = @"AVSampleBufferAudioRenderer";
            if (gCurrentNativeGain < 0.999f) YTMApplyNativeGainToObject(obj, gCurrentNativeGain);
        }
    }
    return obj;
}

- (void)enqueueSampleBuffer:(CMSampleBufferRef)sampleBuffer {
    YTMInstallCrossfadeAdapters();
    @synchronized(gAudioLock) {
        if (![gTrackedRenderers containsObject:self]) [gTrackedRenderers addObject:self];
        gObservedAudioBackend = @"AVSampleBufferAudioRenderer";
        if (gCurrentNativeGain < 0.999f) YTMApplyNativeGainToObject(self, gCurrentNativeGain);
    }
    %orig;
}

%end

%hook AVPlayer

- (void)play {
    %orig;
    if (objc_getAssociatedObject(self, "LGTailPlayer")) return;
    YTMInstallCrossfadeAdapters();
    @synchronized(gAudioLock) {
        [gTrackedPlayers addObject:self];
        if ([gObservedAudioBackend isEqualToString:@"none yet"]) gObservedAudioBackend = @"AVPlayer";
        if (gCurrentNativeGain < 0.999f) YTMApplyNativeGainToObject(self, gCurrentNativeGain);
    }
    @try {
        [[AudioCrossfadeManager sharedInstance] registerActivePlayer:self];
    } @catch (NSException *e) {}
}

- (void)replaceCurrentItemWithPlayerItem:(AVPlayerItem *)item {
    %orig(item);
    if (objc_getAssociatedObject(self, "LGTailPlayer")) return;
    YTMInstallCrossfadeAdapters();
    @synchronized(gAudioLock) {
        [gTrackedPlayers addObject:self];
        if ([gObservedAudioBackend isEqualToString:@"none yet"]) gObservedAudioBackend = @"AVPlayer";
        if (gCurrentNativeGain < 0.999f) YTMApplyNativeGainToObject(self, gCurrentNativeGain);
    }
    @try {
        [[AudioCrossfadeManager sharedInstance] registerActivePlayer:self];
    } @catch (NSException *e) {}
}

%end

%hook AVAudioEngine

- (BOOL)startAndReturnError:(NSError **)outError {
    BOOL ok = %orig;
    if (ok) {
        YTMInstallCrossfadeAdapters();
        @synchronized(gAudioLock) {
            [gTrackedEngines addObject:self];
            if ([gObservedAudioBackend isEqualToString:@"none yet"]) gObservedAudioBackend = @"AVAudioEngine";
            if (gCurrentNativeGain < 0.999f) YTMApplyNativeGainToObject(self, gCurrentNativeGain);
        }
    }
    return ok;
}

%end

#pragma mark - Dynamic Theme Accent Hooks

static void LGApplySliderPalette(UISlider *slider, LGPalette *p) {
    if (p.a1) slider.minimumTrackTintColor = p.a1;
    if (p.tx) slider.thumbTintColor = p.tx;
}

%hook UISlider

- (void)didMoveToWindow {
    %orig;
    if (self.window) {
        LGRegisterViewForPaletteUpdates(self, ^(UIView *v, LGPalette *p, __unused BOOL dark, __unused BOOL staticMode) {
            if ([v isKindOfClass:[UISlider class]]) LGApplySliderPalette((UISlider *)v, p);
        });
    }
}

%end

%hook YTPivotBarItemView

- (void)layoutSubviews {
    %orig;
    LGRegisterViewForPaletteUpdates(self, ^(UIView *v, __unused LGPalette *p, __unused BOOL dark, __unused BOOL staticMode) { [v setNeedsLayout]; });
    if ([self respondsToSelector:@selector(navigationButton)]) {
        UIView *btn = (UIView *)[self performSelector:@selector(navigationButton)];
        if (btn && [btn respondsToSelector:@selector(isSelected)]) {
            BOOL isSel = ((BOOL (*)(id, SEL))objc_msgSend)(btn, @selector(isSelected));
            LGPalette *p = LGTheme.shared.palette;
            if (isSel && p.a1) {
                [btn setTintColor:p.a1];
            } else if (!isSel && p.mu) {
                [btn setTintColor:p.mu];
            }
        }
    }
}

%end

%hook YTPivotBarView

- (void)layoutSubviews {
    %orig;
    LGRegisterViewForPaletteUpdates(self, ^(UIView *v, __unused LGPalette *p, __unused BOOL dark, __unused BOOL staticMode) { [v setNeedsLayout]; });
    self.backgroundColor = [UIColor clearColor];
    self.layer.cornerRadius = 0.0f;
    self.layer.borderWidth = 0.0f;
    self.layer.shadowOpacity = 0.0f;
    if ([self respondsToSelector:@selector(contentView)]) {
        UIView *cv = (UIView *)[self performSelector:@selector(contentView)];
        if (cv) cv.backgroundColor = [UIColor clearColor];
    }
}

%end

%ctor {
    NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithDictionary:[[NSUserDefaults standardUserDefaults] dictionaryForKey:@"YTMUltimate"]];
    if (dict[@"appleCrossfade"] == nil) dict[@"appleCrossfade"] = @(1);
    if (dict[@"appleCrossfadeDuration"] == nil) dict[@"appleCrossfadeDuration"] = @(6.0f);
    if (dict[@"appleCrossfadeGaplessBypass"] == nil) dict[@"appleCrossfadeGaplessBypass"] = @(0);
    if (dict[@"appleDeepBuffer"] == nil) dict[@"appleDeepBuffer"] = @(0);
    if (dict[@"applePrefetchNext"] == nil) dict[@"applePrefetchNext"] = @(0);
    [[NSUserDefaults standardUserDefaults] setObject:dict forKey:@"YTMUltimate"];

    YTMInstallCrossfadeAdapters();
    %init;
}
