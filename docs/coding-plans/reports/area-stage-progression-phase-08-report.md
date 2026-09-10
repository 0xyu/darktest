# Save / Load（玩家侧进度存档）— Phase 8 报告

> 对应计划：`docs/coding-plans/area-stage-progression-coding-plan.md`（**Rev 3.1 的 Phase 8 节**；本 Phase 落地后该文档标记为 Rev 3.2，模型未变）。
> 前置输入：`reports/area-stage-progression-phase-07-6-report.md`（Rev 3 全局关号模型，§7 是本 Phase 的交接清单）。
> 范围：只做**玩家侧进度的持久化**（位置 / 解锁上限 / 通关集合 / 一次性内容消费集合）。
> **不**改 `StageDatabase` / `StageData` / `StageRouter` / `PlayerProgress` 的字段模型，**不**改战斗引擎，**不**新增 autoload 全局状态，**不**加存档 UI（存档/读档按钮、多存档位）。

---

## 1. 一句话结果

玩家侧进度现在**开机自动读档、每次真实变化自动落盘**：位置、解锁上限、通关集合、一次性内容消费集合四项以 identifier/标量形式写进一个 JSON 文件；读档把它们注入同一个挂载点（同时持有两个状态对象），并从存档所在的那一关继续战斗。

```text
入档（写盘）：StageFlow 的真实变化 / AuthoredContentState.consume()
出档（开机）：StageProgressSave.load() → 注入 StageFlow + StageContentController → 从存档关号继续

user://save/stage_progress.json
{
  "version": 1,
  "current_stage_number": 6,
  "highest_stage_reached": 9,
  "completed_stages": ["forest_001", ...],
  "consumed_content": ["forest_006:cache"]
}
```

**没有**任何 area 字段，**没有**任何 Resource 本体。

---

## 2. 改动清单

| 文件 | 变更 |
|---|---|
| `scripts/progress/stage_progress_save.gd` | **新增**（`class_name StageProgressSave`，259 行）。唯一挂载点：同时持有 `PlayerProgress` + `AuthoredContentState`；`to_save_data()` / `load_save_data()` / `save()` / `load()` / `has_save()` / `delete_save()`；格式版本、位置域与解锁上限三条校验；`bind(flow)` 订阅自动存档；`default_path()` / `set_default_path()`（静态，供测试把路径改到 scratch 文件） |
| `scripts/systems/stage_flow.gd` | 新增信号 `progress_changed()`；`on_stage_started()` 在**位置或解锁上限真的变了**时发；`on_battle_cleared()` 只在**新 recorded 完成**时发；TOWN 进入分支把 `complete_stage` 移到 `on_stage_started` 之前，使"进入城镇"只产生**一次**通知（= 一次落盘） |
| `scripts/progress/authored_content_state.gd` | 新增信号 `content_consumed(key)`；`consume()` 新增 key 时发出（幂等重复消费不发） |
| `scripts/world/grid_combat.gd` | 存档挂载：`_stage_save` 建立并 `load()` → 把 `_stage_save.progress` 注入 `StageFlow`、把 `_stage_save.content_state` 注入 `StageContentController`（原先两处就地 `new()` 变成注入）→ `_stage_save.bind(_flow)` 打开自动存档；开机 `stage_manager.initialize_stage(1)` 换成 `_start_first_stage()`（从存档关号恢复）；新增只读访问器 `get_stage_save()`；删除已不再使用的 `AuthoredContentStateScript` const |
| `tools/ui_harness/ui_harness_suite.gd` | 每个测试前 `_reset_game_save()`：把游戏的存档路径重定向到 harness 自己的 scratch 文件（`res://.godot/ui_harness/stage_progress.json`，在 gitignore 的 `.godot/` 内）并删除它 |
| `tests/stage_progress_save_smoke_test.gd` | **新增**冒烟测试（11 用例 / 88 断言）：payload 形状、校验、JSON 与磁盘往返、坏档、以及三个自动存档触发 |
| `tools/ui_harness/suites/test_stage_save.gd` | **新增** harness suite（8 用例 / 52 断言）：在**真实游戏场景**里验证"玩 → 写盘 → 关掉 → 再开 → 恢复" |
| `docs/ui-harness.md` | 新增陷阱条目：harness 会重置游戏存档（以及为什么） |
| `docs/coding-plans/area-stage-progression-coding-plan.md` | Phase 8 标记为已完成 + 落地备注；执行序更新 |

---

## 3. 存档形状与理由（对应计划 §「目标」）

