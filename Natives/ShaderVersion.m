#import "ShaderVersion.h"

@implementation ShaderVersion

- (instancetype)initWithDictionary:(NSDictionary *)dict {
    if (self = [super init]) {
        _versionId = dict[@"id"];
        _name = dict[@"name"];

        NSDictionary *file = [dict[@"files"] firstObject];
        _fileUrl = file[@"url"];
        _fileName = file[@"filename"];
    }
    return self;
}

@end
