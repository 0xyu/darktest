# Area / Stage / StageType 系统 — Phase 7.5 报告（Authored Stage 模型修订 + StageFlow 抽取）

> 对应 `docs/coding-plans/area-stage-progression-coding-plan.md` 的 **Phase 7.5**（本报告新增的 Phase）。
> 前置输入：Phase 7 报告（`area-stage-progression-phase-07-report.md`）。
> 触发原因：Phase 7 交付后复核发现两处问题——(1) **auto 与 manual 的 next-stage 是两条独立路径**，同一次清场在两种模式下行为不同；(2) Phase 5–7 的流程策略全部以 private method 形式堆在 `grid_combat` 里，`grid_combat` 已开始越过 Combat Host 的边界。本 Phase 同时修订**语义**与**结构**。
> 范围：**不**做存档（Phase 8）、**不**加新 Area（Phase 9）、**不**实现剧情 story（按用户决定）。

---

## 1. 本 Phase 修正的语义（用户裁决）

| # | 修正项 | 原 Phase 7 行为 | 现在 |
|---|---|---|---|
| 1 | **auto next stage = manual next stage** | 手动走 `grid_combat._advance_after_clear()`（含 typed 拦截 → 回 WorldMap）；AUTO 在 `auto_combat_controller.gd:346` **直接**调 `stage_manager.start_next_stage()`，完全绕过 host | 只有**一条 seam**：AUTO 改成发 `stage_advance_requested`，由 host 用与手动完全相同的方式处理 |
| 2 | **stage result 不依赖 AUTO 开关** | `_can_advance_to_next_stage()` 里有 `not is_auto_enabled()`；并有"漂移即清空 typed session → 不写进度"规则 | 完成记录/文案/AUTO 全部解耦；FARMING 仅保留"清场原地重刷"（这是模式，不是 result） |
| 3 | **authored stage = 普通战斗关 + 内容层** | authored stage = **替换玩法**（EVENT 不进战斗、进入即算完成） | 战斗照打；内容叠加（boss 敌人 / 宝箱 / 交互 object）；未被 author 的 stage 一律按普通 endless 关处理 |
| 4 | **继续 endless，WorldMap 不是强制 hub** | 手动 typed 清场后被强制弹回 WorldMap | 清场后统一继续 battle N+1；WorldMap 降为随时可开的状态视图/捷径 |
| 5 | **EVENT 并入内容层** | `StageType.EVENT` 是独立玩法类型 | `StageType` 只留 `COMBAT / TOWN / BOSS`；"这一关不是真战斗"这种事由**内容层**表达，不再切割玩法词汇 |

### 1.1 关键：Phase 7 的"漂移规则"是打错层级的补丁

Phase 7 报告 §3.2 / §5.3 / §5.4 用"引擎漂移出 typed stage 即结束 session"来**绕开**第二条路径，而没有去修第二条路径本身。本 Phase 判定该补丁作废，改为统一路径：

```text
修正前（两条路径，互不知情）
  手动  grid_combat._advance_after_clear() ──┬─→ typed 拦截 → open_world_map()
                                            └─→ stage_manager.start_next_stage()
  AUTO  auto_combat._start_next_stage_from_exit() ──→ stage_manager.start_next_stage()   ← 绕过 host

修正后（一条 seam）
  手动 NEXT STAGE / primary_action ─┐
                                    ├─→ grid_combat._advance_after_clear() ─→ stage_manager.start_next_stage()
  AUTO  stage_advance_requested ────┘                    ↓
                                            auto_combat.notify_advance_result(ok)
```

因此 `_typed_entry`（typed session 字典）**整体删除**：不再需要区分"从地图进入"与"endless 推进"。完成判定改为纯数据查询：

```text
清掉 battle stage N
  → 取 PlayerProgress.current_area_id（未进入过任何 Area 时为 ""，即 endless boot）
  → StageDatabase.lookup(area, N)
  → 命中：complete_stage(area, N) + 读下一关类型文案
  → 未命中：什么都不做（普通 endless 关）
```

这条规则让"从地图进入"、"从上一关走过来"、"挂机推进到"三种到达方式**行为完全一致**——正是"不要区分"的要求。

---

## 2. StageFlow 抽取（对 God Object 反馈的回应）

### 2.1 事实核对：GPT 反馈中哪些成立

复核后确认 Phase 5–7 新增的确实是一整块**连续区域**（旧版 213–455 行 ≈ 240 行 + `_advance_after_clear` 拦截 + `_on_stage_completed` 分支 ≈ 270 行），且其中相当部分是**流程策略**而非 Combat Host 职责。但反馈有 3 处偏差需要记录，以免修错方向：

