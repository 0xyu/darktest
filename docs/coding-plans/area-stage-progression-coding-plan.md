# Godot Area → Stage → StageType 关卡系统（Stage Database 架构）

> ⚠️ **Rev 3 取代说明（Phase 7.6）**：本文件的**位置/编号模型**已被
> `global-stage-range-coding-plan.md`（Rev 3，Phase 7.6，已实施）取代。仍然有效的部分：
> StageDatabase 紧凑规格、StageData 运行时对象、StageRouter 由 `stage_type` 决定 destination、
> 内容层叠加、单一 advance seam、StageFlow 分层。**作废**的部分：
> - 「每个 Area 各自从 1 编号」→ Stage 号是**一个全局递增计数器**，Area 只是它上面的一段**区间**
>   （`StageDatabase.first_stage + stage_count`）；area 局部编号不再存在。
> - 「`PlayerProgress.current_area_id` 是存储字段」→ 已**删除**，area 一律由位置**推导**
>   （`StageDatabase.area_for_stage(n)`），并新增单调字段 `highest_stage_reached`。
> - 「endless boot 从不写进度」→ **推翻**：开机那一关就在第一个 Area 的区间内，清掉就记账。
> 落地报告：`docs/coding-plans/reports/area-stage-progression-phase-07-6-report.md`。
>
> 文档版本：**Rev 3.2**（Phase 8 落地后修订：模型无变更，只在 Phase 8 节追加实现备注）。
> 历史：
> - Rev 1 曾设想 `one stage = one .tres`（`forest_01.tres` … `forest_10.tres`），已在 Rev 2 **废弃**。原因见下方「# 关键架构变更」。
> - **Rev 2.1**：见「# Rev 2.1 变更（Phase 7.5）」。落地报告：`docs/coding-plans/reports/area-stage-progression-phase-07-5-report.md`。
> - **Rev 3**（Phase 7.6）：见上方的取代说明。落地报告：`docs/coding-plans/reports/area-stage-progression-phase-07-6-report.md`。
> - **Rev 3.1**（文档修订，**无代码改动**）：
>   1. **Phase 8（Save / Load）整节重写**——它原来写的 JSON 形状（`"current_area": "forest"` / `"current_stage": 6`）是 Rev 2.1 模型的产物，Rev 3 已删除存储字段 `current_area_id`、新增 `highest_stage_reached`，旧形状直接作废。
>   2. **Phase 9（新增 Area）删除**——它的目标是"验证加 Area 不用改核心"，这件事已由 Phase 7.6 的**合成 Area 2（11–20）测试**验证完毕（`test_stage_range` T2/T3/T6 + `test_world_map` 的窗口偏移用例），再 ship 一个真 Area 不会带来新架构结论；真正剩下的是**内容设计任务**。其仍有价值的两条清理项并入 Phase 10，做法准则压缩为文末**附录 A**。
>   3. 相应更新：`Final Architecture` 的 `PlayerProgress` 字段块、Multi-Chat 执行序、Definition of Done 的"新增 Area"片段。
> - **Rev 3.2**（Phase 8 落地）：Phase 8 已实施（`StageProgressSave` 唯一挂载点 + 自动存档 + 开机恢复），**数据模型未变**；落地报告：`docs/coding-plans/reports/area-stage-progression-phase-08-report.md`。

## 总目标

建立可扩展的：

```text
Area
  ↓
StageDatabase（紧凑的每-Area 关卡库，一个 Area 一个数据资源）
  ↓  lookup_stage()
StageData（运行时"关卡定义"）
  ↓
StageRouter（进入哪种玩法，Phase 4）
  ↓
Gameplay Scene / View
```

示例（Forest）：

```text
Forest
├── Stage 01  Combat
├── Stage 02  Combat
├── Stage 03  Combat
├── Stage 04  Combat
├── Stage 05  Combat
├── Stage 06  Event
├── Stage 07  Combat
├── Stage 08  Town
├── Stage 09  Combat
└── Stage 10  Boss
```

最终目标是：

* Area / Stage 使用 Data / Resource 定义，但 **Stage 不与 `.tres` 文件一一对应**
* 一个 Area 用**一个紧凑的 StageDatabase** 描述其全部关卡（阶段数量 + 默认规则 + 稀疏特殊节点）
* StageData 只在查询时**按需物化**，因此 10 关、1,000 关、10,000 关走的是同一条加载/查询架构
* 未来新增 `StageType` 只扩展枚举，不新增文件体系
  * **Rev 2.1 注意**：`StageType` 只回答"进入哪种玩法视图"（COMBAT / TOWN / BOSS）。**加内容**（宝箱 / boss 敌人 / 交互 object / 剧情 …）走**内容层**（`StageContent`），**不是**新增 `StageType`——加内容永远不改路由。
* Stage 类型由 `StageData.stage_type` 决定，不使用 `if stage == 6` 这类硬编码
* PlayerProgress 独立保存玩家进度（completed / unlocked / current 从不写进静态数据）
* 不破坏现有 Combat / Town / HUD / battle `StageManager` 系统

---

# Rev 2.1 变更（Phase 7.5）

Phase 7 交付后复核发现语义与结构两方面问题，Rev 2.1 一并修订。

## 1. 语义：authored stage = 普通关 + 内容层

**游戏主打 endless。** 未被 author 的 stage 一律按普通 endless 关处理；被 author 的 stage **仍然是一关普通战斗**，只是额外叠加「内容层」。

```text
普通 stage（未被 author）        = endless 的一关，无任何额外内容
authored stage（被 author 的关） = 同一关普通战斗 + 内容层条目
```

* 内容层**不是** `StageType`：加内容永远不改变这一关进入哪种玩法。
* 两种生命周期：**一次性**（`one_shot = true`：宝箱取走后消失，该关**变回普通关**）与**可重复**（`one_shot = false`：boss 敌人击败后仍出现）。
* 触发方式：**走到格子上自动触发**；内容 object 不占用网格 occupancy，手动移动与 AUTO 移动走**同一个** `PlayerController.moved` 信号，因此自动化无法改变内容结果。
* **`StageType.EVENT` 退役**：`StageType` 只留 `COMBAT / TOWN / BOSS`。"这一关不是真战斗"这类事改由内容层表达，不再切割玩法词汇。
* **指定 boss 敌人沿用既有管线**：`resources/levels/level_<n>.tres` 的 `LevelConfig.boss`（authored stage 号与 battle level 1:1）。不另建一套。

## 2. auto next stage == manual next stage（单一 seam）

Phase 7 曾存在**两条互不知情的 next-stage 路径**：手动走 host 的 `_advance_after_clear()`（含 typed 拦截 → 回 WorldMap），而 AUTO 直接调 `StageManager.start_next_stage()` 绕过 host。Phase 7 的"漂移规则"（引擎推进出 typed stage 即结束 session）是绕开第二路径的补丁，Rev 2.1 **作废该补丁并统一路径**：

```text
手动 NEXT STAGE / primary_action ─┐
                                  ├─→ 单一 advance seam ─→ StageManager.start_next_stage()
AUTO stage_advance_requested ─────┘
```

