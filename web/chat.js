// LawEditor: the Chat tab. Its logic is CHAT.bend; each part in web/chat/ draws itself; this file wires them
// and talks to the server. It only adds a view: main.js keeps the other views.
import C from "../CHAT.bend";
import H from "../HEAR.bend";
import E from "../EDITOR.bend";
import P from "../POLICY.bend";
import O from "../OFFER.bend";
import G from "../GATE.bend";
import A from "../ASK.bend";
import { mountDiagram } from "bend-ui/diagram";
import { createMessages } from "./chat/messages.js";
import { createFace } from "./chat/face.js";
import { createModels } from "./chat/models.js";
import { createComposer } from "./chat/composer.js";
import { createMode } from "./chat/mode.js";
import { markdown } from "./markdown.js";
import { highlight } from "bend-ui/syntax";
import { createStart } from "./chat/start.js";
import { createGame } from "./chat/game.js";

const $ = (id) => document.getElementById(id);
const said = [];   // [{ who, text }], oldest first

const messages = createMessages($("chat"), document.querySelector(".page"));
const face = createFace();
const [aiDd, modelDd] = document.querySelectorAll("#composer .composer__bar .dropdown:not(#game)");
let saved = null; try { saved = localStorage.getItem("laweditor.ai"); } catch {}
const models = createModels(aiDd, modelDd, saved);
const chatMode = createMode($("mode"), aiDd, models.get().ai, () => conversationId);   // what the chat may do (POLICY.bend, HARNESS.md)

// The conversation as the agent reads it (AGENT.md, "Chat").
// The conversation as it is kept (talk) and as the chat reads it (with its game's name, if it has one).
const talk = () => said.map((m) => (m.who === C.person() ? "Person: " : "Agent: ") + m.text).join("\n");
const conversation = () => C.with_game(talk(), convGame);
// The conversation's game: none yet (a draft folder of its own), or one that exists. Its folder is where
// the chat works (the server's .current). The game button is optional; nothing asks before talking.
let convFolder = null, convGame = "";
const game = createGame($("game"));

async function post(path, body) {
  try { return await (await fetch(path, { method: "POST", body })).text(); }
  catch { return "error\nThe LawEditor server isn't running."; }
}
// A turn: the request runs while the page asks the server, every 300 ms, for the answer so far
// (GET /api/progress/<id>, read by ASK.bend from the turn's file). Codex has none: its answer comes whole.
const newId = () => Date.now().toString(36) + Math.random().toString(36).slice(2, 8);
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
// The gate (GATE.bend) may ask the person during the turn: GET /api/question/<id> holds the question
// while the agent waits; the card's answer goes to POST /api/answer/<id> and the turn goes on.
const GATE_ANSWERS = [
  { label: "Don't allow", value: G.deny_word(), kind: "btn--ghost" },
  { label: "Allow for this session", value: G.session_word(), kind: "" },
  { label: "Allow", value: G.allow_word(), kind: "btn--primary" },
];
// The card goes after what the chat wrote so far; what it writes after the action comes below the card.
async function gateAsks(id, asked, reply, wrote) {
  // GATE.question(): the question, then the language and name of what would change, then what would change.
  const [question, meta = "", ...preview] = asked.split("\n");
  const [lang, name] = meta.split("\t");
  reply.stop();   // its working line goes; with nothing shown yet, the reply goes too
  wait();
  const code = preview.join("\n").replace(/\n+$/, "");
  const card = messages.proposal(question, GATE_ANSWERS, code ? { code, lang, name } : "", "dot dot--warning", true);
  const said = await card.ask();
  await post(`/api/answer/${id}`, said);
  card.set(G.lets_run(said) ? "dot dot--success" : "dot", G.note(said));
  if (G.keeps(said)) setTimeout(chatMode.allowed, 700);   // the gate writes it once the waiting call reads the answer
  free();
  const next = messages.theirs(reply.shown()); face.to(next.slot); face.lookAt(next.el);
  return next;
}
// The context meter under the composer: how much of the AI's context the last turn used (ASK.bend).
const meter = $("context");
function context(percent) {
  if (percent == null) return;
  meter.hidden = false;
  meter.querySelector(".meter__bar > span").style.width = Math.min(100, percent) + "%";
  meter.querySelector(".meter__value").textContent = percent + "%";
}
// The turn running now, so Stop can end it (POST /api/stop/<id>).
let turnId = null, stopped = false;
async function streamed(path, body, reply) {
  const id = newId(); turnId = id;
  let shownText = "";
  let done = false;
  const poll = (async () => {
    while (!done) {
      await sleep(300);
      if (done) break;
      try { const w = await (await fetch(`/api/work/${id}`)).text(); if (!done) context(reply.work(w, id)); } catch {}
      try { const text = await (await fetch(`/api/progress/${id}`)).text(); if (!done && text.trim() && text !== shownText) { shownText = text; reply.live(shown(text)); } } catch {}
      try { const r = await fetch(`/api/question/${id}`); const asked = r.ok ? (await r.text()).trim() : ""; if (!done && asked) { reply = await gateAsks(id, asked, reply, !!shownText.trim()); shownText = (await (await fetch(`/api/progress/${id}`)).text()); } } catch {}
    }
  })();
  const res = await post(`${path}/${id}`, body);
  done = true; await poll;
  try { context(reply.work(await (await fetch(`/api/work/${id}`)).text(), id)); } catch {}   // the last actions and every file changed
  turnId = null;
  return { res, reply, turn: id };
}
const textOf = (res) => res.slice(res.indexOf("\n") + 1).trim() || "The agent didn't answer.";
const failed = (res) => res.startsWith("error");

