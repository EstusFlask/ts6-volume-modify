(() => {
  "use strict";

  const STORAGE_KEY = "ts6_volume_unlock_max_db";
  const DEFAULT_MAX_DB = 30;
  const MIN_MAX_DB = 10;
  const MAX_MAX_DB = 60;
  const ZERO_POSITION = 76;
  const states = new WeakMap();
  let maxDb = readMaxDb();
  let scanQueued = false;

  function readMaxDb() {
    try {
      const value = Number(localStorage.getItem(STORAGE_KEY));
      return Number.isFinite(value) && value >= MIN_MAX_DB && value <= MAX_MAX_DB
        ? value
        : DEFAULT_MAX_DB;
    } catch {
      return DEFAULT_MAX_DB;
    }
  }

  function roundHalf(value) {
    return Math.round(value * 2) / 2;
  }

  function getFader(element) {
    for (const start of [element.__vue__, element.firstElementChild?.__vue__]) {
      for (let candidate = start, depth = 0; candidate && depth < 3;
           candidate = candidate.$parent, depth++) {
        if (typeof candidate.mm2db === "function" &&
            typeof candidate.db2mm === "function" &&
            candidate.$parent?.$options?.name === "ts-client-volume") {
          return candidate;
        }
      }
    }
    return null;
  }

  function patchFader(fader) {
    const oldMm2db = fader.mm2db;
    const oldDb2mm = fader.db2mm;

    fader.mm2db = function (position) {
      if (position <= ZERO_POSITION) return oldMm2db(position);
      return roundHalf((position - ZERO_POSITION) * maxDb / (100 - ZERO_POSITION));
    };
    fader.db2mm = function (db) {
      if (db <= 0) return oldDb2mm(db);
      return Math.min(100, ZERO_POSITION + db * (100 - ZERO_POSITION) / maxDb);
    };
    fader.level_mm = fader.db2mm(fader.level_db);
  }

  function makeField(labelText, value, min, max, onChange) {
    const label = document.createElement("label");
    label.className = "ts6vu-field";
    const text = document.createElement("span");
    text.textContent = labelText;
    const input = document.createElement("input");
    input.type = "number";
    input.min = String(min);
    input.max = String(max);
    input.step = "0.5";
    input.value = String(value);
    input.addEventListener("change", () => onChange(input));
    label.append(text, input);
    return { label, input };
  }

  function installControls(element, fader) {
    const parent = fader.$parent;
    const panel = document.createElement("div");
    panel.className = "ts6vu-controls";
    panel.setAttribute("role", "group");
    panel.setAttribute("aria-label", "单用户音量增强");

    const current = makeField("当前音量 dB", parent.level, -200, maxDb, input => {
      if (input.value.trim() === "") {
        input.value = String(parent.level);
        return;
      }
      const value = Number(input.value);
      if (!Number.isFinite(value)) {
        input.value = String(parent.level);
        return;
      }
      const next = roundHalf(Math.max(-200, Math.min(value, maxDb)));
      parent.level = next;
      fader.level_db = next;
      fader.level_mm = fader.db2mm(next);
      input.value = String(next);
      parent.$nextTick(() => {
        parent.onClientLevelChangeFinished();
        checkReadback(parent, next, panel);
      });
    });
    const maximum = makeField("增益上限 dB", maxDb, MIN_MAX_DB, MAX_MAX_DB, input => {
      const value = Number(input.value);
      if (!Number.isFinite(value) || value < MIN_MAX_DB || value > MAX_MAX_DB) {
        input.value = String(maxDb);
        return;
      }
      maxDb = roundHalf(value);
      try { localStorage.setItem(STORAGE_KEY, String(maxDb)); } catch { /* session only */ }
      document.querySelectorAll(".client-fader").forEach(refreshFader);
    });

    const note = document.createElement("small");
    note.className = "ts6vu-note";
    note.textContent = "上限对所有用户生效，范围 +10 至 +60 dB";
    panel.append(current.label, maximum.label, note);
    for (const type of ["pointerdown", "mousedown", "mouseup", "click", "keydown"]) {
      panel.addEventListener(type, event => event.stopPropagation());
    }
    element.append(panel);

    const unwatch = parent.$watch("level", value => {
      if (document.activeElement !== current.input) current.input.value = String(value);
    });
    parent.$once("hook:beforeDestroy", unwatch);
    states.set(element, { fader, current: current.input, maximum: maximum.input });
  }

  async function checkReadback(parent, expected, panel) {
    try {
      const actual = await parent.client.GetVolumeModifier();
      if (Math.abs(actual - expected) > 0.25) {
        const note = panel.querySelector(".ts6vu-note");
        note.textContent = `客户端返回 ${actual} dB；请求的 ${expected} dB 可能未生效`;
      }
    } catch {
      // A temporary read failure must not interfere with the native control.
    }
  }

  function refreshFader(element) {
    const state = states.get(element);
    if (!state) return;
    state.maximum.value = String(maxDb);
    state.current.max = String(maxDb);
    state.fader.level_mm = state.fader.db2mm(state.fader.level_db);
  }

  function scan() {
    scanQueued = false;
    document.querySelectorAll(".client-fader").forEach(element => {
      const state = states.get(element);
      if (state) {
        if (!element.querySelector(".ts6vu-controls")) installControls(element, state.fader);
        return;
      }
      const fader = getFader(element);
      if (!fader) return;
      patchFader(fader);
      installControls(element, fader);
    });
  }

  function queueScan() {
    if (scanQueued) return;
    scanQueued = true;
    requestAnimationFrame(scan);
  }

  function start() {
    new MutationObserver(queueScan).observe(document.body, { childList: true, subtree: true });
    queueScan();
  }

  if (document.body) start();
  else document.addEventListener("DOMContentLoaded", start, { once: true });
})();
