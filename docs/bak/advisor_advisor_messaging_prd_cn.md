# PRD：Advisor-to-Advisor 通讯基础机制（A2A Messaging）

## 1. 背景与目标

Lumie 当前 Advisor v2 已具备以下能力：
- `advisor_orchestrator`：LLM 路由与技能选择
- `execution_jobs`：异步执行与结果回写
- `admin_task_service`：团队管理员可执行 task 完成/删除等管理操作

但系统仍是「用户 ↔ 自己 advisor」的单通道。缺少「advisor ↔ advisor」协作层，无法支持：
- 用户 A 发起团队任务相关申请后，由 admin 用户的 advisor 进行审批并回执
- 用户 A 在获同意后，向用户 B 的 advisor 发送开放型消息，由 B 的 advisor 思考后反馈

本 PRD 定义一个基础机制，让 `User A`、`Advisor A`、`User B`、`Advisor B` 作为四个独立角色进行可靠通信、思考与可控执行。

## 2. 范围

### 2.1 In Scope
- Advisor-to-Advisor 消息总线（持久化、状态机、重试、幂等）
- 两类消息协议：
  1. 预设消息（structured/preset）
  2. 非预设消息（unstructured/open）
- 接收方 advisor 的 LLM 思考与处理
- 审批结果回流（B advisor → A advisor → A user）
- 与现有 skill 执行框架集成（`advisor_orchestrator` + `execution_service`）
- 基础审计日志与权限校验

### 2.2 Out of Scope（首期）
- 跨 app 外部平台消息互通
- 多级审批链（>1 审批人）
- 多 advisor 并行协商（群聊型）
- 富媒体消息（仅文本 + 结构化 payload）

## 3. 角色与人格模型

四种独立人格与权限边界：
- `User A`：仅能操作自身可见功能（如任务创建、发送申请）
- `Advisor A`：仅能在 A 已启用 capability 下执行 skill；可发起 A2A 请求
- `User B`（可为 admin）：仅能在自己 app 里批准/拒绝或发送消息
- `Advisor B`：独立思考与执行，仅可使用 B 的 capability/credential/权限

关键原则：
- Advisor 不共享 credential
- Advisor 不越权调用对方 skill
- 所有执行均以执行方用户身份鉴权

## 4. 用户故事

### 4.1 预设消息（审批型）
1. A 在 team task 上执行需要 admin 同意的操作（例如 delete/complete 申请）。
2. 系统触发 A2A preset 消息，发给 Admin（B）的 advisor。
3. Advisor B 收到后进行 LLM 思考，生成「给 B 的说明 + 操作建议」。
4. B 在客户端同意后，Advisor B 调用可执行 skill/API（如 admin delete/complete）。
5. 执行结果由 Advisor B 发送回 Advisor A。
6. Advisor A 将结果转述给 A。

### 4.2 非预设消息（开放型）
1. A 明示同意并发起「发送给 B advisor」的自由文本。
2. Advisor B 接收消息后进行 LLM 思考。
3. Advisor B 向 B 展示：
   - A 的原始请求
   - 自己的理解/风险提示/建议行动
4. B 可回复（可选），回复再回传给 Advisor A，Advisor A 再转达 A。

## 5. 功能需求

## 5.1 消息模型
新增集合：`advisor_messages`

核心字段：
- `message_id` (uuid, unique)
- `thread_id`（同一往返会话）
- `conversation_type`：`preset` | `open`
- `preset_type`：如 `team_task_operation_request`（open 时为空）
- `from_user_id` / `from_advisor_id`
- `to_user_id` / `to_advisor_id`
- `initiator_role`：`user` | `advisor` | `system_event`
- `payload`：
  - preset：结构化业务字段（task_id, team_id, requested_action, reason）
  - open：自由文本 + 元数据
- `status`：`queued` | `delivered` | `thinking` | `awaiting_user_decision` | `executing` | `responded` | `failed` | `expired`
- `idempotency_key`（防重）
- `causation_id` / `correlation_id`（链路追踪）
- `created_at` / `updated_at` / `expires_at`

新增集合：`advisor_message_events`（审计事件流）
- 存状态转移与关键动作（投递、思考、审批、执行、回复、失败）

## 5.2 预设消息协议
首期定义 `preset_type = team_task_operation_request`

payload 示例：
- `request_user_id` (A)
- `admin_user_id` (B)
- `task_id`
- `team_id`
- `requested_action`：`admin_complete_task` | `admin_delete_task`
- `request_note`
- `origin`：`team_task_completed` | `team_task_delete_request`

处理规则：
- 进入 B 侧后必须先经 LLM 生成解释与建议
- 必须等待 B 明确同意（human-in-the-loop）
- 同意后由 B advisor 发起执行（走现有 execution/job 或直接受控 service 调用）
- 执行结果结构化回传 A advisor

## 5.3 非预设消息协议
- 发送前需要 A 同意（客户端确认）
- B advisor 必须进行 LLM 思考，不可原样转发
- 输出至少包含：
  - `advisor_b_understanding`
  - `advisor_b_suggestion_to_b`
  - `advisor_b_reply_to_a`（可选）

## 5.4 接收方 advisor 思考机制
新增服务：`advisor_message_processor.py`
- 拉取 `queued` 消息
- 构建接收方 advisor 的上下文（to_user profile、capability、最近历史）
- 调用 LLM 生成：
  - 对用户可读解释
  - 下一步动作建议
  - 若可自动执行则生成 `execution_plan`
