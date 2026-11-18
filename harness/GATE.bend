# LawEditor: the interphone. Before an action that isn't on its list, Claude asks LawEditor and waits
# (--permission-prompt-tool, over MCP). Pure: this reads what Claude sends and writes what goes back;
# server.bend answers POST /mcp/<conversation>/<turn> with it. NEXT.md (0.1.8) and PERMIT.ask_bend() say why.
#
# MCP over HTTP: each POST holds one JSON-RPC message, {"method":"…","params":{…},"jsonrpc":"2.0","id":…}.
# A message with no id is a notice and gets no answer. The tool's answer is one text block holding
# {"behavior":"allow"} or {"behavior":"deny","message":"…"}.

import Base
import ./ASK.bend as Ask
import ./POLICY.bend as P
import ../flows/FLOW.bend as F

# ---------- Reading a message ----------

# The text after "key": in the message's own object (depth 1), not inside params.
# A quote inside a JSON string is always escaped, so a string never looks like a key.
def top.depth.at(opens: Bool, closes: Bool, d: Nat) -> Nat:
  match opens closes:
    case True{} _:
      (1n + d : Nat)
    case False{} True{}:
      Nat.sub(d, 1n)
    case False{} False{}:
      d

def top.depth(+h: Char, d: Nat) -> Nat:
  top.depth.at((Char.is_eq(h, '{') || Char.is_eq(h, '[')), (Char.is_eq(h, '}') || Char.is_eq(h, ']')), d)

def top.here(+d: Nat, +s: String, +marker: String) -> Bool:
  (Nat.is_eq(d, 1n) && String.starts_with(s, marker))

# instr: inside a string; esc: the last char was a backslash; here: a key at depth 1 starts now.
def top.at(s: String, +marker: String, +d: Nat, instr: Bool, esc: Bool, here: Bool) -> String:
  match s instr esc here:
    case SNil{} _ _ _:
      ""
    case SCon{h, t} False{} _ True{}:
      String.drop(SCon{h, t}, String.length(marker))
    case SCon{h, +t} True{} True{} _:
      top.at(t, marker, d, True{}, False{}, top.here(d, t, marker))
    case SCon{+h, +t} True{} False{} _:
      top.at(t, marker, d, Bool.not(Char.is_eq(h, '"')), Char.is_eq(h, Char.from_u32(92)), top.here(d, t, marker))
    case SCon{+h, +t} False{} _ False{}:
      top.at(t, marker, top.depth(h, d), Char.is_eq(h, '"'), False{}, top.here(top.depth(h, d), t, marker))

def top(+s: String, key: String) -> String:
  String.trim_start(top.at(s, "\"" ++ key ++ "\":", 0n, False{}, False{}, False{}))

# A number value: its text up to the next , or }.
def upto.keep(+h: Char, rest: String, stop: Bool) -> String:
  match stop:
    case True{}:
      ""
    case False{}:
      SCon{h, rest}

def upto(s: String) -> String:
  match s:
    case SNil{}:
      ""
    case SCon{+h, t}:
      upto.keep(h, upto(t), (Char.is_eq(h, ',') || Char.is_eq(h, '}')))

# The message's id, as it must be sent back: a number as it is, a string in quotes. "" for a notice.
def id.at(+v: String, quoted: Bool) -> String:
  match quoted:
    case True{}:
      "\"" ++ Ask.jstr(String.drop(v, 1n)) ++ "\""
    case False{}:
      String.trim(upto(v))

def id(+msg: String) -> String:
  id.at(top(msg, "id"), String.starts_with(top(msg, "id"), "\""))

def method(+msg: String) -> String:
  Ask.jstr(String.drop(top(msg, "method"), 1n))

def is_notice(+msg: String) -> Bool:
  String.is_empty(id(msg))

def is_call(+msg: String) -> Bool:
  String.eq(method(msg), "tools/call")

# What Claude wants to do, from the call's arguments: the tool, and the file or command.
def tool(+msg: String) -> String:
  Ask.field(msg, "tool_name")

def what(+msg: String) -> String:
  Ask.target(tool(msg), msg)

# ---------- Answers ----------

def rpc(+id: String, result: String) -> String:
  "{\"jsonrpc\":\"2.0\",\"id\":" ++ id ++ ",\"result\":" ++ result ++ "}"

