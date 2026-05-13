# Advisor Planner Service 系统设计与开发文档

## 1. 背景与目标

当前系统存在两条路径：
- `Advisor-User` 直接对话（用户驱动）
- `Proactive` 手动事项执行（系统驱动）

在复杂任务（多步、条件分支、需要确认）场景下，单轮 `advisor_orchestrator.handle_chat(...)` 容易停在 `direct/guidance`，导致“有回答、无执行”。

本方案目标：
- 统一两条路径的复杂任务执行机制
- 保持 `proactive` 无业务逻辑（只编排，不硬编码业务）
- 让复杂任务通过“多轮自动对话”稳定收敛到执行结果

## 2. 核心原则

- `Planner Service` 只负责编排，不写具体业务规则
- `Advisor` 保持原有能力边界：理解请求、选 skill、发起执行
- `Execution Service` 仍是唯一技能执行入口
- Chat 与 Proactive 复用同一 Planner 回路
- 所有自动确认/继续都必须可审计、可回放、可中断

## 3. 总体架构

### 3.1 角色分工

- `advisor_orchestrator`
  - 统一入口
  - 判断是否需要 planner（复杂任务）
  - 简单任务继续走现有单轮逻辑

- `planner_service`（新增）
  - 将目标拆解为可执行步骤
  - 与 advisor 进行多轮“代理对话”
  - 在需要确认时代表用户确认
  - 追踪每一步执行状态，直到 `done/failed/timeout`

- `execution_service`
  - 执行 skill
  - 返回 `job_id / status / result`

- `proactive_advisor_service`
  - 对每条手动事项调用 planner
  - 读取 planner 结果作为 `manual_instruction_results`

### 3.2 流程总览

1. 请求进入 `advisor_orchestrator`（来源可能是 chat 或 proactive）
2. 复杂度判定：
   - 简单任务：沿用单轮流程
   - 复杂任务：创建 `planner_session`，委托 `planner_service`
3. planner 循环：
   - 产出下一条 message 给 advisor
   - advisor 正常处理（direct/guidance/execution）
   - 若 execution：等待 job 终态
   - planner 根据结果决定下一步（continue/done/failed）
4. 输出统一的执行结果给调用方（chat/proactive）

## 4. 复杂任务判定策略

建议在 `advisor_orchestrator` 增加 `should_use_planner` 判定（可后续抽到策略模块）：

触发条件（任一满足）：
- 请求包含多动作链（如 check + create / find + update）
- 明确条件逻辑（if/when/unless）
- 任务依赖上一步结果（先查再决定）
- 明显需要确认但当前来源无人类实时在环（proactive）

非触发条件：
- 单一查询
- 单一写操作且参数完整
- 纯问答/建议

## 5. Planner Service 设计

### 5.1 输入输出

输入：
- `source`: `chat` | `proactive`
- `user_id`
- `goal_text`（用户原始意图或手动事项）
- `session_id`（chat 会话 / proactive）
- `context`（可选：历史、profile、team）
- `options`（max_steps、timeout、auto_confirm 等）

输出：
- `status`: `done` | `failed` | `timeout` | `aborted`
- `final_summary`
- `steps[]`（完整轨迹）
- `last_advisor_reply`
- `last_job_result`（如有）

### 5.2 状态机

- `pending` -> `running`
- `running` -> `done`
- `running` -> `failed`
- `running` -> `timeout`
- `running` -> `aborted`

### 5.3 回路算法（伪代码）

```text
create planner_session
for step in 1..max_steps:
  planner_msg = planner_next_instruction(state)
  advisor_resp = handle_chat(user_id, planner_msg, history=planner_history, session_id)

  if advisor_resp.type == execution:
    job = wait_job_terminal(advisor_resp.job_id)
    state.consume(job)
  else:
    state.consume(advisor_resp)

  decision = planner_decide(state)
  if decision in {done, failed}: break

if step > max_steps: status=timeout
persist planner_session + planner_steps
return result
```

### 5.4 自动确认策略

- 原则：Planner 不做语义枚举，不猜测业务，只执行通用“继续推进”策略
- 行为：当 advisor 未进入 `execution` 时，Planner 可发送一次标准确认语句（如 `Yes, proceed now and execute it.`）
- 限制：
  - 每步最多自动确认一次
  - 连续 N 步无 execution 则 fail-fast，避免死循环

