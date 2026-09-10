# Global Stage Range / Area 模型（Rev 3）— Coding Plan

> 文档版本：**Rev 3**，插入执行序 **Phase 7.6**（在本文件内标注为 `Phase 7.6`）。
> 前置输入：`area-stage-progression-coding-plan.md`（Rev 2.1）、`reports/area-stage-progression-phase-07-5-report.md`。
> **本文件状态：已实施。** 落地报告：`reports/area-stage-progression-phase-07-6-report.md`。
> **执行时机：必须在 Phase 8（Save / Load）之前。** 理由见 §9。

---

# 0. 一句话

**Stage 是一个全局递增计数器；Area 是这个计数器上的一段区间。** 删除「endless vs authored」二分、删除 area 局部编号、删除第二份 current stage。

```text
Stage 1–10   → Area forest   （Forest）
Stage 11–20  → Area forest2  （Forest 2）
Stage 21–50  → Area dungeon  （Dungeon）
Stage 51+    → 无 Area（纯 endless 推进，地图不显示）
```

---

# 1. 触发原因：三个实测缺陷

## 1.1 缺陷 A：仓库里有两份 current stage，只有一份会被推进

| 存储 | 谁读 | 谁写 |
|---|---|---|
| `StageManager.stage_state.stage_number` | `StageControl._on_stage_started()`（`stage_control.gd:54`） | `StageManager.initialize_stage()` |
| `PlayerProgress.current_stage_number` | `AreaView.compute_state()` 的 `CURRENT`（`area_view.gd:160-166`）、副标题 `at stage N`（`area_view.gd:251-253`） | **只有** `StageFlow._apply_entry()`（`stage_flow.gd:184`）＝ 进入某一关时 |

advance 路径（`_advance_after_clear()` → `stage_manager.start_next_stage()`）**没有任何一处写 progress**。

实测（headless probe，跑完已删）：

```text
从地图进入 forest 01     battle=1  progress=forest/1
手动清场 + NEXT STAGE   battle=2  progress=forest/1     ← 位置漂了
  StageControl 槽位: 1 *2 3 4 5 6
  地图: 01=DONE 02=READY 03=LOCKED
```

> 附带澄清：**这不是 auto/manual 的问题**。auto 与手动共用 `grid_combat._advance_after_clear()`（`grid_combat.gd:178 / 207`），两者结果完全一致 —— 包括一样地漏写位置。

## 1.2 缺陷 B：「endless vs authored」二分导致地图永久冻结

`StageFlow.on_battle_cleared()` 的 early return（`stage_flow.gd:138-140`）：

```gdscript
var area_id: StringName = _progress.current_area_id
if area_id.is_empty():
    return ""          # ← 开机 endless 里清场，什么都不记
```

而 `current_area_id` 只有「在地图上点某一关 / DEV 面板」才被写上。实测：

```text
先进入过 area（area='forest'）
  进入 forest 01   battle=1  completed=0
  AUTO 推进 ×3     battle=4  completed=3  [forest_001..003]
  地图             01=DONE 02=DONE 03=DONE 04=READY      ← 「跟着推进」

从未进过 area（area=''）
  boot             battle=1  completed=0
  AUTO 推进 ×3     battle=4  completed=0
  手动 NEXT ×2     battle=6  completed=0
  地图             01=READY 02=LOCKED 03=LOCKED 04=LOCKED  ← 永久冻结
```

即：**决定行为的是「有没有进过 area」，不是 auto 还是手动。** 关掉 Auto 改手动同样冻结。

## 1.3 缺陷 C：阵亡回退也不写位置

玩家阵亡时 `grid_combat.gd:739` 走 `stage_manager.start_previous_stage()`（battle 号**往回退**）。实测 AUTO 打 forest 03 阵亡时 battle 从 3 退到 2，而 progress 仍是 `forest/3` —— 地图会指着一个已经被打回去的关。

