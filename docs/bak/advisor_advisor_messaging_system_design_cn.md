# Advisor-to-Advisor 通讯系统：详细系统设计与开发需求文档（可直接开发）

版本：v1.0  
日期：2026-04-29  
适用范围：`/Users/ciline/Documents/development/projects/Lumie_APP`

---

## 1. 文档目标

本文档是可执行开发规范，不是概念说明。开发人员按照本文档即可直接实现 A2A（advisor-to-advisor）消息系统 MVP。

本文档约束优先级：
1. 本文档
2. 现有代码风格与约束
3. 旧 PRD（`docs/advisor_advisor_messaging_prd_cn.md`）

---

## 2. MVP 功能边界（严格）

### 2.1 必须实现
1. A 侧创建消息（`preset` / `open`）
2. B 侧收件箱拉取与详情查看
3. B advisor 自动思考（LLM）
4. 对 `preset=team_task_operation_request`：B 必须 approve/reject
5. approve 后执行 admin action（complete/delete）
6. 执行结果回传 A advisor，A 可查询线程
7. 完整审计日志（事件流）
8. 幂等（防重复创建、防重复决策、防重复执行）

### 2.2 明确不实现
1. 附件消息
2. 群组消息
3. 自动批准
4. 跨团队陌生用户通信

---

## 3. 术语与枚举（固定）

### 3.1 ConversationType
- `preset`
- `open`

### 3.2 PresetType
- `team_task_operation_request`

### 3.3 RequestedAction（仅 preset payload）
- `admin_complete_task`
- `admin_delete_task`

### 3.4 MessageStatus（严格状态机）
- `queued`
- `delivered`
- `thinking`
- `awaiting_user_decision`
- `executing`
- `responded`
- `failed`
- `expired`

### 3.5 DecisionType
- `approve`
- `reject`
- `reply`

---

## 4. 数据库设计

## 4.1 集合：`advisor_messages`

### 4.1.1 文档结构（Mongo）
```json
{
  "message_id": "uuid",
  "thread_id": "uuid",
  "conversation_type": "preset|open",
  "preset_type": "team_task_operation_request|null",
  "from_user_id": "string",
  "from_advisor_id": "string",
  "to_user_id": "string",
  "to_advisor_id": "string",
  "initiator_role": "user|advisor|system_event",
  "payload": {
    "text": "string|null",
    "request_note": "string|null",
    "team_id": "string|null",
    "task_id": "string|null",
    "requested_action": "admin_complete_task|admin_delete_task|null",
    "origin": "team_task_completed|team_task_delete_request|null",
    "advisor_b_thinking": "string|null",
    "advisor_b_suggestion": "string|null",
    "advisor_b_reply_to_a": "string|null",
    "decision": "approve|reject|reply|null",
    "decision_comment": "string|null",
    "execution_result": {
      "success": "bool|null",
      "message": "string|null",
      "error_code": "string|null",
      "error_detail": "string|null"
    }
  },
  "status": "queued|delivered|thinking|awaiting_user_decision|executing|responded|failed|expired",
  "idempotency_key": "string",
  "causation_id": "string|null",
  "correlation_id": "string|null",
  "error": "string|null",
  "retry_count": 0,
  "max_retries": 3,
  "created_at": "YYYY-MM-DD HH:mm:ss",
  "updated_at": "YYYY-MM-DD HH:mm:ss",
  "expires_at": "YYYY-MM-DD HH:mm:ss|null"
}
```

### 4.1.2 字段约束
1. `conversation_type=open` 时：
- `preset_type` 必须为 `null`
- `payload.text` 必填
- `payload.requested_action/team_id/task_id` 必须为 `null`

2. `conversation_type=preset` 时：
- `preset_type` 必填，且仅允许 `team_task_operation_request`
- `payload.task_id/team_id/requested_action` 必填
- `payload.text` 可空

3. `idempotency_key` 全局唯一

4. `expires_at`：
- preset 默认 `created_at + 24h`
- open 默认 `created_at + 72h`

## 4.2 集合：`advisor_message_events`

