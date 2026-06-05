# Prompt Log

这份文件收录 Codex Radar Sentinel 从想法到实现过程中，用户直接发给 Codex 的产品需求和反馈 prompt。

为了让项目更透明，也为了保留一点“这个小工具是怎么被磨出来的”的现场感，我们把这些 prompt 一起开源。内容做了最小必要整理：

- 去掉了时间戳。
- 去掉了本地文件路径、截图缓存路径、账号环境、仓库内部操作说明和其他可能带来安全风险的信息。
- 只保留用户直接写给 Codex 的产品需求、设计反馈、验证要求和开源要求。
- 截图只用文字说明代替，不在这里复刻原始图片路径。

## Maintenance Rule

从这条规则开始，后续每个由用户 prompt 驱动的仓库变更都要维护两件事：

- 在 `PROMPTS.md` 追加对应的用户 prompt，继续遵守上面的脱敏规则。
- 在下面的映射表里记录 prompt 和实际 commit 的关系；commit 必须写成可点击的 GitHub commit 链接。功能或文档 commit 的 commit message 应该带上 `Prompt-Id: N` trailer，方便从 `git log` 反查。

Git commit 的 hash 由提交内容决定，所以一个 commit 无法在自己的文件内容里稳定写入自己的最终 hash。遇到“新增 prompt log 本身”这种提交时，用 commit message 的 `Prompt-Id` 先建立关联，也可以先放一个可点击的 `Prompt-Id` commit search 链接，并在下一次 prompt log 维护时把已经确定的 commit 直链补进表里。

## Prompt To Commit Map