## 1.4 文档层面已经过期的一句

`area-stage-progression-coding-plan.md:391` 写着「现仓库不再有两套「current stage」并存」。它当年只删了死字段 `PlayerProgression.current_stage`，**漏算了地图在用的 `PlayerProgress.current_stage_number`** —— 后者是活的第二份，且正在漂。

---

# 2. 用户裁决的模型（本 Rev 的定义）

1. **Stage 只有一个号**：全局递增计数器，永不重置、永不为某个 Area 重新从 1 开始。
2. **Area 是区间的名字**，不是"另一个号空间"。区间互不重叠；一个 stage 最多属于一个 Area。
3. **位置 = 计数器；当前 Area 由位置推导。** 任何地方都不再存第二份位置。
4. **没有「endless 关」与「authored 关」之分**：所有 stage 都是普通 stage；"这一关是 Town" 由该 stage 的 authored 数据（`stage_type`）表达，其余照旧程序化生成敌人。
5. **跨区间自动切换**：清掉 10 推进到 11 时，Area 自动从 forest 变成 forest2（用户已裁决）。
6. **解锁链全局一条**：通关 10 解锁 11，即使跨 Area（用户已裁决）。
7. **推翻** Phase 7.5 的「endless boot loop must never write progress」：开机那一关就在 Area forest 里，清掉就记。

---

# 3. 依据：`docs/game-design.md` 本来就是这样写的

`game-design.md` §5「Stage System」（第 358–372 行）逐字写着：

```text
The game is divided into sequential stages.
Stage 1
Stage 2
...
Stage 10
Stage 11
...
```

并且 §6（第 458 行）写「**Every 10th stage** contains a guaranteed Mini Boss」—— 都是以**单一全局 stage 号**为前提。

**结论：当前的 Area 实现（每个 Area 各从 1 编号）与 `game-design.md` 冲突。** 按 AGENTS.md，`game-design.md` 是 gameplay 规则的 source of truth，因此本 Rev 是**让实现回归已文档化的设计**，而不是新发明一套。顺带：区间取 1–10 / 11–20 / 21–50 时，"每 10 关一个 Mini Boss" 与区间边界天然对齐。

---

# 4. 与现状的差距对照

| 你的模型 | 现状 | 证据 | 本 Rev 是否要改 |
|---|---|---|---|
| Stage 全局递增 | ✅ 已经是 | `StageManager.stage_state.stage_number`（+1 / −1） | 不改（保留） |
| 未 author 的关＝普通关 | ✅ 已经是（Phase 7.5） | `StageDatabase.get_stage()` 惰性生成（`stage_database.gd:85-103`）；`LevelProvider` 对任意 level 都能生成 | 不改 |
| 指定某一关为 Town | ✅ 已经是 | `forest.tres` 的 `special_stages`：08 = TOWN | 不改 |
| 内容层（宝箱／治疗池） | ✅ 已经是 | `StageData.content` + `StageContentController` | 不改 |
| **Area = stage 区间** | ❌ 完全没有 | `StageDatabase` 只有 `area_id / display_name / stage_count / default_stage_type / special_stages`，**无 first/last/offset** | **要改** |
| **进入 N 关就是进入第 N 关** | ❌ 用的是 area 局部号 | `_start_battle_for_area_stage()` → `initialize_stage(maxi(stage_number, 1))`（`grid_combat.gd:361-365`）→ Area 2 的第 1 关会启动 battle **1** | **要改** |
| **位置只有一份** | ❌ 有两份 | §1.1 | **要改** |
| **清场即记账（含开机）** | ❌ 需先手动进入 area | §1.2 | **要改** |
| **解锁链全局一条** | ❌ 每 area 一条 | `is_stage_unlocked(area, n)` 要求同 area 内 n−1 通关（`player_progress.gd:58-63`） | **要改** |
| 地图显示全局号 | ❌ 显示 1..stage_count | `AreaView.get_window_start()` = `window*24+1`（`area_view.gd:129-130`） | **要改** |

