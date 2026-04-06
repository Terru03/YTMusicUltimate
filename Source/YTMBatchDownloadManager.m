#import "YTMBatchDownloadManager.h"
#import "Headers/Localization.h"
#import "Headers/YTMNowPlayingViewController.h"
#import "Headers/YTMToastController.h"
#import "Headers/YTMWatchViewController.h"
#import "Headers/YTPlayerResponse.h"
#import "Headers/YTPlayerViewController.h"
#import "Headers/YTIPlayerResponse.h"
#import "Headers/YTIVideoDetails.h"
#import <math.h>

@interface YTMBatchDownloadManager ()
@property (nonatomic, strong) YTMNowPlayingViewController *nowPlayingController;
@property (nonatomic, strong) YTPlayerViewController *playerViewController;
@property (nonatomic, copy) YTMTrackDownloadBlock trackDownloader;
@property (nonatomic, copy) NSString *collectionIdentifier;
@property (nonatomic, copy) NSString *collectionType;
@property (nonatomic, copy) NSString *collectionTitle;
@property (nonatomic, copy) NSString *collectionSubtitle;
@property (nonatomic, copy) NSString *explicitAlbumTitle;
@property (nonatomic, copy) NSString *explicitQueueTitle;
@property (nonatomic) NSInteger currentTrackNumber;
@property (nonatomic) NSInteger downloadedTrackCount;
@property (nonatomic, strong) NSMutableOrderedSet<NSString *> *downloadedVideoIDs;
@property (nonatomic) UIBackgroundTaskIdentifier backgroundTaskIdentifier;
@property (nonatomic, assign, getter=isDownloadingAlbum) BOOL downloadingAlbum;
@end

@implementation YTMBatchDownloadManager

+ (instancetype)sharedInstance {
    static YTMBatchDownloadManager *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _backgroundTaskIdentifier = UIBackgroundTaskInvalid;
    }
    return self;
}

- (void)downloadAlbumFromNowPlayingController:(YTMNowPlayingViewController *)nowPlayingController
                         playerViewController:(YTPlayerViewController *)playerViewController
                              trackDownloader:(YTMTrackDownloadBlock)trackDownloader {
    if (self.isDownloadingAlbum || !nowPlayingController || !playerViewController || !trackDownloader) {
        return;
    }

    NSString *currentVideoID = playerViewController.contentVideoID;
    if (currentVideoID.length == 0 || !playerViewController.playerResponse) {
        return;
    }

    self.downloadingAlbum = YES;
    self.nowPlayingController = nowPlayingController;
    self.playerViewController = playerViewController;
    self.trackDownloader = trackDownloader;
    self.collectionIdentifier = [NSUUID UUID].UUIDString;
    self.explicitAlbumTitle = [self explicitAlbumTitleForPlayerViewController:playerViewController];
    self.explicitQueueTitle = [self explicitQueueTitleForPlayerViewController:playerViewController];
    self.collectionType = [self preferredCollectionTypeForPlayerViewController:playerViewController];
    self.collectionTitle = [self preferredCollectionTitleForPlayerViewController:playerViewController];
    self.collectionSubtitle = [self preferredCollectionSubtitleForPlayerViewController:playerViewController];
    self.currentTrackNumber = 1;
    self.downloadedTrackCount = 0;
    self.downloadedVideoIDs = [NSMutableOrderedSet orderedSet];
    [self beginBackgroundTask];

    __weak typeof(self) weakSelf = self;
    [self downloadCurrentTrackWithCompletion:^(BOOL success, BOOL cancelled) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) {
            return;
        }

        if (!success || cancelled) {
            [self finalizeAlbumDownload];
            return;
        }

        [self continueDownloadingQueue];
    }];
}

- (void)continueDownloadingQueue {
    if (!self.isDownloadingAlbum) {
        return;
    }

    __weak typeof(self) weakSelf = self;
    [self scheduleAfterDownloadCompletion:^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) {
            return;
        }

        [self moveToNextTrackWithCompletion:^(BOOL moved) {
            __strong typeof(weakSelf) self = weakSelf;
            if (!self || !moved) {
                [self finalizeAlbumDownload];
                return;
            }

            self.currentTrackNumber += 1;
            [self scheduleBeforeDownloadingLoadedTrack:^{
                [self downloadCurrentTrackWithCompletion:^(BOOL success, BOOL cancelled) {
                    if (!success || cancelled) {
                        [self finalizeAlbumDownload];
                        return;
                    }

                    [self continueDownloadingQueue];
                }];
            }];
        }];
    }];
}

