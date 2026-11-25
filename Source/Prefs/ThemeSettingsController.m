#import "ThemeSettingsController.h"
#import "../LiquidGlass.h"
#import "../Headers/ABCSwitch.h"
#import <objc/runtime.h>

extern NSString *LGBuildDiagnosticReport(void);
static char kDiagTextKey;

@interface ThemeSettingsController ()
@property (nonatomic, strong) id themeObserver;
@property (nonatomic, strong) LGBackgroundView *previewBg;
@property (nonatomic, strong) LGGlassView *previewCard;
@property (nonatomic, strong) UIView *previewProgressFill;
@property (nonatomic, strong) UIView *previewPlayBtn;
@property (nonatomic, strong) UIImageView *previewPlayGlyph;
@property (nonatomic, strong) UILabel *previewTitleLabel;
@property (nonatomic, strong) UILabel *previewSubtitleLabel;
@property (nonatomic, strong) UILabel *previewModePill;
@end

@implementation ThemeSettingsController

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"Liquid Glass";
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    [self.view addSubview:self.tableView];

    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.tableView.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [self.tableView.widthAnchor constraintEqualToAnchor:self.view.widthAnchor],
        [self.tableView.heightAnchor constraintEqualToAnchor:self.view.heightAnchor]
    ]];

    [self installLivePreviewHeader];

    __weak typeof(self) weakSelf = self;
    self.themeObserver = LGObserveTheme(^(LGPalette *palette, BOOL dark, BOOL staticMode) {
        [weakSelf updateLivePreviewWithPalette:palette dark:dark staticMode:staticMode];
        [weakSelf.tableView reloadData];
    });
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    if (self.tableView.tableHeaderView) {
        CGRect f = self.tableView.tableHeaderView.frame;
        if (fabs(f.size.width - self.tableView.bounds.size.width) > 1.0f && self.tableView.bounds.size.width > 0) {
            f.size.width = self.tableView.bounds.size.width;
            self.tableView.tableHeaderView.frame = f;
            self.tableView.tableHeaderView = self.tableView.tableHeaderView;
        }
    }
}

- (void)dealloc {
    if (self.themeObserver) {
        [[NSNotificationCenter defaultCenter] removeObserver:self.themeObserver];
    }
}

#pragma mark - Live Preview Card

