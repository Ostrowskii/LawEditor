# LawEditor server. Run it from your project folder:
#
#   bend /path/to/LawEditor/server.bend /path/to/LawEditor/dist /path/to/LawEditor/harness/AGENT.md
#
# It serves the editor, keeps the project's files (GDD.md, TYPES.bend, LAWS.bend)
# in the folder it runs from, and runs the agent (claude or codex) there.

import Base
import ./harness/MODELS.bend as Models
import ./harness/POLICY.bend as Policy
import ./harness/ASK.bend as Ask
import ./harness/GATE.bend as Gate
import ./harness/CHAT.bend as Chat

# ---------- Text ----------

# The n-th item of a list of strings, or "".
def nth(xs: List<&2, String>, n: Nat) -> String:
  match xs n:
    case Nil{} _:
      ""
    case h <> t 0n:
      h
    case h <> t 1n+k:
      nth(t, k)

# The n-th word of the request line: "GET /path HTTP/1.1".
def req_word(s: String, n: Nat) -> String:
  nth(String.split(s, ' '), n)

# Everything after the blank line that ends the headers.
def req_body.at(s: String, here: Bool) -> String:
  match s here:
    case SNil{} _:
      ""
    case SCon{h, t} True{}:
      String.drop(SCon{h, t}, 4n)
    case SCon{h, +t} False{}:
      req_body.at(t, String.starts_with(t, "\r\n\r\n"))

def req_body(+s: String) -> String:
  req_body.at(s, String.starts_with(s, "\r\n\r\n"))

# The part of a path after a prefix: "/api/file/LAWS.bend" less "/api/file/" is "LAWS.bend".
def after(s: String, prefix: String) -> String:
  String.drop(s, String.length(prefix))

def pick(c: Bool, a: String, b: String) -> String:
  match c:
    case True{}:
      a
    case False{}:
      b

# ---------- HTTP ----------

def content_type(+path: String) -> String:
  pick(String.ends_with(path, ".html"), "text/html; charset=utf-8",
  pick(String.ends_with(path, ".js"), "text/javascript; charset=utf-8",
  pick(String.ends_with(path, ".css"), "text/css; charset=utf-8",
  pick(String.ends_with(path, ".svg"), "image/svg+xml",
  pick(String.ends_with(path, ".webp"), "image/webp",
  pick(String.ends_with(path, ".png"), "image/png",
  "text/plain; charset=utf-8"))))))

def http(status: String, ctype: String, body: String) -> String:
  "HTTP/1.1 " ++ status ++ "\r\nContent-Type: " ++ ctype ++ "\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n" ++ body

def ok_text(body: String) -> String:
  http("200 OK", "text/plain; charset=utf-8", body)

def not_found() -> String:
  http("404 Not Found", "text/plain; charset=utf-8", "not found")

# ---------- Files ----------

def text_of(r: Result<&1, &1, U32 & String, String>) -> String:
  match r:
    case Fail{e}:
      ""
    case Done{text}:
      text

def read_got(got: File & Result<&1, &1, U32 & String, String>) -> IO(String):
  (f, r) = got
  do IO<String>:
    File.close(f)
    return text_of(r)

# A whole file as text, or "" if it can't be read.
def read_open(r: Result<&1, &1, U32 & String, File>) -> IO(String):
  match r:
    case Fail{e}:
      IO.pure(String, "")
    case Done{f}:
      do IO<String>:
        got : File & Result<&1, &1, U32 & String, String> <- File.read(f, 4194304)
        read_got(got)

def read_file(path: String) -> IO(String):
  do IO<String>:
    r : Result<&1, &1, U32 & String, File> <- File.open(path, "r")
    read_open(r)

def write_done(w: File & Result<&1, &1, U32 & String, Unit>) -> IO(Unit):
  (f, r) = w
  File.close(f)

def write_open(r: Result<&1, &1, U32 & String, File>, data: String) -> IO(Unit):
  match r:
    case Fail{e}:
      IO.pure(Unit, Unit{})
    case Done{f}:
      do IO<Unit>:
        w : File & Result<&1, &1, U32 & String, Unit> <- File.write(f, data)
        write_done(w)

def write_file(path: String, data: String) -> IO(Unit):
  do IO<Unit>:
    r : Result<&1, &1, U32 & String, File> <- File.open(path, "w")
    write_open(r, data)

# Create a file with a starting text, only if it doesn't exist yet.
def ensure_open(r: Result<&1, &1, U32 & String, File>, path: String, data: String) -> IO(Unit):
  match r:
    case Fail{e}:
      write_file(path, data)
    case Done{f}:
      File.close(f)

def ensure_file(+path: String, data: String) -> IO(Unit):
  do IO<Unit>:
    r : Result<&1, &1, U32 & String, File> <- File.open(path, "r")
    ensure_open(r, path, data)

# The files the editor may read and write in the project folder.
def is_project_file(+name: String) -> Bool:
  (String.eq(name, "GDD.md") || String.eq(name, "TYPES.bend") || String.eq(name, "LAWS.bend"))

# ---------- Processes ----------

# Run a program; answer its exit code and output (stdout, then stderr), or 127 if it can't start.
def run_out(r: Result<&1, &1, U32 & String, U32 & (String & String)>) -> U32 & String:
  match r:
    case Fail{(code, msg)}:
      (127, msg)
    case Done{(code, (out, err))}:
      (code, out ++ err)

# Runs a program with its output going to a file as it is written, so another request can read it
# meanwhile (the chat's answer while it is written: GET /api/progress/<id>). sh only redirects: the
# file and every arg are passed as arguments ("$0", "$@"), never pasted into the command. It also writes
# its process id next to the file (<file>.pid), so Stop can end it (POST /api/stop/<id>).
def run_to.out(r: U32 & String, text: String) -> U32 & String:
  (code, err) = r
  (code, text ++ err)

def run(program: String, args: List<String>, timeout_ms: U32) -> IO(U32 & String):
  do IO<U32 & String>:
    r : Result<&1, &1, U32 & String, U32 & (String & String)> <- Process.run(program, args, "", 4194304, timeout_ms)
    return run_out(r)

