#import "YTMDownloads.h"
#import "YTMDownloadStore.h"
#import "YTMDownloadsCollectionViewController.h"
#import "YTMLocalPlayerViewController.h"

typedef NS_ENUM(NSInteger, YTMDownloadsMode) {
    YTMDownloadsModeAllSongs = 0,
    YTMDownloadsModeCollections
};

@implementation YTMDownloads

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = [UIColor colorWithRed:3/255.0 green:3/255.0 blue:3/255.0 alpha:1.0];

    UIView *segmentedControlContainer = [[UIView alloc] init];
    segmentedControlContainer.translatesAutoresizingMaskIntoConstraints = NO;
    segmentedControlContainer.backgroundColor = self.view.backgroundColor;
    [self.view addSubview:segmentedControlContainer];

    self.segmentedControl = [[UISegmentedControl alloc] initWithItems:@[@"All Songs", @"Albums & Playlists"]];
    self.segmentedControl.translatesAutoresizingMaskIntoConstraints = NO;
    self.segmentedControl.selectedSegmentIndex = 0;
    self.segmentedControl.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.12];
    self.segmentedControl.selectedSegmentTintColor = [UIColor colorWithRed:0.93 green:0.18 blue:0.29 alpha:1.0];
    self.segmentedControl.layer.cornerRadius = 12.0;
    self.segmentedControl.clipsToBounds = YES;
    [self.segmentedControl setTitleTextAttributes:@{
        NSForegroundColorAttributeName: [[UIColor whiteColor] colorWithAlphaComponent:0.82],
        NSFontAttributeName: [UIFont systemFontOfSize:13.0 weight:UIFontWeightSemibold]
    } forState:UIControlStateNormal];
    [self.segmentedControl setTitleTextAttributes:@{
        NSForegroundColorAttributeName: [UIColor whiteColor],
        NSFontAttributeName: [UIFont systemFontOfSize:13.0 weight:UIFontWeightBold]
    } forState:UIControlStateSelected];
    [self.segmentedControl addTarget:self action:@selector(segmentChanged:) forControlEvents:UIControlEventValueChanged];
    [segmentedControlContainer addSubview:self.segmentedControl];

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.backgroundColor = self.view.backgroundColor;
    self.tableView.contentInset = UIEdgeInsetsMake(0.0, 0.0, 110.0, 0.0);
    self.tableView.scrollIndicatorInsets = self.tableView.contentInset;
    [self.view addSubview:self.tableView];

    self.imageView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"music.note.list"]];
    self.imageView.translatesAutoresizingMaskIntoConstraints = NO;
    self.imageView.contentMode = UIViewContentModeScaleAspectFit;
    self.imageView.tintColor = [[UIColor whiteColor] colorWithAlphaComponent:0.8];
    [self.view addSubview:self.imageView];

    self.label = [[UILabel alloc] initWithFrame:CGRectZero];
    self.label.translatesAutoresizingMaskIntoConstraints = NO;
    self.label.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.8];
    self.label.numberOfLines = 0;
    self.label.font = [UIFont systemFontOfSize:16];
    self.label.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:self.label];

    [NSLayoutConstraint activateConstraints:@[
        [segmentedControlContainer.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [segmentedControlContainer.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [segmentedControlContainer.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [segmentedControlContainer.heightAnchor constraintEqualToConstant:52.0],

        [self.segmentedControl.topAnchor constraintEqualToAnchor:segmentedControlContainer.topAnchor constant:8.0],
        [self.segmentedControl.leadingAnchor constraintEqualToAnchor:segmentedControlContainer.leadingAnchor constant:16.0],
        [self.segmentedControl.trailingAnchor constraintEqualToAnchor:segmentedControlContainer.trailingAnchor constant:-16.0],
        [self.segmentedControl.heightAnchor constraintEqualToConstant:36.0],

        [self.tableView.topAnchor constraintEqualToAnchor:segmentedControlContainer.bottomAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        [self.imageView.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.imageView.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor constant:-36.0],
        [self.imageView.widthAnchor constraintEqualToConstant:48.0],
        [self.imageView.heightAnchor constraintEqualToConstant:48.0],

        [self.label.topAnchor constraintEqualToAnchor:self.imageView.bottomAnchor constant:18.0],
        [self.label.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20.0],
        [self.label.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20.0]
    ]];

    [self.view bringSubviewToFront:segmentedControlContainer];

    [self refreshLibrary];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reloadData) name:@"ReloadDataNotification" object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)segmentChanged:(UISegmentedControl *)sender {
    [self updateEmptyState];
    [self.tableView reloadData];
}

- (void)reloadData {
    [self refreshLibrary];
    [self.tableView reloadData];
}

- (void)refreshLibrary {
    self.tracks = [[YTMDownloadStore allTracks] mutableCopy];
    self.collections = [[YTMDownloadStore collectionsFromTracks:self.tracks] mutableCopy];
    [self updateEmptyState];
}

- (void)updateEmptyState {
    BOOL isEmpty = ([self currentMode] == YTMDownloadsModeAllSongs) ? self.tracks.count == 0 : self.collections.count == 0;
    self.imageView.hidden = !isEmpty;
    self.label.hidden = !isEmpty;
    self.label.text = [self currentMode] == YTMDownloadsModeAllSongs ? @"Downloaded songs will show here" : @"Downloaded albums and playlists will show here";
}

- (YTMDownloadsMode)currentMode {
    return self.segmentedControl.selectedSegmentIndex == 0 ? YTMDownloadsModeAllSongs : YTMDownloadsModeCollections;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) {
        return [self currentMode] == YTMDownloadsModeAllSongs ? self.tracks.count : self.collections.count;
    }

    if (self.tracks.count == 0) {
        return 0;
    }

    return [self currentMode] == YTMDownloadsModeAllSongs ? 3 : 2;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 1 && self.tracks.count > 0) {
        return @"Actions";
    }

    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"downloads-cell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"downloads-cell"];
    }

    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.backgroundColor = [[UIColor grayColor] colorWithAlphaComponent:0.25];
    cell.textLabel.textColor = [UIColor whiteColor];
    cell.detailTextLabel.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.7];
    cell.textLabel.numberOfLines = 0;
    cell.detailTextLabel.numberOfLines = 0;
    cell.imageView.image = nil;

    if (indexPath.section == 0 && [self currentMode] == YTMDownloadsModeAllSongs) {
        NSDictionary *track = self.tracks[indexPath.row];
        cell.textLabel.text = track[@"displayName"];
        cell.detailTextLabel.text = track[@"artist"];
        cell.imageView.image = [self artworkImageForTrack:track targetSize:37.5];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        return cell;
    }

    if (indexPath.section == 0 && [self currentMode] == YTMDownloadsModeCollections) {
        NSDictionary *collection = self.collections[indexPath.row];
        cell.textLabel.text = collection[@"title"];
        cell.detailTextLabel.text = collection[@"subtitle"];
        cell.imageView.image = [self artworkImageForCollection:collection targetSize:40.0];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        return cell;
    }

    NSArray<NSDictionary *> *actions = [self currentMode] == YTMDownloadsModeAllSongs ? @[
        @{@"title": @"Shuffle All", @"icon": @"shuffle"},
        @{@"title": LOC(@"SHARE_ALL"), @"icon": @"square.and.arrow.up.on.square"},
        @{@"title": LOC(@"REMOVE_ALL"), @"icon": @"trash"}
    ] : @[
        @{@"title": LOC(@"SHARE_ALL"), @"icon": @"square.and.arrow.up.on.square"},
        @{@"title": LOC(@"REMOVE_ALL"), @"icon": @"trash"}
    ];

    NSDictionary *action = actions[indexPath.row];
    cell.textLabel.text = action[@"title"];
    cell.detailTextLabel.text = nil;
    cell.imageView.image = [UIImage systemImageNamed:action[@"icon"]];
    cell.imageView.tintColor = [action[@"icon"] isEqualToString:@"trash"] ? [UIColor redColor] : [UIColor colorWithRed:30.0/255.0 green:150.0/255.0 blue:245.0/255.0 alpha:1.0];
    return cell;
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section != 0) {
        return nil;
    }

    if ([self currentMode] == YTMDownloadsModeAllSongs) {
        NSMutableDictionary *track = self.tracks[indexPath.row];

        UIContextualAction *shareAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:@"" handler:^(__unused UIContextualAction *action, __unused UIView *sourceView, void (^completionHandler)(BOOL)) {
            [self activityControllerWithObjects:@[track[@"audioURL"]] sender:[self.tableView cellForRowAtIndexPath:indexPath]];
            completionHandler(YES);
        }];
        shareAction.image = [UIImage systemImageNamed:@"square.and.arrow.up"];
        shareAction.backgroundColor = [UIColor systemBlueColor];

        UIContextualAction *renameAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:@"" handler:^(__unused UIContextualAction *action, __unused UIView *sourceView, void (^completionHandler)(BOOL)) {
            [self renameTrack:track];
            completionHandler(YES);
        }];
        renameAction.image = [UIImage systemImageNamed:@"pencil"];
        renameAction.backgroundColor = [UIColor systemOrangeColor];

        UIContextualAction *deleteAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:@"" handler:^(__unused UIContextualAction *action, __unused UIView *sourceView, void (^completionHandler)(BOOL)) {
            [self deleteTrack:track];
            completionHandler(YES);
        }];
        deleteAction.image = [UIImage systemImageNamed:@"trash"];

        UISwipeActionsConfiguration *configuration = [UISwipeActionsConfiguration configurationWithActions:@[deleteAction, renameAction, shareAction]];
        configuration.performsFirstActionWithFullSwipe = YES;
        return configuration;
    }

    NSDictionary *collection = self.collections[indexPath.row];

    UIContextualAction *shareAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:@"" handler:^(__unused UIContextualAction *action, __unused UIView *sourceView, void (^completionHandler)(BOOL)) {
        NSArray *collectionTracks = [YTMDownloadStore tracksForCollectionIdentifier:collection[@"identifier"] tracks:self.tracks];
        [self activityControllerWithObjects:[YTMDownloadStore audioURLsForTracks:collectionTracks] sender:[self.tableView cellForRowAtIndexPath:indexPath]];
        completionHandler(YES);
    }];
    shareAction.image = [UIImage systemImageNamed:@"square.and.arrow.up"];
    shareAction.backgroundColor = [UIColor systemBlueColor];

    UIContextualAction *renameAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:@"" handler:^(__unused UIContextualAction *action, __unused UIView *sourceView, void (^completionHandler)(BOOL)) {
        [self renameCollection:collection];
        completionHandler(YES);
    }];
    renameAction.image = [UIImage systemImageNamed:@"pencil"];
    renameAction.backgroundColor = [UIColor systemOrangeColor];

    UIContextualAction *deleteAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:@"" handler:^(__unused UIContextualAction *action, __unused UIView *sourceView, void (^completionHandler)(BOOL)) {
        [self deleteCollection:collection];
        completionHandler(YES);
    }];
    deleteAction.image = [UIImage systemImageNamed:@"trash"];

    UISwipeActionsConfiguration *configuration = [UISwipeActionsConfiguration configurationWithActions:@[deleteAction, renameAction, shareAction]];
    configuration.performsFirstActionWithFullSwipe = YES;
    return configuration;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0 && [self currentMode] == YTMDownloadsModeAllSongs) {
        [self playTracks:self.tracks startIndex:indexPath.row shuffle:NO collectionTitle:nil];
    } else if (indexPath.section == 0 && [self currentMode] == YTMDownloadsModeCollections) {
        [self openCollection:self.collections[indexPath.row]];
    } else if (indexPath.section == 1 && [self currentMode] == YTMDownloadsModeAllSongs) {
        if (indexPath.row == 0) {
            [self playTracks:self.tracks startIndex:0 shuffle:YES collectionTitle:nil];
        } else if (indexPath.row == 1) {
            [self activityControllerWithObjects:[YTMDownloadStore audioURLsForTracks:self.tracks] sender:[self.tableView cellForRowAtIndexPath:indexPath]];
        } else if (indexPath.row == 2) {
            [self removeAll];
        }
    } else if (indexPath.section == 1) {
        if (indexPath.row == 0) {
            [self activityControllerWithObjects:[YTMDownloadStore audioURLsForTracks:self.tracks] sender:[self.tableView cellForRowAtIndexPath:indexPath]];
        } else if (indexPath.row == 1) {
            [self removeAll];
        }
    }

    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

