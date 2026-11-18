// The project's files, in a pane at the right of the chat (Bend-UI's panes: pane, tree). The tree shows
// every file of the open conversation's project, with what the chat changed marked (+14 −6); a file opens
// in the pane, as it is (read only). It opens from its button in the toolbar, or from a file's name in a
// reply's "files changed". The page keeps nothing: the list and each file are asked to the server by name.
import { initPane, setPane, tree, initTree } from "bend-ui/panes";
import { codeBlock } from "bend-ui/syntax";
import A from "../harness/ASK.bend";
import { project, get, post, esc, icon } from "./where.js";

const pane = document.getElementById("files"), body = document.getElementById("files-body"), title = document.getElementById("files-title");
const LINES = 2000;   // a longer file shows its first lines
let paths = [], changed = new Map(), shown = "", open = [], files = null, isOpen = false, asked = 0;

// What the chat changed: asked by a file's name alone (ASK.bend gives the name), so every path that ends
// in it is marked.
const marks = () => Object.fromEntries(paths.map((p) => [p, changed.get(p) || changed.get(p.split("/").pop())]).filter(([, m]) => m));
const parents = (p) => p.split("/").slice(0, -1).map((_, i, a) => a.slice(0, i + 1).join("/"));

function drawTree() {
  shown = ""; title.textContent = "Files";
  if (!paths.length) { files = null; body.innerHTML = '<p class="detail">No files yet. What the chat builds shows here.</p>'; return; }
  const m = marks();
  open = [...new Set([...open, ...Object.keys(m).flatMap(parents)])];
  body.innerHTML = tree(paths, { open, marks: m, label: "Files" });
  files = initTree(body.firstElementChild, { onOpen: show, onToggle: (path, on) => { open = on ? [...new Set([...open, path])] : open.filter((p) => p !== path); } });
}
async function load() {
  const me = ++asked;
  let got = ""; try { got = await get(project("files")); } catch {}
  if (me !== asked) return;
  paths = got.split("\n").filter(Boolean);
  if (!shown) drawTree();
}
async function show(path) {
  const me = ++asked;
  shown = path; title.textContent = path;
  const text = await post(project("read"), path);
  if (me !== asked) return;
  const lines = text.split("\n"), long = lines.length > LINES;
  body.innerHTML = `<p><button class="link link--icon" type="button">${icon("chevron-left", true)}<span>All files</span></button></p>`
    + (text ? codeBlock(long ? lines.slice(0, LINES).join("\n") : text, { lang: A.extension(path), numbers: true, wrap: true, head: false }) : '<p class="detail">This file is empty, or can\'t be shown as text.</p>')
    + (long ? `<p class="detail">The first ${LINES} lines of ${lines.length}.</p>` : "");
  body.querySelector(".link").addEventListener("click", () => { drawTree(); load(); });
  body.scrollTop = 0;
}

// The corners' words step aside while the pane takes their room.
const foots = document.querySelectorAll(".window__foot");
initPane(pane, { label: "Files", onToggle(on) { isOpen = on; foots.forEach((f) => f.hidden = on); if (on) load(); } });

// A file's name in a reply: the pane opens on it.
document.addEventListener("laweditor:file", async (e) => {
  setPane(pane, true);
  await load();
  const name = e.detail, path = paths.find((p) => p === name) || paths.find((p) => p.endsWith("/" + name));
  if (path) show(path);
});
// A reply changed files: they are marked, and the tree is read again.
document.addEventListener("laweditor:changes", (e) => {
  for (const [file, add, del] of e.detail) changed.set(file, { add, del });
  if (isOpen && !shown) load();
});
// Another conversation: its project's files, and nothing marked yet.
document.addEventListener("laweditor:where", () => { changed = new Map(); open = []; shown = ""; if (isOpen) load(); });