# A program run in the project picked now (.current): sh goes there first; the program and its args are
# passed as arguments, never pasted into the command.
def run_in(program: String, args: List<String>, timeout_ms: U32) -> IO(U32 & String):
  run("sh", "-c" <> "cd .current && exec \"$@\"" <> "sh" <> program <> args, timeout_ms)

def run_to(+file: String, program: String, args: List<String>, timeout_ms: U32) -> IO(U32 & String):
  do IO<U32 & String>:
    r : Result<&1, &1, U32 & String, U32 & (String & String)> <- Process.run("sh", "-c" <> "out=\"$(pwd)/$0\"; echo $$ > \"$out.pid\"; cd .current && exec \"$@\" > \"$out\"" <> file <> program <> args, "", 4194304, timeout_ms)
    text : String <- read_file(file)
    return run_to.out(run_out(r), text)

# Is the agent's command installed? `claude --version` / `codex --version`.
def connect_reply(r: U32 & String) -> String:
  (+code, out) = r
  pick(U32.is_eq(code, 0), ok_text("ok"), http("404 Not Found", "text/plain; charset=utf-8", "notfound"))

def connect(ai: String) -> IO(String):
  do IO<String>:
    r : U32 & String <- run(ai, ["--version"], 15000)
    return connect_reply(r)

# The command line for each agent. What it may do comes from POLICY.bend.
# Codex has no per-command allowlist: in its workspace-write sandbox it may run any command in this folder.
def agent_args.pick(is_codex: Bool, prompt: String) -> List<String>:
  match is_codex:
    case True{}:
      ["exec", "--sandbox", Policy.codex_sandbox(Policy.law_agent()), prompt]
    case False{}:
      ["-p", prompt, "--allowedTools", Policy.claude_tools(Policy.law_agent()), "--permission-mode", "acceptEdits"]

def agent_args(+ai: String, prompt: String) -> List<String>:
  agent_args.pick(String.eq(ai, "codex"), prompt)

# Bend checks the laws. A law that compiles but has no proof yet is fine (a TODO);
# an error points at a Location.
def check_reply(agent: U32 & String, check: U32 & String) -> String:
  (+acode, +aout) = agent
  (ccode, +cout) = check
  pick(U32.is_eq(acode, 127), ok_text("error\nCould not start the agent: " ++ aout),
  pick(String.starts_with(aout, "ERROR"), ok_text("error\n" ++ aout),
  pick(String.contains(cout, "Location:"), ok_text("error\n" ++ cout),
  pick(String.contains(aout, "law "), ok_text("ok\n" ++ aout),
  ok_text("error\nThe agent answered without a law:\n" ++ aout)))))

def generate(+ai: String, agent_md: String, sentence: String) -> IO(String):
  do IO<String>:
    rules : String <- read_file(agent_md)
    agent : U32 & String <- run_in(ai, agent_args(ai, rules ++ "\n\n## Sentence\n\n" ++ sentence), 600000)
    check : U32 & String <- run_in("bend", ["LAWS.bend", "--check-only"], 120000)
    return check_reply(agent, check)

# CHAT.md (what the chat is told) lives next to AGENT.md (what the law agent is told).
def chat_md(+agent_md: String) -> String:
  String.reverse(String.drop(String.reverse(agent_md), String.length("AGENT.md"))) ++ "CHAT.md"

# HEAR.md, the chat's skill (it hears rules in the talk: HEAR.bend), lives there too.
def hear_md(+agent_md: String) -> String:
  String.reverse(String.drop(String.reverse(agent_md), String.length("AGENT.md"))) ++ "HEAR.md"

# Debug: LawEditor's own files live there too (LAWS.bend, PROOF.bend). The page shows them as they are.
def editor_file(+agent_md: String, name: String) -> String:
  String.reverse(String.drop(String.reverse(agent_md), String.length("harness/AGENT.md"))) ++ name

def debug_check.out(r: U32 & String) -> String:
  (code, out) = r
  ok_text(out)

# GET /api/debug/check: Bend checks LawEditor's own laws now; its output, exactly as Bend prints it.
def debug_check(+agent_md: String) -> IO(String):
  do IO<String>:
    r : U32 & String <- run("bend", [editor_file(agent_md, "PROOF.bend")], 120000)
    return debug_check.out(r)

# HARNESS.md, what the chat may do and when it asks (POLICY.bend), lives there too.
def harness_md(+agent_md: String) -> String:
  String.reverse(String.drop(String.reverse(agent_md), String.length("AGENT.md"))) ++ "HARNESS.md"

# The chat: the agent answers the conversation so far, with the model picked in the chat.
# What it may do comes from POLICY.bend (LAWS.bend: it only reads). No model: the CLI's own default.
def chat_args.pick(is_codex: Bool, has_model: Bool, model: String, prompt: String) -> List<String>:
  match is_codex has_model:
    case True{} True{}:
      ["exec", "-m", model, "--sandbox", Policy.codex_sandbox(Policy.chat()), prompt]
    case True{} False{}:
      ["exec", "--sandbox", Policy.codex_sandbox(Policy.chat()), prompt]
    case False{} True{}:
      ["-p", prompt, Policy.claude_isolation(), "--model", model, "--allowedTools", Policy.claude_tools(Policy.chat()), "--output-format", "stream-json", "--verbose", "--include-partial-messages"]
    case False{} False{}:
      ["-p", prompt, Policy.claude_isolation(), "--allowedTools", Policy.claude_tools(Policy.chat()), "--output-format", "stream-json", "--verbose", "--include-partial-messages"]

def chat_args(+ai: String, +model: String, prompt: String) -> List<String>:
  chat_args.pick(String.eq(ai, "codex"), Bool.not(String.is_empty(model)), model, prompt)

# Codex answers in plain text, all at once. Claude streams JSON (ASK.bend reads its answer).
def chat_reply.at(is_codex: Bool, +out: String) -> String:
  match is_codex:
    case True{}:
      "ok\n" ++ out
    case False{}:
      "ok\n" ++ Ask.result_or(out)