- (void)installLivePreviewHeader {
    UIView *container = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width ?: 390, 176)];
    container.backgroundColor = UIColor.clearColor;

    UIView *cardHost = [[UIView alloc] initWithFrame:CGRectZero];
    cardHost.translatesAutoresizingMaskIntoConstraints = NO;
    cardHost.layer.cornerRadius = 22.0f;
    cardHost.clipsToBounds = YES;
    cardHost.layer.borderWidth = 1.0f;
    cardHost.layer.borderColor = [UIColor colorWithWhite:1.0f alpha:0.20f].CGColor;
    [container addSubview:cardHost];

    [NSLayoutConstraint activateConstraints:@[
        [cardHost.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:20.0f],
        [cardHost.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-20.0f],
        [cardHost.topAnchor constraintEqualToAnchor:container.topAnchor constant:12.0f],
        [cardHost.bottomAnchor constraintEqualToAnchor:container.bottomAnchor constant:-4.0f]
    ]];

    self.previewBg = [[LGBackgroundView alloc] initWithFrame:CGRectZero];
    self.previewBg.translatesAutoresizingMaskIntoConstraints = NO;
    [cardHost addSubview:self.previewBg];
    [NSLayoutConstraint activateConstraints:@[
        [self.previewBg.leadingAnchor constraintEqualToAnchor:cardHost.leadingAnchor],
        [self.previewBg.trailingAnchor constraintEqualToAnchor:cardHost.trailingAnchor],
        [self.previewBg.topAnchor constraintEqualToAnchor:cardHost.topAnchor],
        [self.previewBg.bottomAnchor constraintEqualToAnchor:cardHost.bottomAnchor]
    ]];

    self.previewModePill = [[UILabel alloc] init];
    self.previewModePill.translatesAutoresizingMaskIntoConstraints = NO;
    self.previewModePill.font = [UIFont systemFontOfSize:11.0f weight:UIFontWeightSemibold];
    self.previewModePill.textAlignment = NSTextAlignmentCenter;
    self.previewModePill.layer.cornerRadius = 11.0f;
    self.previewModePill.clipsToBounds = YES;
    [cardHost addSubview:self.previewModePill];

    self.previewCard = [[LGGlassView alloc] initWithRadius:18.0f dark:LGTheme.shared.dark];
    self.previewCard.translatesAutoresizingMaskIntoConstraints = NO;
    [cardHost addSubview:self.previewCard];

    [NSLayoutConstraint activateConstraints:@[
        [self.previewModePill.topAnchor constraintEqualToAnchor:cardHost.topAnchor constant:12.0f],
        [self.previewModePill.leadingAnchor constraintEqualToAnchor:cardHost.leadingAnchor constant:14.0f],
        [self.previewModePill.heightAnchor constraintEqualToConstant:22.0f],

        [self.previewCard.leadingAnchor constraintEqualToAnchor:cardHost.leadingAnchor constant:12.0f],
        [self.previewCard.trailingAnchor constraintEqualToAnchor:cardHost.trailingAnchor constant:-12.0f],
        [self.previewCard.bottomAnchor constraintEqualToAnchor:cardHost.bottomAnchor constant:-12.0f],
        [self.previewCard.heightAnchor constraintEqualToConstant:88.0f]
    ]];

    self.previewTitleLabel = [[UILabel alloc] init];
    self.previewTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.previewTitleLabel.font = [UIFont systemFontOfSize:15.0f weight:UIFontWeightBold];
    self.previewTitleLabel.text = @"Now Playing Preview";

    self.previewSubtitleLabel = [[UILabel alloc] init];
    self.previewSubtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.previewSubtitleLabel.font = [UIFont systemFontOfSize:12.0f weight:UIFontWeightRegular];
    self.previewSubtitleLabel.text = @"Aurora Teal";

    UIView *trackBg = [[UIView alloc] init];
    trackBg.translatesAutoresizingMaskIntoConstraints = NO;
    trackBg.backgroundColor = [UIColor colorWithWhite:1.0f alpha:0.22f];
    trackBg.layer.cornerRadius = 1.5f;
    trackBg.clipsToBounds = YES;

    self.previewProgressFill = [[UIView alloc] init];
    self.previewProgressFill.translatesAutoresizingMaskIntoConstraints = NO;
    self.previewProgressFill.layer.cornerRadius = 1.5f;
    [trackBg addSubview:self.previewProgressFill];

    self.previewPlayBtn = [[UIView alloc] init];
    self.previewPlayBtn.translatesAutoresizingMaskIntoConstraints = NO;
    self.previewPlayBtn.layer.cornerRadius = 21.0f;

    self.previewPlayGlyph = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"pause.fill"]];
    self.previewPlayGlyph.translatesAutoresizingMaskIntoConstraints = NO;
    self.previewPlayGlyph.contentMode = UIViewContentModeScaleAspectFit;
    [self.previewPlayBtn addSubview:self.previewPlayGlyph];

    [cardHost addSubview:self.previewTitleLabel];
    [cardHost addSubview:self.previewSubtitleLabel];
    [cardHost addSubview:trackBg];
    [cardHost addSubview:self.previewPlayBtn];

    [NSLayoutConstraint activateConstraints:@[
        [self.previewPlayBtn.trailingAnchor constraintEqualToAnchor:self.previewCard.trailingAnchor constant:-14.0f],
        [self.previewPlayBtn.centerYAnchor constraintEqualToAnchor:self.previewCard.centerYAnchor],
        [self.previewPlayBtn.widthAnchor constraintEqualToConstant:42.0f],
        [self.previewPlayBtn.heightAnchor constraintEqualToConstant:42.0f],

        [self.previewPlayGlyph.centerXAnchor constraintEqualToAnchor:self.previewPlayBtn.centerXAnchor],
        [self.previewPlayGlyph.centerYAnchor constraintEqualToAnchor:self.previewPlayBtn.centerYAnchor],
        [self.previewPlayGlyph.widthAnchor constraintEqualToConstant:18.0f],
        [self.previewPlayGlyph.heightAnchor constraintEqualToConstant:18.0f],

        [self.previewTitleLabel.topAnchor constraintEqualToAnchor:self.previewCard.topAnchor constant:14.0f],
        [self.previewTitleLabel.leadingAnchor constraintEqualToAnchor:self.previewCard.leadingAnchor constant:14.0f],
        [self.previewTitleLabel.trailingAnchor constraintEqualToAnchor:self.previewPlayBtn.leadingAnchor constant:-12.0f],

        [self.previewSubtitleLabel.topAnchor constraintEqualToAnchor:self.previewTitleLabel.bottomAnchor constant:2.0f],
        [self.previewSubtitleLabel.leadingAnchor constraintEqualToAnchor:self.previewTitleLabel.leadingAnchor],
        [self.previewSubtitleLabel.trailingAnchor constraintEqualToAnchor:self.previewTitleLabel.trailingAnchor],

        [trackBg.topAnchor constraintEqualToAnchor:self.previewSubtitleLabel.bottomAnchor constant:12.0f],
        [trackBg.leadingAnchor constraintEqualToAnchor:self.previewTitleLabel.leadingAnchor],
        [trackBg.trailingAnchor constraintEqualToAnchor:self.previewPlayBtn.leadingAnchor constant:-16.0f],
        [trackBg.heightAnchor constraintEqualToConstant:3.0f],

        [self.previewProgressFill.leadingAnchor constraintEqualToAnchor:trackBg.leadingAnchor],
        [self.previewProgressFill.topAnchor constraintEqualToAnchor:trackBg.topAnchor],
        [self.previewProgressFill.bottomAnchor constraintEqualToAnchor:trackBg.bottomAnchor],
        [self.previewProgressFill.widthAnchor constraintEqualToAnchor:trackBg.widthAnchor multiplier:0.62f]
    ]];

    self.tableView.tableHeaderView = container;
}

