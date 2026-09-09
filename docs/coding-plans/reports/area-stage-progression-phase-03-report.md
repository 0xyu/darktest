# Area / Stage / StageType 系统 — Phase 3 报告（Player Progress + 命名清理）

> 对应 `docs/coding-plans/area-stage-progression-coding-plan.md`（**Rev 2**）的 **Phase 3 — Player Progress**。
> 前置输入：Phase 2 报告（`area-stage-progression-phase-02-report.md`）。

---

## 1. 本 Phase 完成内容

本 Phase 做两件事：

**Task A — 清理 battle 侧 `PlayerProgression.current_stage` 死字段**
- 删除 `scripts/player/player_progression.gd` 的 `@export current_stage`（从未被任何玩法代码读取/写入的死字段；战斗 HUD 阶段条 `StageControl` 读的是 battle `StageState`）。
- 同步移除 UI fixture / 测试对该字段的读写：`UIFixture.create_player_progression / create_character` 去掉 `stage` 形参，`test_ui_fixture` 去掉对应断言，`test_development_panel` 调用改两参，`docs/testing-fixtures.md` 签名更新。
- 目的：消除「两套 current stage」语义撞车（plan「命名注意」）。类名 `PlayerProgression` 保留（现为纯角色数值成长：level/exp/gold/skills）。

**Task B — 实现 Rev 2 的 Phase 3（PlayerProgress）**
- 新增 `scripts/progress/player_progress.gd`（`class_name PlayerProgress extends Resource`）：玩家**地图/关卡进度**的唯一持有者，与静态 `AreaData / StageData / StageDatabase` 完全分离。
- 字段：`current_area_id` / `current_stage_number`（当前位置，Phase 4+ 路由才消费）/ `completed_stages`（`Dictionary`，key 为 StageDatabase canonical stage id 字符串）。
- API：`is_stage_unlocked(area_id, stage_number)`、`is_stage_completed(area_id, stage_number)`、`complete_stage(area_id, stage_number) -> bool`、`get_current_stage() -> { area_id, stage_number }`。
- 解锁规则：`stage 1 of an authored area 始终开放`；`n` 开放 ⇔ `n-1` 已完成；不存在/越界/未 author 的 stage 一律不开放、不可完成。
- **不实现**：存档（Phase 8）、WorldMap/UI 接线、`current` 推进流程（Phase 7）——均留后续 Phase。

---

## 2. 修改 / 新增的文件

### 新增

| 文件 | 说明 |
|---|---|
| `scripts/progress/player_progress.gd` (+`.uid`) | 新 `PlayerProgress`：地图/关卡进度 Resource（全局类名，Phase 3 前空闲已确认） |
| `tests/player_progress_smoke_test.gd` (+`.uid`) | Phase 3 最小 smoke test（SceneTree headless，沿用 Phase 1/2 风格） |
| `docs/coding-plans/reports/area-stage-progression-phase-03-report.md` | 本报告 |

### 修改

| 文件 | 说明 |
|---|---|
| `scripts/player/player_progression.gd` | 删 `current_stage` 字段；类注释澄清职责（角色成长；地图位置归 PlayerProgress） |
| `tests/fixtures/ui_fixture.gd` | `create_player_progression(level, gold)` / `create_character(level, gold)` 去 stage 形参 + 内部赋值 + docstring |
| `tests/test_ui_fixture.gd` | `create_character(15, 999)`；删 `current_stage == 7` 断言 |
| `tools/ui_harness/suites/test_development_panel.gd` | `create_player_progression(1, 0)`（两参） |
| `docs/testing-fixtures.md` | 更新两处 fixture 签名 |
| `docs/coding-plans/area-stage-progression-coding-plan.md` | Phase 2/3 标记完成；「命名注意」改为已清理；Execution Order 前移 Phase 5 |

---

## 3. 架构决策

### 3.1 进度只存 identifier，不存 Resource

`completed_stages` 的 key = `StageDatabase` 生成的 **canonical stage id**（如 `forest_006`），由 `StageDatabase.lookup(area, n).id` 取得——单一 id 来源，Phase 8 落盘与 Phase 6 展示复用同一口径（对齐 Phase 2 §5 #2 的提醒）。绝不序列化 Resource 本体。

### 3.2 解锁/完成边界读取 StageDatabase.stage_count

- `_area_has_stage()`：`StageDatabase.load_area(area_id)`，`n ∈ [1, stage_count]` 才存在。避免本类复制每-Area 计数，也防止「完成了 boss 后 stage_count+1 也被误判开放」。
- `complete_stage()` 对不存在/越界/未 author 的 area 返回 `false` 且不落任何记录（干净失败路径，与 Phase 2「未知查询=null」风格一致）。

### 3.3 `current` 是独立指针，不由 completed 推导

