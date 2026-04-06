#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "FFMpegDownloader.h"
#import "Headers/YTUIResources.h"
#import "Headers/YTMActionSheetController.h"
#import "Headers/YTMActionRowView.h"
#import "Headers/YTIPlayerOverlayRenderer.h"
#import "Headers/YTIPlayerOverlayActionSupportedRenderers.h"
#import "Headers/YTMNowPlayingViewController.h"
#import "Headers/YTPlayerView.h"
#import "Headers/YTIThumbnailDetails_Thumbnail.h"
#import "Headers/YTIFormatStream.h"
#import "Headers/YTAlertView.h"
#import "Headers/ELMNodeController.h"
#import "Prefs/YTMDownloadStore.h"
#import "YTMBatchDownloadManager.h"

static BOOL YTMU(NSString *key) {
    NSDictionary *YTMUltimateDict = [[NSUserDefaults standardUserDefaults] dictionaryForKey:@"YTMUltimate"];
    return [YTMUltimateDict[key] boolValue];
}

@interface UIView ()
- (UIViewController *)_viewControllerForAncestor;
@end

@interface ELMTouchCommandPropertiesHandler : NSObject
- (void)downloadAudio:(YTPlayerViewController *)playerResponse;
- (void)downloadAudio:(YTPlayerViewController *)playerResponse completion:(YTMTrackDownloadCompletion)completion;
- (void)downloadAudio:(YTPlayerViewController *)playerResponse collectionInfo:(NSDictionary *)collectionInfo completion:(YTMTrackDownloadCompletion)completion;
- (void)downloadCoverImage:(YTPlayerViewController *)playerResponse;
- (NSString *)getURLFromManifest:(NSURL *)manifest;
@end

