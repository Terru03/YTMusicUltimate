#import "Prefs/YTMLocalMiniPlayerView.h"
#import "Prefs/YTMLocalPlaybackManager.h"

%hook YTMMiniPlayerView
- (BOOL)isHidden {
    return [[YTMLocalPlaybackManager sharedInstance] hasActiveSession] ? YES : %orig;
}

- (void)setHidden:(BOOL)hidden {
    %orig([[YTMLocalPlaybackManager sharedInstance] hasActiveSession] ? YES : hidden);
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
    if ([[YTMLocalPlaybackManager sharedInstance] hasActiveSession]) {
        [[YTMLocalPlaybackManager sharedInstance] togglePlayPause];
        return;
    }

    %orig;
}
%end

%hook YTMMiniPlayerViewController
- (void)didTapMiniplayerPlaybackButton {
    if ([[YTMLocalPlaybackManager sharedInstance] hasActiveSession]) {
        [[YTMLocalPlaybackManager sharedInstance] togglePlayPause];
        return;
    }

    %orig;
}

- (void)didTapMiniplayerNextButton {
    if ([[YTMLocalPlaybackManager sharedInstance] hasActiveSession]) {
        [[YTMLocalPlaybackManager sharedInstance] playNextTrack];
        return;
    }

    %orig;
}
%end
