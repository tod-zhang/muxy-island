<div align="center">
  <img src="ClaudeIsland/Assets.xcassets/AppIcon.appiconset/icon_128x128.png" alt="Logo" width="100" height="100">
  <h3 align="center">Muxy Island</h3>
  <p align="center">
    A macOS menu bar app that brings Dynamic Island-style notifications to <a href="https://github.com/muxy-app/muxy">Muxy</a> terminal sessions running Claude Code.
  </p>
</div>

## 简介

**专门用于 Muxy**。这是 [Vibe Notch (farouqaldori/vibe-notch)](https://github.com/farouqaldori/vibe-notch) 的 fork，在其基础上深度集成了 Muxy 的远程 WebSocket API，让 Vibe Notch 的刘海面板可以直接驱动 Muxy：

- **跳转到 session** — 点击面板里的 session 行，会直接跳转到 Muxy 里对应的 tab/pane（通过 `selectProject` + `focusArea` + `selectTab`）
- **在面板里发消息** — 聊天气泡打开的对话框能直接向 Muxy 对应的 Claude 实例发送 prompt（通过 `takeOverPane` + `terminalInput`）
- **hook 捕获 Muxy 上下文** — Python hook 读取 Muxy 注入的 `MUXY_PANE_ID` / `MUXY_PROJECT_ID` / `MUXY_WORKTREE_ID` 环境变量，无需进程树推断

Muxy 本身也有 Claude Code hook，但只做"发通知到 Muxy 内部 toast"。本 fork 是反向：把事件拉到刘海 UI 上做统一入口，包括审批、聊天、跳转。

## 特性

- **刘海 UI** — 动态岛风格的悬浮面板，鼠标悬停即展开
- **多 session 监控** — 实时追踪所有 Claude Code session（Muxy / tmux / 其他终端）
- **权限审批** — 直接在面板里批准或拒绝工具调用，可配置独立的提示音
- **聊天历史** — 在面板里查看完整对话（markdown 渲染），并向 Muxy pane 发送新消息
- **自动安装 hook** — 首次运行自动在 `~/.claude/settings.json` 注册事件 hook

## 系统要求

- macOS 15.6+
- Claude Code CLI
- （可选）Muxy — [muxy-app/muxy](https://github.com/muxy-app/muxy)，需在 Settings → Mobile 里开启 "Allow mobile device connection"
- （可选）tmux + yabai — 对非 Muxy 的 tmux session 使用 yabai 做窗口聚焦

## 使用 Muxy 集成

1. 打开 Muxy，进入 `Settings → Mobile`，开启 `Allow mobile device connection`
2. 在 Muxy 的 tab 里运行 `claude`
3. 运行本应用，session 会自动出现在刘海面板
4. **首次点击"跳转"**：Muxy 会弹出配对请求，点 approve
5. 之后每次点行都会直接跳到对应 pane

## 构建

```bash
xcodebuild -scheme ClaudeIsland -configuration Release build
```

项目用 Xcode 16 的 `PBXFileSystemSynchronizedRootGroup`，添加新 Swift 文件到 `ClaudeIsland/` 目录下会自动纳入构建。

## 致谢与许可

基于 [farouqaldori/vibe-notch](https://github.com/farouqaldori/vibe-notch)（Apache 2.0）fork。原作者实现了整个刘海 UI + Claude Code hook 系统，本 fork 在此之上新增 Muxy 集成。

本项目同样使用 Apache 2.0 许可证（见 `LICENSE.md`）。

## Fork 特有的改动

- `ClaudeIsland/Services/Muxy/` — MuxyClient（WebSocket + 配对）、MuxyController（高层聚焦/输入 API）、MuxyProtocol（wire types）
- `ClaudeIsland/Resources/claude-island-state.py` — hook 捕获 `MUXY_*` 环境变量
- `ClaudeIsland/Core/NotchViewModel.swift` — hover-to-expand 改成 0 延迟即时响应
- 设置菜单 — 新增独立的 "Approval Sound" 设置（审批提示音可单独配置）
- 分析/更新 — 移除原作者的 Mixpanel token 和 Sparkle feed URL，默认禁用
