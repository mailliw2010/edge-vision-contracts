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
- 产生 deployment / supervisor 状态

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
- default_backend
- active_deployment_count

### `runtime.v1.DeploymentStatus`

表达单个 deployment 的状态，至少需要：

- deployment_id
- node_id
- runtime_instance_id
- state
- health
- status_message

### `nodeagent.v1.NodeStatus`

表达节点侧状态，至少需要：

- node_id
- state
- health
- platform
- device_class
- preferred_backend
- supervisor_reachable

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
