#!/usr/bin/env python3
"""把 APK 里所有 STORED（未压缩）条目按 4 字节对齐，等价于 `zipalign -f -p 4`。

为什么需要它：Android 的 AssetManager 会 mmap `resources.arsc`，未压缩条目一旦
不是 4 字节对齐，安装时会直接报
`INSTALL_PARSE_FAILED_NOT_APK: Failed to load asset path`。
pad 上的 build-tools 自带 zipalign 是 x86 二进制，arm64 上跑不了
（33.0.1 直接 Illegal instruction，34.0.0 只有个 70 字节的壳），所以用纯 Python 补上。

用法：python3 tools/align_apk.py <in.apk> <out.apk> [alignment]
"""
import struct
import sys
import zlib
import zipfile


def dos_time(dt):
    return (
        (dt[3] << 11) | (dt[4] << 5) | (dt[5] // 2),
        ((dt[0] - 1980) << 9) | (dt[1] << 5) | dt[2],
    )


def align(src, dst, alignment=4):
    zin = zipfile.ZipFile(src)
    out = open(dst, "wb")
    central = []
    for info in zin.infolist():
        name = info.filename.encode("utf-8")
        raw = zin.read(info.filename)
        if info.compress_type == zipfile.ZIP_STORED:
            method, comp = 0, raw
        else:
            method = 8
            c = zlib.compressobj(9, zlib.DEFLATED, -15)
            comp = c.compress(raw) + c.flush()
        crc = zlib.crc32(raw) & 0xFFFFFFFF
        dtime, ddate = dos_time(info.date_time)
        off = out.tell()
        extra = b""
        if method == 0:
            base = (-(off + 30 + len(name))) % alignment
            pad = base if base >= 4 else base + alignment
            # zipalign 用的对齐扩展字段：ID 0xD935，内容就是填充字节
            extra = struct.pack("<HH", 0xD935, pad) + b"\x00" * pad
        out.write(struct.pack(
            "<IHHHHHIIIHH", 0x04034B50, 20, 0, method, dtime, ddate,
            crc, len(comp), len(raw), len(name), len(extra)))
        out.write(name)
        out.write(extra)
        out.write(comp)
        central.append((name, method, dtime, ddate, crc, len(comp), len(raw), off, info))

    cd_off = out.tell()
    for name, method, dtime, ddate, crc, csize, usize, off, info in central:
        out.write(struct.pack(
            "<IHHHHHHIIIHHHHHII", 0x02014B50, 20, 20, 0, method, dtime, ddate,
            crc, csize, usize, len(name), 0, 0, 0, 0, 0, off))
        out.write(name)
    cd_size = out.tell() - cd_off
    out.write(struct.pack(
        "<IHHHHIIH", 0x06054B50, 0, 0, len(central), len(central), cd_size, cd_off, 0))
    out.close()
    return len(central)


if __name__ == "__main__":
    if len(sys.argv) < 3:
        print(__doc__.strip().splitlines()[0])
        sys.exit(2)
    n = align(sys.argv[1], sys.argv[2], int(sys.argv[3]) if len(sys.argv) > 3 else 4)
    print("aligned %d entries -> %s" % (n, sys.argv[2]))
