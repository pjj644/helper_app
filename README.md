# 成电助手 (UESTC Helper)

<p align="center">
  <img src="./Application/entry/src/main/resources/base/media/startIcon.png" alt="Logo" width="100" height="100" />
</p>

<p align="center">
  <strong>专为电子科技大学（UESTC）学子打造的 HarmonyOS NEXT 原生校园生活与学习全能助手</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/HarmonyOS-NEXT%20(API%206.0.2%2F22)-blue.svg" alt="HarmonyOS NEXT" />
  <img src="https://img.shields.io/badge/Language-ArkTS%20%7C%20ArkUI-orange.svg" alt="ArkTS" />
  <img src="https://img.shields.io/badge/IDE-DevEco%20Studio%205.0%2B-red.svg" alt="DevEco Studio" />
  <img src="https://img.shields.io/badge/Model-Stage-green.svg" alt="Stage Model" />
  <img src="https://img.shields.io/badge/License-MIT-lightgrey.svg" alt="License" />
</p>

---

## 📖 项目简介

**成电助手（UESTC Helper）** 是一款面向电子科技大学在校师生的鸿蒙原生应用，采用 HarmonyOS NEXT (API 22) 与 ArkTS 纯声明式 UI 开发。应用聚焦日常教务与校园生活痛点，集成了智能课表、考务与 GPA 分析、双校区班车时刻表、AI 伴随智能体、桌面万能服务卡片以及云端同步等全方位功能。

---

## ✨ 核心特性

- 📅 **智能课表系统**：
  - 支持 1~12 节课全天排期、周次快速切换与单双周自适应。
  - 智能解析冲突重叠课程，支持手动添加个性化日程与教室导航。
- 📝 **考务日程与成绩 GPA**：
  - 考试信息抓取与倒计时展示，一键添加提醒防漏考。
  - 学期成绩汇总、均分 / GPA 自动核算与趋势分析。
- 🚌 **双校区班车与日历联动**：
  - 清水河 ↔ 沙河双校区完整班车时刻表与最近班次动态倒计时。
  - 点击一键设为日程提醒，发车前 15 分钟由系统日历强力推送。
- 🤖 **AI 伴随智能体（Assistant）**：
  - 具备全局呼吸悬浮窗（悬浮球 / 面板 / 引导三态协同流转）。
  - 内置 80+ 成电直达服务库与校园知识库，支持流式 Markdown 排版与深度思考打字机。
- 📱 **桌面万能服务卡片（Form Widget）**：
  - 提供 2x2 与 2x4 万能桌面卡片，无需打开应用即可在桌面洞察下一节课倒计时与全天日程。
- ☁️ **端云一体化与安全同步**：
  - 基于华为云 AGC (Cloud DB) 实现跨设备课表与偏好数据加密同步。

---

## 📦 本项目 .HAP 安装包直接体验（免编译快速上手）

如果您不需要修改源码，仅想在 **模拟器** 或 **真机** 上体验本应用，可以直接使用构建好的 `.hap` 安装包：

### 1. 安装包获取
- **本地编译产物路径**：
  ```text
  Application/entry/build/default/outputs/default/entry-default-signed.hap
  ```
