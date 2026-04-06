#import "YTMLocalPlaybackManager.h"
#import "YTMLocalMiniPlayerView.h"
#import "YTMLocalPlayerViewController.h"
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

        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleApplicationDidBecomeActive:) name:UIApplicationDidBecomeActiveNotification object:nil];
    }
    return self;
}

- (void)dealloc {
    if (self.timeObserverToken && self.player) {
        [self.player removeTimeObserver:self.timeObserverToken];
    }
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (BOOL)hasActiveSession {
    return (self.player != nil &&
            self.currentIndex != NSNotFound &&
            self.currentIndex >= 0 &&
            self.currentIndex < self.tracks.count);
}

- (BOOL)isManagingTracks:(NSArray<NSDictionary *> *)tracks {
    if (self.tracks.count != tracks.count) {
        return NO;
    }

    for (NSUInteger index = 0; index < tracks.count; index++) {
        NSURL *existingURL = self.tracks[index][@"audioURL"];
        NSURL *incomingURL = tracks[index][@"audioURL"];
        if (![existingURL.path isEqualToString:incomingURL.path]) {
            return NO;
        }
    }

    return YES;
}

- (void)loadTracks:(NSArray<NSDictionary *> *)tracks startIndex:(NSInteger)startIndex autoplay:(BOOL)autoplay {
    if (tracks.count == 0) {
        return;
    }

    NSInteger normalizedIndex = MAX(0, MIN(startIndex, (NSInteger)tracks.count - 1));
    BOOL isSameTrackList = [self isManagingTracks:tracks];

    [self pauseCompetingAppPlaybackIfNeeded];
    [self configureAudioSession];

    if (!isSameTrackList) {
        self.tracks = [tracks copy];
    }

    if (isSameTrackList && self.player && self.currentIndex == normalizedIndex) {
        if (autoplay) {
            [self.player play];
        } else {
            [self.player pause];
        }

        [self updateNowPlayingInfo];
        [self notifyStateChanged];
        return;
    }

    [self loadTrackAtIndex:normalizedIndex autoplay:autoplay];
}

- (NSDictionary *)currentTrack {
    if (![self hasActiveSession]) {
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

    if (self.tracks.count == 0) {
        return;
    }

    NSInteger nextIndex = (self.currentIndex + 1) % self.tracks.count;
    [self loadTrackAtIndex:nextIndex autoplay:YES];
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

- (void)presentPlayerInterfaceAnimated:(BOOL)animated {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (![self hasActiveSession]) {
            return;
        }

        UIViewController *topViewController = [self topViewController];
        if (!topViewController) {
            return;
        }

        UIViewController *presentedController = topViewController;
        if ([presentedController isKindOfClass:[UINavigationController class]]) {
            UIViewController *rootController = ((UINavigationController *)presentedController).viewControllers.firstObject;
            if ([rootController isKindOfClass:[YTMLocalPlayerViewController class]]) {
                return;
            }
        }

        if ([presentedController isKindOfClass:[YTMLocalPlayerViewController class]]) {
            return;
        }

        YTMLocalPlayerViewController *playerViewController = [[YTMLocalPlayerViewController alloc] initWithTracks:self.tracks startIndex:self.currentIndex];
        UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:playerViewController];
        navigationController.modalPresentationStyle = UIModalPresentationPageSheet;
        if (@available(iOS 15.0, *)) {
            navigationController.sheetPresentationController.detents = @[[UISheetPresentationControllerDetent largeDetent]];
            navigationController.sheetPresentationController.prefersGrabberVisible = YES;
            navigationController.sheetPresentationController.preferredCornerRadius = 24.0;
        }

        [topViewController presentViewController:navigationController animated:animated completion:nil];
    });
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

            [self updateNowPlayingInfo];
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

- (void)handleApplicationDidBecomeActive:(__unused NSNotification *)notification {
    if (![self hasActiveSession]) {
        return;
    }

    [self updateNowPlayingInfo];
    [[YTMLocalMiniPlayerView sharedView] attachIfNeeded];
    [[YTMLocalMiniPlayerView sharedView] refresh];
}

- (void)configureAudioSession {
    AVAudioSession *audioSession = [AVAudioSession sharedInstance];
    [audioSession setCategory:AVAudioSessionCategoryPlayback error:nil];
    [audioSession setActive:YES error:nil];
    [[UIApplication sharedApplication] beginReceivingRemoteControlEvents];
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
        self.nowPlayingInfoCenter.nowPlayingInfo = nil;
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
    nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackQueueIndex] = @(self.currentIndex);
    nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackQueueCount] = @(self.tracks.count);

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
    [[YTMLocalMiniPlayerView sharedView] attachIfNeeded];
    [[YTMLocalMiniPlayerView sharedView] refresh];
    [[NSNotificationCenter defaultCenter] postNotificationName:YTMLocalPlaybackManagerDidUpdateNotification object:self];
}

- (void)pauseCompetingAppPlaybackIfNeeded {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSMutableSet<NSString *> *visitedObjects = [NSMutableSet set];
        for (UIWindow *window in [UIApplication sharedApplication].windows) {
            if (window.isHidden || window.alpha <= 0.0 || window.windowLevel != UIWindowLevelNormal) {
                continue;
            }

            [self pauseCompetingPlaybackInObject:window.rootViewController visitedObjects:visitedObjects];
        }
    });
}

