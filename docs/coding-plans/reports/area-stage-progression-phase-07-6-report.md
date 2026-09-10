# Global Stage Range / Area 模型 — Phase 7.6 报告

> 对应计划：`docs/coding-plans/global-stage-range-coding-plan.md`（Rev 3，Phase 7.6）。
> 前置输入：`area-stage-progression-coding-plan.md`（Rev 2.1）、`reports/area-stage-progression-phase-07-5-report.md`。
> 触发原因：Phase 7.5 交付后实测出三个缺陷（两份 current stage 漂移 / 「endless vs authored」二分让地图永久冻结 / 阵亡回退不写位置），根因都是"Stage 被当成每个 Area 各自的号空间"。
> 范围：**不**做存档（Phase 8）、**不**加新 Area 内容（Phase 9）、**不**改战斗引擎 / LevelProvider / HUD 视图切换 / 任何 `.tscn`。

---

## 1. 一句话结果

Stage 现在是**一个全局递增计数器**（永不复位），Area 只是它上面的一段**区间**；位置只有一份、只有一个写入点，`current_area_id` 不再存储而是由位置推导。

```text
Stage 1–10   → Area forest   （Forest）
Stage 11–20  → Area forest2  （Forest 2，本 Phase 未 ship，测试里用合成区间验证）
Stage 21+    → 无 Area（纯 endless 推进，地图不显示 HERE，底部提示 ENDLESS）
```

---

## 2. 改了什么（逐层）

### 2.1 数据层

| 文件 | 变更 |
|---|---|
| `scripts/data/stage_database.gd` | 新增 `first_stage`（区间起点，全局号）+ `get_last_stage()` + `covers(n)`；`get_stage(n)` 语义改为**全局号**且区间外返回 null；id 补零宽度改由 `last_stage` 位数决定（forest 仍是 `forest_001…forest_010`，宽度一字未变）；新增静态区间查找 `database_for_stage(n)` / `area_for_stage(n)` / `lookup(n)`（带**区域表缓存**，避免每次查询扫盘）；新增静态 `collect_range_conflicts()` / `get_authored_range_conflicts()`（区间不重叠校验）与测试 seam `set_area_table_override()` / `clear_area_table_override()` / `invalidate_cache()` |
| `resources/stage_databases/forest.tres` | 只加一行 `first_stage = 1`（内容、id、`special_stages` 全部不变） |
| `scripts/progress/player_progress.gd` | 三字段模型：`current_stage_number`（唯一位置）、`highest_stage_reached`（单调不减的解锁上限，**新增**）、`completed_stages`（显式完成，key 仍是 canonical id）。**删除** `current_area_id`；新增推导 `get_current_area_id()` / `get_current_area_name()` / `mark_reached(n)`；`is_stage_unlocked/is_stage_completed/complete_stage` 全部改收**全局号** |

### 2.2 流程层

| 文件 | 变更 |
|---|---|
| `scripts/systems/stage_router.gd` | `route(stage_number)` / `request_enter(stage_number)`：不再收 `area_id`，area 由区间推导并写回 route 记录；失败路径文案改为「No authored stage N (no area covers that stage number).」 |
| `scripts/systems/stage_flow.gd` | 新增**唯一位置写入点** `on_stage_started(n)`（写 `current_stage_number` + 抬 `highest_stage_reached`）；`on_battle_cleared(n)` 去掉 area 空值 early return，改为"某 area 覆盖 → 记完成并报下一关；无人覆盖 → 不记但位置照旧前进"；`next_stage_text(n)` 增加跨区文案 `AREA FOREST COMPLETE (10/10) — NEXT: FOREST 2`；TOWN 进入走同一个写入点 |
| `scripts/world/grid_combat.gd` | `_on_stage_started()` 转发到 `_flow.on_stage_started(...)`（**一处接线覆盖全部 5 条改关号入口**：开机 / 地图、DEV 进入 / 推进 / 阵亡回退 / FARMING 原地重刷）；`enter_area_stage(stage_number, from_world_map)` 去掉 area 参数；地图点击门槛与锁定文案改用全局号 |
| `scripts/world/stage_content_controller.gd` | 内容层改用全局 `lookup(n)`；未覆盖区间时照旧零内容 |