- **`unlock` 不在 `grid_combat`**：解锁规则在 `PlayerProgress.is_stage_unlocked()`；`grid_combat` 只是调用它做一次呈现层门槛。
- **`stage routing` 不在 `grid_combat`**：类型→destination 表在 `StageRouter._destination_for_stage_type()`。
- **`WorldMap` 是 Phase 6 明确指定的 host 角色**，不是职责泄漏。
- 另：`StageFlow` / `StageResult` 在本仓库（含计划 Rev 2）**此前零命中**——Phase 7 并未违背自己的 spec，它留下的是**计划未编码的分层债**。本 Phase 的修法是"补上这一层"，而非判定 Phase 7 未完成。

### 2.2 抽取结果

新增 `scripts/systems/stage_flow.gd`（`RefCounted`，190 行），独占以下**规则**：

| StageFlow 负责 | 原位置 |
|---|---|
| 进入记账（current_area_id / current_stage_number） | `grid_combat._apply_stage_entry` |
| visit 型关卡（TOWN）进入即完成 | `grid_combat._record_typed_visit_completion` |
| 战斗清场完成判定 + 完成记录 | `grid_combat._record_typed_battle_completion` |
| 下一关文案（经 router 读 stage_type） | `grid_combat._authored_next_text` |
| 线性解锁门槛 | `grid_combat._on_world_map_stage_enter_requested` 内联 |
| 城镇关闭去向 | `grid_combat._on_town_close_requested` 内联 + `_typed_entry` |
| typed session 状态 | `grid_combat._typed_entry` / `_entry_from_world_map` → **删除** |

`grid_combat` 只保留 **host 机制**：切视图（`hud.show_combat/show_town/show_world_map`）、启战斗（`stage_manager.initialize_stage`）、转发引擎与 HUD 信号，以及**唯一**的 advance seam。已删除的规则型方法：`_record_typed_battle_completion` / `_record_typed_visit_completion` / `_authored_next_text` / `_return_to_world_map_from_typed_clear`。

行数变化（total / 非空）：

```text
grid_combat.gd                863 / 724  →  787 / 653   （净 −76 行；移出 ≈190 行规则，加入 ≈40 行 host 接线 + 内容钩子）
stage_flow.gd                   新增       190 / 164
stage_content_controller.gd     新增       279 / 235
stage_content.gd                新增       103 /  87
authored_content_state.gd       新增        70 /  56
stage_content_object.gd         新增        68 /  55
```

> 说明：`grid_combat` 行数只降了 76 行，因为它**仍然是**本场景的 host（14 个子系统 + ~60 个 `_on_*` handler 是本仓库既有的场景根范式）。真正的变化是：**场景里不再有任何一条流程规则**。评估这一点应看"规则型方法是否归零"，而不是看行数。

---

## 3. Authored Stage 模型（数据 + 运行时）

### 3.1 模型定义

```text
普通 stage（未被 author）
  → 完全就是 endless 的一关，没有任何额外内容

authored stage（被 author 的某一关）
  → 仍然是一关普通战斗（玩法不变）
  → 额外叠加「内容层」条目
```

内容层**不是** `StageType`：加内容永远不会改变这一关进入哪种玩法（`StageRouter` 的路由表不受影响）。

### 3.2 两种生命周期

| 生命周期 | `one_shot` | 行为 | 用户用例 |
|---|---|---|---|
| 一次性 | `true` | 消费后永久消失，该关**变回普通关** | 宝箱（获取后消失） |
| 可重复 | `false` | 每次该关开始都重建（每次访问最多结算一次，防刷） | boss 敌人（击败后仍会出现）、healing pool |

### 3.3 触发方式

**走到格子上自动触发**（用户选定）。关键点：内容 object **不占用网格 occupancy**，所以目标格仍然可行走，玩家（或 AUTO 寻路）可以真的走上去；触发钩子是 `PlayerController.moved`——手动移动与 AUTO 移动走**同一个信号**，因此自动化同样无法改变内容结果。

内容格子只放在：可行走、无敌人占用、且**离出发点曼哈顿距离 > 3**、且不在起终点通道上——因此"进入关卡"本身永远不会触发内容。

### 3.4 "指定出现的 boss 敌人"复用既有管线（零新代码）

