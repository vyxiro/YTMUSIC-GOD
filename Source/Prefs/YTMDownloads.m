#import "YTMDownloads.h"
#import "../LiquidGlass.h"

@implementation YTMDownloads

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = [UIColor clearColor];
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.backgroundColor = [UIColor clearColor];
    self.tableView.backgroundView = nil;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.contentInset = UIEdgeInsetsMake(68.0f, 0.0f, 140.0f, 0.0f);
    [self.view addSubview:self.tableView];

    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.tableView.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [self.tableView.widthAnchor constraintEqualToAnchor:self.view.widthAnchor],
        [self.tableView.heightAnchor constraintEqualToAnchor:self.view.heightAnchor]
    ]];

    [self maybeShowEmptyState];
    [self refreshAudioFiles];
    [self updatePlaylistHeader];

    __weak typeof(self) weakSelf = self;
    self.themeObserver = LGObserveTheme(^(__unused LGPalette *palette, __unused BOOL dark, __unused BOOL staticMode) {
        [weakSelf applyThemeColors];
        [weakSelf updatePlaylistHeader];
        [weakSelf.tableView reloadData];
    });

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reloadData) name:@"ReloadDataNotification" object:nil];
}

- (void)updatePlaylistHeader {
    CGFloat w = self.view.bounds.size.width > 120.0f ? self.view.bounds.size.width : 390.0f;
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, w, 108.0f)];
    header.backgroundColor = [UIColor clearColor];

    UIView *card = [[UIView alloc] initWithFrame:CGRectMake(16.0f, 8.0f, w - 32.0f, 92.0f)];
    card.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    card.backgroundColor = [UIColor clearColor];
    [header addSubview:card];

    LGGlassView *glass = LGAttachGlass(card, 20.0f);
    glass.frame = card.bounds;

    LGPalette *p = LGTheme.shared.palette;
    UIImage *coverImg = nil;
    if (self.audioFiles.count > 0) {
        NSString *imageName = [NSString stringWithFormat:@"%@.png", [self.audioFiles.firstObject stringByDeletingPathExtension]];
        NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
        coverImg = [UIImage imageWithContentsOfFile:[[docs stringByAppendingPathComponent:@"YTMusicUltimate"] stringByAppendingPathComponent:imageName]];
    }

    UIImageView *art = [[UIImageView alloc] initWithFrame:CGRectMake(14.0f, 14.0f, 64.0f, 64.0f)];
    art.layer.cornerRadius = 14.0f;
    art.clipsToBounds = YES;
    art.contentMode = coverImg ? UIViewContentModeScaleAspectFill : UIViewContentModeCenter;
    if (coverImg) {
        art.image = coverImg;
    } else {
        art.backgroundColor = [p.a1 ?: [UIColor systemBlueColor] colorWithAlphaComponent:0.25f];
        art.image = [UIImage systemImageNamed:@"music.note.list"];
        art.tintColor = p.a1 ?: [UIColor whiteColor];
    }
    [card addSubview:art];

    UILabel *titleLbl = [[UILabel alloc] initWithFrame:CGRectMake(92.0f, 22.0f, card.bounds.size.width - 108.0f, 24.0f)];
    titleLbl.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    titleLbl.text = LOC(@"DOWNLOADS") ?: @"Downloaded Playlist";
    titleLbl.font = [UIFont systemFontOfSize:19.0f weight:UIFontWeightBold];
    titleLbl.textColor = p.tx ?: [UIColor whiteColor];
    [card addSubview:titleLbl];

    UILabel *subLbl = [[UILabel alloc] initWithFrame:CGRectMake(92.0f, 48.0f, card.bounds.size.width - 108.0f, 20.0f)];
    subLbl.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    subLbl.text = [NSString stringWithFormat:@"%lu %@", (unsigned long)self.audioFiles.count, self.audioFiles.count == 1 ? @"song • Offline" : @"songs • Offline"];
    subLbl.font = [UIFont systemFontOfSize:13.0f weight:UIFontWeightMedium];
    subLbl.textColor = p.mu ?: [[UIColor whiteColor] colorWithAlphaComponent:0.75f];
    [card addSubview:subLbl];

    self.tableView.tableHeaderView = header;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.view.backgroundColor = [UIColor clearColor];
    if (self.parentViewController.view) {
        self.parentViewController.view.backgroundColor = [UIColor clearColor];
    }
    [self applyThemeColors];
}

