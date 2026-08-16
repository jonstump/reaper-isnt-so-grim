#!/usr/bin/env python3
# Governing: ADR-0005 (clean room — format derived from inspection and lawful
#            sources only), SPEC-0002 REQ "Clean-Room Format Derivation",
#            SPEC-0002 REQ "Input Immutability"
#
# Dump the project document out of an Audacity .aup3 file.
#
# Development only — this is the tool that verified importer/FORMAT.md's claims
# against real projects, not part of the shipped importer. It exists so the next
# person can re-run the verification instead of trusting the table.
#
#     python3 scripts/dev/aup3_dump.py path/to/project.aup3
#     python3 scripts/dev/aup3_dump.py path/to/project.aup3 --raw
#
# The document lives in two BLOB columns, `dict` and `doc`, of the `project`
# table at row id = 1. They are concatenated in that order and parsed as ONE
# stream: `dict` is almost entirely FT_Name fields that intern tag and attribute
# names against numeric IDs, and `doc` then refers to those IDs. `doc` alone does
# not carry the CharSize field that tells you how wide its strings are, which is
# the practical reason the two cannot be parsed separately.
#
# Nothing here is compressed. The stream is a sequence of fields, each opening
# with a one-byte type tag.
#
# Field widths are NOT uniform, which is the trap in this format:
#   * name IDs are uint16
#   * FT_Name's length is uint16, and counts BYTES not characters
#   * FT_String / FT_Data / FT_Raw lengths are uint32, also bytes
#   * everything is little-endian
#   * FT_CharSize sets bytes-per-character for every later string; 4 (UTF-32LE)
#     on the macOS fixtures, but it is written into the file precisely because it
#     is not fixed across platforms, so it must be read rather than assumed.
#
# Read-only by construction: the database is opened with SQLite's mode=ro URI so
# a write cannot be attempted even by mistake, and no journal file is created
# beside the source. These are irreplaceable projects (SPEC-0002 REQ "Input
# Immutability").

import argparse
import pathlib
import sqlite3
import struct
import sys

# Governing: SPEC-0002 REQ "Clean-Room Format Derivation" — the field-type set
# itself is FORMAT.md claim 16.
FIELD_TYPES = {
    0: "CharSize", 1: "StartTag", 2: "EndTag", 3: "String", 4: "Int",
    5: "Bool", 6: "Long", 7: "LongLong", 8: "SizeT", 9: "Float",
    10: "Double", 11: "Data", 12: "Raw", 13: "Push", 14: "Pop", 15: "Name",
}

ENCODINGS = {1: "utf-8", 2: "utf-16-le", 4: "utf-32-le"}


class Stream:
    """Little-endian cursor over the concatenated dict+doc blob."""

    def __init__(self, blob):
        self.b = blob
        self.o = 0
        self.char_size = 1  # replaced by the first FT_CharSize field

    def u8(self):
        v = self.b[self.o]
        self.o += 1
        return v

    def _unpack(self, fmt, size):
        v = struct.unpack_from(fmt, self.b, self.o)[0]
        self.o += size
        return v

    def u16(self): return self._unpack("<H", 2)
    def u32(self): return self._unpack("<I", 4)
    def i32(self): return self._unpack("<i", 4)
    def i64(self): return self._unpack("<q", 8)
    def f32(self): return self._unpack("<f", 4)
    def f64(self): return self._unpack("<d", 8)

    def text(self, n_bytes):
        raw = self.b[self.o:self.o + n_bytes]
        self.o += n_bytes
        enc = ENCODINGS.get(self.char_size)
        if enc is None:
            raise ValueError(f"unsupported CharSize {self.char_size}")
        return raw.decode(enc, "replace")


