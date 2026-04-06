#import "YTMDownloadsCollectionViewController.h"
#import <AVKit/AVKit.h>
#import "YTMDownloadStore.h"
#import "../Headers/YTAlertView.h"
#import "../Headers/YTMToastController.h"
#import "../Headers/Localization.h"

@interface YTMDownloadsCollectionViewController ()
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSDictionary *collection;
@property (nonatomic, strong) NSArray<NSMutableDictionary *> *tracks;
@end

@implementation YTMDownloadsCollectionViewController

- (instancetype)initWithCollection:(NSDictionary *)collection tracks:(NSArray<NSMutableDictionary *> *)tracks {
    self = [super init];
    if (self) {
        _collection = collection;
        _tracks = tracks;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = [UIColor colorWithRed:3/255.0 green:3/255.0 blue:3/255.0 alpha:1.0];
    self.title = self.collection[@"title"];
    self.navigationItem.prompt = self.collection[@"subtitle"];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemClose target:self action:@selector(closeController)];

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.backgroundColor = self.view.backgroundColor;
    [self.view addSubview:self.tableView];

    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];
}

- (void)closeController {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) {
        return self.tracks.count;
    }

    return self.tracks.count > 0 ? 4 : 0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"collection-cell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"collection-cell"];
    }

    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.backgroundColor = [[UIColor grayColor] colorWithAlphaComponent:0.25];
    cell.textLabel.textColor = [UIColor whiteColor];
    cell.detailTextLabel.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.7];
    cell.textLabel.numberOfLines = 0;
    cell.detailTextLabel.numberOfLines = 0;

    if (indexPath.section == 0) {
        NSDictionary *track = self.tracks[indexPath.row];
        cell.textLabel.text = track[@"displayName"];
        NSString *subtitle = track[@"artist"];
        if (subtitle.length == 0 || [subtitle isEqualToString:track[@"displayName"]]) {
            subtitle = track[@"title"];
        }
        cell.detailTextLabel.text = subtitle;
        cell.imageView.image = [self artworkImageForTrack:track targetSize:37.5];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        return cell;
    }

    NSArray<NSDictionary *> *actions = @[
        @{@"title": @"Play All", @"icon": @"play.fill"},
        @{@"title": @"Shuffle", @"icon": @"shuffle"},
        @{@"title": LOC(@"SHARE_ALL"), @"icon": @"square.and.arrow.up.on.square"},
        @{@"title": LOC(@"DELETE"), @"icon": @"trash"}
    ];

    NSDictionary *action = actions[indexPath.row];
    cell.textLabel.text = action[@"title"];
    cell.detailTextLabel.text = nil;
    cell.imageView.image = [UIImage systemImageNamed:action[@"icon"]];
    cell.imageView.tintColor = indexPath.row == 3 ? [UIColor redColor] : [UIColor colorWithRed:30.0/255.0 green:150.0/255.0 blue:245.0/255.0 alpha:1.0];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) {
        [self playTracks:self.tracks startIndex:indexPath.row shuffle:NO];
    } else {
        if (indexPath.row == 0) {
            [self playTracks:self.tracks startIndex:0 shuffle:NO];
        } else if (indexPath.row == 1) {
            [self playTracks:self.tracks startIndex:0 shuffle:YES];
        } else if (indexPath.row == 2) {
            [self activityControllerWithObjects:[YTMDownloadStore audioURLsForTracks:self.tracks] sender:[self.tableView cellForRowAtIndexPath:indexPath]];
        } else if (indexPath.row == 3) {
            [self deleteCollection];
        }
    }

    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0) {
        return self.tracks.count > 0 ? @"Tracks" : nil;
    }

    return self.tracks.count > 0 ? @"Actions" : nil;
}

- (void)deleteCollection {
    YTAlertView *alertView = [NSClassFromString(@"YTAlertView") confirmationDialogWithAction:^{
        NSError *deleteError = nil;
        [YTMDownloadStore deleteCollectionWithIdentifier:self.collection[@"identifier"] tracks:self.tracks error:&deleteError];
        if (!deleteError) {
            if (self.onLibraryChanged) {
                self.onLibraryChanged();
            }
            Class toastClass = NSClassFromString(@"YTMToastController");
            if (toastClass) {
                [(id)[toastClass new] showMessage:LOC(@"DONE")];
            }
            [self dismissViewControllerAnimated:YES completion:nil];
        }
    } actionTitle:LOC(@"DELETE")];
    alertView.title = @"YTMusicUltimate";
    alertView.subtitle = [NSString stringWithFormat:LOC(@"DELETE_MESSAGE"), self.collection[@"title"] ?: @"collection"];
    [alertView show];
}

- (void)playTracks:(NSArray<NSDictionary *> *)tracks startIndex:(NSInteger)startIndex shuffle:(BOOL)shuffle {
    NSArray<NSDictionary *> *playbackTracks = [self playbackOrderForTracks:tracks startIndex:startIndex shuffle:shuffle];
    if (playbackTracks.count == 0) {
        return;
    }

    [self configureAudioSession];

    NSMutableArray<AVPlayerItem *> *items = [NSMutableArray array];
    for (NSDictionary *track in playbackTracks) {
        AVPlayerItem *item = [self playerItemForTrack:track];
        if (item) {
            [items addObject:item];
        }
    }

    if (items.count == 0) {
        return;
    }

    AVPlayerViewController *playerViewController = [[AVPlayerViewController alloc] init];
    playerViewController.player = [AVQueuePlayer queuePlayerWithItems:items];

    [self presentViewController:playerViewController animated:YES completion:^{
        [playerViewController.player play];
    }];
}

- (NSArray<NSDictionary *> *)playbackOrderForTracks:(NSArray<NSDictionary *> *)tracks startIndex:(NSInteger)startIndex shuffle:(BOOL)shuffle {
    NSMutableArray<NSDictionary *> *orderedTracks = [tracks mutableCopy];
    if (shuffle) {
        for (NSUInteger index = orderedTracks.count; index > 1; index--) {
            [orderedTracks exchangeObjectAtIndex:index - 1 withObjectAtIndex:arc4random_uniform((u_int32_t)index)];
        }
        return orderedTracks;
    }

    if (startIndex >= 0 && startIndex < orderedTracks.count) {
        return [orderedTracks subarrayWithRange:NSMakeRange(startIndex, orderedTracks.count - startIndex)];
    }

    return orderedTracks;
}

- (AVPlayerItem *)playerItemForTrack:(NSDictionary *)track {
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

    NSString *collectionTitle = self.collection[@"title"];
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
    if (!image) {
        return nil;
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
