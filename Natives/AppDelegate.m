#import "AppDelegate.h"
#import "SceneDelegate.h"
#import "ios_uikit_bridge.h"
#import "utils.h"

// SurfaceViewController
extern dispatch_group_t fatalExitGroup;

/* 前后台 GPU 访问门，见 egl_bridge.m 中 g_pojavAppBackgrounded 的说明。 */
void pojavSetAppBackgrounded(BOOL backgrounded);

@implementation AppDelegate

#pragma mark - UISceneSession lifecycle


- (UISceneConfiguration *)application:(UIApplication *)application configurationForConnectingSceneSession:(UISceneSession *)connectingSceneSession options:(UISceneConnectionOptions *)options {
    // Called when a new scene session is being created.
    // Use this method to select a configuration to create the new scene with.
    return [[UISceneConfiguration alloc] initWithName:@"Default Configuration" sessionRole:connectingSceneSession.role];
}


- (void)application:(UIApplication *)application didDiscardSceneSessions:(NSSet<UISceneSession *> *)sceneSessions {
    // Called when the user discards a scene session.
    // If any sessions were discarded while the application was not running, this will be called shortly after application:didFinishLaunchingWithOptions.
    // Use this method to release any resources that were specific to the discarded scenes, as they will not return.
}

/* iOS 13+ 有 scene 时这两个回调不会走（由 SceneDelegate 负责），这里保留作
   兜底：LiveContainer / 未启用 scene 的宿主流程下仍要保证后台不碰 GPU。 */
- (void)applicationDidEnterBackground:(UIApplication *)application {
    pojavSetAppBackgrounded(YES);
}

- (void)applicationWillEnterForeground:(UIApplication *)application {
    pojavSetAppBackgrounded(NO);
}

- (void)applicationWillTerminate:(UIApplication *)application {
    if (fatalExitGroup != nil) {
        dispatch_group_leave(fatalExitGroup);
        fatalExitGroup = nil;
    }
}

@end
