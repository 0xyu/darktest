# Godot Area → Stage → StageType 关卡系统

## 总目标

建立可扩展的：

```text
Area
  ↓
Stage
  ↓
StageType
  ↓
StageManager
  ↓
Gameplay Scene
```

系统。

示例：

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

* Area 和 Stage 使用 Data/Resource 定义
* Stage 不与具体玩法 Scene 强耦合
* StageType 决定玩法类型
* StageManager 负责 Stage → Gameplay Scene
* PlayerProgress 独立保存玩家进度
* WorldMap 根据 Area/Stage Data 自动生成节点
* 不使用大量 `if stage == 6` / `if stage == 10`
* 后续可以轻松增加 Event / Elite / Treasure / Shrine / Secret 等 StageType
* 不破坏现有 Combat / Town / HUD 系统

---

# Phase 0 — Repository Audit

## 目标

先理解现有项目，不修改代码。

## Agent Task

检查：

```text
project.godot

现有 World / Map Scene
现有 Combat Scene
现有 Town Scene
现有 Event Scene（如果存在）
现有 GameManager / Autoload
现有 Save / Progress 系统
现有 Resource / Data 架构
现有 Stage / Level 相关代码
```

重点回答：

1. 当前 World 是如何组织的？
2. Combat Scene 是如何进入的？
3. Town Scene 是如何进入的？
4. 是否已经存在 Stage / Level 概念？
5. 是否已经存在 Save / PlayerProgress？
6. 哪些 Singleton / Autoload 可以复用？
7. 哪些现有代码会与新 Area/Stage 系统冲突？

## 严格要求

本 Phase：

```text
NO CODE CHANGES
```

只输出 audit report。

## Output

生成：

```text
docs/area-stage-architecture-audit.md
```

内容包括：

* 当前架构
* 可复用系统
* 冲突点
* 建议修改点
* 风险
* 下一 Phase 的实施建议

---

# Phase 1 — Core Stage Data Model

## 目标

建立 Area / Stage 的核心 Resource。

## 新增

建议：

```text
scripts/data/AreaData.gd
scripts/data/StageData.gd
scripts/data/StageType.gd
```

如果项目已有 data folder，则遵循现有结构。

## StageType

至少支持：

```text
COMBAT
EVENT
TOWN
BOSS
```

设计成未来可以扩展：

```text
ELITE
TREASURE
SHRINE
SECRET
```

而不需要修改 AreaData。

## StageData

至少包含：

```text
id
stage_number
display_name
stage_type
```

以及未来需要的数据入口：

```text
combat_data
event_data
town_data
boss_data
reward_data
requirement_data
```

不要为了当前功能提前创建复杂的所有 Data Class。

## AreaData

至少包含：

```text
id
display_name
stages
background
```

其中：

```text
stages: Array[StageData]
```

## 重要原则

不要保存：

```text
completed
unlocked
player state
```

这些属于 PlayerProgress。

## Validation

加入基本 validation：

* stage id 不为空
* stage number > 0
* stage type 有效
* Area 不允许重复 stage id
* Stage number 不应该重复

## Output

代码 + 最小测试。

不要修改 WorldMap。

---

# Phase 2 — Create Forest Stage Data

## 目标

创建第一个实际 Area：

```text
Forest
```

建立：

```text
Forest
├── 01 Combat
├── 02 Combat
├── 03 Combat
├── 04 Combat
├── 05 Combat
├── 06 Event
├── 07 Combat
├── 08 Town
├── 09 Combat
└── 10 Boss
```

## Resource

建立：

```text
data/areas/forest.tres

data/stages/
├── forest_01.tres
├── forest_02.tres
├── forest_03.tres
├── forest_04.tres
├── forest_05.tres
├── forest_06.tres
├── forest_07.tres
├── forest_08.tres
├── forest_09.tres
└── forest_10.tres
```

如果项目更适合集中管理，也可以：

```text
forest.tres
└── inline StageData
```

Agent 应根据 Phase 0 audit 选择更符合项目现有风格的方案。

## Stage Type

必须验证：

```text
06 = EVENT
08 = TOWN
10 = BOSS
```

其他为：

```text
COMBAT
```

## Output

完成：

```text
Forest AreaData
10 StageData
```

并提供验证方法。

---

# Phase 3 — Player Progress

## 目标

把：

```text
Static Game Data
```

和：

```text
Player State
```

彻底分离。

## 新增

例如：

```text
scripts/progress/PlayerProgress.gd
```

