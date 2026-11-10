# 周计划

「周计划」是一款原生 macOS 应用，用周表整理日常工作，用月历回查历史安排，用 DDL 倒计时跟踪会议、交稿和长期待办。支持 macOS 14 及以上的 Apple 芯片和 Intel Mac。

## 功能

- **周计划**。按周一到周日排布。拖动日期与待办之间的分隔线可调整列宽，应用会记住列宽设置。点「＋」添加周目标或当天待办。单击任务文字可在末尾续写，按回车保存，双击可打开详细编辑和删除。每点一次每日待办左边的方框，状态就按「空框（待办）→ 绿勾（已完成）→ 红叉（未完成）→ 空框」切换。完成时文字划横线。
- **月历**。点周表顶部的「月历」，在同一个窗口查看整月。点月份标题两侧的箭头切换上个月或下个月。日期格标出待办和 DDL 的数量。选中日期后可查看当天详情，点「打开所在周」回到周表并定位到那一天。
- **DDL**。周表顶部列出全部截止事项，未完成项在前，条目多时可在清单内滚动。点方框勾选，点名称编辑，点「＋」添加。每条都可以关闭「显示倒计时」，关闭后仅显示截止日期和时间。
- **系统原生小组件**。WidgetKit 提供中号和大号组件，显示本周目标、今日待办和 DDL。点小组件打开编辑窗口。组件的位置和外观由 macOS 管理。
- **应用桌面卡片**。菜单栏的日历图标可显示或隐藏应用自己的可拖动卡片，也可设置登录时打开应用。

## 安装与添加小组件

正式发布后，从 GitHub Releases 下载 macOS 通用 ZIP，解压后把「周计划.app」拖进「应用程序」，并打开一次。更新前先保存当前编辑并退出旧版本。 [GitHub Releases](https://github.com/liao1123/weekly-plan/releases)

在系统识别扩展的版本上，右键桌面空白处，选择「编辑小组件」，搜索「周计划」，再拖动所需尺寸到桌面。也可以从通知中心添加。 [Apple 小组件使用说明](https://support.apple.com/en-gb/guide/mac-help/mchl52be5da5/mac)

默认的本地构建使用临时签名，预览包可用于检查编辑窗口和包结构。1.4.2 已在 macOS 26.6.2 用 Apple Development 签名从 ZIP 重装验证，系统桌面小组件能读取本周目标和今日待办，点按可打开应用。对外提供下载的安装包使用 Developer ID 签名和 Apple 公证。 [Apple 签名与公证说明](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)

## 本机构建

在装有 Swift 6 工具链的 Mac 上运行：

```sh
sh test.sh
sh build.sh
```

生成的 App 在 `build/周计划.app`。App 内嵌 `WeekPlanWidget.appex`。运行 `sh package.sh` 会在 `dist/` 生成包含两种架构的 `-native-preview.zip`。安装 App 不需要安装 Xcode、模拟器或其他运行时。

测试系统原生小组件时，可使用钥匙串里已有的 Apple Development 或 Developer ID Application 身份重新构建。构建脚本按签名团队配置 App Group，用于在应用与小组件之间共享摘要。开发签名可在 Xcode 的「Settings → Accounts → Manage Certificates」配置。以下名称需要替换为本机签名身份。 [Apple App Group 说明](https://developer.apple.com/documentation/xcode/accessing-app-group-containers)

```sh
WEEKPLAN_SIGNING_IDENTITY='Apple Development: 你的签名身份' sh build.sh build/signed
```

准备公开发布包时，使用 Developer ID Application 身份和预先保存在钥匙串里的 `notarytool` 配置：

```sh
WEEKPLAN_SIGNING_IDENTITY='Developer ID Application: 你的签名身份' \
WEEKPLAN_NOTARY_PROFILE='weekly-plan-notary' \
sh package.sh
```

完成公证后，脚本生成 `-universal.zip`。发布时从本地验收通过的同一份源码构建，将 ZIP 作为对应版本的 GitHub Release 附件。

## 数据与隐私

计划和 DDL 保存在当前 Mac 的「应用程序支持」目录，旧版本保存的备注也留在原数据文件中。系统小组件通过 App Group 读取一份本机摘要，其中包含当前和以后日期的有限条目。应用在本机处理这些数据，小组件内容随系统隐私设置脱敏。

项目源码包含 Swift 文件、资源、测试和打包脚本。发布前应核对提交文件及 ZIP 清单。个人计划、摘要文件、构建缓存、日志和签名凭据均列入忽略规则。签名证书及公证凭据保存在本机钥匙串。演示和截图使用示例数据。
