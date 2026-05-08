# 小宇宙 Mac 全本地方案 Phase 4

## 阶段目标

`Phase 4` 的目标是把已经验证通过的 Mac 端小宇宙本地主链路，重新接回完整的 Obsidian 知识流程。

这一步关注的核心不再是：

- 音频能不能下载
- ASR 能不能跑
- speaker diarization 能不能跑

而是下面这几个更接近最终交付的问题：

1. `knowledge summary` 为什么现在仍然是 `mock`
2. 怎样让真实分析结果稳定写回 Obsidian
3. 怎样确认知识解读、知识卡、主题地图这些下游产物真的生成了

## 为什么需要 Phase 4

截至 `Phase 3` 结束，当前已经确认：

1. Mac 本地 podcast 主链路已经可用。
2. `mac_metal_balanced` 可以作为正式默认档位。
3. `cooldown_guarded` 可以作为保守备选档位。
4. 热保护、长音频降载、speaker 质量门槛都已经进入主流程。

但这还不等于整个 Obsidian 知识链路已经完成，因为当前仍存在一个明确缺口：

- `knowledge summary` 仍然会回退成 `mock`

所以 `Phase 4` 的工作重点是把“音频处理成功”推进成“知识沉淀成功”。

## 当前已确认事实

基于当前代码与本机配置核对，已经可以确认：

1. `obsidian-clipper/scripts/run_clipper.ps1` 已经具备 knowledge summary 自动调用逻辑。
2. 它会在 clipping note 生成后，自动调用：
   - `obsidian-analyzer/scripts/run_analyzer.ps1`
3. 当前不是 clipper 没有接 analyzer。
4. 当前真正的问题是 analyzer 缺少真实 LLM 配置时，会主动回退为 `mock`。

## 当前阻塞点

### 1. analyzer 本机配置缺失

当前机器上原本缺少：

- `obsidian-analyzer/references/local-config.json`

当前状态已经更新为：

- 本机配置骨架已创建
- 已指向当前 Obsidian vault
- 已补齐知识解读、知识卡、主题地图目录配置

但它还没有完成真实联调，因为还缺少可用的 API Key。

### 2. LLM API Key 缺失

当前环境变量状态：

- `DASHSCOPE_API_KEY` 未设置

而当前 `obsidian-analyzer/scripts/invoke_analyzer_llm.py` 只支持：

- `llm.provider = dashscope_openai_compatible`

所以在没有可用 API Key 的情况下，analyzer 仍会回退生成 `mock` 输出，这是当前预期行为，不是偶发 bug。

### 3. 真实知识链路尚未联调

当前还没有完成下面这些验收动作：

1. 使用真实 analyzer 配置跑一次 podcast 端到端链路
2. 验证 `knowledge summary_status = done`
3. 验证 clipping note 中的 knowledge summary 区块被真实更新
4. 验证知识解读 note、知识卡、主题地图是否实际写入目标 Obsidian 目录

## 本阶段实施顺序

### 1. 补齐 analyzer 本机配置

先在本机创建：

- `obsidian-analyzer/references/local-config.json`

要求：

- 不提交到 Git
- 指向当前 Obsidian vault
- 配置知识解读、知识卡、主题地图的输出目录
- 保持 `dashscope_openai_compatible` 作为现有兼容 provider

### 2. 接入真实 LLM 凭据

为 analyzer 提供真实 API Key，优先方式：

- 设置环境变量 `DASHSCOPE_API_KEY`

原因：

- 不把密钥写进仓库
- 不把密钥硬编码进 `local-config.json`
- 更适合当前机器持续复用

### 3. 跑一次真实 podcast -> knowledge 全链路

至少选择 1 条已经在 `Phase 2/3` 通过的节目样本，重新执行完整链路，重点检查：

1. `knowledge_summary_attempted`
2. `knowledge_summary_status`
3. `knowledge_summary_note_updated`
4. `knowledge_note_path`
5. `knowledge_assets_status`
6. `knowledge_card_count`
7. `topic_map_count`

### 4. 回看 Obsidian 实际产物

不仅看 JSON，还要确认 Obsidian 里是否真的生成并写回：

1. clipping note 内的 knowledge summary 区块
2. `Insights/知识解读`
3. `Insights/知识卡`
4. `Insights/主题地图`

### 5. 记录剩余缺口

如果真实知识链路没有一次跑通，需要把问题分清楚是：

- LLM 调用失败
- schema / JSON 结果不符合预期
- note renderer 失败
- knowledge card 抽取失败
- topic map 更新失败
- 路径或 vault 写回失败

## 本阶段完成标准

1. `knowledge summary` 不再停留在 `mock`
2. clipping note 中的 knowledge summary 区块被真实写入
3. 至少完成 1 次真实 podcast 样本的知识链路联调
4. 至少生成：
   - 1 份知识解读 note
   - 可复核的知识卡结果
   - 可复核的主题地图结果
5. 能明确说明当前知识链路剩余风险与后续优化方向

## 当前结论

`Phase 4` 现在已经正式开始，并已进入联调准备阶段。

第一优先级不是继续改音频链路，而是：

- 给 analyzer 补齐真实 LLM 配置
- 让 `knowledge summary` 退出 `mock`
- 做第一次真实知识链路联调
