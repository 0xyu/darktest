# Area / Stage / StageType 系统 — Phase 6 报告（WorldMap / AreaMap Integration）

> 对应 `docs/coding-plans/area-stage-progression-coding-plan.md`（**Rev 2**）的 **Phase 6 — WorldMap / AreaMap Integration**。
> 前置输入：Phase 5 报告（`area-stage-progression-phase-05-report.md`）。范围：**纯新增 WorldMap 呈现层**（StageDatabase 驱动 + PlayerProgress 状态 + 复用 `enter_area_stage` 进入玩法）；完成/解锁/返回流程留 Phase 7，存档留 Phase 8。

---

## 1. 本 Phase 完成内容

让 WorldMap 不再 hard-code `Stage 01 … Stage 10`，而是从数据动态生成关卡节点：

```text
StageDatabase
  ↓ stage_count + get_stage(n).stage_type
  ↓
WorldMapView（列出的每个 Area 一个 AreaView）
  └── AreaView（header + S 形 Path + StageNode[]）
       每个 StageNode = 一次 get_stage(n)：icon/名称由 stage_type 决定
       状态 LOCKED / AVAILABLE / COMPLETED / CURRENT 读自 PlayerProgress
```

落地六件事：

1. **`AreaView`（新，单 Area path 呈现）**：节点 **1..stage_count 全部由 `StageDatabase` 生成**（Forest 10 节点来自 `stage_count=10`），节点类型图标/配色/名称一律读 `get_stage(n).stage_type`——代码零 `if stage == 6`、零"Stage 01..10"列表。节点点击发 `stage_enter_requested(area, n)`；本类不路由、不启战、不写进度。
2. **`WorldMapView`（新，整屏地图 View）**：静态发现 `resources/stage_databases/*.tres`（`StageDatabase.is_valid()` 过滤、按 area_id 排序）→ 每个 Area 建一个 `AreaView`。头部 + LOCKED/AVAILABLE/COMPLETED/CURRENT 图例 + 滚动区。`close_requested` / `stage_enter_requested` 信号；`set_progress` + `refresh` 公开。**加新 Area = 放一个新 `.tres`，本 View 与核心零改动**。
3. **10K 呈现（分页窗口）**：单 Area `stage_count > NODES_PER_WINDOW(24)` 时按窗口分页（`◀ PREV / NEXT ▶`），**每次只物化一页 Control**；合成 `stage_count=1000` 的数据库走同一条 `AreaView` 路径验证（24 节点/页、末页仍能到 stage 1000）。数据架构未改。
4. **HUD 接入**：`WorldMapView` 成为 ViewContainer 的**第三视图**（与 TownView/CombatView 互斥切换：`show_world_map / show_town / show_combat` 互相隐藏）；CombatView 底部新增 **MAP** 按钮（`world_map_toggle_requested`）。
5. **`grid_combat` map host**：新增 `open_world_map()`（用实时 `_player_progress` refresh 后切换视图）、MAP toggle 处理、`_on_world_map_stage_enter_requested`（**解锁门槛**：未解锁返回状态文案；与 DEV 直达入口的 QA bypass 语义并存——Phase 5 已注明解锁推进属 Phase 7）。`_apply_stage_entry` 进入目的地后**收敛回玩法视图**（COMBAT/EVENT→`show_combat`、TOWN→`show_town`），因此从地图点关后地图自动关闭、战斗/城镇可见。
6. **节点状态与锁定**：`AreaView.compute_state(progress, area, n)`（纯函数）按 **LOCKED（未解锁）> COMPLETED > CURRENT（所在关）> AVAILABLE** 判定；LOCKED 节点 `disabled`（点击不可达）。默认进度下 Forest 01=AVAILABLE、其余 LOCKED。

**未实现**（均留后续 Phase）：不改默认运行循环（endless）；不做完成→解锁→返回地图闭环（Phase 7）；不做存档（Phase 8）；EVENT 玩法/独立 Boss 内容；多 Area 间选择 UI 的进一步打磨（Phase 9 加 Swamp 时验证）。DEV「AREA STAGES」演示区**原样保留**（QA 直达/绕过解锁用）。

---

## 2. 修改 / 新增的文件

### 修改

| 文件 | 说明 |
|---|---|
| `scripts/world/grid_combat.gd` | Phase 6 map host：连接 `world_map_toggle_requested` / `world_map_stage_enter_requested`；`open_world_map()` / `_on_hud_world_map_toggle_requested` / `_on_world_map_stage_enter_requested`（解锁门槛 + 状态文案）；`_apply_stage_entry` 增加目的地视图收敛（`show_combat`/`show_town`，关闭地图）。boot/推进路径未触碰 |
| `scripts/ui/mobile_combat_hud.gd` | 新信号 `world_map_toggle_requested` / `world_map_stage_enter_requested`；`%WorldMapView`/`%MapButton` onready；`show_world_map()` + `show_town/show_combat` 改为三视图互斥；`get_world_map_view()`；close/stage 转发 handlers |
| `scenes/ui/MobileCombatHUD.tscn` | ViewContainer 下新增 `WorldMapView` 实例（初始隐藏、unique name）；CombatView 底部 UtilityRow 新增 **MAP** 按钮（unique name `MapButton`） |
| `docs/coding-plans/area-stage-progression-coding-plan.md` | Phase 6 标记「已完成」+ 实现备注；Execution Order 修正重复行并前移 Chat 08（Phase 7）为当前 |