static NSString *YTMUSanitizedMediaComponent(NSString *value) {
    NSString *sanitizedValue = [value stringByReplacingOccurrencesOfString:@"/" withString:@""];
    sanitizedValue = [sanitizedValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

    return sanitizedValue.length > 0 ? sanitizedValue : @"Unknown";
}

static void YTMUSaveCoverForPlayerResponse(YTPlayerResponse *playerResponse, NSString *author, NSString *title) {
    NSMutableArray *thumbnailsArray = playerResponse.playerData.videoDetails.thumbnail.thumbnailsArray;
    YTIThumbnailDetails_Thumbnail *thumbnail = [thumbnailsArray lastObject];
    NSString *thumbnailURL = thumbnail.URL ?: @"";
    if (thumbnailURL.length == 0) {
        return;
    }

    if (thumbnail.width > 0) {
        thumbnailURL = [thumbnailURL stringByReplacingOccurrencesOfString:[NSString stringWithFormat:@"w%u-h%u-", thumbnail.width, thumbnail.width] withString:@"w2048-h2048-"];
    }

    NSData *imageData = [NSData dataWithContentsOfURL:[NSURL URLWithString:thumbnailURL]];

    if (imageData) {
        NSURL *coverURL = [[YTMDownloadStore downloadsDirectoryURL] URLByAppendingPathComponent:[NSString stringWithFormat:@"%@ - %@.png", author, title]];
        [imageData writeToURL:coverURL atomically:YES];
    }
}

static NSDictionary *YTMUMetadataForDownloadedTrack(NSString *author, NSString *title, NSDictionary *collectionInfo) {
    NSMutableDictionary *metadata = [@{
        @"displayName": [NSString stringWithFormat:@"%@ - %@", author, title],
        @"artist": author ?: @"",
        @"title": title ?: @"",
        @"coverFileName": [NSString stringWithFormat:@"%@ - %@.png", author, title],
        @"createdAt": [NSDate date]
    } mutableCopy];

    if (collectionInfo.count > 0) {
        [metadata addEntriesFromDictionary:collectionInfo];
    }

    return metadata;
}

%hook ELMTouchCommandPropertiesHandler
- (void)handleTap {
    if (class_getInstanceVariable([self class], "_controller") == NULL) {
        return %orig;
    }

    if (class_getInstanceVariable([self class], "_tapRecognizer") == NULL) {
        return %orig;
    }

    ELMNodeController *node = [self valueForKey:@"_controller"];
    UIGestureRecognizer *tapRecognizer = [self valueForKey:@"_tapRecognizer"];

    if (![node.key isEqualToString:@"music_download_badge_1"]) {
        return %orig;
    }

    if (![tapRecognizer.view._viewControllerForAncestor isKindOfClass:%c(YTMNowPlayingViewController)]) {
        return %orig;
    }

    YTMNowPlayingViewController *playingVC = (YTMNowPlayingViewController *)tapRecognizer.view._viewControllerForAncestor;
    YTMWatchViewController *watchVC = (YTMWatchViewController *)playingVC.parentViewController;
    YTPlayerViewController *playerVC = watchVC.playerViewController;
    YTPlayerResponse *playerResponse = playerVC.playerResponse;

    if (!playerResponse) {
        YTAlertView *alertView = [%c(YTAlertView) infoDialog];
        alertView.title = LOC(@"DONT_RUSH");
        alertView.subtitle = LOC(@"DONT_RUSH_DESC");
        [alertView show];
        return;
    }

    YTMActionSheetController *sheetController = [%c(YTMActionSheetController) musicActionSheetController];
    sheetController.sourceView = tapRecognizer.view;
    [sheetController addHeaderWithTitle:LOC(@"SELECT_ACTION") subtitle:nil];

    if (YTMU(@"downloadAudio")) {
        [sheetController addAction:[%c(YTActionSheetAction) actionWithTitle:LOC(@"DOWNLOAD_AUDIO") iconImage:[%c(YTUIResources) audioOutline] style:0 handler:^ {
            [self downloadAudio:playerVC];
        }]];

        [sheetController addAction:[%c(YTActionSheetAction) actionWithTitle:@"Download album / queue" iconImage:[%c(YTUIResources) downloadOutline] style:0 handler:^ {
            [[YTMBatchDownloadManager sharedInstance] downloadAlbumFromNowPlayingController:playingVC playerViewController:playerVC trackDownloader:^(YTPlayerViewController *currentPlayerVC, NSDictionary *collectionInfo, YTMTrackDownloadCompletion completion) {
                [self downloadAudio:currentPlayerVC collectionInfo:collectionInfo completion:completion];
            }];
        }]];
    }

    if (YTMU(@"downloadCoverImage")) {
        [sheetController addAction:[%c(YTActionSheetAction) actionWithTitle:LOC(@"DOWNLOAD_COVER") iconImage:[%c(YTUIResources) outlineImageWithColor:[UIColor whiteColor]] style:0 handler:^ {
            [self downloadCoverImage:playerVC];
        }]];
    }

    [sheetController addAction:[%c(YTActionSheetAction) actionWithTitle:LOC(@"DOWNLOAD_PREMIUM") iconImage:[%c(YTUIResources) downloadOutline] secondaryIconImage:[%c(YTUIResources) youtubePremiumBadgeLight] accessibilityIdentifier:nil handler:^ {
        return %orig;
    }]];

    if (YTMU(@"downloadAudio")) {
        [sheetController presentFromViewController:playingVC animated:YES completion:nil];
    } else if (YTMU(@"downloadCoverImage")) {
        [self downloadCoverImage:playerVC];
    } else {
        return %orig;
    }
}

%new
- (void)downloadAudio:(YTPlayerViewController *)playerVC {
    [self downloadAudio:playerVC collectionInfo:nil completion:nil];
}

%new
- (void)downloadAudio:(YTPlayerViewController *)playerVC completion:(YTMTrackDownloadCompletion)completion {
    [self downloadAudio:playerVC collectionInfo:nil completion:completion];
}

%new
- (void)downloadAudio:(YTPlayerViewController *)playerVC collectionInfo:(NSDictionary *)collectionInfo completion:(YTMTrackDownloadCompletion)completion {
    YTPlayerResponse *playerResponse = playerVC.playerResponse;

    if (!playerResponse) {
        if (completion) {
            completion(NO, NO);
        }
        return;
    }

    NSString *title = YTMUSanitizedMediaComponent(playerResponse.playerData.videoDetails.title);
    NSString *author = YTMUSanitizedMediaComponent(playerResponse.playerData.videoDetails.author);
    NSString *urlStr = playerResponse.playerData.streamingData.hlsManifestURL;

    FFMpegDownloader *ffmpeg = [[FFMpegDownloader alloc] init];
    ffmpeg.tempName = playerVC.contentVideoID ?: [NSUUID UUID].UUIDString;
    ffmpeg.mediaName = [NSString stringWithFormat:@"%@ - %@", author, title];
    ffmpeg.duration = MAX(1, round(playerVC.currentVideoTotalMediaTime));
    NSString *downloadedAudioFileName = [NSString stringWithFormat:@"%@.m4a", ffmpeg.mediaName];

    
    NSString *extractedURL = [self getURLFromManifest:[NSURL URLWithString:urlStr]];
    
    if (extractedURL.length > 0) {
        ffmpeg.completion = ^(YTMFFMpegDownloadResult result) {
            if (result == YTMFFMpegDownloadResultSuccess) {
                YTMUSaveCoverForPlayerResponse(playerResponse, author, title);
                [YTMDownloadStore saveMetadata:YTMUMetadataForDownloadedTrack(author, title, collectionInfo) forAudioFileNamed:downloadedAudioFileName];
            }

            if (completion) {
                completion(result == YTMFFMpegDownloadResultSuccess, result == YTMFFMpegDownloadResultCancelled);
            }
        };
        [ffmpeg downloadAudio:extractedURL];
    } else {
        YTAlertView *alertView = [%c(YTAlertView) infoDialog];
        alertView.title = LOC(@"OOPS");
        alertView.subtitle = LOC(@"LINK_NOT_FOUND");
        [alertView show];

        if (completion) {
            completion(NO, NO);
        }
    }
}

%new
- (NSString *)getURLFromManifest:(NSURL *)manifest {
    NSData *manifestData = [NSData dataWithContentsOfURL:manifest];
    NSString *manifestString = [[NSString alloc] initWithData:manifestData encoding:NSUTF8StringEncoding];
    NSArray *manifestLines = [manifestString componentsSeparatedByString:@"\n"];

    NSArray *groupIDS = @[@"234", @"233"]; // Our priority to find group id 234
    for (NSString *groupID in groupIDS) {
        for (NSString *line in manifestLines) {
            NSString *searchString = [NSString stringWithFormat:@"TYPE=AUDIO,GROUP-ID=\"%@\"", groupID];
            if ([line containsString:searchString]) {
                NSRange startRange = [line rangeOfString:@"https://"];
                NSRange endRange = [line rangeOfString:@"index.m3u8"];

                if (startRange.location != NSNotFound && endRange.location != NSNotFound) {
                    NSRange targetRange = NSMakeRange(startRange.location, NSMaxRange(endRange) - startRange.location);
                    return [line substringWithRange:targetRange];
                }
            }
        }
    }

    return nil;
}

%new
- (void)downloadCoverImage:(YTPlayerViewController *)playerVC {
    MBProgressHUD *hud = [MBProgressHUD showHUDAddedTo:[UIApplication sharedApplication].keyWindow animated:YES];
    dispatch_async(dispatch_get_main_queue(), ^{
        hud.mode = MBProgressHUDModeIndeterminate;
    });

    YTPlayerResponse *playerResponse = playerVC.playerResponse;

    NSMutableArray *thumbnailsArray = playerResponse.playerData.videoDetails.thumbnail.thumbnailsArray;
    YTIThumbnailDetails_Thumbnail *thumbnail = [thumbnailsArray lastObject];
    NSString *thumbnailURL = [thumbnail.URL stringByReplacingOccurrencesOfString:[NSString stringWithFormat:@"w%u-h%u-", thumbnail.width, thumbnail.width] withString:@"w2048-h2048-"];

    FFMpegDownloader *ffmpeg = [[FFMpegDownloader alloc] init];
    [ffmpeg downloadImage:[NSURL URLWithString:thumbnailURL]];

    dispatch_async(dispatch_get_main_queue(), ^{
        [hud hideAnimated:YES];
    });
}
%end
