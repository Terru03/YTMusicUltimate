#import <Foundation/Foundation.h>

@class YTMNowPlayingViewController;
@class YTPlayerViewController;

typedef void (^YTMTrackDownloadCompletion)(BOOL success, BOOL cancelled);
typedef void (^YTMTrackDownloadBlock)(YTPlayerViewController *playerViewController, NSDictionary *collectionInfo, YTMTrackDownloadCompletion completion);

@interface YTMBatchDownloadManager : NSObject
+ (instancetype)sharedInstance;
- (void)downloadAlbumFromNowPlayingController:(YTMNowPlayingViewController *)nowPlayingController
                         playerViewController:(YTPlayerViewController *)playerViewController
                              trackDownloader:(YTMTrackDownloadBlock)trackDownloader;
@end
