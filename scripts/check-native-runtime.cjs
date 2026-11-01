// Exercise allocation-driven GC: explicit global.gc() misses the Node 24 abort.
const assert = require("node:assert/strict");
const { createRequire } = require("node:module");
const { resolve } = require("node:path");
const { Worker, isMainThread, workerData } = require("node:worker_threads");

const packageRoot = isMainThread ? resolve(process.argv[2] ?? "result") : workerData;
const requireApp = createRequire(resolve(packageRoot, "lib/open-design/apps/daemon/package.json"));
const Database = requireApp("better-sqlite3");
const db = new Database(":memory:");

if (isMainThread) {
  let garbage = [];
  for (let i = 0; i < 50000; i++) {
    assert.equal(db.prepare("SELECT 1 AS value").get().value, 1);
    garbage.push({ value: "x".repeat(1000), i });
    if (garbage.length > 1000) garbage = [];
  }
  assert.equal(db.prepare("SELECT 2 AS value").get().value, 2);
  db.close();
  requireApp("node-pty");
  // Leave live native objects in workers to exercise environment teardown too.
  Promise.all(Array.from({ length: 4 }, () => new Promise((resolve, reject) => {
    const worker = new Worker(__filename, { workerData: packageRoot });
    worker.on("error", reject);
    worker.on("exit", code => code === 0 ? resolve() : reject(new Error(`Worker exit ${code}`)));
  }))).then(() => {
    console.log("PASS: SQLite GC, worker cleanup, and node-pty load");
  }).catch(error => {
    console.error(error);
    process.exitCode = 1;
  });
} else {
  global.liveStatement = db.prepare("SELECT 1 AS value");
  assert.equal(global.liveStatement.get().value, 1);
}
