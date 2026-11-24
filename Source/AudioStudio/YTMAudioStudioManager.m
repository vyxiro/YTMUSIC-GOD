#import "YTMAudioStudioManager.h"
#import <math.h>

static NSString * const kAudioStudioKey = @"audioStudio";
static NSUInteger const kBandCount = 10;
static float const kDefaultFrequencies[] = {31.0f, 62.0f, 125.0f, 250.0f, 500.0f, 1000.0f, 2000.0f, 4000.0f, 8000.0f, 16000.0f};
static NSString * const kAudioStudioRouteChanged = @"YTMAudioStudioRouteChanged";

static float YTMClamp(float value, float low, float high) {
    return fminf(high, fmaxf(low, value));
}

@interface YTMAudioStudioManager ()
@property (nonatomic, strong) dispatch_queue_t stateQueue;
@property (nonatomic, strong) AVAudioEngine *engine;
@property (nonatomic, strong, readwrite) AVAudioUnitEQ *equalizer;
@property (nonatomic, strong) AVAudioUnitDynamicsProcessor *limiter;
@property (nonatomic, copy, readwrite) NSArray<NSString *> *presetNames;
@property (nonatomic, copy, readwrite) NSString *selectedPresetName;
@property (nonatomic, assign, readwrite) float preampOffsetDB;
@property (nonatomic, assign, readwrite) BOOL limiterEnabled;
@property (nonatomic, assign, readwrite, getter=isEnabled) BOOL enabled;
@property (nonatomic, assign) BOOL adaptiveLoudnessEnabled;
@property (nonatomic, strong) NSMutableArray<NSMutableDictionary *> *bands;
@property (nonatomic, strong) NSDictionary<NSString *, NSDictionary *> *presets;
@property (nonatomic, assign) float importedPreampDB;
@property (nonatomic, assign) BOOL observingVolume;
@property (nonatomic, assign) float lastVolume;
@property (nonatomic, assign) float adaptiveBassDelta;
@property (nonatomic, assign) float adaptiveTrebleDelta;
- (instancetype)initPrivate;
- (NSDictionary<NSString *, NSDictionary *> *)buildPresets;
- (void)configureLimiter;
- (void)updatePreamp;
- (void)saveImportedProfile;
- (NSString *)routeKeyForCurrentOutput;
@end

@implementation YTMAudioStudioManager

+ (instancetype)sharedManager {
    static YTMAudioStudioManager *manager;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ manager = [[self alloc] initPrivate]; });
    return manager;
}

- (instancetype)init { return [YTMAudioStudioManager sharedManager]; }

- (instancetype)initPrivate {
    self = [super init];
    if (!self) return nil;
    _stateQueue = dispatch_queue_create("com.ytmu.audio-studio.state", DISPATCH_QUEUE_SERIAL);
    _equalizer = [[AVAudioUnitEQ alloc] initWithNumberOfBands:kBandCount];
    _limiter = [[AVAudioUnitDynamicsProcessor alloc] init];
    _bands = [NSMutableArray arrayWithCapacity:kBandCount];
    _presetNames = @[@"Flat (Bypass)", @"Harman Target Clarity", @"Apple Music Spatial Warmth", @"Deep Sub-Bass + Clean Vocals", @"Speech & Lyric Focus", @"My Hearing Profile", @"Imported AutoEq"];
    _presets = [self buildPresets];
    _selectedPresetName = @"Flat (Bypass)";
    _limiterEnabled = YES;
    _lastVolume = AVAudioSession.sharedInstance.outputVolume;
    for (NSUInteger i = 0; i < kBandCount; i++) {
        AVAudioUnitEQFilterParameters *filter = _equalizer.bands[i];
        filter.filterType = AVAudioUnitEQFilterTypeParametric;
        filter.frequency = kDefaultFrequencies[i];
        filter.gain = 0.0f;
        filter.bandwidth = 1.41f;
        filter.bypass = YES;
        [_bands addObject:[@{@"frequency": @(kDefaultFrequencies[i]), @"gain": @0.0f, @"q": @1.41f, @"bypass": @YES, @"type": @0} mutableCopy]];
    }
    [self configureLimiter];
    [self loadSettings];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(routeChanged:) name:AVAudioSessionRouteChangeNotification object:nil];
    @try {
        [AVAudioSession.sharedInstance addObserver:self forKeyPath:@"outputVolume" options:NSKeyValueObservingOptionNew context:NULL];
        _observingVolume = YES;
    } @catch (__unused NSException *exception) {
        _observingVolume = NO;
    }
    return self;
}

