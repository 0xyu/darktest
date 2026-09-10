# Area / Stage / StageType 系统 — Phase 7 报告（Stage Completion / Return Flow）

> 对应 `docs/coding-plans/area-stage-progression-coding-plan.md`（**Rev 2**）的 **Phase 7 — Stage Completion / Return Flow**。
> 前置输入：Phase 6 报告（`area-stage-progression-phase-06-report.md`）。范围：**「完成 → 解锁下一关 → 回 WorldMap」闭环**；不做存档（Phase 8）、不加新 Area（Phase 9）、EVENT 真实内容仍为占位。

---

## 1. 本 Phase 完成内容

把 Phase 6 留白的「逐关推进」闭环补上：

```text
WorldMap → Stage → Gameplay → Complete (PlayerProgress) → unlock next → 回 WorldMap
```

落地内容：

1. **完成语义（v1，全部只依赖 `(area_id, stage_number)` 经 StageRouter/StageDatabase 解析，零 stage 数字硬编码）**：
   - **COMBAT / BOSS（战斗型）**：author 战斗在自身 stage 清场时记录完成——`grid_combat._on_stage_completed` 内新增 typed-session 钩子 `_record_typed_battle_completion()`（幂等；FARMING 重刷同关不重复计数）。
   - **TOWN / EVENT（访问型）**：进入即算完成（`_record_typed_visit_completion()`）——本 build 城镇无"离开关卡"的持久玩法返回、EVENT 只是占位，若不如此 EVENT 06 会永久卡住 `06 → 07` 的线性解锁链；真实 EVENT 内容落地后可改回"由玩法返回判定"。DoD 中 `完成 05 → 06（EVENT）→ 07`、`进入 08 → Town`、`完成 09 → 10（BOSS）` 全链打通。
2. **清场状态文案数据驱动**：完成 N 后自动查 `StageDatabase` 下一关类型并显示（如 `STAGE 06 (EVENT) UNLOCKED`）；N 为末关时显示 `AREA FOREST COMPLETE (10/10)`（`_authored_next_text()` 读 `_stage_router.route(area, n+1)`，绝不写死类型/编号）。
3. **typed session 状态机**：`grid_combat._typed_entry` 记录当前 author 关（area_id / stage_number / stage_type / destination / from_map）。只在经 `enter_area_stage` 进入 author 关时非空；endless boot / 默认循环从不设置，因此**默认 endless 玩法与进度写入完全隔离**。
   - 战斗引擎漂移（AUTO/FARMING 推进、defeat 回退导致清场的 battle stage ≠ author stage）即视为 typed session 结束并清空记录——此后清场恢复 boot 式 endless 规则（不写 PlayerProgress）。
4. **返回地图闭环（host 层，未动战斗引擎）**：
   - 手动模式在 typed 战斗清场后走出口 + **NEXT STAGE**：`_advance_after_clear()` 拦截（仅当 typed destination == COMBAT），改为 `open_world_map()` 返回 hub，不再 `start_next_stage()` 无尽推进（typed 流程的"下一关"在地图上选）。
   - 地图来源（`from_map=true`）的 **TOWN** 进入：关闭城镇返回**刷新后的世界地图**（新增 HUD 信号 `town_close_requested`，由 host 裁决去向）。非地图来源（DEV / 直接 `enter_area_stage`）关闭仍回 CombatView——Phase 5 既有行为与测试零改动。
   - 地图来源的 **EVENT** 占位访问：完成即停留在地图（节点转 COMPLETED、下一关 AVAILABLE），不来回跳视图。
   - **endless boot 不变**：清场 → 出口 → `start_next_stage` 照旧（`test_stage_exit_advance` 4/4 零改动转绿证明）。
5. **AUTO / FARMING 语义（文档化的取舍）**：typed 关内 AUTO/FARMING 仍由战斗引擎驱动（挂机刷关）；typed 关首次清场即记完成（幂等），随后推进按漂移规则自然退出 typed session。地图式逐关推进是手动模式玩法。
6. **测试**：新增 `test_stage_progression` ui_harness 套件（8 测试，见 §4）。

