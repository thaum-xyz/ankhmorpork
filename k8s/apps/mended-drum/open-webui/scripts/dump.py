"""Stream a consistent tar of open-webui's SQLite databases to stdout.

Invoked by K8up via the k8up.io/backupcommand annotation. Both databases run in
WAL mode, so copying the files off a live volume can tear. sqlite3's online
backup API takes the read lock and hands back a coherent copy instead.

Exiting non-zero fails the K8up Job, which is what K8upJobFailed alerts on.
That is the point of doing this here rather than trusting the file-level copy:
a broken dump is loud, where a torn webui.db is silent until a restore.
"""

import io
import sqlite3
import sys
import tarfile

DATABASES = (
    ("webui.db", "/app/backend/data/webui.db"),
    ("chroma.sqlite3", "/app/backend/data/vector_db/chroma.sqlite3"),
)


def snapshot(path):
    """Return a consistent copy of the database at path as bytes."""
    source = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
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
        for name, path in DATABASES:
            data = snapshot(path)
            entry = tarfile.TarInfo(name)
            entry.size = len(data)
            tar.addfile(entry, io.BytesIO(data))
            print(f"{name}: {len(data)} bytes", file=sys.stderr)


main()
