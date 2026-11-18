# Changelog

Versions stay at 0.x until the MVP. Each iteration raises the last digit.

## Next

What the person asked for, as goals. Each one becomes an iteration when it's picked.

- The chat answers fast.
- The game the chat builds follows the laws: Bend checks the game itself, not only `TYPES.bend`.
- The chat proposes only sentences that are rules.
- Codex asks before changes too.
- Codex's answer comes without its own notice ("Reading additional input from stdin...").
- When a project is done, the chat shows a link that opens its folder on the computer.
- A main chat that opens other chats (NEXT.md: options B and C).

## 0.1.11 (2026-11-17, work in progress: not validated by the owner yet)

On the branch `harness-engine`, with Bend-UI's branch `harness-panes` (1.1.21, not released). From the options approved in the "LawEditor Harness Options" artifact.

- **One engine, and windows on it.** The conversation lives in the server: `engine/TURN.bend` conducts a turn (the AI, each law it heard, the mode it offers, the gate's questions, the laws written) and keeps every step as an event (`harness/EVENTS.bend`). The page only sends what you wrote or answered and draws the events. Before, the page kept the conversation and conducted the turn, so nothing else could use the app.
- **No current project.** `projects/.current` is gone: every request names its project and its conversation. Any number of conversations and windows go at once. This also ends a leak seen in 0.1.10: a new conversation inherited another game's sentences, because the Laws page kept the document in memory and wrote it into whatever project was "current".
- **Your projects live in `~/LawEditor`**, out of LawEditor's own folder (`LAWEDITOR_HOME`, `LAWEDITOR_PORT`). The first start copies the ones 0.1.10 kept in `projects/`; conversations kept as `Person:` / `Agent:` lines open as before. A game's folder takes the game's name when the game is born (`fox-run`, not the conversation's id).
- **Any folder of the computer can be a project**, where it is (Open a folder… under the message box, with the computer's own folder chooser on macOS; `laweditor here` in a terminal).
- **The side bar lists every conversation with its state**: a dot while the chat works, another while it waits for you, and the game's name. Its menu renames the game, opens its folder, or deletes the conversation (to the project's `.laweditor/trash`). You can start another conversation while one works.
- **The place button under the message box** says New project and nothing has to be picked; its menu puts a new conversation in a game that exists or in a folder of the computer.
- **LawEditor in the terminal**: `laweditor` (`cli.bend`, `bun run cli`) is a second window on the same engine. A question is answered with its letter; `/new`, `/list`, `/open <n>`, `/mode`, `/quit`.
- **A command of your own**: a message that starts with `!` runs in the project's folder, and the chat reads what it printed. A mode that only reads runs none.
- **The project's files, in a pane beside the chat** (Bend-UI's panes: tree, pane): what the chat changed is marked, a file opens there read only, and a file's name in a reply's "files changed" opens it.
- **A real terminal in the app**, in a pane under the chat: your own shell, in the project's folder. A few lines of `python3` hold the pseudo-terminal, since Bend runs a program and waits for it to end. The chat neither sees it nor types in it.
- **Compact view**: the chat and the terminal, with a line of state on top (the game, how many conversations work, how many wait for you).
- **The server only answers its own windows**: a request another site's page sends, or one not addressed to the server by its own name, is refused. It runs commands, so this matters.
- **The house in order**: `engine/` (what runs), `harness/` (the rules the chat follows and what the AIs are told), `flows/` (the drawings). `LAWS.bend` only changed its import paths.
- **Legacy gone**: `.detail` in place of `.meta`; what is only read has no hover (the laws list, the law beside a sentence); the faces in the chat only look; the key-chosen item of the `/` and `@` list shows; Files and Context in Laws show when they are on; code in replies is colored; the page's own side bar toggle, `title_of` and `is_start` are gone.
- **Tested**: with a stand-in AI, in a browser driven by script: a law asked, added, written and checked; a game born and named; the mode offered and switched; three conversations at once in different states; stop; an old conversation opened whole; the Laws page showing only its own project; the files pane; a command in each mode; the real shell (typed, closed, opened again, ended); the compact view. With Claude itself: one turn in Ask before changes, where the gate asked twice and the file was written. Other sites' requests answered 403.
- **Kept on purpose**: `btn--ghost` and `btn--primary`. The lib calls them older names of `btn--plain btn--neutral` and `btn--filled`, but two of its rules exist only under the old ones (the current item of a side bar, the toolbar's main button), so renaming loses them. To settle in Bend-UI.
- **Not yet**: no law covers the engine (NEXT.md lists the ones to propose). Two conversations in the same project can change the same file. The terminal draws lines and colors, not a full screen (no editor like vim), and needs `python3`. The folder chooser is macOS only (elsewhere: `laweditor here`). A deleted conversation has no way back in the app (its files are in `.laweditor/trash`). Codex still can't ask.

## 0.1.9 (2026-11-17)

- **Allowed in this chat, in the mode's menu.** In a mode that asks, the mode button carries the count ("Ask before changes · 3 allowed"), and its menu shows what the person allowed for this conversation: newest first, each row with its kind (Run, Edit, Write) and the exact action, a Find… field, × to take one back and "Stop allowing all". The list shows 8 rows and scrolls inside the menu (Bend-UI 1.1.10's menu with a list). Anything else still asks.
- **Bend decides what the menu shows** (`GATE.bend`, `allowed_*`): the list read from the session file, the count, each row's kind, tone and text, finding, and taking back one action or all of them. `server.bend` answers `GET /api/allowed/<conversation>` and `POST /api/allowed/<conversation>` (body: the action, or `all`).
- **Bend-UI 1.0.3 → 1.1.10.** Follow is gone from the lib (1.0.16), so the laws screen no longer scrolls along while laws are generated. Tones and dots use the lib's new names (success, warning, danger); nothing looks different.
- **Tested in the app**: Allow for this session put "1 allowed" on the button and the row in the menu; × took it back, and the same command asked again.
- **Not yet**: chat replies are shown as plain text, not Markdown. The two laws decided on 2026-11-12 are still not in `LAWS.bend`.

