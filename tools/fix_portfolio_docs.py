from __future__ import annotations

from pathlib import Path
import shutil


PORTFOLIO_CONTENT = """# Obsidian短视频知识采集与爆款拆解系统 - 作品集主文档

## 项目定位

这是一个面向内容研究与知识管理场景的自动化系统，目标是把“短视频分享链接”自动转化为“可沉淀、可检索、可复用”的结构化知识资产。

系统不是单纯完成视频下载，而是围绕“采集、拆解、沉淀、回传”设计完整链路，使短视频内容可以进入 Obsidian 知识库并继续被分析、引用和复盘。

## 项目背景

在内容运营、选题研究和知识管理过程中，短视频存在三个典型问题：

1. 内容分散在抖音、小红书等平台，缺乏统一沉淀入口。
2. 平台收藏只能保存链接，无法形成结构化知识资产。
3. 后续人工做“爆款拆解”成本高，需要重复整理标题、文案、评论、互动数据和视频内容。

因此，这个项目要解决的不是“如何保存一个链接”，而是“如何把短视频沉淀成后续可以复用的知识节点”。

## 用户画像

### 1. 内容研究型用户

典型特征：

- 高频浏览抖音、小红书、播客等内容平台
- 会持续收集选题、表达方式、内容结构和评论反馈
- 希望把“刷到的内容”沉淀为后续可复用的分析素材

核心需求：

- 快速保存内容
- 自动提取关键字段
- 后续可以继续检索、引用和复盘

### 2. 知识管理型用户

典型特征：

- 已经在使用 Obsidian 进行知识管理
- 不满足于“收藏链接”，更关注长期知识资产沉淀
- 需要把外部内容统一纳入个人知识库

核心需求：

- 保留原始来源
- 建立来源笔记与分析笔记之间的关系
- 形成可追溯、可编辑、可扩展的知识节点

### 3. 移动端高频输入用户

典型特征：

- 主要在手机端发现内容
- 希望看到内容后立即提交处理任务
- 不愿在移动端长时间等待结果

核心需求：

- 低成本提交
- 提交后立即获得确认
- 最终结果通过异步渠道回传

## 项目目标

### 用户目标

1. 用户在手机或桌面端看到一个值得保存的视频后，可以低成本提交任务。
2. 系统自动完成采集、下载、笔记生成和爆款拆解。
3. 最终结果既进入 Obsidian，又能通过飞书回传，降低等待成本。

### 系统目标

1. 支持多入口触发，包括 OpenClaw、iPhone 快捷指令和原始分享文案。
2. 将采集与分析解耦，形成稳定的两阶段流水线。
3. 统一写入 Obsidian，形成原始素材层与分析结果层。
4. 对长任务采用异步执行和结果回传机制，避免移动端超时。

## 方案

项目采用“多入口接入 + 两阶段处理 + 结构化沉淀 + 异步反馈”的方案。

### 输入入口

- 飞书 / OpenClaw 对话入口
- iPhone 快捷指令入口
- 原始短视频分享文案
- 直接视频链接

### 处理流程

1. 用户提交短视频链接或分享文案。
2. 接入层识别用户意图，判断是“剪藏”还是“拆解”。
3. `Clipper` 完成内容抓取、视频下载、评论与互动数据采集，并生成 clipping note。
4. `Analyzer` 基于 clipping note 和 sidecar 生成“爆款拆解”笔记。
5. 所有结果写入 Obsidian。
6. 异步任务完成后，结果通过飞书回传给用户。

## 架构

```mermaid
flowchart LR
    A["输入层\n短视频链接 / 分享文案 / iPhone 快捷指令"] --> B["接入层\nOpenClaw / iOS Gateway / Feishu"]
    B --> C["处理层\nClipper / Analyzer"]
    C --> D["存储层\nObsidian Vault"]
    C --> E["反馈层\nFeishu 回执 / Debug Support"]
```

### 一、输入层

负责接收用户任务，包含：

- iPhone 快捷指令
- 飞书 / OpenClaw
- 原始短视频分享文本
- 直接链接

设计价值：

- 降低使用门槛
- 将输入形式统一收敛为标准任务请求

### 二、接入层

当前主要由 `ios-shortcuts-gateway` 和 OpenClaw 路由组成。

职责：

- 识别意图：`clip` 或 `analyze`
- 校验配置和认证
- 将请求转发给对应处理模块
- 对长任务采用异步提交

设计价值：

- 多入口统一编排
- 将移动端短操作与后台长任务解耦

### 三、处理层

由两个核心模块构成：

#### 1. Clipper

职责：

- 解析分享文案中的真实链接
- 识别平台
- 抓取标题、文案、评论、互动数据
- 下载本地视频
- 生成 clipping note

主要输出：

- `Clippings/`
- `Attachments/ShortVideos/...`
- `capture.json`
- `comments.json`
- `metadata.json`

#### 2. Analyzer

职责：

- 读取已有 clipping note 和 sidecar
- 调用模型做结构化分析
- 生成“爆款拆解”笔记
- 回写来源关系和分析状态

主要输出：

- `爆款拆解/`

设计价值：

- 把“采集”与“分析”分离
- 降低耦合
- 提升模块复用性和可维护性

### 四、存储层

统一沉淀到 Obsidian Vault，形成三层结构：

- `Clippings/`：原始采集层
- `Attachments/ShortVideos/...`：原始附件层
- `爆款拆解/`：结构化分析层

设计价值：

- 信息分层清晰
- 支持来源追溯
- 方便后续人工补充和知识复用

### 五、反馈层

针对长任务，系统采用异步反馈：

- iPhone 快捷指令只提交任务
- Gateway 立即返回 `ACCEPTED`
- 电脑后台执行 `Clipper / Analyzer`
- 最终结果通过飞书回传

设计价值：

- 避免移动端超时
- 优化长任务使用体验
- 将系统能力包装成“提交快、反馈清晰”的产品体验

## 关键决策

### 1. 拆分为 Clipper 与 Analyzer 两阶段

原因：

- 采集强调稳定性、兼容性和可追溯
- 分析强调结构化、智能化和可复用

决策收益：

- 降低模块耦合
- 更利于迭代和排错
- 支持后续扩展更多平台和更多分析能力

### 2. 移动端采用异步提交，不同步等待

原因：

- 下载视频、抓取评论和模型分析都属于长任务
- iPhone 快捷指令对长时间同步等待不友好

决策收益：

- 提交体验稳定
- 用户不需要在手机端等待任务完成
- 结果通过飞书异步回传，更贴合真实使用场景

### 3. 用 Obsidian 作为知识沉淀中台

原因：

- 目标不是完成一次自动化，而是沉淀长期可复用资产

决策收益：

- 短视频内容进入统一知识库
- 支持后续引用、编辑、复盘和再分析
- 为个人知识管理和内容研究提供长期价值

### 4. 保留调试包与结构化状态文件

原因：

- 短视频抓取、登录态、模型分析都存在不稳定性

决策收益：

- 支持快速定位问题
- 用户可以直接上传 `support-bundle`
- 降低系统维护成本

## 结果

目前系统已经完成以下能力：

1. 支持短视频分享文本自动解析与剪藏。
2. 支持基于 clipping note 自动生成“爆款拆解”笔记。
3. 已实现 iPhone 快捷指令通过 Tailscale 调用本地 Gateway。
4. 已实现异步提交、后台执行与飞书结果回传。
5. 已形成以 Obsidian 为中心的结构化知识沉淀链路。

在产品层面，这个项目的价值在于：

- 将“收藏链接”升级为“知识资产”
- 将“手动拆解”升级为“自动化结构化分析”
- 将“等待长任务”升级为“异步提交 + 飞书回传”

## 项目成果和指标

### 已落地成果

1. 完成从短视频分享文案输入到 Obsidian 沉淀的完整链路。
2. 建立了 `Clipper -> Analyzer -> Obsidian -> 飞书回传` 的两阶段处理架构。
3. 打通了 iPhone 快捷指令通过 Tailscale 远程提交任务的能力。
4. 实现了异步提交、后台执行、结果回传的长任务体验优化。
5. 建立了 `status.json`、`support-bundle`、飞书回调结果等可观测机制，降低排障成本。

### 当前可验证指标

1. 输入到结果的主路径已打通：
   - 短视频分享文案可生成 `Clippings` 笔记
   - `analyze` 任务可生成 `爆款拆解` 笔记
2. 移动端远程提交已验证：
   - iPhone 快捷指令可通过 Tailscale 成功请求 Gateway `/health`
   - 任务提交可返回 `ACCEPTED`
3. 异步回传已验证：
   - 后台任务执行完成后，可通过 OpenClaw 现有飞书通道发送结果消息
4. 知识沉淀结构已稳定：
   - 原始内容层：`Clippings/`
   - 分析结果层：`爆款拆解/`
   - 附件层：`Attachments/ShortVideos/...`

### 产品价值指标

从产品视角，这个项目至少达成了三类价值指标：

1. 任务完成度：
   - 从“保存链接”升级为“完成采集、分析、沉淀、回传”的完整流程
2. 用户操作成本：
   - 移动端只需提交一次任务，不必在手机端等待长任务完成
3. 知识资产质量：
   - 每条内容都能保留来源、附件、结构化分析结果和后续可追溯关系

### 后续可继续量化的指标

如果作为正式产品继续推进，建议后续补充这组量化指标：

1. 剪藏成功率
2. 拆解成功率
3. 登录态失效频率
4. 单任务平均完成时长
5. 用户从发现内容到提交任务的操作步数
6. 进入 Obsidian 后被二次引用或二次编辑的内容占比

## 反思

### 1. 入口能力与执行能力需要分层设计

项目前期一度尝试让移动端同步拿到最终结果，但真实使用中很快暴露出超时问题。后续将其改为异步提交 + 飞书回传，说明长任务系统必须先定义“任务生命周期”，而不是只关注单次请求。

### 2. 产品设计不能忽略调试与异常体验

视频抓取、登录态、路径与编码问题在真实环境中频繁出现。如果没有 `status.json`、`support-bundle` 和双语错误信息，这个系统会很难维护。对复杂自动化系统来说，调试体验本身就是产品体验的一部分。

### 3. 知识管理产品要强调沉淀，而不是一次性完成

这个项目最重要的不是自动执行本身，而是让内容最终进入 Obsidian，并形成可继续编辑、引用和分析的知识节点。真正的产品价值来自长期复用，而不是一次任务成功。

### 4. 多入口统一编排是后续扩展的基础

项目已经从最初的单入口执行，逐步扩展到 OpenClaw、飞书和 iPhone 快捷指令。后续如果继续扩展 macOS、更多平台或更多内容形态，统一的任务接口和两阶段处理结构会成为关键基础。

## 关联文档

- [[v3.4 基于本地HTTP与Tailscale的iOS快捷指令远程触发方案PRD]]
- [[v3.5 Gateway Async and Feishu Callback PRD]]
- [[Gateway Async and Feishu Callback/Phase 6 - Shortcut Submit Only Mode]]
- [[Gateway Async and Feishu Callback/Phase 7 - End-to-End Validation and User Docs]]
- [[Gateway Async and Feishu Callback/iOS Shortcuts Submit-Only User Guide]]

## 文档链接规则

后续如果继续围绕该项目新增 PRD、Phase 执行细则、复盘文档或用户文档，建议在新文档开头加入一行：

`关联作品集主文档：[[产品经理作品集/Obsidian短视频知识采集与爆款拆解系统 - 作品集主文档]]`
"""

