# Area / Stage / StageType 系统 — Phase 5 报告（Combat / Town Integration）

> 对应 `docs/coding-plans/area-stage-progression-coding-plan.md`（**Rev 2**）的 **Phase 5 — Integrate Existing Combat / Town**。
> 前置输入：Phase 4 报告（`area-stage-progression-phase-04-report.md`）。范围经用户确认：**非破坏性桥接 + 可运行演示**，默认启动/无限推进不变；「WorldMap → 逐关推进」留 Phase 6/7。

---

## 1. 本 Phase 完成内容

让旧 Combat / Town 通过 Stage system 被调用，且进入的 stage 由 `StageDatabase` 查询而来。落地四件事：

1. **运行场景成为 StageRouter host**（`grid_combat`）：
   - 持有 `StageRouter` + 独立的 map 侧 `PlayerProgress`（runtime 首个持有者）。
   - 新增公开入口 **`enter_area_stage(area_id, stage_number) -> bool`**：经 `StageRouter.request_enter()` 解析（stage_type 驱动，零 stage 数字硬编码），成功即进入对应玩法：
     - `COMBAT`（含 `BOSS`，其 destination 折叠为 Combat）→ `StageManager.initialize_stage(n)`（默认 N ↔ battle level N；Forest 10 走现有 authored/fixed level 10 mini-boss 内容）。
     - `TOWN` → HUD `show_town()`（ViewContainer 内 CombatView ↔ TownView 切换）。
     - `EVENT` → 占位：状态文案提示内容属后续 Phase，**不**启动战斗。
   - 未知 / 越界 / 未 author 的请求干净返回 `false` + 状态文案，不动 `PlayerProgress`。
   - 默认 boot `initialize_stage(1)` 与清场推进 `start_next_stage()` 路径**原样未动**（endless 循环保持）。

2. **Town 接线全部接通**（原先 declared+emitted 但无 receiver 的 stub）：
   - `DevelopmentPanel.town_view_requested` → HUD `show_town()`（隐藏 CombatView、显示 TownView）。
   - `TownView.close_requested` → HUD `show_combat()`（返回战斗视图）。
   - `TownView.warehouse_requested` → `EquipmentInventoryPanel.show_warehouse()`；`skills_requested` → `SkillPanel.show_panel()`。
   - `tools/ui_harness/suites/test_town_view.gd` 因此由 **2 失败 → 2 全过**。

3. **DEV 面板新增「AREA STAGES」演示区**：从 `StageDatabase.load_area(&"forest")` 读取并只列 showcase 节点（stage 1 + 与 default 不同的 06/08/10）→ **FOREST 01·COMBAT / 06·EVENT / 08·TOWN / 10·BOSS**，点击发新信号 `area_stage_enter_requested(area, n)`，经 HUD 转发到 `grid_combat.enter_area_stage()`。即人手可点的可运行演示。

4. **新增 ui_harness 套件 `test_stage_flow`**：headless 验证 Forest 01 进战斗 / 10 进 BOSS 战斗 / 08 切 TownView 并可返回 / 06 Event 占位不启战 / 非法 stage 拒绝。

**未实现**（均留后续 Phase）：不改默认运行循环（endless）；不做 WorldMap（Phase 6）；不做完成/解锁/返回流程（Phase 7）；Event 玩法内容（未来）。`PlayerProgress` 仍只被 `grid_combat` 持有，尚未落盘（Phase 8）。

---

## 2. 修改 / 新增的文件

### 修改

| 文件 | 说明 |
|---|---|
| `scripts/world/grid_combat.gd` | 新增 StageRouter host：`_stage_router`/`_player_progress` 成员与 `_ready()` 连接（`enter_requested → _apply_stage_entry`、`hud.area_stage_enter_requested → _on_hud_area_stage_enter_requested`）；公开 `enter_area_stage()` / `get_stage_progress()`；`_apply_stage_entry()` 按 destination 分发（COMBAT→`_start_battle_for_area_stage`、TOWN→`hud.show_town()`、EVENT→占位文案）；未触碰 boot/推进路径 |
| `scripts/ui/mobile_combat_hud.gd` | `%CombatView`/`%TownView` onready 引用；公开 `show_town()`/`show_combat()`；`_ready()` 接通 `town_view_requested`/TownView `close/warehouse/skills`；新增 `area_stage_enter_requested` 信号并转发 DEV 请求 |
| `scripts/ui/development_panel.gd` | 新增 `area_stage_enter_requested` 信号、`AREA STAGES` section 与 `_build_area_stage_actions()`（数据来自 StageDatabase）、`_enter_area_stage()`；`COLOR_STAGE_TYPE` 类型配色 |
| `docs/coding-plans/area-stage-progression-coding-plan.md` | Phase 5 标记「已完成」+ 实现备注；Execution Order 前移 Chat 07（Phase 6）为当前 |

