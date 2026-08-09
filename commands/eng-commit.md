---
description: 终审通过后提交：由 git-operator 精确暂存并生成一个聚焦提交（不推送）
argument-hint: "[可选：提交范围说明]"
disable-model-invocation: true
---

The implementation has passed the fresh CODE+ACCEPTANCE review. Scope note: $ARGUMENTS

Use `git-operator` to inspect `git status` and the actual diff, stage only the intended files, and create one focused commit following recent repository message conventions.

Report the commit hash and the remaining working-tree state. Do not push.
