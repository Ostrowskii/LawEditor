# LawEditor: the chat's logic. Pure; the page asks it and draws the answer.

import Base

# Who wrote a message.
def person() -> U32: 0
def agent() -> U32: 1

# Send is on when there is text and the agent is not answering.
def can_send.talk(answering: Bool, length: U32) -> Bool:
  match answering:
    case True{}:
      False{}
    case False{}:
      (length > 0 : U32)

# A question waits for the person (Add / Always add / Don't add, HEAR.bend): the talk stops until they answer.
def can_send(asking: Bool, answering: Bool, length: U32) -> Bool:
  match asking:
    case True{}:
      False{}
    case False{}:
      can_send.talk(answering, length)

# The agent's latest message: it says what it reads, then its words form, then it is done.
def reading() -> U32: 0
def writing() -> U32: 1
def done() -> U32: 2

# The model list of an AI: loading while the server asks its CLI, then ready (or empty if it can't).
def loading() -> U32: 0
def ready() -> U32: 1
def empty() -> U32: 2

# The model picker is on only when its list is ready.
def can_pick(list: U32) -> Bool:
  U32.is_eq(list, 1)

# The chat starts empty: the agent's face and the composer in the middle, until the first message.
def is_start(messages: U32) -> Bool:
  U32.is_eq(messages, 0)

# ---------- Typing / and @ ----------

# The commands a message can be: typed with /, each with what it does (one per line, split by a tab).
def commands() -> String:
  "/clear\tStart a new conversation\n/laws\tShow the laws of this project\n/context\tSee what the chat is told"

# The message as the chat reads it: the files the person pointed to with @ come after it.
def with_files.of(text: String, files: String, none: Bool) -> String:
  match none:
    case True{}:
      text
    case False{}:
      text ++ "\n\n(Files the person points to: " ++ files ++ ")"

def with_files(text: String, +files: String) -> String:
  with_files.of(text, files, String.eq(files, ""))

# ---------- Conversations ----------

# A conversation's title, for the list: the person's first message, its first line.
def title_of.at(+line: String, person: Bool) -> String:
  match person:
    case True{}:
      String.drop(line, 8n)
    case False{}:
      "Conversation"

def title_of.first(xs: List<&2, String>) -> String:
  match xs:
    case Nil{}:
      ""
    case h <> t:
      h

def title_of(+conversation: String) -> String:
  title_of.at(String.trim(title_of.first(String.lines(conversation))), String.starts_with(String.trim(title_of.first(String.lines(conversation))), "Person: "))

# ---------- Projects ----------

# A project's folder name, from the name the person gives it: lower case, letters and digits, "-" for the rest.
# "Rio Negro" is rio-negro; a name with nothing to keep is "project".
def slug.char(keep: Bool, +c: Char) -> Char:
  match keep:
    case True{}:
      c
    case False{}:
      '-'

def slug.go(s: String) -> String:
  match s:
    case SNil{}:
      ""
    case SCon{+h, t}:
      SCon{slug.char((Char.is_alpha(h) || Char.is_digit(h)), h), slug.go(t)}

def slug.or(+s: String, empty: Bool) -> String:
  match empty:
    case True{}:
      "project"
    case False{}:
      s

def slug(+name: String) -> String:
  slug.or(slug.go(String.to_lower(String.trim(name))), String.eq(String.trim(name), ""))

# ---------- A conversation's game ----------
# A conversation starts with no game. The chat names the game once, on a line of its own, when it starts
# building or hears the first rule: GAME: "Rio Negro" (CHAT.md teaches it). The page hides the line.

def is_game_line(+line: String) -> Bool:
  String.starts_with(String.trim(line), "GAME:")

def game.drop_quote(quote: Bool, +c: Char, rest: String) -> String:
  match quote:
    case True{}:
      rest
    case False{}:
      SCon{c, rest}

def game.unquote(s: String) -> String:
  match s:
    case SNil{}:
      ""
    case SCon{+h, t}:
      game.drop_quote(Char.is_eq(h, '"'), h, game.unquote(t))

def game.name_of(+line: String) -> String:
  String.trim(game.unquote(String.drop(String.trim(line), 5n)))

def game.pick(game: Bool, +line: String, +rest: String) -> String:
  match game:
    case True{}:
      game.name_of(line)
    case False{}:
      rest

def game.first(ls: List<&2, String>) -> String:
  match ls:
    case Nil{}:
      ""
    case +h <> t:
      game.pick(is_game_line(h), h, game.first(t))

# The name the chat gave the game in a reply ("" if it gave none).
def game_name(+reply: String) -> String:
  game.first(String.lines(reply))

def game_words.keep(game: Bool, +line: String, rest: List<&2, String>) -> List<&2, String>:
  match game:
    case True{}:
      rest
    case False{}:
      line <> rest

def game_words.go(ls: List<&2, String>) -> List<&2, String>:
  match ls:
    case Nil{}:
      Nil{}
    case +h <> t:
      game_words.keep(is_game_line(h), h, game_words.go(t))

# What the person reads: the reply without its GAME: line.
def game_words(reply: String) -> String:
  String.trim(String.join(game_words.go(String.lines(reply)), "\n"))

# The conversation as the chat reads it: with a game, a line that names it comes first (CHAT.md: the chat
# doesn't name it again).
def with_game.of(conversation: String, game: String, none: Bool) -> String:
  match none:
    case True{}:
      conversation
    case False{}:
      "Game: \"" ++ game ++ "\"\n\n" ++ conversation

def with_game(conversation: String, +game: String) -> String:
  with_game.of(conversation, game, String.eq(game, ""))
