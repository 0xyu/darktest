# Area / Stage / StageType 系统 — Phase 2 报告（Stage Database 架构）

> 对应 `docs/coding-plans/area-stage-progression-coding-plan.md`（**Rev 2**）的 **Phase 2 — Stage Database + Forest 数据**。
> 前置输入：Phase 0 audit（`docs/area-stage-architecture-audit.md`）+ Phase 1 报告（`docs/coding-plans/reports/area-stage-progression-phase-01-report.md`）。

---

## 1. Summary

本 Phase 完成两件事：

**Task A — 重写 Coding Plan**：废弃 Rev 1「`one stage = one .tres`」方案，把后续 Phase 2–10、Final Architecture、DoD 全部改写为 **Stage Database 架构**（目标 10,000+ stages），并固化命名约束（不抢占 battle 引擎的 `StageManager` / `StageDefinition`）。

**Task B — 实现 Rev 2 的 Phase 2**：
- 新增每-Area 紧凑关卡库 `StageDatabase`（一个 Area 一个数据资源），`StageData` 承担"运行时关卡定义"，查询按需物化。
- 用**一个** `forest.tres` 表达 Forest 全部 10 关（06=EVENT / 08=TOWN / 10=BOSS），**未**创建任何 `forest_01.tres … forest_10.tres`。
- 提供按 `stage_number` / 按 stage id / 跨 Area 的 lookup API；未知/越界安全返回 `null`。
- 通过合成 10,000 关验证同一查询架构（不创建 10K 文件）。
- 更新文档并产出本报告。

Phase 1 已建立的 `StageType / StageData / AreaData` **原样复用，未重建、未重名**。

---

## 2. Architecture

```text
Area（Forest / Swamp …）
  ↓
StageDatabase   （一个 Area 一个紧凑数据资源）
    ├── area_id
    ├── stage_count            ← 可到 10,000+，不需要任何文件
    ├── default_stage_type     ← 共享默认规则（COMBAT）
    └── special_stages[]       ← 稀疏覆盖：只有与默认不同的节点
        ↓  lookup / materialize（按需，懒物化 + 缓存）
StageData（= Phase 1 的静态单关定义，兼作"运行时关卡定义"）
    ├── id / stage_number / stage_type
    └── 玩法数据入口（combat_data / event_data / …，留待接线 Phase）
        ↓
StageRouter（Phase 4，不叫 StageManager）
        ↓
Gameplay
```

**命名映射（关键）**：Coding Plan 里的 "StageDefinition" 在本仓库实现为 Phase 1 的 **`StageData`**——因为 battle 引擎已存在同名 `StageDefinition`（`systems/stage_definition.gd`），以及同名 `StageManager`（单场战斗刷怪引擎）。本系统不抢占这两个名字；Phase 4 的分发器将命名 `StageRouter`。

**静态数据 ≠ 玩家进度**：`StageDatabase / StageData` 不含 completed / unlocked / current；这些属于 Phase 3 的 `PlayerProgress`。

**扩展方式**：新增 Area（含 10K 关的大 Area）= 新增**一个** `resources/stage_databases/<area_id>.tres`；新玩法类型 = 扩展 `StageType` 枚举后再在 `special_stages` 引用。核心查询/路由不改。

---

## 3. Changed Files

### 新增（本 Phase）

| 文件 | 说明 |
|---|---|
| `docs/coding-plans/area-stage-progression-coding-plan.md` | **Rev 2**：Phase 2–10 全部改写为 Stage Database 架构（原文档位于 docs 根，已在本 Phase 迁至 coding-plans 目录，见 §7 已知问题 #1） |
| `scripts/data/stage_database.gd` (+`.uid`) | 新增 `StageDatabase`：紧凑每-Area 关卡库 + lookup + validation |
| `resources/stage_databases/forest.tres` | **唯一** Forest 数据资源（AreaData 风格静态文件） |
| `tests/stage_database_smoke_test.gd` (+`.uid`) | Phase 2 最小 smoke test |
| `docs/coding-plans/reports/phase-02-report.md` | 本报告 |

### 修改（仅为路径引用）

| 文件 | 说明 |
|---|---|
| `docs/area-stage-architecture-audit.md` | header 中 coding-plan 路径改指 `docs/coding-plans/…` |
| `docs/coding-plans/reports/area-stage-progression-phase-01-report.md` | 两处 coding-plan 路径引用更新为 Rev 2 位置 |

### 未改动

`scripts/data/stage_type.gd`、`stage_data.gd`、`area_data.gd`（Phase 1）原样；未触碰 battle `StageManager` / `StageDefinition`、`LevelProvider/LevelManager`、`grid_combat`、HUD、WorldMap（不存在）。

