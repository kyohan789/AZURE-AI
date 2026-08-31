#!/usr/bin/env bash

# 定义 ANSI 颜色转义码
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # 重置颜色

# 1. 显式注册 Provider 并等待完成
echo ">>> [1/7] 正在注册 Microsoft.CognitiveServices 提供程序..."
az provider register --namespace "Microsoft.CognitiveServices" --wait

# 2. 自动查询 Azure Policy 限制的允许区域
echo ">>> [2/7] 正在查询 Policy 限制的允许区域..."
POLICY_QUERY_RESULT=$(az policy assignment list --query "[?name=='sys.regionrestriction'].parameters.listOfAllowedLocations.value | [0]" -o json)

INPUT_LOCATIONS=()
if [ -n "$POLICY_QUERY_RESULT" ] && [ "$POLICY_QUERY_RESULT" != "null" ]; then
  while read -r loc; do
    [ -n "$loc" ] && INPUT_LOCATIONS+=("$loc")
  done < <(echo "$POLICY_QUERY_RESULT" | jq -r '.[]?')
fi

if [ ${#INPUT_LOCATIONS[@]} -eq 0 ]; then
  echo -e "${RED}[!] 未查询到 Policy 区域限制或结果为空，默认选用: eastus2${NC}"
  INPUT_LOCATIONS=("eastus2")
else
  echo -e "${GREEN}[+] 从 Policy 查询到的允许区域: ${INPUT_LOCATIONS[*]}${NC}"
fi

# 3. CognitiveServices 官方可用区域白名单
AVAILABLE_LOCATIONS=(
  "australiaeast" "brazilsouth" "westus" "westus2" "westeurope" "northeurope" 
  "southeastasia" "eastasia" "westcentralus" "southcentralus" "eastus" "eastus2" 
  "canadacentral" "japaneast" "centralindia" "uksouth" "japanwest" "koreacentral" 
  "francecentral" "northcentralus" "centralus" "southafricanorth" "uaenorth" 
  "swedencentral" "switzerlandnorth" "switzerlandwest" "germanywestcentral" 
  "norwayeast" "westus3" "jioindiawest" "qatarcentral" "canadaeast" "polandcentral" 
  "southindia" "italynorth" "spaincentral" "ukwest" "jioindiacentral"
)

# 4. 自动过滤区域
echo ">>> [3/7] 校验并过滤可用区域..."
LOCATIONS=()
for loc in "${INPUT_LOCATIONS[@]}"; do
  if [[ " ${AVAILABLE_LOCATIONS[*]} " =~ " ${loc} " ]]; then
    LOCATIONS+=("$loc")
  else
    echo -e "${RED}[-] 自动跳过 CognitiveServices 不支持的区域: $loc${NC}"
  fi
done

if [ ${#LOCATIONS[@]} -eq 0 ]; then
  echo -e "${RED}[!] 过滤后无符合条件的区域，强制使用默认区域: eastus2${NC}"
  LOCATIONS=("eastus2")
fi

echo -e "${GREEN}[+] 最终确认的部署区域: ${LOCATIONS[*]}${NC}"
echo ""

# 5. 29 个完整模型列表配置 ("部署名|模型名|版本|容量")
ALL_MODELS=(
  "gpt-5.5|gpt-5.5|2026-04-24|1000"
  "gpt-image-2|gpt-image-2|2026-04-21|2"
  "gpt-image-1.5|gpt-image-1.5|2025-12-16|9"
  "gpt-image-1|gpt-image-1|2025-04-15|3"
  "gpt-5.6-luna|gpt-5.6-luna|2026-07-09|1000"
  "gpt-5.6-sol|gpt-5.6-sol|2026-07-09|1000"
  "gpt-5.6-terra|gpt-5.6-terra|2026-07-09|1000"
  "gpt-5.4-nano|gpt-5.4-nano|2026-03-17|5000"
  "gpt-5.4-mini|gpt-5.4-mini|2026-03-17|1000"
  "gpt-5.4-pro|gpt-5.4-pro|2026-03-05|160"
  "gpt-5.4|gpt-5.4|2026-03-05|1000"
  "gpt-5.3-chat|gpt-5.3-chat|2026-03-03|1000"
  "gpt-5.3-codex|gpt-5.3-codex|2026-02-24|1000"
  "gpt-5.2-chat|gpt-5.2-chat|2026-02-10|1000"
  "gpt-5.2-codex|gpt-5.2-codex|2026-01-14|1000"
  "gpt-5.2|gpt-5.2|2025-12-11|1000"
  "gpt-5.1-codex-mini|gpt-5.1-codex-mini|2025-11-13|1000"
  "gpt-5.1-chat|gpt-5.1-chat|2025-11-13|1000"
  "gpt-5.1|gpt-5.1|2025-11-13|1000"
  "gpt-5-chat|gpt-5-chat|2025-10-03|1000"
  "gpt-5-codex|gpt-5-codex|2025-09-15|1000"
  "gpt-5-nano|gpt-5-nano|2025-08-07|5000"
  "gpt-5-mini|gpt-5-mini|2025-08-07|1000"
  "gpt-5|gpt-5|2025-08-07|1000"
  "gpt-4o|gpt-4o|2024-11-20|450"
  "gpt-4o-mini|gpt-4o-mini|2024-07-18|2000"
  "o4-mini|o4-mini|2025-04-16|1000"
  "o3|o3|2025-04-16|1000"
  "o3-mini|o3-mini|2025-01-31|500"
  "o1|o1|2024-12-17|500"
)

TOTAL_MODELS=${#ALL_MODELS[@]}
TOTAL_REGIONS=0
SUCCESS_REGIONS=0
FAILED_REGIONS=0
SUCCESS_ACCOUNTS=()

# 函数：单模型部署/校验 (含实时原始数据打印与彩色输出)
deploy_single_model() {
  local rg=$1
  local account=$2
  local dep_name=$3
  local model_name=$4
  local version=$5
  local capacity=$6
  local current_idx=$7

  echo -e "--- [服务器查询原始数据: $dep_name] ---"
  local existing=$(az cognitiveservices account deployment show --resource-group "$rg" --name "$account" --deployment-name "$dep_name")
  
  if [ -n "$existing" ]; then
    echo -e "${RED}  [=] [$current_idx/$TOTAL_MODELS] 部署 [$dep_name] 已存在，自动跳过。${NC}"
    return 0
  else
    echo -e "${GREEN}  [+] [$current_idx/$TOTAL_MODELS] 正在部署 [$dep_name] (版本: $version, 容量: $capacity)...${NC}"
    echo -e "--- [服务器响应原始数据: 正在提交部署 $dep_name] ---"
    
    az cognitiveservices account deployment create \
      --resource-group "$rg" \
      --name "$account" \
      --deployment-name "$dep_name" \
      --model-name "$model_name" \
      --model-version "$version" \
      --model-format OpenAI \
      --sku-name "GlobalStandard" \
      --sku-capacity "$capacity"
    
    local res=$?
    if [ $res -ne 0 ]; then
      echo -e "${RED}  [!] [$current_idx/$TOTAL_MODELS] 部署 [$dep_name] 失败！${NC}"
    else
      echo -e "${GREEN}  [✓] [$current_idx/$TOTAL_MODELS] 部署 [$dep_name] 成功！${NC}"
    fi
    return $res
  fi
}

# 6. 遍历各区域执行
echo ">>> [4/7] 开始遍历各区域环境配置与部署..."
for LOCATION in "${LOCATIONS[@]}"; do
  ((TOTAL_REGIONS++))
  RESOURCE_GROUP="waz-${LOCATION}"
  
  echo "=================================================="
  echo ">>> [区域处理] 当前检查区域: $LOCATION"

  echo "--- [服务器查询原始数据: 账号列表] ---"
  EXISTING_ACCOUNT_INFO=$(az cognitiveservices account list --query "[?location=='${LOCATION}'].{name:name, rg:resourceGroup} | [0]" -o json)

  ACCOUNT_NAME=""
  if [ -n "$EXISTING_ACCOUNT_INFO" ] && [ "$EXISTING_ACCOUNT_INFO" != "null" ]; then
    ACCOUNT_NAME=$(echo "$EXISTING_ACCOUNT_INFO" | jq -r '.name')
    RESOURCE_GROUP=$(echo "$EXISTING_ACCOUNT_INFO" | jq -r '.rg')
    echo -e "${RED}>>> [!] 区域 $LOCATION 已存在账户: $ACCOUNT_NAME (所属资源组: $RESOURCE_GROUP)${NC}"
  else
    echo ">>> 创建区域专用资源组: $RESOURCE_GROUP"
    echo "--- [服务器响应原始数据: 创建资源组] ---"
    az group create --name $RESOURCE_GROUP --location $LOCATION

    CURRENT_DATE=$(date +%Y%m%d)
    RANDOM_SUFFIX=$(tr -dc 'a-z0-9' < /dev/urandom | head -c 4)
    ACCOUNT_NAME="ai-${CURRENT_DATE}-${RANDOM_SUFFIX}-resource"

    echo ">>> 创建全新 AI 账号: $ACCOUNT_NAME"
    echo "--- [服务器响应原始数据: 创建账号] ---"
    az cognitiveservices account create \
      --name $ACCOUNT_NAME \
      --resource-group $RESOURCE_GROUP \
      --location $LOCATION \
      --kind "OpenAI" \
      --sku "S0" \
      --custom-domain $ACCOUNT_NAME

    if [ $? -ne 0 ]; then
      echo -e "${RED}>>> [!] 区域 $LOCATION 创建账号失败，跳过后续部署。${NC}"
      ((FAILED_REGIONS++))
      echo ""
      continue
    fi
  fi

  # --- [5/7] 部署/验证前置门槛模型 ---
  echo ">>> [5/7] 正在验证前置门槛模型 (gpt-image-2 / gpt-5.6-luna)..."
  
  deploy_single_model "$RESOURCE_GROUP" "$ACCOUNT_NAME" "gpt-image-2" "gpt-image-2" "2026-04-21" "2" "1"
  IMG2_RES=$?

  deploy_single_model "$RESOURCE_GROUP" "$ACCOUNT_NAME" "gpt-5.6-luna" "gpt-5.6-luna" "2026-07-09" "1000" "4"
  LUNA_RES=$?

  if [ $IMG2_RES -ne 0 ] && [ $LUNA_RES -ne 0 ]; then
    echo -e "${RED}>>> [!] 门槛模型 gpt-image-2 与 gpt-5.6-luna 均部署失败，终止该区域后续模型部署。${NC}"
    ((FAILED_REGIONS++))
    echo ""
    continue
  fi

  # --- [6/7] 批量部署剩余 27 个模型 ---
  echo -e "${GREEN}>>> [6/7] 前置验证通过！开始批量部署其余 27 个模型...${NC}"

  MODEL_COUNTER=0
  for model_info in "${ALL_MODELS[@]}"; do
    ((MODEL_COUNTER++))
    IFS='|' read -r dep_name model_name version capacity <<< "$model_info"
    
    # 跳过门槛模型
    if [ "$dep_name" == "gpt-image-2" ] || [ "$dep_name" == "gpt-5.6-luna" ]; then
      continue
    fi

    deploy_single_model "$RESOURCE_GROUP" "$ACCOUNT_NAME" "$dep_name" "$model_name" "$version" "$capacity" "$MODEL_COUNTER"
  done

  SUCCESS_ACCOUNTS+=("${RESOURCE_GROUP}|${ACCOUNT_NAME}|${LOCATION}")
  ((SUCCESS_REGIONS++))
  echo ""
done

# --- [7/7] 输出汇总结果与凭据清单 ---
echo "=================================================="
echo ">>> [7/7] 任务执行结果汇总与凭据打印"
echo "=================================================="
echo "尝试处理区域总数 : $TOTAL_REGIONS"
echo -e "部署成功/符合条件: ${GREEN}$SUCCESS_REGIONS${NC}"
echo -e "部署失败/门槛未过: ${RED}$FAILED_REGIONS${NC}"
echo "=================================================="
echo ""

if [ ${#SUCCESS_ACCOUNTS[@]} -gt 0 ]; then
  echo "=================================================="
  echo "             全局账号凭据与成功模型清单           "
  echo "=================================================="
  for acc in "${SUCCESS_ACCOUNTS[@]}"; do
    IFS='|' read -r rg name loc <<< "$acc"
    
    echo "--- [服务器查询原始数据: 账号 Endpoints 与 Keys] ---"
    endpoint=$(az cognitiveservices account show --resource-group "$rg" --name "$name" --query "properties.endpoint" -o tsv)
    key=$(az cognitiveservices account keys list --resource-group "$rg" --name "$name" --query "key1" -o tsv)
    
    echo "--- [服务器查询原始数据: 部署列表] ---"
    DEPLOYED_JSON=$(az cognitiveservices account deployment list --resource-group "$rg" --name "$name" --query "[].name" -o json)
    SUCCESSFUL_MODELS=$(echo "$DEPLOYED_JSON" | jq -r 'join(", ")')
    SUCCESSFUL_COUNT=$(echo "$DEPLOYED_JSON" | jq -r 'length')

    echo -e "[区域]: $loc"
    echo -e "  账号名称: $name"
    echo -e "  URL Endpoint: ${GREEN}$endpoint${NC}"
    echo -e "  Primary Key : ${GREEN}$key${NC}"
    echo -e "  成功模型数量: ${GREEN}${SUCCESSFUL_COUNT:-0}${NC} / ${TOTAL_MODELS}"
    echo -e "  成功模型列表: ${GREEN}${SUCCESSFUL_MODELS:-无}${NC}"
    echo "--------------------------------------------------"
  done
fi