- (void)downloadCurrentTrackWithCompletion:(YTMTrackDownloadCompletion)completion {
    YTPlayerViewController *currentPlayerViewController = [self activePlayerViewController];
    if (!self.isDownloadingAlbum || !self.trackDownloader || !currentPlayerViewController) {
        if (completion) {
            completion(NO, NO);
        }
        return;
    }

    self.playerViewController = currentPlayerViewController;
    NSString *currentVideoID = currentPlayerViewController.contentVideoID;
    if (currentVideoID.length == 0) {
        if (completion) {
            completion(NO, NO);
        }
        return;
    }

    if ([self.downloadedVideoIDs containsObject:currentVideoID]) {
        if (completion) {
            completion(NO, NO);
        }
        return;
    }

    [self.downloadedVideoIDs addObject:currentVideoID];

    __weak typeof(self) weakSelf = self;
    self.trackDownloader(currentPlayerViewController, [self currentCollectionInfo], ^(BOOL success, BOOL cancelled) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) {
            return;
        }

        if (success) {
            self.downloadedTrackCount += 1;
        }

        if (completion) {
            completion(success, cancelled);
        }
    });
}

- (void)moveToNextTrackWithCompletion:(void (^)(BOOL moved))completion {
    YTPlayerViewController *currentPlayerViewController = [self activePlayerViewController];
    NSString *currentVideoID = currentPlayerViewController.contentVideoID;
    if (!self.isDownloadingAlbum || currentVideoID.length == 0) {
        if (completion) {
            completion(NO);
        }
        return;
    }

    self.playerViewController = currentPlayerViewController;
    [self performNavigationToNextTrack];

    __weak typeof(self) weakSelf = self;
    [self waitForTrackReadinessFromVideoID:currentVideoID attempt:0 readyPassCount:0 completion:^(BOOL changed) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || !changed) {
            if (completion) {
                completion(NO);
            }
            return;
        }

        YTPlayerViewController *loadedPlayerViewController = [self activePlayerViewController];
        self.playerViewController = loadedPlayerViewController;
        NSString *newVideoID = loadedPlayerViewController.contentVideoID;
        BOOL alreadyDownloaded = [self.downloadedVideoIDs containsObject:newVideoID];
        BOOL shouldContinue = [self shouldContinueDownloadingCurrentTrack];

        if (newVideoID.length == 0 || alreadyDownloaded || !shouldContinue) {
            if (completion) {
                completion(NO);
            }
            return;
        }

        if (completion) {
            completion(YES);
        }
    }];
}

- (void)performNavigationToNextTrack {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!self.nowPlayingController || ![self activePlayerViewController]) {
            return;
        }

        @try {
            [self.nowPlayingController didTapNextButton];
        } @catch (__unused NSException *exception) {
            [self finalizeAlbumDownload];
        }
    });
}

- (void)finalizeAlbumDownload {
    NSInteger downloadedTrackCount = self.downloadedTrackCount;

    dispatch_async(dispatch_get_main_queue(), ^{
        if (downloadedTrackCount > 0) {
            NSString *message = [NSString stringWithFormat:@"%@ (%ld)", LOC(@"DONE"), (long)downloadedTrackCount];
            Class toastClass = NSClassFromString(@"YTMToastController");
            if (toastClass) {
                [(id)[toastClass new] showMessage:message];
            }
        }

        [self resetState];
    });
}

- (void)resetState {
    self.nowPlayingController = nil;
    self.playerViewController = nil;
    self.trackDownloader = nil;
    self.collectionIdentifier = nil;
    self.collectionType = nil;
    self.collectionTitle = nil;
    self.collectionSubtitle = nil;
    self.explicitAlbumTitle = nil;
    self.explicitQueueTitle = nil;
    self.currentTrackNumber = 0;
    self.downloadedTrackCount = 0;
    self.downloadedVideoIDs = nil;
    self.downloadingAlbum = NO;
    [self endBackgroundTask];
}

