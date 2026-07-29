# Codex Radar Sentinel Windows 版

这是 Codex Radar Sentinel 的原生 Windows 10 1809+/11 状态版本，使用 .NET 8 WinForms 和 Windows API。正式包是自包含应用，用户不需要另外安装 .NET。数据口径、模块顺序、19 组 Intelligence Efficiency、Insights、重置卡保护和降级行为与 macOS 版对齐；窗口和任务栏交互遵循 Windows 习惯。

## Windows 与 macOS 包严格隔离

两个平台使用完全不同、可精确匹配的 Release 资产名：

- Windows x64：`CodexRadarSentinel-<version>-Windows-x64.zip` 与 `CodexRadarSentinel-<version>-Windows-x64.sha256`
- Windows ARM64：`CodexRadarSentinel-<version>-Windows-arm64.zip` 与 `CodexRadarSentinel-<version>-Windows-arm64.sha256`
- macOS 资产名含 `-macOS`，Windows 安装器绝不会选择它们。

安装器只接受与本机架构唯一匹配的 Windows ZIP，随后依次校验 Release SHA256、包内 `release-manifest.json` 的 `platform: windows`/runtime，以及 exe 自身的 SHA256。Release 缺包、重名、校验和缺失或冲突、架构错误、只有 macOS 包时，安装会在改动现有程序前安全失败。

## 让 Codex 帮你安装

如果你正在 Windows 上使用 Codex 桌面版，可以直接复制下面这段 prompt 给 Codex。需要允许 Codex 访问网络和执行 PowerShell；默认是当前用户安装，不需要管理员权限。

```text
只安装 Windows 版 Codex Radar Sentinel：先确认本机是 Windows 10 1809+ 或 Windows 11，并识别 x64/ARM64；下载并检查 https://raw.githubusercontent.com/WineChord/codex-radar/main/windows/install.ps1，只允许它从 https://github.com/WineChord/codex-radar/releases/latest 选择与本机唯一匹配的 CodexRadarSentinel-<version>-Windows-x64.zip 或 CodexRadarSentinel-<version>-Windows-arm64.zip 及对应 .sha256，严禁使用 macOS 的 .dmg、带 -macOS 的 ZIP 或另一架构。如果没有唯一匹配的 Windows 资产和校验文件，停止并告诉我，绝不使用其他平台或架构的包代替。校验 Release SHA256、包内 platform=windows/runtime manifest 和 exe SHA256 后，按当前用户安装到 %LOCALAPPDATA%\Programs\CodexRadarSentinel，创建开始菜单快捷方式，启动并确认进程以及右下角通知区域图标或任务栏文字；需要权限时问我。
```

Codex 可以直接使用仓库维护的 [`windows/install.ps1`](install.ps1)，其中已经实现平台/架构隔离、校验、回滚和进程检查。

## 直接安装

先下载脚本以便检查，再通过 Windows PowerShell 运行：

```powershell
$installer = Join-Path $env:TEMP "install-codex-radar.ps1"
Invoke-WebRequest -UseBasicParsing "https://raw.githubusercontent.com/WineChord/codex-radar/main/windows/install.ps1" -OutFile $installer
powershell.exe -NoProfile -ExecutionPolicy Bypass -File $installer
if ($LASTEXITCODE -ne 0) { throw "Codex Radar Sentinel 安装失败，退出码：$LASTEXITCODE" }
```

上面的 `raw.githubusercontent.com/.../main/windows/install.ps1` 只有在该文件已经合并到仓库默认分支后才会存在；尚未合并的开发分支会返回 404。已经克隆本仓库时可直接运行当前检出的脚本：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\windows\install.ps1
```

如果希望开机启动，显式增加 `-StartWithWindows`：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File $installer -StartWithWindows
```

默认安装目录是 `%LOCALAPPDATA%\Programs\CodexRadarSentinel`。开始菜单快捷方式和可选开机启动项也都属于当前用户；安装器不会写入 `Program Files`、HKLM 或其他用户目录。升级时只停止从这个安装目录运行的 Codex Radar 进程。如果安装或启动检查失败，会恢复原文件、快捷方式、启动项以及升级前的运行状态。

本地开发调试的启动方式是：
```powershell
Set-Location Path\to\your\codex-radar

dotnet run --project .\windows\CodexRadar.Windows\CodexRadar.Windows.csproj -c Release
```

## 卸载