### 新增

| 文件 | 说明 |
|---|---|
| `scripts/ui/area_view.gd` | `AreaView`（PanelContainer）：StageDatabase 驱动的 S 形 path + StageNode 按钮 + 状态 + 分页窗口 + `compute_state` 纯函数 |
| `scripts/ui/world_map_view.gd` | `WorldMapView`（Control）：区域发现/滚动列表/图例/信号 + `refresh/set_progress/get_stage_node_button` 等 |
| `scenes/ui/WorldMapView.tscn` | 薄场景壳（满屏 Control + 脚本，仿 `TownView.tscn`） |
| `tools/ui_harness/suites/test_world_map.gd` | Phase 6 ui_harness 套件（7 测试，见 §4） |
| `docs/coding-plans/reports/area-stage-progression-phase-06-report.md` | 本报告 |

> 未改：`StageDatabase / StageData / StageType / PlayerProgress / StageRouter`（核心数据/路由层零改动）、TownView/DEV 面板/战斗引擎。`.tscn` 仅 HUD 一处新增两个节点块。

---

## 3. 架构决策

### 3.1 呈现层 = 两个纯 View 类，host 仍在 grid_combat

沿用 Phase 5「非破坏性 host」：`WorldMapView`/`AreaView` **只做呈现与信号**（不 load 战斗、不碰 StageRouter、不写 PlayerProgress）；`grid_combat` 继续当协调者（喂 progress、收 stage 点击、复用 `enter_area_stage`）。未来 Phase 7 若引入地图外壳，只需把 `_player_progress`/视图 owner 上移，路由/分发不变。

### 3.2 WorldMap 的区域列表来自文件系统发现，不写死 forest

`WorldMapView._discover_databases()` 扫 `resources/stage_databases/` 并校验 `is_valid()`。这样 Phase 9 加 Swamp 时**不用改 WorldMap**（放一个 `swamp.tres` 即出现），也符合「新 Area 不触碰核心」。

### 3.3 每个节点状态是 PlayerProgress 的纯函数

`AreaView.compute_state()`：`LOCKED`（未解锁）→ `COMPLETED` → `CURRENT`（current_area/current_stage 匹配）→ `AVAILABLE`。静态数据从不持有 completed/current；节点 `disabled` 表达 LOCKED，host 侧 `_on_world_map_stage_enter_requested` 再兜底拒绝（DEV 面板路径仍可绕过，保持 QA 演示语义）。

### 3.4 10K 呈现 = 分页窗口，不建万级 Control

`NODES_PER_WINDOW = 24`；Forest(10) 单页直出。`stage_count > 24` 时 `AreaView` 分页重建当前窗口节点（`show_window`/pager），只有一页 ~24 个按钮存活；连接线按页内节点重绘。这是**呈现**策略——`StageDatabase` 数据架构与查询路径一字未动。

### 3.5 视图收敛放 `_apply_stage_entry`，让「从地图进关」自动回玩法视图

Phase 5 时进入 COMBAT/EVENT 不切视图（DEV 面板本就是 CombatView 上层覆盖，天然可见战斗）。WorldMap 是整屏第三视图，若不收敛会一直盖住战斗，故在既有分发函数末尾统一 `show_combat()/show_town()`。对 Phase 5 各路径这是 no-op（CombatView 已在显示），因此 `test_stage_flow`/`test_town_view` 零改动全绿。

---

## 4. 测试结果

执行命令（headless，`<project>` = `G:/godotproject/darkrpg`）：

```text
D:/IDE/godotEngine/Godot_v4.7.2-stable_win64_console.exe --headless --import --path .
D:/IDE/godotEngine/Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/<phase 1-4 smoke>
D:/IDE/godotEngine/Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/ui_harness/ui_harness_runner.gd ++ --suite test_world_map
D:/IDE/godotEngine/Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/ui_harness/ui_harness_runner.gd ++ --suite test_stage_flow
D:/IDE/godotEngine/Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/ui_harness/ui_harness_runner.gd ++ --suite test_town_view
D:/IDE/godotEngine/Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/ui_harness/ui_harness_runner.gd            # 全量
D:/IDE/godotEngine/Godot_v4.7.2-stable_win64_console.exe --headless --path . -e --quit                                                  # parse
```