def chat_reply(is_codex: Bool, agent: U32 & String) -> String:
  (+code, +out) = agent
  pick(U32.is_eq(code, 127), ok_text("error\nCould not start the agent: " ++ out), ok_text(chat_reply.at(is_codex, out)))

# Codex runs as before; Claude writes its answer to the turn's file as it goes.
def chat_run(is_codex: Bool, +ai: String, +id: String, args: List<String>) -> IO(U32 & String):
  match is_codex:
    case True{}:
      run_in(ai, args, 600000)
    case False{}:
      run_to(Ask.turn_file(id), ai, args, 600000)

def chat.go(+ai: String, model: String, +id: String, prompt: String) -> IO(String):
  do IO<String>:
    agent : U32 & String <- chat_run(String.eq(ai, "codex"), ai, id, chat_args(ai, model, prompt))
    return chat_reply(String.eq(ai, "codex"), agent)

# target: "<ai>/<model>/<id>" from /api/chat/<ai>/<model>/<id>; id names the turn's file.
def chat(+target: String, +agent_md: String, conversation: String) -> IO(String):
  do IO<String>:
    rules : String <- read_file(chat_md(agent_md))
    skill : String <- read_file(hear_md(agent_md))
    chat.go(nth(String.split(target, '/'), 0n), nth(String.split(target, '/'), 1n), nth(String.split(target, '/'), 2n), rules ++ "\n\n" ++ Policy.mode_section(Policy.chat_mode()) ++ "\n\n" ++ skill ++ "\n\n## Chat\n\n" ++ conversation)

# GET /api/progress/<id>: the answer so far, while the chat writes it.
def progress(id: String) -> IO(String):
  do IO<String>:
    text : String <- read_file(Ask.turn_file(id))
    return ok_text(Ask.progress(text))

# GET /api/work/<id>: what the chat did so far in the turn: its actions, plan, files changed, and what it
# does now (Ask.work, one line each).
def work(id: String) -> IO(String):
  do IO<String>:
    text : String <- read_file(Ask.turn_file(id))
    return ok_text(Ask.work(text))

# POST /api/stop/<id>: the person pressed Stop. The turn's process ends; its request answers with what it had.
def stop(+id: String) -> IO(String):
  do IO<String>:
    r : U32 & String <- run("sh", ["-c", "kill \"$(cat \"$0\")\"", Ask.turn_file(id) ++ ".pid"], 5000)
    return ok_text("stopped")

# ---------- Projects ----------

def files_list.out(r: U32 & String) -> String:
  (code, out) = r
  out

# The server runs in projects/. Each project is a folder there: its sentences (GDD.md), TYPES.bend and
# LAWS.bend, game/ (what the chat builds), and .laweditor/ (its name, conversations, what was allowed,
# each turn's record). .current points to the one picked now. sh gets every name as an argument.

def make_project_sh() -> String:
  "mkdir -p \"$0/game\" \"$0/.laweditor/chats\" \"$0/.laweditor/allowed\" \"$0/.laweditor/turns\"; [ -e \"$0/.laweditor/name\" ] || printf '%s' \"$1\" > \"$0/.laweditor/name\"; [ -e \"$0/GDD.md\" ] || : > \"$0/GDD.md\"; [ -e \"$0/TYPES.bend\" ] || printf 'import Base\\n' > \"$0/TYPES.bend\"; [ -e \"$0/LAWS.bend\" ] || printf 'import Base\\nimport ./TYPES.bend as T\\n' > \"$0/LAWS.bend\"; ln -sfn \"$0\" .current; printf '%s' \"$0\""

# GET /api/projects: the one picked now on the first line, then one per line: its folder, a tab, its name.
def projects_list() -> IO(String):
  do IO<String>:
    r : U32 & String <- run("sh", ["-c", "readlink .current 2>/dev/null || echo; for d in */; do d=${d%/}; [ -d \"$d\" ] || continue; [ -e \"$d/.laweditor/draft\" ] && continue; n=$(cat \"$d/.laweditor/name\" 2>/dev/null || printf '%s' \"$d\"); printf '%s\\t%s\\n' \"$d\" \"$n\"; done"], 5000)
    return ok_text(files_list.out(r))

# POST /api/projects, body: the name. Makes the project (or finds it) and picks it.
def project_new(+name: String) -> IO(String):
  do IO<String>:
    r : U32 & String <- run("sh", ["-c", make_project_sh(), Chat.slug(name), String.trim(name)], 5000)
    return ok_text(files_list.out(r))

# POST /api/draft/<conversation>: a new conversation with no game gets its own folder, marked as a draft:
# it isn't a game (not in the list of games) until it has a sentence or a file (POST /api/promote).
def project_draft(+conv: String) -> IO(String):
  do IO<String>:
    r : U32 & String <- run("sh", ["-c", make_project_sh() ++ "; : > \"$0/.laweditor/draft\"", Chat.slug(conv), ""], 5000)
    return ok_text(files_list.out(r))

# POST /api/promote, body: the game's name. A draft with a sentence (GDD.md) or a file in game/ becomes a
# game with that name; otherwise nothing changes. Answers "promoted" when it did.
def project_promote(+name: String) -> IO(String):
  do IO<String>:
    r : U32 & String <- run("sh", ["-c", "[ -e .current/.laweditor/draft ] || exit 0; { [ -n \"$(ls -A .current/game 2>/dev/null)\" ] || [ -s .current/GDD.md ]; } || exit 0; printf '%s' \"$0\" > .current/.laweditor/name; rm .current/.laweditor/draft; printf promoted", String.trim(name)], 5000)
    return ok_text(files_list.out(r))

# POST /api/rename/<folder>, body: the game's new name.
def project_rename(+folder: String, +name: String) -> IO(String):
  do IO<String>:
    r : U32 & String <- run("sh", ["-c", "[ -d \"$0/.laweditor\" ] && printf '%s' \"$1\" > \"$0/.laweditor/name\"; printf ok", Chat.slug(folder), String.trim(name)], 5000)
    return ok_text(files_list.out(r))