def read_document(path):
    """Return the dict+doc blob, without touching the source or its directory.

    `mode=ro` alone is NOT sufficient, which is worth knowing before trusting it.
    Audacity writes `.aup3` in WAL journal mode, and SQLite cannot read a WAL
    database without its `-shm` shared-memory file — so a `mode=ro` connection
    either creates `-wal`/`-shm` beside the project or, if it cannot, fails to
    open at all. Both were observed on the reference fixtures. Creating files
    beside a source we promised not to touch violates SPEC-0002 REQ "Input
    Immutability" just as surely as writing to it would.

    `immutable=1` is the fix: it tells SQLite the file cannot change underneath
    it, so the WAL/shm machinery is bypassed entirely and nothing is created.
    The precondition is real — do not use this on a project Audacity currently
    has open — but for an importer reading a saved project it holds.
    """
    uri = f"file:{pathlib.Path(path).resolve().as_posix()}?mode=ro&immutable=1"
    db = sqlite3.connect(uri, uri=True)
    try:
        row = db.execute("SELECT dict, doc FROM project WHERE id = 1").fetchone()
    finally:
        db.close()
    if row is None:
        raise SystemExit(f"{path}: no row id=1 in the project table")
    return row[0] + row[1]


def parse(blob):
    """Decode the stream into (names, events). Raises if a field is unreadable."""
    s, names, events = Stream(blob), {}, []
    while s.o < len(blob):
        at = s.o
        kind = FIELD_TYPES.get(s.u8())
        if kind is None:
            raise ValueError(f"unknown field type at byte {at}")

        if kind == "CharSize":
            s.char_size = s.u8()
        elif kind == "Name":
            ident = s.u16()
            names[ident] = s.text(s.u16())          # note: uint16 length
        elif kind in ("StartTag", "EndTag"):
            events.append((kind, names.get(s.u16(), "?")))
        elif kind in ("Push", "Pop"):
            events.append((kind, None))
        elif kind in ("Data", "Raw"):
            events.append((kind, s.text(s.u32())))  # note: uint32 length
        else:
            ident = s.u16()
            name = names.get(ident, f"?{ident}")
            if kind == "String":
                value = s.text(s.u32())
            elif kind in ("Int", "Long", "SizeT"):
                value = s.i32()
            elif kind == "Bool":
                value = bool(s.u8())
            elif kind == "LongLong":
                value = s.i64()
            elif kind == "Float":
                value = s.f32()
                s.i32()                             # trailing digit count
            elif kind == "Double":
                value = s.f64()
                s.i32()
            events.append(("Attr", (name, value)))
    return names, events, s.o


def render(events):
    depth = 0
    for kind, payload in events:
        if kind == "StartTag":
            print("  " * depth + f"<{payload}>")
            depth += 1
        elif kind == "EndTag":
            depth = max(0, depth - 1)
        elif kind == "Attr":
            name, value = payload
            print("  " * depth + f"  {name} = {value!r}")
        elif kind == "Raw" and payload.strip():
            print("  " * depth + f"  # raw: {payload!r}")


def main():
    ap = argparse.ArgumentParser(description="Dump an .aup3 project document.")
    ap.add_argument("project", help="path to a .aup3 file")
    ap.add_argument("--raw", action="store_true",
                    help="list every decoded field instead of the tag tree")
    args = ap.parse_args()

    blob = read_document(args.project)
    names, events, consumed = parse(blob)

    # A short read means the parser and the file disagree. Say so loudly: a
    # partial parse that prints a plausible tree is exactly the failure mode
    # SPEC-0002 REQ "Refusal on Unrecognized Structure" exists to prevent.
    status = "clean" if consumed == len(blob) else f"SHORT — stopped at {consumed}"
    print(f"# {args.project}", file=sys.stderr)
    print(f"# {consumed}/{len(blob)} bytes consumed ({status}), "
          f"{len(names)} interned names", file=sys.stderr)
    if consumed != len(blob):
        raise SystemExit(1)

    if args.raw:
        for kind, payload in events:
            print(f"{kind}\t{payload!r}")
    else:
        render(events)


if __name__ == "__main__":
    main()
