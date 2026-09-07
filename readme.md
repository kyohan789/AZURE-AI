# Azure AI 批量自动化部署工具集

基于 Azure CLI 的轻量级自动化运维脚本集合，专为批量查询配额、多区域并行部署及自动回收设计。

---

## 快速运行 (一键命令)

> **运行前置条件**：  
> 1. 已安装 Azure CLI 并完成登录：`az login`  
> 2. 确保当前订阅处于 **Enabled** 状态且具备相关资源管理权限。

### 1. 语音服务 (Speech Services) 一键部署

自动匹配策略限制区域，多区域并发部署免费/标准层语音服务，失败自动销毁资源组，完成后汇总 Endpoint 和 Key：

```bash
P="http"; S="s://"; H="raw.githubusercontent.com"; R="kyohan789/AZURE-AI"; SCRIPT="aztts.sh"; curl -fsSL "${P}${S}${H}/${R}/refs/heads/main/${SCRIPT}?t=$(date +%s)" | bash
```

### 2. 虚拟机 (VM) 一键部署

扫描全区/受限区域配额，跨区域并发拉起指定规格的虚拟机实例：

```bash
P="http"; S="s://"; H="raw.githubusercontent.com"; R="kyohan789/AZURE-AI"; SCRIPT="azvm.sh"; curl -fsSL "${P}${S}${H}/${R}/refs/heads/main/${SCRIPT}?t=$(date +%s)" | bash
```

### 3. AI 模型服务 (Foundry / OpenAI) 一键部署

自动探测目标区域的 AI 模型可用性，跨区域创建资源并部署模型推理终结点：

```bash
P="http"; S="s://"; H="raw.githubusercontent.com"; R="kyohan789/AZURE-AI"; SCRIPT="azai.sh"; curl -fsSL "${P}${S}${H}/${R}/refs/heads/main/${SCRIPT}?t=$(date +%s)" | bash
```

---

## 脚本清单与功能说明

* **`aztts.sh`**
  * **策略穿透**：自动检查 `sys.regionrestriction` 策略，有策略限制时仅在允许区域部署，无限制时自动遍历全部物理区域。
  * **并发控制**：基于 FIFO 管道槽位控制最大并发数（默认上限 10），配合随机错峰机制避免 Azure CLI 凭据缓存锁冲突。
  * **自动回收**：部署失败自动触发后台异步删除对应资源组（`--no-wait`），避免无用资源残留。
  * **状态汇总**：终端实时彩色进度监控，结束时聚合输出成功区域的 Endpoint 与 API Key 列表。

* **`azvm.sh`**
  * 自动巡检当前订阅在全球各物理区域的计算配额。
  * 跨区域并发创建指定规格（x86 / ARM64）的虚拟机实例并配置网络与存储。

* **`azai.sh`**
  * 批量检测目标区域的 Cognitive Services / Foundry 模型可用性。
  * 自动化创建 AI 资源账号并分发部署模型推理终结点。

---

## 核心参数微调

脚本内部支持通过修改脚本开头的常量进行自定义配置：

| 变量名 | 默认值 | 说明 |
| :--- | :--- | :--- |
| `MAX_JOBS` | `10` | 最大异步并发线程数 |
| `SKU` | `F0` | 语音服务定价层（可选免费层 `F0` 或标准层 `S0`） |
| `RG_PREFIX` | `waz-` | 动态生成的资源组前缀（命名规范：`waz-{region}`） |

---

## 许可证

本项目基于 [MIT License](LICENSE) 开源。
