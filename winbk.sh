# 0. 环境依赖预检 (存在则跳过，缺失则自动静默安装)
if ! command -v zstd >/dev/null 2>&1; then
  echo "[0/4] 检测到未安装 zstd，正在自动部署多线程 zstd..."
  mkdir -p /tmp/zstd_tmp && cd /tmp/zstd_tmp
  curl -sSL "https://github.com/facebook/zstd/releases/download/v1.5.6/zstd-v1.5.6-win64.zip" -o zstd.zip
  unzip -q -o zstd.zip
  cp zstd-v1.5.6-win64/zstd.exe /usr/bin/zstd.exe
  chmod +x /usr/bin/zstd.exe
  cd / && rm -rf /tmp/zstd_tmp
  echo "      -> zstd 部署成功: $(zstd --version)"
else
  echo "[0/4] 检测到系统已安装 zstd，直接跳过安装环节。"
fi

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
ARCHIVE_FILE="/c/backup_${TIMESTAMP}.tar.zst"
OUT_LOG="/c/tar_output_${TIMESTAMP}.log"
ERR_LOG="/c/tar_error_${TIMESTAMP}.log"
SKIP_LOG="/c/tar_skipped_${TIMESTAMP}.log"
TOTAL_START=$SECONDS

echo "[1/4] 扫描 Desktop 与 Downloads 实际总项目数与排除清单..."
STEP1_START=$SECONDS
TOTAL_ITEMS=$(find /c/Users/Administrator/Desktop /c/Users/Administrator/Downloads 2>/dev/null | wc -l)
find /c/Users/Administrator/Desktop /c/Users/Administrator/Downloads \( \
  -name "*0515.7z" \
  -o -name "*MT4.7z*" \
  -o -name "*MS.7z*" \
  -o -name "*AI-1.7z*" \
  -o -name "*.csv" \
  -o -path "*/Logs/*" \
  -o -path "*MTD_TJ*" \
  -o -name "*.hst" \
  -o -name "*.hcc" \
  -o -name "*.hc" \
\) > "$SKIP_LOG" 2>/dev/null
STEP1_TIME=$(( SECONDS - STEP1_START ))
echo "      -> 第 1 步完成，用时: $((STEP1_TIME / 60)) 分 $((STEP1_TIME % 60)) 秒 (${STEP1_TIME}s)"

echo "[2/4] 启用全核心多线程并发打包到 ${ARCHIVE_FILE}..."
STEP2_START=$SECONDS
tar --warning=no-file-changed \
    --exclude="*0515.7z" \
    --exclude="*MT4.7z*" \
    --exclude="*MS.7z*" \
    --exclude="*AI-1.7z*" \
    --exclude="*.csv" \
    --exclude="*/Logs/*" \
    --exclude="*MTD_TJ*" \
    --exclude="*.hst" \
    --exclude="*.hcc" \
    --exclude="*.hc" \
  -I 'zstd -1 -T0' \
  -cvf "$ARCHIVE_FILE" \
  -C /c/Users/Administrator Desktop Downloads \
  > "$OUT_LOG" 2> "$ERR_LOG"
RAW_STATUS=$?
if [ $RAW_STATUS -le 1 ]; then
  TAR_STATUS=0
else
  TAR_STATUS=$RAW_STATUS
fi
STEP2_TIME=$(( SECONDS - STEP2_START ))
echo "      -> 第 2 步完成，用时: $((STEP2_TIME / 60)) 分 $((STEP2_TIME % 60)) 秒 (${STEP2_TIME}s)"

echo "[3/4] 验证数据流与文件完整性..."
STEP3_START=$SECONDS
tar -I 'zstd -d' -tf "$ARCHIVE_FILE" > /dev/null 2>&1 && CHECK_RES="通过" || CHECK_RES="失败"
STEP3_TIME=$(( SECONDS - STEP3_START ))
echo "      -> 第 3 步完成，用时: $((STEP3_TIME / 60)) 分 $((STEP3_TIME % 60)) 秒 (${STEP3_TIME}s)"

echo "[4/4] 正在比对核查总项目数一致性..."
STEP4_START=$SECONDS
PACKED_COUNT=$(wc -l < "$OUT_LOG")
SKIPPED_COUNT=$(wc -l < "$SKIP_LOG")
ACCOUNTED=$(( PACKED_COUNT + SKIPPED_COUNT ))
DIFF=$(( TOTAL_ITEMS - ACCOUNTED ))
if [ $DIFF -eq 0 ]; then
  MATCH_STATUS="完全一致 (0 遗漏)"
else
  MATCH_STATUS="存在差额 (${DIFF} 项)"
fi
STEP4_TIME=$(( SECONDS - STEP4_START ))
echo "      -> 第 4 步完成，用时: $((STEP4_TIME / 60)) 分 $((STEP4_TIME % 60)) 秒 (${STEP4_TIME}s)"

TOTAL_ELAPSED=$(( SECONDS - TOTAL_START ))
echo -e "\n==================== 各步骤耗时明细 ===================="
echo "第 1 步 [扫描与排查] : $((STEP1_TIME / 60)) 分 $((STEP1_TIME % 60)) 秒 (${STEP1_TIME}s)"
echo "第 2 步 [压缩与归档] : $((STEP2_TIME / 60)) 分 $((STEP2_TIME % 60)) 秒 (${STEP2_TIME}s)"
echo "第 3 步 [完整性自检] : $((STEP3_TIME / 60)) 分 $((STEP3_TIME % 60)) 秒 (${STEP3_TIME}s)"
echo "第 4 步 [一致性比对] : $((STEP4_TIME / 60)) 分 $((STEP4_TIME % 60)) 秒 (${STEP4_TIME}s)"
echo "--------------------------------------------------------"
echo "脚本总执行时间       : $((TOTAL_ELAPSED / 60)) 分 $((TOTAL_ELAPSED % 60)) 秒 (${TOTAL_ELAPSED}s)"
echo -e "\n==================== 打包执行与核对报告 ================"
echo "执行状态     : $( [ $TAR_STATUS -eq 0 ] && echo '成功 (已忽略文件变更警告)' || echo "退出代码 $RAW_STATUS" )"
echo "压缩算法     : Zstandard (zstd -1 -T0 多核多线程)"
echo "双目录总项目 : $TOTAL_ITEMS 项 (Desktop + Downloads)"
echo "已归档项目数 : $PACKED_COUNT 项"
echo "规则排除项目 : $SKIPPED_COUNT 项"
echo "账面总计处理 : $ACCOUNTED 项"
echo "总数一致性   : $MATCH_STATUS"
echo "数据完整性   : $CHECK_RES"
echo "异常报错行数 : $(wc -l < "$ERR_LOG") 行"
echo "压缩包大小   : $(ls -lh "$ARCHIVE_FILE" | awk '{print $5}')"
echo "压缩包文件   : $ARCHIVE_FILE"
echo "成功清单     : $OUT_LOG"
echo "排除清单     : $SKIP_LOG"
echo "错误日志     : $ERR_LOG"
echo "========================================================"