- (NSDictionary<NSString *, NSDictionary *> *)buildPresets {
    NSArray *flat = @[@0,@0,@0,@0,@0,@0,@0,@0,@0,@0];
    NSArray *harman = @[@5.5,@4.0,@1.5,@-1.0,@0.0,@0.5,@2.0,@3.0,@1.5,@4.0];
    NSArray *warm = @[@3.0,@2.5,@1.0,@0.5,@1.0,@1.5,@2.5,@2.0,@3.0,@3.5];
    NSArray *deep = @[@6.5,@4.5,@1.0,@-2.5,@-1.0,@1.0,@3.0,@2.5,@2.0,@3.0];
    NSArray *speech = @[@-4.0,@-2.0,@0.0,@-1.5,@1.0,@3.0,@4.5,@3.5,@1.5,@0.0];
    NSArray *harmanQ = @[@0.9,@1.2,@1.4,@1.8,@1.41,@1.41,@1.5,@1.8,@1.41,@1.0];
    NSArray *deepQ = @[@1.0,@1.2,@1.41,@2.0,@1.41,@1.41,@1.4,@1.41,@1.41,@1.41];
    NSArray *defaultQ = @[@1.41,@1.41,@1.41,@1.41,@1.41,@1.41,@1.41,@1.41,@1.41,@1.41];
    return @{@"Flat (Bypass)": @{ @"gains": flat, @"q": defaultQ },
             @"Harman Target Clarity": @{ @"gains": harman, @"q": harmanQ },
             @"Apple Music Spatial Warmth": @{ @"gains": warm, @"q": defaultQ },
             @"Deep Sub-Bass + Clean Vocals": @{ @"gains": deep, @"q": deepQ },
             @"Speech & Lyric Focus": @{ @"gains": speech, @"q": defaultQ }};
}

- (void)configureLimiter {
    self.limiter.threshold = -1.0f;
    self.limiter.headRoom = 0.5f;
    self.limiter.expansionRatio = 1.0f;
    self.limiter.attackTime = 0.001f;
    self.limiter.releaseTime = 0.050f;
}

- (void)loadSettings {
    NSDictionary *root = [NSUserDefaults.standardUserDefaults dictionaryForKey:@"YTMUltimate"];
    NSDictionary *saved = [root[kAudioStudioKey] isKindOfClass:NSDictionary.class] ? root[kAudioStudioKey] : nil;
    if (!saved) return;
    self.enabled = [saved[@"enabled"] boolValue];
    self.adaptiveLoudnessEnabled = [saved[@"adaptive"] boolValue];
    self.importedPreampDB = [saved[@"preamp"] floatValue];
    NSString *name = [saved[@"preset"] isKindOfClass:NSString.class] ? saved[@"preset"] : nil;
    if (name.length) self.selectedPresetName = name;
    NSArray *savedBands = [saved[@"bands"] isKindOfClass:NSArray.class] ? saved[@"bands"] : nil;
    if (savedBands.count == kBandCount) {
        for (NSUInteger i = 0; i < kBandCount; i++) {
            NSDictionary *b = savedBands[i];
            if (![b isKindOfClass:NSDictionary.class]) continue;
            [self setFrequency:[b[@"frequency"] floatValue] q:[b[@"q"] floatValue] forBand:i];
            [self setGain:[b[@"gain"] floatValue] forBand:i];
            [self setBandBypassed:[b[@"bypass"] boolValue] forBand:i];
        }
    } else if (self.presets[self.selectedPresetName]) {
        [self selectPresetNamed:self.selectedPresetName];
    }
    [self updatePreamp];
}