## 0.1.8 (2026-11-16)

- **The chat asks Bend before it acts, and the endless question is gone.** In Ask before changes, Claude no longer checks its own list and retries: before an action that isn't on it, it asks LawEditor's interphone (`GATE.bend`, `POST /mcp/<conversation>/<turn>`, `--permission-prompt-tool`) with the whole action and waits, with no time limit. A command made of parts (`touch hello.txt; ls | tr a-z A-Z`) is asked once and runs once.
- **The gate's rules are one list that runs and draws itself** (`GATE.rules()`): a law forbids it (the chat changing `LAWS.bend`, by edit or by any command naming it), the mode forbids it (Only read: anything but reading), allowed for this session already (the same action, exactly), otherwise ask. `GATE.decide()` runs the list, `GATE.flow()` draws it, and `GATE.tried()` runs it on six actions and groups them by answer: the diagrams "Permission: the gate decides" and "Permission: the gate, tried".
- **The card shows during the turn**: Allow (this once), Allow for this session (kept on the server for this conversation, until the page reloads), Don't allow. When a rule refuses, the chat is told why, so it doesn't try another way.
- **Isolation for the chat that asks**: `--safe-mode` turns off MCP servers, the interphone included, so this chat runs with `Policy.claude_isolation_asking()`: none of the person's settings files (permission rules, hooks, plugins), no MCP server but LawEditor's, no skills or commands. A `CLAUDE.md` in the project folder and Claude's own memory for that folder are no longer kept out. Only read keeps `--safe-mode`.
- **Removed**: the retry flow (`/api/allow`, `--resume`, "Always allow").
- **Tested in the app**: the card came during the reply; Allow for this session ran the command once; the same command again ran without asking.
- **Not yet**: the two laws decided on 2026-11-12 (an answer covers exactly what was answered; the chat is refused on `LAWS.bend` before the person is asked) are in the gate's code, not yet in `LAWS.bend`. Codex still can't ask.

## 0.1.7 (2026-11-12)