`current_area_id / current_stage_number` 仅表示「玩家现在站在哪」；推进/回退属 Phase 7 flow，本 Phase 不自动改它。`get_current_stage()` 为只读访问器（`{ area_id, stage_number }`）。

### 3.4 命名：`PlayerProgress`（地图）vs `PlayerProgression`（角色成长）

混淆源 `current_stage` 已移除，两类的「一字之差」不再伴随功能撞车。长期若需更强区分，另行独立 `refactor:` commit 改名 `CharacterProgression`，不混入 gameplay Phase。

---

## 4. 测试结果

执行命令（headless）：

```text
D:/IDE/godotEngine/Godot_v4.7.2-stable_win64_console.exe --headless --import --path <project>   # 注册新全局类 PlayerProgress + 生成 .uid
D:/IDE/godotEngine/Godot_v4.7.2-stable_win64_console.exe --headless --path <project> -s res://tests/player_progress_smoke_test.gd
D:/IDE/godotEngine/Godot_v4.7.2-stable_win64_console.exe --headless --path <project> -s res://tests/area_stage_data_smoke_test.gd   # Phase 1 回归
D:/IDE/godotEngine/Godot_v4.7.2-stable_win64_console.exe --headless --path <project> -s res://tests/stage_database_smoke_test.gd   # Phase 2 回归
# McpTestSuite-based ui_fixture suite（清理后）：headless driver 调 McpTestRunner.run_suites
D:/IDE/godotEngine/Godot_v4.7.2-stable_win64_console.exe --headless --path <project> -e --quit   # 全项目脚本 parse 校验
```

| 测试 | 结果 |
|---|---|
| `player_progress_smoke_test.gd`（Phase 3，新增） | **PASS**，`PlayerProgress smoke test passed.`，exit 0 |
| `area_stage_data_smoke_test.gd`（Phase 1 回归） | **PASS**，exit 0 |
| `stage_database_smoke_test.gd`（Phase 2 回归） | **PASS**，exit 0 |
| `test_ui_fixture.gd`（McpTestSuite，`current_stage` 清理影响面） | **PASS**，passed=13 failed=0 skipped=0 |
| `--editor --quit`（全项目 parse） | 无 SCRIPT / Parse Error，exit 0 |

覆盖要点：

- 新进度：`forest` 01 开放、02..10 锁定、0/11 永不开放、未 author 的 `swamp` 01 不开放。
- 链式推进：完成 1..5 → 06 开放（EVENT 型）但 10 仍锁；越级完成 6 只开 7、不开 8（线性，无跳跃）；完成全 10 关后不存在 11。
- `complete_stage` 拒绝 0 / 11 / -3 / `swamp`，且拒绝路径零写入。
- `completed_stages` key 均为 String canonical id（`forest_006`），非 Resource。
- `get_current_stage()` 空默认 + 手动 set 后如实返回。

---

## 5. 当前已知问题

1. `PlayerProgress` 尚无持有者/autoload：仅数据 + 测试；`current_area_id` 默认为空，需 Phase 4+ 进入关卡后接线（预期内）。
2. `create_player_progression / create_character` 签名变更（去 `stage` 参）：已全量同步 `.gd` 与 `docs/testing-fixtures.md`；`tools/ui_harness/suites/test_development_panel.gd` 等场景类套件未跑（需编辑器/场景），已通过 `--editor --quit` parse 校验。
3. 跨 Area 解锁（如「通关 A 的 boss 才开放 B」）不在本 Phase 线性规则内——属 Phase 9 多 Area 讨论，届时再扩展 `is_area_unlocked` 或等价物。

---

## 6. 下一 Phase（Phase 4 — StageRouter）需要知道的信息

- **复用**：`StageDatabase.lookup(area, n) / load_area / stage_count`（边界）；`StageData.stage_type`（路由依据）；`PlayerProgress.is_stage_unlocked / get_current_stage`（进入资格与位置）。
- **Phase 3 结论**：静态数据与玩家进度已彻底分离；canonical id 口径统一（`forest_006`）。StageRouter 只读 `StageData.stage_type` 分发，**禁止** `if stage_number == 6` 硬编码；场景切换优先复用现有 `ViewContainer` 同场景 View 切换。
- **命名**：分发器叫 `StageRouter`，**不叫** `StageManager`（battle 刷怪引擎已占用）。
- **不实现**：Phase 4 只做路由壳 + `Forest 01/06/08/10` 走通（Event 可占位），不接 Town/Combat 玩法内容（Phase 5）。

---

## 7. 下一 Phase 是否可以开始

**可以。** `PlayerProgress` 完成且与静态数据分离；`current_stage` 死字段清理无回归（13/13 + Phase 1/2 回归 + 全项目 parse 均绿）。Phase 4 为纯新增 StageRouter，不依赖现有系统重构。
