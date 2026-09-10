# Area / Stage / StageType 系统 — Phase 1 报告

> 对应 `docs/coding-plans/area-stage-progression-coding-plan.md` 的 **Phase 1 — Core Stage Data Model**（Coding Plan 已于 Phase 2 升级为 Rev 2 / Stage Database 架构）。
> 前置输入：`docs/area-stage-architecture-audit.md`（Phase 0 审计报告）。

---

## 1. 本 Phase 完成内容

建立 Area / Stage 的核心 Resource 数据模型与基本校验，**不触碰任何现有玩法代码**。

- 新增 `scripts/data/` 目录，提供三个静态数据类：
  - `StageType` — 关卡玩法类型目录（enum + 静态校验/显示名）。
  - `StageData` — 单个 Stage 节点的定义。
  - `AreaData` — 一个 Area（含有序 Stage 列表）的定义。
- 加入基本 validation（见 §3），全部落在资源自身方法上，便于无 UI 的 headless 测试。
- 按 Coding Plan 要求提供 **最小测试**（`tests/area_stage_data_smoke_test.gd`，SceneTree 形态可 headless 直跑）。

本阶段严格执行 Coding Plan 的 **NO WorldMap 修改** 约束：项目不存在 WorldMap；也确认**未修改** `grid_combat`、`LevelProvider` / `LevelManager` 等现有系统。

## 2. 修改 / 新增的文件

全部为**新增**，无现有文件被修改（另有 Phase 0 产物 `docs/area-stage-architecture-audit.md` 不属于本 Phase 代码变更）。

| 文件 | 类型 | 说明 |
|---|---|---|
| `scripts/data/stage_type.gd` | 新增 | `StageType`：`COMBAT=0, EVENT, TOWN, BOSS`；`is_valid()`、`get_display_name()` |
| `scripts/data/stage_type.gd.uid` | 自动 | Godot 生成的 UID 侧车文件 |
| `scripts/data/stage_data.gd` | 新增 | `StageData` Resource + 校验 |
| `scripts/data/stage_data.gd.uid` | 自动 | UID 侧车 |
| `scripts/data/area_data.gd` | 新增 | `AreaData` Resource + 跨 stage 校验 |
| `scripts/data/area_data.gd.uid` | 自动 | UID 侧车 |
| `tests/area_stage_data_smoke_test.gd` | 新增 | Phase 1 最小 smoke test |
| `tests/area_stage_data_smoke_test.gd.uid` | 自动 | UID 侧车 |

> 文件命名遵循项目 CLAUDE.md 约定 `snake_case.gd`，而非 Coding Plan 建议的 `PascalCase.gd`（项目内全部脚本均为 snake_case）。

## 3. 架构决策

1. **StageType 作为独立全局类**：`enum { COMBAT, EVENT, TOWN, BOSS }` + 静态 `is_valid()/get_display_name()`。
   - 未来扩展（`ELITE / TREASURE / SHRINE / SECRET`）只需在本文件追加 enum 值；`AreaData` / `StageData` / `PlayerProgress` 均无需改动。
   - 校验采用"display-name 字典即合法集合"的单点来源，避免 reorder 破坏 `is_valid`。
2. **StageData 最小字段 + 预留数据入口**：
   - 必需：`id / stage_number / display_name / stage_type`。
   - 预留：`combat_data / event_data / town_data / boss_data / reward_data / requirement_data` —— **一律为可空泛型 `Resource`**，不创建任何具体 Data 类（遵守"不要提前创建复杂 Data Class"），各玩法 Phase 接线时再挂 typed 资源。
   - `stage_type` 默认值用脚本内 `const StageTypes = preload(...)` 引用，降低对全局类缓存的强依赖。
3. **AreaData 聚合有序 Stage**：`id / display_name / stages: Array[StageData] / background(可选 Texture2D)`。
4. **静态数据与玩家状态严格分离**：`AreaData` / `StageData` **不含** completed / unlocked / player state；只提供 validation，无任何运行时状态写入。PlayerProgress 属于后续 Phase。
5. **Validation 落在资源方法** `get_validation_errors() -> PackedStringArray` + `is_valid()`：
   - Stage：id 非空、`stage_number >= 1`、`stage_type` 合法。
   - Area：id 非空；每个 stage 的校验聚合；`stages` 内 **stage id 唯一**；**stage_number 唯一**；null 项防御。
6. **命名规避冲突（沿用 Phase 0 审计建议）**：本阶段**未新增**任何名为 `StageManager` 的类；现有 battle 引擎 `StageManager` / `StageState` / `StageDefinition`（wave runner）语义保持不变。
7. **类名可用性**：`AreaData / StageData / StageType` 在项目全局类中原本空闲，确认可安全使用。

## 4. 测试结果