* **stage 的 result（完成记录 / 文案 / 内容结算）完全不依赖 AUTO / FARMING**。
* FARMING 只保留"清场原地重刷"——这是**模式**语义，不是 result 差异。
* **清场后统一继续 endless（battle N+1）**；WorldMap 降为随时可开的**状态视图 / 捷径**，不再是每次清场的强制 hub。`_typed_entry`（typed session）整体删除。

## 3. 结构：StageFlow 抽取

Phase 5–7 的流程**策略**曾以 private method 形式堆在 `grid_combat`，使其越过 Combat Host 边界。Rev 2.1 抽出 **`StageFlow`**（`scripts/systems/stage_flow.gd`，`RefCounted`），独占：进入记账、visit 型关卡完成、战斗清场完成判定、下一关文案、线性解锁门槛、城镇关闭去向。

`grid_combat` 只保留 **host 机制**：切视图、启战斗、转发信号、唯一 advance seam。

> 职责归属自此应为：

```text
StageRouter      Stage → 玩法分发（类型→destination 表）
StageFlow        authored 流程策略（进入/完成/解锁/下一关文案/城镇去向）
grid_combat      scene host（视图切换、启战斗、信号转发、advance seam）
StageContent     静态：单关的 authored 内容条目
AuthoredContentState  玩家侧：哪些一次性内容已消费（独立于 PlayerProgress）
PlayerProgress   玩家侧：completed / unlocked / current
```

## 4. 玩家侧状态是两个独立对象

```text
PlayerProgress         "哪些 stage 已通关"   completed_stages = { "forest_006": true }
AuthoredContentState   "哪些内容已被用掉"   consumed        = { "forest_006:cache": true }
```

二者不可混同，且都只存 identifier（Phase 8 可直接序列化）。

---

# 关键架构变更（Rev 2）

## 为什么废弃 `one stage = one .tres`

原 Rev 1 的 Phase 2 计划为每个 Stage 建一个 `.tres`：

```text
forest_01.tres
forest_02.tres
...
forest_10.tres
```

项目未来目标是 **10,000+ stages**，因此这个方案被**明确废弃**：

> **Stage 不应该一对一对应 Godot `.tres` 文件。**

禁止创建：

```text
10,000 个 Stage Resource 文件
```

禁止建立依赖：

```text
Stage = .tres file
```

## 新架构方向

```text
Area
  ↓
Stage Database / Stage Registry
  ↓
Stage Definition（运行时）
  ↓
StageRouter
  ↓
Gameplay
```

而不是：

```text
Area
  ↓
10,000 × .tres
```

## 数据格式决策

不机械规定 JSON。根据 Phase 0 audit 与仓库实际：

* 现有数据体系**全部是 Godot Resource**（`resources/enemies`、`resources/levels`、`resources/sub_heroes`），**没有 JSON/CSV 加载管线**，尚无磁盘存档。
* Godot Resource 提供：类型安全导出、编辑器可视化、内建 `load()` + 资源缓存、无需每次 parse。
* 因此采用 **Godot Resource（`.tres`）**：**每个 Area 一个文件**（不是每个 Stage 一个文件）。
  * 10K stage 的"内容量"由**紧凑规格**表达（`stage_count` + `default_stage_type` + 稀疏 `special_stages` 覆盖），而不是 10K 行/10K 文件。
  * Git diff 友好：新增一个特殊节点只改几行。
  * 运行期：一次 `load()` 进缓存；查询 O(1)。

## 命名约束（避免与 battle engine 冲突）

仓库已存在同名但语义不同的类，**不可复用/抢占这些名字**：

* `StageManager`（`scripts/systems/stage_manager.gd`）＝ 单场战斗的刷怪/波次引擎。
* `StageDefinition`（`scripts/systems/stage_definition.gd`）＝ battle 层最终战斗定义。
* `StageState`、`StageControl`、`PlayerProgression` 均已存在。

因此本系统内：

* 分发器统一叫 **`StageRouter`**（Phase 4），**不叫** StageManager。
* "关卡定义"就是 Phase 1 的 **`StageData`**（已含 `id/stage_number/stage_type` + 玩法数据入口），**不再另建** `StageDefinition` 类。

## 静态数据 ≠ 玩家进度

保持不变：

```text
Static Game Data        Player Progress
AreaData                current_area_id
StageDatabase           current_stage_id / current_stage_number
StageData (静态)         completed_stages
                        unlocked 由连续推进推算
```

`StageData / AreaData / StageDatabase` 只描述静态结构，绝不保存 completed / unlocked / visited / current。

> ⚠️ **Rev 3.1 更正**：上面右栏是 Rev 2 时代的字段表，已被 Rev 3 取代。当前 `PlayerProgress` 是 `current_stage_number`（唯一位置）+ `highest_stage_reached`（单调解锁上限）+ `completed_stages`；**没有** `current_area_id`（推导量），"unlocked 由连续推进推算"改为 `is_stage_unlocked(n)` = `n==1 或 n<=highest_stage_reached 或 n-1 已完成`。序列化口径以 **Phase 8** 节为准。

---

# Phase 0 — Repository Audit（已完成）

## 目标

先理解现有项目，不修改代码。→ 产物 `docs/area-stage-architecture-audit.md`。

**审计要点**（详见 audit 报告）：

1. 现有 "Stage" 是 battle 引擎的**连续 int**（难度/生成/门点/死亡回退），不是地图节点。
2. 项目**无** Area / WorldMap / 场景切换 / 存档；Town 是未接线的 DEV stub。
3. `LevelProvider → LevelConfig / LevelTemplate → StageDefinition(battle)` 管线可复用。
4. **不改** `grid_combat`、battle `StageManager`、`LevelProvider/LevelManager` 行为。

**本阶段 NO CODE CHANGES。**

---

# Phase 1 — Core Stage Data Model（已完成）

产物见 `docs/coding-plans/reports/area-stage-progression-phase-01-report.md`。已建立：

| 类 | 文件 | 说明 |
|---|---|---|
| `StageType` | `scripts/data/stage_type.gd` | **Rev 2.1：`COMBAT=0, TOWN, BOSS`**（原 `EVENT` 已退役 —— 它描述的是"这一关不是真战斗"，现由**内容层**表达）+ `is_valid()/get_display_name()`；未来扩展追加枚举即可 |
| `StageData` | `scripts/data/stage_data.gd` | `id / stage_number / display_name / stage_type` + 玩法数据入口（`combat_data…requirement_data`，可空）+ **Rev 2.1：`content: Array[StageContent]`（authored 内容层，绝大多数关卡为空）** |
| `AreaData` | `scripts/data/area_data.gd` | `id / display_name / stages: Array[StageData] / background`（**小/策展集合**形态，见 Phase 2 说明） |
| 最小测试 | `tests/area_stage_data_smoke_test.gd` | 校验 + 枚举顺序 |