- **The harness, drawn from its own code.** `ARCH.bend` is the harness as it is today, as a `FLOW.bend` flow (who acts where); the words for modes, flags and tools are read from `POLICY.bend`, so they follow the code. `DIAGRAMS.bend` turns `HEAR.flow()`, `OFFER.flow()` and `ARCH.flow()` into Mermaid text (`bend DIAGRAMS.bend` prints them; with a URL it sends the ones that changed, from a clean commit only). Each diagram's top node names the commit it came from.
- **A legend for who acts** (`FLOW.who_means`): Person, Skill and System each say what they are, and the diagrams draw their legend from it.
- **Known:** unstable, with bugs not yet listed. This version saves the state as it is before the next round of fixes.

## 0.1.6 (2026-11-11)

- **The chat proposes laws again, also the ones nobody said.** Since 0.1.4 each mode told the chat what to do with a request to build, and the chat did that and dropped its LAW: lines. Now every mode carries one more line, `Policy.still_hears()`, added in `mode_section` so no mode can leave it out; the Switch message (`OFFER.told()`) says it too.
- **Where the rules are** (`HEAR.md`): most rules are never said. The chat looks in what the person says, in what their words take for granted ("a top-down shooter": the player moves in four directions), and in what it decided while building (one shot kills an enemy). Each becomes a proposal: Add, Always add or Don't add. At most five per reply, the most important first. `HEAR.flow()` names the step that way.
- **Tested** with "quero um top down shooter", which states no rule: Only read proposed 3 laws, Ask before changes 5 laws of the game it planned. A rule added from the chat got its law from the law agent, and Bend accepted it.

## 0.1.5 (2026-11-08)

- **Debug screen** (side bar › Debug, to remove later): LawEditor's own `LAWS.bend`, exactly as the file is, and the output of `bend PROOF.bend`, run by the server each time the screen opens (`GET /api/debug/LAWS.bend`, `GET /api/debug/check`). Nothing on it is typed by hand: a law added, changed or removed shows there as it is, and a law that fails shows Bend's own error.

## 0.1.4 (2026-11-07)

- **The chat offers the mode** (`OFFER.bend`, flow A of the four drawn on 2026-11-07). In Only read, when the person wants something built, the chat ends its reply with `MODE: "Ask before changes"`; the page asks Switch / Stay. Switch moves the picker and sends the request again; in Ask before changes the chat writes the smallest version to play first, says how to open it, and asks one question. Stay keeps Only read.
- **The flow is the source, and it is checked.** `OFFER.flow()` is drawn in Chat › Context by Bend-UI's diagram. New laws (`LAWS.bend`, proved in `PROOF.bend`): `offer_flow_is_whole`, `offer_flow_skill_then_system`, `offer_flow_writes_need_you`, `stay_keeps_only_read`, `switch_asks_first`, `reply_hides_offer`.
- **Validated in the app against the diagram**, "quero um jogo de plataforma so andar pro lado":

  | Step | Seen |
  |---|---|
  | You ask for something to be built | Sent in Only read |
  | The chat ends its reply with MODE: | Yes, with a rule (first try missed it: "I want a game" read as a description; the Only read text now says wanting a game means building it) |
  | Switch to Ask before changes? | Card shown, talk stopped |
  | The picker moves; the request goes again | Picker on Ask before changes; a new reply started |
  | The chat writes the smallest version | `plataforma.html` (canvas, arrows or A/D) |
  | Claude refused, question | Allow card with the file |
  | Write it; how to open it; one question | Written; "clique duplo nele"; one question about the screen edge |
  | Stay, Don't allow | Not clicked in this run (Stay is proved by `stay_keeps_only_read`) |

- **Known:** the Allow card shows the whole file, so a game makes it long. The offer card and a rule card can wait at the same time, and answering one frees the message field. The first answer took about 30 s (the chat reads the project first).

## 0.1.3 (2026-11-07)

