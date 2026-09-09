# Area / Stage / StageType 系统 — Phase 4 报告（StageRouter）

> 对应 `docs/coding-plans/area-stage-progression-coding-plan.md`（**Rev 2**）的 **Phase 4 — StageRouter（进入哪种玩法）**。
> 前置输入：Phase 3 报告（`area-stage-progression-phase-03-report.md`）。

---

## 1. 本 Phase 完成内容

按 Phase 3 报告 §6 划定的范围实现 **纯路由壳**（routing shell），不做任何玩法内容接线：

- 新增全局类 **`StageRouter`**（`class_name StageRouter extends RefCounted`，`scripts/systems/stage_router.gd`）——把「进入某 Stage」的请求 `(area_id, stage_number)` 解析成玩家应到达的玩法目的地。
- 数据来源严格走 **`StageDatabase.lookup(area_id, stage_number)`** → 读 **`StageData.stage_type`** 分发，**全程零 `if stage == 6` 这类 stage_number 硬编码**。
- 提供三组 API：
  - `route(area_id, stage_number) -> Dictionary` — 一次查询产出完整 route 记录（`ok / stage / stage_id / stage_type / destination / destination_name / display_name / reason`）；未知 / 越界 / 未 author 的 Area 返回干净的失败记录。
  - `destination_for_stage(stage: StageData) -> int` — 对已持有的 StageData 直接解析目的地。
  - `request_enter(area_id, stage_number) -> bool` + signal **`enter_requested(route)`** — 玩家/宿主触发「进入该关」的入口请求；不可路由时不 emit 并返回 `false`。
- **走通 Forest 01/06/08/10**：headless 测试断言 `forest 01→Destination.COMBAT / 06→EVENT / 08→TOWN / 10→COMBAT（作者类型仍为 BOSS）`。
- 引入独立于 `StageType` 的 **Destination 词汇**，落定 BOSS 路由决策：当前仓库**无独立 BossScene**（boss / mini-boss 是 battle 层特性），故 BOSS 作者类型路由进 `Destination.COMBAT`，而 route 记录保留 `stage_type == BOSS` 供 Phase 5 挂 authored boss 战斗数据。
- **未实现**（均留后续 Phase）：不进真实战斗 / 不显示 TownView / 无 Event 玩法内容（Phase 5）；不做解锁门槛 / current 推进（Phase 7）。运行中的游戏行为**零改动**，保持可运行。

---

## 2. 修改 / 新增的文件

| 文件 | 类型 | 说明 |
|---|---|---|
| `scripts/systems/stage_router.gd` (+`.uid`) | 新增 | `StageRouter`：Stage → 目的地分发器（纯路由壳，RefCounted，可 headless 直测） |
| `tests/stage_router_smoke_test.gd` (+`.uid`) | 新增 | Phase 4 最小 smoke test（SceneTree headless，沿用 Phase 1–3 风格） |
| `docs/coding-plans/area-stage-progression-coding-plan.md` | 修改 | Phase 4 标记「已完成」+ 实现备注；Execution Order 前移 Chat 06（Phase 5）为当前 |
| `docs/coding-plans/reports/area-stage-progression-phase-04-report.md` | 新增 | 本报告 |

> **无现有玩法文件被修改**：`grid_combat.gd`、battle `StageManager`、`MobileCombatHUD`、Town 等原样未动（工作区在实现前后均仅含本 Phase 新增文件，无遗留脏改动）。

---

## 3. 架构决策

### 3.1 Destination 词汇独立于 StageType（BOSS → Combat 落定）

`StageType`（作者视角：这个节点*是什么*）与 `Destination`（玩家视角：进入*哪种玩法*）分离。当前映射集中在单一中央表 `_destination_for_stage_type()`：

```text
COMBAT → Destination.COMBAT
EVENT  → Destination.EVENT
TOWN   → Destination.TOWN
BOSS   → Destination.COMBAT   ← 当前仓库无独立 BossScene，boss 属 battle 层特性
其它/非法 → Destination.NONE
```

- route 记录**同时携带** `stage_type`（保留 BOSS 身份）与 `destination`（入口玩法），Phase 5 可用 `stage_type == BOSS` 加载 boss 专属数据、用 `destination` 决定把玩家放进哪个视图。
- 未来新增作者类型（ELITE / SHRINE / SECRET）或确有独立 Boss/Shrine 场景时，**只改这张表 / 扩展 `Destination` 枚举**，`StageData / StageDatabase` 等 Data 类与路由调用方都不动——满足 Rev 2「扩展只动枚举/数据资源，不碰核心」。