> `AreaData.stages`（显式 `Array[StageData]`）保留为**小型策展列表**的表示，但**不再是大型 Area 的主要表达方式**。大型 Area 走 Phase 2 的 `StageDatabase`。

---

# Phase 2 — Stage Database + Forest 数据（已完成，Rev 2 重写）

> 产物见 `docs/coding-plans/reports/area-stage-progression-phase-02-report.md`。

## 目标

建立"**一个紧凑的每-Area 关卡库**"与按需物化机制，并用它表达 Forest（10 关）。

**禁止**：为每个 stage 建立 `.tres`（`forest_01.tres` … `forest_10.tres`）。

## 新增

```text
scripts/data/stage_database.gd
resources/stage_databases/forest.tres        （唯一一个 Forest 数据资源）
tests/stage_database_smoke_test.gd
```

（若仓库已有 data folder / 更贴切的位置，Agent 可调整目录名，保持一 Area 一文件的思路即可。）

## StageDatabase（新，每 Area 一个实例）

字段：

```gdscript
class_name StageDatabase
extends Resource

@export var area_id: StringName          # &"forest"
@export var display_name: String          # "Forest"
@export_range(1, 99999, 1) var stage_count: int = 1
@export var default_stage_type: int = StageType.COMBAT   # 共享默认规则
@export var special_stages: Array[StageData] = []        # 稀疏覆盖：仅异于默认的节点
```

* `stage_count` 可以非常大（10 / 100 / 1,000 / 10,000）而不产生任何文件。
* `special_stages` 只罗列**与默认不同**（或需要 authored 内容）的节点：Forest 只需 06/08/10 三条。
* `StageData` 承担"运行时关卡定义"角色：查询返回的就是它。**复用 Phase 1，不重造 StageType/StageData。**

## Lookup API

```gdscript
db.get_stage(stage_number: int) -> StageData          # 越界返回 null
db.get_stage_by_id(stage_id: StringName|String) -> StageData
StageDatabase.lookup(area_id, stage_number) -> StageData     # 静态便捷：按 Area 加载后查询
StageDatabase.lookup_stage(stage_id) -> StageData            # "forest_006" → StageData，找不到 → null
```

* Stage id 规范：`<area_id>_<补零 stage_number>`，补零宽度 `max(3, stage_count 位数)`（Forest 为 `forest_001`…`forest_010`）。查询对数字后缀容忍任意补零（`forest_006` / `forest_6` 都命中 stage 6）。
* **懒物化 + 缓存**：只在查询时构造 `StageData` 并按 stage_number 缓存；不会一次性生成 `stage_count` 个对象。

## Validation

`get_validation_errors()` / `is_valid()`（沿用 Phase 1 风格）：

* `area_id` 非空；`stage_count >= 1`；`default_stage_type` 合法。
* 每个 `special_stages` 非空、`stage_type` 合法、`stage_number` 落在 `[1, stage_count]`。
* `special_stages` 的 stage_number 不重复。

## Forest 数据（逻辑）

```text
Forest
├── 01 COMBAT      （默认）
├── 02 COMBAT      （默认）
├── 03 COMBAT      （默认）
├── 04 COMBAT      （默认）
├── 05 COMBAT      （默认）
├── 06 EVENT       （special）
├── 07 COMBAT      （默认）
├── 08 TOWN        （special）
├── 09 COMBAT      （默认）
└── 10 BOSS        （special）
```

即：`forest.tres` 设 `stage_count = 10, default_stage_type = COMBAT`，`special_stages` 只含 06=EVENT / 08=TOWN / 10=BOSS 三条。

## 验证（测试）

至少断言：

```text
Forest 数据资源存在
Forest 有 10 个 stage
get_stage(1) 存在，stage_type == COMBAT
get_stage(6) 存在，stage_type == EVENT
get_stage(8) 存在，stage_type == TOWN
get_stage(10) 存在，stage_type == BOSS
lookup_stage("forest_006") → stage_type == EVENT
lookup_stage("forest_999999") → null
get_stage(0) / get_stage(11) → null
```

另加**合成规模验证**（不真建 10K 文件）：用代码构造 `stage_count = 10_000` 的 StageDatabase，查 `get_stage(10_000)`、覆盖节点等，确认同一条查询路径可用。

## 明确不实现（后续 Phase）

PlayerProgress / Save / WorldMap / Combat 接线 / Town 接线 / Event 玩法 / Boss 玩法——Phase 2 **都不做**。

## Output

代码 + Forest 数据 + 测试 + 更新本 coding plan + `docs/coding-plans/reports/phase-02-report.md`。

---

# Phase 3 — Player Progress（已完成）

> 产物见 `docs/coding-plans/reports/area-stage-progression-phase-03-report.md`。
> `PlayerProgression.current_stage` 死字段清理（见下方「命名注意」）并入本 Phase 一并完成。

## 目标

把静态 Game Data 与 Player State 彻底分离。`StageData / StageDatabase / AreaData` **保持静态不可变**。

## 新增

```text
scripts/progress/PlayerProgress.gd
```

保存：

```gdscript
current_area_id: StringName
current_stage_number: int          # 用 stage_number 表达当前位置（比存整串 id 更稳）
completed_stages: Dictionary       # { "forest_001": true, "forest_002": true, ... }
```

`completed_stages` 的 key 用 **StageDatabase 生成的 stage id**（标识符，不引用 Resource 本身）。

## Unlock Logic

第一版简单线性推进：

```text
stage_number == 1 → unlocked
完成 n → n+1 unlocked（n+1 <= StageDatabase.stage_count）
```

不再需要"列出 stage_01 ~ stage_10"。

## 必须支持

```gdscript
is_stage_unlocked(area_id, stage_number)
is_stage_completed(area_id, stage_number)
complete_stage(area_id, stage_number)
get_current_stage()  # → { area_id, stage_number }
```

`unlocked = (n == 1) or (n-1 in completed_stages)`，读取 `StageDatabase.stage_count` 判定是否越界。

## 命名注意（已清理）

battle 侧 `PlayerProgression`（Resource，角色**数值成长**：level / experience / gold / skills）与本 `PlayerProgress`（**地图/关卡进度**）是两回事。混淆源 `PlayerProgression.current_stage`（从未被任何玩法代码读取的死字段——战斗 HUD 阶段条实际读 battle `StageState`）已在 Phase 3 **一并移除**（含 UI fixture / 测试）。长期若仍想消除一字之差，可单独发 `refactor:` commit 把旧类改名 `CharacterProgression`，勿混入 gameplay Phase。

> ⚠️ **Rev 3 更正（Phase 7.6）**：上一段原写的「现仓库不再有两套『current stage』并存」**当时判断错误** —— Phase 3 只删了死字段 `PlayerProgression.current_stage`，漏算了地图正在读写的活字段 `PlayerProgress.current_area_id` + `current_stage_number`。后者是第二份位置，且只有"进入某一关"会写它，于是"清场推进"与"地图位置"逐步漂开（详见 `global-stage-range-coding-plan.md` §1.1）。Phase 7.6 已删除 `current_area_id`、把位置收敛为唯一写入点，该结论现在成立。

