---
description: 小缺陷修复：按风险裁剪流程，最小改动 + 高价值回归测试
argument-hint: "[要修复的缺陷]"
disable-model-invocation: true
---

Fix: $ARGUMENTS

Keep the process proportional to the risk:
- `explorer` only if the responsible path is unclear.
- `implementer` for the smallest correct fix.
- `test-engineer` for a high-value regression test.
- `reviewer` only for material risk.

Escalate to `debugger` after one focused correction or two failed validation loops rather than making speculative edits. Do not commit.