战斗侧**已经**有一条 authored 敌人管线：`resources/levels/level_<n>.tres`（`LevelConfig.boss`），由 `LevelProvider` 按 battle level 取出；`level_010.tres` 已挂 `AshenOracle`。因为 authored stage 号与 battle level 是 1:1 的（Forest 06 ↔ battle level 6），**"给某一关指定 boss"这件事现有机制已经能做**：加一个 `resources/levels/level_006.tres` 即可，且天然可重复出现（每次 `initialize_stage(6)` 都重新生成）。

因此本 Phase **没有**在内容层重复实现一套 boss 指定——那会复制一个已经能工作的系统。详见 `stage_content.gd` 类文档。

### 3.5 已消费状态：独立状态类

新增 `AuthoredContentState`（`Resource`，用户选定"新建独立状态类"），与 `PlayerProgress` **彻底分离**：

```text
PlayerProgress         "哪些 stage 已通关"        completed_stages = { "forest_006": true }
AuthoredContentState   "哪些内容已被用掉"        consumed = { "forest_006:cache": true }
```

两者不可混同：通关不等于宝箱已开，宝箱已开也不代表该关未完成。key 同样**只存 identifier**（`<stage_id>:<content_id>`），Phase 8 可直接序列化。

---

## 4. EVENT 退役的连带改动

`StageType` 由 `COMBAT/EVENT/TOWN/BOSS` 变为 `COMBAT/TOWN/BOSS`（`BOSS` 由 3 → 2），`StageRouter.Destination.EVENT` 删除。连带更新：

- `resources/stage_databases/forest.tres`：06 不再是 EVENT（改为默认 COMBAT + 内容层，`display_name` = "Forest Hollow"），08 TOWN `2→1`，10 BOSS `3→2`。
- `scripts/ui/area_view.gd`（type 配色/字母表）、`scripts/ui/development_panel.gd`（DEV 按钮配色）移除 EVENT 条目。
- `grid_combat.gd` 的 `Destination.EVENT` 分支删除。

**必须记录**：这一决定使 5 个测试文件中断言旧模型的条目**必须**改写（它们断言的正是被废止的语义）。哪些改了、改成了什么，见 §5.2。除此之外的测试断言全部保持原样。

---

## 5. 测试

### 5.1 执行命令

```text
<godot> --headless --import --path .
<godot> --headless --path . -s res://tests/<smoke>.gd
<godot> --headless --path . --script res://tools/ui_harness/ui_harness_runner.gd ++ --suite <name>
<godot> --headless --path . --script res://tools/ui_harness/ui_harness_runner.gd      # 全量
<godot> --headless --path . -e --quit                                               # parse
```

### 5.2 结果

| 测试 | 结果 |
|---|---|
| 5 个 smoke（Phase 1/2/3/4 + 新增 content） | 全 **PASS** |
| `test_stage_progression`（9 测试，原 8 + 新增 1） | **PASS 9/9** |
| `test_stage_content`（新增 5 测试） | **PASS 5/5** |
| `test_stage_flow` | **PASS 5/5** |
| `test_town_view` | **PASS 2/2** |
| `test_world_map` | **PASS 7/7** |
| `test_stage_exit_advance` | **PASS 4/4** |
| 全量 ui_harness | **76 tests, 75 passed, 1 failed**；唯一失败仍为既有 `test_combat_log_wiring::test_kill_logs_event_end_to_end`（Phase 5/6/7 已记载，与本 Phase diff 无关） |
| `-e --quit` 全项目 parse | 无 SCRIPT ERROR / Parse Error / WARNING，exit 0 |

### 5.3 新增的关键回归守卫

- **`test_auto_and_manual_advance_share_one_seam`**（test_stage_progression，8 断言）：手动清场后按 NEXT STAGE → battle N+1 且不弹地图；同一场景下由 **AUTO 走位**触发 `stage_advance_requested` → 得到**相同**的下一关、相同的完成记录、相同的"地图是否打开"结论。**这个测试在修正前必然失败**（旧行为下手动会回地图、AUTO 会直接推进）。
- **`test_stage_content`**（5 测试）：authored 关仍打普通战斗 + 生成 2 条内容；未 author 的关与 endless boot **零内容**；走上宝箱 → 给金 + 记 consumed + object 移除；重进同关 → 一次性宝箱不复活、可重复 spring 复活；治疗池每次访问最多结算一次（防刷）。
- **`stage_content_smoke_test`**：内容**不改变路由**（forest 06 带内容仍是 COMBAT）、未 author 关卡零内容、内容校验（空 id / 非法 kind / 无效治疗池 / 重复 content id）、consumed 状态的 key 形态与跨关独立性。

