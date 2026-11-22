#!/usr/bin/env python3
"""Convert the Shader Model 1–3 bytecode in little-endian Source VCS v6 files."""

import argparse
import bz2
import json
import lzma
import re
import struct
import subprocess
import tempfile
from pathlib import Path


END = 0xFFFFFFFF
MAX_BLOCK = 1 << 17
HEADER = struct.Struct("<7I")
RECORD = struct.Struct("<2I")
WORD = struct.Struct("<I")
VALVE_LZMA_HEADER = struct.Struct("<4sII5s")


def shader_block(codec: int, payload: bytes) -> bytes:
    if codec == 2:
        decoded = payload
    elif codec == 0:
        decoder = bz2.BZ2Decompressor()
        decoded = decoder.decompress(payload, max_length=MAX_BLOCK + 1)
        if not decoder.eof or decoder.unused_data:
            raise ValueError("Incomplete or oversized bzip2 block")
    elif codec == 1:
        magic, size, compressed_size, properties = VALVE_LZMA_HEADER.unpack_from(payload)
        stream = payload[VALVE_LZMA_HEADER.size:]
        if magic != b"LZMA" or size > MAX_BLOCK or compressed_size != len(stream):
            raise ValueError("Invalid Valve LZMA header")
        decoder = lzma.LZMADecompressor(format=lzma.FORMAT_ALONE, memlimit=64 << 20)
        decoded = decoder.decompress(properties + struct.pack("<Q", size) + stream, max_length=MAX_BLOCK + 1)
        if len(decoded) != size:
            raise ValueError("Incorrect LZMA output length")
    else:
        raise ValueError(f"Unsupported block compression {codec}")
    if not 0 < len(decoded) <= MAX_BLOCK:
        raise ValueError("Invalid shader block size")
    return decoded


def dynamic_combos(blob: bytes, dynamic_count: int):
    seen = set()
    offset = 0
    while offset + WORD.size <= len(blob):
        packed_size, = WORD.unpack_from(blob, offset)
        offset += WORD.size
        if packed_size == END:
            if offset != len(blob):
                raise ValueError("Unexpected data after the combo terminator")
            return
        size = packed_size & 0x3FFFFFFF
        end = offset + size
        if not size or end > len(blob):
            raise ValueError("Truncated shader block")
        decoded = shader_block(packed_size >> 30, blob[offset:end])
        offset = end

        cursor = 0
        while cursor < len(decoded):
            index, shader_size = RECORD.unpack_from(decoded, cursor)
            cursor += RECORD.size
            limit = cursor + shader_size
            if (
                index >= dynamic_count or index in seen or shader_size < 8
                or shader_size % 4 or limit > len(decoded)
            ):
                raise ValueError(f"Invalid dynamic shader combo {index}")
            seen.add(index)
            yield index, decoded[cursor:limit]
            cursor = limit
    raise ValueError("Missing combo terminator")


def convert(path: Path, output: Path, translator: Path) -> None:
    data = path.read_bytes()
    version, total, dynamic, flags, centroid, record_count, crc = HEADER.unpack_from(data)
    if version != 6 or record_count < 2 or not dynamic or total % dynamic:
        raise ValueError("Expected a little-endian VCS v6 file with static and dynamic combos")
    record_end = HEADER.size + record_count * RECORD.size
    if record_end + WORD.size > len(data):
        raise ValueError("Truncated static combo table")
    records = list(RECORD.iter_unpack(data[HEADER.size:record_end]))
    alias_count, = WORD.unpack_from(data, record_end)
    alias_start = record_end + WORD.size
    alias_end = alias_start + alias_count * RECORD.size
    if alias_end > len(data):
        raise ValueError("Truncated static combo alias table")

    stored = {index for index, _ in records[:-1]}
    if len(stored) != len(records) - 1 or max(stored) >= total // dynamic:
        raise ValueError("Invalid static combo IDs")
    sentinel, end = records[-1]
    if sentinel != END or end > len(data) or records[0][1] < alias_end:
        raise ValueError("Invalid shader file offsets")
    aliases = dict(RECORD.iter_unpack(data[alias_start:alias_end]))
    for alias, original in aliases.items():
        if alias in stored or alias >= total // dynamic or original not in stored:
            raise ValueError(f"Invalid alias for static combo {alias}")
    if len(aliases) != alias_count:
        raise ValueError("Duplicate static combo aliases")

    stem = re.sub(r"[^a-zA-Z0-9_]", "_", path.stem)
    destination = output / stem
    if destination.exists():
        raise ValueError(f"Output already exists at {destination}")
    entries = []
    with tempfile.TemporaryDirectory(dir=output) as work:
        staging = Path(work) / stem
        staging.mkdir()
        for (static, begin), (_, end) in zip(records, records[1:]):
            if begin >= end:
                raise ValueError(f"Invalid offset for static combo {static}")
            for index, bytecode in dynamic_combos(data[begin:end], dynamic):
                shader_type = WORD.unpack_from(bytecode)[0] >> 16
                if shader_type not in (0xFFFE, 0xFFFF):
                    raise ValueError(f"Static {static}, dynamic {index}: expected a DX9 shader")
                stage = "vertex" if shader_type == 0xFFFE else "fragment"
                name = f"source_{stem}_{static}_{index}"
                result = subprocess.run([translator, name], input=bytecode, capture_output=True)
                if result.returncode != 0:
                    message = result.stderr.decode(errors="replace").strip()
                    raise ValueError(f"Static {static}, dynamic {index}: {message}")
                filename = name + ".metal"
                (staging / filename).write_bytes(result.stdout)
                entries.append({"static": static, "dynamic": index, "stage": stage, "entry": name, "file": filename})
        manifest = {
            "source": path.name, "source_crc32": crc, "flags": flags,
            "centroid_mask": centroid, "dynamic_count": dynamic,
            "static_aliases": aliases, "variants": entries,
        }
        (staging / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
        staging.rename(destination)
    print(f"{path.name}: {len(entries)} variants, {len(aliases)} static aliases")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("translator", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("files", type=Path, nargs="+")
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    for path in args.files:
        try:
            convert(path, args.output, args.translator.resolve())
        except (ValueError, OSError, EOFError, struct.error, lzma.LZMAError) as error:
            parser.exit(1, f"{path}: {error}\n")


if __name__ == "__main__":
    main()
