//  FCLDownloadService.m
#import "FCLDownloadService.h"
#import <UIKit/UIKit.h>

@implementation FCLDownloadService

+ (instancetype)sharedService {
    static FCLDownloadService *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

#pragma mark - Local Files

- (void)scanFilesForProfile:(NSString *)profileName 
                contentType:(DownloadContentType)contentType
                 completion:(void(^)(NSArray<BaseFile *> *files, NSError *error))completion {
    dispatch_async(dispatch_get_global_queue(DOS_CLASS_USER_INITIATED, 0), ^{
        NSMutableArray<BaseFile *> *files = [NSMutableArray array];
        NSError *error = nil;
        
        NSString *directoryPath = [self directoryForContentType:contentType profileName:profileName];
        NSFileManager *fileManager = [NSFileManager defaultManager];
        
        if (![fileManager fileExistsAtPath:directoryPath]) {
            // Create directory if it doesn't exist
            [fileManager createDirectoryAtPath:directoryPath 
                   withIntermediateDirectories:YES 
                                    attributes:nil 
                                         error:&error];
            if (error) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(@[], error);
                });
                return;
            }
        }
        
        NSArray *directoryContents = [fileManager contentsOfDirectoryAtPath:directoryPath error:&error];
        if (error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(@[], error);
            });
            return;
        }
        
        for (NSString *fileName in directoryContents) {
            NSString *filePath = [directoryPath stringByAppendingPathComponent:fileName];
            
            // Skip directories
            BOOL isDirectory;
            [fileManager fileExistsAtPath:filePath isDirectory:&isDirectory];
            if (isDirectory) continue;
            
            // Skip disabled files (files with .disabled extension)
            if ([fileName hasSuffix:@".disabled"]) continue;
            
            // Create BaseFile object
            BaseFile *file = [[BaseFile alloc] init];
            file.fileName = fileName;
            file.displayName = [fileName stringByDeletingPathExtension];
            file.filePath = filePath;
            file.contentType = contentType;
            
            // Get file attributes
            NSDictionary *attributes = [fileManager attributesOfItemAtPath:filePath error:nil];
            if (attributes) {
                file.fileModificationDate = attributes[NSFileModificationDate];
                file.fileSize = [attributes[NSFileSize] longLongValue];
            }
            
            // Check if disabled version exists
            NSString *disabledPath = [filePath stringByAppendingString:@".disabled"];
            file.disabled = [fileManager fileExistsAtPath:disabledPath];
            
            [files addObject:file];
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            completion([files copy], nil);
        });
    });
}

- (BOOL)toggleFile:(BaseFile *)file error:(NSError **)error {
    if (!file.filePath) {
        if (error) *error = [NSError errorWithDomain:@"FCLDownloadService" 
                                                code:-1 
                                            userInfo:@{NSLocalizedDescriptionKey: @"文件路径为空"}];
        return NO;
    }
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *originalPath = file.filePath;
    NSString *disabledPath = [originalPath stringByAppendingString:@".disabled"];
    
    if (file.disabled) {
        // Enable file - move from .disabled to regular
        if ([fileManager fileExistsAtPath:disabledPath]) {
            return [fileManager moveItemAtPath:disabledPath toPath:originalPath error:error];
        }
    } else {
        // Disable file - move from regular to .disabled
        if ([fileManager fileExistsAtPath:originalPath]) {
            return [fileManager moveItemAtPath:originalPath toPath:disabledPath error:error];
        }
    }
    
    return NO;
}

- (BOOL)deleteFile:(BaseFile *)file error:(NSError **)error {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *pathToDelete = file.filePath;
    
    if (file.disabled) {
        pathToDelete = [pathToDelete stringByAppendingString:@".disabled"];
    }
    
    if (![fileManager fileExistsAtPath:pathToDelete]) {
        if (error) *error = [NSError errorWithDomain:@"FCLDownloadService" 
                                                code:-2 
                                            userInfo:@{NSLocalizedDescriptionKey: @"文件不存在"}];
        return NO;
    }
    
    return [fileManager removeItemAtPath:pathToDelete error:error];
}

#pragma mark - Online Search

- (void)searchOnlineForQuery:(NSString *)query 
                 contentType:(DownloadContentType)contentType
                      loader:(NSString *)loader
                       page:(NSInteger)page
                 completion:(void(^)(NSArray<BaseFile *> *results, BOOL hasMore, NSError *error))completion {
    dispatch_async(dispatch_get_global_queue(DOS_CLASS_USER_INITIATED, 0), ^{
        // Simulate API call - in real implementation, this would call Modrinth/CurseForge API
        // For demonstration, return dummy data
        
        NSMutableArray<BaseFile *> *results = [NSMutableArray array];
        
        if (query.length == 0) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(@[], NO, nil);
            });
            return;
        }
        
        // Generate dummy data based on content type
        for (NSInteger i = 0; i < 10; i++) {
            BaseFile *file = [[BaseFile alloc] init];
            file.fileId = [NSString stringWithFormat:@"%ld", (long)(page * 10 + i)];
            file.displayName = [NSString stringWithFormat:@"%@ %ld", query, (long)(page * 10 + i)];
            file.fileName = [NSString stringWithFormat:@"%@-%ld.zip", [query lowercaseString], (long)(page * 10 + i)];
            file.version = @"1.0.0";
            file.gameVersion = @"1.20.1";
            file.author = @"示例作者";
            file.fileDescription = @"这是一个示例文件描述，用于演示目的。";
            file.downloadURL = [NSURL URLWithString:@"https://example.com/download.zip"];
            file.iconURL = [NSURL URLWithString:@"https://via.placeholder.com/64"];
            file.fileSize = 1024 * 1024 * (i + 1); // 1MB to 10MB
            file.downloadCount = 1000 * (i + 1);
            file.categories = @[@"示例类别"];
            file.loaders = loader.length > 0 ? @[loader] : @[@"fabric", @"forge"];
            file.contentType = contentType;
            file.datePublished = [NSDate dateWithTimeIntervalSinceNow:-86400 * i]; // i days ago
            
            [results addObject:file];
        }
        
        // Simulate network delay
        [NSThread sleepForTimeInterval:0.5];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            completion([results copy], page < 2, nil); // Allow 3 pages of results
        });
    });
}

