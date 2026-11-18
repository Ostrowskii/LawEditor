// The terminal, in a pane under the chat (Bend-UI's panes: pane, term). It is a real shell, the person's
// own, running in the open conversation's project (engine/TERMINAL.bend). The page only moves text: what
// is typed goes to the server as a terminal would send it, and what the shell printed is read from where
// the page stopped, every moment, while the pane is open. Closing the pane leaves the shell running:
// opening it again shows all it printed.
import { initPane, mountTerm } from "bend-ui/panes";
import { project, get, post, sleep, cover } from "./where.js";

const pane = document.getElementById("shell");
// What is typed goes out in the order it was typed: one request at a time, and the keys pressed while it
// travels go together in the next.
let typed = "", sending = false;
async function send(text) {
  typed += text;
  if (sending) return;
  sending = true;
  while (typed) { const keys = typed; typed = ""; await post(project("term/in"), keys); }
  sending = false;
}
const term = mountTerm(document.getElementById("term"), { label: "Terminal", onData: send });
let open = false, run = 0;

async function follow() {
  const me = ++run;
  let at = 0;   // the bytes of output already drawn
  term.clear();
  const started = await post(project("term/start"));
  if (me !== run) return;
  if (started !== "ok") { term.write("The terminal needs python3 on this computer, to hold the shell open.\r\n"); return; }
  while (me === run && open) {
    let got = ""; try { got = await get(project(`term/out/${at}`)); } catch {}
    if (me !== run) return;
    const cut = got.indexOf("\n"), [size, state] = got.slice(0, cut).split("\t"), text = got.slice(cut + 1);
    if (text) term.write(text);
    if (size) at = Number(size);
    if (state === "down") { term.write("\r\n[The shell ended. Close the terminal and open it again for a new one.]\r\n"); return; }
    await sleep(text ? 60 : 200);
  }
}
initPane(pane, { label: "Terminal", onToggle(on) { open = on; cover("shell", on); if (on) { follow(); term.focus(); } else run++; } });
// Another conversation: its project's terminal. (The same one, its folder named: the same shell goes on.)
document.addEventListener("laweditor:where", (e) => { if (open && !e.detail) follow(); });
