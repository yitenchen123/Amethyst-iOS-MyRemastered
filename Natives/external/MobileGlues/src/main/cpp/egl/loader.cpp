//
// Created by Swung0x48 on 2024/10/10.
//

#include "loader.h"
#include "../gl/envvars.h"
#include "../gl/log.h"
#include "../gl/mg.h"
#include "../gles/loader.h"
#include "../includes.h"
#include <EGL/egl.h>
#include <string.h>

#define DEBUG 0

static EGLDisplay eglDisplay = EGL_NO_DISPLAY;
static EGLSurface eglSurface = EGL_NO_SURFACE;
static EGLContext eglContext = EGL_NO_CONTEXT;

// EGL 1.5 起才有 EGL_OPENGL_ES3_BIT；老头文件只有 KHR 变体。
#ifndef EGL_OPENGL_ES3_BIT_KHR
#define EGL_OPENGL_ES3_BIT_KHR 0x00000040
#endif

// 临时上下文原先固定为 ES 2.0。但 LWJGL 3.4.x 的 GL.createCapabilities() 与
// MC 26.3 RenderPearl 的 GlBackend.loadLibrary() 都会查询
// glGetIntegerv(GL_MAJOR_VERSION) —— 该枚举在 ES 2.0 上下文下非法，调用后
// 置 GL_INVALID_ENUM：
//   - 26.2(blaze3d)    → "There is no OpenGL context current"
//   - 26.3(RenderPearl)→ "glGetError mismatch" → 回退 Vulkan → shaderc 崩溃
// 两者同因。故优先建 ES 3 临时上下文；宿主不支持时回退 ES 2（原行为）。
//
// 注意：LOAD_EGL 宏把 egl_eglXxx 函数指针声明为「调用点所在作用域」的 static
// 局部变量，因此尝试逻辑必须用 lambda 留在 init_target_egl() 函数体内 ——
// 拆成独立函数会因名字不可见而编译失败。
void init_target_egl() {
  LOAD_EGL(eglGetProcAddress);
  LOAD_EGL(eglBindAPI);
  LOAD_EGL(eglInitialize);
  LOAD_EGL(eglGetDisplay);
  LOAD_EGL(eglCreatePbufferSurface);
  LOAD_EGL(eglDestroySurface);
  LOAD_EGL(eglDestroyContext);
  LOAD_EGL(eglMakeCurrent);
  LOAD_EGL(eglChooseConfig);
  LOAD_EGL(eglCreateContext);
  LOAD_EGL(eglQueryString);
  LOAD_EGL(eglTerminate);
  LOAD_EGL(eglGetError);

  // 防御性检查: 若关键 EGL 函数指针为 NULL (如 ANGLE 框架未正确加载到全局作用域),
  // 直接返回避免空指针解引用崩溃 (SIGSEGV pc=0x0), 而非调用 0x0 地址。
  if (egl_eglGetDisplay == NULL || egl_eglInitialize == NULL ||
      egl_eglBindAPI == NULL || egl_eglChooseConfig == NULL ||
      egl_eglCreateContext == NULL || egl_eglMakeCurrent == NULL ||
      egl_eglCreatePbufferSurface == NULL || egl_eglGetError == NULL) {
    LOG_W_FORCE("init_target_egl: 关键 EGL 函数指针为 NULL, ANGLE 框架可能未正确加载, "
                "中止 EGL 初始化以避免空指针崩溃\n");
    return;
  }

  // 以指定 ES 版本建立临时（pbuffer）上下文，成功返回 true。
  // 该临时上下文有两个用途：解析 EGL/GL 函数指针；以及在真实上下文建立之前
  // 充当进程内唯一的 current 上下文。
  auto tryEsVersion = [&](int esVersion) -> bool {
    EGLDisplay display = EGL_NO_DISPLAY;
    EGLSurface surface = EGL_NO_SURFACE;
    EGLContext context = EGL_NO_CONTEXT;

    EGLint renderableBit =
        (esVersion >= 3) ? EGL_OPENGL_ES3_BIT_KHR : EGL_OPENGL_ES2_BIT;

    EGLint configAttribs[] = {EGL_RED_SIZE,      8,
                              EGL_GREEN_SIZE,    8,
                              EGL_BLUE_SIZE,     8,
                              EGL_ALPHA_SIZE,    8,
                              EGL_SURFACE_TYPE,  EGL_PBUFFER_BIT,
                              EGL_RENDERABLE_TYPE, renderableBit,
                              EGL_NONE};

    EGLint ctxAttribs[] = {EGL_CONTEXT_CLIENT_VERSION, esVersion, EGL_NONE};

    EGLint pbAttribs[] = {EGL_WIDTH, 32, EGL_HEIGHT, 32, EGL_NONE};

    EGLConfig pbufConfig;
    EGLint configsFound = 0;

    display = egl_eglGetDisplay(EGL_DEFAULT_DISPLAY);
    if (display == EGL_NO_DISPLAY) {
      LOG_D("eglGetDisplay failed for ES %d (0x%x)", esVersion, egl_eglGetError());
      goto cleanup;
    }

    if (egl_eglInitialize(display, NULL, NULL) != EGL_TRUE) {
      LOG_D("eglInitialize failed for ES %d (0x%x)", esVersion, egl_eglGetError());
      goto cleanup;
    }

    if (egl_eglBindAPI(EGL_OPENGL_ES_API) != EGL_TRUE) {
      LOG_D("eglBindAPI failed for ES %d (0x%x)", esVersion, egl_eglGetError());
      goto cleanup;
    }

    if (egl_eglChooseConfig(display, configAttribs, &pbufConfig, 1,
                            &configsFound) != EGL_TRUE) {
      LOG_D("eglChooseConfig failed for ES %d (0x%x)", esVersion,
            egl_eglGetError());
      goto cleanup;
    }

    if (configsFound == 0) {
      // 索引 6 是 EGL_ALPHA_SIZE 的键位置，置 0 即截断属性表（丢弃 alpha 要求）
      configAttribs[6] = 0;
      if (egl_eglChooseConfig(display, configAttribs, &pbufConfig, 1,
                              &configsFound) != EGL_TRUE) {
        LOG_D("Retry eglChooseConfig failed for ES %d (0x%x)", esVersion,
              egl_eglGetError());
        goto cleanup;
      }
      if (configsFound == 0) {
        LOG_D("No valid EGL config found for ES %d", esVersion);
        goto cleanup;
      }
      LOG_D("Using config without alpha channel (ES %d)", esVersion);
    }

    context =
        egl_eglCreateContext(display, pbufConfig, EGL_NO_CONTEXT, ctxAttribs);
    if (context == EGL_NO_CONTEXT) {
      LOG_D("eglCreateContext failed for ES %d (0x%x)", esVersion,
            egl_eglGetError());
      goto cleanup;
    }

    surface = egl_eglCreatePbufferSurface(display, pbufConfig, pbAttribs);
    if (surface == EGL_NO_SURFACE) {
      LOG_D("eglCreatePbufferSurface failed for ES %d (0x%x)", esVersion,
            egl_eglGetError());
      goto cleanup;
    }

    if (egl_eglMakeCurrent(display, surface, surface, context) != EGL_TRUE) {
      LOG_D("eglMakeCurrent failed for ES %d (0x%x)", esVersion,
            egl_eglGetError());
      goto cleanup;
    }

    eglDisplay = display;
    eglSurface = surface;
    eglContext = context;
    LOG_V("EGL initialized successfully (temp context ES %d)", esVersion);
    return true;

  cleanup:
    if (surface != EGL_NO_SURFACE) egl_eglDestroySurface(display, surface);
    if (context != EGL_NO_CONTEXT) egl_eglDestroyContext(display, context);
    if (display != EGL_NO_DISPLAY) egl_eglTerminate(display);
    return false;
  };

  if (tryEsVersion(3)) return;

  LOG_W_FORCE("init_target_egl: ES 3 临时上下文不可用, 回退 ES 2 "
              "(glGetIntegerv(GL_MAJOR_VERSION) 将返回 GL_INVALID_ENUM)\n");
  if (tryEsVersion(2)) return;

  LOG_E("EGL initialization failed");
}

void destroy_temp_egl_ctx() {
  LOAD_EGL(eglDestroySurface);
  LOAD_EGL(eglDestroyContext);
  LOAD_EGL(eglMakeCurrent);
  LOAD_EGL(eglTerminate);

  egl_eglMakeCurrent(eglDisplay, 0, 0, EGL_NO_CONTEXT);
  egl_eglDestroySurface(eglDisplay, eglSurface);
  egl_eglDestroyContext(eglDisplay, eglContext);

  egl_eglTerminate(eglDisplay);
}