---

## 2. 修改 / 新增的文件

### 修改

| 文件 | 说明 |
|---|---|
| `scripts/world/grid_combat.gd` | Phase 7 host：`_typed_entry` / `_entry_from_world_map` 状态；`enter_area_stage(…, from_world_map)`；`_record_typed_battle_completion` / `_record_typed_visit_completion` / `_authored_next_text` / `_return_to_world_map_from_typed_clear` / `_on_town_close_requested`；`_apply_stage_entry` 按 destination 收敛（TOWN/EVENT 记完成、EVENT 地图来源停留地图、记录 typed session）；`_on_stage_completed` typed 文案与记完成；`_advance_after_clear` typed 拦截；预加载 `StageTypeScript` / `StageDatabaseScript` |
| `scripts/ui/mobile_combat_hud.gd` | 新信号 `town_close_requested`；TownView `close_requested` 由直接 `show_combat` 改为转发该信号（host 裁决去向） |
| `docs/coding-plans/area-stage-progression-coding-plan.md` | Phase 7 标记「已完成」+ 实现备注；Execution Order：Chat 08 ✅、Chat 09（Phase 8）为当前 |

### 新增

| 文件 | 说明 |
|---|---|
| `tools/ui_harness/suites/test_stage_progression.gd` | Phase 7 ui_harness 套件（8 测试，见 §4） |
| `docs/coding-plans/reports/area-stage-progression-phase-07-report.md` | 本报告 |

> 未改：`StageDatabase / StageData / StageType / PlayerProgress / StageRouter`（核心数据/路由层再次零改动）、战斗引擎（`StageManager`/battle `StageState`/`AutoCombatController`/`TurnManager`）、`WorldMapView`/`AreaView`、TownView/DEV 面板、`.tscn`（无场景文件变更）。

---

## 3. 架构决策

### 3.1 完成钩子放在 grid_combat 的既有信号缝上，战斗引擎零改动

清场天然会触发 `stage_manager.stage_completed → grid._on_stage_completed`；typed 完成只是在该 handler 开头多调一次 `_record_typed_battle_completion(stage_number)`（带 typed/drift 判定）。**没有**给 StageManager/AutoCombat 加新信号、没有改任何 battle 侧行为。

### 3.2 typed session 与漂移规则：endless 与 author 流程只在一处切换

`_typed_entry` 只由 `_apply_stage_entry`（author 进入）写入；清场时若 battle stage ≠ author stage（AUTO/FARMING 推进、defeat 回退）说明引擎已把玩家带出 author 路径，立即清空 typed——此后完全回到 boot 式 endless（不写进度）。这让 DEV/自动挂机不会"偷偷"把 endless 战斗记成 author 完成，也保住默认循环原义。

### 3.3 访问型关卡（TOWN/EVENT）进入即算完成（v1，注明可回退）

编码计划建议 Town"进入即算完成"；EVENT 无内容却必须可完成才能解锁其后关卡（`完成 06 → 07`），因此 v1 把 EVENT 占位访问也视作完成，并在状态文案与地图节点上明确反馈。真实 EVENT 玩法落地时，只需把完成判定从"进入即完成"移到玩法返回处（改 `_apply_stage_entry` EVENT 分支一行语义 + 补 EVENT View 的 close/完成信号），核心不动。

### 3.4 城镇/地图关闭的去向由 host 裁决（一个信号解决）

TownView 的 close 原在 HUD 内直接 `show_combat`（grid 无法插话）。Phase 7 加 HUD 信号 `town_close_requested`，grid 监听后按 typed（destination==TOWN && from_map）决定回地图还是回战斗；`from_map` 通过 `enter_area_stage(…, from_world_map)` 一路带进 `_typed_entry`。DEV `open_town`（未走 author 进入）与直接 `enter_area_stage`（非地图来源）保持回 CombatView，Phase 5 的 `test_town_view` / `test_stage_flow` 断言零改动转绿。

