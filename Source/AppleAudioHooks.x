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
static __weak id gYTMSettings = nil;
static __weak id gActiveSequencer = nil;
static __weak id gActiveMultiPlayer = nil;
static NSURL *gCurrentTrackStreamURL = nil;
static NSString *gCurrentStreamVideoID = nil;

static NSHashTable *gTrackedRenderers = nil;
static NSHashTable *gTrackedHAMPlayers = nil;
static NSHashTable *gTrackedPlayers = nil;
static NSHashTable *gTrackedEngines = nil;
static NSString *gAudioLock = @"YTM_AUDIO_LOCK";
static float gCurrentNativeGain = 1.0f;
static __thread BOOL tApplyingNativeGain = NO;
static __thread BOOL tSyncingNativeSettings = NO;
static BOOL gProgrammaticAdvance = NO;
static NSString *gObservedAudioBackend = @"none yet";

@interface MLHAMPlayer : NSObject
@property (nonatomic, assign) float volume;
@end

@interface HAMPlayer : NSObject
@property (nonatomic, assign) float volume;
@end

@interface YTMSettingsImpl : NSObject
- (BOOL)isCrossfadeEnabled;
- (void)setCrossfadeEnabled:(BOOL)enabled;
- (NSInteger)crossfadeDuration;
- (void)setCrossfadeDuration:(NSInteger)duration;
@end

@interface YTMPlayerSequencerController : NSObject
- (void)updateCrossfadeTransitionInActiveSequence;
@end

@interface YTCrossfadeTransition : NSObject
- (instancetype)initWithDuration:(double)duration;
@end

@interface MLHAMQueuePlayerContext : NSObject
@property (nonatomic, assign) double crossfadeDuration;
@end

@interface YTIPlayerResponse (LGCrossfadeNative)
- (id)trackAlbumMetadata;
@end

@interface LGAlbumMeta : NSObject
- (NSString *)externalPlaylistId;
- (BOOL)hasTrackNumber;
- (int32_t)trackNumber;
- (BOOL)isLive;
@end

void YTMNotifyNativeCrossfadeSettingsChanged(BOOL enabled, double duration) {
    dispatch_async(dispatch_get_main_queue(), ^{
        id settings = gYTMSettings;
        id seq = gActiveSequencer;
        tSyncingNativeSettings = YES;
        @try {
            if (settings) {
                if ([settings respondsToSelector:@selector(setCrossfadeEnabled:)]) {
                    [(YTMSettingsImpl *)settings setCrossfadeEnabled:enabled];
                }
                if ([settings respondsToSelector:@selector(setCrossfadeDuration:)]) {
                    [(YTMSettingsImpl *)settings setCrossfadeDuration:(NSInteger)MAX(1, llround(duration))];
                }
            }
            if (seq && [seq respondsToSelector:@selector(updateCrossfadeTransitionInActiveSequence)]) {
                [(YTMPlayerSequencerController *)seq updateCrossfadeTransitionInActiveSequence];
            }
        } @catch (__unused NSException *e) {}
        tSyncingNativeSettings = NO;
        [LGCrossfade shared].nativeStatusDetail = enabled
            ? [NSString stringWithFormat:@"armed (%.1fs)", duration]
            : @"disabled";
    });
}

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

        // Prefer progressive audio/mp4 stream URL (checking both mimeType selector & URL query params)
        if ([sd respondsToSelector:@selector(adaptiveFormatsArray)]) {
            NSURL *fallbackWebMOrOther = nil;
            for (YTIFormatStream *fs in sd.adaptiveFormatsArray) {
                NSString *urlStr = [fs respondsToSelector:@selector(URL)] ? fs.URL : nil;
                if (urlStr.length == 0) continue;
                NSString *mime = [fs respondsToSelector:@selector(mimeType)] ? [fs performSelector:@selector(mimeType)] : nil;
                BOOL isAudioMP4 = ([mime isKindOfClass:[NSString class]] && [mime containsString:@"audio/mp4"]) ||
                                  [urlStr containsString:@"mime=audio%2Fmp4"] ||
                                  [urlStr containsString:@"mime=audio/mp4"] ||
                                  [urlStr containsString:@"itag=140"] ||
                                  [urlStr containsString:@"itag=139"];
                if (isAudioMP4) {
                    return [NSURL URLWithString:urlStr];
                }
                if (!fallbackWebMOrOther && ([urlStr containsString:@"mime=audio"] || ([mime isKindOfClass:[NSString class]] && [mime hasPrefix:@"audio/"]))) {
                    fallbackWebMOrOther = [NSURL URLWithString:urlStr];
                }
            }
            // Note: AVPlayer cannot decode WebM/Opus, so prefer HLS audio over WebM if MP4 wasn't found
        }
        // Fallback to HLS manifest URL (LGCrossfade resolves audio-only sub-playlist from it)
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