| 字段 | 来源 | 为什么必须存 |
|---|---|---|
| `current_stage_number` | `PlayerProgress.current_stage_number` | 唯一位置（全局关号）。可以小于 `highest_stage_reached`（阵亡回退过） |
| `highest_stage_reached` | `PlayerProgress.highest_stage_reached` | 单调解锁上限。漏存 → 读档后地图解锁状态丢失（Phase 7.6 §7 点名） |
| `completed_stages` | `PlayerProgress.completed_stages` | 显式通关集合，key 为 canonical id（`forest_006`）。**不能由位置推导**：当前站着的那关还没清 |
| `consumed_content` | `AuthoredContentState.consumed` | 一次性内容已消费集合（`forest_006:cache`） |
| `version` | 本 Phase | 格式版本：读档时**拒绝**比本版本更新的存档，而不是半读 |

明确不存（都有测试守卫）：`current_area_id` / 任何 area 字段（推导量）、`StageDatabase` / `StageData` 本体（静态数据由 `.tres` 提供）、area 局部关号。

> **测试守卫**：`_test_payload_holds_no_area_and_no_resources()` 遍历 payload 的所有 key，任何一个含 `"area"` 就失败；两个集合的元素必须是 `String`（不能是 Resource）。

写入细节：JSON + 制表符缩进，数组按 key 排序（`_sorted_string_keys`），因此同一个状态写出来的文件是**稳定**的（便于人眼与将来的 diff）。

---

## 4. 挂载点：一个对象同时持有两个状态（对应计划 §「挂载点与存档时机」）

```text
grid_combat._ready()
  ├── _stage_save = StageProgressSave.new()      # 默认 user://save/stage_progress.json
  ├── _stage_save.load()                        # 有档就恢复（成功才改状态）
  ├── _flow = StageFlow.new(_stage_save.progress)          # ← 注入，flow 不再自建
  ├── _stage_content.configure(..., _stage_save.content_state)  # ← 注入，controller 不再自建
  ├── _stage_save.bind(_flow)                   # ← 打开自动存档
  └── _start_first_stage()                      # ← 从存档关号继续
```

先 `load()` 再建 flow / controller，是为了让两个消费者**一开始就吃**恢复后的对象 —— 不存在"先建好再修补"的中间态，也不存在**半个玩家**（清了关但宝箱回来 / 宝箱没了但关卡没清）。

`bind(flow)` 的连接方向是"状态对象自己宣布变化"：

```text
StageFlow.progress_changed  ─┐
                             ├─→ StageProgressSave.save()
AuthoredContentState.content_consumed ─┘
```

选择信号而不是在 host 里调 4 次 `save()`：`StageFlow` 是 `PlayerProgress` 的**唯一写入者**（Phase 7.6 的单一位置写入点），所以订阅它按构造就覆盖了**全部**改关号路径（开机 / 地图与 DEV 进入 / 推进 / 阵亡回退 / FARMING 原地重刷 / 城镇访问），未来新加路径也不会漏存。存档对象不知道游戏，游戏也不需要在每个路径记得存档。

---

## 5. 存档时机：三个触发（全部低频）

| 触发 | 位置 | 结果 |
|---|---|---|
| 位置变化 | `StageFlow.on_stage_started()` | 位置或解锁上限真的变了才通知（FARMING 原地重刷不写盘） |
| 记录通关 | `StageFlow.on_battle_cleared()` | 只有**新**完成才通知（同一关重复清场不写盘） |
| 消费一次性内容 | `AuthoredContentState.consume()` | 只有新增 key 才通知（幂等重复消费不写盘） |

"只记真实变化"是对计划原文（"改位置后 / 记完成后 / 消费后"）的一处**收紧**，理由有二：

1. FARMING 是**长时间挂机**模式，`on_stage_started` 每轮都会走；不加判断就会每几秒重写一次文件。
2. 语义更准：`progress_changed` 字面意思就是"进度变了"，没变就没东西要存。

代价：**一次什么都没做的新开局不会立刻产生存档文件**（新开局的位置本来就是 1，没有变化）。第一次真实进度（清掉第 1 关）就会写盘。这一点已由 suite 用例固定下来（`test_a_new_game_boots_on_stage_one_and_saves_once_progress_happens`）。

写盘是同步的、整体覆盖：文件只有几百字节，触发点全是低频玩家事件，不做增量/异步/合并。

---

## 6. 读档与校验（对应计划 §「Load 重建」）

`load()` → `load_save_data()` 的校验顺序：

1. payload 是 `Dictionary`（JSON 解析失败/空文件 → 拒绝）。
2. `version` 必须存在、且**不大于**本版本的 `FORMAT_VERSION`（更新的存档拒绝，不半读）。
3. `current_stage_number` 落进关号声明域 `[1, 999999]`（域由 `PlayerProgress` 自己的 `@export_range` 决定）；域外是损坏值，夹到最近边界。
4. `highest_stage_reached >= current_stage_number`：**不满足时抬高上限**（`mark_reached(position)`），绝不压低位置。
5. 两个 id 集合只接受非空 `String`；其余条目丢弃（不因为一个坏条目丢掉整档）。
6. 已不被任何 area 覆盖的旧 id **保留**（区间重划分后是"陈旧"不是"损坏"）。

