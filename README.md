# edge-vision-contracts

共享契约仓，用来冻结 phase-1 最小闭环依赖的 proto 边界。

当前仍保持 **设计级 / skeleton 级**：只把跨仓边界先钉住，不提前展开字段级精细设计、存储模型或前端 UI 契约。

## phase-1 当前闭环

- control-plane -> `runtime.v1.SupervisorService`：下发部署 / 停止、直连查询 supervisor / deployment 状态
- supervisor / nodeagent -> `controlplane.v1.StatusSinkService`：向 control-plane 发布状态快照
- control-plane 对外 -> `controlplane.v1.StatusQueryService`：暴露 control-plane 已接收的最新状态视图
- control-plane -> `nodeagent.v1.NodeAgentService`：节点状态查询、节点配置下发、supervisor 重启

这里特意把 **runtime 直连控制面** 和 **control-plane 汇聚读侧** 分开：

- `runtime` / `nodeagent` 保留“源头服务”边界
- `controlplane` 保留“接收 + 对外读取最新快照”的边界
- 依赖方可以先基于这组骨架打通 phase-1 最小闭环，而不用等待 control-plane 仓自己补一套独立 proto

## package 边界约定

| package | 负责什么 | 当前刻意不做什么 |
| --- | --- | --- |
| `common/v1` | 共享基元、状态枚举、通用 `ExecutionBackend` | 领域对象明细、资源模型扩展 |
| `runtime/v1` | control-plane 对 supervisor 的控制调用；runtime 侧状态结构 | 调度策略、任务编排细节 |
| `controlplane/v1` | control-plane 暴露的状态入口与最新快照查询 | 前端页面模型、列表筛选、审计流 |
| `nodeagent/v1` | 节点基础状态 / 配置 / supervisor 运维动作 | 升级、诊断、设备管理全量能力 |

## 这次边界收敛点

- 把 runtime / nodeagent 里重复的 backend 枚举收敛到 `common.v1.ExecutionBackend`
- 保留 `StatusSinkService` 作为写入入口，不把 control-plane 的内部持久化模型塞进契约
- 新增 `StatusQueryService` 作为最小读侧骨架，只返回 **latest accepted snapshot**，不引入列表、过滤、分页

## 目录

- `proto/common/v1/`：共享基元、资源引用、状态枚举、共享执行后端枚举
- `proto/runtime/v1/`：supervisor 对外控制面
- `proto/controlplane/v1/`：control-plane 状态入口 + 最新快照查询骨架
- `proto/nodeagent/v1/`：nodeagent 基础状态 / 操作
- `scripts/`：校验 / descriptor 生成脚本
- `buf/`：Buf 预留目录，当前未强依赖

## 快速接入

### 1) 检查本机 proto 工具链

```bash
./scripts/check-proto-toolchain.sh
```

说明：

- `protoc` 是必需项
- `protoc-gen-go` / `protoc-gen-go-grpc` / `grpc_cpp_plugin` 当前只是“可选能力探测”，是否真正启用取决于各依赖方语言栈

### 2) 生成 descriptor set

```bash
./scripts/generate.sh
```

可选：自定义输出路径

```bash
DESCRIPTOR_OUT=/tmp/edge-vision-contracts.pb ./scripts/generate.sh
```

脚本会：

- 检查 `protoc` 是否存在
- 校验 `proto/` 下全部 proto 文件
- 生成 descriptor set，默认输出到 `gen/descriptors/edge-vision-contracts.pb`

### 3) 依赖方如何消费

- **需要先对齐边界**：直接 import `proto/` 下对应 package 即可
- **需要做接口联调 / 兼容性检查**：用 descriptor set 即可，不必等语言绑定全量落地
- **需要语言绑定代码**：当前仓不强推统一生成产物；等 Go / C++ / 其他工具链拍板后再补正式方案

## 已拍板约束

- Jetson / TensorRT 优先
- proto 先冻结 v1 骨架
- 第一阶段只追求最小闭环
- 前端独立仓，不在这里定义 UI 契约
