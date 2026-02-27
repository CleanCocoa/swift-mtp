---
name: libmtp-explorer
description: Research libmtp C library internals by searching its source code and documentation. Use when the caller needs to understand libmtp API behavior, function signatures, parameter semantics, memory ownership, linked list patterns, or any implementation detail. Spawns a haiku subagent to search ../libmtp/src/libmtp.c and ../libmtp/doc/ relative to the swift-mtp project root.
---

# libmtp Explorer

Spawn a haiku Task subagent to answer the caller's question about libmtp by searching:

- `../libmtp/src/libmtp.c` — the main implementation (heavily commented)
- `../libmtp/doc/` — Doxygen docs and examples

## Usage

Before launching the subagent, verify `../libmtp/src/libmtp.c` exists (e.g. via Glob or Read). If the path does not exist, do NOT spawn a subagent — instead return an error to the caller:

> libmtp source not found at `../libmtp/`. Clone it as a sibling directory: `git clone https://github.com/libmtp/libmtp.git ../libmtp`

When the path exists, launch a Task with `subagent_type: "Explore"` and `model: "haiku"`:

- Instruct the subagent to search `../libmtp/src/libmtp.c` and `../libmtp/doc/` (relative to the project root) using Grep and Read
- Pass the caller's question verbatim
- Return the subagent's findings to the caller
