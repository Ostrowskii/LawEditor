# LawEditor: reading what Claude sends: an action's tool, file or command, and what the person reads about it
# (GATE.bend asks with these), and a turn's answer while it is written. Pure; server.bend runs Claude.

import Base
import ./MODELS.bend as Models

# ---------- Text ----------

# The text after the first place marker appears ("" if it never does).
def after.at(s: String, +marker: String, here: Bool) -> String:
  match s here:
    case SNil{} _:
      ""
    case SCon{h, t} True{}:
      String.drop(SCon{h, t}, String.length(marker))
    case SCon{h, +t} False{}:
      after.at(t, marker, String.starts_with(t, marker))

def after(+s: String, +marker: String) -> String:
  after.at(s, marker, String.starts_with(s, marker))

# A JSON string's text, from just after its opening quote to the closing one.
# \n and \t become a new line and a tab; any other \x becomes x (\" \\ \/).
# esc: the last char was a backslash; quote and back: s starts with " or \.
def jstr.code(+c: Char, n: Bool, tab: Bool) -> Char:
  match n tab:
    case True{} _:
      Char.from_u32(10)
    case False{} True{}:
      Char.from_u32(9)
    case False{} False{}:
      c

def jstr.go(s: String, acc: String, esc: Bool, quote: Bool, back: Bool) -> String:
  match s esc quote back:
    case SNil{} _ _ _:
      String.reverse(acc)
    case SCon{+h, +t} True{} _ _:
      jstr.go(t, SCon{jstr.code(h, Char.is_eq(h, 'n'), Char.is_eq(h, 't')), acc}, False{}, String.starts_with(t, "\""), String.starts_with(t, "\\"))
    case SCon{h, t} False{} True{} _:
      String.reverse(acc)
    case SCon{h, t} False{} False{} True{}:
      jstr.go(t, acc, True{}, False{}, False{})
    case SCon{+h, +t} False{} False{} False{}:
      jstr.go(t, SCon{h, acc}, False{}, String.starts_with(t, "\""), String.starts_with(t, "\\"))

def jstr(+s: String) -> String:
  jstr.go(s, "", False{}, String.starts_with(s, "\""), String.starts_with(s, "\\"))

# The string value of "key" at its first place in s ("" if it isn't there).
def field(+s: String, key: String) -> String:
  jstr(after(s, "\"" ++ key ++ "\":\""))

# The last piece of a path: "/a/b/GDD.md" is "GDD.md".
def base_name.of(m: Maybe<&2, String>, path: String) -> String:
  match m:
    case None{}:
      path
    case Some{name}:
      name

def base_name(+path: String) -> String:
  base_name.of(List.last(&2, String, String.split(path, '/')), path)

# ---------- An action ----------

def is_file_tool(+t: String) -> Bool:
  (String.eq(t, "Edit") || String.eq(t, "Write"))

# What it acts on: a file for Edit and Write, a command for Bash.
def target.of(+inp: String, file: Bool) -> String:
  match file:
    case True{}:
      field(inp, "file_path")
    case False{}:
      field(inp, "command")

def target(+t: String, +inp: String) -> String:
  target.of(inp, is_file_tool(t))

# What the person reads: the question, and what would change.
def question.of(+t: String, +what: String, edit: Bool, write: Bool, bash: Bool) -> String:
  match edit write bash:
    case True{} _ _:
      "Allow the chat to edit " ++ base_name(what) ++ "?"
    case False{} True{} _:
      "Allow the chat to write " ++ base_name(what) ++ "?"
    case False{} False{} True{}:
      "Allow the chat to run this command?"
    case False{} False{} False{}:
      "Allow the chat to use " ++ t ++ "?"

def question(+t: String, +what: String) -> String:
  question.of(t, what, String.eq(t, "Edit"), String.eq(t, "Write"), String.eq(t, "Bash"))

# An edit's lines as a diff: each old line after "-", each new one after "+".
def diff.mark(+mark: String, s: String, start: Bool) -> String:
  match s start:
    case SNil{} _:
      ""
    case SCon{+h, t} True{}:
      mark ++ SCon{h, diff.mark(mark, t, Char.is_eq(h, Char.from_u32(10)))}
    case SCon{+h, t} False{}:
      SCon{h, diff.mark(mark, t, Char.is_eq(h, Char.from_u32(10)))}

def diff(+old: String, +new: String) -> String:
  diff.mark("-", old, True{}) ++ "\n" ++ diff.mark("+", new, True{})

