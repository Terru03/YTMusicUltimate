#import "YTMBatchDownloadManager.h"
#import "Headers/Localization.h"
#import "Headers/YTMNowPlayingViewController.h"
#import "Headers/YTMToastController.h"
#import "Headers/YTPlayerResponse.h"
#import "Headers/YTPlayerViewController.h"
#import "Headers/YTIPlayerResponse.h"
#import "Headers/YTIVideoDetails.h"
#import "Headers/YTIThumbnailDetails.h"
#import "Headers/YTIThumbnailDetails_Thumbnail.h"

typedef NS_ENUM(NSInteger, YTMAlbumDownloadDirection) {
    YTMAlbumDownloadDirectionForward = 0,
    YTMAlbumDownloadDirectionBackward
};

@interface YTMBatchDownloadManager ()
@property (nonatomic, strong) YTMNowPlayingViewController *nowPlayingController;
@property (nonatomic, strong) YTPlayerViewController *playerViewController;
@property (nonatomic, copy) YTMTrackDownloadBlock trackDownloader;
@property (nonatomic, copy) NSString *initialVideoID;
@property (nonatomic, copy) NSString *collectionIdentifier;
@property (nonatomic, copy) NSString *collectionTitle;
@property (nonatomic, copy) NSString *collectionSubtitle;
@property (nonatomic, copy) NSString *explicitAlbumTitle;
@property (nonatomic) CGFloat initialPlaybackTime;
@property (nonatomic) NSInteger forwardStepCount;
@property (nonatomic) NSInteger backwardStepCount;
@property (nonatomic) NSInteger currentRelativeTrackNumber;
@property (nonatomic) NSInteger downloadedTrackCount;
@property (nonatomic, strong) NSMutableOrderedSet<NSString *> *downloadedVideoIDs;
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
    self.initialVideoID = currentVideoID;
    self.collectionIdentifier = [NSUUID UUID].UUIDString;
    self.explicitAlbumTitle = [self explicitAlbumTitleForPlayerViewController:playerViewController];
    self.collectionTitle = [self preferredCollectionTitleForPlayerViewController:playerViewController];
    self.collectionSubtitle = [self preferredCollectionSubtitleForPlayerViewController:playerViewController];
    self.initialPlaybackTime = [playerViewController currentVideoMediaTime];
    self.forwardStepCount = 0;
    self.backwardStepCount = 0;
    self.currentRelativeTrackNumber = 0;
    self.downloadedTrackCount = 0;
    self.downloadedVideoIDs = [NSMutableOrderedSet orderedSet];

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

        [self downloadNextTracks];
    }];
}

- (void)downloadNextTracks {
    __weak typeof(self) weakSelf = self;
    [self moveToAdjacentTrackInDirection:YTMAlbumDownloadDirectionForward completion:^(BOOL moved) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) {
            return;
        }

        if (!moved) {
            [self restoreTrackPositionWithDirection:YTMAlbumDownloadDirectionBackward stepsRemaining:self.forwardStepCount completion:^{
                [self downloadPreviousTracks];
            }];
            return;
        }

        self.forwardStepCount += 1;
        self.currentRelativeTrackNumber = self.forwardStepCount;
        [self downloadCurrentTrackWithCompletion:^(BOOL success, BOOL cancelled) {
            if (!success || cancelled) {
                [self restoreTrackPositionWithDirection:YTMAlbumDownloadDirectionBackward stepsRemaining:self.forwardStepCount completion:^{
                    [self finalizeAlbumDownload];
                }];
                return;
            }

            [self downloadNextTracks];
        }];
    }];
}

- (void)downloadPreviousTracks {
    __weak typeof(self) weakSelf = self;
    [self moveToAdjacentTrackInDirection:YTMAlbumDownloadDirectionBackward completion:^(BOOL moved) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) {
            return;
        }

        if (!moved) {
            [self restoreTrackPositionWithDirection:YTMAlbumDownloadDirectionForward stepsRemaining:self.backwardStepCount completion:^{
                [self finalizeAlbumDownload];
            }];
            return;
        }

        self.backwardStepCount += 1;
        self.currentRelativeTrackNumber = -self.backwardStepCount;
        [self downloadCurrentTrackWithCompletion:^(BOOL success, BOOL cancelled) {
            if (!success || cancelled) {
                [self restoreTrackPositionWithDirection:YTMAlbumDownloadDirectionForward stepsRemaining:self.backwardStepCount completion:^{
                    [self finalizeAlbumDownload];
                }];
                return;
            }

            [self downloadPreviousTracks];
        }];
    }];
}

