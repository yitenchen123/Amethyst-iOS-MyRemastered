#import <Foundation/Foundation.h>
#import "SurfaceViewController.h"

#include <dlfcn.h>
#include "environ.h"
#include "utils.h"

#include "bridge_tbl.h"
#include "osm_bridge.h"
#include "osmesa_internal.h"

static osmesa_library handle;

/* Kopper: present straight to the CAMetalLayer instead of the CPU readback. */
static void (*osmesa_kopper_set_layer)(void *) = NULL;
static void *(*osmesa_kopper_find_layer)(void) = NULL;
static BOOL (*osmesa_kopper_present_ok_get)(void) = NULL;
static BOOL kopperActive = NO;
static BOOL kopperLayerSet = NO;

void dlsym_OSMesa() {
    void* dl_handle = dlopen([NSString stringWithFormat:@"@rpath/%s", getenv("AMETHYST_RENDERER")].UTF8String, RTLD_GLOBAL);
    assert(dl_handle);
    handle.OSMesaMakeCurrent = dlsym(dl_handle,"OSMesaMakeCurrent");
    handle.OSMesaGetCurrentContext = dlsym(dl_handle,"OSMesaGetCurrentContext");
    handle.OSMesaCreateContext = dlsym(dl_handle, "OSMesaCreateContext");
    handle.OSMesaDestroyContext = dlsym(dl_handle, "OSMesaDestroyContext");
    handle.OSMesaPixelStore = dlsym(dl_handle,"OSMesaPixelStore");
    handle.glGetString = dlsym(dl_handle,"glGetString");
    handle.glClearColor = dlsym(dl_handle, "glClearColor");
    handle.glClear = dlsym(dl_handle,"glClear");
    handle.glFinish = dlsym(dl_handle, "glFinish");

    /* Optional Kopper hooks (present straight to the CAMetalLayer). */
    osmesa_kopper_set_layer = dlsym(dl_handle, "osmesa_kopper_set_layer");
    osmesa_kopper_find_layer = dlsym(dl_handle, "osmesa_kopper_find_layer");
    osmesa_kopper_present_ok_get = dlsym(dl_handle, "osmesa_kopper_present_ok_get");
    NSLog(@"OSMBridge: kopper hooks set_layer=%p find_layer=%p",
          osmesa_kopper_set_layer, osmesa_kopper_find_layer);
}

bool osm_init() {
    dlsym_OSMesa();

    /* AMETHYST_KOPPER_PRESENT=1 lets Mesa present straight to the layer's
     * Vulkan swapchain and skip the readback. Only engage it when the dylib
     * actually exports the hooks, otherwise we would blank the screen. */
    const char *kopperEnv = getenv("AMETHYST_KOPPER_PRESENT");
    if (kopperEnv && kopperEnv[0] && kopperEnv[0] != '0' &&
        osmesa_kopper_set_layer != NULL) {
        kopperActive = YES;
        NSLog(@"OSMBridge: Kopper unilateral present ENABLED");
    } else {
        kopperActive = NO;
        NSLog(@"OSMBridge: Kopper disabled (env=%s hooks=%p)",
              kopperEnv ? kopperEnv : "(unset)", osmesa_kopper_set_layer);
    }
    return true; // no more specific initialization required
}

osm_render_window_t* osm_init_context(osm_render_window_t* share) {
    osm_render_window_t* render_window = calloc(1, sizeof(osm_render_window_t));
    OSMesaContext context = handle.OSMesaCreateContext(GL_RGBA, share ? share->context : NULL);
    if(!context) {
        NSLog(@"OSMBridge: FAILED to create context");
        free(render_window);
        return NULL;
    }
    render_window->context = context;
    return render_window;
}

