/*
 * Stub override for org.lwjgl.sdl.SDLVideo, tailored for Amethyst iOS.
 *
 * Same strategy as the existing GLFW.java stub: no real libSDL3 is loaded.
 * Window creation and GL context lifecycle delegate to the app's native bridge
 * through the same pojav* symbol set used by org.lwjgl.glfw.GLFW. This makes
 * Minecraft 26.3-snapshot-4+ (org.lwjgl.sdl) able to create its window and GL
 * context on iOS while reusing the proven EGL/rolling-trace plumbing.
 */
package org.lwjgl.sdl;

import java.nio.ByteBuffer;
import java.nio.IntBuffer;

import javax.annotation.Nullable;

import org.lwjgl.system.*;
import org.lwjgl.system.macosx.*;
import org.lwjgl.system.MemoryStack;

import static org.lwjgl.system.JNI.*;
import static org.lwjgl.system.APIUtil.*;
import static org.lwjgl.system.Checks.*;
import static org.lwjgl.system.MemoryUtil.*;

public class SDLVideo {

    public static final long SDL_WINDOW_FULLSCREEN        = 0x00000001L;
    public static final long SDL_WINDOW_OPENGL            = 0x00000002L;
    public static final long SDL_WINDOW_OCCLUDED          = 0x00000004L;
    public static final long SDL_WINDOW_HIDDEN            = 0x00000008L;
    public static final long SDL_WINDOW_BORDERLESS        = 0x00000010L;
    public static final long SDL_WINDOW_RESIZABLE         = 0x00000020L;
    public static final long SDL_WINDOW_MINIMIZED         = 0x00000040L;
    public static final long SDL_WINDOW_MAXIMIZED         = 0x00000080L;
    public static final long SDL_WINDOW_MOUSE_GRABBED     = 0x00000100L;
    public static final long SDL_WINDOW_INPUT_FOCUS       = 0x00000200L;
    public static final long SDL_WINDOW_MOUSE_FOCUS       = 0x00000400L;
    public static final long SDL_WINDOW_EXTERNAL          = 0x00000800L;
    public static final long SDL_WINDOW_MODAL             = 0x00001000L;
    public static final long SDL_WINDOW_HIGH_PIXEL_DENSITY = 0x00002000L;
    public static final long SDL_WINDOW_MOUSE_CAPTURE     = 0x00004000L;
    public static final long SDL_WINDOW_MOUSE_RELATIVE_MODE = 0x00008000L;
    public static final long SDL_WINDOW_ALWAYS_ON_TOP     = 0x00010000L;
    public static final long SDL_WINDOW_UTILITY           = 0x00020000L;
    public static final long SDL_WINDOW_TOOLTIP           = 0x00040000L;
    public static final long SDL_WINDOW_POPUP_MENU        = 0x00080000L;
    public static final long SDL_WINDOW_KEYBOARD_GRABBED  = 0x00100000L;
    public static final long SDL_WINDOW_FILL_DOCUMENT     = 0x00200000L;
    public static final long SDL_WINDOW_VULKAN            = 0x10000000L;
    public static final long SDL_WINDOW_METAL             = 0x20000000L;
    public static final long SDL_WINDOW_TRANSPARENT       = 0x40000000L;
    public static final long SDL_WINDOW_NOT_FOCUSABLE     = 0x80000000L;

    public static final int SDL_WINDOWPOS_UNDEFINED_MASK = 0x1FFF0000;
    public static final int SDL_WINDOWPOS_UNDEFINED       = 0x1FFF0000;
    public static final int SDL_WINDOWPOS_CENTERED_MASK   = 0x2FFF0000;
    public static final int SDL_WINDOWPOS_CENTERED        = 0x2FFF0000;

    /** GL attributes (subset needed by MC). Values match SDL3 gl.h constants. */
    public static final int SDL_GL_RED_SIZE           = 0;
    public static final int SDL_GL_GREEN_SIZE         = 1;
    public static final int SDL_GL_BLUE_SIZE          = 2;
    public static final int SDL_GL_ALPHA_SIZE         = 3;
    public static final int SDL_GL_DOUBLEBUFFER       = 5;
    public static final int SDL_GL_DEPTH_SIZE         = 6;
    public static final int SDL_GL_STENCIL_SIZE       = 7;
    public static final int SDL_GL_MULTISAMPLEBUFFERS = 13;
    public static final int SDL_GL_MULTISAMPLESAMPLES = 14;
    public static final int SDL_GL_ACCELERATED_VISUAL = 15;
    public static final int SDL_GL_RETAINED_BACKING   = 16;
    public static final int SDL_GL_CONTEXT_MAJOR_VERSION = 17;
    public static final int SDL_GL_CONTEXT_MINOR_VERSION = 18;
    public static final int SDL_GL_CONTEXT_FLAGS      = 19;
    public static final int SDL_GL_CONTEXT_PROFILE_MASK = 20;
    public static final int SDL_GL_SHARE_WITH_CURRENT_CONTEXT = 22;
    public static final int SDL_GL_FRAMEBUFFER_SRGB_CAPABLE = 23;
    public static final int SDL_GL_CONTEXT_RELEASE_BEHAVIOR = 25;
    public static final int SDL_GL_CONTEXT_RESET_NOTIFICATION = 26;
    public static final int SDL_GL_CONTEXT_NO_ERROR    = 27;

