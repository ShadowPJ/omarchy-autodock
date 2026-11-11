.pragma library

// Pure helpers for the auto dock, kept out of QML so they can be reasoned
// about (and tested) on their own.

var POSITIONS = ["bottom", "top", "left", "right"]

function normalizePosition(value) {
  var position = String(value || "").toLowerCase()
  return POSITIONS.indexOf(position) >= 0 ? position : "bottom"
}

function isVertical(position) {
  return position === "left" || position === "right"
}

function clampInt(value, min, max, fallback) {
  var n = Math.round(Number(value))
  if (!isFinite(n)) return fallback
  return Math.max(min, Math.min(max, n))
}

// Desktop ids from the config: strings only, trimmed, bounded, no duplicates.
// A trailing ".desktop" is accepted and dropped.
function appIds(list) {
  if (!Array.isArray(list)) return []
  var seen = {}
  var out = []
  for (var i = 0; i < list.length && out.length < 32; i++) {
    if (typeof list[i] !== "string") continue
    var id = list[i].trim().replace(/\.desktop$/, "")
    if (!id || id.length > 200 || seen[id]) continue
    seen[id] = true
    out.push(id)
  }
  return out
}

// Parses config.json text into a normalized config; anything malformed falls
// back to the defaults instead of breaking the dock.
function parseConfig(text, defaults) {
  var raw = {}
  try {
    var parsed = JSON.parse(String(text || "{}"))
    if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) raw = parsed
  } catch (e) {
    raw = {}
  }
  var apps = appIds(raw.apps)
  return {
    position: normalizePosition(raw.position),
    hideDelayMs: clampInt(raw.hideDelayMs, 100, 5000, 400),
    iconSize: clampInt(raw.iconSize, 24, 96, 40),
    apps: apps.length > 0 ? apps : appIds(defaults)
  }
}

// Picks the window to focus for an app: one on the current workspace first,
// then the most recently listed elsewhere.
function pickWindow(windows, workspaceId) {
  for (var i = 0; i < windows.length; i++) {
    if (windows[i].workspaceId === workspaceId) return i
  }
  return windows.length - 1
}