def hello(+msg: String) -> String:
  "{\"protocolVersion\":\"" ++ Ask.field(msg, "protocolVersion") ++ "\",\"capabilities\":{\"tools\":{}},\"serverInfo\":{\"name\":\"laweditor\",\"version\":\"0.1.8\"}}"

# The one tool: Claude names it in --permission-prompt-tool as mcp__laweditor__approve.
def tools() -> String:
  "{\"tools\":[{\"name\":\"approve\",\"description\":\"LawEditor decides whether the chat may take this action.\",\"inputSchema\":{\"type\":\"object\",\"properties\":{\"tool_name\":{\"type\":\"string\"},\"input\":{\"type\":\"object\"},\"tool_use_id\":{\"type\":\"string\"}},\"required\":[\"tool_name\",\"input\"]}}]}"

# The tool's answer. A message must hold no quote or backslash: it sits inside a JSON string twice.
def decided(allowed: Bool, message: String) -> String:
  match allowed:
    case True{}:
      "{\"content\":[{\"type\":\"text\",\"text\":\"{\\\"behavior\\\":\\\"allow\\\"}\"}]}"
    case False{}:
      "{\"content\":[{\"type\":\"text\",\"text\":\"{\\\"behavior\\\":\\\"deny\\\",\\\"message\\\":\\\"" ++ message ++ "\\\"}\"}]}"

# Every message but a call is answered at once: hello, the tool list, or an empty result.
def reply.at(+msg: String, init: Bool, list: Bool) -> String:
  match init list:
    case True{} _:
      rpc(id(msg), hello(msg))
    case False{} True{}:
      rpc(id(msg), tools())
    case False{} False{}:
      rpc(id(msg), "{}")

def reply(+msg: String) -> String:
  reply.at(msg, String.eq(method(msg), "initialize"), String.eq(method(msg), "tools/list"))

# What the page writes back: the person's answer, one word.
def allow_word() -> String: "allow"
def session_word() -> String: "session"
def deny_word() -> String: "deny"

def lets_run(+said: String) -> Bool:
  (String.eq(String.trim(said), allow_word()) || String.eq(String.trim(said), session_word()))

def keeps(+said: String) -> Bool:
  String.eq(String.trim(said), session_word())

# A call's answer, once the person answered: allow or session lets it run, anything else doesn't.
def answer(+msg: String, +said: String) -> String:
  rpc(id(msg), decided(lets_run(said), "The person did not allow it. Don't do it; go on without it."))

# ---------- The question, while Claude waits ----------

# One question at a time per turn: the page reads it, and writes the answer next to it.
def question_file(+turn: String) -> String:
  "/tmp/laweditor-ask-" ++ Ask.safe_id(turn) ++ ".question"

def answer_file(+turn: String) -> String:
  "/tmp/laweditor-ask-" ++ Ask.safe_id(turn) ++ ".answer"

# What the page shows: the question on the first line; on the second, how to draw what would change (its
# language and name, split by a tab); then what would change (a command may hold new lines).
def question(+msg: String) -> String:
  Ask.question(tool(msg), what(msg)) ++ "\n" ++ Ask.preview_lang(tool(msg), msg) ++ Ask.tab() ++ Ask.preview_name(tool(msg), msg) ++ "\n" ++ Ask.preview(tool(msg), msg)

# ---------- The gate decides ----------
# Any agent that wants to act knocks here with the whole action: its tool, and the file or command.
# The rules below are checked in order and the first that fits decides. decide() runs this list and
# flow() draws it, so the diagram is the behavior itself, not a copy of it. To change what the gate
# does, change rules() or a rule's case below: the diagram follows.


type Rule is Data:
  Rule.LawForbids{}
  Rule.ModeForbids{}
  Rule.AllowedForSession{}
  Rule.AskYou{}

type Verdict is Data:
  Verdict.Yes{}
  Verdict.No{}
  Verdict.Ask{}

def rules() -> List<&2, Rule>:
  [Rule.LawForbids{}, Rule.ModeForbids{}, Rule.AllowedForSession{}, Rule.AskYou{}]

# The file no chat may change, by any tool (POLICY.never says the same to Claude's own list).
def guarded() -> String: "LAWS.bend"

# The action as one line of text: the tool, a new line, then the file or command.
# "Allow for this session" keeps exactly this text; another file or another command is another action.
def action(+tool: String, +what: String) -> String:
  tool ++ "\n" ++ what