## Output

`PlayerProgress` + 基础测试。不写存档（Phase 8）。

---

# Phase 4 — StageRouter（已完成，进入哪种玩法）

> 产物见 `docs/coding-plans/reports/area-stage-progression-phase-04-report.md`。
>
> 实现备注（落地范围）：
> - StageRouter 为**纯路由壳**：`route()` / `destination_for_stage()` / `request_enter()`（signal `enter_requested`），headless 测试走通 **Forest 01→COMBAT / 06→EVENT / 08→TOWN / 10→BOSS**。
> - **Destination 词汇独立于 StageType**：BOSS（作者类型）路由进 `Destination.COMBAT`（当前仓库无独立 BossScene，boss/mini-boss 是 battle 层特性）；将来若确有独立 Boss/Shrine 场景，只扩展 `Destination` 枚举，Data 类不动。
> - **未接内容**：不进战斗、不显示 TownView、无 Event 内容（Phase 5）；未做解锁门槛（Phase 7）。只做"进入哪种玩法"的决定与入口请求信号。

## 目标

统一 Stage 进入入口。

```text
StageData
    ↓
StageRouter
    ↓
按 StageData.stage_type 进入对应玩法
```

**命名**：分发器叫 **`StageRouter`**（或类似），**不叫** `StageManager`（已被 battle 引擎占用，见「关键架构变更」）。

## 数据来源

StageRouter **不持有 10 个 stage 文件**，而是：

```gdscript
StageDatabase.lookup(area_id, stage_number) -> StageData   # 或由 StageDatabase 缓存传入
```

再读 `stage_data.stage_type` 决定路由。

## 路由

```text
COMBAT → Combat（Phase 5 接线）
EVENT  → Event View / Scene（内容属未来 Phase，仅占位）
TOWN   → Town View（复用 MobileCombatHUD 的 ViewContainer 切换先例）
BOSS   → Combat + Boss 专属战斗数据（或独立 BossScene，若真的独立才建）
```

**禁止** `if stage_number == 6 … elif stage_number == 8 …`：Stage 06 是 EVENT 的原因必须来自 `StageData.stage_type`。

## Scene Loading

项目无场景切换管理器（Phase 0 audit §4.3）。优先**同场景 View 切换**（现 `ViewContainer` 先例），不新建第二套 scene transition。

## Output

`StageRouter` + 走通 `Forest 01 → Combat / 06 → Event / 08 → Town / 10 → Boss`（Event 可为占位）。

---

# Phase 5 — Integrate Existing Combat / Town（已完成）

> 产物见 `docs/coding-plans/reports/area-stage-progression-phase-05-report.md`。
>
> 实现备注（落地范围）：
> - **非破坏性桥接**：把 StageRouter host 放进运行场景 `grid_combat`（持有 `PlayerProgress`），提供 `enter_area_stage(area, n)`；进入 COMBAT/BOSS → 调 battle `StageManager.initialize_stage(n)`（默认 N↔level N），TOWN → HUD 切 TownView，EVENT → 占位（不启战）。默认启动/无限推进不变。
> - **Town 接线完成**：`town_view_requested` / `TownView.close_requested / warehouse_requested / skills_requested` 全部接上（原先未接线 stub），`test_town_view` 由 2 失败转绿。
> - DEV 面板新增 **AREA STAGES** 区（数据来自 `StageDatabase`，只列 Forest 01/06/08/10）作可运行演示。真正的「WorldMap → 逐关推进」留 Phase 6/7。

## 目标

让旧系统通过 StageRouter 被调用。

## Combat（Battle-Stage 桥接）

`StageData`（地图节点）≠ battle `StageDefinition`。COMBAT/BOSS 进入时映射到底层 battle level：

```text
StageData
  ↓ stage_number / level 映射（默认：Forest 01..10 ↔ battle level 1..10）
  ↓
LevelProvider.get_stage_definition(level)   # 复用固定 LevelConfig 短路或程序化生成
  ↓
battle StageManager（刷怪/门点/胜利/farming/auto 全部照旧）
```

每个类型化 Stage 若需要作者化战斗内容，可挂 authored `LevelConfig`（`resources/levels/*.tres`）短路随机生成；对应关系写进 `StageData` 的未来 `combat_data`（Phase 2 未建，接线时补 typed 资源）。

## Town

`StageRouter` 收到 `stage_type == TOWN` 后显示 TownView，复用现有 ViewContainer 切换，接上原未接线的 `town_view_requested` 等信号。

## Boss

若 Boss 复用 CombatScene 而非独立 BossScene，**不要强行建 BossScene**：`stage_type == BOSS` 的路由目标可以是 Combat + Boss 专用内容（authored `LevelConfig.boss` / combat_data）。

## Output

旧 Combat / Town 能通过 Stage system 正常进入，且 stage 仍由 StageDatabase 查询而来。

---

# Phase 6 — WorldMap / AreaMap Integration（已完成）

> 产物见 `docs/coding-plans/reports/area-stage-progression-phase-06-report.md`。
>
> 实现备注（落地范围）：
> - 新增两个**纯呈现**类：`WorldMapView`（整屏地图 View：列出 `resources/stage_databases/` 下全部 author 的 Area）与 `AreaView`（单 Area 的 S 形 path；StageNode 由 `StageDatabase.stage_count` + 每个 `get_stage(n).stage_type` **动态生成**——节点图标/名称读 stage_type，零 `if stage == 6`，零"Stage 01..10"硬编码）。
> - 状态支持 `LOCKED / AVAILABLE / COMPLETED / CURRENT`，全部读自 `PlayerProgress`（presentation only）。
> - HUD ViewContainer 第三视图 + CombatView 底部 **MAP** 按钮；`grid_combat` 成为 map host：`open_world_map()` 用实时 `PlayerProgress` refresh 后切视图；节点点击（仅非 LOCKED 可点，host 侧再叠加解锁门槛）走既有 `enter_area_stage`；`_apply_stage_entry` 进入后收敛回 Combat/Town 视图（顺带关闭地图）。默认运行循环不变；DEV「AREA STAGES」QA 直达入口保留（可绕过解锁演示）。
> - **10K 呈现**：单 Area > `NODES_PER_WINDOW`(24) 节点时按窗口分页，每次只物化一页 Control（合成 1,000 关走同一条 `AreaView` 路径验证），不改数据架构。
> - **未实现**：完成/解锁/返回流程（Phase 7）、存档（Phase 8）、Event/Boss 专属内容、多 Area 间切换的呈现打磨（数据层已就绪；原 Phase 9 已于 Rev 3.1 删除，做法见文末**附录 A**）。

## 目标

WorldMap 不再 hard-code `Stage 01 … Stage 10`，而是：

```text
StageDatabase
  ↓ stage_count + lookup_stage()
  ↓
动态生成 Stage 节点（1..stage_count）
```

## WorldMap

```text
WorldMap
└── AreaView
    ├── Background
    ├── Path
    └── StageNodes（由 StageDatabase.stage_count 与 stage_type 动态生成）
```