def preview.of(+inp: String, edit: Bool, write: Bool) -> String:
  match edit write:
    case True{} _:
      diff(field(inp, "old_string"), field(inp, "new_string"))
    case False{} True{}:
      field(inp, "content")
    case False{} False{}:
      field(inp, "command")

def preview(+t: String, +inp: String) -> String:
  preview.of(inp, String.eq(t, "Edit"), String.eq(t, "Write"))

# How the page draws it (Bend-UI's code block): its language, and the name over it.
# An edit is a diff; a new file is in its extension's language; a command is shell.
def extension.of(m: Maybe<&2, String>) -> String:
  match m:
    case None{}:
      ""
    case Some{e}:
      e

def extension(+path: String) -> String:
  extension.of(List.last(&2, String, String.split(base_name(path), '.')))

def preview_lang.of(+inp: String, edit: Bool, write: Bool) -> String:
  match edit write:
    case True{} _:
      "diff"
    case False{} True{}:
      extension(field(inp, "file_path"))
    case False{} False{}:
      "sh"

def preview_lang(+t: String, +inp: String) -> String:
  preview_lang.of(inp, String.eq(t, "Edit"), String.eq(t, "Write"))

def preview_name.of(+inp: String, file: Bool) -> String:
  match file:
    case True{}:
      base_name(field(inp, "file_path"))
    case False{}:
      "Command"

def preview_name(+t: String, +inp: String) -> String:
  preview_name.of(inp, is_file_tool(t))

# The answer, once nothing was refused. Only the last event, {"type":"result",…}, has a "result" key
# (inside a message's text, a quote is escaped, so "result":" can't appear there).
def result(+out: String) -> String:
  field(out, "result")

# ---------- The answer while it is written ----------
# Each turn writes Claude's output to its own file, named by an id the page picks. Only letters and
# digits are kept from that id, so it can't point anywhere else.
def safe_id.keep(+c: Char, ok: Bool, rest: String) -> String:
  match ok:
    case True{}:
      SCon{c, rest}
    case False{}:
      rest

def safe_id(s: String) -> String:
  match s:
    case SNil{}:
      ""
    case SCon{+h, t}:
      safe_id.keep(h, (Char.is_alpha(h) || Char.is_digit(h)), safe_id(t))

def turn_file(id: String) -> String:
  "/tmp/laweditor-turn-" ++ safe_id(id) ++ ".jsonl"

# With --include-partial-messages, Claude sends each piece of text as it writes it:
# {"type":"stream_event","event":{"type":"message_start",…}} opens a message, then
# {"delta":{"type":"text_delta","text":"Hello,"}} pieces follow. A reply can hold several messages
# (it writes, reads a file, writes again): the page shows the one being written now.

def text_pieces(xs: List<&2, String>) -> String:
  match xs:
    case Nil{}:
      ""
    case h <> t:
      jstr(String.drop(h, String.length("\"text_delta\",\"text\":\""))) ++ text_pieces(t)

def text_of(xs: List<&2, String>) -> String:
  match xs:
    case Nil{}:
      ""
    case h <> t:
      text_pieces(t)

def last_message.of(m: Maybe<&2, String>) -> String:
  match m:
    case None{}:
      ""
    case Some{s}:
      s

# The text of the message being written now ("" while the chat is reading a file).
def progress(+out: String) -> String:
  text_of(Models.pieces(last_message.of(List.last(&2, String, Models.pieces(out, "\"type\":\"message_start\""))), "\"text_delta\",\"text\":\""))

# The answer when it is done; if Claude gave none (it couldn't start), what it printed.
def result_or.at(+out: String, has: Bool) -> String:
  match has:
    case True{}:
      result(out)
    case False{}:
      out

def result_or(+out: String) -> String:
  result_or.at(out, String.contains(out, "\"result\":\""))


# ---------- The work, while it runs ----------
# What the chat did in a turn, read from the same file: each action (a tool it used) with a detail and its
# output, its plan (PLAN: lines in its text), the files it changed (Edit and Write, lines added and removed),
# what it does now, and how much of its context it used. The page draws it with Bend-UI's .tools, .plan,
# .changes, .working and .meter; one line each, fields split by tabs:
#   T  kind  tone  what  detail   an action, in order (its output: GET /api/output/<turn>/<n>)
#   P  status  text               a step of the plan: done, now or next
#   C  file  added  removed       a file changed, once per file
#   H  title                      the title over the files changed ("3 files changed")
#   W  verb  what                 what it does now (the last action)
#   X  percent                    how much of the context the turn used
# A whole message is one line: {"type":"assistant",…} up to its line's end. The stream's own events
# (content_block_start) carry the tool with an empty input, so only whole messages are read.

