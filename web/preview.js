// The project's page, in a pane beside the chat (Bend-UI's panes and inspect). The frame is always the same:
// the page, and three tools on its bar that read it as it is drawn (harness/INSPECT.bend says which, and
// what each does). The page lives at another address (the server's pages door), so it is read by the probe
// the server adds to it (engine/probe.js): this file tells the probe which tools are on and draws what it
// answers. What comes from the page is only numbers and short texts, and is treated as such.
import { initPane, setPane, setPaneSize } from "bend-ui/panes";
import { draw, facts, key as measuresKey } from "bend-ui/inspect";
import I from "../harness/INSPECT.bend";
import { where, key, get, icon, cover } from "./where.js";

const $ = (id) => document.getElementById(id);
const pane = $("preview"), frame = $("preview-frame"), layer = $("preview-layer"), out = $("preview-out"), bar = $("preview-tools");
const yes = (b) => b === true || b?.$ === "True";
const array = (l) => { const a = []; for (; l.$ === "Con"; l = l.tail) a.push(l.head); return a; };
const ICON = { comment: "pencil", measures: "ruler", inspect: "mouse-pointer-click" };
const TOOLS = array(I.tools()).map((t) => ({ word: I.word(t), name: I.name(t), picks: yes(I.takes_pointer(t)) }));

let pages = "", origin = "";
const ready = get("/api/pages").then((url) => { pages = url.trim(); try { origin = new URL(pages).origin; } catch {} }).catch(() => {});
const S = { open: false, measures: false, tool: "", alive: false, part: null, sized: false, place: "" };
// Whose page: the conversation's project; before its first message, the project picked under the message box.
const shown = () => (where.key ? key() : S.place || key());

// ---------- The bar ----------
bar.innerHTML = TOOLS.map((t) => `<button class="btn btn--ghost btn--sm btn--toggle" type="button" aria-pressed="false" data-tool="${t.word}">${icon(ICON[t.word])}<span>${t.name}</span></button>`).join("")
  + `<button class="btn btn--ghost btn--icon btn--sm" type="button" id="preview-tab" aria-label="Open the page in a tab of its own" title="Open in a tab">${icon("external-link")}</button>`
  + `<button class="btn btn--ghost btn--icon btn--sm" type="button" data-pane-toggle aria-label="Close the page">${icon("x")}</button>`;
const pressed = (t) => (t.picks ? S.tool === t.word : S.measures);
function drawBar() {
  for (const t of TOOLS) { const b = bar.querySelector(`[data-tool="${t.word}"]`); b.setAttribute("aria-pressed", pressed(t)); b.disabled = !S.alive; }
  $("preview-tab").disabled = !pages;
}

// What the tools say, under the page: the key of the measures, the picked part's values, or why nothing shows.
function say(note = "") {
  const parts = [];
  if (note) parts.push(`<p class="detail">${note}</p>`);
  if (S.alive && S.measures) parts.push(measuresKey());
  if (S.alive && S.tool === "inspect") parts.push(S.part ? facts(S.part) : '<p class="detail">Click a part of the page to read its values.</p>');
  if (S.alive && S.tool === "comment") parts.push('<p class="detail">Click a part of the page, then write what should change there.</p>');
  out.innerHTML = parts.join(""); out.hidden = !parts.length;
}

// ---------- The probe ----------
const tell = (m) => { if (S.alive && origin) frame.contentWindow?.postMessage(m, origin); };
const tools = () => tell({ laweditor: "tools", measures: S.measures, tool: S.tool });

// What the page sent, kept to what it can be: numbers, and texts of a known length.
const n = (v) => (Number.isFinite(+v) ? +v : 0);
const four = (a) => [0, 1, 2, 3].map((i) => n(a?.[i]));
const rect = (b) => (b && typeof b === "object" ? { x: n(b.x), y: n(b.y), w: n(b.w), h: n(b.h) } : null);
const box = (b) => ({ ...rect(b), pad: four(b.pad), margin: four(b.margin), rowGap: n(b.rowGap), colGap: n(b.colGap), kids: (Array.isArray(b.kids) ? b.kids : []).slice(0, 200).map(rect).filter(Boolean) });
const text = (v, max) => String(v ?? "").slice(0, max);

