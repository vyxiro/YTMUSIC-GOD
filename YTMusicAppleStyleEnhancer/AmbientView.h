#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface AmbientView : UIView

@property (nonatomic, assign) BOOL glowEnabled;
@property (nonatomic, assign) CGFloat glowIntensity; // 0.1 to 1.0, default 0.65

- (instancetype)initWithFrame:(CGRect)frame;
- (void)updateWithArtworkImage:(nullable UIImage *)image animated:(BOOL)animated;
- (void)applyThemeUpdates;

@end

NS_ASSUME_NONNULL_END
