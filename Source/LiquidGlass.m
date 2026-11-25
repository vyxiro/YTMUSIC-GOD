// LiquidGlass.m  v2.1  - Merged with ARC/thread-safety/nil-guards + Step 1 ambient diagnostics.
#import "LiquidGlass.h"
#import <MediaPlayer/MediaPlayer.h>
#import <QuartzCore/QuartzCore.h>
#import <CoreImage/CoreImage.h>
#include <math.h>
#include <stdlib.h>

NSString *const LGPaletteDidChangeNotification = @"LGPaletteDidChangeNotification";
static const NSInteger kLGBgTag = 0x4C47, kLGGlassTag = 0x4C48;

#pragma mark - colour helpers
static UIColor *LGHex(NSString *h) {
    if (![h isKindOfClass:NSString.class] || h.length < 2) return [UIColor clearColor];
    unsigned v = 0; [[NSScanner scannerWithString:[h substringFromIndex:1]] scanHexInt:&v];
    return [UIColor colorWithRed:((v >> 16) & 255) / 255.0 green:((v >> 8) & 255) / 255.0 blue:(v & 255) / 255.0 alpha:1];
}
static inline CGFloat LGClamp(CGFloat x, CGFloat lo, CGFloat hi) { return MAX(lo, MIN(hi, x)); }
static UIColor *LGHSB(CGFloat h, CGFloat s, CGFloat b) {
    h = h - floor(h);
    return [UIColor colorWithHue:h saturation:LGClamp(s, 0, 1) brightness:LGClamp(b, 0, 1) alpha:1];
}
static CGFloat LGLin(CGFloat c) { return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4); }
static CGFloat LGLum(UIColor *c) {
    CGFloat r = 0, g = 0, b = 0; [c getRed:&r green:&g blue:&b alpha:NULL];
    return .2126 * LGLin(r) + .7152 * LGLin(g) + .0722 * LGLin(b);
}
static CGFloat LGContrast(UIColor *a, UIColor *b) {
    CGFloat la = LGLum(a), lb = LGLum(b); if (la < lb) { CGFloat t = la; la = lb; lb = t; }
    return (la + .05) / (lb + .05);
}
static UIColor *LGMix(UIColor *a, UIColor *b, CGFloat t) {
    CGFloat ar, ag, ab, br, bg, bb; [a getRed:&ar green:&ag blue:&ab alpha:NULL]; [b getRed:&br green:&bg blue:&bb alpha:NULL];
    return [UIColor colorWithRed:ar + (br - ar) * t green:ag + (bg - ag) * t blue:ab + (bb - ab) * t alpha:1];
}
// Keep accents readable on the background (WCAG-style ratio) without changing hue.
static UIColor *LGFixAccent(CGFloat h, CGFloat s, CGFloat v, UIColor *bg, CGFloat target, BOOL dark) {
    for (int i = 0; i < 24; i++) {
        UIColor *c = LGHSB(h, s, v);
        if (LGContrast(c, bg) >= target) return c;
        if (dark) { if (s > .3) s -= .05; else v = MIN(1, v + .02); }
        else { v -= .03; if (v < .3) break; }
    }
    return LGHSB(h, s, v);
}
// Second accent when the art has only one strong hue: ~25 deg away, never muddy yellow-green.
static CGFloat LGAnalog(CGFloat h1) {
    CGFloat h2 = fmod(h1 + .07, 1.0);
    if (h2 >= .17 && h2 <= .45 && !(h1 >= .17 && h1 <= .45)) h2 = fmod(h1 - .07 + 1.0, 1.0);
    return h2;
}

static NSUInteger sHookFires = 0, sArtIngests = 0;
static NSString *LGHexString(UIColor *c) {
    if (!c) return @"#nil";
    CGFloat r = 0, g = 0, b = 0;
    if ([c getRed:&r green:&g blue:&b alpha:NULL]) {
        return [NSString stringWithFormat:@"#%02X%02X%02X", (int)round(r * 255), (int)round(g * 255), (int)round(b * 255)];
    }
    return @"#nonRGB";
}

