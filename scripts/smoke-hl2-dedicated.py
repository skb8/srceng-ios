"""Start the original Source host with the HL2 server and a synthetic game directory."""

import argparse
import subprocess
from pathlib import Path


FILES = {
    "gameinfo.txt": '''"GameInfo"
{
    "game" "Source iOS startup fixture"
    "type" "singleplayer_only"
    "FileSystem"
    {
        "SteamAppId" "220"
        "SearchPaths"
        {
            "Game+Mod" "|gameinfo_path|."
            "GameBin" "|gameinfo_path|bin"
        }
    }
}
''',
    "steam.inf": "PatchVersion=1.0.0.0\nProductName=hl2\nappID=220\n",
    "cfg/valve.rc": "stuffcmds\n",
    "scripts/surfaceproperties_manifest.txt": '"surfaceproperties_manifest"\n{\n}\n',
    "scripts/game_sounds_manifest.txt": '"game_sounds_manifest"\n{\n}\n',
    "scripts/soundscapes_manifest.txt": '"soundscapes_manifest"\n{\n}\n',
    "resource/gameevents.res": '"gameevents"\n{\n}\n',
    "resource/hltvevents.res": '"hltvevents"\n{\n    "source_ios_smoke" { "local" "1" }\n}\n',
    "resource/ModEvents.res": '"modevents"\n{\n}\n',
}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("simulator")
    parser.add_argument("runtime", type=Path)
    args = parser.parse_args()

    runtime = args.runtime.resolve(strict=True)
    game = runtime / "hl2"
    for relative, data in FILES.items():
        path = game / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(data, encoding="utf-8")

    marker = "SOURCE_IOS_HOST_READY"
    invocation = [
        "xcrun", "simctl", "spawn", args.simulator, str(runtime / "dedicated_launcher"),
        "-basedir", str(runtime), "-game", "hl2", "-insecure", "-nomaster",
        "-norestart", "-nocrashdialog", "-sv_pure", "0", "+echo", marker, "+quit",
    ]
    try:
        result = subprocess.run(
            invocation, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            text=True, errors="replace", timeout=60,
        )
    except subprocess.TimeoutExpired as error:
        print((error.stdout or b"").decode("utf-8", "replace"), end="")
        raise SystemExit("Source did not terminate after the quit command") from None

    print(result.stdout, end="")
    if result.returncode:
        raise SystemExit(f"Source exited with status {result.returncode}")
    if 'server.dylib loaded for "Half-Life 2"' not in result.stdout:
        raise SystemExit("Source did not load the Half-Life 2 server module")
    if not any(line.strip() == marker for line in result.stdout.splitlines()):
        raise SystemExit("Source did not execute the console command")


if __name__ == "__main__":
    main()