### 2.3 呈现层

| 文件 | 变更 |
|---|---|
| `scripts/ui/area_view.gd` | 节点号改为 `first_stage .. last_stage`；`get_window_start/end` 按区间偏移；新增 `show_window_for_stage(n)`；`compute_state(progress, stage_number, first_stage)` 不再比较 area；副标题改为 `FOREST (1–10) · at stage 3`；节点点击只发全局号 |
| `scripts/ui/world_map_view.gd` | 信号与转发全部改全局号；打开时**自动跳到含当前位置的窗口**；底部新增 `ENDLESS — stage N (no area authored)`（§11(c)）；区域表改读 `StageDatabase.discovered_databases()`（与区间推导共用同一份缓存，不再各扫一遍目录）；新增只读访问器 `get_endless_text()` |
| `scripts/ui/development_panel.gd` / `mobile_combat_hud.gd` | DEV「AREA STAGES」按区间枚举，信号改传全局号 |
| `scripts/ui/stage_control.gd` | 新增只读访问器 `get_current_stage()`（让测试/调用方不必掏私有字段即可核对阶段条与位置同号） |

---

## 3. 三个缺陷的验证（门禁逐条）

| 缺陷 | 本 Phase 的修法 | 验证 |
|---|---|---|
| A：两份 current stage，只有一份被推进 | 删除 `current_area_id`，位置收敛为 `current_stage_number`，且只有 `on_stage_started()` 写它 | `test_stage_range` T4：手动推进 / AUTO 推进 / 阵亡回退三条路径下，**阶段条 == 战斗关号 == `PlayerProgress.current_stage_number` == 地图 HERE** |
| B：「endless vs authored」二分让地图永久冻结 | 删除 area 空值 early return；开机就是 Area 1 的 stage 1，清场即记账 | `test_stage_progression::test_boot_clear_records_area_1_progress_and_advances`（旧用例语义反转后重写）；`test_stage_range` T1 |
| C：阵亡回退不写位置 | 回退走 `initialize_stage()` → `stage_started` → 同一个写入点 | `test_stage_range` T4(c)：回退后位置跟着后退，且 `highest_stage_reached` 不回退 |

---

## 4. 跨区间与区间外

- **跨区间自动切 Area**（T2）：清掉 10 → 文案读第二个 Area 的数据（`STAGE 11 (COMBAT) UNLOCKED`）→ 推进到 11 → 推导 area 变 `forest2` → 地图第二个 Area 的 11 标 HERE，第一个 Area 不再标 HERE。全程零特例代码。
- **解锁链跨区间**（T3）：完成 10 → `is_stage_unlocked(11)` 为真；且它不会顺带解锁 12。
- **区间外（51+ 语义，测试里用 21+）**（T5）：位置继续前进、`completed_stages` 不增长、地图不显示 HERE、底部 `ENDLESS — stage 21 (no area authored)`；`highest_stage_reached` 仍上升 —— 这正是修掉"author 内容结束后解锁死锁"的那条通道。
- **区间不重叠**（T6）：`collect_range_conflicts()` 报出重叠；相邻（10 / 11）不算重叠；ship 的 area 通过该检查。

---

## 5. 与计划文档的 4 处有意偏差（理由见计划 §15）