# POST /api/project/<folder>: picks a project that exists.
def project_pick(+folder: String) -> IO(String):
  do IO<String>:
    r : U32 & String <- run("sh", ["-c", "[ -d \"$0\" ] && ln -sfn \"$0\" .current && printf ok", Chat.slug(folder)], 5000)
    return ok_text(files_list.out(r))

# ---------- Around the chat: the project's files, its folder, the conversations ----------
# The server runs in the project's folder. The conversations are kept with the project, in .laweditor/chats
# (a folder the file list leaves out): one file each, its title on the first line, then the conversation.

# GET /api/files: the project's files, one path per line (for @ in the composer).
def files_list() -> IO(String):
  do IO<String>:
    r : U32 & String <- run("sh", ["-c", "cd .current && find . -type f -not -path '*/.*' | sed 's|^\\./||' | sort | head -300"], 5000)
    return ok_text(files_list.out(r))

# POST /api/open-folder: opens the project's folder on the computer.
def open_folder() -> IO(String):
  do IO<String>:
    r : U32 & String <- run_in("open", ["."], 5000)
    return ok_text("ok")

def chat_file(+id: String) -> String:
  Ask.here(".laweditor/chats/" ++ Ask.safe_id(id) ++ ".txt")

# POST /api/conversation/<id>, body: the conversation. GET it back; GET /api/conversations lists them.
def conversation_save(+id: String, +body: String) -> IO(String):
  do IO<String>:
    r : U32 & String <- run_in("mkdir", ["-p", ".laweditor/chats"], 5000)
    write_file(chat_file(id), Chat.title_of(body) ++ "\n" ++ body)
    return ok_text("ok")

def conversation_get(+id: String) -> IO(String):
  do IO<String>:
    text : String <- read_file(chat_file(id))
    return ok_text(text)

# Every conversation of every project, newest first, one line each: its folder, its game's name (none for
# a draft), its id and its title, split by tabs.
def conversations() -> IO(String):
  do IO<String>:
    r : U32 & String <- run("sh", ["-c", "for f in $(ls -t */.laweditor/chats/*.txt 2>/dev/null); do d=${f%%/*}; i=$(basename \"$f\" .txt); g=''; [ -e \"$d/.laweditor/draft\" ] || g=$(cat \"$d/.laweditor/name\" 2>/dev/null || printf '%s' \"$d\"); printf '%s\\t%s\\t%s\\t%s\\n' \"$d\" \"$g\" \"$i\" \"$(head -n 1 \"$f\")\"; done"], 5000)
    return ok_text(files_list.out(r))

# GET /api/output/<id>/<n>: what the n-th action of the turn answered (its first lines).
def output(+target: String) -> IO(String):
  do IO<String>:
    text : String <- read_file(Ask.turn_file(nth(String.split(target, '/'), 0n)))
    return ok_text(Ask.output(text, Ask.to_u32(nth(String.split(target, '/'), 1n))))

# ---------- The chat that asks (Ask before changes: POLICY.bend, GATE.bend) ----------
# Before an action that isn't on its list, Claude asks LawEditor's interphone (POST /mcp/<conversation>/<turn>)
# and waits; the gate decides, or asks the person on the page. No retry, no --resume. LAWS.bend stays denied
# twice: Claude's own list (Policy.never) and the gate's first rule.

# xs, then rest: the args lists are built as one.
def with_each(xs: List<&2, String>, rest: List<String>) -> List<String>:
  match xs:
    case Nil{}:
      rest
    case h <> t:
      h <> with_each(t, rest)

# Where the server listens; Claude's interphone address is built from it.
def port() -> U32: 4280
def address() -> String: "127.0.0.1:" ++ U32.show(port())

# Where Claude finds the interphone: this server, at this conversation and turn.
def mcp_config(+conv: String, +turn: String) -> String:
  "{\"mcpServers\":{\"laweditor\":{\"type\":\"http\",\"url\":\"http://" ++ address() ++ "/mcp/" ++ Ask.safe_id(conv) ++ "/" ++ Ask.safe_id(turn) ++ "\"}}}"

def ask_args.model(has_model: Bool, model: String, rest: List<String>) -> List<String>:
  match has_model:
    case True{}:
      "--model" <> model <> rest
    case False{}:
      rest

def ask_args(+model: String, +conv: String, +turn: String, prompt: String) -> List<String>:
  "-p" <> prompt <> with_each(Policy.claude_isolation_asking(), ask_args.model(Bool.not(String.is_empty(model)), model,
    "--allowedTools" <> Policy.claude_tools(Policy.chat()) <> "--disallowedTools" <> with_each(Policy.never(),
    ["--permission-prompts", "host", "--permission-prompt-tool", "mcp__laweditor__approve", "--mcp-config", mcp_config(conv, turn),
     "--output-format", "stream-json", "--verbose", "--include-partial-messages"])))

def ask_reply(agent: U32 & String) -> String:
  (+code, +out) = agent
  pick(U32.is_eq(code, 127), ok_text("error\nCould not start the agent: " ++ out), ok_text("ok\n" ++ Ask.result_or(out)))

# POST /api/ask/<model>/<conversation>/<turn>, body: the conversation. A turn of the chat that asks.
# No time limit: while the person hasn't answered, Claude waits, and so does this.
def ask.go(+model: String, +conv: String, +turn: String, prompt: String) -> IO(String):
  do IO<String>:
    agent : U32 & String <- run_to(Ask.turn_file(turn), "claude", ask_args(model, conv, turn, prompt), 4294967295)
    return ask_reply(agent)

def ask(+target: String, +agent_md: String, +body: String) -> IO(String):
  do IO<String>:
    rules : String <- read_file(chat_md(agent_md))
    skill : String <- read_file(hear_md(agent_md))
    ask.go(nth(String.split(target, '/'), 0n), nth(String.split(target, '/'), 1n), nth(String.split(target, '/'), 2n), rules ++ "\n\n" ++ Policy.mode_section(Policy.Mode.AskBeforeChanges{}) ++ "\n\n" ++ skill ++ "\n\n## Chat\n\n" ++ body)

# ---------- The interphone (GATE.bend; NEXT.md, 0.1.8) ----------
# Claude asks POST /mcp/<conversation>/<turn> before an action that isn't on its list, and waits. The question goes to
# a file the page reads; the server waits for the answer file, with no time limit, as Claude does.