- (void)applyThemeColors {
    LGPalette *p = LGTheme.shared.palette;
    UIColor *emptyColor = self.audioFiles.count == 0 ? (p.mu ?: [[UIColor whiteColor] colorWithAlphaComponent:0.8]) : [UIColor clearColor];
    self.imageView.tintColor = emptyColor;
    self.label.textColor = emptyColor;
}

- (void)maybeShowEmptyState {
    if (self.audioFiles.count == 0) {
        self.imageView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"yt_outline_audio_48pt" inBundle:[NSBundle mainBundle] compatibleWithTraitCollection:nil]];
        self.imageView.contentMode = UIViewContentModeScaleAspectFit;
        self.imageView.tintColor = [[UIColor whiteColor] colorWithAlphaComponent:0.8];
        self.imageView.translatesAutoresizingMaskIntoConstraints = NO;
        [self.tableView addSubview:self.imageView];

        self.label = [[UILabel alloc] initWithFrame:CGRectZero];
        self.label.text = LOC(@"EMPTY");
        self.label.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.8];
        self.label.numberOfLines = 0;
        self.label.font = [UIFont systemFontOfSize:16];
        self.label.textAlignment = NSTextAlignmentCenter;
        self.label.translatesAutoresizingMaskIntoConstraints = NO;
        [self.label sizeToFit];
        [self.tableView addSubview:self.label];

        [NSLayoutConstraint activateConstraints:@[
            [self.imageView.centerXAnchor constraintEqualToAnchor:self.tableView.centerXAnchor],
            [self.imageView.bottomAnchor constraintEqualToAnchor:self.tableView.centerYAnchor constant:-30],
            [self.imageView.widthAnchor constraintEqualToConstant:48],
            [self.imageView.heightAnchor constraintEqualToConstant:48],

            [self.label.centerXAnchor constraintEqualToAnchor:self.tableView.centerXAnchor],
            [self.label.topAnchor constraintEqualToAnchor:self.imageView.bottomAnchor constant:20],
            [self.label.leadingAnchor constraintEqualToAnchor:self.tableView.leadingAnchor constant:20],
            [self.label.trailingAnchor constraintEqualToAnchor:self.tableView.trailingAnchor constant:-20],
        ]];
    }
}

- (void)dealloc {
    if (self.themeObserver) {
        [[NSNotificationCenter defaultCenter] removeObserver:self.themeObserver];
    }
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)reloadData {
    [self refreshAudioFiles];
    [self updatePlaylistHeader];
    [self.tableView reloadData];
}

- (void)refreshAudioFiles {
    NSURL *documentsURL = [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] lastObject];
    NSURL *downloadsURL = [documentsURL URLByAppendingPathComponent:@"YTMusicUltimate"];

    NSError *error;
    NSArray *allFiles = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:downloadsURL.path error:&error];

    if (error) {
        NSLog(@"Error reading contents of directory: %@", error.localizedDescription);
        return;
    }

    NSPredicate *m4aPredicate = [NSPredicate predicateWithFormat:@"SELF ENDSWITH[c] '.m4a'"];
    NSPredicate *mp3Predicate = [NSPredicate predicateWithFormat:@"SELF ENDSWITH[c] '.mp3'"];
    NSPredicate *predicate = [NSCompoundPredicate orPredicateWithSubpredicates:@[m4aPredicate, mp3Predicate]];

    self.audioFiles = [NSMutableArray arrayWithArray:[allFiles filteredArrayUsingPredicate:predicate]];

    [self applyThemeColors];
}

#pragma mark - Table view stuff
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0 && self.audioFiles.count > 0) return @"SAVED TRACKS";
    if (section == 1 && self.audioFiles.count > 0) return @"PLAYLIST ACTIONS";
    return nil;
}

