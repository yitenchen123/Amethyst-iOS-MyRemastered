#import <Foundation/Foundation.h>
#import "SurfaceViewController.h"

#include <dlfcn.h>
#include "bridge_tbl.h"
#include "environ.h"
#include "gl_bridge.h"
#include <string.h>
#include "utils.h"

static EGLDisplay g_EglDisplay;
static egl_library handle;

// Load one EGL entry point, logging (instead of silently accepting) a NULL result.
// A NULL function pointer here means the next call through it segfaults, so we
// want it visible in the log rather than discovered as a crash later on.
#define MG_LOAD_EGL(sym) do {                                              \
        handle.sym = dlsym(dl_handle, #sym);                               \
        if (handle.sym == NULL) {                                          \
            missing++;                                                     \
            NSDebugLog(@"EGLBridge: missing EGL entry point: %s", #sym);   \
        }                                                                  \
    } while (0)

// Resolve the EGL entry points from whichever library actually provides them.
//
// Historically this hard-coded libtinygl4angle.dylib, which meant every renderer
// that routes through the GL bridge (gl4es, mg, MobileGL, mithril) ended up
// loading ANGLE regardless of what the user selected.  We now honour
// AMETHYST_RENDERER first and only fall back to the ANGLE names.
void dlsym_EGL() {
    void* dl_handle = NULL;
    int missing = 0;
    const char* renderer = getenv("AMETHYST_RENDERER");

    // 1) The renderer the launcher actually selected.  MobileGL and mithril
    //    export the full EGL entry point set themselves, so no ANGLE hop needed.
    if (renderer != NULL && renderer[0] != '\0' &&
        strcmp(renderer, RENDERER_NAME_VK_ZINK) != 0) {
        NSString* path = [NSString stringWithFormat:@"@rpath/%s", renderer];
        dl_handle = dlopen(path.UTF8String, RTLD_GLOBAL);
        if (dl_handle != NULL) {
            NSDebugLog(@"EGLBridge: resolved EGL via renderer '%s'", renderer);
        } else {
            NSDebugLog(@"EGLBridge: renderer '%s' exposes no EGL, falling back (%s)",
                       renderer, dlerror());
        }
    }

    // 2) ANGLE as a dylib (the historical behaviour).
    if (dl_handle == NULL) {
        dl_handle = dlopen("@rpath/libtinygl4angle.dylib", RTLD_GLOBAL);
        if (dl_handle != NULL) NSDebugLog(@"EGLBridge: resolved EGL via libtinygl4angle.dylib");
    }

    // 3) ANGLE shipped as frameworks (libEGL.framework / libGLESv2.framework).
    if (dl_handle == NULL) {
        dl_handle = dlopen("@rpath/libEGL.framework/libEGL", RTLD_GLOBAL);
        if (dl_handle != NULL) NSDebugLog(@"EGLBridge: resolved EGL via libEGL.framework");
    }

    if (dl_handle == NULL) {
        NSDebugLog(@"EGLBridge: FATAL - no EGL provider found (%s)", dlerror());
        assert(dl_handle);
        return;
    }

    MG_LOAD_EGL(eglBindAPI);
    MG_LOAD_EGL(eglChooseConfig);
    MG_LOAD_EGL(eglCreateContext);
    MG_LOAD_EGL(eglCreateWindowSurface);
    MG_LOAD_EGL(eglDestroyContext);
    MG_LOAD_EGL(eglDestroySurface);
    MG_LOAD_EGL(eglGetConfigAttrib);
    MG_LOAD_EGL(eglGetCurrentContext);
    MG_LOAD_EGL(eglGetDisplay);
    MG_LOAD_EGL(eglGetError);
    MG_LOAD_EGL(eglGetPlatformDisplay);
    MG_LOAD_EGL(eglInitialize);
    MG_LOAD_EGL(eglMakeCurrent);
    MG_LOAD_EGL(eglSwapBuffers);
    MG_LOAD_EGL(eglReleaseThread);
    MG_LOAD_EGL(eglSwapInterval);
    MG_LOAD_EGL(eglTerminate);
    MG_LOAD_EGL(eglGetCurrentSurface);

    if (missing > 0) {
        NSDebugLog(@"EGLBridge: WARNING - %d EGL entry point(s) unresolved", missing);
    }
}
#undef MG_LOAD_EGL

static bool gl_init() {
    dlsym_EGL();

    g_EglDisplay = handle.eglGetDisplay(EGL_DEFAULT_DISPLAY);
    if (g_EglDisplay == EGL_NO_DISPLAY) {
        NSDebugLog(@"EGLBridge: eglGetDisplay(EGL_DEFAULT_DISPLAY) returned EGL_NO_DISPLAY");
        return false;
    }
    if (!handle.eglInitialize(g_EglDisplay, NULL, NULL)) {
        NSDebugLog(@"EGLBridge: Error eglInitialize() failed: 0x%x", handle.eglGetError());
        return false;
    }
    return true;
}

gl_render_window_t* gl_init_context(gl_render_window_t *share) {
    gl_render_window_t* bundle = calloc(1, sizeof(gl_render_window_t));

    NSString *renderer = NSProcessInfo.processInfo.environment[@"AMETHYST_RENDERER"];
    BOOL angleDesktopGL = [renderer isEqualToString:@ RENDERER_NAME_MTL_ANGLE];

    const EGLint attribs[] = {
        EGL_RED_SIZE, 8,
        EGL_GREEN_SIZE, 8,
        EGL_BLUE_SIZE, 8,
        EGL_ALPHA_SIZE, 8,
        EGL_DEPTH_SIZE, 24,
        EGL_SURFACE_TYPE, EGL_WINDOW_BIT|EGL_PBUFFER_BIT,
        EGL_RENDERABLE_TYPE, angleDesktopGL ? EGL_OPENGL_BIT : EGL_OPENGL_ES3_BIT,
        EGL_NONE
    };

    EGLint num_configs;
    EGLint vid;
    if (!handle.eglChooseConfig(g_EglDisplay, attribs, &bundle->config, 1, &num_configs)) {
        NSDebugLog(@"EGLBridge: Error couldn't get an EGL visual config: 0x%x", handle.eglGetError());
        free(bundle);
        return NULL;
    }
    assert(bundle->config);
    assert(num_configs > 0);

    if (!handle.eglGetConfigAttrib(g_EglDisplay, bundle->config, EGL_NATIVE_VISUAL_ID, &vid)) {
        NSDebugLog(@"EGLBridge: Error eglGetConfigAttrib() failed: 0x%x", handle.eglGetError());
        free(bundle);
        return NULL;
    }

    EGLBoolean bindResult;
    if (angleDesktopGL) {
        NSDebugLog(@"EGLBridge: Binding to desktop OpenGL");
        bindResult = handle.eglBindAPI(EGL_OPENGL_API);
    } else {
        NSDebugLog(@"EGLBridge: Binding to OpenGL ES");
        bindResult = handle.eglBindAPI(EGL_OPENGL_ES_API);
    }
    if (!bindResult) NSDebugLog(@"EGLBridge: bind failed: %p\n", handle.eglGetError());

    bundle->surface = handle.eglCreateWindowSurface(g_EglDisplay, bundle->config, (__bridge EGLNativeWindowType)SurfaceViewController.surface.layer, NULL);
    if (!bundle->surface) {
        NSDebugLog(@"EGLBridge: eglCreateWindowSurface finished with error: 0x%x", handle.eglGetError());
        free(bundle);
        return NULL;
    }

    const EGLint ctx_attribs[] = {
        EGL_CONTEXT_CLIENT_VERSION, 3,
        EGL_NONE
    };
    bundle->context = handle.eglCreateContext(g_EglDisplay, bundle->config, share ? share->context : EGL_NO_CONTEXT, ctx_attribs);
    if (!bundle->context) {
        NSDebugLog(@"EGLBridge: Error eglCreateContext finished with error: 0x%x", handle.eglGetError());
        free(bundle);
        return NULL;
    }
    //NSDebugLog(@"EGLBridge: Created CTX pointer = %p (source = %p)", bundle->context, share?share->context:0);

    return bundle;
}

void gl_make_current(gl_render_window_t* bundle) {
    if(!bundle) {
        if(handle.eglMakeCurrent(g_EglDisplay, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT)) {
            currentBundle = NULL;
        }
        return;
    }

    if(handle.eglMakeCurrent(g_EglDisplay, bundle->surface, bundle->surface, bundle->context)) {
        currentBundle = (basic_render_window_t *)bundle;
    } else {
        NSLog(@"EGLBridge: eglMakeCurrent returned with error: 0x%x", handle.eglGetError());
    }
}

void gl_swap_buffers() {
    if (!handle.eglSwapBuffers(g_EglDisplay, currentBundle->gl.surface) && handle.eglGetError() == EGL_BAD_SURFACE) {
        NSLog(@"eglSwapBuffers error 0x%x", handle.eglGetError());
        //stopSwapBuffers = true;
        //closeGLFWWindow();
    }
}

void gl_swap_interval(int swapInterval) {
    handle.eglSwapInterval(g_EglDisplay, swapInterval);
}

void gl_terminate() {
    handle.eglMakeCurrent(g_EglDisplay, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
    handle.eglDestroySurface(g_EglDisplay, currentBundle->gl.surface);
    handle.eglDestroyContext(g_EglDisplay, currentBundle->gl.context);
    handle.eglTerminate(g_EglDisplay);
    handle.eglReleaseThread();
    free(currentBundle);
    currentBundle = nil;
}

void set_gl_bridge_tbl() {
    br_init = gl_init;
    br_init_context = (br_init_context_t) gl_init_context;
    br_make_current = (br_make_current_t) gl_make_current;
    br_swap_buffers = gl_swap_buffers;
    br_swap_interval = gl_swap_interval;
    br_terminate = gl_terminate;
}