- (void)updateLivePreviewWithPalette:(LGPalette *)palette dark:(BOOL)dark staticMode:(BOOL)staticMode {
    if (!palette) return;
    self.previewBg.darkStyle = dark;
    self.previewBg.staticMode = staticMode;
    [self.previewBg applyPalette:palette animated:YES];

    self.previewCard.darkStyle = dark;
    self.previewCard.staticMode = staticMode;
    self.previewCard.staticFill = palette.b2;

    self.previewTitleLabel.textColor = palette.tx;
    self.previewSubtitleLabel.textColor = palette.mu;
    self.previewSubtitleLabel.text = [NSString stringWithFormat:@"%@  •  %@",
                                      staticMode ? @"Static" : @"Liquid Glass",
                                      LGTheme.shared.ambient ? @"Ambient" : (palette.name ?: @"Preset")];

    self.previewProgressFill.backgroundColor = palette.a1;
    self.previewPlayBtn.backgroundColor = palette.a1;
    self.previewPlayGlyph.tintColor = palette.onAccent ?: UIColor.whiteColor;
    if (staticMode) {
        self.previewPlayBtn.layer.shadowOpacity = 0.0f;
    } else {
        self.previewPlayBtn.layer.shadowColor = palette.a1.CGColor;
        self.previewPlayBtn.layer.shadowOffset = CGSizeMake(0, 3);
        self.previewPlayBtn.layer.shadowRadius = 8.0f;
        self.previewPlayBtn.layer.shadowOpacity = 0.45f;
    }

    NSString *badge = LGTheme.shared.ambient ? @"  AMBIENT MODE  " : @"  PRESET MODE  ";
    self.previewModePill.text = badge;
    self.previewModePill.backgroundColor = LGTheme.shared.ambient
        ? palette.a1
        : [UIColor colorWithWhite:(dark ? 1.0f : 0.0f) alpha:0.16f];
    self.previewModePill.textColor = LGTheme.shared.ambient
        ? (palette.onAccent ?: UIColor.whiteColor)
        : (palette.tx ?: UIColor.whiteColor);
}

- (UISwitch *)makeSwitchWithOn:(BOOL)on action:(SEL)action {
    Class abc = NSClassFromString(@"ABCSwitch");
    UISwitch *sw = abc ? [[abc alloc] init] : [[UISwitch alloc] init];
    sw.onTintColor = LGTheme.shared.palette.a1;
    sw.on = on;
    [sw addTarget:self action:action forControlEvents:UIControlEventValueChanged];
    return sw;
}

