#import "SettingsViewController.h"
#import "ThemeManager.h"
#import "AmbientView.h"
#import "AudioCrossfadeManager.h"

@interface SettingsViewController ()

@property (nonatomic, strong) UILabel *crossfadeDurationLabel;
@property (nonatomic, strong) UISlider *crossfadeSlider;
@property (nonatomic, strong) UILabel *ambientIntensityLabel;
@property (nonatomic, strong) UISlider *ambientIntensitySlider;
@property (nonatomic, strong) UIView *customHexSwatch;

@end

@implementation SettingsViewController

+ (UINavigationController *)presentedInNavigationController {
    SettingsViewController *vc = [[SettingsViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    nav.modalPresentationStyle = UIModalPresentationPageSheet;
    return nav;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"Apple Style Enhancer";
    self.navigationController.navigationBar.prefersLargeTitles = YES;

    UIBarButtonItem *doneBtn = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                                             target:self
                                                                             action:@selector(dismissSelf)];
    self.navigationItem.rightBarButtonItem = doneBtn;

    [self applyThemeColors];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applyThemeColors)
                                                 name:YTMThemeDidChangeNotification
                                               object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)dismissSelf {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)applyThemeColors {
    UIColor *bg = [[ThemeManager sharedManager] oledBackgroundColor];
    UIColor *accent = [[ThemeManager sharedManager] currentAccentColor];

    self.view.backgroundColor = bg;
    self.tableView.backgroundColor = bg;
    self.navigationController.navigationBar.tintColor = accent;

    if (@available(iOS 13.0, *)) {
        UINavigationBarAppearance *appearance = [[UINavigationBarAppearance alloc] init];
        [appearance configureWithOpaqueBackground];
        appearance.backgroundColor = bg;
        appearance.titleTextAttributes = @{NSForegroundColorAttributeName: [UIColor whiteColor]};
        appearance.largeTitleTextAttributes = @{NSForegroundColorAttributeName: [UIColor whiteColor]};
        self.navigationController.navigationBar.standardAppearance = appearance;
        self.navigationController.navigationBar.scrollEdgeAppearance = appearance;
    }

    [self.tableView reloadData];
}

