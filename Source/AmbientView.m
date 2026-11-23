#import "AmbientView.h"
#import "ThemeManager.h"
#import <QuartzCore/QuartzCore.h>

static NSString * const kAmbientPrefsKey = @"YTMAppleStyleEnhancer_AmbientPrefs";
static NSString * const kAmbientEnabledKey = @"ambientGlowEnabled";
static NSString * const kAmbientIntensityKey = @"glowIntensity";

@interface AmbientView ()

@property (nonatomic, strong) CAGradientLayer *primaryGlowLayer;
@property (nonatomic, strong) CAGradientLayer *secondaryGlowLayer;
@property (nonatomic, strong) UIVisualEffectView *blurView;
@property (nonatomic, strong) UIView *blackBaseView;
@property (nonatomic, strong) UIColor *currentDominantColor;
@property (nonatomic, strong) UIColor *currentSecondaryColor;

@end

@implementation AmbientView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self loadPreferences];
        [self setupViewHierarchy];
    }
    return self;
}

- (void)loadPreferences {
    NSDictionary *prefs = [[NSUserDefaults standardUserDefaults] dictionaryForKey:kAmbientPrefsKey];
    if (prefs) {
        self.glowEnabled = prefs[kAmbientEnabledKey] ? [prefs[kAmbientEnabledKey] boolValue] : YES;
        self.glowIntensity = prefs[kAmbientIntensityKey] ? [prefs[kAmbientIntensityKey] floatValue] : 0.65f;
    } else {
        self.glowEnabled = YES;
        self.glowIntensity = 0.65f;
        [self savePreferences];
    }
}

- (void)savePreferences {
    NSMutableDictionary *prefs = [NSMutableDictionary dictionary];
    prefs[kAmbientEnabledKey] = @(self.glowEnabled);
    prefs[kAmbientIntensityKey] = @(self.glowIntensity);
    [[NSUserDefaults standardUserDefaults] setObject:prefs forKey:kAmbientPrefsKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)setGlowEnabled:(BOOL)glowEnabled {
    _glowEnabled = glowEnabled;
    self.hidden = !glowEnabled;
    [self savePreferences];
}

- (void)setGlowIntensity:(CGFloat)glowIntensity {
    _glowIntensity = MAX(0.1f, MIN(1.0f, glowIntensity));
    [self updateGlowLayersAnimated:NO];
    [self savePreferences];
}

- (void)setupViewHierarchy {
    self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.clipsToBounds = YES;
    self.userInteractionEnabled = NO;

    // Pitch-black base layer matching OLED `#000000`
    self.blackBaseView = [[UIView alloc] initWithFrame:self.bounds];
    self.blackBaseView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.blackBaseView.backgroundColor = [[ThemeManager sharedManager] oledBackgroundColor];
    [self addSubview:self.blackBaseView];

    // Primary ambient glow gradient
    self.primaryGlowLayer = [CAGradientLayer layer];
    self.primaryGlowLayer.frame = self.bounds;
    self.primaryGlowLayer.type = kCAGradientLayerRadial;
    self.primaryGlowLayer.startPoint = CGPointMake(0.5, 0.35);
    self.primaryGlowLayer.endPoint = CGPointMake(1.2, 1.2);
    [self.layer addSublayer:self.primaryGlowLayer];

    // Secondary ambient accent glow layer
    self.secondaryGlowLayer = [CAGradientLayer layer];
    self.secondaryGlowLayer.frame = self.bounds;
    self.secondaryGlowLayer.type = kCAGradientLayerRadial;
    self.secondaryGlowLayer.startPoint = CGPointMake(0.65, 0.6);
    self.secondaryGlowLayer.endPoint = CGPointMake(1.4, 1.4);
    [self.layer addSublayer:self.secondaryGlowLayer];

    // Soft Gaussian blur overlay for liquid light diffusion
    UIBlurEffect *blurEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleDark];
    self.blurView = [[UIVisualEffectView alloc] initWithEffect:blurEffect];
    self.blurView.frame = self.bounds;
    self.blurView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.blurView.alpha = 0.55f;
    [self addSubview:self.blurView];

    // Initial default soft colors
    self.currentDominantColor = [UIColor colorWithRed:0.12f green:0.12f blue:0.18f alpha:1.0f];
    self.currentSecondaryColor = [UIColor colorWithRed:0.08f green:0.08f blue:0.14f alpha:1.0f];
    [self updateGlowLayersAnimated:NO];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.primaryGlowLayer.frame = self.bounds;
    self.secondaryGlowLayer.frame = self.bounds;
    self.blackBaseView.frame = self.bounds;
    self.blurView.frame = self.bounds;
}

- (void)applyThemeUpdates {
    self.blackBaseView.backgroundColor = [[ThemeManager sharedManager] oledBackgroundColor];
}

#pragma mark - Artwork Color Analysis

- (void)updateWithArtworkImage:(nullable UIImage *)image animated:(BOOL)animated {
    if (!self.glowEnabled) return;

    if (!image) {
        self.currentDominantColor = [UIColor colorWithRed:0.05f green:0.05f blue:0.08f alpha:1.0f];
        self.currentSecondaryColor = [UIColor blackColor];
        [self updateGlowLayersAnimated:animated];
        return;
    }

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSArray<UIColor *> *extractedColors = [self extractDominantColorsFromImage:image];
        UIColor *dominant = extractedColors.firstObject;
        UIColor *secondary = (extractedColors.count > 1) ? extractedColors[1] : [dominant colorWithAlphaComponent:0.7f];

        dispatch_async(dispatch_get_main_queue(), ^{
            self.currentDominantColor = dominant;
            self.currentSecondaryColor = secondary;
            [self updateGlowLayersAnimated:animated];
        });
    });
}

