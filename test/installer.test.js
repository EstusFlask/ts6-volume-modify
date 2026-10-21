const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { spawnSync } = require("node:child_process");
const test = require("node:test");

const projectRoot = path.resolve(__dirname, "..");
const profiles = JSON.parse(fs.readFileSync(path.join(projectRoot, "config/windows-x64.json"), "utf8"));
const windowsOnly = { skip: process.platform !== "win32" };
const md5 = bytes => crypto.createHash("md5").update(bytes).digest("hex");
const fromHex = hex => Buffer.from(hex.replace(/\s/g, ""), "hex");
const clientFiles = ["TeamSpeak.exe", "TeamSpeak.dll", "html/client_ui/main.js", "html/client_ui/index.html"];

function runInstaller(fixture, ...args) {
  // Let Windows PowerShell discover its own modules when Node was started by PowerShell 7.
  const env = Object.fromEntries(Object.entries(process.env).filter(([key]) => key.toLowerCase() !== "psmodulepath"));
  const result = spawnSync("powershell.exe", [
    "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", path.join(fixture.app, "Install-Volume-Unlock.ps1"),
    "-TeamSpeakPath", fixture.client, "-BackupRoot", fixture.backups, "-NoLaunch", ...args
  ], { encoding: "utf8", windowsHide: true, timeout: 30000, env });
  assert.ifError(result.error);
  return { status: result.status, output: result.stdout + result.stderr };
}

function fixture(t, version, state = "OriginalHash") {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "ts6-volume-installer-test-"));
  t.after(() => {
    assert.equal(path.dirname(root), path.resolve(os.tmpdir()));
    assert.ok(path.basename(root).startsWith("ts6-volume-installer-test-"));
    fs.rmSync(root, { recursive: true, force: true });
  });
  const result = {
    root, app: path.join(root, "addon"), client: path.join(root, "client"), backups: path.join(root, "backups")
  };
  fs.mkdirSync(result.app, { recursive: true });
  for (const name of ["Install-Volume-Unlock.ps1", "addon.json", "src", "config"]) {
    fs.cpSync(path.join(projectRoot, name), path.join(result.app, name), { recursive: true });
  }
  fs.mkdirSync(path.join(result.client, "html/client_ui"), { recursive: true });
  const config = structuredClone(profiles);
  const binaries = new Map();
  // Synthetic files exercise every installer state without redistributing TeamSpeak binaries.
  for (const [profileIndex, profile] of config.entries()) {
    const main = `fixture main.js: ${profile.Version}`;
    profile.MainHash = md5(main);
    for (const spec of profile.BinarySpecs) {
      const original = Buffer.alloc(512, 0x80 + profileIndex);
      for (const [index, patch] of spec.Patches.entries()) {
        patch.Offset = (32 + index * 32).toString(16);
        fromHex(patch.Old).copy(original, parseInt(patch.Offset, 16));
      }
      const states = { OriginalHash: original };
      const patched = Buffer.from(original);
      for (const [index, patch] of spec.Patches.entries()) {
        fromHex(patch.New).copy(patched, parseInt(patch.Offset, 16));
        if (spec.Name === "TeamSpeak.dll" && index === 1) states.IntermediateHash = Buffer.from(patched);
        if (spec.Name === "TeamSpeak.dll" && index === 2 && spec.GainConversionHash) {
          states.GainConversionHash = Buffer.from(patched);
        }
      }
      states.PatchedHash = patched;
      for (const [key, bytes] of Object.entries(states)) spec[key] = md5(bytes);
      if (profile.Version === version) binaries.set(spec.Name, states);
    }
    if (profile.Version === version) {
      result.profile = profile;
      fs.writeFileSync(path.join(result.client, "html/client_ui/main.js"), main);
    }
  }
  for (const [name, states] of binaries) {
    fs.writeFileSync(path.join(result.client, name), states[state] || states.PatchedHash);
  }
  result.config = config;
  result.saveConfig = () => fs.writeFileSync(path.join(result.app, "config/windows-x64.json"), JSON.stringify(config));
  result.saveConfig();
  fs.writeFileSync(path.join(result.client, "html/client_ui/index.html"),
    '<!DOCTYPE html><html><head><!-- unrelated addon --></head><body>original UI</body></html>');
  return result;
}