- (void)openCollection:(NSDictionary *)collection {
    NSArray<NSMutableDictionary *> *collectionTracks = [YTMDownloadStore tracksForCollectionIdentifier:collection[@"identifier"] tracks:self.tracks];
    YTMDownloadsCollectionViewController *controller = [[YTMDownloadsCollectionViewController alloc] initWithCollection:collection tracks:collectionTracks];

    __weak typeof(self) weakSelf = self;
    controller.onLibraryChanged = ^{
        [weakSelf reloadData];
    };

    UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:controller];
    navigationController.modalPresentationStyle = UIModalPresentationFullScreen;
    [self presentViewController:navigationController animated:YES completion:nil];
}

- (void)renameTrack:(NSMutableDictionary *)track {
    UITextView *textView = [self configuredTextViewWithText:track[@"displayName"]];
    YTAlertView *alertView = [NSClassFromString(@"YTAlertView") confirmationDialogWithAction:^{
        NSError *renameError = nil;
        [YTMDownloadStore renameTrack:track toDisplayName:textView.text error:&renameError];
        if (!renameError) {
            [self reloadData];
            Class toastClass = NSClassFromString(@"YTMToastController");
            if (toastClass) {
                [(id)[toastClass new] showMessage:LOC(@"DONE")];
            }
        }
    } actionTitle:LOC(@"RENAME")];
    alertView.title = @"YTMusicUltimate";

    UIView *customView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, alertView.frameForDialog.size.width - 50, 75)];
    textView.frame = customView.bounds;
    [customView addSubview:textView];
    alertView.customContentView = customView;
    [alertView show];
}

