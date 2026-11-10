"""Stream a consistent tar of cleanuparr's SQLite databases to stdout.

Invoked by K8up via the k8up.io/backupcommand annotation. All three are live,
so copying the files off a running volume can tear them. sqlite3's online
backup API takes the read lock and hands back a coherent copy instead.

The copy goes to a scratch file and is streamed from there, one database at a
time, so the memory this needs does not grow with the databases. It used to go
through memory -- a :memory: copy, then serialize() of it, two images at once
-- and K8up runs this inside the cleanuparr container, against its 512Mi limit.
events.db is an action log that only grows: the claim held 40M when this was
written and 223M a month later, and from 2026-09-22 the kernel OOM-killed the
dump every night, six attempts a night, each one taking cleanuparr down with it.

events.db is included anyway, because excluding it would need a second
decision about what a partial restore means.

The scratch file lives in the container's own temp directory, not on the
claim: a copy under /config would double what the volume has to hold, and
would land in the file-level backup as well.

The image ships no sqlite3 binary. It does carry a python for apprise, whose
stdlib sqlite3 is all this needs; the interpreter path is absolute because that
venv is not on PATH for a non-login shell.

Exiting non-zero fails the K8up Job, which is what K8upJobFailed alerts on.
That is the point of doing this here rather than trusting the file-level copy:
a broken dump is loud, where a torn database is silent until a restore.
"""

import os
import sqlite3
import sys
import tarfile
import tempfile

DATABASES = ("cleanuparr.db", "events.db", "users.db")
CONFIG_DIR = "/config"


def snapshot(name, path):
    """Write a consistent copy of the named database to path."""
    source = sqlite3.connect(f"file:{CONFIG_DIR}/{name}?mode=ro", uri=True)
    try:
        copy = sqlite3.connect(path)
        try:
            source.backup(copy)
        finally:
            copy.close()
    finally:
        source.close()


def main():
    with tempfile.TemporaryDirectory() as scratch:
        with tarfile.open(fileobj=sys.stdout.buffer, mode="w|") as tar:
            for name in DATABASES:
                path = os.path.join(scratch, name)
                snapshot(name, path)
                entry = tarfile.TarInfo(name)
                entry.size = os.path.getsize(path)
                with open(path, "rb") as image:
                    tar.addfile(entry, image)
                os.unlink(path)
                print(f"{name}: {entry.size} bytes", file=sys.stderr)


main()
