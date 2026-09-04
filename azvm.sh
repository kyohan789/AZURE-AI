#!/bin/bash

# ==========================================================================
# 主功能菜单：创建 VM / 删除资源组 / 查询 VM 清单
# ==========================================================================
echo "=========================================================================="
echo " 请选择操作模式："
echo " [1] 批量创建 VM (多选区域并发建机) [默认]"
echo " [2] 批量删除资源组 (支持多选 / 全部删除)"
echo " [3] 查询所有虚拟机 (IP、型号、区域，表格显示)"
echo "=========================================================================="
read -r -p "请输入模式 [1/2/3, 默认: 1]: " main_mode
main_mode=$(echo "$main_mode" | tr -d '\r')

# ==========================================================================
# 模式 3：查询所有虚拟机信息并以表格显示（无 PrivateIP）
# ==========================================================================
if [ "$main_mode" == "3" ]; then
    echo -e "\n🔍 正在查询当前订阅下所有虚拟机的详细信息..."
    
    az vm list -d --query "[].{
        Name: name,
        Location: location,
        Size: hardwareProfile.vmSize,
        PublicIP: publicIps,
        ResourceGroup: resourceGroup,
        PowerState: powerState
    }" -o table

    echo "=========================================================================="
    echo "🏁 查询完成！"
    exit 0
fi

