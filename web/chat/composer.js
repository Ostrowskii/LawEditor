// The composer: one field with the send button inside. When Send is on is CHAT.bend.
// While the agent answers, the send button is Stop (Bend-UI's .composer__stop, a square): onStop ends the turn.
// Typing / at the start lists the commands (CHAT.bend's commands); typing @ lists the project's files
// (files(): the server's list), and a picked file becomes a chip above the text (.composer__chips). The
// message goes out with its files: onSend(text, files). Whether the chat answers or a question waits comes
// from the conversation itself (set): the composer doesn't guess.
import C from "../../harness/CHAT.bend";
import { busy, done as doneBtn } from "bend-ui";
import { esc } from "../where.js";

export function createComposer(form, { onSend, onStop, onCommand, files: listFiles }) {
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
  let projectFiles = [];
  const word = () => { const before = text.value.slice(0, text.selectionStart); const m = before.match(/(^|\s)@([^\s@]*)$/); return m ? m[2] : null; };
  function close() { menu.hidden = true; list = []; kind = ""; }
  function draw() {
    if (!list.length) return close();
    menu.hidden = false;
    menu.innerHTML = list.map(([name, about], i) => `<button class="menu__item" type="button" role="option" data-i="${i}"${i === pick ? ' aria-selected="true"' : ""}><span class="mono">${esc(name)}</span>${about ? `<span class="menu__desc">${esc(about)}</span>` : ""}</button>`).join("");
  }
  async function suggest() {
    const v = text.value, at = word();
    if (/^\/\S*$/.test(v)) { kind = "/"; list = commands.filter(([c]) => c.startsWith(v) || (v === "/" && c === "!")); }
    else if (at !== null) { kind = "@"; projectFiles = await listFiles(); list = projectFiles.filter((f) => f.toLowerCase().includes(at.toLowerCase()) && !files.includes(f)).slice(0, 8).map((f) => [f, ""]); }
    else return close();
    pick = 0; draw();
  }
  function choose(i) {
    const [name] = list[i] || []; if (!name) return;
    if (kind === "/" && name === "!") { text.value = "!"; close(); sync(); text.focus(); return; }   // goes on typing the command
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
  form.addEventListener("submit", (e) => {
    e.preventDefault();
    if (answering && !asking) { onStop(); return; }
    const t = text.value.trim();
    if (!C.can_send(asking, answering, t.length)) return;
    const sent = files; files = []; chips(); close();
    text.value = ""; answering = true; sync();
    onSend(t, sent);
  });
  sync();
  // What the conversation is doing: the chat answers (Send is Stop), or a question waits for the person
  // (the field is off, and says why, until they answer).
  const placeholder = text.placeholder;
  function set(isAnswering, isAsking) {
    const freed = (answering || asking) && !isAnswering && !isAsking;
    answering = isAnswering; asking = isAsking; text.disabled = isAsking;
    text.placeholder = isAsking ? "Answer the question to keep talking" : placeholder;
    sync(); if (freed && !form.hidden) text.focus();
  }

  // ---------- A question takes the message box's place (Bend-UI's .ask) ----------
  // Where the person answers is where the chat asks: the question, what it is about (body: a code block,
  // a note, a rule's sentence) and its answers ([{ label, value, main }]). ask() waits for a click.
  // Every button but the main one is bordered and "async": clicked, it turns while the answer goes,
  // then shows its check, and the message box comes back.
  const box = form.querySelector(".composer__box"), dock = form.querySelector(".ask");
  let asked = null;
  function ask(id, { title, body = "", answers }) {
    return new Promise((done) => {
      asked = id;
      dock.innerHTML = `<div class="turn__row"><div class="turn__mark"><span class="dot dot--warning"></span></div><div class="turn__main"><span class="ask__title" id="question-title"></span>${body}<div class="turn__actions"></div></div></div>`;
      dock.querySelector(".ask__title").textContent = title;
      const actions = dock.querySelector(".turn__actions");
      for (const a of answers) {
        const b = document.createElement("button");
        b.className = a.main ? "btn btn--sm btn--primary" : "btn btn--sm btn--bordered btn--async"; b.type = "button";
        if (!a.main) b.innerHTML = '<svg class="icon btn__done" aria-hidden="true"><use href="#i-check"/></svg><span class="btn__label"></span><svg class="btn__spin" viewBox="0 0 20 20" aria-hidden="true"><circle cx="10" cy="10" r="8" pathLength="100"/></svg>';
        (b.querySelector(".btn__label") || b).textContent = a.label;
        b.addEventListener("click", () => {
          actions.querySelectorAll(".btn").forEach((x) => x !== b && (x.disabled = true));
          if (a.main) b.disabled = true; else busy(b, true);
          done(a.value);
        });
        actions.append(b);
      }
      box.hidden = true; dock.hidden = false;
      if (!form.hidden) dock.focus({ preventScroll: true });   // the question, not a button: Enter alone answers nothing
    });
  }
  // The question was answered (here, or in another window): id, or nothing for whichever one shows.
  function answered(id) {
    if (asked === null || (id !== undefined && asked !== id)) return;
    asked = null;
    const close = () => { if (asked !== null) return; dock.hidden = true; dock.replaceChildren(); box.hidden = false; if (!text.disabled && !form.hidden) text.focus(); };
    const b = dock.querySelector('[aria-busy="true"]');
    if (b && id !== undefined) { doneBtn(b, b.textContent.trim()); setTimeout(close, 600); } else close();
  }
  // What a message starts with, put there for the person to go on writing (a comment on a part of the page).
  // A start put before, and not yet written after, gives its place to the new one.
  let start = "";
  function write(prefix) {
    if (text.disabled) return;
    text.value = prefix + (start && text.value.startsWith(start) ? text.value.slice(start.length) : text.value);
    start = prefix; sync(); text.focus(); text.setSelectionRange(text.value.length, text.value.length);
  }
  return { focus: () => text.focus(), set, ask, answered, write };
}