#pragma mark - Native YouTube Music Dual-Deck Crossfade Unlock & Telemetry

%group NativeXfadeSharedConfigGroup
%hook YTColdConfigIosPlayerClientSharedConfigImpl

- (BOOL)enableCrossfade {
    return YES;
}

- (BOOL)enableVolumeFading {
    return YES;
}

%end
%end

%group NativeXfadePlaybackConfigGroup
%hook YTColdConfigMusicPlaybackClientConfigImpl

- (BOOL)iosEnableCrossfade {
    return YES;
}

%end
%end

%group NativeXfadeSettingsGroup
%hook YTMSettingsImpl

- (BOOL)isCrossfadeEnabled {
    gYTMSettings = self;
    return [LGCrossfade shared].enabled;
}

- (NSInteger)crossfadeDuration {
    gYTMSettings = self;
    return (NSInteger)MAX(1, llround([LGCrossfade shared].seconds));
}

- (void)setCrossfadeEnabled:(BOOL)enabled {
    gYTMSettings = self;
    %orig(enabled);
    if (!tSyncingNativeSettings) {
        [AudioCrossfadeManager sharedInstance].crossfadeEnabled = enabled;
        [[AudioCrossfadeManager sharedInstance] saveSettings];
    }
}

- (void)setCrossfadeDuration:(NSInteger)duration {
    gYTMSettings = self;
    %orig(duration);
    if (!tSyncingNativeSettings && duration >= 1 && duration <= 12) {
        [AudioCrossfadeManager sharedInstance].crossfadeDuration = (CGFloat)duration;
        [[AudioCrossfadeManager sharedInstance] saveSettings];
    }
}

%end
%end

%group NativeXfadeUserDefaultsGroup
%hook YTUserDefaults

- (BOOL)isCrossfadeEnabled {
    return [LGCrossfade shared].enabled;
}

- (NSInteger)crossfadeDuration {
    return (NSInteger)MAX(1, llround([LGCrossfade shared].seconds));
}

%end
%end

%group NativeXfadePolicyGroup
%hook YTMCrossfadeTransitionPolicy

+ (BOOL)isCrossfadeTransitionEnabledForCurrentPlayerResponse:(id)curr upcomingPlayerResponse:(id)next {
    if (![LGCrossfade shared].enabled || !curr || !next) {
        return NO;
    }
    @try {
        id currData = [curr respondsToSelector:@selector(playerData)] ? [(YTPlayerResponse *)curr playerData] : nil;
        id nextData = [next respondsToSelector:@selector(playerData)] ? [(YTPlayerResponse *)next playerData] : nil;
        if (!currData || !nextData) return NO;

        id vd1 = [currData respondsToSelector:@selector(videoDetails)] ? [(YTIPlayerResponse *)currData videoDetails] : nil;
        id vd2 = [nextData respondsToSelector:@selector(videoDetails)] ? [(YTIPlayerResponse *)nextData videoDetails] : nil;
        if ((vd1 && [vd1 respondsToSelector:@selector(isLive)] && [(LGAlbumMeta *)vd1 isLive]) ||
            (vd2 && [vd2 respondsToSelector:@selector(isLive)] && [(LGAlbumMeta *)vd2 isLive])) {
            [LGCrossfade shared].nativeStatusDetail = @"skipped (live stream)";
            return NO;
        }

        if ([AudioCrossfadeManager sharedInstance].gaplessBypassEnabled) {
            id m1 = [currData respondsToSelector:@selector(trackAlbumMetadata)] ? [(YTIPlayerResponse *)currData trackAlbumMetadata] : nil;
            id m2 = [nextData respondsToSelector:@selector(trackAlbumMetadata)] ? [(YTIPlayerResponse *)nextData trackAlbumMetadata] : nil;
            NSString *p1 = (m1 && [m1 respondsToSelector:@selector(externalPlaylistId)]) ? [(LGAlbumMeta *)m1 externalPlaylistId] : nil;
            NSString *p2 = (m2 && [m2 respondsToSelector:@selector(externalPlaylistId)]) ? [(LGAlbumMeta *)m2 externalPlaylistId] : nil;
            if (p1.length > 0 && [p1 isEqualToString:p2] &&
                [m1 respondsToSelector:@selector(hasTrackNumber)] && [(LGAlbumMeta *)m1 hasTrackNumber] &&
                [m2 respondsToSelector:@selector(hasTrackNumber)] && [(LGAlbumMeta *)m2 hasTrackNumber]) {
                int32_t t1 = [(LGAlbumMeta *)m1 trackNumber];
                int32_t t2 = [(LGAlbumMeta *)m2 trackNumber];
                if (t2 == t1 + 1) {
                    [LGCrossfade shared].nativeStatusDetail = @"gapless album track (bypassed)";
                    return NO;
                }
            }
        }
    } @catch (__unused NSException *e) {}

    [LGCrossfade shared].nativeStatusDetail = [NSString stringWithFormat:@"armed (%.1fs)", [LGCrossfade shared].seconds];
    return YES;
}

