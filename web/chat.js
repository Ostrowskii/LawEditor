// LawEditor: the Chat tab. Its logic is CHAT.bend; each part in web/chat/ draws itself; this file wires them
// and talks to the server. It only adds a view: main.js keeps the other views.
import C from "../CHAT.bend";
import H from "../HEAR.bend";
import E from "../EDITOR.bend";
import P from "../POLICY.bend";
import O from "../OFFER.bend";
import G from "../GATE.bend";
import { mountDiagram } from "bend-ui/diagram";
import { createMessages } from "./chat/messages.js";
import { createFace } from "./chat/face.js";
import { createModels } from "./chat/models.js";
import { createComposer } from "./chat/composer.js";
import { createMode } from "./chat/mode.js";
import { markdown } from "./markdown.js";
import { highlight } from "bend-ui/syntax";
import { createStart } from "./chat/start.js";

const $ = (id) => document.getElementById(id);
const said = [];   // [{ who, text }], oldest first

const messages = createMessages($("chat"), document.querySelector(".page"));
const face = createFace();
const [aiDd, modelDd] = document.querySelectorAll("#composer .composer__bar .dropdown");
let saved = null; try { saved = localStorage.getItem("laweditor.ai"); } catch {}
const models = createModels(aiDd, modelDd, saved);
const chatMode = createMode($("mode"), aiDd, models.get().ai);   // what the chat may do (POLICY.bend, HARNESS.md)

// The conversation as the agent reads it (AGENT.md, "Chat").
const conversation = () => said.map((m) => (m.who === C.person() ? "Person: " : "Agent: ") + m.text).join("\n");

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
  const [question, ...preview] = asked.split("\n");
  if (!wrote) reply.el.remove();   // nothing written yet: only the "Reading…" placeholder
  composer.hold(true);
  const card = messages.proposal(question, GATE_ANSWERS, preview.join("\n").trim(), "dot dot--warn");
  const said = await card.ask();
  await post(`/api/answer/${id}`, said);
  card.set(G.lets_run(said) ? "dot dot--ok" : "dot", G.note(said));
  composer.hold(false);
  const next = messages.theirs(); face.to(next.slot); face.lookAt(next.el);
  return next;
}
async function streamed(path, body, reply) {
  const id = newId();
  let shownText = "";
  let done = false;
  const poll = (async () => {
    while (!done) {
      await sleep(300);
      if (done) break;
      try { const text = await (await fetch(`/api/progress/${id}`)).text(); if (!done && text.trim() && text !== shownText) { shownText = text; reply.live(O.words(H.words(text))); } } catch {}
      try { const r = await fetch(`/api/question/${id}`); const asked = r.ok ? (await r.text()).trim() : ""; if (!done && asked) { reply = await gateAsks(id, asked, reply, !!shownText.trim()); shownText = (await (await fetch(`/api/progress/${id}`)).text()); } } catch {}
    }
  })();
  const res = await post(`${path}/${id}`, body);
  done = true; await poll;
  return { res, reply };
}
const textOf = (res) => res.slice(res.indexOf("\n") + 1).trim() || "The agent didn't answer.";

// Ask before changes (POLICY.bend, GATE.bend): the chat asks the gate before each action, during the turn,
// and the card shows then (gateAsks). One conversation per page: "Allow for this session" lasts until it reloads.
const conversationId = newId();
async function askFirst(model, reply, extra) {
  const turn = await streamed(`/api/ask/${model}/${conversationId}`, conversation() + extra, reply);
  return { reply: turn.reply, answer: textOf(turn.res) };
}

// extra: a line for the chat after the conversation (after Switch, OFFER.told()).
async function ask(reply, extra = "") {
  const { ai, model } = models.get();
  if (P.mode_asks_at(chatMode.get())) return askFirst(model, reply, extra);
  const turn = await streamed(`/api/chat/${ai}/${model}`, conversation() + extra, reply);
  return { reply: turn.reply, answer: textOf(turn.res) };
}
// What the person reads: the reply without its LAW: and MODE: lines (HEAR.bend, OFFER.bend).
const shown = (text) => O.words(H.words(text));

// The chat offers the mode (OFFER.bend): in Only read, a MODE: line becomes Switch / Stay.
// Switch moves the picker and sends the request again, now in Ask before changes; Stay changes nothing.
const OFFER_ANSWERS = [
  { label: "Stay", value: O.stay(), kind: "btn--ghost" },
  { label: "Switch", value: O.switch(), kind: "btn--primary" },
];
async function offer(answer) {
  if (!O.offers(answer)) return;
  composer.hold(true);   // the talk stops until the person answers (as every question)
  const card = messages.proposal("Switch to Ask before changes?", OFFER_ANSWERS, "So the chat can build it. It asks before each change.", "dot dot--warn");
  const choice = await card.ask();
  chatMode.set(O.mode_after(choice));
  card.set(O.switches(choice) ? "dot dot--ok" : "dot", O.switches(choice) ? "Switched to Ask before changes." : "Stayed in Only read.");
  composer.hold(false);
  if (!O.switches(choice)) return;
  const first = messages.theirs();
  face.to(first.slot); face.lookAt(first.el);
  const { reply, answer: built } = await ask(first, "\n" + O.told());
  said.push({ who: C.agent(), text: built });
  await reply.write(shown(built));
  face.lookAt(null);
  hear(built);
}

const start = createStart(document.querySelector(".page"), $("composer"));
let started = false;

const composer = createComposer($("composer"), async (text) => {
  const from = C.is_start(said.length) ? await start.leave() : undefined;
  if (from !== undefined) { started = true; show(); }
  said.push({ who: C.person(), text }); messages.mine(text);
  const first = messages.theirs();
  face.to(first.slot, from ?? undefined); face.lookAt(first.el);
  const { reply, answer } = await ask(first);
  said.push({ who: C.agent(), text: answer });
  await reply.write(shown(answer));
  face.lookAt(null);
  hear(answer);   // not awaited: the person can keep talking while a proposal waits
  offer(answer);
});

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
const DOT = { [E.empty()]: "dot", [E.busy()]: "dot dot--busy", [E.ok()]: "dot dot--ok", [E.error()]: "dot dot--error" };
let queue = Promise.resolve(), writing = Promise.resolve();
function hear(answer) {
  const n = H.count(answer);
  if (!n) return;
  composer.hold(true);   // CHAT.bend: while a question waits, the talk stops (question_stops_the_talk)
  queue = queue.then(async () => {
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
    composer.hold(false);
    // The laws, one at a time, on their own line: a later question doesn't wait for them.
    for (const { sentence, card } of added) writing = writing.then(async () => {
      const { state, out } = await new Promise((done) =>
        document.dispatchEvent(new CustomEvent("laweditor:add", { detail: { sentence, done } })));
      card.set(DOT[state], out);
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
  const TONE = { Person: "", Skill: "accent", System: "law" };
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
