# edge-vision-contracts

共享契约仓，用来冻结第一阶段最小闭环依赖的 proto 边界。

## 当前范围

本仓当前只做 **docs / proto skeleton**，不提前做字段级精细设计。

第一阶段闭环聚焦：

- control-plane -> supervisor：下发部署/停止、查询 supervisor / deployment 状态
- supervisor -> status：向控制面状态入口上报 supervisor / deployment / node 状态
- nodeagent 基础状态/操作：节点状态查询、节点配置下发、supervisor 重启

已拍板约束：

- Jetson / TensorRT 优先
- proto 先冻结 v1 骨架
- 第一阶段只追求最小闭环
- 前端独立仓，不在这里定义 UI 契约

## 目录

- `proto/common/v1/`：共享基元、资源引用、状态枚举
- `proto/runtime/v1/`：supervisor 对外控制面
- `proto/controlplane/v1/`：状态入口（status sink）
- `proto/nodeagent/v1/`：nodeagent 基础状态/操作
- `scripts/`：校验 / 生成辅助脚本
- `buf/`：Buf 预留目录，当前未强依赖

## 设计取舍

### 为什么把 control-plane -> supervisor 放在 `runtime/v1`

这是 supervisor 暴露给外部调用方的控制面，当前最接近运行时边界，因此先归到 `runtime`。

### 为什么把 supervisor -> status 放在 `controlplane/v1`

这是控制面暴露给节点侧/运行时侧的状态入口，职责上属于 control-plane 接收面。

### 为什么 nodeagent 只保留很少几个 RPC

第一阶段目标是闭环，不是平台完备度：

- `GetNodeStatus`
- `ApplyNodeConfig`
- `RestartSupervisor`

够依赖方开工，但暂不把设备管理、升级、诊断等细节塞进 v1。

## 脚本

### 校验 proto 语法并输出 descriptor set

```bash
./scripts/generate.sh
```

当前脚本会：

- 检查 `protoc` 是否存在
- 校验 `proto/` 下全部 proto 文件
- 生成 `gen/descriptors/edge-vision-contracts.pb`

说明：语言绑定代码生成（Go / C++ / 其他）暂不在这个阶段强制落地，等依赖方和工具链定下来再接。
