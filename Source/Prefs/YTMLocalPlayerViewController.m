#import "YTMLocalPlayerViewController.h"
#import <math.h>
#import "YTMLocalPlaybackManager.h"

@interface YTMLocalPlayerViewController () <UIGestureRecognizerDelegate>
@property (nonatomic, copy) NSArray<NSDictionary *> *tracks;
@property (nonatomic) NSInteger startIndex;
@property (nonatomic, strong) UIImageView *artworkView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UILabel *collectionLabel;
@property (nonatomic, strong) UILabel *queueLabel;
@property (nonatomic, strong) UILabel *elapsedLabel;
@property (nonatomic, strong) UILabel *remainingLabel;
@property (nonatomic, strong) UISlider *progressSlider;
@property (nonatomic, strong) UIButton *previousButton;
@property (nonatomic, strong) UIButton *playPauseButton;
@property (nonatomic, strong) UIButton *nextButton;
@property (nonatomic) BOOL scrubbing;
@end

@implementation YTMLocalPlayerViewController

- (instancetype)initWithTracks:(NSArray<NSDictionary *> *)tracks startIndex:(NSInteger)startIndex {
    self = [super init];
    if (self) {
        _tracks = [tracks copy] ?: @[];
        _startIndex = MAX(0, MIN(startIndex, (NSInteger)_tracks.count - 1));
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = [UIColor colorWithRed:3/255.0 green:3/255.0 blue:3/255.0 alpha:1.0];
    self.title = @"Downloads";
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemClose target:self action:@selector(closeController)];

    [self buildInterface];

    YTMLocalPlaybackManager *manager = [YTMLocalPlaybackManager sharedInstance];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(playbackStateDidChange:) name:YTMLocalPlaybackManagerDidUpdateNotification object:manager];
    if (![manager hasActiveSession] || ![manager isManagingTracks:self.tracks] || manager.currentIndex != self.startIndex) {
        [manager loadTracks:self.tracks startIndex:self.startIndex autoplay:YES];
    }
    [self refreshInterface];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [[YTMLocalPlaybackManager sharedInstance] playerInterfaceDidAppear];
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    [[YTMLocalPlaybackManager sharedInstance] playerInterfaceDidDisappear];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)closeController {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)buildInterface {
    UIScrollView *scrollView = [[UIScrollView alloc] init];
    scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    scrollView.alwaysBounceVertical = YES;
    [self.view addSubview:scrollView];

    UIView *contentView = [[UIView alloc] init];
    contentView.translatesAutoresizingMaskIntoConstraints = NO;
    [scrollView addSubview:contentView];

    [NSLayoutConstraint activateConstraints:@[
        [scrollView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        [contentView.topAnchor constraintEqualToAnchor:scrollView.contentLayoutGuide.topAnchor],
        [contentView.leadingAnchor constraintEqualToAnchor:scrollView.contentLayoutGuide.leadingAnchor],
        [contentView.trailingAnchor constraintEqualToAnchor:scrollView.contentLayoutGuide.trailingAnchor],
        [contentView.bottomAnchor constraintEqualToAnchor:scrollView.contentLayoutGuide.bottomAnchor],
        [contentView.widthAnchor constraintEqualToAnchor:scrollView.frameLayoutGuide.widthAnchor]
    ]];

    UIStackView *stackView = [[UIStackView alloc] init];
    stackView.translatesAutoresizingMaskIntoConstraints = NO;
    stackView.axis = UILayoutConstraintAxisVertical;
    stackView.alignment = UIStackViewAlignmentFill;
    stackView.spacing = 18.0;
    [contentView addSubview:stackView];

    [NSLayoutConstraint activateConstraints:@[
        [stackView.topAnchor constraintEqualToAnchor:contentView.topAnchor constant:24.0],
        [stackView.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:20.0],
        [stackView.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-20.0],
        [stackView.bottomAnchor constraintEqualToAnchor:contentView.bottomAnchor constant:-24.0]
    ]];

    self.artworkView = [[UIImageView alloc] init];
    self.artworkView.translatesAutoresizingMaskIntoConstraints = NO;
    self.artworkView.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.06];
    self.artworkView.contentMode = UIViewContentModeScaleAspectFill;
    self.artworkView.clipsToBounds = YES;
    self.artworkView.layer.cornerRadius = 22.0;
    [stackView addArrangedSubview:self.artworkView];
    [[self.artworkView.heightAnchor constraintEqualToConstant:320.0] setActive:YES];

    self.titleLabel = [[UILabel alloc] init];
    self.titleLabel.textColor = [UIColor whiteColor];
    self.titleLabel.font = [UIFont boldSystemFontOfSize:28.0];
    self.titleLabel.numberOfLines = 1;
    self.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [stackView addArrangedSubview:self.titleLabel];
    [[self.titleLabel.heightAnchor constraintEqualToConstant:34.0] setActive:YES];

    self.subtitleLabel = [[UILabel alloc] init];
    self.subtitleLabel.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.78];
    self.subtitleLabel.font = [UIFont systemFontOfSize:18.0 weight:UIFontWeightMedium];
    self.subtitleLabel.numberOfLines = 1;
    self.subtitleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [stackView addArrangedSubview:self.subtitleLabel];
    [[self.subtitleLabel.heightAnchor constraintEqualToConstant:24.0] setActive:YES];

    self.collectionLabel = [[UILabel alloc] init];
    self.collectionLabel.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.56];
    self.collectionLabel.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightSemibold];
    self.collectionLabel.numberOfLines = 1;
    self.collectionLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [stackView addArrangedSubview:self.collectionLabel];
    [[self.collectionLabel.heightAnchor constraintEqualToConstant:20.0] setActive:YES];

    UIView *sliderContainer = [[UIView alloc] init];
    [stackView addArrangedSubview:sliderContainer];

    self.progressSlider = [[UISlider alloc] init];
    self.progressSlider.translatesAutoresizingMaskIntoConstraints = NO;
    self.progressSlider.minimumValue = 0.0;
    self.progressSlider.maximumValue = 1.0;
    self.progressSlider.minimumTrackTintColor = [UIColor whiteColor];
    self.progressSlider.maximumTrackTintColor = [[UIColor whiteColor] colorWithAlphaComponent:0.2];
    [self.progressSlider addTarget:self action:@selector(sliderTouchDown:) forControlEvents:UIControlEventTouchDown];
    [self.progressSlider addTarget:self action:@selector(sliderValueChanged:) forControlEvents:UIControlEventValueChanged];
    [self.progressSlider addTarget:self action:@selector(sliderTouchUp:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
    [sliderContainer addSubview:self.progressSlider];

    self.elapsedLabel = [[UILabel alloc] init];
    self.elapsedLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.elapsedLabel.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.6];
    self.elapsedLabel.font = [UIFont monospacedDigitSystemFontOfSize:13.0 weight:UIFontWeightMedium];
    [sliderContainer addSubview:self.elapsedLabel];

    self.remainingLabel = [[UILabel alloc] init];
    self.remainingLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.remainingLabel.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.6];
    self.remainingLabel.textAlignment = NSTextAlignmentRight;
    self.remainingLabel.font = [UIFont monospacedDigitSystemFontOfSize:13.0 weight:UIFontWeightMedium];
    [sliderContainer addSubview:self.remainingLabel];

    [NSLayoutConstraint activateConstraints:@[
        [self.progressSlider.topAnchor constraintEqualToAnchor:sliderContainer.topAnchor],
        [self.progressSlider.leadingAnchor constraintEqualToAnchor:sliderContainer.leadingAnchor],
        [self.progressSlider.trailingAnchor constraintEqualToAnchor:sliderContainer.trailingAnchor],

        [self.elapsedLabel.topAnchor constraintEqualToAnchor:self.progressSlider.bottomAnchor constant:6.0],
        [self.elapsedLabel.leadingAnchor constraintEqualToAnchor:sliderContainer.leadingAnchor],
        [self.elapsedLabel.bottomAnchor constraintEqualToAnchor:sliderContainer.bottomAnchor],

        [self.remainingLabel.topAnchor constraintEqualToAnchor:self.progressSlider.bottomAnchor constant:6.0],
        [self.remainingLabel.trailingAnchor constraintEqualToAnchor:sliderContainer.trailingAnchor],
        [self.remainingLabel.bottomAnchor constraintEqualToAnchor:sliderContainer.bottomAnchor]
    ]];

    UIStackView *controlsStackView = [[UIStackView alloc] init];
    controlsStackView.axis = UILayoutConstraintAxisHorizontal;
    controlsStackView.alignment = UIStackViewAlignmentCenter;
    controlsStackView.distribution = UIStackViewDistributionEqualCentering;
    controlsStackView.spacing = 24.0;
    [stackView addArrangedSubview:controlsStackView];

    self.previousButton = [self controlButtonWithSystemName:@"backward.fill" pointSize:24.0 selector:@selector(didTapPrevious)];
    self.playPauseButton = [self controlButtonWithSystemName:@"pause.fill" pointSize:30.0 selector:@selector(didTapPlayPause)];
    self.nextButton = [self controlButtonWithSystemName:@"forward.fill" pointSize:24.0 selector:@selector(didTapNext)];

    self.previousButton.contentEdgeInsets = UIEdgeInsetsMake(12.0, 12.0, 12.0, 12.0);
    self.playPauseButton.contentEdgeInsets = UIEdgeInsetsMake(16.0, 18.0, 16.0, 18.0);
    self.nextButton.contentEdgeInsets = UIEdgeInsetsMake(12.0, 12.0, 12.0, 12.0);
    self.playPauseButton.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.12];
    self.playPauseButton.layer.cornerRadius = 30.0;

    [controlsStackView addArrangedSubview:self.previousButton];
    [controlsStackView addArrangedSubview:self.playPauseButton];
    [controlsStackView addArrangedSubview:self.nextButton];

    self.queueLabel = [[UILabel alloc] init];
    self.queueLabel.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.72];
    self.queueLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightSemibold];
    self.queueLabel.textAlignment = NSTextAlignmentCenter;
    self.queueLabel.numberOfLines = 1;
    [stackView addArrangedSubview:self.queueLabel];
    [[self.queueLabel.heightAnchor constraintEqualToConstant:20.0] setActive:YES];

    UISwipeGestureRecognizer *nextSwipeRecognizer = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(didSwipeToNext)];
    nextSwipeRecognizer.direction = UISwipeGestureRecognizerDirectionLeft;
    nextSwipeRecognizer.delegate = self;
    nextSwipeRecognizer.cancelsTouchesInView = NO;
    [self.view addGestureRecognizer:nextSwipeRecognizer];

    UISwipeGestureRecognizer *previousSwipeRecognizer = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(didSwipeToPrevious)];
    previousSwipeRecognizer.direction = UISwipeGestureRecognizerDirectionRight;
    previousSwipeRecognizer.delegate = self;
    previousSwipeRecognizer.cancelsTouchesInView = NO;
    [self.view addGestureRecognizer:previousSwipeRecognizer];
}

