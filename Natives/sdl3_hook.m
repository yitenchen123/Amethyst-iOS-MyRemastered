// sdl3_hook.m — SDL3 兼容层，移植自 ZalithLauncher2 的
// ZalithLauncher/src/main/jni/sdl_hook.c（Android 端，基于 bytehook）。
//
// iOS 上没有 bytehook，等价机制是 main_hook.m 里 fishhook 住的 dlsym
// （hooked_dlsym）。LWJGL 通过 dlsym 取 SDL 函数指针后直接调用，不走
// __la_symbol_ptr，所以必须在 dlsym 层拦 —— 这和 SDL_SetWindowMouseGrab
// 用的是同一条路子。SDL 内部调用自己的函数不经过 dlsym，因此不会被误伤。
//
// 解决的问题（均与 MC 26.x 的 RenderPearl 相关）：
//
// 1. 移动渲染器都是 OpenGL ES 实现，而 MC 按桌面 GL 惯例初始化 SDL，
//    非 ES 的 profile 请求会被宿主拒绝。建窗前强制切到 ES profile。
//
// 2. MC 26.3 ss9+ 在设备初始化时先建一个隐藏工具窗口（GL 上下文依附其上），
//    随后主窗口创建被拒；销毁工具窗口又会使其上的 GL surface 失效。
//    故把后续建窗请求重定向到首个窗口。
//
// 3. MC 26.3 要求 SDL 与 LWJGL 使用同一 Vulkan 加载器实例（校验
//    vkGetInstanceProcAddr 指针一致），而 SDL 只能按路径加载。若启动器已
//    持有句柄（记录在环境变量里），SDL 加载 libvulkan 时把该句柄还回去。
//
// 4. EGL 代理：eglChooseConfig / eglCreateContext 首选请求失败后做兼容
//    重试（RENDERABLE_TYPE 归一化、剔除 KHR 版本属性、CV=2 兜底）。
//
// 全部行为可用环境变量关闭，默认只在对移动 ES 渲染器时生效：
//   AMETHYST_SDL_GLES_COMPAT=0    关闭 ES profile 强制与 EGL 代理
//   AMETHYST_SDL_REUSE_WINDOW=0   关闭主窗口复用
//   AMETHYST_VULKAN_PTR=<hex>     启用 SDL_LoadObject 句柄共享

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "utils.h"

#include <dlfcn.h>
#include <stdbool.h>
#include <stdint.h>
#include <math.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>   // strcasecmp
#include <sys/types.h>

#pragma mark - SDL3 常量（与 SDL_video.h 对齐，避免依赖 SDL 头文件）

// SDL_GLAttr：从 0 开始顺序计数，CONTEXT_PROFILE_MASK 是第 21 个
#define AME_SDL_GL_CONTEXT_PROFILE_MASK 20
// SDL_GLProfile
#define AME_SDL_GL_CONTEXT_PROFILE_ES 0x0004

#pragma mark - EGL 常量（自给自足，不依赖 EGL 头文件是否存在）

#define AME_EGL_NONE 0x3038
#define AME_EGL_RENDERABLE_TYPE 0x3040
#define AME_EGL_OPENGL_ES_BIT 0x0001
#define AME_EGL_OPENGL_ES2_BIT 0x0004
#define AME_EGL_OPENGL_ES3_BIT 0x0040
#define AME_EGL_OPENGL_BIT 0x0008
// 注意：EGL_CONTEXT_MAJOR_VERSION 与 EGL_CONTEXT_CLIENT_VERSION 同为 0x3098，
// 这是 EGL 的历史遗留（ZL2 代码里也是这个值）。
#define AME_EGL_CONTEXT_CLIENT_VERSION 0x3098
#define AME_EGL_CONTEXT_MAJOR_VERSION_KHR 0x3098
#define AME_EGL_CONTEXT_MINOR_VERSION_KHR 0x30FB

#pragma mark - 真实 SDL 函数指针

// SDL3 里 bool 就是 C99 _Bool（1 字节），这里用 int 做 ABI 安全的返回类型，
// 只取其"非零即成功"的语义，避免与 Objective-C 的 BOOL 混淆。
typedef bool (*ame_fn_SDL_GL_SetAttribute)(int attr, int value);
typedef void *(*ame_fn_SDL_CreateWindow)(const char *title, int w, int h, uint32_t flags);
typedef void *(*ame_fn_SDL_CreateWindowWithProperties)(uint32_t props);
typedef void (*ame_fn_SDL_DestroyWindow)(void *window);
typedef bool (*ame_fn_SDL_SetWindowSize)(void *window, int w, int h);
typedef long long (*ame_fn_SDL_GetNumberProperty)(uint32_t props, const char *name,
                                                  long long default_value);
typedef void *(*ame_fn_SDL_LoadFunction)(void *handle, const char *name);
typedef void *(*ame_fn_SDL_EGL_GetProcAddress)(const char *proc);
typedef void *(*ame_fn_SDL_LoadObject)(const char *path);
typedef void (*ame_fn_SDL_UnloadObject)(void *handle);

// SDL3 GL 入口（被接管后转交启动器 EGL bridge）
typedef bool (*ame_fn_SDL_GL_LoadLibrary)(const char *path);
typedef void *(*ame_fn_SDL_GL_CreateContext)(void *window);
typedef bool (*ame_fn_SDL_GL_MakeCurrent)(void *window, void *context);
typedef bool (*ame_fn_SDL_GL_SwapWindow)(void *window);
typedef void *(*ame_fn_SDL_GL_GetProcAddress)(const char *proc);
typedef bool (*ame_fn_SDL_GL_SetSwapInterval)(int interval);
typedef bool (*ame_fn_SDL_GL_DestroyContext)(void *context);
typedef void *(*ame_fn_SDL_GL_GetCurrentContext)(void);

// 尺寸查询（见 ame_SDL_GetWindowSizeInPixels 处的说明）
typedef bool (*ame_fn_SDL_GetWindowSizeInPixels)(void *window, int *w, int *h);
typedef bool (*ame_fn_SDL_GL_GetDrawableSize)(void *window, int *w, int *h);

// 事件窗口解析回落（见 ame_SDL_GetWindowFromEvent 处的说明）
typedef void *(*ame_fn_SDL_GetWindowFromEvent)(const void *event);
typedef void *(*ame_fn_SDL_GetWindowFromID)(uint32_t id);

// 文本输入：必须在主线程调用（见 ame_SDL_StartTextInputWithProperties 处的说明）
typedef bool (*ame_fn_SDL_StartTextInput)(void *window);
typedef bool (*ame_fn_SDL_StartTextInputWithProperties)(void *window,
                                                        unsigned long long props);
typedef bool (*ame_fn_SDL_StopTextInput)(void *window);
typedef bool (*ame_fn_SDL_SetTextInputArea)(void *window, const void *rect, int cursor);

// 子系统初始化：SDL hint 必须在 SDL_Init 之前设置才生效（见 ame_SDL_InitSubSystem）
typedef bool (*ame_fn_SDL_InitSubSystem)(uint32_t flags);
typedef bool (*ame_fn_SDL_SetHint)(const char *name, const char *value);

// 前向声明：ame_SDL_InitSubSystem 需要它，而其定义在文件后面的"渲染器分类"区
static bool ame_glBridgeEnabled(void);

static ame_fn_SDL_GL_SetAttribute ame_real_GL_SetAttribute = NULL;
static ame_fn_SDL_CreateWindow ame_real_CreateWindow = NULL;
static ame_fn_SDL_CreateWindowWithProperties ame_real_CreateWindowWithProperties = NULL;
static ame_fn_SDL_DestroyWindow ame_real_DestroyWindow = NULL;
static ame_fn_SDL_SetWindowSize ame_real_SetWindowSize = NULL;
static ame_fn_SDL_GetNumberProperty ame_real_GetNumberProperty = NULL;
static ame_fn_SDL_LoadFunction ame_real_LoadFunction = NULL;
static ame_fn_SDL_EGL_GetProcAddress ame_real_EGL_GetProcAddress = NULL;
static ame_fn_SDL_LoadObject ame_real_LoadObject = NULL;
static ame_fn_SDL_UnloadObject ame_real_UnloadObject = NULL;

static ame_fn_SDL_GL_LoadLibrary ame_real_GL_LoadLibrary = NULL;
static ame_fn_SDL_GL_CreateContext ame_real_GL_CreateContext = NULL;
static ame_fn_SDL_GL_MakeCurrent ame_real_GL_MakeCurrent = NULL;
static ame_fn_SDL_GL_SwapWindow ame_real_GL_SwapWindow = NULL;
static ame_fn_SDL_GL_GetProcAddress ame_real_GL_GetProcAddress = NULL;
static ame_fn_SDL_GL_SetSwapInterval ame_real_GL_SetSwapInterval = NULL;
static ame_fn_SDL_GL_DestroyContext ame_real_GL_DestroyContext = NULL;
static ame_fn_SDL_GL_GetCurrentContext ame_real_GL_GetCurrentContext = NULL;
static ame_fn_SDL_GetWindowSizeInPixels ame_real_GetWindowSizeInPixels = NULL;
static ame_fn_SDL_GL_GetDrawableSize ame_real_GL_GetDrawableSize = NULL;

