# 周计划

一款原生 macOS 桌面计划工具。用一张周表管理本周目标、每日待办和备注，用顶部的 DDL 跟踪会议和交稿时间。点「月历」可以按日期查看安排，再跳回所在周编辑。

## 下载与使用

在 [GitHub Releases](https://github.com/liao1123/weekly-plan/releases) 下载 `WeeklyPlan-…-macOS-universal.zip`，解压后把「周计划.app」拖进「应用程序」。支持 macOS 14 及以上的 Apple 芯片和 Intel Mac。

发布包使用本地签名，尚未经过 Apple 公证。下载后如果 macOS 要求确认，先尝试打开应用，再到「系统设置 → 隐私与安全性」按提示操作。 [Apple 的打开说明](https://support.apple.com/zh-cn/102445)

打开应用后，桌面卡片会显示周目标、今日待办和最近的 DDL。拖标题调整位置，点卡片右上角箭头打开编辑窗口。菜单栏的日历图标可控制卡片显示和登录时打开。

计划数据保存在本机的「应用程序支持」目录里。源码仓库和下载包只包含应用。

## 从源码构建

在装有 Swift 6 工具链的 Mac 上运行：

```sh
sh test.sh
sh build.sh
```

应用会生成在 `build/周计划.app`。运行 `sh package.sh` 会在 `dist/` 生成可发布的通用安装包。推送与 `Resources/Info.plist` 版本一致的 `v` 标签时，GitHub Actions 会构建并发布该版本。
