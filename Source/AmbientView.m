#import "AmbientView.h"
#import "ThemeManager.h"
#import <QuartzCore/QuartzCore.h>

@interface AmbientView ()

@property (nonatomic, strong) CAGradientLayer *backgroundGradientLayer;
@property (nonatomic, strong) CAGradientLayer *blobALayer;
@property (nonatomic, strong) CAGradientLayer *blobBLayer;
@property (nonatomic, strong) UIVisualEffectView *diffuseBlurView;
@property (nonatomic, strong) UIImage *lastProcessedArtwork;

@end

@implementation AmbientView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.glowEnabled = YES;
        self.glowIntensity = 0.75f;
        [self setupLiquidGlassLayers];

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(handleThemeChanged)
                                                     name:YTMLiquidThemeDidChangeNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(handleArtworkNotification:)
                                                     name:@"YTMArtworkDidUpdateNotification"
                                                   object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)handleArtworkNotification:(NSNotification *)note {
    if ([note.object isKindOfClass:[UIImage class]]) {
        [self updateWithArtworkImage:(UIImage *)note.object animated:YES];
    }
}

- (void)setupLiquidGlassLayers {
    self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.clipsToBounds = YES;
    self.userInteractionEnabled = NO;

    ThemeManager *tm = [ThemeManager sharedManager];

    // 1. 170-degree Linear Gradient Background: linear-gradient(170deg, var(--b1), var(--b2))
    self.backgroundGradientLayer = [CAGradientLayer layer];
    self.backgroundGradientLayer.frame = self.bounds;
    self.backgroundGradientLayer.startPoint = CGPointMake(0.35, 0.0);
    self.backgroundGradientLayer.endPoint = CGPointMake(0.65, 1.0);

    UIColor *initB1 = [tm baseColor1] ?: [ThemeManager colorFromHexString:@"#06191C"];
    UIColor *initB2 = [tm baseColor2] ?: [ThemeManager colorFromHexString:@"#0B2E33"];
    UIColor *initA1 = [tm accentColor1] ?: [ThemeManager colorFromHexString:@"#19D3B0"];
    UIColor *initA2 = [tm accentColor2] ?: [ThemeManager colorFromHexString:@"#3A7BFF"];

    self.backgroundGradientLayer.colors = @[(id)initB1.CGColor, (id)initB2.CGColor];
    [self.layer addSublayer:self.backgroundGradientLayer];

    // 2. Blob A: Radial gradient orb (replaces hard CALayer circle with soft Gaussian glow matching filter: blur(38px))
    self.blobALayer = [CAGradientLayer layer];
    self.blobALayer.type = kCAGradientLayerRadial;
    self.blobALayer.startPoint = CGPointMake(0.5, 0.5);
    self.blobALayer.endPoint = CGPointMake(1.0, 1.0);
    self.blobALayer.colors = @[
        (id)[initA1 colorWithAlphaComponent:0.80f].CGColor,
        (id)[initA1 colorWithAlphaComponent:0.40f].CGColor,
        (id)[initA1 colorWithAlphaComponent:0.0f].CGColor
    ];
    self.blobALayer.locations = @[@0.0, @0.5, @1.0];
    [self.layer addSublayer:self.blobALayer];

    // 3. Blob B: Radial gradient orb
    self.blobBLayer = [CAGradientLayer layer];
    self.blobBLayer.type = kCAGradientLayerRadial;
    self.blobBLayer.startPoint = CGPointMake(0.5, 0.5);
    self.blobBLayer.endPoint = CGPointMake(1.0, 1.0);
    self.blobBLayer.colors = @[
        (id)[initA2 colorWithAlphaComponent:0.65f].CGColor,
        (id)[initA2 colorWithAlphaComponent:0.30f].CGColor,
        (id)[initA2 colorWithAlphaComponent:0.0f].CGColor
    ];
    self.blobBLayer.locations = @[@0.0, @0.5, @1.0];
    [self.layer addSublayer:self.blobBLayer];

    // 4. Liquid Glass Diffuse Blur Overlay
    UIBlurEffect *blur = [UIBlurEffect effectWithStyle:tm.isLightMode ? UIBlurEffectStyleLight : UIBlurEffectStyleDark];
    self.diffuseBlurView = [[UIVisualEffectView alloc] initWithEffect:blur];
    self.diffuseBlurView.frame = self.bounds;
    self.diffuseBlurView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.diffuseBlurView.alpha = 0.35f;
    [self addSubview:self.diffuseBlurView];

    [self updateBlobLayout];
    [self startBlobFloatingAnimations];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.backgroundGradientLayer.frame = self.bounds;
    self.diffuseBlurView.frame = self.bounds;
    [self updateBlobLayout];
}

