#import "YTMDownloadStore.h"

static NSString *const kYTMUDirectoryName = @"YTMusicUltimate";
static NSString *const kYTMUSidecarExtension = @"ytmu.plist";

static NSString *YTMUSanitizeDisplayName(NSString *value) {
    NSString *sanitizedValue = [[value ?: @"" stringByReplacingOccurrencesOfString:@"/" withString:@""] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return sanitizedValue.length > 0 ? sanitizedValue : @"Unknown";
}

static NSArray<NSString *> *YTMUAudioExtensions(void) {
    return @[@"m4a", @"mp3"];
}

@implementation YTMDownloadStore

+ (NSURL *)downloadsDirectoryURL {
    NSURL *documentsURL = [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] lastObject];
    NSURL *downloadsURL = [documentsURL URLByAppendingPathComponent:kYTMUDirectoryName];
    [[NSFileManager defaultManager] createDirectoryAtURL:downloadsURL withIntermediateDirectories:YES attributes:nil error:nil];
    return downloadsURL;
}

+ (NSArray<NSMutableDictionary *> *)allTracks {
    NSURL *downloadsURL = [self downloadsDirectoryURL];
    NSArray<NSURL *> *allFiles = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:downloadsURL
                                                               includingPropertiesForKeys:@[NSURLCreationDateKey, NSURLNameKey]
                                                                                  options:NSDirectoryEnumerationSkipsHiddenFiles
                                                                                    error:nil];

    NSMutableArray<NSMutableDictionary *> *tracks = [NSMutableArray array];
    for (NSURL *fileURL in allFiles) {
        NSString *extension = fileURL.pathExtension.lowercaseString;
        if (![YTMUAudioExtensions() containsObject:extension]) {
            continue;
        }

        NSString *audioFileName = fileURL.lastPathComponent;
        NSString *baseName = audioFileName.stringByDeletingPathExtension;
        NSDictionary *metadata = [NSDictionary dictionaryWithContentsOfURL:[self metadataURLForBaseName:baseName]] ?: @{};
        NSArray<NSString *> *nameComponents = [baseName componentsSeparatedByString:@" - "];

        NSString *artist = metadata[@"artist"];
        NSString *title = metadata[@"title"];
        if ((!artist || !title) && nameComponents.count >= 2) {
            artist = artist ?: nameComponents.firstObject;
            title = title ?: [[nameComponents subarrayWithRange:NSMakeRange(1, nameComponents.count - 1)] componentsJoinedByString:@" - "];
        }

        NSString *coverFileName = metadata[@"coverFileName"];
        if (coverFileName.length == 0) {
            coverFileName = [NSString stringWithFormat:@"%@.png", baseName];
        }

        NSURL *coverURL = [[self downloadsDirectoryURL] URLByAppendingPathComponent:coverFileName];
        if (![[NSFileManager defaultManager] fileExistsAtPath:coverURL.path]) {
            coverURL = nil;
        }

        NSDate *createdAt = metadata[@"createdAt"];
        if (![createdAt isKindOfClass:[NSDate class]]) {
            createdAt = [self creationDateForFileURL:fileURL] ?: [NSDate distantPast];
        }

        NSMutableDictionary *track = [@{
            @"audioFileName": audioFileName,
            @"audioURL": fileURL,
            @"baseName": baseName,
            @"displayName": metadata[@"displayName"] ?: baseName,
            @"artist": artist ?: @"",
            @"title": title ?: baseName,
            @"createdAt": createdAt
        } mutableCopy];

        if (coverURL) {
            track[@"coverURL"] = coverURL;
            track[@"coverFileName"] = coverFileName;
        }

        [self copyMetadataKey:@"collectionIdentifier" from:metadata to:track];
        [self copyMetadataKey:@"collectionType" from:metadata to:track];
        [self copyMetadataKey:@"collectionTitle" from:metadata to:track];
        [self copyMetadataKey:@"collectionSubtitle" from:metadata to:track];
        [self copyMetadataKey:@"trackNumber" from:metadata to:track];

        [tracks addObject:track];
    }

    [tracks sortUsingComparator:^NSComparisonResult(NSDictionary *lhs, NSDictionary *rhs) {
        NSDate *leftDate = lhs[@"createdAt"] ?: [NSDate distantPast];
        NSDate *rightDate = rhs[@"createdAt"] ?: [NSDate distantPast];
        NSComparisonResult dateResult = [rightDate compare:leftDate];
        if (dateResult != NSOrderedSame) {
            return dateResult;
        }

        return [lhs[@"displayName"] compare:rhs[@"displayName"] options:NSCaseInsensitiveSearch];
    }];

    return tracks;
}