**不需要动**：`StageManager` / `LevelProvider` / `LevelConfig` / `LevelTemplate` / TurnManager / CombatSystem / AutoCombatController / `StageContentObject` / HUD 视图切换 / 任何 `.tscn`。

---

# 5. 数据模型变更

## 5.1 `StageDatabase`：增加区间

```gdscript
class_name StageDatabase
extends Resource

@export var area_id: StringName = &""
@export var display_name: String = ""
@export var first_stage: int = 1                      # 新增：区间起点（全局号）
@export_range(1, 999999, 1) var stage_count: int = 1  # 保留：区间长度
@export var default_stage_type: int = StageTypeScript.COMBAT
@export var special_stages: Array[StageData] = []     # stage_number = 全局号

func get_last_stage() -> int:                          # 新增
	return first_stage + stage_count - 1

func covers(stage_number: int) -> bool:                # 新增
	return stage_number >= first_stage and stage_number <= get_last_stage()

func get_stage(stage_number: int) -> StageData         # 语义变更：参数为全局号；不在区间 → null

static func database_for_stage(stage_number: int) -> StageDatabase   # 新增：区间查找（带缓存）
static func area_for_stage(stage_number: int) -> StringName          # 新增：推导 area_id
```

- 保留 `stage_count`（长度）而不是改成 `first/last` 两个字段：现有 `stage_count` 引用（`AreaView` 分页、`_area_has_stage`、文案）语义不变，改动面最小。
- `special_stages[].stage_number` 改按**全局号**书写；校验从 `[1, stage_count]` 改为 `[first_stage, last_stage]`。
- `database_for_stage()` 需要**缓存**已发现的数据库（现在的 `load_area()` 走 ResourceLoader 缓存，但新的区间查找要扫目录；加一个 static 区间表缓存，避免每次查询扫盘）。
- 新校验：区间不重叠（同一 stage 只能属于一个 Area）；`first_stage >= 1`；`stage_count >= 1`。

**`forest.tres` 只需加一行 `first_stage = 1`** —— 内容、id、测试全部不变。

## 5.2 Stage id 方案

保持现格式：`<area_id>_<补零全局号>`，补零宽度 `max(3, last_stage 的位数)`。

```text
forest   1–10   → forest_001 … forest_010      （与现状完全相同，零改动）
forest2  11–20  → forest2_011 … forest2_020
dungeon  21–50  → dungeon_021 … dungeon_050
```

理由：改动最小；id 直接可读成全局关号；`AreaView`／存档里 Area 身份仍然可见；`AuthoredContentState` 的 `<stage_id>:<content_id>` 形态不变。

> 备选（不推荐，列出以便裁决）：id 只用全局号 `stage_006`。好处是将来重新划分区间不会让旧存档 id 失效；代价是现有 8 个测试文件里的 `forest_006` 全部要改，且 id 里看不到 Area。

## 5.3 `PlayerProgress`：删掉第二份位置

```gdscript
class_name PlayerProgress

@export var current_stage_number: int = 1        # 唯一权威位置 == battle 关号（旧字段，语义收窄）
@export var highest_stage_reached: int = 1       # 新增：单调不减，解锁依据
@export var completed_stages: Dictionary = {}    # 保留：{ "forest_006": true }（仅 authored stage）

# 删除：current_area_id —— 改为推导，避免又出现第二份
func get_current_area_id() -> StringName:        # 推导：StageDatabase.area_for_stage(current_stage_number)
func get_current_stage() -> Dictionary           # { stage_number, area_id(推导), area_name(推导) }

func is_stage_unlocked(stage_number: int) -> bool   # n == 1 or n <= highest_stage_reached
func is_stage_completed(stage_number: int) -> bool  # 查 completed_stages（无 area 覆盖 → false）
func complete_stage(stage_number: int) -> bool      # 仅当某 area covers(n) 时记录
func mark_reached(stage_number: int) -> void        # highest_stage_reached = max(old, n)
```