- (void)renameCollection:(NSDictionary *)collection {
    UITextView *textView = [self configuredTextViewWithText:collection[@"title"]];
    YTAlertView *alertView = [NSClassFromString(@"YTAlertView") confirmationDialogWithAction:^{
        NSError *renameError = nil;
        [YTMDownloadStore renameCollectionWithIdentifier:collection[@"identifier"] title:textView.text tracks:self.tracks error:&renameError];
        if (!renameError) {
            [self reloadData];
            Class toastClass = NSClassFromString(@"YTMToastController");
            if (toastClass) {
                [(id)[toastClass new] showMessage:LOC(@"DONE")];
            }
        }
    } actionTitle:LOC(@"RENAME")];
    alertView.title = @"YTMusicUltimate";

    UIView *customView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, alertView.frameForDialog.size.width - 50, 75)];
    textView.frame = customView.bounds;
    [customView addSubview:textView];
    alertView.customContentView = customView;
    [alertView show];
}

- (UITextView *)configuredTextViewWithText:(NSString *)text {
    UITextView *textView = [[UITextView alloc] init];
    textView.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.15];
    textView.layer.cornerRadius = 3.0;
    textView.layer.borderWidth = 1.0;
    textView.layer.borderColor = [[UIColor grayColor] colorWithAlphaComponent:0.5].CGColor;
    textView.textColor = [UIColor whiteColor];
    textView.text = text ?: @"";
    textView.editable = YES;
    textView.scrollEnabled = YES;
    textView.textAlignment = NSTextAlignmentNatural;
    textView.font = [UIFont systemFontOfSize:14.0];
    return textView;
}

