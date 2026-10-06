#import "GameSurfaceView.h"
#import "LauncherPreferences.h"
#import "PLProfiles.h"
#import "utils.h"

#include <stdlib.h>

@interface GameSurfaceView()
@end

@implementation GameSurfaceView

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    self.layer.drawsAsynchronously = YES;
    self.layer.opaque = YES;

    return self;
}

+ (Class)layerClass {
    /* Always CAMetalLayer-backed.
     *
     * This is deliberately unconditional. +layerClass runs when UIKit
     * instantiates the view (SurfaceViewController.viewDidLoad), which is
     * before JavaLauncher sets AMETHYST_KOPPER_PRESENT and before the
     * renderer is even known - an env/ renderer check here reads stale state
     * and produced a plain CALayer, on which MoltenVK aborts with
     * "-[CALayer naturalDrawableSizeMVK]: unrecognized selector".
     *
     * CAMetalLayer is a CALayer subclass, so the OSMesa bridge's
     * `layer.contents = CGImage` upload behaves exactly as before, and the
     * Vulkan and Kopper paths get the Metal drawable they require. */
    return CAMetalLayer.class;
}

@end