def json(body: String) -> String:
  http("200 OK", "application/json", body)

# Read the answer file every 300 ms until it says something (said: the last read, trimmed).
def wait(fuel: Nat, +path: String, said: String) -> IO(String):
  match fuel said:
    case 0n _:
      IO.pure(String, "")
    case _ SCon{h, t}:
      IO.pure(String, SCon{h, t})
    case 1n+f SNil{}:
      do IO<String>:
        IO.sleep(300)
        got : String <- read_file(path)
        wait(f, path, String.trim(got))

# The person answers: the question goes to a file the page reads, and the answer comes back in another.
# Allow for this session adds the action to the conversation's session file.
def mcp.heard(+conv: String, +turn: String, +msg: String, +text: String, +said: String) -> IO(String):
  do IO<String>:
    write_file(Gate.question_file(turn), "")
    write_file(Gate.answer_file(turn), "")
    write_file(Gate.session_file(conv), Gate.session_after(text, msg, said))
    return json(Gate.answer(msg, said))

def mcp.person(+conv: String, +turn: String, +msg: String, +text: String) -> IO(String):
  do IO<String>:
    write_file(Gate.answer_file(turn), "")
    write_file(Gate.question_file(turn), Gate.question(msg))
    said : String <- wait(4294967295n, Gate.answer_file(turn), "")
    mcp.heard(conv, turn, msg, text, said)

def mcp.by(ask: Bool, r: Gate.Rule, +conv: String, +turn: String, +msg: String, +text: String) -> IO(String):
  match ask:
    case True{}:
      mcp.person(conv, turn, msg, text)
    case False{}:
      IO.pure(String, json(Gate.now(msg, r)))

def mcp.ruled(+conv: String, +turn: String, +msg: String, +text: String) -> IO(String):
  mcp.by(Gate.is_ask(Gate.rule_for(msg, Policy.Mode.AskBeforeChanges{}, text)), Gate.rule_for(msg, Policy.Mode.AskBeforeChanges{}, text), conv, turn, msg, text)

# The gate decides (GATE.rules): a law or the mode refuses, the session allows, or the person is asked.
# Only the chat that asks reaches the interphone, so its mode is Ask before changes.
def mcp.call(+conv: String, +turn: String, +msg: String) -> IO(String):
  do IO<String>:
    text : String <- read_file(Gate.session_file(conv))
    mcp.ruled(conv, turn, msg, text)

def mcp.at(notice: Bool, call: Bool, +conv: String, +turn: String, +msg: String) -> IO(String):
  match notice call:
    case True{} _:
      IO.pure(String, http("202 Accepted", "text/plain; charset=utf-8", ""))
    case False{} True{}:
      mcp.call(conv, turn, msg)
    case False{} False{}:
      IO.pure(String, json(Gate.reply(msg)))

# POST /mcp/<conversation>/<turn>: one MCP message.
def mcp(+target: String, +msg: String) -> IO(String):
  mcp.at(Gate.is_notice(msg), Gate.is_call(msg), nth(String.split(target, '/'), 0n), nth(String.split(target, '/'), 1n), msg)

# GET /api/question/<turn>: the question waiting for the person in this turn, or nothing.
def question(+turn: String) -> IO(String):
  do IO<String>:
    text : String <- read_file(Gate.question_file(turn))
    return ok_text(text)

# POST /api/answer/<turn>, body: allow, session or deny (GATE.allow_word…). The waiting call reads it.
# The question goes away at once, so the page doesn't show it twice.
def person_answer(+turn: String, body: String) -> IO(String):
  do IO<String>:
    write_file(Gate.question_file(turn), "")
    write_file(Gate.answer_file(turn), body)
    return ok_text("ok")

# GET /api/allowed/<conversation>: what the person allowed for it (GATE.session_file), for the mode's menu.
def allowed_get(+conv: String) -> IO(String):
  do IO<String>:
    text : String <- read_file(Gate.session_file(conv))
    return ok_text(text)

def allowed_post.write(+conv: String, +left: String) -> IO(String):
  do IO<String>:
    write_file(Gate.session_file(conv), left)
    return ok_text(left)

# POST /api/allowed/<conversation>, body: one action to take back (GATE.allowed_without), or "all"
# (GATE.allowed_all_word). Answers what is left.
def allowed_post(+conv: String, body: String) -> IO(String):
  do IO<String>:
    text : String <- read_file(Gate.session_file(conv))
    allowed_post.write(conv, Gate.allowed_without(text, body))

# The models an AI offers, asked to its own CLI (MODELS.bend reads the answer). Only claude and codex.
def is_ai(+ai: String) -> Bool:
  (String.eq(ai, "claude") || String.eq(ai, "codex"))

def models_args(is_codex: Bool) -> List<String>:
  match is_codex:
    case True{}:
      ["debug", "models"]
    case False{}:
      ["--help"]

def models_read(is_codex: Bool, +out: String) -> String:
  match is_codex:
    case True{}:
      Models.codex(out)
    case False{}:
      Models.claude(out)

def models_reply(is_codex: Bool, r: U32 & String) -> String:
  (code, +out) = r
  ok_text(models_read(is_codex, out))

def models.at(known: Bool, +ai: String) -> IO(String):
  match known:
    case True{}:
      do IO<String>:
        r : U32 & String <- run(ai, models_args(String.eq(ai, "codex")), 30000)
        return models_reply(String.eq(ai, "codex"), r)
    case False{}:
      IO.pure(String, not_found())

def models(+ai: String) -> IO(String):
  models.at(is_ai(ai), ai)

# ---------- Routes ----------

def static_reply(+text: String, +path: String) -> String:
  pick(String.is_empty(text), not_found(), http("200 OK", content_type(path), text))

def route_static.at(bad: Bool, +path: String, dist: String) -> IO(String):
  match bad:
    case True{}:
      IO.pure(String, not_found())
    case False{}:
      do IO<String>:
        text : String <- read_file(dist ++ path)
        return static_reply(text, path)

