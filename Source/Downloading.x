#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "FFMpegDownloader.h"
#import "Headers/YTUIResources.h"
#import "Headers/YTMActionSheetController.h"
#import "Headers/YTMActionRowView.h"
#import "Headers/YTIPlayerOverlayRenderer.h"
#import "Headers/YTIPlayerOverlayActionSupportedRenderers.h"
#import "Headers/YTMNowPlayingViewController.h"
#import "Headers/YTPlayerView.h"
#import "Headers/YTIThumbnailDetails_Thumbnail.h"
#import "Headers/YTIFormatStream.h"
#import "Headers/YTAlertView.h"
#import "Headers/ELMNodeController.h"

static BOOL YTMU(NSString *key) {
    NSDictionary *YTMUltimateDict = [[NSUserDefaults standardUserDefaults] dictionaryForKey:@"YTMUltimate"];
    return [YTMUltimateDict[key] boolValue];
}

@interface UIView ()
- (UIViewController *)_viewControllerForAncestor;
@end

@interface ELMTouchCommandPropertiesHandler : NSObject
- (void)downloadAudio:(YTPlayerViewController *)playerVC;
- (void)downloadCoverImage:(YTPlayerViewController *)playerVC;
- (NSString *)getURLFromManifest:(NSURL *)manifest;
@end

static NSMutableArray<FFMpegDownloader *> *gActiveDownloaders = nil;

static UIWindow *YTMUKeyWindow(void) {
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if (scene.activationState == UISceneActivationStateForegroundActive && [scene isKindOfClass:[UIWindowScene class]]) {
                for (UIWindow *w in ((UIWindowScene *)scene).windows) {
                    if (w.isKeyWindow) return w;
                }
                return ((UIWindowScene *)scene).windows.firstObject;
            }
        }
    }
    return [UIApplication sharedApplication].keyWindow;
}

static YTPlayerViewController *YTMUFindPlayerVCFromView(UIView *sourceView, UIViewController **outPresenterVC) {
    UIViewController *vc = [sourceView respondsToSelector:@selector(_viewControllerForAncestor)]
        ? [sourceView _viewControllerForAncestor]
        : nil;
    if (outPresenterVC) *outPresenterVC = vc;

    UIViewController *cur = vc;
    while (cur) {
        if ([cur respondsToSelector:@selector(playerViewController)]) {
            id pvc = [cur performSelector:@selector(playerViewController)];
            if (pvc && [pvc isKindOfClass:%c(YTPlayerViewController)]) {
                if (outPresenterVC) *outPresenterVC = cur;
                return (YTPlayerViewController *)pvc;
            }
        }
        cur = cur.parentViewController;
    }
    return nil;
}

