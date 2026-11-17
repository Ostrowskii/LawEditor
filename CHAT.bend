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
