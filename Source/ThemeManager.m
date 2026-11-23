#import "ThemeManager.h"

NSString * const YTMLiquidThemeDidChangeNotification = @"YTMLiquidThemeDidChangeNotification";

static NSString * const kYTMUltimateKey = @"YTMUltimate";
static NSString * const kLiquidThemeKey = @"liquidThemePreset";
static NSString * const kLightModeKey = @"liquidIsLightMode";
static NSString * const kStaticModeKey = @"liquidIsStaticMode";
static NSString * const kOLEDKey = @"oledTheme";

@interface ThemeManager ()

@property (nonatomic, strong) UIColor *ambientA1;
@property (nonatomic, strong) UIColor *ambientA2;
@property (nonatomic, strong) UIColor *ambientB1;
@property (nonatomic, strong) UIColor *ambientB2;

@end

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
        // Defaults to Aurora Teal in dark mode as initial ambient fallback
        self.ambientA1 = [ThemeManager colorFromHexString:@"#19D3B0"];
        self.ambientA2 = [ThemeManager colorFromHexString:@"#3A7BFF"];
        self.ambientB1 = [ThemeManager colorFromHexString:@"#06191C"];
        self.ambientB2 = [ThemeManager colorFromHexString:@"#0B2E33"];
        [self loadSettings];
    }
    return self;
}

- (void)loadSettings {
    NSDictionary *dict = [[NSUserDefaults standardUserDefaults] dictionaryForKey:kYTMUltimateKey];
    if (dict) {
        self.liquidTheme = dict[kLiquidThemeKey] ? [dict[kLiquidThemeKey] integerValue] : YTMLiquidThemeAmbient;
        self.isLightMode = dict[kLightModeKey] ? [dict[kLightModeKey] boolValue] : NO;
        self.isStaticMode = dict[kStaticModeKey] ? [dict[kStaticModeKey] boolValue] : NO;
        self.oledBlackEnabled = dict[kOLEDKey] ? [dict[kOLEDKey] boolValue] : YES;
    } else {
        self.liquidTheme = YTMLiquidThemeAmbient;
        self.isLightMode = NO;
        self.isStaticMode = NO;
        self.oledBlackEnabled = YES;
        [self saveSettings];
    }
}

- (void)saveSettings {
    NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithDictionary:[[NSUserDefaults standardUserDefaults] dictionaryForKey:kYTMUltimateKey]];
    dict[kLiquidThemeKey] = @(self.liquidTheme);
    dict[kLightModeKey] = @(self.isLightMode);
    dict[kStaticModeKey] = @(self.isStaticMode);
    dict[kOLEDKey] = @(self.oledBlackEnabled);
    [[NSUserDefaults standardUserDefaults] setObject:dict forKey:kYTMUltimateKey];
    [[NSUserDefaults standardUserDefaults] synchronize];

    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:YTMLiquidThemeDidChangeNotification object:self];
    });
}

#pragma mark - Theme Palette Colors (From User Liquid Glass Spec)

- (UIColor *)baseColor1 {
    if (self.oledBlackEnabled && !self.isLightMode && self.liquidTheme != YTMLiquidThemeAmbient) {
        return [UIColor blackColor];
    }

    switch (self.liquidTheme) {
        case YTMLiquidThemeAmbient:
            return self.ambientB1 ?: [ThemeManager colorFromHexString:self.isLightMode ? @"#EEFBF9" : @"#06191C"];
        case YTMLiquidThemeAuroraTeal:
            return [ThemeManager colorFromHexString:self.isLightMode ? @"#EEFBF9" : @"#06191C"];
        case YTMLiquidThemeNebulaViolet:
            return [ThemeManager colorFromHexString:self.isLightMode ? @"#F5F1FF" : @"#110A24"];
        case YTMLiquidThemeMarsRust:
            return [ThemeManager colorFromHexString:self.isLightMode ? @"#FFF3EC" : @"#1C0B07"];
        case YTMLiquidThemeIonBlue:
            return [ThemeManager colorFromHexString:self.isLightMode ? @"#EEF4FF" : @"#060D1F"];
        case YTMLiquidThemeSolarAmber:
            return [ThemeManager colorFromHexString:self.isLightMode ? @"#FFFAEA" : @"#1A1204"];
        case YTMLiquidThemeStaticCherry:
            return [ThemeManager colorFromHexString:self.isLightMode ? @"#FFF7F2" : @"#121212"];
        case YTMLiquidThemeStaticMidnight:
            return [ThemeManager colorFromHexString:self.isLightMode ? @"#E9F1FF" : @"#0B1230"];
        case YTMLiquidThemeStaticMatcha:
            return [ThemeManager colorFromHexString:self.isLightMode ? @"#FFF9E6" : @"#0D2E1E"];
        case YTMLiquidThemeStaticLavender:
            return [ThemeManager colorFromHexString:self.isLightMode ? @"#F3E9FF" : @"#1A0B28"];
        case YTMLiquidThemeStaticAmber:
            return [ThemeManager colorFromHexString:self.isLightMode ? @"#FDEBD7" : @"#2A1A0F"];
    }
}

