#!/usr/bin/env bash

# ANSI 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # 重置颜色

# 最大并发数限制
MAX_JOBS=10

# 1. 查询策略中允许的区域限制
echo -e "${CYAN}=== 正在检查策略区域限制 (Policy Restriction) ===${NC}"
POLICY_RAW=$(az policy assignment list --query "[?name=='sys.regionrestriction'].parameters.listOfAllowedLocations.value" --output json 2>/dev/null)
ALLOWED_POLICY_REGIONS=$(echo "$POLICY_RAW" | grep -oE '"[a-zA-Z0-9]+"' | tr -d '"' | tr '[:upper:]' '[:lower:]' | sort -u)

# 2. 获取 Azure 所有支持的标准物理区域列表
echo -e "${CYAN}=== 正在查询标准物理区域 ===${NC}"
ALL_REGIONS=$(az account list-locations --query "[?metadata.regionType=='Physical'].name" --output tsv | tr '[:upper:]' '[:lower:]' | sort -u)

# 3. 判断目标区域
TARGET_REGIONS=()
if [ -n "$ALLOWED_POLICY_REGIONS" ]; then
    echo -e "${YELLOW}检测到策略限制，允许的区域为:${NC}"
    echo "$ALLOWED_POLICY_REGIONS"
    while read -r r; do [ -n "$r" ] && TARGET_REGIONS+=("$r"); done < <(echo "$ALLOWED_POLICY_REGIONS")
else
    echo -e "${YELLOW}未检测到策略限制，使用全部物理区域...${NC}"
    while read -r r; do [ -n "$r" ] && TARGET_REGIONS+=("$r"); done < <(echo "$ALL_REGIONS")
fi

TOTAL=${#TARGET_REGIONS[@]}
echo "=================================================="
echo "最终待部署区域总数: ${TOTAL} (最大并发上限: ${MAX_JOBS})"
echo "待部署区域列表: ${TARGET_REGIONS[*]}"
echo "=================================================="

if [ "$TOTAL" -eq 0 ]; then
    echo -e "${RED}未获取到待部署区域，请检查策略名称或账号权限。${NC}"
    exit 0
fi

WORKDIR=$(mktemp -d /tmp/azure_tts_async.XXXXXX)
trap 'rm -rf "$WORKDIR"' EXIT

# 单区域异步执行函数（带序号与总数前缀）
deploy_worker() {
    local REGION="$1"
    local IDX="$2"
    local TOT="$3"
    local PREFIX="[${IDX}/${TOT} ${REGION}]"

    local DATE
    DATE=$(date +%Y%m%d)
    local RANDOM_STR
    RANDOM_STR=$(tr -dc 'a-z0-9' < /dev/urandom | head -c 6)
    local NAME="${DATE}-${RANDOM_STR}"
    local RG_NAME="waz-${REGION}"

    # 毫秒级轻微错峰扰动
    sleep "0.$((RANDOM % 9 + 1))"

    echo "${PREFIX} >>> 开始创建资源组: ${RG_NAME}"
    az group create --name "$RG_NAME" --location "$REGION" --output json 2>&1 | sed "s/^/${PREFIX}-RG /"
    local RG_STATUS=${PIPESTATUS[0]}

    if [ $RG_STATUS -ne 0 ]; then
        echo -e "${RED}${PREFIX} [-] 资源组创建失败！${NC}"
        echo "FAILED|${REGION}|${RG_NAME}|RG_FAIL" > "${WORKDIR}/${REGION}.status"
        return
    fi

    echo "${PREFIX} >>> 开始创建语音服务: ${NAME} (F0)"
    az cognitiveservices account create \
        --name "$NAME" \
        --resource-group "$RG_NAME" \
        --kind SpeechServices \
        --sku F0 \
        --location "$REGION" \
        --yes \
        --output json 2>&1 | sed "s/^/${PREFIX}-COG /"
    local COG_STATUS=${PIPESTATUS[0]}

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

        echo -e "${GREEN}${PREFIX} [+] 创建成功！${NC}"
        echo "SUCCESS|${REGION}|${RG_NAME}|${NAME}|${ENDPOINT}|${KEY}" > "${WORKDIR}/${REGION}.status"
    else
        echo -e "${RED}${PREFIX} [-] 语音服务创建失败！${NC}"
        echo "FAILED|${REGION}|${RG_NAME}|COG_FAIL" > "${WORKDIR}/${REGION}.status"
    fi
}

echo -e "${CYAN}=== 开始并发部署 (并发窗口: ${MAX_JOBS}) ===${NC}"

# 使用 FIFO 命名管道控制并发上限
FIFO_PATH="${WORKDIR}/job_queue"
mkfifo "$FIFO_PATH"
exec 6<>"$FIFO_PATH"
rm -f "$FIFO_PATH"

# 填充令牌
for ((i=0; i<MAX_JOBS; i++)); do
    echo >&6
done

# 带索引派发任务
INDEX=0
for REGION in "${TARGET_REGIONS[@]}"; do
    ((INDEX++))
    read -r -u 6
    {
        deploy_worker "$REGION" "$INDEX" "$TOTAL"
        echo >&6
    } &
done

# 等待后台任务全部执行完成
wait
exec 6>&- # 关闭管道

echo "=================================================="
echo "所有任务执行完成，正在汇总结果..."

# 汇总与失败清理
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
            FAILED_LIST+=("${R_REGION}")
            CLEANUP_RGS+=("$R_RG")
        fi
    else
        FAILED_LIST+=("${REGION} (未知异常退出)")
        CLEANUP_RGS+=("waz-${REGION}")
    fi
done

# 清理失败的资源组
if [ ${#CLEANUP_RGS[@]} -gt 0 ]; then
    echo ""
    echo -e "${YELLOW}==================== 清理失败资源组 ====================${NC}"
    mapfile -t UNIQUE_CLEANUP_RGS < <(printf "%s\n" "${CLEANUP_RGS[@]}" | sort -u)
    for rg in "${UNIQUE_CLEANUP_RGS[@]}"; do
        echo "后台删除资源组: ${rg} ..."
        az group delete --name "$rg" --yes --no-wait
    done
fi

# 最终汇总展示
echo ""
echo "==================== 执行汇总 ===================="
echo -e "总数: ${TOTAL} | ${GREEN}成功: ${#SUCCESS_LIST[@]}${NC} | ${RED}失败: ${#FAILED_LIST[@]}${NC}"
echo "--------------------------------------------------"

if [ ${#SUCCESS_LIST[@]} -gt 0 ]; then
    echo -e "${GREEN}成功列表 (区域 | 资源组 | 名称 | Endpoint | Key):${NC}"
    for item in "${SUCCESS_LIST[@]}"; do
        echo -e "  ${GREEN}[✓] $item${NC}"
    done
fi

if [ ${#FAILED_LIST[@]} -gt 0 ]; then
    echo ""
    echo -e "${RED}失败列表 (${#FAILED_LIST[@]}):${NC}"
    for item in "${FAILED_LIST[@]}"; do
        echo -e "  ${RED}[✗] $item${NC}"
    done
fi
echo "=================================================="