static ame_fn_SDL_GetWindowFromEvent ame_real_GetWindowFromEvent = NULL;
static ame_fn_SDL_GetWindowFromID ame_real_GetWindowFromID = NULL;
static ame_fn_SDL_StartTextInput ame_real_StartTextInput = NULL;
static ame_fn_SDL_StartTextInputWithProperties ame_real_StartTextInputWithProperties = NULL;
static ame_fn_SDL_StopTextInput ame_real_StopTextInput = NULL;
static ame_fn_SDL_SetTextInputArea ame_real_SetTextInputArea = NULL;
static ame_fn_SDL_InitSubSystem ame_real_InitSubSystem = NULL;
static ame_fn_SDL_SetHint ame_real_SetHint = NULL;

// SDL3 的 SDL_Rect：{ float x, float y, float w, float h; }
typedef struct { float x, y, w, h; } ame_SDLRect;

#pragma mark - EGL 真实函数（首次解析后固定，避免跨 loader 调用）

typedef int (*ame_fn_eglChooseConfig)(void *dpy, const int *attrib_list, void **configs,
                                      int config_size, int *num_config);
typedef void *(*ame_fn_eglCreateContext)(void *dpy, void *config, void *share,
                                         const int *attrib_list);
typedef int (*ame_fn_eglSwapBuffers)(void *dpy, void *surface);

static ame_fn_eglChooseConfig ame_orig_eglChooseConfig = NULL;
static ame_fn_eglCreateContext ame_orig_eglCreateContext = NULL;
static ame_fn_eglSwapBuffers ame_orig_eglSwapBuffers = NULL;

#pragma mark - 外部依赖

// main_hook.m 提供的"绕过 hook"的 dlsym，避免本文件内解析 SDL 符号时
// 又绕回 hooked_dlsym 造成递归。
extern void *amethyst_orig_dlsym(void *handle, const char *name);

static void *ame_real_dlsym(const char *name) {
    if (amethyst_orig_dlsym) {
        void *p = amethyst_orig_dlsym(RTLD_DEFAULT, name);
        if (p != NULL) return p;
    }
    return dlsym(RTLD_DEFAULT, name);
}

#pragma mark - 渲染器分类

static bool ame_envFlagOn(const char *name, bool defaultValue) {
    const char *v = getenv(name);
    if (v == NULL || v[0] == '\0') return defaultValue;
    return !(strcmp(v, "0") == 0 || strcasecmp(v, "false") == 0 ||
             strcasecmp(v, "no") == 0 || strcasecmp(v, "off") == 0);
}

// 启动器把 EGL 库路径放在 POJAVEXEC_EGL（Android 传统），iOS 侧沿用
// AMETHYST_RENDERER。两个都查，保持与 ZL2 语义一致。
static bool ame_isMobileGluesEgl(void) {
    const char *egl = getenv("POJAVEXEC_EGL");
    if (egl == NULL) return false;
    const char *base = strrchr(egl, '/');
    base = (base != NULL) ? base + 1 : egl;
    return strstr(base, "mobileglues") != NULL;
}

// GLES 兼容层（强制 ES profile、EGL 重试）只对移动 ES 渲染器生效，
// 桌面 / OSMesa 路径不得被 ES 化 —— 否则 zink 会被错误处理。
static bool ame_sdlGlesCompatEnabled(void) {
    if (!ame_envFlagOn("AMETHYST_SDL_GLES_COMPAT", true)) return false;

    const char *renderer = getenv("AMETHYST_RENDERER");
    if (renderer == NULL || renderer[0] == '\0') return ame_isMobileGluesEgl();

    if (strstr(renderer, "desktopgl") != NULL) return false;
    if (strncmp(renderer, "gallium_", 8) == 0) return false;      // OSMesa 系
    if (strncmp(renderer, "libOSMesa", 9) == 0) return false;     // zink（含版本号）
    if (strcmp(renderer, "vulkan_zink") == 0) return false;       // zink
    if (strstr(renderer, "libMoltenVK") != NULL) return false;    // 原生 Vulkan
    if (strncmp(renderer, "opengles", 8) == 0) return true;       // 内置 GL4ES
    if (strstr(renderer, "libMobileGL") != NULL) {
        // MobileGL 双后端必须按实现区分，不能按文件名前缀一刀切：
        //   libMobileGL-gles.dylib → DirectGLES，本身就是 ES 实现 → 强制 ES
        //   libMobileGL.dylib      → DirectVulkan，对外声明 GL 4.6 再转 Vulkan，
        //                            与 vulkan_zink 同类。ZL2 对 vulkan_zink
        //                            明确返回 false，此处对齐 —— 给 GL→Vulkan
        //                            转译器套 ES 上下文与 ZL2 的做法相反。
        return strstr(renderer, "-gles") != NULL;
    }
    if (strstr(renderer, "libmithril") != NULL) return true;      // Mithril
    return ame_isMobileGluesEgl();                                // MobileGlues
}

#pragma mark - 1) 强制 ES profile

static bool ame_forcedEsProfile = false;

// SDL3 路径下"最终想要的"上下文语义，供 EGL bridge 决策（见文件末尾的
// amethyst_sdl3_wants_gles_context()）。
//
// 为什么需要它：ZL2 的 forceEglProfileEs() 只调 SDL_GL_SetAttribute(ES)，
// 随后由 SDL 自己的 EGL 后端按该属性建上下文，因此"强制"天然生效。
// 而 iOS 侧 SDL_GL_CreateContext 被本模块接管并转交 EGL bridge（见 5)），
// SDL 内部的属性状态对最终上下文不再有任何影响 —— 这正是此前
// "forced ... = ES" 打了日志、桥却照旧打印 "Binding to desktop OpenGL" 的原因。
// 故在此记下强制结果，让 gl_bridge.m 能按它选择 ES / desktop。
static bool ame_sdl3WantsGles = false;

static void ame_forceEglProfileEs(void) {
    if (!ame_sdlGlesCompatEnabled()) return;
    if (ame_real_GL_SetAttribute == NULL) {
        ame_real_GL_SetAttribute = (ame_fn_SDL_GL_SetAttribute)ame_real_dlsym("SDL_GL_SetAttribute");
    }
    if (ame_real_GL_SetAttribute != NULL) {
        ame_real_GL_SetAttribute(AME_SDL_GL_CONTEXT_PROFILE_MASK, AME_SDL_GL_CONTEXT_PROFILE_ES);
        ame_forcedEsProfile = true;
        ame_sdl3WantsGles = true;
        NSDebugLog(@"[SDLHook] forced SDL_GL_CONTEXT_PROFILE_MASK = ES");
    } else {
        NSDebugLog(@"[SDLHook] SDL_GL_SetAttribute unresolved, cannot force ES profile");
    }
}

#pragma mark - 2) 主窗口复用

static void *ame_primaryWindow = NULL;
static unsigned int ame_primaryWindowRefs = 0;
static int ame_primaryWindowW = 0;
static int ame_primaryWindowH = 0;

static bool ame_shouldReusePrimaryWindow(void) {
    // 判定必须与 ame_sdlGlesCompatEnabled() 解耦 —— 这是从 ZL2 对齐来的关键差异，
    // ZL2 的 shouldReusePrimaryWindow() 只看环境变量，不看 sdlGlesCompatEnabled()。
    //
    // 若沿用耦合写法，一旦把 DirectVulkan（libMobileGL.dylib）移出 ES 强制，
    // 复用会连带被关闭；而 iOS 的 UIKit_CreateWindow 硬性限制每 display 只允许
    // 一个窗口（"Only one window allowed per display."），主窗口创建随即返回 NULL，
    // MC 抛 "Failed to create window"（实测 AMETHYST_SDL_REUSE_WINDOW=0 即此结果）。
    // 即"是否复用"取决于平台单窗口约束，"是否强制 ES"取决于渲染器实现，两回事。
    if (!ame_envFlagOn("AMETHYST_SDL_REUSE_WINDOW", true)) return false;

    // 仍排除桌面 / OSMesa 系：它们不经本文件的 EGL 兼容逻辑，改动无益且可能
    // 波及已验证路径。
    const char *renderer = getenv("AMETHYST_RENDERER");
    if (renderer != NULL && renderer[0] != '\0') {
        if (strstr(renderer, "desktopgl") != NULL) return false;
        if (strncmp(renderer, "gallium_", 8) == 0) return false;
        if (strncmp(renderer, "libOSMesa", 9) == 0) return false;
        if (strcmp(renderer, "vulkan_zink") == 0) return false;
        if (strstr(renderer, "libMoltenVK") != NULL) return false;
    }
    return true;
}

