# Lumie Advisor 跨用户 Advisor 消息与 Pending Action 机制（MVP）

版本：v1.0  
日期：2026-04-30  
范围：`lumie_backend`（优先），`lumie_activity_app`（最小配套）

## 1. 目标与现状

### 1.1 当前系统（已存在）
1. `advisor_orchestrator.handle_chat`：负责 Advisor 聊天路由与 skill 决策（LLM）。
2. `execution_service` + `execution_jobs`：负责真正执行 skill/action。
3. `advisor_pending_actions`：已用于「补充信息后继续执行」的待处理动作。
4. `chat_history_service`：可落库用户与 advisor 的会话消息。

### 1.2 本次新增目标
建立「Advisor A <-> Advisor B」通信基础机制，使得：
1. Advisor 可向另一个用户的 Advisor 发送结构化请求。
2. 接收方 Advisor 必须通过 LLM 思考并决定是否需要用户确认。
3. 若需要确认，创建 pending action 并向接收方用户提问。
4. 收到用户确认后，恢复流程并执行 action。

## 2. 核心业务规则（不模糊）

1. 任何跨用户写操作请求，默认 `require_confirmation=true`（必须有人类确认）。
2. 确认人固定为「接收方用户」（to_user），不是发起方用户。
3. 执行者固定为「接收方 Advisor（receiver advisor）」；发起方只负责提出请求并接收结果回执。
4. 支持 advisor-to-advisor 多轮会话：同一问题链路复用同一个 `thread_id`。
5. 必须设置终止条件：`max_turns`（默认 5）或线程超时，避免无限对话。

## 3. 端到端时序（按你的示例）

示例：`B-advisor -> A-advisor: complete B's task(task_id=xxxxx)`

1. B-advisor 创建跨 advisor 请求消息（状态 `queued`）。
2. 系统投递给 A-advisor（状态 `delivered`）。
3. A-advisor 用 LLM 解析请求并判定：该请求需要 A 用户确认。
4. 系统创建 pending action（`awaiting_user_confirm`），并向 A 用户发问。
5. A 用户回复“同意/可以/okay”。
6. 系统匹配 pending action，写入 `approved`。
7. A-advisor（接收方 advisor）恢复执行管线，调用现有 `execution_service` 执行任务完成动作。
8. 系统将执行结果回传给 B-advisor。
9. 执行结果回传 A-advisor 与 B 用户会话（成功/失败均要落审计）。

## 3.1 A-advisor 询问 B-advisor 并继续处理（调用顺序）

1. A 用户消息进入 `/api/v2/advisor/chat`。  
2. `advisor_orchestrator(A)` 判断需要 B-advisor 信息，调用 `advisor_cross_message_service.create_request(...)`。  
3. A 侧创建/更新 `advisor_pending_actions` 为 `awaiting_peer_reply`，写入 `resume_payload`。  
4. B 侧收到请求，由 `advisor_orchestrator(B)` 基于消息 + 上下文进行 LLM 思考并生成 reply。  
5. `advisor_cross_message_service.create_reply(...)` 写回同一 `thread_id`。  
6. A 侧将 pending action 置为 `peer_replied`。  
7. `advisor_orchestrator(A)` 使用 `resume_payload + B reply` 恢复原流程。  
8. 若仍需继续问 B，则在同一 `thread_id` 下进入下一轮；否则进入执行或结束。  

## 4. 数据模型（新增）

### 4.1 `advisor_cross_messages`
字段：
1. `message_id`(uuid, unique)
2. `thread_id`(uuid)
3. `from_user_id` / `to_user_id`
4. `from_advisor_id` / `to_advisor_id`（MVP 可先写固定值 `default`）
5. `message_type`：`action_request|decision_reply|execution_result`
6. `payload`：
- `action_type`（如 `tasks_complete`）
- `action_params`（task_id, name, opentime, reason...）
- `require_confirmation`(bool)
- `decision`(approve/reject/null)
- `execution_result`(success/error/summary)
7. `status`：`queued|delivered|processed|failed|expired`
8. `idempotency_key`(可选)
9. `created_at` / `updated_at` / `expires_at`（可选）