**为什么解锁需要 `highest_stage_reached`（重要）**：如果解锁只靠 `completed_stages`，那么 Area 结束后（51+ 无 authored 数据）没有任何 stage 会被记录 → `is_stage_unlocked` 永远无法越过最后一个 Area 的边界 → 死锁。而"我曾经走到过第 N 关"本身就是最强的解锁证明：**位置是对手，不是已完成集合。** 这个字段同时修掉缺陷 B（开机清场就 `mark_reached`）。

**为什么 `completed_stages` 还必须单独存在**（不能由 `highest_stage_reached` 推导）：当前位置的那一关**还没清掉**。若用 `n < highest` 推导 DONE，则 Town（进入即完成）会漏记并使解锁链断在 Town；若用 `n <= highest` 推导，则你正站着的那一关会被标成 DONE。所以 DONE 必须是被清场的显式记录。

**三个字段回答三个不同问题，各只有一个写入点**：

| 字段 | 回答 | 唯一写入者 |
|---|---|---|
| `current_stage_number` | 我现在在哪一关（可回退） | `StageFlow.on_battle_started()` |
| `highest_stage_reached` | 我最远到过哪一关（单调） | 同上（取 max） |
| `completed_stages` | 哪些 authored 关已被清掉（DONE） | `StageFlow.on_battle_cleared()` |

## 5.4 `StageData` / `AuthoredContentState`

- `StageData.stage_number` 语义明确为**全局号**；其余字段不变。
- `AuthoredContentState` 不变（key 仍为 `<stage_id>:<content_id>`）。

---

# 6. 流程变更

## 6.1 位置的唯一写入点：`stage_started`

`StageManager.initialize_stage()` 成功时 emit `stage_started`（`stage_manager.gd:127`），而**全部 5 条改关号的入口**都经过它：

| 入口 | 位置 |
|---|---|
| 开机 | `grid_combat.gd:124` `initialize_stage(1)` |
| 进入某一关（地图 / DEV） | `grid_combat.gd:365` |
| 推进（auto + 手动共用 seam） | `grid_combat.gd:201` |
| 阵亡回退 | `grid_combat.gd:739` `start_previous_stage()` |
| FARMING 原地重刷 | `auto_combat_controller.gd:266` |

因此**只在一处接线**即可覆盖全部路径（含缺陷 C 的回退）：

```gdscript
# grid_combat：与 StageControl 现在读的是同一个事件
stage_manager.stage_started.connect(_on_stage_started)   # 已有
# → StageFlow.on_battle_started(stage_state.stage_number)
#      _progress.current_stage_number = n
#      _progress.mark_reached(n)
#      → 地图 HERE / 副标题 / StageControl 从此永远同号
```

## 6.2 `StageFlow` API 变化

```text
request_enter(stage_number)                  # 去掉 area_id 参数；area 由区间推导
is_stage_unlocked(stage_number)              # 去掉 area_id；全局链
on_battle_started(stage_number)              # 新增：唯一位置写入点
on_battle_cleared(stage_number)              # 去掉 area 空值 early return
next_stage_text(stage_number)                # 按 n+1 全局查找
get_current_area_id()                        # 改为推导
```

`on_battle_cleared(n)` 新逻辑：

```text
取 n → 若某 area covers(n)：complete_stage(n) + 报告下一关文案
      → 若 n 已不属任何 area：什么都不记（无 authored 数据可记），位置照旧前进
      → 无论哪种：位置与 highest_reached 已在 on_battle_started 记过
```

文案：

```text
下一关被某 area 覆盖       → "STAGE 12 (COMBAT) UNLOCKED"
n 是某 area 的末关、且下一关是另一个 area 的首关
                          → "AREA FOREST COMPLETE (10/10) — NEXT: FOREST 2"   （见 §11(d)）
n 之后没有任何 area        → 沿用现有 endless 文案（"REACH THE EXIT / PRESS NEXT TO CONTINUE"）
```

