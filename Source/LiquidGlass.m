// LiquidGlass.m - values copied from the HTML sheet (CSS px -> iOS pt at the call site).
// Plain Objective-C, ARC enabled, thread-safe.
#import "LiquidGlass.h"
#import <QuartzCore/QuartzCore.h>
#include <math.h>
#include <stdlib.h>

NSString *const LGPaletteDidChangeNotification = @"LGPaletteDidChangeNotification";
static const NSInteger kLGBgTag = 0x4C47, kLGGlassTag = 0x4C48;

static UIColor *LGHex(NSString *h) {
    if (!h || h.length < 2) return [UIColor clearColor];
    unsigned v = 0;
    [[NSScanner scannerWithString:[h substringFromIndex:1]] scanHexInt:&v];
    return [UIColor colorWithRed:((v >> 16) & 255) / 255.0
                           green:((v >> 8) & 255) / 255.0
                            blue:(v & 255) / 255.0
                           alpha:1.0];
}

static inline CGFloat LGClamp(CGFloat x, CGFloat lo, CGFloat hi) {
    return MAX(lo, MIN(hi, x));
}

static inline UIColor *LGHSB(CGFloat h, CGFloat s, CGFloat b) {
    return [UIColor colorWithHue:fmod(h + 1.0, 1.0)
                      saturation:LGClamp(s, 0, 1)
                      brightness:LGClamp(b, 0, 1)
                           alpha:1.0];
}

// ============================ LGPalette ============================
@implementation LGPalette

// order: b1, b2, a1, a2, tx, mu  (exactly the sheet's T[] data)
+ (NSArray *)data {
    return @[
     @{@"n":@"Aurora Teal",
       @"d":@[@"#06191c",@"#0b2e33",@"#19d3b0",@"#3a7bff",@"#eafffb",@"#8fb8b3"],
       @"l":@[@"#eefbf9",@"#d3f2ee",@"#0aa88a",@"#5b9bff",@"#08302b",@"#4f7a74"]},
     @{@"n":@"Nebula Violet",
       @"d":@[@"#110a24",@"#241346",@"#9a7bff",@"#ff5fb0",@"#f4efff",@"#a99cc8"],
       @"l":@[@"#f5f1ff",@"#e4dbff",@"#6a47ee",@"#ff7ab8",@"#241346",@"#6b5d92"]},
     @{@"n":@"Mars Rust",
       @"d":@[@"#1c0b07",@"#3a1710",@"#ff6a3d",@"#ffb347",@"#fff1ea",@"#c29a8c"],
       @"l":@[@"#fff3ec",@"#ffdccc",@"#e24a1a",@"#ff9f43",@"#3a1710",@"#92604f"]},
     @{@"n":@"Ion Blue",
       @"d":@[@"#060d1f",@"#0e1f47",@"#3d8bff",@"#29e0ff",@"#ecf3ff",@"#8fa6cf"],
       @"l":@[@"#eef4ff",@"#d3e3ff",@"#1a63e0",@"#27b9e6",@"#0e1f47",@"#566b96"]},
     @{@"n":@"Solar Amber",
       @"d":@[@"#1a1204",@"#33220a",@"#ffc21f",@"#ff6f91",@"#fff8e6",@"#c7b283"],
       @"l":@[@"#fffaea",@"#ffecb8",@"#e09a00",@"#ff7a98",@"#33220a",@"#8b7440"]}
    ];
}

+ (NSArray<NSString *> *)presetNames {
    NSMutableArray *a = [NSMutableArray array];
    for (NSDictionary *d in [self data]) {
        [a addObject:d[@"n"]];
    }
    return a;
}

+ (LGPalette *)presetNamed:(NSString *)name dark:(BOOL)dark {
    NSDictionary *hit = nil;
    for (NSDictionary *d in [self data]) {
        if ([d[@"n"] isEqualToString:name]) {
            hit = d;
            break;
        }
    }
    if (!hit) hit = [self data][0];
    NSArray *c = hit[dark ? @"d" : @"l"];
    LGPalette *p = [LGPalette new];
    p.name = hit[@"n"];
    p.b1 = LGHex(c[0]);
    p.b2 = LGHex(c[1]);
    p.a1 = LGHex(c[2]);
    p.a2 = LGHex(c[3]);
    p.tx = LGHex(c[4]);
    p.mu = LGHex(c[5]);
    return p;
}

