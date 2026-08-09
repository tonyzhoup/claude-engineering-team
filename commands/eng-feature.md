---
description: 完整特性工作流：explorer → architect → 架构评审 → implementer → test-engineer → 代码/验收评审
argument-hint: "[要实现的特性]"
disable-model-invocation: true
---

Implement: $ARGUMENTS

Follow the engineering-team operating agreement. Preserve the original requirement through every handoff.

Use the fewest useful agents:
- `explorer` only if the responsible path is unclear; parallel explorers only for genuinely independent areas.
- `architect` only if the change crosses a real architecture boundary.
- a fresh `reviewer` in ARCHITECTURE mode before implementation.
- `implementer` strictly from explicit packets; run packets in parallel only when their write surfaces are disjoint.
- `test-engineer` for independent behavioral coverage.
- a fresh `reviewer` in CODE+ACCEPTANCE mode before declaring completion.

Resolve every `CHANGES_REQUIRED` finding by routing it to the owning role. Do not commit.