- (void)tableView:(UITableView *)tableView willDisplayHeaderView:(UIView *)view forSection:(NSInteger)section {
    if ([view isKindOfClass:[UITableViewHeaderFooterView class]]) {
        UITableViewHeaderFooterView *hf = (UITableViewHeaderFooterView *)view;
        hf.textLabel.textColor = LGTheme.shared.palette.mu ?: [[UIColor whiteColor] colorWithAlphaComponent:0.75f];
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return section == 1 ? @"\n" : nil;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 1 && self.audioFiles.count == 0) {
        return 0;
    }
    return UITableViewAutomaticDimension;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) {
        return self.audioFiles.count;
    }

    if (section == 1) {
        return 2;
    }

    return 0;
}

- (void)applyGlassBackgroundToCell:(UITableViewCell *)cell {
    cell.backgroundColor = [UIColor clearColor];
    cell.contentView.backgroundColor = [UIColor clearColor];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    if (![cell.backgroundView isKindOfClass:[UIView class]] || cell.backgroundView.tag != 9401) {
        UIView *wrap = [[UIView alloc] initWithFrame:CGRectZero];
        wrap.tag = 9401;
        wrap.backgroundColor = [UIColor clearColor];
        LGGlassView *g = [[LGGlassView alloc] initWithRadius:16.0f dark:LGTheme.shared.dark];
        g.translatesAutoresizingMaskIntoConstraints = NO;
        [wrap addSubview:g];
        [NSLayoutConstraint activateConstraints:@[
            [g.leadingAnchor constraintEqualToAnchor:wrap.leadingAnchor],
            [g.trailingAnchor constraintEqualToAnchor:wrap.trailingAnchor],
            [g.topAnchor constraintEqualToAnchor:wrap.topAnchor constant:3.0f],
            [g.bottomAnchor constraintEqualToAnchor:wrap.bottomAnchor constant:-3.0f]
        ]];
        cell.backgroundView = wrap;
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    LGPalette *p = LGTheme.shared.palette;
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"cell"];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"cell"];
    }

    if (indexPath.section == 0 && indexPath.row < self.audioFiles.count) {
        [self applyGlassBackgroundToCell:cell];
        NSString *baseName = [self.audioFiles[indexPath.row] stringByDeletingPathExtension];
        NSRange sep = [baseName rangeOfString:@" - "];
        if (sep.location != NSNotFound) {
            cell.textLabel.text = [baseName substringFromIndex:NSMaxRange(sep)];
            cell.detailTextLabel.text = [baseName substringToIndex:sep.location];
        } else {
            cell.textLabel.text = baseName;
            cell.detailTextLabel.text = @"Downloaded Track";
        }
        cell.textLabel.numberOfLines = 0;
        cell.textLabel.font = [UIFont systemFontOfSize:15.0f weight:UIFontWeightSemibold];
        cell.textLabel.textColor = p.tx ?: [UIColor whiteColor];
        cell.detailTextLabel.textColor = p.mu ?: [[UIColor whiteColor] colorWithAlphaComponent:0.7f];

        NSString *imageName = [NSString stringWithFormat:@"%@.png", [self.audioFiles[indexPath.row] stringByDeletingPathExtension]];
        NSString *documentsDirectory = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES)[0];

        UIImage *image = [UIImage imageWithContentsOfFile:[[documentsDirectory stringByAppendingPathComponent:@"YTMusicUltimate"] stringByAppendingPathComponent:imageName]];
        CGFloat targetSize = 40.0;
        CGFloat scaleFactor = image ? (targetSize / MAX(1.0, MAX(image.size.width, image.size.height))) : 1.0;
        CGSize scaledSize = image ? CGSizeMake(image.size.width * scaleFactor, image.size.height * scaleFactor) : CGSizeMake(targetSize, targetSize);
        UIGraphicsBeginImageContextWithOptions(scaledSize, NO, 0.0);
        [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, scaledSize.width, scaledSize.height) cornerRadius:8] addClip];
        [image drawInRect:CGRectMake(0, 0, scaledSize.width, scaledSize.height)];
        UIImage *roundedImage = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        roundedImage = [roundedImage imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
        cell.imageView.image = roundedImage;
    }

    else if (indexPath.section == 1) {
        cell = [tableView dequeueReusableCellWithIdentifier:@"cell0"];
        if (!cell) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"cell0"];
        }
        [self applyGlassBackgroundToCell:cell];
        NSArray *settingsData = @[
            @{@"title": LOC(@"SHARE_ALL"), @"icon": @"square.and.arrow.up.on.square"},
            @{@"title": LOC(@"REMOVE_ALL"), @"icon": @"trash"},
        ];

        NSDictionary *data = settingsData[indexPath.row];

        cell.textLabel.text = data[@"title"];
        cell.textLabel.textColor = p.tx ?: [UIColor whiteColor];
        cell.textLabel.adjustsFontSizeToFitWidth = YES;
        cell.imageView.image = [UIImage systemImageNamed:data[@"icon"]];
        cell.imageView.tintColor = indexPath.row == 1 ? [UIColor systemRedColor] : (p.a1 ?: [UIColor systemBlueColor]);
    }

    return cell;
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) {
        UIContextualAction *shareAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:@"" handler:^(UIContextualAction * _Nonnull action, __kindof UIView * _Nonnull sourceView, void (^ _Nonnull completionHandler)(BOOL)) {
            [self showActivityViewControllerForIndexPath:indexPath];
            completionHandler(YES);
        }];
        shareAction.image = [UIImage systemImageNamed:@"square.and.arrow.up"];
        shareAction.backgroundColor = [UIColor systemBlueColor];

        UIContextualAction *renameAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:@"" handler:^(UIContextualAction * _Nonnull action, __kindof UIView * _Nonnull sourceView, void (^ _Nonnull completionHandler)(BOOL)) {
            [self renameFileForIndexPath:indexPath];
            completionHandler(YES);
        }];
        renameAction.image = [UIImage systemImageNamed:@"pencil"];
        renameAction.backgroundColor = [UIColor systemOrangeColor];

        UIContextualAction *deleteAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:@"" handler:^(UIContextualAction * _Nonnull action, __kindof UIView * _Nonnull sourceView, void (^ _Nonnull completionHandler)(BOOL)) {
            [self deleteFileForIndexPath:indexPath];
            completionHandler(YES);
        }];
        deleteAction.image = [UIImage systemImageNamed:@"trash"];

        UISwipeActionsConfiguration *configuration = [UISwipeActionsConfiguration configurationWithActions:@[deleteAction, renameAction, shareAction]];
        configuration.performsFirstActionWithFullSwipe = YES;

        return configuration;
    } else {
        return nil;
    }
}