- **The chat shows its answer while it writes it** (Claude). Claude runs with `--include-partial-messages` and its output goes to a file for the turn (`/tmp/laweditor-turn-<id>.jsonl`; the id keeps only letters and digits). The page asks `GET /api/progress/<id>` every 300 ms and draws the text so far; `ASK.bend` reads it (the message being written now). Codex still answers all at once. Measured: the first words show about 3 s after sending, instead of the whole answer at the end.
- **The server runs compiled** (`bun run start` builds `dist/laweditor-server`). Run as `bend server.bend`, Bend waits for a program to finish before it answers anything else, so the page couldn't ask for the answer so far; the compiled server answers while Claude works.

## 0.1.2 (2026-11-07)

- **The chat builds, and says how.** `CHAT.md` says the chat helps build the project as far as its mode allows, and hears its rules. In Only read, asked to build or change something, it says it can once the person picks Ask before changes (as Claude Code does when a mode blocks it), never that it isn't its job. Tested: "cria um jogo da velha que é impossivel perder e tem grafico de gameboy" in Only read now answers "Posso criar o jogo quando você escolher Ask before changes".
- **The chat runs apart from the person's own Claude Code** (`--safe-mode`, `Policy.claude_isolation`): their CLAUDE.md, plugins, hooks and memory don't reach it, and it starts in about half the time (a bare "oi": about 5.4 s before, 2.4 s now). Asking, Allow and the LAWS.bend refusal work the same.
- Not the cause: the person's connectors (Gmail, Drive…) never load in the chat.

## 0.1.1 (2026-11-07)

- **Fix: Allow didn't let the chat write a file.** Two causes, both in `ASK.bend`. (1) A new or rewritten file comes from Claude's Write tool, and the app allowed it as `Write(//path)`; Claude doesn't take that rule, so Write stayed refused. Claude's file rules are all `Edit(…)`, which covers Write: the grant is now always `Edit(//path)`. (2) Claude's refusal tells it "don't retry, it will be refused for the rest of this session"; told only "Go ahead", it gave up after a few tries. The resume now says what was allowed and that the earlier refusal no longer applies. Tested in the app: "Create a new file TEST.md", Allow, the file is written. The question for Write says "write", not "create" (it may be an existing file).
- **The version** shows at the window's bottom-right (a `tag`, from `package.json`); "Made with Bend-UI" stays alone at the left. Bend-UI 1.0.3 (`.window__foot--end`).
- **The chat knows what a rule is** (`HEAR.md`): one fact that can be checked. "What exists or what someone can do", two things in one sentence, and vague words are not rules yet. With something vague, the chat proposes its clear meaning, or asks one plain question with options and waits. Tested: "eu quero criar um jogo 2D onde eu ando e atiro" gave "Quando o jogador anda, a posição dele muda" (its law compiles) and a question about shooting; the answer "aparece uma bala e a munição diminui" gave two rules.
- **Known issue:** the chat can still propose a sentence that isn't a rule. The skill is a prompt, not a check, so it improves the odds but doesn't guarantee it. When it happens, the law agent refuses the sentence and says why; nothing invalid is written. Seen again on 2026-11-07, after the fix.

## 0.1.0 (2026-11-07)

The chat and the laws talk.

- **The chat hears rules** (`HEAR.md`, `HEAR.bend`): it ends its reply with the rules it heard; each becomes a question (Add, Always add, Don't add), and an added sentence gets its law.
- **The chat's modes** (`POLICY.bend`, `HARNESS.md`), picked under the message field:
  - **Only read**, the start: it reads and changes nothing.
  - **Ask before changes**, Claude only (`ASK.bend`): what it isn't allowed is refused and turned into a question (Allow, Always allow, Don't allow); the same conversation goes on with what the person allowed.
  - `LAWS.bend` is refused in every mode.
- Chat › Context shows `HARNESS.md`: what the chat may do in each mode, and when it asks.
- Bend 2.0.40 added `Tool` to Base, so the policy's types are `AgentTool` and `Agent`, with qualified constructors.
- **Known:** Codex can't ask yet (Ask before changes is off with Codex). The version in the window's bottom-right waits for a footer slot in Bend-UI.