#pragma mark - Table View Data Source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 4;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case 0: return @"APPEARANCE";
        case 1: return LGTheme.shared.staticMode ? @"STATIC LOOK PALETTES" : @"LIQUID GLASS PRESETS";
        case 2: return @"MOTION & ADVANCED";
        case 3: return @"AMBIENT DIAGNOSTICS";
        default: return nil;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 1 && LGTheme.shared.ambient) {
        return @"Ambient Mode is active (colours follow the playing artwork). Tap any preset to switch to Preset Mode.";
    }
    if (section == 3) {
        return @"Play a track with Ambient active, then tap Copy All inside Diagnostics to capture live device info.";
    }
    return nil;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case 0: return 3; // Style, Colour Source, Dark/Light
        case 1: return 1; // 2-column preset swatch grid
        case 2: return 3; // Fade full-width slider, Video Sampling, OLED Keyboard
        case 3: return 2; // Live Ambient Status + Diagnostics sheet
        default: return 0;
    }
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 1) {
        NSArray *names = LGTheme.shared.staticMode ? LGPalette.staticNames : LGPalette.presetNames;
        NSInteger rows = ((NSInteger)names.count + 1) / 2;
        return 12.0f + rows * 62.0f + (rows - 1) * 10.0f + 12.0f;
    }
    if (indexPath.section == 2 && indexPath.row == 0) {
        return 82.0f;
    }
    return UITableViewAutomaticDimension;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSString *cellId = [NSString stringWithFormat:@"LGCell_%ld_%ld", (long)indexPath.section, (long)indexPath.row];
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellId];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cellId];
    }

    cell.accessoryView = nil;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.imageView.image = nil;
    cell.textLabel.text = nil;
    cell.detailTextLabel.text = nil;
    cell.textLabel.numberOfLines = 0;
    cell.detailTextLabel.numberOfLines = 0;
    cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    for (UIView *sub in [cell.contentView.subviews copy]) {
        if (sub.tag == 9101 || sub.tag == 9102) [sub removeFromSuperview];
    }

    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    LGTheme *theme = LGTheme.shared;
    UIColor *accent = theme.palette.a1 ?: UIColor.systemBlueColor;
    UIColor *onAccent = theme.palette.onAccent ?: UIColor.whiteColor;

    if (indexPath.section == 0) {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"Style";
            cell.detailTextLabel.text = theme.staticMode ? @"Solid surface + soft glow" : @"Frosted Liquid Glass";
            UISegmentedControl *seg = [[UISegmentedControl alloc] initWithItems:@[@"Liquid", @"Static"]];
            seg.selectedSegmentIndex = theme.staticMode ? 1 : 0;
            seg.selectedSegmentTintColor = accent;
            [seg setTitleTextAttributes:@{NSForegroundColorAttributeName: onAccent} forState:UIControlStateSelected];
            [seg addTarget:self action:@selector(styleChanged:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = seg;
        } else if (indexPath.row == 1) {
            cell.textLabel.text = @"Colour Source";
            cell.detailTextLabel.text = theme.ambient ? @"Follows playing song art" : @"Uses selected preset below";
            UISegmentedControl *seg = [[UISegmentedControl alloc] initWithItems:@[@"Preset", @"Ambient"]];
            seg.selectedSegmentIndex = theme.ambient ? 1 : 0;
            seg.selectedSegmentTintColor = accent;
            [seg setTitleTextAttributes:@{NSForegroundColorAttributeName: onAccent} forState:UIControlStateSelected];
            [seg addTarget:self action:@selector(sourceChanged:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = seg;
        } else {
            cell.textLabel.text = @"Dark Mode";
            cell.detailTextLabel.text = @"Dark vs Light palette base";
            cell.accessoryView = [self makeSwitchWithOn:theme.dark action:@selector(darkToggled:)];
        }
    } else if (indexPath.section == 1) {
        [self populatePresetGridCell:cell];
    } else if (indexPath.section == 2) {
        if (indexPath.row == 0) {
            double fade = [d objectForKey:@"LG_fade"] ? [d doubleForKey:@"LG_fade"] : 1.8;
            UIView *wrap = [[UIView alloc] initWithFrame:CGRectZero];
            wrap.tag = 9102;
            wrap.translatesAutoresizingMaskIntoConstraints = NO;
            [cell.contentView addSubview:wrap];

            UILabel *lbl = [[UILabel alloc] init];
            lbl.translatesAutoresizingMaskIntoConstraints = NO;
            lbl.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
            lbl.text = [NSString stringWithFormat:@"Colour Fade Duration (%.1fs)", fade];

            UILabel *hint = [[UILabel alloc] init];
            hint.translatesAutoresizingMaskIntoConstraints = NO;
            hint.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
            hint.textColor = UIColor.secondaryLabelColor;
            hint.text = @"0.0s = instant";

            UISlider *slider = [[UISlider alloc] init];
            slider.translatesAutoresizingMaskIntoConstraints = NO;
            slider.minimumValue = 0.0f;
            slider.maximumValue = 4.0f;
            slider.value = (float)fade;
            slider.minimumTrackTintColor = accent;
            slider.thumbTintColor = theme.palette.tx ?: UIColor.whiteColor;
            slider.continuous = NO;
            [slider addTarget:self action:@selector(fadeChanged:) forControlEvents:UIControlEventValueChanged];

            [wrap addSubview:lbl];
            [wrap addSubview:hint];
            [wrap addSubview:slider];
            [NSLayoutConstraint activateConstraints:@[
                [wrap.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:16.0f],
                [wrap.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-16.0f],
                [wrap.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:10.0f],
                [wrap.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-10.0f],

                [lbl.leadingAnchor constraintEqualToAnchor:wrap.leadingAnchor],
                [lbl.topAnchor constraintEqualToAnchor:wrap.topAnchor],
                [hint.trailingAnchor constraintEqualToAnchor:wrap.trailingAnchor],
                [hint.centerYAnchor constraintEqualToAnchor:lbl.centerYAnchor],

                [slider.leadingAnchor constraintEqualToAnchor:wrap.leadingAnchor],
                [slider.trailingAnchor constraintEqualToAnchor:wrap.trailingAnchor],
                [slider.topAnchor constraintEqualToAnchor:lbl.bottomAnchor constant:8.0f],
                [slider.bottomAnchor constraintEqualToAnchor:wrap.bottomAnchor]
            ]];
        } else if (indexPath.row == 1) {
            cell.textLabel.text = @"Video Frame Sampling (Experimental)";
            cell.detailTextLabel.text = @"Sample live video frames every 1.5s when Ambient is on";
            cell.accessoryView = [self makeSwitchWithOn:[d boolForKey:@"LG_video"] action:@selector(videoToggled:)];
        } else {
            NSDictionary *dict = [d dictionaryForKey:@"YTMUltimate"];
            cell.textLabel.text = @"OLED Dark Keyboard";
            cell.detailTextLabel.text = @"Force pure black system keyboard";
            cell.accessoryView = [self makeSwitchWithOn:[dict[@"oledKeyboard"] boolValue] action:@selector(keyboardToggled:)];
        }
    } else if (indexPath.section == 3) {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"Ambient Engine Status";
            cell.detailTextLabel.text = theme.ambientStatus;
            cell.imageView.image = [UIImage systemImageNamed:@"waveform.circle.fill"];
            cell.imageView.tintColor = accent;
        } else {
            cell.textLabel.text = @"View & Copy Diagnostics (Ambient + Audio Probe)";
            cell.detailTextLabel.text = @"Inspect Now Playing hook, audio engine classes & view dumps";
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
            cell.imageView.image = [UIImage systemImageNamed:@"doc.text.magnifyingglass"];
            cell.imageView.tintColor = accent;
        }
    }

    return cell;
}

- (void)populatePresetGridCell:(UITableViewCell *)cell {
    LGTheme *theme = LGTheme.shared;
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    BOOL isStatic = theme.staticMode;
    NSArray<NSString *> *names = isStatic ? LGPalette.staticNames : LGPalette.presetNames;
    NSString *selectedName = isStatic ? ([d stringForKey:@"LG_static_theme"] ?: @"Cherry Red")
                                      : ([d stringForKey:@"LG_theme"] ?: @"Aurora Teal");

    UIStackView *rowsStack = [[UIStackView alloc] init];
    rowsStack.tag = 9101;
    rowsStack.axis = UILayoutConstraintAxisVertical;
    rowsStack.spacing = 10.0f;
    rowsStack.translatesAutoresizingMaskIntoConstraints = NO;
    [cell.contentView addSubview:rowsStack];

    [NSLayoutConstraint activateConstraints:@[
        [rowsStack.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:12.0f],
        [rowsStack.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-12.0f],
        [rowsStack.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:12.0f],
        [rowsStack.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-12.0f]
    ]];

    for (NSUInteger i = 0; i < names.count; i += 2) {
        UIStackView *row = [[UIStackView alloc] init];
        row.axis = UILayoutConstraintAxisHorizontal;
        row.distribution = UIStackViewDistributionFillEqually;
        row.spacing = 10.0f;
        [row.heightAnchor constraintEqualToConstant:62.0f].active = YES;

        for (NSUInteger col = 0; col < 2; col++) {
            NSUInteger idx = i + col;
            if (idx >= names.count) {
                UIView *spacer = [UIView new];
                spacer.backgroundColor = UIColor.clearColor;
                [row addArrangedSubview:spacer];
                continue;
            }
            NSString *name = names[idx];
            LGPalette *pal = isStatic ? [LGPalette staticNamed:name dark:theme.dark]
                                      : [LGPalette presetNamed:name dark:theme.dark];
            BOOL isActive = (!theme.ambient && [selectedName isEqualToString:name]);

            UIButton *tile = [UIButton buttonWithType:UIButtonTypeCustom];
            tile.tag = (NSInteger)(isStatic ? (2000 + idx) : (1000 + idx));
            tile.layer.cornerRadius = 14.0f;
            tile.clipsToBounds = YES;
            tile.backgroundColor = [pal.b2 colorWithAlphaComponent:0.95f] ?: UIColor.secondarySystemBackgroundColor;
            tile.layer.borderWidth = isActive ? 2.0f : 1.0f;
            tile.layer.borderColor = (isActive ? pal.a1 : [UIColor colorWithWhite:0.5f alpha:0.25f]).CGColor;
            tile.alpha = theme.ambient ? 0.58f : 1.0f;
            [tile addTarget:self action:@selector(presetTileTapped:) forControlEvents:UIControlEventTouchUpInside];

            UIImageView *swatch = [[UIImageView alloc] initWithImage:[self swatchImageWithPrimary:pal.a1 secondary:(isStatic ? pal.b1 : pal.a2)]];
            swatch.translatesAutoresizingMaskIntoConstraints = NO;
            swatch.userInteractionEnabled = NO;

            UILabel *title = [[UILabel alloc] init];
            title.translatesAutoresizingMaskIntoConstraints = NO;
            title.userInteractionEnabled = NO;
            title.text = name;
            title.font = [UIFont systemFontOfSize:13.0f weight:(isActive ? UIFontWeightBold : UIFontWeightSemibold)];
            title.textColor = pal.tx ?: UIColor.labelColor;
            title.numberOfLines = 2;

            [tile addSubview:swatch];
            [tile addSubview:title];
            [NSLayoutConstraint activateConstraints:@[
                [swatch.leadingAnchor constraintEqualToAnchor:tile.leadingAnchor constant:10.0f],
                [swatch.centerYAnchor constraintEqualToAnchor:tile.centerYAnchor],
                [swatch.widthAnchor constraintEqualToConstant:26.0f],
                [swatch.heightAnchor constraintEqualToConstant:26.0f],

                [title.leadingAnchor constraintEqualToAnchor:swatch.trailingAnchor constant:8.0f],
                [title.trailingAnchor constraintEqualToAnchor:tile.trailingAnchor constant:-26.0f],
                [title.centerYAnchor constraintEqualToAnchor:tile.centerYAnchor]
            ]];

            if (isActive) {
                UIImageView *check = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"checkmark.circle.fill"]];
                check.translatesAutoresizingMaskIntoConstraints = NO;
                check.userInteractionEnabled = NO;
                check.tintColor = pal.a1;
                [tile addSubview:check];
                [NSLayoutConstraint activateConstraints:@[
                    [check.trailingAnchor constraintEqualToAnchor:tile.trailingAnchor constant:-8.0f],
                    [check.centerYAnchor constraintEqualToAnchor:tile.centerYAnchor],
                    [check.widthAnchor constraintEqualToConstant:18.0f],
                    [check.heightAnchor constraintEqualToConstant:18.0f]
                ]];
            }

            [row addArrangedSubview:tile];
        }
        [rowsStack addArrangedSubview:row];
    }
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 3 && indexPath.row == 1) {
        [self showDiagnosticsSheet];
    }
}

