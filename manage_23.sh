#!/bin/bash

# 环境依赖检测与自动补齐
check_dep() {
    if [ ! -f "./udp2raw_amd64" ]; then
        echo "[*] 未检测到 udp2raw_amd64，正在下载安装..."
        wget -qO- https://github.com/wangyu-/udp2raw/releases/download/20230206.0/udp2raw_binaries.tar.gz | tar -zxv udp2raw_amd64 >/dev/null 2>&1
        chmod +x udp2raw_amd64
    fi
}

clean_process() {
    echo "[-] 正在终止已有加速进程..."
    pkill -9 -f speederv2_amd64 >/dev/null 2>&1
    pkill -9 -f udp2raw_amd64 >/dev/null 2>&1
    sleep 1
}

check_dep
clear
echo "=========================================================="
echo "         172.237.8.23 服务端加速方案管理"
echo "=========================================================="
echo "  [1] 模式一：仅使用 UDPspeeder (UDP 42698 -> 52698)"
echo "  [2] 模式二：仅使用 udp2raw    (TCP 52699 -> 52698)"
echo "  [3] 模式三：UDPspeeder + udp2raw 联合加速"
echo "  [4] 停止所有正在运行的加速进程"
echo "  [0] 退出脚本"
echo "=========================================================="
read -p "请输入选项编号 [0-4]: " choice

case "$choice" in
    1)
        clean_process
        echo "[+] 启动模式一：仅使用 UDPspeeder..."
        nohup ./speederv2_amd64 -s -l0.0.0.0:42698 -r127.0.0.1:52698 \
            -f20:10 -k "speeder_pass_23" --mode 1 -q 2 --timeout 30 --mtu 1450 > speeder.log 2>&1 &
        echo "[+] 启动成功！请确认防火墙/安全组已放行 UDP 42698 端口"
        ;;
    2)
        clean_process
        echo "[+] 启动模式二：仅使用 udp2raw..."
        nohup ./udp2raw_amd64 -s -l0.0.0.0:52699 -r127.0.0.1:52698 \
            -k "raw_pass_23" --raw-mode faketcp -a --cipher-mode none --auth-mode none > udp2raw.log 2>&1 &
        echo "[+] 启动成功！请确认防火墙/安全组已放行 TCP 52699 端口"
        ;;
    3)
        clean_process
        echo "[+] 启动模式三：联合加速部署中..."
        nohup ./speederv2_amd64 -s -l127.0.0.1:42698 -r127.0.0.1:52698 \
            -f20:10 -k "speeder_pass_23" --mode 1 -q 2 --timeout 30 --mtu 1450 > speeder.log 2>&1 &
        nohup ./udp2raw_amd64 -s -l0.0.0.0:52699 -r127.0.0.1:42698 \
            -k "raw_pass_23" --raw-mode faketcp -a --cipher-mode none --auth-mode none > udp2raw.log 2>&1 &
        echo "[+] 启动成功！请确认防火墙/安全组已放行 TCP 52699 端口"
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
