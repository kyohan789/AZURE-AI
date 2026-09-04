#!/bin/bash

# ==========================================================================
# 0. 检查依赖与动态读取策略受限区域
# ==========================================================================
echo "🔍 正在检查 Azure 策略受限区域..."
ALLOWED_REGIONS=($(az policy assignment list \
  --query "[?name=='sys.regionrestriction'].parameters.listOfAllowedLocations.value[]" \
  -o tsv 2>/dev/null))

# ==========================================================================
# 区域选择菜单（支持多选）
# ==========================================================================
echo "=========================================================================="
echo " 请选择要部署的目标区域（支持多选，用空格或逗号分隔，如: 1 3 或 1,2,4）："
echo " [1] 美西组 (westus, westus2, westus3) [默认]"
echo " [2] 日本组 (japaneast, japanwest)"

# 动态生成策略受限区域选项（从序号 3 开始）
option_idx=3
declare -A DYNAMIC_OPTIONS

if [ ${#ALLOWED_REGIONS[@]} -gt 0 ]; then
    for reg in "${ALLOWED_REGIONS[@]}"; do
        echo " [$option_idx] 受限区域: $reg"
        DYNAMIC_OPTIONS["$option_idx"]="$reg"
        ((option_idx++))
    done
fi
echo "=========================================================================="
read -p "请输入选项 [默认: 1]: " choices

# 若直接按回车，默认为 1
if [ -z "$choices" ]; then
    choices="1"
fi

# 将逗号替换为空格并转为数组进行多选解析
choices=$(echo "$choices" | tr ',' ' ')
SELECTED_REGIONS=()

for choice in $choices; do
    case "$choice" in
        1)
            SELECTED_REGIONS+=("westus" "westus2" "westus3")
            ;;
        2)
            SELECTED_REGIONS+=("japaneast" "japanwest")
            ;;
        *)
            if [ -n "${DYNAMIC_OPTIONS[$choice]}" ]; then
                SELECTED_REGIONS+=("${DYNAMIC_OPTIONS[$choice]}")
            else
                echo "⚠️ 忽略无效选项: $choice"
            fi
            ;;
    esac
done

# 如果输入全无效，默认选 1
if [ ${#SELECTED_REGIONS[@]} -eq 0 ]; then
    echo "⚠️ 未匹配到有效选项，默认使用美西组！"
    SELECTED_REGIONS=("westus" "westus2" "westus3")
fi

# 数组去重
REGIONS=($(echo "${SELECTED_REGIONS[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))

# 1. 定义部署机型与镜像配置
SKUS=("Standard_B1s" "Standard_B2ats_v2" "Standard_B2pts_v2")

ADMIN_USER="aaa"
ADMIN_PASS='EApBqz9kJfYUmwLujMku'

# x86_64 与 ARM64 镜像 (Ubuntu 26.04 LTS 最新版)
IMAGE_X86="Canonical:ubuntu-26_04-lts:server:latest"
IMAGE_ARM64="Canonical:ubuntu-26_04-lts:server-arm64:latest"

# 临时结果记录目录 (用于跨子进程汇总)
RESULT_DIR=$(mktemp -d)
trap 'rm -rf "$RESULT_DIR"' EXIT

# 2. 单个 VM 的完整创建函数
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

    # 选择架构镜像
    if [[ "$sku" == *"pts"* ]]; then
        current_image="$IMAGE_ARM64"
    else
        current_image="$IMAGE_X86"
    fi

    echo "▶️  [开始] 区域: $loc | 机型: $sku (资源组: $rg_name)"

    # 1. 创建带随机后缀的资源组
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

    # 判断 VM 是否创建成功
    if [ $? -eq 0 ]; then
        # 3. 创建开放全部端口的 NSG 规则
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
        # 记录成功信息
        echo "$vm_name (区域: $loc, 机型: $sku, 资源组: $rg_name)" >> "$RESULT_DIR/success.log"
    else
        echo "❌ [失败] $vm_name 创建失败！正在后台清理/删除空资源组: $rg_name ..."
        # 记录失败信息
        echo "$vm_name (区域: $loc, 机型: $sku)" >> "$RESULT_DIR/failed.log"
        
        # 失败时立即清理该资源组 (--no-wait 不阻塞当前脚本)
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

# 4. 等待所有后台任务完成
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
