#import <UIKit/UIKit.h>

@interface YTMDownloadsCollectionViewController : UIViewController <UITableViewDataSource, UITableViewDelegate>
- (instancetype)initWithCollection:(NSDictionary *)collection tracks:(NSArray<NSMutableDictionary *> *)tracks;
@property (nonatomic, copy) dispatch_block_t onLibraryChanged;
@end
