# 服务商快照

> **快照时间**：2026-10-01 16:00 GMT+8 · **获取最新**：`as capability providers` / `as capability search <domain>`（内容可能随服务端更新，以 CLI 实查为准）

agentschool 当前已收录的 provider / capability 快照。

## 已收录服务商（9 个）

| 服务商 | slug | 类型 | 一句话描述 |
|---|---|---|---|
| 即梦/剪映 | `jimeng` | CLI | 字节跳动 AI 创作平台（图像/视频生成） |
| 飞书/Lark | `lark` | API | 办公协同（文档/多维表格/消息） |
| 腾讯会议 | `tencent-meeting` | API | 会议创建/管理/录制 |
| 阿里云百炼 | `bailian` | CLI | 通义系列大模型/多模态统一网关 |
| 支付宝 | `alipay` | API | 支付/资金/营销 |
| Qoder | `qoder` | API | 云端 Agent 与资源管理 |
| 火山引擎 | `volcengine` | API | 火山方舟 Ark/扣子 Coze/豆包 |
| first-party-oneopcai | — | API | AgentSchool 一方业务服务 |
| first-party-examples | — | API | 官方示例与演示 |

## image 域能力（5 条）

> id 为 UUID（`as capability show <id>` 接受完整 UUID 或 slug）

| slug | 容器 | 名称 |
|---|---|---|
| `jimeng.text2image` | jimeng-cli | 文生图 |
| `jimeng.image.hires` | jimeng-cli | 高清生图 |
| `jimeng.text2video` | jimeng-cli | 文生视频 |
| `bailian.image.generate` | bailian-cli | 文生图（通义万相） |
| `qoder.image.generate` | qoder-cloud-agents-api | 云端文生图 |

## 查询命令

```bash
as capability providers                          # 全部服务商
as capability search image                       # 按域搜索能力
as capability search image --json                # 含 id/slug/provider 的结构化输出
as capability show <id或slug>                    # 能力详情
```
