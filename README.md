# Cognee 一键部署

为 AI Agent 快速部署 Cognee 记忆服务，支持知识图谱 + 向量检索的持久化长期记忆。

## 快速开始

### 使用官方 pip 包（默认）

```bash
export COGNEE_API_KEY=***
curl -sSL https://raw.githubusercontent.com/SLC413/deploy-cognee/main/deploy-cognee.sh | sudo bash
```

### 使用自己的 fork（推荐）

```bash
export COGNEE_API_KEY=***
export COGNEE_SOURCE="git+https://github.com/SLC413/cognee.git"
curl -sSL https://raw.githubusercontent.com/SLC413/deploy-cognee/main/deploy-cognee.sh | sudo bash
```

## 环境变量

| 变量 | 必填 | 默认值 |
|------|------|--------|
| `COGNEE_API_KEY` | ✅ | - |
| `COGNEE_SOURCE` | - | `cognee`（pip 官方包） |
| `COGNEE_LLM_PROVIDER` | - | `deepseek` |
| `COGNEE_LLM_MODEL` | - | `deepseek/deepseek-chat` |
| `COGNEE_EMBEDDING_PROVIDER` | - | `fastembed` |
| `COGNEE_EMBEDDING_MODEL` | - | `BAAI/bge-small-en-v1.5` |
| `COGNEE_PORT` | - | `8011` |

## 支持的 LLM 提供商

- DeepSeek（默认）
- OpenAI / OpenAI 兼容 API
- Ollama（本地模型）
- 任何 LiteLLM 支持的提供商

## 使用自有 fork

```bash
export COGNEE_SOURCE="git+https://github.com/你的用户名/cognee.git"
```

这样就算上游删库，你的部署不受影响。

## 部署后

脚本完成后会输出 OpenClaw 插件配置片段，粘贴到 `~/.openclaw/openclaw.json` 并重启 Gateway 即可启用。

## 要求

- Ubuntu 22.04+ / Debian 12+
- Python 3.10+
- 2 GB+ 可用内存
