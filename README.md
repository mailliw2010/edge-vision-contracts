# edge-vision-contracts

共享契约仓，用来冻结当前最小闭环与后续扩展所依赖的跨仓协议边界。

当前阶段，最小闭环的真实架构口径已经明确为：

- `control-plane` 负责业务编排入口与状态汇聚
- `runtime` 负责 Supervisor / Source / Worker 的执行侧闭环
- `runtime` 最小业务闭环会纳入：
  - ZLMediaKit（流媒体入口/代理）
  - GStreamer / DeepStream（解码与媒体处理）
  - 本机推理（FastDeploy 或直接 TensorRT）
- `contracts` 负责冻结这几者之间真正需要跨仓、跨进程稳定演进的最小协定

当前仍保持 **设计级 / skeleton 级**：只把跨仓边界先钉住，不提前展开字段级精细设计、存储模型或前端 UI 契约。

## 当前最小闭环职责

本仓当前负责：

- 定义 control-plane ↔ runtime 的最小控制与状态契约
- 定义 control-plane ↔ nodeagent 的最小系统契约
- 定义 control-plane 对外可查询的聚合状态契约
- 提供 Go codegen / descriptor 生成能力，支撑 Go 侧 control-plane 联调
- 作为 C++ runtime gRPC 代码生成的 proto source of truth

本仓当前不负责：

- YAML 部署文件格式
- runtime 内部 JSON DAG 结构
- 前端页面模型
- control-plane 仓内 handler / service / repository 细节

## phase-1 当前闭环

- control-plane -> `runtime.v1.SupervisorService`：下发部署 / 停止、直连查询 supervisor / deployment 状态
- supervisor / nodeagent -> `controlplane.v1.StatusSinkService`：向 control-plane 发布状态快照
- runtime -> `controlplane.v1.RuntimeEventSinkService`：向 control-plane 批量上报稳定业务 / runtime 事件
- control-plane 对外 -> `controlplane.v1.StatusQueryService`：暴露 control-plane 已接收的最新状态视图
- control-plane -> `nodeagent.v1.NodeAgentService`：节点状态查询、节点配置下发、supervisor 重启

这里特意把 **runtime 直连控制面** 和 **control-plane 汇聚读侧** 分开：

- `runtime` / `nodeagent` 保留“源头服务”边界
- `controlplane` 保留“接收 + 对外读取最新快照”的边界
- 依赖方可以先基于这组骨架打通 phase-1 最小闭环，而不用等待 control-plane 仓自己补一套独立 proto

## package 边界约定

| package | 负责什么 | 当前刻意不做什么 |
| --- | --- | --- |
| `common/v1` | 共享基元、状态枚举、通用 `ExecutionMode` / `ExecutionBackend` | 领域对象明细、资源模型扩展 |
| `runtime/v1` | control-plane 对 supervisor 的控制调用；runtime 侧执行请求、状态与事件结构 | runtime 内部 graph schema、调度实现细节 |
| `controlplane/v1` | control-plane 暴露的状态入口与最新快照查询 | 前端页面模型、列表筛选、审计流 |
| `nodeagent/v1` | 节点基础状态、节点能力、配置 / supervisor 运维动作 | 升级、诊断、设备管理全量能力 |

## 这次边界收敛点

- 把执行方式拆成 `common.v1.ExecutionMode` 和 `common.v1.ExecutionBackend`
- 在 `runtime.v1.WorkloadSpec` 中补充明确的 `ExecutionRequest`，按方案 B 走“backend 下发声明式执行请求，runtime 内部规范化和绑定”的边界
- 在 `nodeagent.v1.NodeStatus` 中补充 `NodeCapabilities`
- 保留 `StatusSinkService` 作为写入入口，不把 control-plane 的内部持久化模型塞进契约
- 新增 `RuntimeEventSinkService` 作为 runtime -> backend/control-plane 的稳定事件上报 RPC
- 新增 `StatusQueryService` 作为最小读侧骨架，只返回 **latest accepted snapshot**，不引入列表、过滤、分页

## 执行请求边界

当前采用方案 B：

- backend / control-plane 负责保存业务定义、配置修订、部署意图，并把相机、算法、策略和节点解析成声明式 `runtime.v1.ExecutionRequest`
- backend / control-plane 不给 runtime 编译 C++、模型 engine 或 runtime 内部 graph
- runtime 负责根据 `ExecutionRequest` 做校验、规范化、Source/Worker wiring、模型加载、后端绑定和内部执行图构建
- 算法主逻辑优先集中在 runtime，backend 只做编排、引用解析、状态汇聚和产品 API

`ExecutionMode` 和 `ExecutionBackend` 分开表达：

- `ExecutionMode`：runtime 如何调用算法节点，例如本进程逐帧执行、远程 gRPC 服务、远程 HTTP 服务
- `ExecutionBackend`：具体执行引擎或加速目标，例如 TensorRT、CPU、FastDeploy、DeepStream、Triton、ONNX Runtime

旧的 `preferred_backend` / `default_backend` 字段已标记 deprecated，只保留 wire 兼容；新实现应使用 `execution_mode` 和 `execution_backend`。

## Deployment 语义

这里的 `Deployment` 指**算法布控部署**，不是 Kubernetes / Docker / systemd 这类基础设施部署。

它的作用是描述一个期望状态：把某组摄像头或输入、某个业务算法版本、某组 artifact/config/policy、某个目标节点和 runtime 执行策略绑定起来。control-plane 负责保存和下发这个期望状态，runtime 负责把它落成真实运行的 source / worker / pipeline 会话。