1. `is_stage_unlocked(n)` = `n==1 或 n<=highest_stage_reached 或 is_stage_completed(n-1)`。计划 §5.3 的代码草稿只留 reach 一条，但那样"完成 5"不会解锁 6、TOWN 访问不会解锁 9，与 §10.1 要求保留的断言和现有地图体验冲突；§5.3 的**论证**只要求 reach 作为修 51+ 死锁的**额外**通道。
2. 唯一写入点命名为 `StageFlow.on_stage_started(n)`（计划写 `on_battle_started`）：TOWN 不启动战斗，但"进入城镇"同样是站在那一关，需要一个不误导的名字。字段写入仍只有一处。
3. 区间重叠校验是**静态跨区** API（`collect_range_conflicts`），不是单实例 `get_validation_errors()` —— 单个 Resource 看不到兄弟资源。
4. 不新建 `forest2.tres`：测试用 `set_area_table_override()` 在内存里造 Area 2 = 11–20，本 Phase **零新增游戏内容**（新 Area 留给 Phase 9）。

另有一处**保持现状不改**：`AreaView.compute_state()` 仍是 COMPLETED 优先于 CURRENT，所以阵亡回退到"已清过的关"时地图显示 DONE 而非 HERE（旧行为如此）。本 Phase 修的是"HERE 停在旧位置"这个漂移；三处位置现在永远同号。计划 §13 的"三处同号"门禁场景是推进到未清过的关，不受影响。

---

## 6. 测试与回归

新增 `tools/ui_harness/suites/test_stage_range.gd`（T1–T6，6 用例 78 断言，全绿）。

改写（按计划 §10）：
`tests/player_progress_smoke_test.gd`（全局号 + 推导 area + 跨区解锁 + reach 单调 + "`current_area_id` 不再存在"守卫 + `highest_stage_reached` 守卫）、
`tests/stage_database_smoke_test.gd`（区间用例、区间外 null、重叠/相邻、`first_stage>=1`、局部号 override 被拒）、
`tests/stage_router_smoke_test.gd`（`route(n)`、area 推导）、
`tests/stage_content_smoke_test.gd`（`lookup(n)`）、
`tools/ui_harness/suites/test_stage_flow.gd`（`enter_area_stage(n)`，删 `current_area_id` 断言，改断言"被拒绝的进入不改位置/不改解锁上限"）、
`tools/ui_harness/suites/test_stage_progression.gd`（全局号 API；boot 用例语义反转并改名）、
`tools/ui_harness/suites/test_world_map.gd`（全局号 + 删除 `current_area_id` 写入 + 新增"非默认 `first_stage` 的分页偏移"用例）、
`tools/ui_harness/suites/test_stage_content.gd`（`enter_area_stage(n)`）。
`test_stage_exit_advance.gd` 未改（复核后与 boot 写进度不冲突）。

回归结果：

```text
5 个 smoke（player_progress / stage_database / stage_router / stage_content / area_stage_data）  全绿
全量 ui_harness: 83 tests, 82 passed, 1 failed   ← 唯一失败是既有历史失败
                                                 test_combat_log_wiring::test_kill_logs_event_end_to_end
                                                 （baseline 同样失败：76 tests, 75 passed, 1 failed）
无新增脚本错误 / parse 干净
```

---

## 7. 对 Phase 8（Save / Load）的交接

- 需要序列化的位置/进度字段：`current_stage_number`、**`highest_stage_reached`（新增，必须一起存，否则读档后地图解锁状态丢失）**、`completed_stages`（key 仍为 `<area_id>_<补零全局号>` 形态，如 `forest_006`）。
- **不要**序列化 area：它是推导量。存档里出现 area 字段即为第二份位置回归。
- 存档 id 与区间的耦合提醒：将来重新划分区间（例如 dungeon 从 21 改成 25 起）会改变该 Area 的 id 形态，旧存档里的 `completed_stages` 会保留旧 id —— 那时需要一次迁移。当前无存档，代价为零。

---

## 8. 仍然不做的事

不改战斗引擎 / TurnManager / AutoCombatController、不改 `LevelProvider` 生成规则、不新增玩法类型、不做剧情、不做存档（Phase 8）、不为 51+ 造伪 Area、不 ship 第二个 Area（Phase 9）。