- (void)downloadCurrentTrackWithCompletion:(YTMTrackDownloadCompletion)completion {
    if (!self.isDownloadingAlbum || !self.trackDownloader || !self.playerViewController) {
        if (completion) {
            completion(NO, NO);
        }
        return;
    }

    NSString *currentVideoID = self.playerViewController.contentVideoID;
    if (currentVideoID.length == 0) {
        if (completion) {
            completion(NO, NO);
        }
        return;
    }

    if (![self.downloadedVideoIDs containsObject:currentVideoID]) {
        [self.downloadedVideoIDs addObject:currentVideoID];
    }

    __weak typeof(self) weakSelf = self;
    self.trackDownloader(self.playerViewController, [self currentCollectionInfo], ^(BOOL success, BOOL cancelled) {
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

- (void)moveToAdjacentTrackInDirection:(YTMAlbumDownloadDirection)direction completion:(void (^)(BOOL moved))completion {
    NSString *currentVideoID = self.playerViewController.contentVideoID;
    if (!self.isDownloadingAlbum || currentVideoID.length == 0) {
        if (completion) {
            completion(NO);
        }
        return;
    }

    [self performNavigationInDirection:direction];

    __weak typeof(self) weakSelf = self;
    [self waitForTrackReadinessFromVideoID:currentVideoID attempt:0 completion:^(BOOL changed) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || !changed) {
            if (completion) {
                completion(NO);
            }
            return;
        }

        NSString *newVideoID = self.playerViewController.contentVideoID;
        BOOL alreadyDownloaded = [self.downloadedVideoIDs containsObject:newVideoID];
        BOOL shouldContinue = [self shouldContinueDownloadingCurrentTrack];

        if (newVideoID.length == 0 || !shouldContinue || alreadyDownloaded) {
            [self performNavigationInDirection:[self oppositeDirectionForDirection:direction]];
            [self waitForTrackReadinessFromVideoID:newVideoID attempt:0 completion:^(__unused BOOL reverted) {
                if (completion) {
                    completion(NO);
                }
            }];
            return;
        }

        if (completion) {
            completion(YES);
        }
    }];
}

- (void)performNavigationInDirection:(YTMAlbumDownloadDirection)direction {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (direction == YTMAlbumDownloadDirectionBackward) {
            [self.playerViewController seekToTime:0.0];
            [self.nowPlayingController didTapPrevButton];
            return;
        }

        [self.nowPlayingController didTapNextButton];
    });
}

- (void)restoreTrackPositionWithDirection:(YTMAlbumDownloadDirection)direction
                           stepsRemaining:(NSInteger)stepsRemaining
                               completion:(dispatch_block_t)completion {
    if (stepsRemaining <= 0 || !self.isDownloadingAlbum) {
        if (completion) {
            completion();
        }
        return;
    }

    NSString *currentVideoID = self.playerViewController.contentVideoID;
    if (currentVideoID.length == 0) {
        if (completion) {
            completion();
        }
        return;
    }

    [self performNavigationInDirection:direction];

    __weak typeof(self) weakSelf = self;
    [self waitForTrackReadinessFromVideoID:currentVideoID attempt:0 completion:^(BOOL changed) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || !changed) {
            if (completion) {
                completion();
            }
            return;
        }

        [self restoreTrackPositionWithDirection:direction stepsRemaining:stepsRemaining - 1 completion:completion];
    }];
}