#pragma mark - image helpers
static BOOL LGDrawSmall(UIImage *img, int N, uint8_t *buf) {
    if (!img) return NO;
    CGImageRef cg = img.CGImage;
    UIImage *rendered = nil;
    if (!cg) {
        UIGraphicsImageRendererFormat *fmt = [UIGraphicsImageRendererFormat defaultFormat];
        fmt.scale = 1.0;
        rendered = [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(N, N) format:fmt] imageWithActions:^(__unused UIGraphicsImageRendererContext *ctx) {
            [img drawInRect:CGRectMake(0, 0, N, N)];
        }];
        cg = rendered.CGImage;
    }
    if (!cg) return NO;
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(buf, N, N, 8, N * 4, cs, kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(cs); if (!ctx) return NO;
    CGContextSetInterpolationQuality(ctx, kCGInterpolationMedium);
    CGContextDrawImage(ctx, CGRectMake(0, 0, N, N), cg);
    CGContextRelease(ctx); return YES;
}
static NSString *LGSignature(UIImage *img) {          // cheap content hash: placeholder vs real art
    uint8_t px[4 * 4 * 4] = {0}; if (!LGDrawSmall(img, 4, px)) return @"0";
    uint32_t h = 2166136261u; for (int i = 0; i < 64; i++) { h ^= px[i]; h *= 16777619u; }
    return [NSString stringWithFormat:@"%08x", h];
}
static BOOL LGImageIsBlack(UIImage *img) {
    uint8_t px[8 * 8 * 4] = {0}; if (!LGDrawSmall(img, 8, px)) return YES;
    double s = 0; for (int i = 0; i < 64; i++) s += MAX(px[i*4], MAX(px[i*4+1], px[i*4+2])) / 255.0;
    return (s / 64.0) < 0.03;
}
static UIImage *LGMakeBlurredArtwork(UIImage *img, BOOL dark) {
    if (!img) return nil;
    CGFloat side = 160.0;
    UIGraphicsImageRendererFormat *fmt = [UIGraphicsImageRendererFormat defaultFormat];
    fmt.scale = 1.0;
    UIImage *small = [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(side, side) format:fmt] imageWithActions:^(__unused UIGraphicsImageRendererContext *ctx) {
        [img drawInRect:CGRectMake(0, 0, side, side)];
    }];
    if (!small.CGImage) return img;

    static CIContext *sCtx = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ sCtx = [CIContext contextWithOptions:@{kCIContextUseSoftwareRenderer: @NO}]; });

    CIImage *ci = [CIImage imageWithCGImage:small.CGImage];
    CGRect extent = ci.extent;

    CIFilter *clamp = [CIFilter filterWithName:@"CIAffineClamp"];
    [clamp setValue:ci forKey:kCIInputImageKey];
    [clamp setValue:[NSValue valueWithCGAffineTransform:CGAffineTransformIdentity] forKey:kCIInputTransformKey];
    CIImage *clamped = clamp.outputImage ?: ci;

    CIFilter *blur = [CIFilter filterWithName:@"CIGaussianBlur"];
    [blur setValue:clamped forKey:kCIInputImageKey];
    [blur setValue:@(16.0) forKey:kCIInputRadiusKey];
    CIImage *blurred = blur.outputImage ?: clamped;

    CIFilter *color = [CIFilter filterWithName:@"CIColorControls"];
    [color setValue:blurred forKey:kCIInputImageKey];
    [color setValue:@(1.30) forKey:kCIInputSaturationKey];
    [color setValue:@(dark ? -0.05 : 0.06) forKey:kCIInputBrightnessKey];
    [color setValue:@(1.06) forKey:kCIInputContrastKey];
    CIImage *outCI = [color.outputImage imageByCroppingToRect:extent];
    if (!outCI) return small;

    CGImageRef cg = [sCtx createCGImage:outCI fromRect:extent];
    if (!cg) return small;
    UIImage *res = [UIImage imageWithCGImage:cg];
    CGImageRelease(cg);
    return res;
}

#pragma mark - LGPalette
struct LGHist { double w[36], ws[36], wv[36], wc[36], wsn[36]; };
static void LGPeak(const struct LGHist *H, int p, CGFloat *h, CGFloat *s, CGFloat *v) {
    double W = 0, S = 0, V = 0, C = 0, SN = 0;
    for (int d = -1; d <= 1; d++) { int k = (p + d + 36) % 36; W += H->w[k]; S += H->ws[k]; V += H->wv[k]; C += H->wc[k]; SN += H->wsn[k]; }
    if (W <= 0) { *h = 0; *s = .7; *v = .9; return; }
    double hh = atan2(SN, C) / (2 * M_PI); if (hh < 0) hh += 1;
    *h = hh; *s = S / W; *v = V / W;
}
static LGPalette *LGBuild(CGFloat h1, CGFloat s1, CGFloat v1, CGFloat h2, CGFloat s2, CGFloat v2, BOOL dark) {
    LGPalette *p = [LGPalette new]; p.name = @"Ambient";
    if (dark) {   // proportions taken from the sheet's dark presets
        CGFloat bgs = LGClamp(s1 * .95, .5, .85);
        p.b1 = LGHSB(h1, bgs, .105); p.b2 = LGHSB(h1, bgs * .97, .20);
        p.a1 = LGFixAccent(h1, LGClamp(s1 * 1.12, .55, .95), LGClamp(v1 + .12, .90, 1.0), p.b1, 4.5, YES);
        p.a2 = LGFixAccent(h2, LGClamp(s2 * 1.10, .50, .92), LGClamp(v2 + .12, .90, 1.0), p.b1, 3.0, YES);
        p.tx = LGHSB(h1, .08, 1.0); p.mu = LGHSB(h1, .22, .72);
    } else {
        p.b1 = LGHSB(h1, .05, .98); p.b2 = LGHSB(h1, .14, .95);
        p.a1 = LGFixAccent(h1, LGClamp(s1, .6, .95), LGClamp(v1, .62, .80), p.b1, 3.0, NO);
        p.a2 = LGHSB(h2, LGClamp(s2, .45, .8), LGClamp(v2, .85, 1.0));
        p.tx = LGHSB(h1, .80, .19); p.mu = LGHSB(h1, .35, .48);
    }
    p.onAccent = LGContrast(UIColor.whiteColor, p.a1) >= 3.0 ? UIColor.whiteColor : LGHSB(h1, .8, .12);
    return p;
}
static LGPalette *LGNeutral(CGFloat h, BOOL dark) {   // black&white / greyscale covers
    LGPalette *p = [LGPalette new]; p.name = @"Ambient";
    if (dark) { p.a1 = LGHSB(h, .08, .90); p.a2 = LGHSB(h, .10, .72); p.b1 = LGHSB(h, .20, .09); p.b2 = LGHSB(h, .18, .18); p.tx = LGHSB(h, .04, 1); p.mu = LGHSB(h, .10, .72); }
    else      { p.a1 = LGHSB(h, .10, .38); p.a2 = LGHSB(h, .10, .55); p.b1 = LGHSB(h, .03, .98); p.b2 = LGHSB(h, .06, .93); p.tx = LGHSB(h, .30, .15); p.mu = LGHSB(h, .15, .42); }
    p.onAccent = LGContrast(UIColor.whiteColor, p.a1) >= 3.0 ? UIColor.whiteColor : p.b1;
    return p;
}