## Stage Node 显示

每个 node = 一次 `get_stage(n)`，读 `stage_type` 决定 icon（Combat/Event/Town/Boss）与名称。

## 状态

至少支持 `LOCKED / AVAILABLE / COMPLETED / CURRENT`，读自 PlayerProgress。

## 大数据量展示（10K 呈现问题）

若单个 Area 有上千 node，WorldMap 应**分页 / 分区间 / 懒加载**展示，而不是一次建上万个 Control。这是**呈现**问题，不改变数据架构；本 Phase 先支持小 Area（10~100），大数据分页列为已知扩展。

## 禁止

WorldMap 不判断 `if stage == 6 → event icon`；一律走 `stage_data.stage_type`。

---

# Phase 7 — Stage Completion / Return Flow（已完成，**部分语义已被 Phase 7.5 取代**）

> ⚠️ **Rev 2.1 取代说明**：本 Phase 的以下决策已在 **Phase 7.5** 作废，读本段时以 Rev 2.1 为准：
> - 「typed session + 引擎漂移即结束 session」（§实现备注第 3、6 点与报告 §3.2/§5.3/§5.4）→ **删除**。漂移规则是绕开"AUTO 直接调 `start_next_stage()`"这条第二路径的补丁；Phase 7.5 改为**统一 seam**。
> - 「手动 typed 清场后回 WorldMap」（§实现备注第 4 点）→ **删除**。清场后统一**继续 endless**，WorldMap 降为随时可开的状态视图。
> - 「EVENT 占位 / 进入即算完成」→ EVENT 已退役。
> - 「完成语义依赖 AUTO/FARMING」→ **result 与自动化完全解耦**。
>
> 仍然有效的部分：完成判定只依赖 stage number（经 StageRouter/StageDatabase 解析）、零 stage 数字硬编码、下一关文案数据驱动、TOWN 进入即完成。
>
> ⚠️ **Rev 3 更正（Phase 7.6）**：本段原先写的「endless boot 从不写进度」**已作废**。开机那一关就是全局 stage 1，落在第一个 Area 的区间内，清场即记账；`PlayerProgress` 现在是 `current_stage_number`（唯一位置）+ `highest_stage_reached`（单调解锁上限）+ `completed_stages`（显式完成），而 `current_area_id` 已删除、改为推导。详见 `global-stage-range-coding-plan.md`。

> 产物见 `docs/coding-plans/reports/area-stage-progression-phase-07-report.md`。
>
> 实现备注（落地范围）：
> - **闭环达成**：`WorldMap → Stage → Gameplay → Complete(PlayerProgress) → 解锁下一关 → 回 WorldMap`。完成判定只依赖 `(area_id, stage_number)`（经 StageRouter/StageDatabase 解析），零 stage 数字硬编码。
> - **完成语义（v1）**：COMBAT/BOSS 类型关在其 author 战斗**清场**时记 `complete_stage`（`_on_stage_completed` 内 typed-session 钩子）；TOWN / EVENT（占位）**进入即算完成**（访问本身即该玩法的"返回"，否则 EVENT 会卡死线性解锁链）——真实 EVENT 内容落地后此语义可改回玩法返回。战斗型清场后状态文案动态读**下一 author 关的类型**（如 `STAGE 06 (EVENT) UNLOCKED`），末关显示 `AREA COMPLETE (10/10)`。
> - **typed session**：`grid_combat._typed_entry` 记录当前 author 关（area/stage/destination/from_map），仅经 `enter_area_stage` 进入时非空；默认 endless 循环从不写进度。战斗引擎漂移（AUTO/FARMING 推进或 defeat 回退到其他 battle stage）即视为 typed session 结束，后续清场恢复 endless 规则（不写进度）。
> - **返回地图闭环**：手动模式在 typed 战斗清场后走出口 + NEXT STAGE 不再 `start_next_stage` 无尽推进，而是 `open_world_map()`（hub）；地图来源的 TOWN 进入在关闭城镇后回地图（新增 HUD `town_close_requested` 信号由 host 裁决）；地图来源的 EVENT 占位访问完成即停留在地图（节点转 COMPLETED、下一关 AVAILABLE）。非地图来源（DEV/直接调用）的城镇关闭仍回 CombatView（Phase 5 行为不变）。endless boot 清场照旧 `start_next_stage`。
> - **AUTO/FARMING 语义**：typed 关内 AUTO/FARMING 仍走战斗引擎（刷级/挂机）；typed 关清场只记一次完成（幂等），随后按漂移规则退出 typed session。已文档化为设计取舍。
> - **回归**：新增 `test_stage_progression` 套件（8 测试）；Phase 1–6 全部套件/冒烟零改动转绿；全量 ui_harness 仅剩既有 `test_combat_log_wiring::test_kill_logs_event_end_to_end` 一项失败；项目 parse 干净。

## 目标

```text
WorldMap → Stage → Gameplay → Complete → PlayerProgress → Unlock next → 回 WorldMap
```

例：

```text
Forest 05
 ↓ Combat 胜利
 ↓ PlayerProgress.complete_stage("forest", 5)
 ↓ stage 6 unlocked（默认型：查 StageDatabase 得 EVENT）
 ↓ 回 WorldMap
```

- Stage 06 EVENT / 08 TOWN / 10 BOSS 的完成语义由各自玩法返回；解锁判断统一走 `is_stage_unlocked(area, n+1)`。
- Town 是否计入 completed：第一版建议"进入即算完成"（可访问 + 首次进入计入），以实际需求为准。

## 关键

推进逻辑只依赖 `(area_id, stage_number)`，由 `StageDatabase.stage_count` 判定边界，**不依赖具体 stage id 列表或文件**。

---

# Phase 7.5 — Authored Stage 模型修订 + StageFlow 抽取（已完成）

> 产物见 `docs/coding-plans/reports/area-stage-progression-phase-07-5-report.md`。完整变更说明见本文件「# Rev 2.1 变更（Phase 7.5）」。

## 目标

1. **auto next stage == manual next stage**：两条路径收敛为唯一 seam，二者行为与结果完全一致。
2. **stage 的 result 不依赖 AUTO / FARMING**（FARMING 仅保留"原地重刷"模式语义）。
3. **authored stage 重定义为「普通战斗关 + 内容层」**；未被 author 的 stage 一律按 endless 普通关处理；清场后统一继续 endless。
4. **`StageType.EVENT` 退役**，并入内容层表达。
5. **把流程策略从 `grid_combat` 抽成独立 `StageFlow`**，`grid_combat` 退回 Combat Host。
6. 内容层首批实现：**宝箱（一次性）**、**治疗池/交互 object（可重复）**；**boss 指定沿用既有 `LevelConfig` 管线**；剧情 story 本轮不做。

## 落地范围

