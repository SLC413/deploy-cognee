#!/bin/bash
set -euo pipefail

# =========================================================
# Cognee 一键部署脚本
# 用法:
#   export COGNEE_API_KEY=sk-xxx
#   bash deploy-cognee.sh
#
# 可选环境变量:
#   COGNEE_API_KEY       - (必填) LLM API Key
#   COGNEE_LLM_PROVIDER  - LLM 提供商，默认 deepseek
#   COGNEE_LLM_MODEL     - LLM 模型，默认 deepseek/deepseek-chat
#   COGNEE_LLM_ENDPOINT  - LLM 端点（DeepSeek 自动设，其他需手动）
#   COGNEE_EMBEDDING_PROVIDER - embedding 提供商，默认 fastembed
#   COGNEE_EMBEDDING_MODEL    - embedding 模型，默认 BAAI/bge-small-en-v1.5
#   COGNEE_PORT          - 端口，默认 8011
#   COGNEE_USER          - 运行用户，默认 ubuntu
#   COGNEE_SOURCE        - cognee 安装源，默认 pip 官方包
#                          也可用 git: git+https://github.com/SLC413/cognee.git
# =========================================================

COGNEE_LLM_PROVIDER="${COGNEE_LLM_PROVIDER:-deepseek}"
COGNEE_LLM_MODEL="${COGNEE_LLM_MODEL:-deepseek/deepseek-chat}"
COGNEE_EMBEDDING_PROVIDER="${COGNEE_EMBEDDING_PROVIDER:-fastembed}"
COGNEE_EMBEDDING_MODEL="${COGNEE_EMBEDDING_MODEL:-BAAI/bge-small-en-v1.5}"
COGNEE_PORT="${COGNEE_PORT:-8011}"
COGNEE_SOURCE="${COGNEE_SOURCE:-cognee}"
COGNEE_USER="${COGNEE_USER:-ubuntu}"
COGNEE_HOME="/opt/cognee"
COGNEE_ENV="$COGNEE_HOME/.env"
COGNEE_VENV="$COGNEE_HOME/venv"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[✗]${NC} $1"; exit 1; }

echo "╔══════════════════════════════════════╗"
echo "║   Cognee Memory Server — 一键部署   ║"
echo "╚══════════════════════════════════════╝"
echo ""

# ---- 0. 参数检查 ----
if [[ -z "${COGNEE_API_KEY:-}" ]]; then
    err "请设置 COGNEE_API_KEY 环境变量"
fi

# ---- 1. 系统依赖 ----
log "检查系统依赖..."

if ! command -v python3 &>/dev/null; then
    warn "安装 Python..."
    sudo apt-get update -qq && sudo apt-get install -y -qq python3 python3-pip python3-venv
fi

# 确保 venv 模块可用（Ubuntu 默认不装）
if ! python3 -m venv --help &>/dev/null; then
    warn "安装 python3-venv..."
    sudo apt-get install -y -qq python3-venv
fi

# git 安装源码包时需要
if ! command -v git &>/dev/null; then
    sudo apt-get install -y -qq git
fi

PYTHON_VERSION=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
log "Python $PYTHON_VERSION"

# ---- 2. 创建 venv ----
log "创建虚拟环境..."
sudo mkdir -p "$COGNEE_HOME"
sudo python3 -m venv "$COGNEE_VENV"
sudo chown -R "$COGNEE_USER:$COGNEE_USER" "$COGNEE_HOME"

# ---- 3. 安装 cognee + fastembed ----
log "安装 Cognee + FastEmbed（可能需要几分钟）..."
"$COGNEE_VENV/bin/pip" install --quiet "$COGNEE_SOURCE" fastembed

# ---- 4. 写 .env ----
log "写入环境配置..."
LLM_ENDPOINT="${COGNEE_LLM_ENDPOINT:-}"
if [[ "$COGNEE_LLM_PROVIDER" == "deepseek" && -z "$LLM_ENDPOINT" ]]; then
    LLM_ENDPOINT="https://api.deepseek.com"
fi

sudo tee "$COGNEE_ENV" > /dev/null << EOF
LLM_PROVIDER=$COGNEE_LLM_PROVIDER
LLM_MODEL=$COGNEE_LLM_MODEL
LLM_API_KEY=$COGNEE_API_KEY
LLM_ENDPOINT=$LLM_ENDPOINT
EMBEDDING_PROVIDER=$COGNEE_EMBEDDING_PROVIDER
EMBEDDING_MODEL=$COGNEE_EMBEDDING_MODEL
AUTO_FEEDBACK=true
COGNEE_AGENT_MODE=true
ENABLE_BACKEND_ACCESS_CONTROL=false
EOF
sudo chown "$COGNEE_USER:$COGNEE_USER" "$COGNEE_ENV"
sudo chmod 600 "$COGNEE_ENV"