- (UIColor *)baseColor2 {
    switch (self.liquidTheme) {
        case YTMLiquidThemeAmbient:
            return self.ambientB2 ?: [ThemeManager colorFromHexString:self.isLightMode ? @"#D3F2EE" : @"#0B2E33"];
        case YTMLiquidThemeAuroraTeal:
            return [ThemeManager colorFromHexString:self.isLightMode ? @"#D3F2EE" : @"#0B2E33"];
        case YTMLiquidThemeNebulaViolet:
            return [ThemeManager colorFromHexString:self.isLightMode ? @"#E4DBFF" : @"#241346"];
        case YTMLiquidThemeMarsRust:
            return [ThemeManager colorFromHexString:self.isLightMode ? @"#FFDCCC" : @"#3A1710"];
        case YTMLiquidThemeIonBlue:
            return [ThemeManager colorFromHexString:self.isLightMode ? @"#D3E3FF" : @"#0E1F47"];
        case YTMLiquidThemeSolarAmber:
            return [ThemeManager colorFromHexString:self.isLightMode ? @"#FFECB8" : @"#33220A"];
        default:
            return [self baseColor1];
    }
}

- (UIColor *)accentColor1 {
    switch (self.liquidTheme) {
        case YTMLiquidThemeAmbient:
            return self.ambientA1 ?: [ThemeManager colorFromHexString:@"#19D3B0"];
        case YTMLiquidThemeAuroraTeal:
            return [ThemeManager colorFromHexString:self.isLightMode ? @"#0AA88A" : @"#19D3B0"];
        case YTMLiquidThemeNebulaViolet:
            return [ThemeManager colorFromHexString:self.isLightMode ? @"#6A47EE" : @"#9A7BFF"];
        case YTMLiquidThemeMarsRust:
            return [ThemeManager colorFromHexString:self.isLightMode ? @"#E24A1A" : @"#FF6A3D"];
        case YTMLiquidThemeIonBlue:
            return [ThemeManager colorFromHexString:self.isLightMode ? @"#1A63E0" : @"#3D8BFF"];
        case YTMLiquidThemeSolarAmber:
            return [ThemeManager colorFromHexString:self.isLightMode ? @"#E09A00" : @"#FFC21F"];
        case YTMLiquidThemeStaticCherry:
            return [ThemeManager colorFromHexString:@"#FF0000"];
        case YTMLiquidThemeStaticMidnight:
            return [ThemeManager colorFromHexString:@"#3B5BFF"];
        case YTMLiquidThemeStaticMatcha:
            return [ThemeManager colorFromHexString:@"#00C853"];
        case YTMLiquidThemeStaticLavender:
            return [ThemeManager colorFromHexString:@"#8A2BE2"];
        case YTMLiquidThemeStaticAmber:
            return [ThemeManager colorFromHexString:@"#FF8C00"];
    }
}

- (UIColor *)accentColor2 {
    switch (self.liquidTheme) {
        case YTMLiquidThemeAmbient:
            return self.ambientA2 ?: [ThemeManager colorFromHexString:@"#3A7BFF"];
        case YTMLiquidThemeAuroraTeal:
            return [ThemeManager colorFromHexString:self.isLightMode ? @"#5B9BFF" : @"#3A7BFF"];
        case YTMLiquidThemeNebulaViolet:
            return [ThemeManager colorFromHexString:self.isLightMode ? @"#FF7AB8" : @"#FF5FB0"];
        case YTMLiquidThemeMarsRust:
            return [ThemeManager colorFromHexString:self.isLightMode ? @"#FF9F43" : @"#FFB347"];
        case YTMLiquidThemeIonBlue:
            return [ThemeManager colorFromHexString:self.isLightMode ? @"#27B9E6" : @"#29E0FF"];
        case YTMLiquidThemeSolarAmber:
            return [ThemeManager colorFromHexString:self.isLightMode ? @"#FF7A98" : @"#FF6F91"];
        default:
            return [self accentColor1];
    }
}