**区间外的位置是合法存档**：57+ 的纯 endless 尾段照原样恢复，不夹回区间、不报错。

**开机恢复规则**（`grid_combat._start_first_stage()`）：

```text
存档位置 n > 1 且 initialize_stage(n) 成功 → 从第 n 关的普通战斗继续，状态栏 "SAVE RESTORED — STAGE nn"
否则（新开局 / 存档不可用）                → initialize_stage(1)（原有行为）
```

* 战斗关卡号 == 全局关号，这是 endless 循环本来就在用的映射；跨区间（11+）不需要特例。
* 不可用的存档**不阻塞开机**：保留新档状态，从第 1 关开新游戏（有测试）。

---

## 7. 与计划文档的有意偏差（4 处，逐条给理由）

1. **开机恢复不经过 `StageRouter`**。计划的 Load 管线写的是「位置 n → `lookup(n)` → `StageRouter` → 进入对应玩法」。本 Phase 直接走 `initialize_stage(n)`，因为：
   * COMBAT 与 BOSS 的 destination 都是 `COMBAT`，且战斗关卡号 == 全局关号，所以**对这两种关卡，走 router 与不走 router 的可观察结果完全相同**（同样的 `initialize_stage(n)`、同样的 authored boss 短路），router 只会多绕一层；
   * TOWN 位置（玩家在城镇里存了档）若真去"进入对应玩法"，开机就会显示城镇视图而**一整关都没启动**——`stage_state` 没有关卡、没有敌人、越过城镇返回战斗视图后既不能打也不能推进。所以 TOWN 位置按**该关号的普通战斗**恢复（访问本身已记录为 completed，城镇仍在地图上一步之遥）。
   * 收益：开机路径没有"没启动任何关卡"的状态，风险最低。
   * 已由 suite 用例固定：`test_a_saved_visit_stage_resumes_as_a_playable_battle`。
2. **"只记真实变化"**（见 §5）：计划写的是三个时机无条件落盘，这里收紧为"真的变了才落盘"。
3. **测试隔离用路径重定向，而不是让 harness 去删真存档**。`StageProgressSave.set_default_path()` 是运行期静态开关（不写 `project.godot`），harness 在跑任何 suite 前把它指到 `res://.godot/ui_harness/stage_progress.json` 并在每个测试前删掉。这样：测试确定（前一个测试打过的关不会被下一个测试读档恢复）、**绝不触碰玩家的真存档**、也不依赖 `user://` 的可写性。
4. **关号域上限 999999 夹取**：计划只要求"`current_stage_number >= 1`"。这里同时给出上界，用的是 `PlayerProgress` 字段自己的 `@export_range(1, 999999, 1)`；目的是让手改坏档不会把游戏送到 `initialize_stage()` 无法描述的深关号（深层数值缩放的溢出风险见 §9），**不是**把合法位置夹回区间 —— 57 这类尾段位置照原样恢复。

---

## 8. 验证与回归

### 新增

* `tests/stage_progress_save_smoke_test.gd` —— 11 用例 / 88 断言（headless `-s`，不挂场景）：
  payload 形状与"无 area 字段"守卫、`to_save_data` 与 JSON 双向往返、位置域修复、上限抬高（不压低位置）、损坏档拒绝（空 payload / 缺 version / 未来版本）、不可用字段容忍、陈旧 id 保留、磁盘往返（写→读→同状态，含坏文件与空文件）、**三个自动存档触发**（用 `saved` 信号计数证明"没变就不写"）。
* `tools/ui_harness/suites/test_stage_save.gd` —— 8 用例 / 52 断言（真实游戏场景）：
  1. 新开局停在第 1 关、未做事不写档、清掉第 1 关后自己写档；
  2. 进第 6 关 → 位置写盘；清场 → 通关集合写盘；
  3. **关掉再开**（卸载场景 → 重新挂载）：从第 6 关继续、通关与解锁都还在、状态栏报告 SAVE RESTORED；
  4. 恢复的解锁上限让地图第 8 关可进、第 9 关仍锁、HERE 落在恢复的位置；
  5. 存档位置 57（纯 endless 尾段）照原样恢复且**真的生成了战斗**；
  6. 存档位置 8（TOWN）恢复为可打的战斗，不重开城镇视图；
  7. 一次性宝箱消费后**关掉再开**仍然消失、可重复内容照常重生（这是"半个玩家"防线的回归测试）；
  8. 坏档 / 未来版本档 → 开新游戏，不半读、不阻塞开机。

### 回归

