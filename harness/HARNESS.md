# Harness

What the chat may do, and when it asks. Works the same with any AI.
The rules live in POLICY.bend; LAWS.bend checks them.

## Modes

The person picks one under the message field. It starts on "Only read".
"Ask before changes" works with Claude only: Codex can't ask yet. "Change freely" comes later.

| What the chat does    | Only read | Ask before changes | Change freely |
|-----------------------|-----------|--------------------|---------------|
| Read files            | Yes       | Yes                | Yes           |
| Edit or create files  | No        | Asks               | Yes           |
| Run commands          | No        | Asks               | Asks          |
| Change LAWS.bend      | Never     | Never              | Never         |

## When it offers the mode

In Only read, when the person wants something built, the chat doesn't refuse: it offers
Ask before changes (OFFER.bend). Switch moves the picker and sends the request again;
Stay changes nothing. The flow is drawn in Chat › Context, from OFFER.flow().

## When it asks

In Ask before changes, before an action that isn't reading, the chat knocks at the gate with the
whole action (GATE.bend) and waits. A law refuses, the mode refuses, what was allowed for this
conversation passes; otherwise the person is asked: Allow, Allow for this session, or Don't allow.
Until they answer, the turn waits, with no time limit. Nothing is tried twice.

## What is yours

A message that starts with ! is a command you run yourself, in the project's folder. Nothing is
asked, since you are the one asking; a mode that only reads runs none. The chat reads what it printed.
The terminal under the chat is your own shell. The chat neither sees it nor types in it.

## One engine

The page and the terminal (laweditor) are windows on the same engine: the conversation, its
questions and what was allowed live in the server, kept with the project. What is done in one
shows in the other.

## Checked by

chat_only_reads, chat_claude_reads, chat_codex_reads, chat_never_changes

## Ideas from

- Claude Code: a mode picker under the field; asking before an action; rules per tool.
- Codex: a read-only mode as the safe start.
- Hermes: allow once, for the session, or never.