- (UIButton *)controlButtonWithSystemName:(NSString *)systemName pointSize:(CGFloat)pointSize selector:(SEL)selector {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    UIImageSymbolConfiguration *configuration = [UIImageSymbolConfiguration configurationWithPointSize:pointSize weight:UIImageSymbolWeightSemibold];
    UIImage *image = [[UIImage systemImageNamed:systemName] imageWithConfiguration:configuration];
    [button setImage:image forState:UIControlStateNormal];
    [button setTintColor:[UIColor whiteColor]];
    [button addTarget:self action:selector forControlEvents:UIControlEventTouchUpInside];
    return button;
}

- (void)playbackStateDidChange:(NSNotification *)notification {
    if (notification.object != [YTMLocalPlaybackManager sharedInstance]) {
        return;
    }

    if (![[YTMLocalPlaybackManager sharedInstance] hasActiveSession]) {
        [self closeController];
        return;
    }

    if (!self.scrubbing) {
        [self refreshInterface];
    }
}

- (void)refreshInterface {
    YTMLocalPlaybackManager *manager = [YTMLocalPlaybackManager sharedInstance];
    NSDictionary *track = [manager currentTrack];
    if (!track) {
        return;
    }

    NSString *displayName = track[@"displayName"];
    NSString *title = track[@"title"];
    NSString *artist = track[@"artist"];
    NSString *collectionTitle = track[@"collectionTitle"];

    self.titleLabel.text = displayName.length > 0 ? displayName : title;
    self.subtitleLabel.text = artist.length > 0 ? artist : title;
    self.collectionLabel.text = collectionTitle.length > 0 ? collectionTitle : @"Downloaded audio";
    self.queueLabel.text = [NSString stringWithFormat:@"Track %ld of %ld", (long)manager.currentIndex + 1, (long)manager.tracks.count];

    UIImage *artworkImage = [self artworkImageForTrack:track];
    self.artworkView.image = artworkImage ?: [self placeholderArtworkImage];

    NSTimeInterval duration = [manager currentDuration];
    NSTimeInterval currentTime = [manager currentTime];
    self.progressSlider.maximumValue = duration > 0 ? duration : 1.0;
    self.progressSlider.value = duration > 0 ? MIN(currentTime, duration) : 0.0;
    [self updateTimeLabelsForCurrentTime:currentTime duration:duration];
    [self updateNavigationButtons];
    [self updatePlayPauseButton];
}