function snapshot(fixture) {
  return clientFiles.map(name => md5(fs.readFileSync(path.join(fixture.client, name))));
}

for (const profile of profiles) {
  test(`${profile.Version}: installs and reinstalls all supported binary states`, windowsOnly, async t => {
    const states = ["OriginalHash", "IntermediateHash", "PatchedHash"];
    if (profile.BinarySpecs[1].GainConversionHash) states.push("GainConversionHash");
    for (const state of states) {
      await t.test(state, t => {
        const files = fixture(t, profile.Version, state);
        const before = snapshot(files);
        let initialBackup;
        for (let attempt = 0; attempt < 2; attempt++) {
          const result = runInstaller(files);
          assert.equal(result.status, 0, result.output);
          assert.ok(result.output.includes(`Detected TeamSpeak ${profile.Version} (Windows x64).`));
          for (const spec of files.profile.BinarySpecs) {
            assert.equal(md5(fs.readFileSync(path.join(files.client, spec.Name))), spec.PatchedHash);
          }
          const index = fs.readFileSync(path.join(files.client, "html/client_ui/index.html"), "utf8");
          assert.equal(index.match(/ADDON_START v2 ts6_volume_unlock/g).length, 1);
          assert.ok(index.includes("<!-- unrelated addon -->"));
          assert.ok(index.includes("ts6_volume_unlock_max_db"));
          if (attempt === 0) initialBackup = fs.readdirSync(files.backups)[0];
        }
        const backups = fs.readdirSync(files.backups).sort();
        assert.equal(backups.length, 2);
        const first = path.join(files.backups, initialBackup);
        assert.equal(md5(fs.readFileSync(path.join(first, "TeamSpeak.exe"))), before[0]);
        assert.equal(md5(fs.readFileSync(path.join(first, "TeamSpeak.dll"))), before[1]);
        assert.equal(md5(fs.readFileSync(path.join(first, "index.html"))), before[3]);
      });
    }
  });

  test(`${profile.Version}: CheckOnly validates patches without writing files or backups`, windowsOnly, t => {
    const files = fixture(t, profile.Version);
    const before = snapshot(files);
    const result = runInstaller(files, "-CheckOnly");
    assert.equal(result.status, 0, result.output);
    assert.match(result.output, /Compatibility check passed/);
    assert.deepEqual(snapshot(files), before);
    assert.equal(fs.existsSync(files.backups), false);
  });
}

for (const name of ["html/client_ui/main.js", "TeamSpeak.exe", "TeamSpeak.dll"]) {
  test(`rejects an unknown ${name} before making any changes`, windowsOnly, t => {
    const files = fixture(t, profiles[0].Version);
    fs.appendFileSync(path.join(files.client, name), "unknown build");
    const before = snapshot(files);
    const result = runInstaller(files);
    assert.notEqual(result.status, 0);
    assert.match(result.output, /No files were changed/);
    assert.deepEqual(snapshot(files), before);
    assert.equal(fs.existsSync(files.backups), false);
  });
}

test("preflight rejects invalid patch bytes, offsets, and output hashes before writing", windowsOnly, async t => {
  for (const kind of ["bytes", "offset", "hash"]) {
    await t.test(kind, t => {
      const files = fixture(t, profiles[0].Version);
      const spec = files.profile.BinarySpecs[1];
      if (kind === "bytes") spec.Patches[0].Old = "FF";
      if (kind === "offset") spec.Patches[0].Offset = "FFFF";
      if (kind === "hash") spec.PatchedHash = "0".repeat(32);
      files.saveConfig();
      const before = snapshot(files);
      const result = runInstaller(files, "-CheckOnly");
      assert.notEqual(result.status, 0);
      assert.match(result.output, /Unexpected bytes|outside|checksum did not match/);
      assert.deepEqual(snapshot(files), before);
      assert.equal(fs.existsSync(files.backups), false);
    });
  }
});

test("restores both binaries and HTML if UI installation fails after binary patching", windowsOnly, t => {
  const files = fixture(t, profiles[0].Version);
  fs.writeFileSync(path.join(files.client, "html/client_ui/index.html"), "<html>missing head</html>");
  const before = snapshot(files);
  const result = runInstaller(files);
  assert.notEqual(result.status, 0);
  assert.match(result.output, /Could not find the HTML head/);
  assert.deepEqual(snapshot(files), before);
  assert.equal(fs.readdirSync(files.backups).length, 1);
  assert.equal(fs.existsSync(path.join(files.client, "TeamSpeak.dll.ts6vu-new")), false);
});

