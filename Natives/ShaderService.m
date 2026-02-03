#import "ShaderService.h"
#import "ShaderItem.h"
#import "ShaderVersion.h"

@implementation ShaderService

+ (instancetype)shared {
    static ShaderService *service;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        service = [[ShaderService alloc] init];
    });
    return service;
}

#pragma mark - Search

- (void)searchShaders:(NSString *)keyword completion:(void (^)(NSArray<ShaderItem *> *))completion {
    NSString *urlStr =
    [NSString stringWithFormat:
     @"https://api.modrinth.com/v2/search?query=%@&facets=[[\"project_type:shader\"]]",
     keyword ?: @""];

    NSURL *url = [NSURL URLWithString:
                  [urlStr stringByAddingPercentEncodingWithAllowedCharacters:
                   NSCharacterSet.URLQueryAllowedCharacterSet]];

    [[[NSURLSession sharedSession] dataTaskWithURL:url
                                 completionHandler:^(NSData *data, NSURLResponse *res, NSError *err) {
        if (!data) {
            completion(@[]);
            return;
        }

        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        NSArray *hits = json[@"hits"];

        NSMutableArray *result = [NSMutableArray array];
        for (NSDictionary *dict in hits) {
            [result addObject:[[ShaderItem alloc] initWithDictionary:dict]];
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            completion(result);
        });
    }] resume];
}

#pragma mark - Versions

- (void)fetchVersions:(NSString *)projectId completion:(void (^)(NSArray<ShaderVersion *> *))completion {
    NSString *urlStr =
    [NSString stringWithFormat:@"https://api.modrinth.com/v2/project/%@/version", projectId];

    NSURL *url = [NSURL URLWithString:urlStr];

    [[[NSURLSession sharedSession] dataTaskWithURL:url
                                 completionHandler:^(NSData *data, NSURLResponse *res, NSError *err) {
        NSArray *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];

        NSMutableArray *result = [NSMutableArray array];
        for (NSDictionary *dict in json) {
            [result addObject:[[ShaderVersion alloc] initWithDictionary:dict]];
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            completion(result);
        });
    }] resume];
}

#pragma mark - Download

- (void)downloadShader:(ShaderVersion *)version completion:(void (^)(BOOL))completion {

    NSURL *url = [NSURL URLWithString:version.fileUrl];

    [[[NSURLSession sharedSession] downloadTaskWithURL:url
                                     completionHandler:^(NSURL *location, NSURLResponse *res, NSError *err) {

        if (!location) {
            completion(NO);
            return;
        }

        NSString *mcRoot = /* 你原来获取 .minecraft 的方法 */;
        NSString *shaderDir = [mcRoot stringByAppendingPathComponent:@"shaderpacks"];

        [[NSFileManager defaultManager] createDirectoryAtPath:shaderDir
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:nil];

        NSString *destPath = [shaderDir stringByAppendingPathComponent:version.fileName];
        NSURL *destURL = [NSURL fileURLWithPath:destPath];

        [[NSFileManager defaultManager] removeItemAtURL:destURL error:nil];
        [[NSFileManager defaultManager] moveItemAtURL:location toURL:destURL error:nil];

        dispatch_async(dispatch_get_main_queue(), ^{
            completion(YES);
        });

    }] resume];
}

@end
