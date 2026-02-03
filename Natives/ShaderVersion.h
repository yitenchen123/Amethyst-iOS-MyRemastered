#import <Foundation/Foundation.h>

@interface ShaderVersion : NSObject

@property (nonatomic, copy) NSString *versionId;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *fileUrl;
@property (nonatomic, copy) NSString *fileName;

- (instancetype)initWithDictionary:(NSDictionary *)dict;

@end