test("real TeamSpeak client: verifies hashes, native limits, UI contract, and reinstall", {
  skip: process.platform !== "win32" || !process.env.TS6_CLIENT_PATH
}, t => {
  const source = path.resolve(process.env.TS6_CLIENT_PATH);
  const main = fs.readFileSync(path.join(source, "html/client_ui/main.js"));
  const profile = profiles.find(profile => profile.MainHash === md5(main));
  assert.ok(profile, "Unrecognized client main.js");
  const files = fixture(t, profile.Version);
  // Use the unmodified release manifest for the real binaries.
  fs.copyFileSync(path.join(projectRoot, "config/windows-x64.json"), path.join(files.app, "config/windows-x64.json"));
  for (const name of clientFiles) fs.copyFileSync(path.join(source, name), path.join(files.client, name));
  const sourceHashes = clientFiles.map(name => md5(fs.readFileSync(path.join(source, name))));
  const text = main.toString("utf8");
  assert.match(text, /name:"ts-client-volume"/);
  assert.match(text, /staticClass:"client-fader"/);
  assert.match(text, /"level-change-finished":\w\.onClientLevelChangeFinished/);
  assert.match(text, /onClientLevelChangeFinished\(\)\{this\.initialized&&this\.client\.SetVolumeModifier\(this\.level,!0\)\}/);
  assert.match(text, /GetVolumeModifier\(\)\{return new Promise/);

  for (let attempt = 0; attempt < 2; attempt++) {
    const result = runInstaller(files);
    assert.equal(result.status, 0, result.output);
    for (const spec of profile.BinarySpecs) {
      const bytes = fs.readFileSync(path.join(files.client, spec.Name));
      assert.equal(md5(bytes), spec.PatchedHash);
      for (const patch of spec.Patches) {
        const offset = parseInt(patch.Offset, 16);
        const replacement = fromHex(patch.New);
        assert.deepEqual(bytes.subarray(offset, offset + replacement.length), replacement);
      }
      if (spec.Name === "TeamSpeak.dll") verifyNativeLimits(bytes, spec.Patches);
    }
    const html = fs.readFileSync(path.join(files.client, "html/client_ui/index.html"), "utf8");
    assert.equal(html.match(/ADDON_START v2 ts6_volume_unlock/g).length, 1);
  }
  assert.deepEqual(clientFiles.map(name => md5(fs.readFileSync(path.join(source, name)))), sourceHashes);
});

function verifyNativeLimits(bytes, patches) {
  // Resolve RIP-relative addresses through the PE section table, not raw file offsets.
  const peOffset = bytes.readUInt32LE(0x3c);
  assert.equal(bytes.toString("hex", peOffset, peOffset + 4), "50450000");
  const sectionCount = bytes.readUInt16LE(peOffset + 6);
  const sectionStart = peOffset + 24 + bytes.readUInt16LE(peOffset + 20);
  const sections = Array.from({ length: sectionCount }, (_, i) => {
    const offset = sectionStart + i * 40;
    return { rva: bytes.readUInt32LE(offset + 12), size: bytes.readUInt32LE(offset + 16), raw: bytes.readUInt32LE(offset + 20) };
  });
  function constantReferencedAt(offset) {
    const code = sections.find(s => s.raw <= offset && offset + 4 <= s.raw + s.size);
    assert.ok(code);
    const targetRva = offset - code.raw + code.rva + 4 + bytes.readInt32LE(offset);
    const target = sections.find(s => s.rva <= targetRva && targetRva + 4 <= s.rva + s.size);
    assert.ok(target);
    return bytes.readFloatLE(targetRva - target.rva + target.raw);
  }
  assert.equal(constantReferencedAt(parseInt(patches[2].Offset, 16)), 60);
  assert.equal(bytes.readFloatLE(parseInt(patches[3].Offset, 16)), 1000);
  assert.equal(constantReferencedAt(parseInt(patches[4].Offset, 16)), 1000);
}
