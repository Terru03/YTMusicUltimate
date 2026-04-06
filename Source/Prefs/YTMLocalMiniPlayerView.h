#import <UIKit/UIKit.h>

@interface YTMLocalMiniPlayerView : UIView
+ (instancetype)sharedView;
- (void)attachIfNeeded;
- (void)refresh;
@end
