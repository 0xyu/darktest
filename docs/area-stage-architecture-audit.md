# Area / Stage / StageType 系统 — Phase 0 Repository Audit

> 对应 `docs/coding-plans/area-stage-progression-coding-plan.md` 的 **Phase 0**。
> 本阶段 **NO CODE CHANGES**，只做仓库审计并输出本报告。

审计基准 commit：`a63316f`（另有未提交 WIP：`header_row.tscn/.gd` 删除 header 内的 stage 标签，仅 UI 展示迁移，见 §4.6）。

---

## 0. 结论摘要（TL;DR）

- 当前游戏是 **单一场景、无限线性、纯战斗数值推进**：`Main.tscn` → `grid_combat.tscn`，一个 11×7 横向竞技场，Stage = 从 1 开始的连续整数，清场后走到右端出口进下一关。
- **不存在** `Area` / `WorldMap` / `StageType` / 离散"地图关卡节点"概念（全仓库 grep 无 `AreaData`、`WorldMap`、`StageType`）。
- 现有一个**同名但语义完全不同**的 `StageManager`（`scripts/systems/stage_manager.gd`），职责是**单场战斗内的敌人刷新/波次推进**，不是"进入哪种玩法场景"的分发器 → 这是与计划最关键的冲突点，必须在 Phase 1 敲定命名/职责方案。
- Town 目前是 **DEV stub**：一个挂在 HUD 里的 `TownView`（`scenes/ui/TownView.tscn`），由 `DevelopmentPanel.open_town()` 发出 `town_view_requested`，但**全工程无任何接收方连接该信号** → 实际不可达。
- **没有任何磁盘存档**。`PlayerProgression`（Resource）有 `current_stage` 字段但**从未被写入**；只有内存态。
- **没有任何 gameplay autoload / singleton / 场景切换基础设施**，不能"复用第二套 SceneManager"（因为根本不存在第一套）。
- 有一个成熟、可直接复用的 **Level → StageDefinition → StageManager(battle) 数据管线** 和 **YARD Registry → EnemyData** 资源体系，后续离散 Stage 的战斗内容应挂在它上面，而不是另起炉灶。

---

## 1. 当前架构

### 1.1 场景层级（入口 → 唯一玩法场景）

`project.godot`：
- `run/main_scene = "res://scenes/world/Main.tscn"`
- autoload 只有 `_mcp_game_helper`（`addons/godot_ai/runtime/game_helper.gd`，MCP 测试用）。**无游戏逻辑 autoload**。

`scenes/world/Main.tscn` 极简：一个 `Node2D(Main)` 只实例化一个 `grid_combat.tscn`。

`scenes/world/grid_combat.tscn`（真正的"整个世界/玩法"）节点树：

```text
grid_combat (Node2D, scripts/world/grid_combat.gd)
├── CombatCamera (Camera2D)
├── DungeonBackground (Sprite2D)
├── Grid (Node2D)  → GridMap2D：grid_size 11×7, cell_size 65
├── Player (Player.tscn → PlayerController)
├── TurnManager
├── CombatSystem
├── LevelManager
│   └── LevelProvider（enemy_registry = res://resources/enemies/enemy_registry.tres）
├── StageManager
├── ExperienceSystem
├── MobileCombatHUD (CanvasLayer, scenes/ui/MobileCombatHUD.tscn)
├── GoldSystem
├── LootSystem
├── AutoCombatController
├── SubHeroCombatManager
└── CombatPresentation
```

### 1.2 游戏循环（无"地图 → 关卡"分层）

`grid_combat.gd::_ready()` 直接 `stage_manager.initialize_stage(1)` 开始战斗：

```text
启动 → 竞技场 Stage N（左侧出生点入场）
 → 玩家移动/攻击（move + 1 action per turn）
 → 清光敌人 → StageState.is_complete = true
 → 走到右端"Next Stage Point"（或 AUTO/FARMING 自动）→ start_next_stage()
 → 死亡 → 回到上一 stage（start_previous_stage）
```

- Stage 数字即难度来源：敌人按 stage 缩放（`EnemyScaling` + 成长率）。
- 每 `stage % 10 == 0` = mini boss；随机特殊遭遇（`SpecialEncounterType`：ELITE/TREASURE_MONSTER/RANDOM_MINI_BOSS/GOLD_MONSTER/CURSED_MONSTER…）**全部仍是战斗形态**，不是独立 Event 玩法。
- AUTO / FARMING / 倍速都在同一场景内，由 `AutoCombatController` 驱动。

