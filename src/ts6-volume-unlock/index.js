(() => {
  "use strict";

  const STORAGE_KEY = "ts6_volume_unlock_max_db";
  const LANGUAGE_STORAGE_KEY = "ts6_volume_unlock_language";
  const DEFAULT_MAX_DB = 30;
  const MIN_MAX_DB = 10;
  const MAX_MAX_DB = 60;
  const ZERO_POSITION = 76;
  const translations = {
    en: {
      aria: "Per-user volume boost",
      current: "Current volume (dB)",
      maximum: "Maximum boost (dB)",
      language: "Language",
      initial: "Client readback appears after a change. Maximum: +10 to +60 dB.",
      pending: value => `Requested ${value} dB; checking client readback…`,
      mismatch: (requested, actual) => `Requested ${requested} dB; client readback: ${actual} dB. The value did not persist.`,
      success: actual => `Client readback: ${actual} dB. Native audio processing may still limit loudness.`,
      error: "Could not read back the client volume. Reopen this menu and try again."
    },
    "zh-CN": {
      aria: "单用户音量增强",
      current: "当前音量（dB）",
      maximum: "增益上限（dB）",
      language: "语言",
      initial: "调节后显示客户端读回值；上限范围 +10 至 +60 dB。",
      pending: value => `已请求 ${value} dB，正在核对客户端读回值…`,
      mismatch: (requested, actual) => `请求 ${requested} dB，客户端读回 ${actual} dB；数值未保持。`,
      success: actual => `客户端读回 ${actual} dB；实际响度仍可能受原生音频处理限制。`,
      error: "无法读取客户端音量，请重新打开菜单再试。"
    }
  };
  const states = new WeakMap();
  let maxDb = readMaxDb();
  let language = readLanguage();
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

  function readLanguage() {
    try {
      return localStorage.getItem(LANGUAGE_STORAGE_KEY) === "zh-CN" ? "zh-CN" : "en";
    } catch {
      return "en";
    }
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
    return { label, text, input };
  }

  function installControls(element, fader) {
    const parent = fader.$parent;
    let checkTimer = null;
    const panel = document.createElement("div");
    panel.className = "ts6vu-controls";
    panel.setAttribute("role", "group");

    const current = makeField("", parent.level, -200, maxDb, input => {
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
        scheduleCheck(next);
      });
    });
    const maximum = makeField("", maxDb, MIN_MAX_DB, MAX_MAX_DB, input => {
      const value = Number(input.value);
      if (!Number.isFinite(value) || value < MIN_MAX_DB || value > MAX_MAX_DB) {
        input.value = String(maxDb);
        return;
      }
      maxDb = roundHalf(value);
      try { localStorage.setItem(STORAGE_KEY, String(maxDb)); } catch { /* session only */ }
      document.querySelectorAll(".client-fader").forEach(refreshFader);
    });

    const languageLabel = document.createElement("label");
    languageLabel.className = "ts6vu-field";
    const languageText = document.createElement("span");
    const languageSelect = document.createElement("select");
    for (const [value, label] of [["en", "English"], ["zh-CN", "简体中文"]]) {
      const option = document.createElement("option");
      option.value = value;
      option.textContent = label;
      languageSelect.append(option);
    }
    languageSelect.value = language;
    languageSelect.addEventListener("change", () => {
      language = languageSelect.value === "zh-CN" ? "zh-CN" : "en";
      try { localStorage.setItem(LANGUAGE_STORAGE_KEY, language); } catch { /* session only */ }
      document.querySelectorAll(".client-fader").forEach(refreshLanguage);
    });
    languageLabel.append(languageText, languageSelect);

    const note = document.createElement("small");
    note.className = "ts6vu-note";
    panel.append(current.label, maximum.label, languageLabel, note);
    for (const type of ["pointerdown", "mousedown", "mouseup", "click", "keydown"]) {
      panel.addEventListener(type, event => event.stopPropagation());
    }
    element.append(panel);

    const state = {
      fader,
      panel,
      current: current.input,
      maximum: maximum.input,
      currentText: current.text,
      maximumText: maximum.text,
      languageText,
      languageSelect,
      note,
      status: { kind: "initial" },
      readbackSequence: 0
    };
    states.set(element, state);
    refreshLanguage(element);

    function scheduleCheck(expected) {
      if (checkTimer !== null) clearTimeout(checkTimer);
      const sequence = ++state.readbackSequence;
      state.status = { kind: "pending", expected };
      renderStatus(state);
      checkTimer = setTimeout(() => {
        checkTimer = null;
        checkReadback(parent, expected, state, sequence);
      }, 500);
    }

    // The native slider emits this after its own persisted setter has run.
    fader.$on("level-change-finished", () => scheduleCheck(parent.level));

    const unwatch = parent.$watch("level", value => {
      if (document.activeElement !== current.input) current.input.value = String(value);
    });
    parent.$once("hook:beforeDestroy", () => {
      unwatch();
      if (checkTimer !== null) clearTimeout(checkTimer);
    });
  }

  function renderStatus(state) {
    const copy = translations[language];
    const status = state.status;
    if (status.kind === "pending") state.note.textContent = copy.pending(status.expected);
    else if (status.kind === "mismatch") state.note.textContent = copy.mismatch(status.expected, status.actual);
    else if (status.kind === "success") state.note.textContent = copy.success(status.actual);
    else if (status.kind === "error") state.note.textContent = copy.error;
    else state.note.textContent = copy.initial;
  }

  function refreshLanguage(element) {
    const state = states.get(element);
    if (!state) return;
    const copy = translations[language];
    state.panel.setAttribute("aria-label", copy.aria);
    state.currentText.textContent = copy.current;
    state.maximumText.textContent = copy.maximum;
    state.languageText.textContent = copy.language;
    state.languageSelect.value = language;
    renderStatus(state);
  }

  async function checkReadback(parent, expected, state, sequence) {
    try {
      const actual = await parent.client.GetVolumeModifier();
      if (sequence !== state.readbackSequence) return;
      if (Math.abs(actual - expected) > 0.25) {
        state.status = { kind: "mismatch", expected, actual };
      } else {
        state.status = { kind: "success", actual };
      }
    } catch {
      if (sequence !== state.readbackSequence) return;
      state.status = { kind: "error" };
    }
    renderStatus(state);
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