### 4.2 `advisor_pending_actions`（复用并扩展）
新增/统一字段：
1. `action_type`: `cross_advisor_action_confirmation`
2. `source_message_id`
3. `thread_id`
4. `requester_user_id`（谁发起）
5. `approver_user_id`（谁确认）
6. `resume_payload`（确认后恢复执行所需参数）
7. `status`: `awaiting_user_confirm|approved|rejected|expired|consumed`
8. `turn_count`（当前 advisor 对话轮次）
9. `max_turns`（默认 5）

## 5. 状态机（强约束）

### 5.1 Cross Message 状态机
1. `queued -> delivered -> processed`
2. 任一状态可进入 `failed`
3. `queued/delivered` 超时可进入 `expired`

### 5.2 Pending Action 状态机
1. `awaiting_peer_reply -> peer_replied|expired`
2. `peer_replied -> awaiting_peer_reply|awaiting_user_confirm|consumed`
3. `awaiting_user_confirm -> approved|rejected|expired`
4. `approved -> consumed`（执行管线已接管）
5. `rejected/expired/consumed` 均为终态，不可逆

## 6. 入口与 API 策略（MVP）

### 6.1 跨 advisor 请求发起（无新增 endpoint）
跨 advisor request 不暴露对外 API。  
发起入口统一为内部服务调用：
1. `advisor_orchestrator` 在对话中识别到跨 advisor 写请求后，直接调用 `advisor_cross_message_service.create_request(...)`。
2. 后续如有系统事件触发，也走同一 service，不新增外部接口。

### 6.2 用户确认入口（仅 Chat，不新增 endpoint）
1. A-advisor 创建 pending action 后，向 A 用户发送一条 advisor chat 消息（并触发 push）。  
2. 用户点击 push 进入现有 chat 页面，在 chat 中回复“同意/拒绝/补充问题”。  
3. `advisor_orchestrator.handle_chat` 识别该回复对应的 pending action，并写入 `approved/rejected`，随后继续或终止执行流程。  
4. 全流程不新增任何用于确认的独立 API。

### 6.3 线程查询
不新增对外线程查询 endpoint。线程内容通过现有 chat 历史与内部审计记录查看（内部工具/DB）。

## 7. 执行编排（与现有代码对齐）

1. 新增服务：`advisor_cross_message_service.py`
- 创建消息
- 投递消息
- 状态迁移
- 审计落库

2. 在 `advisor_orchestrator.handle_chat` 增加「pending action 恢复分支」
- 类似现有 `task_create_clarification` 恢复逻辑
- 当识别到 `cross_advisor_action_confirmation` 且用户已批准时，触发恢复
- 由接收方 advisor 调用 skill 执行，不切回发起方 advisor

3. 执行仍走现有 `execution_service.create_execution_job/run_execution_job`
- 不重写执行框架
- 只新增「恢复输入构造」与「执行后回传 cross message」

## 8. LLM 决策规范（接收方 Advisor）

Prompt 必须输出结构化 JSON：
1. `needs_confirmation`(bool)
2. `question_to_user`(string)
3. `decision_hint`(`approve|reject|ask_more`)
4. `reason`(string)

规则：
1. 只要是跨用户写请求，`needs_confirmation` 只能为 true。
2. `question_to_user` 必须可直接发送给用户，长度 <= 200 字。
3. 用户确认语义词（同意/可以/okay/yes）映射为 `approve`。

## 9. 安全与权限

1. 仅同一 team 内用户允许互发 cross-advisor 请求。
2. action 执行前二次校验：`task_id` 所属用户必须与 action 目标一致。
3. 审批人必须是 pending action 的 `approver_user_id`。
4. 所有写操作在 execution result 内记录 `write_confirmed`（复用现有约束）。

## 10. 开发任务拆分（可直接排期）