- (BOOL)shouldContinueDownloadingCurrentTrack {
    YTPlayerViewController *currentPlayerViewController = [self activePlayerViewController];
    if (!currentPlayerViewController) {
        return NO;
    }

    if (self.explicitAlbumTitle.length > 0) {
        NSString *currentAlbumTitle = [self explicitAlbumTitleForPlayerViewController:currentPlayerViewController];
        return [[self normalizedString:currentAlbumTitle] isEqualToString:[self normalizedString:self.explicitAlbumTitle]];
    }

    if (self.explicitQueueTitle.length > 0) {
        NSString *currentQueueTitle = [self explicitQueueTitleForPlayerViewController:currentPlayerViewController];
        return [[self normalizedString:currentQueueTitle] isEqualToString:[self normalizedString:self.explicitQueueTitle]];
    }

    return YES;
}

- (NSDictionary *)currentCollectionInfo {
    NSMutableDictionary *collectionInfo = [@{
        @"collectionIdentifier": self.collectionIdentifier ?: [NSUUID UUID].UUIDString,
        @"collectionType": self.collectionType ?: @"playlist",
        @"trackNumber": @(self.currentTrackNumber)
    } mutableCopy];

    if (self.collectionTitle.length > 0) {
        collectionInfo[@"collectionTitle"] = self.collectionTitle;
    }

    if (self.collectionSubtitle.length > 0) {
        collectionInfo[@"collectionSubtitle"] = self.collectionSubtitle;
    }

    return collectionInfo;
}

- (NSString *)explicitAlbumTitleForPlayerViewController:(YTPlayerViewController *)playerViewController {
    return [self stringValueForKeyPaths:@[
        @"playerResponse.playerData.videoDetails.album",
        @"playerResponse.playerData.videoDetails.albumTitle",
        @"playerResponse.playerData.videoDetails.albumName",
        @"playerResponse.playerData.videoDetails.musicAlbumName",
        @"playerResponse.playerData.album",
        @"playerResponse.playerData.albumName"
    ] onObject:playerViewController];
}

- (NSString *)explicitQueueTitleForPlayerViewController:(YTPlayerViewController *)playerViewController {
    return [self stringValueForKeyPaths:@[
        @"playerResponse.playerData.videoDetails.playlist",
        @"playerResponse.playerData.videoDetails.playlistTitle",
        @"playerResponse.playerData.videoDetails.playlistName",
        @"playerResponse.playerData.playlistTitle",
        @"playerResponse.playerData.playlistName"
    ] onObject:playerViewController];
}

- (NSString *)preferredCollectionTypeForPlayerViewController:(YTPlayerViewController *)playerViewController {
    if ([self explicitAlbumTitleForPlayerViewController:playerViewController].length > 0) {
        return @"album";
    }

    return @"playlist";
}

- (NSString *)preferredCollectionTitleForPlayerViewController:(YTPlayerViewController *)playerViewController {
    NSString *albumName = [self explicitAlbumTitleForPlayerViewController:playerViewController];
    if (albumName.length > 0) {
        return albumName;
    }

    NSString *queueTitle = [self explicitQueueTitleForPlayerViewController:playerViewController];
    if (queueTitle.length > 0) {
        return queueTitle;
    }

    NSString *artist = playerViewController.playerResponse.playerData.videoDetails.author;
    return artist.length > 0 ? artist : @"Queue";
}

- (NSString *)preferredCollectionSubtitleForPlayerViewController:(YTPlayerViewController *)playerViewController {
    NSString *artist = playerViewController.playerResponse.playerData.videoDetails.author;
    NSString *title = playerViewController.playerResponse.playerData.videoDetails.title;

    if (artist.length > 0 && ![artist isEqualToString:self.collectionTitle]) {
        return artist;
    }

    return title.length > 0 ? title : @"Queue download";
}