+ (NSArray<NSMutableDictionary *> *)collectionsFromTracks:(NSArray<NSMutableDictionary *> *)tracks {
    NSMutableDictionary<NSString *, NSMutableArray<NSMutableDictionary *> *> *groupedTracks = [NSMutableDictionary dictionary];
    for (NSMutableDictionary *track in tracks) {
        NSString *identifier = track[@"collectionIdentifier"];
        if (identifier.length == 0) {
            continue;
        }

        if (!groupedTracks[identifier]) {
            groupedTracks[identifier] = [NSMutableArray array];
        }
        [groupedTracks[identifier] addObject:track];
    }

    NSMutableArray<NSMutableDictionary *> *collections = [NSMutableArray array];
    for (NSString *identifier in groupedTracks) {
        NSArray<NSMutableDictionary *> *collectionTracks = [self tracksForCollectionIdentifier:identifier tracks:tracks];
        if (collectionTracks.count == 0) {
            continue;
        }

        NSDictionary *firstTrack = collectionTracks.firstObject;
        NSString *collectionType = firstTrack[@"collectionType"] ?: @"album";
        NSString *collectionTitle = firstTrack[@"collectionTitle"];
        NSString *collectionSubtitle = firstTrack[@"collectionSubtitle"];
        NSString *fallbackTitle = firstTrack[@"artist"];
        if (fallbackTitle.length == 0) {
            fallbackTitle = firstTrack[@"displayName"];
        }

        if (collectionTitle.length == 0) {
            collectionTitle = fallbackTitle.length > 0 ? fallbackTitle : @"Collection";
        }

        NSString *typeLabel = [collectionType isEqualToString:@"playlist"] ? @"Playlist" : @"Album";
        NSString *subtitlePrefix = collectionSubtitle.length > 0 ? collectionSubtitle : firstTrack[@"artist"];
        NSString *subtitle = subtitlePrefix.length > 0 ? [NSString stringWithFormat:@"%@ • %@ • %ld songs", subtitlePrefix, typeLabel, (long)collectionTracks.count] : [NSString stringWithFormat:@"%@ • %ld songs", typeLabel, (long)collectionTracks.count];

        NSMutableDictionary *collection = [@{
            @"identifier": identifier,
            @"title": collectionTitle,
            @"subtitle": subtitle,
            @"type": collectionType,
            @"trackCount": @(collectionTracks.count),
            @"createdAt": firstTrack[@"createdAt"] ?: [NSDate distantPast]
        } mutableCopy];

        if (firstTrack[@"coverURL"]) {
            collection[@"coverURL"] = firstTrack[@"coverURL"];
        }

        [collections addObject:collection];
    }

    [collections sortUsingComparator:^NSComparisonResult(NSDictionary *lhs, NSDictionary *rhs) {
        return [rhs[@"createdAt"] compare:lhs[@"createdAt"]];
    }];

    return collections;
}

+ (NSArray<NSMutableDictionary *> *)tracksForCollectionIdentifier:(NSString *)identifier tracks:(NSArray<NSMutableDictionary *> *)tracks {
    NSPredicate *predicate = [NSPredicate predicateWithBlock:^BOOL(NSDictionary *track, __unused NSDictionary *bindings) {
        return [track[@"collectionIdentifier"] isEqualToString:identifier];
    }];

    NSMutableArray<NSMutableDictionary *> *collectionTracks = [[tracks filteredArrayUsingPredicate:predicate] mutableCopy];
    [collectionTracks sortUsingComparator:^NSComparisonResult(NSDictionary *lhs, NSDictionary *rhs) {
        NSNumber *leftTrackNumber = lhs[@"trackNumber"];
        NSNumber *rightTrackNumber = rhs[@"trackNumber"];

        if ([leftTrackNumber isKindOfClass:[NSNumber class]] && [rightTrackNumber isKindOfClass:[NSNumber class]]) {
            NSComparisonResult orderResult = [leftTrackNumber compare:rightTrackNumber];
            if (orderResult != NSOrderedSame) {
                return orderResult;
            }
        }

        NSDate *leftDate = lhs[@"createdAt"] ?: [NSDate distantPast];
        NSDate *rightDate = rhs[@"createdAt"] ?: [NSDate distantPast];
        return [leftDate compare:rightDate];
    }];

    return collectionTracks;
}

