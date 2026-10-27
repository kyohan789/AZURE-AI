#!/bin/bash

# 清理原有残留进程
clean_process() {
    echo "[-] 正在终止已有加速进程..."
    pkill -9 -f speederv2_amd64 >/dev/null 2>&1
    pkill -9 -f udp2raw_amd64 >/dev/null 2>&1
    sleep 1
}

clear
echo "=========================================================="
echo "         172.238.34.148 服务端加速方案选择"
echo "=========================================================="
echo "  [1] 模式一：仅使用 UDPspeeder (UDP 21885 -> 11885)"
echo "  [2] 模式二：仅使用 udp2raw    (TCP 31885 -> 11885)"
echo "  [3] 模式三：UDPspeeder + udp2raw 联合加速"
echo "  [4] 停止所有正在运行的加速进程"
echo "  [0] 退出脚本"
echo "=========================================================="
read -p "请输入选项编号 [0-4]: " choice

case "$choice" in
    1)
        clean_process
        echo "[+] 启动模式一：仅使用 UDPspeeder..."
        nohup ./speederv2_amd64 -s -l0.0.0.0:21885 -r127.0.0.1:11885 \
            -f20:10 -k "speeder_pass_148" --mode 1 -q 2 --timeout 30 --mtu 1450 > speeder.log 2>&1 &
        echo "[+] 启动成功！请确认云控制台安全组已放行 UDP 21885 端口"
        ;;
    2)
        clean_process
        echo "[+] 启动模式二：仅使用 udp2raw..."
        nohup ./udp2raw_amd64 -s -l0.0.0.0:31885 -r127.0.0.1:11885 \
            -k "raw_pass_148" --raw-mode faketcp -a --cipher-mode none --auth-mode none --mtu 1450 > udp2raw.log 2>&1 &
        echo "[+] 启动成功！请确认云控制台安全组已放行 TCP 31885 端口"
        ;;
    3)
        clean_process
        echo "[+] 启动模式三：联合加速部署中..."
        # 内部转发层
        nohup ./speederv2_amd64 -s -l127.0.0.1:21885 -r127.0.0.1:11885 \
            -f20:10 -k "speeder_pass_148" --mode 1 -q 2 --timeout 30 --mtu 1450 > speeder.log 2>&1 &
        # 外网伪装层
        nohup ./udp2raw_amd64 -s -l0.0.0.0:31885 -r127.0.0.1:21885 \
            -k "raw_pass_148" --raw-mode faketcp -a --cipher-mode none --auth-mode none --mtu 1450 > udp2raw.log 2>&1 &
        echo "[+] 启动成功！请确认云控制台安全组已放行 TCP 31885 端口"
        ;;
    4)
        clean_process
        echo "[+] 所有加速进程已成功停止！"
        ;;
    0)
        echo "[*] 操作已取消，退出脚本。"
        exit 0
        ;;
    *)
        echo "[!] 输入错误，请输入 0 到 4 之间的数字。"
        exit 1
        ;;
esac
