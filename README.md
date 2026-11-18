# LawEditor

A workbench for [Bend](https://github.com/bendlang/bend): talk with an agent about your project, and turn what you mean into **laws** the Bend compiler checks.

- **Chat**: talk with Claude or Codex about your project. What it may do is the mode you pick: only read, or ask you before each change.
  When you state a rule in the talk ("the player starts with 3 lives"), the chat proposes it as a sentence; you answer Add, Always add (this conversation) or Don't add. An added sentence goes to the document and its law is written and checked, as with Generate.
- **Laws**: write a rule in a plain sentence; the agent writes it as a Bend law, and Bend checks it.
- **One engine, several windows**: the page and the terminal (`laweditor`) show the same conversations. Any number of them go at once, each in its own project.

Everything is Bend: the server (`server.bend`), the engine (`engine/`), the rules the chat follows (`harness/`), the terminal (`cli.bend`), the editor's own rules (`LAWS.bend`), and the look ([Bend-UI](https://github.com/isabellaherman/Bend-UI), whose rules are laws too). JS only reads input and draws.

## What is checked

Nothing here asks to be trusted. Each claim below is checked by the Bend compiler, or enforced by a tool.

| Claim | How |
|---|---|
| A law you write compiles | `bend LAWS.bend --check-only`, run by the agent and again by the server. Red when it doesn't, with the reason |
| The editor follows its own rules (below) | `LAWS.bend` + `PROOF.bend` in this repo: `bun run check` |
| The look stays on the design system: spacing scale, control heights, nested radii, the 4 grid | Bend-UI's laws: a value off the scale doesn't compile |
| Shortcuts never clash, keep the browser's keys, and never fire while you type | Bend-UI's key laws |
| The chat does only what its mode allows | `POLICY.bend` holds the modes (`HARNESS.md`). **Only read** (the start): laws prove Claude gets `--allowedTools Read` and Codex `--sandbox read-only`. **Ask before changes** (Claude only): before an action that isn't reading, Claude asks the gate and waits; `GATE.bend`'s rules decide (a law forbids, the mode forbids, allowed for this conversation, otherwise you are asked). `LAWS.bend` is denied in every mode. The CLI enforces them |
| The law agent reads, edits, writes and runs only bend | `POLICY.bend`; laws prove Claude gets `--allowedTools Read,Edit,Write,Bash(bend:*)`. Codex can't allow one command: it gets `--sandbox workspace-write`, so it writes only in the project folder but may run other commands there |
| The chat adds nothing without you | The skill `HEAR.md` (a prompt) asks the chat to end its reply with `LAW: "<sentence>"` lines; it can miss a rule or make one up. `HEAR.bend` reads them, and laws prove: every conversation starts by asking, Don't add adds nothing, only Always add stops the asking, a sentence already in the document isn't asked again. The engine writes the sentence; the chat still only reads |
| Only this computer's own windows reach the server | `server.bend` refuses a request another site's page sends (its `Origin`) or one not addressed to it by its own name (`Host`). Not a law yet: tested by hand |
| You see exactly what the agents are told | Laws › Context shows `AGENT.md`, Chat › Context shows `CHAT.md` and its skill `HEAR.md`; the server sends those files as they are |
| The model lists are real | Read from each AI's CLI by `MODELS.bend`; none is typed by hand |

The editor's own rules (`LAWS.bend`, proved in `PROOF.bend`):

- A title never gets a state.
- Editing a line with a law, or one that failed, sends it back to empty.
- If a line was edited while the agent worked, the answer is dropped.
- With nothing pending, there is nothing to generate; and one run at a time.
- A law block and a sentence block have the same minimum height.
- In Only read, the chat may only read, and never changes a file (`POLICY.bend`): Claude gets `Read`, Codex the `read-only` sandbox.
- The law agent may read, edit, write and run bend, and nothing else: Claude gets exactly that; Codex writes only in the project folder.
- Each tool says what it does: reading never changes a file, and the chat runs no command.

## Run

You need [Bend](https://github.com/bendlang/bend) (`bend` on your PATH), [Bun](https://bun.sh), and `claude` (Claude Code) or `codex` installed and logged in. The terminal inside the app also needs `python3`.

```bash
bun install
bun run start
```

Open http://127.0.0.1:4280. `bun run start` builds the page, the server (`dist/laweditor-server`) and the terminal (`dist/laweditor`), and runs the server in the home of your projects.

- **Your projects live in `~/LawEditor`**, one folder each (`LAWEDITOR_HOME` names another home). A project holds `GDD.md` (your sentences), `TYPES.bend` and `LAWS.bend` (the laws), `game/` (what the chat builds) and `.laweditor/` (its name, its conversations, what you allowed, each turn's record).
- **Any folder of the computer can be a project**, where it is: Open a folder… under the message box, or `laweditor here` in a terminal. LawEditor keeps its things in a `.laweditor` folder inside it.
- `LAWEDITOR_PORT` moves the server from 4280.
- Coming from 0.1.10: the first `bun run start` copies the projects kept in `projects/` to `~/LawEditor`. The originals stay where they were.

## The terminal

```bash
ln -s "$PWD/dist/laweditor" /usr/local/bin/laweditor   # once, so it runs from anywhere
laweditor          # a new conversation (in this folder's project, when the folder is one)
laweditor here     # this folder becomes a project, and the conversation is in it
laweditor list     # the conversations, with their state
```

It is a second window on the same server (which has to be running): what you do there shows in the app, and what the app does shows there. Write and press Enter; a question is answered with its letter; `!command` runs a command in the project; `/new`, `/list`, `/open <n>`, `/mode`, `/quit`.

## How it works

The app opens on a new conversation, with nothing to pick. The side bar has **New conversation**, **Laws**, **Debug**, and the list of every conversation: the one that moved last first, each with its state (a dot while the chat works, another while it waits for you) and its game's name. Its menu (…) renames the game, opens its folder or deletes the conversation (it goes to the project's `.laweditor/trash`).

**Chat** talks with an AI. Your first message starts the conversation in a folder of its own; once it has a sentence or a file it becomes a game, named by the chat, and the folder takes that name. Under the message field:

- **Where**: it says New project. Its menu puts a new conversation in a game that exists, or opens a folder of the computer. Once the conversation has begun it stays where it is.
- **The AI** (Claude or Codex) and **its model**: the list comes from that AI's own CLI (`claude --help` aliases, `codex debug models`).
- **The mode**: **Only read** (it reads your project and never edits it) or **Ask before changes** (Claude only: before it changes a file or runs a command, you get Allow / Allow for this session / Don't allow). In a mode that asks, the menu also lists what you allowed in this conversation.

A reply and everything that comes of it is one **turn**, drawn on one ruler (Bend-UI's `.turn`): its plan, each thing it did (a row that opens to what it answered), what it does now, its words, then one line with the files it changed. When the reply ends, its work folds into one line ("Worked for 48s · 3 actions") that opens again. The rules it heard stay under it, each with what came of it.

A **question** (a rule to add, the mode it offers, an action that needs your yes) takes the message box's place until you answer: where you answer is where it asks, with what would change shown in it. The turn keeps one line as the record ("Allowed · Write index.html"). An action you refused says "not run", and a file counts as changed only when the action that changes it ran.

A message that starts with `!` is a command you run yourself in the project (`!ls`); `/` lists the commands and `@` points to a file. The chat's **Context** button shows `CHAT.md`, its skill `HEAR.md` and `HARNESS.md` (what the chat may do, and when it asks).

Several conversations go at once: start another while one works, and come back to it from the list.

In the toolbar: **Files** opens the project's files in a pane at the right (a file opens there, read only; a file's name in a reply's "files changed" opens it too). **Terminal** opens your own shell in the project's folder, in a pane under the chat; the chat neither sees it nor types in it. **Compact view** keeps the chat and the terminal, with a line of state on top.

**Laws** is where rules become laws. It shows the open conversation's project:

1. Write a rule and press Enter. It gets an empty dot.
2. Pick an AI in the agent (hover the face) and press **Generate LAWs**.
3. For each sentence, the agent adds what's missing to `TYPES.bend`, appends one law to `LAWS.bend`, and checks it with `bend LAWS.bend --check-only`. The server checks again.
4. Green: the law compiles (a law with no proof yet is fine). Red: it doesn't, or the agent couldn't write one; the message says why.

The selector shows the sentences alone, with their laws, or side by side. Two buttons on the right show:

- **Files** (`<>`): `LAWS.bend` and `TYPES.bend` as they are. Deleting a sentence never deletes its law: the law turns amber here until you remove it. To edit, hold the lock.
- **Context** (book): `AGENT.md`, exactly what the law agent is told. Read only.

## How it is built

One engine, and windows on it. The server keeps nothing in memory and has no "current" project: every request names its project and its conversation, and what happened is in their files.

- A conversation is a list of events, kept with its project (`harness/EVENTS.bend`): what you wrote, each turn, each reply, each question and its answer, the game being born. Nothing is ever taken out.
- `engine/TURN.bend` conducts a turn: it runs the AI, asks each law it heard, offers the mode, asks before an action through the gate, and writes the laws. The rules of each step are in `harness/`.
- A window sends what you wrote or answered (`POST /api/c/<project>/<conversation>/say`, `answer/<question>`, `stop`) and reads the events after the ones it has (`GET …/events/<n>`). The page draws them; the terminal prints them.

## Files

| File | What it is |
|---|---|
| `server.bend` | The door: reads a request and hands it to the engine. Refuses what isn't from its own page or terminal |
| `cli.bend` | LawEditor in the terminal (`dist/laweditor`): a window on the same engine |
| `engine/TURN.bend` | A conversation's turn, conducted: the AI, the questions, the laws, the events |
| `engine/PROJECTS.bend` | The projects: their folders, their lists, a game being born, a folder opened from elsewhere |
| `engine/LAW.bend` | The law agent: writes one sentence's law, and Bend checks it |
| `engine/TERMINAL.bend` | A real shell in a project, for the terminal pane |
| `engine/PLACES.bend`, `engine/SYS.bend` | Where each thing is kept; files and programs |
| `harness/EVENTS.bend` | A conversation as events: writing them, and reading what is going on from them |
| `harness/POLICY.bend` | The tools (and what each does: changes a file, runs a command), the two agents, the chat's modes, and the tools each is given; each CLI's flags come from it |
| `harness/GATE.bend` | The gate: the rules that decide an action (a law forbids, the mode forbids, allowed, ask you), and what was allowed |
| `harness/HEAR.bend` | The chat hears rules: reads its `LAW:` lines, and when to ask (Add / Always add / Don't add) |
| `harness/OFFER.bend` | The chat offers the mode: in Only read, a request to build becomes Switch / Stay |
| `harness/ASK.bend` | Reads what Claude sends: an action, a turn's answer while it is written, its work |
| `harness/CHAT.bend`, `harness/MODELS.bend` | The chat's small rules (when Send is on, the commands, the game's name); the models each AI's CLI offers |
| `harness/AGENT.md`, `CHAT.md`, `HEAR.md`, `HARNESS.md` | What the law agent is told; what the chat is told; its skill; what it may do and when it asks |
| `flows/FLOW.bend` | How a flow is written: its steps, who acts in each, where each goes |
| `flows/ARCH.bend`, `PERMIT.bend`, `DIAGRAMS.bend` | The harness, the permission flows, and the program that draws them |
| `EDITOR.bend` | The Laws editor's logic (line states, when Generate is on) |
| `LAWS.bend` / `PROOF.bend` | The editor's own rules and their proofs (`bun run check`) |
| `web/` | The page: `index.html` (Bend-UI classes only); `main.js` (Laws), `chat.js` and `chat/` (Chat), `files.js`, `shell.js`, `compact.js`, `where.js`, `markdown.js`. They draw; no CSS of its own |

Agent instructions for this repo: [`AGENTS.md`](AGENTS.md).
