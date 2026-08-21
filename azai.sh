#!/usr/bin/env bash

# 1. 查询订阅下所有的 CognitiveServices / OpenAI 账户
echo ">>> 正在获取所有 AI 账户列表..."
ACCOUNTS_JSON=$(az cognitiveservices account list --query "[].[name, resourceGroup, location]" -o json)

ACCOUNT_COUNT=$(echo "$ACCOUNTS_JSON" | jq '. | length')
if [ "$ACCOUNT_COUNT" -eq 0 ]; then
  echo "[!] 未找到任何 AI 账户，脚本退出。"
  exit 1
fi

echo "[+] 共找到 $ACCOUNT_COUNT 个 AI 账户，开始逐一部署模型..."
echo ""

# 2. 遍历每个账户并连续部署两个模型
echo "$ACCOUNTS_JSON" | jq -c '.[]' | while read -r item; do
  ACCOUNT_NAME=$(echo "$item" | jq -r '.[0]')
  RESOURCE_GROUP=$(echo "$item" | jq -r '.[1]')
  LOCATION=$(echo "$item" | jq -r '.[2]')

  echo "=================================================="
  echo ">>> 目标账户: $ACCOUNT_NAME ($LOCATION)"

  # --- 部署模型 1: gpt-image-2 ---
  echo ">>> [1/2] 正在部署 gpt-image-2 (配额: 2)..."
  az cognitiveservices account deployment create \
    --resource-group "$RESOURCE_GROUP" \
    --name "$ACCOUNT_NAME" \
    --deployment-name "gpt-image-2" \
    --model-name "gpt-image-2" \
    --model-version "2026-04-21" \
    --model-format OpenAI \
    --sku-name "GlobalStandard" \
    --sku-capacity 2 \
    --output table

  # --- 部署模型 2: gpt-5.6-luna ---
  echo ">>> [2/2] 正在部署 gpt-5.6-luna (配额: 1000)..."
  az cognitiveservices account deployment create \
    --resource-group "$RESOURCE_GROUP" \
    --name "$ACCOUNT_NAME" \
    --deployment-name "gpt-5.6-luna" \
    --model-name "gpt-5.6-luna" \
    --model-version "2026-07-09" \
    --model-format OpenAI \
    --sku-name "GlobalStandard" \
    --sku-capacity 1000 \
    --output table

  echo ""
done