// Ask before changes (POLICY.bend, GATE.bend): the chat asks the gate before each action, during the turn,
// and the card shows then (gateAsks). One conversation per page: "Allow for this session" lasts until it reloads.
let conversationId = newId();
async function askFirst(model, reply, extra) {
  const turn = await streamed(`/api/ask/${model}/${conversationId}`, conversation() + extra, reply);
  return { reply: turn.reply, answer: textOf(turn.res), failed: failed(turn.res), turn: turn.turn };
}

// extra: a line for the chat after the conversation (after Switch, OFFER.told()).
async function ask(reply, extra = "") {
  const { ai, model } = models.get();
  if (P.mode_asks_at(chatMode.get())) return askFirst(model, reply, extra);
  const turn = await streamed(`/api/chat/${ai}/${model}`, conversation() + extra, reply);
  return { reply: turn.reply, answer: textOf(turn.res), failed: failed(turn.res), turn: turn.turn };
}
// What the person reads: the reply without its LAW:, MODE: and PLAN: lines (HEAR.bend, OFFER.bend, ASK.bend).
function shown(text) { return O.words(H.words(A.plan_words(C.game_words(text)))); }

// The chat offers the mode (OFFER.bend): in Only read, a MODE: line becomes Switch / Stay.
// Switch moves the picker and sends the request again, now in Ask before changes; Stay changes nothing.
const OFFER_ANSWERS = [
  { label: "Stay", value: O.stay(), kind: "btn--ghost" },
  { label: "Switch", value: O.switch(), kind: "btn--primary" },
];
function offer(answer) {
  if (!O.offers(answer)) return;
  wait();   // the talk stops until the person answers (as every question)
  questions = questions.then(() => offered(answer));
}
async function offered(answer) {
  const card = messages.proposal("Switch to Ask before changes?", OFFER_ANSWERS, "So the chat can build it. It asks before each change.", "dot dot--warning");
  const choice = await card.ask();
  chatMode.set(O.mode_after(choice));
  card.set(O.switches(choice) ? "dot dot--success" : "dot", O.switches(choice) ? "Switched to Ask before changes." : "Stayed in Only read.");
  free();
  if (!O.switches(choice)) return;
  const first = messages.theirs();
  face.to(first.slot); face.lookAt(first.el);
  const { reply, answer: built, turn } = await ask(first, "\n" + O.told());
  said.push({ who: C.agent(), text: built, turn });
  await reply.write(shown(built));
  face.lookAt(null);
  hear(built);
}

// One question at a time. After a reply, the laws it heard are asked first, then the mode it offers; the
// gate's card comes during a turn. While any question waits, the message box is off and says why.
let questions = Promise.resolve(), waiting = 0;
function wait() { if (waiting++ === 0) composer.hold(true); }
function free() { if (--waiting === 0) composer.hold(false); }

