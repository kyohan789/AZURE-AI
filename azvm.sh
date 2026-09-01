#!/bin/bash

# ==========================================================================
# 区域选择菜单
# ==========================================================================
echo "=========================================================================="
echo " 请选择要部署的目标区域组："
echo " [1] 美西组 (westus, westus2, westus3) [默认]"
echo " [2] 日本组 (japaneast, japanwest)"
echo "=========================================================================="
read -p "请输入选项 [1/2, 默认: 1]: " choice

# 处理默认选项与输入匹配
case "$choice" in
    2)
        REGIONS=("japaneast" "japanwest")
        group_name="日本组 (japaneast, japanwest)"
        ;;
    1|"")
        REGIONS=("westus" "westus2" "westus3")
        group_name="美西组 (westus, westus2, westus3)"
        ;;
    *)
        echo "⚠️ 输入无效，默认使用美西组！"
        REGIONS=("westus" "westus2" "westus3")
        group_name="美西组 (westus, westus2, westus3)"
        ;;
esac

# 1. 定义部署机型与镜像配置
SKUS=("Standard_B1s" "Standard_B2ats_v2" "Standard_B2pts_v2")

ADMIN_USER="aaa"
ADMIN_PASS='EApBqz9kJfYUmwLujMku'

# x86_64 与 ARM64 镜像 (Ubuntu 26.04 LTS 最新版)
IMAGE_X86="Canonical:ubuntu-26_04-lts:server:latest"
IMAGE_ARM64="Canonical:ubuntu-26_04-lts:server-arm64:latest"

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
    else
        echo "❌ [失败] $vm_name 创建失败！正在后台清理/删除空资源组: $rg_name ..."
        
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
export ADMIN_USER ADMIN_PASS IMAGE_X86 IMAGE_ARM64

total_tasks=$((${#REGIONS[@]} * ${#SKUS[@]}))
echo "=========================================================================="
echo "🚀 目标区域: $group_name"
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