# A law forbids it: an edit of LAWS.bend, or a command that names it (Bend can't tell a command
# that only reads from one that changes, so any command naming it is refused).
def law_forbids.at(+what: String, file: Bool, bash: Bool) -> Bool:
  match file bash:
    case True{} _:
      String.eq(Ask.base_name(what), guarded())
    case False{} True{}:
      String.contains(what, guarded())
    case False{} False{}:
      False{}

def law_forbids(+tool: String, +what: String) -> Bool:
  law_forbids.at(what, Ask.is_file_tool(tool), String.eq(tool, "Bash"))

# The mode doesn't allow it: Only read lets the chat read, and nothing else, without asking.
def only_reads(m: P.Mode) -> Bool:
  match m:
    case P.Mode.OnlyRead{}:
      True{}
    case P.Mode.AskBeforeChanges{}:
      False{}
    case P.Mode.ChangeFreely{}:
      False{}

def mode_forbids(+tool: String, m: P.Mode) -> Bool:
  (only_reads(m) && Bool.not(String.eq(tool, "Read")))

def allowed_for_session(session: List<&2, String>, +tool: String, +what: String) -> Bool:
  List.contains(~String, ~String.eq, session, action(tool, what))

def fits(r: Rule, +tool: String, +what: String, +m: P.Mode, +session: List<&2, String>) -> Bool:
  match r:
    case Rule.LawForbids{}:
      law_forbids(tool, what)
    case Rule.ModeForbids{}:
      mode_forbids(tool, m)
    case Rule.AllowedForSession{}:
      allowed_for_session(session, tool, what)
    case Rule.AskYou{}:
      True{}

def verdict(r: Rule) -> Verdict:
  match r:
    case Rule.LawForbids{}:
      Verdict.No{}
    case Rule.ModeForbids{}:
      Verdict.No{}
    case Rule.AllowedForSession{}:
      Verdict.Yes{}
    case Rule.AskYou{}:
      Verdict.Ask{}

def pick(hit: Bool, mine: Rule, later: Rule) -> Rule:
  match hit:
    case True{}:
      mine
    case False{}:
      later

# The first rule that fits. With none left, ask: the gate never says yes on its own.
def first(rs: List<&2, Rule>, +tool: String, +what: String, +m: P.Mode, +session: List<&2, String>) -> Rule:
  match rs:
    case Nil{}:
      Rule.AskYou{}
    case +h <> t:
      pick(fits(h, tool, what, m, session), h, first(t, tool, what, m, session))

def decide(rs: List<&2, Rule>, +tool: String, +what: String, +m: P.Mode, +session: List<&2, String>) -> Verdict:
  verdict(first(rs, tool, what, m, session))

# What the agent is told when a rule refuses, so it doesn't try another way.
def refused(r: Rule) -> String:
  match r:
    case Rule.LawForbids{}:
      "A law of this project forbids it: the chat never changes " ++ guarded() ++ ", by any tool or command. Don't try another way; tell the person."
    case Rule.ModeForbids{}:
      "The mode is Only read: nothing but reading. Don't try another way; if it is needed, tell the person to pick Ask before changes."
    case Rule.AllowedForSession{}:
      ""
    case Rule.AskYou{}:
      ""

# ---------- The session: what the person allowed for this conversation ----------
# One file per conversation (the page names it), each action ending with the record separator (char 30),
# since a command may hold new lines. A new conversation starts with none.

def sep() -> Char: Char.from_u32(30)

# Kept with the project: what was allowed in a conversation stays when the app restarts.
def session_file(+conv: String) -> String:
  Ask.here(".laweditor/allowed/" ++ Ask.safe_id(conv) ++ ".allowed")

def session_list(+text: String) -> List<&2, String>:
  String.split(text, sep())

def session_add(+text: String, +tool: String, +what: String) -> String:
  text ++ action(tool, what) ++ SCon{sep(), ""}

# ---------- What you allowed, on the page ----------
# The mode's menu (web/chat/mode.js) shows the actions kept for this conversation, newest first, finds in
# them, and takes one back (the server writes the file without it) or all (an empty file). A taken-back
# action asks again next time.

def allowed.keep(+s: String, rest: List<&2, String>) -> List<&2, String>:
  match s:
    case SNil{}:
      rest
    case SCon{h, t}:
      s <> rest

def allowed.nonempty(xs: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}:
      Nil{}
    case +h <> t:
      allowed.keep(h, allowed.nonempty(t))

# Newest first: the file keeps them in the order they were allowed.
def allowed_list(+text: String) -> List<&2, String>:
  List.reverse(&2, String, allowed.nonempty(session_list(text)))

