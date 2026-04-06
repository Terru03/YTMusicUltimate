#import "YTMLocalPlaybackManager.h"
#import <UIKit/UIKit.h>
#import <MediaPlayer/MediaPlayer.h>
#import <math.h>

NSString *const YTMLocalPlaybackManagerDidUpdateNotification = @"YTMLocalPlaybackManagerDidUpdateNotification";

@interface YTMLocalPlaybackManager ()
@property (nonatomic, strong, readwrite) AVPlayer *player;
@property (nonatomic, copy, readwrite) NSArray<NSDictionary *> *tracks;
@property (nonatomic, readwrite) NSInteger currentIndex;
@property (nonatomic, strong) id timeObserverToken;
@property (nonatomic, strong) id nowPlayingSession;
@property (nonatomic, strong) MPRemoteCommandCenter *remoteCommandCenter;
@property (nonatomic, strong) MPNowPlayingInfoCenter *nowPlayingInfoCenter;
@property (nonatomic) BOOL remoteCommandsConfigured;
@end

@implementation YTMLocalPlaybackManager

+ (instancetype)sharedInstance {
    static YTMLocalPlaybackManager *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _tracks = @[];
        _currentIndex = NSNotFound;
        _nowPlayingInfoCenter = [MPNowPlayingInfoCenter defaultCenter];
    }
    return self;
}

- (void)dealloc {
    if (self.timeObserverToken && self.player) {
        [self.player removeTimeObserver:self.timeObserverToken];
    }
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)loadTracks:(NSArray<NSDictionary *> *)tracks startIndex:(NSInteger)startIndex autoplay:(BOOL)autoplay {
    if (tracks.count == 0) {
        return;
    }

    self.tracks = [tracks copy];
    NSInteger normalizedIndex = MAX(0, MIN(startIndex, (NSInteger)tracks.count - 1));
    [self configureAudioSession];
    [self loadTrackAtIndex:normalizedIndex autoplay:autoplay];
}

- (NSDictionary *)currentTrack {
    if (self.currentIndex == NSNotFound || self.currentIndex < 0 || self.currentIndex >= self.tracks.count) {
        return nil;
    }

    return self.tracks[self.currentIndex];
}

- (NSTimeInterval)currentTime {
    if (!self.player) {
        return 0.0;
    }

    NSTimeInterval seconds = CMTimeGetSeconds(self.player.currentTime);
    return isfinite(seconds) && seconds > 0.0 ? seconds : 0.0;
}

- (NSTimeInterval)currentDuration {
    if (!self.player.currentItem) {
        return 0.0;
    }

    NSTimeInterval seconds = CMTimeGetSeconds(self.player.currentItem.duration);
    return isfinite(seconds) && seconds > 0.0 ? seconds : 0.0;
}

- (BOOL)isPlaying {
    return self.player.rate > 0.0;
}

- (void)play {
    [self.player play];
    [self updateNowPlayingInfo];
    [self notifyStateChanged];
}

- (void)pause {
    [self.player pause];
    [self updateNowPlayingInfo];
    [self notifyStateChanged];
}

- (void)togglePlayPause {
    self.isPlaying ? [self pause] : [self play];
}

- (void)playNextTrack {
    if (self.currentIndex == NSNotFound) {
        return;
    }

    if (self.currentIndex + 1 >= self.tracks.count) {
        [self pause];
        return;
    }

    [self loadTrackAtIndex:self.currentIndex + 1 autoplay:YES];
}

- (void)playPreviousTrackOrRestart {
    NSTimeInterval currentTime = [self currentTime];
    if (currentTime > 3.0 || self.currentIndex == 0 || self.currentIndex == NSNotFound) {
        [self seekToTime:0.0 completion:nil];
        return;
    }

    [self loadTrackAtIndex:self.currentIndex - 1 autoplay:YES];
}