- (void)showActivityViewControllerForIndexPath:(NSIndexPath *)indexPath {
    NSURL *documentsURL = [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] lastObject];
    NSURL *audioURL = [documentsURL URLByAppendingPathComponent:[NSString stringWithFormat:@"YTMusicUltimate/%@", self.audioFiles[indexPath.row]]];

    [self activityControllerWithObjects:@[audioURL] sender:[self.tableView cellForRowAtIndexPath:indexPath]];
}

- (void)renameFileForIndexPath:(NSIndexPath *)indexPath {
    NSURL *documentsURL = [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] lastObject];
    NSURL *audioURL = [documentsURL URLByAppendingPathComponent:[NSString stringWithFormat:@"YTMusicUltimate/%@", self.audioFiles[indexPath.row]]];
    NSURL *coverURL = [documentsURL URLByAppendingPathComponent:[NSString stringWithFormat:@"YTMusicUltimate/%@.png", [self.audioFiles[indexPath.row] stringByDeletingPathExtension]]];

    UITextView *textView = [[UITextView alloc] init];
    textView.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.15];
    textView.layer.cornerRadius = 3.0;
    textView.layer.borderWidth = 1.0;
    textView.layer.borderColor = [[UIColor grayColor] colorWithAlphaComponent:0.5].CGColor;
    textView.textColor = [UIColor whiteColor];
    textView.text = [self.audioFiles[indexPath.row] stringByDeletingPathExtension];
    textView.editable = YES;
    textView.scrollEnabled = YES;
    textView.textAlignment = NSTextAlignmentNatural;
    textView.font = [UIFont systemFontOfSize:14.0];

    YTAlertView *alertView = [NSClassFromString(@"YTAlertView") confirmationDialogWithAction:^{
        NSString *newName = [textView.text stringByReplacingOccurrencesOfString:@"/" withString:@""];
        NSString *extension = [audioURL pathExtension];

        NSURL *newAudioURL = [documentsURL URLByAppendingPathComponent:[NSString stringWithFormat:@"YTMusicUltimate/%@.%@", newName, extension]];
        NSURL *newCoverURL = [documentsURL URLByAppendingPathComponent:[NSString stringWithFormat:@"YTMusicUltimate/%@.png", newName]];

        NSError *error = nil;
        [[NSFileManager defaultManager] moveItemAtURL:audioURL toURL:newAudioURL error:&error];
        [[NSFileManager defaultManager] moveItemAtURL:coverURL toURL:newCoverURL error:&error];

        if (!error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self reloadData];
                [[NSClassFromString(@"YTMToastController") alloc] showMessage:LOC(@"DONE")];
            });
        }
    }
    actionTitle:LOC(@"RENAME")];
    alertView.title = @"YTMusicUltimate";

    UIView *customView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, alertView.frameForDialog.size.width - 50, 75)];
    textView.frame = customView.frame;
    [customView addSubview:textView];

    alertView.customContentView = customView;
    [alertView show];
}