def allowed.size(xs: List<&2, String>) -> U32:
  match xs:
    case Nil{}:
      0
    case h <> t:
      (1 + allowed.size(t) : U32)

def allowed_count(+text: String) -> U32:
  allowed.size(allowed_list(text))

def allowed.at.go(xs: List<&2, String>, here: Bool, +i: U32) -> String:
  match xs here:
    case Nil{} _:
      ""
    case (+h <> t) True{}:
      h
    case (h <> t) False{}:
      allowed.at.go(t, U32.is_eq(i, 1), (i - 1 : U32))

# The i-th action, newest first (0 is the newest), as kept: the tool, a new line, the file or command.
def allowed_at(+text: String, +i: U32) -> String:
  allowed.at.go(allowed_list(text), U32.is_eq(i, 0), i)

def allowed.tool.go(s: String, here: Bool, acc: String) -> String:
  match s here:
    case SNil{} _:
      String.reverse(acc)
    case SCon{h, t} True{}:
      String.reverse(acc)
    case SCon{+h, +t} False{}:
      allowed.tool.go(t, String.starts_with(t, "\n"), SCon{h, acc})

def allowed.what.go(s: String, here: Bool) -> String:
  match s here:
    case SNil{} _:
      ""
    case SCon{h, t} True{}:
      t
    case SCon{h, +t} False{}:
      allowed.what.go(t, String.starts_with(t, "\n"))

def allowed_tool(+entry: String) -> String:
  allowed.tool.go(entry, String.starts_with(entry, "\n"), "")

def allowed_what(+entry: String) -> String:
  allowed.what.go(entry, String.starts_with(entry, "\n"))

# The word that leads a row: a command runs; a file tool keeps its name.
def allowed.kind.at(bash: Bool, +tool: String) -> String:
  match bash:
    case True{}:
      "Run"
    case False{}:
      tool

def allowed_kind(+entry: String) -> String:
  allowed.kind.at(String.eq(allowed_tool(entry), "Bash"), allowed_tool(entry))

# Its tone (Bend-UI's menu__lead--<tone>): edits in accent, new files in warning, commands plain.
def allowed.tone.at(edit: Bool, write: Bool) -> String:
  match edit write:
    case True{} _:
      "accent"
    case False{} True{}:
      "warning"
    case False{} False{}:
      ""

def allowed_tone(+entry: String) -> String:
  allowed.tone.at(String.eq(allowed_tool(entry), "Edit"), String.eq(allowed_tool(entry), "Write"))

# The whole action in words, for the row's title (a long command ends in "…" on the row).
def allowed_title(+entry: String) -> String:
  allowed_kind(entry) ++ ": " ++ allowed_what(entry)

def allowed.lower(s: String) -> String:
  match s:
    case SNil{}:
      ""
    case SCon{h, t}:
      SCon{Char.to_lower(h), allowed.lower(t)}

# Find…: the row shows when its words hold what the person typed, in any case. Nothing typed shows all.
def allowed_matches(+entry: String, +query: String) -> Bool:
  String.contains(allowed.lower(allowed_title(entry)), allowed.lower(String.trim(query)))

def allowed_tag(+n: U32) -> String:
  U32.show(n) ++ " allowed"

def allowed.count.at(all: Bool, +shown: U32, +total: U32) -> String:
  match all:
    case True{}:
      U32.show(total)
    case False{}:
      U32.show(shown) ++ " of " ++ U32.show(total)

# The count by the menu's title: all of them, or "3 of 49" while finding.
def allowed_count_text(+shown: U32, +total: U32, +query: String) -> String:
  allowed.count.at(String.eq(String.trim(query), ""), shown, total)

def allowed.drop.at(skip: Bool, +h: String, rest: String) -> String:
  match skip:
    case True{}:
      rest
    case False{}:
      h ++ SCon{sep(), ""} ++ rest

def allowed.drop(xs: List<&2, String>, +entry: String) -> String:
  match xs:
    case Nil{}:
      ""
    case +h <> t:
      allowed.drop.at((String.eq(h, entry) || String.eq(h, "")), h, allowed.drop(t, entry))

# Taking back this word takes back all of them (an action always holds a new line, so it is never this).
# The server doesn't wait for an empty body, so "all" is a word.
def allowed_all_word() -> String: "all"

