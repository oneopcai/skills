# 能力域（Domain）说明

agentschool 把能力分成 **11 个域**。每个域有约定的 slug 命名与典型场景。

## 命名约定

```text
<provider>.<domain>.<action>
```

例子：
- `bailian.image.generate` — 阿里云百炼 · 图像 · 生成
- `jimeng.text2image` — 即梦 · 图像（text2image 是约定子动作）
- `bailian.image.edit` — 阿里云百炼 · 图像 · 编辑
- `qoder.image.generate` — Qoder · 图像 · 生成

## 11 个域速查

| domain | 含义 | 典型场景 |
|---|---|---|
| `image` | 图像生成 / 编辑 | 封面图、海报、配图 |
| `text` | 文本生成（LLM）| 写作、摘要、问答 |
| `vision` | 图像理解 | OCR、截图识别、文档解析 |
| `omni` | 多模态 | 图文对话、视频理解 |
| `tts` | 文字转语音 | 配音、播报 |
| `asr` | 语音转文字 | 转写、字幕 |
| `video` | 视频生成 / 编辑 | 短视频、动效 |
| `knowledge` | 知识库 / RAG | 检索、问答 |
| `memory` | 长期记忆 | 用户偏好、上下文 |
| `workflow` | 流程编排 | 多步任务串联 |
| `agent` | Agent 框架 | 规划、工具调用 |

## 11 个域详解（action_verb 枚举）

### 1. `image` — 图像生成 / 编辑

| action_verb | 含义 | 典型服务商 |
|---|---|---|
| `generate` / `text2image` | 文生图 | bailian / jimeng / qoder |
| `edit` | 图像编辑（局部修改）| bailian |
| `hires` | 高清放大 | jimeng |

**典型场景**：自媒体封面、配图、海报、头像、AI 头像。

### 2. `text` — 文本生成（LLM）

| action_verb | 含义 |
|---|---|
| `chat` | 对话 |
| `completion` | 续写 |
| `summarize` | 摘要 |
| `translate` | 翻译 |

**典型场景**：文案生成、摘要、改写、翻译、问答。

### 3. `vision` — 图像理解

| action_verb | 含义 |
|---|---|
| `ocr` | 文字识别 |
| `vqa` | 视觉问答 |
| `classify` | 图像分类 |
| `detect` | 目标检测 |

**典型场景**：截图识字、文档解析、图片理解。

### 4. `omni` — 多模态（图+文+音+视任意组合）

**典型场景**：图文对话、视频问答、跨模态检索。

### 5. `tts` — 文字转语音

| action_verb | 含义 |
|---|---|
| `synthesize` | 合成语音 |
| `clone` | 声音克隆 |

**典型场景**：视频配音、解说、播客。

### 6. `asr` — 语音转文字

| action_verb | 含义 |
|---|---|
| `transcribe` | 转写 |
| `diarize` | 说话人分离 |

**典型场景**：字幕生成、会议记录、采访转写。

### 7. `video` — 视频生成 / 编辑

| action_verb | 含义 |
|---|---|
| `text2video` | 文生视频 |
| `image2video` | 图生视频 |
| `edit` | 视频剪辑 |
| `ref2video` | 参考视频生成 |

**典型场景**：AI 短片、商品视频、动效。

### 8. `knowledge` — 知识库 / RAG

| action_verb | 含义 |
|---|---|
| `search` | 文档检索 |
| `index` | 建索引 |
| `query` | 知识问答 |

**典型场景**：私域问答、企业文档、客服知识库。

### 9. `memory` — 长期记忆

| action_verb | 含义 |
|---|---|
| `store` | 存入 |
| `recall` | 召回 |
| `forget` | 遗忘 |

**典型场景**：Agent 上下文管理、用户偏好记录、跨会话记忆。

### 10. `workflow` — 流程编排

| action_verb | 含义 |
|---|---|
| `trigger` | 触发工作流 |
| `define` | 定义工作流 |

**典型场景**：多步任务串联（搜 → 摘要 → 出图 → 推送）。

### 11. `agent` — Agent 框架

| action_verb | 含义 |
|---|---|
| `run` | 运行 Agent |
| `plan` | 任务规划 |
| `tool_call` | 工具调用 |

**典型场景**：ReAct / AutoGPT 风格的多步决策。

## 选域指引

| 用户意图 | 推荐域 |
|---|---|
| **生成内容** | `image` / `text` / `video` / `tts` |
| **理解内容** | `vision` / `asr` / `text` |
| **存储 / 检索** | `knowledge` / `memory` |
| **多步 / 复杂任务** | `agent` / `workflow` |
| **跨模态 / 不确定** | `omni`（能力少、价格高，谨慎）|
