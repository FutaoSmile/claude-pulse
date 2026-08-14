# Claude Pulse

Claude Pulse 是一个常驻 macOS 屏幕边缘的 Claude Code 多会话状态面板。它通过 Claude Code 官方 Hooks 接收实时事件，让你无需逐个检查终端窗口，也能知道 Claude 正在处理任务，还是正在等你回复或授权。

状态仅保存在应用内存中。Claude Pulse 不解析终端文字、不保存提示词或会话历史，也不需要联网。

## 功能

- 同时查看多个 Claude Code 会话
- 在 iTerm2 中显示 Claude Code 当前对话标题和项目名
- 点击会话可切回对应的 iTerm2 标签页，右键可打开或复制工作目录
- 胶囊与完整面板两种显示形态
- 仅点击胶囊右侧下拉按钮展开，拖动胶囊其他区域可移动位置
- 状态事件只更新胶囊，不会自动展开面板
- 官方 Claude 品牌图标与原生 SwiftUI 动画
- 支持所有桌面空间和全屏应用
- 完全本地运行，通过 Unix Domain Socket 接收事件

## 支持的状态

| 状态 | 含义 |
| --- | --- |
| 处理中 | Claude 正在思考、读取文件或执行操作 |
| 等你回复 | Claude 已回复，正在等你继续输入 |
| 等待授权 | 有一项操作需要确认后才能继续 |
| 出现错误 | 工具执行失败，建议打开对应窗口查看 |
| 暂时空闲 | 会话已连接，目前没有正在进行的任务 |

## 系统要求

- macOS 14 或更高版本
- Swift 6 / Xcode Command Line Tools
- 已安装 Claude Code

## 安装

```bash
git clone https://github.com/FutaoSmile/claude-pulse.git
cd claude-pulse
chmod +x scripts/install-hooks.sh scripts/uninstall-hooks.sh
./scripts/install-hooks.sh
```

安装脚本会：

1. 构建 release 版本。
2. 安装应用到 `/Applications/Claude Pulse.app`。
3. 安装 Hook 桥接命令到 `~/.local/bin/cc-light`。
4. 以非破坏方式将所需 Hooks 合并到 `~/.claude/settings.json`。
5. 应用运行时会定期检查 Hooks；如果其他配置工具覆盖了该文件，Claude Pulse 会自动把缺失项合并回来。
5. 启动 Claude Pulse。

重新安装或修复 Hooks 后，请重新启动已打开的 Claude Code 会话。之后的会话会在触发 Hook 时自动出现。

首次点击会话切回 iTerm2 时，macOS 可能会询问是否允许 Claude Pulse 控制 iTerm2。允许后即可精确切换到对应标签页；无法读取终端标题时，列表会回退显示项目目录名。

## 本地演示

应用启动后可注入三个模拟会话：

```bash
~/.local/bin/cc-light demo
```

## 卸载

```bash
./scripts/uninstall-hooks.sh
```

卸载脚本只删除 Claude Pulse 添加的 Hooks 和桥接命令，不会修改其他 Claude Code 配置。应用可在 Finder 的“应用程序”目录中移到废纸篓。

## 工作方式

```text
Claude Code Hooks → cc-light emit → Unix Domain Socket → Claude Pulse
```

Hook 命令始终静默失败：即使 Claude Pulse 没有运行，也不会阻断 Claude Code。

## 品牌资产

仓库中的 Claude 图标来自 Anthropic 官方 Press Kit。Claude、Claude Code 和相关品牌资产是 Anthropic 的商标；本项目与 Anthropic 没有关联，也未获得其官方背书。