ONE_PAGE_CONTENT = """# Obsidian短视频知识采集与爆款拆解系统 - 作品集1页版

## 项目一句话

把“短视频分享链接”自动转化为“可沉淀、可检索、可复用”的结构化知识资产，并将结果统一写入 Obsidian。

## 项目背景

短视频内容分散在抖音、小红书等平台，用户通常只能“收藏链接”，很难形成后续可复用的知识资产。与此同时，人工做爆款拆解成本高，需要反复整理标题、文案、评论、互动数据和视频内容。

这个项目要解决的是：如何把碎片化短视频内容自动沉淀为结构化知识节点。

## 目标用户

- 内容研究型用户：需要持续收集选题、结构、评论反馈
- 知识管理型用户：希望把外部内容统一纳入 Obsidian
- 移动端高频输入用户：希望手机端快速提交，稍后再收结果

## 核心方案

系统采用“多入口接入 + 两阶段处理 + 结构化沉淀 + 异步反馈”的方案：

```mermaid
flowchart LR
    A["输入层\n短视频链接 / 分享文案 / iPhone 快捷指令"] --> B["接入层\nOpenClaw / iOS Gateway / Feishu"]
    B --> C["处理层\nClipper / Analyzer"]
    C --> D["存储层\nObsidian Vault"]
    C --> E["反馈层\nFeishu 回执 / Debug Support"]
```

### 处理流程

1. 用户提交短视频链接或分享文案
2. 接入层识别意图：剪藏或拆解
3. `Clipper` 完成内容采集、视频下载、评论和互动数据抓取，并生成 clipping note
4. `Analyzer` 基于 clipping note 和 sidecar 生成“爆款拆解”笔记
5. 所有结果写入 Obsidian
6. 长任务采用异步执行，结果通过飞书回传

## 关键产品决策

### 1. 采集与分析分层

将系统拆分为 `Clipper` 和 `Analyzer` 两阶段，分别承担“稳定采集”和“结构化分析”，降低耦合，提高可维护性。

### 2. 移动端异步提交

由于视频下载和模型分析属于长任务，移动端不再同步等待，而是只负责提交任务，后台执行完成后通过飞书回传结果。

### 3. 以 Obsidian 作为知识沉淀中台

系统目标不是一次性完成下载，而是把短视频沉淀为长期可编辑、可引用、可复盘的知识资产。

## 项目成果

- 打通了从短视频分享文案到 Obsidian 沉淀的完整链路
- 建立了 `Clipper -> Analyzer -> Obsidian -> 飞书回传` 的两阶段架构
- 打通了 iPhone 快捷指令通过 Tailscale 远程提交任务
- 实现了异步提交、后台执行、结果回传的长任务体验优化
- 建立了 `status.json`、`support-bundle`、回调结果等可观测机制

## 当前可验证指标

- 短视频分享文案可生成 `Clippings` 笔记
- `analyze` 任务可生成 `爆款拆解` 笔记
- iPhone 快捷指令可成功请求 Gateway `/health`
- 任务提交可返回 `ACCEPTED`
- 后台任务执行完成后，可通过 OpenClaw 现有飞书通道发送结果消息

## 我的思考

这个项目最关键的价值不在“自动下载视频”，而在于把内容沉淀为结构化知识资产。实际推进过程中，异步任务设计、异常体验和调试可观测性，和功能本身同样重要。

## 关联文档

- [[产品经理作品集/Obsidian短视频知识采集与爆款拆解系统 - 作品集主文档]]
"""