- (void)deleteFileForIndexPath:(NSIndexPath *)indexPath {
    NSURL *documentsURL = [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] lastObject];
    NSURL *audioURL = [documentsURL URLByAppendingPathComponent:[NSString stringWithFormat:@"YTMusicUltimate/%@", self.audioFiles[indexPath.row]]];
    NSURL *coverURL = [documentsURL URLByAppendingPathComponent:[NSString stringWithFormat:@"YTMusicUltimate/%@.png", [self.audioFiles[indexPath.row] stringByDeletingPathExtension]]];

    YTAlertView *alertView = [NSClassFromString(@"YTAlertView") confirmationDialogWithAction:^{
        BOOL audioRemoved = [[NSFileManager defaultManager] removeItemAtURL:audioURL error:nil];
        BOOL coverRemoved = [[NSFileManager defaultManager] removeItemAtURL:coverURL error:nil];

        if (audioRemoved && coverRemoved) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.audioFiles removeObjectAtIndex:indexPath.row];
                [self.tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
                [self maybeShowEmptyState];
            });
        }
    }
    actionTitle:LOC(@"DELETE")];
    alertView.title = @"YTMusicUltimate";
    alertView.subtitle = [NSString stringWithFormat:LOC(@"DELETE_MESSAGE"), [self.audioFiles[indexPath.row] stringByDeletingPathExtension]];
    [alertView show];
}

- (BOOL)tableView:(UITableView *)tableView shouldHighlightRowAtIndexPath:(NSIndexPath *)indexPath {
    return YES;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    // Playing song can conflict with YTMusicPlayer
    if (indexPath.section == 0) {
        NSURL *documentsURL = [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] lastObject];
        NSURL *audioURL = [documentsURL URLByAppendingPathComponent:[NSString stringWithFormat:@"YTMusicUltimate/%@", self.audioFiles[indexPath.row]]];
        NSString *imageName = [NSString stringWithFormat:@"%@.png", [self.audioFiles[indexPath.row] stringByDeletingPathExtension]];
        NSString *documentsDirectory = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES)[0];

        NSString *authorTitleString = [self.audioFiles[indexPath.row] stringByDeletingPathExtension];
        // NSArray *components = [authorTitleString componentsSeparatedByString:@" - "];

        AVAudioSession *audioSession = [AVAudioSession sharedInstance];

        NSError *setCategoryError = nil;
        BOOL success = [audioSession setCategory:AVAudioSessionCategoryPlayback error:&setCategoryError];

        if (!success) {
            NSLog(@"Error setting AVAudioSession category: %@", setCategoryError.localizedDescription);
        }

        NSError *activationError = nil;
        success = [audioSession setActive:YES error:&activationError];

        if (!success) {
            NSLog(@"Error activating AVAudioSession: %@", activationError.localizedDescription);
        }

        AVPlayerItem *playerItem = [AVPlayerItem playerItemWithURL:audioURL];
        AVMutableMetadataItem *titleMetadataItem = [AVMutableMetadataItem metadataItem];
        titleMetadataItem.key = AVMetadataCommonKeyTitle;
        titleMetadataItem.keySpace = AVMetadataKeySpaceCommon;
        titleMetadataItem.value = authorTitleString;

        // AVMutableMetadataItem *authorMetadataItem = [AVMutableMetadataItem metadataItem];
        // authorMetadataItem.key = AVMetadataCommonKeyAlbumName; // It doesn't works
        // authorMetadataItem.keySpace = AVMetadataKeySpaceCommon;
        // authorMetadataItem.value = components[0];

        AVMutableMetadataItem *artworkMetadataItem = [AVMutableMetadataItem metadataItem];
        artworkMetadataItem.key = AVMetadataCommonKeyArtwork;
        artworkMetadataItem.keySpace = AVMetadataKeySpaceCommon;
        UIImage *artworkImage = [UIImage imageWithContentsOfFile:[[documentsDirectory stringByAppendingPathComponent:@"YTMusicUltimate"] stringByAppendingPathComponent:imageName]];
        artworkMetadataItem.value = UIImagePNGRepresentation(artworkImage);

        playerItem.externalMetadata = @[titleMetadataItem, artworkMetadataItem];

        AVPlayerViewController *playerViewController = [[AVPlayerViewController alloc] init];
        AVPlayer *player = [AVPlayer playerWithPlayerItem:playerItem];
        playerViewController.player = player;

        [self presentViewController:playerViewController animated:YES completion:^{
            [player play];
        }];
    }

    if (indexPath.section == 1) {
        if (indexPath.row == 0) {
            [self shareAll:indexPath];
        }

        if (indexPath.row == 1) {
            [self removeAll];
        }
    }

    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