```text
全量 ui_harness         91 tests, 90 passed, 1 failed, 0 skipped
  baseline（改动前）     83 tests, 82 passed, 1 failed
  唯一失败是既有历史失败  test_combat_log_wiring::test_kill_logs_event_end_to_end（baseline 同样失败）
7 个 SceneTree smoke    area_stage_data / player_progress / stage_database / stage_router /
                        stage_content / stage_progress_save / subhero_progression —— 全绿（exit 0）
parse                  干净（编辑器 Debugger 无新增脚本错误；3 个新增 .gd 各带 1 个编辑器生成的 .uid，与仓库其它脚本一致）
```

Phase 7.6 的 8 个既有 suite（stage_flow / stage_progression / stage_range / stage_content / world_map / stage_exit_advance / town_view / development_panel）**一行未改**即全绿 —— 说明"存档注入 + 开机恢复"没有改变既有玩法语义（每个测试前重置存档是关键前提）。

### 实机验证（编辑器运行，`user://` 真实落盘）

harness 用的是 scratch 路径，所以另在编辑器里跑了三轮真实游戏（`project_run` + `game_eval`，每次启动 `current_run_errors` 均为空）：

```text
第 1 轮  新开局 → 位置 1 / 无存档文件；enter_area_stage(6) + 清场 →
         文件出现，内容正是计划的形状：
         { version:1, current_stage_number:6, highest_stage_reached:6,
           completed_stages:["forest_006"], consumed_content:[] }
第 2 轮  重开 → battle stage 6（2 个敌人已生成）/ position 6 / completed ["forest_006"] 还原 /
         内容层重新生成 2 条（宝箱 + 可重复泉）/ 状态栏 "SAVE RESTORED — STAGE 06"
         再消费宝箱 → 文件出现 consumed_content:["forest_006:cache"]
第 3 轮  重开 → 状态栏仍 "SAVE RESTORED — STAGE 06"，内容层只剩可重复的泉（宝箱不再出现），
         consumed 集合还原
清理     验证结束后删除验证用的 user:// 存档（不把合成进度留在开发机游戏数据里）
```

---

## 9. 已知风险与遗留

1. **区间重划分的迁移成本从现在起不为零**（计划 Section「与区间重划分的耦合」）：`completed_stages` 的 key 是 `<area_id>_<补零全局号>`，改区间起点/长度会改 id 形态，旧存档里的旧 id 不会被新查询认出来。当前无迁移代码（`version` 字段已就位，将来可据此做格式转换）。
2. **深关号的数值缩放未验证**：存档把位置带到很深的关号（例如手改 999999）时，敌人按指数曲线缩放可能溢出。这是 endless 数值设计的既有边界，不是存档逻辑引入的；上限夹取只是避免"离谱值"进入 `initialize_stage()`。
3. **存档不包含任何战斗/角色状态**：金币、装备、等级、Sub Hero 仍不持久化（各自有 `to_save_data()` 形状但无落盘）。Phase 8 的范围是"玩家侧关卡进度"；把它们并入同一个存档文件是后续独立工作（不要顺手做，会牵动战斗引擎）。
4. **没有存档 UI / 多存档位 / 手动存档**：只有自动存档。`StageProgressSave` 的路径是构造参数，做存档位时不需要改数据模型。
5. **沙箱环境的 `user://` 不可写**（本次开发环境特有）：本机 DSH 文件沙箱下的子进程无法写 `%APPDATA%`，因此**自动化测试全部走 `res://.godot/` 的 scratch 路径**，真实的 `user://save/stage_progress.json` 路径由编辑器进程（不受该沙箱限制）在运行时验证。这不是代码问题，但换机复现时要知道。
6. **MCP `test_run` 目前报 `test_ui_fixture.gd (cannot instantiate — abstract or broken)`**：与本 Phase 无关（该文件及其依赖 `res://tests/fixtures/ui_fixture.gd` 未被改动），且同一脚本在**冷 headless 进程**里 `can_instantiate()` 为真、编辑器也能正常解析出 14 个函数 —— 属于编辑器脚本缓存的既有状态。gate 用的是 ui_harness + smoke，不依赖该通道。

---

## 10. 对 Phase 10（Refactor / Cleanup）的交接

* Phase 10 清单里的"存档"职责行现在是真实存在的对象：

```text
PlayerProgress        玩家进度（位置 / 解锁上限 / 通关集合）
AuthoredContentState  玩家侧：哪些一次性内容已消费
StageProgressSave     唯一挂载点 + 唯一落盘点（只存 identifier）
```

* 仍未做的 Phase 10 清理项（Rev 3.1 从原 Phase 9 并入）：`scripts/ui/development_panel.gd` 里写死的 `load_area(&"forest")` 与 `FOREST %02d` 文案。
* Phase 8 **没有**引入新的硬编码、也没有新增 stage 数字判断；Phase 10 的 grep 清单（`stage == 6` / 一 stage 一 `.tres` / 按文件拼路径）在本 Phase 新增的两个文件中均为零命中。
