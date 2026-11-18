// LawEditor: the page. The editor's logic is EDITOR.bend (its rules: LAWS.bend);
// this file reads input, talks to the server and draws.

import { isNarrow, setSide } from "bend-ui";
import { mountAgent, flyBetween } from "bend-ui/agent";
import { createThread, openBlock, formBlock } from "bend-ui/thread";
import claudeMark from "bend-ui/brand/claude.webp";
import openaiMark from "bend-ui/brand/openai.svg";
import E from "../EDITOR.bend";
import { markdown } from "./markdown.js";
import { highlight, toHtml } from "bend-ui/syntax";
import pkg from "../package.json";
import { project, get, esc } from "./where.js";

const $ = (id) => document.getElementById(id);
const win = $("win"), doc = $("doc");
$("version").textContent = "v" + pkg.version;   // the app's version, from package.json

// =========================================================
// Server
// =========================================================
async function api(path, body) {
  const res = await fetch(path, body === undefined ? {} : { method: "POST", body });
  return { ok: res.ok, status: res.status, text: await res.text() };
}
// The project's files (GDD.md, TYPES.bend, LAWS.bend): the open conversation's project, asked by name each
// time (web/where.js), so what is read and written is never another project's.
const readFile = async (name) => { try { return (await api(project("file/" + name))).text; } catch { return ""; } };
const writeFile = (name, text) => api(project("file/" + name), text).catch(() => {});

