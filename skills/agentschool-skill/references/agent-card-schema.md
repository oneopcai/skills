# 能力卡导出格式（勘误版）

> **勘误（2026-08-23，trial P3）**：本文档旧版描述的 `--format agent-card`
> （`application/x-agent-card+v1` 结构化能力卡）**在 CLI 中并不存在**——
> `as capability export` 从未实现过该格式，旧文档把未实现的设想当成了可用功能
> （试用期实测 `--format agent-card` 直接报"单条导出仅支持 json/markdown/all"）。
> 旧 schema 描述已整体废弃，本文改为记录**实际存在**的导出格式。

## 实际格式清单（as capability export，以 --help 与实测为准）

### 单条导出（`as capability export <id> --format <fmt>`）

| 格式 | 说明 |
|---|---|
| `json` | 能力详情 JSON（endpoints + evidences 全量） |
| `markdown` | 人读 Markdown（领域/动作/端点/证据） |
| `all` | 同时输出 json + markdown（默认） |

批量格式（`openai-tools` / `anthropic-tools` / `skill-bundle`）不支持单条导出。

### 批量导出（`as capability export --all / --provider <id> / --domain <d> --format <fmt>`）

| 格式 | 说明 |
|---|---|
| `openai-tools` | OpenAI Function Calling tools 数组（单 JSON 文件） |
| `anthropic-tools` | Anthropic Tool Use tools 数组（单 JSON 文件） |
| `skill-bundle` | 目录包：`capabilities/*.md` + `providers/*.json` + 两种 tools JSON + manifest |

单条格式（`json` / `markdown` / `all`）不支持批量导出。

### 常见错误

- `--format agent-card` → 报错"单条导出仅支持 json/markdown/all"（该格式不存在）
- id 传数字序号 → 404；**id 是 UUID**（`as capability search` 结果的 `id` 字段）