- (NSString *)normalizedString:(NSString *)value {
    NSString *normalizedValue = [[value ?: @"" lowercaseString] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return normalizedValue;
}

- (NSString *)stringValueForKeyPaths:(NSArray<NSString *> *)keyPaths onObject:(id)object {
    for (NSString *keyPath in keyPaths) {
        @try {
            id value = [object valueForKeyPath:keyPath];
            if ([value isKindOfClass:[NSString class]] && [(NSString *)value length] > 0) {
                return value;
            }
        } @catch (__unused NSException *exception) {
        }
    }

    return nil;
}

- (YTPlayerViewController *)activePlayerViewController {
    YTMWatchViewController *watchViewController = self.nowPlayingController.parentViewController;
    if ([watchViewController isKindOfClass:[YTMWatchViewController class]] && watchViewController.playerViewController) {
        return watchViewController.playerViewController;
    }

    return self.playerViewController;
}

- (BOOL)isTrackReadyForDownloadForPlayerViewController:(YTPlayerViewController *)playerViewController {
    if (!playerViewController) {
        return NO;
    }

    YTPlayerResponse *playerResponse = playerViewController.playerResponse;
    NSString *title = playerResponse.playerData.videoDetails.title;
    NSString *author = playerResponse.playerData.videoDetails.author;
    NSString *manifestURL = playerResponse.playerData.streamingData.hlsManifestURL;

    return (playerResponse != nil &&
            title.length > 0 &&
            author.length > 0 &&
            manifestURL.length > 0);
}

- (BOOL)currentTrackHasStartedPlaybackForPlayerViewController:(YTPlayerViewController *)playerViewController
                                                      attempt:(NSInteger)attempt {
    if (!playerViewController) {
        return NO;
    }

    CGFloat currentMediaTime = [playerViewController currentVideoMediaTime];
    if (isfinite(currentMediaTime) && currentMediaTime > 0.9) {
        return YES;
    }

    return attempt >= 10;
}

- (BOOL)currentTrackHasResolvedDurationForPlayerViewController:(YTPlayerViewController *)playerViewController {
    if (!playerViewController) {
        return NO;
    }

    CGFloat totalMediaTime = playerViewController.currentVideoTotalMediaTime;
    return isfinite(totalMediaTime) && totalMediaTime > 1.0;
}

- (void)waitForTrackReadinessFromVideoID:(NSString *)videoID
                                 attempt:(NSInteger)attempt
                          readyPassCount:(NSInteger)readyPassCount
                              completion:(void (^)(BOOL changed))completion {
    if (!self.isDownloadingAlbum) {
        if (completion) {
            completion(NO);
        }
        return;
    }

    if (attempt >= 60) {
        if (completion) {
            completion(NO);
        }
        return;
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.45 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        YTPlayerViewController *currentPlayerViewController = [self activePlayerViewController];
        self.playerViewController = currentPlayerViewController;
        NSString *currentVideoID = currentPlayerViewController.contentVideoID;
        BOOL didTrackChange = (currentVideoID.length > 0 && ![currentVideoID isEqualToString:videoID]);
        BOOL readyForDownload = (didTrackChange &&
                                 [self isTrackReadyForDownloadForPlayerViewController:currentPlayerViewController] &&
                                 [self currentTrackHasResolvedDurationForPlayerViewController:currentPlayerViewController] &&
                                 [self currentTrackHasStartedPlaybackForPlayerViewController:currentPlayerViewController attempt:attempt]);
        NSInteger nextReadyPassCount = readyForDownload ? readyPassCount + 1 : 0;

        if (nextReadyPassCount >= 3) {
            if (completion) {
                completion(YES);
            }
            return;
        }

        [self waitForTrackReadinessFromVideoID:videoID
                                       attempt:attempt + 1
                               readyPassCount:nextReadyPassCount
                                    completion:completion];
    });
}

- (void)scheduleAfterDownloadCompletion:(dispatch_block_t)continuation {
    if (!continuation) {
        return;
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (!self.isDownloadingAlbum) {
            return;
        }

        continuation();
    });
}

- (void)scheduleBeforeDownloadingLoadedTrack:(dispatch_block_t)continuation {
    if (!continuation) {
        return;
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.65 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (!self.isDownloadingAlbum) {
            return;
        }

        continuation();
    });
}

- (void)beginBackgroundTask {
    if (self.backgroundTaskIdentifier != UIBackgroundTaskInvalid) {
        return;
    }

    __weak typeof(self) weakSelf = self;
    self.backgroundTaskIdentifier = [[UIApplication sharedApplication] beginBackgroundTaskWithName:@"YTMusicUltimateAlbumDownload" expirationHandler:^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) {
            return;
        }

        [self finalizeAlbumDownload];
    }];
}

- (void)endBackgroundTask {
    if (self.backgroundTaskIdentifier == UIBackgroundTaskInvalid) {
        return;
    }

    [[UIApplication sharedApplication] endBackgroundTask:self.backgroundTaskIdentifier];
    self.backgroundTaskIdentifier = UIBackgroundTaskInvalid;
}

@end
