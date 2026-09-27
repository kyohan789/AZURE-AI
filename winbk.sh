TIMESTAMP=$(date +"%Y%m%d_%H%M%S"); \
ARCHIVE_FILE="/c/desktop_${TIMESTAMP}.tar.gz"; \
OUT_LOG="/c/tar_output_${TIMESTAMP}.log"; \
ERR_LOG="/c/tar_error_${TIMESTAMP}.log"; \
SKIP_LOG="/c/tar_skipped_${TIMESTAMP}.log"; \
START_TIME=$SECONDS; \
echo "[1/4] 扫描桌面实际总项目数与排除清单..."; \
TOTAL_ITEMS=$(find /c/Users/Administrator/Desktop | wc -l); \
find /c/Users/Administrator/Desktop \( -name "*0515.7z" -o -path "*/Logs/*" -o -path "*MTD_TJ*" -o -name "*.hst" -o -name "*.hcc" -o -name "*.hc" \) > "$SKIP_LOG" 2>/dev/null; \
echo "[2/4] 开始打包桌面到 ${ARCHIVE_FILE}..."; \
tar --exclude="*0515.7z" \
    --exclude="*/Logs/*" \
    --exclude="*MTD_TJ*" \
    --exclude="*.hst" \
    --exclude="*.hcc" \
    --exclude="*.hc" \
  -I 'gzip -1' \
  -cvf "$ARCHIVE_FILE" \
  -C /c/Users/Administrator Desktop \
  > "$OUT_LOG" 2> "$ERR_LOG"; \
TAR_STATUS=$?; \
ELAPSED=$(( SECONDS - START_TIME )); \
echo "[3/4] 验证数据流与文件完整性..."; \
tar -tzf "$ARCHIVE_FILE" > /dev/null 2>&1 && CHECK_RES="通过" || CHECK_RES="失败"; \
echo "[4/4] 正在比对核查总项目数一致性..."; \
PACKED_COUNT=$(wc -l < "$OUT_LOG"); \
SKIPPED_COUNT=$(wc -l < "$SKIP_LOG"); \
ACCOUNTED=$(( PACKED_COUNT + SKIPPED_COUNT )); \
DIFF=$(( TOTAL_ITEMS - ACCOUNTED )); \
if [ $DIFF -eq 0 ]; then \
  MATCH_STATUS="完全一致 (0 遗漏)"; \
else \
  MATCH_STATUS="存在差额 (${DIFF} 项)"; \
fi; \
echo -e "\n==================== 打包执行与核对报告 ===================="; \
echo "执行状态     : $( [ $TAR_STATUS -eq 0 ] && echo '成功' || echo "退出代码 $TAR_STATUS" )"; \
echo "总计耗时     : $((ELAPSED / 60)) 分 $((ELAPSED % 60)) 秒 (共 ${ELAPSED} 秒)"; \
echo "桌面总项目数 : $TOTAL_ITEMS 项"; \
echo "已归档项目数 : $PACKED_COUNT 项"; \
echo "规则排除项目 : $SKIPPED_COUNT 项"; \
echo "账面总计处理 : $ACCOUNTED 项"; \
echo "总数一致性   : $MATCH_STATUS"; \
echo "数据完整性   : $CHECK_RES"; \
echo "异常报错行数 : $(wc -l < "$ERR_LOG") 行"; \
echo "压缩包大小   : $(ls -lh "$ARCHIVE_FILE" | awk '{print $5}')"; \
echo "压缩包文件   : $ARCHIVE_FILE"; \
echo "成功清单     : $OUT_LOG"; \
echo "排除清单     : $SKIP_LOG"; \
echo "错误日志     : $ERR_LOG"; \
echo "============================================================"
