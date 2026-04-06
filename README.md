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

## phase-1 生成策略

### 结论

phase-1 先把 **Go 生成链跑通**，但继续坚持：

1. `proto/` 才是 source of truth
2. `gen/` 只放本仓可重复生成的产物，不承载业务实现
3. 默认不提交语言绑定产物，避免把 contracts 仓变成某个 consumer 的私有 SDK 仓
4. C++ 先不正式落生成物；等 build system、发布方式、ABI 约束明确后再开启

### 为什么先支持 Go

- 当前 phase-1 闭环里，control-plane / nodeagent 侧更需要先有稳定 Go binding 做接口联调
- 环境里已经有 `protoc-gen-go` / `protoc-gen-go-grpc`
- Go 生成链可以在不引入业务代码、不锁死 consumer 仓结构的前提下先稳定下来

### Go 侧仓内约定

- 各 proto 的 `go_package` 统一落在 `edgevision/contracts/gen/...`
- `scripts/generate.sh` 用 `GO_MODULE=edgevision/contracts` 作为默认 module 前缀来生成 Go 代码
- 生成后的文件路径会落到仓内 `gen/common/v1`、`gen/runtime/v1`、`gen/controlplane/v1`、`gen/nodeagent/v1`
- 这个前缀是 **contracts 仓自己的中性命名**，不是某个 consumer 私有 import path；后续如果仓库正式落到固定 VCS 地址，再统一调整 module 前缀

### 为什么暂不提交 Go / C++ 生成物

- 现在更需要的是 **可重复生成**，不是把 `.pb.go` / C++ stub 当成手工维护资产
- 一旦提交生成物，就会马上引入版本漂移、review 噪音、不同语言产物同步策略这些额外负担
- C++ 虽然已有 `grpc_cpp_plugin`，但还没确定 phase-1 要绑定哪套构建 / 分发方式；现在提交 C++ 产物只会过早锁设计

## 目录

- `proto/common/v1/`：共享基元、资源引用、状态枚举、共享执行后端枚举
- `proto/runtime/v1/`：supervisor 对外控制面
- `proto/controlplane/v1/`：control-plane 状态入口 + 最新快照查询骨架
- `proto/nodeagent/v1/`：nodeagent 基础状态 / 操作
- `scripts/`：校验 / 生成脚本
- `gen/`：本地可重复生成产物目录（默认不提交）
- `buf/`：Buf 预留目录，当前未强依赖

## 快速接入

### 1) 检查本机 proto 工具链

```bash
./scripts/check-proto-toolchain.sh
```

说明：

- `protoc` 是必需项
- `protoc-gen-go` / `protoc-gen-go-grpc` 是 Go 生成所需
- `grpc_cpp_plugin` 当前只做能力探测，phase-1 暂不默认生成 C++ 代码

### 2) 生成 descriptor + Go 代码

```bash
./scripts/generate.sh
```

脚本默认会：

- 检查 `protoc`
- 扫描并校验 `proto/` 下全部 proto 文件
- 生成 descriptor set，默认输出到 `gen/descriptors/edge-vision-contracts.pb`
- 生成 Go message / grpc stub 到仓内 `gen/...`

只生成 descriptor：

```bash
./scripts/generate.sh descriptor
```

只生成 Go：

```bash
./scripts/generate.sh go
```

可选：自定义输出参数

```bash
DESCRIPTOR_OUT=/tmp/edge-vision-contracts.pb ./scripts/generate.sh descriptor
GO_MODULE=edgevision/contracts ./scripts/generate.sh go
```

> 注意：`gen/` 默认是忽略目录。脚本保证“能生成”，但 phase-1 不把这些产物作为必须提交的版本化资产。

### 3) 依赖方如何消费

- **先对齐边界**：直接 import `proto/` 下对应 package
- **做接口联调 / 兼容性检查**：优先使用 descriptor set
- **需要 Go binding**：在本仓执行 `./scripts/generate.sh go`，或在自己的 CI 里对本仓 proto 做同样生成
- **不要** 为了某个单一 consumer 去修改 proto package / `go_package` 命名；contracts 仓边界应保持中性

## 已拍板约束

- Jetson / TensorRT 优先
- proto 先冻结 v1 骨架
- 第一阶段只追求最小闭环
- 前端独立仓，不在这里定义 UI 契约
