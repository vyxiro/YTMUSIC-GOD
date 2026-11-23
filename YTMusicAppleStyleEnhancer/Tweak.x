#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import "ThemeManager.h"
#import "AmbientView.h"
#import "AudioCrossfadeManager.h"
#import "SettingsViewController.h"

// Forward declarations of YouTube Music internal classes
@interface YTMNavigationBarView : UIView
@end

@interface YTMNowPlayingViewController : UIViewController
@property (nonatomic, strong) AmbientView *ytmAppleAmbientView;
- (void)didTapNextButton;
- (void)didTapPrevButton;
@end

@interface YTMPlayerControlsView : UIView
@property (nonatomic, strong) UIButton *playPauseButton;
@property (nonatomic, strong) UIButton *nextButton;
@property (nonatomic, strong) UIButton *prevButton;
@end

@interface YTMNowPlayingView : UIView
@property (nonatomic, readonly) YTMPlayerControlsView *playerControlsView;
@property (nonatomic, strong) UIImageView *artworkImageView;
@end

@interface YTPlayerViewController : UIViewController
- (CGFloat)currentVideoMediaTime;
- (CGFloat)currentVideoTotalMediaTime;
- (NSString *)currentVideoID;
- (void)didTapNextButton;
@end

@interface YTPivotBarItemView : UIView
@property (nonatomic, assign) BOOL selected;
- (void)setTintColor:(UIColor *)color;
@end

@interface YTPivotBarView : UIView
@property (nonatomic, readonly) UIView *contentView;
@end

@interface YTMPlayerPageColorScheme : NSObject
- (void)setPlayButtonColor:(UIColor *)color;
@end

@interface YTColor : UIColor
+ (UIColor *)blackPure;
@end

@interface YTMAccountButton : UIButton
- (id)initWithTitle:(id)title identifier:(id)identifier icon:(id)icon actionBlock:(void (^)(BOOL finished))action;
@end

@interface YTMAvatarAccountView : UIView
@end

@interface UIView (PrivateAncestor)
- (UIViewController *)_viewControllerForAncestor;
@end

static AmbientView *gActiveAmbientView = nil;

#pragma mark - 1. Smooth Audio Crossfade & Playback Hooks

%hook YTPlayerViewController

- (void)viewDidLoad {
    %orig;
    [[AudioCrossfadeManager sharedInstance] registerPlayerViewController:self];
}

- (void)playbackController:(id)arg1 didActivateVideo:(id)arg2 withPlaybackData:(id)arg3 {
    %orig;
    [[AudioCrossfadeManager sharedInstance] registerPlayerViewController:self];
    [[AudioCrossfadeManager sharedInstance] willTransitionToNextTrack];
}

- (void)singleVideo:(id)video currentVideoTimeDidChange:(id)time {
    %orig;
    CGFloat current = [self currentVideoMediaTime];
    CGFloat total = [self currentVideoTotalMediaTime];
    if (total > 0) {
        [[AudioCrossfadeManager sharedInstance] didUpdatePlaybackTime:current duration:total];
    }
}

- (void)potentiallyMutatedSingleVideo:(id)video currentVideoTimeDidChange:(id)time {
    %orig;
    CGFloat current = [self currentVideoMediaTime];
    CGFloat total = [self currentVideoTotalMediaTime];
    if (total > 0) {
        [[AudioCrossfadeManager sharedInstance] didUpdatePlaybackTime:current duration:total];
    }
}

%end

%hook AVPlayer

- (void)play {
    %orig;
    [[AudioCrossfadeManager sharedInstance] registerActivePlayer:self];
}

- (void)replaceCurrentItemWithPlayerItem:(AVPlayerItem *)item {
    %orig(item);
    if (item) {
        [[AudioCrossfadeManager sharedInstance] optimizePlayerItemForLowNetwork:item];
        [[AudioCrossfadeManager sharedInstance] didStartNewTrackWithPlayer:self];
    }
}

%end

%hook AVPlayerItem

- (instancetype)initWithURL:(NSURL *)URL {
    AVPlayerItem *item = %orig(URL);
    if (item) {
        [[AudioCrossfadeManager sharedInstance] optimizePlayerItemForLowNetwork:item];
    }
    return item;
}

- (instancetype)initWithAsset:(AVAsset *)asset {
    AVPlayerItem *item = %orig(asset);
    if (item) {
        [[AudioCrossfadeManager sharedInstance] optimizePlayerItemForLowNetwork:item];
    }
    return item;
}

%end

#pragma mark - 2. Low-Network Aggressive Buffer & Network Resilience

%hook NSURLSessionConfiguration