void osm_apply_current_ll() {
    if (currentBundle->osm.width == windowWidth && currentBundle->osm.height == windowHeight) {
        return;
    }

    currentBundle->osm.width = windowWidth;
    currentBundle->osm.height = windowHeight;
    currentBundle->osm.buffer = reallocf(currentBundle->osm.buffer, windowWidth * windowHeight * 4);

    handle.OSMesaMakeCurrent(currentBundle->osm.context, currentBundle->osm.buffer, GL_UNSIGNED_BYTE, currentBundle->osm.width, currentBundle->osm.height);
    handle.OSMesaPixelStore(OSMESA_ROW_LENGTH, currentBundle->osm.width);
    handle.OSMesaPixelStore(OSMESA_Y_UP, 0);
}

void osm_make_current(osm_render_window_t* bundle) {
    if(!bundle) {
        free(currentBundle->osm.buffer);
        CGColorSpaceRelease(currentBundle->osm.color_space);
        currentBundle->osm.buffer = NULL;
        currentBundle->osm.color_space = NULL;
        currentBundle->osm.width = currentBundle->osm.height = 0;
        currentBundle = NULL;
        //technically this does nothing as its not possible to unbind a context in OSMesa
        handle.OSMesaMakeCurrent(NULL, NULL, 0, 0, 0);
        return;
    }

    currentBundle = (basic_render_window_t *)bundle;
    currentBundle->osm.color_space = CGColorSpaceCreateDeviceRGB();
    osm_apply_current_ll();
}

void osm_swap_buffers() {
    osm_apply_current_ll();

    if (kopperActive && osmesa_kopper_set_layer != NULL) {
        /* kopperActive is only set once the dylib exports the hooks, so this
         * is safe to call from the render thread: Mesa guards the layer
         * handoff internally, and a NULL layer just clears it. */
        if (!kopperLayerSet) {
            void *layer = (__bridge void *)SurfaceViewController.surface.layer;
            if (layer != NULL) {
                osmesa_kopper_set_layer(layer);
                kopperLayerSet = YES;
                NSLog(@"OSMBridge: handed CAMetalLayer %p to Mesa", layer);
            }
        }
        if (kopperLayerSet) {
            /* glFinish drives Mesa's flush_front, which presents through
             * kopper when it can. Only skip the CGImage upload if it
             * actually did - otherwise the frame would never reach the
             * screen (the readback went into the CPU buffer and nothing
             * displays it). */
            handle.glFinish();
            BOOL presented = osmesa_kopper_present_ok_get
                ? osmesa_kopper_present_ok_get() : YES;
            static BOOL warnedNoPresent = NO;
            if (!presented && !warnedNoPresent) {
                warnedNoPresent = YES;
                NSLog(@"OSMBridge: kopper did not present (falling back to "
                      @"CGImage upload; is the swapchain format usable?)");
            }
            if (presented)
                return;
        }
    }

    handle.glFinish(); // this will force osmesa to write the last rendered image into the buffer
    osm_render_window_t bundle = currentBundle->osm;
    dispatch_async(dispatch_get_main_queue(), ^{
    CGDataProviderRef bitmapProvider = CGDataProviderCreateWithData(NULL, bundle.buffer, windowWidth * windowHeight * 4, NULL);
    CGImageRef bitmap = CGImageCreate(windowWidth, windowHeight, 8, 32, 4 * windowWidth, bundle.color_space, kCGImageAlphaNoneSkipLast | kCGBitmapByteOrderDefault, bitmapProvider, NULL, FALSE, kCGRenderingIntentDefault);
    SurfaceViewController.surface.layer.contents = (__bridge id)bitmap;
    CGImageRelease(bitmap);
    CGDataProviderRelease(bitmapProvider);
    });
}

void osm_swap_interval(int swapInterval) {
    // Nothing to do here
}

void osm_terminate() {
    // Nothing to do here
}

void set_osm_bridge_tbl() {
    br_init = osm_init;
    br_init_context = (br_init_context_t) osm_init_context;
    br_make_current = (br_make_current_t) osm_make_current;
    br_swap_buffers = osm_swap_buffers;
    br_swap_interval = osm_swap_interval;
    br_terminate = osm_terminate;
}