### P0（必须）
1. 建表与索引：`advisor_cross_messages` + `advisor_pending_actions` 扩展索引。
2. 新增模型：`models/advisor_cross_message.py`。
3. 不新增 `advisor_message` 对外路由；发起与确认全部复用现有 `/api/v2/advisor/chat`。
4. 新增服务：`services/advisor_cross_message_service.py`。
5. `advisor_orchestrator` 增加三段逻辑：跨 advisor 意图识别后内部发起 request；peer reply 到达后恢复；用户确认后恢复执行。
6. `execution_service` 增加执行完成后 cross result 回传，并由接收方 advisor 在 chat 中反馈给用户。
7. 增加多轮控制：每轮递增 `turn_count`，达到 `max_turns` 后自动终止并给用户说明。

## 11. 验收标准（必须全部满足）

1. A 用户未确认前，A-advisor 不会执行写操作。
2. A 用户确认后，A-advisor 能触发并完成执行。
3. 执行结果会回传到 B-advisor 请求线程。
4. 全链路可追踪（message + pending + execution job + audit logs）。
5. 同一 `thread_id` 支持多轮 advisor 对话，并在 `max_turns` 或超时后稳定结束。

## 12. 非目标（本次不做）

1. 多级审批（A 确认后还要 C 确认）。
2. 自动审批策略引擎。
3. 跨团队/陌生用户 advisor 通信。

## 13. 前端展示约束（新增）

### 13.1 数据契约（后端）
1. 复用现有 `chat_messages` 集合，不新建前端专用会话表。
2. 协作线程消息必须在 `metadata` 写入以下字段：
- `channel`: `advisor_user` | `advisor_collab`（协作线程固定 `advisor_collab`）
- `readonly`: bool（协作线程固定 `true`）
- `thread_id`: string（对应 `advisor_cross_messages.thread_id`）
- `collab_status`: `in_progress|waiting_user_confirm|done|failed|expired`
- `peer_user_id`: string（对端用户）
3. 普通消息若无上述字段，按 `channel=advisor_user` 处理（向后兼容旧数据）。

### 13.2 会话列表接口契约（`GET /advisor/sessions`）
1. 在现有 `SessionSummaryResponse` 上新增字段：
- `channel`（默认 `advisor_user`）
- `readonly`（默认 `false`）
- `thread_id`（可空）
- `collab_status`（可空）
- `peer_user_id`（可空）
2. `chat_history_service.get_sessions()` 聚合时，从该 `session_id` 的最新一条消息 `metadata` 提取上述字段返回。
3. 列表排序规则保持不变：按 `last_message_at` 倒序混排（协作与普通会话不分组）。

### 13.3 历史列表 UI 规则（`advisor_screen.dart` 的 `_HistoryPanel`）
1. 使用同一列表展示全部 session（现有行为不变）。
2. 当 `channel=advisor_collab` 时，标题上方增加固定标记：`Advisor 协作记录`。
3. 协作会话 subtitle 显示：`最后更新时间 + collab_status`；普通会话继续显示 `x messages`。
4. 协作会话 preview 使用后端已脱敏摘要，不显示内部推理原文。

### 13.4 会话详情只读规则（Chat 页）
1. 进入 `readonly=true` 的 session 时：
- 隐藏输入框与发送按钮
- 禁用键盘输入与提交动作
2. UI 文案固定：`这是 Advisor 协作记录，仅供查看。`

### 13.5 后端硬校验（必须）
1. 在 `POST /api/v2/advisor/chat`（`advisor_v2_routes.advisor_chat_v2`）增加校验：
- 若 `request.session_id` 对应会话为 `readonly=true`，直接拒绝用户写入。
2. 拒绝返回：`409 Conflict`，`detail="This advisor collaboration thread is read-only."`
3. 该校验优先于 LLM 路由与执行逻辑（即不进入 `advisor_orchestrator.handle_chat`）。

### 13.6 内容边界（协作线程）
1. 允许展示：请求摘要、确认结论、执行结果、失败原因（面向用户可读）。
2. 禁止展示：LLM chain-of-thought、完整内部 prompt、敏感凭证与 token 信息。
