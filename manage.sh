#!/bin/bash

DEFAULT_PORT=11885

# 自动探测 Hysteria 2 监听端口 (兼容 IPv4 与 IPv6 udp6)
detect_hysteria_port() {
    local port=""
    
    # 方案 1: ss 命令 (支持 udp4 和 udp6)
    if command -v ss >/dev/null 2>&1; then
        port=$(ss -uanp 2>/dev/null | grep -iE 'hysteria|hy2' | grep -oE ':[0-9]+' | tr -d ':' | head -n 1)
    fi

    # 方案 2: netstat 命令 (备用)
    if [ -z "$port" ] && command -v netstat >/dev/null 2>&1; then
        port=$(netstat -uanp 2>/dev/null | grep -iE 'hysteria|hy2' | grep -oE ':[0-9]+' | tr -d ':' | head -n 1)
    fi

    # 方案 3: lsof 命令 (备用)
    if [ -z "$port" ] && command -v lsof >/dev/null 2>&1; then
        port=$(lsof -iUDP -n -P 2>/dev/null | grep -iE 'hysteria|hy2' | grep -oE ':[0-9]+' | tr -d ':' | head -n 1)
    fi

    # 方案 4: 直接从进程 PID 关联文件描述符探测 (终极保底)
    if [ -z "$port" ]; then
        local pid=$(pgrep -i -f hysteria | head -n 1)
        if [ -n "$pid" ] && [ -d "/proc/$pid/net" ]; then
            local hex_port=$(awk '$2 ~ /^[0-9A-F]+:[0-9A-F]+/ {print $2}' /proc/$pid/net/udp* 2>/dev/null | awk -F':' '{print $2}' | head -n 1)
            if [ -n "$hex_port" ]; then
                port=$((16#$hex_port))
            fi
        fi
    fi

    if [ -n "$port" ] && [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -gt 0 ]; then
        HY2_PORT="$port"
        echo "[+] 成功探测到 Hysteria 2 活跃监听端口: ${HY2_PORT}"
    else
        HY2_PORT="$DEFAULT_PORT"
        echo "[-] 未自动探测到端口，使用默认端口: ${HY2_PORT}"
    fi
}

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
detect_hysteria_port

clear
echo "=========================================================="
echo "          Hysteria 2 通用服务端加速方案管理"
echo "          (已自动对齐目标服务端口: ${HY2_PORT})"
echo "=========================================================="
echo "  [1] 模式一：仅使用 UDPspeeder (UDP 21885 -> ${HY2_PORT})"
echo "  [2] 模式二：仅使用 udp2raw    (TCP 31885 -> ${HY2_PORT})"
echo "  [3] 模式三：UDPspeeder + udp2raw 联合加速"
echo "  [4] 停止所有正在运行的加速进程"
echo "  [0] 退出脚本"
echo "=========================================================="
read -p "请输入选项编号 [0-4]: " choice

case "$choice" in
    1)
        clean_process
        echo "[+] 启动模式一：仅使用 UDPspeeder..."
        nohup ./speederv2_amd64 -s -l0.0.0.0:21885 -r127.0.0.1:${HY2_PORT} \
            -f20:10 -k "speeder_pass_all" --mode 1 -q 2 --timeout 30 --mtu 1450 > speeder.log 2>&1 &
        echo "[+] 启动成功！已转发至 127.0.0.1:${HY2_PORT}，请确认防火墙放行 UDP 21885"
        ;;
    2)
        clean_process
        echo "[+] 启动模式二：仅使用 udp2raw..."
        nohup ./udp2raw_amd64 -s -l0.0.0.0:31885 -r127.0.0.1:${HY2_PORT} \
            -k "raw_pass_all" --raw-mode faketcp -a --cipher-mode none --auth-mode none --mtu-warn 1500 > udp2raw.log 2>&1 &
        echo "[+] 启动成功！已转发至 127.0.0.1:${HY2_PORT}，请确认防火墙放行 TCP 31885"
        ;;
    3)
        clean_process
        echo "[+] 启动模式三：联合加速部署中..."
        nohup ./speederv2_amd64 -s -l127.0.0.1:21885 -r127.0.0.1:${HY2_PORT} \
            -f20:10 -k "speeder_pass_all" --mode 1 -q 2 --timeout 30 --mtu 1450 > speeder.log 2>&1 &
        nohup ./udp2raw_amd64 -s -l0.0.0.0:31885 -r127.0.0.1:21885 \
            -k "raw_pass_all" --raw-mode faketcp -a --cipher-mode none --auth-mode none --mtu-warn 1500 > udp2raw.log 2>&1 &
        echo "[+] 启动成功！已串联转发至 127.0.0.1:${HY2_PORT}，请确认防火墙放行 TCP 31885"
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
