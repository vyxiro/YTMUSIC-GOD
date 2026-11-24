#import "YTMAudioStudioSettingsController.h"
#import "../AudioStudio/YTMAudioStudioManager.h"
#import "YTMHearingCalibrationViewController.h"

@interface YTMAutoEqTextController : UIViewController
@property (nonatomic, copy) void (^importHandler)(NSString *text);
@end

@implementation YTMAutoEqTextController {
    UITextView *_textView;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.title = @"Paste AutoEq Text";
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancel)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Import" style:UIBarButtonItemStyleDone target:self action:@selector(importText)];
    _textView = [[UITextView alloc] initWithFrame:CGRectZero];
    _textView.translatesAutoresizingMaskIntoConstraints = NO;
    _textView.font = [UIFont monospacedSystemFontOfSize:14 weight:UIFontWeightRegular];
    _textView.layer.borderColor = UIColor.separatorColor.CGColor;
    _textView.layer.borderWidth = 1.0;
    _textView.layer.cornerRadius = 10.0;
    _textView.text = UIPasteboard.generalPasteboard.string ?: @"";
    [self.view addSubview:_textView];
    [NSLayoutConstraint activateConstraints:@[
        [_textView.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:16],
        [_textView.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-16],
        [_textView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:16],
        [_textView.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-16]
    ]];
}
- (void)cancel { [self dismissViewControllerAnimated:YES completion:nil]; }
- (void)importText { if (self.importHandler) self.importHandler(_textView.text ?: @""); }
@end

@interface YTMAudioStudioSettingsController ()
@property (nonatomic, strong) YTMAudioStudioManager *manager;
@end

