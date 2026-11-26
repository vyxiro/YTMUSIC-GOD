// LGHooks.x : MPNowPlayingInfoCenter hook + Step 1 ambient & audio discovery diagnostics + Phase 2 view dumper.
// Zero unconfirmed YouTube class hooks. Nothing touches UIKit inside %ctor.
#import "LiquidGlass.h"
#import "LGCrossfade.h"
#import "AudioCrossfadeManager.h"
#import <MediaPlayer/MediaPlayer.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>

extern NSString *YTMObservedAudioBackend(void);

static BOOL gMPClassExistedAtInstall = NO;

@interface UIView (LGDebugPrivate)
- (NSString *)recursiveDescription;
- (id)_viewControllerForAncestor;
@end

@interface UIViewController (LGDebugPrivate)
- (NSString *)_printHierarchy;
@end

static NSString *LGDescribeColor(UIColor *c) {
    if (!c) return @"nil";
    if ([c isEqual:UIColor.clearColor]) return @"clear";
    CGFloat r = 0, g = 0, b = 0, a = 0;
    if ([c getRed:&r green:&g blue:&b alpha:&a]) {
        return [NSString stringWithFormat:@"#%02X%02X%02X(a=%.2f)", (int)round(r * 255), (int)round(g * 255), (int)round(b * 255), a];
    }
    return c.description;
}

static void LGWalkViews(UIView *v, UIWindow *win, int depth, NSMutableString *out) {
    if (!v || depth > 24) return;
    CGRect wf = [v convertRect:v.bounds toView:win];
    CGFloat winW = MAX(1.0, win.bounds.size.width);
    BOOL interesting = (wf.size.width >= winW * 0.45 && wf.size.height >= 28) ||
                       (v.backgroundColor && ![v.backgroundColor isEqual:UIColor.clearColor]) ||
                       v.clipsToBounds || v.opaque;
    if (interesting) {
        id vc = [v respondsToSelector:@selector(_viewControllerForAncestor)] ? [v _viewControllerForAncestor] : nil;
        NSString *vcName = vc ? NSStringFromClass([vc class]) : @"-";
        NSString *indent = [@"" stringByPaddingToLength:(depth * 2) withString:@" " startingAtIndex:0];
        [out appendFormat:@"%@%@ frame=(%.0f,%.0f %.0fx%.0f) opq=%d clip=%d a=%.2f bg=%@ vc=%@\n",
         indent, NSStringFromClass([v class]),
         wf.origin.x, wf.origin.y, wf.size.width, wf.size.height,
         v.opaque, v.clipsToBounds, v.alpha, LGDescribeColor(v.backgroundColor), vcName];
    }
    for (UIView *sub in v.subviews) {
        LGWalkViews(sub, win, depth + 1, out);
    }
}

static void LGDumpPaletteClasses(NSMutableString *out) {
    [out appendString:@"=== Palette & Theme Classes ===\n"];
    for (NSString *clsName in @[@"YTCommonColorPalette", @"YTMPlayerPageColorScheme", @"YTColor"]) {
        Class cls = NSClassFromString(clsName);
        if (!cls) {
            [out appendFormat:@"%@: NOT FOUND\n", clsName];
            continue;
        }
        [out appendFormat:@"%@: FOUND\n", clsName];
        unsigned int count = 0;
        Method *methods = class_copyMethodList(cls, &count);
        NSMutableArray *names = [NSMutableArray array];
        for (unsigned int i = 0; i < count && i < 60; i++) {
            [names addObject:NSStringFromSelector(method_getName(methods[i]))];
        }
        if (methods) free(methods);
        [out appendFormat:@"  instance methods (%u): %@\n", count, [names componentsJoinedByString:@", "]];
    }
}

static UIWindow *LGFindActiveWindow(void) {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if ([scene isKindOfClass:UIWindowScene.class]) {
            UIWindowScene *ws = (UIWindowScene *)scene;
            for (UIWindow *w in ws.windows) {
                if (w.isKeyWindow) return w;
            }
            if (ws.windows.firstObject) return ws.windows.firstObject;
        }
    }
    return UIApplication.sharedApplication.windows.firstObject;
}

