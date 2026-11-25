#import "AmbientView.h"
#import "LiquidGlass.h"

@interface AmbientView ()
@property (nonatomic, strong) LGBackgroundView *bgView;
@end

@implementation AmbientView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.userInteractionEnabled = NO;
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.backgroundColor = [UIColor clearColor];
        _glowEnabled = YES;
        _glowIntensity = 0.75f;
        _bgView = [[LGBackgroundView alloc] initWithFrame:self.bounds];
        _bgView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self addSubview:_bgView];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    _bgView.frame = self.bounds;
}

- (void)updateWithArtworkImage:(nullable UIImage *)image animated:(BOOL)animated {
    // Artwork ingestion is driven cleanly by LGIngestNowPlayingInfo -> LGTheme -> LGBackgroundView.
}

- (void)applyThemeColorsAnimated:(BOOL)animated {
    LGTheme *t = LGTheme.shared;
    _bgView.darkStyle = t.dark;
    _bgView.staticMode = t.staticMode;
    [_bgView applyPalette:t.palette animated:animated];
}

+ (void)applyLiquidGlassToView:(UIView *)view cornerRadius:(CGFloat)radius {
    if (!view) return;
    LGAttachGlass(view, radius);
}

@end