- (UIImage *)artworkImageForTrack:(NSDictionary *)track {
    NSURL *coverURL = track[@"coverURL"];
    return coverURL ? [UIImage imageWithContentsOfFile:coverURL.path] : nil;
}

- (UIImage *)placeholderArtworkImage {
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(700.0, 700.0)];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext * _Nonnull rendererContext) {
        CGRect bounds = CGRectMake(0, 0, 700.0, 700.0);
        [[UIColor colorWithRed:28/255.0 green:28/255.0 blue:28/255.0 alpha:1.0] setFill];
        UIRectFill(bounds);

        UIImageSymbolConfiguration *configuration = [UIImageSymbolConfiguration configurationWithPointSize:180.0 weight:UIImageSymbolWeightRegular];
        UIImage *symbolImage = [[UIImage systemImageNamed:@"music.note.list"] imageWithConfiguration:configuration];
        symbolImage = [symbolImage imageWithTintColor:[[UIColor whiteColor] colorWithAlphaComponent:0.72] renderingMode:UIImageRenderingModeAlwaysOriginal];
        CGSize imageSize = symbolImage.size;
        CGRect imageRect = CGRectMake((CGRectGetWidth(bounds) - imageSize.width) / 2.0, (CGRectGetHeight(bounds) - imageSize.height) / 2.0, imageSize.width, imageSize.height);
        [symbolImage drawInRect:imageRect];
    }];
}