### 1.3 关卡数据管线（可复用的核心资产）

```text
StageManager(battle) ──request_level(stage_number)──> LevelManager
                                                          │
                                                          ▼
                                                      LevelProvider
                                       ┌───────────────────┴──────────────────┐
                              fixed LevelConfig (.tres)              程序化生成
                              resources/levels/                         (seed = level_id)
                              level_001/002/010/100                     LevelTemplate + enemy_pool
                                       │                                  （特殊遭遇/成长率）
                                       └──────────► StageDefinition ◄────────┘
                                                          │
                                                          ▼
                                            StageManager 生成敌人、管理门点
```

关键类（均已存在）：
- `StageDefinition`（`systems/stage_definition.gd`）— 单 stage 战斗定义：`stage_number / level_id / template_id / display_name / difficulty_multiplier / enemy_entries / boss / is_mini_boss_stage / special_*`。
- `StageEnemyEntry`（`stage_enemy_entry.gd`）— 敌人数/等级/出生规则/属性倍率。
- `LevelConfig`（`level_config.gd`）— 作者手写的固定关卡 `.tres`，`to_stage_definition()` 转成 `StageDefinition`。
- `LevelProvider`（`level_provider.gd`）— 固定资源短路（`has_fixed_level`），否则按 `LevelTemplate` + 每 level seed 程序化生成；mini boss `%10`、特殊遭遇概率成长、`special_encounter_chance` 状态。
- `LevelManager`（`level_manager.gd`）— LevelProvider 的薄封装 + 成长率 getter。
- YARD `Registry`（`addons/yard/registry.gd`）→ `resources/enemies/enemy_registry.tres` 扫描 `resources/enemies/generated/` 收集 `EnemyData`，供随机池使用。

### 1.4 玩家状态与存档

- 玩家 = `Player.tscn`（`PlayerController`），持有：`PlayerStats`、`PlayerProgression`、`EquipmentInventory`、`StorageInventory`、Sub Hero 进度服务等 **Resource**。
- `PlayerProgression`（`player_progression.gd`）：`level / experience / gold / current_stage / skill_points / skill_levels`。注意 **`current_stage` 从未被赋值**（仅导出默认值 1），实际"当前关"只存在于 `StageState` 运行时。
- **无磁盘存档**：无 `user://`、无 `ConfigFile`、无 autoload 状态仓库。Sub Hero 有 `to_save_data()/load_save_data()`（内存序列化 API，为未来存档准备的形状），但没有落盘。`DevelopmentPanel` / `UIFixture` 也只做内存注入。
- 结论：重启游戏 = 重新从 Stage 1 开始；"我推进到第几 Area/Stage" 的概念目前不存在、也不可持久化。

### 1.5 HUD / 面板结构（Town 现在住在这里）

`scenes/ui/MobileCombatHUD.tscn`（CanvasLayer，挂在 grid_combat 下）：

```text
MobileCombatHUD (CanvasLayer)
└── Root
    ├── SafeArea
    │   └── MainContent (VBox)
    │       ├── ViewContainer
    │       │   ├── TownView          ← 占位城镇视图（默认隐藏）
    │       │   └── CombatView
    │       │       ├── TopPanel → Header(header_row)
    │       │       ├── CombatSection (EnemySummaryPanel / CombatActions)
    │       │       ├── SubHeroRow / CombatLogPanel
    │       │       ├── BottomPanel (Shop / Skills / Bestiary / Dev / Speed)
    │       │       └── StageControl   ← 6 格 stage 数字条
    │       │   └── SkillPanel
    │       └── MainNavigation         ← 底部导航条(Character/Inventory/Shop)
    ├── DevelopmentPanel / SubHeroShopPanel / InventoryPanel / EnemyBestiaryPanel
    ├── SubHeroAssignmentPanel / LootPresentation / StateBanner …
```

- `TownView`（`scripts/ui/town_view.gd`，代码构建 UI）：标题 TOWN + "仓库"（`warehouse_requested`）/ "技能导师"（`skills_requested`）两个设施卡片 + 关闭（`close_requested`）。
- TownView 文档注释明言：由 `DevelopmentPanel.open_town() → town_view_requested` 让 HUD 用 TownView 替换 CombatView。
- **但 grep 全工程：`town_view_requested` 只有声明与 emit，没有任何 `.connect` 接收方**；`warehouse_requested/skills_requested` 同理 → Town 目前是**未接线的 stub**，DEV 面板里点城镇并不会真的切换视图。`git log` `a0fa671 town view` 印证其为近期新增的半成品。
- `StageControl`（`stage_control.gd`）读取 `StageManager.stage_started`，6 个 slot 显示连续 stage 数字；slot 1 固定为 Stage 1，代码注释：*"Slot 1 is fixed to Stage 1 (reserved for a future 'Town Stage')"，`TOWN_STAGE := 1`* → 现有 UI 已为"未来把某个槽位当 Town"预留假设，但该假设是"Town 在 1 号槽"，与计划的 "Forest Stage 08 = Town" 不一致（见 §4.5）。

