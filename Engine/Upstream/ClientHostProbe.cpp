#include <dlfcn.h>
#include <stdio.h>

#include "engine/ios_client_host.h"
#include "engine_launcher_api.h"
#include "appframework/ilaunchermgr.h"
#include "appframework/ios_metal_surface.h"

static CreateInterfaceFn loadFactory(const char *path)
{
    void *module = dlopen(path, RTLD_NOW | RTLD_LOCAL);
    if (!module) {
        fprintf(stderr, "Failed to load %s: %s\n", path, dlerror());
        return nullptr;
    }

    auto factory = reinterpret_cast<CreateInterfaceFn>(dlsym(module, "CreateInterface"));
    if (!factory) {
        fprintf(stderr, "Failed to resolve CreateInterface in %s: %s\n", path, dlerror());
    }
    return factory;
}

static bool hasInterface(const char *path, const char *version)
{
    CreateInterfaceFn factory = loadFactory(path);
    if (factory && factory(version, nullptr)) {
        printf("Loaded %s\n", version);
        return true;
    }

    fprintf(stderr, "%s did not expose %s\n", path, version);
    return false;
}

int main(int argc, char **argv)
{
    if (argc != 5) {
        fputs("usage: source-client-host-probe libengine libioswindow libclient libserver\n", stderr);
        return 2;
    }

    CreateInterfaceFn factory = loadFactory(argv[1]);
    if (!factory || !factory(VENGINE_LAUNCHER_API_VERSION, nullptr)) {
        fputs("The client host did not expose IEngineAPI\n", stderr);
        return 1;
    }

    auto *host = static_cast<ISourceIOSClientHost *>(factory(SOURCE_IOS_CLIENT_HOST_VERSION, nullptr));
    if (!host || host->Start() || host->RunFrame()) {
        fputs("The iOS frame controller did not reject an uninitialized session\n", stderr);
        return 1;
    }

    host->Stop();
    host->Stop();
    puts("Loaded IEngineAPI and SourceIOSClientHost001");

    factory = loadFactory(argv[2]);
    if (!factory || !factory(SDLMGR_INTERFACE_VERSION, nullptr)) {
        fputs("The window module did not expose the Source launcher interface\n", stderr);
        return 1;
    }

    auto *surface = static_cast<ISourceIOSMetalSurface *>(factory(SOURCE_IOS_METAL_SURFACE_VERSION, nullptr));
    if (!surface || surface->GetMetalLayer()) {
        fputs("The window module did not expose an inactive Metal surface\n", stderr);
        return 1;
    }
    puts("Loaded SDLMgrInterface001 and SourceIOSMetalSurface001");

    // From cdll_int.h and eiface.h in the pinned Source revision.
    return hasInterface(argv[3], "VClient017") && hasInterface(argv[4], "ServerGameDLL010") ? 0 : 1;
}