def route_static(+path: String, dist: String) -> IO(String):
  route_static.at(String.contains(path, ".."), path, dist)

def route_file_get.at(allowed: Bool, name: String) -> IO(String):
  match allowed:
    case True{}:
      do IO<String>:
        text : String <- read_file(Ask.here(name))
        return ok_text(text)
    case False{}:
      IO.pure(String, not_found())

def route_file_get(+name: String) -> IO(String):
  route_file_get.at(is_project_file(name), name)

def route_agent_md(agent_md: String) -> IO(String):
  do IO<String>:
    text : String <- read_file(agent_md)
    return ok_text(text)

def route_chat_md(+agent_md: String) -> IO(String):
  route_agent_md(chat_md(agent_md))

# GET: /api/models/<ai>, /api/connect/<ai>, /api/file/AGENT.md, /api/file/CHAT.md, /api/file/HEAR.md, /api/file/HARNESS.md, /api/file/<name>, or a file of the page.
def route_get.files(is_file: Bool, +path: String, dist: String) -> IO(String):
  match is_file:
    case True{}:
      route_file_get(after(path, "/api/file/"))
    case False{}:
      route_static(pick(String.eq(path, "/"), "/index.html", path), dist)

def route_get.harness_md(is_harness_md: Bool, +path: String, dist: String, +agent_md: String) -> IO(String):
  match is_harness_md:
    case True{}:
      route_agent_md(harness_md(agent_md))
    case False{}:
      route_get.files(String.starts_with(path, "/api/file/"), path, dist)

def route_get.hear_md(is_hear_md: Bool, +path: String, dist: String, +agent_md: String) -> IO(String):
  match is_hear_md:
    case True{}:
      route_agent_md(hear_md(agent_md))
    case False{}:
      route_get.harness_md(String.eq(path, "/api/file/HARNESS.md"), path, dist, agent_md)

def route_get.chat_md(is_chat_md: Bool, +path: String, dist: String, +agent_md: String) -> IO(String):
  match is_chat_md:
    case True{}:
      route_chat_md(agent_md)
    case False{}:
      route_get.hear_md(String.eq(path, "/api/file/HEAR.md"), path, dist, agent_md)

def route_get.agent(is_agent: Bool, +path: String, dist: String, +agent_md: String) -> IO(String):
  match is_agent:
    case True{}:
      route_agent_md(agent_md)
    case False{}:
      route_get.chat_md(String.eq(path, "/api/file/CHAT.md"), path, dist, agent_md)

def route_get.connect(is_connect: Bool, +path: String, dist: String, agent_md: String) -> IO(String):
  match is_connect:
    case True{}:
      connect(after(path, "/api/connect/"))
    case False{}:
      route_get.agent(String.eq(path, "/api/file/AGENT.md"), path, dist, agent_md)

def route_get.models(is_models: Bool, +path: String, dist: String, agent_md: String) -> IO(String):
  match is_models:
    case True{}:
      models(after(path, "/api/models/"))
    case False{}:
      route_get.connect(String.starts_with(path, "/api/connect/"), path, dist, agent_md)

def route_get.output(is_output: Bool, +path: String, dist: String, agent_md: String) -> IO(String):
  match is_output:
    case True{}:
      output(after(path, "/api/output/"))
    case False{}:
      route_get.models(String.starts_with(path, "/api/models/"), path, dist, agent_md)

def route_get.work(is_work: Bool, +path: String, dist: String, agent_md: String) -> IO(String):
  match is_work:
    case True{}:
      work(after(path, "/api/work/"))
    case False{}:
      route_get.output(String.starts_with(path, "/api/output/"), path, dist, agent_md)

def route_get.progress(is_progress: Bool, +path: String, dist: String, agent_md: String) -> IO(String):
  match is_progress:
    case True{}:
      progress(after(path, "/api/progress/"))
    case False{}:
      route_get.work(String.starts_with(path, "/api/work/"), path, dist, agent_md)

# Debug (a screen to remove later): GET /api/debug/LAWS.bend and /api/debug/check.
def route_get.debug_laws(is_laws: Bool, +path: String, dist: String, +agent_md: String) -> IO(String):
  match is_laws:
    case True{}:
      route_agent_md(editor_file(agent_md, "LAWS.bend"))
    case False{}:
      route_get.progress(String.starts_with(path, "/api/progress/"), path, dist, agent_md)

def route_get.debug(is_check: Bool, +path: String, dist: String, +agent_md: String) -> IO(String):
  match is_check:
    case True{}:
      debug_check(agent_md)
    case False{}:
      route_get.debug_laws(String.eq(path, "/api/debug/LAWS.bend"), path, dist, agent_md)

# GET /mcp/<conversation>/<turn>: the interphone sends nothing on its own (no event stream).
def route_get.mcp(is_mcp: Bool, +path: String, dist: String, +agent_md: String) -> IO(String):
  match is_mcp:
    case True{}:
      IO.pure(String, http("405 Method Not Allowed", "text/plain; charset=utf-8", ""))
    case False{}:
      route_get.debug(String.eq(path, "/api/debug/check"), path, dist, agent_md)

def route_get.question(is_q: Bool, +path: String, dist: String, +agent_md: String) -> IO(String):
  match is_q:
    case True{}:
      question(after(path, "/api/question/"))
    case False{}:
      route_get.mcp(String.starts_with(path, "/mcp/"), path, dist, agent_md)

def route_get.allowed(is_a: Bool, +path: String, dist: String, +agent_md: String) -> IO(String):
  match is_a:
    case True{}:
      allowed_get(after(path, "/api/allowed/"))
    case False{}:
      route_get.question(String.starts_with(path, "/api/question/"), path, dist, agent_md)

def route_get.around(+path: String, dist: String, +agent_md: String, files: Bool, list: Bool, one: Bool) -> IO(String):
  match files list one:
    case True{} _ _:
      files_list()
    case False{} True{} _:
      conversations()
    case False{} False{} True{}:
      conversation_get(after(path, "/api/conversation/"))
    case False{} False{} False{}:
      route_get.allowed(String.starts_with(path, "/api/allowed/"), path, dist, agent_md)

