#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <MediaPlayer/MediaPlayer.h>
#import <objc/message.h>
#import "AudioCrossfadeManager.h"
#import "LGCrossfade.h"
#import "NetworkBufferOptimizer.h"
#import "LiquidGlass.h"
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

@interface YTPlaybackController : NSObject
@end

static __weak YTPlayerViewController *gCurrentPlayerVC = nil;
static __weak id gCurrentNowPlayingVC = nil;
static NSURL *gCurrentTrackStreamURL = nil;
static NSString *gCurrentStreamVideoID = nil;

static NSHashTable *gTrackedRenderers = nil;
static NSHashTable *gTrackedHAMPlayers = nil;
static NSHashTable *gTrackedPlayers = nil;
static NSHashTable *gTrackedEngines = nil;
static NSString *gAudioLock = @"YTM_AUDIO_LOCK";
static float gCurrentNativeGain = 1.0f;
static __thread BOOL tApplyingNativeGain = NO;
static BOOL gProgrammaticAdvance = NO;
static NSString *gObservedAudioBackend = @"none yet";

@interface MLHAMPlayer : NSObject
@property (nonatomic, assign) float volume;
@end

@interface HAMPlayer : NSObject
@property (nonatomic, assign) float volume;
@end

NSString *YTMObservedAudioBackend(void) {
    @synchronized(gAudioLock) {
        return [NSString stringWithFormat:@"%@ (renderers=%lu, ham=%lu, players=%lu, engines=%lu, gain=%.2f)",
                gObservedAudioBackend,
                (unsigned long)gTrackedRenderers.count,
                (unsigned long)gTrackedHAMPlayers.count,
                (unsigned long)gTrackedPlayers.count,
                (unsigned long)gTrackedEngines.count,
                gCurrentNativeGain];
    }
}

static void YTMApplyNativeGainToObject(id obj, float gain) {
    if (!obj) return;
    tApplyingNativeGain = YES;
    @try {
        if ([obj isKindOfClass:[AVSampleBufferAudioRenderer class]]) {
            ((AVSampleBufferAudioRenderer *)obj).volume = gain;
        } else if ([obj isKindOfClass:[AVPlayer class]]) {
            ((AVPlayer *)obj).volume = gain;
        } else if ([obj isKindOfClass:[AVAudioEngine class]]) {
            ((AVAudioEngine *)obj).mainMixerNode.outputVolume = gain;
        } else if ([obj respondsToSelector:@selector(setVolume:)]) {
            ((void (*)(id, SEL, float))objc_msgSend)(obj, @selector(setVolume:), gain);
        }
    } @catch (__unused NSException *e) {}
    tApplyingNativeGain = NO;
}

static NSURL *YTMExtractBestAudioStreamURL(YTPlayerViewController *pvc) {
    if (!pvc || ![pvc respondsToSelector:@selector(playerResponse)]) return nil;
    @try {
        YTPlayerResponse *resp = pvc.playerResponse;
        YTIStreamingData *sd = resp.playerData.streamingData;
        if (!sd) return nil;

        // Prefer progressive audio/mp4 stream URL (instant seek & low memory in AVPlayer tail)
        if ([sd respondsToSelector:@selector(adaptiveFormatsArray)]) {
            for (YTIFormatStream *fs in sd.adaptiveFormatsArray) {
                NSString *urlStr = [fs respondsToSelector:@selector(URL)] ? fs.URL : nil;
                if (urlStr.length == 0) continue;
                if ([fs respondsToSelector:@selector(mimeType)]) {
                    NSString *mime = [fs performSelector:@selector(mimeType)];
                    if ([mime isKindOfClass:[NSString class]] && [mime containsString:@"audio/mp4"]) {
                        return [NSURL URLWithString:urlStr];
                    }
                }
            }
        }
        // Fallback to HLS manifest URL
        if ([sd respondsToSelector:@selector(hlsManifestURL)] && sd.hlsManifestURL.length > 0) {
            return [NSURL URLWithString:sd.hlsManifestURL];
        }
    } @catch (__unused NSException *e) {}
    return nil;
}

