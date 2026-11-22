"""Place a compiled test shader into raw, bzip2, and LZMA Source VCS v6 blocks."""

import bz2
import lzma
import struct
import sys
from pathlib import Path


def main() -> None:
    tokens = Path(sys.argv[1]).read_bytes()
    record = struct.pack("<II", 0, len(tokens)) + tokens
    lzma_alone = lzma.compress(record, format=lzma.FORMAT_ALONE)
    valve_lzma = (
        struct.pack("<4sII", b"LZMA", len(record), len(lzma_alone) - 13)
        + lzma_alone[:5]
        + lzma_alone[13:]
    )
    encoded = [(2, record), (0, bz2.compress(record)), (1, valve_lzma)]
    header = struct.pack("<7I", 6, 4, 1, 0, 0, 4, 0)
    alias = struct.pack("<3I", 1, 3, 0)
    offset = len(header) + len(alias) + 4 * 8
    table = bytearray()
    shaders = bytearray()
    for index, (compression, payload) in enumerate(encoded):
        table.extend(struct.pack("<II", index, offset + len(shaders)))
        shaders.extend(struct.pack("<I", compression << 30 | len(payload)))
        shaders.extend(payload)
        shaders.extend(struct.pack("<I", 0xFFFFFFFF))
    table.extend(struct.pack("<II", 0xFFFFFFFF, offset + len(shaders)))
    Path(sys.argv[2]).write_bytes(header + table + alias + shaders)


if __name__ == "__main__":
    main()
