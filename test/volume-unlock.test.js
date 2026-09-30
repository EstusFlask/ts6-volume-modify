const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const vm = require("node:vm");

function element() {
  return {
    children: [],
    listeners: new Map(),
    append(...children) { this.children.push(...children); },
    addEventListener(name, handler) { this.listeners.set(name, handler); },
    setAttribute() {},
    querySelector(selector) {
      if (selector === ".ts6vu-controls") {
        return this.children.find(child => child.className === "ts6vu-controls") || null;
      }
      if (selector === ".ts6vu-note") {
        return this.children.find(child => child.className === "ts6vu-note") || null;
      }
      return null;
    }
  };
}

test("the per-user fader reaches the chosen gain and commits numeric changes", () => {
  const calls = [];
  const client = {
    SetVolumeModifier(value, save) { calls.push({ value, save }); },
    GetVolumeModifier() { return Promise.resolve(calls.at(-1).value); }
  };
  const parent = {
    $options: { name: "ts-client-volume" },
    level: 0,
    client,
    $watch() { return () => {}; },
    $once() {},
    $nextTick(callback) { callback(); },
    onClientLevelChangeFinished() { client.SetVolumeModifier(this.level, true); }
  };
  const fader = {
    $parent: parent,
    level_db: 0,
    mm2db(position) { return position <= 76 ? 0 : (position - 76) * 10 / 24; },
    db2mm(db) { return db <= 0 ? 76 : 76 + db * 24 / 10; }
  };
  const root = element();
  root.__vue__ = fader;
  const values = new Map();
  const document = {
    body: {},
    activeElement: null,
    createElement: element,
    querySelectorAll(selector) { return selector === ".client-fader" ? [root] : []; }
  };
  const code = fs.readFileSync(path.join(__dirname, "../src/ts6-volume-unlock/index.js"), "utf8");
  vm.runInNewContext(code, {
    document,
    MutationObserver: class { observe() {} },
    requestAnimationFrame(callback) { callback(); },
    localStorage: {
      getItem(key) { return values.get(key) ?? null; },
      setItem(key, value) { values.set(key, value); }
    }
  });

  assert.equal(fader.mm2db(76), 0);
  assert.equal(fader.mm2db(88), 15);
  assert.equal(fader.mm2db(100), 30);
  assert.equal(fader.db2mm(30), 100);

  const panel = root.querySelector(".ts6vu-controls");
  assert.ok(panel);
  const current = panel.children[0].children[1];
  const maximum = panel.children[1].children[1];
  maximum.value = "40";
  maximum.listeners.get("change")();
  assert.equal(values.get("ts6_volume_unlock_max_db"), "40");
  assert.equal(fader.mm2db(100), 40);
  assert.equal(current.max, "40");

  current.value = "25";
  current.listeners.get("change")();
  assert.equal(parent.level, 25);
  assert.deepEqual(calls.at(-1), { value: 25, save: true });
});
