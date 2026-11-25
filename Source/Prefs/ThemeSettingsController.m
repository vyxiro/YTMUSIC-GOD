#import "ThemeSettingsController.h"
#import "../LiquidGlass.h"
#import "../Headers/ABCSwitch.h"

@interface ThemeSettingsController ()
@property (nonatomic, strong) UILabel *fadeValueLabel;
@end

@implementation ThemeSettingsController

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"Liquid Glass Themes";
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

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(paletteDidChange)
                                                 name:LGPaletteDidChangeNotification
                                               object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)paletteDidChange {
    [self.tableView reloadData];
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

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return UITableViewAutomaticDimension;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 4;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case 0: return @"STYLE & AMBIENT ENGINE";
        case 1: return @"LIQUID GLASS PRESETS";
        case 2: return @"STATIC LOOK PALETTES";
        case 3: return @"EXTRAS";
        default: return nil;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    switch (section) {
        case 0: return @"Style (Liquid or Static) and Colour Source (Preset or Ambient) work independently.";
        case 1: return @"Used when Style is Liquid Glass and Ambient Mode is off.";
        case 2: return @"Flat solid colours with a soft centre glow (no blur or glass).";
        default: return nil;
    }
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case 0: return 5; // Style, Ambient, Dark, Fade, Video
        case 1: return (NSInteger)LGPalette.presetNames.count;
        case 2: return (NSInteger)LGPalette.staticNames.count;
        case 3: return 1; // OLED keyboard
        default: return 0;
    }
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
    cell.detailTextLabel.numberOfLines = 0;
    cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];

    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    LGTheme *theme = LGTheme.shared;
    UIColor *accent = theme.palette.a1;

    if (indexPath.section == 0) {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"Style";
            cell.detailTextLabel.text = theme.staticMode ? @"Static (Flat solid + soft glow)" : @"Liquid Glass (Gradient, blobs & blur)";
            UISegmentedControl *seg = [[UISegmentedControl alloc] initWithItems:@[@"Liquid", @"Static"]];
            seg.selectedSegmentIndex = theme.staticMode ? 1 : 0;
            seg.selectedSegmentTintColor = accent;
            [seg setTitleTextAttributes:@{NSForegroundColorAttributeName: theme.palette.onAccent ?: UIColor.whiteColor} forState:UIControlStateSelected];
            [seg addTarget:self action:@selector(styleChanged:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = seg;
        } else if (indexPath.row == 1) {
            cell.textLabel.text = @"Ambient Mode";
            cell.detailTextLabel.text = @"Derive colours dynamically from playing song artwork";
            cell.accessoryView = [self makeSwitchWithOn:theme.ambient action:@selector(ambientToggled:)];
        } else if (indexPath.row == 2) {
            cell.textLabel.text = @"Dark Mode";
            cell.detailTextLabel.text = @"Switch between Dark and Light colour variants";
            cell.accessoryView = [self makeSwitchWithOn:theme.dark action:@selector(darkToggled:)];
        } else if (indexPath.row == 3) {
            double fade = [d objectForKey:@"LG_fade"] ? [d doubleForKey:@"LG_fade"] : 1.8;
            cell.textLabel.text = [NSString stringWithFormat:@"Colour Fade (%.1fs)", fade];
            cell.detailTextLabel.text = @"0.0s = instant transition";
            UISlider *slider = [[UISlider alloc] initWithFrame:CGRectMake(0, 0, 140, 32)];
            slider.minimumValue = 0.0f;
            slider.maximumValue = 4.0f;
            slider.value = (float)fade;
            slider.minimumTrackTintColor = accent;
            slider.thumbTintColor = theme.palette.tx;
            slider.continuous = NO;
            [slider addTarget:self action:@selector(fadeChanged:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = slider;
        } else if (indexPath.row == 4) {
            cell.textLabel.text = @"Video Frame Sampling (Experimental)";
            cell.detailTextLabel.text = @"Sample live video frames in Video mode (~1.5s)";
            cell.accessoryView = [self makeSwitchWithOn:[d boolForKey:@"LG_video"] action:@selector(videoToggled:)];
        }
    } else if (indexPath.section == 1) {
        NSArray<NSString *> *names = LGPalette.presetNames;
        NSString *name = names[indexPath.row];
        LGPalette *pal = [LGPalette presetNamed:name dark:theme.dark];
        cell.textLabel.text = name;
        cell.detailTextLabel.text = theme.ambient ? @"Preset paused while Ambient Mode is active" : @"Liquid Glass preset";
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;

        NSString *current = [d stringForKey:@"LG_theme"] ?: @"Aurora Teal";
        if (!theme.staticMode && !theme.ambient && [current isEqualToString:name]) {
            cell.accessoryType = UITableViewCellAccessoryCheckmark;
            cell.tintColor = accent;
        }
        cell.imageView.image = [self swatchImageWithPrimary:pal.a1 secondary:pal.a2];
    } else if (indexPath.section == 2) {
        NSArray<NSString *> *names = LGPalette.staticNames;
        NSString *name = names[indexPath.row];
        LGPalette *pal = [LGPalette staticNamed:name dark:theme.dark];
        cell.textLabel.text = name;
        cell.detailTextLabel.text = theme.ambient ? @"Palette paused while Ambient Mode is active" : @"Static Look palette";
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;

        NSString *current = [d stringForKey:@"LG_static_theme"] ?: @"Cherry Red";
        if (theme.staticMode && !theme.ambient && [current isEqualToString:name]) {
            cell.accessoryType = UITableViewCellAccessoryCheckmark;
            cell.tintColor = accent;
        }
        cell.imageView.image = [self swatchImageWithPrimary:pal.a1 secondary:pal.b1];
    } else if (indexPath.section == 3) {
        NSDictionary *dict = [d dictionaryForKey:@"YTMUltimate"];
        cell.textLabel.text = @"OLED Dark Keyboard";
        cell.detailTextLabel.text = @"Force black system keyboard";
        cell.accessoryView = [self makeSwitchWithOn:[dict[@"oledKeyboard"] boolValue] action:@selector(keyboardToggled:)];
    }

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;

    if (indexPath.section == 1) {
        NSString *name = LGPalette.presetNames[indexPath.row];
        [d setObject:name forKey:@"LG_theme"];
        [d setObject:@"liquid" forKey:@"LG_style"];
        [d setBool:NO forKey:@"LG_static"];
        [d setBool:NO forKey:@"LG_ambient"];
        [d synchronize];
        [LGTheme.shared reload];
    } else if (indexPath.section == 2) {
        NSString *name = LGPalette.staticNames[indexPath.row];
        [d setObject:name forKey:@"LG_static_theme"];
        [d setObject:@"static" forKey:@"LG_style"];
        [d setBool:YES forKey:@"LG_static"];
        [d setBool:NO forKey:@"LG_ambient"];
        [d synchronize];
        [LGTheme.shared reload];
    }
}

#pragma mark - Actions

- (void)styleChanged:(UISegmentedControl *)sender {
    BOOL isStatic = (sender.selectedSegmentIndex == 1);
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    [d setObject:(isStatic ? @"static" : @"liquid") forKey:@"LG_style"];
    [d setBool:isStatic forKey:@"LG_static"];
    [d synchronize];
    [LGTheme.shared reload];
}

- (void)ambientToggled:(UISwitch *)sender {
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    [d setBool:sender.isOn forKey:@"LG_ambient"];
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
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(24, 24)];
    return [r imageWithActions:^(__unused UIGraphicsImageRendererContext *ctx) {
        UIBezierPath *circle = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(1, 1, 22, 22)];
        [c2 ?: UIColor.darkGrayColor setFill];
        [circle fill];
        UIBezierPath *inner = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(4, 4, 16, 16)];
        [c1 ?: UIColor.whiteColor setFill];
        [inner fill];
    }];
}

@end