- (void)showDiagnosticsSheet {
    NSMutableString *report = [NSMutableString stringWithString:LGBuildDiagnosticReport() ?: @""];
    NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    for (NSString *fname in @[@"lg_dump_home.txt", @"lg_dump_nowplaying.txt"]) {
        NSString *path = [docs stringByAppendingPathComponent:fname];
        NSString *content = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
        if (content.length) {
            NSRange rec = [content rangeOfString:@"=== [window recursiveDescription]"];
            NSString *head = (rec.location != NSNotFound) ? [content substringToIndex:rec.location] : content;
            [report appendFormat:@"\n%@\n", head];
        } else {
            [report appendFormat:@"\n[%@: not yet captured — open Home / Now Playing first]\n", fname];
        }
    }

    UIViewController *vc = [UIViewController new];
    vc.title = @"Diagnostics";
    UITextView *tv = [[UITextView alloc] initWithFrame:CGRectZero];
    tv.editable = NO;
    tv.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    tv.text = report;
    tv.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    vc.view = tv;

    vc.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Close"
                                                                            style:UIBarButtonItemStylePlain
                                                                           target:self
                                                                           action:@selector(closeDiagnostics)];
    vc.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Copy All"
                                                                             style:UIBarButtonItemStyleDone
                                                                            target:self
                                                                            action:@selector(copyDiagnostics)];
    objc_setAssociatedObject(self, &kDiagTextKey, report, OBJC_ASSOCIATION_COPY_NONATOMIC);
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    [self presentViewController:nav animated:YES completion:nil];
}