INTERVIEW_CONTENT = """# Obsidian短视频知识采集与爆款拆解系统 - 面试讲述版

## 一句话介绍

这是一个把短视频分享链接自动沉淀为 Obsidian 结构化知识资产的系统，核心解决的是“外部内容如何低成本进入知识库，并进一步自动完成爆款拆解”。

## 1. 项目背景

我当时想解决的是一个很具体的问题：短视频内容虽然很有研究价值，但日常收藏通常只停留在平台收藏夹或者链接层面，后续很难被检索、复用和复盘。

如果要人工整理成知识笔记，又要重复做很多机械工作，比如保存链接、提取标题、整理文案、抓评论、看互动数据、再写爆款拆解，成本很高。

所以我想做一个系统，把“看到一个视频”到“进入知识库并形成结构化分析”这条链路自动化。

## 2. 目标

这个项目有三个目标：

1. 让用户可以低门槛提交短视频内容，不管是桌面端还是手机端。
2. 把内容自动沉淀进 Obsidian，而不是只保存一个链接。
3. 在沉淀原始内容的基础上，进一步自动生成“爆款拆解”结果。

## 3. 我怎么拆这个问题

我最后把系统拆成了两阶段：

### 第一阶段：Clipper

负责采集。

它解决的问题是：
- 解析分享文案里的真实链接
- 抓视频标题、文案、评论、互动数据
- 下载本地视频
- 生成 clipping note

这一步的重点是稳定性和来源追溯。

### 第二阶段：Analyzer

负责分析。

它读取 clipping note 和 sidecar，然后调用模型生成结构化的“爆款拆解”笔记。

这一步的重点是结构化输出和可复用性。

我之所以这样拆，是因为采集和分析本质上是两种能力：
- 采集强调稳定、兼容和可追溯
- 分析强调结构化、智能化和知识沉淀

## 4. 架构怎么设计

系统现在的主链路是：

1. 用户从 OpenClaw、飞书或者 iPhone 快捷指令发起任务
2. 接入层识别用户意图，是“剪藏”还是“拆解”
3. `Clipper` 先完成原始采集
4. 如果是拆解任务，再调用 `Analyzer`
5. 所有结果写入 Obsidian
6. 长任务通过异步方式执行，最终结果通过飞书回传

这里我做过一个比较重要的产品决策，就是把移动端改成“提交即返回”。

因为真实链路里有视频下载、页面抓取、模型分析，这些都是长任务。如果让 iPhone 一直同步等待，体验非常差，而且会超时。

所以我把交互改成：
- 手机端只负责提交
- Gateway 立即返回任务已接收
- 电脑后台继续执行
- 最终结果通过飞书主动发回给用户

这个改动本质上是把“功能能不能跑”升级成“用户体验是不是成立”。

## 5. 这个项目里我最看重的几个决策

### 决策一：两阶段处理，而不是一个大脚本串到底

这样做的好处是：
- 结构更清晰
- 出问题更容易定位
- 以后如果换模型或者增加平台，不需要重写整条链路

### 决策二：Obsidian 不是结果展示页，而是知识沉淀中台

我不是把它当成一个“存文件”的地方，而是把它设计成：
- 原始采集层 `Clippings/`
- 附件层 `Attachments/ShortVideos/...`
- 分析层 `爆款拆解/`

这样内容进来以后，可以继续被编辑、引用和复盘。

### 决策三：把异常和调试也当成产品体验的一部分

这个项目里实际遇到过很多复杂问题，比如：
- 视频平台登录态失效
- 路径和编码问题
- 标题和来源链接对不上
- 移动端超时

所以我后面补了：
- `status.json`
- `support-bundle`
- 双语错误信息
- 飞书回调状态

这部分虽然看起来偏工程，但从产品角度看，它直接决定系统是不是可用、可维护。

## 6. 项目结果

目前这个系统已经实现了：

1. 短视频分享文案可自动生成 `Clippings` 笔记
2. `analyze` 任务可生成 `爆款拆解` 笔记
3. iPhone 快捷指令可通过 Tailscale 远程提交任务
4. 长任务可以异步执行，结果通过飞书回传
5. 内容最终会以结构化方式沉淀到 Obsidian

如果从价值角度总结，我认为这个项目做成了三件事：

1. 把“收藏链接”升级成“知识资产”
2. 把“手动拆解”升级成“自动化结构化分析”
3. 把“等待长任务”升级成“异步提交 + 结果回传”

## 7. 我的反思

这个项目让我比较明确地感受到两件事：

第一，复杂系统里，功能并不等于体验。  
一开始链路能跑通，不代表用户真的能顺畅使用，特别是在移动端和长任务场景下，必须重新设计交互方式。

第二，知识管理类产品的价值不在于一次自动化成功，而在于内容能不能沉淀成后续可复用的资产。  
所以这个项目最核心的不是“下载视频”，而是“建立一个可持续积累的结构化知识流程”。

## 面试时可补充展开的点

- 如果面试官更关注产品设计：重点讲用户路径、交互方式和异步体验
- 如果面试官更关注系统架构：重点讲两阶段处理和多入口统一编排
- 如果面试官更关注落地能力：重点讲你怎么把真实问题一点点修到能用

## 关联文档

- [[产品经理作品集/Obsidian短视频知识采集与爆款拆解系统 - 作品集主文档]]
- [[产品经理作品集/Obsidian短视频知识采集与爆款拆解系统 - 作品集1页版]]
"""