// =========================================================
// Laws in LAWS.bend: each starts at its "# LAW: "<sentence>"" comment
// =========================================================
function parseLaws(src) {
  const laws = [];
  const lines = src.split("\n");
  for (let i = 0; i < lines.length; i++) {
    const m = lines[i].match(/^# LAW: "(.*)"\s*$/);
    if (!m) continue;
    const body = [lines[i]];
    for (let j = i + 1; j < lines.length && !/^# LAW: /.test(lines[j]); j++) body.push(lines[j]);
    while (body.length && !body[body.length - 1].trim()) body.pop();
    laws.push({ sentence: m[1], code: body.join("\n") });
  }
  return laws;
}
let laws = [];   // [{ sentence, code }]
const lawFor = (text) => laws.find((l) => l.sentence === text.trim());

// =========================================================
// Document: one block per line. Its state comes from EDITOR.bend.
// =========================================================

const S = { title: E.title(), empty: E.empty(), busy: E.busy(), ok: E.ok(), error: E.error() };
const DOT = { [S.empty]: "dot", [S.busy]: "dot dot--busy", [S.ok]: "dot dot--success", [S.error]: "dot dot--danger" };
let current = null;
let running = false;

// A line is a Bend-UI pair: the sentence block (.line) and its law block (the aside).
// Each block's minimum height, in lines, comes from EDITOR.bend (law_block_min_is_sentence_min).
function makeBlock(kind = "text", text = "", after = null) {
  const pair = document.createElement("div");
  pair.className = "pair";
  pair.innerHTML = '<div class="block line"><div class="block__slot"></div><div class="block__text" contenteditable="true"></div></div><div class="block block--still pair__aside"></div>';
  const b = pair.firstChild;
  b.style.setProperty("--block-min-lines", E.min_lines(E.sentence()));
  pair.lastChild.style.setProperty("--block-min-lines", E.min_lines(E.law_block()));
  if (kind === "title") b.classList.add("block--title");
  b.querySelector(".block__text").textContent = text;
  b.querySelector(".block__text").dataset.placeholder = "Write a rule and press Enter";
  after ? after.parentElement.after(pair) : doc.append(pair);
  setState(b, kind === "title" ? S.title : S.empty);
  return b;
}
const textOf = (b) => b.querySelector(".block__text").textContent.trim();
const isTitle = (b) => b.classList.contains("block--title");
const stateOf = (b) => Number(b.dataset.state);

// how: "open" (the law block opens from nothing) or "form" (its text forms again), from Bend-UI's thread.
function setState(b, state, out = "", how = "") {
  b.dataset.state = state;
  const empty = !textOf(b) && state === S.empty;
  b.querySelector(".block__slot").innerHTML = state === S.title || empty ? "" : `<span class="${DOT[state]}"></span>`;
  if (state === S.error && out) b.querySelector(".dot").title = out;   // the reason, in the sentences view too
  syncGen();
  return drawLaw(b.nextElementSibling, empty ? -1 : state, out, textOf(b), how);
}

// The law block: the same .block as a sentence. Its dot is the law's state; its text is the law
// (line by line, in color: Bend-UI's syntax), the reason it failed, or (while the agent works) the sentence being read.
// No law: no block.
function drawLaw(el, state, out, sentence, how) {
  const block = (dot, text) => `<div class="block__slot"><span class="${dot}"></span></div>${text}`;
  const code = state === S.ok;
  el.classList.toggle("syntax", code);
  let html = "";
  if (code) html = block(DOT[S.ok], `<div class="block__text">${out.split("\n").map((l) => `<span class="block__line">${toHtml(l) || " "}</span>`).join("")}</div>`);
  else if (state === S.error) html = block(DOT[S.error], `<div class="block__text">${esc(out)}</div>`);
  else if (state === S.busy) html = block(DOT[S.busy], `<div class="block__text thread__reading">${esc(sentence)}</div>`);
  if (how === "open") { el.classList.remove("block--code"); return openBlock(el, html); }
  if (how === "form") return formBlock(el, html, code ? "block--code" : "");
  el.classList.toggle("block--code", code);
  el.innerHTML = html;
  return Promise.resolve();
}

const lines = () => [...doc.querySelectorAll(".line")];
const select = (b) => lines().forEach((x) => x.setAttribute("aria-selected", x === b));
function focusEnd(b) {
  const t = b.querySelector(".block__text"); t.focus();
  const r = document.createRange(); r.selectNodeContents(t); r.collapse(false);
  const s = getSelection(); s.removeAllRanges(); s.addRange(r);
}
// Title / Text: a dropdown on the line you are on.
const KIND = { title: { label: "Title", icon: "heading-1" }, text: { label: "Text", icon: "pilcrow" } };
function syncSize() {
  const kind = current && isTitle(current) ? "title" : "text";
  $("kind-label").textContent = KIND[kind].label;
  $("kind").querySelector("[aria-haspopup] use").setAttribute("href", "#i-" + KIND[kind].icon);
  $("kind").querySelectorAll(".menu__item").forEach((x) => x.setAttribute("aria-checked", x.dataset.kind === kind));
}

doc.addEventListener("focusin", (e) => { const b = e.target.closest(".line"); if (b) { current = b; syncSize(); } });
doc.addEventListener("mousedown", (e) => { const b = e.target.closest(".line"); if (b && !isTitle(b) && textOf(b)) select(b); });
doc.addEventListener("keydown", (e) => {
  const b = e.target.closest(".line"); if (!b) return;
  if (e.key === "Enter") {
    e.preventDefault();
    if (!textOf(b)) return;
    if (!isTitle(b)) { setState(b, stateOf(b)); select(b); }
    focusEnd(makeBlock("text", "", b));
    save();
  }
  const prevPair = b.parentElement.previousElementSibling;
  if (e.key === "Backspace" && !textOf(b) && prevPair?.classList.contains("pair")) {
    e.preventDefault();
    b.parentElement.remove(); focusEnd(prevPair.querySelector(".line")); save();
  }
});
doc.addEventListener("input", (e) => {
  const b = e.target.closest(".line"); if (!b) return;
  setState(b, E.after_edit(stateOf(b)));   // a result no longer matches edited text
  save();
});
// Pasting keeps only the text.
doc.addEventListener("paste", (e) => {
  if (!e.target.closest(".block__text")) return;
  e.preventDefault();
  document.execCommand("insertText", false, e.clipboardData.getData("text/plain").replace(/\s*\n\s*/g, " "));
});

$("kind").addEventListener("pick", (e) => {
  if (!current) return;
  const toTitle = e.detail.dataset.kind === "title";
  current.classList.toggle("block--title", toTitle);
  setState(current, toTitle ? S.title : S.empty);
  syncSize(); save();
});

// GDD.md: one line per block; "# " marks a title. It is saved a moment after the last key, to the project
// the document was read from (saveTo): if the page moves to another conversation first, it is saved at once.
let saveT = null, saveTo = "";
function saveNow() {
  if (saveT === null) return;
  clearTimeout(saveT); saveT = null;
  const out = lines().filter((b) => textOf(b)).map((b) => (isTitle(b) ? "# " : "") + textOf(b));
  api(saveTo, out.join("\n") + "\n").catch(() => {});
  renderLaws();
}
function save() {
  clearTimeout(saveT);
  saveTo = project("file/GDD.md");
  saveT = setTimeout(saveNow, 400);
}

// =========================================================
// Generate
// =========================================================
const pending = () => lines().filter((b) => !isTitle(b) && textOf(b) && E.is_pending(stateOf(b)));
function syncGen() {
  $("gen").disabled = !E.can_generate(running, pending().length);
  $("gen-label").textContent = running ? "Generating…" : "Generate LAWs";
  document.querySelectorAll(".agent__item[data-id='claude'], .agent__item[data-id='codex']").forEach((b) => b.disabled = running);
}

// The thread ties each sentence to its law while the agent works (Bend-UI).
const thread = createThread(doc);

$("gen").addEventListener("click", async () => {
  if (!conn.active) { const a = visible(); a.open(); a.ask(true); return; }   // no AI yet: ask for one
  running = true; syncGen();
  const list = pending();
  setView("laws");
  await thread.begin(list.map((b) => b.parentElement));
  for (const [i, b] of list.entries()) {
    if (!conn.active || !b.isConnected) continue;
    const sentence = textOf(b);
    agents.lg.lookAtEl(b); agents.sm.lookAtEl(b);
    await Promise.all([setState(b, S.busy, "", "open"), thread.start(i)]);
    const { good, out } = await writeLaw(sentence);
    if (!b.isConnected) continue;                       // deleted while the agent worked
    const edited = textOf(b) !== sentence;
    const next = E.after_result(edited, good);
    await Promise.all([setState(b, next, next === S.empty ? "" : out, "form"), thread.done(i, next === S.ok)]);
  }
  agents.lg.lookAtEl(null); agents.sm.lookAtEl(null);
  running = false; syncGen();
  await thread.end();
  await thread.release();
  await loadLaws();
  ensureLine();
});

// The law agent writes one sentence's law; the server checks it with Bend.
async function writeLaw(sentence) {
  let good = false, out = "";
  try {
    const r = await api(project("generate/" + conn.active), sentence);
    const nl = r.text.indexOf("\n");
    good = r.text.slice(0, nl) === "ok";
    out = r.text.slice(nl + 1).trim();
    if (good) out = out.split("\n").filter((l) => !/^# LAW: /.test(l)).join("\n");   // the sentence is already above it
    if (!good) agentFailed(out);
  } catch {
    out = "The LawEditor server isn't running."; lose("server");
  }
  return { good, out };
}

// The document always ends with an empty line to write in (EDITOR.bend: needs_line).
function ensureLine() {
  const last = lines().at(-1);
  if (E.needs_line(!!last && !textOf(last))) makeBlock("text");
}

// An error that means the agent itself can't run: drop the connection, ask again.
function agentFailed(out) {
  if (/Could not start the agent/i.test(out)) lose("notfound");
  else if (/auth|log ?in|api key|credential/i.test(out)) lose("nologin");
}

// =========================================================
// Agent: Claude or Codex
// =========================================================
const AIS = [
  { id: "claude", name: "Claude", mark: `<img src="${claudeMark}" alt="">` },
  { id: "codex", name: "Codex", mark: `<img src="${openaiMark}" alt="">` },
];
const conn = { active: null, status: {}, reason: {} };
const REASON = { notfound: "not found", nologin: "not logged in", lost: "disconnected", server: "server not running" };

const items = (control) => [control, ...AIS.map((a) => ({ id: a.id, mark: a.mark, label: a.name, ring: true }))];
const agents = {
  lg: mountAgent($("agent-lg"), { size: "lg", open: "hover", items: items({ id: "min", icon: "minimize-2", label: "Minimize" }), onPick: (id) => pick(id) }),
  sm: mountAgent($("agent-sm"), { size: "sm", open: "hover", items: items({ id: "max", icon: "maximize-2", label: "Expand" }), onPick: (id) => pick(id) }),
};
const visible = () => agents[win.dataset.agent];
const both = (fn) => { fn(agents.lg); fn(agents.sm); };

function renderAgents() {
  for (const a of AIS) {
    const st = conn.status[a.id] || "";
    const label = st === "busy" ? "Connecting…" : st === "error" ? `${a.name} ${REASON[conn.reason[a.id]]}` : conn.active === a.id ? `${a.name} · connected` : a.name;
    both((ag) => ag.setItem(a.id, { status: st === "ok" && conn.active !== a.id ? "" : st, label, pressed: conn.active === a.id }));
  }
}

function pick(id) {
  if (id === "min") return swap("sm");
  if (id === "max") return swap("lg");
  connect(id);
}

async function connect(id) {
  if (running || conn.status[id] === "busy" || conn.active === id) return;
  conn.status[id] = "busy"; renderAgents();
  let ok = false, reason = "notfound";
  try { const r = await api("/api/connect/" + id); ok = r.ok; }
  catch { reason = "server"; }
  conn.status[id] = ok ? "ok" : "error";
  conn.reason[id] = ok ? "" : reason;
  if (ok) { conn.active = id; visible().spin(); both((a) => a.ask(false)); try { localStorage.setItem("laweditor.ai", id); } catch {} }
  else visible().shake();
  renderAgents(); both((a) => a.flash(id));
}

function lose(reason) {
  const id = conn.active; if (!id) return;
  conn.status[id] = "error"; conn.reason[id] = reason; conn.active = null;
  visible().shake(); renderAgents(); both((a) => a.flash(id));
}

// Minimize / expand: the face flies between the corner and the toolbar.
function swap(to) {
  const from = win.dataset.agent; if (from === to) return;
  agents[from].close();
  const rect = agents[from].face.getBoundingClientRect();
  win.dataset.agent = to;
  try { localStorage.setItem("laweditor.agent", to); } catch {}
  flyBetween(rect, agents[to]);
}

// =========================================================
// Laws view: what the agent wrote. Read only; hold the lock to edit.
// =========================================================
let typesSrc = "", lawsSrc = "";
async function loadLaws() {
  [lawsSrc, typesSrc] = await Promise.all([readFile("LAWS.bend"), readFile("TYPES.bend")]);
  laws = parseLaws(lawsSrc);
  renderLaws();
}
function renderLaws() {
  const list = $("laws-list"); list.innerHTML = "";
  const inDoc = new Set(lines().filter((b) => !isTitle(b)).map(textOf));
  if (!laws.length) list.innerHTML = '<p class="detail doc__note">No laws yet. Write a rule in the document and generate.</p>';
  for (const l of laws) {
    const orphan = !inDoc.has(l.sentence);   // its sentence was deleted: keep the law, flag it
    const b = document.createElement("div");
    b.className = "block block--still";   // only read here: nothing to pick
    b.innerHTML = `<div class="block__slot"><span class="dot ${orphan ? "dot--warning" : "dot--success"}"></span></div><div class="block__text"></div><pre class="block__out"></pre>`;
    b.querySelector(".block__text").textContent = l.sentence + (orphan ? "  (sentence deleted)" : "");
    b.querySelector(".block__out").textContent = l.code.split("\n").slice(1).join("\n");
    list.append(b);
  }
  $("types-code").textContent = typesSrc.trim() || "import Base";
  highlight($("types-code").parentElement);
}

// Hold to edit: the ring fills in amber; let go early and nothing happens.
const unlock = $("unlock");
let holdT;
unlock.addEventListener("pointerdown", () => {
  unlock.dataset.status = "hold";
  holdT = setTimeout(() => { unlock.dataset.status = "warn"; editLaws(true); }, 960);
});
["pointerup", "pointerleave", "pointercancel"].forEach((ev) => unlock.addEventListener(ev, () => {
  clearTimeout(holdT); if (unlock.dataset.status === "hold") delete unlock.dataset.status;
}));
function editLaws(on) {
  $("laws-read").hidden = on; $("laws-edit").hidden = !on;
  $("laws-note").textContent = on ? "Editing. Laws you change here are yours: the agent never rewrites them." : "Hold the lock to edit.";
  if (on) { $("laws-src").value = lawsSrc; $("types-src").value = typesSrc; }
  else delete unlock.dataset.status;
}
$("edit-cancel").addEventListener("click", () => editLaws(false));
$("edit-save").addEventListener("click", async () => {
  await writeFile("LAWS.bend", $("laws-src").value);
  await writeFile("TYPES.bend", $("types-src").value);
  editLaws(false);
  await loadLaws();
  refreshDocStates();
});
// A sentence whose law was removed by hand goes back to empty; one whose law exists is green.
function refreshDocStates() {
  lines().forEach((b) => {
    if (isTitle(b) || !textOf(b) || stateOf(b) === S.busy) return;
    const l = lawFor(textOf(b));
    if (l) setState(b, S.ok, l.code.split("\n").slice(1).join("\n"));
    else if (stateOf(b) === S.ok) setState(b, S.empty);
  });
}

// =========================================================
// Side bar, views, full screen
// =========================================================
// The side bar opens and closes by itself (Bend-UI: data-side-toggle). The page only remembers how the
// person left it, for the next time (on a wide screen: a narrow one always starts with it away).
const side = $("side");
try { if (!isNarrow() && localStorage.getItem("laweditor.side") === "open") setSide(side, true); } catch {}
new MutationObserver(() => { if (!isNarrow()) try { localStorage.setItem("laweditor.side", side.classList.contains("is-open") ? "open" : "closed"); } catch {} }).observe(side, { attributes: true, attributeFilter: ["class"] });
side.querySelectorAll("[data-view]").forEach((b) => b.addEventListener("click", () => {
  side.querySelectorAll("[data-view]").forEach((x) => x === b ? x.setAttribute("aria-current", "page") : x.removeAttribute("aria-current"));
  const laws = b.dataset.view === "doc";
  document.querySelectorAll(".doc-only").forEach((x) => x.hidden = !laws);
  if (laws) setView(lawView);
  else for (const s of ["doc", "laws", "context"]) $("view-" + s).hidden = true;   // chat.js shows Chat
  if (laws) loadDoc();   // the project's files as they are now: the chat may have added a sentence
  if (isNarrow()) setSide(side, false);
}));

// Laws shows the document (its selector: sentences, with laws, or split), or, from their own buttons,
// its files (LAWS.bend, TYPES.bend) or its context (AGENT.md, what the law agent is told).
// show: false only remembers it (Chat is open).
const VIEW_CLASS = { sentences: [], laws: ["doc--stack"], split: ["doc--split", "doc--wide"] };
const VIEW_SECTION = { sentences: "doc", laws: "doc", split: "doc", files: "laws", context: "context" };
let lawView = "sentences", docView = "sentences";
function setView(v, show = true) {
  lawView = v;
  if (VIEW_CLASS[v]) docView = v;
  if (VIEW_CLASS[v]) { doc.classList.remove("doc--stack", "doc--split", "doc--wide"); doc.classList.add(...VIEW_CLASS[v]); }
  $("view").querySelectorAll("button").forEach((b) => b.setAttribute("aria-pressed", b.dataset.view === v));
  for (const b of [$("files-btn"), $("context-btn")]) b.setAttribute("aria-pressed", String(b.dataset.view === v));
  try { localStorage.setItem("laweditor.view", v); } catch {}
  if (!show) return;
  for (const s of ["doc", "laws", "context"]) $("view-" + s).hidden = s !== VIEW_SECTION[v];
  $("kind").hidden = $("gen").hidden = VIEW_SECTION[v] !== "doc";   // they act on the document
  if (v === "files") { editLaws(false); loadLaws(); }
}
$("view").addEventListener("change", (e) => setView(e.detail.dataset.view));
// Files and Context: a second click goes back to the document.
for (const b of [$("files-btn"), $("context-btn")]) b.addEventListener("click", () => setView(lawView === b.dataset.view ? docView : b.dataset.view));
try { const v = localStorage.getItem("laweditor.view"); if (v in VIEW_SECTION) setView(v, false); } catch {}

$("full").addEventListener("click", (e) => {
  const full = win.classList.toggle("is-full");
  const label = full ? "Exit full screen" : "Full screen";
  e.currentTarget.title = label; e.currentTarget.setAttribute("aria-label", label);
  e.currentTarget.querySelector("use").setAttribute("href", full ? "#i-minimize" : "#i-maximize");
});

// =========================================================
// The document of the open conversation's project
// =========================================================
// Read again whenever it may have changed under the page: the page moved to another conversation
// ("laweditor:where"), the chat added a sentence or its law was written ("laweditor:changed"), or Laws
// is shown. Not while the person's own change waits to be saved, or the law agent runs from this page.
let loading = 0;
async function loadDoc() {
  if (running || saveT !== null) return;
  const me = ++loading;
  const gdd = await readFile("GDD.md");
  await loadLaws();
  if (me !== loading || running || saveT !== null) return;
  const had = document.activeElement?.closest?.("#doc");
  doc.querySelectorAll(".pair").forEach((x) => x.remove());
  current = null;
  for (const line of gdd.split("\n").filter((l) => l.trim())) {
    const title = line.startsWith("# ");
    const text = title ? line.slice(2) : line;
    const b = makeBlock(title ? "title" : "text", text);
    const l = !title && lawFor(text);
    if (l) setState(b, S.ok, l.code.split("\n").slice(1).join("\n"));
  }
  const last = makeBlock("text");
  if (had) focusEnd(last);
  renderLaws(); syncGen();
}
document.addEventListener("laweditor:where", () => { saveNow(); loadDoc(); });
document.addEventListener("laweditor:changed", loadDoc);

// =========================================================
// Start: load the project, reconnect the last AI
// =========================================================
(async function start() {
  try { const saved = localStorage.getItem("laweditor.agent"); if (saved) win.dataset.agent = saved; } catch {}
  if (isNarrow()) win.dataset.agent = "sm";

  let agentMd = ""; try { agentMd = await get("/api/told/AGENT.md"); } catch {}
  $("agent-md").innerHTML = markdown(agentMd || "# AGENT.md not found");
  $("agent-md").querySelectorAll("pre").forEach((pre) => highlight(pre));
  await loadDoc();
  renderAgents();

  try { const ai = localStorage.getItem("laweditor.ai"); if (ai) connect(ai); } catch {}
})();