- (void)updateBlobLayout {
    CGFloat w = self.bounds.size.width;
    CGFloat h = self.bounds.size.height;
    if (w <= 0 || h <= 0) return;

    // Blob A: width 280, height 280, top-right
    self.blobALayer.frame = CGRectMake(w - 200, -50, 280, 280);

    // Blob B: width 260, height 260, mid-left
    self.blobBLayer.frame = CGRectMake(-80, h * 0.32, 260, 260);
}

- (void)startBlobFloatingAnimations {
    [self.blobALayer removeAnimationForKey:@"floatA"];
    [self.blobBLayer removeAnimationForKey:@"floatB"];

    CAKeyframeAnimation *animA = [CAKeyframeAnimation animationWithKeyPath:@"transform.translation"];
    animA.values = @[
        [NSValue valueWithCGSize:CGSizeMake(0, 0)],
        [NSValue valueWithCGSize:CGSizeMake(-30, 35)],
        [NSValue valueWithCGSize:CGSizeMake(20, 50)],
        [NSValue valueWithCGSize:CGSizeMake(25, -20)],
        [NSValue valueWithCGSize:CGSizeMake(0, 0)]
    ];
    animA.duration = 14.0;
    animA.repeatCount = HUGE_VALF;
    animA.autoreverses = YES;
    animA.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    [self.blobALayer addAnimation:animA forKey:@"floatA"];

    CAKeyframeAnimation *animB = [CAKeyframeAnimation animationWithKeyPath:@"transform.translation"];
    animB.values = @[
        [NSValue valueWithCGSize:CGSizeMake(0, 0)],
        [NSValue valueWithCGSize:CGSizeMake(35, -30)],
        [NSValue valueWithCGSize:CGSizeMake(-25, -45)],
        [NSValue valueWithCGSize:CGSizeMake(-20, 25)],
        [NSValue valueWithCGSize:CGSizeMake(0, 0)]
    ];
    animB.duration = 18.0;
    animB.repeatCount = HUGE_VALF;
    animB.autoreverses = YES;
    animB.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    [self.blobBLayer addAnimation:animB forKey:@"floatB"];
}

- (void)handleThemeChanged {
    [self applyThemeColorsAnimated:YES];
}

- (void)applyThemeColorsAnimated:(BOOL)animated {
    ThemeManager *tm = [ThemeManager sharedManager];

    UIColor *b1 = [tm baseColor1] ?: [ThemeManager colorFromHexString:@"#06191C"];
    UIColor *b2 = [tm baseColor2] ?: [ThemeManager colorFromHexString:@"#0B2E33"];
    UIColor *a1 = [tm accentColor1] ?: [ThemeManager colorFromHexString:@"#19D3B0"];
    UIColor *a2 = [tm accentColor2] ?: [ThemeManager colorFromHexString:@"#3A7BFF"];

    if (tm.isStaticMode) {
        self.blobALayer.hidden = YES;
        self.blobBLayer.hidden = YES;
        self.diffuseBlurView.hidden = YES;
        self.backgroundGradientLayer.colors = @[(id)b1.CGColor, (id)b1.CGColor];
        return;
    }

    self.blobALayer.hidden = NO;
    self.blobBLayer.hidden = NO;
    self.diffuseBlurView.hidden = NO;

    NSArray *newBgColors = @[(id)b1.CGColor, (id)b2.CGColor];
    NSArray *newBlobAColors = @[
        (id)[a1 colorWithAlphaComponent:0.80f].CGColor,
        (id)[a1 colorWithAlphaComponent:0.40f].CGColor,
        (id)[a1 colorWithAlphaComponent:0.0f].CGColor
    ];
    NSArray *newBlobBColors = @[
        (id)[a2 colorWithAlphaComponent:0.65f].CGColor,
        (id)[a2 colorWithAlphaComponent:0.30f].CGColor,
        (id)[a2 colorWithAlphaComponent:0.0f].CGColor
    ];

    if (animated) {
        CFTimeInterval duration = 1.8; // Exact transition from user CSS spec (1.8s ease)
        CAMediaTimingFunction *ease = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];

        CABasicAnimation *bgAnim = [CABasicAnimation animationWithKeyPath:@"colors"];
        bgAnim.fromValue = self.backgroundGradientLayer.colors;
        bgAnim.toValue = newBgColors;
        bgAnim.duration = duration;
        bgAnim.timingFunction = ease;
        [self.backgroundGradientLayer addAnimation:bgAnim forKey:@"bgAnim"];

        CABasicAnimation *blobAAnim = [CABasicAnimation animationWithKeyPath:@"colors"];
        blobAAnim.fromValue = self.blobALayer.colors;
        blobAAnim.toValue = newBlobAColors;
        blobAAnim.duration = duration;
        blobAAnim.timingFunction = ease;
        [self.blobALayer addAnimation:blobAAnim forKey:@"blobAColorsAnim"];

        CABasicAnimation *blobBAnim = [CABasicAnimation animationWithKeyPath:@"colors"];
        blobBAnim.fromValue = self.blobBLayer.colors;
        blobBAnim.toValue = newBlobBColors;
        blobBAnim.duration = duration;
        blobBAnim.timingFunction = ease;
        [self.blobBLayer addAnimation:blobBAnim forKey:@"blobBColorsAnim"];
    }

    self.backgroundGradientLayer.colors = newBgColors;
    self.blobALayer.colors = newBlobAColors;
    self.blobBLayer.colors = newBlobBColors;
}

