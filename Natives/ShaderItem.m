#import "ShaderItem.h"

@implementation ShaderItem

- (instancetype)initWithDictionary:(NSDictionary *)dict {
    if (self = [super init]) {
        _projectId = dict[@"project_id"];
        _title = dict[@"title"];
        _desc = dict[@"description"];
        _iconUrl = dict[@"icon_url"];
    }
    return self;
}

@end
