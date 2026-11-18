// Where a new conversation goes: the button under the message box (Bend-UI dropdown). Nothing has to be
// picked: it says "New project", and the first message starts one (the server gives the conversation a
// folder; the chat names the game: CHAT.md, GAME:). The menu puts the conversation in a game that exists,
// or in a folder of the computer (POST /api/open-folder: the computer's own folder chooser).
// Once the conversation has begun it stays where it is: the button gives way to the game's name.
import { get, post, menuItem, esc, icon } from "../where.js";

export function createPlace(dd, tag) {
  const button = dd.querySelector("[aria-haspopup]"), label = button.querySelector("span"), menu = dd.querySelector(".menu");
  let games = [], chosen = null;   // chosen: { key, name }, or null for a new project
  function draw() {
    label.textContent = chosen ? chosen.name : "New project";
    menu.innerHTML = menuItem("New project", { data: 'data-key=""', checked: !chosen, lead: "plus" })
      + games.map(([k, n]) => menuItem(n, { data: `data-key="${esc(k)}"`, checked: chosen?.key === k, lead: "folder" })).join("")
      + '<hr class="separator">' + menuItem("Open a folder…", { data: "data-open", lead: "external-link" });
  }
  async function load() {
    try { games = (await get("/api/projects")).split("\n").filter(Boolean).map((l) => l.split("\t")); } catch { games = []; }
    draw();
  }
  dd.addEventListener("pick", async (e) => {
    const d = e.detail?.dataset; if (!d) return;
    if ("open" in d) {
      const [k, name] = (await post("/api/open-folder")).split("\t");
      if (k) { await load(); chosen = { key: k, name: name || k }; }
      draw(); return;
    }
    chosen = d.key ? { key: d.key, name: (games.find(([g]) => g === d.key) || [])[1] || d.key } : null;
    draw();
  });
  button.addEventListener("click", () => { if (menu.hidden) load(); });   // opening: the games as they are now
  load();
  return {
    chosen: () => chosen,
    choose(k, name) { chosen = { key: k, name }; draw(); },
    // A new conversation: the button again, on "New project".
    open() { chosen = null; dd.hidden = false; tag.hidden = true; load(); },
    // The conversation has begun: its game's name shows (nothing while it has none), and nothing is picked.
    lock(name) { dd.hidden = true; tag.hidden = !name; tag.innerHTML = name ? icon("folder", true) + esc(name) : ""; },
  };
}