- **GitHub 线上发布**：可在本仓库的 [Releases 页面](https://github.com/pjj644/helper_app/releases) 获取最新的 Signed HAP 安装包。

### 2. 安装方式 A：DevEco 模拟器一键拖拽（推荐，极简）
1. 打开 DevEco Studio，启动**本地模拟器（Local Emulator）**或**远程模拟器（Remote Emulator）**。
2. 在 Windows 文件管理器中找到 `entry-default-signed.hap` 文件。
3. **鼠标拖动该文件直接松手放入正在运行的模拟器窗口中**。
4. 模拟器将自动静默安装，片刻后桌面上即会出现「成电助手」App 图标。

### 3. 安装方式 B：通过 HDC 命令行工具安装（真机 / 模拟器通用）
DevEco Studio 自带 `hdc` 命令行工具（位于 DevEco SDK 的 `openharmony/toolchains/hdc.exe`）。

在终端中执行：
```powershell
# 1. 检查设备是否连接成功（真机需开启 USB 调试，模拟器需处于启动状态）
hdc list targets

# 2. 执行安装（-r 参数支持保留数据覆盖安装）
hdc app install -r "Application/entry/build/default/outputs/default/entry-default-signed.hap"
```
终端输出 `[Success]` 即表示安装成功。

---

## 🛠️ DevEco Studio 源码运行指南

如需在本地进行二次开发或编译源码，请按照以下步骤配置开发环境：

### 1. 环境准备
- **操作系统**：Windows 10 / 11 64位 或 macOS
- **开发工具**：[DevEco Studio](https://developer.huawei.com/consumer/cn/deveco-studio/) **5.0+** (兼容 NEXT Release / Beta)
- **SDK 版本**：HarmonyOS NEXT Developer Preview / Release，**API Version 6.0.2 (22)**
- **模型**：Stage 模型

### 2. 克隆仓库
```bash
git clone https://github.com/pjj644/helper_app.git
```

### 3. 打开工程（⚠️ 非常重要）
> **注意**：本项目鸿蒙工程源码位于 `Application/` 子目录下。
1. 启动 DevEco Studio。
2. 点击 **Open**。
3. **请务必选择并打开仓库下的 `Application` 文件夹**（而非外层的仓库根目录 `helper_app`）。

### 4. 依赖同步 (ohpm Sync)
工程打开后，DevEco Studio 会检测 `oh-package.json5`。
- 如果提示需要同步，点击右上角的 **Sync Now**。
- DevEco 会自动下载安装所需要的 `oh_modules` 依赖包。

### 5. 配置应用签名 (Signing Configs)
为了能在真机或模拟器上顺利调试运行，需配置调试证书：
1. 在 DevEco Studio 菜单栏选择：`File` -> `Project Structure...`（快捷键 `Ctrl+Alt+Shift+S`）。
2. 在左侧面板选择 **Project** -> **Signing Configs**。
3. 勾选 **Automatically generate signature**（自动生成签名）。
4. 确保登录了华为开发者账号，IDE 会自动向华为云申请并下载对应的调试证书与 Profile 文件。
5. 点击 **Apply** 并保存。

### 6. 运行与调试
1. **准备运行目标**：
   - **模拟器**：在顶部菜单点击 `Tools` -> `Device Manager`，新建并启动 Phone 类型的模拟器（确保系统版本与 API 22 兼容）。
   - **真机**：使用 USB 数据线连接搭载 HarmonyOS NEXT 的华为手机，进入「设置 -> 关于手机」连续点击版本号开启开发者选项，并打开「USB 调试」。
2. **启动应用**：
   - 在 DevEco 顶部运行配置中选中模块 `entry`，选择你的设备/模拟器。
   - 点击绿色运行按钮 **▶ Run 'entry'**（快捷键 `Shift+F10`）。
   - IDE 将自动编译 HAP、安装并自动拉起应用主界面。

---

## 💻 常用命令行构建指令

如需通过命令行快速构建或进行持续集成，推荐使用官方 DevEco CLI 或 Hvigor：

### 使用 DevEco CLI（推荐）
```powershell
# 编译 Debug HAP 安装包
devecocli build --modules entry@default --build-mode debug

# 清理构建缓存产物
devecocli build clean

# 执行代码规范静态检查（Code Linter）
devecocli check lint
```

### 使用 Hvigor Wrapper（需在 `Application/` 目录下）
```powershell
# 编译 Debug 包
.\hvigorw.bat assembleHap -p product=default -p buildMode=debug

# 清理并全量重新编译
.\hvigorw.bat clean assembleHap
```
编译生成的安装包位于：`Application/entry/build/default/outputs/default/`

---

## 📁 项目工程结构

```text
helper_app/
├── Application/                   # HarmonyOS 原生工程主目录（在 DevEco 中打开此目录）
│   ├── AppScope/                  # 应用全局配置与资源（app.json5, 图标等）
│   ├── build-profile.json5        # 工程级构建与签名配置
│   ├── hvigorfile.ts              # Hvigor 构建脚本
│   ├── oh-package.json5           # 工程级三方依赖管理
│   └── entry/                     # 主功能模块 (Stage Model)
│       └── src/main/
│           ├── module.json5       # Ability 与权限声明配置
│           ├── resources/         # 页面资源（字体、颜色、字符串、图片）
│           └── ets/
│               ├── entryability/  # 应用入口 UIAbility
│               ├── entryformability/ # 桌面万能卡片 FormExtensionAbility
│               ├── pages/         # 页面层 (五主Tab + 二级路由页)
│               ├── components/    # 业务复用 UI 组件
│               ├── service/       # 业务逻辑服务层 (课表/考试/班车/日历等)
│               ├── repository/    # 数据持久化存储层 (Preferences / Cloud DB)
│               ├── model/         # 纯 TS 数据模型与算法定义
│               └── common/        # 基础常量、工具库、AI 智能体引擎
├── CloudProgram/                  # 华为云 AGC 云端一体化工程（CloudDB / 云函数）
├── icon/                          # 矢量图形资源资产
└── README.md                      # 项目说明文档
```

---

## ❓ 常见问题排查 (FAQ)

### Q1: 拖拽或安装 HAP 时提示 `verify cert failed` 错误？
- **原因**：设备或模拟器对安装包证书签名有校验要求。
- **解决**：确保使用的是已签名的 `entry-default-signed.hap`；若在自己的模拟器/真机运行，建议在 DevEco Studio 中通过步骤五勾选 **Automatically generate signature** 重新打出专属您设备的 Debug 签名包。

### Q2: 导入工程时报错或报找不到模块？
- **原因**：未在 `Application/` 目录下执行依赖同步。
- **解决**：请确认 DevEco 打开的是 `helper_app/Application` 目录，并在右上角点击 **Sync Now**，或在命令行中运行 `ohpm install`。

### Q3: 运行在模拟器上时 AI 助手网络请求超时？
- **原因**：模拟器走独立网络 NAT 网关，无法通过 `localhost` 访问宿主机后端服务。
- **解决**：应用已默认内置公网直连通道；若本地脱机联调后端，请在 App 内「我的 -> 应用设置 -> 助手后端」将地址配置为宿主机的真实 **局域网 IP**（如 `http://192.168.x.x:3000`）。

---

## 📄 开源许可证

本项目基于 [MIT License](LICENSE) 开源。欢迎贡献代码与提出 Issue！