### 1.6 测试 / 工具

- `res://tests/`：`fixtures/ui_fixture.gd`、`test_ui_fixture.gd` + 一批 Sub Hero / Skill smoke test；另有 `res://tests/` 需编辑器重启才识别新套件（见项目记忆），headless 用 `McpTestRunner`。
- 文档：`docs/testing-fixtures.md`、`docs/ui-harness.md`；`res://tools/ui_harness/` 供 headless UI 校验。
- 当前 **没有** stage/level 系统的专门测试（老的 smoke test 归档在 `archive/mvp/smoke_tests/`）。
- MCP 运行期帮助 `_mcp_game_helper` + `addons/godot_ai` 提供 `project_run / game_manage / game_eval / editor_screenshot` 等运行时验证手段。

---

## 2. 七个重点问题的回答

1. **当前 World 如何组织？**
   没有 World 概念。`Main.tscn` 只有一个 `grid_combat` 实例；"世界" = 一张 11×7 竞技场 + 一堆 overlay UI。不存在地图/Area/多场景分层。最近 commit（`5a01c95` "stage start cell from left to next stage cell right"）将关卡表达为竞技场左右两端的**门点**而非地图节点。

2. **Combat Scene 如何进入？**
   没有"进入"动作 —— 游戏启动即 main scene 就是战斗。后续 stage 由清场后走到右出口触发 `StageManager.start_next_stage()`；AUTO/FARMING 在同一场景内循环。全工程**无 `change_scene*` 调用**，也无场景切换管理器。

3. **Town Scene 如何进入？**
   目前**没有正式入口**。Town = HUD `ViewContainer` 里的一个 View（`TownView.tscn`），设计入口是 DEV 面板 `open_town()` → `town_view_requested`（未接线）。仓库/技能导师设施请求也未接线 → Town 是 stub。计划中"Forest 08 = Town 并可从 Stage 进入"的流程当前完全不存在。

4. **是否已经存在 Stage / Level 概念？**
   **部分存在，但语义不同。**
   - 已有（战斗层）：`StageManager / StageState / StageDefinition / StageEnemyEntry`、`LevelManager / LevelProvider / LevelConfig / LevelTemplate`、`StageControl`(UI)、`SpecialEncounterType`、固定 `.tres`（`level_001/002/010/100`）。
   - 不存在（地图层）：`Area`、离散关卡节点、`StageType(COMBAT/EVENT/TOWN/BOSS)`、WorldMap。现有 `StageManager` 的"stage"是 **int（battle index / 难度档位）**，不是计划中的"地图上某个可进入的玩法节点"。

5. **是否已经存在 Save / PlayerProgress？**
   **没有落盘存档。** `PlayerProgression`（Resource）字段齐全但纯内存；`current_stage` 未使用。Sub Hero 有序列化 API 形状。没有全局 GameManager/autoload 承载进度，没有 `current_area_id/current_stage_id/completed_stages` 概念。

6. **哪些 Singleton / Autoload 可以复用？**
   **没有可复用的 gameplay singleton。** 唯一 autoload 是 MCP 测试 helper。也不存在 SceneManager / GameManager / NavigationManager / SaveManager。计划的 Phase 4 "不要重新创建第二套" 实际意味着需要**新建第一套**，届时须决定：autoload（符合但违反项目"避免不必要 autoload"规则，需克制）vs 最外层场景持有并注入（推荐，见 §5）。跨系统解耦现在全靠**场景树内 signal**，这本身就是项目既有模式，应延续。

7. **哪些现有代码会与新 Area/Stage 系统冲突？**
   详见 §4。最关键三点：(a) 同名 `StageManager` 语义冲突；(b) 现有 "stage=连续数字" 的整套难度/生成逻辑与"离散类型化节点"之间需要桥接；(c) 单一场景 + 无存档 + 无入口分层，与"WorldMap → Stage → 玩法"所需的外壳/返回/持久化流程之间存在结构性缺口。

---

## 3. 可复用系统（Phase 1+ 应尽量挂靠）