const start = createStart(document.querySelector(".page"), $("composer"));
let started = false;

const composer = createComposer($("composer"), async (text, files) => {
  const from = await leaveStart();
  if (!convFolder) {
    const g = game.chosen();
    if (g) { await post(`/api/project/${encodeURIComponent(g.folder)}`, ""); convFolder = g.folder; convGame = g.name; }
    else { await post(`/api/draft/${conversationId}`, ""); convFolder = conversationId; }
    game.lock(convFolder, convGame);
  }
  said.push({ who: C.person(), text: C.with_files(text, files.join(", ")) }); messages.mine(text, files);
  await reply(from);
}, () => { if (!turnId) return; stopped = true; post(`/api/stop/${turnId}`, ""); }, command);

// The start goes when the chat begins (a first message, or an old conversation opened).
async function leaveStart() {
  if (started) return undefined;
  const from = await start.leave(); started = true; show();
  return from;
}

// Commands typed with / (CHAT.bend's commands).
function command(name) {
  if (name === "/clear") fresh();   // a new conversation; the old ones stay in the list
  if (name === "/laws") document.querySelector('#side [data-view="doc"]').click();
  if (name === "/context") document.querySelector('#chat-view [data-view="context"]')?.click();
}

// The conversations, kept with the project (POST/GET /api/conversation/<id>, GET /api/conversations):
// saved after each turn, listed in the side bar under Chat, newest first; one opens where it stopped.
// After the conversation, a line with the record separator, then each message's turn (the agent's), so
// opening it again draws what each reply did (GET /api/work/<turn>).
const TURNS = "\n\u001e\n";
async function saveConversation() {
  await post(`/api/conversation/${conversationId}`, talk() + TURNS + said.map((m) => m.turn || "").join(","));
  listConversations();
}
// The side bar: the conversations of each game together, under the game's name (click it to rename;
// + starts a conversation in it), the games most recently used first; conversations with no game below.
async function listConversations() {
  const box = $("history");
  let rows = [];
  try { rows = (await (await fetch("/api/conversations")).text()).split("\n").filter(Boolean).map((l) => l.split("\t")); } catch {}
  box.innerHTML = "";
  const groups = new Map();
  for (const r of rows) { const k = r[1] ? r[0] : ""; if (!groups.has(k)) groups.set(k, []); groups.get(k).push(r); }
  const loose = groups.get("") || []; groups.delete("");
  const item = ([folder, , id, title]) => {
    const b = document.createElement("button");
    b.className = "btn btn--ghost"; b.type = "button"; b.title = title;
    if (id === conversationId) b.setAttribute("aria-current", "page");
    b.innerHTML = '<span class="side__text"></span>'; b.firstChild.textContent = title;
    b.addEventListener("click", () => openConversation(folder, id));
    return b;
  };
  for (const [folder, list] of groups) {
    const name = list[0][1], head = document.createElement("div");
    head.className = "side__row";
    head.innerHTML = '<h2 class="side__label side__text"></h2><button class="btn btn--ghost btn--icon btn--sm side__more" type="button"><svg class="icon icon--sm" aria-hidden="true"><use href="#i-plus"/></svg></button>';
    const label = head.firstChild, plus = head.lastChild;
    label.textContent = name; label.title = "Rename"; label.tabIndex = 0;
    plus.setAttribute("aria-label", `New conversation in ${name}`); plus.title = `New conversation in ${name}`;
    plus.addEventListener("click", () => { try { sessionStorage.setItem("laweditor.game", JSON.stringify({ folder, name })); } catch {} fresh(); });
    label.addEventListener("click", () => rename(label, folder, name));
    label.addEventListener("keydown", (e) => { if (e.key === "Enter") rename(label, folder, name); });
    box.append(head, ...list.map(item));
  }
  if (loose.length) {
    const h = document.createElement("h2"); h.className = "side__label side__text"; h.textContent = "Conversations";
    box.append(h, ...loose.map(item));
  }
}
// Renaming a game: its name turns into a field; Enter keeps the new name, Escape the old one.
function rename(label, folder, name) {
  const f = document.createElement("input");
  f.className = "input input--sm"; f.value = name; f.setAttribute("aria-label", "Name of the game");
  label.replaceWith(f); f.focus(); f.select();
  const done = async (keep) => {
    const n = f.value.trim();
    if (keep && n && n !== name) {
      await post(`/api/rename/${encodeURIComponent(folder)}`, n);
      if (folder === convFolder) { convGame = n; game.lock(convFolder, n); }
      game.reload();
    }
    listConversations();
  };
  f.addEventListener("keydown", (e) => { if (e.key === "Enter") done(true); if (e.key === "Escape") done(false); });
  f.addEventListener("blur", () => done(true));
}
async function openConversation(folder, id) {
  if (id === conversationId) { document.querySelector('#side [data-view="chat"]').click(); return; }   // back to it from Laws
  if (turnId || waiting) return;
  await post(`/api/project/${encodeURIComponent(folder)}`, "");   // the chat works in its folder again
  let text = ""; try { text = await (await fetch(`/api/conversation/${id}`)).text(); } catch { return; }
  await leaveStart();
  document.querySelector('#side [data-view="chat"]').click();
  conversationId = id; said.length = 0; $("chat").innerHTML = "";
  const [talk, turns = ""] = text.split(TURNS), ids = turns.split(",");
  for (const line of talk.split("\n").slice(1)) {
    const m = line.match(/^(Person|Agent): (.*)$/);
    if (m) said.push({ who: m[1] === "Person" ? C.person() : C.agent(), text: m[2] });
    else if (said.length) said[said.length - 1].text += "\n" + line;
  }
  said.forEach((m, i) => { if (ids[i]) m.turn = ids[i]; });
  let last = null;
  for (const m of said) {
    if (m.who === C.person()) { messages.mine(m.text); continue; }
    last = messages.theirs();
    if (m.turn) try { context(last.work(await (await fetch(`/api/work/${m.turn}`)).text(), m.turn)); } catch {}
    last.restore(shown(m.text));
  }
  if (last) face.to(last.slot);
  const row = (await (await fetch("/api/conversations")).text()).split("\n").map((l) => l.split("\t")).find((r) => r[2] === id) || [];
  convFolder = folder; convGame = row[1] || ""; game.lock(folder, convGame);
  listConversations();
}