- (void)deleteTrack:(NSDictionary *)track {
    YTAlertView *alertView = [NSClassFromString(@"YTAlertView") confirmationDialogWithAction:^{
        NSError *deleteError = nil;
        [YTMDownloadStore deleteTrack:track error:&deleteError];
        if (!deleteError) {
            [self reloadData];
        }
    } actionTitle:LOC(@"DELETE")];
    alertView.title = @"YTMusicUltimate";
    alertView.subtitle = [NSString stringWithFormat:LOC(@"DELETE_MESSAGE"), track[@"displayName"]];
    [alertView show];
}

- (void)deleteCollection:(NSDictionary *)collection {
    YTAlertView *alertView = [NSClassFromString(@"YTAlertView") confirmationDialogWithAction:^{
        NSError *deleteError = nil;
        [YTMDownloadStore deleteCollectionWithIdentifier:collection[@"identifier"] tracks:self.tracks error:&deleteError];
        if (!deleteError) {
            [self reloadData];
        }
    } actionTitle:LOC(@"DELETE")];
    alertView.title = @"YTMusicUltimate";
    alertView.subtitle = [NSString stringWithFormat:LOC(@"DELETE_MESSAGE"), collection[@"title"] ?: @"collection"];
    [alertView show];
}

- (void)removeAll {
    YTAlertView *alertView = [NSClassFromString(@"YTAlertView") confirmationDialogWithAction:^{
        NSError *deleteError = nil;
        [YTMDownloadStore deleteAllDownloads:&deleteError];
        if (!deleteError) {
            [self reloadData];
        }
    } actionTitle:LOC(@"DELETE")];
    alertView.title = @"YTMusicUltimate";
    alertView.subtitle = [NSString stringWithFormat:LOC(@"DELETE_MESSAGE"), LOC(@"ALL_DOWNLOADS")];
    [alertView show];
}