def route_get.projects(+path: String, dist: String, +agent_md: String, projects: Bool) -> IO(String):
  match projects:
    case True{}:
      projects_list()
    case False{}:
      route_get.around(path, dist, agent_md, String.eq(path, "/api/files"), String.eq(path, "/api/conversations"), String.starts_with(path, "/api/conversation/"))

def route_get(+path: String, dist: String, +agent_md: String) -> IO(String):
  route_get.projects(path, dist, agent_md, String.eq(path, "/api/projects"))

# POST: /api/generate/<ai> (body: the sentence), /api/chat/<ai>/<model> (body: the conversation),
# /api/file/<name> (body: the file).
def route_file_post.at(allowed: Bool, name: String, body: String) -> IO(String):
  match allowed:
    case True{}:
      do IO<String>:
        write_file(Ask.here(name), body)
        return ok_text("saved")
    case False{}:
      IO.pure(String, not_found())

def route_file_post(+name: String, body: String) -> IO(String):
  route_file_post.at(is_project_file(name), name, body)

def route_post.files(is_file: Bool, +path: String, body: String) -> IO(String):
  match is_file:
    case True{}:
      route_file_post(after(path, "/api/file/"), body)
    case False{}:
      IO.pure(String, not_found())

def route_post.generate(is_gen: Bool, +path: String, body: String, agent_md: String) -> IO(String):
  match is_gen:
    case True{}:
      generate(after(path, "/api/generate/"), agent_md, body)
    case False{}:
      route_post.files(String.starts_with(path, "/api/file/"), path, body)

def route_post.chat(is_chat: Bool, +path: String, body: String, agent_md: String) -> IO(String):
  match is_chat:
    case True{}:
      chat(after(path, "/api/chat/"), agent_md, body)
    case False{}:
      route_post.generate(String.starts_with(path, "/api/generate/"), path, body, agent_md)


def route_post.ask(is_ask: Bool, +path: String, body: String, agent_md: String) -> IO(String):
  match is_ask:
    case True{}:
      ask(after(path, "/api/ask/"), agent_md, body)
    case False{}:
      route_post.chat(String.starts_with(path, "/api/chat/"), path, body, agent_md)

def route_post.mcp(is_mcp: Bool, +path: String, +body: String, agent_md: String) -> IO(String):
  match is_mcp:
    case True{}:
      mcp(after(path, "/mcp/"), body)
    case False{}:
      route_post.ask(String.starts_with(path, "/api/ask/"), path, body, agent_md)

def route_post.answer(is_a: Bool, +path: String, +body: String, agent_md: String) -> IO(String):
  match is_a:
    case True{}:
      person_answer(after(path, "/api/answer/"), body)
    case False{}:
      route_post.mcp(String.starts_with(path, "/mcp/"), path, body, agent_md)

def route_post.allowed(is_a: Bool, +path: String, +body: String, agent_md: String) -> IO(String):
  match is_a:
    case True{}:
      allowed_post(after(path, "/api/allowed/"), body)
    case False{}:
      route_post.answer(String.starts_with(path, "/api/answer/"), path, body, agent_md)

def route_post.stop(is_stop: Bool, +path: String, +body: String, agent_md: String) -> IO(String):
  match is_stop:
    case True{}:
      stop(after(path, "/api/stop/"))
    case False{}:
      route_post.allowed(String.starts_with(path, "/api/allowed/"), path, body, agent_md)

def route_post.around(+path: String, +body: String, agent_md: String, folder: Bool, save: Bool) -> IO(String):
  match folder save:
    case True{} _:
      open_folder()
    case False{} True{}:
      conversation_save(after(path, "/api/conversation/"), body)
    case False{} False{}:
      route_post.stop(String.starts_with(path, "/api/stop/"), path, body, agent_md)

def route_post.games(+path: String, +body: String, agent_md: String, draft: Bool, promote: Bool, rename: Bool) -> IO(String):
  match draft promote rename:
    case True{} _ _:
      project_draft(after(path, "/api/draft/"))
    case False{} True{} _:
      project_promote(body)
    case False{} False{} True{}:
      project_rename(after(path, "/api/rename/"), body)
    case False{} False{} False{}:
      route_post.around(path, body, agent_md, String.eq(path, "/api/open-folder"), String.starts_with(path, "/api/conversation/"))

def route_post.projects(+path: String, +body: String, agent_md: String, make: Bool, pick: Bool) -> IO(String):
  match make pick:
    case True{} _:
      project_new(body)
    case False{} True{}:
      project_pick(after(path, "/api/project/"))
    case False{} False{}:
      route_post.games(path, body, agent_md, String.starts_with(path, "/api/draft/"), String.eq(path, "/api/promote"), String.starts_with(path, "/api/rename/"))

def route_post(+path: String, +body: String, agent_md: String) -> IO(String):
  route_post.projects(path, body, agent_md, String.eq(path, "/api/projects"), String.starts_with(path, "/api/project/"))

def route.at(is_post: Bool, +req: String, dist: String, agent_md: String) -> IO(String):
  match is_post:
    case True{}:
      route_post(req_word(req, 1n), req_body(req), agent_md)
    case False{}:
      route_get(req_word(req, 1n), dist, agent_md)

def route(+req: String, dist: String, agent_md: String) -> IO(String):
  route.at(String.eq(req_word(req, 0n), "POST"), req, dist, agent_md)

# ---------- Connections ----------

def send_done(m: Socket & Result<&1, &1, (U32 & String) & List<&2, U32>, Unit>) -> IO(Unit):
  (s, r) = m
  Socket.close(s)

def answer.text(s: Socket, req: String, dist: String, agent_md: String) -> IO(Unit):
  do IO<Unit>:
    res  : String <- route(req, dist, agent_md)
    sent : Socket & Result<&1, &1, (U32 & String) & List<&2, U32>, Unit> <- TCP.send(s, res)
    send_done(sent)

# Images go out as bytes: read as text, they would be decoded as UTF-8 and break.
def bytes_of(r: Result<&1, &1, U32 & String, List<&2, U32>>) -> List<&2, U32>:
  match r:
    case Fail{e}:
      []
    case Done{data}:
      data