### 5.4 因模型变更而改写的既有断言（逐项）

| 文件 | 旧断言 | 新断言 |
|---|---|---|
| `tests/area_stage_data_smoke_test.gd` | `BOSS == 3`、EVENT 合法性、forest_06=EVENT | `BOSS == 2`、TOWN 合法性、forest_06=COMBAT |
| `tests/stage_database_smoke_test.gd` | stage 6 / `forest_006` / `forest_6` 为 EVENT | 均为 COMBAT |
| `tests/stage_router_smoke_test.gd` | 06 → `Destination.EVENT`、EVENT 名称/合法性 | 06 → `Destination.COMBAT`、TOWN 名称/合法性 |
| `tools/ui_harness/suites/test_stage_flow.gd` | EVENT 占位不启战 | 06 启 battle stage 6（正常战斗） |
| `tools/ui_harness/suites/test_stage_progression.gd` | 清场后**回地图**（2 个测试）、EVENT 访问停留地图、下一关文案 `STAGE 06 (EVENT)` | 清场后**继续 endless**、地图入口进战斗关、下一关文案 `STAGE 08 (TOWN)` |

> 除上表外，`test_stage_flow` / `test_town_view` / `test_world_map` / `test_stage_exit_advance` 的既有断言均**未改动**即转绿。

---

## 6. 修改 / 新增的文件

### 新增

| 文件 | 说明 |
|---|---|
| `scripts/systems/stage_flow.gd` | **StageFlow**：进入记账、完成判定、下一关文案、解锁门槛、城镇去向 |
| `scripts/data/stage_content.gd` | `StageContent`：内容条目（CHEST / HEALING_POOL）+ `one_shot` 生命周期 |
| `scripts/progress/authored_content_state.gd` | `AuthoredContentState`：已消费内容（独立于 PlayerProgress） |
| `scripts/world/stage_content_object.gd` | 内容 object 的呈现（自己 `_draw()`，不占 occupancy） |
| `scripts/world/stage_content_controller.gd` | 内容层运行时：生成位置、走位触发、结算、消费 |
| `tests/stage_content_smoke_test.gd` | 内容数据 + consumed 状态 smoke |
| `tools/ui_harness/suites/test_stage_content.gd` | 内容层运行时套件（5 测试） |
| `docs/coding-plans/reports/area-stage-progression-phase-07-5-report.md` | 本报告 |

### 修改

| 文件 | 说明 |
|---|---|
| `scripts/world/grid_combat.gd` | 删除 `_typed_entry`/`_entry_from_world_map` 与 4 个规则方法；改为 `_flow` + 单一 advance seam + 内容层接线 |
| `scripts/systems/auto_combat_controller.gd` | 新增 `stage_advance_requested` / `notify_advance_result()`；`_start_next_stage_from_exit()` 不再直接推进 stage |
| `scripts/data/stage_type.gd` | 移除 `EVENT`；补文档说明"内容不是 StageType" |
| `scripts/systems/stage_router.gd` | 移除 `Destination.EVENT` |
| `scripts/data/stage_data.gd` | 新增 `content: Array[StageContent]` + 内容校验 |
| `scripts/data/stage_database.gd` | 注释更新（EVENT 移除） |
| `scripts/player/player_controller.gd` | 新增 `heal(amount) -> int`（内容层治疗专用 seam，与消耗品/装备特效区分） |
| `scripts/ui/area_view.gd`、`scripts/ui/development_panel.gd` | 移除 EVENT 配色/字母条目 |
| `resources/stage_databases/forest.tres` | 06 改为 COMBAT + Hidden Cache（一次性）+ Forest Spring（可重复）；08/10 类型重编号 |
| `docs/coding-plans/area-stage-progression-coding-plan.md` | 新增 Phase 7.5、Rev 2.1 变更说明、执行顺序更新 |
| 5 个既有测试文件 | 见 §5.4 |

**未改**：`StageDatabase` 查询逻辑、`PlayerProgress`、`WorldMapView`、`AreaView` 结构、战斗引擎（`StageManager` / battle `StageState` / `AutoCombatController` 的战斗决策 / `TurnManager` / `CombatSystem`）、`LevelProvider` / `LevelConfig`、任何 `.tscn`。

---

## 7. 已知问题 / 取舍

