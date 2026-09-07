// Stream a consistent copy of seerr's SQLite database to stdout.
//
// Invoked by K8up via the k8up.io/backupcommand annotation. db.sqlite3 runs in
// WAL mode -- the -wal and -shm files are both present -- so copying it off a
// running volume can tear it.
//
// VACUUM INTO rather than a driver-specific backup call: it is one SQL
// statement, produces a coherent standalone database, and works through
// whatever driver happens to be bundled. The image ships no sqlite3 binary and
// carries node-sqlite3 rather than better-sqlite3, which has no serialize().
// The require path is absolute because this script lives outside /app and node
// resolves modules relative to the file.
//
// VACUUM INTO refuses to overwrite, hence the unlink first. The copy is written
// to /tmp rather than the config volume so a backup never adds to what is being
// backed up.
//
// Exiting non-zero fails the K8up Job, which is what K8upJobFailed alerts on.
// That is the point of doing this here rather than trusting the file-level
// copy: a broken dump is loud, where a torn database is silent until a restore.

const sqlite3 = require("/app/node_modules/sqlite3");
const fs = require("fs");

const SOURCE = "/app/config/db/db.sqlite3";
const TARGET = "/tmp/seerr-backup.sqlite";

const fail = (what, err) => {
  process.stderr.write(`${what}: ${err.message}\n`);
  process.exit(1);
};

try {
  fs.unlinkSync(TARGET);
} catch (e) {
  // absent is the normal case
}

const db = new sqlite3.Database(SOURCE, sqlite3.OPEN_READONLY, (err) => {
  if (err) fail("open", err);
  db.run("VACUUM INTO ?", [TARGET], (err2) => {
    if (err2) fail("vacuum", err2);
    process.stderr.write(`${SOURCE}: ${fs.statSync(TARGET).size} bytes\n`);
    const stream = fs.createReadStream(TARGET);
    stream.on("error", (e) => fail("read", e));
    // Let the process end when the pipe drains rather than calling exit, which
    // would risk truncating stdout mid-flush.
    stream.on("close", () => {
      try {
        fs.unlinkSync(TARGET);
      } catch (e) {
        // the dump already succeeded; a stale temp file is not worth failing on
      }
    });
    stream.pipe(process.stdout);
  });
});