// iOS 专有：ZL2 明确注释了"尺寸无需额外处理，由 Android Surface 决定（创建时即
// 取 Surface 尺寸，与请求值无关）"。iOS 没有这个前提 —— SDL 的 UIKit 后端按
// 请求值建窗口，于是 RenderPearl 那个隐藏工具窗口就是实打实的 320x480。
//
// 主窗口复用后 MC 拿到的仍是 320x480 这个尺寸，会按它设置 viewport / GUI scale；
// 而 EGL surface 由 SurfaceViewController 的 layer 独立创建（实测 1826x844），
// 两者对不上 → 画面全黑（输入正常，因为控制层是启动器自己的 view）。
// 故复用时必须把窗口尺寸同步成当前请求值。
// 在视图层级中定位 SDL 的 SDL_uikitview。
// 不走 SDL 属性 API（SDL_PROP_WINDOW_UIKIT_WINDOW_POINTER 的字符串值随版本可能
// 变动），改为直接遍历层级匹配类名 —— SDL 的视图已被启动器嵌进宿主 view，
// 一定在同一棵树上，不依赖任何 SDL 符号。
static UIView *ame_findSDLView(UIView *from) {
    Class sdlClass = NSClassFromString(@"SDL_uikitview");
    if (sdlClass == nil || from == nil) return nil;

    UIView *root = from;
    while (root.superview != nil) root = root.superview;

    NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithObject:root];
    while (stack.count > 0) {
        UIView *v = stack.lastObject;
        [stack removeLastObject];
        if ([v isKindOfClass:sdlClass]) return v;
        [stack addObjectsFromArray:v.subviews];
    }
    return nil;
}

// iOS 专有：ZL2 明确注释了"尺寸无需额外处理，由 Android Surface 决定（创建时即
// 取 Surface 尺寸，与请求值无关）"。iOS 没有这个前提 —— SDL 的 UIKit 后端按
// 请求值建窗口，于是 RenderPearl 那个隐藏工具窗口就是实打实的 320x480。
#pragma mark - EGL surface 真实像素尺寸

// 取 EGL surface 的真实像素尺寸 —— 即 CAMetalLayer.drawableSize，由启动器配成
// physicalSize x resolutionScale。这是 ANGLE 实际渲染的分辨率。
static bool ame_eglSurfacePixelSize(int *outW, int *outH) {
    if (outW == NULL || outH == NULL) return false;

    UIView *gsv = nil;
    Class svc = NSClassFromString(@"SurfaceViewController");
    if (svc != nil && [svc respondsToSelector:NSSelectorFromString(@"surface")]) {
        id obj = [svc performSelector:NSSelectorFromString(@"surface")];
        if ([obj isKindOfClass:[UIView class]]) gsv = (UIView *)obj;
    }
    if (gsv == nil) return false;
    CALayer *layer = gsv.layer;
    if (layer == nil) return false;

    // 优先取 CAMetalLayer.drawableSize（gl_bridge 建 surface 用的就是它）
    SEL sel = NSSelectorFromString(@"drawableSize");
    if ([layer respondsToSelector:sel]) {
        NSMethodSignature *sig = [layer methodSignatureForSelector:sel];
        if (sig != nil && strcmp([sig methodReturnType], @encode(CGSize)) == 0) {
            NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
            inv.selector = sel;
            [inv invokeWithTarget:layer];
            CGSize size = CGSizeZero;
            [inv getReturnValue:&size];
            if (size.width > 1.0 && size.height > 1.0) {
                *outW = (int)round(size.width);
                *outH = (int)round(size.height);
                return true;
            }
        }
    }
    // 回退：bounds x contentsScale（启动器配置两者一致，最多差 1 像素的取整）
    CGFloat scale = layer.contentsScale;
    CGSize bs = layer.bounds.size;
    if (scale > 0.0 && bs.width > 1.0 && bs.height > 1.0) {
        *outW = (int)round(bs.width * scale);
        *outH = (int)round(bs.height * scale);
        return true;
    }
    return false;
}

// —— 为什么要接管这两个查询 ——
// MC 的 viewport / framebuffer 尺寸来自它们。SDL 内部把「像素密度」固定为
// UIScreen.scale（本设备 3.0），完全不知道启动器的 resolutionScale，
// 于是无论用户设 25% 还是 100%，SDL 一律回报
// points(812x375) x 3.0 = 2436x1125。而 EGL surface 是
// physicalSize x resolutionScale，两者只在 100% 时相等：
//   100% -> 2436 vs 2436  正常
//    75% -> 2436 vs 1826  viewport 大 1.33 倍，画面被裁到左下角
//    25% -> 2436 vs  609  viewport 大 4 倍，画面严重超出屏幕
// 接管后回报 EGL surface 的真实尺寸，viewport 与 surface 严格一致；
// 而 points 仍恒为全屏逻辑尺寸（供输入坐标与 GUI 布局），两者解耦，
// 行为与 GLFW 路径一致：改分辨率只改渲染像素，画面布局不变。
static bool ame_SDL_GetWindowSizeInPixels(void *window, int *w, int *h) {
    int sw = 0, sh = 0;
    if (ame_eglSurfacePixelSize(&sw, &sh)) {
        if (w != NULL) *w = sw;
        if (h != NULL) *h = sh;
        return true;
    }
    if (ame_real_GetWindowSizeInPixels != NULL) {
        return ame_real_GetWindowSizeInPixels(window, w, h);
    }
    return false;
}

static bool ame_SDL_GL_GetDrawableSize(void *window, int *w, int *h) {
    int sw = 0, sh = 0;
    if (ame_eglSurfacePixelSize(&sw, &sh)) {
        if (w != NULL) *w = sw;
        if (h != NULL) *h = sh;
        return true;
    }
    if (ame_real_GL_GetDrawableSize != NULL) {
        return ame_real_GL_GetDrawableSize(window, w, h);
    }
    return false;
}

#pragma mark - 事件窗口解析回落（对齐 ZL2）

// SDL 的鼠标焦点（mouse->focus）会被 SDL_UpdateMouseFocus 的坐标越界判定清除：
// 虚拟鼠标坐标经分辨率缩放后可超过 SDL window 尺寸。这一点对我们尤其致命 ——
// 我们把 SDL window 尺寸设成了物理像素（2436x1124），而输入桥上报的坐标是
// 按 points 换算来的，越界概率比 ZL2 更高，表现为鼠标/触摸时灵时不灵。
//
// iOS 同样只有一个窗口，故解析失败时回落到上次成功解析出的窗口（ZL2 的
// sdlLastEventWindow 等价物）。
static void *ame_sdlLastEventWindow = NULL;

static void *ame_SDL_GetWindowFromEvent(const void *event) {
    void *window = ame_real_GetWindowFromEvent != NULL
                       ? ame_real_GetWindowFromEvent(event)
                       : NULL;
    if (window != NULL) {
        ame_sdlLastEventWindow = window;
        return window;
    }
    if (ame_sdlLastEventWindow != NULL) {
        NSDebugLog(@"[SDLHook] GetWindowFromEvent: NULL -> fallback %p",
                   ame_sdlLastEventWindow);
        return ame_sdlLastEventWindow;
    }
    return NULL;
}

static void *ame_SDL_GetWindowFromID(uint32_t id) {
    void *window = ame_real_GetWindowFromID != NULL
                       ? ame_real_GetWindowFromID(id)
                       : NULL;
    if (window != NULL) {
        ame_sdlLastEventWindow = window;
        return window;
    }
    if (ame_sdlLastEventWindow != NULL) {
        NSDebugLog(@"[SDLHook] GetWindowFromID(%u): NULL -> fallback %p",
                   (unsigned)id, ame_sdlLastEventWindow);
        return ame_sdlLastEventWindow;
    }
    return NULL;
}

#pragma mark - 文本输入主线程化

// SDL 的 iOS 后端在 SDL_StartTextInputWithProperties 里直接操作 UIKit
// （-[SDL_uikitviewcontroller setTextFieldProperties:]）。MC 从渲染线程调用它，
// 于是出现：
//     "modifying the autolayout engine from a background thread"
// 异常虽被 SDL 侧 catch，但布局未能完成，软键盘行为不可预期。
//
// 修法：这类入口若不在主线程，就 dispatch 到主线程执行。文本输入是低频操作，
// 用 async 避免阻塞渲染线程（也避免主线程同步等待造成死锁）。
static bool ame_dispatchTextInputToMain(void (^work)(void)) {
    if (work == nil) return false;
    if ([NSThread isMainThread]) {
        work();
        return true;
    }
    dispatch_async(dispatch_get_main_queue(), work);
    return true;
}