- (void)closeDiagnostics {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)copyDiagnostics {
    NSString *report = objc_getAssociatedObject(self, &kDiagTextKey);
    if (report) UIPasteboard.generalPasteboard.string = report;
}

#pragma mark - Actions

- (void)presetTileTapped:(UIButton *)sender {
    NSInteger raw = sender.tag;
    BOOL isStatic = (raw >= 2000);
    NSUInteger idx = (NSUInteger)(isStatic ? (raw - 2000) : (raw - 1000));
    NSArray<NSString *> *names = isStatic ? LGPalette.staticNames : LGPalette.presetNames;
    if (idx >= names.count) return;

    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    if (isStatic) {
        [d setObject:names[idx] forKey:@"LG_static_theme"];
        [d setObject:@"static" forKey:@"LG_style"];
        [d setBool:YES forKey:@"LG_static"];
    } else {
        [d setObject:names[idx] forKey:@"LG_theme"];
        [d setObject:@"liquid" forKey:@"LG_style"];
        [d setBool:NO forKey:@"LG_static"];
    }
    [d setBool:NO forKey:@"LG_ambient"];
    [d synchronize];
    [LGTheme.shared reload];
}

- (void)styleChanged:(UISegmentedControl *)sender {
    BOOL isStatic = (sender.selectedSegmentIndex == 1);
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    [d setObject:(isStatic ? @"static" : @"liquid") forKey:@"LG_style"];
    [d setBool:isStatic forKey:@"LG_static"];
    [d synchronize];
    [LGTheme.shared reload];
}