### 3.5 "下一关"提示从数据读类型（再次验证无硬编码）

`_authored_next_text()` 用 `_stage_router.route(area_id, n+1)` 拿下一关 `stage_type` 与存在性（`ok=false` 即末关 → `AREA COMPLETE (n/n)`），文案/解锁全部数据驱动；没有任何 `if stage == N` 或类型表外判断。

---

## 4. 测试结果

执行命令（headless，`<project>` = `G:/godotproject/darkrpg`）：

```text
D:/IDE/godotEngine/Godot_v4.7.2-stable_win64_console.exe --headless --import --path .
D:/IDE/godotEngine/Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/ui_harness/ui_harness_runner.gd ++ --suite <name>
D:/IDE/godotEngine/Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/<phase 1-4 smoke>
D:/IDE/godotEngine/Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/ui_harness/ui_harness_runner.gd   # 全量
D:/IDE/godotEngine/Godot_v4.7.2-stable_win64_console.exe --headless --path . -e --quit                                          # parse
```

| 测试 | 结果 |
|---|---|
| Phase 1–4 smoke 回归（4 个） | 全 **PASS**，exit 0 |
| `test_stage_progression`（新增 8 测试） | **PASS 8/8** |
| `test_stage_flow`（Phase 5） | **PASS 5/5**（零改动回归） |
| `test_town_view`（Phase 5） | **PASS 2/2**（零改动回归） |
| `test_world_map`（Phase 6） | **PASS 7/7**（零改动回归） |
| `test_stage_exit_advance`（endless 出口门） | **PASS 4/4**（零改动回归，证明 endless 推进未被 typed 拦截影响） |
| 全量 ui_harness | **69/70 passed**；唯一失败仍为既有 `test_combat_log_wiring::test_kill_logs_event_end_to_end`（见 §5） |
| `--headless -e --quit`（全项目 parse） | 无 SCRIPT ERROR / Parse Error，exit 0 |

`test_stage_progression` 覆盖要点：

- **typed 战斗清场记完成 + 返回地图**：进入 author forest 01 → 清场 → `completed_stages` 含 `forest_001`、02 解锁、状态文案 `AREA FOREST … STAGE 02 (COMBAT) UNLOCKED`；走出口按 NEXT STAGE → 世界地图出现（不再开 battle 2），节点 01=COMPLETED、02=AVAILABLE。
- **中段清场下一关类型数据驱动**：完成 1–4 后清 author 05 → 文案含 `STAGE 06 (EVENT) UNLOCKED`（EVENT 类型来自 StageDatabase，非硬编码）。
- **地图进 TOWN**：进入即完成（08 completed、09 unlocked）；关闭城镇回**地图**（09 可用、08 COMPLETED）。
- **地图进 EVENT（占位）**：访问即完成并**停留地图**（06 COMPLETED、07 解锁可用）。
- **直接/DEV typed TOWN**：关闭仍回 CombatView（回归守卫 Phase 5 行为）。
- **endless boot**：boot battle 清场不写任何进度、走出口照旧推进 battle 2、不弹地图。
- **FARMING on typed 关**：首次清场记一次完成，重刷清场幂等（`completed_stages` 恒 1 key），关卡号不变。
- **BOSS 收尾**：清 author 10 → `AREA FOREST COMPLETE (10/10)`，出口后回地图、10 节点 COMPLETED、全 10 关完成。

---

## 5. 当前已知问题 / 取舍