def tab() -> String:
  SCon{Char.from_u32(9), SNil{}}

def nl() -> String:
  SCon{Char.from_u32(10), SNil{}}

def rest_of(xs: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}:
      []
    case h <> t:
      t

def line_of(+s: String) -> String:
  Models.upto(s, Char.from_u32(10))

def work.pick(empty: Bool, +a: String, +b: String) -> String:
  match empty:
    case True{}:
      b
    case False{}:
      a

def nonempty_or(+a: String, +b: String) -> String:
  work.pick(String.eq(a, ""), a, b)

# The tools of one message: the pieces after each {"type":"tool_use" in its line.
def tools_in(+line: String) -> List<&2, String>:
  rest_of(Models.pieces(line, "{\"type\":\"tool_use\""))

def tools_of.each(xs: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}:
      []
    case +h <> t:
      List.append(&2, String, tools_in(line_of(h)), tools_of.each(t))

# Every tool the chat used in the turn, in order.
def tools_of(+out: String) -> List<&2, String>:
  tools_of.each(rest_of(Models.pieces(out, "{\"type\":\"assistant\"")))

def tool_name(+p: String) -> String:
  field(p, "name")

def tool_input(+p: String) -> String:
  after(p, "\"input\":")

# What each tool answered, in the same order: {"type":"tool_result","content":"…"} (or its content's "text").
def result_text(+line: String) -> String:
  nonempty_or(field(line, "content"), field(line, "text"))

def results_of.each(xs: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}:
      []
    case +h <> t:
      result_text(line_of(h)) <> results_of.each(t)

def results_of(+out: String) -> List<&2, String>:
  results_of.each(rest_of(Models.pieces(out, "\"type\":\"tool_result\"")))

# The output of the n-th action (counted from 0), at most output_lines lines.
def output_lines() -> U32: 40

def take_lines.next(newline: Bool, n: U32) -> U32:
  match newline:
    case True{}:
      (n - 1 : U32)
    case False{}:
      n

def take_lines.go(s: String, n: U32) -> String:
  match s n:
    case SNil{} _:
      ""
    case SCon{h, t} 0:
      "…"
    case SCon{+h, t} m:
      SCon{h, take_lines.go(t, take_lines.next(Char.is_eq(h, Char.from_u32(10)), m))}

def nth_or(xs: List<&2, String>, n: U32) -> String:
  match xs n:
    case Nil{} _:
      ""
    case h <> t 0:
      h
    case h <> t m:
      nth_or(t, (m - 1 : U32))

# An edit shows what it changed (a diff, "-" and "+" lines); any other action what it answered.
def output.of(+out: String, +tool: String, +n: U32, edit: Bool) -> String:
  match edit:
    case True{}:
      diff(field(tool_input(tool), "old_string"), field(tool_input(tool), "new_string"))
    case False{}:
      take_lines.go(nth_or(results_of(out), n), output_lines())

def output(+out: String, +n: U32) -> String:
  output.of(out, nth_or(tools_of(out), n), n, String.eq(tool_name(nth_or(tools_of(out), n)), "Edit"))

# The word of an action, as in the Allowed list: Run for a command, Find for a search.
def work.kind.at(+name: String, bash: Bool, find: Bool) -> String:
  match bash find:
    case True{} _:
      "Run"
    case False{} True{}:
      "Find"
    case False{} False{}:
      name

def work_kind(+name: String) -> String:
  work.kind.at(name, String.eq(name, "Bash"), (String.eq(name, "Glob") || String.eq(name, "Grep")))

# Its tone (Bend-UI's tool__kind--<tone>): edits in accent, new files in warning, the rest plain.
def work.tone.at(edit: Bool, write: Bool) -> String:
  match edit write:
    case True{} _:
      "accent"
    case False{} True{}:
      "warning"
    case False{} False{}:
      ""

def work_tone(+name: String) -> String:
  work.tone.at(String.eq(name, "Edit"), String.eq(name, "Write"))

# What it acted on: a command's description (or the command), a file's name, a search's pattern.
def work.what.at(+inp: String, bash: Bool, file: Bool) -> String:
  match bash file:
    case True{} _:
      nonempty_or(field(inp, "description"), field(inp, "command"))
    case False{} True{}:
      base_name(field(inp, "file_path"))
    case False{} False{}:
      field(inp, "pattern")