+ (NSArray<NSURL *> *)audioURLsForTracks:(NSArray<NSDictionary *> *)tracks {
    NSMutableArray<NSURL *> *audioURLs = [NSMutableArray array];
    for (NSDictionary *track in tracks) {
        NSURL *audioURL = track[@"audioURL"];
        if (audioURL) {
            [audioURLs addObject:audioURL];
        }
    }
    return audioURLs;
}

+ (void)saveMetadata:(NSDictionary *)metadata forAudioFileNamed:(NSString *)audioFileName {
    if (audioFileName.length == 0) {
        return;
    }

    NSString *baseName = audioFileName.stringByDeletingPathExtension;
    NSMutableDictionary *payload = [[NSDictionary dictionaryWithContentsOfURL:[self metadataURLForBaseName:baseName]] mutableCopy] ?: [NSMutableDictionary dictionary];
    [payload addEntriesFromDictionary:metadata ?: @{}];
    payload[@"audioFileName"] = audioFileName;
    payload[@"displayName"] = payload[@"displayName"] ?: baseName;
    payload[@"createdAt"] = payload[@"createdAt"] ?: [NSDate date];

    if ([payload writeToURL:[self metadataURLForBaseName:baseName] atomically:YES]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:@"ReloadDataNotification" object:nil];
        });
    }
}

+ (BOOL)renameTrack:(NSMutableDictionary *)track toDisplayName:(NSString *)displayName error:(NSError **)error {
    NSString *newBaseName = YTMUSanitizeDisplayName(displayName);
    NSURL *downloadsURL = [self downloadsDirectoryURL];
    NSURL *oldAudioURL = track[@"audioURL"];
    if (!oldAudioURL) {
        return NO;
    }

    NSString *extension = oldAudioURL.pathExtension;
    NSURL *newAudioURL = [downloadsURL URLByAppendingPathComponent:[NSString stringWithFormat:@"%@.%@", newBaseName, extension]];
    if ([newAudioURL.path isEqualToString:oldAudioURL.path]) {
        return YES;
    }

    if ([[NSFileManager defaultManager] fileExistsAtPath:newAudioURL.path]) {
        if (error) {
            *error = [NSError errorWithDomain:@"YTMusicUltimate" code:409 userInfo:@{NSLocalizedDescriptionKey: @"A download with that name already exists."}];
        }
        return NO;
    }

    NSDictionary *metadata = [NSDictionary dictionaryWithContentsOfURL:[self metadataURLForBaseName:track[@"baseName"]]] ?: @{};
    NSError *moveError = nil;
    [[NSFileManager defaultManager] moveItemAtURL:oldAudioURL toURL:newAudioURL error:&moveError];
    if (moveError) {
        if (error) {
            *error = moveError;
        }
        return NO;
    }

    NSURL *oldCoverURL = track[@"coverURL"];
    NSString *newCoverFileName = nil;
    if (oldCoverURL) {
        newCoverFileName = [NSString stringWithFormat:@"%@.%@", newBaseName, oldCoverURL.pathExtension];
        NSURL *newCoverURL = [downloadsURL URLByAppendingPathComponent:newCoverFileName];
        [[NSFileManager defaultManager] removeItemAtURL:newCoverURL error:nil];
        [[NSFileManager defaultManager] moveItemAtURL:oldCoverURL toURL:newCoverURL error:nil];
    }

    [[NSFileManager defaultManager] removeItemAtURL:[self metadataURLForBaseName:track[@"baseName"]] error:nil];
    NSMutableDictionary *updatedMetadata = [metadata mutableCopy] ?: [NSMutableDictionary dictionary];
    updatedMetadata[@"displayName"] = newBaseName;
    updatedMetadata[@"audioFileName"] = newAudioURL.lastPathComponent;
    if (newCoverFileName.length > 0) {
        updatedMetadata[@"coverFileName"] = newCoverFileName;
    }
    [updatedMetadata writeToURL:[self metadataURLForBaseName:newBaseName] atomically:YES];

    return YES;
}