- (void)fetchVersionsForFile:(BaseFile *)file 
                  completion:(void(^)(NSArray<BaseFile *> * _Nullable versions, NSError * _Nullable error))completion {
    dispatch_async(dispatch_get_global_queue(DOS_CLASS_USER_INITIATED, 0), ^{
        // Generate dummy versions
        NSMutableArray<BaseFile *> *versions = [NSMutableArray array];
        
        NSArray *versionNumbers = @[@"2.0.0", @"1.9.0", @"1.8.5", @"1.7.2", @"1.6.0"];
        NSArray *gameVersions = @[@"1.20.1", @"1.20", @"1.19.4", @"1.19.2", @"1.18.2"];
        
        for (NSInteger i = 0; i < versionNumbers.count; i++) {
            BaseFile *version = [[BaseFile alloc] init];
            version.fileId = [NSString stringWithFormat:@"version-%ld", (long)i];
            version.displayName = [NSString stringWithFormat:@"%@ %@", file.displayName, versionNumbers[i]];
            version.fileName = [NSString stringWithFormat:@"%@-%@.jar", [file.displayName lowercaseString], versionNumbers[i]];
            version.version = versionNumbers[i];
            version.gameVersion = gameVersions[i % gameVersions.count];
            version.author = file.author;
            version.fileDescription = [NSString stringWithFormat:@"版本 %@，适用于 Minecraft %@", versionNumbers[i], version.gameVersion];
            version.downloadURL = [NSURL URLWithString:[NSString stringWithFormat:@"https://example.com/%@", version.fileName]];
            version.iconURL = file.iconURL;
            version.fileSize = 1024 * 1024 * (i + 1);
            version.downloadCount = 1000 * (versionNumbers.count - i);
            version.categories = file.categories;
            version.loaders = @[@"fabric", @"forge"];
            version.contentType = file.contentType;
            version.datePublished = [NSDate dateWithTimeIntervalSinceNow:-86400 * i * 7]; // i weeks ago
            
            [versions addObject:version];
        }
        
        // Simulate network delay
        [NSThread sleepForTimeInterval:0.3];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            completion([versions copy], nil);
        });
    });
}

#pragma mark - Download

- (void)downloadFile:(BaseFile *)file 
           toProfile:(NSString *)profileName
          completion:(void(^)(NSError * _Nullable error, NSString * _Nullable filePath))completion {
    dispatch_async(dispatch_get_global_queue(DOS_CLASS_USER_INITIATED, 0), ^{
        // Simulate download
        [NSThread sleepForTimeInterval:2.0];
        
        // Get destination directory
        NSString *directoryPath = [self directoryForContentType:file.contentType profileName:profileName];
        NSString *destinationPath = [directoryPath stringByAppendingPathComponent:file.fileName];
        
        // Simulate download success/failure
        BOOL success = arc4random_uniform(10) > 1; // 90% success rate
        
        dispatch_async(dispatch_get_main_queue(), ^{
            if (success) {
                // In real implementation, you would save the downloaded file
                // For now, just return the destination path
                completion(nil, destinationPath);
            } else {
                NSError *error = [NSError errorWithDomain:@"FCLDownloadService" 
                                                     code:-3 
                                                 userInfo:@{NSLocalizedDescriptionKey: @"下载失败，请检查网络连接"}];
                completion(error, nil);
            }
        });
    });
}

#pragma mark - File Management

- (NSString *)directoryForContentType:(DownloadContentType)contentType profileName:(NSString *)profileName {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths firstObject];
    
    // Create profile directory
    NSString *profileDir = [documentsDirectory stringByAppendingPathComponent:profileName ?: @"default"];
    
    // Create subdirectory based on content type
    NSString *subdirectory;
    switch (contentType) {
        case DownloadContentTypeMods:
            subdirectory = @"mods";
            break;
        case DownloadContentTypeShaderPacks:
            subdirectory = @"shaderpacks";
            break;
        case DownloadContentTypeResourcePacks:
            subdirectory = @"resourcepacks";
            break;
        case DownloadContentTypeWorlds:
            subdirectory = @"saves";
            break;
        default:
            subdirectory = @"files";
            break;
    }
    
    return [profileDir stringByAppendingPathComponent:subdirectory];
}

- (BOOL)isFileDisabled:(NSString *)filePath {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *disabledPath = [filePath stringByAppendingString:@".disabled"];
    return [fileManager fileExistsAtPath:disabledPath];
}

- (BOOL)setFileDisabled:(NSString *)filePath disabled:(BOOL)disabled error:(NSError **)error {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *disabledPath = [filePath stringByAppendingString:@".disabled"];
    
    if (disabled) {
        // Disable - move to .disabled
        if ([fileManager fileExistsAtPath:filePath]) {
            return [fileManager moveItemAtPath:filePath toPath:disabledPath error:error];
        }
    } else {
        // Enable - move from .disabled
        if ([fileManager fileExistsAtPath:disabledPath]) {
            return [fileManager moveItemAtPath:disabledPath toPath:filePath error:error];
        }
    }
    
    return NO;
}

@end