static bool ame_SDL_StartTextInput(void *window) {
    return ame_dispatchTextInputToMain(^{
        if (ame_real_StartTextInput != NULL) ame_real_StartTextInput(window);
    });
}

static bool ame_SDL_StartTextInputWithProperties(void *window,
                                                 unsigned long long props) {
    return ame_dispatchTextInputToMain(^{
        if (ame_real_StartTextInputWithProperties != NULL) {
            ame_real_StartTextInputWithProperties(window, props);
        }
    });
}

static bool ame_SDL_StopTextInput(void *window) {
    return ame_dispatchTextInputToMain(^{
        if (ame_real_StopTextInput != NULL) ame_real_StopTextInput(window);
    });
}

static bool ame_SDL_SetTextInputArea(void *window, const void *rect, int cursor) {
    // rect 由调用方栈上持有，且 block 是异步执行的 —— 不能把局部变量的地址
    // 传进 block（函数返回后失效）。改堆分配，由 block 在使用后释放。
    ame_SDLRect *heapRect = NULL;
    if (rect != NULL) {
        heapRect = (ame_SDLRect *)malloc(sizeof(ame_SDLRect));
        if (heapRect != NULL) memcpy(heapRect, rect, sizeof(ame_SDLRect));
    }

    if ([NSThread isMainThread]) {
        bool r = ame_real_SetTextInputArea != NULL
                     ? ame_real_SetTextInputArea(window, heapRect, cursor)
                     : false;
        free(heapRect);
        return r;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        if (ame_real_SetTextInputArea != NULL) {
            ame_real_SetTextInputArea(window, heapRect, cursor);
        }
        free(heapRect);
    });
    return true;
}

#pragma mark - SDL hint（对齐 ZL2 的 SDL_InitSubSystem hook）

// hint 必须在 SDL_Init 之前设置才生效，因此挂在 InitSubSystem 上、在调用
// 原函数之前设置 —— 这与 ZL2 custom_SDL_InitSubSystem_Func 的做法一致。
//
//   SDL_RETURN_KEY_HIDES_IME       ZL2 注释：启动器的正常行为，SDL 默认 false
//   SDL_ENABLE_SCREEN_KEYBOARD=1   MC 按桌面惯例设成 0 以禁用平台软键盘（改用
//                                  自绘 IME UI），但移动端依赖 SDL 唤起输入法；
//                                  MC 在 SDL_Init 之前设值，此处覆盖回启用
//   SDL_OPENGL_FORCE_SRGB_FRAMEBUFFER=0
//                                  ZL2：MobileGlues 无法传入正确的 EGL 参数来
//                                  支持这个；对所有走 EGL bridge 的移动转译型
//                                  渲染器同样适用
static bool ame_SDL_InitSubSystem(uint32_t flags) {
    if (ame_real_SetHint == NULL) {
        ame_real_SetHint = (ame_fn_SDL_SetHint)ame_real_dlsym("SDL_SetHint");
    }
    if (ame_real_SetHint != NULL) {
        ame_real_SetHint("SDL_RETURN_KEY_HIDES_IME", "true");
        if (ame_glBridgeEnabled()) {
            ame_real_SetHint("SDL_OPENGL_FORCE_SRGB_FRAMEBUFFER", "0");
        }
        ame_real_SetHint("SDL_ENABLE_SCREEN_KEYBOARD", "1");
        NSDebugLog(@"[SDLHook] SDL hint set (screenKeyboard=1, srgb=%s)",
                   ame_glBridgeEnabled() ? "off" : "default");
    }
    if (ame_real_InitSubSystem != NULL) {
        return ame_real_InitSubSystem(flags);
    }
    return false;
}

//
// 主窗口复用后 MC 拿到的仍是 320x480 这个尺寸，会按它设置 viewport / GUI scale，
// 而 EGL surface 由 SurfaceViewController 的 layer 独立创建，两者对不上 → 黑屏。
//
// —— 窗口尺寸必须用像素，而不是 points（对齐 ZL2 / 安卓与 GLFW）——
// ZL2 的 SDLSurface.nativeResize() 调用
//     SDLActivity.nativeSetScreenResolution(surfaceW, surfaceH,
//                                           deviceW, deviceH, density, rate)
// 把"窗口尺寸"直接定义成 Surface 的像素尺寸，而非 points；GLFW 路径下
// glfwGetWindowSize() 同样返回物理像素。两者因此都不会把逻辑尺寸误当成渲染尺寸。
//
// 早前这里按 SDL 的 points 语义设成全屏逻辑尺寸(812x375)，SDL 随即派发
// RESIZED(812x375)，MC 便据此设置 viewport —— 而 EGL surface 是 2436x1124，
// 画面于是只占屏幕一角（约 1/9 面积）。现改为全屏物理像素，与 ZL2/安卓、GLFW
// 语义一致：窗口尺寸恒定 → GUI 布局稳定；渲染像素随分辨率变 → 可自由缩放。
//
// 注意取原生 scale 而非 layer.contentsScale：后者含 resolutionScale，若乘上去
// 会让窗口尺寸随分辨率变化，GUI 布局跟着变（正是要避免的）。
static void ame_syncReusedWindowSize(void *window, int w, int h) {
    if (window == NULL || w <= 0 || h <= 0) return;

    // 取启动器的 GameSurfaceView —— EGL surface 就绑在它的 layer 上
    UIView *gsv = nil;
    Class svc = NSClassFromString(@"SurfaceViewController");
    if (svc != nil && [svc respondsToSelector:NSSelectorFromString(@"surface")]) {
        id obj = [svc performSelector:NSSelectorFromString(@"surface")];
        if ([obj isKindOfClass:[UIView class]]) gsv = (UIView *)obj;
    }

    // 窗口尺寸 = 全屏物理像素（恒定，不随 resolutionScale 变化）
    int targetW = w, targetH = h;
    if (gsv != nil && gsv.bounds.size.width > 0.0 && gsv.bounds.size.height > 0.0) {
        CGFloat native = [UIScreen mainScreen].scale;
        if (!(native > 0.0)) native = 1.0;
        targetW = (int)round(gsv.bounds.size.width  * native);
        targetH = (int)round(gsv.bounds.size.height * native);
    }

    if (ame_real_SetWindowSize == NULL) {
        ame_real_SetWindowSize =
            (ame_fn_SDL_SetWindowSize)ame_real_dlsym("SDL_SetWindowSize");
    }
    bool ok = false;
    if (ame_real_SetWindowSize != NULL) {
        ok = ame_real_SetWindowSize(window, targetW, targetH);
    }

    // SetWindowSize 之后 SDL 会按自身换算调整视图；这里把视图强制回全屏逻辑尺寸
    // 并把密度归一，使显示仍铺满屏幕（真正的渲染尺寸由 EGL surface 决定）。
    UIView *sdlView = ame_findSDLView(gsv);
    if (sdlView != nil) {
        if (fabs((double)sdlView.contentScaleFactor - 1.0) > 0.001) {
            CGFloat old = sdlView.contentScaleFactor;
            sdlView.contentScaleFactor = 1.0;
            NSDebugLog(@"[SDLHook] SDL view contentScaleFactor %.3f -> 1.000 "
                       @"(window sized in pixels)", old);
        }
        if (gsv != nil && gsv.bounds.size.width > 0.0) {
            CGRect full = CGRectMake(0.0, 0.0,
                                     gsv.bounds.size.width,
                                     gsv.bounds.size.height);
            CGSize cur = sdlView.frame.size;
            if (fabs((double)cur.width  - (double)full.size.width)  > 0.5 ||
                fabs((double)cur.height - (double)full.size.height) > 0.5) {
                NSDebugLog(@"[SDLHook] SDL view frame %.0fx%.0f -> %.0fx%.0f "
                           @"(fullscreen points)",
                           cur.width, cur.height,
                           full.size.width, full.size.height);
                sdlView.frame = full;
                [sdlView setNeedsLayout];
            }
        }
    }

    NSDebugLog(@"[SDLHook] reused window resize %dx%d -> %dx%d px "
               @"(req px %dx%d) (%s)",
               ame_primaryWindowW, ame_primaryWindowH, targetW, targetH, w, h,
               ok ? "ok" : (ame_real_SetWindowSize ? "rejected"
                                                   : "no SDL_SetWindowSize"));
    ame_primaryWindowW = targetW;
    ame_primaryWindowH = targetH;
}

