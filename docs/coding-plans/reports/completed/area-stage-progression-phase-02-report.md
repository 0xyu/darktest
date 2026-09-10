# Area / Stage / StageType 系统 — Phase 2 报告（Stage Database 架构）

> 对应 `docs/coding-plans/area-stage-progression-coding-plan.md`（**Rev 2**）的 **Phase 2 — Stage Database + Forest 数据**。
> 前置输入：Phase 0 audit（`docs/area-stage-architecture-audit.md`）+ Phase 1 报告（`docs/coding-plans/reports/area-stage-progression-phase-01-report.md`）。

---

## 1. 本 Phase 完成内容

本 Phase 完成两件事：

**Task A — 重写 Coding Plan（Rev 2）**
废弃 Rev 1 的 `one stage = one .tres`（`forest_01.tres … forest_10.tres`）方案，把 **Phase 2–10、Final Architecture、DoD** 全部改写为 **Stage Database 架构**，目标支撑 **10,000+ stages**，并固化命名约束（不抢占 battle 引擎的 `StageManager` / `StageDefinition`，Phase 4 分发器命名 `StageRouter`）。

**Task B — 实现 Rev 2 的 Phase 2**
- 新增每-Area 紧凑关卡库 `StageDatabase`（一个 Area 一个数据资源），`StageData` 承担"运行时关卡定义"；查询**按需物化 + 缓存**。
- 用**一个** `forest.tres` 表达 Forest 全部 10 关（01–05,07,09=COMBAT / 06=EVENT / 08=TOWN / 10=BOSS）；**未创建**任何 `forest_01.tres … forest_10.tres`。
- 提供按 `stage_number` / 按 stage id / 跨 Area 的 lookup API；未知、越界、未 author 的 Area 均安全返回 `null`。
- 用**合成 `stage_count = 10,000`** 验证同一查询架构（不创建 10K 文件）。
- Phase 1 已建立的 `StageType / StageData / AreaData` **原样复用，未重建、未重名**。

---

## 2. 修改 / 新增的文件

全部代码均为**新增**；现有玩法代码（battle `StageManager` / `StageDefinition`、`LevelProvider/LevelManager`、`grid_combat`、HUD）**未改动**。另有 Coding Plan 由 docs 根旧版改写并复制到 coding-plans 目录（副本清理见 §5 已知问题 #1）。

### 新增

| 文件 | 说明 |
|---|---|
| `docs/coding-plans/area-stage-progression-coding-plan.md` | **Rev 2**：Phase 2–10 / Final Architecture / DoD 改写为 Stage Database 架构 |
| `scripts/data/stage_database.gd` (+`.uid`) | 新增 `StageDatabase`：紧凑每-Area 关卡库 + lookup + validation |
| `resources/stage_databases/forest.tres` | **唯一** Forest 数据资源（`stage_count=10`，`default=COMBAT`，`special_stages` 仅 06/08/10 三条） |
| `tests/stage_database_smoke_test.gd` (+`.uid`) | Phase 2 最小 smoke test |
| `docs/coding-plans/reports/area-stage-progression-phase-02-report.md` | 本报告 |

### 修改

| 文件 | 说明 |
|---|---|
| `docs/coding-plans/reports/area-stage-progression-phase-01-report.md` | 两处 coding-plan 路径引用更新为 Rev 2 位置 |

> 注：`docs/area-stage-architecture-audit.md`（Phase 0）的 coding-plan 引用曾被本 Phase 改指新路径，随后在磁盘上被外部**回退**为 docs 根路径——以当前磁盘状态为准，本报告不将其列为修改。

---

## 3. 架构决策

### 3.1 数据形态：一个 Area 一个紧凑 Resource，而非每 Stage 一个 `.tres`

目标 **10,000+ stages** ⇒ 每 Stage 一个 `.tres` 会产生 10K 文件（Git diff 灾难、不可维护、加载/内存线性膨胀）。故：

> **Stage ≠ .tres 文件。10,000 stages ≠ 10,000 .tres files。**

数据格式沿用仓库惯例选 **Godot Resource（`.tres`）——每 Area 一个文件**（仓库无 JSON/CSV 管线；`.tres` 提供类型导出、编辑器可视化、`load()` 内建缓存，无需每次进 Stage parse）。10K 关由紧凑规格承载，而非 10K 行/10K 文件。