// Ambient mode: dominant hue -> a1, a distant hue -> a2, backgrounds derived from a1's hue.
+ (LGPalette *)paletteFromArtwork:(UIImage *)image dark:(BOOL)dark {
    if (!image) return nil;
    enum { N = 24, K = 12 };
    uint8_t px[N * N * 4];
    memset(px, 0, sizeof(px));

    CGImageRef cgImage = image.CGImage;
    BOOL freeCg = NO;
    if (!cgImage) {
        UIGraphicsBeginImageContextWithOptions(CGSizeMake(N, N), NO, 1.0);
        [image drawInRect:CGRectMake(0, 0, N, N)];
        UIImage *rendered = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        cgImage = rendered.CGImage;
    }
    if (!cgImage) return nil;

    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(px, N, N, 8, N * 4, cs, kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(cs);
    if (!ctx) return nil;
    CGContextDrawImage(ctx, CGRectMake(0, 0, N, N), cgImage);
    CGContextRelease(ctx);
    if (freeCg && cgImage) CGImageRelease(cgImage);

    double wt[K] = {0}, hh[K] = {0}, ss[K] = {0};
    for (int i = 0; i < N * N; i++) {
        uint8_t a = px[i * 4 + 3];
        if (a < 200) continue;
        UIColor *c = [UIColor colorWithRed:px[i * 4] / 255.0
                                     green:px[i * 4 + 1] / 255.0
                                      blue:px[i * 4 + 2] / 255.0
                                     alpha:1.0];
        CGFloat h = 0, s = 0, b = 0;
        [c getHue:&h saturation:&s brightness:&b alpha:NULL];
        if (b < 0.15 || s < 0.15) continue; // ignore near-black / grey
        double w = s * s * b;
        int k = MAX(0, MIN(K - 1, (int)(h * K)));
        wt[k] += w;
        hh[k] += w * h;
        ss[k] += w * s;
    }

    int i1 = 0;
    for (int k = 1; k < K; k++) {
        if (wt[k] > wt[i1]) i1 = k;
    }
    if (wt[i1] < 0.5) return nil; // greyscale art: keep previous palette

    int i2 = -1;
    double best = 0;
    for (int k = 0; k < K; k++) {
        int dist = MIN(abs(k - i1), K - abs(k - i1));
        if (dist >= 2 && wt[k] > best) {
            best = wt[k];
            i2 = k;
        }
    }
    CGFloat h1 = hh[i1] / wt[i1];
    CGFloat s1 = ss[i1] / wt[i1];
    CGFloat h2 = (i2 >= 0 && best > wt[i1] * 0.15) ? (hh[i2] / wt[i2]) : (h1 + 0.08);
    CGFloat s2 = (i2 >= 0 && best > wt[i1] * 0.15) ? (ss[i2] / wt[i2]) : s1;

    LGPalette *p = [LGPalette new];
    p.name = @"Ambient";
    if (dark) {
        p.a1 = LGHSB(h1, LGClamp(s1, .55, .9), .95);
        p.a2 = LGHSB(h2, LGClamp(s2, .55, .9), .95);
        p.b1 = LGHSB(h1, LGClamp(s1, .5, .85), .09);
        p.b2 = LGHSB(h1, LGClamp(s1, .5, .80), .18);
        p.tx = LGHSB(h1, .06, .97);
        p.mu = LGHSB(h1, .20, .72);
    } else {
        p.a1 = LGHSB(h1, LGClamp(s1, .6, .9), .80);
        p.a2 = LGHSB(h2, LGClamp(s2, .5, .85), .92);
        p.b1 = LGHSB(h1, .06, .98);
        p.b2 = LGHSB(h1, .17, .92);
        p.tx = LGHSB(h1, .70, .18);
        p.mu = LGHSB(h1, .35, .42);
    }
    return p;
}
@end

// ============================ LGTheme ============================
@implementation LGTheme {
    LGPalette *_art;
}
+ (LGTheme *)shared {
    static LGTheme *t;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        t = [LGTheme new];
        [t reloadSilently];
    });
    return t;
}

- (void)reloadSilently {
    @synchronized(self) {
        NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
        _dark = [d objectForKey:@"LG_dark"] ? [d boolForKey:@"LG_dark"] : YES;
        _ambient = [d boolForKey:@"LG_ambient"];
        _staticMode = [d boolForKey:@"LG_static"] || UIAccessibilityIsReduceTransparencyEnabled();
        LGPalette *preset = [LGPalette presetNamed:([d stringForKey:@"LG_theme"] ?: @"Aurora Teal") dark:_dark];
        _palette = (_ambient && _art) ? _art : preset;
    }
}

- (void)reload {
    [self reloadSilently];
    if ([NSThread isMainThread]) {
        [NSNotificationCenter.defaultCenter postNotificationName:LGPaletteDidChangeNotification object:nil];
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{
            [NSNotificationCenter.defaultCenter postNotificationName:LGPaletteDidChangeNotification object:nil];
        });
    }
}