* `StageFlow`（`scripts/systems/stage_flow.gd`）：进入记账、visit 完成、战斗清场完成判定、下一关文案、解锁门槛、城镇关闭去向。`grid_combat` 内**不再有任何流程规则**。
* **唯一 advance seam**：`AutoCombatController` 新增 `stage_advance_requested` / `notify_advance_result()`；`_start_next_stage_from_exit()` 不再直接推进 stage。手动与 AUTO 共用 `grid_combat._advance_after_clear()`。
* `_typed_entry` / `_entry_from_world_map` 与 4 个规则方法（`_record_typed_battle_completion` / `_record_typed_visit_completion` / `_authored_next_text` / `_return_to_world_map_from_typed_clear`）**删除**。
* 内容层：`StageContent`（数据）/ `AuthoredContentState`（独立玩家侧状态）/ `StageContentObject`（呈现）/ `StageContentController`（运行时）。走上格子触发，内容格不占 occupancy。
* Forest 06 现为 **COMBAT + Hidden Cache（一次性）+ Forest Spring（可重复）** 的示例。
* 测试：新增 `test_stage_content`（5）+ `stage_content_smoke_test`；`test_stage_progression` 增至 9（新增 auto/manual 单一 seam 守卫，该测试在修正前必然失败）；因模型变更改写的既有断言逐项记录在报告 §5.4。

## 门禁

* 全量 ui_harness **76 tests / 75 passed**（唯一失败为既有 `test_combat_log_wiring::test_kill_logs_event_end_to_end`）；5 个 smoke + 全项目 parse 干净。

---

# Phase 8 — Save / Load（**Rev 3.1 重写**）

> ⚠️ **本节曾按 Rev 2.1 的"每 Area 各自编号 + 存储 `current_area_id`"模型书写**（旧样例如 `{"current_area": "forest", "current_stage": 6, ...}`）。该模型已被 Rev 3（Phase 7.6）取代：`current_area_id` **已从 `PlayerProgress` 删除**（area 改为推导量），并新增单调字段 `highest_stage_reached`。**照旧样例实现 = 把"两份位置"请回存档里**，故整节按当前代码重写。

## 目标

持久化**玩家侧进度**，只存 identifier / 标量，**不存 Resource，也不存 area**。

当前正确形状（4 组数据，来自 2 个对象）：

```json
{
  "version": 1,
  "current_stage_number": 6,
  "highest_stage_reached": 9,
  "completed_stages": ["forest_001", "forest_002", "forest_003", "forest_004", "forest_005"],
  "consumed_content": ["forest_006:cache"]
}
```

| 字段 | 来源 | 为什么必须存 |
|---|---|---|
| `current_stage_number` | `PlayerProgress.current_stage_number` | **唯一位置**（全局关号）。可以小于 `highest_stage_reached`（阵亡回退过） |
| `highest_stage_reached` | `PlayerProgress.highest_stage_reached` | **单调解锁上限**。漏存 → 读档后地图解锁状态丢失（Phase 7.6 报告 §7 点名） |
| `completed_stages` | `PlayerProgress.completed_stages` | 显式通关集合，key 为 canonical id（`forest_006`）。**不能由位置推导**：当前站着的那关还没清 |
| `consumed_content` | `AuthoredContentState.consumed` | 一次性内容（宝箱）已消费集合，key 形如 `forest_006:cache` |

**明确不存**：

```text
current_area_id / 任何 area 字段      # 推导量：StageDatabase.area_for_stage(n)。存它 = 第二份位置回归
StageDatabase / StageData 本体        # 静态数据由 .tres 提供；存本体等于把 10K 关快照进存档
area 局部关号作为"位置"                # 全局号是唯一编号
```

## Load 重建

```text
存档 → PlayerProgress(current_stage_number / highest_stage_reached / completed_stages)
      + AuthoredContentState(consumed)
     → 注入 StageFlow / StageContentController
     → 位置 n → StageDatabase.lookup(n) → StageData → StageRouter → 进入对应玩法
```

* **区间外的位置是合法存档**（如 51+ 的纯 endless 尾段）：不要夹取回区间内，那是"author 内容走完"的正常状态。
* 至少要两条校验：`current_stage_number >= 1`；`highest_stage_reached >= current_stage_number`（不满足时用 `PlayerProgress.mark_reached(current_stage_number)` **抬高上限**，而不是压低位置）。
* `completed_stages` 里存在**当前内容已不覆盖**的 id（区间被重划分过）不是坏档：`is_stage_completed()` 只认能从 `StageDatabase` 取到 id 的号，旧 id 静静留着即可 —— 但那正是下一节说的迁移点。

## 挂载点与存档时机（现状）

今天两个状态对象都是**就地 `new()`**，没有任何注入点：

```gdscript
# scripts/world/grid_combat.gd _ready()
_flow = StageFlowScript.new()                                      # → 自建 PlayerProgress
_stage_content.configure(..., AuthoredContentStateScript.new())    # → 自建 AuthoredContentState
```

两者**都已支持注入**（`StageFlow._init(progress)`、`StageContentController.configure(..., state)`），所以本 Phase **不需要改数据模型**，只需要：

1. 定下**唯一挂载点** —— 建议由一个存档 / session 对象**同时持有** `PlayerProgress` 与 `AuthoredContentState`，避免挂载点分裂（分裂的后果就是读档只恢复一半）。
2. 把上面两处 `new()` 换成**注入**已加载（或新建）的实例。
3. 存档时机（全是低频事件，直接写盘即可）：`StageFlow.on_stage_started()` 改位置后、`StageFlow.on_battle_cleared()` 记完成后、`AuthoredContentState.consume()` 消费一次性内容后。

## 可复用的先例

仓库已有"对象自带 `to_save_data()/load_save_data()` + 外层聚合"的形状（`SubHeroInstance` / `SubHeroProgressionService`，见 `docs/area-stage-architecture-audit.md` 的「序列化形状」一行）——本 Phase 的两个状态对象正好同形。但**落盘本身在仓库里尚无先例**（`scripts/` 下没有任何 `FileAccess`），文件位置 / 格式由本 Phase 自定。

## 与区间重划分的耦合（迁移成本提醒）

`completed_stages` 的 key 是 **canonical id（`<area_id>_<补零全局号>`）**，而补零宽度由**该 Area 区间末号**决定。因此**重新划分区间**（例如把 dungeon 从 21 起改成 25 起）会改变该 Area 的 id 形态，旧存档里的旧 id 不会被新查询认出来。

* 当前项目**尚无存档**，此代价为零。
* **Phase 8 一落地，此代价就不再为零**：此后改区间需要一次迁移，或靠 `version` 字段做格式转换。这是选"id"而非"纯全局号"换可读性的代价（取舍见 `global-stage-range-coding-plan.md` §5.2 / §12.2）。

## 不做

不改 `StageDatabase` / `StageData` / `StageRouter` / `PlayerProgress` 的字段模型（它们已经是 identifier 形态）；不改战斗引擎；不把存档做成新的 autoload 全局状态（先由 host 持有并注入）。

