//  FCLDownloadService.h
#import <Foundation/Foundation.h>
#import "BaseFile.h"

NS_ASSUME_NONNULL_BEGIN

@interface FCLDownloadService : NSObject

+ (instancetype)sharedService;

#pragma mark - Local Files
- (void)scanFilesForProfile:(NSString *)profileName 
                contentType:(DownloadContentType)contentType
                 completion:(void(^)(NSArray<BaseFile *> *files, NSError *error))completion;

- (BOOL)toggleFile:(BaseFile *)file error:(NSError **)error;
- (BOOL)deleteFile:(BaseFile *)file error:(NSError **)error;

#pragma mark - Online Search
- (void)searchOnlineForQuery:(NSString *)query 
                 contentType:(DownloadContentType)contentType
                      loader:(NSString *)loader
                       page:(NSInteger)page
                 completion:(void(^)(NSArray<BaseFile *> *results, BOOL hasMore, NSError *error))completion;

- (void)fetchVersionsForFile:(BaseFile *)file 
                  completion:(void(^)(NSArray<BaseFile *> * _Nullable versions, NSError * _Nullable error))completion;

#pragma mark - Download
- (void)downloadFile:(BaseFile *)file 
           toProfile:(NSString *)profileName
          completion:(void(^)(NSError * _Nullable error, NSString * _Nullable filePath))completion;

#pragma mark - File Management
- (NSString *)directoryForContentType:(DownloadContentType)contentType profileName:(NSString *)profileName;
- (BOOL)isFileDisabled:(NSString *)filePath;
- (BOOL)setFileDisabled:(NSString *)filePath disabled:(BOOL)disabled error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END