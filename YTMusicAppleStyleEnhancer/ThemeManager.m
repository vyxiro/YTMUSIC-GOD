#import "ThemeManager.h"

NSString * const YTMThemeDidChangeNotification = @"YTMThemeDidChangeNotification";

static NSString * const kThemePrefsKey = @"YTMAppleStyleEnhancer_ThemePrefs";
static NSString * const kOLEDKey = @"oledBlackEnabled";
static NSString * const kPresetKey = @"themePreset";
static NSString * const kCustomHexKey = @"customHexColor";

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
        [self loadSettings];
    }
    return self;
}

- (void)loadSettings {
    NSDictionary *prefs = [[NSUserDefaults standardUserDefaults] dictionaryForKey:kThemePrefsKey];
    if (prefs) {
        self.oledBlackEnabled = prefs[kOLEDKey] ? [prefs[kOLEDKey] boolValue] : YES;
        self.themePreset = prefs[kPresetKey] ? [prefs[kPresetKey] integerValue] : YTMThemePresetOLEDYellow;
        self.customHexColor = prefs[kCustomHexKey] ?: @"#FFD60A";
    } else {
        // Defaults: OLED pitch-black enabled with Cyber Yellow accent
        self.oledBlackEnabled = YES;
        self.themePreset = YTMThemePresetOLEDYellow;
        self.customHexColor = @"#FFD60A";
        [self saveSettings];
    }
}

- (void)saveSettings {
    NSMutableDictionary *prefs = [NSMutableDictionary dictionary];
    prefs[kOLEDKey] = @(self.oledBlackEnabled);
    prefs[kPresetKey] = @(self.themePreset);
    prefs[kCustomHexKey] = self.customHexColor ?: @"#FFD60A";
    [[NSUserDefaults standardUserDefaults] setObject:prefs forKey:kThemePrefsKey];
    [[NSUserDefaults standardUserDefaults] synchronize];

    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:YTMThemeDidChangeNotification object:self];
    });
}

- (UIColor *)currentAccentColor {
    switch (self.themePreset) {
        case YTMThemePresetOLEDYellow:
            // OLED Cyber Yellow: vibrant, punchy high-contrast yellow
            return [UIColor colorWithRed:1.00f green:0.839f blue:0.039f alpha:1.0f]; // #FFD60A
        case YTMThemePresetOLEDGreen:
            // OLED Emerald Green: vibrant neon-emerald
            return [UIColor colorWithRed:0.188f green:0.820f blue:0.345f alpha:1.0f]; // #30D158
        case YTMThemePresetCustomHex:
            if (self.customHexColor.length > 0) {
                UIColor *color = [ThemeManager colorFromHexString:self.customHexColor];
                if (color) return color;
            }
            return [UIColor colorWithRed:1.00f green:0.839f blue:0.039f alpha:1.0f];
        case YTMThemePresetDefaultRed:
        default:
            return [UIColor colorWithRed:1.00f green:0.00f blue:0.00f alpha:1.0f]; // YouTube Red
    }
}

- (UIColor *)currentAccentHighlightColor {
    UIColor *base = [self currentAccentColor];
    CGFloat r, g, b, a;
    if ([base getRed:&r green:&g blue:&b alpha:&a]) {
        return [UIColor colorWithRed:MIN(1.0f, r * 1.15f)
                               green:MIN(1.0f, g * 1.15f)
                                blue:MIN(1.0f, b * 1.15f)
                               alpha:a];
    }
    return base;
}

- (UIColor *)oledBackgroundColor {
    if (!self.oledBlackEnabled) {
        return [UIColor colorWithRed:0.07f green:0.07f blue:0.07f alpha:1.0f];
    }
    return [UIColor blackColor]; // #000000 pure OLED black
}

- (UIColor *)oledSurfaceColor {
    if (!self.oledBlackEnabled) {
        return [UIColor colorWithRed:0.12f green:0.12f blue:0.12f alpha:1.0f];
    }
    // Deepest obsidian black with ultra-subtle separation for cards
    return [UIColor colorWithRed:0.02f green:0.02f blue:0.02f alpha:1.0f];
}

#pragma mark - Hex Utilities

+ (UIColor *)colorFromHexString:(NSString *)hexString {
    if (!hexString) return nil;
    NSString *cleanString = [hexString stringByReplacingOccurrencesOfString:@"#" withString:@""];
    cleanString = [cleanString stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    
    unsigned int rgbValue = 0;
    NSScanner *scanner = [NSScanner scannerWithString:cleanString];
    if (![scanner scanHexInt:&rgbValue]) {
        return nil;
    }
    
    if (cleanString.length == 6) {
        return [UIColor colorWithRed:((rgbValue & 0xFF0000) >> 16) / 255.0f
                               green:((rgbValue & 0x00FF00) >> 8) / 255.0f
                                blue:(rgbValue & 0x0000FF) / 255.0f
                               alpha:1.0f];
    } else if (cleanString.length == 8) {
        return [UIColor colorWithRed:((rgbValue & 0xFF000000) >> 24) / 255.0f
                               green:((rgbValue & 0x00FF0000) >> 16) / 255.0f
                                blue:((rgbValue & 0x0000FF00) >> 8) / 255.0f
                               alpha:(rgbValue & 0x000000FF) / 255.0f];
    }
    return nil;
}

+ (NSString *)hexStringFromColor:(UIColor *)color {
    if (!color) return @"#FFD60A";
    CGFloat r, g, b, a;
    if ([color getRed:&r green:&g blue:&b alpha:&a]) {
        return [NSString stringWithFormat:@"#%02X%02X%02X",
                (int)(r * 255.0f), (int)(g * 255.0f), (int)(b * 255.0f)];
    }
    return @"#FFD60A";
}

@end
