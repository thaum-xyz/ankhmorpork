"""Stream a consistent tar of cleanuparr's SQLite databases to stdout.

Invoked by K8up via the k8up.io/backupcommand annotation. All three are live,
so copying the files off a running volume can tear them. sqlite3's online
backup API takes the read lock and hands back a coherent copy instead.

events.db is by far the largest -- 36M of the 40M volume -- and is an action
log rather than configuration. It is included anyway because it is cheap and
excluding it would need a second decision about what a partial restore means.

The image ships no sqlite3 binary. It does carry a python for apprise, whose
stdlib sqlite3 is all this needs; the interpreter path is absolute because that
venv is not on PATH for a non-login shell.

Exiting non-zero fails the K8up Job, which is what K8upJobFailed alerts on.
That is the point of doing this here rather than trusting the file-level copy:
a broken dump is loud, where a torn database is silent until a restore.
"""

import io
import sqlite3
import sys
import tarfile

DATABASES = ("cleanuparr.db", "events.db", "users.db")
CONFIG_DIR = "/config"


def snapshot(name):
    """Return a consistent copy of the named database as bytes."""
    source = sqlite3.connect(f"file:{CONFIG_DIR}/{name}?mode=ro", uri=True)
    try:
        memory = sqlite3.connect(":memory:")
        try:
            source.backup(memory)
            return memory.serialize()
        finally:
            memory.close()
    finally:
        source.close()


def main():
    with tarfile.open(fileobj=sys.stdout.buffer, mode="w|") as tar:
        for name in DATABASES:
            data = snapshot(name)
            entry = tarfile.TarInfo(name)
            entry.size = len(data)
            tar.addfile(entry, io.BytesIO(data))
            print(f"{name}: {len(data)} bytes", file=sys.stderr)


main()
