#!/bin/bash

# ==========================================================================
# 0. 动态读取策略受限区域列表（过滤 Windows 换行符 \r）
# ==========================================================================
echo "🔍 正在检查 Azure 策略受限区域..."
ALLOWED_REGIONS=()
raw_output=$(az policy assignment list \
  --query "[?name=='sys.regionrestriction'].parameters.listOfAllowedLocations.value" \
  -o tsv 2>/dev/null | tr -d '\r')

for r in $raw_output; do
    [ -n "$r" ] && ALLOWED_REGIONS+=("$r")
done

# ==========================================================================
# 区域选择菜单（支持多选）
# ==========================================================================
echo "=========================================================================="
echo " 请选择要部署的目标区域（支持多选，用空格或逗号分隔，如: 3 4 或 1,3）："
echo " [1] 美西组 (westus, westus2, westus3) [默认]"
echo " [2] 日本组 (japaneast, japanwest)"

# 动态打印策略受限区域选项（从序号 3 开始）
reg_count=${#ALLOWED_REGIONS[@]}
if [ "$reg_count" -gt 0 ]; then
    for ((i=0; i<reg_count; i++)); do
        opt_num=$((i + 3))
        echo " [$opt_num] 受限区域: ${ALLOWED_REGIONS[$i]}"
    done
fi
echo "=========================================================================="
read -r -p "请输入选项 [默认: 1]: " user_input

# 1. 默认值处理（回车默认 1）
if [ -z "$user_input" ]; then
    user_input="1"
fi

# 2. 清洗输入（去 \r，逗号替换为空格）
clean_input=$(echo "$user_input" | tr -d '\r' | tr ',' ' ')

SELECTED_REGIONS=()

# 3. 逐个解析选项（纯数组下标匹配，彻底抛弃关联数组）
for item in $clean_input; do
    if [ "$item" == "1" ]; then
        SELECTED_REGIONS+=("westus" "westus2" "westus3")
    elif [ "$item" == "2" ]; then
        SELECTED_REGIONS+=("japaneast" "japanwest")
    elif [[ "$item" =~ ^[0-9]+$ ]]; then
        target_idx=$((item - 3))
        if [ "$target_idx" -ge 0 ] && [ "$target_idx" -lt "$reg_count" ]; then
            SELECTED_REGIONS+=("${ALLOWED_REGIONS[$target_idx]}")
        else
            max_opt=$((reg_count + 2))
            echo "⚠️ 选项 $item 超出范围 (有效选项: 1 - $max_opt)"
        fi
    else
        echo "⚠️ 忽略无效输入: $item"
    fi
done

# 4. 兜底处理
if [ ${#SELECTED_REGIONS[@]} -eq 0 ]; then
    echo "⚠️ 未匹配到有效选项，默认使用美西组！"
    SELECTED_REGIONS=("westus" "westus2" "westus3")
fi

# 5. 数组去重
REGIONS=($(echo "${SELECTED_REGIONS[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))

# ==========================================================================
# 1. 定义部署机型与镜像配置
# ==========================================================================
SKUS=("Standard_B1s" "Standard_B2ats_v2" "Standard_B2pts_v2")

ADMIN_USER="aaa"
ADMIN_PASS='EApBqz9kJfYUmwLujMku'

# x86_64 与 ARM64 镜像 (Ubuntu 26.04 LTS 最新版)
IMAGE_X86="Canonical:ubuntu-26_04-lts:server:latest"
IMAGE_ARM64="Canonical:ubuntu-26_04-lts:server-arm64:latest"

# 临时结果记录目录 (用于跨子进程汇总)
RESULT_DIR=$(mktemp -d)
trap 'rm -rf "$RESULT_DIR"' EXIT

# ==========================================================================
# 2. 单个 VM 的完整创建函数
# ==========================================================================
deploy_vm() {
    local loc=$1
    local sku=$2

    # 生成 5 位随机小写字母和数字组合
    rand_suffix=$(cat /dev/urandom | tr -dc 'a-z0-9' | fold -w 5 | head -n 1)

    # 命名转换（带随机字符）
    sku_clean=$(echo "$sku" | tr '[:upper:]' '[:lower:]' | tr '_' '-')
    res_name="${loc}-${sku_clean}-${rand_suffix}"
    rg_name="rg-${res_name}"
    vm_name="vm-${res_name}"
    nsg_name="${vm_name}NSG"

    # 根据机型选择架构镜像
    if [[ "$sku" == *"pts"* ]]; then
        current_image="$IMAGE_ARM64"
    else
        current_image="$IMAGE_X86"
    fi

    echo "▶️  [开始] 区域: $loc | 机型: $sku (资源组: $rg_name)"

    # 1. 创建带随机后缀的独立资源组
    az group create \
      --name "$rg_name" \
      --location "$loc" \
      -o none 2>&1

    # 2. 创建虚拟机
    az vm create \
      --resource-group "$rg_name" \
      --name "$vm_name" \
      --location "$loc" \
      --image "$current_image" \
      --size "$sku" \
      --admin-username "$ADMIN_USER" \
      --admin-password "$ADMIN_PASS" \
      --os-disk-size-gb 64 \
      -o none 2>&1

    # 3. 状态校验与后续操作
    if [ $? -eq 0 ]; then
        # 创建全开放 NSG 规则
        az network nsg rule create \
          --resource-group "$rg_name" \
          --nsg-name "$nsg_name" \
          --name allow_all_inbound \
          --priority 100 \
          --direction Inbound \
          --access Allow \
          --protocol '*' \
          --source-address-prefixes '*' \
          --source-port-ranges '*' \
          --destination-address-prefixes '*' \
          --destination-port-ranges '*' \
          --description "Allow all inbound traffic (temporary - insecure)" \
          -o none 2>&1

        echo "✅ [成功] $vm_name 部署完成！"
        echo "$vm_name (区域: $loc, 机型: $sku, 资源组: $rg_name)" >> "$RESULT_DIR/success.log"
    else
        echo "❌ [失败] $vm_name 创建失败！正在后台清理/删除空资源组: $rg_name ..."
        echo "$vm_name (区域: $loc, 机型: $sku)" >> "$RESULT_DIR/failed.log"
        
        # 失败时立即后台异步清理空资源组
        az group delete \
          --name "$rg_name" \
          --yes \
          --no-wait \
          -o none 2>&1
    fi
}

# 导出函数及变量供子进程调用
export -f deploy_vm
export ADMIN_USER ADMIN_PASS IMAGE_X86 IMAGE_ARM64 RESULT_DIR

total_tasks=$((${#REGIONS[@]} * ${#SKUS[@]}))
echo "=========================================================================="
echo "🚀 已选定目标区域: ${REGIONS[*]}"
echo "🚀 正在并发启动共 $total_tasks 个 VM 的部署流程..."
echo "=========================================================================="

# 3. 双重循环并发启动所有任务
for loc in "${REGIONS[@]}"; do
    for sku in "${SKUS[@]}"; do
        deploy_vm "$loc" "$sku" &
    done
done

# 4. 等待所有后台任务执行完毕
echo "⏳ 所有任务已投递，正在后台并发建机中，请稍候..."
wait

echo "=========================================================================="
echo "🎉 所有并发部署任务已全部执行完毕！"
echo "=========================================================================="

# ==========================================================================
# 5. 汇总与统计结果
# ==========================================================================
touch "$RESULT_DIR/success.log" "$RESULT_DIR/failed.log"
success_count=$(wc -l < "$RESULT_DIR/success.log" | tr -d ' ')
failed_count=$(wc -l < "$RESULT_DIR/failed.log" | tr -d ' ')

echo ""
echo "📊 ================== 部署结果统计 =================="
echo "   总任务数: $total_tasks"
echo "   ✅ 成功数: $success_count"
echo "   ❌ 失败数: $failed_count"
echo "======================================================"

if [ "$success_count" -gt 0 ]; then
    echo -e "\n🟢 成功创建的虚拟机列表:"
    idx=1
    while IFS= read -r line; do
        echo "   [$idx] $line"
        ((idx++))
    done < "$RESULT_DIR/success.log"
fi

if [ "$failed_count" -gt 0 ]; then
    echo -e "\n🔴 创建失败的虚拟机列表:"
    idx=1
    while IFS= read -r line; do
        echo "   [$idx] $line"
        ((idx++))
    done < "$RESULT_DIR/failed.log"
fi

echo -e "\n🏁 汇总完毕！"
