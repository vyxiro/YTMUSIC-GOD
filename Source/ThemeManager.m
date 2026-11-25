#import "ThemeManager.h"
#import "LiquidGlass.h"

NSString * const YTMLiquidThemeDidChangeNotification = @"YTMLiquidThemeDidChangeNotification";

@implementation ThemeManager

+ (instancetype)sharedManager {
    static ThemeManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[ThemeManager alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        [[NSNotificationCenter defaultCenter] addObserverForName:LGPaletteDidChangeNotification
                                                          object:nil
                                                           queue:[NSOperationQueue mainQueue]
                                                      usingBlock:^(__unused NSNotification *note) {
            [[NSNotificationCenter defaultCenter] postNotificationName:YTMLiquidThemeDidChangeNotification object:self];
        }];
    }
    return self;
}

- (BOOL)isLightMode { return !LGTheme.shared.dark; }
- (BOOL)isStaticMode { return LGTheme.shared.staticMode; }
- (BOOL)oledBlackEnabled { return NO; }

- (UIColor *)baseColor1 { return LGTheme.shared.palette.b1; }
- (UIColor *)baseColor2 { return LGTheme.shared.palette.b2; }
- (UIColor *)accentColor1 { return LGTheme.shared.palette.a1; }
- (UIColor *)accentColor2 { return LGTheme.shared.palette.a2; }
- (UIColor *)textColor { return LGTheme.shared.palette.tx; }
- (UIColor *)mutedColor { return LGTheme.shared.palette.mu; }
- (UIColor *)onAccentColor { return LGTheme.shared.palette.onAccent; }

- (UIColor *)glassBackgroundColor {
    if (LGTheme.shared.staticMode) {
        return LGTheme.shared.palette.b2;
    }
    return [UIColor colorWithWhite:1.0f alpha:(LGTheme.shared.dark ? 0.09f : 0.55f)];
}

- (UIColor *)glassBorderColor {
    if (LGTheme.shared.staticMode) {
        return [UIColor colorWithWhite:0.5f alpha:0.35f];
    }
    return [UIColor colorWithWhite:1.0f alpha:(LGTheme.shared.dark ? 0.20f : 0.80f)];
}

- (UIColor *)glassHighlightColor {
    if (LGTheme.shared.staticMode) {
        return [UIColor clearColor];
    }
    return [UIColor colorWithWhite:1.0f alpha:(LGTheme.shared.dark ? 0.28f : 0.95f)];
}

@end