1. **全量 ui_harness 仍有 1 个既有失败**：`test_combat_log_wiring::test_kill_logs_event_end_to_end`（Phase 5/6/7 已记载，与本 Phase diff 无关）。
2. **story（剧情）本轮未做**（用户决定）。内容层的 seam 已就位：新增一个 `Kind.STORY` + 一次性消费即可接入，不需要动 StageFlow 或网格逻辑。
3. **boss 指定沿用既有 `LevelConfig` 管线**（§3.4），**没有**在内容层另建一套。若希望"在内容资源里直接写 boss 敌人"而不是"新增 `level_<n>.tres`"，那是另一种设计工作流，需要先确认是否要偏离现有 designer 流程。
4. **多 Area 时内容层按 `current_area_id` 判定**：玩家从地图进入 Forest 后，被 endless 推进到 stage 11+ 时该关未 author → 零内容。这是符合预期的（"未指定即普通关"）。但若将来希望"跨 Area 的 endless 推进"，需要重新定义 `current_area_id` 何时清空——本 Phase 保持现状。
5. **内容格子是随机候选 + 固定 stride 分布**：不是策划手摆坐标。当前内容类型（宝箱/治疗池）对位置不敏感；若将来需要"精确放在某格"，应给 `StageContent` 加一个可选 `cell: Vector2i` 覆盖，而不是改分布算法。
6. **AUTO 走位触发的端到端测试**用 `action_delay_seconds = 0` 驱动，以避免 headless 下依赖真实 delta 时长（原代码用 0.05s 定时器）。这改的是测试内的参数，不是生产默认值。
7. **新增 `.gd` 暂无 `.uid` sidecar**（仓库既有先例；headless import 已入 uid cache，编辑器首开自动补齐）。
8. **无运行时截图 / 人工验收**：内容 object 的 `_draw()` 呈现（宝箱/水池图形）未经视觉确认，仅经逻辑测试。建议编辑器内跑一次 Forest 06 目视确认。

---

## 8. 下一 Phase（Phase 8 — Save / Load）需要知道的信息

- **两个待序列化对象，都是纯 identifier**：
  - `PlayerProgress`：`current_area_id` / `current_stage_number` / `completed_stages: Dictionary`
  - `AuthoredContentState`：`consumed: Dictionary`（key 形如 `"forest_006:cache"`）
- **挂载点**：`PlayerProgress` 现在由 `StageFlow._init()` 创建（`grid_combat._ready()` 里 `StageFlowScript.new()`）。`StageFlow._init(progress)` **已支持注入**，所以 Phase 8 只需在 boot 时构造/读档后把 `PlayerProgress` 传给 StageFlow，不需要动 StageFlow 内部。
- `AuthoredContentState` 同理：`StageContentController.configure(..., state)` 已支持注入；不注入时自建空状态。**建议 Phase 8 让 StageFlow 或一个新的 SessionState 同时持有这两者**，避免存档挂载点分裂成两处。
- **存档时机建议**：`StageFlow.on_battle_cleared()` 命中（有 authored stage 被完成）之后、以及 `StageContentController.resolve_at()` 消费一次性内容之后。
- **读档后回到位置**：`enter_area_stage(area, n)` 即可；路由支持任意补零 id / stage_number。`WorldMap` 无需改动，`open_world_map()` refresh 即按新 progress 渲染。
- **禁止**：不要序列化 `StageDatabase` / `StageData` / `StageContent` 本体，只存 identifier；不要因存档回退本 Phase 的统一 seam 或把流程规则搬回 `grid_combat`。
- **回归基线**：全量 ui_harness **76 tests / 75 passed**，唯一失败为既有 `test_combat_log_wiring::test_kill_logs_event_end_to_end`；5 个 smoke + parse 干净。

---

## 9. 下一 Phase 是否可以开始

**可以。** 本 Phase 完成后：

- auto 与 manual 的 next-stage 走**同一条 seam**，并有专门回归测试钉住（该测试在修正前必然失败）；
- stage 的完成结果与 AUTO/FARMING **完全解耦**（FARMING 仅保留"原地重刷"这一模式语义）；
- 流程**规则**已从 `grid_combat` 全部移出（场景内规则型方法归零），`grid_combat` 回到 Combat Host；
- authored stage 模型改为"普通战斗关 + 内容层"，宝箱/治疗池已有可运行实现与测试，未 author 的关严格按 endless 普通关处理；boss 指定沿用既有 `LevelConfig` 管线；
- EVENT 已并入内容层退役，连带测试按 §5.4 逐项改写并全绿。

Phase 8 只需在两个现成的 identifier 形态状态对象上做序列化/注入，无架构前置依赖。