---

## 4. Data Strategy

### 为什么没有 one-stage-one-tres

项目目标是 **10,000+ stages**。若每个 Stage 一个 `.tres`，将产生 10K 个文件：Git diff 灾难、编辑不可维护、加载/内存线性膨胀。故 Rev 2 明确：

> **Stage ≠ .tres 文件。** 10,000 stages ≠ 10,000 .tres files。

### 数据格式选择

审计确认仓库数据体系**全部是 Godot Resource**，无 JSON/CSV 加载管线，无磁盘存档。因此采用 **Godot Resource（`.tres`）——每个 Area 一个文件**，理由：

- 类型安全导出 + 编辑器可视化 + 内建 `load()` 资源缓存（一次加载，后续命中缓存，不需要每次进 Stage 重新 parse）。
- 与现有 `resources/enemies / resources/levels / resources/sub_heroes` 约定一致。
- 10K 关的"内容量"由**紧凑规格**承载（`stage_count` + `default_stage_type` + 稀疏 `special_stages`），不是 10K 行。

### 10K 如何扩展

- 新增 1,000 / 10,000 关 = 改一行 `stage_count`；默认规则覆盖绝大多数关。
- 只有异于默认的节点进 `special_stages`（稀疏）；即使万关里只有几百个特殊节点，也是几百行，而非万关万文件。
- **懒物化 + 每号缓存**：`get_stage()` 只在首次访问某关时才构造 `StageData` 并按 `stage_number` 缓存；不会预生成 `stage_count` 个对象。内存上界 ≈ 实际查询过的关数。
- 单次查询对 `special_stages` 做线性扫描（该数组刻意保持稀疏、很小），命中后物化；验证了合成 `stage_count = 10_000` 走同一代码路径。

### 数据落点

`resources/stage_databases/<area_id>.tres`（每 Area 一个）。`StageDatabase.load_area()` 从该约定路径加载；文件缺失时返回 `null`（不报错），因此「未 author 的 Area 查询 = null」是干净路径。

---

## 5. API

`StageDatabase`（`scripts/data/stage_database.gd`，`extends Resource`，`class_name StageDatabase`）：

```gdscript
# 实例查询
db.get_stage(stage_number: int) -> StageData        # 越界(<=0 / >stage_count) 返回 null
db.get_stage_by_id(stage_id: String) -> StageData   # "forest_006" / "forest_6" → stage 6；不属于本 Area / 越界 → null

# 静态（跨 Area）
StageDatabase.load_area(area_id: StringName) -> StageDatabase        # 无文件 → null，不报错
StageDatabase.lookup(area_id, stage_number) -> StageData
StageDatabase.lookup_stage(stage_id) -> StageData                    # "forest_006" → …；未知 → null

# Validation
db.get_validation_errors() -> PackedStringArray
db.is_valid() -> bool
```

**Stage id 规范**：`<area_id>_<补零 stage_number>`，补零宽度 = `max(3, stage_count 位数)`（Forest = `forest_001 … forest_010`）。id 查询对数字后缀**容忍任意补零**（`forest_006` / `forest_6` 都命中 stage 6），未知后缀安全返回 `null`。

返回的 `StageData` 由数据库物化（特殊节点会先 `duplicate()` 再回填 canonical id），调用方/未来 Phase 不会改动 authored 资源。

---

## 6. Tests

执行命令（headless）：

```text
D:/IDE/godotEngine/Godot_v4.7.2-stable_win64_console.exe --headless --import --path <project>   # 注册新全局类 StageDatabase + 导入 forest.tres
D:/IDE/godotEngine/Godot_v4.7.2-stable_win64_console.exe --headless --path <project> -s res://tests/stage_database_smoke_test.gd
D:/IDE/godotEngine/Godot_v4.7.2-stable_win64_console.exe --headless --path <project> -s res://tests/area_stage_data_smoke_test.gd
```

结果：

| 测试 | 结果 |
|---|---|
| `stage_database_smoke_test.gd`（Phase 2） | **PASS**，`StageDatabase / Forest data smoke test passed.`，exit 0 |
| `area_stage_data_smoke_test.gd`（Phase 1 回归） | **PASS**，`Area / Stage data smoke test passed.`，exit 0 |

Phase 2 测试覆盖（Forest）：