| Prompt | Commit(s) | Notes |
| --- | --- | --- |
| 1-4 | [27677cc](https://github.com/WineChord/codex-radar/commit/27677cc) | 初版 macOS 菜单栏 app。 |
| 5 | [e832074](https://github.com/WineChord/codex-radar/commit/e832074) | release 包和安装能力。 |
| 6 | [ae5eed9](https://github.com/WineChord/codex-radar/commit/ae5eed9) | 紧凑状态栏。 |
| 7 | [7e08bf2](https://github.com/WineChord/codex-radar/commit/7e08bf2) | 速蹬预览、强调样式和 app branding。 |
| 8 | [69e55fd](https://github.com/WineChord/codex-radar/commit/69e55fd) | 双语、按钮说明、可配置项。 |
| 9 | [72ecc5a](https://github.com/WineChord/codex-radar/commit/72ecc5a) | 自动更新和更紧凑的文档展示。 |
| 10 | [b0fff69](https://github.com/WineChord/codex-radar/commit/b0fff69) | 中英文 README 和安装 prompt。 |
| 11 | [5c5aecf](https://github.com/WineChord/codex-radar/commit/5c5aecf) | README 开头 CodexRadar credit。 |
| 12 | [c8b5f7a](https://github.com/WineChord/codex-radar/commit/c8b5f7a) | 中英文完整菜单截图。 |
| 13 | [2a0e886](https://github.com/WineChord/codex-radar/commit/2a0e886) | GitHub API 403 fallback、高清菜单截图、更新验证。 |
| 14 | [bf85a69](https://github.com/WineChord/codex-radar/commit/bf85a69) | reset 绝对时间、手动更新测试、更新循环修复。 |
| 15 | [d2e2a09](https://github.com/WineChord/codex-radar/commit/d2e2a09) | 更新安装失败 fallback。 |
| 16 | [b82b960](https://github.com/WineChord/codex-radar/commit/b82b960) | prompt log 开源。 |
| 17 | [c299a80](https://github.com/WineChord/codex-radar/commit/c299a80), [c9941ea](https://github.com/WineChord/codex-radar/commit/c9941ea) | prompt/commit 映射维护规则；commit message 带 `Prompt-Id: 17`。 |
| 18 | [fab26dc](https://github.com/WineChord/codex-radar/commit/fab26dc), [`Prompt-Id: 18 commits`](https://github.com/WineChord/codex-radar/search?q=%22Prompt-Id%3A+18%22&type=commits) | commit 链接要求；直达链接加可点击 search 链接覆盖后续 bookkeeping。 |
| 19 | [099b672](https://github.com/WineChord/codex-radar/commit/099b672), [`Prompt-Id: 19 commits`](https://github.com/WineChord/codex-radar/search?q=%22Prompt-Id%3A+19%22&type=commits) | 菜单更新区增加可点击 PROMPTS.md 入口。 |
| 20 | [066d2ea](https://github.com/WineChord/codex-radar/commit/066d2ea), [`Prompt-Id: 20 commits`](https://github.com/WineChord/codex-radar/search?q=%22Prompt-Id%3A+20%22&type=commits) | CodexRadar 数据格式同步 skill、IQ 小数兼容和发版前 live/UI 检查。 |
| 21 | [2e41bb5](https://github.com/WineChord/codex-radar/commit/2e41bb5), [`Prompt-Id: 21 commits`](https://github.com/WineChord/codex-radar/search?q=%22Prompt-Id%3A+21%22&type=commits) | 状态栏 IQ 默认截断为整数，并提供精确小数显示开关。 |
| 22 | [4ec0c87](https://github.com/WineChord/codex-radar/commit/4ec0c87), [`Prompt-Id: 22 commits`](https://github.com/WineChord/codex-radar/search?q=%22Prompt-Id%3A+22%22&type=commits) | 精简 README 中给 Codex 的自然语言安装 prompt。 |
| 23 | [56726d7](https://github.com/WineChord/codex-radar/commit/56726d7), [`Prompt-Id: 23 commits`](https://github.com/WineChord/codex-radar/search?q=%22Prompt-Id%3A+23%22&type=commits) | 状态栏增加可选 5h 短窗额度 segment，默认关闭。 |
| 24 | [1a60bdf](https://github.com/WineChord/codex-radar/commit/1a60bdf), [`Prompt-Id: 24 commits`](https://github.com/WineChord/codex-radar/search?q=%22Prompt-Id%3A+24%22&type=commits) | 进一步压缩 README 中给 Codex 的下载安装 prompt。 |

## Prompts

### 1. 初始想法

```text
https://codexradar.com/

你读读这个网站，看看我们能在上面做一个什么辅助或者应用之类的，能让我们在 codex 界面什么地方或者是 mac 上什么地方或者是怎么样，能够非常及时地得到应该“速蹬“以及 limit 确实发生了 reset（而不是需要我自己去看当前的剩余额度这样），你发挥你的想象力，怎么才是最方便最佳的做法？
```

### 2. 菜单栏 app、IQ 和产品设计

```text
macOS 菜单栏常驻小工具 这个开发需要什么东西吗？本地环境你看支持开发吗？以及开发完了之后，本机支持运行吗（不需要发布就能运行是吧）。对了，IQ 那个我感觉也可以利用起来，这个页面能利用的并且比较友好的，我感觉是不是都可以尝试利用下，好好做做产品设计
```

### 3. 周额度百分比

```text
我还想让状态栏常驻显示我现在的 week 剩余的 token 百分比，把这个也加上吧
```

### 4. 开始实现

```text
那你设计产品和实现，好好搞吧，用 git 做管理，直接在当前项目做各种 git add commit 直接 push 到 main 分支上。
```

### 5. Credit、release 和本机安装

```text
对了，把那个 https://codexradar.com/ 链接都带上，搞上鸣谢之类的，该 cite 的都 cite，push to main，对了，可以搞 release 啥的，release 能安装的包让用户直接安装使用。你直接在我现在的机器上直接尝试帮我安装好？并自己调试调试看看效果啥的是否符合预期？
```

### 6. 状态栏要更紧凑

```text
感觉有些东西都挡住了。而且感觉状态部分太占地方了，可不可以直接就是显示 97%/75/低 这种，然后加上合理美观高可读的颜色

[附图：状态栏和下拉菜单 UI 反馈截图，原始图片路径已隐去]
```

### 7. 字体、图标、速蹬强调和 README 截图

```text
然后下拉的字体感觉也有点小，改大一点，并且看看怎么可以调节。以及这个 macos app 的图标太没有辨识度了。。。。你看看怎么优化一下？你不是有图片生成工具吗？发挥你的聪明才智，生成一个极具美感符合 macos 设计的 app 图标。对了，需要速登的时候你要不要搞个什么全红醒目提示的效果啥的（可以手动关，也可以默认自动过合理的时长关掉（比如确实 reset 或者确实不会提前 reset 等）），或者你用第二张截图的那个作为 macos app  的图标？你看看怎么合适怎么来？第三张截图里面中间这种红色总感觉有点跳。。。对了此外，有没有办法让我怎么 debug 就是手动触发看一下假如变成速登啥的具体效果会是啥样子？对了对了，你可以把这个 app 的状态栏以及点击之后的下拉栏啥的内容做截图，放到 github readme 里面明显的地方来吸引用户（之后有任何 UI 更新都动态更新截图）？此外就是下拉里面是不是要在比较靠上的地方就告诉用户这是三个值都是啥意思，尤其中间是表示 IQ，不在开始就标注下用户可能不知道状态栏这三都是啥意思

[附图：macOS app 图标、状态栏图标和颜色反馈截图，原始图片路径已隐去]
```

### 8. 双语、按钮说明和可配置项

```text
下面这一排按钮也没有说明是表示什么意思的，此外就是感觉这些按钮是不是比例不太美观？你看呢？对了支持下切换中英文双语呗，默认中文，然后中文的时候除了一些英文术语确实用英文非常方便，通用描述用中文就好。对了像状态栏的不同状态，你也都截图放到 readme 里面展示效果，比如正常啥样子，速登的时候会显示的效果等（要放声音吗？是不是可以默认不放声音，可以让用户开启？），展示不同阶段都是什么样子的。对了，支持下状态栏可以选择显示这三个指标中的哪几个，比如用户可以选择只显示 97%/低 这种，灵活一点，但是也要好用一点，用户友好一点。对了，里面下拉的展示的东西要尽可能地清晰易懂，让用户能够很好地理解，降低使用门槛，就是一看就能懂的那种。然后各种可以做更改可以配的地方可以适度地放出来让用户能自己改改配置等，也先不用太复杂，关注用户好用易用易懂非常清晰明了。

[附图：底部按钮区域反馈截图，原始图片路径已隐去]
```

### 9. 状态栏截图、XL 字体和自动更新

```text
你把这几个实际展示在 status line 上的效果截图放到 readme 里呗，避免用户以为会在 status bar 上面占据过大的空间。此外就是这里的第四章节图字体切换成 XL 之后，整体感觉不太协调不太美观，好好修修。此外，加个自动更新版本的功能？可以选择是否自动更新，默认选择“是”，自动更新的话就是检查有最新版本就会直接更新到最新版本（不用用户点确认以及感知之类的，然后有地方可以点击查看 changelog 啥的，并且跳转到 github 啥的（求 star 啥的你懂的）），然后也可以手动点击哪里触发更新啥的。你懂，都好好做做

[附图：不同状态栏样式和 XL 字体布局反馈截图，原始图片路径已隐去]
```

### 10. 中英文 README 和安装 prompt

```text
github 上搞成中英文 readme，点击可以切换，默认中文。对了，在 readme 很开头的地方可以直接教用户怎么让 codex 帮他装我们当前的这个项目（直接让用户把某个什么 prompt 复制给 codex 然后执行（需要让 codex 有一些对应的权限）），中文的时候显示中文 prompt，英文的时候显示英文的 prompt，然后 readme 里面的各种截图也用对应语言的。最好是实际的跑起来之后在 mac 系统上的截图。。。。你懂。。。。尤其是我给你的截图里面展示的，最好是真实的 status bar 里面的对应状态的截图。。。千万不要自己手画，只展示我们本身的 status bar 就行了，就是最多那三个数字，右边的那些其他的其实不需要展示

[附图：README 截图展示方式反馈图，原始图片路径已隐去]
```

### 11. README 开头给足 CodexRadar credit

```text
在 readme 开头就给满 credit 给 https://codexradar.com/ ，不要说什么无需打开之类的话你懂的（懂？）
```

### 12. 全量中英文截图和尺寸维护

```text
这种相关的中英文截图全量带上吧并实时维护？现在已经有的 status bar 的截图我非常满意，就不需要动了，整体的这个界面中英文啥的最好截图带到 readme 里面，并且注意尺寸长宽高等你懂

[附图：完整菜单截图反馈图，原始图片路径已隐去]
```

### 13. 高清菜单截图和 HTTP 403 更新问题

```text
上一条那个，我建议你在我的高清的屏幕上去截图那两张中英文菜单图。此外你看看我现在给你的截图，更新失败显示 http 403 会是因为什么？现在自动更新的时间间隔是多少？有怎么测试过确实可以自动更新或者手动触发更新可以成功吗？比如你去发一个版本，然后在本机上试试更新的功能，看看能不能运行成功

[附图：更新失败 HTTP 403 截图，原始图片路径已隐去]
```

### 14. Reset 绝对时间和手动更新测试

```text
这里搞成不但显示几天后多少小时后，也同样显示具体的日期时刻吧。然后你顺便测测通过点击手动触发更新是否有问题。此外，好像开机更新会陷入循环，不断下载最新然后更新。。。。。

[附图：额度 reset 时间显示反馈截图，原始图片路径已隐去]
```

### 15. 更新失败 fallback

```text
我感觉也要做一些 fallback，避免出现因为一些原因更新失败的话反复退出重启这种 bug？对了，帮我确认下假如背景的自动更新触发的时候，因为一些原因失败的话，不会导致这个 status bar 出错退出就行了，你懂我意思？
```

### 16. 开源 prompt log

```text
现在我决定做非常彻底的开源，那就是把我们造这个项目我写给你的所有 prompt（包括我现在写的这条），也全部开源到这个仓库，并且要在 readme 里面给个显眼的引用位置，标注一下算是博大家一个开心哈哈哈，你懂我意思？懂？好好揣摩我想要干什么，好好干！直接 push to main！对了，要注意隐去一些可能导致安全问题的一些东西，并且只记录包含我直接给你发的给你写的 prompt。对了，时间信息可以隐去不要带（你懂吗？你懂的）。
```

### 17. Prompt 和 commit 一一映射

```text
对了，还要记上这样一个点，以后每个 commit 或者啥东西，也都把对应的 prompt 给带到仓库那个记录 prompt 的地方（并和实际的 commit 做一一映射）
```

### 18. Commit 映射要可点击

```text
commit 要求是可以点击的链接
```

### 19. 菜单里加 PROMPTS.md 跳转

```text
这里把 prompts.md 也带上能点击跳转的？
```

### 20. CodexRadar 数据格式同步 skill、IQ 修复和发版检查

```text
数据格式等有更多的信息更新，你可以再看看怎么和最新的网站各种数据对齐。这样，我们搞一个 skill 存在当前 repo 中吧，这个 skill 的能力就是当你执行这个 skill 的时候，可以自己去对应的网站 https://codexradar.com/ 上去看最新的数据格式等是否有什么变化之类的或者是否网站功能本身有什么增加之类的，然后把相关的东西更新映射到我们的现在这个 mac 控件上。这次版本更新后，中间的 IQ 好像显示有问题。你每次发版之前都要系统查一下整体的效果看看是否有异常。懂？

[附图：CodexRadar IQ 62.5 与菜单栏 IQ 显示 -- 的反馈截图，原始图片路径已隐去]
```

### 21. 状态栏 IQ 默认整数并可切换小数

```text
我感觉 status bar 展示可以默认做整数截断以节约空间，然后点击下拉里面可以展示精确值。（给选项让用户可以切换 status bar 显示精确的小数数字？默认截断只显示整数）
```

### 22. 精简 Codex 安装 prompt

```text
我感觉是不是可以极致精简一下仓库里的自然语言安装的指令？你要考虑的对象是 codex，他是非常聪明的，你应该不需要写很多 prompt？懂？但是也要确保安装任务能够完成
```

### 23. 状态栏可选 5h 短窗

```text
实现这个需求：状态栏显示的内容多加一个 5h 短窗的[旺柴]，默认不打开，可以手动打开

[附图：状态栏显示开关区域反馈截图，原始图片路径已隐去]
```

### 24. 极致精简下载安装 prompt

```text
用于下载安装的 prompt 是否还能更加简短，达到极致的 token efficiency，同时保证执行不会有任何问题
```
