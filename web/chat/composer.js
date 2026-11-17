// The composer: one field with the send button inside. When Send is on is CHAT.bend.
// While the agent answers, the send button is Stop (Bend-UI's .composer__stop, a square): onStop ends the turn.
// Typing / at the start lists the commands (CHAT.bend's commands); typing @ lists the project's files
// (GET /api/files), and a picked file becomes a chip above the text (.composer__chips). The message goes out
// with its files: onSend(text, files).
import C from "../../CHAT.bend";

const esc = (s) => s.replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]));

export function createComposer(form, onSend, onStop = () => {}, onCommand = () => {}) {
  const text = form.querySelector(".composer__text"), send = form.querySelector(".composer__send");
  const field = form.querySelector(".composer__field"), menu = form.querySelector("#suggest");
  let answering = false, asking = false, files = [], list = [], pick = 0, kind = "";
  const arrow = send.innerHTML, square = '<svg class="icon" viewBox="0 0 24 24" aria-hidden="true"><rect x="7" y="7" width="10" height="10" rx="1" fill="currentColor" stroke="none"/></svg>';
  const sync = () => {
    const stop = answering && !asking;
    send.classList.toggle("composer__stop", stop);
    send.innerHTML = stop ? square : arrow;
    send.setAttribute("aria-label", stop ? "Stop" : "Send"); send.title = stop ? "Stop" : "Send";
    send.disabled = !stop && !C.can_send(asking, answering, text.value.trim().length);
  };

  // ---------- Suggestions: / commands and @ files ----------
  const commands = C.commands().split("\n").map((l) => l.split("\t"));
  let projectFiles = null;
  const loadFiles = async () => { try { projectFiles = (await (await fetch("/api/files")).text()).split("\n").filter(Boolean); } catch { projectFiles = []; } };
  const word = () => { const before = text.value.slice(0, text.selectionStart); const m = before.match(/(^|\s)@([^\s@]*)$/); return m ? m[2] : null; };
  function close() { menu.hidden = true; list = []; kind = ""; }
  function draw() {
    if (!list.length) return close();
    menu.hidden = false;
    menu.innerHTML = list.map(([name, about], i) => `<button class="menu__item" type="button" role="option" data-i="${i}"${i === pick ? ' aria-selected="true"' : ""}><span class="mono">${esc(name)}</span>${about ? `<span class="menu__desc">${esc(about)}</span>` : ""}</button>`).join("");
  }
  async function suggest() {
    const v = text.value, at = word();
    if (/^\/\S*$/.test(v)) { kind = "/"; list = commands.filter(([c]) => c.startsWith(v)); }
    else if (at !== null) { kind = "@"; if (!projectFiles) await loadFiles(); list = projectFiles.filter((f) => f.toLowerCase().includes(at.toLowerCase()) && !files.includes(f)).slice(0, 8).map((f) => [f, ""]); }
    else return close();
    pick = 0; draw();
  }
  function choose(i) {
    const [name] = list[i] || []; if (!name) return;
    if (kind === "/") { text.value = ""; close(); sync(); onCommand(name); return; }
    files.push(name); chips();
    const pos = text.selectionStart, before = text.value.slice(0, pos).replace(/@[^\s@]*$/, "");
    text.value = before + text.value.slice(pos); text.focus(); text.setSelectionRange(before.length, before.length);
    close(); sync();
  }
  function chips() {
    let box = field.querySelector(".composer__chips");
    if (!files.length) { box?.remove(); return; }
    if (!box) { box = document.createElement("div"); box.className = "composer__chips"; field.prepend(box); }
    box.innerHTML = files.map((f, i) => `<span class="tag tag--mono">@${esc(f)}<button class="btn btn--plain btn--icon btn--sm" type="button" data-remove="${i}" aria-label="Remove ${esc(f)}"><svg class="icon icon--sm" aria-hidden="true"><use href="#i-x"/></svg></button></span>`).join("");
  }
  field.addEventListener("click", (e) => { const b = e.target.closest("[data-remove]"); if (b) { files.splice(Number(b.dataset.remove), 1); chips(); text.focus(); } });
  menu.addEventListener("mousedown", (e) => e.preventDefault());
  menu.addEventListener("click", (e) => { const b = e.target.closest("[data-i]"); if (b) choose(Number(b.dataset.i)); });
  text.addEventListener("blur", () => setTimeout(close, 100));

  text.addEventListener("input", () => { sync(); suggest(); });
  text.addEventListener("keydown", (e) => {
    if (!menu.hidden && list.length) {
      if (e.key === "ArrowDown" || e.key === "ArrowUp") { e.preventDefault(); pick = (pick + (e.key === "ArrowDown" ? 1 : list.length - 1)) % list.length; draw(); return; }
      if (e.key === "Enter" || e.key === "Tab") { e.preventDefault(); choose(pick); return; }
      if (e.key === "Escape") { e.preventDefault(); close(); return; }
    }
    if (e.key === "Enter" && !e.shiftKey) { e.preventDefault(); form.requestSubmit(); }
  });
  form.addEventListener("submit", async (e) => {
    e.preventDefault();
    if (answering) { onStop(); return; }
    const t = text.value.trim();
    if (!C.can_send(asking, answering, t.length)) return;
    const sent = files; files = []; chips(); close();
    text.value = ""; answering = true; sync();
    await onSend(t, sent);
    answering = false; sync(); text.focus();
  });
  sync();
  // A question waits for the person: the field is off, and says why, until they answer.
  const placeholder = text.placeholder;
  function hold(on) {
    asking = on; text.disabled = on;
    text.placeholder = on ? "Answer the question above to keep talking" : placeholder;
    sync(); if (!on) text.focus();
  }
  return { focus: () => text.focus(), hold, forget: () => { projectFiles = null; } };
}