- Forest 资源存在（单一 `forest.tres`），`area_id == "forest"`，`stage_count == 10`，`is_valid() == true`；`special_stages` 仅 3 条（06/08/10）。
- `get_stage(1)…get_stage(10)` 全部存在；类型映射 **01–05,07,09=COMBAT / 06=EVENT / 08=TOWN / 10=BOSS**。
- id 查询：`get_stage_by_id("forest_006")==EVENT`、`forest_008==TOWN`、`forest_010==BOSS`；`forest_001==COMBAT`；补零容忍 `forest_6==EVENT`、`forest_1==COMBAT`；canonical id `forest_006`。
- 静态跨 Area：`StageDatabase.lookup("forest",6)==EVENT`、`lookup_stage("forest_008/010")==TOWN/BOSS`。
- 未知安全返回 null：`get_stage(0/11/-3)`、`get_stage_by_id("forest_999999"/"forest_"/"swamp_001")`、`lookup_stage("forest_999999"/"swamp_001")`、`lookup("forest",999)`、`load_area("swamp")`（均 null，且无 load 报错）。
- **合成 10,000 关**（不建文件）：`stage_count=10000` 的 DB `is_valid()`；`get_stage(10000)==COMBAT`；`get_stage(10001)==null`；追加一个 `5000=BOSS` override 后 `get_stage(5000)==BOSS` 且 canonical id `synthetic_05000`（宽度 5）。
- Validation：非法 `default_stage_type`、`special_stages` 重复号、越界号分别被报告。

---

## 7. Known Issues

1. **coding-plan 存在新旧两份（待清理）**：Rev 2 已写入 `docs/coding-plans/area-stage-progression-coding-plan.md`；原 docs 根旧 Rev 1 文件 `docs/area-stage-progression-coding-plan.md` 仍在磁盘（未提交），内容已过时。删除该旧副本需人工确认（权限拦截）。**建议：确认后删除，仅保留 `docs/coding-plans/` 下 Rev 2。**
2. **Stage id 补零宽度与 Phase 1 样例不一致**：Phase 1 测试内的 `AreaData` 样例用 2 位 id（`forest_06`）；StageDatabase canonical id 用 `max(3, …)` 位（`forest_006`）。对 StageDatabase 无影响（查询容忍补零），但 **Phase 3 `PlayerProgress.completed_stages` 的 key 与 Phase 6 展示**需统一到 StageDatabase canonical id，落地时注意。
3. **数据资源目录 `resources/stage_databases/` 为新目录**：不在 CLAUDE.md 目标结构（原写 `resources/stages`）。本 Phase 按"每-Area 一文件"新开目录；若项目偏好其他落点可在 Phase 3 前调整，改动仅目录 + `DATABASE_DIR` 常量。
4. **编辑器未打开验证**：`forest.tres` 经 headless `--import` 与 headless 测试加载通过；未在 Godot 编辑器里可视化打开过（会按需补写 uid 等，属正常）。建议 Phase 3 前在编辑器里开一次确认 inspector 正常。
5. **玩法数据入口仍为泛型占位**：`StageData` 的 `combat_data/event_data/…` 仍为 null；Forest 的 EVENT/TOWN/BOSS 只有类型与显示名，无玩法内容——**有意为之**，内容属 Phase 5+。

---

## 8. Next Phase（Phase 3 — Player Progress）需要知道

- **复用**：`StageData`（查询返回对象）作为"关卡定义"；`StageDatabase.get_stage()/get_stage_by_id()` 提供"是否存在/是否越界"判定；`stage_count` 提供推进边界。
- **建议 API 基线**（来自 Coding Plan Rev 2 Phase 3）：
  ```gdscript
  is_stage_unlocked(area_id, stage_number) -> bool     # n==1 或 n-1 已完成
  is_stage_completed(area_id, stage_number) -> bool
  complete_stage(area_id, stage_number)
  get_current_stage() -> { area_id, stage_number }
  ```
  `completed_stages` 用 StageDatabase canonical id（如 `forest_001`）作 key；**不要**存 Resource 本体。
- **命名**：新类叫 `PlayerProgress`（`scripts/progress/`）；勿与 battle 侧 `PlayerProgression`（含未使用的 `current_stage`）混淆。`PlayerProgress` 全局类名当前空闲，可用。
- **类缓存**：新增含 `class_name` 的脚本后需一次 `--headless --import` 刷新全局类缓存，再 headless 跑测试（沿用本 Phase 命令）。
- **不实现**：Phase 3 只做进度 + 测试，不写存档（Phase 8）、不接 WorldMap。
- **前置清理建议**：落地 Phase 3 前先删除旧 Rev 1 coding-plan（见 §7 #1），避免文档双源。

## 9. 下一 Phase 是否可以开始

**可以。** Rev 2 coding plan 已更新，Forest 数据 + lookup API + 验证全部通过（含合成 10K 规模、未知查询安全返回 null），无 per-stage `.tres`。Phase 3 纯新增 PlayerProgress，不依赖任何现有系统重构。