@implementation LGPalette
+ (NSArray *)liquidData {   // b1, b2, a1, a2, tx, mu : copied from the sheet
    return @[
     @{@"n":@"Aurora Teal",   @"d":@[@"#06191c",@"#0b2e33",@"#19d3b0",@"#3a7bff",@"#eafffb",@"#8fb8b3"], @"l":@[@"#eefbf9",@"#d3f2ee",@"#0aa88a",@"#5b9bff",@"#08302b",@"#4f7a74"]},
     @{@"n":@"Nebula Violet", @"d":@[@"#110a24",@"#241346",@"#9a7bff",@"#ff5fb0",@"#f4efff",@"#a99cc8"], @"l":@[@"#f5f1ff",@"#e4dbff",@"#6a47ee",@"#ff7ab8",@"#241346",@"#6b5d92"]},
     @{@"n":@"Mars Rust",     @"d":@[@"#1c0b07",@"#3a1710",@"#ff6a3d",@"#ffb347",@"#fff1ea",@"#c29a8c"], @"l":@[@"#fff3ec",@"#ffdccc",@"#e24a1a",@"#ff9f43",@"#3a1710",@"#92604f"]},
     @{@"n":@"Ion Blue",      @"d":@[@"#060d1f",@"#0e1f47",@"#3d8bff",@"#29e0ff",@"#ecf3ff",@"#8fa6cf"], @"l":@[@"#eef4ff",@"#d3e3ff",@"#1a63e0",@"#27b9e6",@"#0e1f47",@"#566b96"]},
     @{@"n":@"Solar Amber",   @"d":@[@"#1a1204",@"#33220a",@"#ffc21f",@"#ff6f91",@"#fff8e6",@"#c7b283"], @"l":@[@"#fffaea",@"#ffecb8",@"#e09a00",@"#ff7a98",@"#33220a",@"#8b7440"]}];
}
+ (NSArray *)staticData {   // name, accent, dark bg, light bg : the sheet's P[] array
    return @[@[@"Cherry Red",@"#FF0000",@"#121212",@"#FFF7F2"], @[@"Midnight Blue",@"#3B5BFF",@"#0B1230",@"#E9F1FF"],
             @[@"Matcha Green",@"#00C853",@"#0D2E1E",@"#FFF9E6"], @[@"Lavender Haze",@"#8A2BE2",@"#1A0B28",@"#F3E9FF"],
             @[@"Amber Glow",@"#FF8C00",@"#2A1A0F",@"#FDEBD7"]];
}
+ (NSArray<NSString *> *)presetNames { NSMutableArray *a = [NSMutableArray array]; for (NSDictionary *d in [self liquidData]) [a addObject:d[@"n"]]; return a; }
+ (NSArray<NSString *> *)staticNames { NSMutableArray *a = [NSMutableArray array]; for (NSArray *d in [self staticData]) [a addObject:d[0]]; return a; }
+ (LGPalette *)presetNamed:(NSString *)name dark:(BOOL)dark {
    NSDictionary *hit = nil; for (NSDictionary *d in [self liquidData]) if ([d[@"n"] isEqualToString:name]) { hit = d; break; }
    if (!hit) hit = [self liquidData][0];
    NSArray *c = hit[dark ? @"d" : @"l"]; LGPalette *p = [LGPalette new]; p.name = hit[@"n"];
    p.b1 = LGHex(c[0]); p.b2 = LGHex(c[1]); p.a1 = LGHex(c[2]); p.a2 = LGHex(c[3]); p.tx = LGHex(c[4]); p.mu = LGHex(c[5]);
    p.onAccent = LGContrast(UIColor.whiteColor, p.a1) >= 3.0 ? UIColor.whiteColor : p.b1;   // sheet uses white; amber needs dark
    return p;
}
+ (LGPalette *)staticNamed:(NSString *)name dark:(BOOL)dark {
    NSArray *hit = nil; for (NSArray *d in [self staticData]) if ([d[0] isEqualToString:name]) { hit = d; break; }
    if (!hit) hit = [self staticData][0];
    LGPalette *p = [LGPalette new]; p.name = hit[0];
    p.a1 = p.a2 = LGHex(hit[1]); p.b1 = LGHex(dark ? hit[2] : hit[3]);
    p.b2 = LGMix(p.b1, dark ? UIColor.whiteColor : UIColor.blackColor, dark ? .07 : .05);
    p.tx = dark ? LGHex(@"#f6f6f8") : LGHex(@"#17171b"); p.mu = dark ? LGHex(@"#c2c2ca") : LGHex(@"#5f5f6a");
    p.onAccent = LGContrast(UIColor.whiteColor, p.a1) >= 3.0 ? UIColor.whiteColor : p.b1;
    return p;
}
// Any colour: 36-bin hue histogram, weighted by chroma, smoothed; two peaks; neutral fallback for B&W art.
+ (LGPalette *)paletteFromImage:(UIImage *)image dark:(BOOL)dark {
    enum { N = 32 }; uint8_t px[N * N * 4];
    if (!LGDrawSmall(image, N, px)) return nil;
    struct LGHist H; memset(&H, 0, sizeof H);
    int valid = 0, colourful = 0; double sr = 0, sg = 0, sb = 0;
    for (int i = 0; i < N * N; i++) {
        double a = px[i*4+3]; if (a < 200) continue;
        double r = MIN(1.0, px[i*4] / a), g = MIN(1.0, px[i*4+1] / a), b = MIN(1.0, px[i*4+2] / a);
        valid++; sr += r; sg += g; sb += b;
        CGFloat h = 0, s = 0, v = 0;
        [[UIColor colorWithRed:r green:g blue:b alpha:1] getHue:&h saturation:&s brightness:&v alpha:NULL];
        if (v < .12 || s < .18) continue;                       // letterbox black / grey
        colourful++;
        double wt = pow(s, 1.5) * (.35 + .65 * v); int k = MAX(0, MIN(35, (int)(h * 36)));
        H.w[k] += wt; H.ws[k] += wt * s; H.wv[k] += wt * v; H.wc[k] += wt * cos(2 * M_PI * h); H.wsn[k] += wt * sin(2 * M_PI * h);
    }
    if (valid < 64) return nil;
    if (colourful < valid * .05) {
        CGFloat h0 = 0, s0 = 0; [[UIColor colorWithRed:sr / valid green:sg / valid blue:sb / valid alpha:1] getHue:&h0 saturation:&s0 brightness:NULL alpha:NULL];
        return LGNeutral(s0 > .05 ? h0 : .60, dark);
    }
    double sm[36]; int p1 = 0;
    for (int k = 0; k < 36; k++) { sm[k] = H.w[k] + .5 * (H.w[(k + 35) % 36] + H.w[(k + 1) % 36]); if (sm[k] > sm[p1]) p1 = k; }
    CGFloat h1, s1, v1, h2, s2, v2; LGPeak(&H, p1, &h1, &s1, &v1);
    int p2 = -1; double best = -1;
    for (int k = 0; k < 36; k++) {
        int d = MIN((k - p1 + 36) % 36, (p1 - k + 36) % 36);
        if (d >= 4 && d <= 7 && sm[k] >= .40 * sm[p1] && sm[k] > best) { best = sm[k]; p2 = k; }
    }
    if (p2 >= 0) LGPeak(&H, p2, &h2, &s2, &v2); else { h2 = LGAnalog(h1); s2 = s1; v2 = v1; }
    if (p2 >= 0 && h2 >= .17 && h2 <= .45 && !(h1 >= .17 && h1 <= .45)) { h2 = LGAnalog(h1); s2 = s1; v2 = v1; }
    return LGBuild(h1, s1, v1, h2, s2, v2, dark);
}
@end