#pragma mark - Table View Data Source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 5;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case 0: return @"AUDIO CROSSFADE (APPLE MUSIC STYLE)";
        case 1: return @"NETWORK & BUFFER OPTIMIZATION";
        case 2: return @"AMBIENT ARTWORK GLOW";
        case 3: return @"THEME & OLED ACCENTS";
        case 4: return @"ABOUT & CREDITS";
        default: return nil;
    }
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case 0: return 2; // Toggle + Duration slider
        case 1: return 1; // Aggressive buffer toggle
        case 2: return 2; // Ambient glow toggle + Intensity slider
        case 3: return 5; // OLED Black + 4 Presets
        case 4: return 2; // Version + Status
        default: return 0;
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSString *cellId = [NSString stringWithFormat:@"Cell_%ld_%ld", (long)indexPath.section, (long)indexPath.row];
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellId];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cellId];
    }

    cell.backgroundColor = [[ThemeManager sharedManager] oledSurfaceColor];
    cell.textLabel.textColor = [UIColor whiteColor];
    cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.accessoryView = nil;
    cell.accessoryType = UITableViewCellAccessoryNone;

    AudioCrossfadeManager *audioMgr = [AudioCrossfadeManager sharedInstance];
    ThemeManager *themeMgr = [ThemeManager sharedManager];

    // SECTION 0: CROSSFADE
    if (indexPath.section == 0) {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"Smooth Audio Crossfade";
            cell.detailTextLabel.text = @"Apple Music-style equal-power track overlap";
            UISwitch *sw = [[UISwitch alloc] init];
            sw.on = audioMgr.crossfadeEnabled;
            sw.onTintColor = [themeMgr currentAccentColor];
            [sw addTarget:self action:@selector(crossfadeToggled:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
        } else if (indexPath.row == 1) {
            cell.textLabel.text = [NSString stringWithFormat:@"Crossfade Duration: %.1f s", audioMgr.crossfadeDuration];
            self.crossfadeDurationLabel = cell.textLabel;

            UISlider *slider = [[UISlider alloc] initWithFrame:CGRectMake(0, 0, 150, 30)];
            slider.minimumValue = 1.0f;
            slider.maximumValue = 12.0f;
            slider.value = audioMgr.crossfadeDuration;
            slider.tintColor = [themeMgr currentAccentColor];
            [slider addTarget:self action:@selector(crossfadeSliderChanged:) forControlEvents:UIControlEventValueChanged];
            self.crossfadeSlider = slider;
            cell.accessoryView = slider;
        }
    }
    // SECTION 1: BUFFER OPTIMIZATION
    else if (indexPath.section == 1) {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"Aggressive 120s Read-Ahead Buffer";
            cell.detailTextLabel.text = @"Pre-caches queue tracks for zero-stutter cellular playback";
            UISwitch *sw = [[UISwitch alloc] init];
            sw.on = audioMgr.lowNetworkBufferingEnabled;
            sw.onTintColor = [themeMgr currentAccentColor];
            [sw addTarget:self action:@selector(bufferToggled:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
        }
    }
    // SECTION 2: AMBIENT GLOW
    else if (indexPath.section == 2) {
        NSDictionary *ambientPrefs = [[NSUserDefaults standardUserDefaults] dictionaryForKey:@"YTMAppleStyleEnhancer_AmbientPrefs"];
        BOOL ambientOn = ambientPrefs[@"ambientGlowEnabled"] ? [ambientPrefs[@"ambientGlowEnabled"] boolValue] : YES;
        float intensity = ambientPrefs[@"glowIntensity"] ? [ambientPrefs[@"glowIntensity"] floatValue] : 0.65f;

        if (indexPath.row == 0) {
            cell.textLabel.text = @"Dynamic Album-Art Ambient Glow";
            cell.detailTextLabel.text = @"Extracts artwork colors into animated background glow";
            UISwitch *sw = [[UISwitch alloc] init];
            sw.on = ambientOn;
            sw.onTintColor = [themeMgr currentAccentColor];
            [sw addTarget:self action:@selector(ambientToggled:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
        } else if (indexPath.row == 1) {
            cell.textLabel.text = [NSString stringWithFormat:@"Glow Intensity: %d%%", (int)(intensity * 100)];
            self.ambientIntensityLabel = cell.textLabel;

            UISlider *slider = [[UISlider alloc] initWithFrame:CGRectMake(0, 0, 150, 30)];
            slider.minimumValue = 0.2f;
            slider.maximumValue = 1.0f;
            slider.value = intensity;
            slider.tintColor = [themeMgr currentAccentColor];
            [slider addTarget:self action:@selector(ambientSliderChanged:) forControlEvents:UIControlEventValueChanged];
            self.ambientIntensitySlider = slider;
            cell.accessoryView = slider;
        }
    }
    // SECTION 3: THEMES & ACCENTS
    else if (indexPath.section == 3) {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"True OLED Pitch Black (#000000)";
            cell.detailTextLabel.text = @"Eliminates dark gray palettes across all views";
            UISwitch *sw = [[UISwitch alloc] init];
            sw.on = themeMgr.oledBlackEnabled;
            sw.onTintColor = [themeMgr currentAccentColor];
            [sw addTarget:self action:@selector(oledToggled:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
        } else if (indexPath.row == 1) {
            cell.textLabel.text = @"OLED Cyber Yellow (#FFD60A)";
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
            cell.accessoryType = (themeMgr.themePreset == YTMThemePresetOLEDYellow) ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
            cell.tintColor = [UIColor colorWithRed:1.0f green:0.839f blue:0.039f alpha:1.0f];
        } else if (indexPath.row == 2) {
            cell.textLabel.text = @"OLED Emerald Green (#30D158)";
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
            cell.accessoryType = (themeMgr.themePreset == YTMThemePresetOLEDGreen) ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
            cell.tintColor = [UIColor colorWithRed:0.188f green:0.820f blue:0.345f alpha:1.0f];
        } else if (indexPath.row == 3) {
            cell.textLabel.text = @"Default YouTube Music Red";
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
            cell.accessoryType = (themeMgr.themePreset == YTMThemePresetDefaultRed) ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
            cell.tintColor = [UIColor colorWithRed:1.0f green:0.0f blue:0.0f alpha:1.0f];
        } else if (indexPath.row == 4) {
            cell.textLabel.text = [NSString stringWithFormat:@"Custom Hex Accent: %@", themeMgr.customHexColor ?: @"#FFD60A"];
            cell.detailTextLabel.text = @"Tap to enter custom RGB hex color";
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
            cell.accessoryType = (themeMgr.themePreset == YTMThemePresetCustomHex) ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
            
            UIView *swatch = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 24, 24)];
            swatch.layer.cornerRadius = 12;
            swatch.layer.borderWidth = 1.5;
            swatch.layer.borderColor = [UIColor whiteColor].CGColor;
            swatch.backgroundColor = [ThemeManager colorFromHexString:themeMgr.customHexColor] ?: [themeMgr currentAccentColor];
            cell.accessoryView = swatch;
        }
    }
    // SECTION 4: ABOUT
    else if (indexPath.section == 4) {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"YTMusicAppleStyleEnhancer";
            cell.detailTextLabel.text = @"Version 1.0.0 • Loaded via Sideloadly Injection";
        } else if (indexPath.row == 1) {
            cell.textLabel.text = @"Crossfade Engine";
            cell.detailTextLabel.text = @"Equal-Power CADisplayLink 120Hz interpolation";
        }
    }

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    ThemeManager *themeMgr = [ThemeManager sharedManager];

    if (indexPath.section == 3) {
        if (indexPath.row == 1) {
            themeMgr.themePreset = YTMThemePresetOLEDYellow;
            [themeMgr saveSettings];
        } else if (indexPath.row == 2) {
            themeMgr.themePreset = YTMThemePresetOLEDGreen;
            [themeMgr saveSettings];
        } else if (indexPath.row == 3) {
            themeMgr.themePreset = YTMThemePresetDefaultRed;
            [themeMgr saveSettings];
        } else if (indexPath.row == 4) {
            [self promptCustomHexPicker];
        }
    }
}

#pragma mark - Actions

- (void)crossfadeToggled:(UISwitch *)sender {
    [AudioCrossfadeManager sharedInstance].crossfadeEnabled = sender.isOn;
    [[AudioCrossfadeManager sharedInstance] savePreferences];
}

- (void)crossfadeSliderChanged:(UISlider *)sender {
    float rounded = roundf(sender.value * 2.0f) / 2.0f; // 0.5s increments
    [AudioCrossfadeManager sharedInstance].crossfadeDuration = rounded;
    [[AudioCrossfadeManager sharedInstance] savePreferences];
    self.crossfadeDurationLabel.text = [NSString stringWithFormat:@"Crossfade Duration: %.1f s", rounded];
}

- (void)bufferToggled:(UISwitch *)sender {
    [AudioCrossfadeManager sharedInstance].lowNetworkBufferingEnabled = sender.isOn;
    [[AudioCrossfadeManager sharedInstance] savePreferences];
}

- (void)ambientToggled:(UISwitch *)sender {
    NSMutableDictionary *prefs = [NSMutableDictionary dictionaryWithDictionary:[[NSUserDefaults standardUserDefaults] dictionaryForKey:@"YTMAppleStyleEnhancer_AmbientPrefs"]];
    prefs[@"ambientGlowEnabled"] = @(sender.isOn);
    [[NSUserDefaults standardUserDefaults] setObject:prefs forKey:@"YTMAppleStyleEnhancer_AmbientPrefs"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)ambientSliderChanged:(UISlider *)sender {
    NSMutableDictionary *prefs = [NSMutableDictionary dictionaryWithDictionary:[[NSUserDefaults standardUserDefaults] dictionaryForKey:@"YTMAppleStyleEnhancer_AmbientPrefs"]];
    prefs[@"glowIntensity"] = @(sender.value);
    [[NSUserDefaults standardUserDefaults] setObject:prefs forKey:@"YTMAppleStyleEnhancer_AmbientPrefs"];
    [[NSUserDefaults standardUserDefaults] synchronize];
    self.ambientIntensityLabel.text = [NSString stringWithFormat:@"Glow Intensity: %d%%", (int)(sender.value * 100)];
}

- (void)oledToggled:(UISwitch *)sender {
    [ThemeManager sharedManager].oledBlackEnabled = sender.isOn;
    [[ThemeManager sharedManager] saveSettings];
}

- (void)promptCustomHexPicker {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Custom Accent Hex"
                                                                   message:@"Enter any hex code (e.g. #FFD60A, #30D158, #00E5FF, #BF5AF2):"
                                                            preferredStyle:UIAlertControllerStyleAlert];

    [alert addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.placeholder = @"#FFD60A";
        textField.text = [ThemeManager sharedManager].customHexColor;
        textField.autocapitalizationType = UITextAutocapitalizationTypeAllCharacters;
    }];

    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];

    [alert addAction:[UIAlertAction actionWithTitle:@"Apply" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        NSString *text = alert.textFields.firstObject.text;
        if (text.length > 0) {
            if (![text hasPrefix:@"#"]) {
                text = [@"#" stringByAppendingString:text];
            }
            [ThemeManager sharedManager].customHexColor = text;
            [ThemeManager sharedManager].themePreset = YTMThemePresetCustomHex;
            [[ThemeManager sharedManager] saveSettings];
        }
    }]];

    [self presentViewController:alert animated:YES completion:nil];
}

@end