| 系统 | 位置 | 可复用处 |
|---|---|---|
| Level→StageDefinition 管线 | `level_manager.gd` / `level_provider.gd` / `level_config.gd` | 离散 COMBAT/BOSS Stage 的"战斗内容"直接引用 `level_id`，复用 `request_level()`，无需另存敌人组成 |
| 固定关卡资源 | `resources/levels/*.tres`（LevelConfig） | 手写关卡已有短路机制（不走 `%10` boss / 随机遭遇），正适合承载作者化 Forest 关卡 |
| 战斗 Stage 引擎 | `stage_manager.gd` / `stage_state.gd` / `stage_enemy_entry.gd` | COMBAT/BOSS 进入后照旧用它刷怪、管门点、判胜利、farming/auto、死亡回退 |
| 敌人数据/随机池 | `resources/enemies/enemy_registry.tres`(YARD) + `generated/` + EnemyData | 敌方数据来源，勿迁移 |
| Town 占位视图 + ViewContainer 切换先例 | `town_view.gd` / `MobileCombatHUD.tscn` | "进入某玩法 = 同场景切 View"的现成先例（CombatView↔TownView），规避多场景切换缺失问题 |
| 文案 | `systems/game_locale.gd`（en / zh_Hant） | Town/Event/Stage 显示文案走它 |
| 测试基建 | `tests/`、`fixtures/ui_fixture.gd`、`tools/ui_harness/`、MCP `_mcp_game_helper`、`McpTestRunner` | Phase 1+ 最小测试沿用此形态（headless 优先） |
| 序列化形状 | sub-hero `to_save_data()/load_save_data()` | Phase 8 落盘只存 identifier 的风格可参照 |

---

## 4. 冲突点与建议（本阶段不改代码）

### 4.1 类名冲突：`StageManager`
现有 `StageManager`（战斗刷怪）是全局 `class_name`。计划"Phase 4 StageManager = 进入哪种玩法的分发器"若同名新建会**类名重复 → 解析错误**。
- **建议**：Phase 1/4 决定 —— 优先**不抢占现名**：分发器另取 `StageRouter` / `AreaStageDirector` 等；现有 `StageManager` 保持"战斗引擎"不动。这样最小侵入、最符合"复用现有系统"。
- 好消息：计划的 `AreaData / StageData / StageType` 三个名字当前**均未被占用**，可直接用。

### 4.2 "Stage"语义冲突（最重要设计问题）
现有世界把 Stage 当连续 int：`stage_number` 驱动难度缩放、`%10` boss、每关 seed、门点推进、farming、死亡回退；`StageControl` 也画连续数字窗口。
计划的 Stage 是离散、作者化、带类型的节点（Forest 01–10，06 Event / 08 Town / 10 Boss）。
- **建议**：把两层桥接起来 —— `AreaData.stages[]` 的每个 `StageData`（含顺序号）只是一个**地图/进度节点**；当它实际进 COMBAT/BOSS 时，映射到一个底层 `LevelConfig` / level_id，继续走现管线。即 **Map-Stage ≠ Battle-Stage**，两者用映射连接，避免重写难度系统。
- 若让"Forest 10 个 Stage 数字"直接当作现有关卡号使用，会撞上现有 `%10 mini boss`、随机遭遇、seed 生成逻辑 → 需要为每个节点提供固定 authored 内容短路它们。

### 4.3 单一场景 vs 多场景 / 没有 scene transition
无 `change_scene`、无外壳层、boot 即开战。
- **建议**：保持单场景思路 —— 引入一个最外层"进度外壳"场景（或在 Main 上扩展）持有 `WorldMap View + grid_combat`；"进入 Town/Event/回地图"都做成 View 切换（复用 ViewContainer 模式），不新建场景栈。这样不需要造场景切换管理器，也符合项目避免不必要抽象/依赖的规则。
- 风险提示：若计划坚持独立 GameplayScene（TownScene/BossScene…），需额外引入场景过渡基建 —— 属大改，Phase 5 前应确认。

### 4.4 无进度 / 无存档导致缺少"当前在哪"
当前 run 永远从 Stage 1 开始、状态全内存。
- **建议**：新系统需要 `PlayerProgress`（`current_area_id / current_stage_id / completed_stages`）作为独立 Resource，由外壳场景持有并注入；`StageData/AreaData` 保持静态不可变（写对，plan 已强调）。Phase 8 再落盘。

