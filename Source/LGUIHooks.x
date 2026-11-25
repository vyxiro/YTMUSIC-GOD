#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "LiquidGlass.h"
#import "Headers/YTMNowPlayingView.h"
#import "Headers/YTMPlayerControlsView.h"
#import "Headers/YTPivotBarView.h"
#import "Headers/YTPivotBarItemView.h"
#import "Headers/YTQTMButton.h"
#import "Headers/YTMActionRowView.h"
#import "Headers/YTMBrowseViewController.h"
#import "Headers/YTMWatchViewController.h"

#pragma mark - Forward Declarations (Confirmed Runtime Classes)

@interface YTMContentViewController : UIViewController
@end

@interface YTMPlayerHeaderView : UIView
@end

@interface YTMPlayerCarouselView : UIView
@end

@interface YTMPlaylistPanelVideoCell : UIView
@end

@interface YTMPlayerTabView : UIView
@end

@interface YTMMiniPlayerView : UIView
@end

@interface YTMStoryboardScrubber : UIView
@end

@interface YTMChipCloudScrollableChipView : UIView
@end

#pragma mark - Theme Observer Box

@interface LGUIThemeObserverBox : NSObject
@property (nonatomic, strong) id token;
@end

@implementation LGUIThemeObserverBox
- (void)dealloc {
    if (_token) {
        [[NSNotificationCenter defaultCenter] removeObserver:_token];
    }
}
@end

static char kLGUIObserverKey;
static char kLGWatchBgKey;
static char kLGPivotItemPillKey;

