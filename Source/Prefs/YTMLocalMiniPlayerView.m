#import "YTMLocalMiniPlayerView.h"
#import "YTMLocalPlaybackManager.h"

@interface YTMLocalMiniPlayerView () <UIGestureRecognizerDelegate>
@property (nonatomic, strong) UIVisualEffectView *backgroundView;
@property (nonatomic, strong) UIImageView *artworkView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UIButton *playPauseButton;
@property (nonatomic, strong) UIButton *nextButton;
@property (nonatomic) NSInteger displayedTrackIndex;
@property (nonatomic) NSInteger pendingTrackAnimationDirection;
@property (nonatomic) BOOL animatingTrackTransition;
@end

@implementation YTMLocalMiniPlayerView

+ (instancetype)sharedView {
    static YTMLocalMiniPlayerView *sharedView = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedView = [[self alloc] initWithFrame:CGRectZero];
    });
    return sharedView;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.hidden = YES;
        self.displayedTrackIndex = NSNotFound;
        self.layer.cornerRadius = 18.0;
        self.layer.masksToBounds = YES;
        self.backgroundColor = [UIColor clearColor];

        UIBlurEffect *blurEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemChromeMaterialDark];
        self.backgroundView = [[UIVisualEffectView alloc] initWithEffect:blurEffect];
        self.backgroundView.userInteractionEnabled = NO;
        [self addSubview:self.backgroundView];

        self.artworkView = [[UIImageView alloc] init];
        self.artworkView.contentMode = UIViewContentModeScaleAspectFill;
        self.artworkView.clipsToBounds = YES;
        self.artworkView.layer.cornerRadius = 10.0;
        [self addSubview:self.artworkView];

        self.titleLabel = [[UILabel alloc] init];
        self.titleLabel.textColor = [UIColor whiteColor];
        self.titleLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightSemibold];
        self.titleLabel.numberOfLines = 1;
        [self addSubview:self.titleLabel];

        self.subtitleLabel = [[UILabel alloc] init];
        self.subtitleLabel.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.72];
        self.subtitleLabel.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightMedium];
        self.subtitleLabel.numberOfLines = 1;
        [self addSubview:self.subtitleLabel];

        self.playPauseButton = [self buttonWithSystemName:@"pause.fill" selector:@selector(didTapPlayPause)];
        [self addSubview:self.playPauseButton];

        self.nextButton = [self buttonWithSystemName:@"forward.fill" selector:@selector(didTapNext)];
        [self addSubview:self.nextButton];

        UITapGestureRecognizer *tapGestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(didTapMiniPlayer)];
        tapGestureRecognizer.delegate = self;
        tapGestureRecognizer.cancelsTouchesInView = NO;
        [self addGestureRecognizer:tapGestureRecognizer];

        UISwipeGestureRecognizer *nextSwipeRecognizer = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(didSwipeToNext)];
        nextSwipeRecognizer.direction = UISwipeGestureRecognizerDirectionLeft;
        nextSwipeRecognizer.delegate = self;
        nextSwipeRecognizer.cancelsTouchesInView = NO;
        [self addGestureRecognizer:nextSwipeRecognizer];

        UISwipeGestureRecognizer *previousSwipeRecognizer = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(didSwipeToPrevious)];
        previousSwipeRecognizer.direction = UISwipeGestureRecognizerDirectionRight;
        previousSwipeRecognizer.delegate = self;
        previousSwipeRecognizer.cancelsTouchesInView = NO;
        [self addGestureRecognizer:previousSwipeRecognizer];

        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handlePlaybackStateDidChange:) name:YTMLocalPlaybackManagerDidUpdateNotification object:[YTMLocalPlaybackManager sharedInstance]];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleApplicationDidBecomeActive:) name:UIApplicationDidBecomeActiveNotification object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (UIButton *)buttonWithSystemName:(NSString *)systemName selector:(SEL)selector {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    UIImageSymbolConfiguration *configuration = [UIImageSymbolConfiguration configurationWithPointSize:17.0 weight:UIImageSymbolWeightSemibold];
    UIImage *image = [[UIImage systemImageNamed:systemName] imageWithConfiguration:configuration];
    [button setImage:image forState:UIControlStateNormal];
    [button setTintColor:[UIColor whiteColor]];
    [button addTarget:self action:selector forControlEvents:UIControlEventTouchUpInside];
    return button;
}

