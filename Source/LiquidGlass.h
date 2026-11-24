// LiquidGlass.h - UIKit port of the "YT Music · Liquid Glass Theme Sheet" HTML.
// Plain Objective-C, no Logos. Import from your .x files.
#import <UIKit/UIKit.h>

extern NSString *const LGPaletteDidChangeNotification;

// ---------- Palette (b1/b2 background, a1/a2 accents, tx text, mu muted) ----------
@interface LGPalette : NSObject
@property (nonatomic, copy)   NSString *name;
@property (nonatomic, strong) UIColor *b1, *b2, *a1, *a2, *tx, *mu;
+ (NSArray<NSString *> *)presetNames;                       // 5 themes from the sheet
+ (LGPalette *)presetNamed:(NSString *)name dark:(BOOL)dark;
+ (LGPalette *)paletteFromArtwork:(UIImage *)image dark:(BOOL)dark; // ambient mode
@end

// ---------- Full-bleed background: 170deg gradient + two soft blobs ----------
@interface LGBackgroundView : UIView
@property (nonatomic) BOOL darkStyle;     // light mode lowers blob opacity to .5
@property (nonatomic) BOOL staticMode;    // flat b1, no blobs (the sheet's "static look")
- (void)applyPalette:(LGPalette *)p animated:(BOOL)animated; // 1.8s fade when animated
@end

// ---------- Glass surface (chips, mini player, tab bar, cards) ----------
@interface LGGlassView : UIView
@property (nonatomic) CGFloat radius;     // use bounds.height/2 for capsules
@property (nonatomic) BOOL darkStyle;
@property (nonatomic) BOOL staticMode;    // solid b2 + 1px border, no blur
@property (nonatomic, strong) UIColor *staticFill; // b2 when staticMode
- (instancetype)initWithRadius:(CGFloat)radius dark:(BOOL)dark;
@end

// ---------- Global state ----------
@interface LGTheme : NSObject
@property (class, readonly) LGTheme *shared;
@property (nonatomic, strong, readonly) LGPalette *palette;
@property (nonatomic, readonly) BOOL dark;        // follows the app's page style
@property (nonatomic, readonly) BOOL staticMode;  // pref + Reduce Transparency
@property (nonatomic, readonly) BOOL ambient;     // palette from playing song
- (void)reload;                                   // re-read NSUserDefaults, post notification
- (void)setArtwork:(UIImage *)image;              // call on track change when ambient is on
@end

// Insert / reuse the shared background behind `host` (index 0). Returns it.
LGBackgroundView *LGInstallBackground(UIView *host);
// Make `host` transparent and put a glass layer behind its content.
LGGlassView *LGAttachGlass(UIView *host, CGFloat radius);
