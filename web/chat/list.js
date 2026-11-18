// The conversations, in the side bar: every one, the one that moved last first. Each shows its state
// (a dot while the chat works, another while it waits for the person) and its game's name. Its menu (…)
// renames the game, opens its folder, or deletes the conversation (it goes to the project's
// .laweditor/trash: nothing is lost). GET /api/conversations: the server's list, read again every while.
import { get, post, esc, icon, menuItem } from "../where.js";

const DOT = { working: "dot dot--busy", asking: "dot dot--warning" };
const SAYS = { working: "working", asking: "waits for you" };

export function createList(box, { current, onOpen, onMoved, onGone }) {
  let text = null, editing = false;
  function draw(rows) {
    box.replaceChildren(...rows.map(([key, game, id, state, title]) => {
      const row = document.createElement("div");
      row.className = "side__row";
      const name = title || "New conversation";
      row.innerHTML = `<button class="btn btn--plain btn--neutral" type="button"${id === current() ? ' aria-current="page"' : ""}>`
        + (DOT[state] ? `<span class="${DOT[state]}" role="img" aria-label="${SAYS[state]}"></span>` : "")
        + `<span class="side__text">${esc(name)}</span>${game ? `<span class="tag">${esc(game)}</span>` : ""}</button>`
        + `<div class="dropdown side__more"><button class="btn btn--plain btn--neutral btn--icon btn--sm" type="button" aria-haspopup="menu" aria-expanded="false" aria-label="Actions for ${esc(name)}">${icon("ellipsis")}</button>`
        + `<div class="menu menu--end" role="menu" hidden>${game ? menuItem("Rename the game", { data: 'data-act="rename"', lead: "pencil" }) : ""}`
        + menuItem("Open its folder", { data: 'data-act="folder"', lead: "folder" }) + '<hr class="separator">'
        + menuItem("Delete conversation", { data: 'data-act="delete"', lead: "trash-2" }) + "</div></div>";
      row.firstChild.addEventListener("click", () => onOpen(key, id));
      row.lastChild.addEventListener("pick", (e) => act(e.detail.dataset.act, row, key, game, id));
      return row;
    }));
  }
  // The game's name turns into a field: Enter keeps the new name, Escape the old one.
  function rename(row, key, game) {
    editing = true;
    const f = document.createElement("input");
    f.className = "input input--sm"; f.value = game; f.setAttribute("aria-label", "Name of the game");
    row.replaceChildren(f); f.focus(); f.select();
    let done = false;
    const end = async (keep) => {
      if (done) return; done = true;
      const n = f.value.trim();
      if (keep && n && n !== game) await post(`/api/p/${encodeURIComponent(key)}/rename`, n);
      editing = false; refresh(true);
    };
    f.addEventListener("keydown", (e) => { if (e.key === "Enter") end(true); if (e.key === "Escape") end(false); });
    f.addEventListener("blur", () => end(true));
  }
  // Deleting asks once more, in the row itself.
  function confirm(row, key, id) {
    editing = true;
    row.innerHTML = '<span class="side__text detail">Delete it?</span><button class="btn btn--plain btn--neutral btn--sm" type="button">Keep</button><button class="btn btn--tinted btn--danger btn--sm" type="button">Delete</button>';
    const [, keep, del] = row.children;
    const end = () => { editing = false; refresh(true); };
    keep.addEventListener("click", end);
    del.addEventListener("click", async () => { await post(`/api/c/${encodeURIComponent(key)}/${id}/delete`); if (id === current()) onGone(); end(); });
    keep.focus();
  }
  function act(what, row, key, game, id) {
    if (what === "rename") rename(row, key, game);
    if (what === "folder") post(`/api/p/${encodeURIComponent(key)}/open`);
    if (what === "delete") confirm(row, key, id);
  }
  // force: draw even if the server's list didn't change (the open conversation did).
  async function refresh(force = false) {
    if (editing) return;
    let got = ""; try { got = await get("/api/conversations"); } catch { return; }
    const rows = got.split("\n").filter(Boolean).map((l) => l.split("\t"));
    document.dispatchEvent(new CustomEvent("laweditor:list", { detail: rows }));   // the compact view counts them
    const mine = rows.find((r) => r[2] === current());
    if (mine) onMoved(mine[0], mine[1]);   // its project got its folder and name (the game was born)
    if (!force && got === text) return;
    text = got;
    box.closest(".side__section").hidden = !rows.length;
    draw(rows);
  }
  setInterval(refresh, 1500);
  refresh();
  return { refresh: () => refresh(true) };
}