### 3.2 `StageDatabase` = 紧凑的每-Area 关卡库

```text
Area（Forest / Swamp …）
  ↓
StageDatabase（resources/stage_databases/<area_id>.tres）
  ├── area_id
  ├── stage_count            ← 可到 10,000+，不需要任何文件
  ├── default_stage_type     ← 共享默认规则（COMBAT）
  └── special_stages[]       ← 稀疏覆盖：仅与默认不同的节点（Forest 只 3 条）
      ↓ lookup / 按需物化 + 按号缓存
StageData（= Phase 1 静态单关定义，兼作"运行时关卡定义"）
      ↓
StageRouter（Phase 4；不叫 StageManager）
      ↓
Gameplay
```

- 默认规则覆盖绝大多数关；只有 EVENT/TOWN/BOSS（或需要 authored 内容）的关进 `special_stages`。
- `get_stage()` 首次访问某关才构造 `StageData` 并按 `stage_number` 缓存；不预生成 `stage_count` 个对象（内存上界 ≈ 实际查询过的关数）。
- 对 `special_stages` 的扫描刻意保持在线性、稀疏、很小，保证单次查询廉价。

### 3.3 命名映射（关键）

Coding Plan 的 "StageDefinition" 在本仓库实现为 Phase 1 的 **`StageData`**——因为 battle 引擎已存在同名 `StageDefinition`（`systems/stage_definition.gd`）与同名 `StageManager`（单场战斗刷怪引擎）。本系统**不抢占**这两个名字；Phase 4 的分发器命名 `StageRouter`。

### 3.4 静态数据 ≠ 玩家进度

`StageDatabase / StageData` 不含 completed / unlocked / current——这些属于 Phase 3 的 `PlayerProgress`。返回的 `StageData` 由数据库物化（特殊节点先 `duplicate()` 再回填 canonical id），调用方不会改动 authored 资源。

### 3.5 Stage id 规范

`<area_id>_<补零 stage_number>`，补零宽度 = `max(3, stage_count 位数)`（Forest = `forest_001 … forest_010`）。id 查询容忍任意补零（`forest_006` / `forest_6` 都命中 stage 6）。

### 3.6 数据落点

新目录 `resources/stage_databases/<area_id>.tres`；`StageDatabase.load_area()` 从该约定路径加载，文件缺失返回 `null`（不报错），使"未 author 的 Area 查询 = null"成为干净路径。

---

## 4. 测试结果

执行命令（headless）：

```text
D:/IDE/godotEngine/Godot_v4.7.2-stable_win64_console.exe --headless --import --path <project>   # 注册新全局类 StageDatabase + 导入 forest.tres
D:/IDE/godotEngine/Godot_v4.7.2-stable_win64_console.exe --headless --path <project> -s res://tests/stage_database_smoke_test.gd
D:/IDE/godotEngine/Godot_v4.7.2-stable_win64_console.exe --headless --path <project> -s res://tests/area_stage_data_smoke_test.gd
```

| 测试 | 结果 |
|---|---|
| `stage_database_smoke_test.gd`（Phase 2） | **PASS**，`StageDatabase / Forest data smoke test passed.`，exit 0 |
| `area_stage_data_smoke_test.gd`（Phase 1 回归） | **PASS**，`Area / Stage data smoke test passed.`，exit 0 |

覆盖（Forest + 合成规模）：