- 更新消息状态与事件

思考约束：
- 使用接收方用户时区、身份、权限
- 禁止产生“已执行”幻觉（沿用现有 `reply_class` 约束）
- 写操作前必须有显式批准（preset 默认必须批准）

## 5.5 执行集成
- 新增 skill/API 适配层：`advisor_message_action_executor`
- 对 `team_task_operation_request`：
  - 调用 `admin_task_service.admin_complete_task` 或 `admin_delete_task`
  - 执行身份为 B（admin）
- 执行结果写入 `advisor_messages.payload.execution_result`
- 然后触发回执消息至 A advisor

## 5.6 通知与会话
- 向 B 推送：`advisor_message_received`
- 向 A 推送：`advisor_message_response`
- 在 advisor chat history 中记录“系统消息卡片”（非普通聊天气泡）

## 6. 非功能需求

- 可靠性：至少一次投递 + 幂等消费
- 安全性：严格用户边界，禁止跨用户 credential 读取
- 可观测：全链路 trace（message_id/thread_id）
- 延迟目标：
  - 消息入队到 B advisor 可见 < 3s（P95）
  - B 同意后执行开始 < 2s（P95）
- 可恢复：失败可重试，最大重试次数可配置

## 7. 数据库设计

## 7.1 新增集合与索引
`core/database.py` 增加：
- `advisor_messages.message_id` unique
- `advisor_messages.thread_id`
- `advisor_messages.to_user_id + status + created_at`
- `advisor_messages.idempotency_key` unique
- `advisor_messages.expires_at` TTL（可选）

`advisor_message_events`：
- `event_id` unique
- `message_id + created_at`

## 7.2 与现有集合关系
- `execution_jobs`：执行记录
- `chat_messages`：用户可见会话
- `advisor_pending_actions`：可复用思路，但 A2A 不直接复用该表

## 8. API 设计（建议）

### 8.1 发消息（A 侧）
`POST /api/v2/advisor/messages`
- 入参：`to_user_id | to_user_hint`, `conversation_type`, `preset_type?`, `payload`
- 出参：`message_id`, `status`

### 8.2 收件箱（B 侧）
`GET /api/v2/advisor/messages/inbox?status=...`

### 8.3 消息详情
`GET /api/v2/advisor/messages/{message_id}`

### 8.4 决策（B 侧）
`POST /api/v2/advisor/messages/{message_id}/decision`
- `decision`: `approve` | `reject` | `reply`
- `comment`

### 8.5 回执查询（A 侧）
`GET /api/v2/advisor/messages/thread/{thread_id}`

## 9. 状态机

`queued` → `delivered` → `thinking` →
- preset: `awaiting_user_decision` → (`executing` → `responded`) | `responded(rejected)`
- open: `responded`

异常路径：任一状态可转 `failed`；超时转 `expired`。

## 10. 关键时序

### 10.1 预设审批
1. A 触发事件（task 相关）
2. 生成 preset 消息入队
3. B advisor 思考并通知 B
4. B 同意
5. B advisor 执行 admin action
6. 结果回传 A advisor
7. A advisor 通知 A

### 10.2 开放消息
1. A 确认发送
2. B advisor 思考
3. B 收到“消息+思考”
4. B 可回复
5. A advisor 收到并转达 A

## 11. 权限与风控

- 发起方必须具备对目标用户的合法联系关系（同 team / 明确授权）
- preset 审批必须验证：B 确实是对应 team admin
- 执行前再次权限校验（防 TOCTOU）
- 记录审计日志，便于回放与追责
- 对 open 消息加入敏感词/PII 过滤（可配置）

## 12. 里程碑

### Phase 1（MVP）
- 支持 `team_task_operation_request`
- 支持 open 文本消息
- 支持 approve/reject/reply
- 最小 UI 卡片 + 推送

### Phase 2
- 多种 preset_type（邀请、日程协调、健康提醒协商）
- 更细粒度策略（自动批准白名单）
- 更强可观测面板

## 13. 验收标准

- 能完成 A→Advisor A→Advisor B→B 决策→Advisor B 执行→Advisor A→A 的闭环
- 无越权执行（错误权限应拒绝并审计）
- 重复提交同一 idempotency_key 不会重复执行
- 失败重试后无重复副作用
- 日志可按 `message_id/thread_id` 完整追踪

## 14. 对现有代码的改造点（建议）

- `lumie_backend/app/core/database.py`
  - 新增 `advisor_messages` / `advisor_message_events` 索引
- `lumie_backend/app/models/`
  - 新增 `advisor_message.py`（请求/响应/状态枚举）
- `lumie_backend/app/services/`
  - 新增 `advisor_message_service.py`
  - 新增 `advisor_message_processor.py`
  - 新增 `advisor_message_action_executor.py`
- `lumie_backend/app/api/`
  - 新增 `advisor_message_routes.py`（并挂载到 v2 advisor 域）
- `lumie_activity_app/lib/features/advisor/`
  - 新增消息卡片与审批交互入口

## 15. 风险与待确认

- 是否允许某些 preset 在策略满足时自动批准（首期建议不允许）
- B 长时间不处理时的超时策略（建议 24h 过期并通知 A）
- open 消息是否允许附件（首期不允许）
- Advisor A/B 的 persona prompt 是否需要可配置（首期固定模板）

---

该 PRD 基于当前项目已有的 advisor v2 编排与 admin task 权限模型设计，目标是最小增量实现「跨用户 advisor 协作」并保持安全边界清晰。
