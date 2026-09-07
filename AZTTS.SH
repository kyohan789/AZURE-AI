#!/usr/bin/env bash

# 1. 设置资源组名称
RESOURCE_GROUP="waz-eastus2"

# 2. 查询策略中允许的区域限制
echo "=== 正在检查策略区域限制 (Policy Restriction) ==="
ALLOWED_POLICY_REGIONS=$(az policy assignment list \
    --query "[?name=='sys.regionrestriction'].parameters.listOfAllowedLocations.value[]" \
    --output tsv | sort -u | grep -v '^$')

# 3. 查询支持 SpeechServices 免费层 (F0) 的可用区域
echo "=== 正在查询支持 SpeechServices 免费层级 (F0) 的可用区域 ==="
SPEECH_REGIONS=$(az cognitiveservices account list-skus \
    --kind SpeechServices \
    --query "[?name=='F0'].locations[]" \
    --output tsv | sort -u | grep -v '^$')

# 4. 根据策略判断目标执行区域（如果有策略限制，取交集；否则取全部）
if [ -n "$ALLOWED_POLICY_REGIONS" ]; then
    echo "检测到策略区域限制，将仅在限制区域内匹配创建..."
    mapfile -t TARGET_REGIONS < <(comm -12 <(echo "$ALLOWED_POLICY_REGIONS") <(echo "$SPEECH_REGIONS"))
else
    echo "未检测到策略限制，将针对所有可用区域创建..."
    mapfile -t TARGET_REGIONS < <(echo "$SPEECH_REGIONS")
fi

TOTAL=${#TARGET_REGIONS[@]}
echo "最终待部署区域总数: ${TOTAL}"
echo "待部署区域列表: ${TARGET_REGIONS[*]}"
echo "=================================================="

if [ "$TOTAL" -eq 0 ]; then
    echo "没有需要创建的区域，脚本退出。"
    exit 0
fi

# 初始化统计变量与记录数组
SUCCESS_COUNT=0
FAILED_COUNT=0
declare -a SUCCESS_LIST=()
declare -a FAILED_LIST=()

# 5. 遍历并创建服务
CURRENT=0
for REGION in "${TARGET_REGIONS[@]}"; do
    ((CURRENT++))
    DATE=$(date +%Y%m%d)
    RANDOM_STR=$(tr -dc 'a-z0-9' < /dev/urandom | head -c 6)
    NAME="${DATE}-${RANDOM_STR}"

    echo ""
    echo "[${CURRENT}/${TOTAL}] 正在创建: ${NAME} (区域: ${REGION}, 层级: F0) ..."
    echo "--- 原始返回数据 ---"

    # 执行创建并保留原始输出
    az cognitiveservices account create \
        --name "$NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --kind SpeechServices \
        --sku F0 \
        --location "$REGION" \
        --yes \
        --output json

    STATUS=$?
    echo "--- 返回结束 ---"

    if [ $STATUS -eq 0 ]; then
        echo "状态: [成功]"
        ((SUCCESS_COUNT++))
        
        # 获取 Endpoint (URL)
        ENDPOINT=$(az cognitiveservices account show \
            --name "$NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --query "properties.endpoint" \
            --output tsv 2>/dev/null)

        # 获取 Key1
        KEY=$(az cognitiveservices account keys list \
            --name "$NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --query "key1" \
            --output tsv 2>/dev/null)

        SUCCESS_LIST+=("${REGION} | ${NAME} | ${ENDPOINT} | ${KEY}")
    else
        echo "状态: [失败]"
        ((FAILED_COUNT++))
        FAILED_LIST+=("${REGION}")
    fi
done

# 6. 执行结果汇总
echo ""
echo "==================== 执行汇总 ===================="
echo "总数: ${TOTAL} | 成功: ${SUCCESS_COUNT} | 失败: ${FAILED_COUNT}"
echo "--------------------------------------------------"

if [ ${#SUCCESS_LIST[@]} -gt 0 ]; then
    echo "成功列表 (区域 | 名称 | Endpoint | Key):"
    for item in "${SUCCESS_LIST[@]}"; do
        echo "  [✓] $item"
    done
fi

if [ ${#FAILED_LIST[@]} -gt 0 ]; then
    echo ""
    echo "失败列表 (${FAILED_COUNT}):"
    for item in "${FAILED_LIST[@]}"; do
        echo "  [✗] $item"
    done
fi
echo "=================================================="