- (void)pauseCompetingPlaybackInObject:(id)object visitedObjects:(NSMutableSet<NSString *> *)visitedObjects {
    if (!object) {
        return;
    }

    NSString *visitKey = [NSString stringWithFormat:@"%p", object];
    if ([visitedObjects containsObject:visitKey]) {
        return;
    }
    [visitedObjects addObject:visitKey];

    if (object == self || object == self.player || object == self.player.currentItem) {
        return;
    }

    if ([object isKindOfClass:[AVPlayer class]]) {
        [(AVPlayer *)object pause];
        return;
    }

    id directPlayer = [self safeValueForAnyKey:@[@"player", @"_player", @"playerInternal", @"_playerInternal"] onObject:object];
    if (directPlayer && directPlayer != self.player) {
        if ([directPlayer isKindOfClass:[AVPlayer class]]) {
            [(AVPlayer *)directPlayer pause];
        } else if ([directPlayer respondsToSelector:@selector(pause)]) {
            [self invokeSelectorNamed:@"pause" onObject:directPlayer];
        }
    }

    if ([self objectShowsVisiblePauseButton:object]) {
        for (NSString *selectorName in @[@"didTapMiniplayerPlaybackButton", @"didTapPlaybackButton", @"didTapPlayButton"]) {
            if ([object respondsToSelector:NSSelectorFromString(selectorName)]) {
                [self invokeSelectorNamed:selectorName onObject:object];
                break;
            }
        }
    }

    for (NSString *selectorName in @[@"pause", @"pausePlayback"]) {
        if ([object respondsToSelector:NSSelectorFromString(selectorName)]) {
            [self invokeSelectorNamed:selectorName onObject:object];
            break;
        }
    }

    NSArray *relatedKeys = @[
        @"playerViewController",
        @"watchViewController",
        @"playbackController",
        @"contentPlaybackController",
        @"miniPlayerViewController",
        @"presentedViewController",
        @"parentViewController",
        @"nextResponder"
    ];

    for (NSString *key in relatedKeys) {
        id relatedObject = [self safeValueForKey:key onObject:object];
        if (relatedObject && relatedObject != object) {
            [self pauseCompetingPlaybackInObject:relatedObject visitedObjects:visitedObjects];
        }
    }

    if ([object isKindOfClass:[UIViewController class]]) {
        UIViewController *viewController = (UIViewController *)object;
        for (UIViewController *childViewController in viewController.childViewControllers) {
            [self pauseCompetingPlaybackInObject:childViewController visitedObjects:visitedObjects];
        }
        [self pauseCompetingPlaybackInObject:viewController.view visitedObjects:visitedObjects];
    } else if ([object isKindOfClass:[UIView class]]) {
        UIView *view = (UIView *)object;
        for (UIView *subview in view.subviews) {
            [self pauseCompetingPlaybackInObject:subview visitedObjects:visitedObjects];
        }
    }
}

- (BOOL)objectShowsVisiblePauseButton:(id)object {
    UIButton *pauseButton = [self safeValueForAnyKey:@[@"pauseButton", @"_pauseButton"] onObject:object];
    if (![pauseButton isKindOfClass:[UIButton class]]) {
        return NO;
    }

    return (!pauseButton.hidden &&
            pauseButton.alpha > 0.01 &&
            pauseButton.window != nil &&
            pauseButton.userInteractionEnabled);
}

- (id)safeValueForAnyKey:(NSArray<NSString *> *)keys onObject:(id)object {
    for (NSString *key in keys) {
        id value = [self safeValueForKey:key onObject:object];
        if (value) {
            return value;
        }
    }

    return nil;
}

- (id)safeValueForKey:(NSString *)key onObject:(id)object {
    @try {
        return [object valueForKey:key];
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

- (void)invokeSelectorNamed:(NSString *)selectorName onObject:(id)object {
    SEL selector = NSSelectorFromString(selectorName);
    if (!object || ![object respondsToSelector:selector]) {
        return;
    }

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    [object performSelector:selector];
#pragma clang diagnostic pop
}

- (UIViewController *)topViewController {
    UIApplication *application = [UIApplication sharedApplication];
    UIWindow *targetWindow = application.keyWindow;
    if (!targetWindow) {
        for (UIWindow *window in [application.windows reverseObjectEnumerator]) {
            if (!window.isHidden && window.alpha > 0.0 && window.windowLevel == UIWindowLevelNormal) {
                targetWindow = window;
                break;
            }
        }
    }

    return [self topViewControllerFromRootViewController:targetWindow.rootViewController];
}

- (UIViewController *)topViewControllerFromRootViewController:(UIViewController *)rootViewController {
    if (!rootViewController) {
        return nil;
    }

    if ([rootViewController isKindOfClass:[UINavigationController class]]) {
        UINavigationController *navigationController = (UINavigationController *)rootViewController;
        return [self topViewControllerFromRootViewController:navigationController.visibleViewController];
    }

    if ([rootViewController isKindOfClass:[UITabBarController class]]) {
        UITabBarController *tabBarController = (UITabBarController *)rootViewController;
        return [self topViewControllerFromRootViewController:tabBarController.selectedViewController];
    }

    if (rootViewController.presentedViewController) {
        return [self topViewControllerFromRootViewController:rootViewController.presentedViewController];
    }

    return rootViewController;
}

@end
