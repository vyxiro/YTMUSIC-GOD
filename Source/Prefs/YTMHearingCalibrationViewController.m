#import "YTMHearingCalibrationViewController.h"
#import "../AudioStudio/YTMAudioStudioManager.h"
#import <math.h>

@interface YTMHearingCalibrationViewController ()
@property (nonatomic, strong) AVAudioEngine *toneEngine;
@property (nonatomic, strong) AVAudioPlayerNode *tonePlayer;
@property (nonatomic, strong) AVAudioPCMBuffer *toneBuffer;
@property (nonatomic, strong) UILabel *frequencyLabel;
@property (nonatomic, strong) UILabel *levelLabel;
@property (nonatomic, strong) UILabel *instructionLabel;
@property (nonatomic, strong) UIButton *hearButton;
@property (nonatomic, strong) UIProgressView *progressView;
@property (nonatomic, strong) NSTimer *stepTimer;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *thresholds;
@property (nonatomic, assign) NSUInteger frequencyIndex;
@property (nonatomic, assign) NSUInteger stepIndex;
@property (nonatomic, assign) float currentDBFS;
@property (nonatomic, assign) BOOL testRunning;
@end

@implementation YTMHearingCalibrationViewController

static NSArray<NSNumber *> *YTMTestFrequencies(void) { return @[@250, @500, @1000, @2000, @4000, @8000]; }

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Hearing Calibration";
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.thresholds = [NSMutableDictionary dictionary];
    [self buildInterface];
    [self updateLabels];
}

- (void)buildInterface {
    UIStackView *stack = [[UIStackView alloc] initWithFrame:CGRectZero];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.alignment = UIStackViewAlignmentFill;
    stack.spacing = 20.0;
    [self.view addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:24],
        [stack.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-24],
        [stack.centerYAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.centerYAnchor]
    ]];

    UILabel *title = [[UILabel alloc] init];
    title.text = @"Find your listening threshold";
    title.font = [UIFont preferredFontForTextStyle:UIFontTextStyleTitle2];
    title.textAlignment = NSTextAlignmentCenter;
    title.numberOfLines = 0;
    [stack addArrangedSubview:title];

    self.frequencyLabel = [[UILabel alloc] init];
    self.frequencyLabel.font = [UIFont systemFontOfSize:38 weight:UIFontWeightSemibold];
    self.frequencyLabel.textAlignment = NSTextAlignmentCenter;
    [stack addArrangedSubview:self.frequencyLabel];

    self.instructionLabel = [[UILabel alloc] init];
    self.instructionLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    self.instructionLabel.textColor = UIColor.secondaryLabelColor;
    self.instructionLabel.textAlignment = NSTextAlignmentCenter;
    self.instructionLabel.numberOfLines = 0;
    self.instructionLabel.text = @"Use your usual headphones at a comfortable level. Tap when you can just hear the tone.";
    [stack addArrangedSubview:self.instructionLabel];

    self.progressView = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
    [stack addArrangedSubview:self.progressView];

    self.levelLabel = [[UILabel alloc] init];
    self.levelLabel.font = [UIFont monospacedDigitSystemFontOfSize:17 weight:UIFontWeightMedium];
    self.levelLabel.textAlignment = NSTextAlignmentCenter;
    [stack addArrangedSubview:self.levelLabel];

    self.hearButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.hearButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.hearButton setTitle:@"I Hear It" forState:UIControlStateNormal];
    self.hearButton.titleLabel.font = [UIFont systemFontOfSize:21 weight:UIFontWeightSemibold];
    self.hearButton.backgroundColor = UIColor.systemBlueColor;
    [self.hearButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    self.hearButton.layer.cornerRadius = 18.0;
    self.hearButton.enabled = NO;
    [self.hearButton addTarget:self action:@selector(recordThreshold) forControlEvents:UIControlEventTouchUpInside];
    [stack addArrangedSubview:self.hearButton];
    [self.hearButton.heightAnchor constraintEqualToConstant:58.0].active = YES;
    [self.hearButton.widthAnchor constraintEqualToConstant:220.0].active = YES;
    self.hearButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentCenter;

    UIButton *start = [UIButton buttonWithType:UIButtonTypeSystem];
    [start setTitle:@"Start Test" forState:UIControlStateNormal];
    [start addTarget:self action:@selector(startTest) forControlEvents:UIControlEventTouchUpInside];
    start.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    [stack addArrangedSubview:start];
}

- (void)startTest {
    [self stopTone];
    self.frequencyIndex = 0;
    self.stepIndex = 0;
    [self.thresholds removeAllObjects];
    self.testRunning = YES;
    AVAudioSession *session = AVAudioSession.sharedInstance;
    NSError *error = nil;
    [session setCategory:AVAudioSessionCategoryPlayback withOptions:AVAudioSessionCategoryOptionMixWithOthers error:&error];
    if (error) { [self showError:error.localizedDescription]; self.testRunning = NO; return; }
    [session setActive:YES error:&error];
    if (error) { [self showError:error.localizedDescription]; self.testRunning = NO; return; }
    self.toneEngine = [[AVAudioEngine alloc] init];
    self.tonePlayer = [[AVAudioPlayerNode alloc] init];
    [self.toneEngine attachNode:self.tonePlayer];
    AVAudioFormat *format = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:44100.0 channels:1];
    [self.toneEngine connect:self.tonePlayer to:self.toneEngine.mainMixerNode format:format];
    [self beginFrequency];
}

