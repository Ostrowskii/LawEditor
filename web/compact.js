// The compact view: the chat and the terminal, and little else. The side bar and the toolbar step aside
// for a thin line of state (Bend-UI's strip): the conversation's project, how many conversations work and
// how many wait for the person (a click opens the first of them), and the way back to the full app.
import { setPane } from "bend-ui/panes";
import { setSide } from "bend-ui";
import { where, icon, esc } from "./where.js";

const $ = (id) => document.getElementById(id);
const strip = $("strip"), side = $("side"), toolbar = document.querySelector(".toolbar");
let rows = [], sideWas = false;

const first = (state) => rows.find((r) => r[3] === state);
function draw() {
  const mine = rows.find((r) => r[2] === where.conv), count = (state) => rows.filter((r) => r[3] === state).length;
  $("strip-place").innerHTML = icon("folder", true) + esc(mine?.[1] || "New project");
  for (const [id, state, dot, words] of [["strip-working", "working", "dot dot--busy", "working"], ["strip-asking", "asking", "dot dot--warning", "waiting for you"]]) {
    const n = count(state), b = $(id);
    b.hidden = !n; b.innerHTML = `<span class="${dot}"></span><span>${n} ${words}</span>`;
  }
}
function set(on) {
  if (on) sideWas = side.classList.contains("is-open");
  strip.hidden = !on; toolbar.hidden = on; side.hidden = on;
  if (on) { setPane($("shell"), true); draw(); } else setSide(side, sideWas);
  try { localStorage.setItem("laweditor.compact", on ? "on" : "off"); } catch {}
}
$("compact").addEventListener("click", () => set(true));
$("strip-full").addEventListener("click", () => set(false));
for (const [id, state] of [["strip-working", "working"], ["strip-asking", "asking"]])
  $(id).addEventListener("click", () => { const r = first(state); if (r) document.dispatchEvent(new CustomEvent("laweditor:open", { detail: { key: r[0], conv: r[2] } })); });
document.addEventListener("laweditor:list", (e) => { rows = e.detail; if (!strip.hidden) draw(); });
document.addEventListener("laweditor:where", () => { if (!strip.hidden) draw(); });
try { if (localStorage.getItem("laweditor.compact") === "on") set(true); } catch {}
