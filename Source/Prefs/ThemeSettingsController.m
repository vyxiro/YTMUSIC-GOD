#import "ThemeSettingsController.h"
#import "../LiquidGlass.h"
#import "../Headers/ABCSwitch.h"
#import <objc/runtime.h>

extern NSString *LGBuildDiagnosticReport(void);
static char kDiagTextKey;

@interface ThemeSettingsController ()
@property (nonatomic, strong) id themeObserver;
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

    __weak typeof(self) weakSelf = self;
    self.themeObserver = LGObserveTheme(^(__unused LGPalette *palette, __unused BOOL dark, __unused BOOL staticMode) {
        [weakSelf.tableView reloadData];
    });
}

- (void)dealloc {
    if (self.themeObserver) {
        [[NSNotificationCenter defaultCenter] removeObserver:self.themeObserver];
    }
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
    return 5;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case 0: return @"AMBIENT STATUS & DIAGNOSTICS";
        case 1: return @"STYLE & ENGINE";
        case 2: return @"LIQUID GLASS PRESETS";
        case 3: return @"STATIC LOOK PALETTES";
        case 4: return @"EXTRAS";
        default: return nil;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    switch (section) {
        case 0: return @"Play 2 songs with Ambient Mode on, then open this page or tap Copy Diagnostics.";
        case 1: return @"Style (Liquid or Static) and Colour Source (Preset or Ambient) work independently.";
        default: return nil;
    }
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case 0: return 2; // Live Ambient Status + Diagnostics/Audio Probe viewer
        case 1: return 5; // Style, Ambient, Dark, Fade, Video
        case 2: return (NSInteger)LGPalette.presetNames.count;
        case 3: return (NSInteger)LGPalette.staticNames.count;
        case 4: return 1; // OLED keyboard
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
    cell.textLabel.numberOfLines = 0;
    cell.detailTextLabel.numberOfLines = 0;
    cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];

    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    LGTheme *theme = LGTheme.shared;
    UIColor *accent = theme.palette.a1;

    if (indexPath.section == 0) {
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
    } else if (indexPath.section == 1) {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"Style";
            cell.detailTextLabel.text = theme.staticMode ? @"Static (Flat solid + soft glow)" : @"Liquid Glass";
            UISegmentedControl *seg = [[UISegmentedControl alloc] initWithItems:@[@"Liquid", @"Static"]];
            seg.selectedSegmentIndex = theme.staticMode ? 1 : 0;
            seg.selectedSegmentTintColor = accent;
            [seg setTitleTextAttributes:@{NSForegroundColorAttributeName: theme.palette.onAccent ?: UIColor.whiteColor} forState:UIControlStateSelected];
            [seg addTarget:self action:@selector(styleChanged:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = seg;
        } else if (indexPath.row == 1) {
            cell.textLabel.text = @"Ambient Mode";
            cell.detailTextLabel.text = @"Derive colours from playing track";
            cell.accessoryView = [self makeSwitchWithOn:theme.ambient action:@selector(ambientToggled:)];
        } else if (indexPath.row == 2) {
            cell.textLabel.text = @"Dark Mode";
            cell.detailTextLabel.text = @"Dark vs Light colour palette";
            cell.accessoryView = [self makeSwitchWithOn:theme.dark action:@selector(darkToggled:)];
        } else if (indexPath.row == 3) {
            double fade = [d objectForKey:@"LG_fade"] ? [d doubleForKey:@"LG_fade"] : 1.8;
            cell.textLabel.text = [NSString stringWithFormat:@"Fade (%.1fs)", fade];
            cell.detailTextLabel.text = @"0.0s = instant";
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
            cell.textLabel.text = @"Video Sampling";
            cell.detailTextLabel.text = @"Sample video frames every 1.5s (exp)";
            cell.accessoryView = [self makeSwitchWithOn:[d boolForKey:@"LG_video"] action:@selector(videoToggled:)];
        }
    } else if (indexPath.section == 2) {
        NSString *name = LGPalette.presetNames[indexPath.row];
        LGPalette *pal = [LGPalette presetNamed:name dark:theme.dark];
        cell.textLabel.text = name;
        cell.detailTextLabel.text = theme.ambient ? @"Paused (Ambient active)" : @"Liquid Glass preset";
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
        NSString *current = [d stringForKey:@"LG_theme"] ?: @"Aurora Teal";
        if (!theme.staticMode && !theme.ambient && [current isEqualToString:name]) {
            cell.accessoryType = UITableViewCellAccessoryCheckmark;
            cell.tintColor = accent;
        }
        cell.imageView.image = [self swatchImageWithPrimary:pal.a1 secondary:pal.a2];
    } else if (indexPath.section == 3) {
        NSString *name = LGPalette.staticNames[indexPath.row];
        LGPalette *pal = [LGPalette staticNamed:name dark:theme.dark];
        cell.textLabel.text = name;
        cell.detailTextLabel.text = theme.ambient ? @"Paused (Ambient active)" : @"Static Look palette";
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
        NSString *current = [d stringForKey:@"LG_static_theme"] ?: @"Cherry Red";
        if (theme.staticMode && !theme.ambient && [current isEqualToString:name]) {
            cell.accessoryType = UITableViewCellAccessoryCheckmark;
            cell.tintColor = accent;
        }
        cell.imageView.image = [self swatchImageWithPrimary:pal.a1 secondary:pal.b1];
    } else if (indexPath.section == 4) {
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

    if (indexPath.section == 0 && indexPath.row == 1) {
        [self showDiagnosticsSheet];
        return;
    }

    if (indexPath.section == 2) {
        NSString *name = LGPalette.presetNames[indexPath.row];
        [d setObject:name forKey:@"LG_theme"];
        [d setObject:@"liquid" forKey:@"LG_style"];
        [d setBool:NO forKey:@"LG_static"];
        [d setBool:NO forKey:@"LG_ambient"];
        [d synchronize];
        [LGTheme.shared reload];
    } else if (indexPath.section == 3) {
        NSString *name = LGPalette.staticNames[indexPath.row];
        [d setObject:name forKey:@"LG_static_theme"];
        [d setObject:@"static" forKey:@"LG_style"];
        [d setBool:YES forKey:@"LG_static"];
        [d setBool:NO forKey:@"LG_ambient"];
        [d synchronize];
        [LGTheme.shared reload];
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