- (void)playTracks:(NSArray<NSDictionary *> *)tracks startIndex:(NSInteger)startIndex shuffle:(BOOL)shuffle collectionTitle:(NSString *)collectionTitle {
    NSArray<NSDictionary *> *playbackTracks = [self playbackOrderForTracks:tracks shuffle:shuffle];
    NSInteger playbackStartIndex = shuffle ? 0 : startIndex;
    if (playbackTracks.count == 0 || playbackStartIndex < 0 || playbackStartIndex >= playbackTracks.count) {
        return;
    }

    if (collectionTitle.length > 0) {
        NSMutableArray<NSMutableDictionary *> *decoratedTracks = [NSMutableArray array];
        for (NSDictionary *track in playbackTracks) {
            NSMutableDictionary *mutableTrack = [track mutableCopy];
            mutableTrack[@"collectionTitle"] = collectionTitle;
            [decoratedTracks addObject:mutableTrack];
        }
        playbackTracks = decoratedTracks;
    }

    YTMLocalPlayerViewController *playerViewController = [[YTMLocalPlayerViewController alloc] initWithTracks:playbackTracks startIndex:playbackStartIndex];
    UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:playerViewController];
    navigationController.modalPresentationStyle = UIModalPresentationPageSheet;
    if (@available(iOS 15.0, *)) {
        navigationController.sheetPresentationController.detents = @[[UISheetPresentationControllerDetent largeDetent]];
        navigationController.sheetPresentationController.prefersGrabberVisible = YES;
        navigationController.sheetPresentationController.preferredCornerRadius = 24.0;
    }
    [self presentViewController:navigationController animated:YES completion:nil];
}

- (NSArray<NSDictionary *> *)playbackOrderForTracks:(NSArray<NSDictionary *> *)tracks shuffle:(BOOL)shuffle {
    NSMutableArray<NSDictionary *> *orderedTracks = [tracks mutableCopy];
    if (shuffle) {
        for (NSUInteger index = orderedTracks.count; index > 1; index--) {
            [orderedTracks exchangeObjectAtIndex:index - 1 withObjectAtIndex:arc4random_uniform((u_int32_t)index)];
        }
    }

    return orderedTracks;
}