#pragma mark - Artwork Color Analysis for Ambient Mode

- (void)updateWithArtworkImage:(nullable UIImage *)image animated:(BOOL)animated {
    if (!self.glowEnabled || !image) return;
    if (self.lastProcessedArtwork == image) return;
    self.lastProcessedArtwork = image;

    ThemeManager *tm = [ThemeManager sharedManager];
    if (tm.liquidTheme != YTMLiquidThemeAmbient) return;

    CGImageRef cgImage = image.CGImage;
    if (!cgImage) return;
    CGImageRetain(cgImage);

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        size_t width = 20;
        size_t height = 20;
        size_t bytesPerRow = width * 4;
        uint8_t *rawData = (uint8_t *)calloc(height * bytesPerRow, sizeof(uint8_t));
        if (!rawData) {
            CGImageRelease(cgImage);
            return;
        }

        CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
        CGContextRef context = CGBitmapContextCreate(rawData, width, height, 8, bytesPerRow, colorSpace,
                                                     kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
        CGColorSpaceRelease(colorSpace);
        if (!context) {
            free(rawData);
            CGImageRelease(cgImage);
            return;
        }

        CGContextDrawImage(context, CGRectMake(0, 0, width, height), cgImage);
        CGContextRelease(context);
        CGImageRelease(cgImage);

        UIColor *cand1 = nil;
        UIColor *cand2 = nil;
        CGFloat maxScore1 = -1.0;
        CGFloat maxScore2 = -1.0;

        for (size_t y = 0; y < height; y++) {
            for (size_t x = 0; x < width; x++) {
                size_t idx = (y * bytesPerRow) + (x * 4);
                CGFloat r = rawData[idx] / 255.0f;
                CGFloat g = rawData[idx + 1] / 255.0f;
                CGFloat b = rawData[idx + 2] / 255.0f;

                UIColor *color = [UIColor colorWithRed:r green:g blue:b alpha:1.0f];
                CGFloat h, s, v, a;
                [color getHue:&h saturation:&s brightness:&v alpha:&a];

                if (v < 0.20 || v > 0.95 || s < 0.25) continue;

                CGFloat score = (s * 0.60) + (v * 0.40);
                if (score > maxScore1) {
                    maxScore2 = maxScore1;
                    cand2 = cand1;
                    maxScore1 = score;
                    cand1 = color;
                } else if (score > maxScore2) {
                    maxScore2 = score;
                    cand2 = color;
                }
            }
        }
        free(rawData);

        if (!cand1) cand1 = [ThemeManager colorFromHexString:@"#19D3B0"] ?: [UIColor cyanColor];
        if (!cand2) cand2 = [cand1 colorWithAlphaComponent:0.75] ?: [UIColor blueColor];

        // Derive subtle dark gradient bases
        CGFloat r1, g1, b1, a1;
        [cand1 getRed:&r1 green:&g1 blue:&b1 alpha:&a1];
        UIColor *derivedB1 = [UIColor colorWithRed:r1 * 0.10 green:g1 * 0.10 blue:b1 * 0.10 alpha:1.0];
        UIColor *derivedB2 = [UIColor colorWithRed:r1 * 0.20 green:g1 * 0.20 blue:b1 * 0.20 alpha:1.0];

        dispatch_async(dispatch_get_main_queue(), ^{
            [tm updateAmbientColorsWithAccent1:cand1 accent2:cand2 base1:derivedB1 base2:derivedB2];
            [self applyThemeColorsAnimated:animated];
        });
    });
}

#pragma mark - Liquid Glass Helper (Matching .glass CSS spec)

+ (void)applyLiquidGlassToView:(UIView *)view cornerRadius:(CGFloat)radius {
    if (!view) return;

    ThemeManager *tm = [ThemeManager sharedManager];

    view.layer.cornerRadius = radius;
    view.layer.masksToBounds = NO;

    view.backgroundColor = [tm glassBackgroundColor];
    view.layer.borderWidth = 1.0f;
    view.layer.borderColor = [tm glassBorderColor].CGColor;

    view.layer.shadowColor = [UIColor blackColor].CGColor;
    view.layer.shadowOpacity = 0.35f;
    view.layer.shadowOffset = CGSizeMake(0, 8);
    view.layer.shadowRadius = 12.0f;
}

@end