def work_what(+name: String, +inp: String) -> String:
  work.what.at(inp, String.eq(name, "Bash"), (is_file_tool(name) || String.eq(name, "Read")))

# What it does now, as a verb.
def work.verb.at(+kind: String, run: Bool, read: Bool, edit: Bool, write: Bool, find: Bool) -> String:
  match run read edit write find:
    case True{} _ _ _ _:
      "Running"
    case False{} True{} _ _ _:
      "Reading"
    case False{} False{} True{} _ _:
      "Editing"
    case False{} False{} False{} True{} _:
      "Writing"
    case False{} False{} False{} False{} True{}:
      "Searching"
    case False{} False{} False{} False{} False{}:
      "Using " ++ kind

def work_verb(+kind: String) -> String:
  work.verb.at(kind, String.eq(kind, "Run"), String.eq(kind, "Read"), String.eq(kind, "Edit"), String.eq(kind, "Write"), String.eq(kind, "Find"))

# Lines in a text: its new lines plus one (none for an empty text).
def lines.step(newline: Bool, n: U32) -> U32:
  match newline:
    case True{}:
      (n + 1 : U32)
    case False{}:
      n

def lines.go(s: String, n: U32) -> U32:
  match s:
    case SNil{}:
      n
    case SCon{+h, t}:
      lines.go(t, lines.step(Char.is_eq(h, Char.from_u32(10)), n))

# A text that ends in a new line has no line after it: "hello\nworld\n" is 2 lines.
def lines.trail(ends: Bool, n: U32) -> U32:
  match ends:
    case True{}:
      (n - 1 : U32)
    case False{}:
      n

def lines.count(empty: Bool, +s: String) -> U32:
  match empty:
    case True{}:
      0
    case False{}:
      lines.trail(String.ends_with(s, nl()), lines.go(s, 1))

def lines(+s: String) -> U32:
  lines.count(String.eq(s, ""), s)

# The detail at the end of an action's line: an edit's "+4 −1", a new file's "+62", otherwise how many
# lines it answered ("12 lines"); nothing while it hasn't answered.
def signed(+mark: String, +n: U32) -> String:
  work.pick(U32.is_eq(n, 0), mark ++ U32.show(n), "")

def spaced(+a: String, +b: String) -> String:
  work.pick((String.eq(a, "") || String.eq(b, "")), a ++ " " ++ b, a ++ b)

def lines.word(+n: U32) -> String:
  work.pick(U32.is_eq(n, 0), work.pick(U32.is_eq(n, 1), U32.show(n) ++ " lines", "1 line"), "")

def detail.at(+inp: String, +result: String, edit: Bool, write: Bool) -> String:
  match edit write:
    case True{} _:
      spaced(signed("+", lines(field(inp, "new_string"))), signed("−", lines(field(inp, "old_string"))))
    case False{} True{}:
      signed("+", lines(field(inp, "content")))
    case False{} False{}:
      lines.word(lines(result))

def detail(+name: String, +inp: String, +result: String) -> String:
  detail.at(inp, result, String.eq(name, "Edit"), String.eq(name, "Write"))

def action_line(+p: String, +result: String) -> String:
  "T" ++ tab() ++ work_kind(tool_name(p)) ++ tab() ++ work_tone(tool_name(p)) ++ tab() ++ work_what(tool_name(p), tool_input(p)) ++ tab() ++ detail(tool_name(p), tool_input(p), result) ++ nl()

# Each action with its answer: the i-th result goes with the i-th action (none yet while it runs).
def actions(xs: List<&2, String>, +rs: List<&2, String>, +i: U32) -> String:
  match xs:
    case Nil{}:
      ""
    case +h <> t:
      action_line(h, nth_or(rs, i)) ++ actions(t, rs, (i + 1 : U32))

# The plan: the chat writes its steps in its text, one per line, and writes them again as they change:
#   PLAN: [x] Make the map        done
#   PLAN: [>] Put the player on it  now
#   PLAN: [ ] Enemies             next
# A step's last line wins; the steps keep the order they first came in. CHAT.md teaches it.
def text_of_turn.each(xs: List<&2, String>) -> String:
  match xs:
    case Nil{}:
      ""
    case +h <> t:
      jstr(after(h, "{\"type\":\"text\",\"text\":\"")) ++ nl() ++ text_of_turn.each(t)

