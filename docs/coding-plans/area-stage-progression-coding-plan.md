# Godot Area → Stage → StageType 关卡系统（Stage Database 架构）

> 文档版本：**Rev 2**（Phase 2 起改为 Stage Database 架构，目标是支撑 **10,000+ stages**）。
> 历史：Rev 1 曾设想 `one stage = one .tres`（`forest_01.tres` … `forest_10.tres`），已在 Rev 2 **废弃**。原因见下方「# 关键架构变更」。

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
* 未来新增 `StageType`（ELITE / TREASURE / SHRINE / SECRET …）只扩展枚举，不新增文件体系
* Stage 类型由 `StageData.stage_type` 决定，不使用 `if stage == 6` 这类硬编码
* PlayerProgress 独立保存玩家进度（completed / unlocked / current 从不写进静态数据）
* 不破坏现有 Combat / Town / HUD / battle `StageManager` 系统

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
| `StageType` | `scripts/data/stage_type.gd` | `COMBAT=0, EVENT, TOWN, BOSS` + `is_valid()/get_display_name()`；未来扩展追加枚举即可 |
| `StageData` | `scripts/data/stage_data.gd` | `id / stage_number / display_name / stage_type` + 玩法数据入口（`combat_data…requirement_data`，可空） |
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

battle 侧 `PlayerProgression`（Resource，角色**数值成长**：level / experience / gold / skills）与本 `PlayerProgress`（**地图/关卡进度**）是两回事。混淆源 `PlayerProgression.current_stage`（从未被任何玩法代码读取的死字段——战斗 HUD 阶段条实际读 battle `StageState`）已在 Phase 3 **一并移除**（含 UI fixture / 测试），现仓库不再有两套「current stage」并存。长期若仍想消除一字之差，可单独发 `refactor:` commit 把旧类改名 `CharacterProgression`，勿混入 gameplay Phase。

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

# Phase 5 — Integrate Existing Combat / Town

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

# Phase 6 — WorldMap / AreaMap Integration

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

# Phase 7 — Stage Completion / Return Flow

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

# Phase 8 — Save / Load

## 目标

持久化 Area/Stage 进度，**只存 identifier，不存 Resource**：

```json
{
  "current_area": "forest",
  "current_stage": 6,
  "completed_stages": ["forest_001", "forest_002", "forest_003", "forest_004", "forest_005"]
}
```

Load 重建：

```text
Save → PlayerProgress → (area_id, stage_number) → StageDatabase.lookup → StageData → 进入对应玩法
```

`completed_stages` 用 stage id 字符串即可；`current_stage` 也可用数字，由 DB 再生成 id。不要序列化 StageDatabase / StageData 本体。

---

# Phase 9 — Add More Area（Swamp / 更多）

## 目标

验证架构不是只为 Forest 写的，且**扩展一个 Area 不需要改核心**。

新增例如 `Swamp`：

```text
Swamp
├── 01..05  COMBAT
├── 06      EVENT
├── 07..09  COMBAT（可用 stage_count 更大验证：如 07~29 COMBAT）
├── ...     TOWN / BOSS 依规则
└── N       BOSS
```

做法：**只新增一个 `resources/stage_databases/swamp.tres`**（`area_id="swamp"`，`stage_count=N`，`default_stage_type=COMBAT`，`special_stages` 覆盖 EVENT/TOWN/BOSS 节点）。

若想加入 ELITE / SHRINE 等类型：先扩展 `StageType` 枚举，再在 swamp.tres 的 special_stages 引用新类型。**核心 `StageRouter / PlayerProgress / WorldMap / StageDatabase` 不应改动。**

如果为了 Swamp 必须大改核心，说明仍有 hard-code，需要在本 Phase 修掉。

---

# Phase 10 — Refactor / Cleanup

## 最终检查

搜索项目，确认**没有**：

```text
stage == 6 / stage == 8 / stage == 10            # 玩法硬编码
forest_01.tres / forest_02.tres / ...            # 一 stage 一文件设计
"res://resources/stage_databases/forest_006.tres" # 按文件拼路径
```

确认职责：

```text
AreaData        静态：小/策展 Area 描述（含 background）
StageDatabase   静态：大型 Area 的紧凑关卡库（count + 默认规则 + 覆盖）
StageData       静态：单关定义（也是 DB 查询返回的"运行时定义"）
StageRouter     Stage → 玩法分发（Phase 4）
PlayerProgress  玩家进度（completed / unlocked / current）
Save            只存 identifier
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
      ┌─────────┼─────────┐
      │         │         │
   Combat     Event      Town
      │         │         │
      └─────────┼─────────┘
             (BOSS 走 Combat)
```

同时：

```text
PlayerProgress
│
├── current_area_id
├── current_stage_number
└── completed_stages (id → true)
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
Chat 06  Phase 5   Combat / Town Integration          ← 当前
Chat 07  Phase 6   WorldMap Integration
Chat 08  Phase 7   Completion / Return Flow
Chat 09  Phase 8   Save / Load
Chat 10  Phase 9   More Area（Swamp）
Chat 11  Phase 10  Final Refactor
```

---

# 每个新 Chat Session 的开场规则

每次把：

```text
1. 本 Coding Plan（Rev 2）
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
06 → Event
07 → Combat
08 → Town
09 → Combat
10 → Boss
```

并且：

```text
完成 01 → 02 unlocked
完成 05 → 06 unlocked（类型=EVENT，由 stage_type 决定而非 if 判断）
完成 06 → 07 unlocked
进入 08 → Town
完成 09 → 10 unlocked（类型=BOSS）
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
（如需新玩法类型，则扩展 StageType 枚举）
```

全程不出现：

```text
one stage = one .tres
```

这才是这个系统真正的扩展性目标。
