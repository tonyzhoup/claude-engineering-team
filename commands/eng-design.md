---
description: 纯架构任务：最小持久决策 + 实现包，并由独立评审挑战过度设计
argument-hint: "[要设计的变更]"
disable-model-invocation: true
---

Analyze and design: $ARGUMENTS

Gather only the repository facts actually needed, then have `architect` produce the smallest durable decision and bounded implementation packets.

Spawn a fresh `reviewer` in ARCHITECTURE mode to challenge over-engineering, state ownership, failure behavior, migration hazards, and materially simpler alternatives.

Return the revised design and handoffs. Do not edit code.