# Every text the chat wrote in the turn (its whole messages), in order.
def text_of_turn.lines(xs: List<&2, String>) -> String:
  match xs:
    case Nil{}:
      ""
    case +h <> t:
      text_of_turn.each(rest_of(Models.pieces(line_of(h), "{\"type\":\"text\",\"text\":\""))) ++ text_of_turn.lines(t)

def text_of_turn(+out: String) -> String:
  text_of_turn.lines(rest_of(Models.pieces(out, "{\"type\":\"assistant\"")))

type Step is Data:
  Step{text: String, status: String}

def step.text(+s: Step) -> String:
  match s:
    case Step{+t, st}:
      t

def step.status(+s: Step) -> String:
  match s:
    case Step{t, +st}:
      st

def step.pick(same: Bool, merged: List<&2, Step>, other: List<&2, Step>) -> List<&2, Step>:
  match same:
    case True{}:
      merged
    case False{}:
      other

def step.add(+s: Step, ss: List<&2, Step>) -> List<&2, Step>:
  match ss:
    case Nil{}:
      [s]
    case +h <> +t:
      step.pick(String.eq(step.text(h), step.text(s)), s <> t, h <> step.add(s, t))

def step.status_of(done: Bool, now: Bool) -> String:
  match done now:
    case True{} _:
      "done"
    case False{} True{}:
      "now"
    case False{} False{}:
      "next"

# "[x] Make the map" is done, "[>] …" now, "[ ] …" next.
def step.of(+rest: String) -> Step:
  Step{String.trim(String.drop(rest, 3n)), step.status_of(String.starts_with(rest, "[x]"), String.starts_with(rest, "[>]"))}

def is_plan_line(+line: String) -> Bool:
  String.starts_with(String.trim(line), "PLAN:")

def steps.keep(plan: Bool, +line: String, ss: List<&2, Step>) -> List<&2, Step>:
  match plan:
    case True{}:
      step.add(step.of(String.trim(String.drop(String.trim(line), 5n))), ss)
    case False{}:
      ss

def steps.go(ls: List<&2, String>, ss: List<&2, Step>) -> List<&2, Step>:
  match ls:
    case Nil{}:
      ss
    case +h <> t:
      steps.go(t, steps.keep(is_plan_line(h), h, ss))

def steps.lines(ss: List<&2, Step>) -> String:
  match ss:
    case Nil{}:
      ""
    case +h <> t:
      "P" ++ tab() ++ step.status(h) ++ tab() ++ step.text(h) ++ nl() ++ steps.lines(t)

def plan_of(+out: String) -> String:
  steps.lines(steps.go(String.lines(text_of_turn(out)), []))

def plan_words.keep(plan: Bool, +line: String, rest: List<&2, String>) -> List<&2, String>:
  match plan:
    case True{}:
      rest
    case False{}:
      line <> rest

# What the person reads: the reply without its PLAN: lines (the plan is drawn apart).
def plan_words.step(+line: String, rest: List<&2, String>) -> List<&2, String>:
  plan_words.keep(is_plan_line(line), line, rest)

def plan_words.go(ls: List<&2, String>) -> List<&2, String>:
  match ls:
    case Nil{}:
      Nil{}
    case +h <> t:
      plan_words.step(h, plan_words.go(t))

def plan_words(reply: String) -> String:
  String.trim(String.join(plan_words.go(String.lines(reply)), "\n"))

# The files changed: one per file, its lines added and removed summed over its edits, in the order first changed.
type Change is Data:
  Change{file: String, added: U32, removed: U32}

def change.at(write: Bool, +name: String, +inp: String) -> Change:
  match write:
    case True{}:
      Change{field(inp, "file_path"), lines(field(inp, "content")), 0}
    case False{}:
      Change{field(inp, "file_path"), lines(field(inp, "new_string")), lines(field(inp, "old_string"))}

def change.of(+name: String, +inp: String) -> Change:
  change.at(String.eq(name, "Write"), name, inp)

def change.file(+c: Change) -> String:
  match c:
    case Change{+f, a, r}:
      f

def change.added(+c: Change) -> U32:
  match c:
    case Change{f, +a, r}:
      a

def change.removed(+c: Change) -> U32:
  match c:
    case Change{f, a, +r}:
      r

def change.pick(same: Bool, merged: List<&2, Change>, other: List<&2, Change>) -> List<&2, Change>:
  match same:
    case True{}:
      merged
    case False{}:
      other

