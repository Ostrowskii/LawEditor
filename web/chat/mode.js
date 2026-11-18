// The chat's mode: a Bend-UI dropdown under the composer. The modes, their names, which one the chat
// starts in and which can be picked are POLICY.bend (HARNESS.md); this draws them and keeps the pick.
// A mode that asks needs an AI that can ask: picking Codex turns it off and goes back to the start mode.
// In a mode that asks, the menu also shows what the person allowed for this conversation (GATE.bend:
// the allowed_* functions read the server's file; the conversation's allowed): newest first,
// found in with Find…, taken back one by one (×) or all. The button carries the count.
import P from "../../harness/POLICY.bend";
import G from "../../harness/GATE.bend";

import { icon, get, post } from "../where.js";

// allowedAt(): where the open conversation's allowed list is asked for.
export function createMode(dd, aiDd, firstAi, allowedAt) {
  const button = dd.querySelector("[aria-haspopup]");
  const label = button.querySelector("span");
  const menu = dd.querySelector(".menu");
  let mode = Number(P.chat_mode_index()), codex = firstAi === "codex";
  let text = "", find = "";
  const items = [];
  for (let i = 0; i < Number(P.mode_count()); i++) {
    const b = document.createElement("button");
    b.className = "menu__item"; b.type = "button"; b.dataset.mode = i;
    b.setAttribute("role", "menuitemradio");
    b.innerHTML = '<span></span><svg class="icon icon--sm menu__check"><use href="#i-check"/></svg>';
    b.querySelector("span").textContent = P.mode_name(i);
    items.push(b);
  }
  menu.append(...items);

  // What was allowed: the count on the button, and a section in the menu (Bend-UI's menu__section).
  const tag = document.createElement("span");
  tag.className = "tag tag--success"; tag.hidden = true;
  label.after(tag);
  const section = document.createElement("div");
  section.className = "menu__section"; section.hidden = true;
  section.innerHTML = '<div class="menu__head"><span>Allowed in this chat</span><span class="tag tag--success"></span></div>'
    + '<div class="menu__field"><input class="input input--sm" type="search" placeholder="Find…" aria-label="Find an allowed action"></div>'
    + '<div class="menu__list"></div>'
    + '<div class="menu__foot"><span class="menu__note">Anything else still asks you.</span><button type="button" class="btn btn--sm">Stop allowing all</button></div>';
  menu.append(section);
  const count = section.querySelector(".menu__head .tag"), field = section.querySelector("input");
  const list = section.querySelector(".menu__list"), clear = section.querySelector(".menu__foot .btn");

  function row(entry) {
    const r = document.createElement("div");
    r.className = "menu__row"; r.title = G.allowed_title(entry);
    const tone = G.allowed_tone(entry);
    r.innerHTML = `<span class="menu__lead${tone ? " menu__lead--" + tone : ""}"></span><span class="menu__text mono"></span>`
      + `<button type="button" class="btn btn--ghost btn--icon btn--sm" title="Stop allowing this">${icon("x")}</button>`;
    r.querySelector(".menu__lead").textContent = G.allowed_kind(entry);
    r.querySelector(".menu__text").textContent = G.allowed_what(entry);
    const x = r.querySelector("button");
    x.setAttribute("aria-label", "Stop allowing " + G.allowed_what(entry));
    x.addEventListener("click", () => takeBack(entry));
    return r;
  }
  function drawAllowed() {
    const n = Number(G.allowed_count(text)), on = n > 0 && !!P.mode_asks_at(mode);
    tag.hidden = !on; section.hidden = !on;
    menu.classList.toggle("menu--wide", on);
    if (!on) return;
    tag.textContent = G.allowed_tag(n);
    const shown = [];
    for (let i = 0; i < n; i++) { const e = G.allowed_at(text, i); if (G.allowed_matches(e, find)) shown.push(e); }
    list.replaceChildren(...shown.map(row));
    if (!shown.length) list.innerHTML = '<p class="menu__empty">Nothing allowed matches.</p>';
    count.textContent = G.allowed_count_text(shown.length, n, find);
  }
  async function load() {
    try { text = await get(allowedAt()); } catch {}
    drawAllowed();
  }
  async function takeBack(entry) {   // G.allowed_all_word() takes back all of them
    text = await post(allowedAt(), entry);
    if (!G.allowed_count(text)) find = "", field.value = "";
    drawAllowed();
  }
  field.addEventListener("input", () => { find = field.value; drawAllowed(); });
  clear.addEventListener("click", () => takeBack(G.allowed_all_word()));
  button.addEventListener("click", () => { if (menu.hidden) load(); });   // opening: read the file again

  function draw() {
    items.forEach((b, i) => { b.disabled = !P.mode_can_pick(i, codex); b.setAttribute("aria-checked", i === mode); });
    label.textContent = P.mode_name(mode);
    drawAllowed();
  }
  dd.addEventListener("pick", (e) => { if (!e.detail.dataset.mode) return; mode = Number(e.detail.dataset.mode); draw(); });
  aiDd.addEventListener("pick", (e) => {
    codex = e.detail.dataset.id === "codex";
    if (!P.mode_can_pick(mode, codex)) mode = Number(P.chat_mode_index());
    draw();
  });
  draw();
  // set: the offer's Switch (OFFER.bend) moves the picker, as if the person had picked it.
  // allowed: read what was allowed again (after the card's Allow for this session).
  return {
    get: () => mode,
    set(i) { if (P.mode_can_pick(i, codex)) { mode = Number(i); draw(); } },
    allowed: load,
  };
}