static void YTMInstallCrossfadeAdapters(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        @synchronized(gAudioLock) {
            if (!gTrackedRenderers) gTrackedRenderers = [NSHashTable weakObjectsHashTable];
            if (!gTrackedHAMPlayers) gTrackedHAMPlayers = [NSHashTable weakObjectsHashTable];
            if (!gTrackedPlayers) gTrackedPlayers = [NSHashTable weakObjectsHashTable];
            if (!gTrackedEngines) gTrackedEngines = [NSHashTable weakObjectsHashTable];
        }

        LGCrossfade *xf = LGCrossfade.shared;
        xf.setNativeGain = ^(float gain) {
            NSArray *renderers = nil, *ham = nil, *players = nil, *engines = nil;
            @synchronized(gAudioLock) {
                gCurrentNativeGain = gain;
                renderers = gTrackedRenderers.allObjects;
                ham = gTrackedHAMPlayers.allObjects;
                players = gTrackedPlayers.allObjects;
                engines = gTrackedEngines.allObjects;
            }
            for (id r in renderers) YTMApplyNativeGainToObject(r, gain);
            for (id h in ham) YTMApplyNativeGainToObject(h, gain);
            for (id p in players) YTMApplyNativeGainToObject(p, gain);
            for (id e in engines) YTMApplyNativeGainToObject(e, gain);
        };

        xf.advanceToNext = ^BOOL {
            id npVC = gCurrentNowPlayingVC;
            if (npVC && [npVC respondsToSelector:@selector(didTapNextButton)]) {
                gProgrammaticAdvance = YES;
                @try {
                    [npVC didTapNextButton];
                } @catch (__unused NSException *e) {
                    gProgrammaticAdvance = NO;
                    return NO;
                }
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    gProgrammaticAdvance = NO;
                });
                return YES;
            }
            return NO;
        };

        xf.currentStreamURL = ^NSURL * {
            @synchronized(gAudioLock) {
                if (gCurrentTrackStreamURL) return gCurrentTrackStreamURL;
            }
            YTPlayerViewController *pvc = gCurrentPlayerVC;
            return pvc ? YTMExtractBestAudioStreamURL(pvc) : nil;
        };
    });
}