### 4.2.1 文档结构
```json
{
  "event_id": "uuid",
  "message_id": "uuid",
  "thread_id": "uuid",
  "event_type": "created|delivered|thinking_started|thinking_completed|decision_recorded|execution_started|execution_completed|response_sent|failed|expired",
  "actor_user_id": "string|null",
  "actor_advisor_id": "string|null",
  "from_status": "string|null",
  "to_status": "string|null",
  "metadata": {},
  "created_at": "YYYY-MM-DD HH:mm:ss"
}
```

## 4.3 索引（必须添加）
在 `lumie_backend/app/core/database.py` 的 `create_indexes()` 新增：

1. `advisor_messages.message_id` unique
2. `advisor_messages.thread_id`
3. `advisor_messages.to_user_id + status + created_at`
4. `advisor_messages.from_user_id + created_at`
5. `advisor_messages.idempotency_key` unique
6. `advisor_messages.expires_at` TTL（`expireAfterSeconds: 0`）
7. `advisor_message_events.event_id` unique
8. `advisor_message_events.message_id + created_at`

---

## 5. 后端模型定义

新增文件：`lumie_backend/app/models/advisor_message.py`

必须包含：
1. Enums：ConversationType, PresetType, RequestedAction, MessageStatus, DecisionType
2. 请求模型：
- `AdvisorMessageCreateRequest`
- `AdvisorMessageDecisionRequest`
3. 响应模型：
- `AdvisorMessageResponse`
- `AdvisorMessageListResponse`
- `AdvisorMessageThreadResponse`

### 5.1 Create Request（精确）
```python
class AdvisorMessageCreateRequest(BaseModel):
    to_user_id: str
    conversation_type: ConversationType
    preset_type: Optional[PresetType] = None
    payload: dict
    session_id: Optional[str] = None
    idempotency_key: str = Field(..., min_length=8, max_length=128)
```

### 5.2 Decision Request（精确）
```python
class AdvisorMessageDecisionRequest(BaseModel):
    decision: DecisionType
    comment: Optional[str] = Field(None, max_length=1000)
    idempotency_key: str = Field(..., min_length=8, max_length=128)
```

---

## 6. API 设计（精确契约）

新增路由文件：`lumie_backend/app/api/advisor_message_routes.py`
路由前缀：`/advisor/messages`
Tag：`advisor-messages`

## 6.1 创建消息
`POST /api/v2/advisor/messages`

### 请求
```json
{
  "to_user_id": "user-b-id",
  "conversation_type": "preset",
  "preset_type": "team_task_operation_request",
  "payload": {
    "task_id": "task-123",
    "team_id": "team-1",
    "requested_action": "admin_delete_task",
    "request_note": "I want admin to confirm deletion",
    "origin": "team_task_delete_request"
  },
  "idempotency_key": "a2a-create-<uuid>",
  "session_id": "optional"
}
```

### 响应 201
```json
{
  "message_id": "uuid",
  "thread_id": "uuid",
  "status": "queued"
}
```

### 错误
- `400` 参数不合法
- `403` 无权限联系该用户
- `404` `to_user_id` 不存在
- `409` `idempotency_key` 冲突（返回同一 message_id）

## 6.2 收件箱
`GET /api/v2/advisor/messages/inbox?status=awaiting_user_decision&limit=20&offset=0`

### 响应 200
```json
{
  "items": [...],
  "total": 12
}
```

## 6.3 消息详情
`GET /api/v2/advisor/messages/{message_id}`

### 规则
- 仅 `from_user_id` 或 `to_user_id` 可见
- 其他用户返回 `403`

## 6.4 决策
`POST /api/v2/advisor/messages/{message_id}/decision`

### 请求
```json
{
  "decision": "approve",
  "comment": "Looks good",
  "idempotency_key": "a2a-decision-<uuid>"
}
```

### 响应 200
```json
{
  "message_id": "uuid",
  "status": "executing"
}
```

### 决策业务规则
1. 仅 `to_user_id` 可调用
2. 仅 `status=awaiting_user_decision` 可调用
3. `preset` 只允许 `approve/reject`
4. `open` 只允许 `reply`

## 6.5 线程查询
`GET /api/v2/advisor/messages/thread/{thread_id}`

- 返回该线程按 `created_at asc` 的全部消息

---

## 7. 服务层设计

## 7.1 `advisor_message_service.py`（核心）
必须实现以下函数：