- (UIColor *)textColor {
    switch (self.liquidTheme) {
        case YTMLiquidThemeAuroraTeal:
            return [ThemeManager colorFromHexString:self.isLightMode ? @"#08302B" : @"#EAFFFB"];
        case YTMLiquidThemeNebulaViolet:
            return [ThemeManager colorFromHexString:self.isLightMode ? @"#241346" : @"#F4EFFF"];
        case YTMLiquidThemeMarsRust:
            return [ThemeManager colorFromHexString:self.isLightMode ? @"#3A1710" : @"#FFF1EA"];
        case YTMLiquidThemeIonBlue:
            return [ThemeManager colorFromHexString:self.isLightMode ? @"#0E1F47" : @"#ECF3FF"];
        case YTMLiquidThemeSolarAmber:
            return [ThemeManager colorFromHexString:self.isLightMode ? @"#33220A" : @"#FFF8E6"];
        default:
            return self.isLightMode ? [UIColor colorWithWhite:0.1f alpha:1.0f] : [UIColor whiteColor];
    }
}

- (UIColor *)mutedColor {
    switch (self.liquidTheme) {
        case YTMLiquidThemeAuroraTeal:
            return [ThemeManager colorFromHexString:self.isLightMode ? @"#4F7A74" : @"#8FB8B3"];
        case YTMLiquidThemeNebulaViolet:
            return [ThemeManager colorFromHexString:self.isLightMode ? @"#6B5D92" : @"#A99CC8"];
        case YTMLiquidThemeMarsRust:
            return [ThemeManager colorFromHexString:self.isLightMode ? @"#92604F" : @"#C29A8C"];
        case YTMLiquidThemeIonBlue:
            return [ThemeManager colorFromHexString:self.isLightMode ? @"#566B96" : @"#8FA6CF"];
        case YTMLiquidThemeSolarAmber:
            return [ThemeManager colorFromHexString:self.isLightMode ? @"#8B7440" : @"#C7B283"];
        default:
            return [UIColor secondaryLabelColor];
    }
}

#pragma mark - Glass Material Tokens

- (UIColor *)glassBackgroundColor {
    if (self.isLightMode) {
        return [UIColor colorWithWhite:1.0f alpha:0.55f]; // --g: rgba(255,255,255,.55)
    }
    return [UIColor colorWithWhite:1.0f alpha:0.09f]; // --g: rgba(255,255,255,.09)
}

- (UIColor *)glassBorderColor {
    if (self.isLightMode) {
        return [UIColor colorWithWhite:1.0f alpha:0.80f]; // --gb: rgba(255,255,255,.8)
    }
    return [UIColor colorWithWhite:1.0f alpha:0.20f]; // --gb: rgba(255,255,255,.2)
}

- (UIColor *)glassHighlightColor {
    if (self.isLightMode) {
        return [UIColor colorWithWhite:1.0f alpha:0.95f]; // --hl: rgba(255,255,255,.95)
    }
    return [UIColor colorWithWhite:1.0f alpha:0.28f]; // --hl: rgba(255,255,255,.28)
}

#pragma mark - Ambient Updates

- (void)updateAmbientColorsWithAccent1:(UIColor *)a1 accent2:(UIColor *)a2 base1:(UIColor *)b1 base2:(UIColor *)b2 {
    self.ambientA1 = a1;
    self.ambientA2 = a2;
    self.ambientB1 = b1;
    self.ambientB2 = b2;

    if (self.liquidTheme == YTMLiquidThemeAmbient) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:YTMLiquidThemeDidChangeNotification object:self];
        });
    }
}

#pragma mark - Utilities

+ (UIColor *)colorFromHexString:(NSString *)hexString {
    if (!hexString) return nil;
    NSString *clean = [hexString stringByReplacingOccurrencesOfString:@"#" withString:@""];
    clean = [clean stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    unsigned int rgb = 0;
    NSScanner *scanner = [NSScanner scannerWithString:clean];
    if (![scanner scanHexInt:&rgb]) return nil;

    if (clean.length == 6) {
        return [UIColor colorWithRed:((rgb & 0xFF0000) >> 16) / 255.0f
                               green:((rgb & 0x00FF00) >> 8) / 255.0f
                                blue:(rgb & 0x0000FF) / 255.0f
                               alpha:1.0f];
    } else if (clean.length == 8) {
        return [UIColor colorWithRed:((rgb & 0xFF000000) >> 24) / 255.0f
                               green:((rgb & 0x00FF0000) >> 16) / 255.0f
                                blue:((rgb & 0x0000FF00) >> 8) / 255.0f
                               alpha:(rgb & 0x000000FF) / 255.0f];
    }
    return nil;
}

+ (NSString *)hexStringFromColor:(UIColor *)color {
    if (!color) return @"#19D3B0";
    CGFloat r, g, b, a;
    if ([color getRed:&r green:&g blue:&b alpha:&a]) {
        return [NSString stringWithFormat:@"#%02X%02X%02X",
                (int)(r * 255.0f), (int)(g * 255.0f), (int)(b * 255.0f)];
    }
    return @"#19D3B0";
}

@end
