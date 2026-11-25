#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, YTMLiquidThemePreset) {
    YTMLiquidThemeAmbient       = 0,
    YTMLiquidThemeAuroraTeal    = 1,
    YTMLiquidThemeNebulaViolet  = 2,
    YTMLiquidThemeMarsRust      = 3,
    YTMLiquidThemeIonBlue       = 4,
    YTMLiquidThemeSolarAmber    = 5,
    YTMLiquidThemeStaticCherry  = 6,
    YTMLiquidThemeStaticMidnight= 7,
    YTMLiquidThemeStaticMatcha  = 8,
    YTMLiquidThemeStaticLavender= 9,
    YTMLiquidThemeStaticAmber   = 10
};

extern NSString * const YTMLiquidThemeDidChangeNotification;

@interface ThemeManager : NSObject

@property (nonatomic, readonly) BOOL isLightMode;
@property (nonatomic, readonly) BOOL isStaticMode;
@property (nonatomic, readonly) BOOL oledBlackEnabled;

+ (instancetype)sharedManager;

- (UIColor *)baseColor1;
- (UIColor *)baseColor2;
- (UIColor *)accentColor1;
- (UIColor *)accentColor2;
- (UIColor *)textColor;
- (UIColor *)mutedColor;
- (UIColor *)onAccentColor;

- (UIColor *)glassBackgroundColor;
- (UIColor *)glassBorderColor;
- (UIColor *)glassHighlightColor;

@end

NS_ASSUME_NONNULL_END
