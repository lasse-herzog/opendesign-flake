// Test the real renderer through upstream's supervised desktop inspection API.
// Run under xvfb-run; extra arguments apply only to this isolated test instance.
import { spawn } from "node:child_process";
import { randomUUID } from "node:crypto";
import { mkdtemp, readdir, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { resolve, join } from "node:path";
import { setTimeout as sleep } from "node:timers/promises";
import { pathToFileURL } from "node:url";

const packageRoot = resolve(process.argv[2] ?? "result");
const resourceRoot = join(packageRoot, "lib/open-design");
const { getSidecarStatus, invokeSidecar, stopSidecar } = await import(pathToFileURL(
  join(resourceRoot, "packages/sidecar/dist/index.mjs"),
));
const { APP_KEYS, SIDECAR_MESSAGES } = await import(pathToFileURL(
  join(resourceRoot, "packages/sidecar-proto/dist/index.mjs"),
));
const root = await mkdtemp(join(tmpdir(), "open-design-desktop-"));
const namespace = `nix-smoke-${randomUUID().slice(0, 8)}`;
const stamp = { app: APP_KEYS.DESKTOP, channel: "stable", mode: "runtime", namespace, source: "packaged" };
const child = spawn(join(packageRoot, "bin/open-design"), process.argv.slice(3), {
  detached: true,
  env: {
    ...process.env,
    XDG_CONFIG_HOME: join(root, "config"),
    XDG_CACHE_HOME: join(root, "cache"),
    XDG_DATA_HOME: join(root, "data"),
    OD_PACKAGED_NAMESPACE: namespace,
    OD_PACKAGED_NAMESPACE_BASE_ROOT: join(root, "namespaces"),
  },
  stdio: ["ignore", "pipe", "pipe"],
});
let logs = "";
for (const stream of [child.stdout, child.stderr]) {
  stream.on("data", (chunk) => { logs = (logs + chunk).slice(-16000); });
}
let ready = false;
try {
  const deadline = Date.now() + 120000;
  while (Date.now() < deadline) {
    // The launcher hands ownership to a supervised desktop and exits with zero.
    if (child.signalCode || (child.exitCode !== null && child.exitCode !== 0)) {
      throw new Error(`Launcher exited with ${child.exitCode ?? child.signalCode}`);
    }
    let status;
    try { status = await getSidecarStatus(stamp, { timeoutMs: 1000 }); }
    catch { await sleep(500); continue; }
    if (status.state !== "running" || !status.windowVisible) { await sleep(500); continue; }
    const evaluation = await invokeSidecar(stamp, SIDECAR_MESSAGES.EVAL, {
      expression: `(async () => ({
        ready: document.readyState === 'complete' && window.__od__?.client?.type === 'desktop' && document.body.innerText.length > 30,
        health: (await fetch('/api/health')).status,
        title: document.title,
        userAgent: navigator.userAgent
      }))()`,
    }, { timeoutMs: 15000 });
    if (evaluation.ok && evaluation.value?.ready && evaluation.value.health === 200) {
      if (process.env.OPEN_DESIGN_SMOKE_SCREENSHOT) {
        await invokeSidecar(stamp, SIDECAR_MESSAGES.SCREENSHOT, {
          path: resolve(process.env.OPEN_DESIGN_SMOKE_SCREENSHOT),
        }, { timeoutMs: 15000 });
      }
      console.log(JSON.stringify(evaluation.value));
      console.log("PASS: Electron renderer, upstream preload bridge, and daemon HTTP 200");
      ready = true;
      break;
    }
    await sleep(500);
  }
  if (!ready) throw new Error("Desktop did not become ready before the timeout");
} catch (error) {
  console.error(logs);
  for (const name of await readdir(root, { recursive: true })) {
    if (name.endsWith(".log")) {
      console.error(name, (await readFile(join(root, name), "utf8")).slice(-12000));
    }
  }
  throw error;
} finally {
  // Stop only this test's unique namespace, including any failed-start peers.
  for (const app of [APP_KEYS.DESKTOP, APP_KEYS.WEB, APP_KEYS.DAEMON]) {
    const stopped = await stopSidecar({ ...stamp, app });
    if (stopped.remainingPids.length) throw new Error(`Test left ${app} processes running`);
  }
  if (child.exitCode === null && child.signalCode === null) process.kill(-child.pid, "SIGTERM");
  await rm(root, { recursive: true, force: true, maxRetries: 4, retryDelay: 100 });
}