static void YTMFeedLiveCrossfadeTime(YTPlayerViewController *pvc, CGFloat current, CGFloat total) {
    if (total <= 0 || current < 0) return;
    static CFTimeInterval sLastFeed = 0;
    CFTimeInterval now = CACurrentMediaTime();
    if (now - sLastFeed < 0.35) return;
    sLastFeed = now;

    NSString *vid = [pvc respondsToSelector:@selector(currentVideoID)] ? pvc.currentVideoID : nil;
    if (vid.length > 0 && ![vid isEqualToString:gCurrentStreamVideoID]) {
        NSURL *u = YTMExtractBestAudioStreamURL(pvc);
        @synchronized(gAudioLock) {
            gCurrentStreamVideoID = vid;
            gCurrentTrackStreamURL = u;
        }
    }
    [[LGCrossfade shared] noteLiveTime:(double)current total:(double)total trackID:vid];
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
        NSURL *streamURL = YTMExtractBestAudioStreamURL(self);
        @synchronized(gAudioLock) {
            gCurrentStreamVideoID = videoID;
            gCurrentTrackStreamURL = streamURL;
        }

        [[AudioCrossfadeManager sharedInstance] registerPlayerViewController:self];
        [[AudioCrossfadeManager sharedInstance] notifyTrackActivatedWithVideoID:videoID player:nil];
        [[LGCrossfade shared] noteTrackActivated:videoID];
        [[NetworkBufferOptimizer sharedInstance] notifyNewTrackLoadedWithVideoID:videoID];
        YTMFeedLiveCrossfadeTime(self, [self currentVideoMediaTime], [self currentVideoTotalMediaTime]);

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
                                    [LGTheme.shared ingestArtwork:img trackKey:(videoID ?: urlStr)];
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
            YTMFeedLiveCrossfadeTime(self, current, total);
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
            YTMFeedLiveCrossfadeTime(self, current, total);
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

#pragma mark - Now Playing VC Hooks

%hook YTMNowPlayingViewController

- (void)viewDidLoad {
    %orig;
    gCurrentNowPlayingVC = self;
    self.view.backgroundColor = [UIColor clearColor];
    [[AudioCrossfadeManager sharedInstance] registerNowPlayingViewController:self];
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    gCurrentNowPlayingVC = self;
    [[AudioCrossfadeManager sharedInstance] registerNowPlayingViewController:self];
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

#pragma mark - AVFoundation & HAMPlayer Audio Backend Hooks

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

- (void)setVolume:(float)volume {
    if (tApplyingNativeGain) {
        %orig(volume);
        return;
    }
    float scaled = volume * gCurrentNativeGain;
    @synchronized(gAudioLock) {
        if (![gTrackedRenderers containsObject:self]) [gTrackedRenderers addObject:self];
        gObservedAudioBackend = @"AVSampleBufferAudioRenderer";
    }
    %orig(scaled);
}

- (void)enqueueSampleBuffer:(CMSampleBufferRef)sampleBuffer {
    YTMInstallCrossfadeAdapters();
    float targetGain = 1.0f;
    BOOL needsUpdate = NO;
    @synchronized(gAudioLock) {
        if (![gTrackedRenderers containsObject:self]) [gTrackedRenderers addObject:self];
        if ([gObservedAudioBackend isEqualToString:@"none yet"]) gObservedAudioBackend = @"AVSampleBufferAudioRenderer";
        targetGain = gCurrentNativeGain;
        needsUpdate = (fabsf(((AVSampleBufferAudioRenderer *)self).volume - targetGain) > 0.02f);
    }
    if (needsUpdate) {
        YTMApplyNativeGainToObject(self, targetGain);
    }
    %orig;
}

%end

%group MLHAMGroup
%hook MLHAMPlayer

- (instancetype)initWithVideo:(id)a playerConfig:(id)b stickySettings:(id)c playerViewProvider:(id)d latencyLogger:(id)e reloadContext:(id)f mediaPlayerResources:(id)g recompositeProvider:(id)h {
    id obj = %orig;
    if (obj) {
        YTMInstallCrossfadeAdapters();
        @synchronized(gAudioLock) {
            [gTrackedHAMPlayers addObject:obj];
            gObservedAudioBackend = @"MLHAMPlayer+AVSampleBufferAudioRenderer";
            if (gCurrentNativeGain < 0.999f) YTMApplyNativeGainToObject(obj, gCurrentNativeGain);
        }
    }
    return obj;
}

- (instancetype)initWithVideo:(id)a playerConfig:(id)b stickySettings:(id)c playerViewProvider:(id)d playerConfiguration:(id)e queuePlayer:(id)f latencyLogger:(id)g reloadContext:(id)h mediaPlayerResources:(id)i recompositeProvider:(id)j {
    id obj = %orig;
    if (obj) {
        YTMInstallCrossfadeAdapters();
        @synchronized(gAudioLock) {
            [gTrackedHAMPlayers addObject:obj];
            gObservedAudioBackend = @"MLHAMPlayer+AVSampleBufferAudioRenderer";
            if (gCurrentNativeGain < 0.999f) YTMApplyNativeGainToObject(obj, gCurrentNativeGain);
        }
    }
    return obj;
}

- (void)setVolume:(float)volume {
    if (tApplyingNativeGain) {
        %orig(volume);
        return;
    }
    @synchronized(gAudioLock) {
        if (![gTrackedHAMPlayers containsObject:self]) [gTrackedHAMPlayers addObject:self];
        gObservedAudioBackend = @"MLHAMPlayer+AVSampleBufferAudioRenderer";
    }
    %orig(volume * gCurrentNativeGain);
}

%end
%end

%group HAMGroup
%hook HAMPlayer

- (void)setStartedTrackRenderers:(id)arg1 {
    %orig;
    @synchronized(gAudioLock) {
        if (![gTrackedHAMPlayers containsObject:self]) [gTrackedHAMPlayers addObject:self];
    }
    if (gCurrentNativeGain < 0.999f) YTMApplyNativeGainToObject(self, gCurrentNativeGain);
}

- (void)setVolume:(float)volume {
    if (tApplyingNativeGain) {
        %orig(volume);
        return;
    }
    @synchronized(gAudioLock) {
        if (![gTrackedHAMPlayers containsObject:self]) [gTrackedHAMPlayers addObject:self];
    }
    %orig(volume * gCurrentNativeGain);
}

%end
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
    if (objc_getClass("MLHAMPlayer")) {
        %init(MLHAMGroup);
    }
    if (objc_getClass("HAMPlayer")) {
        %init(HAMGroup);
    }
}
