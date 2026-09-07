#!/usr/bin/env bash

# 1. 查询策略中允许的区域限制
echo "=== 正在检查策略区域限制 (Policy Restriction) ==="
POLICY_RAW=$(az policy assignment list --query "[?name=='sys.regionrestriction'].parameters.listOfAllowedLocations.value" --output json 2>/dev/null)

# 提取双引号内的区域代码，转小写、去空格
ALLOWED_POLICY_REGIONS=$(echo "$POLICY_RAW" | grep -oE '"[a-zA-Z0-9]+"' | tr -d '"' | tr '[:upper:]' '[:lower:]' | sort -u)

# 2. 获取 Azure 所有支持的标准物理区域列表
echo "=== 正在查询标准物理区域 ==="
ALL_REGIONS=$(az account list-locations --query "[?metadata.regionType=='Physical'].name" --output tsv | tr '[:upper:]' '[:lower:]' | sort -u)

# 3. 判断目标区域
TARGET_REGIONS=()
if [ -n "$ALLOWED_POLICY_REGIONS" ]; then
    echo "检测到策略限制，允许的区域为:"
    echo "$ALLOWED_POLICY_REGIONS"
    
    while read -r r; do
        [ -n "$r" ] && TARGET_REGIONS+=("$r")
    done < <(echo "$ALLOWED_POLICY_REGIONS")
else
    echo "未检测到策略限制，使用全部物理区域..."
    while read -r r; do
        [ -n "$r" ] && TARGET_REGIONS+=("$r")
    done < <(echo "$ALL_REGIONS")
fi

TOTAL=${#TARGET_REGIONS[@]}
echo "=================================================="
echo "最终待部署区域总数: ${TOTAL}"
echo "待部署区域列表: ${TARGET_REGIONS[*]}"
echo "=================================================="

if [ "$TOTAL" -eq 0 ]; then
    echo "未获取到待部署区域，请检查策略名称或账号权限。"
    exit 0
fi

# 初始化统计变量与记录数组
SUCCESS_COUNT=0
FAILED_COUNT=0
declare -a SUCCESS_LIST=()
declare -a FAILED_LIST=()
declare -a CLEANUP_RGS=()

# 4. 遍历区域：先创建该区域资源组，再创建语音服务
CURRENT=0
for REGION in "${TARGET_REGIONS[@]}"; do
    ((CURRENT++))
    DATE=$(date +%Y%m%d)
    RANDOM_STR=$(tr -dc 'a-z0-9' < /dev/urandom | head -c 6)
    NAME="${DATE}-${RANDOM_STR}"
    RG_NAME="waz-${REGION}"

    echo ""
    echo "[${CURRENT}/${TOTAL}] 准备区域: ${REGION}"
    echo ">>> [1/2] 正在创建/确认资源组: ${RG_NAME} ..."
    
    az group create \
        --name "$RG_NAME" \
        --location "$REGION" \
        --output json

    RG_STATUS=$?
    if [ $RG_STATUS -ne 0 ]; then
        echo "资源组创建失败，记录清理并跳过该区域部署。"
        ((FAILED_COUNT++))
        FAILED_LIST+=("${REGION} (资源组创建失败)")
        CLEANUP_RGS+=("$RG_NAME")
        continue
    fi

    echo ">>> [2/2] 正在创建语音服务: ${NAME} (资源组: ${RG_NAME}, 层级: F0) ..."
    echo "--- 原始返回数据 ---"

    az cognitiveservices account create \
        --name "$NAME" \
        --resource-group "$RG_NAME" \
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
        
        ENDPOINT=$(az cognitiveservices account show \
            --name "$NAME" \
            --resource-group "$RG_NAME" \
            --query "properties.endpoint" \
            --output tsv 2>/dev/null)

        KEY=$(az cognitiveservices account keys list \
            --name "$NAME" \
            --resource-group "$RG_NAME" \
            --query "key1" \
            --output tsv 2>/dev/null)

        SUCCESS_LIST+=("${REGION} | ${RG_NAME} | ${NAME} | ${ENDPOINT} | ${KEY}")
    else
        echo "状态: [失败]"
        ((FAILED_COUNT++))
        FAILED_LIST+=("${REGION} (语音服务创建失败)")
        CLEANUP_RGS+=("$RG_NAME")
    fi
done

# 5. 清理创建失败的资源组
if [ ${#CLEANUP_RGS[@]} -gt 0 ]; then
    echo ""
    echo "==================== 清理失败资源组 ===================="
    # 去重处理
    mapfile -t UNIQUE_CLEANUP_RGS < <(printf "%s\n" "${CLEANUP_RGS[@]}" | sort -u)
    for rg in "${UNIQUE_CLEANUP_RGS[@]}"; do
        echo "正在后台删除失败资源组: ${rg} ..."
        az group delete --name "$rg" --yes --no-wait
    done
    echo "已触发所有失败资源组的后台删除操作 (--no-wait)。"
fi

# 6. 执行结果汇总
echo ""
echo "==================== 执行汇总 ===================="
echo "总数: ${TOTAL} | 成功: ${SUCCESS_COUNT} | 失败: ${FAILED_COUNT}"
echo "--------------------------------------------------"

if [ ${#SUCCESS_LIST[@]} -gt 0 ]; then
    echo "成功列表 (区域 | 资源组 | 名称 | Endpoint | Key):"
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
