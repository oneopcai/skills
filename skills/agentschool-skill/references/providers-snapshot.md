# 服务商快照

agentschool 当前已收录的部分 provider / container / capability 快照。

## 已收录服务商

| 服务商 | 容器 slug | 类型 | install_command |
|---|---|---|---|
| 阿里云百炼 | `bailian-cli` | CLI | `npm install -g bailian-cli` |
| 即梦 / 剪映 | `jimeng-cli` | CLI | （待补） |
| Qoder | `qoder-cloud-agents-api` | HTTP API | （无需 CLI） |

## 已收录 image 域能力

| id | slug | 容器 | 证据 |
|---|---|---|---|
| 1 | `jimeng.text2image` | `jimeng-cli` | L2 |
| 7 | `jimeng.image.hires` | `jimeng-cli` | L2 |
| 6 | `bailian.image.generate` | `bailian-cli` | L2 |
| 14 | `bailian.image.edit` | `bailian-cli` | L2 |
| 8 | `qoder.image.generate` | `qoder-cloud-agents-api` | L2 |

## 已收录其它域（节选）

agentschool 数据模型 `Provider -> ProductContainer -> Capability`，可按 `as capability search <domain>` 查。

## 收录质量自检

- 每条能力至少挂载 1 个 `InterfaceEndpoint`（CLI / API / SDK）
- 商用能力（bailian / jimeng / qoder）证据等级 ≥ L2
- `trust.verified` 字段在 `evidence_level >= L2` 时折叠为 `true`

## 当前 gap（缺口）

agentschool 当前**未直接暴露**以下信息给 agent：

1. **容器 `install_command`**：`as capability containers` 子命令目前**没有 `--json` 选项**，agent 拿不到安装命令
2. **容器 ↔ 能力 双向索引**：agent 拿到 `capability_id` 后若要反查容器信息，需额外调 `GET /api/v1/containers/{id}`，不是单一调用闭环

**两种修复方向**（任选其一）：

- 扩展 `as capability` 子命令，补 `--json` / `--show <container_id>` 输出 install_command
- 在 agent-card schema 里直接加 `provider.install_command` 字段，一次拿全

**当前 workaround**：skill 通过 HTTP API 拿（`as capability export --format all`）或等 as CLI 后续补完。
