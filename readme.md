
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

```

```
