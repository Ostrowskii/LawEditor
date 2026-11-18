// Where the page is: the conversation that is open, and its project. Every request names them, so the
// server never has to remember which project is "current" (engine/PLACES.bend).
// A conversation with no game yet has no project of its own name: it names itself (its key is its own name).
const newId = () => "c" + Date.now().toString(36) + Math.random().toString(36).slice(2, 8);
export const where = { key: "", conv: newId() };

export const key = () => where.key || where.conv;
export const project = (path) => `/api/p/${encodeURIComponent(key())}/${path}`;
export const conversation = (path) => `/api/c/${encodeURIComponent(key())}/${where.conv}/${path}`;

// The page moved: to another conversation (conv), or its project got its folder (key).
// "laweditor:where" tells the other parts (Laws, the files, the terminal) to read that project again;
// its detail is true when only the project's folder was named (the same conversation, the same files).
export function go(k, conv = where.conv) {
  const moved = k !== where.key || conv !== where.conv, same = conv === where.conv;
  where.key = k; where.conv = conv;
  if (moved) document.dispatchEvent(new CustomEvent("laweditor:where", { detail: same }));
}
export const fresh = () => go("", newId());

export async function get(path) {
  const r = await fetch(path);
  return r.ok ? r.text() : "";
}
export async function post(path, body = "") {
  try { const r = await fetch(path, { method: "POST", body }); return r.ok ? await r.text() : ""; }
  catch { return ""; }
}

export const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]));
export const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
export const lessMotion = matchMedia("(prefers-reduced-motion: reduce)");
export const icon = (n, sm) => `<svg class="icon${sm ? " icon--sm" : ""}" aria-hidden="true"><use href="#i-${n}"/></svg>`;
// A menu's item (Bend-UI's dropdown): a radio item shows its check.
export const menuItem = (label, { data = "", checked = null, lead = "" } = {}) =>
  `<button class="menu__item" type="button" role="${checked === null ? "menuitem" : "menuitemradio"}"${checked === null ? "" : ` aria-checked="${checked}"`} ${data}>${lead ? icon(lead, true) : ""}<span>${esc(label)}</span>${checked === null ? "" : '<svg class="icon icon--sm menu__check"><use href="#i-check"/></svg>'}</button>`;

// The words in the window's corners (made with, the version) step aside while a pane takes their room.
const covering = new Set();
export function cover(pane, on) {
  on ? covering.add(pane) : covering.delete(pane);
  document.querySelectorAll(".window__foot").forEach((f) => f.hidden = covering.size > 0);
}