#pragma mark - LGTheme
@implementation LGTheme {
    LGPalette *_art; UIImage *_lastImage, *_blurredArt; NSString *_lastKey; BOOL _artDark;
    NSDate *_lastVideoApply; int _blackStreak; BOOL _videoUnsupported; NSString *_lastTrack;
}
+ (LGTheme *)shared { static LGTheme *t; static dispatch_once_t o; dispatch_once(&o, ^{ t = [LGTheme new]; [t reloadSilently]; }); return t; }
- (UIImage *)blurredArtwork {
    @synchronized(self) { return _blurredArt; }
}
- (void)reloadSilently {
    @synchronized(self) {
        NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
        _dark = [d objectForKey:@"LG_dark"] ? [d boolForKey:@"LG_dark"] : YES;
        NSString *styleStr = [d stringForKey:@"LG_style"];
        BOOL styleStatic = styleStr ? [styleStr isEqualToString:@"static"] : [d boolForKey:@"LG_static"];
        _staticMode = styleStatic || UIAccessibilityIsReduceTransparencyEnabled();
        _ambient = [d boolForKey:@"LG_ambient"];
        _fadeDuration = LGClamp([d objectForKey:@"LG_fade"] ? [d doubleForKey:@"LG_fade"] : 1.8, 0, 4);
        if (_ambient && _lastImage && (!_art || _artDark != _dark)) {       // dark/light toggled: recompute (about 1 ms)
            LGPalette *p = [LGPalette paletteFromImage:_lastImage dark:_dark]; if (p) { _art = p; _artDark = _dark; }
            _blurredArt = LGMakeBlurredArtwork(_lastImage, _dark);
        }
        LGPalette *base = styleStatic ? [LGPalette staticNamed:([d stringForKey:@"LG_static_theme"] ?: @"Cherry Red") dark:_dark]
                                      : [LGPalette presetNamed:([d stringForKey:@"LG_theme"] ?: @"Aurora Teal") dark:_dark];
        _palette = (_ambient && _art) ? _art : base;
    }
}
- (void)reload {
    [self reloadSilently];
    dispatch_async(dispatch_get_main_queue(), ^{ [NSNotificationCenter.defaultCenter postNotificationName:LGPaletteDidChangeNotification object:nil]; });
}
- (void)ingestArtwork:(UIImage *)image trackKey:(NSString *)trackKey {
    if (!image) return;
    NSString *key = [NSString stringWithFormat:@"%@|%@", trackKey ?: @"", LGSignature(image)];
    dispatch_async(dispatch_get_main_queue(), ^{
        BOOL shouldExtract = NO;
        BOOL dark = YES;
        @synchronized(self) {
            if (![key isEqualToString:self->_lastKey]) {
                self->_lastKey = key; self->_lastImage = image; self->_blackStreak = 0; self->_lastTrack = trackKey; sArtIngests++;
                shouldExtract = self->_ambient;
                dark = self->_dark;
            }
        }
        if (!shouldExtract) {
            [NSNotificationCenter.defaultCenter postNotificationName:LGPaletteDidChangeNotification object:nil];
            return;
        }
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            LGPalette *p = [LGPalette paletteFromImage:image dark:dark];
            UIImage *blurred = LGMakeBlurredArtwork(image, dark);
            NSLog(@"[LG] ingestArtwork extracted a1=%@ b1=%@ dark=%d key='%@'", LGHexString(p.a1), LGHexString(p.b1), dark, trackKey ?: @"");
            dispatch_async(dispatch_get_main_queue(), ^{
                @synchronized(self) {
                    if (!p || ![key isEqualToString:self->_lastKey]) return;
                    self->_art = p; self->_artDark = dark; self->_blurredArt = blurred;
                }
                [self reload];
            });
        });
    });
}
- (NSString *)ambientStatus {
    @synchronized(self) {
        if (!_ambient) return [NSString stringWithFormat:@"Ambient is off (Now Playing updates: %lu, artworks: %lu)", (unsigned long)sHookFires, (unsigned long)sArtIngests];
        if (!_art) return [NSString stringWithFormat:@"Waiting for artwork. Now Playing updates: %lu, artworks received: %lu", (unsigned long)sHookFires, (unsigned long)sArtIngests];
        return [NSString stringWithFormat:@"Active: accent %@ from \"%@\"", LGHexString(_art.a1), _lastTrack ?: @"current track"];
    }
}
- (void)ingestVideoFrame:(UIImage *)frame {   // main thread
    if (!_ambient || !frame || _videoUnsupported) return;
    if (LGImageIsBlack(frame)) {              // protected / GPU-only layers often snapshot as black
        if (++_blackStreak >= 3) { _videoUnsupported = YES; [LGVideoSampler stop]; NSLog(@"[LG] video snapshots are black; using cover art only"); }
        return;
    }
    _blackStreak = 0;
    NSDate *now = [NSDate date];
    if (_lastVideoApply && [now timeIntervalSinceDate:_lastVideoApply] < 2.5) return;   // rate limit: no flicker
    LGPalette *p = [LGPalette paletteFromImage:frame dark:_dark]; if (!p) return;
    @synchronized(self) {
        if (_art) {                                                                        // hysteresis: ignore tiny changes
            CGFloat ar, ag, ab, br, bg, bb; [_art.a1 getRed:&ar green:&ag blue:&ab alpha:NULL]; [p.a1 getRed:&br green:&bg blue:&bb alpha:NULL];
            if (sqrt((ar-br)*(ar-br) + (ag-bg)*(ag-bg) + (ab-bb)*(ab-bb)) < .12) return;
        }
        _lastVideoApply = now; _art = p; _artDark = _dark;
    }
    NSLog(@"[LG] ingestVideoFrame usable: extracted a1=%@", LGHexString(p.a1));
    [self reload];
}
@end

