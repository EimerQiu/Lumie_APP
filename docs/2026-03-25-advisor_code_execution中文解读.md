**整体架构**
文档里的核心思路已经落地：Advisor 不是单纯聊天，而是一个“LLM 路由层 + 后端执行层”的统一入口。用户始终走 [`/api/v1/advisor/chat`](/Users/ciline/Documents/development/projects/Lumie_APP/lumie_backend/app/api/advisor_routes.py)，后端在 [`advisor_service.py`](/Users/ciline/Documents/development/projects/Lumie_APP/lumie_backend/app/services/advisor_service.py) 里先调用 Claude 做一层 tool routing：
- 不需要用户数据时，直接返回 `type: "direct"`。
- 需要查用户数据时，调用 `run_data_analysis`，创建 `analysis_jobs` 任务，再异步执行。
- 现在还额外支持 `create_task`，用于直接写入任务系统，这条路不走沙箱。

分析任务的执行链在 [`analysis_service.py`](/Users/ciline/Documents/development/projects/Lumie_APP/lumie_backend/app/services/analysis_service.py)：
1. 创建 `analysis_jobs` 记录。
2. 组装 schema/glossary/profile prompt，见 [`analysis_prompt_service.py`](/Users/ciline/Documents/development/projects/Lumie_APP/lumie_backend/app/services/analysis_prompt_service.py)。
3. 调 Claude 生成 Python 分析代码，见 [`analysis_llm_service.py`](/Users/ciline/Documents/development/projects/Lumie_APP/lumie_backend/app/services/analysis_llm_service.py)。
4. 先做静态安全扫描，见 [`analysis_security_service.py`](/Users/ciline/Documents/development/projects/Lumie_APP/lumie_backend/app/services/analysis_security_service.py)。
5. 再进 Docker 沙箱执行，见 [`analysis_sandbox_service.py`](/Users/ciline/Documents/development/projects/Lumie_APP/lumie_backend/app/services/analysis_sandbox_service.py)。
6. 把 `summary/data/chart_base64/nav_hint` 写回 Mongo，再由前端轮询读取 [`analysis_routes.py`](/Users/ciline/Documents/development/projects/Lumie_APP/lumie_backend/app/api/analysis_routes.py)。

**Advisor Screen 如何接入**
Flutter 侧已经把 direct 和 analysis 两条路径统一进同一个 chat UI：
- 发送消息在 [`advisor_service.dart`](/Users/ciline/Documents/development/projects/Lumie_APP/lumie_activity_app/lib/core/services/advisor_service.dart)。
- 若返回 `analysis`，[`advisor_screen.dart`](/Users/ciline/Documents/development/projects/Lumie_APP/lumie_activity_app/lib/features/advisor/screens/advisor_screen.dart) 会先插入一个“分析中”占位消息，再用 [`analysis_service.dart`](/Users/ciline/Documents/development/projects/Lumie_APP/lumie_activity_app/lib/core/services/analysis_service.dart) 每 2 秒轮询 job。
- 成功后占位消息替换成富结果卡片 [`analysis_result_card.dart`](/Users/ciline/Documents/development/projects/Lumie_APP/lumie_activity_app/lib/features/advisor/widgets/analysis_result_card.dart)；失败则替换成错误消息。
- 同一个 screen 还接了 session/history 能力：`session_id` 会随请求发送，聊天消息持久化到 `chat_messages`，前端可按 session 恢复历史，相关代码在 [`chat_history_routes.py`](/Users/ciline/Documents/development/projects/Lumie_APP/lumie_backend/app/api/chat_history_routes.py)、[`chat_history_service.py`](/Users/ciline/Documents/development/projects/Lumie_APP/lumie_backend/app/services/chat_history_service.py)、[`chat_history_service.dart`](/Users/ciline/Documents/development/projects/Lumie_APP/lumie_activity_app/lib/core/services/chat_history_service.dart)。

**我认为现在这套架构的关键边界**
- `advisor_service.py` 是“意图编排层”：决定是 direct、analysis，还是 create_task。
- `analysis_service.py` 是“异步任务编排层”：管 job 生命周期、重试、通知、状态落库。
- `analysis_prompt/llm/security/sandbox` 四个 service 组成“代码执行子系统”。
- Flutter 的 advisor screen 只关心统一消息流，不关心后端内部走了哪条执行路径。

**有两个值得注意的现状**
- 文档和代码有少量漂移。比如设计文档/开发日志里写过 Layer 2 用 Haiku、analysis quota 是 free 3 / pro 20，但当前代码里 [`analysis_llm_service.py`](/Users/ciline/Documents/development/projects/Lumie_APP/lumie_backend/app/services/analysis_llm_service.py) 用的是 `claude-sonnet-4-6`，[`analysis_service.py`](/Users/ciline/Documents/development/projects/Lumie_APP/lumie_backend/app/services/analysis_service.py) 里的 daily limit 现在是 free/pro 都 200。
- 文档最初聚焦“只读数据分析”，但实际实现已经演进成“多工具 Advisor 平台”：除了 `run_data_analysis`，还接入了 `create_task`、chat persistence、analysis complete push 等附加能力。

所以如果我们接下来要“在架构中添加新的内容”，我建议把它当成给 `advisor_service.py` 继续增加新工具/新执行路径的问题，而不是只改分析沙箱本身。你下一步如果愿意，我们可以直接一起讨论：
1. 新能力应该是“只读分析型工具”
2. 还是“会写业务数据的操作型工具”
3. 还是“长任务/异步工作流型工具”

这三类在你们现有架构里，落点会很不一样。