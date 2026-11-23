#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, YTMLiquidThemePreset) {
    YTMLiquidThemeAmbient       = 0, // Dynamic artwork color extraction with 1.8s morph
    YTMLiquidThemeAuroraTeal    = 1, // #06191C, #19D3B0, #3A7BFF
    YTMLiquidThemeNebulaViolet  = 2, // #110A24, #9A7BFF, #FF5FB0
    YTMLiquidThemeMarsRust      = 3, // #1C0B07, #FF6A3D, #FFB347
    YTMLiquidThemeIonBlue       = 4, // #060D1F, #3D8BFF, #29E0FF
    YTMLiquidThemeSolarAmber    = 5, // #1A1204, #FFC21F, #FF6F91
    YTMLiquidThemeStaticCherry  = 6, // #FF0000, #121212
    YTMLiquidThemeStaticMidnight= 7, // #3B5BFF, #0B1230
    YTMLiquidThemeStaticMatcha  = 8, // #00C853, #0D2E1E
    YTMLiquidThemeStaticLavender= 9, // #8A2BE2, #1A0B28
    YTMLiquidThemeStaticAmber   = 10 // #FF8C00, #2A1A0F
};

extern NSString * const YTMLiquidThemeDidChangeNotification;

@interface ThemeManager : NSObject

@property (nonatomic, assign) YTMLiquidThemePreset liquidTheme;
@property (nonatomic, assign) BOOL isLightMode;
@property (nonatomic, assign) BOOL isStaticMode; // Disables blobs & blurs for flat reference look
@property (nonatomic, assign) BOOL oledBlackEnabled;
@property (nonatomic, copy) NSString *customHexColor;

+ (instancetype)sharedManager;

// Liquid Glass Palette Colors
- (UIColor *)baseColor1;
- (UIColor *)baseColor2;
- (UIColor *)accentColor1;
- (UIColor *)accentColor2;
- (UIColor *)textColor;
- (UIColor *)mutedColor;

// Glass Material Properties
- (UIColor *)glassBackgroundColor;
- (UIColor *)glassBorderColor;
- (UIColor *)glassHighlightColor;

// Dynamic Ambient Color updates (from song artwork)
- (void)updateAmbientColorsWithAccent1:(UIColor *)a1 accent2:(UIColor *)a2 base1:(UIColor *)b1 base2:(UIColor *)b2;

- (void)loadSettings;
- (void)saveSettings;

+ (UIColor *)colorFromHexString:(NSString *)hexString;
+ (NSString *)hexStringFromColor:(UIColor *)color;

@end

NS_ASSUME_NONNULL_END
