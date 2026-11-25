#import <UIKit/UIKit.h>
#import "LiquidGlass.h"
#import "ThemeManager.h"

static BOOL YTMU(NSString *key) {
    NSDictionary *YTMUltimateDict = [[NSUserDefaults standardUserDefaults] dictionaryForKey:@"YTMUltimate"];
    return [YTMUltimateDict[key] boolValue];
}

static BOOL isOLEDKeyboard() {
    return YTMU(@"YTMUltimateIsEnabled") && YTMU(@"oledKeyboard");
}

static BOOL isLowContrast() {
    return YTMU(@"YTMUltimateIsEnabled") && YTMU(@"lowContrast");
}

@interface YTMPlayerPageColorScheme : NSObject
- (void)setPlayButtonColor:(UIColor *)color;
@end

@interface UIKeyboardDockView : UIView
@end

@interface UIKeyboardLayoutStar : UIView
@end

@interface YTPivotBarView : UIView
@end

@interface YTMMusicMenuTitleView : UIView
@end

@interface MDCSnackbarMessageView : UIView
@end

@interface UIPredictionViewController : UIViewController
@end

@interface UICandidateViewController : UIViewController
@end

%hook YTMPlayerPageColorScheme
- (UIColor *)playButtonColor {
    return LGTheme.shared.palette.a1 ?: %orig;
}

- (UIColor *)backgroundColor {
    return [UIColor clearColor];
}

- (UIColor *)expandedTabsBackgroundColor {
    return [UIColor clearColor];
}

- (UIColor *)halfExpandedTabsBackgroundColor {
    return [UIColor clearColor];
}

- (UIColor *)miniPlayerColor {
    return [UIColor clearColor];
}

- (UIColor *)tabViewColor {
    return [UIColor clearColor];
}

- (UIColor *)expandedTabViewColor {
    return [UIColor clearColor];
}

- (UIColor *)overlayButtonColor {
    if (LGTheme.shared.staticMode) {
        return LGTheme.shared.palette.b2 ?: %orig;
    }
    return [UIColor colorWithWhite:1.0f alpha:(LGTheme.shared.dark ? 0.09f : 0.55f)];
}

- (UIColor *)overlayScrimColor {
    return [UIColor clearColor];
}

- (UIColor *)AVSwitchBackgroundLightColor {
    if (LGTheme.shared.staticMode) {
        return LGTheme.shared.palette.b2 ?: %orig;
    }
    return [UIColor colorWithWhite:1.0f alpha:0.22f];
}

- (UIColor *)AVSwitchBackgroundDarkColor {
    if (LGTheme.shared.staticMode) {
        return LGTheme.shared.palette.b2 ?: %orig;
    }
    return [UIColor colorWithWhite:1.0f alpha:0.12f];
}

- (UIColor *)AVSwitchActiveModeColor {
    return LGTheme.shared.palette.a1 ?: %orig;
}

- (UIColor *)queueBackgroundColor {
    return [UIColor clearColor];
}

- (UIColor *)halfExpandedQueueBackgroundColor {
    return [UIColor clearColor];
}

- (UIColor *)queueCurrentlyPlayingColor {
    UIColor *a1 = LGTheme.shared.palette.a1;
    return a1 ? [a1 colorWithAlphaComponent:0.25f] : %orig;
}

- (UIColor *)halfExpandedQueueCurrentlyPlayingColor {
    UIColor *a1 = LGTheme.shared.palette.a1;
    return a1 ? [a1 colorWithAlphaComponent:0.25f] : %orig;
}

- (BOOL)gradientBackgroundEnabled {
    return NO;
}

- (NSArray<UIColor *> *)gradientBackgroundColors {
    return @[ [UIColor clearColor], [UIColor clearColor] ];
}

- (NSArray<UIColor *> *)playerTopScrimColors {
    return @[ [UIColor clearColor], [UIColor clearColor] ];
}

- (NSArray<UIColor *> *)playerBottomScrimColors {
    return @[ [UIColor clearColor], [UIColor clearColor] ];
}

- (NSArray<UIColor *> *)playerBottomScrimOpaqueColors {
    return @[ [UIColor clearColor], [UIColor clearColor] ];
}

- (NSArray<UIColor *> *)miniPlayerScrimColors {
    return @[ [UIColor clearColor], [UIColor clearColor] ];
}
%end

@interface YTLightweightBrowseBackgroundView : UIView
@end

@implementation YTLightweightBrowseBackgroundView (LGDummy)
@end

%hook YTLightweightBrowseBackgroundView
- (UIImageView *)imageView {
    self.backgroundColor = [UIColor clearColor];
    return nil;
}
%end

#pragma mark - OLED Dark Keyboard
%group OLEDKeyboardGroup
%hook UIPredictionViewController
- (void)loadView {
    %orig;
    if (isOLEDKeyboard()) [self.view setBackgroundColor:[UIColor blackColor]];
}
%end

%hook UICandidateViewController
- (void)loadView {
    %orig;
    if (isOLEDKeyboard()) [self.view setBackgroundColor:[UIColor blackColor]];
}
%end

%hook UIKBRenderConfig
- (void)setLightKeyboard:(BOOL)arg1 { isOLEDKeyboard() ? %orig(NO) : %orig; }
%end

%hook UIKeyboardDockView
- (void)didMoveToWindow {
    if (isOLEDKeyboard()) self.backgroundColor = [UIColor blackColor];
    %orig;
}
%end

%hook UIKeyboardLayoutStar 
- (void)didMoveToWindow {
    if (isOLEDKeyboard()) self.backgroundColor = [UIColor blackColor];
    %orig;
}
%end
%end

#pragma mark - Low contrast mode
%group CommonColorPaletteGroup
%hook YTCommonColorPalette
- (UIColor *)textPrimary { 
    return isLowContrast() ? [UIColor colorWithWhite:0.565 alpha:1] : %orig;
}
- (UIColor *)textSecondary { 
    return isLowContrast() ? [UIColor colorWithWhite:0.565 alpha:1] : %orig;
}
%end
%end

%ctor {
    %init;
    if (objc_getClass("YTCommonColorPalette")) {
        %init(CommonColorPaletteGroup);
    }
    if (objc_getClass("UIKeyboardLayoutStar")) {
        %init(OLEDKeyboardGroup);
    }
}
