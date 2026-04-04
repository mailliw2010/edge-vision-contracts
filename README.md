# edge-vision-contracts

共享契约仓。

## 职责

- Runtime gRPC proto
- NodeAgent proto
- 共享消息与 schema
- 代码生成脚本

## 当前约定

- 先冻结 **v1 proto 骨架**
- 先确定目录、package、service、核心消息体边界
- 字段级细化可以随着 control-plane / runtime 开发继续迭代

## 建议目录

- `proto/`：协议文件
- `buf/`：可选的契约管理配置
- `scripts/`：生成脚本

当前已初始化的 proto 目录包括：

- `proto/common/v1/`
- `proto/runtime/v1/`
- `proto/nodeagent/v1/`
- `proto/controlplane/v1/`