## 6.3 `StageRouter`

`route(area_id, stage_number)` → `route(stage_number)`（area 由区间推导）。`Destination` 表与"内容不改路由"规则全部不变。

## 6.4 城镇（TOWN）

- 进入即完成（现状不变）。
- 关闭城镇：来自地图 → 回地图（现状不变）；其余 → 回战斗视图。
- 关闭后计数器停在该 TOWN 关；玩家用 exit / NEXT STAGE 推进到 n+1（见 §11(b)）。

## 6.5 自动化

`AutoCombatController` **不改**。Phase 7.5 的单一 seam 保留；本 Rev 只是让这条 seam 的结果也被记账。

---

# 7. 呈现层变更

| 位置 | 改动 |
|---|---|
| `AreaView.setup(database, progress)` | 节点号从 `1..stage_count` 改为 `first_stage .. first_stage+stage_count-1` |
| `AreaView.get_window_start()` | `first_stage + window_index * NODES_PER_WINDOW` |
| `AreaView.compute_state()` | 入参改为全局号；`CURRENT` 判定改用 `progress.current_stage_number`（不再比较 `current_area_id`） |
| `AreaView` 副标题 | `"FOREST (1–10) · at stage 3"` |
| `AreaView._rebuild_path()` / `_find_override` 查询 | 一律传全局号 |
| `WorldMapView` | 节点点击 → `stage_enter_requested(stage_number)`（去掉 area 参数）；打开时若当前位置在某 area 内，自动跳到含该关的窗口 |
| 无 Area 区间（51+） | 地图不显示当前位置；建议在 `WorldMapView` 底部加一行 `"ENDLESS — stage 57 (no area authored)"`（见 §11(c)） |

---

# 8. 迁移步骤（每步结束时项目仍可运行）

> 诚实说明：§8 的 **Group A 必须整体落地**（`PlayerProgress` / `StageRouter` / `StageFlow` / `grid_combat` 的签名互相联动，拆开会出现中间态编译错误）；B/C/D 可独立跟进。

| 组 | 内容 | 门禁 |
|---|---|---|
| **A（模型 + 流程）** | `StageDatabase` 区间 + 区间查找缓存；`forest.tres` 加 `first_stage = 1`；`StageRouter.route(n)`；`StageFlow`（`request_enter` / `on_battle_started` / `on_battle_cleared` / 全局解锁 / 文案）；`PlayerProgress` 新 API + 删 `current_area_id`；`grid_combat` 接线 `stage_started` + 入口改全局号 | 4 个 smoke 转绿；`-e --quit` parse 干净；ui suite 除"断言待改写"外无新增运行错误 |
| **B（地图 UI）** | `AreaView` / `WorldMapView` 全局号 + 分页偏移 + 副标题 + HERE + 自动跳窗口 | `test_world_map` 的窗口/分页断言改写后转绿 |
| **C（测试改写 + 跨区间验证）** | §10 清单逐项改写；新增 `test_stage_range` 套件（用合成 `StageDatabase` 造 Area 2 = 11–20，不真建 `.tres`） | 全量 ui_harness 绿（除既有 `test_combat_log_wiring` 1 项历史失败） |
| **D（文档）** | 老 plan 升 Rev 3 + 作废标记；新 Phase 报告 | 文档与代码一致 |

---

# 9. 为什么必须在 Phase 8 之前

Phase 8（Save / Load）计划序列化的正是本 Rev 要改的东西（`current_area_id` / `current_stage_number` / `forest_006` 形态 id）。先做 Phase 8 = 写两遍存档代码 + 两套迁移。建议执行序调整为：

