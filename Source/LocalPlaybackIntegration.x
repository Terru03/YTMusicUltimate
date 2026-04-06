#import "Prefs/YTMLocalMiniPlayerView.h"
#import "Prefs/YTMLocalPlaybackManager.h"

static void YTMUStopLocalPlaybackIfNeeded(void) {
    YTMLocalPlaybackManager *manager = [YTMLocalPlaybackManager sharedInstance];
    if ([manager hasActiveSession]) {
        [manager stopAndClearSession];
    }
}

%hook YTMMiniPlayerView
- (BOOL)isHidden {
    return [[YTMLocalPlaybackManager sharedInstance] hasActiveSession] ? YES : %orig;
}

- (void)setHidden:(BOOL)hidden {
    YTMLocalPlaybackManager *manager = [YTMLocalPlaybackManager sharedInstance];
    if ([manager hasActiveSession] && !hidden) {
        [manager stopAndClearSession];
        %orig(NO);
        return;
    }

    %orig([manager hasActiveSession] ? YES : hidden);
}
%end

%hook YTMNowPlayingViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;

    if ([[YTMLocalPlaybackManager sharedInstance] hasActiveSession]) {
        [[YTMLocalMiniPlayerView sharedView] attachIfNeeded];
    }
}

- (void)didTapPlayButton {
    YTMUStopLocalPlaybackIfNeeded();
    %orig;
}

- (void)didTapNextButton {
    YTMUStopLocalPlaybackIfNeeded();
    %orig;
}

- (void)didTapPrevButton {
    YTMUStopLocalPlaybackIfNeeded();
    %orig;
}
%end

%hook YTMMiniPlayerViewController
- (void)didTapMiniplayerPlaybackButton {
    YTMUStopLocalPlaybackIfNeeded();
    %orig;
}

- (void)didTapMiniplayerNextButton {
    YTMUStopLocalPlaybackIfNeeded();
    %orig;
}
%end