- (void)attachIfNeeded {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *targetWindow = [self targetWindow];
        if (!targetWindow) {
            return;
        }

        if (self.superview != targetWindow) {
            [self removeFromSuperview];
            [targetWindow addSubview:self];
        }

        [self updateFrameForWindow:targetWindow];
        [self refresh];
    });
}

- (void)layoutSubviews {
    [super layoutSubviews];

    self.backgroundView.frame = self.bounds;

    CGFloat height = CGRectGetHeight(self.bounds);
    CGFloat artworkSize = height - 16.0;
    self.artworkView.frame = CGRectMake(8.0, 8.0, artworkSize, artworkSize);

    CGFloat controlsWidth = 88.0;
    CGFloat labelsX = CGRectGetMaxX(self.artworkView.frame) + 10.0;
    CGFloat labelsWidth = MAX(40.0, CGRectGetWidth(self.bounds) - labelsX - controlsWidth - 8.0);
    self.titleLabel.frame = CGRectMake(labelsX, 12.0, labelsWidth, 20.0);
    self.subtitleLabel.frame = CGRectMake(labelsX, CGRectGetMaxY(self.titleLabel.frame) + 2.0, labelsWidth, 18.0);

    CGFloat buttonY = floor((height - 34.0) / 2.0);
    self.nextButton.frame = CGRectMake(CGRectGetWidth(self.bounds) - 40.0, buttonY, 28.0, 34.0);
    self.playPauseButton.frame = CGRectMake(CGRectGetMinX(self.nextButton.frame) - 34.0, buttonY, 28.0, 34.0);
}

- (void)refresh {
    dispatch_async(dispatch_get_main_queue(), ^{
        YTMLocalPlaybackManager *manager = [YTMLocalPlaybackManager sharedInstance];
        NSDictionary *track = [manager currentTrack];
        BOOL visible = ([manager hasActiveSession] &&
                        track != nil &&
                        !manager.isPlayerInterfaceVisible);

        if (!visible) {
            self.hidden = YES;
            return;
        }

        if (!self.superview) {
            [self attachIfNeeded];
            return;
        }

        UIWindow *targetWindow = [self targetWindow];
        if (targetWindow) {
            [self updateFrameForWindow:targetWindow];
        }

        self.hidden = NO;
        if (manager.currentIndex != self.displayedTrackIndex && !self.hidden && self.window && !self.animatingTrackTransition) {
            [self animateTrackTransitionToTrack:track manager:manager];
            return;
        }

        [self applyTrack:track manager:manager];
    });
}

- (void)applyTrack:(NSDictionary *)track manager:(YTMLocalPlaybackManager *)manager {
    if (!track) {
        return;
    }

    self.hidden = NO;
    self.displayedTrackIndex = manager.currentIndex;
    self.titleLabel.text = [self preferredTitleForTrack:track];
    self.subtitleLabel.text = [self preferredSubtitleForTrack:track];
    self.artworkView.image = [self artworkImageForTrack:track] ?: [self placeholderArtworkImage];

    NSString *playPauseSystemName = manager.isPlaying ? @"pause.fill" : @"play.fill";
    UIImageSymbolConfiguration *configuration = [UIImageSymbolConfiguration configurationWithPointSize:17.0 weight:UIImageSymbolWeightSemibold];
    UIImage *playPauseImage = [[UIImage systemImageNamed:playPauseSystemName] imageWithConfiguration:configuration];
    [self.playPauseButton setImage:playPauseImage forState:UIControlStateNormal];

    BOOL canGoNext = manager.tracks.count > 0;
    self.nextButton.enabled = canGoNext;
    self.nextButton.alpha = canGoNext ? 1.0 : 0.45;
}