```text
Chat 09  Phase 7.6  Global Stage Range 模型（Rev 3，本文件）   ← 先做
Chat 10  Phase 8    Save / Load                                ← 序列化新模型
Chat 11  Phase 9    更多 Area（用区间表达，验证扩展性）
Chat 12  Phase 10   Final Refactor
```

---

# 10. 测试改动清单（逐文件，已核对现有断言）

## 10.1 需要改写

| 文件 | 现有断言（行号为实测） | 改成 |
|---|---|---|
| `tests/player_progress_smoke_test.gd` | 全文用 `is_stage_unlocked(&"forest", n)` 等 area 形式（39–111）；`:43`「stage 11 should never unlock」；`:68`「complete_stage 拒绝 forest 11」；`:97-105` `current_area_id` + `get_current_stage().area_id`；`:110-111` swamp 未 author | 全部改全局号；`:43` 改为「fresh progress: 11 未解锁（10 未完成）」；`:68` 改为「11 不被任何 area 覆盖 → complete_stage 返回 false」；`:97-105` 改为断言 area **推导**结果；新增「跨区间解锁：完成 10 → 11 unlocked」 |
| `tests/stage_database_smoke_test.gd` | `:109-111` `get_stage(0)/get_stage(11)/get_stage(-3)` 为 null；`:117` `lookup("forest", 999)`；`:131-143` 合成 10,000 关 | 语义不变（forest 仍 1–10），**但新增**：`first_stage` 区间用例、"区间外 → null"、两个区间重叠 → 校验报错 |
| `tests/stage_router_smoke_test.gd` | `:60/77/108-112` `router.route(&"forest", n)`；`:95/99` `StageDatabase.lookup(&"forest", 6/10)` | 签名改 `route(n)`；`lookup(n)` 换新 API；`:109`「forest 11 路由失败」改为「11 不被任何 area 覆盖 → 失败（当前数据下）」 |
| `tests/stage_content_smoke_test.gd` | `:44/72/84` `lookup(&"forest", 6)` | 换新 API；consumed key 形态**不变** |
| `tests/area_stage_data_smoke_test.gd` | 只测枚举/类型 | 预期**不改**（实施时复核） |
| `tools/ui_harness/suites/test_stage_flow.gd` | `:66/78/97/117/128-130` `enter_area_stage(&"forest", n)`；`:127/132` `current_area_id` | 改 `enter_area_stage(n)`；删 `current_area_id` 断言，改为「被拒绝的进入不改变 `current_stage_number`」 |
| `tools/ui_harness/suites/test_stage_progression.gd` | `:113` `_enter_typed_stage(area, n)`；`:134-135/150/178/189-199/212-213/229-230/268/309/321` area 形式 API；`:282` boot `get_current_stage().stage_number == 1`；**`:278-291` `test_endless_boot_clear_writes_no_progress_and_still_advances`** | API 改全局号；**`:278-291` 语义反转**并改名为 `test_boot_clear_records_area_1_progress_and_advances`（boot 清场现在要记 `completed(1)` 且位置到 2）；`:329/336` 「第 11 关超出 authored path 不写进度」改为「位置=11、`completed` 仍为 10、地图无 HERE」 |
| `tools/ui_harness/suites/test_world_map.gd` | `:151/199` `complete_stage(&"forest", n)`；`:153-154` 直接 `set("current_area_id")` + `current_stage_number`；`:190` 「locked click 不移动 progress」；`:239-250` 窗口分页 `get_stage_node(1/24/25/1000)` | 删 `current_area_id` 写入（改设 `current_stage_number`）；`:190` 改为断言 `current_stage_number` 不变；分页断言按 `first_stage` 偏移改写（area 1 下数值不变，但**新增**一条 area 2 偏移用例） |
| `tools/ui_harness/suites/test_stage_content.gd` | `:84/105/113/133/144/156` `enter_area_stage(&"forest", n)` | 改全局号 |
| `tools/ui_harness/suites/test_stage_exit_advance.gd` | 无 area 断言 | 预期**不改**；需复核 boot 现在会写 progress 是否与断言冲突（应无） |