# ---- 5. systemd 服务 ----
log "创建 systemd 服务..."
sudo tee /etc/systemd/system/cognee.service > /dev/null << SYSTEMDEOF
[Unit]
Description=Cognee Memory Server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$COGNEE_USER
WorkingDirectory=$COGNEE_HOME
EnvironmentFile=$COGNEE_ENV
ExecStart=$COGNEE_VENV/bin/uvicorn cognee.api.client:app --host 0.0.0.0 --port $COGNEE_PORT
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
SYSTEMDEOF

sudo systemctl daemon-reload
sudo systemctl enable cognee --now

# ---- 6. 等待健康检查 ----
log "等待 Cognee 就绪..."
for i in $(seq 1 30); do
    if curl -sf "http://127.0.0.1:$COGNEE_PORT/health" 2>/dev/null | grep -q '"ready"'; then
        break
    fi
    sleep 2
done

HEALTH=$(curl -sf "http://127.0.0.1:$COGNEE_PORT/health" 2>/dev/null || echo '{"status":"error"}')
echo "   $HEALTH"

if echo "$HEALTH" | grep -q '"ready"'; then
    log "Cognee 服务运行正常!"
else
    warn "Cognee 启动中，请稍后检查: journalctl -u cognee -n 20"
fi

# ---- 7. 输出 OpenClaw 配置片段 ----
# ---- 8. 自动配置 OpenClaw 插件 ----
COGNEE_HOME_DIR=$(eval echo ~$COGNEE_USER)
OPENCLAW_CONFIG="$COGNEE_HOME_DIR/.openclaw/openclaw.json"
if [[ -f "$OPENCLAW_CONFIG" ]]; then
    log "检测到 OpenClaw 配置，自动合并插件..."
    python3 -c "
import json, sys
plugin_config = {
    'allow': ['cognee-openclaw'],
    'entries': {
        'cognee-openclaw': {
            'enabled': True,
            'hooks': {'allowPromptInjection': True},
            'config': {
                'baseUrl': 'http://localhost:$COGNEE_PORT',
                'datasetName': 'agent_sessions',
                'autoRecall': True,
                'autoIndex': True,
                'enableSessions': True,
                'captureSession': True,
                'searchType': 'HYBRID_COMPLETION'
            }
        },
        'memory-core': {'enabled': False},
        'memory-lancedb': {'enabled': False}
    },
    'slots': {'memory': 'cognee-openclaw'}
}
with open('$OPENCLAW_CONFIG') as f:
    cfg = json.load(f)
cfg['plugins'] = plugin_config
with open('$OPENCLAW_CONFIG', 'w') as f:
    json.dump(cfg, f, indent=2)
print('ok')
" && log "OpenClaw 插件配置已合并" || warn "自动合并失败，请手动粘贴下方配置"
else
    warn "未找到 $OPENCLAW_CONFIG，跳过自动配置"
fi

echo ""
echo "╔══════════════════════════════════════╗"
echo "║   Cognee 服务已部署!                 ║"
echo "╚══════════════════════════════════════╝"
echo ""
echo "   健康检查:  http://127.0.0.1:$COGNEE_PORT/health"
echo "   日志:      sudo journalctl -u cognee -f"

if [[ -f "$OPENCLAW_CONFIG" ]]; then
    echo "   插件配置:  已自动合并到 $OPENCLAW_CONFIG"
    echo "   激活记忆:  openclaw gateway restart"
else
    echo ""
    echo "   ⚠  未检测到 OpenClaw，手动配置如下:"
    echo ""
    cat << PLUGINCONF
{
  "plugins": {
    "allow": ["cognee-openclaw"],
    "entries": {
      "cognee-openclaw": {
        "enabled": true,
        "hooks": { "allowPromptInjection": true },
        "config": {
          "baseUrl": "http://localhost:$COGNEE_PORT",
          "datasetName": "agent_sessions"
        }
      },
      "memory-core": { "enabled": false },
      "memory-lancedb": { "enabled": false }
    },
    "slots": { "memory": "cognee-openclaw" }
  }
}
PLUGINCONF
fi
echo ""