BACKLINK_TARGETS = [
    "v3.4 基于本地HTTP与Tailscale的iOS快捷指令远程触发方案PRD.md",
    "v3.5 Gateway Async and Feishu Callback PRD.md",
    "Gateway Async and Feishu Callback/Phase 6 - Shortcut Submit Only Mode.md",
    "Gateway Async and Feishu Callback/Phase 7 - End-to-End Validation and User Docs.md",
    "Gateway Async and Feishu Callback/iOS Shortcuts Submit-Only User Guide.md",
]

BACKLINK_LINE = "关联作品集主文档：[[产品经理作品集/Obsidian短视频知识采集与爆款拆解系统 - 作品集主文档]]"


def find_flow_dir() -> Path:
    root = Path("E:/iCloudDrive/iCloudDrive/iCloud~md~obsidian")
    matches = list(root.glob("*/Notes/openclaw结合Obsidian的结构化知识库流程"))
    if not matches:
        raise SystemExit("flow directory not found")
    return matches[0]


def ensure_portfolio_doc(flow_dir: Path) -> Path:
    portfolio_dir = flow_dir / "产品经理作品集"
    portfolio_dir.mkdir(parents=True, exist_ok=True)
    doc_path = portfolio_dir / "Obsidian短视频知识采集与爆款拆解系统 - 作品集主文档.md"
    doc_path.write_text(PORTFOLIO_CONTENT, encoding="utf-8")
    one_page_path = portfolio_dir / "Obsidian短视频知识采集与爆款拆解系统 - 作品集1页版.md"
    one_page_path.write_text(ONE_PAGE_CONTENT, encoding="utf-8")
    interview_path = portfolio_dir / "Obsidian短视频知识采集与爆款拆解系统 - 面试讲述版.md"
    interview_path.write_text(INTERVIEW_CONTENT, encoding="utf-8")
    return doc_path


