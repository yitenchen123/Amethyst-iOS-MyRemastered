#import "SurfaceViewController.h"

#include "jni.h"
#include <assert.h>
#include <dlfcn.h>

#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/types.h>

#include "EGL/egl.h"
#include "EGL/eglext.h"
#include "GL/osmesa.h"

#include "glfw_keycodes.h"
#include "ctxbridges/bridge_tbl.h"
#include "ctxbridges/osmesa_internal.h"
#include "utils.h"

#include <unistd.h>

/* ---------------------------------------------------------------------------
 * 前后台 GPU 访问门 —— 修「切后台再切回前台卡死」。
 *
 * 病历：iOS 在 App 后台化之后禁止任何 GPU 访问，而 MC 的渲染线程并不知情，
 * 它每帧照常走 LWJGL glfwSwapBuffers -> pojavSwapBuffers -> eglSwapBuffers。
 * 后台期间这次调用会阻塞在 Metal 的 present / nextDrawable 上（命令队列已被
 * 系统挂起），且该阻塞在切回前台之后也不会自然解除 —— 渲染线程永久停在
 * swap 里，进程活着但画面冻结，即用户看到的「切后台再回来卡死」。
 *
 * 修法：进入后台后直接掐断 swap，渲染线程不再触碰 GPU，只做节流空转；
 * 回到前台立即恢复。pojavSwapBuffers 是所有走 bridge_tbl 的后端
 * （gl4es / NG-GL4ES / MobileGL / ANGLE / zink-OSMesa）的公共出口，
 * 故一处生效、全后端通吃。
 * ------------------------------------------------------------------------- */
static volatile BOOL g_pojavAppBackgrounded = NO;
static NSTimeInterval g_pojavBackgroundedAt = 0;

void pojavSetAppBackgrounded(BOOL backgrounded) {
    BOOL was = g_pojavAppBackgrounded;
    if (was == backgrounded) return;   /* 幂等：resignActive/enterBackground 会重复调用 */
    if (backgrounded) {
        g_pojavBackgroundedAt = [NSDate date].timeIntervalSince1970;
        g_pojavAppBackgrounded = YES;
        NSLog(@"[Lifecycle] backgrounded -- swap/present gated OFF (iOS forbids GPU access once backgrounded)");
    } else {
        g_pojavAppBackgrounded = NO;
        NSTimeInterval gated = [NSDate date].timeIntervalSince1970 - g_pojavBackgroundedAt;
        NSLog(@"[Lifecycle] foregrounded -- swap/present restored (gated %.2fs)", gated);
    }
}

BOOL pojavIsAppBackgrounded(void) {
    return g_pojavAppBackgrounded;
}

int clientAPI;

void JNI_LWJGL_changeRenderer(const char* value_c) {
    JNIEnv *env;
    (*runtimeJavaVMPtr)->GetEnv(runtimeJavaVMPtr, (void **)&env, JNI_VERSION_1_4);
    jstring key = (*env)->NewStringUTF(env, "org.lwjgl.opengl.libname");
    jstring value = (*env)->NewStringUTF(env, value_c);
    jclass clazz = (*env)->FindClass(env, "java/lang/System");
    jmethodID method = (*env)->GetStaticMethodID(env, clazz, "setProperty", "(Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;");
    (*env)->CallStaticObjectMethod(env, clazz, method, key, value);
}

void pojavTerminate() {
    CallbackBridge_nativeSetInputReady(NO);
    if (!br_terminate) return;
    br_terminate();
}

void* pojavGetCurrentContext() {
    return br_get_current();
}

int pojavInit(BOOL useStackQueue) {
    clientAPI = GLFW_OPENGL_API;
    isInputReady = 1;
    isUseStackQueueCall = useStackQueue;
    return JNI_TRUE;
}

int pojavInitOpenGL() {
    NSString *renderer = NSProcessInfo.processInfo.environment[@"AMETHYST_RENDERER"];
    BOOL isAuto = [renderer isEqualToString:@"auto"];
    if (isAuto || [renderer isEqualToString:@ RENDERER_NAME_GL4ES]) {
        // At this point, if renderer is still auto (unspecified major version), pick gl4es
        renderer = @ RENDERER_NAME_GL4ES;
        setenv("AMETHYST_RENDERER", renderer.UTF8String, 1);
        set_gl_bridge_tbl();
    } else if ([renderer isEqualToString:@ RENDERER_NAME_MOBILEGLUES]) {
        renderer = @ RENDERER_NAME_MOBILEGLUES;
        setenv("AMETHYST_RENDERER", renderer.UTF8String, 1);
        set_gl_bridge_tbl();
    } else if ([renderer isEqualToString:@ RENDERER_NAME_MTL_ANGLE]) {
        set_gl_bridge_tbl();
    } else if ([renderer hasPrefix:@"libOSMesa"]) {
        setenv("GALLIUM_DRIVER","zink",1);
        set_osm_bridge_tbl();
    }
    JNI_LWJGL_changeRenderer(renderer.UTF8String);
    // Preload renderer library
    dlopen([NSString stringWithFormat:@"@rpath/%@", renderer].UTF8String, RTLD_GLOBAL);

    return !br_init();
    //return 0;
}

void pojavSetWindowHint(int hint, int value) {
    if (hint == GLFW_CLIENT_API) {
        clientAPI = value;
    } else if (strcmp(getenv("AMETHYST_RENDERER"), "auto")==0 && hint == GLFW_CONTEXT_VERSION_MAJOR) {
        switch (value) {
            case 1:
            case 2:
                setenv("AMETHYST_RENDERER", RENDERER_NAME_GL4ES, 1);
                JNI_LWJGL_changeRenderer(RENDERER_NAME_GL4ES);
                break;
            // case 4: use Zink?
            default:
                setenv("AMETHYST_RENDERER", RENDERER_NAME_MOBILEGLUES, 1);
                JNI_LWJGL_changeRenderer(RENDERER_NAME_MOBILEGLUES);
                break;
        }
    }
}

void pojavSwapBuffers() {
    if (g_pojavAppBackgrounded) {
        /* 见 g_pojavAppBackgrounded 处的说明：后台绝不触碰 GPU。
           20Hz 节流空转，避免烧 CPU；回到前台后下一帧即恢复正常 swap。 */
        static int bgSkipped = 0;
        if (++bgSkipped == 1 || (bgSkipped % 100) == 0) {
            NSLog(@"[Lifecycle] swap skipped while backgrounded (%d frames)", bgSkipped);
        }
        usleep(50 * 1000);
        return;
    }
    br_swap_buffers();
}

void pojavMakeCurrent(basic_render_window_t* window) {
    br_make_current(window);
}

void* pojavCreateContext(basic_render_window_t* contextSrc) {
    if (clientAPI == GLFW_NO_API) {
        // Game has selected Vulkan API to render
        return (__bridge void *)SurfaceViewController.surface.layer;
    }

    static BOOL inited = NO;
    if (!inited) {
        inited = YES;
        pojavInitOpenGL();
    }

    return br_init_context(contextSrc);
}

void pojavSwapInterval(int interval) {
    if (!br_swap_interval) return;
    br_swap_interval(interval);
}