+ (NSURLSessionConfiguration *)defaultSessionConfiguration {
    NSURLSessionConfiguration *config = %orig;
    if ([AudioCrossfadeManager sharedInstance].lowNetworkBufferingEnabled) {
        config.timeoutIntervalForRequest = 45.0;
        config.timeoutIntervalForResource = 300.0;
        config.waitsForConnectivity = YES;
        config.allowsExpensiveNetworkAccess = YES;
        config.allowsConstrainedNetworkAccess = YES;
        config.HTTPMaximumConnectionsPerHost = 6;
    }
    return config;
}

+ (NSURLSessionConfiguration *)ephemeralSessionConfiguration {
    NSURLSessionConfiguration *config = %orig;
    if ([AudioCrossfadeManager sharedInstance].lowNetworkBufferingEnabled) {
        config.timeoutIntervalForRequest = 45.0;
        config.timeoutIntervalForResource = 300.0;
        config.waitsForConnectivity = YES;
        config.allowsExpensiveNetworkAccess = YES;
        config.allowsConstrainedNetworkAccess = YES;
    }
    return config;
}

%end

#pragma mark - 3. Ambient Artwork Glow & Now Playing Integration

%hook YTMNowPlayingViewController

%property (nonatomic, strong) AmbientView *ytmAppleAmbientView;

- (void)viewDidLoad {
    %orig;

    if (!self.ytmAppleAmbientView) {
        self.ytmAppleAmbientView = [[AmbientView alloc] initWithFrame:self.view.bounds];
        self.ytmAppleAmbientView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self.view insertSubview:self.ytmAppleAmbientView atIndex:0];
        gActiveAmbientView = self.ytmAppleAmbientView;
    }
}

- (void)viewDidLayoutSubviews {
    %orig;
    if (self.ytmAppleAmbientView) {
        self.ytmAppleAmbientView.frame = self.view.bounds;
        [self.view sendSubviewToBack:self.ytmAppleAmbientView];
    }
}

%end

// Hook image updates to feed album artwork into AmbientView
%hook UIImageView

- (void)setImage:(UIImage *)image {
    %orig(image);

    // If this image view is part of the player artwork hierarchy, extract dominant glow
    if (image && gActiveAmbientView && gActiveAmbientView.glowEnabled) {
        // Inspect if this UIImageView is reasonably sized to be album art (typically > 120x120)
        CGSize sz = image.size;
        if (sz.width >= 120 && sz.height >= 120 && fabs(sz.width - sz.height) < 40) {
            [gActiveAmbientView updateWithArtworkImage:image animated:YES];
        }
    }
}

%end

#pragma mark - 4. True OLED Pitch Black (#000000)

%hook YTColor

+ (UIColor *)black0 {
    return [ThemeManager sharedManager].oledBlackEnabled ? [[ThemeManager sharedManager] oledBackgroundColor] : %orig;
}

+ (UIColor *)black1 {
    return [ThemeManager sharedManager].oledBlackEnabled ? [[ThemeManager sharedManager] oledBackgroundColor] : %orig;
}

+ (UIColor *)black2 {
    return [ThemeManager sharedManager].oledBlackEnabled ? [[ThemeManager sharedManager] oledBackgroundColor] : %orig;
}

+ (UIColor *)black3 {
    return [ThemeManager sharedManager].oledBlackEnabled ? [[ThemeManager sharedManager] oledBackgroundColor] : %orig;
}

+ (UIColor *)black4 {
    return [ThemeManager sharedManager].oledBlackEnabled ? [[ThemeManager sharedManager] oledBackgroundColor] : %orig;
}

%end

%hook YTMPlayerPageColorScheme

- (UIColor *)backgroundColor {
    return [ThemeManager sharedManager].oledBlackEnabled ? [[ThemeManager sharedManager] oledBackgroundColor] : %orig;
}

- (UIColor *)expandedTabsBackgroundColor {
    return [ThemeManager sharedManager].oledBlackEnabled ? [[ThemeManager sharedManager] oledBackgroundColor] : %orig;
}

- (UIColor *)miniPlayerColor {
    return [ThemeManager sharedManager].oledBlackEnabled ? [[ThemeManager sharedManager] oledBackgroundColor] : %orig;
}

- (UIColor *)expandedTabViewColor {
    return [ThemeManager sharedManager].oledBlackEnabled ? [[ThemeManager sharedManager] oledBackgroundColor] : %orig;
}

- (UIColor *)overlayButtonColor {
    return [ThemeManager sharedManager].oledBlackEnabled ? [[ThemeManager sharedManager] oledBackgroundColor] : %orig;
}

- (UIColor *)AVSwitchBackgroundColor {
    return [ThemeManager sharedManager].oledBlackEnabled ? [[ThemeManager sharedManager] oledBackgroundColor] : %orig;
}

