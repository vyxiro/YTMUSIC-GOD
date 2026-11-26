#import "AppleAudioSettingsController.h"
#import "../LGCrossfade.h"
#import "../LiquidGlass.h"

extern NSString *YTMObservedAudioBackend(void);

@interface AppleAudioSettingsController ()
@property (nonatomic, strong) UILabel *crossfadeDurationLabel;
@property (nonatomic, strong) UILabel *crossfadeStatusLabel;
@property (nonatomic, strong) UISlider *crossfadeSlider;
@property (nonatomic, strong) UILabel *cacheSizeLabel;
@property (nonatomic, strong) NSTimer *statusTimer;
@end

@implementation AppleAudioSettingsController

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"Apple Audio & Network";
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
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self refreshCrossfadeStatus];
    [self.statusTimer invalidate];
    __weak typeof(self) w = self;
    self.statusTimer = [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(__unused NSTimer *t) {
        [w refreshCrossfadeStatus];
    }];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self.statusTimer invalidate];
    self.statusTimer = nil;
}

- (void)dealloc {
    [self.statusTimer invalidate];
}

- (void)refreshCrossfadeStatus {
    if (self.crossfadeStatusLabel) {
        self.crossfadeStatusLabel.text = [NSString stringWithFormat:@"%@\n%@", LGCrossfade.shared.status, YTMObservedAudioBackend()];
    }
}

