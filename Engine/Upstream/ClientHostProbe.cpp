#include <dlfcn.h>
#include <stdio.h>

#include "engine/ios_client_host.h"
#include "engine_launcher_api.h"

int main(int argc, char **argv)
{
    if (argc != 2) {
        fputs("usage: source-client-host-probe path-to-libengine\n", stderr);
        return 2;
    }

    void *module = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
    if (!module) {
        fprintf(stderr, "Failed to load the Source client host: %s\n", dlerror());
        return 1;
    }

    auto factory = reinterpret_cast<CreateInterfaceFn>(dlsym(module, "CreateInterface"));
    if (!factory) {
        fprintf(stderr, "Failed to resolve the client host factory: %s\n", dlerror());
        return 1;
    }

    if (!factory(VENGINE_LAUNCHER_API_VERSION, nullptr)) {
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
    return 0;
}
