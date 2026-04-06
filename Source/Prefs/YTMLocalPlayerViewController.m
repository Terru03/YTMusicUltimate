#import "YTMLocalPlayerViewController.h"
#import <AVFoundation/AVFoundation.h>
#import <math.h>

@interface YTMLocalPlayerViewController ()
@property (nonatomic, copy) NSArray<NSDictionary *> *tracks;
@property (nonatomic) NSInteger currentIndex;
@property (nonatomic, strong) AVPlayer *player;
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
@property (nonatomic, strong) id timeObserverToken;
@property (nonatomic) BOOL scrubbing;
@end

@implementation YTMLocalPlayerViewController

- (instancetype)initWithTracks:(NSArray<NSDictionary *> *)tracks startIndex:(NSInteger)startIndex {
    self = [super init];
    if (self) {
        _tracks = [tracks copy] ?: @[];
        _currentIndex = MAX(0, MIN(startIndex, (NSInteger)_tracks.count - 1));
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = [UIColor colorWithRed:3/255.0 green:3/255.0 blue:3/255.0 alpha:1.0];
    self.title = @"Downloads";
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemClose target:self action:@selector(closeController)];

    [self configureAudioSession];
    [self buildInterface];
    [self loadTrackAtIndex:self.currentIndex autoplay:YES];
}

- (void)dealloc {
    if (self.timeObserverToken && self.player) {
        [self.player removeTimeObserver:self.timeObserverToken];
    }
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)closeController {
    [self.player pause];
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

    NSLayoutConstraint *artworkHeightConstraint = [self.artworkView.heightAnchor constraintEqualToConstant:300.0];
    artworkHeightConstraint.active = YES;

    self.titleLabel = [[UILabel alloc] init];
    self.titleLabel.textColor = [UIColor whiteColor];
    self.titleLabel.font = [UIFont boldSystemFontOfSize:28.0];
    self.titleLabel.numberOfLines = 2;
    [stackView addArrangedSubview:self.titleLabel];

    self.subtitleLabel = [[UILabel alloc] init];
    self.subtitleLabel.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.78];
    self.subtitleLabel.font = [UIFont systemFontOfSize:18.0 weight:UIFontWeightMedium];
    self.subtitleLabel.numberOfLines = 2;
    [stackView addArrangedSubview:self.subtitleLabel];

    self.collectionLabel = [[UILabel alloc] init];
    self.collectionLabel.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.56];
    self.collectionLabel.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightSemibold];
    self.collectionLabel.numberOfLines = 2;
    [stackView addArrangedSubview:self.collectionLabel];

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
    self.queueLabel.numberOfLines = 0;
    [stackView addArrangedSubview:self.queueLabel];
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
        self.timeObserverToken = [self.player addPeriodicTimeObserverForInterval:CMTimeMakeWithSeconds(0.5, NSEC_PER_SEC) queue:dispatch_get_main_queue() usingBlock:^(CMTime time) {
            __strong typeof(weakSelf) self = weakSelf;
            if (!self || self.scrubbing) {
                return;
            }
            [self updateProgressWithCurrentTime:CMTimeGetSeconds(time)];
        }];
    } else {
        [self.player replaceCurrentItemWithPlayerItem:item];
    }

    [self updateInterfaceForTrack:track];
    [self updateProgressWithCurrentTime:0.0];
    [self updateNavigationButtons];

    if (autoplay) {
        [self.player play];
    } else {
        [self.player pause];
    }

    [self updatePlayPauseButton];
}

- (void)updateInterfaceForTrack:(NSDictionary *)track {
    NSString *displayName = track[@"displayName"];
    NSString *title = track[@"title"];
    NSString *artist = track[@"artist"];
    NSString *collectionTitle = track[@"collectionTitle"];

    self.titleLabel.text = displayName.length > 0 ? displayName : title;
    self.subtitleLabel.text = artist.length > 0 ? artist : title;
    self.collectionLabel.text = collectionTitle.length > 0 ? collectionTitle : @"Downloaded audio";
    self.queueLabel.text = [NSString stringWithFormat:@"Track %ld of %ld", (long)self.currentIndex + 1, (long)self.tracks.count];

    UIImage *artworkImage = [self artworkImageForTrack:track];
    self.artworkView.image = artworkImage ?: [self placeholderArtworkImage];
}

