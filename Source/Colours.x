#import <UIKit/UIKit.h>
#import "ThemeManager.h"

static BOOL YTMU(NSString *key) {
    NSDictionary *YTMUltimateDict = [[NSUserDefaults standardUserDefaults] dictionaryForKey:@"YTMUltimate"];
    return [YTMUltimateDict[key] boolValue];
}

static BOOL isOLEDTheme(void) {
    return YTMU(@"YTMUltimateIsEnabled") && [ThemeManager sharedManager].oledBlackEnabled;
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

#pragma mark - OLED Dark mode
@interface YTColor : UIColor
+ (UIColor *)blackPure;
@end

%hook YTColor
+ (UIColor *)black0 {
    if (![ThemeManager sharedManager].isStaticMode) return %orig;
    return isOLEDTheme() ? [self blackPure] : %orig;
}

+ (UIColor *)black1 {
    if (![ThemeManager sharedManager].isStaticMode) return %orig;
    return isOLEDTheme() ? [self blackPure] : %orig;
}

+ (UIColor *)black2 {
    if (![ThemeManager sharedManager].isStaticMode) return %orig;
    return isOLEDTheme() ? [self blackPure] : %orig;
}

+ (UIColor *)black3 {
    if (![ThemeManager sharedManager].isStaticMode) return %orig;
    return isOLEDTheme() ? [self blackPure] : %orig;
}

+ (UIColor *)black4 {
    if (![ThemeManager sharedManager].isStaticMode) return %orig;
    return isOLEDTheme() ? [self blackPure] : %orig;
}
%end

%hook YTMPlayerPageColorScheme
- (UIColor *)backgroundColor {
    if (![ThemeManager sharedManager].isStaticMode) {
        return [UIColor clearColor];
    }
    return isOLEDTheme() ? [UIColor blackColor] : %orig;
}

- (UIColor *)expandedTabsBackgroundColor {
    if (![ThemeManager sharedManager].isStaticMode) {
        return [UIColor clearColor];
    }
    return isOLEDTheme() ? [UIColor blackColor] : %orig;
}

- (UIColor *)miniPlayerColor {
    if (![ThemeManager sharedManager].isStaticMode) {
        return [[ThemeManager sharedManager] glassBackgroundColor];
    }
    return isOLEDTheme() ? [UIColor blackColor] : %orig;
}

- (UIColor *)expandedTabViewColor {
    if (![ThemeManager sharedManager].isStaticMode) {
        return [UIColor clearColor];
    }
    return isOLEDTheme() ? [UIColor blackColor] : %orig;
}

- (UIColor *)overlayButtonColor {
    if (![ThemeManager sharedManager].isStaticMode) {
        return [[ThemeManager sharedManager] glassBackgroundColor];
    }
    return isOLEDTheme() ? [UIColor blackColor] : %orig;
}

- (UIColor *)overlayErrorBackgroundColor {
    return isOLEDTheme() ? [UIColor blackColor] : %orig;
}

- (UIColor *)AVSwitchBackgroundColor {
    if (![ThemeManager sharedManager].isStaticMode) {
        return [[ThemeManager sharedManager] glassBackgroundColor];
    }
    return isOLEDTheme() ? [UIColor blackColor] : %orig;
}

- (UIColor *)AVSwitchActiveModeColor {
    if (![ThemeManager sharedManager].isStaticMode) {
        return [[ThemeManager sharedManager] accentColor1];
    }
    return isOLEDTheme() ? [[UIColor whiteColor] colorWithAlphaComponent:0.1] : %orig;
}

- (UIColor *)queueBackgroundColor {
    if (![ThemeManager sharedManager].isStaticMode) {
        return [UIColor clearColor];
    }
    return isOLEDTheme() ? [UIColor blackColor] : %orig;
}

- (UIColor *)queueCurrentlyPlayingColor {
    if (![ThemeManager sharedManager].isStaticMode) {
        return [[[ThemeManager sharedManager] accentColor1] colorWithAlphaComponent:0.25f];
    }
    return isOLEDTheme() ? [[UIColor whiteColor] colorWithAlphaComponent:0.1] : %orig;
}

- (BOOL)gradientBackgroundEnabled {
    if (![ThemeManager sharedManager].isStaticMode) return NO;
    return isOLEDTheme() ? NO : %orig;
}
%end

%hook YTPivotBarView
- (UIView *)contentView {
    UIView *orig = %orig;
    if (![ThemeManager sharedManager].isStaticMode) {
        orig.backgroundColor = [UIColor clearColor];
    } else if (isOLEDTheme()) {
        orig.backgroundColor = [UIColor blackColor];
    }
    return orig;
}
%end

@interface YTLightweightBrowseBackgroundView : UIView
@end

%hook YTLightweightBrowseBackgroundView
- (UIImageView *)imageView {
    if (![ThemeManager sharedManager].isStaticMode) {
        self.backgroundColor = [UIColor clearColor];
        return nil;
    }
    if (!isOLEDTheme()) {
        return %orig;
    }
    self.backgroundColor = [UIColor blackColor];
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
