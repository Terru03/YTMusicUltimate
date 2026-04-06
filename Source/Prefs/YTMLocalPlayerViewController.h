#import <UIKit/UIKit.h>

@interface YTMLocalPlayerViewController : UIViewController
- (instancetype)initWithTracks:(NSArray<NSDictionary *> *)tracks startIndex:(NSInteger)startIndex;
@end