### 4.5 `StageControl` / `Stage 1 = Town` 假设
`stage_control.gd` 已把 slot 1 固定为 Stage 1 并预留"未来 Town Stage"。这与计划"Forest 08 = Town"（Town 不是 1 号槽、Forest 01 是 Combat）冲突，也与连续数字 UI 绑定。
- **建议**：Phase 6 改地图后重做该条（读 `StageType` 显示 icon：Combat/Event/Town/Boss），而不是继续"数字窗口 + 保留 1 号槽"。规划时把 `TOWN_STAGE := 1` 常量列入清理项。

### 4.6 未提交 WIP
`scenes/ui/header_row.tscn` + `scripts/ui/header_row.gd` 未提交改动 = 把 header 里的 stage 标签删掉（展示迁移到 `stage_control` 条）。纯 UI 展示迁移，**与新系统不冲突**，仅提示工作区非干净、后续实施前建议先提交。

### 4.7 其他易被新代码踩到的点
- `PlayerProgression.current_stage` 未使用，且与新 `PlayerProgress.current_stage_id` 名字相近易混 → 建议后续删除或改名，避免两套"当前关"并存。
- 别把完成态（completed/unlocked）写进 `StageData`（静态数据）—— plan 原则正确，审计确认现 `LevelConfig/EnemyData` 也都是纯静态资源，风格一致。
- `LevelProvider` 的随机遭遇概率是**有状态**的（`special_encounter_chance` 在 instance 内递增/归零），未来接入多个 Area 时注意作用域。

---

## 5. 风险清单

1. **改动面（最大）**：把"stage"从连续 int 重组为 Area/Stage 节点会触及当前核心循环（难度、生成、推进、farming/auto、死亡回退）。任何阶段都要**保持游戏可运行**（CLAUDE.md 硬性要求），建议按"新增数据层 + 映射"增量落地，而非重写 StageManager。
2. **类名冲突**：新增全局 `class_name StageManager/StageDefinition/…` 与现有重名会直接报错 → 命名方案在写任何代码前定死。
3. **多场景冲动**：一旦开始造独立 GameplayScene 会引入场景栈/状态传递/进度恢复的连锁工作。倾向 View 级切换降低风险。
4. **无存档基础**：离散进度一旦上线，"从存档恢复"才成为刚需；Phase 8 前进度都在内存，重开归零属于预期，但 UI/测试要知情。
5. **程序化生成短路缺失**：作者化 Forest 关卡必须能跳过 `%10 boss` / 随机遭遇 / seed 规则；现 `has_fixed_level` 短路已具备，但需为每个类型化 Stage 校验内容来源不为空。
6. **Event/Elite/Treasure 等类型尚无对应玩法**：`SpecialEncounterType` 全是战斗变体；计划的 EVENT 玩法完全空白。Phase 1–2 只做类型定义与数据，不要提前实现 EVENT 内容（避免 speculative，符合 CLAUDE.md）。

---

## 6. 对下一 Phase（Phase 1 — Core Stage Data Model）的实施建议

1. **命名**：新增 `scripts/data/`（或遵循现 `scripts/systems/` 结构，项目现无 `data/` 目录，需新建）下 `AreaData.gd`、`StageData.gd`、`StageType.gd`；`StageData` / `StageType` / `AreaData` 名字可用。**不要**新建名为 `StageManager` 的类。
2. **StageType**：`enum { COMBAT, EVENT, TOWN, BOSS }` 起步，注释预留 `ELITE / TREASURE / SHRINE / SECRET`。
3. **StageData 最小字段**：`id / stage_number / display_name / stage_type` + 未来数据入口（`combat_data/event_data/…` 可先不建，plan 已同意不为未来建复杂类）。可加 `level_id`（桥接现 `LevelProvider`）。
4. **AreaData**：`id / display_name / stages: Array[StageData] / background`。**不含** completed/unlocked/player state。
5. **Validation**：id 非空、stage_number>0、stage_type 合法、area 内 id/序号不重复 —— 用简单方法 + 最小测试（放 `res://tests/`，headless `McpTestRunner` 跑，遵循 `testing-fixtures.md` 风格），不连 UI。
6. **范围**：不修改 WorldMap（不存在）、不动 `grid_combat`、不动 `LevelProvider/LevelManager` 行为；保持现游戏可运行。
7. 先提交当前 `header_row` WIP，再开始 Phase 1。

**结论：Phase 1 可以安全开始。** 现有战斗/关卡/资源/测试基础设施都齐备且可复用；只要守住"不重名、不改现有 stage 引擎语义、不做多场景、不实现 EVENT 内容"四点，Phase 1（纯数据模型 + 校验测试）不会与现状冲突。
