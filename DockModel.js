.pragma library

// Pure helpers for the auto dock, kept out of QML so they can be reasoned
// about (and tested) on their own.

var POSITIONS = ["bottom", "top", "left", "right"]
var MAX_APPS = 32

var FALLBACK = {
  position: "bottom",
  hideDelayMs: 400,
  iconSize: 40,
  apps: []
}

function normalizePosition(value, fallback) {
  var position = String(value || "").toLowerCase()
  return POSITIONS.indexOf(position) >= 0 ? position : (fallback || "bottom")
}

function isVertical(position) {
  return position === "left" || position === "right"
}

function clampInt(value, min, max, fallback) {
  var n = Math.round(Number(value))
  if (value === undefined || value === null || !isFinite(n)) return fallback
  return Math.max(min, Math.min(max, n))
}

// Desktop ids from a config: strings only, trimmed, bounded, no duplicates.
// A trailing ".desktop" is accepted and dropped.
function appIds(list) {
  if (!Array.isArray(list)) return []
  var seen = {}
  var out = []
  for (var i = 0; i < list.length && out.length < MAX_APPS; i++) {
    if (typeof list[i] !== "string") continue
    var id = list[i].trim().replace(/\.desktop$/, "")
    if (!id || id.length > 200 || seen[id]) continue
    seen[id] = true
    out.push(id)
  }
  return out
}

function parseObject(text) {
  try {
    var parsed = JSON.parse(String(text || ""))
    if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) return parsed
  } catch (e) {}
  return null
}

// Normalizes a raw config object over a base config. A key the raw object
// leaves out, or gets wrong, keeps the base value. An "apps" array is taken
// as given even when empty: an empty dock is a choice, not a mistake.
function normalize(raw, base) {
  base = base || FALLBACK
  raw = raw || {}
  return {
    position: normalizePosition(raw.position, base.position),
    hideDelayMs: clampInt(raw.hideDelayMs, 100, 5000, base.hideDelayMs),
    iconSize: clampInt(raw.iconSize, 24, 96, base.iconSize),
    apps: Array.isArray(raw.apps) ? appIds(raw.apps) : base.apps.slice()
  }
}

// The config in effect: the user's file over the plugin's bundled defaults.
function effectiveConfig(defaultsText, userText) {
  var defaults = normalize(parseObject(defaultsText), FALLBACK)
  return normalize(parseObject(userText), defaults)
}

// The user's file with a new app list, keeping whatever else it holds.
function withApps(userText, config, apps) {
  var raw = parseObject(userText) || {
    position: config.position,
    hideDelayMs: config.hideDelayMs,
    iconSize: config.iconSize
  }
  raw.apps = appIds(apps)
  return JSON.stringify(raw, null, 2) + "\n"
}

// A copy of list with the item at index moved by delta, clamped to the ends.
function moved(list, index, delta) {
  var out = list.slice()
  var to = Math.max(0, Math.min(out.length - 1, index + delta))
  if (index < 0 || index >= out.length || to === index) return out
  var item = out.splice(index, 1)[0]
  out.splice(to, 0, item)
  return out
}

// Picks the window to focus for an app: one on the current workspace first,
// then the most recently listed elsewhere.
function pickWindow(windows, workspaceId) {
  for (var i = 0; i < windows.length; i++) {
    if (windows[i].workspaceId === workspaceId) return i
  }
  return windows.length - 1
}
