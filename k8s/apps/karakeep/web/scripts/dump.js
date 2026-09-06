// Stream a consistent copy of karakeep's SQLite database to stdout.
//
// Invoked by K8up via the k8up.io/backupcommand annotation. Copying the file
// off a live volume can tear; serialize() reads it through SQLite itself and
// hands back a coherent image instead.
//
// The image ships no sqlite3 binary, so this goes through the better-sqlite3
// the application itself uses. The path is absolute because this script lives
// outside /app and node resolves modules relative to the file.
//
// queue.db is deliberately not included. It is a liteque job queue, not data:
// restoring a stale one would replay or block jobs that have long since been
// handled. K8up's file-level backup of the PVC still captures it.
//
// Throwing fails the K8up Job, which is what K8upJobFailed alerts on. That is
// the point of doing this here rather than trusting the file-level copy: a
// broken dump is loud, where a torn db.db is silent until a restore.

const Database = require("/app/node_modules/better-sqlite3");

const path = `${process.env.DATA_DIR || "/data"}/db.db`;
const db = new Database(path, { readonly: true });

try {
  const image = db.serialize();
  process.stderr.write(`${path}: ${image.length} bytes\n`);
  process.stdout.write(image);
} finally {
  db.close();
}