### 新增

| 文件 | 说明 |
|---|---|
| `tools/ui_harness/suites/test_stage_flow.gd` (+`.uid`) | Phase 5 ui_harness 套件（mount Main，驱动 `enter_area_stage`） |
| `docs/coding-plans/reports/area-stage-progression-phase-05-report.md` | 本报告 |

> 未改 `.tscn`；`test_town_view.gd` 原有期望即 Phase 5 目标（未改）。battle 引擎（`StageManager`/`LevelProvider`…）与 town/hud 面板类本体未改。

---

## 3. 架构决策

### 3.1 用非破坏性「host 进单关」实现 Phase 5，不重写运行循环

仓库现实：单场景、无限连续 battle、无地图外壳；若让 boot/推进直接改走 10 关 Forest，会撞上「Forest 结束后无 11」「Town/Event 完成后语义属 Phase 7」「WorldMap 属 Phase 6」等缺口。故用户确认采用**桥接层**：把「进入某 author 关卡」做成 `grid_combat` 上可随时调用的入口（`enter_area_stage`），按需解析并启动对应旧系统；默认运行（Stage 1 起 + 清场 +1）一字未动 → 现游戏零回归地保持可运行。

### 3.2 StageRouter host 放在运行场景，不建 autoload / 第二场景栈

按 Phase 4 报告 §6 建议与仓库「最外层场景持有并注入」倾向：router + progress 由 `grid_combat`（已是 HUD/StageManager 的协调者）持有。未来 Phase 6/7 若要引入地图外壳/更全局的 owner，只把 `_player_progress` 的所有权上移即可，路由/分发逻辑不变。

### 3.3 目的地分发只读 `StageData.stage_type`（经 route），禁止 stage 数字硬编码

`_apply_stage_entry` 用 `match route.destination`（`Destination.COMBAT/TOWN/EVENT/NONE`），Forest 06=EVENT、08=TOWN、10=BOSS 的语义全部来自 `StageDatabase`，代码零 `if stage == 6/8/10`。DEV 演示区按钮也是**读 StageDatabase**（`stage_type != default`）动态生成，不写死类型表。

### 3.4 Town = 同场景 View 切换，不建 scene transition

TOWN 复用既有 `ViewContainer` 里 `CombatView ↔ TownView`（Phase 0 audit §4.3 推荐）。TownView 各 facility 仍只是发信号，面板打开/归属由 HUD 决定（保持 TownView 为 dumb list）。

### 3.5 battle 映射默认 N ↔ level N，author 覆盖留接口

`_start_battle_for_area_stage(stage_id, n)` 默认 `initialize_stage(n)`（Forest 01..10 ↔ battle 1..10；level 10 走现有固定 LevelConfig → boss/mini-boss）。将来某 Stage 要非线性/authored 战斗，只在此函数读 `StageData.combat_data`（typed LevelConfig），路由表与调用方都不动。

### 3.6 PlayerProgress 首个 runtime 持有者，语义保持不变

`get_stage_progress()` 暴露 map 进度；进入成功才更新 `current_area_id/current_stage_number`。本类仍不含存档、不含解锁推进（Phase 7/8）。与 battle 侧 `PlayerProgression`（角色数值成长）继续隔离。

---

## 4. 测试结果

执行命令（headless，`<project>` = `G:/godotproject/darkrpg`）：

```text
D:/IDE/godotEngine/Godot_v4.7.2-stable_win64_console.exe --headless --import --path .
D:/IDE/godotEngine/Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/<phase 1-4 smoke>   # 回归
D:/IDE/godotEngine/Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/ui_harness/ui_harness_runner.gd ++ --suite test_town_view
D:/IDE/godotEngine/Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/ui_harness/ui_harness_runner.gd ++ --suite test_stage_flow
D:/IDE/godotEngine/Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/ui_harness/ui_harness_runner.gd            # 全量
D:/IDE/godotEngine/Godot_v4.7.2-stable_win64_console.exe --headless --path . -e --quit                                                  # parse
```

| 测试 | 结果 |
|---|---|
| Phase 1–4 smoke 回归（`area_stage_data`/`stage_database`/`player_progress`/`stage_router`） | 全 **PASS**，exit 0 |
| `test_town_view`（ui_harness，Phase 5 前 2 失败） | **PASS 2/2**（dev entry 切换 + 仓库/技能导师开对应面板） |
| `test_stage_flow`（ui_harness，新增） | **PASS 5/5** |
| 全量 ui_harness | **54/55 passed**；唯一失败为**既有** `test_combat_log_wiring::test_kill_logs_event_end_to_end`（见 §5） |
| `--headless -e --quit`（全项目 parse） | 无 SCRIPT ERROR / Parse Error，exit 0 |