%end
%end

%group NativeXfadeSequencerGroup
%hook YTMPlayerSequencerController

- (instancetype)initWithPlayerViewController:(id)pvc {
    id obj = %orig;
    if (obj) {
        gActiveSequencer = obj;
        @try {
            [obj setValue:@YES forKey:@"_enableCrossfade"];
        } @catch (__unused NSException *e) {}
    }
    return obj;
}

- (void)setQueueController:(id)qc {
    %orig;
    gActiveSequencer = self;
}

- (id)crossfadeTransitionFromSettings {
    if (![LGCrossfade shared].enabled) return nil;
    Class cls = objc_getClass("YTCrossfadeTransition");
    if (cls) {
        double secs = [LGCrossfade shared].seconds;
        return [[cls alloc] initWithDuration:secs];
    }
    return %orig;
}

- (void)updateCrossfadeTransitionInActiveSequence {
    gActiveSequencer = self;
    %orig;
    [LGCrossfade shared].nativeStatusDetail = [LGCrossfade shared].enabled
        ? [NSString stringWithFormat:@"armed (%.1fs)", [LGCrossfade shared].seconds]
        : @"disabled";
}

%end
%end

%group MLHAMMultiGroup
%hook MLHAMMultiPlayer

- (instancetype)initWithStickySettings:(id)a playerViewProvider:(id)b mediaPlayerResources:(id)c {
    id obj = %orig;
    if (obj) {
        gActiveMultiPlayer = obj;
        YTMInstallCrossfadeAdapters();
        @synchronized(gAudioLock) {
            [gTrackedHAMPlayers addObject:obj];
            gObservedAudioBackend = @"MLHAMMultiPlayer (Native Dual-Deck)";
        }
        [LGCrossfade shared].nativeMultiPlayerActive = YES;
        [LGCrossfade shared].nativeStatusDetail = [LGCrossfade shared].enabled
            ? [NSString stringWithFormat:@"armed (%.1fs)", [LGCrossfade shared].seconds]
            : @"disabled";
    }
    return obj;
}

- (void)load {
    %orig;
    gActiveMultiPlayer = self;
    [LGCrossfade shared].nativeMultiPlayerActive = YES;
    @synchronized(gAudioLock) {
        if (![gTrackedHAMPlayers containsObject:self]) [gTrackedHAMPlayers addObject:self];
        gObservedAudioBackend = @"MLHAMMultiPlayer (Native Dual-Deck)";
    }
}

- (BOOL)shouldApplyTransitionEffect:(id)effect previousClip:(id)prevClip toClip:(id)toClip {
    BOOL apply = %orig;
    [LGCrossfade shared].nativeMultiPlayerActive = YES;
    if (!apply && [LGCrossfade shared].enabled) {
        [LGCrossfade shared].nativeStatusDetail = @"transition skipped (route/policy)";
    }
    return apply;
}