def change.add(+c: Change, cs: List<&2, Change>) -> List<&2, Change>:
  match cs:
    case Nil{}:
      [c]
    case +h <> +t:
      change.pick(String.eq(change.file(h), change.file(c)), Change{change.file(h), (change.added(h) + change.added(c) : U32), (change.removed(h) + change.removed(c) : U32)} <> t, h <> change.add(c, t))

def changes.keep(file: Bool, +p: String, cs: List<&2, Change>) -> List<&2, Change>:
  match file:
    case True{}:
      change.add(change.of(tool_name(p), tool_input(p)), cs)
    case False{}:
      cs

def changes.go(xs: List<&2, String>, cs: List<&2, Change>) -> List<&2, Change>:
  match xs:
    case Nil{}:
      cs
    case +h <> t:
      changes.go(t, changes.keep(is_file_tool(tool_name(h)), h, cs))

def changes.lines(cs: List<&2, Change>) -> String:
  match cs:
    case Nil{}:
      ""
    case +h <> t:
      "C" ++ tab() ++ base_name(change.file(h)) ++ tab() ++ U32.show(change.added(h)) ++ tab() ++ U32.show(change.removed(h)) ++ nl() ++ changes.lines(t)

def changes.count(cs: List<&2, Change>, n: U32) -> U32:
  match cs:
    case Nil{}:
      n
    case h <> t:
      changes.count(t, (n + 1 : U32))

# The title over the files changed: "1 file changed", "3 files changed" (none without files).
def changes.title.at(+n: U32, one: Bool) -> String:
  match one:
    case True{}:
      "H" ++ tab() ++ "1 file changed" ++ nl()
    case False{}:
      "H" ++ tab() ++ U32.show(n) ++ " files changed" ++ nl()

def changes.title.of(+n: U32, none: Bool) -> String:
  match none:
    case True{}:
      ""
    case False{}:
      changes.title.at(n, U32.is_eq(n, 1))

def changes.title(+n: U32) -> String:
  changes.title.of(n, U32.is_eq(n, 0))

# Now: the last action.
def now.last(xs: List<&2, String>, found: String) -> String:
  match xs:
    case Nil{}:
      found
    case +h <> t:
      now.last(t, h)

def now.at(none: Bool, +p: String) -> String:
  match none:
    case True{}:
      ""
    case False{}:
      "W" ++ tab() ++ work_verb(work_kind(tool_name(p))) ++ tab() ++ work_what(tool_name(p), tool_input(p)) ++ nl()

def now.of(+p: String) -> String:
  now.at(String.eq(p, ""), p)

# The context used: the last message's tokens in (new, written to cache, read from cache) and out, over the
# model's window, in percent. Each turn sends the whole conversation, so it grows as the talk does.
def starts_digit(s: String) -> Bool:
  match s:
    case SNil{}:
      False{}
    case SCon{+h, t}:
      Char.is_digit(h)

def digits.go(s: String, n: U32, digit: Bool) -> U32:
  match s digit:
    case SNil{} _:
      n
    case SCon{h, t} False{}:
      n
    case SCon{+h, +t} True{}:
      digits.go(t, ((n * 10) + (Char.to_u32(h) - 48) : U32), starts_digit(t))

def number(+s: String, +key: String) -> U32:
  digits.go(after(s, "\"" ++ key ++ "\":"), 0, starts_digit(after(s, "\"" ++ key ++ "\":")))

def last_or(m: Maybe<&2, String>) -> String:
  match m:
    case None{}:
      ""
    case Some{s}:
      s

def context.used(+usage: String) -> U32:
  (number(usage, "input_tokens") + number(usage, "cache_creation_input_tokens") + number(usage, "cache_read_input_tokens") + number(usage, "output_tokens") : U32)

def context.percent(+used: U32, +window: U32) -> String:
  work.pick(U32.is_eq(window, 0), "X" ++ tab() ++ U32.show(((used * 100) / window : U32)) ++ nl(), "")

def context_of(+out: String) -> String:
  context.percent(context.used(line_of(last_or(List.last(&2, String, rest_of(Models.pieces(out, "{\"type\":\"assistant\"")))))), number(out, "contextWindow"))

def work(+out: String) -> String:
  actions(tools_of(out), results_of(out), 0) ++ plan_of(out) ++ changes.lines(changes.go(tools_of(out), [])) ++ changes.title(changes.count(changes.go(tools_of(out), []), 0)) ++ now.of(now.last(tools_of(out), "")) ++ context_of(out)

# A number written in text ("12" is 12; "" is 0).
def to_u32(+s: String) -> U32:
  digits.go(s, 0, starts_digit(s))
