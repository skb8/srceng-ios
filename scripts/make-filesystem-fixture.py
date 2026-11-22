"""Create a minimal Source gameinfo.txt and a VPK with one embedded file."""

import argparse
import struct
import zlib
from pathlib import Path


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("game_directory", type=Path)
    parser.add_argument("--version", type=int, choices=(1, 2), required=True)
    args = parser.parse_args()
    game_dir = args.game_directory
    game_dir.mkdir(parents=True, exist_ok=True)

    gameinfo = '''"GameInfo"
{
    "game" "Source iOS filesystem fixture"
    "FileSystem"
    {
        "SearchPaths"
        {
            "Game" "|gameinfo_path|fixture_dir.vpk"
        }
    }
}
'''
    (game_dir / "gameinfo.txt").write_text(gameinfo, encoding="utf-8")

    payload = b"Source iOS filesystem probe\n"
    embedded_archive_index = 0x7FFF
    entry = struct.pack("<IHHIIH", zlib.crc32(payload), 0, embedded_archive_index, 0, len(payload), 0xFFFF)
    tree = b"txt\0sourceios\0probe\0" + entry + b"\0\0\0"
    header = struct.pack("<III", 0x55AA1234, args.version, len(tree))
    if args.version == 2:
        header += struct.pack("<4I", len(payload), 0, 0, 0)
    (game_dir / "fixture_dir.vpk").write_bytes(header + tree + payload)


if __name__ == "__main__":
    main()