    public static final int SDL_GL_CONTEXT_PROFILE_CORE          = 0x0001;
    public static final int SDL_GL_CONTEXT_PROFILE_COMPATIBILITY = 0x0002;
    public static final int SDL_GL_CONTEXT_PROFILE_ES            = 0x0004;
    public static final int SDL_GL_CONTEXT_DEBUG_FLAG            = 0x0001;
    public static final int SDL_GL_CONTEXT_FORWARD_COMPATIBLE_FLAG = 0x0002;

    protected SDLVideo() {
        throw new UnsupportedOperationException();
    }

    /** Single active SDL window/context, mirroring GLFW stub's mainContext. */
    private static long s_window = 0L;

    // ------------------------------------------------------------------
    // Native bridge (same AngelAuraAmethyst dylib symbols GLFW.java uses)
    // ------------------------------------------------------------------
    static {
        try {
            System.load(System.getenv("BUNDLE_PATH") + "/AngelAuraAmethyst");
        } catch (UnsatisfiedLinkError e) {
            e.printStackTrace();
        }
    }

    private static final SharedLibrary SDL = new MacOSXLibraryDL("AngelAuraAmethyst", DynamicLinkLoader.RTLD_DEFAULT);

    public static final class Functions {
        private Functions() {}
        public static final long
            CreateContext     = apiGetFunctionAddress(SDL, "pojavCreateContext"),
            GetCurrentContext = apiGetFunctionAddress(SDL, "pojavGetCurrentContext"),
            MakeCurrent       = apiGetFunctionAddress(SDL, "pojavMakeCurrent"),
            SwapBuffers       = apiGetFunctionAddress(SDL, "pojavSwapBuffers"),
            SwapInterval      = apiGetFunctionAddress(SDL, "pojavSwapInterval"),
            SetWindowHint     = apiGetFunctionAddress(SDL, "pojavSetWindowHint");
    }

    // ------------------------------------------------------------------
    // Window creation / destruction
    // ------------------------------------------------------------------

    /** Create window backed by a real EGL context, like glfwCreateWindow. */
    @NativeType("SDL_Window *")
    public static long SDL_CreateWindow(@NativeType("const char *") CharSequence title, int w, int h, @NativeType("SDL_WindowFlags") long flags) {
        return nSDL_CreateWindow(memAddress(memUTF8(title)), w, h, flags);
    }

    public static long nSDL_CreateWindow(long titlePtr, int w, int h, @NativeType("SDL_WindowFlags") long flags) {
        long ptr = invokePP(0L, Functions.CreateContext);
        if (ptr == 0L) return 0L;
        s_window = ptr;
        return ptr;
    }

    public static void SDL_DestroyWindow(@NativeType("SDL_Window *") long window) {
        if (s_window == window) s_window = 0L;
    }

    // ------------------------------------------------------------------
    // Window state (stub: iOS drives the window via SurfaceViewController)
    // ------------------------------------------------------------------

    public static boolean SDL_SetWindowTitle(@NativeType("SDL_Window *") long window, @NativeType("const char *") CharSequence title) {
        return true;
    }

    public static String SDL_GetWindowTitle(@NativeType("SDL_Window *") long window) {
        return "";
    }

    public static boolean SDL_ShowWindow(@NativeType("SDL_Window *") long window) {
        return true;
    }

    public static boolean SDL_HideWindow(@NativeType("SDL_Window *") long window) {
        return true;
    }

    public static boolean SDL_RaiseWindow(@NativeType("SDL_Window *") long window) {
        return true;
    }

    public static boolean SDL_SetWindowSize(@NativeType("SDL_Window *") long window, int w, int h) {
        return true;
    }

    public static boolean SDL_GetWindowSize(@NativeType("SDL_Window *") long window, @Nullable @NativeType("int *") IntBuffer w, @Nullable @NativeType("int *") IntBuffer h) {
        int[] size = parsedWindowSize();
        if (w != null) w.put(0, size[0]);
        if (h != null) h.put(0, size[1]);
        return true;
    }

    public static boolean SDL_GetWindowSizeInPixels(@NativeType("SDL_Window *") long window, @Nullable @NativeType("int *") IntBuffer w, @Nullable @NativeType("int *") IntBuffer h) {
        long[] size = parsedPixelSize();
        if (w != null) w.put(0, (int) size[0]);
        if (h != null) h.put(0, (int) size[1]);
        return true;
    }

    @NativeType("SDL_WindowFlags")
    public static long SDL_GetWindowFlags(@NativeType("SDL_Window *") long window) {
        return SDL_WINDOW_OPENGL | SDL_WINDOW_RESIZABLE | SDL_WINDOW_HIGH_PIXEL_DENSITY;
    }