- (void)saveSettings {
    @synchronized (self) {
    @synchronized (NSUserDefaults.standardUserDefaults) {
        NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
        NSMutableDictionary *root = [[defaults dictionaryForKey:@"YTMUltimate"] mutableCopy] ?: [NSMutableDictionary dictionary];
        root[kAudioStudioKey] = @{@"enabled": @(self.enabled), @"adaptive": @(self.adaptiveLoudnessEnabled), @"preamp": @(self.importedPreampDB), @"preset": self.selectedPresetName ?: @"Flat (Bypass)", @"bands": [self.bands copy]};
        [defaults setObject:root forKey:@"YTMUltimate"];
    }
    }
}

- (BOOL)isEnabled { @synchronized (self) { return _enabled; } }
- (void)setEnabled:(BOOL)enabled { @synchronized (self) { _enabled = enabled; } }
- (BOOL)adaptiveLoudnessEnabled { @synchronized (self) { return _adaptiveLoudnessEnabled; } }
- (void)setAdaptiveLoudnessEnabled:(BOOL)enabled { @synchronized (self) { _adaptiveLoudnessEnabled = enabled; } }
- (float)preampOffsetDB { @synchronized (self) { return _preampOffsetDB; } }

- (void)selectPresetNamed:(NSString *)name {
    NSDictionary *profile = self.presets[name];
    if (!profile) {
        NSDictionary *saved = [NSUserDefaults.standardUserDefaults dictionaryForKey:@"YTMUltimate"][kAudioStudioKey];
        profile = saved[@"customProfiles"][name];
    }
    if (!profile) return;
    self.selectedPresetName = name;
    NSArray *gains = profile[@"gains"];
    NSArray *qs = profile[@"q"];
    NSArray *frequencies = profile[@"frequencies"];
    NSArray *bypasses = profile[@"bypasses"];
    for (NSUInteger i = 0; i < MIN(kBandCount, gains.count); i++) {
        [self setGain:[gains[i] floatValue] forBand:i];
        if (i < qs.count) {
            float frequency = frequencies.count > i ? [frequencies[i] floatValue] : kDefaultFrequencies[i];
            [self setFrequency:frequency q:[qs[i] floatValue] forBand:i];
        }
        [self setBandBypassed:bypasses.count > i ? [bypasses[i] boolValue] : NO forBand:i];
    }
    [self updatePreamp];
    [self saveSettings];
}

- (float)gainForBand:(NSUInteger)i { @synchronized (self) { return i < self.bands.count ? [self.bands[i][@"gain"] floatValue] : 0.0f; } }
- (float)frequencyForBand:(NSUInteger)i { @synchronized (self) { return i < self.bands.count ? [self.bands[i][@"frequency"] floatValue] : 0.0f; } }
- (float)qForBand:(NSUInteger)i { @synchronized (self) { return i < self.bands.count ? [self.bands[i][@"q"] floatValue] : 1.41f; } }
- (BOOL)isBandBypassed:(NSUInteger)i { @synchronized (self) { return i >= self.bands.count || [self.bands[i][@"bypass"] boolValue]; } }

- (void)setGain:(float)gain forBand:(NSUInteger)i {
    @synchronized (self) {
    if (i >= kBandCount || !isfinite(gain)) return;
    gain = YTMClamp(gain, -15.0f, 15.0f);
    self.bands[i][@"gain"] = @(gain);
    self.equalizer.bands[i].gain = gain;
    self.equalizer.bands[i].bypass = [self.bands[i][@"bypass"] boolValue];
    [self updatePreamp];
    }
}

- (void)setFrequency:(float)frequency q:(float)q forBand:(NSUInteger)i {
    @synchronized (self) {
    if (i >= kBandCount || !isfinite(frequency) || !isfinite(q)) return;
    frequency = YTMClamp(frequency, 20.0f, 20000.0f);
    q = YTMClamp(q, 0.1f, 10.0f);
    self.bands[i][@"frequency"] = @(frequency);
    self.bands[i][@"q"] = @(q);
    AVAudioUnitEQFilterParameters *filter = self.equalizer.bands[i];
    filter.filterType = (AVAudioUnitEQFilterType)[self.bands[i][@"type"] integerValue];
    filter.frequency = frequency;
    // AVAudioUnitEQ expresses parametric bandwidth in octaves rather than Q.
    filter.bandwidth = (float)(2.0 * asinh(1.0 / (2.0 * q)) / log(2.0));
    }
}