`test_stage_flow` 覆盖要点：

- `enter_area_stage(&"forest", 1)` → true；battle level 1 启动；CombatView 可见；`PlayerProgress.current = forest/01`。
- `enter_area_stage(&"forest", 10)`（BOSS）→ true；battle level 10 启动并实际 spawn；current = forest/10；CombatView 可见。
- `enter_area_stage(&"forest", 8)`（TOWN）→ true；TownView 可见 & CombatView 隐藏；current = forest/08；`close_requested` 后回到 CombatView。
- `enter_area_stage(&"forest", 6)`（EVENT）→ true；current = forest/06；**不**启动 battle（battle stage 不变）；CombatView 可见。
- `forest 0 / 11 / swamp 1` → 均 false，且 progress 不变。

---

## 5. 当前已知问题

1. **全量 ui_harness 仍有 1 个既有失败**：`test_combat_log_wiring::test_kill_logs_event_end_to_end`（单独跑也失败；本 Phase diff 未触及 combat log / kill / exp 路径，判定为 Phase 5 前已存在的独立问题，未归因到本 Phase）。可另开 task 修复。
2. **`PlayerProgress` 仍无持久 owner/落盘**：由 `grid_combat` 场景持有，重进场景即重建、无存档（Phase 8）。DEV 演示/测试以外，尚无流程去推进它（Phase 7）。
3. **`enter_area_stage` 不做解锁门槛**：可强制进入任何已 author 的关（含未解锁的 06/08/10）——按设计（解锁属 Phase 7 flow）；DEV 面板因此才能任意演示。
4. **TOWN 进入是「查看」，非状态切换**：进入 town 时背后 battle 状态仍在（演示/桥接语义）；Town 是否计入 completed / 何时回地图属 Phase 7。
5. **EVENT / BOSS 内容仍为占位或默认**：Forest 06 EVENT 仅文案；Forest 10 BOSS 走 battle 既有 mini-boss/固定 level 内容，无 author 专属事件/剧情（后续 Phase）。`StageData` 的 `combat_data/event_data` 泛型入口仍未接 typed 资源。
6. **DEV「AREA STAGES」目前硬编码 area=&"forest"**（演示用）；未来多 Area 后可改为遍历可用 area（Phase 9 再做）。
7. **`test_combat_log_wiring` 之外无运行时截图验证**：Town/战斗切换由 headless ui_harness 覆盖；未做编辑器内人工 MCP/截图验收（非阻塞）。

---

## 6. 下一 Phase（Phase 6 — WorldMap / AreaMap Integration）需要知道的信息

- **可直接复用的入口**：`grid_combat.enter_area_stage(area_id, stage_number) -> bool`（或接 `StageRouter.request_enter/enter_requested`），COMBAT/BOSS→战斗、TOWN→TownView、EVENT→占位，已可用且被 ui_harness 覆盖。WorldMap 的 StageNode 点击 = 调这个入口。
- **读数据**：`StageDatabase.load_area(area_id)/stage_count/get_stage(n)`；`StageType.get_display_name(stage_type)`（图标/名称）；`PlayerProgress.is_stage_unlocked/is_stage_completed/get_current_stage`（`LOCKED/AVAILABLE/COMPLETED/CURRENT` 状态）。运行时对象从 `grid_combat.get_stage_progress()` 取得。
- **禁止**：WorldMap 里 `if stage == 6 → event icon`；一律读 `stage_data.stage_type`。
- **呈现**：先支持小 Area（10~100 node）；10K node 分页/懒加载列为已知扩展（Coding Plan Phase 6）。
- **宿主决策前瞻**：若 Phase 6/7 需要「WorldMap View + grid_combat」外壳，把 `PlayerProgress` owner 从 grid_combat 上移到外壳/注入处，路由分发不变。
- **回归基线**：Phase 1–5 smoke（4 个）+ `test_town_view` + `test_stage_flow` 全绿；改动请全量复跑 + `-e --quit` parse。全量 ui_harness 应仍仅剩 `test_combat_log_wiring` 一个既有失败。

---

## 7. 下一 Phase 是否可以开始

**可以。** Combat/Town 已能通过 StageRouter 从 `grid_combat` 正常进入且 stage 由 `StageDatabase` 查询而来（Forest 01 战斗 / 06 Event 占位 / 08 Town 视图 / 10 Boss 战斗全部 headless 验证通过）；Town stub 接线完成（`test_town_view` 2/2 转绿）；Phase 1–4 回归 + 全项目 parse 全绿；默认运行零改动仍可运行。Phase 6 为纯新增 WorldMap 呈现层，主要依赖已就绪的 `StageDatabase`/`PlayerProgress`/`enter_area_stage`，不依赖现有系统重构。
