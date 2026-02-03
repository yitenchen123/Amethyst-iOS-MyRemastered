#import <Foundation/Foundation.h>
@class ShaderItem;
@class ShaderVersion;

@interface ShaderService : NSObject

+ (instancetype)shared;

- (void)searchShaders:(NSString *)keyword
           completion:(void (^)(NSArray<ShaderItem *> *items))completion;

- (void)fetchVersions:(NSString *)projectId
            completion:(void (^)(NSArray<ShaderVersion *> *versions))completion;

- (void)downloadShader:(ShaderVersion *)version
            completion:(void (^)(BOOL success))completion;

@end