- (UIImage *)artworkImageForTrack:(NSDictionary *)track {
    NSURL *coverURL = track[@"coverURL"];
    if (!coverURL) {
        return nil;
    }

    UIImage *image = [UIImage imageWithContentsOfFile:coverURL.path];
    return image;
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

- (void)playerItemDidFinishPlaying:(NSNotification *)notification {
    if (notification.object != self.player.currentItem) {
        return;
    }

    if (self.currentIndex + 1 < self.tracks.count) {
        [self loadTrackAtIndex:self.currentIndex + 1 autoplay:YES];
        return;
    }

    [self.player pause];
    [self updatePlayPauseButton];
}

- (void)didTapPrevious {
    NSTimeInterval currentTime = MAX(CMTimeGetSeconds(self.player.currentTime), 0.0);
    if (currentTime > 3.0 || self.currentIndex == 0) {
        [self.player seekToTime:kCMTimeZero toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero];
        [self updateProgressWithCurrentTime:0.0];
        return;
    }

    [self loadTrackAtIndex:self.currentIndex - 1 autoplay:YES];
}

- (void)didTapPlayPause {
    if (self.player.rate > 0.0) {
        [self.player pause];
    } else {
        [self.player play];
    }

    [self updatePlayPauseButton];
}

- (void)didTapNext {
    if (self.currentIndex + 1 >= self.tracks.count) {
        [self.player pause];
        [self updatePlayPauseButton];
        return;
    }

    [self loadTrackAtIndex:self.currentIndex + 1 autoplay:YES];
}

- (void)sliderTouchDown:(UISlider *)slider {
    self.scrubbing = YES;
}

- (void)sliderValueChanged:(UISlider *)slider {
    [self updateTimeLabelsForCurrentTime:slider.value duration:[self currentDuration]];
}

- (void)sliderTouchUp:(UISlider *)slider {
    self.scrubbing = NO;
    CMTime targetTime = CMTimeMakeWithSeconds(slider.value, NSEC_PER_SEC);
    __weak typeof(self) weakSelf = self;
    [self.player seekToTime:targetTime toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero completionHandler:^(__unused BOOL finished) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) {
                return;
            }

            [self updateProgressWithCurrentTime:slider.value];
        });
    }];
}

- (void)updateProgressWithCurrentTime:(NSTimeInterval)currentTime {
    NSTimeInterval duration = [self currentDuration];
    self.progressSlider.maximumValue = duration > 0 ? duration : 1.0;
    self.progressSlider.value = duration > 0 ? MIN(currentTime, duration) : 0.0;
    [self updateTimeLabelsForCurrentTime:currentTime duration:duration];
    [self updateNavigationButtons];
}

- (NSTimeInterval)currentDuration {
    CMTime duration = self.player.currentItem.duration;
    if (!CMTIME_IS_NUMERIC(duration)) {
        return 0.0;
    }

    NSTimeInterval seconds = CMTimeGetSeconds(duration);
    if (!isfinite(seconds) || seconds < 0.0) {
        return 0.0;
    }

    return seconds;
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
    self.previousButton.enabled = (self.currentIndex > 0 || CMTimeGetSeconds(self.player.currentTime) > 3.0);
    self.previousButton.alpha = self.previousButton.enabled ? 1.0 : 0.45;
    self.nextButton.enabled = self.currentIndex + 1 < self.tracks.count;
    self.nextButton.alpha = self.nextButton.enabled ? 1.0 : 0.45;
}

- (void)updatePlayPauseButton {
    NSString *systemName = self.player.rate > 0.0 ? @"pause.fill" : @"play.fill";
    UIImageSymbolConfiguration *configuration = [UIImageSymbolConfiguration configurationWithPointSize:30.0 weight:UIImageSymbolWeightSemibold];
    UIImage *image = [[UIImage systemImageNamed:systemName] imageWithConfiguration:configuration];
    [self.playPauseButton setImage:image forState:UIControlStateNormal];
    [self updateNavigationButtons];
}

- (void)configureAudioSession {
    AVAudioSession *audioSession = [AVAudioSession sharedInstance];
    [audioSession setCategory:AVAudioSessionCategoryPlayback error:nil];
    [audioSession setActive:YES error:nil];
}

@end