#pragma mark - 3) EGL 兼容重试

// RENDERABLE_TYPE 归一化为 ES2_BIT：宿主若不支持请求的 ES3/桌面 GL 位，
// 退回 ES2 至少能拿到一个可用 config。
static int ame_normalizeEglChooseConfigList(const int *attrib_list, int *fixed, int cap) {
    if (attrib_list == NULL) return 0;
    int n = 0;
    for (int i = 0; n < cap - 2; i += 2) {
        int attr = attrib_list[i];
        int val = attrib_list[i + 1];
        if (attr == AME_EGL_NONE) {
            fixed[n] = AME_EGL_NONE;
            fixed[n + 1] = 0;
            n += 2;
            break;
        }
        if (attr == AME_EGL_RENDERABLE_TYPE) {
            if ((val & (AME_EGL_OPENGL_ES3_BIT | AME_EGL_OPENGL_BIT)) != 0 &&
                (val & AME_EGL_OPENGL_ES2_BIT) == 0) {
                val = (val & ~(AME_EGL_OPENGL_ES3_BIT | AME_EGL_OPENGL_BIT)) |
                      AME_EGL_OPENGL_ES2_BIT;
            }
        }
        fixed[n] = attr;
        fixed[n + 1] = val;
        n += 2;
    }
    return n > 0;
}

// 剔除宿主不识别的 KHR 版本属性，生成兼容重试表；返回请求的主版本号（无则 0）
static int ame_normalizeEglContextAttribs(const int *attrib_list, int *fixed, int cap,
                                          bool esSemantics) {
    int version = 0;
    bool hasClientVersion = false;
    if (attrib_list == NULL) return 0;
    int n = 0;
    for (int i = 0; n < cap - 2; i += 2) {
        int attr = attrib_list[i];
        int val = attrib_list[i + 1];
        if (attr == AME_EGL_NONE) break;
        if (attr == AME_EGL_CONTEXT_MAJOR_VERSION_KHR) {  // 记录主版本后剔除
            if (version == 0) version = val;
            continue;
        }
        if (attr == AME_EGL_CONTEXT_MINOR_VERSION_KHR) continue;
        if (attr == AME_EGL_CONTEXT_CLIENT_VERSION) {
            hasClientVersion = true;
            if (version == 0) version = val;
        }
        if (n >= cap - 2) return 0;
        fixed[n++] = attr;
        fixed[n++] = val;
    }
    // 仅 ES 语义下补写 CLIENT_VERSION（避免退化成驱动默认版本）；
    // desktop 语义不补写 —— 桌面 context 不使用 CLIENT_VERSION
    if (esSemantics && version > 0 && !hasClientVersion) {
        if (n >= cap - 2) return 0;
        fixed[n++] = AME_EGL_CONTEXT_CLIENT_VERSION;
        fixed[n++] = version;
    }
    if (n >= cap - 2) return 0;
    fixed[n++] = AME_EGL_NONE;
    fixed[n++] = 0;
    return version;
}

static void *ame_proxyEglCreateContext(void *dpy, void *config, void *share,
                                       const int *attrib_list) {
    if (ame_orig_eglCreateContext == NULL) {
        NSDebugLog(@"[SDLHook] eglCreateContext was not resolved");
        return NULL;
    }

    void *ctx = ame_orig_eglCreateContext(dpy, config, share, attrib_list);
    if (ctx != NULL || !ame_sdlGlesCompatEnabled()) return ctx;

    bool esSemantics = ame_forcedEsProfile;
    int fixed[64];
    int version = ame_normalizeEglContextAttribs(attrib_list, fixed, 64, esSemantics);
    if (version == 0) return ctx;

    NSDebugLog(@"[SDLHook] retrying eglCreateContext without KHR version attrs (CV=%d)", version);
    ctx = ame_orig_eglCreateContext(dpy, config, share, fixed);
    if (ctx != NULL || !esSemantics || version <= 2) return ctx;  // CV=2 为移动端最后兜底

    NSDebugLog(@"[SDLHook] retrying eglCreateContext with CV=2 after CV=%d failed", version);
    int es2[3] = {AME_EGL_CONTEXT_CLIENT_VERSION, 2, AME_EGL_NONE};
    return ame_orig_eglCreateContext(dpy, config, share, es2);
}

static int ame_proxyEglChooseConfig(void *dpy, const int *attrib_list, void **configs,
                                    int config_size, int *num_config) {
    if (ame_orig_eglChooseConfig == NULL) {
        NSDebugLog(@"[SDLHook] eglChooseConfig was not resolved");
        return 0;
    }

    int result = ame_orig_eglChooseConfig(dpy, attrib_list, configs, config_size, num_config);
    if (result && num_config != NULL && *num_config > 0) return result;
    if (!ame_sdlGlesCompatEnabled()) return result;  // 兼容 fallback 仅限移动 ES 渲染器

    int fixed[64];
    if (!ame_normalizeEglChooseConfigList(attrib_list, fixed, 64)) return result;
    int fallbackCount = 0;
    int fallbackResult = ame_orig_eglChooseConfig(dpy, fixed, configs, config_size, &fallbackCount);
    if (fallbackResult && num_config != NULL) *num_config = fallbackCount;
    NSDebugLog(@"[SDLHook] eglChooseConfig fallback result=%d count=%d",
               fallbackResult, fallbackCount);
    return fallbackResult;
}

static int ame_proxyEglSwapBuffers(void *dpy, void *surface) {
    if (ame_orig_eglSwapBuffers == NULL) {
        NSDebugLog(@"[SDLHook] eglSwapBuffers was not resolved");
        return 0;
    }
    return ame_orig_eglSwapBuffers(dpy, surface);
}

// 把原始指针换成代理。orig 为 NULL 时不覆盖（ZL2 语义：首次解析后固定）。
static void ame_maybeWrapEgl(const char *name, void **out) {
    if (name == NULL || *out == NULL) return;
    if (strcmp(name, "eglChooseConfig") == 0) {
        if (ame_orig_eglChooseConfig == NULL) ame_orig_eglChooseConfig = (ame_fn_eglChooseConfig)*out;
        if (*out != (void *)ame_proxyEglChooseConfig) *out = (void *)ame_proxyEglChooseConfig;
    } else if (strcmp(name, "eglCreateContext") == 0) {
        if (ame_orig_eglCreateContext == NULL) ame_orig_eglCreateContext = (ame_fn_eglCreateContext)*out;
        if (*out != (void *)ame_proxyEglCreateContext) *out = (void *)ame_proxyEglCreateContext;
    } else if (strcmp(name, "eglSwapBuffers") == 0) {
        if (ame_orig_eglSwapBuffers == NULL) ame_orig_eglSwapBuffers = (ame_fn_eglSwapBuffers)*out;
        if (*out != (void *)ame_proxyEglSwapBuffers) *out = (void *)ame_proxyEglSwapBuffers;
    }
}

#pragma mark - SDL 函数包装

static void *ame_SDL_CreateWindow(const char *title, int w, int h, uint32_t flags) {
    ame_forceEglProfileEs();
    NSDebugLog(@"[SDLHook] SDL_CreateWindow title=%s %dx%d flags=0x%x",
               title ? title : "(null)", w, h, flags);
    bool reuse = ame_shouldReusePrimaryWindow();
    if (reuse && ame_primaryWindow != NULL) {
        ame_primaryWindowRefs++;
        NSDebugLog(@"[SDLHook] reusing primary window %p, refs=%u",
                   ame_primaryWindow, ame_primaryWindowRefs);
        ame_syncReusedWindowSize(ame_primaryWindow, w, h);
        return ame_primaryWindow;
    }
    void *wnd = ame_real_CreateWindow ? ame_real_CreateWindow(title, w, h, flags) : NULL;
    if (reuse && wnd != NULL) {
        ame_primaryWindow = wnd;
        ame_primaryWindowRefs = 1;
        ame_primaryWindowW = w;
        ame_primaryWindowH = h;
    }
    NSDebugLog(@"[SDLHook] SDL_CreateWindow -> %p", wnd);
    return wnd;
}

