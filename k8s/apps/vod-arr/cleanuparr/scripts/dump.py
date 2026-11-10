"""Stream a consistent tar of cleanuparr's SQLite databases to stdout.

Invoked by K8up via the k8up.io/backupcommand annotation. All three are live,
so copying the files off a running volume can tear them. sqlite3's online
backup API takes the read lock and hands back a coherent copy instead.

events.db is by far the largest -- 36M of the 40M volume when this was written,
155M a month later -- and is an action log rather than configuration. It is
included anyway because it is cheap and excluding it would need a second
decision about what a partial restore means.

Each copy goes through a file under the container's own /tmp, never through
memory. K8up runs this inside the cleanuparr container, so it is charged to
cleanuparr's memory limit, and the kernel kills the whole container on an OOM
rather than this process alone. Copying into ":memory:" and serialising cost
3.5x the database size, which passed 512Mi once events.db reached 150M: every
backup from 2026-10-08 failed and restarted the app it was backing up. A file
costs a few megabytes of page cache however large the database gets.

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
    # Not under /config: the file-level backup of that claim runs alongside
    # this and would pick the copies up.
    with tempfile.TemporaryDirectory(prefix="cleanuparr-dump-") as scratch:
        with tarfile.open(fileobj=sys.stdout.buffer, mode="w|") as tar:
            for name in DATABASES:
                path = os.path.join(scratch, name)
                snapshot(name, path)
                tar.add(path, arcname=name)
                print(f"{name}: {os.path.getsize(path)} bytes", file=sys.stderr)
                # One at a time, so the peak on disk is the largest database
                # rather than all three.
                os.remove(path)


main()