1. `create_message(request_user_id: str, req: AdvisorMessageCreateRequest) -> dict`
2. `list_inbox(user_id: str, status: Optional[str], limit: int, offset: int) -> dict`
3. `get_message(user_id: str, message_id: str) -> dict`
4. `decide_message(user_id: str, message_id: str, req: AdvisorMessageDecisionRequest) -> dict`
5. `list_thread(user_id: str, thread_id: str) -> dict`
6. `mark_expired_messages(now: datetime) -> int`

## 7.2 `advisor_message_processor.py`（异步处理）
必须实现：

1. `process_queued_messages(batch_size: int = 20)`
2. `process_single_message(message_id: str)`
3. `run_thinking_step(message: dict) -> dict`
4. `transition_status(message_id, from_status, to_status)`（CAS 更新）

### 7.2.1 Thinking 行为（固定）
- 当消息 `queued`：改为 `delivered`
- 当 `delivered`：改为 `thinking`
- 调 LLM 生成 `advisor_b_thinking/advisor_b_suggestion`
- `preset` -> `awaiting_user_decision`
- `open` -> `responded`

## 7.3 `advisor_message_action_executor.py`
必须实现：

1. `execute_preset_action(message: dict) -> dict`
2. `execute_admin_complete_task(admin_user_id: str, task_id: str) -> dict`
3. `execute_admin_delete_task(admin_user_id: str, task_id: str) -> dict`

执行映射：
- `requested_action=admin_complete_task` -> `admin_task_service.admin_complete_task(...)`
- `requested_action=admin_delete_task` -> `admin_task_service.admin_delete_task(...)`

---

## 8. 状态机与并发控制（必须按此实现）

## 8.1 合法迁移
1. `queued -> delivered`
2. `delivered -> thinking`
3. `thinking -> awaiting_user_decision`（preset）
4. `thinking -> responded`（open）
5. `awaiting_user_decision -> executing`（approve）
6. `awaiting_user_decision -> responded`（reject/reply）
7. `executing -> responded`
8. `* -> failed`
9. `queued|delivered|thinking|awaiting_user_decision -> expired`

## 8.2 CAS 更新规则
所有状态迁移必须使用：
```python
update_one({"message_id": id, "status": expected}, {"$set": {"status": next}})
```
若 `modified_count==0`，视为并发冲突，不得继续下游动作。

## 8.3 幂等规则
1. 创建消息：按 `idempotency_key` 去重
2. 决策：单独记录 `decision_idempotency` 集合（或在 `advisor_messages` 内保存处理过 key 数组）
3. 执行：`executing` 前检查 `payload.execution_result.success is None`

---

## 9. LLM 提示词规范（必须）

文件：`lumie_backend/app/services/advisor_message_prompt_service.py`

提供两个 prompt builder：
1. `build_preset_receiver_prompt(...)`
2. `build_open_receiver_prompt(...)`

输出必须为 JSON（严格 schema）：
```json
{
  "advisor_b_thinking": "...",
  "advisor_b_suggestion": "...",
  "advisor_b_reply_to_a": "..."
}
```

解析失败处理：
- 重试 1 次（temperature=0）
- 仍失败 -> `failed`，`error="LLM_OUTPUT_PARSE_ERROR"`

---

## 10. 权限规则（必须逐条实现）

1. `create_message`：发送方与接收方必须满足任一：
- 同一 `team_id` 下均为 `team_members.status=member`
- 或发送方是接收方 team admin（用于管理流程）

2. `preset/team_task_operation_request`：
- `to_user_id` 必须是 `payload.team_id` 的 admin
- `from_user_id` 必须是该 team 成员
- `task_id` 必须属于该 team

3. `approve` 执行前再次校验 admin 身份，防止审批后权限变化

4. 任意消息读取必须是消息参与方

---

## 11. 错误码与错误语义（固定）

统一返回格式：
```json
{
  "error_code": "STRING_CODE",
  "detail": "human readable"
}
```

必须支持：
- `A2A_INVALID_PAYLOAD`
- `A2A_PERMISSION_DENIED`
- `A2A_TARGET_NOT_FOUND`
- `A2A_STATUS_CONFLICT`
- `A2A_IDEMPOTENCY_CONFLICT`
- `A2A_MESSAGE_EXPIRED`
- `A2A_EXECUTION_FAILED`
- `A2A_LLM_FAILED`
- `A2A_INTERNAL_ERROR`