addEventListener("message", (e) => {
  if (!origin || e.origin !== origin || e.source !== frame.contentWindow) return;
  const m = e.data; if (!m || typeof m !== "object") return;
  if (m.laweditor === "ready") { S.alive = true; frame.hidden = false; drawBar(); say(); tools(); }
  if (m.laweditor === "boxes") {
    try {
      draw(layer, { boxes: (Array.isArray(m.boxes) ? m.boxes : []).slice(0, 1500).filter((b) => b && typeof b === "object").map(box), hover: rect(m.hover), picked: rect(m.picked),
        pins: (Array.isArray(m.pins) ? m.pins : []).slice(0, 100).map((p) => ({ box: rect(p?.box), fx: n(p?.fx), fy: n(p?.fy), label: text(p?.label, 3), fresh: !!p?.fresh })).filter((p) => p.box) });
    } catch (err) { console.error("The page's boxes could not be drawn:", err); }
  }
  if (m.laweditor === "pick") {
    const p = m.part && typeof m.part === "object" ? m.part : {};
    if (S.tool === "inspect") { S.part = { name: text(m.name, 80), w: n(p.w), h: n(p.h), pad: four(p.pad), margin: four(p.margin), gap: n(p.gap), radius: n(p.radius), size: n(p.size), weight: text(p.weight, 12) }; say(); }
    // A comment: the message starts with the part it points at (INSPECT.bend writes the words).
    if (S.tool === "comment") document.dispatchEvent(new CustomEvent("laweditor:point", { detail: I.points_at(text(m.name, 80), text(m.text, 200)) }));
  }
});

bar.addEventListener("click", (e) => {
  if (e.target.closest("#preview-tab")) { if (pages) window.open(`${pages}/${encodeURIComponent(shown())}/`, "_blank", "noopener"); return; }
  const b = e.target.closest("[data-tool]"); if (!b) return;
  const t = TOOLS.find((x) => x.word === b.dataset.tool);
  if (!t.picks) S.measures = !S.measures;
  else { if (S.tool === "comment") tell({ laweditor: "pins", do: "drop" }); S.tool = S.tool === t.word ? "" : t.word; S.part = null; }
  drawBar(); say(); tools();
});

// ---------- The page ----------
// It shows when the probe answers; a project with no page yet answers nothing, and the pane says so.
let asked = 0;
async function load() {
  const me = ++asked;
  await ready;
  if (me !== asked || !S.open) return;
  S.alive = false; S.part = null; frame.hidden = true; layer.replaceChildren(); drawBar();
  if (!pages) { say("The pages door is closed on this computer, so a project's page can't be shown here."); return; }
  say("Opening the page…");
  frame.src = `${pages}/${encodeURIComponent(shown())}/?${I.query()}`;
  setTimeout(() => { if (me === asked && !S.alive) say("This project has no page yet. When the chat builds one, it shows here."); }, 2500);
}

initPane(pane, { label: "Page", onToggle(on) {
  S.open = on; cover("preview", on);
  if (!on) { asked++; frame.removeAttribute("src"); return; }
  if (!S.sized) { S.sized = true; setPaneSize(pane, Math.round(pane.parentElement.clientWidth / 2)); }   // it opens on half the room; the grip keeps what you set
  load();
} });

// "Open the page", in a reply: the pane opens on it.
document.addEventListener("laweditor:preview", () => { if (S.open) load(); else setPane(pane, true); });
// Bend bundled the page again: the frame shows the new one.
document.addEventListener("laweditor:page", () => { if (S.open) load(); });
// The message a comment started was sent: its pin stays where it points.
document.addEventListener("laweditor:sent", () => tell({ laweditor: "pins", do: "keep" }));
// A project was picked for a conversation that hasn't begun: its page.
document.addEventListener("laweditor:place", (e) => { if (e.detail === S.place) return; S.place = e.detail; if (S.open && !where.key) load(); });
// Another conversation: its project's page, with no pin.
document.addEventListener("laweditor:where", (e) => { if (S.open && !e.detail) load(); });
drawBar();