- (void)setBandBypassed:(BOOL)bypassed forBand:(NSUInteger)i {
    @synchronized (self) {
    if (i >= kBandCount) return;
    self.bands[i][@"bypass"] = @(bypassed);
    self.equalizer.bands[i].bypass = bypassed;
    [self updatePreamp];
    }
}

- (void)updatePreamp {
    @synchronized (self) {
    float maxGain = 0.0f;
    for (NSUInteger i = 0; i < self.bands.count; i++) {
        if (![self.bands[i][@"bypass"] boolValue]) maxGain = fmaxf(maxGain, [self.bands[i][@"gain"] floatValue]);
    }
    self.preampOffsetDB = -maxGain + self.importedPreampDB;
    self.equalizer.globalGain = self.preampOffsetDB;
    }
}

- (BOOL)importAutoEqProfileFromText:(NSString *)text error:(NSError **)error {
    if (![text isKindOfClass:NSString.class] || text.length == 0) {
        if (error) *error = [NSError errorWithDomain:@"YTMAudioStudio" code:1 userInfo:@{NSLocalizedDescriptionKey: @"Paste an AutoEq or EqualizerAPO profile first.", NSLocalizedFailureReasonErrorKey: @"The profile text is empty."}];
        return NO;
    }
    NSRegularExpression *preampRegex = [NSRegularExpression regularExpressionWithPattern:@"(?im)^\\s*Preamp\\s*:\\s*([-+]?\\d+(?:\\.\\d+)?)\\s*dB" options:0 error:nil];
    NSTextCheckingResult *preampMatch = [preampRegex firstMatchInString:text options:0 range:NSMakeRange(0, text.length)];
    self.importedPreampDB = preampMatch ? [[text substringWithRange:[preampMatch rangeAtIndex:1]] floatValue] : 0.0f;
    NSString *pattern = @"(?im)^\\s*Filter\\s*\\d+\\s*:\\s*(ON|OFF)\\s+(PK|LSC|HSC)\\s+Fc\\s+([-+]?\\d+(?:\\.\\d+)?)\\s*Hz\\s+Gain\\s+([-+]?\\d+(?:\\.\\d+)?)\\s*dB(?:\\s+Q\\s+([-+]?\\d+(?:\\.\\d+)?))?";
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil];
    NSArray<NSTextCheckingResult *> *matches = [regex matchesInString:text options:0 range:NSMakeRange(0, text.length)];
    if (!matches.count) {
        if (error) *error = [NSError errorWithDomain:@"YTMAudioStudio" code:2 userInfo:@{NSLocalizedDescriptionKey: @"No supported EqualizerAPO filters were found.", NSLocalizedFailureReasonErrorKey: @"Expected Filter N: ON/OFF PK|LSC|HSC Fc … Hz Gain … dB Q … lines."}];
        return NO;
    }
    NSMutableArray<NSDictionary *> *filters = [NSMutableArray arrayWithCapacity:matches.count];
    for (NSTextCheckingResult *m in matches) {
        NSString *(^capture)(NSUInteger) = ^NSString *(NSUInteger idx) { NSRange r = [m rangeAtIndex:idx]; return r.location == NSNotFound ? @"" : [text substringWithRange:r]; };
        NSString *kind = capture(2);
        [filters addObject:@{@"on": @([capture(1) caseInsensitiveCompare:@"ON"] == NSOrderedSame), @"kind": kind, @"frequency": @([capture(3) floatValue]), @"gain": @([capture(4) floatValue]), @"q": @(capture(5).length ? [capture(5) floatValue] : 1.41f)}];
    }
    if (filters.count > kBandCount) {
        NSArray *sorted = [filters sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
            float ia = fabsf([a[@"gain"] floatValue]); float ib = fabsf([b[@"gain"] floatValue]);
            return ia > ib ? NSOrderedAscending : (ia < ib ? NSOrderedDescending : NSOrderedSame);
        }];
        NSSet *chosen = [NSSet setWithArray:[sorted subarrayWithRange:NSMakeRange(0, kBandCount)]];
        NSMutableArray *ordered = [NSMutableArray array];
        for (NSDictionary *filter in filters) if ([chosen containsObject:filter]) [ordered addObject:filter];
        filters = ordered;
    }
    self.selectedPresetName = @"Imported AutoEq";
    for (NSUInteger i = 0; i < kBandCount; i++) {
        if (i >= filters.count) { [self setBandBypassed:YES forBand:i]; continue; }
        NSDictionary *f = filters[i];
        NSInteger type = [f[@"kind"] isEqual:@"LSC"] ? AVAudioUnitEQFilterTypeLowShelf : ([f[@"kind"] isEqual:@"HSC"] ? AVAudioUnitEQFilterTypeHighShelf : AVAudioUnitEQFilterTypeParametric);
        self.bands[i][@"type"] = @(type);
        [self setFrequency:[f[@"frequency"] floatValue] q:[f[@"q"] floatValue] forBand:i];
        [self setGain:[f[@"gain"] floatValue] forBand:i];
        [self setBandBypassed:![f[@"on"] boolValue] forBand:i];
    }
    [self updatePreamp];
    [self saveImportedProfile];
    return YES;
}