保存：

```text
current_area_id
current_stage_id
completed_stages
```

建议使用：

```gdscript
completed_stages: Dictionary
```

例如：

```text
forest_01 = true
forest_02 = true
forest_03 = true
```

## Unlock Logic

第一版只实现简单线性 progression：

```text
Stage 01 → unlocked
完成 Stage 01
→ Stage 02 unlocked
完成 Stage 02
→ Stage 03 unlocked
...
```

不要在这一 Phase 加复杂 branching。

## 必须支持

```text
is_stage_unlocked()
is_stage_completed()
complete_stage()
get_current_stage()
```

## 重要

不要修改 StageData：

错误：

```gdscript
stage.completed = true
```

正确：

```text
StageData = immutable/static definition

PlayerProgress = runtime/player save state
```

## Output

PlayerProgress + 基础 tests。

---

# Phase 4 — StageManager

## 目标

建立统一 Stage 进入入口。

核心：

```text
StageData
    ↓
StageManager
    ↓
根据 StageType 进入对应 Gameplay Scene
```

## API

建议：

```text
enter_stage(stage_data)
enter_stage_by_id(area_id, stage_id)
```

内部：

```text
COMBAT → CombatScene
EVENT  → EventScene
TOWN   → TownScene
BOSS   → BossScene
```

## 禁止

不要出现：

```gdscript
if stage_number == 6:
...
elif stage_number == 8:
...
elif stage_number == 10:
...
```

Stage 06 是 Event 的原因必须来自：

```text
StageData.stage_type
```

## Scene Loading

优先复用现有 Scene transition 系统。

如果项目已经有：

```text
SceneManager
GameManager
NavigationManager
```

不要重新创建第二套。

## Output

完成：

```text
StageManager
```

并确保可以：

```text
Forest Stage 01 → Combat
Forest Stage 06 → Event
Forest Stage 08 → Town
Forest Stage 10 → Boss
```

---

# Phase 5 — Integrate Existing Combat / Town

## 目标

让旧系统通过 StageManager 被调用。

## Combat

原来的 Combat 启动方式：

```text
直接进入 CombatScene
```

逐步改成：

```text
WorldMap
 ↓
StageManager
 ↓
StageData
 ↓
CombatScene
```

CombatScene 不需要知道：

```text
Forest Stage 03
```

它只接收：

```text
CombatData
```

或者当前 Stage Context。

## Town

同样：

```text
WorldMap
 ↓
StageManager
 ↓
Forest Stage 08
 ↓
TownScene
```

## Boss

如果当前 Boss 使用 CombatScene，而不是独立 BossScene：

不要强行创建 BossScene。

可以：

```text
StageType = BOSS

StageManager
 ↓
CombatScene
 ↓
Boss-specific CombatData
```

只有在 Boss 真的是独立 gameplay loop 时才建立 BossScene。

## Output

旧 Combat / Town 可以通过 Stage system 正常进入。

---

# Phase 6 — WorldMap / AreaMap Integration

## 目标

让 WorldMap 不再 hard-code：

```text
Stage 01
Stage 02
...
Stage 10
```

而是：

```text
AreaData
 ↓
stages
 ↓
动态创建 Stage Nodes
```

## WorldMap

推荐结构：

```text
WorldMap
└── AreaView
    ├── Background
    ├── Path
    └── StageNodes
```

StageNodes 动态生成：

```text
for stage in area_data.stages:
    create_stage_node(stage)
```

## Stage Node 显示

根据：

```text
stage.stage_number
stage.stage_type
PlayerProgress
```

显示：

```text
01
02
03
...
```

以及不同 icon：

```text
Combat
Event
Town
Boss
```

## 状态

至少支持：

```text
LOCKED
AVAILABLE
COMPLETED
CURRENT
```

## 禁止

WorldMap 不应该判断：

```text
if stage == 6 → event icon
if stage == 8 → town icon
```

应该：

```text
stage.stage_type
```

决定 icon。

---

# Phase 7 — Stage Completion / Return Flow

## 目标

建立完整流程：

```text
WorldMap
 ↓
Stage
 ↓
Gameplay
 ↓
Complete
 ↓
PlayerProgress
 ↓
Unlock next stage
 ↓
Return WorldMap
```

例如：

```text
Forest 05
 ↓
Combat
 ↓
Victory
 ↓
complete_stage("forest_05")
 ↓
Forest 06 unlocked
 ↓
WorldMap
```

Stage 06：