- (void)finalizeAlbumDownload {
    NSInteger downloadedTrackCount = self.downloadedTrackCount;
    NSString *initialVideoID = self.initialVideoID;
    CGFloat initialPlaybackTime = self.initialPlaybackTime;

    dispatch_async(dispatch_get_main_queue(), ^{
        if ([self.playerViewController.contentVideoID isEqualToString:initialVideoID]) {
            [self.playerViewController seekToTime:initialPlaybackTime];
        }

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
    self.initialVideoID = nil;
    self.explicitAlbumTitle = nil;
    self.collectionIdentifier = nil;
    self.collectionTitle = nil;
    self.collectionSubtitle = nil;
    self.initialPlaybackTime = 0.0;
    self.forwardStepCount = 0;
    self.backwardStepCount = 0;
    self.currentRelativeTrackNumber = 0;
    self.downloadedTrackCount = 0;
    self.downloadedVideoIDs = nil;
    self.downloadingAlbum = NO;
}

- (NSString *)currentArtworkURLForPlayerViewController:(YTPlayerViewController *)playerViewController {
    YTPlayerResponse *playerResponse = playerViewController.playerResponse;
    NSMutableArray *thumbnailsArray = playerResponse.playerData.videoDetails.thumbnail.thumbnailsArray;
    YTIThumbnailDetails_Thumbnail *thumbnail = [thumbnailsArray lastObject];

    return thumbnail.URL ?: @"";
}

- (BOOL)shouldContinueDownloadingCurrentTrack {
    NSString *currentAlbumTitle = [self explicitAlbumTitleForPlayerViewController:self.playerViewController];
    if (self.explicitAlbumTitle.length > 0 && currentAlbumTitle.length > 0) {
        return [[self normalizedString:currentAlbumTitle] isEqualToString:[self normalizedString:self.explicitAlbumTitle]];
    }

    return YES;
}

- (YTMAlbumDownloadDirection)oppositeDirectionForDirection:(YTMAlbumDownloadDirection)direction {
    return direction == YTMAlbumDownloadDirectionForward ? YTMAlbumDownloadDirectionBackward : YTMAlbumDownloadDirectionForward;
}

- (NSDictionary *)currentCollectionInfo {
    NSMutableDictionary *collectionInfo = [@{
        @"collectionIdentifier": self.collectionIdentifier ?: [NSUUID UUID].UUIDString,
        @"collectionType": @"album",
        @"trackNumber": @(self.currentRelativeTrackNumber)
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
        @"playerResponse.playerData.videoDetails.albumName",
        @"playerResponse.playerData.videoDetails.musicAlbumName",
        @"playerResponse.playerData.album",
        @"playerResponse.playerData.albumName"
    ] onObject:playerViewController];
}

- (NSString *)preferredCollectionTitleForPlayerViewController:(YTPlayerViewController *)playerViewController {
    NSString *albumName = [self explicitAlbumTitleForPlayerViewController:playerViewController];

    if (albumName.length > 0) {
        return albumName;
    }

    NSString *artist = playerViewController.playerResponse.playerData.videoDetails.author;
    return artist.length > 0 ? artist : @"Album";
}

- (NSString *)preferredCollectionSubtitleForPlayerViewController:(YTPlayerViewController *)playerViewController {
    NSString *artist = playerViewController.playerResponse.playerData.videoDetails.author;
    NSString *title = playerViewController.playerResponse.playerData.videoDetails.title;

    if (artist.length > 0 && ![artist isEqualToString:self.collectionTitle]) {
        return artist;
    }

    return title.length > 0 ? title : @"Album download";
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

- (BOOL)isTrackReadyForDownload {
    YTPlayerResponse *playerResponse = self.playerViewController.playerResponse;
    NSString *title = playerResponse.playerData.videoDetails.title;
    NSString *author = playerResponse.playerData.videoDetails.author;
    NSString *manifestURL = playerResponse.playerData.streamingData.hlsManifestURL;

    return (playerResponse != nil &&
            title.length > 0 &&
            author.length > 0 &&
            manifestURL.length > 0);
}

- (void)waitForTrackReadinessFromVideoID:(NSString *)videoID
                                 attempt:(NSInteger)attempt
                              completion:(void (^)(BOOL changed))completion {
    if (!self.isDownloadingAlbum) {
        if (completion) {
            completion(NO);
        }
        return;
    }

    if (attempt >= 50) {
        if (completion) {
            completion(NO);
        }
        return;
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        NSString *currentVideoID = self.playerViewController.contentVideoID;
        BOOL didTrackChange = (currentVideoID.length > 0 && ![currentVideoID isEqualToString:videoID]);

        if (didTrackChange && [self isTrackReadyForDownload]) {
            if (completion) {
                completion(YES);
            }
            return;
        }

        [self waitForTrackReadinessFromVideoID:videoID attempt:attempt + 1 completion:completion];
    });
}

@end