- (void)setArtwork:(UIImage *)image {
    if (!_ambient || !image) return;
    BOOL dark = _dark;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        LGPalette *p = [LGPalette paletteFromArtwork:image dark:dark];
        if (!p) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            @synchronized(self) {
                self->_art = p;
            }
            [self reload];
        });
    });
}
@end

// ============================ LGBackgroundView ============================
@implementation LGBackgroundView {
    CAGradientLayer *_base, *_blobA, *_blobB;
    LGPalette *_pal;
}

- (instancetype)initWithFrame:(CGRect)f {
    if ((self = [super initWithFrame:f])) {
        self.userInteractionEnabled = NO;
        self.tag = kLGBgTag;
        _darkStyle = YES;
        _base = [CAGradientLayer layer];
        _base.startPoint = CGPointMake(0.41, 0);
        _base.endPoint = CGPointMake(0.59, 1); // ~170deg
        for (int i = 0; i < 2; i++) {
            CAGradientLayer *b = [CAGradientLayer layer];
            b.type = kCAGradientLayerRadial;
            b.startPoint = CGPointMake(.5, .5);
            b.endPoint = CGPointMake(1, 1);
            if (i == 0) _blobA = b; else _blobB = b;
        }
        [self.layer addSublayer:_base];
        [self.layer addSublayer:_blobA];
        [self.layer addSublayer:_blobB];
        [NSNotificationCenter.defaultCenter addObserver:self
                                               selector:@selector(themeChanged)
                                                   name:LGPaletteDidChangeNotification
                                                 object:nil];
        [self themeChanged];
    }
    return self;
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)themeChanged {
    LGTheme *t = LGTheme.shared;
    _darkStyle = t.dark;
    _staticMode = t.staticMode;
    [self applyPalette:t.palette animated:YES];
}

- (NSArray *)blobColors:(UIColor *)c {
    if (!c) c = [UIColor clearColor];
    return @[
        (id)c.CGColor,
        (id)c.CGColor,
        (id)[c colorWithAlphaComponent:.5].CGColor,
        (id)[c colorWithAlphaComponent:0].CGColor
    ];
}

- (void)applyPalette:(LGPalette *)p animated:(BOOL)animated {
    if (!p) return;
    _pal = p;
    if (UIAccessibilityIsReduceMotionEnabled()) animated = NO;

    // sheet: .blob opacity .75 / .55 (dark), .5 (light)
    _blobA.opacity = _darkStyle ? .75 : .5;
    _blobB.opacity = .5 + (_darkStyle ? .05 : 0);
    _blobA.hidden = _blobB.hidden = _staticMode;

    NSArray *baseC = _staticMode ? @[(id)p.b1.CGColor, (id)p.b1.CGColor] : @[(id)p.b1.CGColor, (id)p.b2.CGColor];
    NSArray *aC = [self blobColors:p.a1], *bC = [self blobColors:p.a2];

    void (^set)(CAGradientLayer *, NSArray *) = ^(CAGradientLayer *l, NSArray *c) {
        if (animated) {
            CABasicAnimation *an = [CABasicAnimation animationWithKeyPath:@"colors"];
            an.fromValue = ((CAGradientLayer *)(l.presentationLayer ?: l)).colors;
            an.toValue = c;
            an.duration = 1.8; // sheet: transition 1.8s ease
            an.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
            [l addAnimation:an forKey:@"lgcolors"];
        }
        l.colors = c;
    };
    set(_base, baseC);
    set(_blobA, aC);
    set(_blobB, bC);
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat W = self.bounds.size.width, H = self.bounds.size.height;
    if (W <= 0 || H <= 0) return;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _base.frame = self.bounds;
    // Sheet geometry in fractions of the 278x588 phone: A r=.377W c=(.838W,.11H); B r=.342W c=(.09W,.604H)
    CAGradientLayer *layers[2] = { _blobA, _blobB };
    CGFloat R[2]  = { .377 * W, .342 * W };
    CGFloat CX[2] = { .838 * W, .090 * W };
    CGFloat CY[2] = { .110 * H, .604 * H };
    for (int i = 0; i < 2; i++) {
        CGFloat ext = R[i] + 46; // r + ~1.2 x blur(38)
        layers[i].frame = CGRectMake(CX[i] - ext, CY[i] - ext, ext * 2, ext * 2);
        layers[i].locations = @[@0, @(MAX(.1, (R[i] - 30) / ext)), @(R[i] / ext), @1];
    }
    [CATransaction commit];
}
@end

// ============================ LGGlassView ============================
@implementation LGGlassView {
    UIView *_clip, *_tint;
    UIVisualEffectView *_blur;
    CALayer *_hl;
}

