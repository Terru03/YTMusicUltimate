#import <Foundation/Foundation.h>

@interface YTMDownloadStore : NSObject
+ (NSURL *)downloadsDirectoryURL;
+ (NSArray<NSMutableDictionary *> *)allTracks;
+ (NSArray<NSMutableDictionary *> *)collectionsFromTracks:(NSArray<NSMutableDictionary *> *)tracks;
+ (NSArray<NSMutableDictionary *> *)tracksForCollectionIdentifier:(NSString *)identifier tracks:(NSArray<NSMutableDictionary *> *)tracks;
+ (NSArray<NSURL *> *)audioURLsForTracks:(NSArray<NSDictionary *> *)tracks;
+ (void)saveMetadata:(NSDictionary *)metadata forAudioFileNamed:(NSString *)audioFileName;
+ (BOOL)renameTrack:(NSMutableDictionary *)track toDisplayName:(NSString *)displayName error:(NSError **)error;
+ (BOOL)renameCollectionWithIdentifier:(NSString *)identifier title:(NSString *)title tracks:(NSArray<NSMutableDictionary *> *)tracks error:(NSError **)error;
+ (BOOL)deleteTrack:(NSDictionary *)track error:(NSError **)error;
+ (BOOL)deleteCollectionWithIdentifier:(NSString *)identifier tracks:(NSArray<NSMutableDictionary *> *)tracks error:(NSError **)error;
+ (BOOL)deleteAllDownloads:(NSError **)error;
@end