static void YTMUShowInfoAlert(NSString *title, NSString *subtitle) {
    dispatch_async(dispatch_get_main_queue(), ^{
        Class alertCls = %c(YTAlertView);
        if (alertCls && [alertCls respondsToSelector:@selector(infoDialog)]) {
            YTAlertView *alertView = [alertCls infoDialog];
            alertView.title = title;
            alertView.subtitle = subtitle;
            [alertView show];
            return;
        }
        UIViewController *root = YTMUKeyWindow().rootViewController;
        while (root.presentedViewController) root = root.presentedViewController;
        if (root) {
            UIAlertController *ac = [UIAlertController alertControllerWithTitle:title message:subtitle preferredStyle:UIAlertControllerStyleAlert];
            [ac addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [root presentViewController:ac animated:YES completion:nil];
        }
    });
}

%hook ELMTouchCommandPropertiesHandler
- (void)handleTap {
    if (class_getInstanceVariable([self class], "_controller") == NULL ||
        class_getInstanceVariable([self class], "_tapRecognizer") == NULL) {
        return %orig;
    }

    ELMNodeController *node = [self valueForKey:@"_controller"];
    UIGestureRecognizer *tapRecognizer = [self valueForKey:@"_tapRecognizer"];
    if (![node respondsToSelector:@selector(key)] || ![node.key isEqualToString:@"music_download_badge_1"]) {
        return %orig;
    }

    UIViewController *ancestorVC = [tapRecognizer.view respondsToSelector:@selector(_viewControllerForAncestor)]
        ? tapRecognizer.view._viewControllerForAncestor
        : nil;
    if (!ancestorVC || ![ancestorVC isKindOfClass:%c(YTMNowPlayingViewController)]) {
        return %orig;
    }

    UIViewController *presenterVC = ancestorVC;
    YTPlayerViewController *playerVC = YTMUFindPlayerVCFromView(tapRecognizer.view, &presenterVC);
    YTPlayerResponse *playerResponse = [playerVC respondsToSelector:@selector(playerResponse)] ? playerVC.playerResponse : nil;

    if (!playerVC || !playerResponse) {
        YTMUShowInfoAlert(LOC(@"DONT_RUSH"), LOC(@"DONT_RUSH_DESC"));
        return;
    }

    BOOL wantAudio = YTMU(@"downloadAudio");
    BOOL wantCover = YTMU(@"downloadCoverImage");
    if (!wantAudio && !wantCover) {
        // Neither custom download toggle enabled -> let YouTube handle natively without crashing
        return %orig;
    }

    if (wantAudio && !wantCover) {
        [self downloadAudio:playerVC];
        return;
    }
    if (wantCover && !wantAudio) {
        [self downloadCoverImage:playerVC];
        return;
    }

    // Both options enabled: try YTM action sheet safely, otherwise fall back to UIAlertController
    Class sheetCls = %c(YTMActionSheetController);
    Class actionCls = %c(YTActionSheetAction);
    Class resCls = %c(YTUIResources);
    SEL actionSel = @selector(actionWithTitle:iconImage:style:handler:);

    if (sheetCls && actionCls &&
        [sheetCls respondsToSelector:@selector(musicActionSheetController)] &&
        [actionCls respondsToSelector:actionSel]) {
        YTMActionSheetController *sheetController = [sheetCls musicActionSheetController];
        if ([sheetController respondsToSelector:@selector(setSourceView:)]) {
            sheetController.sourceView = tapRecognizer.view;
        }
        if ([sheetController respondsToSelector:@selector(addHeaderWithTitle:subtitle:)]) {
            [sheetController addHeaderWithTitle:LOC(@"SELECT_ACTION") subtitle:nil];
        }

        UIImage *audioImg = (resCls && [resCls respondsToSelector:@selector(audioOutline)])
            ? [resCls audioOutline]
            : [UIImage systemImageNamed:@"waveform"];
        UIImage *coverImg = (resCls && [resCls respondsToSelector:@selector(outlineImageWithColor:)])
            ? [resCls outlineImageWithColor:[UIColor whiteColor]]
            : [UIImage systemImageNamed:@"photo"];

        __weak typeof(self) weakSelf = self;
        [sheetController addAction:[actionCls actionWithTitle:LOC(@"DOWNLOAD_AUDIO") iconImage:audioImg style:0 handler:^{
            [weakSelf downloadAudio:playerVC];
        }]];
        [sheetController addAction:[actionCls actionWithTitle:LOC(@"DOWNLOAD_COVER") iconImage:coverImg style:0 handler:^{
            [weakSelf downloadCoverImage:playerVC];
        }]];

        if ([sheetController respondsToSelector:@selector(presentFromViewController:animated:completion:)]) {
            [sheetController presentFromViewController:(ancestorVC ?: presenterVC) animated:YES completion:nil];
            return;
        }
    }

    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:LOC(@"SELECT_ACTION") message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;
    [sheet addAction:[UIAlertAction actionWithTitle:LOC(@"DOWNLOAD_AUDIO") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *act) {
        [weakSelf downloadAudio:playerVC];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:LOC(@"DOWNLOAD_COVER") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *act) {
        [weakSelf downloadCoverImage:playerVC];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:LOC(@"CANCEL") style:UIAlertActionStyleCancel handler:nil]];
    if (sheet.popoverPresentationController && tapRecognizer.view) {
        sheet.popoverPresentationController.sourceView = tapRecognizer.view;
        sheet.popoverPresentationController.sourceRect = tapRecognizer.view.bounds;
    }
    UIViewController *host = ancestorVC ?: presenterVC ?: YTMUKeyWindow().rootViewController;
    while (host.presentedViewController) host = host.presentedViewController;
    [host presentViewController:sheet animated:YES completion:nil];
}

%new
- (void)downloadAudio:(YTPlayerViewController *)playerVC {
    YTPlayerResponse *playerResponse = [playerVC respondsToSelector:@selector(playerResponse)] ? playerVC.playerResponse : nil;
    if (!playerResponse || !playerResponse.playerData || !playerResponse.playerData.videoDetails) {
        YTMUShowInfoAlert(LOC(@"OOPS"), LOC(@"LINK_NOT_FOUND"));
        return;
    }

    NSString *rawTitle = playerResponse.playerData.videoDetails.title ?: @"Track";
    NSString *rawAuthor = playerResponse.playerData.videoDetails.author ?: @"Artist";
    NSString *title = [rawTitle stringByReplacingOccurrencesOfString:@"/" withString:@"-"];
    NSString *author = [rawAuthor stringByReplacingOccurrencesOfString:@"/" withString:@"-"];
    NSString *urlStr = playerResponse.playerData.streamingData.hlsManifestURL;

    if (urlStr.length == 0) {
        YTMUShowInfoAlert(LOC(@"OOPS"), LOC(@"LINK_NOT_FOUND"));
        return;
    }

    static dispatch_once_t once;
    dispatch_once(&once, ^{ gActiveDownloaders = [NSMutableArray array]; });

    FFMpegDownloader *ffmpeg = [[FFMpegDownloader alloc] init];
    ffmpeg.tempName = [playerVC respondsToSelector:@selector(contentVideoID)] ? (playerVC.contentVideoID ?: @"track") : @"track";
    ffmpeg.mediaName = [NSString stringWithFormat:@"%@ - %@", author, title];
    CGFloat totalTime = [playerVC respondsToSelector:@selector(currentVideoTotalMediaTime)] ? playerVC.currentVideoTotalMediaTime : 0.0f;
    ffmpeg.duration = MAX(1.0, round(totalTime));

    [gActiveDownloaders addObject:ffmpeg];

    NSMutableArray *thumbnailsArray = playerResponse.playerData.videoDetails.thumbnail.thumbnailsArray;
    YTIThumbnailDetails_Thumbnail *thumbnail = [thumbnailsArray lastObject];
    NSString *thumbURL = thumbnail.URL;

    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSString *extractedURL = [weakSelf getURLFromManifest:[NSURL URLWithString:urlStr]];
        if (thumbURL.length > 0 && extractedURL.length > 0) {
            NSData *imageData = [NSData dataWithContentsOfURL:[NSURL URLWithString:thumbURL]];
            if (imageData.length > 0) {
                NSURL *documentsURL = [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] lastObject];
                NSURL *folderURL = [documentsURL URLByAppendingPathComponent:@"YTMusicUltimate"];
                [[NSFileManager defaultManager] createDirectoryAtURL:folderURL withIntermediateDirectories:YES attributes:nil error:nil];
                NSURL *coverURL = [folderURL URLByAppendingPathComponent:[NSString stringWithFormat:@"%@ - %@.png", author, title]];
                [imageData writeToURL:coverURL atomically:YES];
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (extractedURL.length > 0) {
                [ffmpeg downloadAudio:extractedURL];
            } else {
                [gActiveDownloaders removeObject:ffmpeg];
                YTMUShowInfoAlert(LOC(@"OOPS"), LOC(@"LINK_NOT_FOUND"));
            }
        });
    });
}

