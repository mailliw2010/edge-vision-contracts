# edge-vision-contracts phase-1 closure notes

这一版的 contracts 目标不是“把所有领域一次性定义完”，而是先把 phase-1 的最小闭环冻结住。

## 闭环参与方

### 1. control-plane

control-plane 是**汇聚与对外读侧**，它做三件事：

- 向 runtime 侧下发控制意图
- 向 nodeagent 下发节点级意图
- 接收 runtime / nodeagent 的状态快照并对外暴露最新视图

### 2. runtime

runtime 是**执行侧**，它负责：

- supervisor 侧部署/停止
- source / worker 的本地 wiring
- 根据 backend 下发的声明式 `ExecutionRequest` 做校验、规范化、模型加载和后端绑定
- 产生 deployment / supervisor 状态
- 上报稳定 runtime / 业务事件

### 3. nodeagent

nodeagent 是**节点侧执行入口**，它负责：

- 节点状态
- 节点配置下发
- supervisor 运维动作

## 最小状态流

### control-plane -> runtime

- `runtime.v1.SupervisorService.ApplyDeployment`
- `runtime.v1.SupervisorService.StopDeployment`
- `runtime.v1.SupervisorService.GetSupervisorStatus`
- `runtime.v1.SupervisorService.GetDeploymentStatus`

### control-plane -> nodeagent

- `nodeagent.v1.NodeAgentService.GetNodeStatus`
- `nodeagent.v1.NodeAgentService.ApplyNodeConfig`
- `nodeagent.v1.NodeAgentService.RestartSupervisor`

### runtime/nodeagent -> control-plane

- `controlplane.v1.StatusSinkService.PublishStatus`
- `controlplane.v1.RuntimeEventSinkService.PublishRuntimeEvents`

### control-plane/event-ingest -> consumers

- `controlplane.v1.BusinessEventEnvelope` as the RabbitMQ/Kafka/NATS payload
- consumers subscribe to MQ topics by default

### control-plane 对外读侧

- `controlplane.v1.StatusQueryService`

## 最小消息语义

### `common.v1.RequestMeta`

用于追踪一次控制意图或状态写入，phase-1 只要求：

- request_id 可区分
- trace_id 可选但建议带
- actor 可标识来源
- sent_at 记录发送时间

### `common.v1.ResourceRef`

用于资源引用，phase-1 只要求：

- kind
- id
- revision

### `runtime.v1.SupervisorStatus`

表达 runtime 执行侧总体状态，至少需要：

- node_id
- state
- health
- default_execution_mode
- default_execution_backend
- active_deployment_count

### `runtime.v1.DeploymentStatus`

表达单个 deployment 的状态，至少需要：

- deployment_id
- node_id
- runtime_instance_id
- state
- health
- status_message
- effective_execution_mode
- effective_execution_backend

### `runtime.v1.ExecutionRequest`

表达 backend / control-plane 下发给 runtime 的明确执行请求。

它是声明式配置，不是 runtime 内部 graph，也不是跨进程传递的编译产物。backend 只解析 deployment 意图和资源引用；runtime 才负责把这些信息规范化为 source / worker / pipeline 的内部执行形态。

至少需要：

- execution_request_id
- execution_mode
- execution_backend
- sources
- algorithms
- outputs
- policy

### `nodeagent.v1.NodeStatus`

表达节点侧状态，至少需要：

- node_id
- state
- health
- platform
- device_class
- preferred_execution_mode
- preferred_execution_backend
- supervisor_reachable
- capabilities

### `nodeagent.v1.NodeCapabilities`

表达节点能否承载某类算法执行请求，至少需要：

- architecture / operating_system / device_class
- accelerators
- supported_execution_modes
- supported_execution_backends
- decode_codecs / encode_codecs
- cuda_version / tensorrt_version / nvidia_driver_version
- hardware decode / encode flags

### `runtime.v1.RuntimeEvent`

表达 runtime 上报给 backend/control-plane 的稳定事件。它不是逐帧 telemetry，也不承载原始帧。

至少需要：

- event_id
- deployment_id
- node_id
- runtime_instance_id
- source_binding_id / algorithm_binding_id
- event_type
- severity
- occurred_at
- sequence

### `controlplane.v1.BusinessEvent`

表达 control-plane/event-ingest 增强、去重、状态推进后的业务事件。它是默认给业务消费者订阅的事件形态。

它可以在 `RuntimeEvent` 基础上补充：

- 全局 event_id
- camera_id / camera_name / location_id
- business_algorithm_id / business_algorithm_version
- tenant_id / project_id
- event lifecycle state
- evidence references after storage
- enriched attributes

### `controlplane.v1.BusinessEventEnvelope`

表达发布到 RabbitMQ/Kafka/NATS 的消息载荷。proto 只冻结 payload，不绑定具体 broker。

至少需要：

- schema_version
- topic
- routing_key
- event
- headers

## Deployment 语义

这里的 deployment 是**算法布控部署**：

- 它绑定 camera/input、业务算法版本、artifact/config/policy、目标 node 和 runtime 执行策略
- control-plane 负责保存期望状态、解析引用并下发 `ExecutionRequest`
- runtime 负责把期望状态落成真实运行的 source / worker / pipeline 会话

它不是基础设施部署，不直接表示容器、systemd unit、Kubernetes Deployment 或模型编译任务。

## RPC / REST / MQ 取舍

选定链路：

```text
runtime -> control-plane/event-ingest: gRPC
control-plane/event-ingest -> RabbitMQ/Kafka/NATS: enriched business event
consumers -> MQ topics
```

runtime -> control-plane/event-ingest 使用 gRPC：

- proto 已是跨进程契约事实源，gRPC 能复用强类型 schema 和生成代码
- 内部服务到服务通信需要 deadline、状态码、连接复用和批量请求
- runtime 业务事件量是低/中频，常见约 0.5/s，峰值约 2-3/s，适合批量 RPC ingest

control-plane/event-ingest -> consumers 使用 MQ：

- 多个消费者订阅不应由 runtime 承担
- control-plane/event-ingest 可以先补齐 camera、deployment、算法、租户、证据和生命周期信息
- MQ 更适合 fanout、消费者组、异步削峰、失败重试、持久化缓冲和后续重放

REST 仍用于 frontend / 外部自动化 / 人工调试。业务消费者默认订阅 MQ 里的 `BusinessEventEnvelope`，只有本地低延迟联动、算法调试、预览/OSD、断网降级和 profiling 这类场景才直接读 runtime/observe-agent。

## Rulego 评估口径

Rulego 暂不进入 phase-1 proto。它可以评估为 backend 侧业务规则配置/校验工具，或作为可选远程规则服务；不应让 C++ runtime 的 GStreamer/TensorRT 基础模型执行链依赖 Go 规则引擎。

## 这版已经闭环的点

- `common` 作为最小共享底座
- `runtime` 作为控制面执行侧
- `nodeagent` 作为节点执行侧
- `controlplane` 作为汇聚与读取侧

## 这版暂时不做的点

- pagination / filtering / audit stream
- 复杂任务编排 DSL
- 全量设备管理模型
- 业务无关的通用配置协议

## 冻结原则

如果后续要扩展，优先新增字段，不轻易改已有字段语义。