static void *ame_SDL_CreateWindowWithProperties(uint32_t props) {
    ame_forceEglProfileEs();
    NSDebugLog(@"[SDLHook] SDL_CreateWindowWithProperties props=%u", props);
    bool reuse = ame_shouldReusePrimaryWindow();
    if (reuse && ame_primaryWindow != NULL) {
        ame_primaryWindowRefs++;
        NSDebugLog(@"[SDLHook] reusing primary window %p, refs=%u",
                   ame_primaryWindow, ame_primaryWindowRefs);
        // properties 版本的宽高需从 props 里取（SDL_PROP_WINDOW_CREATE_WIDTH/
        // HEIGHT_NUMBER）。取不到就不改尺寸，行为与改动前一致。
        if (ame_real_GetNumberProperty == NULL) {
            ame_real_GetNumberProperty =
                (ame_fn_SDL_GetNumberProperty)ame_real_dlsym("SDL_GetNumberProperty");
        }
        if (ame_real_GetNumberProperty != NULL) {
            int pw = (int)ame_real_GetNumberProperty(props, "SDL.window.create.width", 0);
            int ph = (int)ame_real_GetNumberProperty(props, "SDL.window.create.height", 0);
            ame_syncReusedWindowSize(ame_primaryWindow, pw, ph);
        }
        return ame_primaryWindow;
    }
    void *wnd = ame_real_CreateWindowWithProperties
                    ? ame_real_CreateWindowWithProperties(props)
                    : NULL;
    if (reuse && wnd != NULL) {
        ame_primaryWindow = wnd;
        ame_primaryWindowRefs = 1;
        ame_primaryWindowW = 0;
        ame_primaryWindowH = 0;
    }
    NSDebugLog(@"[SDLHook] SDL_CreateWindowWithProperties -> %p", wnd);
    return wnd;
}

static void ame_SDL_DestroyWindow(void *window) {
    if (window != NULL && window == ame_primaryWindow) {
        if (ame_primaryWindowRefs > 0) ame_primaryWindowRefs--;
        if (ame_primaryWindowRefs > 0) {
            NSDebugLog(@"[SDLHook] DestroyWindow %p skipped, refs=%u",
                       window, ame_primaryWindowRefs);
            return;
        }
        ame_primaryWindow = NULL;
        ame_primaryWindowRefs = 0;
        ame_primaryWindowW = 0;
        ame_primaryWindowH = 0;
        // 窗口已销毁，事件解析回落缓存必须一并失效，否则会返回悬垂指针
        ame_sdlLastEventWindow = NULL;
    }
    if (ame_real_DestroyWindow) ame_real_DestroyWindow(window);
}

static void *ame_SDL_LoadFunction(void *handle, const char *name) {
    void *r = ame_real_LoadFunction ? ame_real_LoadFunction(handle, name) : NULL;
    ame_maybeWrapEgl(name, &r);
    return r;
}

// SDL 公共 EGL 解析入口，可绕过 SDL_LoadFunction；补齐同样的代理
static void *ame_SDL_EGL_GetProcAddress(const char *proc) {
    void *r = ame_real_EGL_GetProcAddress ? ame_real_EGL_GetProcAddress(proc) : NULL;
    if (proc == NULL || r == NULL) return r;
    ame_maybeWrapEgl(proc, &r);
    return r;
}

// Vulkan 加载器一致性：MC 26.3 起 RenderPearl 要求 SDL 与 LWJGL 使用同一
// 加载器实例（校验 vkGetInstanceProcAddr 指针一致），而 SDL 仅能按路径加载。
// 启动器若已持有句柄（十六进制记录在 AMETHYST_VULKAN_PTR），此处直接还回。
// 对应句柄的引用计数由启动器持有，故忽略 SDL 侧的卸载。
static void *ame_SDL_LoadObject(const char *path) {
    if (path != NULL && (strstr(path, "vulkan") != NULL || strstr(path, "MoltenVK") != NULL)) {
        const char *vkptr = getenv("AMETHYST_VULKAN_PTR");
        if (vkptr != NULL && vkptr[0] != '\0') {
            void *handle = (void *)(uintptr_t)strtoull(vkptr, NULL, 16);
            if (handle != NULL) {
                NSDebugLog(@"[SDLHook] SDL_LoadObject('%s') -> shared handle %p", path, handle);
                return handle;
            }
        }
    }
    return ame_real_LoadObject ? ame_real_LoadObject(path) : NULL;
}

static void ame_SDL_UnloadObject(void *handle) {
    const char *vkptr = getenv("AMETHYST_VULKAN_PTR");
    if (vkptr != NULL && vkptr[0] != '\0') {
        void *vulkan_handle = (void *)(uintptr_t)strtoull(vkptr, NULL, 16);
        if (handle == vulkan_handle) {
            NSDebugLog(@"[SDLHook] SDL_UnloadObject(%p) ignored (shared handle)", handle);
            return;
        }
    }
    if (ame_real_UnloadObject) ame_real_UnloadObject(handle);
}

#pragma mark - 5) SDL GL 入口 → 启动器 EGL bridge

// 为什么需要接管：
//   SDL 的 UIKit 后端走的是 EAGL / CAEAGLLayer（iOS 系统 OpenGLES 框架），
//   而 MobileGL / Mithril / MobileGlues 提供的是 **EGL + GL** 符号。两者不是
//   同一套 ABI，SDL 自己建的上下文拿不到渲染器的 GL 函数，MC 26.3 的
//   GlBackend 因此判定 OpenGL 不可用并回落到原生 Vulkan。
//
//   启动器的 EGL bridge（gl_bridge.m）早已在 GLFW 路径（26.2 及以下）验证可用，
//   且 gl_init_context() 直接从 SurfaceViewController 的 layer 建 EGL surface，
//   不依赖 SDL 建了哪个 view —— 所以可以整条搬到 SDL3 路径上复用。
//
// 判定复用 ame_sdlGlesCompatEnabled()：它已排除 zink（libOSMesa/gallium_/
// vulkan_zink）与原生 Vulkan（libMoltenVK），因此 zink 在 26.3 上"回落 Vulkan"
// 那条已验证可用的路径不会受到任何影响。
//
// 默认开启（2026-09-05 实测结论）：
//
// 此前默认关闭的理由是"接管后桌面 GLSL 经 shaderc/glslang 编译稳定崩溃"。该
// 崩溃根因已定位并修复 —— MobileGL 静态嵌入 glslang/SPIRV-Tools，其 C++ 符号
// 与 shaderc 内嵌的副本在 dyld 层 interpose，同一 Module 对象被两套布局解析，
// 崩于 spvtools::opt::Module::ForEachInst。上游 MobileGL 早已为 macOS 用
// exported_symbols_list 修过（只导出 _CGL*/_egl*/_gl[A-Z0-9]*），唯独 iOS 分支
// 被条件排除；补齐后重编的 dylib 实测不再崩溃。
//
// 另需说明：崩溃与"是否接管"无关。曾实测 BRIDGE=0 + NO_PRELOAD_RENDERER=1 同样
// 崩在同一地址 —— 真正的变量是 MobileGL 以 RTLD_GLOBAL 还是 RTLD_LOCAL 载入。
//
// 实测（874b9e8，接管 + DirectGLES）：MC 完整走通 OpenGL 后端，资源全部加载、
// 首帧渲染成功、无崩溃，仅画面全黑。黑屏系主窗口复用后未同步尺寸所致，已由
// ame_syncReusedWindowSize() 修复（iOS 无 ZL2 依赖的 Android Surface 前提）。
//
// 回落路径的风险已不再是默认关闭的理由：MoltenVK 1.2.9（为修 A11 上 1.21.1
// 草方块而降级）转译不了 MC 26.3 的 SPIR-V，会生成非法 MSL
// （float3 vertex(thread const int& index)），故 26.3 现在更不能依赖回落。
//
// 如需回到"不接管 -> 回落 Vulkan"，用 AMETHYST_SDL_GL_BRIDGE=0。
static bool ame_glBridgeEnabled(void) {
    if (!ame_envFlagOn("AMETHYST_SDL_GL_BRIDGE", true)) return false;

    const char *renderer = getenv("AMETHYST_RENDERER");
    if (renderer == NULL || renderer[0] == '\0') return false;

    // 绝不接管的：zink 在 26.3 上依赖"OpenGL 被隐藏 → 回落 Vulkan"且已验证
    // 可进世界，是唯一的可用路径，一个字节都不能动。
    if (strncmp(renderer, "libOSMesa", 9) == 0) return false;    // zink（带版本号）
    if (strncmp(renderer, "gallium_", 8) == 0) return false;     // OSMesa 系
    if (strcmp(renderer, "vulkan_zink") == 0) return false;      // zink
    // 原生 Vulkan 自身走 Vulkan 路径，不需要 GL bridge
    if (strstr(renderer, "libMoltenVK") != NULL) return false;

    // 需要 EGL bridge 的转译型渲染器：它们提供 EGL + GL 符号，SDL 的 EAGL
    // 后端无法对接，必须由 bridge 建上下文并供给 GL 函数指针。
    if (strstr(renderer, "libMobileGL") != NULL) return true;    // MobileGL 双后端
    if (strstr(renderer, "libmithril") != NULL) return true;     // Mithril
    if (strstr(renderer, "mobileglues") != NULL) return true;    // MobileGlues
    if (strstr(renderer, "gl4es") != NULL) return true;          // GL4ES
    if (strstr(renderer, "libltw") != NULL) return true;         // LTW
    if (strncmp(renderer, "opengles", 8) == 0) return true;      // 内置 GLES

    return ame_isMobileGluesEgl();
}

