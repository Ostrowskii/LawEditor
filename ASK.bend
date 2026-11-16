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

def preview.of(+inp: String, edit: Bool, write: Bool) -> String:
  match edit write:
    case True{} _:
      field(inp, "new_string")
    case False{} True{}:
      field(inp, "content")
    case False{} False{}:
      field(inp, "command")

def preview(+t: String, +inp: String) -> String:
  preview.of(inp, String.eq(t, "Edit"), String.eq(t, "Write"))

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