## 10.2 新增

`tools/ui_harness/suites/test_stage_range.gd`：

```text
T1 boot 即处于 Area 1 内：起手 current_stage_number == 1 且 area 推导 == forest
T2 跨区间自动切 area：清掉 10 → 推进到 11，位置 11、area 推导 == forest2、地图 HERE 落在 area 2 的 11
T3 全局解锁链：完成 10 → is_stage_unlocked(11) 为真（跨 area）
T4 位置三路一致：auto 推进 / 手动推进 / 阵亡回退 三种情况下
    StageControl 显示的关号 == progress.current_stage_number == 地图 HERE 的关号
T5 区间外（51+）：位置继续前进、completed 不增长、地图不显示 HERE、无脚本错误
T6 区间重叠 → StageDatabase.get_validation_errors() 非空
```

`tests/player_progress_smoke_test.gd` 新增「`current_area_id` 不再存在」的守卫（防止第二份位置回归）。

---

# 11. 待你裁决（5 项，含我的建议）

> **实施时全部按「我的建议」落地**（(a) 是、(b) 是、(c) 地图不显示 HERE + 底部 `ENDLESS — stage N (no area authored)`、(d) 有下一个 area 时加 `— NEXT: <AREA>`、(e) `completed_stages` 继续用 canonical id）。

| # | 问题 | 我的建议 |
|---|---|---|
| **(a)** | 地图上点击任意已解锁关 = 把全局计数器设成那个号？ | **是**（今天也是这个语义，只是跟着改成全局号） |
| **(b)** | TOWN 关闭后计数器停在该关，玩家用 exit / NEXT 推进到 n+1？ | **是**（与"清场后继续 endless"一致；不新增特殊规则） |
| **(c)** | 51+ 无 area 时地图怎么表现？ | 地图不显示 HERE，底部加一行 `ENDLESS — stage 57`；并**不做**伪 Area |
| **(d)** | 某 Area 末关清掉时的文案？ | `AREA FOREST COMPLETE (10/10) — NEXT: FOREST 2`（有下一个 area）／`AREA FOREST COMPLETE (10/10)` + endless 文案（没有） |
| **(e)** | `completed_stages` 用 id 还是全局号？ | 用 id（§5.2），保住现有 8 个测试文件与 Phase 8 的 identifier 形态 |

---

# 12. 风险与取舍

1. **净删特例，但有一次性迁移成本**：`current_area_id` 的移除会让 `test_stage_flow` / `test_world_map` / `player_progress_smoke_test` 的若干断言必须改写（§10）。这是"单一真相"的必然代价，且这些断言钉的正是要作废的语义。
2. **id 与区间的耦合**：重新划分区间（把 dungeon 从 21 起改成 25 起）会让该 Area 的 id 变化 → 旧存档的 `completed_stages` 里保留旧 id。当前项目**尚无存档**，此代价为零；Phase 8 之后若再改区间，需要一次迁移。备选方案（id 只用全局号）已在 §5.2 列出。
3. **`highest_stage_reached` 是新增字段**，必须在 Phase 8 一起序列化（否则读档后地图解锁状态丢失）。
4. **`database_for_stage()` 的目录扫描**：必须缓存（§5.1），否则每次查询扫盘。
5. **不做的事**：不改战斗引擎、不改 `LevelProvider` 生成规则、不新增玩法类型、不做剧情、不做存档（Phase 8）、不为 51+ 造伪 Area。

---

# 13. 门禁 / DoD

完成后必须能：

