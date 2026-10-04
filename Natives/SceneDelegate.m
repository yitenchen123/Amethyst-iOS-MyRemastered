#import "SceneDelegate.h"
#import "ios_uikit_bridge.h"
#import "utils.h"

extern UIWindow *mainWindow;

/* 前后台 GPU 访问门，见 egl_bridge.m 中 g_pojavAppBackgrounded 的说明。 */
void pojavSetAppBackgrounded(BOOL backgrounded);

@interface SceneDelegate ()

@end

@implementation SceneDelegate


- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)connectionOptions {
    UIWindowScene *windowScene = (UIWindowScene *)scene;
    self.window = [[UIWindow alloc] initWithWindowScene:windowScene];
    self.window.frame = windowScene.coordinateSpace.bounds;
    mainWindow = self.window;
    launchInitialViewController(self.window);
    [self.window makeKeyAndVisible];
}


- (void)sceneDidDisconnect:(UIScene *)scene {
    // Called as the scene is being released by the system.
    // This occurs shortly after the scene enters the background, or when its session is discarded.
    // Release any resources associated with this scene that can be re-created the next time the scene connects.
    // The scene may re-connect later, as its session was not neccessarily discarded (see `application:didDiscardSceneSessions` instead).
    pojavSetAppBackgrounded(YES);
}


- (void)sceneDidBecomeActive:(UIScene *)scene {
    // Called when the scene has moved from an inactive state to an active state.
    // Use this method to restart any tasks that were paused (or not yet started) when the scene was inactive.
    // 解除后台门：恢复 swap/present。幂等，重复调用无害。
    pojavSetAppBackgrounded(NO);
}


- (void)sceneWillResignActive:(UIScene *)scene {
    // Called when the scene will move from an active state to an inactive state.
    // This may occur due to temporary interruptions (ex. an incoming phone call).
    // 下拉通知栏 / 来电 / 多任务视图同样走到这里，此时 GPU 随时可能被系统
    // 回收，一律按「不得再触碰 GPU」处理；回前台由 sceneDidBecomeActive 解除。
    pojavSetAppBackgrounded(YES);
}


- (void)sceneWillEnterForeground:(UIScene *)scene {
    // Called as the scene transitions from the background to the foreground.
    // Use this method to undo the changes made on entering the background.
    pojavSetAppBackgrounded(NO);
}


- (void)sceneDidEnterBackground:(UIScene *)scene {
    // Called as the scene transitions from the foreground to the background.
    // Use this method to save data, release shared resources, and store enough scene-specific state information
    // to restore the scene back to its current state.
    // 顺序要紧：先掐断 GPU 访问，再让 MC 暂停（发 ESC）。若先发 ESC，MC 在
    // 打开暂停菜单的过程中仍会 present，那一帧就足以把渲染线程卡死在后台。
    pojavSetAppBackgrounded(YES);
    CallbackBridge_pauseGameIfNeed();
}

@end