- Forest 数据资源存在（单一 `forest.tres`），`area_id=="forest"`，`stage_count==10`，`is_valid()==true`；`special_stages` 仅 3 条。
- `get_stage(1)…(10)` 全部存在；类型 **01–05,07,09=COMBAT / 06=EVENT / 08=TOWN / 10=BOSS**。
- id 查询：`get_stage_by_id("forest_006")==EVENT`、`forest_008==TOWN`、`forest_010==BOSS`、`forest_001==COMBAT`；补零容忍 `forest_6==EVENT`、`forest_1==COMBAT`；canonical id `forest_006`。
- 静态跨 Area：`StageDatabase.lookup("forest",6)==EVENT`、`lookup_stage("forest_008/010")==TOWN/BOSS`。
- 未知安全返回 null：`get_stage(0/11/-3)`、`get_stage_by_id("forest_999999"/"forest_"/"swamp_001")`、`lookup_stage("forest_999999"/"swamp_001")`、`lookup("forest",999)`、`load_area("swamp")`（均 null，且**无 load 报错**）。
- **合成 10,000 关（不建文件）**：`stage_count=10000` 的 DB `is_valid()`；`get_stage(10000)==COMBAT`；`get_stage(10001)==null`；追加 `5000=BOSS` override 后 `get_stage(5000)==BOSS` 且 canonical id `synthetic_05000`（宽度 5）。
- Validation：非法 `default_stage_type`、`special_stages` 重复号、越界号分别被报告。

---

## 5. 当前已知问题

1. ~~coding-plan 新旧两份并存（待定）~~ **已解决**：Phase 2 完成后 canonical 定为 `docs/coding-plans/area-stage-progression-coding-plan.md`（Rev 2）；docs 根旧 Rev 1 副本已由用户删除；Phase 0 audit 的 coding-plan 引用已同步指向 canonical 位置。
2. **Stage id 补零宽度与 Phase 1 样例不一致**：Phase 1 测试内 `AreaData` 样例用 2 位 id（`forest_06`）；StageDatabase canonical id 用 `max(3,…)` 位（`forest_006`）。对 StageDatabase 无影响（查询容忍补零），但 **Phase 3 `PlayerProgress.completed_stages` 的 key 与 Phase 6 展示**需统一到 StageDatabase canonical id。
3. **数据资源目录为新增 `resources/stage_databases/`**：不在 CLAUDE.md 目标结构（原写 `resources/stages`）。可保留或改放其他位置，改动仅目录 + 类内 `DATABASE_DIR` 常量。
4. **编辑器未打开验证**：`forest.tres` 经 headless `--import` 与 headless 测试加载通过；未在 Godot 编辑器可视化打开过（编辑器打开会按需补 uid 等，属正常）。建议 Phase 3 前在编辑器里开一次确认。
5. **玩法数据入口仍为泛型占位**：`StageData` 的 `combat_data/event_data/…` 仍为 null；Forest 的 EVENT/TOWN/BOSS 只有类型与显示名，无玩法内容——**有意为之**，属 Phase 5+。

---

## 6. 下一 Phase（Phase 3 — Player Progress）需要知道的信息

- **复用**：`StageData`（查询返回对象）作为"关卡定义"；`StageDatabase.get_stage()/get_stage_by_id()` 判定存在/越界；`stage_count` 提供推进边界。
- **建议 API 基线**（Coding Plan Rev 2 Phase 3）：
  ```gdscript
  is_stage_unlocked(area_id, stage_number) -> bool     # n==1 或 n-1 已完成
  is_stage_completed(area_id, stage_number) -> bool
  complete_stage(area_id, stage_number)
  get_current_stage() -> { area_id, stage_number }
  ```
  `completed_stages` 用 StageDatabase canonical id（如 `forest_001`）作 key；**不要**存 Resource 本体。
- **命名**：新类叫 `PlayerProgress`（建议 `scripts/progress/`）；勿与 battle 侧 `PlayerProgression`（含未使用的 `current_stage`）混淆。`PlayerProgress` 全局类名当前空闲，可用。
- **类缓存**：新增含 `class_name` 的脚本后需一次 `--headless --import` 刷新全局类缓存，再 headless 跑测试（沿用本 Phase 命令）。
- **不实现**：Phase 3 只做进度 + 测试；不写存档（Phase 8）、不接 WorldMap、不改 UI。

---

## 7. 下一 Phase 是否可以开始

**可以。** Rev 2 coding plan 已更新；Forest 数据 + lookup API + 验证全部通过（含合成 10K 规模、未知查询安全返回 null），无 per-stage `.tres`。Phase 3 为纯新增 PlayerProgress，不依赖现有系统重构。

> 唯一建议在 Phase 3 前收敛的是 **§5 #1（coding-plan canonical 位置/旧副本清理）与 #2（id 补零口径）**——均不阻塞 Phase 3 编码，但建议先定案以免文档双源。
