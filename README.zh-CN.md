<div align="center">

# claude-onesync

**在一台电脑上改了 Claude Code 的配置，其他电脑自动跟上。**

规则、设置、hooks、agents、skills 和 memory，笔记本、台式机、服务器上都保持一样。删除也会同步。不用常驻进程，也不需要额外的服务，文件只进你自己的私有 git 仓库。

[![tests](https://github.com/Jcxu97/claude-onesync/actions/workflows/test.yml/badge.svg)](https://github.com/Jcxu97/claude-onesync/actions/workflows/test.yml)
![PowerShell 7](https://img.shields.io/badge/PowerShell-7%2B-5391FE)
![platforms](https://img.shields.io/badge/Windows%20%7C%20macOS%20%7C%20Linux-lightgrey)
[![license: MIT](https://img.shields.io/badge/license-MIT-green)](LICENSE)

[English](README.md) · 中文

<img src="docs/how-it-works.drawio.svg" alt="claude-onesync 的结构" width="900">

</div>

## 遇到的问题

你在笔记本上教了 Claude Code 一条规则，第二天换到台式机，它就不知道了。一台机器上加了 hook，另一台忘了加。删掉一个旧 skill，过两天又从备份里冒出来。

两台以上的机器，靠手动复制 `~/.claude` 已经管不过来。直接把它放进 git，或者软链接到网盘，又会碰到别的问题。
1. Claude Code 的 memory 按启动目录分开存（`~/.claude/projects/<目录>/memory`）。你在一个项目里存下的规则，换个项目就读不到。
2. git 不保留文件时间。拉取以后每个文件看起来都是新的，按"谁新用谁"写的脚本会把你本机真实的改动覆盖掉。
3. 一台机器删掉的文件，别的机器上还在，下次同步又被带回来。
4. `~/.claude` 里还有登录凭据、对话记录和只属于这台机器的设置，这些不能离开本机。

## onesync 做了什么

| | |
|---|---|
| **一处改动，处处生效** | 哪台机器改了文件，就从那台同步到其他所有机器。 |
| **删除也同步** | 在一台机器上删掉 skill 或 memory，其他机器也会删掉。 |
| **共享 memory 进每个项目** | 类型是 `feedback` 或 `user` 的 memory 会复制到每个项目目录，在哪个目录启动 Claude 都按你的规则办事。项目笔记只留在自己的项目里。 |
| **新的改动胜出** | 比的是本机文件时间和 git 提交时间，不是 `git pull` 写下的文件时间。 |
| **不会丢东西** | 被覆盖或删除的文件先进 `~/.claude/.onesync-trash/`，保留 30 天。 |
| **密钥不上传** | 看起来含有 API key 的文件不会上传。 |
| **自动运行** | 每次开新会话、按计划定时，或者你手动跑。不弹任何窗口。 |
| **一个文件，没有常驻进程** | `onesync.ps1` 是一个 PowerShell 7 脚本，只依赖 `git`。 |

## 快速开始

每台机器都要装 [PowerShell 7](https://learn.microsoft.com/powershell/scripting/install/installing-powershell) 和 git。

1. 在 GitHub 上点 **Use this template**，新仓库选 **Private**。
2. 在第一台机器上克隆你的新仓库，删掉模板标记文件。

   ```bash
   git clone https://github.com/<you>/<your-repo>.git ~/.claude-onesync
   cd ~/.claude-onesync
   git rm .onesync-template && git commit -m "my sync repo" && git push
   ```

3. 先预演一遍。它只列出要复制什么，不改任何东西。

   ```bash
   pwsh ./onesync.ps1 status
   ```

4. 跑第一次同步，再装上会话启动时自动同步的 hook。

   ```bash
   pwsh ./onesync.ps1 sync
   pwsh ./onesync.ps1 install-hook
   ```

5. 其他每台机器克隆同一个仓库，做第 3 步和第 4 步。

想定时同步的话再加一个计划任务（默认每 20 分钟一次）。

```bash
pwsh ./onesync.ps1 install-schedule
```

### 也可以让 Claude Code 自己装

在每台机器的 Claude Code 里贴这段话。

```text
在这台机器上装好 claude-onesync。我的私有仓库是 <仓库地址>。
克隆到 ~/.claude-onesync。如果有 .onesync-template，删掉它，提交并推送。
运行 "pwsh ./onesync.ps1 status"，把计划给我看，等我确认。
然后运行 "pwsh ./onesync.ps1 sync" 和 "pwsh ./onesync.ps1 install-hook"。
```

## 原理

<div align="center"><img src="docs/sync-round.drawio.svg" alt="一轮同步" width="520"></div>

一轮同步分这几步。
1. **拉取。** 先拉取仓库。rebase 有冲突时本机的提交胜出，因为它是更新的改动。
2. **本机删除。** onesync 记着上一轮同步过哪些文件（`~/.claude/.onesync-state.json`）。上一轮有、现在没了，就是在这台机器上删的，从仓库里删掉。
3. **别台删除。** git 历史显示仓库删过这个文件，而且本机这份比那次删除还旧，就把本机这份挪进回收站。如果你在删除之后又改过本机这份，就留着，重新上传。
4. **改动。** 两边不一样的文件，新的一方胜出。"新"指的是本机文件时间和最后一次改动这个文件的提交时间相比。
5. **共享 memory。** `memory/_shared/` 里的每个文件复制到每个 `~/.claude/projects/*/memory/`。
6. **索引。** 每个 `MEMORY.md` 合并所有机器的索引行，再加上一段自动生成的共享 memory 索引。指向已删除文件的行会去掉。
7. **提交并推送。**

### 同步哪些东西

| 同步的 | 仓库里的位置 |
|---|---|
| `CLAUDE.md`、`settings.json` | `claude/` |
| `agents/`、`commands/`、`hooks/`、`skills/`、`output-styles/` | `claude/` |
| `type: feedback` 或 `type: user` 的 memory | `memory/_shared/` |
| 其他项目 memory | `memory/<项目目录>/` |

| 从来不读的 | 原因 |
|---|---|
| `CLAUDE.local.md`、`settings.local.json` | 只属于这台机器的设置（路径、装了什么工具、API 地址）。 |
| `.credentials.json`、对话记录、todos、缓存 | 私密，或者只对这台机器有意义。 |
| 软链接目录、junction、带 `.git` 的目录 | 归别的工具管，在每台机器上各自安装。 |
| `node_modules`、`__pycache__`、`.venv`、`.cache` | 构建产物。自己的规则写进 `.onesyncignore`。 |

要改同步范围，改 `onesync.ps1` 开头的 `$SharedItems`。

## 安全措施

- **检查仓库是否私有。** 装了 GitHub CLI（`gh`）的话，仓库是公开的就直接停下。
- **检查密钥。** 文件里有 `sk-ant-…`、`ghp_…`、`AKIA…` 或私钥这类内容，就只留在本机，并给出提示。密钥请放进环境变量或 `settings.local.json`。
- **删除上限。** 一轮要删超过 30 个文件时什么都不改，直接停下。核对清单后加 `-AllowMassDelete` 再跑。
- **回收站。** 删除和被覆盖的文件进 `~/.claude/.onesync-trash/<时间>/`，保留 30 天。
- **不碰别人的目录。** 不进软链接、junction 和 git 克隆的目录，不会顺着链接删掉别的仓库里的文件。
- **模板保护。** 仓库里有 `.onesync-template` 时脚本不运行，防止把配置同步进公开模板。
- **同时只跑一轮。** 用锁文件防止 hook 和计划任务同时运行。

## 命令

| 命令 | 作用 |
|---|---|
| `pwsh ./onesync.ps1 status` | 列出这一轮的计划，不改任何东西。 |
| `pwsh ./onesync.ps1 sync` | 跑一轮同步。 |
| `pwsh ./onesync.ps1 install-hook` | 每次开 Claude Code 新会话时跑一轮。 |
| `pwsh ./onesync.ps1 install-schedule` | 登录时和之后每 20 分钟跑一轮（Windows 用任务计划程序；macOS 和 Linux 上打印一行 cron）。 |
| `pwsh ./onesync.ps1 uninstall-schedule` | 删除计划任务。 |

| 参数 | 用途 |
|---|---|
| `-MaxDelete 30` | 改删除上限。 |
| `-AllowMassDelete` | 允许这一轮删除超过上限。 |
| `-AllowSecrets` | 看起来含密钥的文件也上传。 |
| `-EveryMinutes 20` | `install-schedule` 的间隔。 |
| `-NoPush` | 只提交，不推送。 |
| `-ClaudeHome <path>` | 换一个 Claude Code 目录。 |

日志在 `~/.claude/.onesync.log`。

## 局限

- **按整个文件比较。** 两轮之间两台机器改了同一个文件，新的那份胜出。另一份在回收站（本机这边）或 git 历史（仓库那边）里。
- **时钟。** 判断新旧用的是系统时间，请开着自动校时。
- **会话启动。** hook 在会话启动时运行，Claude Code 可能在 hook 跑完之前就读了部分文件，这部分改动从下一个会话开始生效。
- **在 Windows 11 上实测过。** CI 在 Ubuntu 和 macOS 上跑同一套测试。

## 为什么不直接……

- **把 `~/.claude` 放进 git，或者软链接到网盘？** 凭据和对话记录也会被同步。删除和"哪边更新"都没人管。memory 还是只在一个项目目录里。
- **只同步 memory 目录？** `CLAUDE.md` 里的规则、hooks 和 skills 照样会不一致。一个启动目录的 memory 也到不了别的目录。

## 参与贡献

欢迎提 bug 和 pull request。提交改动前先跑测试。

```bash
pwsh tests/run.ps1
```

测试在临时目录里造两台假机器和一个空仓库，不会碰你真实的 `~/.claude`。

## 许可证

[MIT](LICENSE)
