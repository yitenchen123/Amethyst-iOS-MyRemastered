#import <Foundation/Foundation.h>

@interface ShaderItem : NSObject

@property (nonatomic, copy) NSString *projectId;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *desc;
@property (nonatomic, copy) NSString *iconUrl;

- (instancetype)initWithDictionary:(NSDictionary *)dict;

@end