void LGIngestNowPlayingInfo(NSDictionary *info) {
    if (![info isKindOfClass:NSDictionary.class]) return;
    sHookFires++;
    MPMediaItemArtwork *art = info[MPMediaItemPropertyArtwork];
    NSString *title = info[MPMediaItemPropertyTitle] ?: @"", *artist = info[MPMediaItemPropertyArtist] ?: @"";
    NSNumber *elapsed = info[MPNowPlayingInfoPropertyElapsedPlaybackTime];
    NSNumber *dur = info[MPMediaItemPropertyPlaybackDuration];
    NSLog(@"[LG] MPNowPlayingInfoCenter fire #%lu: title='%@' artist='%@' artwork=%@ elapsed=%@ dur=%@",
          (unsigned long)sHookFires, title, artist, art ? @"YES" : @"NO", elapsed ?: @"-", dur ?: @"-");
    if (!art) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [NSNotificationCenter.defaultCenter postNotificationName:LGPaletteDidChangeNotification object:nil];
        });
        return;
    }
    NSString *ta = [NSString stringWithFormat:@"%@|%@", title, artist];
    static NSString *lastTA; static NSDate *lastAt;
    BOOL same = [ta isEqualToString:lastTA];
    if (same && lastAt && [[NSDate date] timeIntervalSinceDate:lastAt] < 1.0) return;   // the app re-posts this dictionary often
    lastTA = ta; lastAt = [NSDate date];
    dispatch_async(dispatch_get_main_queue(), ^{
        CGSize s = art.bounds.size; CGFloat side = LGClamp(MIN(s.width, s.height), 64, 300);
        UIImage *img = [art imageWithSize:CGSizeMake(side, side)];
        NSLog(@"[LG] MPArtwork imageWithSize(%.0f,%.0f) -> %@", side, side, img ? @"YES" : @"NO");
        if (img) [LGTheme.shared ingestArtwork:img trackKey:ta];
    });
}

