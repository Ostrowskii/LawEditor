# LawEditor: the interphone. Before an action that isn't on its list, Claude asks LawEditor and waits
# (--permission-prompt-tool, over MCP). Pure: this reads what Claude sends and writes what goes back;
# server.bend answers POST /mcp/<turn> with it. NEXT.md (0.1.8) and PERMIT.ask_bend() say why.
#
# MCP over HTTP: each POST holds one JSON-RPC message, {"method":"…","params":{…},"jsonrpc":"2.0","id":…}.
# A message with no id is a notice and gets no answer. The tool's answer is one text block holding
# {"behavior":"allow"} or {"behavior":"deny","message":"…"}.

import Base
import ./ASK.bend as Ask

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

def decided(allowed: Bool) -> String:
  match allowed:
    case True{}:
      "{\"content\":[{\"type\":\"text\",\"text\":\"{\\\"behavior\\\":\\\"allow\\\"}\"}]}"
    case False{}:
      "{\"content\":[{\"type\":\"text\",\"text\":\"{\\\"behavior\\\":\\\"deny\\\",\\\"message\\\":\\\"The person did not allow it. Don't do it; go on without it.\\\"}\"}]}"

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

# A call's answer, once the person answered: "allow" lets it run, anything else doesn't.
def answer(+msg: String, +said: String) -> String:
  rpc(id(msg), decided(String.eq(String.trim(said), "allow")))

# ---------- The question, while Claude waits ----------

# One question at a time per turn: the page reads it, and writes the answer next to it.
def question_file(+turn: String) -> String:
  "/tmp/laweditor-ask-" ++ Ask.safe_id(turn) ++ ".question"

def answer_file(+turn: String) -> String:
  "/tmp/laweditor-ask-" ++ Ask.safe_id(turn) ++ ".answer"

# The tool on the first line, then the file or command (a command may hold new lines).
def question(+msg: String) -> String:
  tool(msg) ++ "\n" ++ what(msg)
