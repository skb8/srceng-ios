#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>
#import <UIKit/UIKit.h>

#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>

#include "appframework/ilaunchermgr.h"
#include "appframework/ios_metal_surface.h"
#include "tier0/icommandline.h"

static void fail(const char *message)
{
    fprintf(stderr, "%s\n", message);
    exit(1);
}

@interface SourceMetalWindowProbe : UIResponder <UIApplicationDelegate>
@end

@implementation SourceMetalWindowProbe

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options
{
    dispatch_async(dispatch_get_main_queue(), ^{
        CommandLine()->CreateCmdLine("SourceMetalWindowProbe -nomousegrab");
        NSURL *moduleURL = [[NSBundle mainBundle].bundleURL
            URLByAppendingPathComponent:@"bin/libioswindow.dylib"];
        void *module = dlopen(moduleURL.fileSystemRepresentation, RTLD_NOW | RTLD_LOCAL);
        if (!module) fail(dlerror());

        auto factory = reinterpret_cast<CreateInterfaceFn>(dlsym(module, "CreateInterface"));
        if (!factory) fail(dlerror());

        auto *window = static_cast<ILauncherMgr *>(factory(SDLMGR_INTERFACE_VERSION, nullptr));
        auto *surface = static_cast<ISourceIOSMetalSurface *>(factory(SOURCE_IOS_METAL_SURFACE_VERSION, nullptr));
        if (!window || !surface || window->Init() != INIT_OK ||
            !window->CreateGameWindow("Source Metal probe", true, 1280, 720)) {
            fail("The Source launcher could not create its iOS window");
        }

        CAMetalLayer *layer = (__bridge CAMetalLayer *)surface->GetMetalLayer();
        if (![layer isKindOfClass:[CAMetalLayer class]]) fail("Source did not create a CAMetalLayer");
        layer.device = MTLCreateSystemDefaultDevice();
        layer.pixelFormat = MTLPixelFormatBGRA8Unorm;
        if (!layer.device) fail("Metal has no device for the Source window");

        dispatch_async(dispatch_get_main_queue(), ^{
            id<CAMetalDrawable> drawable = [layer nextDrawable];
            id<MTLCommandQueue> queue = [layer.device newCommandQueue];
            id<MTLCommandBuffer> commands = [queue commandBuffer];
            if (!drawable || !commands) fail("The Source Metal window did not produce a drawable");

            MTLRenderPassDescriptor *pass = [MTLRenderPassDescriptor renderPassDescriptor];
            pass.colorAttachments[0].texture = drawable.texture;
            pass.colorAttachments[0].loadAction = MTLLoadActionClear;
            pass.colorAttachments[0].storeAction = MTLStoreActionStore;
            pass.colorAttachments[0].clearColor = MTLClearColorMake(0.25, 0.5, 0.75, 1);
            id<MTLRenderCommandEncoder> encoder = [commands renderCommandEncoderWithDescriptor:pass];
            if (!encoder) fail("The Source Metal window could not create a render pass");

            [encoder endEncoding];
            [commands presentDrawable:drawable];
            [commands commit];
            [commands waitUntilCompleted];
            if (commands.status != MTLCommandBufferStatusCompleted) fail("The Metal clear pass failed");

            window->Shutdown();
            if (surface->GetMetalLayer()) fail("Source did not release the window's Metal surface");
            puts("Presented a Metal drawable from the Source window manager");
            fflush(stdout);
            exit(0);
        });
    });
    return YES;
}

@end

int main(int argc, char **argv)
{
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([SourceMetalWindowProbe class]));
    }
}
