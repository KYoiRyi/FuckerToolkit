import struct
import sys


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: check_macho_header.py <macho>", file=sys.stderr)
        return 2

    with open(sys.argv[1], "rb") as handle:
        data = handle.read()

    magic = struct.unpack_from("<I", data, 0)[0]
    if magic != 0xFEEDFACF:
        print(f"unexpected Mach-O magic: 0x{magic:x}", file=sys.stderr)
        return 1

    _, _, _, _, ncmds, sizeofcmds, _, _ = struct.unpack_from("<IiiIIIII", data, 0)
    load_end = 32 + sizeofcmds
    off = 32
    min_section = len(data)

    for _ in range(ncmds):
        cmd, cmdsize = struct.unpack_from("<II", data, off)
        if cmd == 0x19:
            nsects = struct.unpack_from("<I", data, off + 64)[0]
            sect = off + 72
            for _ in range(nsects):
                section_offset = struct.unpack_from("<I", data, sect + 48)[0]
                if section_offset:
                    min_section = min(min_section, section_offset)
                sect += 80
        off += cmdsize

    if load_end > min_section:
        print(
            f"Mach-O load commands overlap section data: load_end={load_end} min_section={min_section}",
            file=sys.stderr,
        )
        return 1

    print(f"Mach-O header ok: load_end={load_end} min_section={min_section} gap={min_section - load_end}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