@implementation YTMAudioStudioSettingsController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Audio Studio & Hearing EQ";
    self.manager = YTMAudioStudioManager.sharedManager;
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    [self.view addSubview:self.tableView];
    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 5; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) { case 0: return 2; case 1: return 2; case 2: return 10; case 3: return 1; case 4: return 5; default: return 0; }
}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    NSArray *titles = @[@"MASTER SWITCH & STATUS", @"PRESETS & AUTOEQ", @"10-BAND PARAMETRIC EQ", @"HEARING CALIBRATION", @"ADAPTIVE LOUDNESS & ROUTING"];
    return titles[section];
}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) return @"The EQ and limiter settings are prepared here. YouTube Music's private renderer must be connected to this audio graph for these settings to affect streamed playback.";
    if (section == 3) return @"The test records a relative headphone threshold in dBFS. iPhone output level is not calibrated to dB SPL, so this is not a clinical hearing test.";
    return nil;
}
- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath { return indexPath.section == 2 ? 82.0 : UITableViewAutomaticDimension; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSString *identifier = [NSString stringWithFormat:@"AudioStudio-%ld-%ld", (long)indexPath.section, (long)indexPath.row];
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:identifier];
    cell.accessoryView = nil; cell.accessoryType = UITableViewCellAccessoryNone; cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.detailTextLabel.numberOfLines = 0;
    if (indexPath.section == 0 && indexPath.row == 0) {
        cell.textLabel.text = @"Enable Audio Studio";
        UISwitch *toggle = [[UISwitch alloc] init]; toggle.on = self.manager.isEnabled;
        [toggle addTarget:self action:@selector(enabledChanged:) forControlEvents:UIControlEventValueChanged]; cell.accessoryView = toggle;
    } else if (indexPath.section == 0) {
        cell.textLabel.text = [NSString stringWithFormat:@"Preamp: %.1f dB", self.manager.preampOffsetDB];
        cell.detailTextLabel.text = self.manager.limiterEnabled ? @"Limiter configured: −1 dB threshold · 0.5 dB headroom" : @"Limiter off";
        cell.imageView.image = [UIImage systemImageNamed:@"waveform"];
    } else if (indexPath.section == 1 && indexPath.row == 0) {
        cell.textLabel.text = @"Preset"; cell.detailTextLabel.text = self.manager.selectedPresetName;
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator; cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    } else if (indexPath.section == 1) {
        cell.textLabel.text = @"Paste AutoEq Text"; cell.detailTextLabel.text = @"Import EqualizerAPO / AutoEq filter blocks";
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator; cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    } else if (indexPath.section == 2) {
        NSUInteger band = (NSUInteger)indexPath.row;
        cell.textLabel.text = [NSString stringWithFormat:@"Band %lu · %.0f Hz · Q %.2f", (unsigned long)band + 1, [self.manager frequencyForBand:band], [self.manager qForBand:band]];
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%+.1f dB%@", [self.manager gainForBand:band], [self.manager isBandBypassed:band] ? @" · Bypassed" : @""];
        UISlider *slider = [[UISlider alloc] initWithFrame:CGRectMake(0, 0, MAX(240.0, self.view.bounds.size.width - 110.0), 30)];
        slider.minimumValue = -15.0f; slider.maximumValue = 15.0f; slider.value = [self.manager gainForBand:band]; slider.tag = band;
        [slider addTarget:self action:@selector(gainChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = slider; cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    } else if (indexPath.section == 3) {
        cell.textLabel.text = @"Start 60-Second Hearing Test";
        cell.detailTextLabel.text = @"Six frequencies, one at a time";
        cell.imageView.image = [UIImage systemImageNamed:@"ear"];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator; cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    } else if (indexPath.section == 4 && indexPath.row == 0) {
        cell.textLabel.text = @"Adaptive Loudness";
        cell.detailTextLabel.text = @"Low-volume bass and treble compensation";
        UISwitch *toggle = [[UISwitch alloc] init]; toggle.on = self.manager.adaptiveLoudnessEnabled;
        [toggle addTarget:self action:@selector(adaptiveChanged:) forControlEvents:UIControlEventValueChanged]; cell.accessoryView = toggle;
    } else if (indexPath.section == 4) {
        NSArray *routes = self.manager.outputRouteNames;
        NSString *route = routes[(NSUInteger)indexPath.row - 1];
        cell.textLabel.text = route;
        cell.detailTextLabel.text = [self.manager presetNameForRoute:route] ?: @"No automatic preset";
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator; cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    }
    return cell;
}

- (void)enabledChanged:(UISwitch *)sender { self.manager.enabled = sender.isOn; [self.manager saveSettings]; [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:0] withRowAnimation:UITableViewRowAnimationNone]; }
- (void)adaptiveChanged:(UISwitch *)sender { self.manager.adaptiveLoudnessEnabled = sender.isOn; [self.manager saveSettings]; }
- (void)gainChanged:(UISlider *)sender {
    NSUInteger band = (NSUInteger)sender.tag;
    [self.manager setGain:sender.value forBand:band];
    NSIndexPath *path = [NSIndexPath indexPathForRow:(NSInteger)band inSection:2];
    UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:path];
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%+.1f dB%@", [self.manager gainForBand:band], [self.manager isBandBypassed:band] ? @" · Bypassed" : @""];
    NSIndexPath *status = [NSIndexPath indexPathForRow:1 inSection:0];
    [self.manager saveSettings];
    [self.tableView reloadRowsAtIndexPaths:@[status] withRowAnimation:UITableViewRowAnimationNone];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 1 && indexPath.row == 0) { [self showPresetPickerForRoute:nil]; return; }
    if (indexPath.section == 1 && indexPath.row == 1) { [self showAutoEqEditor]; return; }
    if (indexPath.section == 2) {
        NSUInteger band = (NSUInteger)indexPath.row;
        [self.manager setBandBypassed:![self.manager isBandBypassed:band] forBand:band];
        [self.manager saveSettings]; [self.tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone]; return;
    }
    if (indexPath.section == 3) {
        YTMHearingCalibrationViewController *controller = [[YTMHearingCalibrationViewController alloc] init];
        [self.navigationController pushViewController:controller animated:YES]; return;
    }
    if (indexPath.section == 4 && indexPath.row > 0) [self showPresetPickerForRoute:self.manager.outputRouteNames[(NSUInteger)indexPath.row - 1]];
}

- (void)showPresetPickerForRoute:(nullable NSString *)route {
    NSString *title = route ? [NSString stringWithFormat:@"Preset for %@", route] : @"Choose EQ Preset";
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSString *name in self.manager.presetNames) {
        [alert addAction:[UIAlertAction actionWithTitle:name style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
            if (route) [self.manager setPresetName:name forRoute:route]; else [self.manager selectPresetNamed:name];
            [self.tableView reloadData];
        }]];
    }
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    alert.popoverPresentationController.sourceView = self.view;
    alert.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds), 1, 1);
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showAutoEqEditor {
    YTMAutoEqTextController *editor = [[YTMAutoEqTextController alloc] init];
    editor.importHandler = ^(NSString *text) {
        NSError *error = nil;
        if ([self.manager importAutoEqProfileFromText:text error:&error]) {
            [editor dismissViewControllerAnimated:YES completion:^{ [self.tableView reloadData]; }];
        } else {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Import Failed" message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [editor presentViewController:alert animated:YES completion:nil];
        }
    };
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:editor];
    nav.modalPresentationStyle = UIModalPresentationFormSheet;
    [self presentViewController:nav animated:YES completion:nil];
}

@end