def send_bytes.body(m: Socket & Result<&1, &1, (U32 & String) & List<&2, U32>, Unit>, data: List<&2, U32>) -> IO(Unit):
  (s, r) = m
  do IO<Unit>:
    sent : Socket & Result<&1, &1, (U32 & String) & List<&2, U32>, Unit> <- TCP.send_bytes(s, data)
    send_done(sent)

def send_bytes.read(s: Socket, got: File & Result<&1, &1, U32 & String, List<&2, U32>>, ctype: String) -> IO(Unit):
  (f, r) = got
  do IO<Unit>:
    File.close(f)
    head : Socket & Result<&1, &1, (U32 & String) & List<&2, U32>, Unit> <- TCP.send(s, http("200 OK", ctype, ""))
    send_bytes.body(head, bytes_of(r))

def send_bytes.open(s: Socket, r: Result<&1, &1, U32 & String, File>, ctype: String) -> IO(Unit):
  match r:
    case Fail{e}:
      do IO<Unit>:
        sent : Socket & Result<&1, &1, (U32 & String) & List<&2, U32>, Unit> <- TCP.send(s, not_found())
        send_done(sent)
    case Done{f}:
      do IO<Unit>:
        got : File & Result<&1, &1, U32 & String, List<&2, U32>> <- File.read_bytes(f, 4194304)
        send_bytes.read(s, got, ctype)

def answer.bytes(s: Socket, +path: String, dist: String) -> IO(Unit):
  do IO<Unit>:
    r : Result<&1, &1, U32 & String, File> <- File.open(dist ++ path, "r")
    send_bytes.open(s, r, content_type(path))

def is_image(+path: String) -> Bool:
  ((String.ends_with(path, ".webp") || String.ends_with(path, ".png")) && Bool.not(String.contains(path, "..")))

def answer.at(image: Bool, s: Socket, +req: String, dist: String, agent_md: String) -> IO(Unit):
  match image:
    case True{}:
      answer.bytes(s, req_word(req, 1n), dist)
    case False{}:
      answer.text(s, req, dist, agent_md)

def answer(s: Socket, +req: String, dist: String, agent_md: String) -> IO(Unit):
  answer.at(is_image(req_word(req, 1n)), s, req, dist, agent_md)

# A POST whose body hasn't arrived with the headers gets one more read.
def more(m: Socket & Result<&1, &1, U32 & String, Maybe<&1, String>>, head: String, dist: String, agent_md: String) -> IO(Unit):
  (s, r) = m
  match r:
    case Done{Some{rest}}:
      answer(s, head ++ rest, dist, agent_md)
    case Done{None{}}:
      answer(s, head, dist, agent_md)
    case Fail{e}:
      Socket.close(s)

def first.at(waiting: Bool, s: Socket, req: String, dist: String, agent_md: String) -> IO(Unit):
  match waiting:
    case True{}:
      do IO<Unit>:
        m : Socket & Result<&1, &1, U32 & String, Maybe<&1, String>> <- TCP.recv(s, 1048576)
        more(m, req, dist, agent_md)
    case False{}:
      answer(s, req, dist, agent_md)

# A POST that says its body is empty (Content-Length: 0, as an empty fetch sends) has nothing more to wait for.
def first(s: Socket, +req: String, dist: String, agent_md: String) -> IO(Unit):
  first.at((String.eq(req_word(req, 0n), "POST") && String.is_empty(req_body(req)) && Bool.not(String.contains(String.to_lower(req), "content-length: 0\r"))), s, req, dist, agent_md)

def talk_read(m: Socket & Result<&1, &1, U32 & String, Maybe<&1, String>>, dist: String, agent_md: String) -> IO(Unit):
  (s, r) = m
  match r:
    case Done{Some{req}}:
      first(s, req, dist, agent_md)
    case Done{None{}}:
      Socket.close(s)
    case Fail{e}:
      Socket.close(s)

def talk(s: Socket, dist: String, agent_md: String) -> IO(Unit):
  do IO<Unit>:
    m : Socket & Result<&1, &1, U32 & String, Maybe<&1, String>> <- TCP.recv(s, 1048576)
    talk_read(m, dist, agent_md)

def conn(m: Listener & Result<&1, &1, U32 & String, Socket>, +dist: String, +agent_md: String) -> IO(Listener):
  (l, r) = m
  do IO<Listener>:
    s : Socket <- IO.pass(Socket, r)
    IO.spawn(Unit, talk(s, dist, agent_md))
    return l

def serve(fuel: Nat, l: Listener, +dist: String, +agent_md: String) -> IO(Unit):
  match fuel:
    case 0n:
      Listener.close(l)
    case 1n+fuel2:
      do IO<Unit>:
        m  : Listener & Result<&1, &1, U32 & String, Socket> <- TCP.accept(l)
        l2 : Listener <- conn(m, dist, agent_md)
        serve(fuel2, l2, dist, agent_md)

# ---------- Start ----------

# The arguments: the program, then the page folder (dist), then AGENT.md.
def start.agent(dist: String, rest: List<String>, l: Listener) -> IO(Unit):
  match rest:
    case Nil{}:
      serve(4294967295n, l, dist, "AGENT.md")
    case a <> more:
      serve(4294967295n, l, dist, a)

def start.dist(rest: List<String>, l: Listener) -> IO(Unit):
  match rest:
    case Nil{}:
      serve(4294967295n, l, "dist", "AGENT.md")
    case d <> more:
      start.agent(d, more, l)

def start(args: List<String>, l: Listener) -> IO(Unit):
  match args:
    case Nil{}:
      serve(4294967295n, l, "dist", "AGENT.md")
    case p <> rest:
      start.dist(rest, l)

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    first : U32 & String <- run("sh", ["-c", "[ -d .current ] || { p=$(ls -1d */ 2>/dev/null | head -n 1); [ -n \"$p\" ] && ln -sfn \"${p%/}\" .current; }; true"], 5000)
    l : Listener <- IO.try(Listener, TCP.listen("127.0.0.1", port()))
    IO.print("LawEditor: http://" ++ address())
    start(args, l)
