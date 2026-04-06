#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <Photos/Photos.h>
#import "Utils/MobileFFmpeg/MobileFFmpegConfig.h"
#import "Utils/MobileFFmpeg/MobileFFmpeg.h"
#import "Utils/MobileFFmpeg/MobileFFprobe.h"
#import "Utils/MBProgressHUD/MBProgressHUD.h"
#import "Headers/Localization.h"

typedef NS_ENUM(NSInteger, YTMFFMpegDownloadResult) {
    YTMFFMpegDownloadResultSuccess = 0,
    YTMFFMpegDownloadResultCancelled,
    YTMFFMpegDownloadResultFailed
};

@interface FFMpegDownloader : NSObject <LogDelegate, StatisticsDelegate>
@property (nonatomic, strong) MBProgressHUD *hud;
@property (nonatomic, strong) NSString *tempName;
@property (nonatomic, strong) NSString *mediaName;
@property (nonatomic) NSInteger duration;
@property (nonatomic) BOOL suppressUserInterface;
@property (nonatomic, copy) void (^completion)(YTMFFMpegDownloadResult result);
- (void)downloadAudio:(NSString *)audioURL;
- (void)downloadImage:(NSURL *)link;
- (void)shareMedia:(NSURL *)mediaURL;
@end