static void LGApplyThemeObserver(UIView *view, void (^onChange)(UIView *v, LGPalette *p, BOOL dark, BOOL staticMode)) {
    if (!view || objc_getAssociatedObject(view, &kLGUIObserverKey)) return;
    LGUIThemeObserverBox *box = [LGUIThemeObserverBox new];
    __weak UIView *weakView = view;
    box.token = LGObserveTheme(^(LGPalette *p, BOOL dark, BOOL staticMode) {
        UIView *strongView = weakView;
        if (strongView && onChange) {
            onChange(strongView, p, dark, staticMode);
        }
    });
    objc_setAssociatedObject(view, &kLGUIObserverKey, box, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static BOOL LGIsNearBlackOrDarkOpaque(UIColor *c) {
    if (!c) return NO;
    CGFloat r = 0, g = 0, b = 0, a = 0;
    if ([c getRed:&r green:&g blue:&b alpha:&a]) {
        return a > 0.85f && r < 0.08f && g < 0.08f && b < 0.08f;
    }
    CGFloat w = 0;
    if ([c getWhite:&w alpha:&a]) {
        return a > 0.85f && w < 0.08f;
    }
    return NO;
}

static BOOL LGIsVideoViewOrContainer(UIView *v) {
    if (!v) return NO;
    NSString *cls = NSStringFromClass([v class]);
    if ([cls containsString:@"YTPlayerView"] ||
        [cls containsString:@"HAMVideo"] ||
        [cls containsString:@"AVPlayerLayer"] ||
        [cls containsString:@"YTMVideoOverlay"]) {
        return YES;
    }
    for (UIView *sub in v.subviews) {
        NSString *subCls = NSStringFromClass([sub class]);
        if ([subCls containsString:@"YTPlayerView"] || [subCls containsString:@"HAMVideo"]) {
            return YES;
        }
    }
    return NO;
}

static BOOL LGAncestorHasLGBackground(UIView *v) {
    UIView *cur = v.superview;
    while (cur) {
        for (UIView *sub in cur.subviews) {
            if ([sub isKindOfClass:[LGBackgroundView class]] && !sub.hidden && sub.alpha > 0.5f) return YES;
        }
        cur = cur.superview;
    }
    return NO;
}

static UIView *LGFindDescendantOfClass(UIView *root, Class cls, int depth) {
    if (!root || !cls || depth > 10) return nil;
    for (UIView *sub in root.subviews) {
        if ([sub isKindOfClass:cls]) return sub;
        if ([sub isKindOfClass:[LGBackgroundView class]] ||
            [sub isKindOfClass:[LGGlassView class]] ||
            [sub isKindOfClass:[UICollectionView class]]) {
            continue;
        }
        NSString *name = NSStringFromClass([sub class]);
        if ([name containsString:@"YTELMView"] || [name containsString:@"Scrubber"]) continue;
        UIView *hit = LGFindDescendantOfClass(sub, cls, depth + 1);
        if (hit) return hit;
    }
    return nil;
}

static void LGSyncWatchBackgroundAlpha(UIView *watchView, UIView *nowPlayingView) {
    if (!watchView) return;
    LGBackgroundView *bg = objc_getAssociatedObject(watchView, &kLGWatchBgKey);
    if (!bg) {
        for (UIView *sub in watchView.subviews) {
            if ([sub isKindOfClass:[LGBackgroundView class]]) {
                bg = (LGBackgroundView *)sub;
                break;
            }
        }
    }
    if (!bg) return;

    if (!CGRectIsEmpty(watchView.bounds) && !CGRectEqualToRect(bg.frame, watchView.bounds)) {
        bg.frame = watchView.bounds;
    }
    [watchView sendSubviewToBack:bg];

    CGFloat watchH = watchView.bounds.size.height;
    UIView *np = nowPlayingView ?: LGFindDescendantOfClass(watchView, objc_getClass("YTMNowPlayingView"), 0);
    UIView *mini = LGFindDescendantOfClass(watchView, objc_getClass("YTMMiniPlayerView"), 0);
    UIView *tab = LGFindDescendantOfClass(watchView, objc_getClass("YTMPlayerTabView"), 0);
    UIView *carousel = LGFindDescendantOfClass(watchView, objc_getClass("YTMPlayerCarouselView"), 0);

    CGFloat targetAlpha = 0.0f;
    if (np && !np.hidden && np.alpha > 0.01f) {
        targetAlpha = MAX(targetAlpha, np.alpha);
    }

    BOOL miniAtBottom = NO;
    if (mini && !mini.hidden && mini.alpha > 0.05f && watchH > 200.0f) {
        CGRect mf = [watchView convertRect:mini.bounds fromView:mini];
        if (mf.origin.y < watchH * 0.45f) {
            // Mini player docked at top -> Queue / Lyrics / Related sheet is open
            targetAlpha = 1.0f;
        } else if (mf.origin.y >= watchH * 0.55f && mf.origin.y < watchH - 20.0f && mini.alpha > 0.5f) {
            miniAtBottom = YES;
        }
    }

    if (carousel && !carousel.hidden && carousel.alpha > 0.05f && !miniAtBottom && watchH > 200.0f) {
        CGRect cf = [watchView convertRect:carousel.bounds fromView:carousel];
        if (CGRectGetMaxY(cf) > 100.0f && cf.origin.y < watchH - 120.0f) {
            targetAlpha = MAX(targetAlpha, carousel.alpha);
        }
    }

    if (tab && !tab.hidden && tab.alpha > 0.05f && watchH > 200.0f) {
        CGRect tf = [watchView convertRect:tab.bounds fromView:tab];
        if (tf.size.height > 160.0f && tf.origin.y < watchH - 180.0f) {
            targetAlpha = 1.0f;
        }
    }

    bg.alpha = targetAlpha;
}

static void LGStylePlayButton(UIView *btn, LGPalette *p, BOOL staticMode) {
    if (!btn || !p) return;
    btn.backgroundColor = p.a1;
    btn.tintColor = p.onAccent ?: UIColor.whiteColor;
    if ([btn isKindOfClass:[UIButton class]]) {
        UIButton *uib = (UIButton *)btn;
        uib.imageView.tintColor = p.onAccent ?: UIColor.whiteColor;
        [uib setTitleColor:(p.onAccent ?: UIColor.whiteColor) forState:UIControlStateNormal];
    }
    for (UIView *sub in btn.subviews) {
        if ([sub isKindOfClass:[UIImageView class]]) {
            sub.tintColor = p.onAccent ?: UIColor.whiteColor;
        }
    }
    CGFloat h = btn.bounds.size.height;
    if (h > 20.0f) {
        btn.layer.cornerRadius = h * 0.5f;
    }
    if (staticMode) {
        btn.layer.shadowOpacity = 0.0f;
        btn.layer.borderWidth = 0.0f;
    } else if (p.a1) {
        btn.layer.borderWidth = 1.0f;
        btn.layer.borderColor = [UIColor colorWithWhite:1.0f alpha:0.42f].CGColor;
        btn.layer.shadowColor = p.a1.CGColor;
        btn.layer.shadowOffset = CGSizeMake(0, 4);
        btn.layer.shadowRadius = 14.0f;
        btn.layer.shadowOpacity = 0.55f;
    }
}

static void LGResetSecondaryTransportButton(UIView *btn, LGPalette *p) {
    if (!btn) return;
    btn.backgroundColor = [UIColor clearColor];
    btn.layer.borderWidth = 0.0f;
    btn.layer.shadowOpacity = 0.0f;
    UIColor *glyph = p.tx ?: UIColor.whiteColor;
    btn.tintColor = glyph;
    if ([btn isKindOfClass:[UIButton class]]) {
        UIButton *uib = (UIButton *)btn;
        uib.imageView.tintColor = glyph;
        [uib setTitleColor:glyph forState:UIControlStateNormal];
    }
    for (UIView *sub in btn.subviews) {
        if ([sub isKindOfClass:[UIImageView class]]) {
            sub.tintColor = glyph;
        }
    }
}

#pragma mark - Home / Browse Full-Screen Background

%group ContentVCHooks
%hook YTMContentViewController

- (void)viewDidLoad {
    %orig;
    self.view.backgroundColor = [UIColor clearColor];
    LGBackgroundView *bg = LGInstallBackground(self.view);
    if (bg) bg.scrimMultiplier = 1.35f;
}

- (void)viewDidLayoutSubviews {
    %orig;
    self.view.backgroundColor = [UIColor clearColor];
    LGBackgroundView *bg = LGInstallBackground(self.view);
    if (bg) {
        bg.scrimMultiplier = 1.35f;
        bg.frame = self.view.bounds;
        [self.view sendSubviewToBack:bg];
    }
    for (UIView *sub in self.view.subviews) {
        if ([sub isKindOfClass:[LGBackgroundView class]]) continue;
        if (LGIsNearBlackOrDarkOpaque(sub.backgroundColor)) {
            sub.backgroundColor = [UIColor clearColor];
        }
    }
}

%end
%end

%group BrowseVCHooks
%hook YTMBrowseViewController

- (void)viewDidLoad {
    %orig;
    self.view.backgroundColor = [UIColor clearColor];
    if (!LGAncestorHasLGBackground(self.view)) {
        LGInstallBackground(self.view);
    }
}

- (void)viewDidLayoutSubviews {
    %orig;
    self.view.backgroundColor = [UIColor clearColor];
    // Clear GOOHeaderViewController opaque wrapper if present
    if (self.view.superview) {
        UIColor *sbg = self.view.superview.backgroundColor;
        if (sbg && ![sbg isEqual:[UIColor clearColor]]) {
            self.view.superview.backgroundColor = [UIColor clearColor];
        }
    }
    if (!LGAncestorHasLGBackground(self.view)) {
        LGBackgroundView *bg = LGInstallBackground(self.view);
        if (bg) {
            bg.frame = self.view.bounds;
            [self.view sendSubviewToBack:bg];
        }
    } else {
        // Remove duplicate child LGBackgroundView if ancestor YTMContentView already provides full-bleed background
        for (UIView *sub in [self.view.subviews copy]) {
            if ([sub isKindOfClass:[LGBackgroundView class]]) {
                [sub removeFromSuperview];
            }
        }
    }
}

%end
%end

#pragma mark - Full-Bleed Now Playing (YTMWatchViewController)

%group WatchVCHooks
%hook YTMWatchViewController

- (void)viewDidLoad {
    %orig;
    self.view.backgroundColor = [UIColor clearColor];
    LGBackgroundView *bg = LGInstallBackground(self.view);
    if (bg) {
        objc_setAssociatedObject(self.view, &kLGWatchBgKey, bg, OBJC_ASSOCIATION_ASSIGN);
        LGSyncWatchBackgroundAlpha(self.view, nil);
    }
}

- (void)viewDidLayoutSubviews {
    %orig;
    self.view.backgroundColor = [UIColor clearColor];
    LGBackgroundView *bg = LGInstallBackground(self.view);
    if (bg) {
        objc_setAssociatedObject(self.view, &kLGWatchBgKey, bg, OBJC_ASSOCIATION_ASSIGN);
        bg.frame = self.view.bounds;
        [self.view sendSubviewToBack:bg];
    }
    for (UIView *sub in self.view.subviews) {
        if ([sub isKindOfClass:[LGBackgroundView class]] || LGIsVideoViewOrContainer(sub)) continue;
        if (LGIsNearBlackOrDarkOpaque(sub.backgroundColor)) {
            sub.backgroundColor = [UIColor clearColor];
        }
    }
    LGSyncWatchBackgroundAlpha(self.view, nil);
}

%end
%end

#pragma mark - Now Playing Frosted Card & Transport Pill

%group NowPlayingViewHooks
%hook YTMNowPlayingView

- (void)setAlpha:(CGFloat)alpha {
    %orig;
    UIView *cur = self.superview;
    Class watchCls = objc_getClass("YTMWatchView");
    while (cur && watchCls && ![cur isKindOfClass:watchCls]) {
        cur = cur.superview;
    }
    if (cur) LGSyncWatchBackgroundAlpha(cur, self);
}

- (void)setHidden:(BOOL)hidden {
    %orig;
    UIView *cur = self.superview;
    Class watchCls = objc_getClass("YTMWatchView");
    while (cur && watchCls && ![cur isKindOfClass:watchCls]) {
        cur = cur.superview;
    }
    if (cur) LGSyncWatchBackgroundAlpha(cur, self);
}

- (void)layoutSubviews {
    %orig;
    LGApplyThemeObserver(self, ^(UIView *v, __unused LGPalette *p, __unused BOOL dark, __unused BOOL staticMode) {
        [v setNeedsLayout];
    });

    self.backgroundColor = [UIColor clearColor];
    self.clipsToBounds = NO;

    CGSize sz = self.bounds.size;
    if (sz.width > 120.0f && sz.height > 120.0f) {
        LGGlassView *card = LGAttachGlass(self, 28.0f);
        card.autoresizingMask = UIViewAutoresizingNone;
        card.frame = CGRectMake(8.0f, -6.0f, sz.width - 16.0f, sz.height + 14.0f);
        [self sendSubviewToBack:card];
    }

    // Style ELM action pills (Like, Dislike, Lyrics, Comments, Save) inside YTMNowPlayingView
    LGTheme *t = LGTheme.shared;
    for (UIView *sub in self.subviews) {
        NSString *cls = NSStringFromClass([sub class]);
        if ([cls containsString:@"YTELMView"] || [sub isKindOfClass:[UIScrollView class]]) {
            for (UIView *inner in sub.subviews) {
                if ([inner isKindOfClass:[UICollectionView class]]) {
                    inner.backgroundColor = [UIColor clearColor];
                    for (UIView *cell in inner.subviews) {
                        for (UIView *target in @[cell, cell.subviews.firstObject ?: cell]) {
                            CGSize cs = target.bounds.size;
                            if (cs.height >= 26.0f && cs.height <= 44.0f && cs.width >= 30.0f && cs.width <= 260.0f &&
                                (target == cell || target.layer.cornerRadius >= 10.0f)) {
                                if (target != cell && cell.layer.borderWidth > 0) cell.layer.borderWidth = 0;
                                target.layer.cornerRadius = cs.height * 0.5f;
                                target.clipsToBounds = YES;
                                if (t.staticMode) {
                                    target.backgroundColor = t.palette.b2;
                                    target.layer.borderWidth = 1.0f;
                                    target.layer.borderColor = [UIColor colorWithWhite:0.5f alpha:0.35f].CGColor;
                                } else {
                                    target.backgroundColor = [UIColor colorWithWhite:(t.dark ? 1.0f : 0.0f) alpha:(t.dark ? 0.08f : 0.06f)];
                                    target.layer.borderWidth = 0.85f;
                                    target.layer.borderColor = [UIColor colorWithWhite:1.0f alpha:(t.dark ? 0.28f : 0.70f)].CGColor;
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    UIView *cur = self.superview;
    Class watchCls = objc_getClass("YTMWatchView");
    while (cur && watchCls && ![cur isKindOfClass:watchCls]) {
        cur = cur.superview;
    }
    if (cur) LGSyncWatchBackgroundAlpha(cur, self);
}

%end
%end

static void LGUpdatePlayerControlsButtons(UIView *controls, LGPalette *p, BOOL staticMode) {
    CGSize sz = controls.bounds.size;
    if (sz.width < 40.0f) return;

    // Identify ONLY the single centered Play/Pause button
    UIView *playBtn = nil;
    CGFloat bestScore = CGFLOAT_MAX;
    for (UIView *sub in controls.subviews) {
        if ([sub isKindOfClass:[LGGlassView class]] || sub.hidden) continue;
        if (![sub isKindOfClass:[UIButton class]] && ![NSStringFromClass([sub class]) containsString:@"Button"]) continue;
        CGSize bs = sub.bounds.size;
        if (bs.width < 44.0f || bs.height < 44.0f) continue;
        CGFloat dx = fabs(CGRectGetMidX(sub.frame) - sz.width * 0.5f);
        if (dx < 28.0f) {
            CGFloat score = dx - bs.width * 0.1f; // prefer dead-center & larger height
            if (score < bestScore) {
                bestScore = score;
                playBtn = sub;
            }
        }
    }

    for (UIView *sub in controls.subviews) {
        if ([sub isKindOfClass:[LGGlassView class]]) continue;
        if (![sub isKindOfClass:[UIButton class]] && ![NSStringFromClass([sub class]) containsString:@"Button"]) continue;
        if (sub == playBtn) {
            LGStylePlayButton(sub, p, staticMode);
        } else {
            LGResetSecondaryTransportButton(sub, p);
        }
    }
}

%group PlayerControlsHooks
%hook YTMPlayerControlsView

- (void)layoutSubviews {
    %orig;
    LGApplyThemeObserver(self, ^(UIView *v, LGPalette *p, __unused BOOL dark, BOOL staticMode) {
        LGUpdatePlayerControlsButtons(v, p, staticMode);
        [v setNeedsLayout];
    });

    self.backgroundColor = [UIColor clearColor];
    CGSize sz = self.bounds.size;
    if (sz.width > 120.0f && sz.height > 40.0f) {
        LGGlassView *pill = LGAttachGlass(self, sz.height * 0.5f);
        pill.autoresizingMask = UIViewAutoresizingNone;
        CGFloat insetX = (sz.width > 340.0f) ? 6.0f : 0.0f;
        pill.frame = CGRectMake(insetX, 0.0f, sz.width - insetX * 2.0f, sz.height);
        [self sendSubviewToBack:pill];
    }

    LGUpdatePlayerControlsButtons(self, LGTheme.shared.palette, LGTheme.shared.staticMode);
}

%end
%end

#pragma mark - Now Playing Header & Artwork Rounding

%group PlayerHeaderHooks
%hook YTMPlayerHeaderView

- (void)layoutSubviews {
    %orig;
    LGApplyThemeObserver(self, ^(UIView *v, __unused LGPalette *p, __unused BOOL dark, __unused BOOL staticMode) {
        [v setNeedsLayout];
    });
    self.backgroundColor = [UIColor clearColor];
    for (UIView *sub in self.subviews) {
        if ([sub isKindOfClass:[LGGlassView class]]) continue;
        NSString *cls = NSStringFromClass([sub class]);
        CGSize s = sub.bounds.size;
        BOOL looksLikeAVPill = [cls containsString:@"Switch"] ||
                               ([cls containsString:@"Header"] && s.width >= 76.0f && s.width <= 160.0f && s.height >= 26.0f && s.height <= 46.0f) ||
                               (sub.subviews.count >= 2 && s.width >= 76.0f && s.width <= 150.0f && s.height >= 28.0f && s.height <= 44.0f && sub.layer.cornerRadius >= 12.0f);
        if (looksLikeAVPill) {
            LGGlassView *pill = LGAttachGlass(sub, s.height * 0.5f);
            pill.frame = sub.bounds;
            [sub sendSubviewToBack:pill];
        }
    }
    UIView *cur = self.superview;
    Class watchCls = objc_getClass("YTMWatchView");
    while (cur && watchCls && ![cur isKindOfClass:watchCls]) cur = cur.superview;
    if (cur) LGSyncWatchBackgroundAlpha(cur, nil);
}

%end
%end

%group PlayerCarouselHooks
static void LGRoundLargeArtworkInTree(UIView *root, UIColor *borderColor, BOOL isStatic) {
    for (UIView *sub in root.subviews) {
        if (LGIsVideoViewOrContainer(sub)) continue;
        NSString *cls = NSStringFromClass([sub class]);
        if (([cls isEqualToString:@"YTImageView"] || [sub isKindOfClass:[UIImageView class]]) &&
            sub.bounds.size.width >= 160.0f && sub.bounds.size.height >= 160.0f) {
            sub.layer.cornerRadius = 26.0f;
            sub.clipsToBounds = YES;
            sub.layer.borderWidth = 1.15f;
            sub.layer.borderColor = borderColor.CGColor;
            // Slightly inset edge-to-edge covers so rounded borders & ambient halo show cleanly
            if (sub.bounds.size.width >= 360.0f && sub.bounds.size.height >= 300.0f) {
                sub.transform = CGAffineTransformMakeScale(0.92f, 0.92f);
            } else {
                sub.transform = CGAffineTransformIdentity;
            }
            if (sub.superview && !isStatic) {
                sub.superview.clipsToBounds = NO;
                sub.superview.layer.shadowColor = UIColor.blackColor.CGColor;
                sub.superview.layer.shadowOffset = CGSizeMake(0, 10);
                sub.superview.layer.shadowRadius = 24.0f;
                sub.superview.layer.shadowOpacity = 0.45f;
            }
        } else if (sub.subviews.count > 0 && sub.bounds.size.width >= 160.0f) {
            LGRoundLargeArtworkInTree(sub, borderColor, isStatic);
        }
    }
}

%hook YTMPlayerCarouselView

- (void)layoutSubviews {
    %orig;
    LGApplyThemeObserver(self, ^(UIView *v, __unused LGPalette *p, __unused BOOL dark, __unused BOOL staticMode) {
        [v setNeedsLayout];
    });
    self.backgroundColor = [UIColor clearColor];
    for (UIView *sub in self.subviews) {
        if ([sub isKindOfClass:[UICollectionView class]] || LGIsNearBlackOrDarkOpaque(sub.backgroundColor)) {
            sub.backgroundColor = [UIColor clearColor];
        }
    }
    BOOL isStatic = LGTheme.shared.staticMode;
    BOOL isDark = LGTheme.shared.dark;
    UIColor *borderColor = isStatic
        ? [UIColor colorWithWhite:0.5f alpha:0.35f]
        : [UIColor colorWithWhite:1.0f alpha:(isDark ? 0.36f : 0.78f)];
    LGRoundLargeArtworkInTree(self, borderColor, isStatic);

    UIView *cur = self.superview;
    Class watchCls = objc_getClass("YTMWatchView");
    while (cur && watchCls && ![cur isKindOfClass:watchCls]) cur = cur.superview;
    if (cur) LGSyncWatchBackgroundAlpha(cur, nil);
}

%end
%end

%group PlaylistCellHooks
%hook YTMPlaylistPanelVideoCell

- (void)layoutSubviews {
    %orig;
    if (self.bounds.size.height >= 160.0f && self.bounds.size.width >= 160.0f) {
        BOOL isStatic = LGTheme.shared.staticMode;
        BOOL isDark = LGTheme.shared.dark;
        UIColor *borderColor = isStatic
            ? [UIColor colorWithWhite:0.5f alpha:0.35f]
            : [UIColor colorWithWhite:1.0f alpha:(isDark ? 0.36f : 0.78f)];
        LGRoundLargeArtworkInTree(self, borderColor, isStatic);
    }
}

%end
%end

#pragma mark - Scrubber (Expanded Now Playing & Mini Player Progress)

static void LGColorScrubber(UIView *scrubber, LGPalette *p, BOOL dark) {
    if (!scrubber || !p) return;
    UIColor *a1 = p.a1 ?: UIColor.whiteColor;
    for (UIView *sub in scrubber.subviews) {
        NSString *cls = NSStringFromClass([sub class]);
        if ([cls containsString:@"StoryboardFrame"]) continue;
        CGSize s = sub.bounds.size;
        // Track bar container holds track [0], buffer [1], fill [2+]
        if (s.width > 40.0f && s.height > 0.0f && s.height <= 8.0f && sub.subviews.count >= 2) {
            NSArray<UIView *> *bars = sub.subviews;
            bars[0].backgroundColor = [UIColor colorWithWhite:(dark ? 1.0f : 0.0f) alpha:0.16f];
            if (bars.count >= 2) {
                bars[1].backgroundColor = [a1 colorWithAlphaComponent:0.30f];
            }
            if (bars.count >= 3) {
                bars.lastObject.backgroundColor = a1;
            }
        } else if (s.width >= 8.0f && s.width <= 20.0f && fabs(s.width - s.height) < 2.0f && sub.subviews.count == 0) {
            // Circular scrubber thumb (crisp glowing dot like target screenshots)
            sub.backgroundColor = dark ? UIColor.whiteColor : (p.tx ?: UIColor.blackColor);
            sub.layer.borderWidth = 0.0f;
            sub.layer.shadowColor = UIColor.whiteColor.CGColor;
            sub.layer.shadowOffset = CGSizeZero;
            sub.layer.shadowRadius = 4.0f;
            sub.layer.shadowOpacity = dark ? 0.65f : 0.25f;
        }
    }
}

%group ScrubberHooks
%hook YTMStoryboardScrubber

- (void)layoutSubviews {
    %orig;
    LGApplyThemeObserver(self, ^(UIView *v, LGPalette *p, BOOL dark, __unused BOOL staticMode) {
        LGColorScrubber(v, p, dark);
    });
    LGColorScrubber(self, LGTheme.shared.palette, LGTheme.shared.dark);
}

%end
%end

#pragma mark - Bottom Queue Bar & Sheet (YTMPlayerTabView)

%group PlayerTabViewHooks
%hook YTMPlayerTabView

- (void)layoutSubviews {
    %orig;
    LGApplyThemeObserver(self, ^(UIView *v, __unused LGPalette *p, __unused BOOL dark, __unused BOOL staticMode) {
        [v setNeedsLayout];
    });
    self.backgroundColor = [UIColor clearColor];
    for (UIView *sub in self.subviews) {
        if ([sub isKindOfClass:[LGGlassView class]]) continue;
        if (LGIsNearBlackOrDarkOpaque(sub.backgroundColor)) {
            sub.backgroundColor = [UIColor clearColor];
        }
        for (UIView *sub2 in sub.subviews) {
            if ([sub2 isKindOfClass:[UICollectionView class]] || LGIsNearBlackOrDarkOpaque(sub2.backgroundColor)) {
                sub2.backgroundColor = [UIColor clearColor];
            }
        }
    }

    CGSize sz = self.bounds.size;
    if (sz.width < 120.0f || sz.height < 36.0f) return;

    CGFloat safeBottom = 0.0f;
    if (@available(iOS 11.0, *)) {
        safeBottom = self.safeAreaInsets.bottom;
    }

    LGGlassView *glass = LGAttachGlass(self, 22.0f);
    glass.autoresizingMask = UIViewAutoresizingNone;
    if (sz.height <= 160.0f) {
        // Collapsed bottom queue bar ("Song mix >")
        CGFloat pillH = MIN(56.0f, MAX(44.0f, sz.height - safeBottom - 8.0f));
        glass.radius = 22.0f;
        glass.backgroundColor = UIColor.clearColor;
        glass.frame = CGRectMake(12.0f, 4.0f, sz.width - 24.0f, pillH);
    } else {
        // Expanded Queue / Lyrics / Related sheet: frosted glass over opaque Watch background
        glass.radius = 28.0f;
        LGTheme *t = LGTheme.shared;
        glass.backgroundColor = t.staticMode
            ? UIColor.clearColor
            : [UIColor colorWithWhite:(t.dark ? 0.0f : 1.0f) alpha:(t.dark ? 0.32f : 0.24f)];
        glass.frame = CGRectMake(8.0f, 0.0f, sz.width - 16.0f, sz.height + 28.0f);
    }
    [self sendSubviewToBack:glass];

    UIView *cur = self.superview;
    Class watchCls = objc_getClass("YTMWatchView");
    while (cur && watchCls && ![cur isKindOfClass:watchCls]) cur = cur.superview;
    if (cur) LGSyncWatchBackgroundAlpha(cur, nil);
}

%end
%end

#pragma mark - Mini Player (Floating Inset Capsule, Zero Seam, Zero Art Bulge)

static void LGStyleMiniPlayerHierarchy(UIView *root) {
    for (UIView *sub in root.subviews) {
        if ([sub isKindOfClass:[LGGlassView class]]) continue;
        NSString *cls = NSStringFromClass([sub class]);
        if ([sub isKindOfClass:[UICollectionView class]] ||
            [cls containsString:@"YTMPlaylistPanelVideoCell"] ||
            [cls containsString:@"YTMGradientBackgroundView"]) {
            sub.backgroundColor = [UIColor clearColor];
            if ([sub isKindOfClass:[UICollectionView class]]) {
                sub.clipsToBounds = YES;
            }
        } else if (sub.backgroundColor) {
            CGFloat white = 0, alpha = 0;
            if ([sub.backgroundColor getWhite:&white alpha:&alpha] && alpha > 0.01f && alpha < 0.25f && sub.bounds.size.height > 20.0f) {
                sub.backgroundColor = [UIColor clearColor];
            }
        }
        if ([cls isEqualToString:@"YTImageView"] && sub.bounds.size.width >= 36.0f && sub.bounds.size.width <= 72.0f) {
            sub.layer.cornerRadius = 10.0f;
            sub.clipsToBounds = YES;
            // Slightly scale down & nudge 48x48 cover so it sits cleanly inside the 18pt rounded capsule corner without bulging
            sub.transform = CGAffineTransformMakeScale(0.84f, 0.84f);
        } else if (sub.subviews.count > 0 && ![cls containsString:@"Scrubber"]) {
            LGStyleMiniPlayerHierarchy(sub);
        }
    }
}

%group MiniPlayerHooks
%hook YTMMiniPlayerView

- (void)setAlpha:(CGFloat)alpha {
    %orig;
    UIView *cur = self.superview;
    Class watchCls = objc_getClass("YTMWatchView");
    while (cur && watchCls && ![cur isKindOfClass:watchCls]) cur = cur.superview;
    if (cur) LGSyncWatchBackgroundAlpha(cur, nil);
}

- (void)setHidden:(BOOL)hidden {
    %orig;
    UIView *cur = self.superview;
    Class watchCls = objc_getClass("YTMWatchView");
    while (cur && watchCls && ![cur isKindOfClass:watchCls]) cur = cur.superview;
    if (cur) LGSyncWatchBackgroundAlpha(cur, nil);
}

- (void)layoutSubviews {
    %orig;
    LGApplyThemeObserver(self, ^(UIView *v, __unused LGPalette *p, __unused BOOL dark, __unused BOOL staticMode) {
        [v setNeedsLayout];
    });

    self.backgroundColor = [UIColor clearColor];
    self.clipsToBounds = NO;
    if (self.superview) {
        self.superview.backgroundColor = [UIColor clearColor];
        // Clear opaque black backing view inside YTMWatchView behind the mini player
        UIView *watch = self.superview.superview;
        if (watch) {
            for (UIView *sib in watch.subviews) {
                if (sib != self.superview && ![sib isKindOfClass:[LGBackgroundView class]] && !LGIsVideoViewOrContainer(sib)) {
                    if (sib.bounds.size.height <= 90.0f && LGIsNearBlackOrDarkOpaque(sib.backgroundColor)) {
                        sib.backgroundColor = [UIColor clearColor];
                    }
                }
            }
        }
    }

    LGStyleMiniPlayerHierarchy(self);

    CGSize sz = self.bounds.size;
    if (sz.width > 120.0f && sz.height > 36.0f) {
        LGGlassView *capsule = LGAttachGlass(self, 18.0f);
        capsule.autoresizingMask = UIViewAutoresizingNone;
        capsule.frame = CGRectMake(8.0f, 1.0f, sz.width - 16.0f, sz.height - 2.0f);
        [self sendSubviewToBack:capsule];

        // Tuck bottom mini scrubber cleanly inside the capsule rounded corners
        Class scrubberCls = objc_getClass("YTMStoryboardScrubber");
        for (UIView *sub in self.subviews) {
            if (scrubberCls && [sub isKindOfClass:scrubberCls] && sub.bounds.size.height <= 4.0f) {
                sub.frame = CGRectMake(24.0f, sz.height - 4.0f, sz.width - 48.0f, 2.0f);
                LGColorScrubber(sub, LGTheme.shared.palette, LGTheme.shared.dark);
            }
        }
    }

    UIView *cur = self.superview;
    Class watchCls = objc_getClass("YTMWatchView");
    while (cur && watchCls && ![cur isKindOfClass:watchCls]) cur = cur.superview;
    if (cur) LGSyncWatchBackgroundAlpha(cur, nil);
}

%end
%end

#pragma mark - Home & Queue Category Chips (Frosted Capsules + Accent Fill)

%group ChipCloudHooks
%hook YTMChipCloudScrollableChipView

- (void)layoutSubviews {
    %orig;
    LGApplyThemeObserver(self, ^(UIView *v, __unused LGPalette *p, __unused BOOL dark, __unused BOOL staticMode) {
        [v setNeedsLayout];
    });

    CGSize sz = self.bounds.size;
    if (sz.width < 20.0f || sz.height < 20.0f) return;

    BOOL isSelected = NO;
    if ([self respondsToSelector:@selector(isSelected)]) {
        isSelected = ((BOOL (*)(id, SEL))objc_msgSend)(self, @selector(isSelected));
    }

    LGTheme *t = LGTheme.shared;
    LGPalette *p = t.palette;
    LGGlassView *glass = LGAttachGlass(self, sz.height * 0.5f);
    glass.frame = self.bounds;
    [self sendSubviewToBack:glass];

    if (isSelected) {
        glass.hidden = YES;
        self.backgroundColor = p.a1 ?: UIColor.whiteColor;
        self.layer.cornerRadius = sz.height * 0.5f;
        self.layer.borderWidth = 0.0f;
        self.clipsToBounds = YES;
        UIColor *glyph = p.onAccent ?: UIColor.whiteColor;
        for (UIView *sub in self.subviews) {
            if ([sub isKindOfClass:[UILabel class]]) {
                ((UILabel *)sub).textColor = glyph;
            } else if ([sub isKindOfClass:[UIButton class]]) {
                [((UIButton *)sub) setTitleColor:glyph forState:UIControlStateNormal];
                sub.tintColor = glyph;
            } else if ([sub isKindOfClass:[UIImageView class]]) {
                sub.tintColor = glyph;
            }
        }
    } else {
        glass.hidden = NO;
        self.backgroundColor = [UIColor clearColor];
        self.layer.borderWidth = 0.0f;
        UIColor *txt = t.dark ? [UIColor colorWithWhite:1.0f alpha:0.92f] : (p.tx ?: UIColor.blackColor);
        for (UIView *sub in self.subviews) {
            if ([sub isKindOfClass:[UILabel class]]) {
                ((UILabel *)sub).textColor = txt;
            } else if ([sub isKindOfClass:[UIButton class]]) {
                [((UIButton *)sub) setTitleColor:txt forState:UIControlStateNormal];
                sub.tintColor = txt;
            }
        }
    }
}

%end
%end

#pragma mark - Legacy Action Row & Sliders

%group ActionRowHooks
%hook YTMActionRowView
- (void)layoutSubviews {
    %orig;
    LGApplyThemeObserver(self, ^(UIView *v, __unused LGPalette *p, __unused BOOL dark, __unused BOOL staticMode) {
        [v setNeedsLayout];
    });
    LGTheme *t = LGTheme.shared;
    self.backgroundColor = [UIColor clearColor];
    for (UIView *sub in self.subviews) {
        sub.backgroundColor = [UIColor clearColor];
        if ([sub isKindOfClass:[UIScrollView class]]) {
            for (UIView *btn in sub.subviews) {
                if ([btn isKindOfClass:[UIButton class]] || [btn isKindOfClass:objc_getClass("MDCButton")]) {
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
%end

%group SliderHooks
%hook UISlider

- (void)didMoveToWindow {
    %orig;
    if (self.window) {
        LGApplyThemeObserver(self, ^(UIView *v, LGPalette *p, __unused BOOL dark, __unused BOOL staticMode) {
            if ([v isKindOfClass:[UISlider class]]) {
                UISlider *s = (UISlider *)v;
                if (p.a1) s.minimumTrackTintColor = p.a1;
                if (p.tx) s.thumbTintColor = p.tx;
            }
        });
    }
}

%end
%end

#pragma mark - Floating Inset Tab Bar (YTPivotBarView & YTPivotBarItemView)

static void LGUpdatePivotItemVisual(YTPivotBarItemView *item) {
    LGTheme *t = LGTheme.shared;
    LGPalette *p = t.palette;

    UIView *btn = nil;
    if ([item respondsToSelector:@selector(navigationButton)]) {
        btn = (UIView *)[item performSelector:@selector(navigationButton)];
    }
    BOOL isSel = NO;
    if (btn && [btn respondsToSelector:@selector(isSelected)]) {
        isSel = ((BOOL (*)(id, SEL))objc_msgSend)(btn, @selector(isSelected));
    }

    UIView *pill = objc_getAssociatedObject(item, &kLGPivotItemPillKey);
    if (!pill && item.bounds.size.width > 10.0f) {
        pill = [UIView new];
        pill.userInteractionEnabled = NO;
        [item insertSubview:pill atIndex:0];
        objc_setAssociatedObject(item, &kLGPivotItemPillKey, pill, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    if (pill) {
        CGRect pr = CGRectInset(item.bounds, 4.0f, 4.0f);
        if (pr.size.width > 8.0f && pr.size.height > 8.0f) {
            pill.frame = pr;
            pill.layer.cornerRadius = pr.size.height * 0.5f;
            if (isSel) {
                pill.hidden = NO;
                if (t.staticMode) {
                    pill.backgroundColor = [p.a1 ?: UIColor.whiteColor colorWithAlphaComponent:0.18f];
                    pill.layer.borderWidth = 0.0f;
                } else {
                    pill.backgroundColor = [UIColor colorWithWhite:(t.dark ? 1.0f : 0.0f) alpha:(t.dark ? 0.21f : 0.12f)];
                    pill.layer.borderWidth = 0.9f;
                    pill.layer.borderColor = [UIColor colorWithWhite:1.0f alpha:(t.dark ? 0.40f : 0.75f)].CGColor;
                }
            } else {
                pill.hidden = YES;
            }
        }
    }

    UIColor *activeTint = t.staticMode ? (p.a1 ?: UIColor.whiteColor) : (p.tx ?: UIColor.whiteColor);
    UIColor *inactiveTint = p.mu ?: [UIColor colorWithWhite:1.0f alpha:0.65f];
    if (btn) {
        btn.tintColor = isSel ? activeTint : inactiveTint;
        if ([btn isKindOfClass:[UIButton class]]) {
            UIButton *b = (UIButton *)btn;
            [b setTitleColor:(isSel ? activeTint : inactiveTint) forState:UIControlStateNormal];
            [b setTitleColor:activeTint forState:UIControlStateSelected];
        }
    }
}

%group PivotBarHooks
%hook YTPivotBarItemView

- (void)layoutSubviews {
    %orig;
    LGApplyThemeObserver(self, ^(UIView *v, __unused LGPalette *p, __unused BOOL dark, __unused BOOL staticMode) {
        LGUpdatePivotItemVisual((YTPivotBarItemView *)v);
    });
    LGUpdatePivotItemVisual(self);
}

%end

%hook YTQTMButton

- (void)setSelected:(BOOL)selected {
    %orig;
    Class itemCls = objc_getClass("YTPivotBarItemView");
    if (itemCls && [self.superview isKindOfClass:itemCls]) {
        LGUpdatePivotItemVisual((YTPivotBarItemView *)self.superview);
    }
}

%end

%hook YTPivotBarView

- (UIView *)contentView {
    UIView *orig = %orig;
    if (orig) orig.backgroundColor = [UIColor clearColor];
    return orig;
}

- (void)layoutSubviews {
    %orig;
    LGApplyThemeObserver(self, ^(UIView *v, __unused LGPalette *p, __unused BOOL dark, __unused BOOL staticMode) {
        [v setNeedsLayout];
    });

    self.backgroundColor = [UIColor clearColor];
    self.layer.cornerRadius = 0.0f;
    self.layer.borderWidth = 0.0f;
    self.layer.shadowOpacity = 0.0f;

    UIView *cv = nil;
    if ([self respondsToSelector:@selector(contentView)]) {
        cv = (UIView *)[self performSelector:@selector(contentView)];
        if (cv) cv.backgroundColor = [UIColor clearColor];
    }

    // Clear opaque bar backing siblings inside YTMContentView if present
    if (self.superview) {
        for (UIView *sib in self.superview.subviews) {
            if (sib != self && ![sib isKindOfClass:[LGBackgroundView class]] && sib.bounds.size.height <= 120.0f) {
                if (LGIsNearBlackOrDarkOpaque(sib.backgroundColor)) {
                    sib.backgroundColor = [UIColor clearColor];
                }
            }
        }
    }

    CGSize sz = self.bounds.size;
    if (sz.width < 120.0f || sz.height < 40.0f) return;

    // Remap tab items into [18 .. sz.width - 18] so outer icons and active pill never overhang the floating capsule
    Class itemCls = objc_getClass("YTPivotBarItemView");
    UIView *container = cv ?: self;
    CGFloat capSide = 18.0f;
    CGFloat capInnerW = sz.width - capSide * 2.0f;
    NSMutableArray<UIView *> *items = [NSMutableArray array];
    for (UIView *sub in container.subviews) {
        if (itemCls && [sub isKindOfClass:itemCls] && !sub.hidden && sub.bounds.size.width > 10.0f) {
            [items addObject:sub];
        }
    }
    if (items.count > 0) {
        [items sortUsingComparator:^NSComparisonResult(UIView *a, UIView *b) {
            return a.frame.origin.x < b.frame.origin.x ? NSOrderedAscending : (a.frame.origin.x > b.frame.origin.x ? NSOrderedDescending : NSOrderedSame);
        }];
        CGFloat slotW = capInnerW / (CGFloat)items.count;
        for (NSUInteger idx = 0; idx < items.count; idx++) {
            UIView *it = items[idx];
            CGRect f = it.frame;
            f.origin.x = capSide + idx * slotW;
            f.size.width = slotW;
            it.frame = f;
        }
    }

    // Hug YTPivotBarItemView bounds vertically so home indicator safe area stays clear
    CGRect itemUnion = CGRectNull;
    for (UIView *sub in items) {
        CGRect r = [self convertRect:sub.bounds fromView:sub];
        itemUnion = CGRectIsNull(itemUnion) ? r : CGRectUnion(itemUnion, r);
    }

    CGFloat safeBottom = 0.0f;
    if (@available(iOS 11.0, *)) {
        safeBottom = self.safeAreaInsets.bottom;
    }
    CGFloat pillY = 1.0f;
    CGFloat pillH = MIN(60.0f, MAX(52.0f, sz.height - safeBottom - 2.0f));
    if (!CGRectIsNull(itemUnion) && itemUnion.size.height >= 36.0f && itemUnion.size.height <= 64.0f) {
        pillY = MAX(0.0f, itemUnion.origin.y - 3.0f);
        pillH = MAX(52.0f, itemUnion.size.height + 6.0f);
    }

    LGGlassView *capsule = LGAttachGlass(self, pillH * 0.5f);
    capsule.autoresizingMask = UIViewAutoresizingNone;
    capsule.frame = CGRectMake(14.0f, pillY, sz.width - 28.0f, pillH);
    [self sendSubviewToBack:capsule];
}

%end
%end

#pragma mark - Constructor (Runtime Class-Guarded Init)

%ctor {
    if (objc_getClass("YTMContentViewController"))         %init(ContentVCHooks);
    if (objc_getClass("YTMBrowseViewController"))          %init(BrowseVCHooks);
    if (objc_getClass("YTMWatchViewController"))           %init(WatchVCHooks);
    if (objc_getClass("YTMNowPlayingView"))                %init(NowPlayingViewHooks);
    if (objc_getClass("YTMPlayerControlsView"))            %init(PlayerControlsHooks);
    if (objc_getClass("YTMPlayerHeaderView"))              %init(PlayerHeaderHooks);
    if (objc_getClass("YTMPlayerCarouselView"))            %init(PlayerCarouselHooks);
    if (objc_getClass("YTMPlaylistPanelVideoCell"))        %init(PlaylistCellHooks);
    if (objc_getClass("YTMStoryboardScrubber"))            %init(ScrubberHooks);
    if (objc_getClass("YTMPlayerTabView"))                 %init(PlayerTabViewHooks);
    if (objc_getClass("YTMMiniPlayerView"))                %init(MiniPlayerHooks);
    if (objc_getClass("YTMChipCloudScrollableChipView"))   %init(ChipCloudHooks);
    if (objc_getClass("YTMActionRowView"))                 %init(ActionRowHooks);
    %init(SliderHooks);
    if (objc_getClass("YTPivotBarView") && objc_getClass("YTPivotBarItemView") && objc_getClass("YTQTMButton")) {
        %init(PivotBarHooks);
    }
}
