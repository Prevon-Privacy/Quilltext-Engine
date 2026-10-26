---
kind: ops-doc
area: unsorted
class: reference
status: live
---
# START HERE — what is `prevon_quilltext_engine`?

This is our copy of a free, open-source text editor toolkit (AppFlowy Editor), modified for Prevon's app. The license requires that if we change it and ship it, our changed version of THIS CODE ONLY must be public. That's why this repo exists.

Nothing else about Prevon is public. This folder should only ever contain generic editor code — no vaults, mnemonics, encryption, or Prevon-specific system names. Prevon features get added from the the main Prevon app, plugged into this editor's extension points — never inside this folder.

Real work happens in the monorepo copy (the main Prevon project). This public repo is a mirror, updated by a fixed script when the owner pushes. Nobody edits this copy directly, and no AI agent runs the publish step by hand.