#import "AmbientView.h"
#import "ThemeManager.h"
#import <QuartzCore/QuartzCore.h>

@interface AmbientView ()

@property (nonatomic, strong) CAGradientLayer *backgroundGradientLayer;
@property (nonatomic, strong) CALayer *blobALayer;
@property (nonatomic, strong) CALayer *blobBLayer;
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
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
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
    UIColor *initB1 = [tm baseColor1] ?: [UIColor blackColor];
    UIColor *initB2 = [tm baseColor2] ?: [UIColor darkGrayColor];
    UIColor *initA1 = [tm accentColor1] ?: [UIColor cyanColor];
    UIColor *initA2 = [tm accentColor2] ?: [UIColor blueColor];

    self.backgroundGradientLayer.colors = @[(id)initB1.CGColor, (id)initB2.CGColor];
    [self.layer addSublayer:self.backgroundGradientLayer];

    // 2. Blob A: width 210, height 210, top: -40, right: -60, background: var(--a1), opacity: 0.75
    self.blobALayer = [CALayer layer];
    self.blobALayer.cornerRadius = 105;
    self.blobALayer.opacity = 0.75f;
    self.blobALayer.backgroundColor = initA1.CGColor;
    [self.layer addSublayer:self.blobALayer];

    // 3. Blob B: width 190, height 190, top: 260, left: -70, background: var(--a2), opacity: 0.55
    self.blobBLayer = [CALayer layer];
    self.blobBLayer.cornerRadius = 95;
    self.blobBLayer.opacity = 0.55f;
    self.blobBLayer.backgroundColor = initA2.CGColor;
    [self.layer addSublayer:self.blobBLayer];

    // 4. Liquid Glass Blur Overlay (filter: blur(38px))
    UIBlurEffect *blur = [UIBlurEffect effectWithStyle:tm.isLightMode ? UIBlurEffectStyleLight : UIBlurEffectStyleDark];
    self.diffuseBlurView = [[UIVisualEffectView alloc] initWithEffect:blur];
    self.diffuseBlurView.frame = self.bounds;
    self.diffuseBlurView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.diffuseBlurView.alpha = 0.70f;
    [self addSubview:self.diffuseBlurView];

    [self updateBlobLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.backgroundGradientLayer.frame = self.bounds;
    self.diffuseBlurView.frame = self.bounds;
    [self updateBlobLayout];
}

- (void)updateBlobLayout {
    CGFloat w = self.bounds.size.width;
    // Blob A: top -40, right -60
    self.blobALayer.frame = CGRectMake(w - 150, -40, 210, 210);
    // Blob B: top 260, left -70
    self.blobBLayer.frame = CGRectMake(-70, 260, 190, 190);
}

- (void)handleThemeChanged {
    [self applyThemeColorsAnimated:YES];
}

- (void)applyThemeColorsAnimated:(BOOL)animated {
    ThemeManager *tm = [ThemeManager sharedManager];

    UIColor *b1 = [tm baseColor1] ?: [UIColor blackColor];
    UIColor *b2 = [tm baseColor2] ?: [UIColor darkGrayColor];
    UIColor *a1 = [tm accentColor1] ?: [UIColor cyanColor];
    UIColor *a2 = [tm accentColor2] ?: [UIColor blueColor];

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
    CGColorRef newA1 = a1.CGColor;
    CGColorRef newA2 = a2.CGColor;

    if (animated) {
        CFTimeInterval duration = 1.8; // Exact transition from user CSS spec (1.8s ease)
        CAMediaTimingFunction *ease = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];

        CABasicAnimation *bgAnim = [CABasicAnimation animationWithKeyPath:@"colors"];
        bgAnim.fromValue = self.backgroundGradientLayer.colors;
        bgAnim.toValue = newBgColors;
        bgAnim.duration = duration;
        bgAnim.timingFunction = ease;
        [self.backgroundGradientLayer addAnimation:bgAnim forKey:@"bgAnim"];

        CABasicAnimation *blobAAnim = [CABasicAnimation animationWithKeyPath:@"backgroundColor"];
        blobAAnim.fromValue = (id)self.blobALayer.backgroundColor;
        blobAAnim.toValue = (__bridge id)newA1;
        blobAAnim.duration = duration;
        blobAAnim.timingFunction = ease;
        [self.blobALayer addAnimation:blobAAnim forKey:@"blobAAnim"];

        CABasicAnimation *blobBAnim = [CABasicAnimation animationWithKeyPath:@"backgroundColor"];
        blobBAnim.fromValue = (id)self.blobBLayer.backgroundColor;
        blobBAnim.toValue = (__bridge id)newA2;
        blobBAnim.duration = duration;
        blobBAnim.timingFunction = ease;
        [self.blobBLayer addAnimation:blobBAnim forKey:@"blobBAnim"];
    }

    self.backgroundGradientLayer.colors = newBgColors;
    self.blobALayer.backgroundColor = newA1;
    self.blobBLayer.backgroundColor = newA2;
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
        UIColor *derivedB1 = [UIColor colorWithRed:r1 * 0.12 green:g1 * 0.12 blue:b1 * 0.12 alpha:1.0];
        UIColor *derivedB2 = [UIColor colorWithRed:r1 * 0.18 green:g1 * 0.18 blue:b1 * 0.18 alpha:1.0];

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

    // Background fill & border
    view.backgroundColor = [tm glassBackgroundColor];
    view.layer.borderWidth = 1.0f;
    view.layer.borderColor = [tm glassBorderColor].CGColor;

    // Drop shadow: 0 8px 24px -12px rgba(0,0,0,.35)
    view.layer.shadowColor = [UIColor blackColor].CGColor;
    view.layer.shadowOpacity = 0.35f;
    view.layer.shadowOffset = CGSizeMake(0, 8);
    view.layer.shadowRadius = 12.0f;
}

@end