运行安装目录内的卸载脚本。默认会删除当前用户的程序、快捷方式、启动项和缓存设置：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\Programs\CodexRadarSentinel\uninstall.ps1"
```

增加 `-KeepData` 可以保留设置和脱敏后的重置卡元数据。

## 功能与系统要求

- 可在“通知区域图标（当前位置）”和“任务栏文字（输入法/通知区域左侧）”之间切换；默认沿用通知区域图标。
- 任务栏文字直接常驻显示与 macOS 相同的可配置摘要段；它是安全的无激活圆角窗口，不注入或修改 Explorer。
- 两种位置都支持左键打开或收起雷达面板，以及右键打开包含退出的完整菜单。
- 通过 `codex app-server --listen stdio://` 读取本机周额度和 5 小时额度。
- 在 `Codex 额度` 中记录真实本机周额度余量，提供 24 小时、7 天和 30 天曲线；支持鼠标悬停/拖动、左右键逐点查看，明确标出观测到的重置和数据断档。历史默认显示但折叠，隐藏后仍继续后台采样。
- 点击底部 `布局` 会在当前雷达窗口内进入紧凑编辑器；可拖动或用箭头排序，并分别设置模块及子项是否显示、是否默认展开。当前结论、紧急提示和连接错误始终保留，需要处理的重置卡或失败更新会临时置顶且不能隐藏。
- 展示 CodexRadar 公告、分布式 Model IQ、逐任务成本/耗时/通过数/体感、19 组 Intelligence Efficiency、额度雷达、重置雷达、Fast 雷达、社区 Prompt、场景建议与降智预警，并保留旧数据契约兼容。
- Insights 只接受已知 schema 和合法时间戳；网络、空数据、格式错误或时间回退时保留最近一次有效结果，不用损坏的新响应覆盖界面。
- “到期前自动使用重置卡”严格默认关闭。只有用户确认授权、账号与完整卡片集合仍一致、时钟连续、目标唯一且进入到期前约 30 分钟窗口时才会发送请求；未决请求先只读对账，账号/卡片/时钟变化或存储异常会撤销授权并安全关闭。
- 60 秒自动刷新、Windows 通知、中英文界面、多显示器定位、Per-Monitor DPI 和单实例保护；面板卡片采用原子替换，相同数据只更新时间，不会在后台刷新时清空成白屏。
- Windows 10 1809（build 17763）或更高版本，或 Windows 11；支持 x64 和 ARM64。
- 本机额度需要已安装并登录 Codex CLI。若不在 `PATH`，可用 `CODEX_RADAR_CODEX_PATH` 指向 `codex.exe` 或 `codex.cmd`。

找不到 Codex CLI 时，CodexRadar 公开数据仍可使用，只有本机额度区显示连接提示。

状态位置可在面板的“显示与提醒”模块打开 `设置`，进入 `状态栏` 页切换，也可右键当前状态入口后从 `状态显示位置` 切换。“通知区域图标”是否被收入 `^` 溢出区由 Windows 决定；“任务栏文字”无需点开溢出区，会自动贴靠在当前任务栏输入法/通知区域左侧，并在全屏应用时隐藏。

本机额度通过无 BOM UTF-8 的 JSON Lines 与 `codex app-server` 通信；如果首条 RPC 被写入 BOM，Codex 会拒绝初始化，周额度和 5h 都会显示 `--`。Windows 版的自检会防止这个协议问题回归。面板打开时会先显示已经缓存的界面，再合并后台数据，网络等待和 Codex 进程扫描不会阻塞状态区点击。每分钟刷新若只有获取时间变化，只更新顶部时间；内容确实变化时，先在隐藏的候选控件树中完整构建和布局，成功后再一次性替换旧内容。构建异常会保留旧界面并等待下次刷新，不会清空成白屏。

## 本地开发与测试

```powershell
dotnet run --project .\windows\CodexRadar.Windows\CodexRadar.Windows.csproj

dotnet build .\windows\CodexRadar.Windows\CodexRadar.Windows.csproj -c Release
dotnet run --project .\windows\CodexRadar.Windows\CodexRadar.Windows.csproj -c Release --no-build -- --self-test
dotnet run --project .\windows\CodexRadar.Windows\CodexRadar.Windows.csproj -c Release --no-build -- --ui-self-test
dotnet run --project .\windows\CodexRadar.Windows\CodexRadar.Windows.csproj -c Release --no-build -- --taskbar-ui-self-test
```

请从普通 Windows PowerShell、开始菜单或资源管理器启动 GUI。如果让 Codex 桌面版代为运行开发构建，需要允许它在主机 Windows 用户上下文启动 GUI 和访问网络；隔离用户上下文看不到真实用户的 Codex 登录态，此时公开雷达仍可用，但本机周额度/5h 会显示连接提示。

## 构建 Windows Release 资产