+ (BOOL)renameCollectionWithIdentifier:(NSString *)identifier title:(NSString *)title tracks:(NSArray<NSMutableDictionary *> *)tracks error:(NSError **)error {
    NSString *newTitle = YTMUSanitizeDisplayName(title);
    NSArray<NSMutableDictionary *> *collectionTracks = [self tracksForCollectionIdentifier:identifier tracks:tracks];
    for (NSDictionary *track in collectionTracks) {
        NSString *baseName = track[@"baseName"];
        NSURL *metadataURL = [self metadataURLForBaseName:baseName];
        NSMutableDictionary *metadata = [[NSDictionary dictionaryWithContentsOfURL:metadataURL] mutableCopy] ?: [NSMutableDictionary dictionary];
        metadata[@"collectionTitle"] = newTitle;
        if (![metadata writeToURL:metadataURL atomically:YES]) {
            if (error) {
                *error = [NSError errorWithDomain:@"YTMusicUltimate" code:500 userInfo:@{NSLocalizedDescriptionKey: @"Couldn't update the collection title."}];
            }
            return NO;
        }
    }

    return YES;
}

+ (BOOL)deleteTrack:(NSDictionary *)track error:(NSError **)error {
    NSURL *audioURL = track[@"audioURL"];
    if (!audioURL) {
        return NO;
    }

    NSError *removeError = nil;
    [[NSFileManager defaultManager] removeItemAtURL:audioURL error:&removeError];
    [[NSFileManager defaultManager] removeItemAtURL:[self metadataURLForBaseName:track[@"baseName"]] error:nil];
    if (track[@"coverURL"]) {
        [[NSFileManager defaultManager] removeItemAtURL:track[@"coverURL"] error:nil];
    }

    if (removeError && error) {
        *error = removeError;
    }

    return removeError == nil;
}

+ (BOOL)deleteCollectionWithIdentifier:(NSString *)identifier tracks:(NSArray<NSMutableDictionary *> *)tracks error:(NSError **)error {
    NSArray<NSMutableDictionary *> *collectionTracks = [self tracksForCollectionIdentifier:identifier tracks:tracks];
    for (NSDictionary *track in collectionTracks) {
        NSError *deleteError = nil;
        if (![self deleteTrack:track error:&deleteError]) {
            if (error) {
                *error = deleteError;
            }
            return NO;
        }
    }

    return YES;
}

+ (BOOL)deleteAllDownloads:(NSError **)error {
    NSURL *downloadsURL = [self downloadsDirectoryURL];
    if (![[NSFileManager defaultManager] fileExistsAtPath:downloadsURL.path]) {
        return YES;
    }

    BOOL removed = [[NSFileManager defaultManager] removeItemAtURL:downloadsURL error:error];
    if (removed) {
        [[NSFileManager defaultManager] createDirectoryAtURL:downloadsURL withIntermediateDirectories:YES attributes:nil error:nil];
    }

    return removed;
}

+ (NSURL *)metadataURLForBaseName:(NSString *)baseName {
    return [[self downloadsDirectoryURL] URLByAppendingPathComponent:[NSString stringWithFormat:@"%@.%@", baseName, kYTMUSidecarExtension]];
}

+ (NSDate *)creationDateForFileURL:(NSURL *)fileURL {
    NSDate *creationDate = nil;
    [fileURL getResourceValue:&creationDate forKey:NSURLCreationDateKey error:nil];
    return creationDate;
}

+ (void)copyMetadataKey:(NSString *)key from:(NSDictionary *)source to:(NSMutableDictionary *)destination {
    id value = source[key];
    if (value) {
        destination[key] = value;
    }
}

@end
