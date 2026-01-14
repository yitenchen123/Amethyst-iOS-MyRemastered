//  BaseFile.h
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// 下载类型枚举
typedef NS_ENUM(NSInteger, DownloadContentType) {
    DownloadContentTypeMods,
    DownloadContentTypeShaderPacks,
    DownloadContentTypeResourcePacks,
    DownloadContentTypeWorlds
};

// 文件类型枚举
typedef NS_ENUM(NSInteger, FileType) {
    FileTypeJar,
    FileTypeZip,
    FileTypeMcPack,
    FileTypeMcWorld,
    FileTypeMcMeta,
    FileTypeUnknown
};

@interface BaseFile : NSObject

@property (nonatomic, copy) NSString *fileId;
@property (nonatomic, copy) NSString *displayName;
@property (nonatomic, copy) NSString *fileName;
@property (nonatomic, copy) NSString *version;
@property (nonatomic, copy) NSString *gameVersion;
@property (nonatomic, copy) NSString *author;
@property (nonatomic, copy) NSString *fileDescription;
@property (nonatomic, strong) NSURL *iconURL;
@property (nonatomic, strong) NSURL *downloadURL;
@property (nonatomic, assign) long long fileSize;
@property (nonatomic, strong) NSDate *datePublished;
@property (nonatomic, strong) NSArray<NSString *> *categories;
@property (nonatomic, strong) NSArray<NSString *> *loaders;
@property (nonatomic, assign) NSInteger downloadCount;
@property (nonatomic, assign) BOOL disabled;
@property (nonatomic, copy) NSString *filePath;
@property (nonatomic, strong) NSDate *fileModificationDate;
@property (nonatomic, assign) DownloadContentType contentType;
@property (nonatomic, assign) FileType fileType;

- (instancetype)initWithDictionary:(NSDictionary *)dictionary;
- (NSDictionary *)toDictionary;

// 图标获取
- (NSString *)contentTypeIconName;
- (NSString *)fileTypeIconName;
- (UIColor *)contentTypeColor;

@end

NS_ASSUME_NONNULL_END