- (void)shareAll:(NSIndexPath *)indexPath {
    NSURL *documentsURL = [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] lastObject];
    NSURL *audiosFolder = [documentsURL URLByAppendingPathComponent:@"YTMusicUltimate"];

    NSArray<NSURL *> *files = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:audiosFolder
                                                               includingPropertiesForKeys:@[NSURLNameKey, NSURLIsDirectoryKey]
                                                                                  options:NSDirectoryEnumerationSkipsHiddenFiles
                                                                                    error:nil];

    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"pathExtension.lowercaseString == 'm4a' || pathExtension.lowercaseString == 'mp3'"];
    files = [files filteredArrayUsingPredicate:predicate];

    [self activityControllerWithObjects:files sender:[self.tableView cellForRowAtIndexPath:indexPath]];
}

- (void)removeAll {
    NSURL *documentsURL = [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] lastObject];
    NSURL *audiosFolder = [documentsURL URLByAppendingPathComponent:@"YTMusicUltimate"];

    YTAlertView *alertView = [NSClassFromString(@"YTAlertView") confirmationDialogWithAction:^{
        BOOL audiosRemoved = [[NSFileManager defaultManager] removeItemAtURL:audiosFolder error:nil];

        if (audiosRemoved) {
            [self.audioFiles removeAllObjects];
            self.imageView.tintColor = [[UIColor whiteColor] colorWithAlphaComponent:0.8];
            self.label.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.8];
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.tableView reloadData];
            });
        }
    }
    actionTitle:LOC(@"DELETE")];
    alertView.title = @"YTMusicUltimate";
    alertView.subtitle = [NSString stringWithFormat:LOC(@"DELETE_MESSAGE"), LOC(@"ALL_DOWNLOADS")];
    [alertView show];
}

- (void)activityControllerWithObjects:(NSArray<id> *)items sender:(UIView *)sender {
    if (items.count == 0) return;

    UIActivityViewController *activityVC = [[UIActivityViewController alloc] initWithActivityItems:items applicationActivities:nil];
    activityVC.excludedActivityTypes = @[UIActivityTypeAssignToContact, UIActivityTypePrint];

    UIPopoverPresentationController *popover = activityVC.popoverPresentationController;
    if (popover && sender) {
        popover.sourceView = sender;
        popover.sourceRect = CGRectMake(CGRectGetWidth(sender.bounds) - 10.0, CGRectGetMidY(sender.bounds), 1.0, 1.0);
        popover.permittedArrowDirections = UIPopoverArrowDirectionRight;
    }

    [self presentViewController:activityVC animated:YES completion:nil];
}

@end
