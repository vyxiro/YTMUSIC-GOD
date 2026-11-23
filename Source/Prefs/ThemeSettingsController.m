#import "ThemeSettingsController.h"
#import "../ThemeManager.h"
#import "../Headers/ABCSwitch.h"

@interface ThemeSettingsController ()
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

    [[NSNotificationCenter defaultCenter] addObserver:self.tableView
                                             selector:@selector(reloadData)
                                                 name:YTMLiquidThemeDidChangeNotification
                                               object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self.tableView];
}

#pragma mark - Table View Data Source

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return UITableViewAutomaticDimension;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 3;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case 0: return @"LIQUID GLASS THEMES (APPLE MUSIC STYLE)";
        case 1: return @"STATIC PALETTES (FLAT REFERENCE LOOK)";
        case 2: return @"SURFACE & CONTRAST OPTIONS";
        default: return nil;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) {
        return @"Translucent, blurred, edge-lit glass with organic glowing background blobs.";
    } else if (section == 1) {
        return @"Flat solid colors with a single fixed glow behind album artwork (no blur).";
    }
    return nil;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case 0: return 6; // Ambient, Aurora, Nebula, Mars, Ion, Solar
        case 1: return 6; // Static toggle, Cherry, Midnight, Matcha, Lavender, Amber
        case 2: return 3; // Light mode switch, OLED Pitch Black, OLED Keyboard
        default: return 0;
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSString *cellId = [NSString stringWithFormat:@"ThemeCell_%ld_%ld", (long)indexPath.section, (long)indexPath.row];
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellId];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cellId];
    }

    cell.accessoryView = nil;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;

    ThemeManager *tm = [ThemeManager sharedManager];

    // SECTION 0: LIQUID GLASS
    if (indexPath.section == 0) {
        NSArray *liquidData = @[
            @{@"name": @"Ambient Mode", @"desc": @"Dynamic colors derived from currently playing track artwork", @"preset": @(YTMLiquidThemeAmbient), @"hex": @"#19D3B0"},
            @{@"name": @"Aurora Teal", @"desc": @"Cold polar glow; calm & focused (#06191C / #19D3B0)", @"preset": @(YTMLiquidThemeAuroraTeal), @"hex": @"#19D3B0"},
            @{@"name": @"Nebula Violet", @"desc": @"Deep-space purple (#110A24 / #9A7BFF / #FF5FB0)", @"preset": @(YTMLiquidThemeNebulaViolet), @"hex": @"#9A7BFF"},
            @{@"name": @"Mars Rust", @"desc": @"Warm red-orange dust (#1C0B07 / #FF6A3D / #FFB347)", @"preset": @(YTMLiquidThemeMarsRust), @"hex": @"#FF6A3D"},
            @{@"name": @"Ion Blue", @"desc": @"Electric thruster blue (#060D1F / #3D8BFF / #29E0FF)", @"preset": @(YTMLiquidThemeIonBlue), @"hex": @"#3D8BFF"},
            @{@"name": @"Solar Amber", @"desc": @"Sunlit gold-to-rose (#1A1204 / #FFC21F / #FF6F91)", @"preset": @(YTMLiquidThemeSolarAmber), @"hex": @"#FFC21F"}
        ];

        NSDictionary *item = liquidData[indexPath.row];
        cell.textLabel.text = item[@"name"];
        cell.detailTextLabel.text = item[@"desc"];
        cell.detailTextLabel.numberOfLines = 0;
        cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;

        NSInteger targetPreset = [item[@"preset"] integerValue];
        if (!tm.isStaticMode && tm.liquidTheme == targetPreset) {
            cell.accessoryType = UITableViewCellAccessoryCheckmark;
        }

        // Swatch icon
        UIView *swatch = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 22, 22)];
        swatch.layer.cornerRadius = 11;
        swatch.backgroundColor = [ThemeManager colorFromHexString:item[@"hex"]];
        cell.imageView.image = [self imageFromView:swatch];
    }
    // SECTION 1: STATIC LOOK
    else if (indexPath.section == 1) {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"Static Look (Flat Reference)";
            cell.detailTextLabel.text = @"Turns off floating blobs and glass blurs";

            ABCSwitch *sw = [[NSClassFromString(@"ABCSwitch") alloc] init];
            sw.onTintColor = [UIColor colorWithRed:30.0/255.0 green:150.0/255.0 blue:245.0/255.0 alpha:1.0];
            sw.on = tm.isStaticMode;
            [sw addTarget:self action:@selector(staticModeToggled:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
        } else {
            NSArray *staticData = @[
                @{@"name": @"Cherry Red", @"desc": @"Signature red with high contrast (#FF0000 / #121212)", @"preset": @(YTMLiquidThemeStaticCherry), @"hex": @"#FF0000"},
                @{@"name": @"Midnight Blue", @"desc": @"Electric cobalt & deep navy (#3B5BFF / #0B1230)", @"preset": @(YTMLiquidThemeStaticMidnight), @"hex": @"#3B5BFF"},
                @{@"name": @"Matcha Green", @"desc": @"Fresh forest green (#00C853 / #0D2E1E)", @"preset": @(YTMLiquidThemeStaticMatcha), @"hex": @"#00C853"},
                @{@"name": @"Lavender Haze", @"desc": @"Moody plum violet (#8A2BE2 / #1A0B28)", @"preset": @(YTMLiquidThemeStaticLavender), @"hex": @"#8A2BE2"},
                @{@"name": @"Amber Glow", @"desc": @"Warm espresso orange (#FF8C00 / #2A1A0F)", @"preset": @(YTMLiquidThemeStaticAmber), @"hex": @"#FF8C00"}
            ];

            NSDictionary *item = staticData[indexPath.row - 1];
            cell.textLabel.text = item[@"name"];
            cell.detailTextLabel.text = item[@"desc"];
            cell.detailTextLabel.numberOfLines = 0;
            cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;

            NSInteger targetPreset = [item[@"preset"] integerValue];
            if (tm.isStaticMode && tm.liquidTheme == targetPreset) {
                cell.accessoryType = UITableViewCellAccessoryCheckmark;
            }

            UIView *swatch = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 22, 22)];
            swatch.layer.cornerRadius = 11;
            swatch.backgroundColor = [ThemeManager colorFromHexString:item[@"hex"]];
            cell.imageView.image = [self imageFromView:swatch];
        }
    }
    // SECTION 2: SURFACE CONTROLS
    else if (indexPath.section == 2) {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"Light Mode Palette";
            cell.detailTextLabel.text = @"Switches translucent glass to airy light styling";

            ABCSwitch *sw = [[NSClassFromString(@"ABCSwitch") alloc] init];
            sw.onTintColor = [UIColor colorWithRed:30.0/255.0 green:150.0/255.0 blue:245.0/255.0 alpha:1.0];
            sw.on = tm.isLightMode;
            [sw addTarget:self action:@selector(lightModeToggled:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
        } else if (indexPath.row == 1) {
            cell.textLabel.text = @"True OLED Pitch Black (#000000)";
            cell.detailTextLabel.text = @"Overrides surface grays with absolute black";

            ABCSwitch *sw = [[NSClassFromString(@"ABCSwitch") alloc] init];
            sw.onTintColor = [UIColor colorWithRed:30.0/255.0 green:150.0/255.0 blue:245.0/255.0 alpha:1.0];
            sw.on = tm.oledBlackEnabled;
            [sw addTarget:self action:@selector(oledToggled:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
        } else if (indexPath.row == 2) {
            NSDictionary *dict = [[NSUserDefaults standardUserDefaults] dictionaryForKey:@"YTMUltimate"];
            cell.textLabel.text = LOC(@"OLED_DARK_KEYBOARD");
            cell.detailTextLabel.text = LOC(@"OLED_DARK_KEYBOARD_DESC");

            ABCSwitch *sw = [[NSClassFromString(@"ABCSwitch") alloc] init];
            sw.onTintColor = [UIColor colorWithRed:30.0/255.0 green:150.0/255.0 blue:245.0/255.0 alpha:1.0];
            sw.on = [dict[@"oledKeyboard"] boolValue];
            [sw addTarget:self action:@selector(keyboardToggled:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
        }
    }

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    ThemeManager *tm = [ThemeManager sharedManager];

    if (indexPath.section == 0) {
        tm.isStaticMode = NO;
        tm.liquidTheme = (YTMLiquidThemePreset)indexPath.row;
        [tm saveSettings];
        [self.tableView reloadData];
    } else if (indexPath.section == 1 && indexPath.row > 0) {
        tm.isStaticMode = YES;
        NSInteger staticPreset = (indexPath.row - 1) + YTMLiquidThemeStaticCherry;
        tm.liquidTheme = (YTMLiquidThemePreset)staticPreset;
        [tm saveSettings];
        [self.tableView reloadData];
    }
}

#pragma mark - Actions

- (void)staticModeToggled:(UISwitch *)sender {
    [ThemeManager sharedManager].isStaticMode = sender.isOn;
    [[ThemeManager sharedManager] saveSettings];
    [self.tableView reloadData];
}

- (void)lightModeToggled:(UISwitch *)sender {
    [ThemeManager sharedManager].isLightMode = sender.isOn;
    [[ThemeManager sharedManager] saveSettings];
    [self.tableView reloadData];
}

- (void)oledToggled:(UISwitch *)sender {
    [ThemeManager sharedManager].oledBlackEnabled = sender.isOn;
    [[ThemeManager sharedManager] saveSettings];
}

- (void)keyboardToggled:(UISwitch *)sender {
    NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithDictionary:[[NSUserDefaults standardUserDefaults] dictionaryForKey:@"YTMUltimate"]];
    dict[@"oledKeyboard"] = @(sender.isOn);
    [[NSUserDefaults standardUserDefaults] setObject:dict forKey:@"YTMUltimate"];
}

- (UIImage *)imageFromView:(UIView *)view {
    UIGraphicsBeginImageContextWithOptions(view.bounds.size, NO, 0.0);
    [view.layer renderInContext:UIGraphicsGetCurrentContext()];
    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return img;
}

@end
