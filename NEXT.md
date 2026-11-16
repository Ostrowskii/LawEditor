# Next: the chat asks Bend before it acts (0.1.8)

Decided on 2026-11-12 with the repo owner. Built in 0.1.8 (2026-11-16); the laws below are still to add. The flows are in `PERMIT.bend`; `bend DIAGRAMS.bend` draws them.

## The bug (0.1.7)

A command made of parts (`sed … | sed … > /tmp/x.js && node --check /tmp/x.js && echo OK`) asks forever. The person allows it; `ASK.bend` adds the whole line to Claude's list (`Bash(<whole command>)`); Claude's CLI checks each part alone, finds none on the list, and refuses again. Seen in every project. Reproduced outside the app with Claude Code 2.1.322.

## The decision: Bend decides, the CLI obeys

Two fixes were drawn (`PERMIT.list()`, `PERMIT.ask_bend()`):

- **A, write the list right**: cut the command into parts as Claude does and add one line per part. Bend would have to copy how each CLI reads its list (Codex has no list per command), and the loop comes back the day the CLI cuts differently.
- **B, the CLI asks Bend** (chosen): before an action that isn't on its list, Claude asks our server and waits. Bend gets the whole action, decides with `POLICY.bend` and the laws, and asks the person only when it must. No retry, no `--resume`. A model that runs locally fits the same flow, with no CLI in between: the harness runs the tool itself.

## What the three references do

All three stop the agent, hand the whole action to the harness, and wait for allow, allow always or deny.

