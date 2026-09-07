```markdown
# Azure AI 批量自动化部署工具集

基于 Azure CLI 的轻量级自动化运维脚本集合，专为批量查询配额、多区域并行部署及自动回收设计。

---

## 快速运行 (一键命令)

> **运行前置条件**：  
> 1. 已安装 [Azure CLI](https://learn.microsoft.com/zh-cn/cli/azure/install-azure-cli) 并完成登录：`az login`  
> 2. 确保当前订阅处于 **Enabled** 状态且具备相关资源管理权限。

### 1. 语音服务 (Speech Services) 一键部署
自动匹配策略限制区域，多区域并发部署免费/标准层语音服务，失败自动销毁资源组，完成后汇总 Endpoint 和 Key：
```bash
curl -fsSL "[https://raw.githubusercontent.com/kyohan789/AZURE-AI/refs/heads/main/AZTTS.SH?t=$(date](https://raw.githubusercontent.com/kyohan789/AZURE-AI/refs/heads/main/AZTTS.SH?t=$(date) +%s)" | bash

```

### 2. 虚拟机 (VM) 一键部署

扫描全区/受限区域配额，跨区域并发拉起指定规格的虚拟机实例：

```bash
curl -fsSL "[https://raw.githubusercontent.com/kyohan789/AZURE-AI/refs/heads/main/AZVM.SH?t=$(date](https://raw.githubusercontent.com/kyohan789/AZURE-AI/refs/heads/main/AZVM.SH?t=$(date) +%s)" | bash

```

### 3. AI 模型服务 (Foundry / OpenAI) 一键部署

自动探测目标区域的 AI 模型可用性，跨区域创建资源并部署模型推理终结点：

```bash
curl -fsSL "[https://raw.githubusercontent.com/kyohan789/AZURE-AI/refs/heads/main/AZMODEL.SH?t=$(date](https://raw.githubusercontent.com/kyohan789/AZURE-AI/refs/heads/main/AZMODEL.SH?t=$(date) +%s)" | bash

```

---

## 脚本功能简介

* **`AZTTS.SH`**：
* 自动查询订阅的 `sys.regionrestriction` 策略，有策略限制时仅在允许区域部署，无限制时遍历全物理区。
* 内置并发槽控制（默认最大 10 并发），配合毫秒级随机错峰，避免 Azure CLI 凭据缓存锁冲突。
* 部署失败自动触发后台异步删除资源组（`--no-wait`）。
* 终端彩色进度实时打印，并在全部结束后汇总成功的 URL 与 API 密钥。


* **`AZVM.SH`**：用于自动化多区域创建虚拟主机，适配 x86/ARM64 架构镜像并自动配置对应网络与存储。
* **`AZMODEL.SH`**：用于自动化批量部署 Azure Cognitive Services / Foundry AI 账户及对应模型 Deployment。

---

## 核心配置参数微调

脚本内部支持通过修改顶部变量进行个性化调整：

| 变量名 | 默认值 | 说明 |
| --- | --- | --- |
| `MAX_JOBS` | `10` | 最大异步并发线程数 |
| `SKU` | `F0` | 服务定价层级（可选 `F0` 免费层或 `S0` 标准层） |
| `RG_PREFIX` | `waz-` | 动态生成的资源组前缀（格式：`waz-{region}`） |

---

## 许可证

本项目基于 [MIT License](https://www.google.com/search?q=LICENSE) 开源。

```

```