- (UIColor *)queueBackgroundColor {
    return [ThemeManager sharedManager].oledBlackEnabled ? [[ThemeManager sharedManager] oledBackgroundColor] : %orig;
}

- (BOOL)gradientBackgroundEnabled {
    // Disable Google default grey-gradient so pure OLED black or custom ambient glow shines
    return [ThemeManager sharedManager].oledBlackEnabled ? NO : %orig;
}

%end

%hook YTPivotBarView

- (UIView *)contentView {
    UIView *view = %orig;
    if ([ThemeManager sharedManager].oledBlackEnabled) {
        view.backgroundColor = [[ThemeManager sharedManager] oledBackgroundColor];
    }
    return view;
}

%end

#pragma mark - 5. Dynamic Multi-Color Theme Accents (Yellow, Green & Custom Hex)

%hook UISlider

- (void)didMoveToWindow {
    %orig;
    if (self.window) {
        UIColor *accent = [[ThemeManager sharedManager] currentAccentColor];
        self.minimumTrackTintColor = accent;
        self.thumbTintColor = accent;
    }
}

%end

%hook YTPivotBarItemView

- (void)layoutSubviews {
    %orig;
    if (self.selected) {
        UIColor *accent = [[ThemeManager sharedManager] currentAccentColor];
        [self setTintColor:accent];
    }
}

- (void)setSelected:(BOOL)selected {
    %orig(selected);
    if (selected) {
        UIColor *accent = [[ThemeManager sharedManager] currentAccentColor];
        [self setTintColor:accent];
    }
}

%end

%hook UISwitch

- (void)didMoveToWindow {
    %orig;
    if (self.window) {
        self.onTintColor = [[ThemeManager sharedManager] currentAccentColor];
    }
}

%end

#pragma mark - 6. In-App Settings Menu Integration (Triple-Tap & Menu Button)

%hook YTMNavigationBarView

- (void)didMoveToWindow {
    %orig;
    if (self.window) {
        // Add triple-tap recognizer on navigation bar for instant settings access
        BOOL hasGesture = NO;
        for (UIGestureRecognizer *gr in self.gestureRecognizers) {
            if ([gr isKindOfClass:[UITapGestureRecognizer class]] && [(UITapGestureRecognizer *)gr numberOfTapsRequired] == 3) {
                hasGesture = YES;
                break;
            }
        }
        if (!hasGesture) {
            UITapGestureRecognizer *tripleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(ytmApple_openSettingsMenu)];
            tripleTap.numberOfTapsRequired = 3;
            [self addGestureRecognizer:tripleTap];
            self.userInteractionEnabled = YES;
        }
    }
}

%new
- (void)ytmApple_openSettingsMenu {
    UIViewController *topVC = [self _viewControllerForAncestor];
    if (topVC) {
        UINavigationController *nav = [SettingsViewController presentedInNavigationController];
        [topVC presentViewController:nav animated:YES completion:nil];
    }
}

%end

// Also integrate settings button directly into the Account/Profile menu view
%hook YTMAvatarAccountView

- (void)setAccountMenuUpperButtons:(id)arg1 lowerButtons:(id)arg2 {
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(24, 24)];
    UIImage *icon = [renderer imageWithActions:^(UIGraphicsImageRendererContext * _Nonnull ctx) {
        UIImage *sparkles = [UIImage systemImageNamed:@"sparkles"];
        UIImageView *imgView = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, 24, 24)];
        imgView.image = sparkles;
        imgView.tintColor = [[ThemeManager sharedManager] currentAccentColor];
        imgView.contentMode = UIViewContentModeScaleAspectFit;
        [imgView.layer renderInContext:ctx.CGContext];
    }];

    YTMAccountButton *enhancerBtn = [[%c(YTMAccountButton) alloc] initWithTitle:@"Apple Style Enhancer"
                                                                     identifier:@"ytm_apple_enhancer"
                                                                           icon:icon
                                                                    actionBlock:^(BOOL finished) {
        UIViewController *topVC = [self _viewControllerForAncestor];
        if (topVC) {
            UINavigationController *nav = [SettingsViewController presentedInNavigationController];
            [topVC presentViewController:nav animated:YES completion:nil];
        }
    }];
    enhancerBtn.tintColor = [[ThemeManager sharedManager] currentAccentColor];

    NSMutableArray *newLower = [NSMutableArray arrayWithArray:arg2];
    [newLower addObject:enhancerBtn];

    %orig(arg1, newLower);
}

%end

#pragma mark - Constructor

%ctor {
    NSLog(@"[YTMusicAppleStyleEnhancer] Initialized successfully. Loaded theme: %ld", (long)[ThemeManager sharedManager].themePreset);
}
