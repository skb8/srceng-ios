#include <cstdio>
#include <cstring>

#include "appframework/IAppSystemGroup.h"
#include "filesystem.h"
#include "filesystem_init.h"
#include "tier0/icommandline.h"
#include "tier1/utlbuffer.h"
#include "vstdlib/cvar.h"

namespace
{
class FilesystemProbe final : public CAppSystemGroup
{
public:
    explicit FilesystemProbe(const char *gamePath) : m_GamePath(gamePath) {}

    bool Create() override
    {
        const AppModule_t module = LoadModule(VStdLib_GetICVarFactory());
        if (!AddSystem(module, CVAR_INTERFACE_VERSION))
            return false;

        m_Filesystem = static_cast<IFileSystem *>(AddSystem(module, FILESYSTEM_INTERFACE_VERSION));
        return m_Filesystem != nullptr;
    }

    bool PreInit() override { return true; }
    void PostShutdown() override {}
    void Destroy() override { m_Filesystem = nullptr; }

    int Main() override
    {
        FileSystem_UseVProjectBinDir(true);
        FileSystem_SetErrorMode(FS_ERRORMODE_NONE);
        CFSSearchPathsInit paths;
        paths.m_pDirectoryName = m_GamePath;
        paths.m_pFileSystem = m_Filesystem;
        if (FileSystem_LoadSearchPaths(paths) != FS_OK)
        {
            std::fprintf(stderr, "Could not mount gameinfo.txt: %s\n", FileSystem_GetLastErrorString());
            return 1;
        }

        CUtlBuffer file;
        constexpr char expected[] = "Source iOS filesystem probe\n";
        if (!m_Filesystem->ReadFile("sourceios/probe.txt", "GAME", file)
            || file.TellPut() != sizeof(expected) - 1
            || std::memcmp(file.Base(), expected, sizeof(expected) - 1) != 0)
        {
            std::fprintf(stderr, "Could not read the probe file from the VPK search path\n");
            return 1;
        }
        std::puts("Mounted gameinfo.txt and read the VPK fixture through IFileSystem.");
        return 0;
    }

private:
    const char *m_GamePath;
    IFileSystem *m_Filesystem = nullptr;
};
}

int main(int argc, char **argv)
{
    if (argc != 2)
    {
        std::fprintf(stderr, "usage: source-filesystem-probe absolute-game-directory\n");
        return 2;
    }

    char vproject[] = "-vproject";
    char noAsync[] = "-noasync";
    char *sourceArgs[] = {argv[0], vproject, argv[1], noAsync};
    CommandLine()->CreateCmdLine(sizeof(sourceArgs) / sizeof(sourceArgs[0]), sourceArgs);
    return FilesystemProbe(argv[1]).Run();
}
