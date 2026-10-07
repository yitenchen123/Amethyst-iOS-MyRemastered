# Zink Kopper on iOS — status and handover notes

Last updated: 2026-10-07 (end of the bring-up session).

## Where things stand

| Item | State |
|---|---|
| Kopper present path (real EGL, no readback) | **Working** — first frame presented, `swapOK=472` |
| GL version for the Kopper renderer | **Fixed** — reports `OpenGL 4.6 (Compatibility Profile)` |
| `libgallium` exporting the `gl*` entry points | **Fixed** — required for LWJGL's dlsym |
| Kopper renderer usable for play | **No** — see "Open red flag" below |
| Vulkan Zink (OSMesa) renderer | Stable, GL 4.6. Use this. |
| voxy on zink | **Not possible** — see below |

### Open red flag: Kopper blanks/red-screens after ~8 s

Device log (Minecraft 1.21.1, iPhone X/A11, commit 7091d15):

```
[RenderDiag] first eglSwapBuffers OK surface=0x1385993d0
[RenderDiag] exit(0) snapshot: swapOK=472 swapFail=0
[RenderDiag] eglSwapBuffers FAILED #1 eglError=0x3008 surface=0x1385993d0
Thread[#1,Render thread]: No context is current or a function that is not
    available in the current context was called.
```

`0x3008` is `EGL_BAD_DISPLAY`. The first ~472 frames present fine, then the
display goes bad and every later GL call complains that no context is current.

Not yet root-caused. Untried leads, in order of likelihood:

1. **Where the EGL display is invalidated.** `gl_terminate()` is the only
   caller of `eglTerminate()`, so check whether something calls
   `br_terminate()` mid-run, or whether the kopper swapchain recreation
   (geometry re-alignment, `Task50`/`Task60` paths in `gl_bridge.m`) leaves the
   display handle stale. The swap counter reaching 472 before the first failure
   is consistent with a one-off event rather than per-frame damage.
2. **kopper vs the launcher's surface bookkeeping.** The launcher owns an EGL
   window surface that kopper does not present through. If anything tears that
   surface down while kopper keeps using its own swapchain, the display can end
   up in the state above.
3. **`eglSwapInterval` on a kopper surface.** `pojavSwapInterval` forwards to
   `eglSwapInterval`; with kopper the present path is the swapchain, so verify
   the call is harmless there.

Suggested instrumentation: log every `eglTerminate` / `eglDestroySurface` /
`eglMakeCurrent(NO_*)` call with a backtrace, plus the display handle value, then
correlate with the frame counter.

## What was fixed along the way

Each of these was a real blocker, found in this order:

1. **Wrong drawable type.** `GameSurfaceView` was `CALayer`-backed on the OSMesa
   renderer, so MoltenVK died on
   `-[CALayer naturalDrawableSizeMVK]: unrecognized selector`. The view is now
   always `CAMetalLayer`-backed (`GameSurfaceView.m`), and the kopper path
   validates the drawable before use (`zink_kopper_present_ios.c`).
2. **Swapchain format.** The code demanded `VK_FORMAT_R8G8B8A8_UNORM`; MoltenVK
   offers `B8G8R8A8_UNORM`. Either is now accepted.
3. **Per-frame surface rebuild loop.** `present_teardown()` cleared the layer,
   so a failed format check retried every frame (1333 log lines in one run).
   The failure is now latched.
4. **No fallback signal.** The app could not tell whether kopper had presented,
   so it stopped uploading frames and showed black. `osmesa.c` exports
   `osmesa_kopper_present_ok_get()` for the app to poll.
5. **`eglChooseConfig` mismatch.** The launcher asked for
   `EGL_WINDOW_BIT|EGL_PBUFFER_BIT` while Mesa's iOS platform registered
   window-only configs, so nothing matched and an assert fired. Both sides
   fixed.
6. **RGBA8 configs on a Metal layer.** `CAMetalLayer` rejects
   `MTLPixelFormatRGBA8Unorm` (110) with `CAMetalLayerInvalid`. The iOS EGL
   platform now registers BGRA8 configs only.
7. **EGL image did not export `gl*`.** LWJGL resolves GL entry points by dlsym
   on the renderer image. Mesa's driver `link_with`'d `libglapi` (the dispatch
   table, exports nothing) instead of `link_whole`-ing `libglapi_bridge` (walk
   `MAPI_TMP_PUBLIC_ENTRIES_NO_HIDDEN`, defines every `gl*`). This was why the
   OSMesa dylib always worked and the EGL one never did. Fixed in
   `src/gallium/targets/dri/meson.build`.
8. **Zink environment not applied to the EGL renderer.** Both
   `JavaLauncher.m` and `ZinkConfig.m` matched only the `libOSMesa` file-name
   prefix, so the kopper renderer never got `MESA_GL_VERSION_OVERRIDE` and
   reported 4.1. Now matched by renderer name.

## voxy: not possible on zink/iOS

```
error: invalid xfb_buffer specified 0 is larger than
       MAX_TRANSFORM_FEEDBACK_BUFFERS - 1 (-1)
  at me.cortex.voxy...Shader$Builder
  -> ExceptionInInitializerError -> crash
```

voxy hard-codes transform feedback. Metal has no equivalent, so MoltenVK
cannot expose `VK_EXT_transform_feedback`, so zink cannot expose TF, and the
shader never compiles.

Android zink works because Android has native Vulkan drivers that implement
`VK_EXT_transform_feedback`; iOS has only the MoltenVK translation layer.

**MobileGL is the workable renderer for voxy** on this device — it implements
its own Vulkan backend and emulates what it needs, and the user's log confirms
voxy loads under it.

Note also: `OPEN GL 4.6` is declared by zink via `MESA_GL_VERSION_OVERRIDE`
regardless of the underlying Vulkan version. MoltenVK 1.2.9 reports Vulkan
1.2.280, so features that genuinely need Vulkan 1.3+ are still absent; the
override only affects the version string. Upgrading the bundled
`libMoltenVK.dylib` (still 1.2.9, 6.66 MB, in
`Natives/resources/Frameworks/`) to 1.4.x gets Vulkan 1.4.357 and a real
capability bump — a device log from a 1.4.3 build showed
`zink Vulkan 1.4(Apple A11 GPU (MOLTENVK))`.

## Frame rate

The 30 fps lock seen in one session is a setting, not a code path:
`video.disable_game_vsync=0` in that log. Turning on the launcher's
"unlock frame rate" switch sets `POJAV_DISABLE_VSYNC=1`, which forces
`eglSwapInterval(0)`; for kopper that selects `VK_PRESENT_MODE_MAILBOX_KHR`
(or IMMEDIATE when advertised) instead of FIFO.

## Repository state

- Mesa fork `yitenchen123/mesa-ios-osmesa`, branch `main` — all of the above
  merged; the EGL/kopper CI job builds and ships dylibs.
- Launcher `yitenchen123/Amethyst-iOS-MyRemastered`, branch `feat/sdl3` —
  renderer wiring, `libEGL.dylib` (merged EGL+GL image), `libEGL.1.dylib`,
  `libgallium-26.3.0-devel.dylib` under `Natives/resources/Frameworks/`.