listConversations();
// A conversation with no game becomes one once it has a sentence or a file: named by the chat (GAME:),
// or by its first message if the chat gave no name.
async function promote(answer = "") {
  if (convGame) return;
  const name = C.game_name(answer) || (said.find((m) => m.who === C.person())?.text || "Game").split("\n")[0].slice(0, 40);
  if ((await post("/api/promote", name)).includes("promoted")) { convGame = name; game.lock(convFolder, name); game.reload(); listConversations(); }
}

// A new conversation from the + of a game starts in that game.
try { const g = JSON.parse(sessionStorage.getItem("laweditor.game") || "null"); sessionStorage.removeItem("laweditor.game"); if (g) game.choose(g.folder, g.name); } catch {}
// New conversation: the chat view (the page remembers the last view), then a fresh page.
const fresh = () => { document.querySelector('#side [data-view="chat"]').click(); location.reload(); };
$("new-conversation").addEventListener("click", fresh);

// One turn of the agent; if it stops with an error, a card says why and Try again runs the turn again.
async function reply(from) {
  const first = messages.theirs();
  face.to(first.slot, from ?? undefined); face.lookAt(first.el);
  stopped = false;
  const { reply: r, answer, failed: broke, turn } = await ask(first);
  if (stopped) { r.stop(); face.lookAt(null); messages.failed("You stopped the reply.", () => reply()); return; }
  if (broke) { r.stop(); face.lookAt(null); messages.failed(answer, () => reply()); return; }
  const reply_ = r;
  said.push({ who: C.agent(), text: answer, turn });
  await reply_.write(shown(answer));
  face.lookAt(null);
  await promote(answer);
  saveConversation();
  hear(answer);    // the laws it heard, one card at a time
  offer(answer);   // then, if it offers one, the mode
}

