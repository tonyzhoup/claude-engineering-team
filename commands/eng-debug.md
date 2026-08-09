---
description: 疑难调试：先复现再证明根因，最小修正 + 聚焦验证 + 独立复核
argument-hint: "[失败现象]"
disable-model-invocation: true
---

Investigate: $ARGUMENTS

Preserve all existing evidence. Use `debugger` only after the local cause is not obvious or normal attempts have failed.

Require, in order: reproduction or the strongest available evidence, tested hypotheses, a proven root cause, the smallest fix, focused validation, and a fresh final `reviewer`.

Reject fixes that hide the failure behind retries, sleeps, broad catches, or defensive layers. Do not commit.