### 3.2 纯路由壳，内容一律不进本类

`request_enter` 只「决定并发出请求」（emit `enter_requested`），**不**启动战斗、不切 View、不实例化任何玩法——这些是 Phase 5 host 的职责。这样 Phase 4 不被 Phase 5 内容拖累，也满足 CLAUDE.md「只实现本 Phase / 不提前建系统」。

### 3.3 不读进度、不做解锁门槛

路由只判断「是否存在作者化的 Stage」（读 `StageDatabase`），**不**读 `PlayerProgress`、不判 `is_stage_unlocked`。解锁/回退门槛属于 Phase 7 完成流程，由 flow 调用方在 `request_enter` 前施加。保持路由与玩家状态彻底解耦（呼应「静态数据 ≠ 玩家进度」）。

### 3.4 失败路径与既有风格一致

未知 / 越界 / 未 author 的请求返回 **`ok == false` + 人类可读 `reason`**（对齐 Phase 2「未知查询=null」与 `PlayerProgress.complete_stage()` 返回 `false` 的干净失败风格）；`request_enter` 对失败请求**不 emit**、返回 `false`。

### 3.5 形态与落点

- `extends RefCounted`（非 Node）：目前没有任何宿主场景/外壳持有它，做成无场景依赖的协调器，Phase 5 host / 测试都可就地持有；`RefCounted` 是 `Object` 子类，定义 signal 无问题。
- 命名遵守 Rev 2 约束：分发器叫 **`StageRouter`**，**未**抢占 battle 引擎的 `StageManager / StageDefinition`。落点 `scripts/systems/`（作为 dispatcher/system），与 battle `StageManager` 文件并列但语义、代码、状态全隔离。
- `route()` 返回 Dictionary（携带 `stage_id / stage_type / destination / display_name / reason`），沿用 `PlayerProgress.get_current_stage()` 的 dict 风格，不为 record 另建 class。

---

## 4. 测试结果

执行命令（headless，工作目录 `<project>` = `G:/godotproject/darkrpg`）：

```text
D:/IDE/godotEngine/Godot_v4.7.2-stable_win64_console.exe --headless --import --path .          # 注册 StageRouter 全局类 + 生成 .uid
D:/IDE/godotEngine/Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/stage_router_smoke_test.gd
D:/IDE/godotEngine/Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/area_stage_data_smoke_test.gd   # Phase 1 回归
D:/IDE/godotEngine/Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/stage_database_smoke_test.gd    # Phase 2 回归
D:/IDE/godotEngine/Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/player_progress_smoke_test.gd   # Phase 3 回归
D:/IDE/godotEngine/Godot_v4.7.2-stable_win64_console.exe --headless --path . -e --quit         # 全项目 parse 校验
```

| 测试 | 结果 |
|---|---|
| `stage_router_smoke_test.gd`（Phase 4，新增） | **PASS**，`StageRouter smoke test passed.`，exit 0 |
| `area_stage_data_smoke_test.gd`（Phase 1 回归） | **PASS**，exit 0 |
| `stage_database_smoke_test.gd`（Phase 2 回归） | **PASS**，exit 0 |
| `player_progress_smoke_test.gd`（Phase 3 回归） | **PASS**，exit 0 |
| `-e --quit`（全项目 parse） | 无 SCRIPT ERROR / Parse Error，exit 0 |

覆盖要点：

- **Forest 走通**：1–10 全部 `route ok`，目的地映射 **01–05,07,09→COMBAT / 06→EVENT / 08→TOWN**；每关 route 携带 canonical id（`forest_006`）。
- **BOSS 特殊断言**：`forest 10 → destination COMBAT` 但 `stage_type 仍为 BOSS`（作者类型不被路由折叠吞掉）。
- **destination 词汇**：`get_destination_name(COMBAT/EVENT/TOWN) == "Combat/Event/Town"`；`NONE == "Unknown"`；`is_valid_destination(999) == false`。
- **未知干净失败**：`forest 0 / 11 / -3`、未 author 的 `swamp 1` → `ok=false`、`destination=NONE`、`reason` 非空。
- **request_enter**：`forest 6 / 8` 成功并 emit 两次（`forest_006→EVENT`、`forest_008→TOWN`）；`forest 0 / swamp 1` 返回 `false` 且**不 emit**。
- **防路由猜测**：`stage_type = 999`（非法）→ `destination_for_stage` 返回 `NONE`，不会猜成某个玩法。