- (instancetype)initWithRadius:(CGFloat)radius dark:(BOOL)dark {
    if ((self = [super initWithFrame:CGRectZero])) {
        _radius = radius;
        _darkStyle = dark;
        self.tag = kLGGlassTag;
        self.userInteractionEnabled = NO;

        _clip = [UIView new];
        _clip.clipsToBounds = YES;
        _clip.layer.borderWidth = 1;

        _blur = [UIVisualEffectView new];
        _tint = [UIView new];
        _hl = [CALayer layer];

        [_clip addSubview:_blur];
        [_clip addSubview:_tint];
        [_clip.layer addSublayer:_hl];
        [self addSubview:_clip];

        self.layer.shadowOffset = CGSizeMake(0, 8);
        self.layer.shadowRadius = 12; // 0 8px 24px -12px

        [NSNotificationCenter.defaultCenter addObserver:self
                                               selector:@selector(themeChanged)
                                                   name:LGPaletteDidChangeNotification
                                                 object:nil];
        [self refresh];
    }
    return self;
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)themeChanged {
    LGTheme *t = LGTheme.shared;
    _darkStyle = t.dark;
    _staticMode = t.staticMode;
    _staticFill = t.palette.b2;
    [self refresh];
}

- (void)setRadius:(CGFloat)r {
    _radius = r;
    [self setNeedsLayout];
}

- (void)refresh {
    // sheet: dark fill .09 / border .2 / highlight .28 ; light .55 / .8 / .95 (TUNE)
    CGFloat fill = _darkStyle ? .09 : .55;
    CGFloat border = _darkStyle ? .2 : .8;
    CGFloat hl = _darkStyle ? .28 : .95;

    if (_staticMode) {
        _blur.effect = nil;
        _blur.hidden = YES;
        _tint.backgroundColor = _staticFill ?: [UIColor colorWithWhite:.12 alpha:1];
        _clip.layer.borderColor = [UIColor colorWithWhite:.5 alpha:.35].CGColor;
        _hl.hidden = YES;
        self.layer.shadowOpacity = 0;
    } else {
        _blur.hidden = NO;
        _blur.effect = [UIBlurEffect effectWithStyle:_darkStyle ? UIBlurEffectStyleSystemUltraThinMaterialDark
                                                               : UIBlurEffectStyleSystemUltraThinMaterialLight];
        _tint.backgroundColor = [UIColor colorWithWhite:1 alpha:fill];
        _clip.layer.borderColor = [UIColor colorWithWhite:1 alpha:border].CGColor;
        _hl.backgroundColor = [UIColor colorWithWhite:1 alpha:hl].CGColor;
        _hl.hidden = NO;
        self.layer.shadowColor = UIColor.blackColor.CGColor;
        self.layer.shadowOpacity = .35;
    }
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect b = self.bounds;
    if (b.size.width <= 0 || b.size.height <= 0) return;

    _clip.frame = b;
    _blur.frame = b;
    _tint.frame = b;
    _clip.layer.cornerRadius = MIN(_radius, MIN(b.size.width, b.size.height) / 2);
    CGFloat r = _clip.layer.cornerRadius;
    _hl.frame = CGRectMake(r * .6, 0, MAX(0, b.size.width - r * 1.2), 1);

    CGRect sp = CGRectInset(b, 12, 12);
    if (sp.size.width > 0 && sp.size.height > 0) {
        self.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:sp cornerRadius:MAX(0, r - 12)].CGPath;
    } else {
        self.layer.shadowPath = nil;
    }
}
@end

// ============================ helpers ============================
LGBackgroundView *LGInstallBackground(UIView *host) {
    if (!host) return nil;
    UIView *old = [host viewWithTag:kLGBgTag];
    if ([old isKindOfClass:LGBackgroundView.class]) return (LGBackgroundView *)old;
    LGBackgroundView *bg = [[LGBackgroundView alloc] initWithFrame:host.bounds];
    bg.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [host insertSubview:bg atIndex:0];
    return bg;
}

LGGlassView *LGAttachGlass(UIView *host, CGFloat radius) {
    if (!host) return nil;
    UIView *old = [host viewWithTag:kLGGlassTag];
    if ([old isKindOfClass:LGGlassView.class]) {
        ((LGGlassView *)old).radius = radius;
        return (LGGlassView *)old;
    }
    host.backgroundColor = UIColor.clearColor;
    LGGlassView *g = [[LGGlassView alloc] initWithRadius:radius dark:LGTheme.shared.dark];
    g.frame = host.bounds;
    g.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [host insertSubview:g atIndex:0];
    [g themeChanged];
    return g;
}