# ==========================================================================
# 模式 2：删除资源组
# ==========================================================================
if [ "$main_mode" == "2" ]; then
    echo -e "\n🔍 正在获取当前订阅下的所有资源组..."
    ALL_RGS=()
    raw_rgs=$(az group list --query "[].name" -o tsv 2>/dev/null | tr -d '\r')

    for rg in $raw_rgs; do
        [ -n "$rg" ] && ALL_RGS+=("$rg")
    done

    rg_total=${#ALL_RGS[@]}
    if [ "$rg_total" -eq 0 ]; then
        echo "⚠️ 当前订阅下未找到任何资源组！"
        exit 0
    fi

    echo "=========================================================================="
    echo " 找到以下资源组（支持多选，用空格或逗号分隔，如: 1 3 或 1,2,4；输入 all 为全选）："
    for ((i=0; i<rg_total; i++)); do
        opt_num=$((i + 1))
        echo " [$opt_num] ${ALL_RGS[$i]}"
    done
    echo "=========================================================================="
    read -r -p "请输入要删除的资源组序号: " del_input
    clean_del_input=$(echo "$del_input" | tr -d '\r' | tr ',' ' ')

    TARGET_RGS=()
    if [ "$clean_del_input" == "all" ] || [ "$clean_del_input" == "ALL" ]; then
        TARGET_RGS=("${ALL_RGS[@]}")
    else
        for item in $clean_del_input; do
            if [[ "$item" =~ ^[0-9]+$ ]]; then
                idx=$((item - 1))
                if [ "$idx" -ge 0 ] && [ "$idx" -lt "$rg_total" ]; then
                    TARGET_RGS+=("${ALL_RGS[$idx]}")
                else
                    echo "⚠️ 序号 $item 超出范围 (有效范围: 1 - $rg_total)"
                fi
            else
                echo "⚠️ 忽略无效输入: $item"
            fi
        done
    fi

    TARGET_RGS=($(echo "${TARGET_RGS[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))

    if [ ${#TARGET_RGS[@]} -eq 0 ]; then
        echo "❌ 未选择任何有效的资源组，操作已取消。"
        exit 0
    fi

    echo -e "\n⚠️  【危险操作】即将删除以下 ${#TARGET_RGS[@]} 个资源组及其下所有资源："
    for r in "${TARGET_RGS[@]}"; do
        echo "  - $r"
    done
    read -r -p "确认彻底删除吗？(y/N): " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo "已取消删除操作。"
        exit 0
    fi

    echo -e "\n🗑️  正在并发提交删除请求到 Azure 后台..."
    for r in "${TARGET_RGS[@]}"; do
        az group delete --name "$r" --yes --no-wait -o none 2>&1
        echo "  ✔️ 已向 Azure 提交删除指令: $r (后台异步清理中)"
    done

    echo "=========================================================================="
    echo "🎉 所有选中资源组的删除任务已全部下发！"
    echo "=========================================================================="
    exit 0
fi

# ==========================================================================
# 模式 1：批量创建 VM
# ==========================================================================

# 0. 动态读取策略受限区域列表
echo -e "\n🔍 正在检查 Azure 策略受限区域..."
ALLOWED_REGIONS=()
raw_output=$(az policy assignment list \
  --query "[?name=='sys.regionrestriction'].parameters.listOfAllowedLocations.value" \
  -o tsv 2>/dev/null | tr -d '\r')

for r in $raw_output; do
    [ -n "$r" ] && ALLOWED_REGIONS+=("$r")
done

reg_count=${#ALLOWED_REGIONS[@]}

# 区域选择菜单（支持多选）
echo "=========================================================================="
echo " 请选择要部署的目标区域（支持多选，用空格或逗号分隔，如: 3 或 1 4 5）："
echo " [1] 美西组 (westus, westus2, westus3) [默认]"
echo " [2] 日本组 (japaneast, japanwest)"
if [ "$reg_count" -gt 0 ]; then
    echo " [3] 所有受限区域 (一键部署所有受限区域: ${ALLOWED_REGIONS[*]})"
    for ((i=0; i<reg_count; i++)); do
        opt_num=$((i + 4))
        echo " [$opt_num] 受限区域: ${ALLOWED_REGIONS[$i]}"
    done
fi
echo "=========================================================================="
read -r -p "请输入选项 [默认: 1]: " user_input

if [ -z "$user_input" ]; then
    user_input="1"
fi

clean_input=$(echo "$user_input" | tr -d '\r' | tr ',' ' ')
SELECTED_REGIONS=()

for item in $clean_input; do
    if [ "$item" == "1" ]; then
        SELECTED_REGIONS+=("westus" "westus2" "westus3")
    elif [ "$item" == "2" ]; then
        SELECTED_REGIONS+=("japaneast" "japanwest")
    elif [ "$item" == "3" ] && [ "$reg_count" -gt 0 ]; then
        SELECTED_REGIONS+=("${ALLOWED_REGIONS[@]}")
    elif [[ "$item" =~ ^[0-9]+$ ]] && [ "$reg_count" -gt 0 ]; then
        target_idx=$((item - 4))
        if [ "$target_idx" -ge 0 ] && [ "$target_idx" -lt "$reg_count" ]; then
            SELECTED_REGIONS+=("${ALLOWED_REGIONS[$target_idx]}")
        else
            max_opt=$((reg_count + 3))
            echo "⚠️ 选项 $item 超出范围 (有效选项: 1 - $max_opt)"
        fi
    else
        echo "⚠️ 忽略无效输入: $item"
    fi
done

if [ ${#SELECTED_REGIONS[@]} -eq 0 ]; then
    echo "⚠️ 未匹配到有效选项，默认使用美西组！"
    SELECTED_REGIONS=("westus" "westus2" "westus3")
fi

REGIONS=($(echo "${SELECTED_REGIONS[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))

# ==========================================================================
# 机型选择菜单：支持默认 3 款基础机型，支持单独勾选各规格 Fas_v7
# ==========================================================================
echo "=========================================================================="
echo " 请选择要部署的机型（支持多选，用空格或逗号分隔，如: 2 4 或 1,5）："
echo " [1] 基础三机型 (Standard_B1s, Standard_B2ats_v2, Standard_B2pts_v2) [默认]"
echo " [2] Standard_F2as_v7  (2核 8G  AMD Zen 5 全核无超线程)"
echo " [3] Standard_F4as_v7  (4核 16G AMD Zen 5 全核无超线程)"
echo " [4] Standard_F8as_v7  (8核 32G AMD Zen 5 全核无超线程)"
echo " [5] Standard_F16as_v7 (16核 64G AMD Zen 5 全核无超线程)"
echo " [6] Standard_F32as_v7 (32核 128G AMD Zen 5 全核无超线程)"
echo "=========================================================================="
read -r -p "请输入机型选项 [默认: 1]: " sku_input

if [ -z "$sku_input" ]; then
    sku_input="1"
fi

clean_sku_input=$(echo "$sku_input" | tr -d '\r' | tr ',' ' ')
SELECTED_SKUS=()

for s_item in $clean_sku_input; do
    case "$s_item" in
        1)
            SELECTED_SKUS+=("Standard_B1s" "Standard_B2ats_v2" "Standard_B2pts_v2")
            ;;
        2)
            SELECTED_SKUS+=("Standard_F2as_v7")
            ;;
        3)
            SELECTED_SKUS+=("Standard_F4as_v7")
            ;;
        4)
            SELECTED_SKUS+=("Standard_F8as_v7")
            ;;
        5)
            SELECTED_SKUS+=("Standard_F16as_v7")
            ;;
        6)
            SELECTED_SKUS+=("Standard_F32as_v7")
            ;;
        *)
            echo "⚠️ 忽略无效机型选项: $s_item"
            ;;
    esac
done

if [ ${#SELECTED_SKUS[@]} -eq 0 ]; then
    echo "⚠️ 未匹配到有效机型，默认使用基础三机型！"
    SELECTED_SKUS=("Standard_B1s" "Standard_B2ats_v2" "Standard_B2pts_v2")
fi

SKUS=($(echo "${SELECTED_SKUS[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))

ADMIN_USER="aaa"
ADMIN_PASS='EApBqz9kJfYUmwLujMku'

# x86_64 与 ARM64 镜像 (Ubuntu 26.04 LTS 最新版)
IMAGE_X86="Canonical:ubuntu-26_04-lts:server:latest"
IMAGE_ARM64="Canonical:ubuntu-26_04-lts:server-arm64:latest"

RESULT_DIR=$(mktemp -d)
trap 'rm -rf "$RESULT_DIR"' EXIT

deploy_vm() {
    local loc=$1
    local sku=$2

    rand_suffix=$(cat /dev/urandom | tr -dc 'a-z0-9' | fold -w 5 | head -n 1)

    sku_clean=$(echo "$sku" | tr '[:upper:]' '[:lower:]' | tr '_' '-')
    res_name="${loc}-${sku_clean}-${rand_suffix}"
    rg_name="rg-${res_name}"
    vm_name="vm-${res_name}"
    nsg_name="${vm_name}NSG"

    # 选择架构镜像 (pts 系列为 ARM64，其余 B 系列及 Fas_v7 均走 x86_64)
    if [[ "$sku" == *"pts"* ]]; then
        current_image="$IMAGE_ARM64"
    else
        current_image="$IMAGE_X86"
    fi

    echo "▶️  [开始] 区域: $loc | 机型: $sku (资源组: $rg_name)"

    # 1. 创建独立资源组
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

    # 3. 结果校验
    if [ $? -eq 0 ]; then
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
        
        az group delete \
          --name "$rg_name" \
          --yes \
          --no-wait \
          -o none 2>&1
    fi
}

export -f deploy_vm
export ADMIN_USER ADMIN_PASS IMAGE_X86 IMAGE_ARM64 RESULT_DIR

total_tasks=$((${#REGIONS[@]} * ${#SKUS[@]}))
echo "=========================================================================="
echo "🚀 已选定目标区域: ${REGIONS[*]}"
echo "🚀 已选定目标机型: ${SKUS[*]}"
echo "🚀 正在并发启动共 $total_tasks 个 VM 的部署流程..."
echo "=========================================================================="

for loc in "${REGIONS[@]}"; do
    for sku in "${SKUS[@]}"; do
        deploy_vm "$loc" "$sku" &
    done
done

echo "⏳ 所有任务已投递，正在后台并发建机中，请稍候..."
wait

echo "=========================================================================="
echo "🎉 所有并发部署任务已全部执行完毕！"
echo "=========================================================================="

# 汇总与统计结果
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