---

## 5. 当前已知问题

1. **StageRouter 尚无运行期调用方**：运行中的游戏仍从 Stage 1 直接开战（连续 battle stage），没有地图/外壳流程去触发 `request_enter`——本 Phase 刻意如此（纯新增壳），预期内；待 Phase 5（host 接线）与 Phase 6/7（地图 + 完成流程）接入。
2. **`request_enter` 不做解锁门槛**：未接 `PlayerProgress.is_stage_unlocked`，因为解锁/推进属 Phase 7 flow 语义；若接入方需锁，须自行在调用前判断（已在代码注释与 §3.3 说明）。
3. **BOSS→Combat 是当前决策而非最终定案**：基于「仓库无独立 BossScene」。若 Phase 5 评估后需要独立 Boss 场景/独立事件，只需扩展 `Destination` 枚举 + 改 `_destination_for_stage_type()` 中央表，Data 类与调用方不受影响。
4. **只有 headless 单元/smoke 覆盖**：本 Phase 无 UI / 场景集成测试（Town/Event 视图与真实战斗启动属 Phase 5 内容，届时再上 ui_harness / 运行时验证）。
5. **`StageData` 数据入口仍为泛型占位**：Forest EVENT/TOWN/BOSS 仍只有类型与显示名，无 `event_data / combat_data` 等——Phase 2 已知问题 #5 的延续，接战斗内容时（Phase 5）再挂 typed 资源。

---

## 6. 下一 Phase（Phase 5 — Combat / Town Integration）需要知道的信息

- **复用**：
  - `StageRouter.route(area, n)` / `destination_for_stage(stage)` 决定目的地；`request_enter(area, n)` + signal `enter_requested(route)` 是 Phase 5 host 的接入点（connect 后拿到含 `stage / destination / stage_type` 的 route record）。
  - 区分 boss：route 记录里的 `stage_type == BOSS`（不要只看 `destination`，它是 COMBAT）。
  - Stage 来源继续走 `StageDatabase.lookup`；不要退回 `if stage == 6` 硬编码。
- **Combat 桥接建议**（coding plan Phase 5）：host 收到 `destination == COMBAT` 时，把 `StageData` 映射到 battle level（默认 Forest N ↔ battle level N），走现管线 `LevelProvider.get_stage_definition(level)` → battle `StageManager`；BOSS 再按 `stage_type` 挂 authored `LevelConfig`/boss 数据（可写入 `StageData.combat_data / boss_data` typed 资源，字段 Phase 2 已预留）。
- **Town**：`destination == TOWN` → 显示 `TownView`，复用 `MobileCombatHUD` 内 `ViewContainer` 的同场景 View 切换先例（`CombatView ↔ TownView`），并接上此前**未接线**的 `town_view_requested` / `warehouse_requested` / `skills_requested` 信号（可参考 `tools/ui_harness/suites/test_town_view.gd` 的期望行为）。
- **Event**：目前仅占位路由（`Destination.EVENT`）；Phase 5 若仍不做内容，保持仅 log/占位即可，勿提前实现 Event 玩法。
- **形态提示**：`StageRouter` 是 `RefCounted`，Phase 5 需要决定 host 放哪（最外层外壳场景 or `grid_combat` 内协调者），但遵守 Phase 0 审计 §4.3 建议——**同场景 View 切换，不新建第二套 scene transition**。
- **回归基线**：Phase 1–4 的 smoke test（`area_stage_data` / `stage_database` / `player_progress` / `stage_router`）全部为 SceneTree headless 直跑，改动后请全部复跑 + `-e --quit` parse 校验。
- **保持现游戏可运行**：Phase 5 接 Town/Combat 时不要改动 `grid_combat` 核心循环的既有行为，优先以「新增 host 监听 `enter_requested`」的方式叠接。

---

## 7. 下一 Phase 是否可以开始

**可以。** `StageRouter` 路由壳完成且通过 headless 测试（Forest 01→COMBAT / 06→EVENT / 08→TOWN / 10→BOSS，含 BOSS 折叠为 Combat 但类型保留、未知请求干净失败）；Phase 1–3 回归 + 全项目 parse 全绿；运行中游戏零改动仍可运行。Phase 5 为纯新增 host 接线（把 route 目的地接到现有 Combat/Town），不依赖现有系统重构，风险低。