%new
- (NSString *)getURLFromManifest:(NSURL *)manifest {
    if (!manifest) return nil;
    NSData *manifestData = [NSData dataWithContentsOfURL:manifest];
    if (!manifestData.length) return nil;
    NSString *manifestString = [[NSString alloc] initWithData:manifestData encoding:NSUTF8StringEncoding];
    NSArray *manifestLines = [manifestString componentsSeparatedByString:@"\n"];

    NSArray *groupIDS = @[@"234", @"233"]; // Our priority to find group id 234
    for (NSString *groupID in groupIDS) {
        for (NSString *line in manifestLines) {
            NSString *searchString = [NSString stringWithFormat:@"TYPE=AUDIO,GROUP-ID=\"%@\"", groupID];
            if ([line containsString:searchString]) {
                NSRange startRange = [line rangeOfString:@"https://"];
                NSRange endRange = [line rangeOfString:@"index.m3u8"];

                if (startRange.location != NSNotFound && endRange.location != NSNotFound && NSMaxRange(endRange) > startRange.location) {
                    NSRange targetRange = NSMakeRange(startRange.location, NSMaxRange(endRange) - startRange.location);
                    return [line substringWithRange:targetRange];
                }
            }
        }
    }

    return nil;
}

%new
- (void)downloadCoverImage:(YTPlayerViewController *)playerVC {
    UIWindow *kw = YTMUKeyWindow();
    MBProgressHUD *hud = kw ? [MBProgressHUD showHUDAddedTo:kw animated:YES] : nil;
    if (hud) hud.mode = MBProgressHUDModeIndeterminate;

    YTPlayerResponse *playerResponse = [playerVC respondsToSelector:@selector(playerResponse)] ? playerVC.playerResponse : nil;
    NSMutableArray *thumbnailsArray = playerResponse.playerData.videoDetails.thumbnail.thumbnailsArray;
    YTIThumbnailDetails_Thumbnail *thumbnail = [thumbnailsArray lastObject];
    if (!thumbnail || thumbnail.URL.length == 0) {
        [hud hideAnimated:YES];
        YTMUShowInfoAlert(LOC(@"OOPS"), LOC(@"LINK_NOT_FOUND"));
        return;
    }

    NSString *thumbnailURL = [thumbnail.URL stringByReplacingOccurrencesOfString:[NSString stringWithFormat:@"w%u-h%u-", thumbnail.width, thumbnail.width] withString:@"w2048-h2048-"];
    FFMpegDownloader *ffmpeg = [[FFMpegDownloader alloc] init];
    [ffmpeg downloadImage:[NSURL URLWithString:thumbnailURL]];

    dispatch_async(dispatch_get_main_queue(), ^{
        [hud hideAnimated:YES];
    });
}
%end