## 6. 数据模型（MongoDB）

### 6.1 `planner_sessions`（新增）

字段建议：
- `planner_session_id` (uuid)
- `source` (`chat|proactive`)
- `user_id`
- `session_id`
- `goal_text`
- `status` (`pending|running|done|failed|timeout|aborted`)
- `max_steps`
- `current_step`
- `started_at`
- `finished_at`
- `final_summary`
- `error`

索引建议：
- `planner_session_id` unique
- `(user_id, started_at desc)`
- `(source, started_at desc)`

### 6.2 `planner_steps`（新增）

字段建议：
- `planner_session_id`
- `step_no`
- `planner_message`
- `advisor_response_type` (`direct|guidance|execution`)
- `advisor_reply`
- `job_id`
- `job_status`
- `job_result_summary`
- `decision` (`continue|done|failed`)
- `created_at`

索引建议：
- `(planner_session_id, step_no)` unique
- `(job_id)`

## 7. 与现有模块集成

### 7.1 `advisor_orchestrator` 改造点

- 新增复杂度判断入口
- 当复杂任务触发时，调用 `planner_service.run_planner_session(...)`
- 对 chat 来源：返回“已开始执行复杂任务”的中间响应 + 最终结果回填（可异步）

### 7.2 `proactive_advisor_service` 改造点

- `_execute_manual_checklist_instructions` 从“单次 handle_chat”改为“调用 planner”
- 将 planner 输出映射为 `manual_instruction_results`
- 不在 proactive 内写任何 task/health/home 等业务分支

### 7.3 审计联动

- `proactive_information_rounds.checklist.manual_instruction_results` 写入 planner 汇总
- `proactive_runs` 记录 `planner_session_id`（可选）

## 8. 失败与保护机制

- `max_steps`（默认 6~10）
- `step_timeout_seconds`（每步等待上限）
- `session_timeout_seconds`（整轮上限）
- `max_auto_confirms_per_step = 1`
- `max_consecutive_non_execution_steps`（连续无执行上限）
- 出错降级：返回结构化失败，不阻塞整轮 proactive

## 9. 开发计划（建议分期）

### Phase 1: 基础能力

- 新建 `planner_service.py`
- 新增 `planner_sessions/planner_steps` 数据结构与持久化
- 打通最小回路（planner -> advisor -> execution/job -> planner）

### Phase 2: Proactive 接入

- 用 planner 替换手工事项单轮执行
- 保留现有返回结构，最小化上层改动

### Phase 3: Chat 接入

- 在 `advisor_orchestrator` 加复杂任务判定与 planner 委托
- 增加 chat 侧可见的执行态与最终态

### Phase 4: 观测与策略

- 增加 planner metrics（成功率、平均步数、超时率）
- 优化 fail-fast 与重试策略

## 10. 测试计划

### 10.1 单元测试

- planner 状态机流转
- 单步成功/失败/超时
- 自动确认触发一次且不死循环

### 10.2 集成测试

- proactive 手工事项：check+create 多步任务成功收敛
- chat 复杂任务：能自动多轮推进至 execution
- 权限错误/缺凭证场景：可失败并产出明确 summary

### 10.3 回归测试

- 简单单轮任务不应误触 planner
- 原有 advisor 直连路径行为不变

## 11. 迁移与发布

- 先灰度：仅 `proactive` 使用 planner（feature flag）
- 稳定后开放到 chat
- 生产默认保留回退开关：`PLANNER_ENABLED=false` 可回退旧路径

## 12. 风险与注意事项

- 风险：planner 循环导致 token/时延上涨
  - 对策：严格步数上限与早停策略
- 风险：过度自动确认触发不期望写操作
  - 对策：planner 层加入写操作白名单和风险等级
- 风险：多模块日志难追踪
  - 对策：全链路携带 `planner_session_id`

## 13. 验收标准

- 复杂任务在 proactive 中可稳定执行，不再“只回复不执行”
- proactive 代码中无业务硬编码分支
- chat/proactive 共用同一 planner 编排机制
- 审计可回放每一步决策与执行结果