# The file without one action (taken back), or empty after taking back all.
def allowed.without.at(all: Bool, +text: String, +entry: String) -> String:
  match all:
    case True{}:
      ""
    case False{}:
      allowed.drop(session_list(text), entry)

def allowed_without(+text: String, +entry: String) -> String:
  allowed.without.at(String.eq(entry, allowed_all_word()), text, entry)

# ---------- The gate, at a call ----------
# The rule that decides this call, from the message and the session file's text.
def rule_for(+msg: String, +m: P.Mode, +session_text: String) -> Rule:
  first(rules(), tool(msg), what(msg), m, session_list(session_text))

# The answer when a rule decides alone (Yes or No); Ask goes to the person instead.
def now(+msg: String, r: Rule) -> String:
  match r:
    case Rule.LawForbids{}:
      rpc(id(msg), decided(False{}, refused(Rule.LawForbids{})))
    case Rule.ModeForbids{}:
      rpc(id(msg), decided(False{}, refused(Rule.ModeForbids{})))
    case Rule.AllowedForSession{}:
      rpc(id(msg), decided(True{}, ""))
    case Rule.AskYou{}:
      rpc(id(msg), decided(False{}, "Nobody answered."))

# The session file after the person answered: the action added only for Allow for this session.
def session_after.at(kept: Bool, +text: String, +msg: String) -> String:
  match kept:
    case True{}:
      session_add(text, tool(msg), what(msg))
    case False{}:
      text

def session_after(+text: String, +msg: String, +said: String) -> String:
  session_after.at(keeps(said), text, msg)

# ---------- The gate, drawn from its rules ----------

def rule_name(r: Rule) -> String:
  match r:
    case Rule.LawForbids{}:
      "Does a law forbid it? (the chat changing " ++ guarded() ++ ")"
    case Rule.ModeForbids{}:
      "Does the mode forbid it? (Only read: anything but reading)"
    case Rule.AllowedForSession{}:
      "Allowed for this session already? (the same action, exactly)"
    case Rule.AskYou{}:
      "Otherwise: ask you, and wait"

# Where each verdict goes, after the rules: n is how many rules there are.
def runs_at(+n: Nat) -> Nat: (1n + n : Nat)
def refused_at(+n: Nat) -> Nat: (2n + n : Nat)
def you_at(+n: Nat) -> Nat: (3n + n : Nat)
def keeps_at(+n: Nat) -> Nat: (4n + n : Nat)

def verdict_at(v: Verdict, +n: Nat) -> Nat:
  match v:
    case Verdict.Yes{}:
      runs_at(n)
    case Verdict.No{}:
      refused_at(n)
    case Verdict.Ask{}:
      you_at(n)

def rule_arrows(r: Rule, +n: Nat, +next: Nat) -> List<&2, F.Go>:
  match r:
    case Rule.AskYou{}:
      [F.Go{verdict_at(verdict(r), n), ""}]
    case Rule.LawForbids{}:
      [F.Go{verdict_at(verdict(r), n), "yes"}, F.Go{next, "no"}]
    case Rule.ModeForbids{}:
      [F.Go{verdict_at(verdict(r), n), "yes"}, F.Go{next, "no"}]
    case Rule.AllowedForSession{}:
      [F.Go{verdict_at(verdict(r), n), "yes"}, F.Go{next, "no"}]

# Rule i is step 1 + i (step 0 is the knock).
def rule_steps(rs: List<&2, Rule>, +n: Nat, +i: Nat) -> List<&2, F.Step>:
  match rs:
    case Nil{}:
      Nil{}
    case +h <> t:
      F.Step{rule_name(h), F.System{}, False{}, rule_arrows(h, n, (2n + i : Nat))} <> rule_steps(t, n, (1n + i : Nat))

def size(rs: List<&2, Rule>) -> Nat:
  match rs:
    case Nil{}:
      0n
    case h <> t:
      (1n + size(t) : Nat)

def flow.of(+n: Nat) -> List<&2, F.Step>:
  List.append(&2, F.Step,
    [F.Step{"An agent wants to act and sends the whole action (Claude: MCP tool; Codex: app-server; a local model: the harness)", F.Cli{}, False{}, [F.Go{1n, ""}]}],
    List.append(&2, F.Step, rule_steps(rules(), n, 0n),
      [F.Step{"It runs", F.Cli{}, False{}, []},
       F.Step{"Refused; the chat goes on without it", F.Cli{}, False{}, []},
       F.Step{"Allow / Allow for this session / Don't allow", F.Person{}, False{}, [F.Go{runs_at(n), "Allow"}, F.Go{keeps_at(n), "Allow for this session"}, F.Go{refused_at(n), "Don't allow"}]},
       F.Step{"Bend keeps the exact action until the conversation ends or you take it back (the mode's menu: Allowed in this chat)", F.System{}, False{}, [F.Go{runs_at(n), ""}]}]))

