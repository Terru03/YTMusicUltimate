#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

extern NSString *const YTMLocalPlaybackManagerDidUpdateNotification;

@interface YTMLocalPlaybackManager : NSObject
@property (nonatomic, strong, readonly) AVPlayer *player;
@property (nonatomic, copy, readonly) NSArray<NSDictionary *> *tracks;
@property (nonatomic, readonly) NSInteger currentIndex;
@property (nonatomic, readonly, getter=isPlaying) BOOL playing;

+ (instancetype)sharedInstance;
- (void)loadTracks:(NSArray<NSDictionary *> *)tracks startIndex:(NSInteger)startIndex autoplay:(BOOL)autoplay;
- (NSDictionary *)currentTrack;
- (NSTimeInterval)currentTime;
- (NSTimeInterval)currentDuration;
- (void)play;
- (void)pause;
- (void)togglePlayPause;
- (void)playNextTrack;
- (void)playPreviousTrackOrRestart;
- (void)seekToTime:(NSTimeInterval)time completion:(dispatch_block_t)completion;
@end