- (void)seekToTime:(NSTimeInterval)time completion:(dispatch_block_t)completion {
    if (!self.player) {
        if (completion) {
            completion();
        }
        return;
    }

    CMTime targetTime = CMTimeMakeWithSeconds(MAX(time, 0.0), NSEC_PER_SEC);
    [self.player seekToTime:targetTime toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero completionHandler:^(__unused BOOL finished) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self updateNowPlayingInfo];
            [self notifyStateChanged];
            if (completion) {
                completion();
            }
        });
    }];
}

- (void)loadTrackAtIndex:(NSInteger)index autoplay:(BOOL)autoplay {
    if (index < 0 || index >= self.tracks.count) {
        return;
    }

    self.currentIndex = index;
    NSDictionary *track = self.tracks[index];
    NSURL *audioURL = track[@"audioURL"];
    if (!audioURL) {
        return;
    }

    AVPlayerItem *item = [AVPlayerItem playerItemWithURL:audioURL];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemDidPlayToEndTimeNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(playerItemDidFinishPlaying:) name:AVPlayerItemDidPlayToEndTimeNotification object:item];

    if (!self.player) {
        self.player = [AVPlayer playerWithPlayerItem:item];
        __weak typeof(self) weakSelf = self;
        self.timeObserverToken = [self.player addPeriodicTimeObserverForInterval:CMTimeMakeWithSeconds(0.5, NSEC_PER_SEC) queue:dispatch_get_main_queue() usingBlock:^(__unused CMTime time) {
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) {
                return;
            }

            [self notifyStateChanged];
        }];
        [self configureRemotePlaybackSession];
    } else {
        [self.player replaceCurrentItemWithPlayerItem:item];
    }

    if (autoplay) {
        [self.player play];
    } else {
        [self.player pause];
    }

    [self updateNowPlayingInfo];
    [self notifyStateChanged];
}

- (void)playerItemDidFinishPlaying:(NSNotification *)notification {
    if (notification.object != self.player.currentItem) {
        return;
    }

    if (self.currentIndex + 1 < self.tracks.count) {
        [self loadTrackAtIndex:self.currentIndex + 1 autoplay:YES];
        return;
    }

    [self pause];
}

- (void)configureAudioSession {
    AVAudioSession *audioSession = [AVAudioSession sharedInstance];
    [audioSession setCategory:AVAudioSessionCategoryPlayback error:nil];
    [audioSession setActive:YES error:nil];
}

- (void)configureRemotePlaybackSession {
    self.nowPlayingInfoCenter = [MPNowPlayingInfoCenter defaultCenter];

    Class sessionClass = NSClassFromString(@"MPNowPlayingSession");
    if (sessionClass && !self.nowPlayingSession) {
        id session = [[sessionClass alloc] initWithPlayers:@[self.player]];
        self.nowPlayingSession = session;

        if ([session respondsToSelector:@selector(remoteCommandCenter)]) {
            self.remoteCommandCenter = [session remoteCommandCenter];
        }

        if ([session respondsToSelector:@selector(nowPlayingInfoCenter)]) {
            self.nowPlayingInfoCenter = [session nowPlayingInfoCenter];
        }
    }

    if (!self.remoteCommandCenter) {
        self.remoteCommandCenter = [MPRemoteCommandCenter sharedCommandCenter];
    }

    if (!self.remoteCommandsConfigured) {
        [self configureRemoteCommands];
        self.remoteCommandsConfigured = YES;
    }

    if (self.nowPlayingSession && [self.nowPlayingSession respondsToSelector:@selector(becomeActiveIfPossibleWithCompletion:)]) {
        [self.nowPlayingSession becomeActiveIfPossibleWithCompletion:nil];
    }
}

