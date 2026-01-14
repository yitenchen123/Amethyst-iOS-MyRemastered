//  BaseFile.m
#import "BaseFile.h"
#import <UIKit/UIKit.h>

@implementation BaseFile

- (instancetype)initWithDictionary:(NSDictionary *)dictionary {
    self = [super init];
    if (self) {
        _fileId = dictionary[@"id"] ?: @"";
        _displayName = dictionary[@"displayName"] ?: @"";
        _fileName = dictionary[@"fileName"] ?: @"";
        _version = dictionary[@"version"] ?: @"";
        _gameVersion = dictionary[@"gameVersion"] ?: @"";
        _author = dictionary[@"author"] ?: @"Unknown Author";
        _fileDescription = dictionary[@"description"] ?: @"";
        
        if (dictionary[@"iconURL"]) {
            _iconURL = [NSURL URLWithString:dictionary[@"iconURL"]];
        }
        
        if (dictionary[@"downloadURL"]) {
            _downloadURL = [NSURL URLWithString:dictionary[@"downloadURL"]];
        }
        
        _fileSize = [dictionary[@"fileSize"] longLongValue] ?: 0;
        _downloadCount = [dictionary[@"downloadCount"] integerValue] ?: 0;
        _disabled = [dictionary[@"disabled"] boolValue];
        _filePath = dictionary[@"filePath"] ?: @"";
        
        // Parse date
        if (dictionary[@"datePublished"]) {
            NSISO8601DateFormatter *formatter = [[NSISO8601DateFormatter alloc] init];
            _datePublished = [formatter dateFromString:dictionary[@"datePublished"]];
        }
        
        // Parse arrays
        _categories = dictionary[@"categories"] ?: @[];
        _loaders = dictionary[@"loaders"] ?: @[];
        
        // Determine content type
        NSString *contentTypeStr = dictionary[@"contentType"] ?: @"mods";
        if ([contentTypeStr isEqualToString:@"shaderpacks"]) {
            _contentType = DownloadContentTypeShaderPacks;
        } else if ([contentTypeStr isEqualToString:@"resourcepacks"]) {
            _contentType = DownloadContentTypeResourcePacks;
        } else if ([contentTypeStr isEqualToString:@"worlds"]) {
            _contentType = DownloadContentTypeWorlds;
        } else {
            _contentType = DownloadContentTypeMods;
        }
        
        // Determine file type from extension
        NSString *extension = [[_fileName pathExtension] lowercaseString];
        if ([extension isEqualToString:@"jar"]) {
            _fileType = FileTypeJar;
        } else if ([extension isEqualToString:@"zip"]) {
            _fileType = FileTypeZip;
        } else if ([extension isEqualToString:@"mcpack"]) {
            _fileType = FileTypeMcPack;
        } else if ([extension isEqualToString:@"mcworld"]) {
            _fileType = FileTypeMcWorld;
        } else if ([extension isEqualToString:@"mcmeta"]) {
            _fileType = FileTypeMcMeta;
        } else {
            _fileType = FileTypeUnknown;
        }
    }
    return self;
}

- (NSDictionary *)toDictionary {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    
    if (_fileId) dict[@"id"] = _fileId;
    if (_displayName) dict[@"displayName"] = _displayName;
    if (_fileName) dict[@"fileName"] = _fileName;
    if (_version) dict[@"version"] = _version;
    if (_gameVersion) dict[@"gameVersion"] = _gameVersion;
    if (_author) dict[@"author"] = _author;
    if (_fileDescription) dict[@"description"] = _fileDescription;
    if (_iconURL) dict[@"iconURL"] = _iconURL.absoluteString;
    if (_downloadURL) dict[@"downloadURL"] = _downloadURL.absoluteString;
    
    dict[@"fileSize"] = @(_fileSize);
    dict[@"downloadCount"] = @(_downloadCount);
    dict[@"disabled"] = @(_disabled);
    
    if (_filePath) dict[@"filePath"] = _filePath;
    
    if (_datePublished) {
        NSISO8601DateFormatter *formatter = [[NSISO8601DateFormatter alloc] init];
        dict[@"datePublished"] = [formatter stringFromDate:_datePublished];
    }
    
    if (_categories) dict[@"categories"] = _categories;
    if (_loaders) dict[@"loaders"] = _loaders;
    
    // Content type string
    switch (_contentType) {
        case DownloadContentTypeShaderPacks:
            dict[@"contentType"] = @"shaderpacks";
            break;
        case DownloadContentTypeResourcePacks:
            dict[@"contentType"] = @"resourcepacks";
            break;
        case DownloadContentTypeWorlds:
            dict[@"contentType"] = @"worlds";
            break;
        default:
            dict[@"contentType"] = @"mods";
            break;
    }
    
    return [dict copy];
}

- (NSString *)contentTypeIconName {
    switch (_contentType) {
        case DownloadContentTypeMods:
            return @"puzzlepiece.extension.fill";
        case DownloadContentTypeShaderPacks:
            return @"sparkles";
        case DownloadContentTypeResourcePacks:
            return @"paintbrush.fill";
        case DownloadContentTypeWorlds:
            return @"map.fill";
        default:
            return @"doc.fill";
    }
}

- (NSString *)fileTypeIconName {
    switch (_fileType) {
        case FileTypeJar:
            return @"archivebox.fill";
        case FileTypeZip:
            return @"archivebox";
        case FileTypeMcPack:
            return @"square.stack.3d.up.fill";
        case FileTypeMcWorld:
            return @"globe";
        case FileTypeMcMeta:
            return @"doc.text.fill";
        default:
            return @"doc";
    }
}

- (UIColor *)contentTypeColor {
    switch (_contentType) {
        case DownloadContentTypeMods:
            return [UIColor systemBlueColor];
        case DownloadContentTypeShaderPacks:
            return [UIColor systemPurpleColor];
        case DownloadContentTypeResourcePacks:
            return [UIColor systemGreenColor];
        case DownloadContentTypeWorlds:
            return [UIColor systemOrangeColor];
        default:
            return [UIColor systemGrayColor];
    }
}

@end