| 测试 | 结果 |
|---|---|
| Phase 1–4 smoke 回归（`area_stage_data`/`stage_database`/`player_progress`/`stage_router`） | 全 **PASS**，exit 0 |
| `test_world_map`（ui_harness，新增 7 测试） | **PASS 7/7** |
| `test_stage_flow`（Phase 5 套件） | **PASS 5/5**（零改动回归） |
| `test_town_view`（Phase 5 套件） | **PASS 2/2**（零改动回归） |
| 全量 ui_harness | **61/62 passed**；唯一失败仍为既有 `test_combat_log_wiring::test_kill_logs_event_end_to_end`（见 §5） |
| `--headless -e --quit`（全项目 parse） | 无 SCRIPT ERROR / Parse Error，exit 0 |

`test_world_map` 覆盖要点：

- MAP 按钮开/关地图（CombatView↔WorldMapView 互斥）；close_requested 返回战斗。
- **节点数 == `StageDatabase.stage_count`（10）**，且每个节点的 `stage_type` == 同关 `get_stage(n).stage_type`（证明 DB 驱动、非硬编码）。
- 默认进度：01=AVAILABLE（可点）、02=LOCKED（disabled）。
- 完成后状态：完成 1–3 → 1..3=COMPLETED、站在 4 → 4=CURRENT（可点）、5=LOCKED。
- 点击 LOCKED 节点不进入（`push_click` 被 disabled 拦下；battle/progress 不变）。
- 完成 1–9 后点击 10（BOSS）→ battle level 10 启动、progress current=10、CombatView 可见、地图自动隐藏。
- 合成 `stage_count=1000` 的 AreaView：分页 42 窗口、每页只物化 24 节点、末页可达 stage 1000（10K 呈现验证）。

---

## 5. 当前已知问题

1. **全量 ui_harness 仍有 1 个既有失败**：`test_combat_log_wiring::test_kill_logs_event_end_to_end`（Phase 5 报告已记载、单独跑也失败，非本 Phase diff 引入；本 Phase 未触及 combat log 路径）。可另开 task 修复。
2. **无运行时截图/人工验收**：地图开合、节点布局由 headless 套件覆盖；编辑器内 MCP/截图视觉验收未做（非阻塞，同 Phase 5）。
3. **世界地图的「当前关」进度只随 `enter_area_stage` 更新**：endless 默认循环不清除时，`PlayerProgress.current` 只有走地图/DEV 进入类型化 Stage 后才移动（Phase 7 flow 会接管）。
4. **地图内无「从战斗/城镇返回地图」闭环**：COMBAT/EVENT 进入后地图关闭回 CombatView；TOWN close 也回 CombatView——「逐关推进后回地图」属 Phase 7。
5. **地图 UI 文案为英文为主**（与 MainNavigation/StageType display 一致）；如需中文化可后续统一走 game_locale。
6. 代码新建 `.gd` 暂无 `.uid` sidecar（headless import 已入 uid cache；仓库 tests/*.gd 亦有先例无 sidecar），首次以编辑器打开会自动补齐，不影响运行。

---

## 6. 下一 Phase（Phase 7 — Stage Completion / Return Flow）需要知道的信息

- **可直接复用**：`grid_combat.open_world_map()`/MAP toggle、`WorldMapView.stage_enter_requested → grid`、`AreaView.compute_state`（含 CURRENT 语义）、`enter_area_stage`。完成一关后推进只需：`PlayerProgress.complete_stage(area, n)` → `refresh()` 地图 → 下一关解锁即 AVAILABLE（默认型节点自动按 `stage_type` 呈现）。
- **边界语义待定**（coding plan Phase 7）：TOWN「进入即算完成？」、战斗胜利→自动记 completed 的接入点（battle `StageManager.stage_completed` vs 走人后回地图）、EVENT/BOSS 的完成判定。
- **宿主前瞻**：若「回到地图」要成为闭环终点，需在 `_apply_stage_entry` 之外补一条「返回地图」路径（`hud.show_world_map()` + refresh 即可，无需动数据层）。
- **禁止**：解锁/完成逻辑必须只依赖 `(area_id, stage_number)` + `StageDatabase.stage_count`；WorldMap 已零 stage 数字硬编码，Phase 7 也别引入。
- **回归基线**：Phase 1–6 smoke（4 个）+ `test_town_view` + `test_stage_flow` + `test_world_map` 全绿；改动请全量复跑 + `-e --quit` parse。全量 ui_harness 应仍仅剩 `test_combat_log_wiring` 一个既有失败。

---

## 7. 下一 Phase 是否可以开始

**可以。** WorldMap 呈现层已落地并可运行：Forest 节点完全由 `StageDatabase` 动态生成（无 stage 数字硬编码），`LOCKED/AVAILABLE/COMPLETED/CURRENT` 状态读自 `PlayerProgress`，节点点击经既有 `enter_area_stage` 进入对应玩法且视图正确收敛；`test_world_map` 7/7、Phase 1–5 回归 + 全项目 parse 全绿；核心数据/路由层（`StageDatabase`/`StageData`/`StageType`/`PlayerProgress`/`StageRouter`）零改动。Phase 7 在既有 map host + progress 语义上做「完成→解锁→返回地图」闭环即可，不依赖新重构。
