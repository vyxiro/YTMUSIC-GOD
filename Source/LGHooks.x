// LGHooks.x : MPNowPlayingInfoCenter ambient ingestion + safe Phase 2 runtime view hierarchy dumper.
// Zero unconfirmed YouTube class hooks. Nothing touches UIKit inside %ctor.
#import "LiquidGlass.h"
#import <MediaPlayer/MediaPlayer.h>
#import <objc/runtime.h>

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

    // Also emit the compact key-views table to NSLog in 800-char chunks so syslog/Console captures it.
    NSRange keyStart = [out rangeOfString:@"=== Key Views"];
    NSRange recStart = [out rangeOfString:@"=== [window recursiveDescription]"];
    if (keyStart.location != NSNotFound && recStart.location != NSNotFound && recStart.location > keyStart.location) {
        NSString *summary = [out substringWithRange:NSMakeRange(0, recStart.location)];
        NSUInteger len = summary.length, pos = 0;
        while (pos < len) {
            NSUInteger chunk = MIN(800, len - pos);
            NSLog(@"[LG_DUMP] %@", [summary substringWithRange:NSMakeRange(pos, chunk)]);
            pos += chunk;
        }
    }
}

%hook MPNowPlayingInfoCenter
- (void)setNowPlayingInfo:(NSDictionary *)info {
    %orig;
    LGIngestNowPlayingInfo(info);
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