// The skill (HEAR.md) asked the chat to end its reply with LAW: "<sentence>" lines.
// HEAR.bend reads them and decides: ask (every session starts so), or, after "Always add", add.
// An added sentence goes to the document, and the law agent writes its law (main.js, "laweditor:add").
let mode = H.start();
const heard = [];   // sentences proposed this session, so none is asked twice
const ANSWERS = [
  { label: "Don't add", value: H.dont(), kind: "btn--ghost" },
  { label: "Always add", value: H.always(), kind: "" },
  { label: "Add", value: H.add(), kind: "btn--primary" },
];
const DOT = { [E.empty()]: "dot", [E.busy()]: "dot dot--busy", [E.ok()]: "dot dot--success", [E.error()]: "dot dot--danger" };
let writing = Promise.resolve();
function hear(answer) {
  const n = H.count(answer);
  if (!n) return;
  wait();   // CHAT.bend: while a question waits, the talk stops (question_stops_the_talk)
  questions = questions.then(async () => {
    let gdd = ""; try { gdd = await (await fetch("/api/file/GDD.md")).text(); } catch {}
    // First every question, right under the reply; then the laws, so the person isn't held while the agent works.
    const added = [];
    for (let i = 0; i < n; i++) {
      const sentence = H.proposal(answer, i);
      if (!H.is_new(sentence, gdd + "\n" + heard.join("\n"))) continue;
      heard.push(sentence);
      const card = messages.proposal(sentence, ANSWERS);
      const choice = H.must_ask(mode) ? await card.ask() : H.add();
      mode = H.mode_after(mode, choice);
      if (!H.adds(choice)) { card.set("dot", "Not added."); continue; }
      card.set(DOT[E.busy()], "Added to the document. Writing its law…");
      added.push({ sentence, card });
    }
    free();
    // The laws, one at a time, on their own line: a later question doesn't wait for them.
    for (const { sentence, card } of added) writing = writing.then(async () => {
      const { state, out } = await new Promise((done) =>
        document.dispatchEvent(new CustomEvent("laweditor:add", { detail: { sentence, done } })));
      card.set(DOT[state], out);
      promote();   // an accepted sentence can make this conversation a game
    });
  });
}

// Chat opens first. Its selector shows the conversation or its context (CHAT.md, what the chat is told).
// main.js hides its own views when Chat is picked; this shows Chat. In Chat the face lives beside the
// replies, so the big agent (and its toolbar dock) step aside.
let chatView = "chat", inChat = true;
function show() {
  start.show(inChat && chatView === "chat" && !started);
  $("view-chat").hidden = !(inChat && chatView === "chat");
  $("composer").hidden = !(inChat && chatView === "chat");
  $("view-chat-context").hidden = !(inChat && chatView === "context");
  document.querySelectorAll(".chat-only").forEach((x) => x.hidden = !inChat);
  document.querySelector(".window__dock").hidden = inChat;
  document.querySelector(".toolbar__dock").hidden = inChat;
}
$("chat-view").addEventListener("change", (e) => { chatView = e.detail.dataset.view; show(); if (chatView === "chat") composer.focus(); });
document.querySelectorAll("#side [data-view]").forEach((b) => b.addEventListener("click", () => {
  inChat = b.dataset.view === "chat"; show();
  if (inChat && chatView === "chat") composer.focus();
}));
// Chat › Context: the offer flow, drawn from OFFER.flow() by Bend-UI's diagram (the code is the source).
{
  const items = (l) => { const out = []; while (l.$ === "Con") { out.push(l.head); l = l.tail; } return out; };
  const TONE = { Person: "", Skill: "accent", System: "success" };
  const steps = items(O.flow());
  mountDiagram($("offer-flow"), {
    nodes: steps.map((s) => ({ label: s.name, tone: TONE[s.who.$], tag: s.writes ? "writes a file" : "" })),
    edges: steps.flatMap((s, i) => items(s.next).map((g) => ({ from: i, to: Number(g.to), label: g.label }))),
  });
}
fetch("/api/file/HARNESS.md").then((r) => r.text()).then((md) => { $("harness-md").textContent = md || "HARNESS.md not found"; }).catch(() => {});
fetch("/api/file/HEAR.md").then((r) => r.text()).then((md) => { $("hear-md").innerHTML = markdown(md || "# HEAR.md not found"); }).catch(() => {});
fetch("/api/file/CHAT.md").then((r) => r.text()).then((md) => { $("chat-md").innerHTML = markdown(md || "# CHAT.md not found"); $("chat-md").querySelectorAll("pre").forEach(highlight); }).catch(() => {});
show();