NSUInteger LGNowPlayingHookCount(void) { return sHookFires; }

id LGObserveTheme(void (^apply)(LGPalette *palette, BOOL dark, BOOL staticMode)) {
    if (!apply) return nil;
    void (^run)(void) = ^{ LGTheme *t = LGTheme.shared; apply(t.palette, t.dark, t.staticMode); };
    run();
    return [NSNotificationCenter.defaultCenter addObserverForName:LGPaletteDidChangeNotification object:nil
                                                           queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *n) { run(); }];
}

#pragma mark - LGBackgroundView (Full-Bleed Blurred Artwork & Atmospheric Wash — Zero Bulbs)
@implementation LGBackgroundView {
    CAGradientLayer *_base, *_scrim, *_glow;
    UIImageView *_artView;
    LGPalette *_pal;
    UIImage *_appliedArt;
}
- (instancetype)initWithFrame:(CGRect)f {
    if ((self = [super initWithFrame:f])) {
        self.userInteractionEnabled = NO; self.tag = kLGBgTag; _darkStyle = YES; _scrimMultiplier = 1.0f;
        self.clipsToBounds = YES;

        _base = [CAGradientLayer layer];
        _base.startPoint = CGPointMake(0.15, 0.0);
        _base.endPoint = CGPointMake(0.85, 1.0);
        [self.layer addSublayer:_base];

        _artView = [[UIImageView alloc] initWithFrame:f];
        _artView.contentMode = UIViewContentModeScaleAspectFill;
        _artView.clipsToBounds = YES;
        _artView.alpha = 0.0f;
        [self addSubview:_artView];

        _scrim = [CAGradientLayer layer];
        _scrim.startPoint = CGPointMake(0.5, 0.0);
        _scrim.endPoint = CGPointMake(0.5, 1.0);
        _scrim.locations = @[@0.0, @0.38, @0.72, @1.0];
        [self.layer addSublayer:_scrim];

        _glow = [CAGradientLayer layer];
        _glow.type = kCAGradientLayerRadial;
        _glow.startPoint = CGPointMake(0.5, 0.5);
        _glow.endPoint = CGPointMake(1.0, 1.0);
        _glow.locations = @[@0.0, @0.72];
        [self.layer addSublayer:_glow];

        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(themeChanged) name:LGPaletteDidChangeNotification object:nil];
        [self themeChanged];
    }
    return self;
}
- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }
- (void)setScrimMultiplier:(CGFloat)m {
    _scrimMultiplier = m > 0 ? m : 1.0f;
    [self applyPalette:_pal ?: LGTheme.shared.palette animated:NO];
}
- (void)themeChanged { LGTheme *t = LGTheme.shared; _darkStyle = t.dark; _staticMode = t.staticMode; [self applyPalette:t.palette animated:YES]; }
- (void)applyPalette:(LGPalette *)p animated:(BOOL)animated {
    if (!p) return;
    _pal = p;
    LGTheme *t = LGTheme.shared;
    NSTimeInterval dur = t.fadeDuration;
    if (UIAccessibilityIsReduceMotionEnabled() || dur <= 0) animated = NO;

    UIImage *art = (!_staticMode && t.ambient) ? t.blurredArtwork : nil;
    _glow.hidden = !_staticMode;
    _scrim.hidden = _staticMode;

    NSArray *baseC;
    if (_staticMode) {
        baseC = @[(id)p.b1.CGColor, (id)p.b1.CGColor];
    } else {
        UIColor *topTint = LGMix(p.b1, p.a1 ?: p.b2, _darkStyle ? 0.24 : 0.16);
        UIColor *midTint = LGMix(p.b2, p.a2 ?: p.a1, _darkStyle ? 0.22 : 0.14);
        UIColor *botTint = LGMix(p.b1, p.b2, 0.45);
        baseC = @[(id)topTint.CGColor, (id)midTint.CGColor, (id)botTint.CGColor];
        _base.locations = @[@0.0, @0.48, @1.0];
    }

    CGFloat m = _scrimMultiplier > 0 ? _scrimMultiplier : 1.0f;
    NSArray *scrimC;
    if (_darkStyle) {
        scrimC = @[
            (id)[UIColor colorWithWhite:0.0 alpha:LGClamp(0.26 * m, 0.0, 0.72)].CGColor,
            (id)[UIColor colorWithWhite:0.0 alpha:LGClamp(0.14 * m, 0.0, 0.60)].CGColor,
            (id)[UIColor colorWithWhite:0.0 alpha:LGClamp(0.28 * m, 0.0, 0.72)].CGColor,
            (id)[UIColor colorWithWhite:0.0 alpha:LGClamp(0.42 * m, 0.0, 0.80)].CGColor
        ];
    } else {
        scrimC = @[
            (id)[UIColor colorWithWhite:1.0 alpha:LGClamp(0.24 * m, 0.0, 0.65)].CGColor,
            (id)[UIColor colorWithWhite:1.0 alpha:LGClamp(0.14 * m, 0.0, 0.55)].CGColor,
            (id)[UIColor colorWithWhite:1.0 alpha:LGClamp(0.26 * m, 0.0, 0.65)].CGColor,
            (id)[UIColor colorWithWhite:1.0 alpha:LGClamp(0.36 * m, 0.0, 0.72)].CGColor
        ];
    }
    NSArray *glowC = @[(id)[p.a1 colorWithAlphaComponent:_darkStyle ? .45 : .28].CGColor, (id)[p.a1 colorWithAlphaComponent:0].CGColor];

    void (^set)(CAGradientLayer *, NSArray *) = ^(CAGradientLayer *l, NSArray *c) {
        if (animated) {
            CABasicAnimation *an = [CABasicAnimation animationWithKeyPath:@"colors"];
            an.fromValue = ((CAGradientLayer *)(l.presentationLayer ?: l)).colors; an.toValue = c; an.duration = dur;
            an.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
            [l addAnimation:an forKey:@"lgcolors"];
        }
        l.colors = c;
    };
    set(_base, baseC);
    set(_scrim, scrimC);
    set(_glow, glowC);

    if (art != _appliedArt) {
        _appliedArt = art;
        void (^swap)(void) = ^{
            self->_artView.image = art;
            self->_artView.alpha = art ? (self->_scrimMultiplier > 1.15f ? 0.78f : 0.96f) : 0.0f;
        };
        if (animated && dur > 0.05) {
            [UIView transitionWithView:_artView duration:dur options:UIViewAnimationOptionTransitionCrossDissolve | UIViewAnimationOptionAllowUserInteraction animations:swap completion:nil];
        } else {
            swap();
        }
    } else if (_artView.image) {
        _artView.alpha = (_staticMode || !t.ambient) ? 0.0f : (_scrimMultiplier > 1.15f ? 0.78f : 0.96f);
    }
    [self setNeedsLayout];
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat W = self.bounds.size.width, H = self.bounds.size.height; if (W < 1 || H < 1) return;
    [CATransaction begin]; [CATransaction setDisableActions:YES];
    _base.frame = self.bounds;
    _artView.frame = CGRectInset(self.bounds, -12.0f, -12.0f);
    _scrim.frame = self.bounds;
    _glow.frame = CGRectMake(W / 2 - .95 * W, H / 2 - .48 * H, 1.9 * W, .96 * H);
    [CATransaction commit];
}
@end

