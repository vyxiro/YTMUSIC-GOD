#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, YTMThemePreset) {
    YTMThemePresetDefaultRed = 0,
    YTMThemePresetOLEDYellow = 1,
    YTMThemePresetOLEDGreen  = 2,
    YTMThemePresetCustomHex  = 3
};

// Notification posted when theme settings change
extern NSString * const YTMThemeDidChangeNotification;

@interface ThemeManager : NSObject

@property (nonatomic, assign) BOOL oledBlackEnabled;
@property (nonatomic, assign) YTMThemePreset themePreset;
@property (nonatomic, copy) NSString *customHexColor;

+ (instancetype)sharedManager;

- (UIColor *)currentAccentColor;
- (UIColor *)currentAccentHighlightColor;
- (UIColor *)oledBackgroundColor;
- (UIColor *)oledSurfaceColor;

- (void)saveSettings;
- (void)loadSettings;

+ (UIColor *)colorFromHexString:(NSString *)hexString;
+ (NSString *)hexStringFromColor:(UIColor *)color;

@end

NS_ASSUME_NONNULL_END