> 产物见 `docs/coding-plans/reports/area-stage-progression-phase-08-report.md`（**已完成**）。
>
> 实现备注（落地范围）：
> - 新增 **`StageProgressSave`**（`scripts/progress/stage_progress_save.gd`）：**唯一挂载点**，同时持有 `PlayerProgress` + `AuthoredContentState`；落盘 `user://save/stage_progress.json`（JSON，5 个字段：`version` / `current_stage_number` / `highest_stage_reached` / `completed_stages` / `consumed_content`，**零 area 字段、零 Resource 本体**）。
> - **自动存档 = 订阅信号**，而不是在游戏各路径里调 `save()`：`StageFlow.progress_changed`（只在位置或解锁上限**真的变了**时发）+ `AuthoredContentState.content_consumed`（幂等重复消费不发）。计划要求的三处时机全覆盖，且 FARMING 挂机不会反复写盘。副作用一处：**一次什么都没做的新开局不会立刻产生存档文件**。
> - **开机恢复**：`grid_combat._start_first_stage()` 从存档关号继续（`initialize_stage(n)`），**不**经过 `StageRouter` —— COMBAT/BOSS 走 router 与不走 router 的可观察结果完全相同（战斗关卡号 == 全局关号），而 TOWN 位置若"进入城镇"会让开机时**没有任何关卡启动**（无敌人、无法推进），故 TOWN 位置按该关号的普通战斗恢复。坏档 / 未来版本档不阻塞开机，直接开新游戏。
> - **校验**：`version` 缺失或比本版本更新 → 拒绝；`current_stage_number ∈ [1, 999999]`（字段自身声明域）；`highest_stage_reached < position` → **抬高上限**（`mark_reached`）而不是压低位置；**区间外位置（57+）是合法存档且不夹取**；已不被 area 覆盖的旧 id 保留。
> - **测试隔离**：`StageProgressSave.set_default_path()` 是运行期静态开关（不写 `project.godot`）；UI harness 在每个测试前把游戏存档重定向到 `res://.godot/ui_harness/stage_progress.json` 并删除，**绝不触碰玩家的真存档**（见 `docs/ui-harness.md` 陷阱 9）。
> - **回归**：新增 `tests/stage_progress_save_smoke_test.gd`（11 用例 / 88 断言）+ `tools/ui_harness/suites/test_stage_save.gd`（8 用例 / 52 断言）；全量 ui_harness **91 tests / 90 passed / 1 failed**（唯一失败为既有历史失败 `test_combat_log_wiring::test_kill_logs_event_end_to_end`，baseline 同样失败）；7 个 SceneTree smoke 全绿；编辑器实机验证"玩 → 关掉 → 再开 → 从存档关继续"通过。

---

# Phase 9 — 新增 Area（**Rev 3.1：已删除**）

> **本节作为"架构验证 Phase"已删除**，理由：
>
> 1. 它的目标是"验证扩展一个 Area 不需要改核心"。**这件事已经验证完了**——Phase 7.6 用**内存里的合成 Area 2（11–20，`StageDatabase.set_area_table_override()`）**跑通了同一条路径，零新增游戏内容：
>    * `test_stage_range` **T2**：清掉 10 → 推进 11 → area 推导自动变 area 2、地图 HERE 落在 area 2 的 11、area 1 不再标 HERE；
>    * `test_stage_range` **T3**：完成 10 → `is_stage_unlocked(11)` 为真（跨区间解锁链）；
>    * `test_stage_range` **T6**：区间重叠被 `collect_range_conflicts()` 报出，相邻（10/11）不算重叠；
>    * `test_world_map`：**非默认 `first_stage` 的窗口偏移**用例。
>
>    再 ship 一个真 Area 不会得出新的架构结论，只会得到"这确实是内容"。
> 2. 真去做第二个 Area，主要工作是**游戏设计**（区间起点/长度、哪些节点挂哪种内容、难度曲线），不是 coding phase；按项目规则也不应为它先建投机代码。
> 3. 原 Phase 9 里**仍然可执行**的清理项已并入 **Phase 10** 的检查清单（DEV 面板仍写死 `load_area(&"forest")` 与 `FOREST %02d` 标签）。
>
> 新增 Area 的做法与"内容层 vs 新 `StageType`"的判断准则**压缩保留在文末「附录 A」**，需要时照它做即可。
>
> **Phase 10 的编号保留不动**，以免与历史报告里"Phase 9 = 新增 Area"的说法打架。

---

# Phase 10 — Refactor / Cleanup

## 最终检查

搜索项目，确认**没有**：

```text
stage == 6 / stage == 8 / stage == 10            # 玩法硬编码
forest_01.tres / forest_02.tres / ...            # 一 stage 一文件设计
"res://resources/stage_databases/forest_006.tres" # 按文件拼路径
```

并确认**没有**（Rev 3.1：自原 Phase 9 并入的 area 字面量清理）：

```text
load_area(&"forest") / area id 字面量出现在核心与 UI 代码里   # 已知遗留：scripts/ui/development_panel.gd
"FOREST %02d" 之类写死的区域名                                # 应读 StageDatabase.display_name
```

确认职责：

```text
AreaData        静态：小/策展 Area 描述（含 background）
StageDatabase   静态：大型 Area 的紧凑关卡库（count + 默认规则 + 覆盖）
StageData       静态：单关定义（也是 DB 查询返回的"运行时定义"）
StageContent    静态：单关的 authored 内容层条目（宝箱 / 交互 object …，可空）
StageRouter     Stage → 玩法分发（类型→destination 表）
StageFlow       authored 流程策略（进入 / 完成 / 解锁门槛 / 下一关文案 / 城镇去向）
PlayerProgress  玩家进度（completed / unlocked / current）
AuthoredContentState  玩家侧：哪些一次性内容已消费（独立于 PlayerProgress）
Save            只存 identifier
```

并确认**没有**：

```text
grid_combat 内出现流程规则（完成判定 / 解锁 / 下一关文案 / 返回去向）   # Rev 2.1：应全部在 StageFlow
手动与 AUTO 各自推进 stage                        # Rev 2.1：只能有一条 advance seam
stage result 依赖 is_auto_enabled() / is_farming_enabled()
内容层条目改变某一关的 stage_type / route         # 内容只叠加，不改玩法
```

---

# Final Architecture

```text
                    WorldData（可选聚合层）
                       │
                ┌──────┴──────┐
                │             │
             Forest          Swamp
                │
          StageDatabase   (一个 Area 一个数据资源)
            ├── area_id
            ├── stage_count
            ├── default_stage_type
            └── special_stages[]（稀疏覆盖）
                │  lookup_stage()
                ▼
          StageData（= 运行时关卡定义）
            ├── id / stage_number
            ├── stage_type
            └── 玩法数据入口（combat_data / event_data / …，接线时挂）
                │
                ▼
          StageRouter
                │
      ┌─────────┴─────────┐
      │                   │
   Combat                Town
      │                   │
      └─────────┬─────────┘
          (BOSS 走 Combat)

  战斗关之上可叠加「内容层」（StageContent）：
    宝箱 / 治疗池 / 特殊交互 object / …（一次性或可重复）
  内容不改变路由，也不改变这一关进入哪种玩法
```

同时（**Rev 3.1 更正** —— 旧版此处列出的 `current_area_id` 已不存在，area 是推导量）：