```text
Forest 06
 ↓
Event
 ↓
Event Complete
 ↓
Forest 07 unlocked
```

Stage 08：

```text
Forest 08
 ↓
Town
 ↓
Return
```

需要明确：

**Town 是否算 completion stage。**

第一版建议：

```text
Town = visitable + counts as completed after first entry
```

如果项目设计不同，以实际需求为准。

---

# Phase 8 — Save / Load

## 目标

确保 Area/Stage progression 可以持久化。

保存：

```text
current_area_id
current_stage_id
completed_stages
```

不要保存：

```text
StageData Resource 本身
```

只保存 identifier。

例如：

```json
{
    "current_area": "forest",
    "current_stage": "forest_06",
    "completed_stages": [
        "forest_01",
        "forest_02",
        "forest_03",
        "forest_04",
        "forest_05"
    ]
}
```

## Load

启动游戏：

```text
Save
 ↓
PlayerProgress
 ↓
WorldMap
 ↓
AreaData
 ↓
StageData
```

重新构建 runtime state。

---

# Phase 9 — Add More Area

## 目标

验证架构不是只为 Forest 写的。

增加：

```text
Swamp
```

例如：

```text
Swamp
├── 01 Combat
├── 02 Combat
├── 03 Elite
├── 04 Combat
├── 05 Event
├── 06 Combat
├── 07 Shrine
├── 08 Town
├── 09 Elite
└── 10 Boss
```

如果 Phase 1~8 架构正确：

**不应该修改 StageManager 核心逻辑。**

只需要新增：

```text
Swamp AreaData
Swamp StageData
```

如果为了 Swamp 必须修改大量核心代码，则说明架构存在 hard-code，需要在本 Phase 修复。

---

# Phase 10 — Refactor / Cleanup

## 最终检查

搜索项目：

```text
stage == 6
stage == 8
stage == 10

forest_01
forest_02
forest_03
...
```

确认没有 gameplay logic hard-code 这些 stage number。

检查：

```text
WorldMap
StageManager
Combat
Town
Event
Boss
Save
PlayerProgress
```

确保职责清晰。

---

# Final Architecture

最终目标：

```text
                    WorldData
                       │
                ┌──────┴──────┐
                │             │
             Forest          Swamp
                │
             AreaData
                │
       ┌────────┼───────────────┐
       │        │               │
   StageData StageData       StageData
       │
       ├── id
       ├── stage_number
       ├── stage_type
       ├── gameplay_data
       ├── reward_data
       └── requirement_data
                │
                ▼
          StageManager
                │
      ┌─────────┼─────────┐
      │         │         │
   Combat     Event      Town
      │         │         │
      └─────────┼─────────┘
                │
             Boss
```

同时：

```text
PlayerProgress
│
├── current_area_id
├── current_stage_id
└── completed_stages
```

独立于：

```text
AreaData
StageData
```

---

# Multi-Chat Execution Order

必须按照以下顺序开 Chat Session：

```text
Chat 01
Phase 0
Repository Audit

        ↓

Chat 02
Phase 1
Core Data Model

        ↓

Chat 03
Phase 2
Forest Data

        ↓

Chat 04
Phase 3
Player Progress

        ↓

Chat 05
Phase 4
StageManager

        ↓

Chat 06
Phase 5
Combat / Town Integration

        ↓

Chat 07
Phase 6
WorldMap Integration

        ↓

Chat 08
Phase 7
Completion / Return Flow

        ↓

Chat 09
Phase 8
Save / Load

        ↓

Chat 10
Phase 9
Swamp Validation

        ↓

Chat 11
Phase 10
Final Refactor
```

每一个 Chat Session **只负责一个 Phase**。

---

# 每个新 Chat Session 的开场规则

每次把：

```text
1. 本 Coding Plan
2. 当前 Phase
3. 上一个 Phase 的 output/report
```

交给 agent。

并要求：

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

---

# Definition of Done

整个系统完成后，必须能够实现：

```text
WorldMap
    ↓
Forest
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
完成 01
 ↓
02 unlocked

完成 05
 ↓
06 Event unlocked

完成 06
 ↓
07 unlocked

进入 08
 ↓
Town

完成 09
 ↓
10 Boss unlocked
```

新增：

```text
Swamp
```

时，不需要修改核心：

```text
StageManager
PlayerProgress
WorldMap
```

只需要添加新的：

```text
AreaData
StageData
```

即可。

这才是这个系统真正的扩展性目标。