- (void)updateGlowLayersAnimated:(BOOL)animated {
    if (!self.currentDominantColor) return;

    CGFloat intensity = self.glowIntensity;
    UIColor *topColor = [self.currentDominantColor colorWithAlphaComponent:0.75f * intensity];
    UIColor *midColor = [self.currentDominantColor colorWithAlphaComponent:0.35f * intensity];
    UIColor *clearColor = [UIColor colorWithRed:0 green:0 blue:0 alpha:0.0f];

    NSArray *primaryColors = @[(id)topColor.CGColor, (id)midColor.CGColor, (id)clearColor.CGColor];

    UIColor *secTop = [self.currentSecondaryColor colorWithAlphaComponent:0.60f * intensity];
    UIColor *secMid = [self.currentSecondaryColor colorWithAlphaComponent:0.25f * intensity];
    NSArray *secondaryColors = @[(id)secTop.CGColor, (id)secMid.CGColor, (id)clearColor.CGColor];

    if (animated) {
        CABasicAnimation *animPrimary = [CABasicAnimation animationWithKeyPath:@"colors"];
        animPrimary.fromValue = self.primaryGlowLayer.colors;
        animPrimary.toValue = primaryColors;
        animPrimary.duration = 1.2;
        animPrimary.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
        [self.primaryGlowLayer addAnimation:animPrimary forKey:@"colorsChange"];

        CABasicAnimation *animSecondary = [CABasicAnimation animationWithKeyPath:@"colors"];
        animSecondary.fromValue = self.secondaryGlowLayer.colors;
        animSecondary.toValue = secondaryColors;
        animSecondary.duration = 1.2;
        animSecondary.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
        [self.secondaryGlowLayer addAnimation:animSecondary forKey:@"colorsChange"];
    }

    self.primaryGlowLayer.colors = primaryColors;
    self.secondaryGlowLayer.colors = secondaryColors;
}

- (NSArray<UIColor *> *)extractDominantColorsFromImage:(UIImage *)image {
    // Downscale image to a tiny 20x20 pixel matrix to extract dominant colors fast without CPU spikes
    CGSize thumbSize = CGSizeMake(20, 20);
    UIGraphicsBeginImageContextWithOptions(thumbSize, NO, 1.0f);
    [image drawInRect:CGRectMake(0, 0, thumbSize.width, thumbSize.height)];
    UIImage *thumbnail = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();

    CGImageRef cgImage = thumbnail.CGImage;
    if (!cgImage) {
        return @[[UIColor colorWithWhite:0.2f alpha:1.0f], [UIColor blackColor]];
    }

    size_t width = CGImageGetWidth(cgImage);
    size_t height = CGImageGetHeight(cgImage);
    size_t bytesPerPixel = 4;
    size_t bytesPerRow = bytesPerPixel * width;
    size_t bitsPerComponent = 8;

    uint8_t *rawData = (uint8_t *)calloc(height * bytesPerRow, sizeof(uint8_t));
    if (!rawData) {
        return @[[UIColor colorWithWhite:0.2f alpha:1.0f], [UIColor blackColor]];
    }

    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(rawData, width, height,
                                                 bitsPerComponent, bytesPerRow, colorSpace,
                                                 kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(colorSpace);

    if (!context) {
        free(rawData);
        return @[[UIColor colorWithWhite:0.2f alpha:1.0f], [UIColor blackColor]];
    }

    CGContextDrawImage(context, CGRectMake(0, 0, width, height), cgImage);
    CGContextRelease(context);

    // Track vibrant candidates
    CGFloat bestScore1 = -1.0f;
    UIColor *bestColor1 = nil;
    CGFloat bestScore2 = -1.0f;
    UIColor *bestColor2 = nil;

    for (size_t y = 0; y < height; y++) {
        for (size_t x = 0; x < width; x++) {
            size_t byteIndex = (bytesPerRow * y) + (x * bytesPerPixel);
            CGFloat r = rawData[byteIndex] / 255.0f;
            CGFloat g = rawData[byteIndex + 1] / 255.0f;
            CGFloat b = rawData[byteIndex + 2] / 255.0f;

            UIColor *sample = [UIColor colorWithRed:r green:g blue:b alpha:1.0f];
            CGFloat h, s, v, a;
            [sample getHue:&h saturation:&s brightness:&v alpha:&a];

            // Filter out near-pure-black or near-white or muddy neutral gray
            if (v < 0.18f || v > 0.95f || s < 0.25f) continue;

            // Score based on saturation and vibrancy
            CGFloat score = (s * 0.65f) + (v * 0.35f);
            if (score > bestScore1) {
                bestScore2 = bestScore1;
                bestColor2 = bestColor1;
                bestScore1 = score;
                bestColor1 = sample;
            } else if (score > bestScore2) {
                bestScore2 = score;
                bestColor2 = sample;
            }
        }
    }

    free(rawData);

    if (!bestColor1) {
        bestColor1 = [UIColor colorWithRed:0.2f green:0.25f blue:0.35f alpha:1.0f];
    }
    if (!bestColor2) {
        bestColor2 = [bestColor1 colorWithAlphaComponent:0.75f];
    }

    return @[bestColor1, bestColor2];
}

@end