- (NSArray<UIView *> *)trackTransitionViews {
    return @[self.artworkView, self.titleLabel, self.subtitleLabel];
}

- (NSInteger)resolvedAnimationDirectionFromIndex:(NSInteger)previousIndex
                                         toIndex:(NSInteger)newIndex
                                       trackCount:(NSInteger)trackCount {
    if (self.pendingTrackAnimationDirection != 0) {
        NSInteger direction = self.pendingTrackAnimationDirection;
        self.pendingTrackAnimationDirection = 0;
        return direction;
    }

    if (previousIndex == NSNotFound || newIndex == NSNotFound || trackCount <= 1) {
        return 0;
    }

    if (((previousIndex + 1) % trackCount) == newIndex) {
        return 1;
    }

    if (((previousIndex - 1 + trackCount) % trackCount) == newIndex) {
        return -1;
    }

    return newIndex > previousIndex ? 1 : -1;
}

- (void)animateTrackTransitionToTrack:(NSDictionary *)track manager:(YTMLocalPlaybackManager *)manager {
    NSInteger direction = [self resolvedAnimationDirectionFromIndex:self.displayedTrackIndex toIndex:manager.currentIndex trackCount:manager.tracks.count];
    if (direction == 0 || !track) {
        [self applyTrack:track manager:manager];
        return;
    }

    self.animatingTrackTransition = YES;
    NSArray<UIView *> *transitionViews = [self trackTransitionViews];
    CGFloat offset = 42.0;
    CGFloat outgoingOffset = direction > 0 ? -offset : offset;
    CGFloat incomingOffset = -outgoingOffset;

    [UIView animateWithDuration:0.15 delay:0.0 options:UIViewAnimationOptionCurveEaseIn animations:^{
        for (UIView *view in transitionViews) {
            view.transform = CGAffineTransformMakeTranslation(outgoingOffset, 0.0);
            view.alpha = 0.0;
        }
    } completion:^(__unused BOOL finished) {
        [self applyTrack:track manager:manager];

        for (UIView *view in transitionViews) {
            view.transform = CGAffineTransformMakeTranslation(incomingOffset, 0.0);
            view.alpha = 0.0;
        }

        [UIView animateWithDuration:0.22
                              delay:0.0
             usingSpringWithDamping:0.9
              initialSpringVelocity:0.2
                            options:UIViewAnimationOptionCurveEaseOut
                         animations:^{
            for (UIView *view in transitionViews) {
                view.transform = CGAffineTransformIdentity;
                view.alpha = 1.0;
            }
        } completion:^(__unused BOOL innerFinished) {
            self.animatingTrackTransition = NO;
        }];
    }];
}

- (void)handlePlaybackStateDidChange:(NSNotification *)notification {
    if (notification.object != [YTMLocalPlaybackManager sharedInstance]) {
        return;
    }

    [self refresh];
}

- (void)handleApplicationDidBecomeActive:(__unused NSNotification *)notification {
    [self attachIfNeeded];
}

- (void)didTapPlayPause {
    [[YTMLocalPlaybackManager sharedInstance] togglePlayPause];
}

- (void)didTapNext {
    self.pendingTrackAnimationDirection = 1;
    [[YTMLocalPlaybackManager sharedInstance] playNextTrack];
}

- (void)didTapMiniPlayer {
    [[YTMLocalPlaybackManager sharedInstance] presentPlayerInterfaceAnimated:YES];
}

- (void)didSwipeToNext {
    self.pendingTrackAnimationDirection = 1;
    [[YTMLocalPlaybackManager sharedInstance] playNextTrack];
}

