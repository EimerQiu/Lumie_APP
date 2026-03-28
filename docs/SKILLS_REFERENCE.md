# Advisor Skills 快速参考

> 文件路径：`lumie_backend/app/skills/system/`

---

## Lumie 内部数据（lumie_internal_data）

| Skill ID | 文件 | 触发场景 | 不适用场景 |
|---|---|---|---|
| `tasks_query` | `lumie_internal/tasks_query.md` | 查询任何时间段的任务/药物提醒（今天、明天、本周、上周、过期等），或按关键词查找特定任务 | 综合健康报告 |
| `health_data_query` | `lumie_internal/health_data_query.md` | 单项健康数据查询：睡眠、运动活动、步行测试、休息日、心率 | 跨域综合分析、任务查询 |
| `comprehensive_health_assessment` | `lumie_internal/comprehensive_health_assessment.md` | 跨域综合健康报告，同时涵盖睡眠+活动+药物+步行测试（"我最近整体情况怎样"） | 只问单项数据时 |
| `team_member_health_snapshot` | `lumie_internal/team_member_health_snapshot.md` | 家长/管理员查看某个团队成员的健康概况 | 查询自己的数据 |

---

## 浏览器操作（browser_portal_access）

| Skill ID | 文件 | 触发场景 |
|---|---|---|
| `school_homework_query` | `browser/school_homework_query.md` | 登录学校门户，查询近期作业和作业截止日期 |

---

## 邮件（email_read）

| Skill ID | 文件 | 触发场景 |
|---|---|---|
| `email_keyword_search` | `email/email_keyword_search.md` | 在邮箱中按关键词搜索邮件，返回匹配邮件摘要 |

---

## Skill 路由机制说明

Layer 1（Advisor 对话层）用 **关键词倒排索引** 从所有 skills 中检索候选项，再交给 Claude 选择最合适的 skill：

- **keywords** 字段权重最高（×3）
- **tags** 字段次之（×2）
- **title / summary** 文本最低（×1）
- 分词器是简单的正则 `\w+`，**无词干处理**，`reminder` 和 `reminders` 是两个不同的 token

新增 skill 时，keywords 要覆盖用户可能说的所有变体词。

---

## 当前 Skill 文件列表

```
lumie_backend/app/skills/system/
├── lumie_internal/
│   ├── tasks_query.md
│   ├── health_data_query.md
│   ├── comprehensive_health_assessment.md
│   └── team_member_health_snapshot.md
├── browser/
│   └── school_homework_query.md
└── email/
    └── email_keyword_search.md
```