- (void)saveImportedProfile {
    NSDictionary *profile = @{ @"gains": [self.bands valueForKey:@"gain"], @"q": [self.bands valueForKey:@"q"], @"frequencies": [self.bands valueForKey:@"frequency"], @"bypasses": [self.bands valueForKey:@"bypass"] };
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSMutableDictionary *root = [[defaults dictionaryForKey:@"YTMUltimate"] mutableCopy] ?: [NSMutableDictionary dictionary];
    NSMutableDictionary *settings = [root[kAudioStudioKey] mutableCopy] ?: [NSMutableDictionary dictionary];
    NSMutableDictionary *custom = [settings[@"customProfiles"] mutableCopy] ?: [NSMutableDictionary dictionary];
    custom[@"Imported AutoEq"] = profile;
    settings[@"customProfiles"] = custom;
    root[kAudioStudioKey] = settings;
    [defaults setObject:root forKey:@"YTMUltimate"];
    [self saveSettings];
}

- (void)applyHearingThresholds:(NSDictionary<NSString *,NSNumber *> *)thresholds {
    NSArray<NSNumber *> *freqs = @[@250,@500,@1000,@2000,@4000,@8000];
    NSUInteger targetBands[] = {3,4,5,6,7,8};
    NSMutableArray *gains = [NSMutableArray array];
    for (NSUInteger i = 0; i < freqs.count; i++) {
        NSString *key = freqs[i].stringValue;
        float threshold = [thresholds[key] floatValue];
        float compensation = YTMClamp((threshold * 0.5f), -3.0f, 9.0f);
        [self setGain:compensation forBand:targetBands[i]];
        [gains addObject:@(compensation)];
    }
    self.selectedPresetName = @"My Hearing Profile";
    NSMutableDictionary *profile = [@{ @"gains": [self.bands valueForKey:@"gain"], @"q": [self.bands valueForKey:@"q"], @"frequencies": [self.bands valueForKey:@"frequency"], @"bypasses": [self.bands valueForKey:@"bypass"] } mutableCopy];
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSMutableDictionary *root = [[defaults dictionaryForKey:@"YTMUltimate"] mutableCopy] ?: [NSMutableDictionary dictionary];
    NSMutableDictionary *settings = [root[kAudioStudioKey] mutableCopy] ?: [NSMutableDictionary dictionary];
    NSMutableDictionary *custom = [settings[@"customProfiles"] mutableCopy] ?: [NSMutableDictionary dictionary];
    custom[@"My Hearing Profile"] = profile;
    settings[@"customProfiles"] = custom;
    settings[@"hearingThresholds"] = thresholds;
    root[kAudioStudioKey] = settings;
    [defaults setObject:root forKey:@"YTMUltimate"];
    [self saveSettings];
}