- **Claude Code**: `--permission-prompt-tool` (an MCP tool) answers `{"behavior":"allow"}` or `{"behavior":"deny","message":…}`; Claude waits with no time limit. Deny rules are checked first, so the tool is never asked about them. ([CLI](https://code.claude.com/docs/en/cli-reference), [order of checks](https://code.claude.com/docs/en/agent-sdk/permissions#how-permissions-are-evaluated), [compound commands](https://code.claude.com/docs/en/permissions#compound-commands))
- **Codex**: only its `app-server` asks a client (`item/commandExecution/requestApproval`, answered `accept`, `acceptForSession`, `decline` or `cancel`). `codex exec`, which LawEditor runs today, asks no one. ([app-server](https://learn.chatgpt.com/docs/app-server), [approvals](https://learn.chatgpt.com/docs/agent-approvals-security))
- **Hermes Agent**: the harness runs the tools and decides itself: allow once, allow always, deny. No answer in 300 s means deny. It also cuts commands into parts for its deny list and says that is "not a complete shell interpreter". ([security](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/security.md), [approval.py](https://github.com/NousResearch/hermes-agent/blob/main/tools/approval.py))

## Tested on 2026-11-12 (outside the app, Claude Code 2.1.322)

- Claude asked a small outside tool, waited 5 s for its answer, and got the **whole** command (`tool_name`, `input`, `tool_use_id`).
- Allow: the command ran once. Deny: it didn't run, and the chat didn't retry.
- `--disallowedTools Edit(LAWS.bend)` won: Claude refused by itself and never asked the tool. (With a rule written in the wrong path form, the edit went through and nothing warned: the list is not a guard, Bend is.)
- The tool works over plain HTTP (`"type": "http"`), with plain JSON answers. So `server.bend` itself can be the interphone; Bend doesn't need to read stdin.

## The pieces

1. **`server.bend` answers `POST /mcp`**: the MCP calls (`initialize`, `tools/list`, `tools/call`). A `tools/call` puts the question where the page can see it and waits for the answer. The compiled server already answers other requests while one waits (since 0.1.3).
2. **Bend decides** (`ASK.bend`, `POLICY.bend`): allowed already in this session or always, so yes; a law forbids it, so no; otherwise, ask the person. It waits for the answer with no time limit, as Claude does.
3. **The page asks during the turn**: the card shows while the chat is still working, and the answer goes back to the waiting call.
4. **Claude runs with** `--permission-prompts host --permission-prompt-tool …` and an MCP config naming the server, instead of `--permission-prompts none` and `--resume`.
5. **Codex comes later**: it needs `codex app-server` instead of `codex exec`.

## Open questions

- **How the waiting call hears the answer**: a file it reads every few hundred ms (as `/api/progress` does), or a channel between the two requests. Leaning to the file: it already works.

## Decided with the repo owner (2026-11-12)

- **No time limit**: the card waits for the person, as Claude does. A setting for "no answer after X minutes means no" (Hermes uses 300 s) is a later idea, not 0.1.8.
- **Laws to add** (`LAWS.bend`, proved in `PROOF.bend`):
  - **An answer covers exactly what was answered.** Allow: this once. Allow for session: the same action, exactly, until the conversation ends. Always allow: the same action, exactly, in this project only. And the same action is never asked twice in a row: the bug can't come back. ("Never asked again", said loosely, would have made Allow mean Always, crossed projects, and let one `rm` stand for another.)
  - **The chat is refused on `LAWS.bend` before the person is asked.** Only the chat: the law agent, which writes the laws after Add, runs with its own tools (`law_agent_claude`) and doesn't go through the interphone.
- **Two buttons, named truly**: Allow and "Allow for this session" (today's "Always allow" only lasts until the page reloads). The law speaks of those two. A real "always, in this project" is a later idea.
- **Dropped**: "no answer means no" (there's no time limit).

## Built so far

- **Piece 1, the interphone** (`GATE.bend`, `server.bend`: `POST /mcp/<turn>`), tested alone on 2026-11-12: Claude 2.1.322 connected to the compiled server, asked with the whole command, waited for the answer file; allow ran it once, deny didn't, no retry. While a call waits, the server still answers the page. Nothing calls it from the app yet.
- **Piece 2, the gate decides** (`GATE.rules()`, `decide()`, `flow()`, `tried()`), 2026-11-16.
- **Piece 3, the card during the turn** (`GET /api/question/<turn>`, `POST /api/answer/<turn>`, the session file per conversation), 2026-11-16.
- **Piece 4, Claude asks the gate** (`--permission-prompts host`, `--permission-prompt-tool mcp__laweditor__approve`, `--mcp-config`), 2026-11-16. Tested in the app. `--safe-mode` turns off MCP, so the chat that asks is isolated by `Policy.claude_isolation_asking()`.
- **Found while building**: `run_to` stops Claude after 600 s (10 min), so "no time limit" needs that raised for the chat (piece 4). One question at a time per turn: two calls at once would overwrite each other's file.

# Next: the game follows the laws (0.2.0)

A design note, not built yet. Written on 2026-11-08 from a talk with the repo owner, to be read by people and by the tools that will help design the larger flows.

## Today (0.1.5)

- The person talks in the chat; the chat hears rules and proposes them; an accepted sentence goes to `GDD.md`, and the law agent writes its law in `LAWS.bend`. This works.
- But a law checks a stand-in, not the game. To state a law, the law agent adds the smallest model it needs to `TYPES.bend` (a player with a position, a `walk` function). The game the chat builds (for example `plataforma.html`, in JavaScript) is separate code that never meets that model.
- So a game can break a rule and nothing turns red.

## 0.2.0: the laws check the game itself

- The game's logic is written in Bend: its state, and what each action does (walk, jump, lose a life). A page only reads input and draws what Bend returns, as LawEditor itself is built.
- The laws talk about that code, not about a stand-in. Bend checks them, and proofs show the game keeps them.
- If the chat changes the game and breaks a rule (the player rises while walking), the law turns red.

## The first decision: which language

Laws only work on Bend code. So a request to build starts with this choice:

1. **The person names another language** (Python, Unity, JavaScript…): build in it, and say the laws won't check this code.
2. **No language named**: build the logic in Bend, and the laws check it.
3. **No language named, but Bend can't do it yet** (3D, for example): say so, and ask whether to go on in another language (without law checks) or with a simpler version in Bend.

## Open questions

- **Who decides case 3?** The model (a skill: it guesses and can be wrong), or a list in Bend of what Bend can do today (2D canvas, keyboard, sound…) that the system reads and laws can check. The second fits the method: a system step, proved, not a model's guess.
- **Where the flow lives.** Like `HEAR.flow()` and `OFFER.flow()`, this flow should be data in `FLOW.bend` form, drawn by Bend-UI's diagram and checked by the same laws (whole, skill then system, no write without the person) before it is built.
- **What the person sees.** Which language the game is in, and whether its laws are on, should be visible in the chat, not guessed.
- **The step after.** Once the logic is in Bend, how the law agent and the game code stay one: the law agent writes laws against the game's functions instead of adding a stand-in to `TYPES.bend`.