- (void)didTapPrevious {
    [[YTMLocalPlaybackManager sharedInstance] playPreviousTrackOrRestart];
}

- (void)didTapPlayPause {
    [[YTMLocalPlaybackManager sharedInstance] togglePlayPause];
}

- (void)didTapNext {
    [[YTMLocalPlaybackManager sharedInstance] playNextTrack];
}

- (void)didSwipeToNext {
    [[YTMLocalPlaybackManager sharedInstance] playNextTrack];
}

- (void)didSwipeToPrevious {
    [[YTMLocalPlaybackManager sharedInstance] playPreviousTrackOrRestart];
}

- (void)sliderTouchDown:(UISlider *)slider {
    self.scrubbing = YES;
}

- (void)sliderValueChanged:(UISlider *)slider {
    [self updateTimeLabelsForCurrentTime:slider.value duration:[[YTMLocalPlaybackManager sharedInstance] currentDuration]];
}

- (void)sliderTouchUp:(UISlider *)slider {
    self.scrubbing = NO;
    [[YTMLocalPlaybackManager sharedInstance] seekToTime:slider.value completion:^{
        [self refreshInterface];
    }];
}

- (void)updateTimeLabelsForCurrentTime:(NSTimeInterval)currentTime duration:(NSTimeInterval)duration {
    self.elapsedLabel.text = [self formattedTime:currentTime];
    NSTimeInterval remainingTime = MAX(duration - currentTime, 0.0);
    self.remainingLabel.text = duration > 0 ? [NSString stringWithFormat:@"-%@", [self formattedTime:remainingTime]] : @"--:--";
}

- (NSString *)formattedTime:(NSTimeInterval)time {
    if (!isfinite(time) || time < 0.0) {
        return @"00:00";
    }

    NSInteger roundedTime = (NSInteger)llround(time);
    NSInteger hours = roundedTime / 3600;
    NSInteger minutes = (roundedTime % 3600) / 60;
    NSInteger seconds = roundedTime % 60;

    if (hours > 0) {
        return [NSString stringWithFormat:@"%ld:%02ld:%02ld", (long)hours, (long)minutes, (long)seconds];
    }

    return [NSString stringWithFormat:@"%02ld:%02ld", (long)minutes, (long)seconds];
}

- (void)updateNavigationButtons {
    YTMLocalPlaybackManager *manager = [YTMLocalPlaybackManager sharedInstance];
    BOOL canGoBack = (manager.currentIndex > 0 || [manager currentTime] > 3.0);
    self.previousButton.enabled = canGoBack;
    self.previousButton.alpha = canGoBack ? 1.0 : 0.45;

    BOOL canGoNext = manager.tracks.count > 0;
    self.nextButton.enabled = canGoNext;
    self.nextButton.alpha = canGoNext ? 1.0 : 0.45;
}

- (void)updatePlayPauseButton {
    BOOL isPlaying = [YTMLocalPlaybackManager sharedInstance].playing;
    NSString *systemName = isPlaying ? @"pause.fill" : @"play.fill";
    UIImageSymbolConfiguration *configuration = [UIImageSymbolConfiguration configurationWithPointSize:30.0 weight:UIImageSymbolWeightSemibold];
    UIImage *image = [[UIImage systemImageNamed:systemName] imageWithConfiguration:configuration];
    [self.playPauseButton setImage:image forState:UIControlStateNormal];
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    if ([touch.view isDescendantOfView:self.progressSlider] ||
        [touch.view isDescendantOfView:self.previousButton] ||
        [touch.view isDescendantOfView:self.playPauseButton] ||
        [touch.view isDescendantOfView:self.nextButton]) {
        return NO;
    }

    return YES;
}

@end