// egl_bridge.m 的上下文入口。这些函数没有公开头文件，故在此 extern 声明。
// 参数用 void* 以避开 basic_render_window_t 的类型依赖。
// SDL3 路径用 ForSDL3 变体：不写 org.lwjgl.opengl.libname（该属性由 JavaLauncher
// 在 JVM 启动时以 -D 传入，LWJGL 早已读取；此处再设无效且需 attach 非 JVM 线程）。
extern int   pojavInitOpenGLForSDL3(void);
extern void *pojavCreateContext(void *contextSrc);
extern void  pojavMakeCurrent(void *window);
extern void  pojavSwapBuffers(void);
extern void  pojavSwapInterval(int interval);

static bool   g_glBridgeInited = false;
static void  *g_glContext = NULL;      // 充当 SDL_GLContext
static void  *g_rendererHandle = NULL; // 渲染器 dylib 句柄（缓存，避免重复 dlopen）

static void *ame_rendererHandle(void) {
    if (g_rendererHandle != NULL) return g_rendererHandle;
    const char *renderer = getenv("AMETHYST_RENDERER");
    if (renderer == NULL || renderer[0] == '\0') return NULL;
    NSString *path = [NSString stringWithFormat:@"@rpath/%s", renderer];
    // 渲染器已由 pojavInitOpenGL 以 RTLD_GLOBAL 预加载，此处返回同一句柄，
    // 仅增加引用计数，不会重复映射。
    g_rendererHandle = dlopen(path.UTF8String, RTLD_NOW | RTLD_GLOBAL);
    if (g_rendererHandle == NULL) {
        NSDebugLog(@"[SDLHook] renderer dlopen('%@') failed: %s",
                   path, dlerror() ?: "unknown");
    }
    return g_rendererHandle;
}

// 库已由启动器预加载，这里只负责初始化 bridge
static bool ame_SDL_GL_LoadLibrary(const char *path) {
    if (!g_glBridgeInited) {
        g_glBridgeInited = true;
        int r = pojavInitOpenGLForSDL3();
        NSDebugLog(@"[SDLHook] SDL_GL_LoadLibrary('%s') -> pojavInitOpenGLForSDL3()=%d (EGL bridge)",
                   path ?: "<null>", r);
    }
    return true;
}

static void *ame_SDL_GL_CreateContext(void *window) {
    // MC 26.3 ss9+ 在设备初始化时先建一个隐藏工具窗口（flags 含 SDL_WINDOW_HIDDEN），
    // 随后再建主窗口。而 EGL bridge 的上下文生命周期与进程一致
    // （SDL_GL_DestroyContext 不真正销毁，见下），若每次调用都新建，就会在同一个
    // CALayer 上叠加第二个 EGLSurface —— 部分 EGL 实现（含 MobileGL）会直接失败，
    // 即便成功也会让 eglMakeCurrent 在两个 surface 间反复切换。
    // 故复用首个上下文，与 ZL2 的 shouldReusePrimaryWindow() 同一思路。
    if (g_glContext != NULL) {
        NSDebugLog(@"[SDLHook] SDL_GL_CreateContext(%p) -> reuse existing %p", window, g_glContext);
        // 复用时也要保证它处于 current 状态：MC 建完上下文后必然调 MakeCurrent，
        // 这里不额外处理。
        return g_glContext;
    }
    void *ctx = pojavCreateContext(NULL);
    if (ctx != NULL) g_glContext = ctx;
    NSDebugLog(@"[SDLHook] SDL_GL_CreateContext(%p) -> %p (EGL bridge)", window, ctx);
    return ctx;
}

static bool ame_SDL_GL_MakeCurrent(void *window, void *context) {
    if (context != NULL) g_glContext = context;
    pojavMakeCurrent(context);
    NSDebugLog(@"[SDLHook] SDL_GL_MakeCurrent(%p, %p) -> EGL bridge", window, context);
    return true;
}

static bool ame_SDL_GL_SwapWindow(void *window) {
    pojavSwapBuffers();
    return true;
}

// GL 函数必须来自渲染器自身。若误返回系统 GLES / EAGL 的实现，
// LWJGL 拿到的函数指针与 EGL 上下文不匹配，会直接崩。
static void *ame_SDL_GL_GetProcAddress(const char *proc) {
    if (proc == NULL) return NULL;
    void *h = ame_rendererHandle();
    if (h != NULL) {
        void *p = dlsym(h, proc);
        if (p != NULL) return p;
    }
    void *r = ame_real_GL_GetProcAddress ? ame_real_GL_GetProcAddress(proc) : NULL;
    if (r == NULL) r = dlsym(RTLD_DEFAULT, proc);
    return r;
}

static bool ame_SDL_GL_SetSwapInterval(int interval) {
    pojavSwapInterval(interval);
    return true;
}

// 上下文由 EGL bridge 持有，生命周期与进程一致。这里不真正销毁，
// 只摘掉引用 —— 否则 SDL 会用 EAGL 的语义去释放一个 EGL 对象而崩溃。
static bool ame_SDL_GL_DestroyContext(void *context) {
    NSDebugLog(@"[SDLHook] SDL_GL_DestroyContext(%p) ignored (owned by EGL bridge)", context);
    if (g_glContext == context) g_glContext = NULL;
    return true;
}

static void *ame_SDL_GL_GetCurrentContext(void) {
    return g_glContext;
}

#pragma mark - 对 main_hook.m 的接入点