- (void)configureRemoteCommands {
    [self.remoteCommandCenter.playCommand addTarget:self action:@selector(handlePlayCommand:)];
    [self.remoteCommandCenter.pauseCommand addTarget:self action:@selector(handlePauseCommand:)];
    [self.remoteCommandCenter.togglePlayPauseCommand addTarget:self action:@selector(handleTogglePlayPauseCommand:)];
    [self.remoteCommandCenter.nextTrackCommand addTarget:self action:@selector(handleNextTrackCommand:)];
    [self.remoteCommandCenter.previousTrackCommand addTarget:self action:@selector(handlePreviousTrackCommand:)];
    [self.remoteCommandCenter.changePlaybackPositionCommand addTarget:self action:@selector(handleChangePlaybackPositionCommand:)];

    self.remoteCommandCenter.playCommand.enabled = YES;
    self.remoteCommandCenter.pauseCommand.enabled = YES;
    self.remoteCommandCenter.togglePlayPauseCommand.enabled = YES;
    self.remoteCommandCenter.nextTrackCommand.enabled = YES;
    self.remoteCommandCenter.previousTrackCommand.enabled = YES;
    self.remoteCommandCenter.changePlaybackPositionCommand.enabled = YES;
}

- (MPRemoteCommandHandlerStatus)handlePlayCommand:(__unused MPRemoteCommandEvent *)event {
    [self play];
    return MPRemoteCommandHandlerStatusSuccess;
}

- (MPRemoteCommandHandlerStatus)handlePauseCommand:(__unused MPRemoteCommandEvent *)event {
    [self pause];
    return MPRemoteCommandHandlerStatusSuccess;
}

- (MPRemoteCommandHandlerStatus)handleTogglePlayPauseCommand:(__unused MPRemoteCommandEvent *)event {
    [self togglePlayPause];
    return MPRemoteCommandHandlerStatusSuccess;
}

- (MPRemoteCommandHandlerStatus)handleNextTrackCommand:(__unused MPRemoteCommandEvent *)event {
    [self playNextTrack];
    return MPRemoteCommandHandlerStatusSuccess;
}

- (MPRemoteCommandHandlerStatus)handlePreviousTrackCommand:(__unused MPRemoteCommandEvent *)event {
    [self playPreviousTrackOrRestart];
    return MPRemoteCommandHandlerStatusSuccess;
}

- (MPRemoteCommandHandlerStatus)handleChangePlaybackPositionCommand:(MPChangePlaybackPositionCommandEvent *)event {
    [self seekToTime:event.positionTime completion:nil];
    return MPRemoteCommandHandlerStatusSuccess;
}

- (void)updateNowPlayingInfo {
    NSDictionary *track = [self currentTrack];
    if (!track) {
        return;
    }

    NSMutableDictionary *nowPlayingInfo = [NSMutableDictionary dictionary];
    NSString *displayName = track[@"displayName"];
    NSString *title = track[@"title"];
    NSString *artist = track[@"artist"];
    NSString *collectionTitle = track[@"collectionTitle"];

    nowPlayingInfo[MPMediaItemPropertyTitle] = displayName.length > 0 ? displayName : (title ?: @"Downloaded track");
    nowPlayingInfo[MPMediaItemPropertyArtist] = artist ?: @"";
    if (collectionTitle.length > 0) {
        nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = collectionTitle;
    }

    NSTimeInterval duration = [self currentDuration];
    if (duration > 0.0) {
        nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = @(duration);
    }

    nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = @([self currentTime]);
    nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = @(self.isPlaying ? 1.0 : 0.0);

    UIImage *artworkImage = [self artworkImageForTrack:track];
    if (artworkImage) {
        MPMediaItemArtwork *artwork = [[MPMediaItemArtwork alloc] initWithBoundsSize:artworkImage.size requestHandler:^UIImage * _Nonnull(CGSize size) {
            return artworkImage;
        }];
        nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork;
    }

    self.nowPlayingInfoCenter.nowPlayingInfo = nowPlayingInfo;
}

- (UIImage *)artworkImageForTrack:(NSDictionary *)track {
    NSURL *coverURL = track[@"coverURL"];
    if (!coverURL) {
        return nil;
    }

    return [UIImage imageWithContentsOfFile:coverURL.path];
}

- (void)notifyStateChanged {
    [[NSNotificationCenter defaultCenter] postNotificationName:YTMLocalPlaybackManagerDidUpdateNotification object:self];
}

@end
