#include <dlfcn.h>
#include <stdio.h>

typedef void *(*CreateInterfaceFn)(const char *, int *);

int main(int argc, char **argv) {
    if (argc != 2) {
        fputs("usage: source-client-probe path-to-libclient\n", stderr);
        return 2;
    }

    void *module = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
    if (!module) {
        fprintf(stderr, "Failed to load HL2 client: %s\n", dlerror());
        return 1;
    }

    CreateInterfaceFn factory = (CreateInterfaceFn)dlsym(module, "CreateInterface");
    if (!factory) {
        fprintf(stderr, "Failed to resolve the HL2 client factory: %s\n", dlerror());
        dlclose(module);
        return 1;
    }

    // CLIENT_DLL_INTERFACE_VERSION from public/cdll_int.h in the pinned engine.
    int status = 1;
    if (!factory("VClient017", &status) || status != 0) {
        fputs("The HL2 client factory did not expose VClient017\n", stderr);
        dlclose(module);
        return 1;
    }

    puts("Loaded the HL2 client and resolved VClient017");
    dlclose(module);
    return 0;
}