#pragma mark - LGGlassView (iOS 26 Specular Liquid Glass)
@implementation LGGlassView {
    UIView *_clip, *_tint;
    UIVisualEffectView *_blur;
    CAGradientLayer *_gloss, *_specBorder;
    CAShapeLayer *_specMask;
}
- (instancetype)initWithRadius:(CGFloat)radius dark:(BOOL)dark {
    if ((self = [super initWithFrame:CGRectZero])) {
        _radius = radius; _darkStyle = dark; self.tag = kLGGlassTag; self.userInteractionEnabled = NO;
        _clip = [UIView new]; _clip.clipsToBounds = YES;
        _blur = [UIVisualEffectView new];
        _tint = [UIView new];

        _gloss = [CAGradientLayer layer];
        _gloss.startPoint = CGPointMake(0.5, 0.0);
        _gloss.endPoint = CGPointMake(0.5, 1.0);
        _gloss.locations = @[@0.0, @0.35, @1.0];

        _specBorder = [CAGradientLayer layer];
        _specBorder.startPoint = CGPointMake(0.0, 0.0);
        _specBorder.endPoint = CGPointMake(1.0, 1.0);
        _specBorder.locations = @[@0.0, @0.32, @0.68, @1.0];
        _specMask = [CAShapeLayer layer];
        _specMask.fillColor = UIColor.clearColor.CGColor;
        _specMask.strokeColor = UIColor.whiteColor.CGColor;
        _specMask.lineWidth = 1.25;
        _specBorder.mask = _specMask;

        [_clip addSubview:_blur];
        [_clip addSubview:_tint];
        [_clip.layer addSublayer:_gloss];
        [_clip.layer addSublayer:_specBorder];
        [self addSubview:_clip];

        self.layer.shadowOffset = CGSizeMake(0, 8); self.layer.shadowRadius = 14;
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(themeChanged) name:LGPaletteDidChangeNotification object:nil];
        [self refresh];
    }
    return self;
}
- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }
- (void)themeChanged { LGTheme *t = LGTheme.shared; _darkStyle = t.dark; _staticMode = t.staticMode; _staticFill = t.palette.b2; [self refresh]; }
- (void)setRadius:(CGFloat)r { _radius = r; [self setNeedsLayout]; }
- (void)refresh {
    if (_staticMode) {
        _blur.effect = nil; _blur.hidden = YES;
        _gloss.hidden = YES; _specBorder.hidden = YES;
        _tint.backgroundColor = _staticFill ?: [UIColor colorWithWhite:.12 alpha:1];
        _clip.layer.borderWidth = 1.0f;
        _clip.layer.borderColor = [UIColor colorWithWhite:.5 alpha:.35].CGColor;
        self.layer.shadowOpacity = 0;
    } else {
        _blur.hidden = NO;
        _blur.effect = [UIBlurEffect effectWithStyle:_darkStyle ? UIBlurEffectStyleSystemUltraThinMaterialDark : UIBlurEffectStyleSystemUltraThinMaterialLight];
        _blur.alpha = _darkStyle ? 0.88f : 0.92f;
        _tint.backgroundColor = [UIColor colorWithWhite:1.0 alpha:(_darkStyle ? 0.045 : 0.36)];
        _clip.layer.borderWidth = 0.0f;

        _gloss.hidden = NO;
        _gloss.colors = @[
            (id)[UIColor colorWithWhite:1.0 alpha:(_darkStyle ? 0.13 : 0.42)].CGColor,
            (id)[UIColor colorWithWhite:1.0 alpha:(_darkStyle ? 0.03 : 0.10)].CGColor,
            (id)UIColor.clearColor.CGColor
        ];

        _specBorder.hidden = NO;
        _specBorder.colors = _darkStyle ? @[
            (id)[UIColor colorWithWhite:1.0 alpha:0.50].CGColor,
            (id)[UIColor colorWithWhite:1.0 alpha:0.14].CGColor,
            (id)[UIColor colorWithWhite:1.0 alpha:0.08].CGColor,
            (id)[UIColor colorWithWhite:1.0 alpha:0.32].CGColor
        ] : @[
            (id)[UIColor colorWithWhite:1.0 alpha:0.92].CGColor,
            (id)[UIColor colorWithWhite:1.0 alpha:0.45].CGColor,
            (id)[UIColor colorWithWhite:1.0 alpha:0.28].CGColor,
            (id)[UIColor colorWithWhite:1.0 alpha:0.75].CGColor
        ];

        self.layer.shadowColor = UIColor.blackColor.CGColor;
        self.layer.shadowOpacity = _darkStyle ? 0.32f : 0.16f;
    }
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect b = self.bounds;
    if (b.size.width <= 0 || b.size.height <= 0) return;
    [CATransaction begin]; [CATransaction setDisableActions:YES];
    _clip.frame = b; _blur.frame = b; _tint.frame = b;
    CGFloat r = MIN(_radius, MIN(b.size.width, b.size.height) / 2);
    _clip.layer.cornerRadius = r;
    _gloss.frame = CGRectMake(0, 0, b.size.width, MIN(b.size.height, MAX(24.0f, b.size.height * 0.45f)));
    _specBorder.frame = b;
    _specMask.frame = b;
    _specMask.path = [UIBezierPath bezierPathWithRoundedRect:CGRectInset(b, 0.6f, 0.6f) cornerRadius:MAX(0, r - 0.6f)].CGPath;
    [CATransaction commit];
    CGRect sp = CGRectInset(b, 12, 12);
    if (sp.size.width > 0 && sp.size.height > 0) self.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:sp cornerRadius:MAX(0, r - 12)].CGPath;
    else self.layer.shadowPath = nil;
}
@end

