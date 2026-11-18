// The conversations, in the side bar: every one, the one that moved last first. Each shows its state
// (a dot while the chat works, another while it waits for the person) and its project's name. Its menu (…)
// renames the project, opens its folder, or deletes the conversation (it goes to the project's
// .laweditor/trash: nothing is lost). GET /api/conversations: the server's list, read again every while.
import { get, post, esc, icon, menuItem } from "../where.js";

const DOT = { working: "dot dot--busy", asking: "dot dot--warning" };
const SAYS = { working: "working", asking: "waits for you" };

export function createList(box, { current, onOpen, onMoved, onGone }) {
  let text = null, editing = false;
  function draw(rows) {
    box.replaceChildren(...rows.map(([key, project, id, state, title]) => {
      const row = document.createElement("div");
      row.className = "side__row";
      const name = title || "New conversation";
      row.innerHTML = `<button class="btn btn--ghost" type="button"${id === current() ? ' aria-current="page"' : ""}>`
        + (DOT[state] ? `<span class="${DOT[state]}" role="img" aria-label="${SAYS[state]}"></span>` : '<span class="dot" aria-hidden="true"></span>')   // an empty dot: nothing going on; every title starts at the same place
        + `<span class="side__text">${esc(name)}</span>${project ? `<span class="tag">${esc(project)}</span>` : ""}</button>`
        + `<div class="dropdown side__more"><button class="btn btn--ghost btn--icon btn--sm" type="button" aria-haspopup="menu" aria-expanded="false" aria-label="Actions for ${esc(name)}">${icon("ellipsis")}</button>`
        + `<div class="menu menu--end" role="menu" hidden>${project ? menuItem("Rename the project", { data: 'data-act="rename"', lead: "pencil" }) : ""}`
        + menuItem("Open its folder", { data: 'data-act="folder"', lead: "folder" }) + '<hr class="separator">'
        + menuItem("Delete conversation", { data: 'data-act="delete"', lead: "trash-2" }) + "</div></div>";
      row.firstChild.addEventListener("click", () => onOpen(key, id));
      row.lastChild.addEventListener("pick", (e) => act(e.detail.dataset.act, row, key, project, id));
      return row;
    }));
  }
  // The project's name turns into a field: Enter keeps the new name, Escape the old one.
  function rename(row, key, name) {
    editing = true;
    const f = document.createElement("input");
    f.className = "input input--sm"; f.value = name; f.setAttribute("aria-label", "Name of the project");
    row.replaceChildren(f); f.focus(); f.select();
    let done = false;
    const end = async (keep) => {
      if (done) return; done = true;
      const n = f.value.trim();
      if (keep && n && n !== name) await post(`/api/p/${encodeURIComponent(key)}/rename`, n);
      editing = false; refresh(true);
    };
    f.addEventListener("keydown", (e) => { if (e.key === "Enter") end(true); if (e.key === "Escape") end(false); });
    f.addEventListener("blur", () => end(true));
  }
  // Deleting asks once more: the row's menu opens again, on the question. (Plain items: a button in a
  // menu inside the side bar would take the side bar's width.)
  function confirm(row) {
    const dd = row.querySelector(".side__more"), menu = dd.querySelector(".menu"), button = dd.querySelector("[aria-haspopup]");
    editing = true;
    menu.innerHTML = '<p class="menu__empty">Delete this conversation? It goes to the project\'s trash folder.</p>'
      + menuItem("Delete it", { data: 'data-act="deleted"', lead: "trash-2" }) + menuItem("Keep it", { data: 'data-act="kept"', lead: "x" });
    setTimeout(() => {
      button.click();
      // Closed without an answer: the row is as it was.
      menu.addEventListener("toggle", (e) => { if (e.newState === "closed") setTimeout(() => { if (editing) { editing = false; refresh(true); } }, 50); });
    });
  }
  async function forget(key, id) {
    await post(`/api/c/${encodeURIComponent(key)}/${id}/delete`);
    editing = false;
    if (id === current()) onGone(); else refresh(true);
  }
  function act(what, row, key, project, id) {
    if (what === "rename") rename(row, key, project);
    if (what === "folder") post(`/api/p/${encodeURIComponent(key)}/open`);
    if (what === "delete") confirm(row);
    if (what === "deleted") forget(key, id);
    if (what === "kept") { editing = false; refresh(true); }
  }
  // force: draw even if the server's list didn't change (the open conversation did).
  async function refresh(force = false) {
    if (editing) return;
    let got = ""; try { got = await get("/api/conversations"); } catch { return; }
    const rows = got.split("\n").filter(Boolean).map((l) => l.split("\t"));
    document.dispatchEvent(new CustomEvent("laweditor:list", { detail: rows }));   // the compact view counts them
    const mine = rows.find((r) => r[2] === current());
    if (mine) onMoved(mine[0], mine[1]);   // its project got its folder and name
    if (!force && got === text) return;
    text = got;
    box.closest(".side__section").hidden = !rows.length;
    draw(rows);
  }
  setInterval(refresh, 1500);
  refresh();
  return { refresh: () => refresh(true) };
}
