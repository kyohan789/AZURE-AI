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

# 创建临时工作目录存储各并发任务的输出与结果
WORKDIR=$(mktemp -d /tmp/azure_tts_deploy.XXXXXX)
trap 'rm -rf "$WORKDIR"' EXIT

# 单区域部署任务函数（在子进程中并行执行）
deploy_region() {
    local REGION="$1"
    local INDEX="$2"
    local TOTAL="$3"
    local WORKDIR="$4"

    local DATE
    DATE=$(date +%Y%m%d)
    local RANDOM_STR
    RANDOM_STR=$(tr -dc 'a-z0-9' < /dev/urandom | head -c 6)
    local NAME="${DATE}-${RANDOM_STR}"
    local RG_NAME="waz-${REGION}"
    local LOG_FILE="${WORKDIR}/${REGION}.log"

    {
        echo "=================================================="
        echo "[${INDEX}/${TOTAL}] 开始部署区域: ${REGION}"
        echo ">>> [1/2] 正在创建/确认资源组: ${RG_NAME} ..."
        az group create --name "$RG_NAME" --location "$REGION" --output json
        local RG_STATUS=$?

        if [ $RG_STATUS -ne 0 ]; then
            echo "[-] 资源组 ${RG_NAME} 创建失败。"
            echo "FAILED|${REGION}|${RG_NAME}|RG_CREATE_FAIL" > "${WORKDIR}/${REGION}.status"
            echo "=================================================="
            return
        fi

        echo ">>> [2/2] 正在创建语音服务: ${NAME} (层级: F0) ..."
        az cognitiveservices account create \
            --name "$NAME" \
            --resource-group "$RG_NAME" \
            --kind SpeechServices \
            --sku F0 \
            --location "$REGION" \
            --yes \
            --output json
        local COG_STATUS=$?

        if [ $COG_STATUS -eq 0 ]; then
            local ENDPOINT
            ENDPOINT=$(az cognitiveservices account show \
                --name "$NAME" \
                --resource-group "$RG_NAME" \
                --query "properties.endpoint" \
                --output tsv 2>/dev/null)

            local KEY
            KEY=$(az cognitiveservices account keys list \
                --name "$NAME" \
                --resource-group "$RG_NAME" \
                --query "key1" \
                --output tsv 2>/dev/null)

            echo "[+] 区域 [${REGION}] 创建成功！"
            echo "SUCCESS|${REGION}|${RG_NAME}|${NAME}|${ENDPOINT}|${KEY}" > "${WORKDIR}/${REGION}.status"
        else
            echo "[-] 区域 [${REGION}] 语音服务创建失败，标记删除资源组: ${RG_NAME} ..."
            echo "FAILED|${REGION}|${RG_NAME}|SPEECH_CREATE_FAIL" > "${WORKDIR}/${REGION}.status"
        fi
        echo "=================================================="
    } > "$LOG_FILE" 2>&1

    # 实时打印该并发区域的完整原始返回日志
    cat "$LOG_FILE"
}

# 4. 并发拉起所有区域的部署任务
echo "正在异步并行部署所有目标区域..."
INDEX=0
for REGION in "${TARGET_REGIONS[@]}"; do
    ((INDEX++))
    deploy_region "$REGION" "$INDEX" "$TOTAL" "$WORKDIR" &
done

# 等待所有后台任务完成
wait
echo "所有异步任务执行完成，正在汇总结果..."

# 5. 解析结果与清理失败资源组
SUCCESS_LIST=()
FAILED_LIST=()
CLEANUP_RGS=()

for REGION in "${TARGET_REGIONS[@]}"; do
    STATUS_FILE="${WORKDIR}/${REGION}.status"
    if [ -f "$STATUS_FILE" ]; then
        IFS='|' read -r TYPE R_REGION R_RG R_NAME R_ENDPOINT R_KEY < "$STATUS_FILE"
        if [ "$TYPE" == "SUCCESS" ]; then
            SUCCESS_LIST+=("${R_REGION} | ${R_RG} | ${R_NAME} | ${R_ENDPOINT} | ${R_KEY}")
        else
            FAILED_LIST+=("${R_REGION} (${R_NAME})")
            CLEANUP_RGS+=("$R_RG")
        fi
    else
        FAILED_LIST+=("${REGION} (未知退出)")
        CLEANUP_RGS+=("waz-${REGION}")
    fi
done

# 异步清理失败的资源组
if [ ${#CLEANUP_RGS[@]} -gt 0 ]; then
    echo ""
    echo "==================== 清理失败资源组 ===================="
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
echo "总数: ${TOTAL} | 成功: ${#SUCCESS_LIST[@]} | 失败: ${#FAILED_LIST[@]}"
echo "--------------------------------------------------"

if [ ${#SUCCESS_LIST[@]} -gt 0 ]; then
    echo "成功列表 (区域 | 资源组 | 名称 | Endpoint | Key):"
    for item in "${SUCCESS_LIST[@]}"; do
        echo "  [✓] $item"
    done
fi

if [ ${#FAILED_LIST[@]} -gt 0 ]; then
    echo ""
    echo "失败列表 (${#FAILED_LIST[@]}):"
    for item in "${FAILED_LIST[@]}"; do
        echo "  [✗] $item"
    done
fi
echo "=================================================="