- (void)spawnCrossfadeWithActiveContext:(id)activeCtx activeClip:(id)activeClip nextContext:(id)nextCtx {
    double dur = 0.0;
    @try {
        if (nextCtx && [nextCtx respondsToSelector:@selector(crossfadeDuration)]) {
            dur = [(MLHAMQueuePlayerContext *)nextCtx crossfadeDuration];
        }
    } @catch (__unused NSException *e) {}
    [LGCrossfade shared].nativeMultiPlayerActive = YES;
    [LGCrossfade shared].nativeStatusDetail = [NSString stringWithFormat:@"OVERLAP MIXING (%.1fs)!", dur > 0 ? dur : [LGCrossfade shared].seconds];
    %orig;
    double resetAfter = MAX(1.5, (dur > 0 ? dur : [LGCrossfade shared].seconds) + 0.5);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(resetAfter * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if ([LGCrossfade shared].nativeMultiPlayerActive) {
            [LGCrossfade shared].nativeStatusDetail = [LGCrossfade shared].enabled
                ? [NSString stringWithFormat:@"armed (%.1fs)", [LGCrossfade shared].seconds]
                : @"disabled";
        }
    });
}

- (void)logCrossfadeTransitionRejected:(id)reason previousClip:(id)prevClip toClip:(id)toClip {
    %orig;
    [LGCrossfade shared].nativeStatusDetail = [NSString stringWithFormat:@"rejected: %@", reason ?: @"unknown"];
}

- (void)setVolume:(float)volume {
    if (tApplyingNativeGain) {
        %orig(volume);
        return;
    }
    @synchronized(gAudioLock) {
        if (![gTrackedHAMPlayers containsObject:self]) [gTrackedHAMPlayers addObject:self];
        gObservedAudioBackend = @"MLHAMMultiPlayer (Native Dual-Deck)";
    }
    %orig(volume * gCurrentNativeGain);
}

%end
%end

%group MLHAMQueueGroup
%hook MLHAMQueuePlayer

- (void)setStartedTrackRenderers:(id)arg1 {
    %orig;
    @synchronized(gAudioLock) {
        if (![gTrackedHAMPlayers containsObject:self]) [gTrackedHAMPlayers addObject:self];
        if (!gActiveMultiPlayer) gObservedAudioBackend = @"MLHAMQueuePlayer+HAMSBAR";
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

%group HAMSBARGroup
%hook HAMSBARAudioTrackRenderer

- (void)setVolume:(float)volume {
    if (tApplyingNativeGain) {
        %orig(volume);
        return;
    }
    @synchronized(gAudioLock) {
        if (![gTrackedRenderers containsObject:self]) [gTrackedRenderers addObject:self];
        if ([gObservedAudioBackend isEqualToString:@"none yet"]) gObservedAudioBackend = @"HAMSBARAudioTrackRenderer";
    }
    %orig(volume * gCurrentNativeGain);
}

%end
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
    if (objc_getClass("MLHAMPlayer")) %init(MLHAMGroup);
    if (objc_getClass("HAMPlayer")) %init(HAMGroup);
    if (objc_getClass("YTColdConfigIosPlayerClientSharedConfigImpl")) %init(NativeXfadeSharedConfigGroup);
    if (objc_getClass("YTColdConfigMusicPlaybackClientConfigImpl")) %init(NativeXfadePlaybackConfigGroup);
    if (objc_getClass("YTMSettingsImpl")) %init(NativeXfadeSettingsGroup);
    if (objc_getClass("YTUserDefaults")) %init(NativeXfadeUserDefaultsGroup);
    if (objc_getClass("YTMCrossfadeTransitionPolicy")) %init(NativeXfadePolicyGroup);
    if (objc_getClass("YTMPlayerSequencerController")) %init(NativeXfadeSequencerGroup);
    if (objc_getClass("MLHAMMultiPlayer")) %init(MLHAMMultiGroup);
    if (objc_getClass("MLHAMQueuePlayer")) %init(MLHAMQueueGroup);
    if (objc_getClass("HAMSBARAudioTrackRenderer")) %init(HAMSBARGroup);
}