    public static boolean SDL_SetWindowFullscreen(@NativeType("SDL_Window *") long window, @NativeType("bool") boolean fullscreen) {
        return true;
    }

    public static boolean SDL_SetWindowMouseGrab(@NativeType("SDL_Window *") long window, @NativeType("bool") boolean grabbed) {
        org.lwjgl.glfw.CallbackBridge.nativeSetGrabbing(grabbed);
        return true;
    }

    public static boolean SDL_SetWindowKeyboardGrab(@NativeType("SDL_Window *") long window, @NativeType("bool") boolean grabbed) {
        return true;
    }

    @NativeType("SDL_Window *")
    public static long SDL_GetGrabbedWindow() {
        return s_window;
    }

    /** Package-visible accessor for SDLEvents. */
    static long windowAddress() {
        return s_window;
    }

    /** Package-visible accessor for SDLEvents (logical points). */
    static int[] publicWindowSize() {
        return parsedWindowSize();
    }

    public static boolean SDL_WindowHasSurface(@NativeType("SDL_Window *") long window) {
        return true;
    }

    // ------------------------------------------------------------------
    // GL context management (delegate to pojav* bridge)
    // ------------------------------------------------------------------

    public static void SDL_GL_ResetAttributes() {
    }

    public static boolean SDL_GL_SetAttribute(@NativeType("SDL_GLAttr") int attr, int value) {
        return true;
    }

    public static boolean SDL_GL_GetAttribute(@NativeType("SDL_GLAttr") int attr, @Nullable @NativeType("int *") IntBuffer value) {
        if (value != null) {
            if (attr == SDL_GL_CONTEXT_MAJOR_VERSION) value.put(0, 3);
            else if (attr == SDL_GL_CONTEXT_MINOR_VERSION) value.put(0, 2);
            else value.put(0, 0);
        }
        return true;
    }

    @NativeType("SDL_GLContext")
    public static long SDL_GL_CreateContext(@NativeType("SDL_Window *") long window) {
        return invokePP(0L, Functions.CreateContext);
    }

    public static boolean SDL_GL_MakeCurrent(@NativeType("SDL_Window *") long window, @NativeType("SDL_GLContext") long context) {
        invokePV(window, Functions.MakeCurrent);
        return true;
    }

    @NativeType("SDL_GLContext")
    public static long SDL_GL_GetCurrentContext() {
        return invokeP(Functions.GetCurrentContext);
    }

    @NativeType("SDL_Window *")
    public static long SDL_GL_GetCurrentWindow() {
        return s_window;
    }

    public static boolean SDL_GL_SetSwapInterval(int interval) {
        invokeV(interval, Functions.SwapInterval);
        return true;
    }

    @NativeType("bool")
    public static boolean SDL_GL_GetSwapInterval(@Nullable @NativeType("int *") IntBuffer interval) {
        if (interval != null) {
            try {
                double fps = Double.parseDouble(System.getProperty("UIScreen.maximumFramesPerSecond", "60"));
                interval.put(0, fps > 0 ? 1 : 0);
            } catch (Exception e) {
                interval.put(0, 1);
            }
        }
        return true;
    }

    public static float SDL_GetWindowPixelDensity(@NativeType("SDL_Window *") long window) {
        try {
            return (float) Double.parseDouble(System.getProperty("UIScreen.mainScreen.scale", "1.0"));
        } catch (Exception e) {
            return 1.0f;
        }
    }

    public static boolean SDL_GL_SwapWindow(@NativeType("SDL_Window *") long window) {
        invokePV(window, Functions.SwapBuffers);
        return true;
    }

    public static boolean SDL_GL_DestroyContext(@NativeType("SDL_GLContext") long context) {
        return true;
    }

    @NativeType("SDL_FunctionPointer")
    public static long SDL_GL_GetProcAddress(@NativeType("const char *") CharSequence proc) {
        return Functions.CreateContext;
    }

    public static boolean SDL_GL_ExtensionSupported(@NativeType("const char *") CharSequence extension) {
        return true;
    }

    // ------------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------------

    private static int[] parsedWindowSize() {
        String size = System.getProperty("glfw.windowSize", "1280x720");
        String[] parts = size.split("x");
        int w = 1280, h = 720;
        try { w = Integer.parseInt(parts[0]); } catch (Exception ignored) {}
        try { h = parts.length > 1 ? Integer.parseInt(parts[1]) : 720; } catch (Exception ignored) {}
        return new int[]{ w, h };
    }

    private static long[] parsedPixelSize() {
        int[] win = parsedWindowSize();
        double scale = 1.0;
        try {
            scale = Double.parseDouble(System.getProperty("UIScreen.mainScreen.scale", "1.0"));
        } catch (Exception ignored) {}
        return new long[]{ Math.round(win[0] * scale), Math.round(win[1] * scale) };
    }
}