#pragma mark - Table View Data Source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 3;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case 0: return @"SMOOTH AUDIO CROSSFADE";
        case 1: return @"LOW-NETWORK STREAMING & BUFFER";
        case 2: return @"PREFETCH CACHE";
        default: return nil;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) {
        return @"Applies an equal-power mathematical volume fade to blend track transitions without silence.";
    } else if (section == 1) {
        return @"Expands read-ahead streaming window to 120 seconds and pre-caches the next queue tracks as soon as the song passes 15% playback.";
    }
    return nil;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case 0: return 4; // Status, Switch, Slider, Gapless switch
        case 1: return 2; // Deep buffer switch, Prefetch switch
        case 2: return 1; // Clear cache
        default: return 0;
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSString *cellId = [NSString stringWithFormat:@"AppleCell_%ld_%ld", (long)indexPath.section, (long)indexPath.row];
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellId];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cellId];
    }

    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.accessoryView = nil;
    cell.accessoryType = UITableViewCellAccessoryNone;

    AudioCrossfadeManager *audioMgr = [AudioCrossfadeManager sharedInstance];
    NetworkBufferOptimizer *netMgr = [NetworkBufferOptimizer sharedInstance];
    UIColor *accent = LGTheme.shared.palette.a1 ?: [UIColor colorWithRed:30.0/255.0 green:150.0/255.0 blue:245.0/255.0 alpha:1.0];

    // SECTION 0: CROSSFADE
    if (indexPath.section == 0) {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"Crossfade Engine Status";
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%@\n%@", LGCrossfade.shared.status, YTMObservedAudioBackend()];
            cell.detailTextLabel.numberOfLines = 0;
            self.crossfadeStatusLabel = cell.detailTextLabel;
        } else if (indexPath.row == 1) {
            cell.textLabel.text = @"Apple Music Crossfade";
            cell.detailTextLabel.text = @"Smooth equal-power fade transition between songs";
            cell.detailTextLabel.numberOfLines = 0;

            ABCSwitch *sw = [[NSClassFromString(@"ABCSwitch") alloc] init];
            sw.onTintColor = accent;
            sw.on = audioMgr.crossfadeEnabled;
            [sw addTarget:self action:@selector(crossfadeToggled:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
        } else if (indexPath.row == 2) {
            cell.textLabel.text = [NSString stringWithFormat:@"Crossfade Duration: %.1f s", audioMgr.crossfadeDuration];
            cell.detailTextLabel.text = @"Adjust transition duration (1.0s to 12.0s)";
            self.crossfadeDurationLabel = cell.textLabel;

            UISlider *slider = [[UISlider alloc] initWithFrame:CGRectMake(0, 0, 140, 30)];
            slider.minimumValue = 1.0f;
            slider.maximumValue = 12.0f;
            slider.value = audioMgr.crossfadeDuration;
            slider.minimumTrackTintColor = accent;
            [slider addTarget:self action:@selector(crossfadeSliderChanged:) forControlEvents:UIControlEventValueChanged];
            self.crossfadeSlider = slider;
            cell.accessoryView = slider;
        } else if (indexPath.row == 3) {
            cell.textLabel.text = @"Gapless Album Detection";
            cell.detailTextLabel.text = @"Bypasses crossfade on continuous album tracks";
            cell.detailTextLabel.numberOfLines = 0;

            ABCSwitch *sw = [[NSClassFromString(@"ABCSwitch") alloc] init];
            sw.onTintColor = accent;
            sw.on = audioMgr.gaplessBypassEnabled;
            [sw addTarget:self action:@selector(gaplessToggled:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
        }
    }
    // SECTION 1: BUFFERING & PRE-FETCH
    else if (indexPath.section == 1) {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"Low-Network Deep Buffer Mode";
            cell.detailTextLabel.text = @"Expands forward audio buffer to 120s for weak reception";
            cell.detailTextLabel.numberOfLines = 0;

            ABCSwitch *sw = [[NSClassFromString(@"ABCSwitch") alloc] init];
            sw.onTintColor = [UIColor colorWithRed:30.0/255.0 green:150.0/255.0 blue:245.0/255.0 alpha:1.0];
            sw.on = netMgr.deepBufferEnabled;
            [sw addTarget:self action:@selector(deepBufferToggled:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
        } else if (indexPath.row == 1) {
            cell.textLabel.text = @"Smart Next-Track Pre-Fetch";
            cell.detailTextLabel.text = @"Pre-downloads next queue tracks after 15% playhead";
            cell.detailTextLabel.numberOfLines = 0;

            ABCSwitch *sw = [[NSClassFromString(@"ABCSwitch") alloc] init];
            sw.onTintColor = [UIColor colorWithRed:30.0/255.0 green:150.0/255.0 blue:245.0/255.0 alpha:1.0];
            sw.on = netMgr.prefetchNextEnabled;
            [sw addTarget:self action:@selector(prefetchToggled:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
        }
    }
    // SECTION 2: CACHE MANAGEMENT
    else if (indexPath.section == 2) {
        cell.textLabel.text = @"Clear Prefetched Audio Cache";
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
        cell.imageView.image = [UIImage systemImageNamed:@"trash"];
        cell.imageView.tintColor = [UIColor systemRedColor];

        UILabel *sizeLbl = [[UILabel alloc] init];
        sizeLbl.text = [netMgr formattedCacheSize];
        sizeLbl.textColor = [UIColor secondaryLabelColor];
        sizeLbl.font = [UIFont systemFontOfSize:15];
        [sizeLbl sizeToFit];
        self.cacheSizeLabel = sizeLbl;
        cell.accessoryView = sizeLbl;
    }

    return cell;
}

#pragma mark - Actions

- (void)crossfadeToggled:(UISwitch *)sender {
    [AudioCrossfadeManager sharedInstance].crossfadeEnabled = sender.isOn;
    [[AudioCrossfadeManager sharedInstance] saveSettings];
    if (!sender.isOn) [[LGCrossfade shared] cancel];
    [self refreshCrossfadeStatus];
}

- (void)crossfadeSliderChanged:(UISlider *)sender {
    float rounded = roundf(sender.value * 2.0f) / 2.0f; // 0.5s increments
    [AudioCrossfadeManager sharedInstance].crossfadeDuration = rounded;
    [[AudioCrossfadeManager sharedInstance] saveSettings];
    self.crossfadeDurationLabel.text = [NSString stringWithFormat:@"Crossfade Duration: %.1f s", rounded];
    [self refreshCrossfadeStatus];
}

- (void)gaplessToggled:(UISwitch *)sender {
    [AudioCrossfadeManager sharedInstance].gaplessBypassEnabled = sender.isOn;
    [[AudioCrossfadeManager sharedInstance] saveSettings];
}

- (void)deepBufferToggled:(UISwitch *)sender {
    [NetworkBufferOptimizer sharedInstance].deepBufferEnabled = sender.isOn;
    [[NetworkBufferOptimizer sharedInstance] saveSettings];
}

- (void)prefetchToggled:(UISwitch *)sender {
    [NetworkBufferOptimizer sharedInstance].prefetchNextEnabled = sender.isOn;
    [[NetworkBufferOptimizer sharedInstance] saveSettings];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (indexPath.section == 2 && indexPath.row == 0) {
        [[NetworkBufferOptimizer sharedInstance] clearCache];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            self.cacheSizeLabel.text = [[NetworkBufferOptimizer sharedInstance] formattedCacheSize];
            [self.cacheSizeLabel sizeToFit];
            [self.tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
        });
    }
}

@end