static void LGDumpHierarchyToFile(NSString *filename, UIWindow *preferredWin) {
    UIWindow *win = preferredWin ?: LGFindActiveWindow();
    if (!win) return;

    NSMutableString *out = [NSMutableString string];
    [out appendFormat:@"=== LiquidGlass Discovery Dump: %@ ===\n", filename];
    [out appendFormat:@"Window: %@ frame=%@\n\n", NSStringFromClass([win class]), NSStringFromCGRect(win.bounds)];

    LGDumpPaletteClasses(out);
    [out appendString:@"\n=== ViewController Hierarchy ===\n"];
    if (win.rootViewController && [win.rootViewController respondsToSelector:@selector(_printHierarchy)]) {
        [out appendString:[win.rootViewController _printHierarchy] ?: @""];
    }

    [out appendString:@"\n=== Key Views (class, winFrame, opaque, clipsToBounds, bgColor, owningVC) ===\n"];
    LGWalkViews(win, win, 0, out);

    [out appendString:@"\n=== [window recursiveDescription] ===\n"];
    if ([win respondsToSelector:@selector(recursiveDescription)]) {
        [out appendString:[win recursiveDescription] ?: @""];
    }

    NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    if (docs) {
        NSString *path = [docs stringByAppendingPathComponent:filename];
        [out writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
        NSLog(@"[LG] Wrote discovery dump to %@", path);
    }
}

// Read-only runtime Audio & Now Playing probe (Audio Phase A: discovery only, zero hooks added).
NSString *LGBuildDiagnosticReport(void) {
    NSMutableString *out = [NSMutableString string];
    [out appendString:@"=== AMBIENT & NOW PLAYING DIAGNOSTICS ===\n"];
    [out appendFormat:@"MPNowPlayingInfoCenter existed at %%ctor: %@\n", gMPClassExistedAtInstall ? @"YES" : @"NO"];
    [out appendFormat:@"MPNowPlayingInfoCenter setNowPlayingInfo fires: %lu\n", (unsigned long)LGNowPlayingHookCount()];
    [out appendFormat:@"LGTheme.ambientStatus: %@\n", LGTheme.shared.ambientStatus];

    NSDictionary *curInfo = [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo;
    [out appendFormat:@"defaultCenter.nowPlayingInfo present: %@ (keys: %lu)\n",
     curInfo ? @"YES" : @"NO", (unsigned long)curInfo.count];
    if (curInfo) {
        MPMediaItemArtwork *art = curInfo[MPMediaItemPropertyArtwork];
        [out appendFormat:@"  Title: %@\n", curInfo[MPMediaItemPropertyTitle] ?: @"-"];
        [out appendFormat:@"  Artist: %@\n", curInfo[MPMediaItemPropertyArtist] ?: @"-"];
        [out appendFormat:@"  MPMediaItemPropertyArtwork: %@\n", art ? NSStringFromCGSize(art.bounds.size) : @"NO"];
        [out appendFormat:@"  Elapsed: %@ | Duration: %@\n",
         curInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] ?: @"-",
         curInfo[MPMediaItemPropertyPlaybackDuration] ?: @"-"];
    }

    [out appendString:@"\n=== AUDIO PHASE A PROBE (READ-ONLY) ===\n"];
    [out appendFormat:@"LGCrossfade.status: %@\n", LGCrossfade.shared.status];
    [out appendFormat:@"Observed native audio backend: %@\n", YTMObservedAudioBackend()];
    AudioCrossfadeManager *acm = [AudioCrossfadeManager sharedInstance];
    [out appendFormat:@"Crossfade enabled: %d | duration: %.1fs | isCrossfading: %d | videoID: %@\n",
     acm.crossfadeEnabled, acm.crossfadeDuration, acm.isCrossfading, [acm valueForKey:@"currentVideoID"] ?: @"-"];
    id activeP = [acm valueForKey:@"activePlayer"];
    id activeVC = [acm valueForKey:@"activePlayerVC"];
    id npVC = [acm valueForKey:@"nowPlayingVC"];
    [out appendFormat:@"activePlayer (AVPlayer): %@ | activePlayerVC: %@ | nowPlayingVC: %@\n",
     activeP ? NSStringFromClass([activeP class]) : @"nil",
     activeVC ? NSStringFromClass([activeVC class]) : @"nil",
     npVC ? NSStringFromClass([npVC class]) : @"nil"];

    AVAudioSession *sess = [AVAudioSession sharedInstance];
    [out appendFormat:@"AVAudioSession category=%@ mode=%@ sampleRate=%.0f outputVolume=%.2f\n",
     sess.category, sess.mode, sess.sampleRate, sess.outputVolume];

    [out appendString:@"\n--- Runtime Audio/Queue Classes ---\n"];
    unsigned int clsCount = 0;
    Class *classes = objc_copyClassList(&clsCount);
    NSMutableArray *hits = [NSMutableArray array];
    for (unsigned int i = 0; i < clsCount; i++) {
        const char *cname = class_getName(classes[i]);
        NSString *s = [NSString stringWithUTF8String:cname];
        if ([s containsString:@"HAMAudio"] || [s containsString:@"HAMPlayer"] ||
            [s containsString:@"HAMQueue"] || [s containsString:@"YTMQueue"] ||
            [s containsString:@"MLHAMQueue"] || [s containsString:@"AudioFade"] ||
            [s containsString:@"AudioTrackRenderer"] ||
            [s isEqualToString:@"YTPlayerViewController"] || [s isEqualToString:@"AVAudioEngine"]) {
            unsigned int mc = 0;
            Method *ms = class_copyMethodList(classes[i], &mc);
            NSMutableArray *interestingSel = [NSMutableArray array];
            for (unsigned int m = 0; m < mc; m++) {
                NSString *sel = NSStringFromSelector(method_getName(ms[m]));
                if ([sel localizedCaseInsensitiveContainsString:@"volume"] ||
                    [sel localizedCaseInsensitiveContainsString:@"gain"] ||
                    [sel localizedCaseInsensitiveContainsString:@"fade"] ||
                    [sel localizedCaseInsensitiveContainsString:@"clip"] ||
                    [sel localizedCaseInsensitiveContainsString:@"next"] ||
                    [sel localizedCaseInsensitiveContainsString:@"advance"] ||
                    [sel localizedCaseInsensitiveContainsString:@"player"] ||
                    [sel localizedCaseInsensitiveContainsString:@"audio"] ||
                    [sel localizedCaseInsensitiveContainsString:@"render"]) {
                    [interestingSel addObject:sel];
                    if (interestingSel.count >= 24) break;
                }
            }
            if (ms) free(ms);
            [hits addObject:[NSString stringWithFormat:@"%@ [%@]", s, [interestingSel componentsJoinedByString:@", "]]];
        }
    }
    if (classes) free(classes);
    for (NSString *h in [hits sortedArrayUsingSelector:@selector(compare:)]) {
        [out appendFormat:@"  %@\n", h];
    }

    NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    if (docs) {
        NSString *p = [docs stringByAppendingPathComponent:@"lg_audio_probe.txt"];
        [out writeToFile:p atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
    NSLog(@"[LG_AUDIO_PROBE]\n%@", out);
    return out;
}

%hook MPNowPlayingInfoCenter
- (void)setNowPlayingInfo:(NSDictionary *)info {
    %orig;
    LGIngestNowPlayingInfo(info);
    [[LGCrossfade shared] noteNowPlayingInfo:info];
}
%end

%hook UIViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    NSString *cls = NSStringFromClass([self class]);
    if ([cls containsString:@"NowPlaying"] || [cls containsString:@"WatchViewController"]) {
        static BOOL didDumpNP = NO;
        if (!didDumpNP) {
            didDumpNP = YES;
            __weak UIWindow *win = self.view.window;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                LGDumpHierarchyToFile(@"lg_dump_nowplaying.txt", win);
            });
        }
    }
}
%end

%ctor {
    gMPClassExistedAtInstall = (objc_getClass("MPNowPlayingInfoCenter") != Nil);
    NSLog(@"[LG] LGHooks %%ctor: MPNowPlayingInfoCenter exists=%@", gMPClassExistedAtInstall ? @"YES" : @"NO");
    %init;
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidFinishLaunchingNotification
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(__unused NSNotification *note) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            LGDumpHierarchyToFile(@"lg_dump_home.txt", nil);
        });
    }];
}