- (AVPlayerItem *)playerItemForTrack:(NSDictionary *)track collectionTitle:(NSString *)collectionTitle {
    NSURL *audioURL = track[@"audioURL"];
    if (!audioURL) {
        return nil;
    }

    AVPlayerItem *playerItem = [AVPlayerItem playerItemWithURL:audioURL];
    NSMutableArray *metadataItems = [NSMutableArray array];

    AVMutableMetadataItem *titleMetadataItem = [AVMutableMetadataItem metadataItem];
    titleMetadataItem.key = AVMetadataCommonKeyTitle;
    titleMetadataItem.keySpace = AVMetadataKeySpaceCommon;
    titleMetadataItem.value = track[@"displayName"];
    [metadataItems addObject:titleMetadataItem];

    if (collectionTitle.length > 0) {
        AVMutableMetadataItem *albumMetadataItem = [AVMutableMetadataItem metadataItem];
        albumMetadataItem.key = AVMetadataCommonKeyAlbumName;
        albumMetadataItem.keySpace = AVMetadataKeySpaceCommon;
        albumMetadataItem.value = collectionTitle;
        [metadataItems addObject:albumMetadataItem];
    }

    NSURL *coverURL = track[@"coverURL"];
    UIImage *artworkImage = coverURL ? [UIImage imageWithContentsOfFile:coverURL.path] : nil;
    if (artworkImage) {
        AVMutableMetadataItem *artworkMetadataItem = [AVMutableMetadataItem metadataItem];
        artworkMetadataItem.key = AVMetadataCommonKeyArtwork;
        artworkMetadataItem.keySpace = AVMetadataKeySpaceCommon;
        artworkMetadataItem.value = UIImagePNGRepresentation(artworkImage);
        [metadataItems addObject:artworkMetadataItem];
    }

    playerItem.externalMetadata = metadataItems;
    return playerItem;
}

- (void)configureAudioSession {
    AVAudioSession *audioSession = [AVAudioSession sharedInstance];
    [audioSession setCategory:AVAudioSessionCategoryPlayback error:nil];
    [audioSession setActive:YES error:nil];
}

- (UIImage *)artworkImageForTrack:(NSDictionary *)track targetSize:(CGFloat)targetSize {
    NSURL *coverURL = track[@"coverURL"];
    UIImage *image = coverURL ? [UIImage imageWithContentsOfFile:coverURL.path] : nil;
    return [self roundedImage:image targetSize:targetSize];
}

- (UIImage *)artworkImageForCollection:(NSDictionary *)collection targetSize:(CGFloat)targetSize {
    NSURL *coverURL = collection[@"coverURL"];
    UIImage *image = coverURL ? [UIImage imageWithContentsOfFile:coverURL.path] : nil;
    return [self roundedImage:image targetSize:targetSize];
}

- (UIImage *)roundedImage:(UIImage *)image targetSize:(CGFloat)targetSize {
    if (!image) {
        return [self placeholderArtworkImageForTargetSize:targetSize];
    }

    CGFloat scaleFactor = targetSize / MAX(image.size.width, image.size.height);
    CGSize scaledSize = CGSizeMake(image.size.width * scaleFactor, image.size.height * scaleFactor);
    UIGraphicsBeginImageContextWithOptions(scaledSize, NO, 0.0);
    [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, scaledSize.width, scaledSize.height) cornerRadius:6] addClip];
    [image drawInRect:CGRectMake(0, 0, scaledSize.width, scaledSize.height)];
    UIImage *roundedImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return [roundedImage imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
}

- (UIImage *)placeholderArtworkImageForTargetSize:(CGFloat)targetSize {
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(targetSize, targetSize)];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext * _Nonnull rendererContext) {
        CGRect rect = CGRectMake(0, 0, targetSize, targetSize);
        [[UIBezierPath bezierPathWithRoundedRect:rect cornerRadius:6.0] addClip];
        [[[UIColor whiteColor] colorWithAlphaComponent:0.08] setFill];
        UIRectFill(rect);

        UIImageSymbolConfiguration *configuration = [UIImageSymbolConfiguration configurationWithPointSize:targetSize * 0.42 weight:UIImageSymbolWeightRegular];
        UIImage *symbolImage = [[UIImage systemImageNamed:@"music.note.list"] imageWithConfiguration:configuration];
        symbolImage = [symbolImage imageWithTintColor:[[UIColor whiteColor] colorWithAlphaComponent:0.7] renderingMode:UIImageRenderingModeAlwaysOriginal];
        CGSize symbolSize = symbolImage.size;
        CGRect symbolRect = CGRectMake((targetSize - symbolSize.width) / 2.0, (targetSize - symbolSize.height) / 2.0, symbolSize.width, symbolSize.height);
        [symbolImage drawInRect:symbolRect];
    }];
}

- (void)activityControllerWithObjects:(NSArray<id> *)items sender:(UIView *)sender {
    if (items.count == 0) {
        return;
    }

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
