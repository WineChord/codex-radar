# Codex Radar Sentinel

中文 | [English](README.en.md)

首先鸣谢 [CodexRadar](https://codexradar.com/)：本项目依赖 CodexRadar 提供的公开信号，包括 Codex 速蹬窗口、reset、reset 预测、RSS 事件和 model IQ。Codex Radar Sentinel 是一个本地 macOS 菜单栏工具，把 CodexRadar 的公开信号与本机 Codex 额度状态整合到状态栏里。

![Codex Radar Sentinel 中文状态栏](docs/assets/zh/status-normal.png)

## News / 最新功能

<details>
<summary><strong>v0.1.23：折叠区整行可点</strong> - 点标题文字、图标或右侧状态都能展开，不用再精确点左侧小箭头。</summary>

<img src="docs/assets/zh/news-pacing.png" width="390" alt="Codex Radar Sentinel 应剩策略截图">

- `应剩计算策略` 和 `状态栏高级` 的标题行都变成整行按钮。
- 左侧箭头只是视觉提示，实际可以点标题文字、图标、右侧状态。
- 这类小交互降低了菜单栏工具的操作精度要求，尤其适合高频点开查看。

</details>

<details>
<summary><strong>v0.1.22：策略卡片可直接切换</strong> - 不再依赖菜单栏弹窗里不稳定的下拉选择器。</summary>

- `应剩` 会把建议剩余和实际剩余放在一起看，直接告诉你还能多用还是该放慢。
- 展开 `应剩计算策略` 后，点击任一策略说明卡片即可切换。
- 当前策略会有蓝色高亮和 `当前` 标记，不需要猜当前选中了什么。

</details>

<details>
<summary><strong>v0.1.21：多种应剩策略</strong> - 按不同工作习惯规划周额度节奏。</summary>

<img src="docs/assets/zh/news-pacing.png" width="390" alt="Codex Radar Sentinel 用量节奏截图">

- 新增 `按时间`、`每日`、`留余`、`工作日`、`先用` 五种策略。
- 每种策略都解释公式、刷新粒度和适用场景。
- 可选把 `应剩` 放进状态栏，例如用 `应80%` 提醒现在理想剩余。

</details>

<details>
<summary><strong>v0.1.19：应剩改成建议剩余</strong> - 看“现在应该还剩多少”，比看“应该用掉多少”更直观。</summary>

- 用 `建议剩余 / 实际剩余 / 可多用` 三个卡片解释当前节奏。
- 例如建议应剩 80%、实际还剩 90%，就直接提示可以多用一点。
- 这个表达更适合控制周额度节奏，不需要用户自己反向换算。

</details>

<details>
<summary><strong>v0.1.17：状态栏高级压缩</strong> - 在不牺牲可读性的前提下减少菜单栏占位。</summary>

<p>
  <img src="docs/assets/zh/status-normal.png" height="30" alt="正常状态">
  <img src="docs/assets/zh/status-custom.png" height="30" alt="自定义状态">
</p>

- 可调分隔符、左右留白、字体比例。
- IQ 可以选择原值、`/10` 整数或 `/10` 小数。
- 可以隐藏 `%`，也可以只保留自己关心的状态栏段。

</details>

<details>
<summary><strong>v0.1.11：5h 短窗可选显示</strong> - 除了周额度，也能把短窗额度放进状态栏。</summary>

- `5h` 默认关闭，需要时可以手动打开。
- 打开后状态栏可以类似 `96%/99%/62/低`，第二个百分比就是短窗。
- 适合排查“周额度还很多，但短窗先触顶”的情况。

</details>

<details>
<summary><strong>v0.1.7：Prompt Log 开源</strong> - 把产品从想法、吐槽、截图反馈到发布验证的 prompt 一起放进仓库。</summary>

- 新增 [Prompt Log](PROMPTS.md)，记录用户直接给 Codex 的产品需求、设计反馈和验证要求。
- 去掉时间戳、本地路径、截图缓存路径和安全敏感信息，只保留可公开的产品上下文。
- 后续每条 prompt 都维护到实际 commit 的映射，commit 链接可点击。

</details>

<details>
<summary><strong>v0.1.4：自动更新</strong> - 新版本可以静默下载、校验、替换并重开。</summary>

- 默认开启自动更新，启动后会检查 GitHub Release，之后每 6 小时检查一次。
- 下载后校验 SHA256，再替换 app bundle。
- 如果更新失败，会保留当前版本并短期暂停同版本自动重试，避免循环重启。

</details>

<details>
<summary><strong>v0.1.0：第一版菜单栏仪表盘</strong> - 把 CodexRadar 公开信号和本机 Codex 额度合到一个 macOS 状态栏工具。</summary>

<p>
  <img src="docs/assets/zh/status-normal.png" height="30" alt="正常状态">
  <img src="docs/assets/zh/status-speed.png" height="30" alt="速蹬状态">
  <img src="docs/assets/zh/status-limit.png" height="30" alt="限额状态">
</p>

- 常驻显示周额度、Codex IQ 和 CodexRadar 信号。
- 速蹬窗口开启时状态栏变红，并发送 macOS 通知。
- reset 事件、预测、IQ、额度状态都在同一个下拉菜单里看。

</details>

## 让 Codex 帮你安装

如果你正在用 Codex 桌面版，可以直接复制下面这段 prompt 给 Codex。需要允许 Codex 访问网络、执行 shell 命令、写入 `/Applications`；如果 macOS 弹出通知权限，点允许即可。

```text
直接安装 Codex Radar Sentinel：下载 https://github.com/WineChord/codex-radar/releases/latest 的最新 macOS 包，装进 /Applications，启动并确认菜单栏；需权限问我。
```

## 状态栏含义

状态栏标题刻意保持很短：

```text
96%/62/低
```

三个值分别是：

- `96%`：Codex 周额度剩余百分比。
- `62`：Codex IQ 分数。状态栏默认截断为整数以节省空间；下拉菜单里的 Codex IQ 区块会显示精确值，例如 `62.5`。
- `低`：CodexRadar 的 reset / 速蹬信号。

下拉菜单的 `状态栏显示` 里还可以手动打开：

- `5h`：把 5 小时短窗额度也放进状态栏；默认关闭，打开后会类似 `96%/99%/62/低`。
- `应剩`：把“按节奏现在应该还剩多少周额度”放进状态栏；默认关闭，中文显示类似 `应80%`，英文显示类似 `R80%`。

`应剩计算策略` 默认收起。点击这一整行标题即可展开或收起；展开后点击任一策略卡片即可切换，并会直接说明每个策略的公式、刷新粒度和适用场景。

`状态栏高级` 默认收起；点击这一整行标题即可展开或收起。展开后可以调分隔符、左右留白、字体比例、IQ 是否按 `/10` 显示，以及状态栏里是否保留 `%`。这些设置只影响状态栏标题，下拉菜单里的完整数值不变。

当 [CodexRadar](https://codexradar.com/) 报告速蹬窗口开启时，状态栏 item 会变成红底白字。红色强调可以手动关闭；窗口结束或 30 分钟强调时间到后会自动退场。

## 状态展示

这些截图来自真实 macOS 状态栏：脚本会启动真实 app，切换预览状态，然后裁剪本 app 的状态栏 item。不是手绘 mock，也不包含右侧其他菜单栏图标。

| 正常 | 速蹬窗口 | 本机限额 | 自定义 |
| --- | --- | --- | --- |
| ![正常状态](docs/assets/zh/status-normal.png) | ![速蹬状态](docs/assets/zh/status-speed.png) | ![限额状态](docs/assets/zh/status-limit.png) | ![自定义状态](docs/assets/zh/status-custom.png) |

可以在下拉菜单里选择状态栏显示哪些值。例如不关心 IQ 时，可以只显示 `96%/低`。
如果关心 5 小时短窗，可以手动打开 `5h`，它会作为一个额外百分比插入到周额度和 IQ 之间。
如果想按 reset 窗口节奏均匀使用周额度，可以手动打开 `应剩`。
如果想让状态栏也显示精确 IQ 小数，可以打开 `状态栏 IQ 小数`。

## 完整菜单界面

这张图由 app 自己在高清屏上截取真实 SwiftUI 菜单窗口生成，和状态栏截图、News 小图一起由 `./scripts/update_readme_screenshots.sh` 维护。README 里按 390px 宽度展示，避免尺寸过大；点开原图可以看到高清细节。

<img src="docs/assets/zh/menu-full.png" width="390" alt="Codex Radar Sentinel 中文完整菜单界面">

## 它会显示什么

- Codex 周额度剩余，来自本机 Codex app-server。
- Codex 短窗额度剩余，也来自本机 Codex app-server。
- 用量节奏：按所选策略计算当前建议剩余百分比，并和实际周额度剩余对比；例如建议应剩 80%、实际还剩 90%，就会提示可以多用一点。
  策略包括：`按时间` 平滑均匀用完；`每日` 按天级预算推进；`留余` 前期保留 20% 缓冲；`工作日` 工作日多用、周末少用；`先用` 前半程更积极，避免 reset 前剩太多。
- [CodexRadar](https://codexradar.com/) 当前速蹬窗口和 reset 状态。
- [CodexRadar](https://codexradar.com/) 24h / 48h reset 预测。
- Codex IQ 每日探针结果。

应用默认中文；下拉菜单里可以切换 English。Codex、IQ、Reset、Prediction、Radar 这类英文术语会保留，因为它们在产品里更清楚。

## 通知

应用会在这些情况发送 macOS 通知：

- 速蹬窗口开启。
- CodexRadar 记录到 reset；顶部直接显示“上次 reset 时间是 ...”，本机额度仍看 `Codex 额度`。
- 周额度低于 30%。
- 周额度低于 15%。
- 周额度从低位恢复。
- Prediction 升到 high，或 CodexRadar 明确标记 should_notify。
- Codex IQ 进入 red 或低于 80。

通知声音默认关闭，可以在下拉菜单里打开。首次启动会把历史 reset 窗口记为已见过，避免补发旧通知；如果首次启动时正好处在速蹬窗口中，仍然会提醒。

## 更新

自动更新默认开启。应用启动 5 秒后会先检查一次，之后每 6 小时检查一次最新 GitHub Release，下载 ZIP，校验 release 里的 SHA256，然后替换已安装的 app bundle 并自动重开。

如果下载、校验或安装失败，应用会保留当前版本并在菜单里显示失败原因。安装脚本也会先备份旧版；如果替换失败，会恢复并重新打开旧版。对同一个刚刚安装失败的版本，自动更新会暂停短期重试，手动 `检查更新` 仍可立即重试。

底部工具栏固定提供 `刷新`、`Radar`、`Codex`、`GitHub` 和 `退出`，方便常用跳转不用滚动菜单。

版本更新区还提供：

- `检查更新`：立刻检查并安装新版本。
- `Changelog`：打开最新 release notes。
- `Prompts`：打开开源的 prompt log。
- `GitHub ★`：打开仓库页面。

如果只想手动更新，可以在下拉菜单关闭 `自动更新`。

## Codex Skill

仓库里带了一个 repo 内 skill：[CodexRadar Sync](skills/codex-radar-sync/SKILL.md)。当 CodexRadar 页面或 JSON 数据格式变化时，可以让 Codex 执行这个 skill：它会检查 CodexRadar 最新主页和公开端点，比较字段变化，更新 Swift 解码和 macOS 菜单映射，并在发版前跑完整 UI/数据检查。

## 调试预览

下拉菜单里有 `预览` 分段控件，可以本地查看不同状态：

- `Live`：真实数据。
- `速蹬`：速蹬窗口 UI，包括红色状态栏和红色提示。
- `Reset`：CodexRadar 记录到 reset 的 UI。
- `限额`：本机限额 UI。

预览只影响 UI 展示；真实通知和去重仍使用 live 数据。

也可以用环境变量启动：

```bash
CODEX_RADAR_PREVIEW=speedWindow swift run CodexRadarSentinel
```

可选值是 `live`、`speedWindow`、`resetConfirmed`、`blocked`。

## 数据来源

Codex Radar Sentinel 读取这些公开 CodexRadar 入口：

- [CodexRadar homepage](https://codexradar.com/)
- [current.json](https://codexradar.com/current.json)：包含速蹬窗口、reset、Prediction 和 model IQ。
- [feed.xml](https://codexradar.com/feed.xml)

本机额度读取 Codex app-server：

```json
{"method":"account/rateLimits/read"}
```

当响应里存在 `rateLimitsByLimitId.codex` 时，优先使用这个 bucket。5 小时窗口显示为 `短窗`，10,080 分钟窗口显示为 `周额度`。

## 手动安装

从最新 GitHub Release 下载 `.dmg`，打开后把 `Codex Radar Sentinel.app` 拖到 `Applications`。

`.zip` 里包含同一个 app bundle，适合喜欢手动复制的用户。

## 本地运行

构建普通 macOS `.app`：

```bash
./scripts/build_app.sh
open ".build/Codex Radar Sentinel.app"
```

开发时也可以直接运行：

```bash
swift run CodexRadarSentinel
```

如果 Codex 不在默认路径，可以设置：

```bash
CODEX_RADAR_CODEX_PATH=/path/to/codex
```

## 开发

运行测试：

```bash
swift test
```

发版前做 live 数据和 UI 检查：

```bash
./scripts/check_release_readiness.sh 0.1.23
```

构建 release 包：

```bash
swift build -c release
./scripts/build_app.sh
./scripts/package_release.sh 0.1.23
```

更新 README 状态栏和菜单截图：

```bash
./scripts/update_readme_screenshots.sh
```

这个脚本会启动真实 app 并裁剪 macOS 状态栏 item，也会调用 app 自己的文档截图模式渲染完整菜单界面，并从完整菜单生成 News 小图。因此需要本机允许 System Events 读取辅助功能信息，并允许屏幕截图。

重新生成 macOS 图标：

```bash
./scripts/generate_app_icon.sh
```

## 鸣谢

Codex Radar Sentinel 之所以能成立，是因为 [CodexRadar](https://codexradar.com/) 提供了清晰的公开信号，包括 Codex 速蹬窗口、reset、reset 预测、RSS 事件和 model IQ。本应用只是把这些公开信号和用户本机 Codex 额度状态整合成一个 macOS 菜单栏工具。

Codex Radar Sentinel 与 CodexRadar 或 OpenAI 没有关联。