- (void)sourceChanged:(UISegmentedControl *)sender {
    BOOL isAmbient = (sender.selectedSegmentIndex == 1);
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    [d setBool:isAmbient forKey:@"LG_ambient"];
    [d synchronize];
    [LGTheme.shared reload];
}

- (void)darkToggled:(UISwitch *)sender {
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    [d setBool:sender.isOn forKey:@"LG_dark"];
    [d synchronize];
    [LGTheme.shared reload];
}

- (void)fadeChanged:(UISlider *)sender {
    double snapped = round(sender.value * 5.0) / 5.0;
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    [d setDouble:snapped forKey:@"LG_fade"];
    [d synchronize];
    [LGTheme.shared reload];
}

- (void)videoToggled:(UISwitch *)sender {
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    [d setBool:sender.isOn forKey:@"LG_video"];
    [d synchronize];
    [LGTheme.shared reload];
}

- (void)keyboardToggled:(UISwitch *)sender {
    NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithDictionary:[NSUserDefaults.standardUserDefaults dictionaryForKey:@"YTMUltimate"]];
    dict[@"oledKeyboard"] = @(sender.isOn);
    [NSUserDefaults.standardUserDefaults setObject:dict forKey:@"YTMUltimate"];
    [NSUserDefaults.standardUserDefaults synchronize];
}

- (UIImage *)swatchImageWithPrimary:(UIColor *)c1 secondary:(UIColor *)c2 {
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(26, 26)];
    return [r imageWithActions:^(__unused UIGraphicsImageRendererContext *ctx) {
        UIBezierPath *circle = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(1, 1, 24, 24)];
        [c2 ?: UIColor.darkGrayColor setFill];
        [circle fill];
        UIBezierPath *inner = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(5, 5, 16, 16)];
        [c1 ?: UIColor.whiteColor setFill];
        [inner fill];
    }];
}

@end