- (NSArray<NSString *> *)outputRouteNames { return @[@"Bluetooth / AirPods", @"Car Audio", @"Wired Headphones / DAC", @"iPhone Speaker", @"Other"] ; }

- (NSString *)routeKeyForCurrentOutput {
    AVAudioSessionPortDescription *port = AVAudioSession.sharedInstance.currentRoute.outputs.firstObject;
    NSString *type = port.portType;
    if ([type isEqualToString:AVAudioSessionPortBluetoothA2DP] || [type isEqualToString:AVAudioSessionPortBluetoothHFP] || [type isEqualToString:AVAudioSessionPortBluetoothLE]) return @"Bluetooth / AirPods";
    if ([type isEqualToString:AVAudioSessionPortCarAudio]) return @"Car Audio";
    if ([type isEqualToString:AVAudioSessionPortHeadphones] || [type isEqualToString:AVAudioSessionPortUSBAudio]) return @"Wired Headphones / DAC";
    if ([type isEqualToString:AVAudioSessionPortBuiltInSpeaker]) return @"iPhone Speaker";
    return @"Other";
}

- (NSString *)presetNameForCurrentRoute { return [self presetNameForRoute:[self routeKeyForCurrentOutput]]; }
- (NSString *)presetNameForRoute:(NSString *)route { return [NSUserDefaults.standardUserDefaults dictionaryForKey:@"YTMUltimate"][kAudioStudioKey][@"routePresets"][route]; }
- (void)setPresetName:(NSString *)presetName forRoute:(NSString *)route {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSMutableDictionary *root = [[defaults dictionaryForKey:@"YTMUltimate"] mutableCopy] ?: [NSMutableDictionary dictionary];
    NSMutableDictionary *settings = [root[kAudioStudioKey] mutableCopy] ?: [NSMutableDictionary dictionary];
    NSMutableDictionary *routes = [settings[@"routePresets"] mutableCopy] ?: [NSMutableDictionary dictionary];
    if (presetName.length) routes[route] = presetName; else [routes removeObjectForKey:route];
    settings[@"routePresets"] = routes; root[kAudioStudioKey] = settings; [defaults setObject:root forKey:@"YTMUltimate"];
}

- (void)refreshRoutePreset {
    NSString *route = [self routeKeyForCurrentOutput];
    NSString *preset = [self presetNameForRoute:route];
    if (preset.length) [self selectPresetNamed:preset];
    if (!self.enabled || !preset.length) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        Class toastClass = NSClassFromString(@"YTMToastController");
        if ([toastClass instancesRespondToSelector:@selector(showMessage:)]) [[toastClass new] performSelector:@selector(showMessage:) withObject:[NSString stringWithFormat:@"Audio preset: %@", preset]];
    });
    [[NSNotificationCenter defaultCenter] postNotificationName:kAudioStudioRouteChanged object:route];
}

- (void)routeChanged:(NSNotification *)note { dispatch_async(self.stateQueue, ^{ [self refreshRoutePreset]; }); }

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context {
    if (![keyPath isEqualToString:@"outputVolume"] || !self.adaptiveLoudnessEnabled) { [super observeValueForKeyPath:keyPath ofObject:object change:change context:context]; return; }
    float volume = YTMClamp([change[NSKeyValueChangeNewKey] floatValue], 0.0f, 1.0f);
    self.lastVolume = volume;
    float scale = volume < 0.40f ? 1.0f - volume / 0.40f : 0.0f;
    float bass = 6.0f * scale;
    float treble = 3.5f * scale;
    float bassBase = [self.bands[0][@"gain"] floatValue] - self.adaptiveBassDelta;
    float trebleBase = [self.bands[8][@"gain"] floatValue] - self.adaptiveTrebleDelta;
    self.adaptiveBassDelta = bass;
    self.adaptiveTrebleDelta = treble;
    [self setGain:YTMClamp(bassBase + bass, -15.0f, 15.0f) forBand:0];
    [self setGain:YTMClamp(trebleBase + treble, -15.0f, 15.0f) forBand:8];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    if (self.observingVolume) @try { [AVAudioSession.sharedInstance removeObserver:self forKeyPath:@"outputVolume"]; } @catch (__unused NSException *exception) {}
}

@end