分别生成自包含压缩包和校验和：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\windows\build.ps1 -Runtime win-x64
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\windows\build.ps1 -Runtime win-arm64
```

版本默认读取项目版本，发布自动化也可传入 `-Version 0.1.62`。Release 资产版本采用 `major.minor.patch`，可带预发布后缀；脚本会刻意拒绝 `+build` 元数据，避免更新器查找资产时产生歧义。把 `artifacts\windows\release` 中对应的两个文件原名上传，例如：

```text
CodexRadarSentinel-0.1.62-Windows-x64.zip
CodexRadarSentinel-0.1.62-Windows-x64.sha256
CodexRadarSentinel-0.1.62-Windows-arm64.zip
CodexRadarSentinel-0.1.62-Windows-arm64.sha256
```

`-FrameworkDependent` 仅供开发，会刻意跳过 Release 资产生成，避免把依赖外部 .NET Runtime 的包误发成自包含正式包。

每个 ZIP 根目录严格只有三个条目：`CodexRadarSentinel.exe`、`uninstall.ps1` 和 `release-manifest.json`。schema 1 清单包含 `product`、`platform`、`runtime`、`architecture`、`version`、`executable`、`executable_sha256`、`uninstaller`、`uninstaller_sha256`、`minimum_windows_build`、`framework_dependent` 和 `generated_utc`。安装器/更新器应拒绝缺失、额外或嵌套条目，不能递归搜索一个看似可用的 exe。

## 兼容性与发布验证

项目目标框架固定为 `net8.0-windows10.0.17763.0`，并把平台兼容性警告作为构建错误。`.github/workflows/windows.yml` 在 Windows x64 和原生 Windows 11 ARM64 runner 上执行编译、离线协议/隐私回归、WinForms 视觉烟雾测试、自包含打包以及包内原生自检。

每个准备发布的二进制还应在对应系统上生成可复现证据：

| 目标 | 运行方式 |
| --- | --- |
| Windows 10 1809+ x64 | 实机或虚拟机运行 `validate-compatibility.ps1 -Target windows-10-x64` |
| Windows 11 x64 | x64 runner、实机或虚拟机运行 `-Target windows-11-x64` |
| Windows 11 ARM64 | 原生 ARM64 runner 或设备运行 `-Target windows-11-arm64` |

```powershell
.\windows\verify-release.ps1 -Runtime win-x64 -RunSelfTest
.\windows\validate-compatibility.ps1 `
  -Target windows-11-x64 `
  -Executable .\artifacts\windows\win-x64\CodexRadar.Windows.exe
```

验证脚本检查操作系统 build、进程架构、核心自检、中英文 M/L/XL 面板视觉、真实 Explorer 任务栏放置与右键退出入口、ZIP 条目、manifest、双层 SHA256 和 PE 架构，并把 JSON 证据写入 `artifacts\windows`。Windows 10 的真实桌面行为仍需在 Windows 10 实机/虚拟机执行该脚本；仅在较新系统编译不能替代这一步。

## 包信任与 SmartScreen

当前社区构建可能尚未做 Authenticode 签名，因此程序积累信誉前，Windows SmartScreen 首次运行时可能提示确认。安装器会对未签名程序给出明确警告、拒绝任何无效的 Authenticode 签名，并依赖精确资产名、Release SHA256 和包内文件 SHA256 校验。它能确认下载内容与该 GitHub 仓库发布的内容一致，但若 GitHub Release 本身被接管，并不等价于固定的代码签名身份。未来正式发布流程应在打包前对 `CodexRadarSentinel.exe` 做 Authenticode 签名；不要重命名或二次打包已签名资产。

## 隐私

只有开启或手动刷新重置卡查询时，应用才读取 `%USERPROFILE%\.codex\auth.json`；根级或 `tokens` 内的 `access_token`/`accessToken` 只发送到 ChatGPT reset-credit 接口，请求后立即丢弃，不写入设置、日志或保护状态。

卡片缓存仅保存标题、状态、本地时间、类型和原始 ID 的完整 SHA-256 指纹；界面最多显示指纹前 8 位。指纹不可逆，原始 ID 及其后缀不会落盘。自动使用功能的授权、账本、对账记录和撤销标记仅包含账号/卡片指纹、时间、随机 UUID/幂等键和状态，不保存访问令牌、邮箱或原始卡片 ID。加载旧版含 `IdSuffix` 的设置时会立即迁移并覆盖旧字段。

额度历史独立保存为 `%LOCALAPPDATA%\CodexRadarSentinel\weekly-quota-history-v1.json`，只含采样时间、周额度剩余百分比和服务端 reset 时间，最多保留 31 天。目录、数据文件和锁文件限制为当前 Windows 用户；写入使用独占锁、同目录临时文件、写透落盘和原子替换。损坏的历史文件只会显示安全警告，绝不会被自动覆盖，也不会上传。

“开机启动”只把安装后的 exe 路径写入 `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`。应用内额外提示音默认关闭；通知区域气泡的系统声音仍由 Windows 通知与专注设置控制。

[English documentation](README.md)