/// 由 hooked_dlsym 在返回 orig_dlsym 之前调用。
/// 返回非 NULL 表示本模块接管了该符号；否则返回 NULL 让调用方走原路径。
void *amethyst_sdl3_hook_resolve(void *handle, const char *name) {
    if (name == NULL) return NULL;

    // 先记下真实指针（无论本次是否接管，后续包装都要用到）
    if (strcmp(name, "SDL_CreateWindow") == 0) {
        if (ame_real_CreateWindow == NULL) {
            ame_real_CreateWindow = (ame_fn_SDL_CreateWindow)amethyst_orig_dlsym(handle, name);
        }
        NSDebugLog(@"[SDLHook] hooked SDL_CreateWindow (real=%p)", (void *)ame_real_CreateWindow);
        return (void *)ame_SDL_CreateWindow;
    }
    if (strcmp(name, "SDL_CreateWindowWithProperties") == 0) {
        if (ame_real_CreateWindowWithProperties == NULL) {
            ame_real_CreateWindowWithProperties =
                (ame_fn_SDL_CreateWindowWithProperties)amethyst_orig_dlsym(handle, name);
        }
        NSDebugLog(@"[SDLHook] hooked SDL_CreateWindowWithProperties (real=%p)",
                   (void *)ame_real_CreateWindowWithProperties);
        return (void *)ame_SDL_CreateWindowWithProperties;
    }
    if (strcmp(name, "SDL_DestroyWindow") == 0) {
        if (ame_real_DestroyWindow == NULL) {
            ame_real_DestroyWindow = (ame_fn_SDL_DestroyWindow)amethyst_orig_dlsym(handle, name);
        }
        return (void *)ame_SDL_DestroyWindow;
    }
    if (strcmp(name, "SDL_LoadFunction") == 0) {
        if (ame_real_LoadFunction == NULL) {
            ame_real_LoadFunction = (ame_fn_SDL_LoadFunction)amethyst_orig_dlsym(handle, name);
        }
        return (void *)ame_SDL_LoadFunction;
    }
    if (strcmp(name, "SDL_EGL_GetProcAddress") == 0) {
        if (ame_real_EGL_GetProcAddress == NULL) {
            ame_real_EGL_GetProcAddress =
                (ame_fn_SDL_EGL_GetProcAddress)amethyst_orig_dlsym(handle, name);
        }
        return (void *)ame_SDL_EGL_GetProcAddress;
    }
    if (strcmp(name, "SDL_LoadObject") == 0) {
        if (ame_real_LoadObject == NULL) {
            ame_real_LoadObject = (ame_fn_SDL_LoadObject)amethyst_orig_dlsym(handle, name);
        }
        return (void *)ame_SDL_LoadObject;
    }
    if (strcmp(name, "SDL_UnloadObject") == 0) {
        if (ame_real_UnloadObject == NULL) {
            ame_real_UnloadObject = (ame_fn_SDL_UnloadObject)amethyst_orig_dlsym(handle, name);
        }
        return (void *)ame_SDL_UnloadObject;
    }
    // 尺寸查询：与 GL 后端无关，无条件接管（见函数处注释）
    if (strcmp(name, "SDL_GetWindowSizeInPixels") == 0) {
        if (ame_real_GetWindowSizeInPixels == NULL) {
            ame_real_GetWindowSizeInPixels =
                (ame_fn_SDL_GetWindowSizeInPixels)amethyst_orig_dlsym(handle, name);
        }
        NSDebugLog(@"[SDLHook] hooked SDL_GetWindowSizeInPixels -> EGL surface size");
        return (void *)ame_SDL_GetWindowSizeInPixels;
    }
    // SDL_GL_SetAttribute 不接管：MC 自己调用它设属性是合法行为，我们只在
    // 建窗前主动调用同一个函数来强制 ES profile（见 ame_forceEglProfileEs）。
    // SDL GL 上下文接管（MobileGL / Mithril / MobileGlues / gl4es / LTW）
    if (ame_glBridgeEnabled()) {
        if (strcmp(name, "SDL_GL_LoadLibrary") == 0) {
            if (ame_real_GL_LoadLibrary == NULL)
                ame_real_GL_LoadLibrary = (ame_fn_SDL_GL_LoadLibrary)amethyst_orig_dlsym(handle, name);
            NSDebugLog(@"[SDLHook] hooked SDL_GL_LoadLibrary -> EGL bridge");
            return (void *)ame_SDL_GL_LoadLibrary;
        }
        if (strcmp(name, "SDL_GL_CreateContext") == 0) {
            if (ame_real_GL_CreateContext == NULL)
                ame_real_GL_CreateContext = (ame_fn_SDL_GL_CreateContext)amethyst_orig_dlsym(handle, name);
            NSDebugLog(@"[SDLHook] hooked SDL_GL_CreateContext -> EGL bridge");
            return (void *)ame_SDL_GL_CreateContext;
        }
        if (strcmp(name, "SDL_GL_MakeCurrent") == 0) {
            if (ame_real_GL_MakeCurrent == NULL)
                ame_real_GL_MakeCurrent = (ame_fn_SDL_GL_MakeCurrent)amethyst_orig_dlsym(handle, name);
            NSDebugLog(@"[SDLHook] hooked SDL_GL_MakeCurrent -> EGL bridge");
            return (void *)ame_SDL_GL_MakeCurrent;
        }
        if (strcmp(name, "SDL_GL_SwapWindow") == 0) {
            if (ame_real_GL_SwapWindow == NULL)
                ame_real_GL_SwapWindow = (ame_fn_SDL_GL_SwapWindow)amethyst_orig_dlsym(handle, name);
            NSDebugLog(@"[SDLHook] hooked SDL_GL_SwapWindow -> EGL bridge");
            return (void *)ame_SDL_GL_SwapWindow;
        }
        if (strcmp(name, "SDL_GL_GetProcAddress") == 0) {
            if (ame_real_GL_GetProcAddress == NULL)
                ame_real_GL_GetProcAddress = (ame_fn_SDL_GL_GetProcAddress)amethyst_orig_dlsym(handle, name);
            NSDebugLog(@"[SDLHook] hooked SDL_GL_GetProcAddress -> renderer dlsym");
            return (void *)ame_SDL_GL_GetProcAddress;
        }
        if (strcmp(name, "SDL_GL_SetSwapInterval") == 0) {
            if (ame_real_GL_SetSwapInterval == NULL)
                ame_real_GL_SetSwapInterval = (ame_fn_SDL_GL_SetSwapInterval)amethyst_orig_dlsym(handle, name);
            NSDebugLog(@"[SDLHook] hooked SDL_GL_SetSwapInterval -> EGL bridge");
            return (void *)ame_SDL_GL_SetSwapInterval;
        }
        if (strcmp(name, "SDL_GL_DestroyContext") == 0) {
            if (ame_real_GL_DestroyContext == NULL)
                ame_real_GL_DestroyContext = (ame_fn_SDL_GL_DestroyContext)amethyst_orig_dlsym(handle, name);
            return (void *)ame_SDL_GL_DestroyContext;
        }
        if (strcmp(name, "SDL_GL_GetCurrentContext") == 0) {
            if (ame_real_GL_GetCurrentContext == NULL)
                ame_real_GL_GetCurrentContext = (ame_fn_SDL_GL_GetCurrentContext)amethyst_orig_dlsym(handle, name);
            return (void *)ame_SDL_GL_GetCurrentContext;
        }
        if (strcmp(name, "SDL_GL_GetDrawableSize") == 0) {
            if (ame_real_GL_GetDrawableSize == NULL)
                ame_real_GL_GetDrawableSize = (ame_fn_SDL_GL_GetDrawableSize)amethyst_orig_dlsym(handle, name);
            NSDebugLog(@"[SDLHook] hooked SDL_GL_GetDrawableSize -> EGL surface size");
            return (void *)ame_SDL_GL_GetDrawableSize;
        }
    }

    // —— 以下与渲染后端无关，无条件接管 ——
    // GLFW 老路径不加载 libSDL3，根本不会查询这些符号，因此不受影响。
    if (strcmp(name, "SDL_GetWindowFromEvent") == 0) {
        if (ame_real_GetWindowFromEvent == NULL)
            ame_real_GetWindowFromEvent =
                (ame_fn_SDL_GetWindowFromEvent)amethyst_orig_dlsym(handle, name);
        NSDebugLog(@"[SDLHook] hooked SDL_GetWindowFromEvent -> last-window fallback");
        return (void *)ame_SDL_GetWindowFromEvent;
    }
    if (strcmp(name, "SDL_GetWindowFromID") == 0) {
        if (ame_real_GetWindowFromID == NULL)
            ame_real_GetWindowFromID =
                (ame_fn_SDL_GetWindowFromID)amethyst_orig_dlsym(handle, name);
        NSDebugLog(@"[SDLHook] hooked SDL_GetWindowFromID -> last-window fallback");
        return (void *)ame_SDL_GetWindowFromID;
    }
    if (strcmp(name, "SDL_StartTextInput") == 0) {
        if (ame_real_StartTextInput == NULL)
            ame_real_StartTextInput =
                (ame_fn_SDL_StartTextInput)amethyst_orig_dlsym(handle, name);
        NSDebugLog(@"[SDLHook] hooked SDL_StartTextInput -> main thread");
        return (void *)ame_SDL_StartTextInput;
    }
    if (strcmp(name, "SDL_StartTextInputWithProperties") == 0) {
        if (ame_real_StartTextInputWithProperties == NULL)
            ame_real_StartTextInputWithProperties =
                (ame_fn_SDL_StartTextInputWithProperties)amethyst_orig_dlsym(handle, name);
        NSDebugLog(@"[SDLHook] hooked SDL_StartTextInputWithProperties -> main thread");
        return (void *)ame_SDL_StartTextInputWithProperties;
    }
    if (strcmp(name, "SDL_StopTextInput") == 0) {
        if (ame_real_StopTextInput == NULL)
            ame_real_StopTextInput =
                (ame_fn_SDL_StopTextInput)amethyst_orig_dlsym(handle, name);
        NSDebugLog(@"[SDLHook] hooked SDL_StopTextInput -> main thread");
        return (void *)ame_SDL_StopTextInput;
    }
    if (strcmp(name, "SDL_SetTextInputArea") == 0) {
        if (ame_real_SetTextInputArea == NULL)
            ame_real_SetTextInputArea =
                (ame_fn_SDL_SetTextInputArea)amethyst_orig_dlsym(handle, name);
        NSDebugLog(@"[SDLHook] hooked SDL_SetTextInputArea -> main thread");
        return (void *)ame_SDL_SetTextInputArea;
    }
    if (strcmp(name, "SDL_InitSubSystem") == 0) {
        if (ame_real_InitSubSystem == NULL)
            ame_real_InitSubSystem =
                (ame_fn_SDL_InitSubSystem)amethyst_orig_dlsym(handle, name);
        NSDebugLog(@"[SDLHook] hooked SDL_InitSubSystem -> launcher hints");
        return (void *)ame_SDL_InitSubSystem;
    }

    return NULL;
}

#pragma mark - 供 EGL bridge 查询的上下文语义

/// SDL3 路径下，建窗前是否已把 GL profile 强制为 ES（ZL2 的 forceEglProfileEs
/// 在 iOS 上的等价物，见本文件 1)）。
///
/// 仅当本模块接管了 SDL GL 入口（即走 EGL bridge 的转译型渲染器）时才可能为
/// true；GLFW 老路径（MC 26.2 及以下）根本不经过这里，恒为 false，因此
/// MobileGL 在老路径上仍走已验证可用的 desktop GL 3.3 Core 上下文。
bool amethyst_sdl3_wants_gles_context(void) {
    return ame_sdl3WantsGles && ame_glBridgeEnabled();
}