- 新增：`tests/area_stage_data_smoke_test.gd`（`extends SceneTree`）。
- 覆盖：
  - StageType：COMBAT=0、BOSS=3 的枚举顺序；4 类型全部 valid；未知类型 999 invalid；EVENT 有显示名。
  - StageData：结构完整 valid；空 id / stage_number=0 / 未知 stage_type 均 invalid。
  - AreaData：合法 Area（含 COMBAT/EVENT/TOWN/BOSS 混合）valid；空 area id invalid；重复 stage id invalid（含"duplicate stage id"提示）；重复 stage_number invalid。
- 执行命令（headless，退出码 0 = 通过）：

```text
D:/IDE/godotEngine/Godot_v4.7.2-stable_win64_console.exe --headless --import --path <project>   # 刷新全局类缓存
D:/IDE/godotEngine/Godot_v4.7.2-stable_win64_console.exe --headless --path <project> -s res://tests/area_stage_data_smoke_test.gd
```

- 结果：`Area / Stage data smoke test passed.`，`test-exit: 0`。headless `--import` 已确认 3 个新全局类（AreaData / StageData / StageType）成功注册。
- 现有玩法代码未改动，`--import` 全程无解析错误，游戏保持可运行。

> 调试记录：测试内首次以 `.call("is_valid", ...)` 调 StageType 静态方法被 GDScript 静态分析拒绝（`Cannot call non-static function "call()" on the class`），已改为直接静态调用 `StageTypeScript.is_valid(...)`（与项目内 `SpecialEncounterTypeResource.get_display_name(...)` 用法一致）。

## 5. 当前已知问题

1. **全局类缓存依赖**：新含 `class_name` 的脚本需一次编辑器/`--import` 扫描才会写入 `.godot/global_script_class_cache.cfg`；在此之前 headless 直接解析含 `Array[StageData]` 等类型引用的文件会失败。Phase 1 已通过一次 `--headless --import` 解决；后续每个新增脚本类后需重复此步。
2. **数据入口为泛型占位**：`StageData` 的 6 个 `*_data` 字段当前为 null（无类型约束），编辑器里呈空 Resource 框；需等各玩法 Phase 赋予具体资源。这是**有意**的，不是缺陷。
3. **UI 尚未消费新模型**：`StageControl` 仍按"连续 stage 数字 + slot1=Stage1 预留 Town"展示；该假设与"Forest 08=Town"等类型化 Stage 不一致（详见 Phase 0 审计 §4.5），需在 Phase 6 地图化时一并处理。当前不阻塞。
4. 工作区存在 Phase 0 之前遗留的未提交 `header_row.tscn/.gd` 改动（删除 header 内 stage 标签的展示迁移），与新模型无关，仅提示工作区非干净。

## 6. 下一 Phase（Phase 2 — Create Forest Stage Data）需要知道的信息

- **类名可用**：`AreaData / StageData / StageType` 已注册全局类，可在 `.tres` / 代码中直接引用。
- **校验 API**：`StageData.get_validation_errors()` / `AreaData.get_validation_errors()` 可用作数据落地后的验证入口。
- **建议的 Forest 结构**：
  - `01-05, 07, 09 = COMBAT`；`06 = EVENT`；`08 = TOWN`；`10 = BOSS`。
- **资源形态待选（审计建议二选一，按项目"一个实体一个 .tres"风格，倾向分离文件）**：
  1. `AreaData forest.tres`（inline `Array[StageData]`）——节点少、单文件易维护；
  2. `data/areas/forest.tres` + `data/stages/forest_01..10.tres`——与 `resources/levels/*.tres` 一文件一实体风格一致，便于后续复用现有 `LevelConfig` / `LevelProvider`（每个 StageData 将来可桥接 `level_id`）。
- **注意 typed `Array[StageData]` 的 `.tres` 写法**：元素需带 `StageData` 脚本引用（`[ext_resource type="Script" ...]`），或直接用 inline `sub_resource`；建完后用 `AreaData.get_validation_errors()` 验证，并跑 headless smoke test。
- **别名碰撞**：确认不要新建 `StageManager` 名（已被 battle engine 占用）。Phase 2 不需要管理器，仅数据 + 验证。
- **文档源**：Forest 结构规范见 `docs/coding-plans/area-stage-progression-coding-plan.md`（Rev 2）的 Phase 2；新增/重写数据前先 Read 该 Phase。
- **建议在改动前**先运行一次 `--headless --import`（若新增脚本/类型），保证类缓存与 `--import` 输出无解析错误；所有改动应保持现游戏可运行（不触碰 `grid_combat` / HUD）。

## 7. 下一 Phase 是否可以开始

**可以。** 前置审计（Phase 0）已完成，核心数据模型（Phase 1）已建立并通过最小测试，命名决策已落地（未占用 `StageManager`，新类名注册成功）。Phase 2 为纯数据创建 + 验证，风险低，且不依赖任何管理器重构。