- (void)didSwipeToPrevious {
    YTMLocalPlaybackManager *manager = [YTMLocalPlaybackManager sharedInstance];
    NSTimeInterval currentTime = [manager currentTime];
    self.pendingTrackAnimationDirection = (currentTime > 3.0 || manager.currentIndex == 0 || manager.currentIndex == NSNotFound) ? 0 : -1;
    [[YTMLocalPlaybackManager sharedInstance] playPreviousTrackOrRestart];
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    if ([touch.view isDescendantOfView:self.playPauseButton] || [touch.view isDescendantOfView:self.nextButton]) {
        return NO;
    }

    return YES;
}

- (UIWindow *)targetWindow {
    UIApplication *application = [UIApplication sharedApplication];
    if (application.keyWindow) {
        return application.keyWindow;
    }

    for (UIWindow *window in [application.windows reverseObjectEnumerator]) {
        if (!window.isHidden && window.alpha > 0.0 && window.windowLevel == UIWindowLevelNormal) {
            return window;
        }
    }

    return application.windows.firstObject;
}

- (void)updateFrameForWindow:(UIWindow *)window {
    CGFloat horizontalPadding = 12.0;
    CGFloat height = 64.0;
    CGFloat bottomClearance = MAX(82.0, window.safeAreaInsets.bottom + 48.0);
    CGFloat availableWidth = MAX(180.0, CGRectGetWidth(window.bounds) - (horizontalPadding * 2.0));
    CGFloat originY = CGRectGetHeight(window.bounds) - bottomClearance - height;
    self.frame = CGRectMake(horizontalPadding, originY, availableWidth, height);
    [self setNeedsLayout];
}

- (NSString *)preferredTitleForTrack:(NSDictionary *)track {
    NSString *displayName = track[@"displayName"];
    NSString *title = track[@"title"];
    return displayName.length > 0 ? displayName : (title.length > 0 ? title : @"Downloaded track");
}

- (NSString *)preferredSubtitleForTrack:(NSDictionary *)track {
    NSString *collectionTitle = track[@"collectionTitle"];
    NSString *artist = track[@"artist"];
    if (collectionTitle.length > 0 && artist.length > 0) {
        return [NSString stringWithFormat:@"%@ • %@", artist, collectionTitle];
    }

    if (artist.length > 0) {
        return artist;
    }

    return collectionTitle.length > 0 ? collectionTitle : @"Local playback";
}

- (UIImage *)artworkImageForTrack:(NSDictionary *)track {
    NSURL *coverURL = track[@"coverURL"];
    return coverURL ? [UIImage imageWithContentsOfFile:coverURL.path] : nil;
}

- (UIImage *)placeholderArtworkImage {
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(48.0, 48.0)];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext * _Nonnull rendererContext) {
        CGRect rect = CGRectMake(0, 0, 48.0, 48.0);
        [[UIBezierPath bezierPathWithRoundedRect:rect cornerRadius:10.0] addClip];
        [[[UIColor whiteColor] colorWithAlphaComponent:0.08] setFill];
        UIRectFill(rect);

        UIImageSymbolConfiguration *configuration = [UIImageSymbolConfiguration configurationWithPointSize:18.0 weight:UIImageSymbolWeightRegular];
        UIImage *symbolImage = [[UIImage systemImageNamed:@"music.note.list"] imageWithConfiguration:configuration];
        symbolImage = [symbolImage imageWithTintColor:[[UIColor whiteColor] colorWithAlphaComponent:0.72] renderingMode:UIImageRenderingModeAlwaysOriginal];
        CGSize imageSize = symbolImage.size;
        CGRect imageRect = CGRectMake((CGRectGetWidth(rect) - imageSize.width) / 2.0, (CGRectGetHeight(rect) - imageSize.height) / 2.0, imageSize.width, imageSize.height);
        [symbolImage drawInRect:imageRect];
    }];
}

@end