def flow() -> List<&2, F.Step>:
  flow.of(size(rules()))

# ---------- The gate, tried ----------
# Actions run through decide(): the diagram groups each one under what the gate answered.
# Nothing here says the answer; decide() does, so a change in rules() moves them.

type Example is Data:
  Example{name: String, tool: String, what: String, mode: P.Mode, session: List<&2, String>}

def examples() -> List<&2, Example>:
  [
    Example{"Edit LAWS.bend", "Edit", "/project/LAWS.bend", P.Mode.AskBeforeChanges{}, []},
    Example{"sed -i … LAWS.bend", "Bash", "sed -i 's/a/b/' LAWS.bend", P.Mode.AskBeforeChanges{}, []},
    Example{"head index.html, in Only read", "Bash", "head index.html", P.Mode.OnlyRead{}, []},
    Example{"cd project; head index.html; git log, first time", "Bash", "cd project; head index.html; git log", P.Mode.AskBeforeChanges{}, []},
    Example{"The same command, after Allow for this session", "Bash", "cd project; head index.html; git log", P.Mode.AskBeforeChanges{}, ["Bash\ncd project; head index.html; git log"]},
    Example{"rm b.txt, when only rm a.txt was allowed", "Bash", "rm b.txt", P.Mode.AskBeforeChanges{}, ["Bash\nrm a.txt"]}
  ]

def tried_verdict(e: Example) -> Verdict:
  match e:
    case Example{n, +t, +w, +m, +s}:
      decide(rules(), t, w, m, s)

def same(a: Verdict, b: Verdict) -> Bool:
  match a b:
    case Verdict.Yes{} Verdict.Yes{}:
      True{}
    case Verdict.No{} Verdict.No{}:
      True{}
    case Verdict.Ask{} Verdict.Ask{}:
      True{}
    case _ _:
      False{}

def example_name(e: Example) -> String:
  match e:
    case Example{n, t, w, m, s}:
      n

def under.at(hit: Bool, +i: Nat, rest: List<&2, F.Go>) -> List<&2, F.Go>:
  match hit:
    case True{}:
      F.Go{i, ""} <> rest
    case False{}:
      rest

# Arrows from a verdict to each example the gate answered with it (example k is step 4 + k).
def under(es: List<&2, Example>, +v: Verdict, +i: Nat) -> List<&2, F.Go>:
  match es:
    case Nil{}:
      Nil{}
    case +h <> t:
      under.at(same(tried_verdict(h), v), i, under(t, v, (1n + i : Nat)))

def example_steps(es: List<&2, Example>) -> List<&2, F.Step>:
  match es:
    case Nil{}:
      Nil{}
    case h <> t:
      F.Step{example_name(h), F.Cli{}, False{}, []} <> example_steps(t)

def tried() -> List<&2, F.Step>:
  List.append(&2, F.Step,
    [F.Step{"The gate, tried on these actions", F.System{}, False{}, [F.Go{1n, ""}, F.Go{2n, ""}, F.Go{3n, ""}]},
     F.Step{"Refused, without asking", F.System{}, False{}, under(examples(), Verdict.No{}, 4n)},
     F.Step{"Asks you", F.Person{}, False{}, under(examples(), Verdict.Ask{}, 4n)},
     F.Step{"Allowed, without asking", F.System{}, False{}, under(examples(), Verdict.Yes{}, 4n)}],
    example_steps(examples()))

def is_ask(r: Rule) -> Bool:
  match r:
    case Rule.LawForbids{}:
      False{}
    case Rule.ModeForbids{}:
      False{}
    case Rule.AllowedForSession{}:
      False{}
    case Rule.AskYou{}:
      True{}

# ---------- The card, on the page ----------
# What the card says once the person answered.
def note.at(runs: Bool, kept: Bool) -> String:
  match runs kept:
    case True{} True{}:
      "Allowed for this session."
    case True{} False{}:
      "Allowed."
    case False{} _:
      "Not allowed."

def note(+said: String) -> String:
  note.at(lets_run(said), keeps(said))