---

## 12. 与现有模块集成点

1. `advisor_v2_routes.py` 不改原 `/chat` 协议
2. `main.py`（或 API router 汇总处）挂载 `advisor_message_routes`
3. 可选：在 task/admin 操作入口触发 preset 创建
- MVP 先通过 API 手动创建
- 下一阶段再做自动触发

4. `chat_history_service`
- 新增系统消息写入方法：`save_system_message(...)`
- 当消息 `responded` 时写入双方会话

---

## 13. 后台调度

## 13.1 处理循环
在 `notification_daemon.py` 增加周期任务：
1. `process_advisor_messages()` 每 5 秒
2. 批量拉取 `status=queued`（最多20）
3. 串行或有限并发（建议并发=3）处理

## 13.2 过期任务
每 60 秒执行：
- 扫描 `expires_at < now` 且 status 非终态
- 状态改为 `expired`
- 记录事件

---

## 14. 开发任务拆解（按文件）

## 14.1 数据与模型
1. 新建 `app/models/advisor_message.py`
2. 修改 `app/core/database.py` 增加索引

## 14.2 服务
1. 新建 `app/services/advisor_message_service.py`
2. 新建 `app/services/advisor_message_processor.py`
3. 新建 `app/services/advisor_message_action_executor.py`
4. 新建 `app/services/advisor_message_prompt_service.py`

## 14.3 API
1. 新建 `app/api/advisor_message_routes.py`
2. 在 API 注册入口挂载

## 14.4 守护进程
1. 修改 `lumie_backend/notification_daemon.py` 增加处理周期

## 14.5 测试
1. 新建 `tests/test_advisor_message_service.py`
2. 新建 `tests/test_advisor_message_routes.py`
3. 新建 `tests/test_advisor_message_processor.py`

---

## 15. 测试用例（必须通过）

### 15.1 创建消息
1. 正常创建 open -> `201 queued`
2. 重复 `idempotency_key` -> `409` 且返回同 message_id
3. 非团队关系创建 -> `403`

### 15.2 preset 校验
1. task 不在 team -> `400 A2A_INVALID_PAYLOAD`
2. to_user 非 admin -> `403 A2A_PERMISSION_DENIED`

### 15.3 processor
1. queued -> thinking -> awaiting_user_decision（preset）
2. queued -> thinking -> responded（open）
3. LLM JSON 无法解析 -> failed

### 15.4 decision
1. preset approve -> executing -> responded(success)
2. preset reject -> responded
3. 非接收方决策 -> 403
4. 非 awaiting_user_decision 决策 -> 409

### 15.5 执行
1. approve 后 `admin_delete_task` 成功
2. approve 后执行失败 -> responded + execution_result.success=false

---

## 16. 完成定义（DoD）

以下全部满足才算完成：
1. 所有新 API 可用并通过测试
2. 状态机无非法跳转
3. 幂等可验证
4. 审计事件完整
5. 两条主流程可端到端跑通：
- preset 审批执行回执
- open 思考回复

---

## 17. 实现细节补充（禁止模糊）

1. 时间格式统一使用现有 `format_utc_datetime(...)`
2. `message_id/thread_id/event_id` 均使用 `uuid4()` 字符串
3. `from_advisor_id/to_advisor_id` MVP 固定格式：`"advisor:<user_id>"`
4. 所有 DB 写操作必须设置 `updated_at`
5. 所有失败都必须记录 `advisor_message_events(event_type=failed)`
6. 不允许 silent fail（捕获异常后必须写日志 + 错误状态）

---

## 18. 未来扩展预留字段（本期不使用但必须保留）

在 `payload` 预留：
- `attachments: []`
- `policy_flags: {}`
- `auto_approval_eligible: bool|null`

这些字段本期只存不处理。

---

## 19. 交付顺序（推荐执行顺序）

1. 数据模型与索引
2. service（create/get/list/thread）
3. processor + prompt
4. decision + action executor
5. API 路由
6. daemon 集成
7. 测试与联调

按此顺序开发，可最大化减少返工。