1. **全量 ui_harness 仍有 1 个既有失败**：`test_combat_log_wiring::test_kill_logs_event_end_to_end`（Phase 5/6 报告已记载、与 Phase 7 diff 无关）。本轮未触碰 combat log / kill 路径。
2. **EVENT/TOWN「进入即算完成」是占位语义**：真实 EVENT 内容或独立 Town 通关判定落地后需改为玩法返回判定（§3.3），届时完成钩子位置不变、语义一处改。
3. **AUTO/FARMING 会漂移出 typed session**：typed 关内开 AUTO/FARMING 挂机时，引擎推进到其他 battle stage 后按设计停止写 author 进度（`_typed_entry` 清空）。地图式逐关推进是**手动模式**玩法；自动挂机仍是 endless 语义。已文档化，避免"自动悄悄记完成/破坏线性解锁"。
4. **defeat 回退同属漂移**：typed 关战败后引擎回退到前一 battle stage，之后清场按 endless 规则；玩家需从地图重新进入该 author 关来恢复 author 完成语义（与引擎"退一层战斗"模型一致）。
5. **关闭地图回到战斗后 typed 已清空的场景**：typed 清场→回地图→地图 ✕ 关闭→战斗视图（VICTORY）→ 再按 NEXT STAGE 会走 endless `start_next_stage`。这是有意的"退出 author 闭环"逃生口，文档已注明。
6. **无运行时截图/人工验收**：闭环由 headless 套件覆盖；编辑器内 MCP/截图视觉验收未做（非阻塞，同 Phase 5/6）。
7. 代码新建 `.gd` 暂无 `.uid` sidecar（仓库既有先例，headless import 已入 uid cache；编辑器首开自动补齐）。
8. 地图/城镇相关 UI 文案仍以英文为主（与 MainNavigation/StageType display 一致）；如需中文化走 game_locale。

---

## 6. 下一 Phase（Phase 8 — Save / Load）需要知道的信息

- **可复用**：`PlayerProgress` 字段已是纯 identifier 形态（`current_area_id` / `current_stage_number` / `completed_stages: Dictionary`，key 为 StageDatabase 规范 stage id，如 `"forest_006"`）——Phase 8 序列化 **不需要**动数据模型，只需把这三者映射为 JSON/Save 资源再重建 `PlayerProgress` 实例。
- **完成语义现状（供存档/读档对齐）**：typed 战斗清场 / TOWN、EVENT 访问 即写 `completed_stages`；`current_*` 每次 author 进入即更新（endless boot 从不写）。读档后 `current_area_id/current_stage_number` 非空即可用既有 `enter_area_stage` 直接回到该 author 关（路由已支持任意补零 id / stage_number）。
- **Save 位置**：目前 `PlayerProgress` 由 `grid_combat._ready()` `new()` 创建（内存态）；Phase 8 需要决定挂载点（autoload/singleton 或 grid 内注入）与存档时机（建议：typed 完成点与城镇关闭点后 `save`，启动 boot 时 `load` 覆盖默认 progress）。
- **WorldMap 无需改动**：读档后 `open_world_map()` refresh 即按新 progress 渲染 LOCKED/AVAILABLE/COMPLETED/CURRENT。
- **禁止**：不要序列化 `StageDatabase` / `StageData` 本体，只存 identifier；不要因存档重构本 Phase 的任何 host/数据逻辑。
- **回归基线**：Phase 1–7（smoke 4 + `test_stage_flow` + `test_town_view` + `test_world_map` + `test_stage_exit_advance` + `test_stage_progression` 8）全绿；全量 ui_harness 仅剩 `test_combat_log_wiring::test_kill_logs_event_end_to_end` 一个既有失败；全项目 parse 干净。

---

## 7. 下一 Phase 是否可以开始

**可以。** Phase 7 闭环已达成并可运行：战斗型清场自动记完成并按 `StageDatabase` 解锁下一关（含 EVENT 类型数据驱动文案），TOWN/EVENT 访问即完成，手动 typed 流程经出口/城镇关闭返回刷新后的世界地图；endless 默认循环与 boot 推进行为经 `test_stage_exit_advance` 等零改动回归证明未受影响；核心数据/路由层（`StageDatabase/StageData/StageType/PlayerProgress/StageRouter`）再次零改动。`test_stage_progression` 8/8、Phase 1–6 全部回归 + 全项目 parse 全绿。Phase 8 只需在现成 identifier 形态的 `PlayerProgress` 上做序列化/重建，无架构前置依赖。
