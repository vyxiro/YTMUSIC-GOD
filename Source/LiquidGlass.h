// LiquidGlass.h  v2  (supersedes v1)
// Adds: unlimited ambient colours from cover/video, Static+Ambient, static-look palettes,
// accent glyph colour, track-change ingestion via MPNowPlayingInfoCenter, video-frame sampling.
// Settings keys (NSUserDefaults):
//   LG_style        "liquid" | "static"      (LG_static BOOL still honoured)
//   LG_ambient      BOOL    colours follow the playing track (any colour, any mode)
//   LG_theme        liquid preset name       (used when LG_ambient is off)
//   LG_static_theme static-look palette name (used when LG_ambient is off)
//   LG_dark         BOOL    default YES
//   LG_fade         double  seconds, default 1.8 (0 = instant; Reduce Motion forces instant)
//   LG_video        BOOL    sample live video frames in video mode (experimental)
#import <UIKit/UIKit.h>

extern NSString *const LGPaletteDidChangeNotification;

@interface LGPalette : NSObject
@property (nonatomic, copy)   NSString *name;
@property (nonatomic, strong) UIColor *b1, *b2, *a1, *a2, *tx, *mu;
@property (nonatomic, strong) UIColor *onAccent;      // glyph colour on top of a1 (white or dark)
+ (NSArray<NSString *> *)presetNames;                 // 5 liquid themes
+ (NSArray<NSString *> *)staticNames;                 // 5 static-look palettes
+ (LGPalette *)presetNamed:(NSString *)name dark:(BOOL)dark;
+ (LGPalette *)staticNamed:(NSString *)name dark:(BOOL)dark;
+ (LGPalette *)paletteFromImage:(UIImage *)image dark:(BOOL)dark;   // any colour, not limited to presets
@end

@interface LGBackgroundView : UIView
@property (nonatomic) BOOL darkStyle;
@property (nonatomic) BOOL staticMode;    // flat bg + one soft ellipse glow, no blobs
- (void)applyPalette:(LGPalette *)p animated:(BOOL)animated;
@end

@interface LGGlassView : UIView
@property (nonatomic) CGFloat radius;
@property (nonatomic) BOOL darkStyle;
@property (nonatomic) BOOL staticMode;    // solid b2 + 1pt grey border, no blur, no shadow
@property (nonatomic, strong) UIColor *staticFill;
- (instancetype)initWithRadius:(CGFloat)radius dark:(BOOL)dark;
@end

@interface LGTheme : NSObject
@property (class, readonly) LGTheme *shared;
@property (nonatomic, strong, readonly) LGPalette *palette;
@property (nonatomic, readonly) BOOL dark, staticMode, ambient;
@property (nonatomic, readonly) NSTimeInterval fadeDuration;
- (void)reload;                                                   // re-read prefs, post notification
- (void)ingestArtwork:(UIImage *)image trackKey:(NSString *)key;  // call on every track change
- (void)ingestVideoFrame:(UIImage *)frame;                        // called by LGVideoSampler
@end

// Call from the MPNowPlayingInfoCenter hook (see LGHooks.x). No YouTube class names needed.
void LGIngestNowPlayingInfo(NSDictionary *info);

// Optional, experimental: sample the on-screen video container about every 1.5 s.
@interface LGVideoSampler : NSObject
+ (void)startForView:(UIView *)videoContainer;
+ (void)stop;
@end

LGBackgroundView *LGInstallBackground(UIView *host);
LGGlassView *LGAttachGlass(UIView *host, CGFloat radius);
