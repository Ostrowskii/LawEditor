// The game button under the composer (Bend-UI dropdown). It is optional: a new conversation starts with no
// game and you just write; the game is born from the conversation (CHAT.md: GAME:, server: draft, promote).
// Picking a game before the first message puts the conversation in a game that exists. Once the
// conversation has a game, the button shows it and stays: a conversation is in one game only.
// GET /api/projects answers the open one, then each game: its folder, a tab, its name.
const esc = (s) => s.replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]));

export function createGame(dd) {
  const button = dd.querySelector("[aria-haspopup]"), label = button.querySelector("span"), menu = dd.querySelector(".menu");
  let games = [], chosen = null, locked = false;
  function draw() {
    const on = chosen || null;
    label.textContent = on ? on.name : "Game";
    button.classList.toggle("btn--bordered", !!on); button.classList.toggle("btn--ghost", !on);
    button.title = locked ? `This conversation's game: ${on?.name}` : "Work on a game that exists (optional)";
    dd.hidden = locked && !on;   // a conversation with no game yet: nothing to show
    menu.innerHTML = locked && !on ? ""
      : locked
      ? `<button class="menu__item" type="button" role="menuitemradio" aria-checked="true" disabled><span>${esc(on.name)}</span><svg class="icon icon--sm menu__check"><use href="#i-check"/></svg></button><p class="menu__empty">A conversation stays in one game. For another, start a new conversation.</p>`
      : `<button class="menu__item" type="button" role="menuitemradio" aria-checked="${!on}" data-folder=""><span>No game yet</span><svg class="icon icon--sm menu__check"><use href="#i-check"/></svg></button>`
        + games.map(([f, n]) => `<button class="menu__item" type="button" role="menuitemradio" aria-checked="${on?.folder === f}" data-folder="${esc(f)}"><span>${esc(n)}</span><svg class="icon icon--sm menu__check"><use href="#i-check"/></svg></button>`).join("");
  }
  dd.addEventListener("pick", (e) => {
    if (locked) return;
    const f = e.detail?.dataset?.folder; if (f === undefined) return;
    chosen = f ? { folder: f, name: (games.find(([g]) => g === f) || [])[1] || f } : null; draw();
  });
  async function load() {
    try { games = (await (await fetch("/api/projects")).text()).split("\n").slice(1).filter(Boolean).map((l) => l.split("\t")); } catch { games = []; }
    draw();
  }
  load();
  return {
    chosen: () => chosen,
    choose(folder, name) { chosen = { folder, name }; draw(); },
    // The conversation has begun: its game (or none yet) shows and stays.
    lock(folder, name) { locked = true; chosen = name ? { folder, name } : null; draw(); },
    reload: load,
  };
}