## 事件上报传输选择

当前采用的事件链路是：

```text
runtime
  -> control-plane/event-ingest: gRPC RuntimeEventSinkService.PublishRuntimeEvents
  -> RabbitMQ/Kafka/NATS: BusinessEventEnvelope
  -> consumers: subscribe MQ topics
```

runtime -> control-plane/event-ingest 使用 gRPC，原因是：

- 这是执行侧到 ingest 的服务到服务通信，双方都依赖 proto，gRPC 可以直接复用强类型 schema 和生成代码
- 事件频率低/中频，当前业务事件大约 0.5/s，峰值约 2-3/s；gRPC 批量上报足够直接
- 有 deadline、状态码、拦截器、连接复用等内置能力，和现有 `SupervisorService` / `StatusSinkService` 风格一致

control-plane/event-ingest -> consumers 使用 RabbitMQ/Kafka/NATS，原因是：

- 存在多个消费者同时订阅业务事件的需求，fanout 不应由 runtime 承担
- control-plane 可以先完成事件增强、去重、状态推进、权限/租户/相机/算法元数据补齐和证据引用落库
- MQ 更适合多消费者、异步削峰、消费者组、失败重试、持久化缓冲和后续重放

REST 更适合 frontend、外部系统和人工调试，不适合作为 runtime 高频内部事件通道的首选。

消费者默认订阅 control-plane/event-ingest 发布的 `BusinessEventEnvelope`，而不是直接连 runtime。只有本地低延迟动作、算法调试、预览/OSD、断网降级和 runtime profiling 这类场景，才应该直接从 runtime 或 observe-agent 获取原始执行侧数据。

高频帧级 telemetry、profile 和原始观测流不走这个 RPC，应继续走 runtime -> observe-agent 的观测链路。

## Rulego 评估口径

Rulego 这类 Go 规则引擎暂不进入 v1 proto 枚举。它可以作为候选方案评估，但不应把 C++ runtime 的基础模型推理路径耦合到 Go 规则引擎里。

更合适的评估方向是：

- backend 侧：用于业务规则的配置校验、产品编排或轻量策略解释
- runtime 侧：若要参与执行，优先作为远程规则服务或声明式配置来源，而不是替代 C++/GStreamer/TensorRT 主执行链
- 事件规则：可以消费 runtime 上报后的稳定事件，但不处理原始帧和高频模型输出

## phase-1 生成策略

### 结论

phase-1 生成策略分成两侧：

- Go control-plane 侧：继续使用本仓 `scripts/generate.sh` 生成 Go binding。
- C++ runtime 侧：由 `edge-vision-runtime` 的 CMake 在 `EVR_ENABLE_GRPC=ON` 时从本仓 `proto/` 按需生成 C++ protobuf/gRPC stub。

同时继续坚持：

1. `proto/` 才是 source of truth
2. `gen/` 只放本仓可重复生成的产物，不承载业务实现
3. 默认不提交语言绑定产物，避免把 contracts 仓变成某个 consumer 的私有 SDK 仓
4. C++ 生成物留在 runtime build 目录，不进入 contracts 仓

### Go 侧仓内约定

- 当前 phase-1 闭环里，control-plane / nodeagent 侧更需要先有稳定 Go binding 做接口联调
- 环境里已经有 `protoc-gen-go` / `protoc-gen-go-grpc`
- Go 生成链可以在不引入业务代码、不锁死 consumer 仓结构的前提下先稳定下来

- 各 proto 的 `go_package` 统一落在 `edgevision/contracts/gen/...`
- `scripts/generate.sh` 用 `GO_MODULE=edgevision/contracts` 作为默认 module 前缀来生成 Go 代码
- 生成后的文件路径会落到仓内 `gen/common/v1`、`gen/runtime/v1`、`gen/controlplane/v1`、`gen/nodeagent/v1`
- 这个前缀是 **contracts 仓自己的中性命名**，不是某个 consumer 私有 import path；后续如果仓库正式落到固定 VCS 地址，再统一调整 module 前缀

### C++ runtime 侧约定

- runtime 直接实现 `runtime.v1.SupervisorService`，不引入 Go runtime shim。
- C++ stub 由 runtime 仓 CMake 从 `proto/` 生成，输出到 runtime build 目录。
- 生成依赖是 `protoc`、`grpc_cpp_plugin`、`protobuf` 和 `grpc++`。
- control-plane 和 runtime 之间只保留 protobuf/gRPC 边界，不再定义 Go supervisor -> C++ worker 的二次内部控制协议。

### 为什么暂不提交 Go / C++ 生成物

- 现在更需要的是 **可重复生成**，不是把 `.pb.go` / C++ stub 当成手工维护资产
- 一旦提交生成物，就会马上引入版本漂移、review 噪音、不同语言产物同步策略这些额外负担
- C++ 生成物属于 runtime build artifact，应由 runtime CMake 管理

## 目录

- `proto/common/v1/`：共享基元、资源引用、状态枚举、执行模式 / 执行后端枚举
- `proto/runtime/v1/`：supervisor 对外控制面、明确执行请求、runtime 状态与事件结构
- `proto/controlplane/v1/`：control-plane 状态入口 + 最新快照查询骨架
- `proto/nodeagent/v1/`：nodeagent 基础状态、节点能力 / 操作
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
- `grpc_cpp_plugin` 是 runtime C++ gRPC 构建所需；contracts 仓脚本只探测，不默认生成 C++ 代码

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