- (AVAudioPCMBuffer *)createSineBufferWithFrequency:(float)frequency format:(AVAudioFormat *)format {
    AVAudioFrameCount frames = 44100;
    AVAudioPCMBuffer *buffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:format frameCapacity:frames];
    if (!buffer.floatChannelData) return nil;
    buffer.frameLength = frames;
    float *samples = buffer.floatChannelData[0];
    double phaseStep = 2.0 * M_PI * frequency / format.sampleRate;
    for (AVAudioFrameCount frame = 0; frame < frames; frame++) samples[frame] = (float)sin(phaseStep * frame);
    return buffer;
}

- (void)beginFrequency {
    if (!self.testRunning) return;
    if (self.frequencyIndex >= YTMTestFrequencies().count) { [self finishTest]; return; }
    self.stepIndex = 0;
    self.currentDBFS = -45.0f;
    AVAudioFormat *format = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:44100.0 channels:1];
    self.toneBuffer = [self createSineBufferWithFrequency:YTMTestFrequencies()[self.frequencyIndex].floatValue format:format];
    if (!self.toneBuffer) { [self showError:@"Could not create the calibration tone."]; [self finishTest]; return; }
    self.tonePlayer.volume = powf(10.0f, self.currentDBFS / 20.0f);
    [self.tonePlayer stop];
    [self.tonePlayer scheduleBuffer:self.toneBuffer atTime:nil options:AVAudioPlayerNodeBufferLoops completionHandler:nil];
    NSError *error = nil;
    if (!self.toneEngine.isRunning && ![self.toneEngine startAndReturnError:&error]) { [self showError:error.localizedDescription ?: @"Audio engine failed to start."]; [self finishTest]; return; }
    [self.tonePlayer play];
    self.hearButton.enabled = YES;
    [self updateLabels];
    __weak typeof(self) weakSelf = self;
    self.stepTimer = [NSTimer scheduledTimerWithTimeInterval:1.5 repeats:YES block:^(__unused NSTimer *timer) {
        [weakSelf advanceLevel];
    }];
    [UIView animateWithDuration:0.65 delay:0 options:UIViewAnimationOptionRepeat | UIViewAnimationOptionAutoreverse | UIViewAnimationOptionAllowUserInteraction animations:^{ self.hearButton.transform = CGAffineTransformMakeScale(1.04, 1.04); self.hearButton.alpha = 0.78; } completion:nil];
}

- (void)advanceLevel {
    // Six 10-second windows keep the complete test to one minute. Levels rise in 3 dB steps.
    self.stepIndex++;
    if (self.stepIndex >= 6) {
        NSString *key = YTMTestFrequencies()[self.frequencyIndex].stringValue;
        self.thresholds[key] = @15.0f;
        [self moveToNextFrequency];
        return;
    }
    self.currentDBFS = -45.0f + 3.0f * self.stepIndex;
    self.tonePlayer.volume = powf(10.0f, self.currentDBFS / 20.0f);
    [self updateLabels];
}

- (void)recordThreshold {
    if (!self.testRunning) return;
    NSString *key = YTMTestFrequencies()[self.frequencyIndex].stringValue;
    // A relative threshold above the initial -45 dBFS reference; this is not a calibrated SPL value.
    self.thresholds[key] = @(fmaxf(0.0f, self.currentDBFS + 45.0f));
    [self moveToNextFrequency];
}

- (void)moveToNextFrequency {
    [self.stepTimer invalidate]; self.stepTimer = nil;
    [self.hearButton.layer removeAllAnimations];
    [self.tonePlayer stop];
    self.frequencyIndex++;
    [self updateLabels];
    if (self.frequencyIndex >= YTMTestFrequencies().count) { [self finishTest]; return; }
    [self beginFrequency];
}

- (void)updateLabels {
    if (self.frequencyIndex >= YTMTestFrequencies().count) return;
    self.frequencyLabel.text = [NSString stringWithFormat:@"%@ Hz", YTMTestFrequencies()[self.frequencyIndex]];
    self.levelLabel.text = self.testRunning ? [NSString stringWithFormat:@"Tone level  %+.0f dBFS", self.currentDBFS] : @"Ready · 6 frequencies · about 60 seconds";
    self.progressView.progress = (float)self.frequencyIndex / (float)YTMTestFrequencies().count;
}

- (void)finishTest {
    self.testRunning = NO;
    [self.stepTimer invalidate]; self.stepTimer = nil;
    [UIView animateWithDuration:0.2 animations:^{ self.hearButton.transform = CGAffineTransformIdentity; self.hearButton.alpha = 1.0; }];
    [self.hearButton setTitle:@"I Hear It" forState:UIControlStateNormal];
    self.hearButton.enabled = NO;
    [self stopTone];
    if (self.thresholds.count == YTMTestFrequencies().count) {
        [[YTMAudioStudioManager sharedManager] applyHearingThresholds:self.thresholds];
        self.progressView.progress = 1.0f;
        self.frequencyLabel.text = @"Calibration saved";
        self.levelLabel.text = @"My Hearing Profile has been applied to the EQ.";
        self.instructionLabel.text = @"Your profile is saved. Thresholds are relative to this device and headphone level.";
    }
}

- (void)stopTone {
    [self.stepTimer invalidate]; self.stepTimer = nil;
    [self.tonePlayer stop];
    [self.toneEngine stop];
    self.tonePlayer = nil; self.toneEngine = nil; self.toneBuffer = nil;
    NSError *sessionError = nil;
    [AVAudioSession.sharedInstance setActive:NO withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation error:&sessionError];
}

- (void)showError:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Audio Test Unavailable" message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)viewWillDisappear:(BOOL)animated { [super viewWillDisappear:animated]; if (self.testRunning) [self finishTest]; }
- (void)dealloc { [self stopTone]; }

@end
