const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { spawnSync } = require("node:child_process");
const { inflateRawSync } = require("node:zlib");
const test = require("node:test");

const projectRoot = path.resolve(__dirname, "..");
const addon = JSON.parse(fs.readFileSync(path.join(projectRoot, "addon.json"), "utf8"));

function readZip(bytes) {
  const end = bytes.length - 22; // Build-Packages writes ZIPs without archive comments.
  assert.equal(bytes.readUInt32LE(end), 0x06054b50);
  const count = bytes.readUInt16LE(end + 10);
  let cursor = bytes.readUInt32LE(end + 16);
  const entries = new Map();
  for (let i = 0; i < count; i++) {
    assert.equal(bytes.readUInt32LE(cursor), 0x02014b50);
    const method = bytes.readUInt16LE(cursor + 10);
    const size = bytes.readUInt32LE(cursor + 20);
    const nameLength = bytes.readUInt16LE(cursor + 28);
    const extraLength = bytes.readUInt16LE(cursor + 30);
    const commentLength = bytes.readUInt16LE(cursor + 32);
    const local = bytes.readUInt32LE(cursor + 42);
    const name = bytes.toString("utf8", cursor + 46, cursor + 46 + nameLength);
    assert.equal(bytes.readUInt32LE(local), 0x04034b50);
    const start = local + 30 + bytes.readUInt16LE(local + 26) + bytes.readUInt16LE(local + 28);
    const compressed = bytes.subarray(start, start + size);
    assert.ok(method === 0 || method === 8);
    assert.equal(entries.has(name), false);
    entries.set(name, method === 8 ? inflateRawSync(compressed) : compressed);
    cursor += 46 + nameLength + extraLength + commentLength;
  }
  return entries;
}

test("distribution packages contain exact sources, version data, and required installer files", {
  skip: process.platform !== "win32"
}, t => {
  const output = fs.mkdtempSync(path.join(os.tmpdir(), "ts6-volume-package-test-"));
  t.after(() => {
    assert.equal(path.dirname(output), path.resolve(os.tmpdir()));
    assert.ok(path.basename(output).startsWith("ts6-volume-package-test-"));
    fs.rmSync(output, { recursive: true, force: true });
  });
  const env = Object.fromEntries(Object.entries(process.env).filter(([key]) => key.toLowerCase() !== "psmodulepath"));
  const result = spawnSync("powershell.exe", [
    "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", path.join(projectRoot, "Build-Packages.ps1"),
    "-OutputDirectory", output
  ], { encoding: "utf8", windowsHide: true, timeout: 30000, env });
  assert.ifError(result.error);
  assert.equal(result.status, 0, result.stdout + result.stderr);
  const shared = [
    "addon.json", "inject.html", "src/ts6-volume-unlock/index.js", "src/ts6-volume-unlock/style.css",
    "README.md", "README.zh-CN.md", "THIRD_PARTY_NOTICES.md", "docs/native-patches.md"
  ];
  for (const kind of ["One-Click", "UI-Only"]) {
    const entries = readZip(fs.readFileSync(path.join(output, `TS6-Volume-Unlock-${kind}-${addon.version}.zip`)));
    const expected = [...shared];
    if (kind === "One-Click") expected.push("Install-Volume-Unlock.cmd", "Install-Volume-Unlock.ps1", "config/windows-x64.json");
    assert.deepEqual([...entries.keys()].sort(), expected.sort());
    for (const [name, bytes] of entries) assert.deepEqual(bytes, fs.readFileSync(path.join(projectRoot, name)), name);
    assert.equal(JSON.parse(entries.get("addon.json")).version, addon.version);
  }
});
