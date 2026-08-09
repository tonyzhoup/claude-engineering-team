# Claude Engineering Team

**Version 1.2.1** — [**codex-engineering-team**](https://github.com/tonyzhoup/codex-engineering-team) 的 Claude Code 版本。保留同一套团队契约、交接协议与实现包格式，把执行层从 Codex 自定义 agent 换成 Claude Code subagent。两个包保持同版本号即表示契约同代。

一支刻意保持精简的工程 agent 团队，目标是**简洁、长效、稳健、优雅，不过度设计**。

## 团队

| Agent | 模型 / effort | 权限 | 职责 |
|---|---|---|---|
| `explorer` | Sonnet 5 / high | 只读 | 仓库事实、执行路径、归属、影响面 |
| `architect` | Opus 5 / xhigh | 只读 | 最小持久决策与实现包 |
| `implementer` | Sonnet 5 / high | 可写 | 有边界的生产代码实现 |
| `test-engineer` | Sonnet 5 / high | 可写（仅测试） | 独立的、由需求驱动的测试 |
| `reviewer` | Opus 5 / xhigh | 只读 | 架构、代码、验收三道门禁 |
| `debugger` | Opus 5 / xhigh | 可写 | 疑难根因调试与最小修正 |
| `git-operator` | Sonnet 5 / high | 只读 + Git | 精确的仓库状态与历史操作 |

分层原则：**架构与评审用最强大脑（Opus 5 + xhigh），编码与测试用性价比模型（Sonnet 5）**。

Codex 版给 `implementer`/`test_engineer` 用的是 `max`，这里改为 `xhigh`/`high`。不用 `max` 是因为官方文档明确标注它"容易过度思考、收益递减，大规模采用前需实测"。

`implementer` 刻意高于 Sonnet 5 的默认档（`high`）：它是唯一直接改生产代码的角色，一个错误要走完"测试→评审→返工"整条链才收得回来，值得多花推理 token。`test-engineer` 留在默认档，因为测试写错在下一次运行就暴露了。

官方模型/档位指南的基线是*"for most tasks you should use the model's default effort level"*——若你实测下来 `implementer` 在 `high` 上表现无差别，降档即可省一笔。

**为什么不直接用内置 `Explore`**：内置 Explore 会继承主会话模型（Claude API 上封顶到 Opus）。你的主会话默认跑 Opus 5，那内置 Explore 就是 Opus 在跑探索。本团队的 `explorer` 把模型钉死在 Sonnet 5，且**会加载 `CLAUDE.md`**（内置 Explore/Plan 刻意跳过），所以既更便宜也更懂项目约定。

主对话就是 supervisor。没有常驻的 supervisor agent，也没有工作流数据库。

## 契约存放位置

```text
~/.claude/
├── CLAUDE.md          # 何时该委派、路由、门禁、边界、完成标准（受管块）
├── agents/            # 每个角色的授权、期望输入，及其输出规格（Handoff / Packet 模板）
│   └── *.md
└── commands/          # 工作流入口斜杠命令
    └── eng-*.md

<repo>/
└── CLAUDE.md          # 仓库结构、命令、约定、约束、完成标准
```

全局文件说明**团队如何协作**；每个 agent 文件说明**该角色如何工作、产出什么形状**；仓库 `CLAUDE.md` 说明**这个代码库如何工作**。

关键前提：Claude Code 的**自定义 subagent 会加载完整的 `CLAUDE.md` 层级**（`~/.claude/CLAUDE.md`、项目规则、`CLAUDE.local.md`），因此全局契约对七个 agent 都生效。只有内置的 `Explore` 和 `Plan` 会跳过 `CLAUDE.md`——所以工程任务应优先用本团队的 agent，而不是这两个内置 agent。

交接默认留在 subagent 的返回消息里。除非确实需要跨会话持久化或审计轨迹，否则不要为每个任务建文件。

## 安装

在本目录下执行：

```bash
./install-user.sh
```

安装脚本会：

1. 安装七个 agent 与六个斜杠命令，仅在内容变化时备份同名文件；
2. 在全局 `CLAUDE.md` 中追加或替换一个带清晰标记的受管块，仅在内容变化时备份；
3. 不修改 `settings.json`。

只装 agent 与命令、不动全局 `CLAUDE.md`：

```bash
./install-user.sh --no-global
```

安装后**重启一个新的 Claude Code 会话**：首次创建 `commands/` 目录后，文件监听不会自动加载其中的新文件。

### 上下文成本

`global/CLAUDE.md` 是 102 行 / 7.8 KB。装进 `~/.claude/CLAUDE.md` 后，它会加载进**每一次会话**——包括"帮我改个变量名"这种——以及**每一个 subagent**（自定义 subagent 必然加载完整 CLAUDE.md 层级，没有开关可以关掉）。一条六步流水线约 18k tokens 花在契约本身上。

官方建议单个 CLAUDE.md 控制在 200 行以内（越长越费上下文、遵守度越低），102 行在预算内。

契约按"谁需要谁携带"切分：路由、门禁、边界这些**主对话**才用得上的规则留在全局块；Handoff 的确切格式和 Packet 模板属于**输出规格**，下沉到产出它们的 agent 文件里。副作用是即使用 `--no-global` 只装 agent，各角色仍能产出格式正确的交接块。

## 加入项目事实

把模板复制进仓库并填上真实命令与约束：

```bash
cp project/CLAUDE.md.template /path/to/repo/CLAUDE.md
```

不要在每个仓库里重复全局工作流规则。项目说明要短、准、具体。

## 斜杠命令

| 命令 | 用途 |
|---|---|
| `/eng-feature <特性>` | 完整特性流程：探索 → 架构 → 架构评审 → 实现 → 测试 → 代码/验收评审 |
| `/eng-fix <缺陷>` | 小缺陷修复，流程按风险裁剪 |
| `/eng-design <变更>` | 只做架构：最小持久决策 + 实现包 + 独立架构评审 |
| `/eng-debug <现象>` | 疑难调试：先复现、再证明根因、最小修正 |
| `/eng-commit` | 终审通过后由 `git-operator` 提交（不推送） |
| `/eng-verify` | 安装自检 |

这些命令都设了 `disable-model-invocation: true`，只能由你手动触发，不会被模型自动加载。

## 预期工作流

非平凡变更：

```text
Explorer(s)
  -> Architect
  -> 全新 Reviewer（ARCHITECTURE）
  -> Implementer 实现包
  -> Test Engineer
  -> 全新 Reviewer（CODE+ACCEPTANCE）
  -> 仅在需要时 Git Operator
```

小而明确的变更：跳过架构环节，只用最少的必要角色。

## 交接设计

每个 subagent 都以一个紧凑的 `## Handoff` 块结尾，包含 status、next role、summary、evidence、decisions、changes、risks、blockers 和一个 next action。architect 额外输出有边界的实现包，明确写面、不变式、验收检查与升级条件。

模板放在**各自的 agent 文件里**而不是全局块里：它是输出规格，只有产出者需要确切形状；主对话读到什么就照什么路由，不需要预先知道模板。全局块只保留主对话路由要用的东西——status 语义和三个具名 blocker 各自路由到谁。

这里刻意用 Markdown 而不是 JSON 工作流 schema：人类可读、能扛住模型与版本变化，且足以让主对话决定下一步。

## 与 Codex 版本的差异

原版在 [tonyzhoup/codex-engineering-team](https://github.com/tonyzhoup/codex-engineering-team)。契约、角色、交接格式、实现包格式、门禁语义完全一致，差异只在平台落地方式：

| 维度 | Codex | Claude Code |
|---|---|---|
| Agent 定义 | `~/.codex/agents/*.toml` | `~/.claude/agents/*.md`（YAML frontmatter + 正文即系统提示词） |
| 全局契约 | `~/.codex/AGENTS.md` | `~/.claude/CLAUDE.md` 受管块 |
| 项目说明 | `<repo>/AGENTS.md` | `<repo>/CLAUDE.md` |
| 推理档位 | `model_reasoning_effort` | frontmatter `effort` |
| 只读隔离 | `sandbox_mode = "read-only"` | 工具白名单不含 `Edit`/`Write`/`NotebookEdit` + 提示词约束 |
| 示例提示词 | `sample-prompts.md` | `commands/eng-*.md` 斜杠命令 |
| 运行时配置 | `config-snippet.toml` | 不需要，agent 与命令自动发现 |
| 角色命名 | `test_engineer` / `git_operator` | `test-engineer` / `git-operator`（Claude Code 只允许小写字母与连字符） |

两处刻意的收紧：

- `git-operator` 在 Claude 版本里**没有任何文件编辑工具**（Codex 版给的是 `workspace-write`）。Git 操作全部走 Bash，从机制上保证它不会改动源码或测试内容。
- 只读角色的 Bash 仍然存在（`git diff`、`rg`、`git log` 需要），因此只读是"工具白名单 + 提示词纪律"，不是沙箱级强制。若要硬隔离，可在 `~/.claude/settings.json` 的 `permissions.deny` 中增加规则。

## 设计权衡与已知局限

这套结构不是对所有任务都最优，以下几点是清醒的取舍，不是遗漏。

**1. 用 subagent 拆分阶段，与官方"多阶段共享上下文时应留在主对话"的建议相冲突。**

官方文档明确把"planning、implementation、testing 这类共享大量上下文的多阶段任务"列为**应该用主对话**的场景，理由是 subagent 每次都从零上下文启动，看不到会话历史。

这里仍然拆分，是因为**模型分层在单一对话里做不到**——只有 subagent 才能让 architect 跑 Opus、implementer 跑 Sonnet。这正是你要的成本结构，代价就是上下文连续性。

补偿手段写进了全局契约：主对话每次委派都必须把原始需求、验收标准和上一份 handoff 放进 subagent 的 prompt。这是官方对 subagent/teammate 的头号最佳实践。

**2. 因此不要让整条流水线变成默认路径。** 全局块里的「When not to delegate」是这套设计能不臃肿的关键，它把官方"何时该留在主对话"的判据内化成硬规则：委派只在**隔离冗长产出、限制工具权限、切换模型档位**三者之一成立时才做；需要频繁往返、多阶段共享大量上下文、或只是快速定点改动的，直接在主对话干。一次改名、加个字段，别走流水线。

真正划算的场景是：跨模块边界的变更、需要独立视角的评审、根因不明的调试。

**3. 每个 subagent 返回的结构化报告都会进主对话上下文。** 官方警告过"多个 subagent 各自返回详细结果会显著消耗上下文"。契约里的"能给结论就不要贴原始日志"就是为此。六步流水线跑完，主对话会累积六份报告。

**4. 只读是软约束。** 只读角色仍持有 Bash，靠的是工具白名单（无 `Edit`/`Write`）+ 提示词纪律，不是沙箱。要硬隔离得上 `permissions.deny`。

**5. 七个 agent 都不能再派生 subagent。** 它们的 `tools` 里都没有 `Agent`，这是刻意的——路由权归主对话。Claude Code 默认允许 subagent 嵌套三层，官方也建议"想让 reviewer 保持只读就把 `Agent` 从它的 tools 里去掉"。这条正好对上。

## 什么时候手动升级到 agent teams

Claude Code 另有一套 **agent teams**：teammate 是完整独立的 Claude Code 会话，彼此能直接发消息、共享任务列表、你也能切进去直接对话。

**本包刻意不依赖它**：实验特性、默认关闭、token 成本显著更高，且已知限制不轻——`/resume` 和 `/rewind` 不恢复 in-process teammate、teammate 常忘记标记任务完成导致依赖卡住、一个会话只能有一个 team 且不能嵌套。而这套流水线本身是顺序 + 门禁的形状，官方也建议顺序任务用单会话或 subagent。

### 判据

teams 唯一无法被 subagent 替代的能力是**teammate 之间能互相反驳**。只有当"独立视角会互相证伪"本身是收益来源时才值得升级。满足以下之一：

- **调试出现锚定**：`debugger` 已经跑过一轮，给出了一个说得通但没被证伪的根因，而失败仍在复现。单个 agent 顺序排查会锁死在第一个合理解释上。
- **评审维度互不重叠且都很重**：安全、性能、测试覆盖需要同时深挖，且你不希望一个 reviewer 在维度间摊薄注意力。

不满足这两条就别开——多花的 token 换不回东西。

### 启用

```json
// ~/.claude/settings.json
{ "env": { "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1" } }
```

重启会话生效。默认 in-process 模式（agent 面板在输入框下方，上下键选中、回车进入直接对话）；装了 tmux 或 iTerm2 + `it2` 可设 `"teammateMode": "auto"` 用分屏。

### 竞争性假设调试

```text
<失败现象>。已排查过：<已有证据与被否掉的假设>。

起 4 个 teammate，用 debugger 这个 agent type，各自认领一个互不相同的根因假设去查。
要求它们互相发消息、主动证伪对方的假设，像科学辩论一样，不要各查各的。
只有能给出复现或直接证据的假设才算活下来。
最后由你综合：说明哪个假设活下来、靠什么证据、其余为什么被排除。先不要改代码。
```

### 多视角并行评审

```text
评审 <改动范围>。起 3 个 teammate，都用 reviewer 这个 agent type，各自锁定一个维度：
一个只看安全，一个只看性能与并发，一个只看测试覆盖与验收对齐。
维度不要重叠。各自按 reviewer 的裁定格式给结论，然后由你合并成一份，冲突处标明分歧。
```

复用本包定义时有两点差异要知道：teammate 模式下 agent 正文是**追加**到系统提示词而非替换它，且 `skills`/`mcpServers` 两个字段不生效（`tools` 和 `model` 正常沿用）。

## 可选调整

- **想更强的架构/评审大脑**：把 `architect.md`、`reviewer.md`、`debugger.md` 的 `model` 改为 `fable`。Fable 5 更适合长时间自主任务；对单次深度分析，Opus 5 + `xhigh` 通常是更好的成本/效果平衡点，所以默认用 Opus 5。
- **想更省**：把 `explorer` 的 `effort` 降到 `medium`。注意 Haiku 4.5 不支持 `effort` 字段，改成 `haiku` 会让该字段失效。
- **想接管所有自动探索**：把 `explorer.md` 改名为 `Explore`（`name` 和文件名一起改）。同名的用户级 subagent 会覆盖内置 Explore，Claude 的所有自动探索委派都会落到 Sonnet 上。收益是省钱，代价是改变了内置行为，默认不这么做。
- **想让 agent 能查外部文档**：在对应 agent 的 `tools` 中加入 `WebSearch, WebFetch`，或用 `mcpServers` 字段挂载 context7 之类的 MCP。默认不给，是为了让"仓库是事实来源"这条规则成立。默认也没给 `Skill`，若你的项目技能里写了关键约定，可以给 `implementer`/`architect` 加上。
- **主对话档位**：`~/.claude/settings.json` 的 `effortLevel` 控制 supervisor 自身的推理档；subagent 的 `effort` 会覆盖它。

## 冒烟测试

安装并重启会话后，在一个真实仓库里执行：

```text
/eng-verify
```

然后用 `/eng-feature` 跑一个真实的中等规模需求。