```text
开机（不动任何 UI）→ 位置 1、area 推导 == forest、地图 01 = HERE
AUTO 挂机清场并推进 3 关 → 位置 4、地图 01~03 = DONE、04 = HERE
  且 StageControl 显示 4 == 地图 HERE == progress.current_stage_number   ← 三处同号
关掉 AUTO 改手动 → 结果完全相同
阵亡回退 → 位置跟着回退（且 highest_stage_reached 不回退）
清掉 10 → 推进到 11 → area 自动变 forest2、地图 HERE 落在 area 2 的 11
未进过任何 area 的场景不再存在：开机就在 Area 1 内
```

且**不出现**：

```text
current_area_id 作为存储字段（只允许推导）
area 局部 stage 编号（1..stage_count 作为"位置"语义）
两处以上写 current_stage_number
"endless boot never writes progress"（已推翻）
```

回归基线：4 个 smoke + 全量 ui_harness（除既有 `test_combat_log_wiring::test_kill_logs_event_end_to_end` 1 项历史失败）+ `-e --quit` parse 干净。

---

# 14. review 时最需要你确认的三件事

1. §11 的 5 项裁决（尤其 (c) 51+ 的表现）。
2. §5.3 的三字段划分（`current_stage_number` / `highest_stage_reached` / `completed_stages`）是否接受 —— 这是本 Rev 唯一"新增字段"的地方。
3. §9 的执行序调整（本 Rev 插在 Phase 8 之前）。

---

# 15. 实施记录（Phase 7.6，与本文档的 4 处有意偏差）

落地报告：`reports/area-stage-progression-phase-07-6-report.md`。以下 4 处按"文档意图 > 文档字面"处理，均已在代码注释中说明理由：

1. **`is_stage_unlocked(n)` 不只是 `n <= highest_stage_reached`，而是「n==1 或 n<=highest 或 n-1 已完成」。**
   §5.3 的代码草稿只写了 reach 一条，但那会让"清掉 5 → 地图上 6 仍锁着"（只要还没打过去），也让 §10.1 里要求保留的"完成 5 → 解锁 6"、TOWN 访问后"解锁 9"全部失效。§5.3 自己的论证（"位置是对手，不是已完成集合"，用于修掉 51+ 死锁）只要求 reach 作为**额外**通道，因此实现为「补集 + reach 上限」。T3「完成 10 → 11 解锁」与 §13 的三处同号门禁在此实现下全部成立。
2. **唯一写入点命名为 `StageFlow.on_stage_started(n)`（而非 `on_battle_started`）。**
   它由两个来源调用：host 转发 `StageManager.stage_started`（战斗），以及 TOWN 进入时 flow 自己的记账（TOWN 不启动战斗，但"进入城镇"就是站在那一关）。命名取"开始了一关"以免读者以为城镇不写位置。字段写入仍只有一处。
3. **区间重叠校验是静态跨区检查**：`StageDatabase.collect_range_conflicts(list)` / `get_authored_range_conflicts()`，而不是单实例 `get_validation_errors()` —— 一个 Resource 看不到兄弟资源，硬塞进实例校验只能是假的。单实例校验仍负责 `first_stage >= 1`、`special_stages` 落在 `[first_stage, last_stage]`（拦住"用 area 局部号写 override"这类作者错误）。
4. **测试里不新建 `forest2.tres`**：通过 `StageDatabase.set_area_table_override()` / `clear_area_table_override()`（显式区域表，测试 seam）在内存里造 Area 2 = 11–20，因此本 Phase 不新增任何游戏内容。`test_stage_range` 的 6 个用例全部走真实场景。

另有一处"不改"的决定：**`AreaView.compute_state()` 的优先级保持 COMPLETED > CURRENT**（现状如此）。因此阵亡回退到"已经清过的关"时，地图上那一关显示 DONE 而不是 HERE —— 本 Phase 修的是"地图指着已经被打回去的关"（旧缺陷 C：HERE 停在旧位置），现在三处位置永远同号，只是站在已清过的地面上时不再额外标 HERE。§13 的"三处同号"门禁场景（推进到未清过的 N）不受影响，`test_stage_range` T4 对两条规则都做了断言。
