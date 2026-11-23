#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface AmbientView : UIView

@property (nonatomic, assign) BOOL glowEnabled;
@property (nonatomic, assign) CGFloat glowIntensity;

- (instancetype)initWithFrame:(CGRect)frame;
- (void)updateWithArtworkImage:(nullable UIImage *)image animated:(BOOL)animated;
- (void)applyThemeColorsAnimated:(BOOL)animated;

// Helper to wrap any UIView into a liquid glass frosted card matching .glass
+ (void)applyLiquidGlassToView:(UIView *)view cornerRadius:(CGFloat)radius;

@end

NS_ASSUME_NONNULL_END
