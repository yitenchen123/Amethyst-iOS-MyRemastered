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
    NSString *renderer = [PLProfiles resolveKeyForCurrentProfile:@"renderer"];

    /* Kopper: Mesa presents straight to a CAMetalLayer-backed Vulkan
     * swapchain, so the view must be CAMetalLayer-backed even on the OSMesa
     * renderer. Opt-in via AMETHYST_KOPPER_PRESENT so the plain CALayer +
     * CGImage path stays the default when it is off. */
    const char *kopperEnv = getenv("AMETHYST_KOPPER_PRESENT");
    if (kopperEnv && kopperEnv[0] && kopperEnv[0] != '0') {
        return CAMetalLayer.class;
    }

    if ([renderer hasPrefix:@"libOSMesa"]) {
        return CALayer.class;
    } else if ([renderer isEqualToString:@ RENDERER_NAME_VULKAN]) {
        // MoltenVK needs a CAMetalLayer-backed surface directly.
        return CAMetalLayer.class;
    } else {
        return CAMetalLayer.class;
    }
}

@end