def update_backlink(doc_path: Path) -> None:
    if not doc_path.exists():
        return
    text = doc_path.read_text(encoding="utf-8", errors="replace")
    text = text.replace(
        "关联作品集主文档：[[äº§åç»çä½åé/ObsidianÃ§ÂÂ­Ã¨Â§ÂÃ©Â¢ÂÃ§ÂÂ¥Ã¨Â¯ÂÃ©ÂÂÃ©ÂÂÃ¤Â¸ÂÃ§ÂÂÃ¦Â¬Â¾Ã¦ÂÂÃ¨Â§Â£Ã§Â³Â»Ã§Â»Â - Ã¤Â½ÂÃ¥ÂÂÃ©ÂÂÃ¤Â¸Â»Ã¦ÂÂÃ¦Â¡Â£]]",
        "",
    )
    text = text.replace("关联作品集主文档：[[äº§åç»çä½åé/Obsidianç­è§é¢ç¥è¯ééä¸çæ¬¾æè§£ç³»ç» - ä½åéä¸»ææ¡£]]", "")
    text = text.replace("?????????[[äº§åç»çä½åé/ObsidianÃ§ÂÂ­Ã¨Â§ÂÃ©Â¢ÂÃ§ÂÂ¥Ã¨Â¯ÂÃ©ÂÂÃ©ÂÂÃ¤Â¸ÂÃ§ÂÂÃ¦Â¬Â¾Ã¦ÂÂÃ¨Â§Â£Ã§Â³Â»Ã§Â»Â - Ã¤", "")
    if BACKLINK_LINE in text:
        doc_path.write_text(text, encoding="utf-8")
        return
    lines = text.splitlines()
    insert_at = 1 if lines and lines[0].startswith("# ") else 0
    if insert_at < len(lines) and lines[insert_at].strip():
        lines.insert(insert_at, "")
        insert_at += 1
    lines.insert(insert_at, BACKLINK_LINE)
    lines.insert(insert_at + 1, "")
    doc_path.write_text("\n".join(lines).rstrip() + "\n", encoding="utf-8")


def cleanup_garbled_duplicates(flow_dir: Path) -> None:
    expected_dir = flow_dir / "产品经理作品集"
    for child in flow_dir.iterdir():
        if child == expected_dir:
            continue
        if child.is_dir() and "作品集" not in child.name and "äº§" in child.name:
            shutil.rmtree(child)


def sync_clean_v35_docs(flow_dir: Path) -> None:
    source_root = Path("E:/Codex_project/obsidian-skillkit/ios-shortcuts-gateway/references/obsidian-v35")
    if not source_root.exists():
        return
    for src in source_root.rglob("*.md"):
        rel = src.relative_to(source_root)
        dst = flow_dir / rel
        dst.parent.mkdir(parents=True, exist_ok=True)
        dst.write_text(src.read_text(encoding="utf-8"), encoding="utf-8")
        update_backlink(dst)


def main() -> None:
    flow_dir = find_flow_dir()
    ensure_portfolio_doc(flow_dir)
    sync_clean_v35_docs(flow_dir)
    for rel in BACKLINK_TARGETS:
        update_backlink(flow_dir / rel)
    cleanup_garbled_duplicates(flow_dir)
    print(flow_dir)


if __name__ == "__main__":
    main()