```text
PlayerProgress（玩家侧 · 位置与通关）
│
├── current_stage_number      ← 唯一位置（全局关号），唯一写入点 StageFlow.on_stage_started()
├── highest_stage_reached     ← 单调解锁上限（阵亡回退不下降）
└── completed_stages (id → true)

AuthoredContentState（玩家侧 · 另一个独立对象）
└── consumed ("<stage_id>:<content_id>" → true)

area 不是字段：由 StageDatabase.area_for_stage(current_stage_number) 推导
存档只序列化上面 3 + 1 项（见 Phase 8），不含任何 area 字段
```

独立于静态 `AreaData / StageDatabase / StageData`。

```text
10,000 stages ≠ 10,000 .tres files
```

---

# Multi-Chat Execution Order

每个 Chat Session **只负责一个 Phase**，按序：

```text
Chat 01  Phase 0   Repository Audit                 ✅ 完成
Chat 02  Phase 1   Core Stage Data Model             ✅ 完成
Chat 03  Phase 2   Stage Database + Forest            ✅ 完成
Chat 04  Phase 3   Player Progress                    ✅ 完成
Chat 05  Phase 4   StageRouter                        ✅ 完成
Chat 06  Phase 5   Combat / Town Integration          ✅ 完成
Chat 07  Phase 6   WorldMap Integration                ✅ 完成
Chat 08  Phase 7   Completion / Return Flow            ✅ 完成（部分语义被 7.5 取代）
Chat 08b Phase 7.5 Authored Stage 模型 + StageFlow 抽取 ✅ 完成
Chat 08c Phase 7.6 Global Stage Range 模型（Rev 3）        ✅ 完成
Chat 09  Phase 8   Save / Load（按 Rev 3 模型序列化）       ✅ 完成
         Phase 9   新增 Area                                ✗ 已删除（Rev 3.1，见该节；做法见附录 A）
Chat 10  Phase 10  Final Refactor                          ← 下一个
```

---

# 每个新 Chat Session 的开场规则

每次把：

```text
1. 本 Coding Plan（**Rev 2.1**）
2. 当前 Phase
3. 上一个 Phase 的 output/report
```

交给 agent。并要求：

```text
Before modifying code:

1. Inspect the current repository.
2. Read the previous phase output.
3. Identify existing systems that should be reused.
4. Do not duplicate existing managers or singletons.
5. Do not refactor unrelated systems.
6. Implement only this phase.
7. Run relevant tests/checks.
8. Report changed files.
9. Report remaining risks.
10. Report whether the next phase can start.
```

仓库当前实现是 source of truth；不要假设过往 Phase 完全照旧文档实现，以实际代码为准。

---

# Definition of Done

整个系统完成后，必须能：

```text
WorldMap
    ↓
Forest（StageDatabase）
    ↓
01 → Combat
02 → Combat
03 → Combat
04 → Combat
05 → Combat
06 → Combat + 内容层（Hidden Cache 一次性 / Forest Spring 可重复）   # Rev 2.1
07 → Combat
08 → Town
09 → Combat
10 → Boss
```

并且：

```text
完成 01 → 02 unlocked
完成 05 → 06 unlocked（06 是 authored 关：仍是 Combat，额外带内容层）
完成 06 → 07 unlocked（清场后继续 endless，不再被强制弹回 WorldMap）
进入 08 → Town（进入即完成，关闭回地图）
完成 09 → 10 unlocked（类型=BOSS，由 stage_type 决定而非 if 判断）
AUTO 开启与否 → 上述每一步的 result 完全相同                        # Rev 2.1
```

新增 Area（Swamp / 更多）时，**不需要修改核心**：

```text
StageRouter
PlayerProgress
StageDatabase（核心查询）
WorldMap
```

只需要新增：

```text
一个 StageDatabase 数据资源（resources/stage_databases/swamp.tres）
  ├── area_id            = "swamp"
  ├── display_name       = "Swamp"
  ├── first_stage        ← Rev 3：区间起点（全局号），必须与已有区间不重叠
  ├── stage_count        ← 区间长度（first_stage .. first_stage + count - 1）
  ├── default_stage_type ← 共享默认规则
  └── special_stages[]   ← 稀疏覆盖（内容层也挂这里）
（如需新玩法类型，则扩展 StageType 枚举；加内容不改路由）
```

> 这条路径**已由 Phase 7.6 的合成 Area 2 测试证明**（`test_stage_range` T2/T3/T6），不需要真 ship 第二个 Area 才算验证完毕；真 ship 是内容任务，做法见**附录 A**。

全程不出现：

```text
one stage = one .tres
```

这才是这个系统真正的扩展性目标。

---

# 附录 A — 新增 Area / 新内容怎么做（内容任务，非架构 Phase）

> Rev 3.1：原 Phase 9 的内容压缩为这份准则保留。这是**内容设计**的做法说明，不是待执行的 Phase；真要做时按它做即可。

## A.1 加一个 Area

只新增一个 `resources/stage_databases/<area>.tres`：

```text
area_id            = "swamp"
display_name       = "Swamp"
first_stage        = 11        # 区间起点（全局号），必须落在已有区间之外
stage_count        = 20        # 于是覆盖 11–30
default_stage_type = COMBAT
special_stages     = [ 覆盖节点：TOWN / BOSS / 带内容层的节点 ]
```

* **区间不重叠**由 `StageDatabase.collect_range_conflicts()` 校验（相邻 10 / 11 不算重叠，ship 的 area 必须通过）。
* 放完即出现在 WorldMap（`WorldMapView._discover_databases()` → `StageDatabase.discovered_databases()` 扫目录 + `is_valid()` 过滤），**核心零改动**。注意区域表是**进程内缓存**的：运行中新增 `.tres` 需 `StageDatabase.invalidate_cache()`，重启则自然生效。
* 该 Area 的 stage id 形如 `swamp_011`：补零宽度 = `max(3, 区间末号的位数)`。**改区间起点/长度会改 id 形态** → 存档迁移代价见 Phase 8 节。

## A.2 加内容（绝大多数情况）

先确认它是"另一种玩法"还是"叠加在战斗关上的内容"：

* **内容**（精英敌人 / 宝箱怪 / 祭坛交互 / 治疗池 …）→ 走**内容层**：在该 Area 的 `special_stages` 条目上挂 `StageContent` 条目（`one_shot` 决定一次性还是可重复），**核心改动为零，路由不变**。
* **另一种玩法视图**（真的不打架、要独立场景）→ 才扩展 `StageType` 枚举 + `StageRouter` 的 destination 表。

"这一关不是真战斗"这类事**永远走内容层**，不要新增 `StageType`（Rev 2.1 起 `EVENT` 已退役）。

## A.3 何时才需要重新评估核心

如果为了加一个 Area 必须改 `StageRouter / StageFlow / PlayerProgress / StageDatabase / WorldMap`，说明仍有 hard-code（已知遗留见 Phase 10 清单），应先修 hard-code 而不是为它加特例。