#pragma mark - LGVideoSampler (experimental)
@implementation LGVideoSampler
static NSTimer *sTimer; static __weak UIView *sTarget;
+ (void)startForView:(UIView *)v {
    [self stop]; sTarget = v;
    sTimer = [NSTimer scheduledTimerWithTimeInterval:1.5 repeats:YES block:^(__unused NSTimer *t) { [LGVideoSampler tick]; }];
}
+ (void)stop { [sTimer invalidate]; sTimer = nil; sTarget = nil; }
+ (void)tick {
    UIView *v = sTarget; if (!v || !v.window || v.bounds.size.width < 50 || !LGTheme.shared.ambient) return;
    if (![NSUserDefaults.standardUserDefaults boolForKey:@"LG_video"]) return;
    CGSize sz = CGSizeMake(64, MAX(16, 64 * v.bounds.size.height / v.bounds.size.width));
    UIGraphicsImageRendererFormat *f = [UIGraphicsImageRendererFormat defaultFormat]; f.scale = 1;
    UIImage *img = [[[UIGraphicsImageRenderer alloc] initWithSize:sz format:f] imageWithActions:^(__unused UIGraphicsImageRendererContext *c) {
        [v drawViewHierarchyInRect:CGRectMake(0, 0, sz.width, sz.height) afterScreenUpdates:NO];
    }];
    [LGTheme.shared ingestVideoFrame:img];
}
@end

#pragma mark - helpers
static UIView *LGFindDirectSubviewWithTag(UIView *host, NSInteger tag) {
    for (UIView *sub in host.subviews) {
        if (sub.tag == tag) return sub;
    }
    return nil;
}

LGBackgroundView *LGInstallBackground(UIView *host) {
    if (!host) return nil;
    UIView *old = LGFindDirectSubviewWithTag(host, kLGBgTag); if ([old isKindOfClass:LGBackgroundView.class]) return (LGBackgroundView *)old;
    LGBackgroundView *bg = [[LGBackgroundView alloc] initWithFrame:host.bounds];
    bg.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight; [host insertSubview:bg atIndex:0]; return bg;
}
LGGlassView *LGAttachGlass(UIView *host, CGFloat radius) {
    if (!host) return nil;
    UIView *old = LGFindDirectSubviewWithTag(host, kLGGlassTag);
    if ([old isKindOfClass:LGGlassView.class]) { ((LGGlassView *)old).radius = radius; return (LGGlassView *)old; }
    host.backgroundColor = UIColor.clearColor;
    LGGlassView *g = [[LGGlassView alloc] initWithRadius:radius dark:LGTheme.shared.dark]; g.frame = host.bounds;
    g.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight; [host insertSubview:g atIndex:0]; [g themeChanged]; return g;
}
