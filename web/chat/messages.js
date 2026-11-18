// Chat messages: draws them. The agent's reply goes through CHAT.bend's phases: reading, writing, done.
// While it works, the reply shows what ASK.bend reads from the turn (GET /api/work/<id>): its actions
// (.tools), its plan (.plan), what it does now (.working) and, at the end, the files it changed (.changes).
import C from "../../harness/CHAT.bend";
import { busy, done as doneBtn } from "bend-ui";
import { markdown } from "../markdown.js";
import { codeBlock } from "bend-ui/syntax";

const lessMotion = matchMedia("(prefers-reduced-motion: reduce)");
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

export function createMessages(list, page) {
  const down = () => page.scrollTo({ top: page.scrollHeight, behavior: lessMotion.matches ? "auto" : "smooth" });

  // Yours: a bubble at the right that fades in.
  // files: what the person pointed to with @, as tags after the text.
  function mine(text, files = []) {
    const m = document.createElement("div");
    m.className = "msg msg--me is-arriving";
    m.textContent = text;
    for (const f of files) { const t = document.createElement("span"); t.className = "tag tag--mono"; t.textContent = "@" + f; m.append(" ", t); }
    list.append(m); down();
  }

  // The agent's: its face, then what it is doing, then its words.
  // skip: actions an earlier reply of this turn already shows (the turn goes on after a permission card).
  function theirs(skip = 0) {
    const m = document.createElement("div");
    m.className = "msg msg--face";
    m.innerHTML = '<div class="msg__face"><div></div></div><div class="msg__body"><div class="working"><span class="dot dot--warning"></span><span class="working__verb">Reading</span><span class="working__what">your project</span><span class="working__time">0s</span></div></div>';
    list.append(m); down();
    const body = m.lastChild, working = body.querySelector(".working");
    const text = document.createElement("div");
    let phase = C.reading(), streamed = false, tools = null, plan = null, changes = [], head = "";
    const t0 = Date.now(), tick = setInterval(() => { working.querySelector(".working__time").textContent = Math.round((Date.now() - t0) / 1000) + "s"; }, 1000);
    const before = (el) => body.insertBefore(el, text.isConnected ? text : working);
    const say = (s) => { if (!text.isConnected) body.insertBefore(text, working); text.textContent = s; };
    // The work so far, as ASK.bend wrote it: one line each, T (action), P (plan step), C (file), H (files' title), W (now).
    // turn: the turn's id, so an action can show what it answered (GET /api/output/<turn>/<n>) when opened.
    // Answers how much context the turn used (percent), or null.
    function work(lines, turn) {
      const rows = lines.split("\n").filter(Boolean).map((l) => l.split("\t"));
      const acts = rows.filter((r) => r[0] === "T"), steps = rows.filter((r) => r[0] === "P"), now = rows.find((r) => r[0] === "W");
      changes = rows.filter((r) => r[0] === "C"); head = (rows.find((r) => r[0] === "H") || [])[1] || "";
      if (acts.length > skip + (tools ? tools.children.length : 0)) {
        if (!tools) { tools = document.createElement("div"); tools.className = "tools"; before(tools); }
        for (const [, kind, tone, what] of acts.slice(skip + tools.children.length)) {
          const n = skip + tools.children.length, d = document.createElement("details"); d.className = "disclosure tool";
          d.innerHTML = '<summary><svg class="icon icon--sm disclosure__chevron" aria-hidden="true"><use href="#i-chevron-down"/></svg><span class="tool__kind"></span><span class="tool__what mono"></span><span class="tool__meta"></span></summary><pre class="tool__out"></pre>';
          const k = d.querySelector(".tool__kind"); k.textContent = kind; if (tone) k.classList.add("tool__kind--" + tone);
          d.querySelector(".tool__what").textContent = what; tools.append(d);
          d.addEventListener("toggle", async () => {
            const out = d.querySelector(".tool__out");
            if (!d.open || !out || out.textContent) return;
            let text = ""; try { text = await (await fetch(`/api/output/${turn}/${n}`)).text(); } catch {}
            // An edit answers with what it changed: drawn as a diff code block, clipped when long.
            if (kind === "Edit" && text) { out.replaceWith(Object.assign(document.createElement("div"), { innerHTML: codeBlock(text, { lang: "diff", name: what, clip: true }) }).firstChild); return; }
            out.textContent = text || "(no output)";
          });
        }
        // The detail comes when the action answers: an edit's lines, or how many lines it answered.
        acts.slice(skip).forEach(([, , , , detail], i) => { const m = tools.children[i]?.querySelector(".tool__meta"); if (m && detail) m.textContent = detail; });
      }
      if (steps.length) {
        if (!plan) { plan = document.createElement("ol"); plan.className = "plan"; body.insertBefore(plan, tools ? tools.nextSibling : body.firstChild); }
        steps.forEach(([, status, what], i) => {
          let li = plan.children[i];
          if (!li) { li = document.createElement("li"); li.className = "plan__step"; li.style.setProperty("--i", i); li.innerHTML = '<span class="plan__node"><i class="node__core"></i></span><span class="plan__text"></span>'; plan.append(li); }
          const was = li.classList.contains("is-now");
          li.querySelector(".plan__text").textContent = what;
          li.classList.toggle("is-done", status === "done"); li.classList.toggle("is-now", status === "now");
          if (was && status === "done") { li.classList.add("is-pop"); setTimeout(() => li.classList.remove("is-pop"), 600); }
        });
      }
      if (now && !streamed) { working.querySelector(".working__verb").textContent = now[1]; working.querySelector(".working__what").textContent = now[2]; }
      down();
      const x = rows.find((r) => r[0] === "X");
      return x ? Number(x[1]) : null;
    }
    // Done: the working line goes; the files changed come under the answer.
    function finish() {
      clearInterval(tick); working.remove();
      if (!changes.length) return;
      const c = document.createElement("div"); c.className = "changes";
      c.innerHTML = '<div class="changes__head"><span></span></div>';
      c.querySelector(".changes__head span").textContent = head;
      for (const [, file, add, del] of changes) {
        const r = document.createElement("div"); r.className = "changes__row";
        r.innerHTML = '<span class="changes__file mono"></span><span class="changes__add"></span><span class="changes__del"></span>';
        r.children[0].textContent = file; r.children[1].textContent = Number(add) ? "+" + add : ""; r.children[2].textContent = Number(del) ? "−" + del : "";
        c.append(r);
      }
      body.append(c);
      // The project changed: the card that closes the turn (Harness Lab, "Open the project folder"): a green
      // dot, what changed, and a link that opens the folder on the computer (POST /api/open-folder).
      const card = document.createElement("div");
      card.innerHTML = '<div class="block block--done"><div class="block__slot"><span class="dot dot--success"></span></div><div class="block__text"></div></div><div class="actions actions--start"><button class="link link--icon" type="button"><svg class="icon icon--sm" aria-hidden="true"><use href="#i-folder"/></svg><span>Open project folder</span></button></div>';
      card.querySelector(".block__text").textContent = "Done. " + head + ".";
      card.querySelector(".link").addEventListener("click", () => fetch("/api/open-folder", { method: "POST" }));
      body.append(card);
    }
    // The answer, once whole: Markdown, drawn by Bend-UI's .prose.
    const prose = (s) => { if (!text.isConnected) body.insertBefore(text, working); text.className = "prose"; text.innerHTML = markdown(s); };
    return {
      el: m, slot: m.firstChild.firstChild, work,
      shown: () => skip + (tools ? tools.children.length : 0),
      // The answer while it is written (Claude streams it): shown as it comes, no word motion.
      live(s) {
        streamed = true; phase = C.writing(); say(s);
        working.querySelector(".working__verb").textContent = "Writing"; working.querySelector(".working__what").textContent = "";
        down();
      },
      // The answer arrives whole from the CLI; its words appear one after another, each fading in.
      async write(answer) {
        if (!streamed) {
          phase = C.writing(); say("");
          for (const w of answer.split(/(\s+)/).filter(Boolean)) {
            const s = document.createElement("span");
            if (/\S/.test(w)) s.className = "msg__word";
            s.textContent = w; text.append(s);
            if (/\S/.test(w) && !lessMotion.matches) { down(); await sleep(30); }
          }
        }
        prose(answer); finish(); phase = C.done(); down();
      },
      // From an old conversation, opened again: no motion, the answer and what it changed.
      restore(answer) { prose(answer); finish(); phase = C.done(); },
      // It stopped with an error: the working line goes; the error card comes from failed().
      stop() { clearInterval(tick); working.remove(); if (!text.isConnected && !tools && !plan) m.remove(); },
      phase: () => phase,
    };
  }

  // A rule the chat heard (HEAR.bend), under its reply: the sentence as a document block, and the person's answer.
  // answers: [{ label, value, kind }], kind is a Bend-UI button ("btn--primary", "btn--ghost" or "").
  // The same card asks before the chat acts (ASK.bend): then preview is what would change, and dot is "dot dot--warning".
  // preview is a note, or { code, lang, name }: a code block, clipped when long (an edit comes as a diff).
  // Every card uses Bend-UI's polished buttons (Harness Lab): every button but the main one is bordered and
  // "async": clicked, it turns while the answer goes, then shows its check.
  function proposal(sentence, answers, preview = "", dot = "dot", polish = true) {
    const m = document.createElement("div");
    m.className = "msg msg--face";
    m.innerHTML = '<div class="msg__face"></div><div><div class="block"><div class="block__slot"><span class="dot"></span></div><div class="block__text"></div></div><div class="actions"></div></div>';
    const block = m.querySelector(".block"), actions = m.querySelector(".actions");
    block.querySelector(".block__text").textContent = sentence;
    block.querySelector(".dot").className = dot;
    if (preview && typeof preview === "object") block.insertAdjacentHTML("beforeend", codeBlock(preview.code, { lang: preview.lang, name: preview.name, clip: true }));
    else if (preview) { const p = document.createElement("pre"); p.className = "block__out is-preview"; p.textContent = preview; block.append(p); }
    list.append(m); down();
    return {
      // Waits for a click; the buttons go away.
      ask: () => new Promise((done) => {
        for (const a of answers) {
          const b = document.createElement("button");
          const main = a.kind === "btn--primary";
          b.className = ("btn btn--sm " + (polish && !main ? "btn--bordered btn--async" : a.kind)).trim(); b.type = "button";
          if (polish && !main) b.innerHTML = '<svg class="icon btn__done" aria-hidden="true"><use href="#i-check"/></svg><span class="btn__label"></span><svg class="btn__spin" viewBox="0 0 20 20" aria-hidden="true"><circle cx="10" cy="10" r="8" pathLength="100"/></svg>';
          (b.querySelector(".btn__label") || b).textContent = a.label;
          b.addEventListener("click", () => {
            if (!(polish && !main)) { actions.remove(); done(a.value); return; }
            actions.querySelectorAll(".btn").forEach((x) => x !== b && (x.disabled = true));
            busy(b, true); done(a.value);
          });
          actions.append(b);
        }
        down();
      }),
      // What happened to it: the block's dot, and a note under the sentence.
      set(dot, note) {
        const b = actions.querySelector('[aria-busy="true"]');
        if (b) { doneBtn(b); setTimeout(() => actions.remove(), 600); } else actions.remove();
        block.querySelector(".dot").className = dot;
        let out = block.querySelector(".block__out:not(.is-preview)");
        if (!out) { out = document.createElement("pre"); out.className = "block__out"; block.append(out); }
        out.textContent = note; down();
      },
    };
  }

  // A reply from an old conversation, opened again: its text, as Markdown.
  function past(text) {
    const m = document.createElement("div");
    m.className = "msg msg--face";
    m.innerHTML = '<div class="msg__face"><div></div></div><div class="msg__body"><div class="prose"></div></div>';
    m.querySelector(".prose").innerHTML = markdown(text);
    list.append(m); down();
    return { el: m, slot: m.firstChild.firstChild };
  }

  // The reply stopped: a card without a dot (Bend-UI drops its column), why, and Try again.
  function failed(why, again) {
    const m = document.createElement("div");
    m.className = "msg msg--face";
    m.innerHTML = '<div class="msg__face"></div><div><div class="block"><div class="block__text"></div></div><div class="actions"><button class="btn btn--sm" type="button">Try again</button></div></div>';
    m.querySelector(".block__text").textContent = why;
    m.querySelector(".actions .btn").addEventListener("click", () => { m.remove(); again(); });
    list.append(m); down();
  }

  return { mine, theirs, proposal, failed, past };
}
