# 轻量战斗动画与反馈系统 — 实施计划

> 本文档是给**独立新会话**直接执行用的编码计划。所有调研结论已内嵌（含文件:行号引用），
> 执行时无需重新调研架构，只需按阶段实现并验证。配套任务清单见 `task.md`。
> 需求原文（英文 33 节规格）以本计划转述为准；如与本计划冲突，以"不破坏现有玩法"为最高原则。

## 1. 目标

为现有 Godot 4.7.2 竖屏回合制 RPG 增加**可复用的战斗表现层**：

- 静态角色代币（Static Character Token）：一张静态头像 + 阴影，靠 tween 产生全部动感。
- 通用命中反应（闪白/红闪/抖动/击退）、死亡表现、MISS/DODGE/BLOCK 表现。
- 攻击演出：预备 → 冲刺 → 命中 VFX → hit stop → 命中反应 → 伤害数字 → 镜头震动 → 收招。
- 法术演出：投射物 / 瞬发 / 范围三类。
- 程序化 VFX（slash/impact/fire/ice/lightning/poison/holy/dark/arcane/heal 等），数据驱动、不按敌人定制。
- 伤害数字、hit stop、仅战斗区镜头震动（HUD 不震）。
- 与现有 Auto/Farm/游戏速度集成：加速但不删除反馈。

**硬性约束**：

1. 不需要任何敌人动画帧表；一张静态头像即可接入。
2. 表现层绝不决定伤害是否发生；伤害结算时机保持现状（立即结算）。
3. 视觉位移不得改动逻辑网格坐标。
4. 不重写战斗系统、不复制伤害计算、不引入 ECS/骨骼动画/粒子引擎等大框架。
5. 任何临时效果必须自清理（无孤儿 tween、无卡死的相机偏移/hit stop/modulate/scale/position）。

## 2. 现有架构调研结论（已验证，直接引用）

### 2.1 战斗结算与事件源

- `scripts/combat/combat_system.gd`
  - 信号：`attack_resolved(result: DamageResult)`（:4）、`actor_died(actor)`（:5）、`skill_resolved`、`skill_failed`。
  - `_resolve_attack()`（:60-117）**立即**结算伤害并写回 HP；非法攻击产出 `is_miss=true` 的结果（:72-75）；
    击杀时调用 `target.handle_defeat()`（:109-110）并 emit `actor_died`（:115-116）。
  - 现状伤害数字由 `_spawn_damage_number()`（:282-294）生成，`@export feedback_parent_path`（:9）**仅**被该函数使用 → 迁移到表现层后两者一并删除（先 grep 确认无 .tscn 赋值）。
- `scripts/combat/damage_result.gd`：仅有 `attacker_id/target_id/skill_id/raw_damage/final_damage/is_critical/is_miss/target_defeated`，**没有节点引用** → 需新增 `attacker/target: Node`（非 @export）。
- `scripts/systems/turn_manager.gd`：回合流转（player turn → 逐个 enemy turn → victory/defeat）。表现层**不得**等待或阻塞回合流转。
- `scripts/combat/skill_catalog.gd`：三个技能 → VFX 映射依据：
  - `whirlwind`：ADJACENT_AREA（范围）→ slash + area 环。
  - `arcane_bolt`：range 2 单目标 → 投射物（arcane）。
  - `execution_strike`：melee 1.5x → heavy_slash（HEAVY 演出）。

### 2.2 单位与视觉现状

- `scripts/player/player_controller.gd`
  - 视觉全在 `_draw()`：player.png  sprite（常量 `PLAYER_SPRITE`/`SPRITE_RECT`，:6-9）+ 地面椭圆 + 选中金环。
  - 位移直接写 `global_position`：`try_move()`、`place_at()`、`revive_for_retry()`、`_ready()`。
  - 信号 `moved(from_cell, to_cell, points_remaining)`；`handle_defeat()` 不隐藏节点。
- `scripts/enemies/enemy_controller.gd`
  - `_draw()`（:294-314）：阴影圆 + `CharacterSpriteCatalog.get_texture()` 的 AtlasTexture（24px  cell，Rect2(-24,-27,48,48)，`TEXTURE_FILTER_NEAREST`，:57）+ boss 金环 + HP 条。
  - `handle_defeat()`（:97-106）：`visible = false` + `process_mode = PROCESS_MODE_DISABLED`，**节点不 free** → 死亡演出必须接管"隐藏"；且 token 子节点必须 `PROCESS_MODE_ALWAYS`，否则继承 DISABLED 后 tween 不跑。
  - `_move_toward_target()` 瞬移并 emit `moved(from, to)`。
- `scripts/systems/character_sprite_catalog.gd`：`get_texture(id) -> AtlasTexture`，敌人只存 catalog id。
- 敌人/玩家被 stage 切换时由 StageManager 释放（queue_free）→ 绑定节点的 tween 自动消亡，安全。

### 2.3 场景 / HUD / 相机

- `scenes/world/grid_combat.tscn` 为战斗场景（Main.tscn 仅实例化它）。**当前没有 Camera2D**。
- `scenes/ui/MobileCombatHUD.tscn` 根节点是 **CanvasLayer**（:88）→ Camera2D 震动天然不影响 HUD；TownView 也在 HUD 内，不受影响。
- `project.godot`：720×1280，`stretch/canvas_items + expand`，`gl_compatibility`（additive CanvasItemMaterial 可用）。
- `scripts/world/grid_combat.gd`
  - `_ready()`（:26-83）集中接线所有系统；新系统按同样方式加入。
  - `_layout_portrait_grid()`（:212-239）在视口变化时**直接重设** player/enemies 的 `global_position` → 重排后必须让 token `snap()`。
  - `_on_sub_hero_attack_feedback_requested()`（:421-431）已在 HUD 画布生成 `SubHeroAttackEffect` 投射物（保留，不重复造）。
- `scripts/combat/sub_hero_attack_effect.gd`：现有"代码绘制投射物+冲击"VFX 范本（风格参照）。
- `scripts/sub_hero/sub_hero_combat_manager.gd` 信号：`attack_resolved(result)`、`attack_feedback_requested(result, target)`（:9-10）。

### 2.4 速度 / 调试 / i18n / 验证

- `scripts/systems/auto_combat_controller.gd`：`GameSpeed{X1,X2,FASTEST}`；信号 `auto_mode_changed` / `farming_changed` / `game_speed_changed`；行动间隔 x1=0.40s / x2=0.20s / fastest=0.05s。**速度唯一来源**，不得新设第二套。
- `scripts/ui/development_panel.gd`：UI 全代码构建（`_section_title()` / `_make_button(label, color, callable)`，:212-252）→ 直接加 "COMBAT FX TEST" 段；该面板即既有 debug 入口（HUD 的 DEV 按钮）。
- `scripts/systems/game_locale.gd`：`_STRINGS` 字典 + `translate(key, values)`（:20,:55）→ 浮字文本（MISS/DODGE/BLOCK/CRITICAL）走 i18n。
- 验证工具链：
  - Godot：`D:\IDE\godotEngine\Godot_v4.7.2-stable_win64_console.exe`
  - 导入新资源：`--headless --editor --quit --path G:/godotproject/darkrpg`
  - 启动自检：`--headless --quit-after 120 --path G:/godotproject/darkrpg res://scenes/world/grid_combat.tscn`
  - 测试：`res://tests/*.gd`（见 `docs/testing-fixtures.md`；新测试套件 headless 跑，参考 McpTestRunner 方式）。

## 3. 架构设计

```text
CombatSystem（玩法：伤害立即结算，保持不变）
   │  attack_resolved(DamageResult{+attacker,+target})   actor_died(actor)
   ▼
CombatPresentationSystem（Node，grid_combat 新子节点；只读事件，不回写玩法）
   ├─ CharacterToken ×N（Player/每个 Enemy 的子节点）
   │     ├─ Avatar（Node2D，draw_texture_rect 静态头像）
   │     ├─ Flash（Node2D，additive CanvasItemMaterial 叠画同纹理 → 闪白/红闪）
   │     └─ 阴影（token 自身 _draw，随抬升/落地缩放）
   ├─ CombatVFX 实例（表现层子节点，程序化 _draw，短命自删）
   ├─ DamageNumber 实例（表现层子节点，tween 浮字）
   └─ CombatCamera（Camera2D，grid_combat 新子节点；只震 offset）
MobileCombatHUD（CanvasLayer）── 不受相机影响，保持独立
```

### 3.1 关键设计决策

1. **位移偏移法（零侵入网格）**：单位 `global_position`/`grid_position` 仍由玩法瞬设；token 用**本地 position 偏移**做视觉：`play_move(offset)` = `position = offset` 后 tween 回 `ZERO`。攻击冲刺/击退/抖动全部是临时偏移，结束必回 `ZERO`。逻辑坐标永不被表现层修改。
2. **Tween 安全**：全部 `token.create_tween()`（绑定节点，free 即杀）。表现层 `await` 不用 `tween.finished`（节点自由后永不 resume 会挂协程），改 await 信号 `motion_phase_finished`；token 在 `_exit_tree()` 也 emit 该信号兜底。
3. **Hit stop**：`token.freeze(duration)` = 暂停其当前 motion tween（`Tween.set_paused(true)`）+ `SceneTreeTimer` 到时恢复；**禁用 `Engine.time_scale`**；UI 与输入完全不受影响。
4. **速度集成**：`CombatPresentationConfig.get_speed_multiplier(auto_or_farming, game_speed)` 为唯一换算点；结果写入各 `token.speed_multiplier` 与 VFX/浮字 spawn 参数。FASTEST=0.45、X2=0.7、X1+(auto|farming)=0.7、X1 手动=1.0（乘到所有时长上）。
5. **死亡表现接管隐藏**：enemy `handle_defeat()` 删除 `visible = false`（保留 `PROCESS_MODE_DISABLED`）；`_draw()` 在 `_is_defeated` 时提前 return（不画 HP 条/环）；`actor_died` 延迟约 0.12s（×速度）后 `token.play_death()`，动画结束 token 自 `visible=false`。`revive_for_retry()` → `token.reset_visuals()`。
6. **伤害数字归属迁移**：生成点从 CombatSystem 移到表现层（impact 时刻），CombatSystem 删除 `_spawn_damage_number()` 与 `feedback_parent_path`。`hud.show_critical_indicator()` 等 HUD 反馈保留不动。
7. **相机**：grid_combat 新增 `CombatCamera`（Camera2D），`position = get_viewport_rect().size * 0.5`（_ready 与 `size_changed` 时重设，等价当前无相机取景）；震动只写 `camera.offset`，结束/退出归零。
8. **闪白实现**：additive 叠画子节点（决策见上），不写 shader、不复制纹理；天然"失败也无害"（最坏只是不闪）。
9. **VFX 数据驱动**：`StringName` 类别 → `match` 分派绘制；敌人/技能只携带类别 id；禁止按敌人名字分支。
10. **玩家优先**：攻击方为玩家时预备/冲刺/VFX 强度×1.15~1.25（config 常量），敌人用通用弱档。

## 4. 新增文件（4 个）

### 4.1 `scripts/combat/combat_presentation_config.gd`

`class_name CombatPresentationConfig extends RefCounted`，纯常量 + 一个静态换算函数：

| 组 | 常量（建议初值） |
|---|---|
| 移动 | `MOVE_DURATION_PER_CELL=0.18`、`MOVE_DURATION_PER_CELL_FAST=0.10`、`MOVE_HOP=3.0` |
| 攻击 | `ANTICIPATION=0.10`、`DASH=0.13`、`IMPACT_PAUSE=0.06`、`RECOVERY=0.20`、`ANTICIPATION_OFFSET=8.0`、`LUNGE_DISTANCE=26.0`、`HEAVY_LUNGE_DISTANCE=34.0`、`HEAVY_ANTICIPATION_SCALE=1.6`、`PLAYER_INTENSITY=1.2` |
| 命中反应 | `WHITE_FLASH=0.04`、`FLASH=0.10`、`REACTION_SHAKE=0.10`、`KNOCKBACK=6.0`、`CRIT_KNOCKBACK=10.0`、`HEAVY_KNOCKBACK=12.0`、`REACTION_SHAKE_AMPLITUDE=3.0` |
| Hit stop | `HITSTOP_NORMAL=0.04`、`HITSTOP_CRIT=0.065`、`HITSTOP_HEAVY=0.08` |
| 镜头震动 | `SHAKE_NORMAL=Vector2(1.5,0.06)`、`SHAKE_CRIT=Vector2(4.0,0.10)`、`SHAKE_HEAVY=Vector2(6.5,0.14)`（x=intensity px，y=duration s） |
| 浮字 | `NUMBER_LIFETIME=0.8` |
| VFX | `IMPACT_LIFETIME=0.22`、`PROJECTILE_TRAVEL=0.18` |
| 死亡 | `DEATH_DURATION=0.45`、`DEATH_DELAY=0.12` |
| 颜色 | `COLOR_DAMAGE="f1e6d0"`、`COLOR_CRIT="f1d277"`、`COLOR_HEAL="82d49b"`、`COLOR_POISON="9fd35a"`、`COLOR_MISS="b9b2c4"`、`COLOR_BLOCK="9fb6c9"`、`COLOR_FIRE="e07840"`、`COLOR_ICE="9fd8e8"`、`COLOR_LIGHTNING="d8c8ff"`、`COLOR_DARK="b06ae0"`、`COLOR_HOLY="e8d8a0"` |

`static func get_speed_multiplier(auto_or_farming: bool, game_speed: int) -> float`。

### 4.2 `scripts/combat/character_token.gd`

`class_name CharacterToken extends Node2D`。子节点（代码创建）：`Avatar`、`Flash`（内部类 `AvatarDrawer`/`FlashDrawer extends Node2D`，各自 `_draw()` 画 `texture` 于 `rect`；Flash 挂 `CanvasItemMaterial.blend_mode = BLEND_MODE_ADD`）。token 自身 `_draw()` 画地面阴影椭圆（脚底，x 半径≈rect 宽×0.42，y 压扁 0.45，随 `_shadow_scale` 缩放）。

```text
enum HitVariant { NORMAL, CRITICAL, HEAVY, MISS, DODGE, BLOCK, DEATH }
signal motion_phase_finished      # 每个可 await 阶段结束 emit；_exit_tree 也 emit（防协程挂死）
signal death_finished
var speed_multiplier: float = 1.0

setup(texture: Texture2D, rect: Rect2, nearest: bool)   # nearest→Avatar.texture_filter=NEAREST（像素怪）；texture=null→Avatar 画通用占位圆
play_move(offset: Vector2, cells: int, fast: bool)      # position=offset → tween 回 ZERO（时长=cells×PER_CELL×mult）；中途 MOVE_HOP 抬升 + 阴影 0.90→落地 1.05 回 1.0
snap()                                                  # 杀 motion tween、position=ZERO（ teleport/重排用）
wind_up(dir, heavy) / dash(dir, heavy) / recover()      # 各启动一个 motion tween，结束 emit motion_phase_finished（调用方 await 该信号）
play_hit_reaction(variant: HitVariant, dir: Vector2)    # 闪白→红闪（Flash.modulate.a tween）+ 击退+垂直抖动（tween_method 合成 offset，衰减回 ZERO）；DEATH 不在此处理
play_dodge(dir: Vector2)                                # 小侧移+小 hop，无闪白
play_death()                                            # 杀 motion tween→position=ZERO；scale 1→0.6、rotation→0.35、modulate.a→0（DEATH_DURATION×mult）→ visible=false + death_finished
is_dying() -> bool
reset_visuals()                                         # 复原 scale/rotation/modulate/visible/offset（revive 用）
freeze(duration: float)                                 # 当前 motion tween set_paused(true)；SceneTreeTimer 恢复（守卫 is_instance_valid）
```

安全细则：`_ready()` 设 `process_mode = PROCESS_MODE_ALWAYS`（父 enemy 被 DISABLED 时死亡动画仍要跑）；所有 tween 用 `create_tween()`；`_exit_tree()` kill tweens 并 emit `motion_phase_finished`。

### 4.3 `scripts/combat/combat_vfx.gd`

`class_name CombatVFX extends Node2D`。`setup(vfx_id: StringName, direction: Vector2, strong: bool, speed_multiplier: float)`；`setup_projectile(from: Vector2, to: Vector2, impact_id: StringName, speed_multiplier: float)`（旅行 `PROJECTILE_TRAVEL` 后切冲击绘制）。内部 `_process` 累计 elapsed，`_draw()` 按 id `match` 程序化绘制；setup 时用本地 `RandomNumberGenerator` 预生成抖动数组（**不在 _draw 里取随机**）。寿命到 `queue_free()`；`z_index = 15`。

类别：`slash`（金属弧光扫过）、`heavy_slash`（双弧交叉+更大）、`impact`（扩环+十字线，暗红/金）、`fire`（上升火星+橙光）、`ice`（浅蓝碎晶）、`lightning`（自上折线闪 0.12s）、`poison`（绿泡上升）、`holy`（金环辉）、`dark`（紫内爆环）、`arcane`（紫弹尾迹+爆）、`heal`（绿光上升十字）、`buff`/`debuff`（上/下箭羽）、`area`（地面扩环）。暗色哥特配色（用 config 颜色），寿命 0.08~0.25s×mult。

### 4.4 `scripts/combat/combat_presentation_system.gd`

`class_name CombatPresentationSystem extends Node`。

- `@export` NodePath 默认值：`../CombatSystem`、`../AutoCombatController`、`../CombatCamera`、`../Player`、`../StageManager`、`../SubHeroCombatManager`。
- `_ready()`：解析依赖；建两个子层 Node2D（VFX 层/浮字层可即自身）；连接：
  - `combat_system.attack_resolved` → `_on_attack_resolved`
  - `combat_system.actor_died` → `_on_actor_died`
  - `auto_combat` 三速度信号 → `_refresh_speed`
  - `player.healing_item_used` / `player.item_used` → 治疗浮字+heal VFX
  - `player.moved`、stage `stage_started`/`enemy_spawned` → 连接单位 `moved` → `token.play_move(...)`（cells 由 from/to 曼哈顿距离算）
  - `sub_hero.attack_feedback_requested` → 延迟 `PROJECTILE_TRAVEL` 后在 target 打冲击 VFX+浮字+NORMAL 反应
  - `get_viewport().size_changed` → 相机居中
- 主序列 `_on_attack_resolved(result)`（异步，逐步 `is_instance_valid` 守卫）：
  1. `is_miss` → target `play_dodge(dir)` + MISS 浮字，return。
  2. 判定：`heavy = result.skill_id == &"execution_strike"`；`vfx_id` 由 skill 映射（whirlwind→slash+area；arcane_bolt→projectile(arcane)；默认 slash；crit/heavy→strong）。
  3. `await token_atk.wind_up(dir, heavy)` → `await token_atk.dash(dir, heavy)`（await `motion_phase_finished`）。
  4. impact：spawn 攻击 VFX 于 target 位置；`freeze()` 双方 token + `await create_timer(hitstop×mult)`。
  5. target `play_hit_reaction(CRITICAL|HEAVY|NORMAL, dir)`；spawn 伤害浮字（crit 用 CRITICAL 档）；crit/heavy/boss 攻击方 → `shake(...)`。
  6. `await token_atk.recover()`。
- `_on_actor_died(actor)`：`create_timer(DEATH_DELAY×mult).timeout` → token 存在且 `!is_dying()` → `play_death()`。
- 法术：`_play_spell(caster, target, element, is_projectile, is_area)`：cast 预备（wind_up 不冲刺或小幅 scale 脉冲）→ projectile/instant/area VFX → 复用 impact 段。供 `test_effect` 与技能映射调用。
- `shake(intensity, duration)`：kill 旧 shake tween；`tween_method` 每帧随机偏移×衰减；结束 `camera.offset = ZERO`；`_exit_tree` 归零。
- `notify_layout_changed()`：player + 在场敌人 token 全部 `snap()`。
- `test_effect(case: StringName)`：dev 面板入口（normal/critical/heavy/miss/block/fire/lightning/heal/death），用**伪造 DamageResult + 真实节点**走表现序列，不触碰玩法结算；death 用例对第一个存活敌人 token 播死亡后在其 `death_finished` 后 `reset_visuals()` 复原。

## 5. 修改文件（8 个，精确到点）

1. `scripts/combat/damage_result.gd`：+`var attacker: Node`、`var target: Node`（非 @export，注释说明仅表现层用）。
2. `scripts/combat/combat_system.gd`：`_resolve_attack()` 内赋 `result.attacker/target`；**删除** `_spawn_damage_number()` 与 `feedback_parent_path` export（先 grep 确认无场景赋值）。
3. `scripts/player/player_controller.gd`：
   - `_ready()` 建 `CharacterToken`（name="CharacterToken"）并 `setup(PLAYER_SPRITE, SPRITE_RECT, false)`。
   - `try_move()`：改 `global_position` 前记 old world，之后 `token.play_move(old - new, 1, false)`。
   - `place_at()` / `_ready()` 初设 / `revive_for_retry()`：`token.snap()`；revive 另加 `token.reset_visuals()`。
   - `_draw()` 只保留选中金环（sprite/阴影已归 token）。
4. `scripts/enemies/enemy_controller.gd`：
   - `_ready()` 建 token：`setup(CharacterSpriteCatalog.get_texture(enemy_data.character_sprite_id), Rect2(-24,-27,48,48), true)`。
   - `_move_toward_target()`：同 player 记 old/new → `token.play_move(offset, 曼哈顿距离, false)`。
   - `_draw()`：删除阴影/sprite/占位圆，仅保留 boss 环 + HP 条；`if _is_defeated: return`。
   - `handle_defeat()`：删除 `visible = false`（保留 PROCESS_MODE_DISABLED）。
5. `scenes/world/grid_combat.tscn`：+`[node name="CombatCamera" type="Camera2D" parent="."]`、+`[node name="CombatPresentation" type="Node" parent="."] script=...`（load_steps +1×2，新 ext_resource）。
6. `scripts/world/grid_combat.gd`：+`@onready var combat_presentation := $CombatPresentation`；`_layout_portrait_grid()` 末尾调用 `combat_presentation.notify_layout_changed()`。
7. `scripts/ui/development_panel.gd`：`_build_ui()` 增加 `_section_title("COMBAT FX TEST")` + 9 个 `_make_button(...)`；回调经 `get_tree().root.get_node_or_null("Main/grid_combat/CombatPresentation")` 调 `test_effect(&"case")`。
8. `scripts/systems/game_locale.gd`：`_STRINGS` 增 `fx.miss`/`fx.dodge`/`fx.block`/`fx.critical`（en/zh_Hant 双语，参照现有条目格式）。

## 6. 实施阶段（与 task.md 对应）

- **P1** 配置 + DamageResult 引用 + CombatSystem 清理 → headless 启动验证。
- **P2** CharacterToken + player/enemy 接入（含移动 tween、死亡可见性接管）→ headless 启动；有 MCP 则截图目视。
- **P3** DamageNumber 重构（Kind/tween/描边/速度）+ 表现层接管生成。
- **P4** CombatVFX 全类别。
- **P5** CombatPresentationSystem 主序列 + hit stop + 相机震动 + 场景接线（Camera/Presentation 节点、layout snap）。
- **P6** 法术三类 +  sub hero 冲击 + 治疗浮字。
- **P7** 速度集成（auto/farming/game_speed → multiplier 传播）。
- **P8** DevelopmentPanel 测试段 + locale 字符串。
- **P9** 全量验证 + 验收清单逐项核对 + 修复。

每阶段结束至少跑：headless 启动自检（见 §8）；P9 另跑 `res://tests/` 既有用例。

## 7. 风险与注意（实现前必读）

1. **process_mode 继承**：enemy 死亡后 `PROCESS_MODE_DISABLED` 会停子节点 tween → token 必须 `PROCESS_MODE_ALWAYS`。
2. **await 挂死**：不得 await 自由节点的 tween/信号；统一 await `motion_phase_finished`（`_exit_tree` 兜底 emit）。
3. **重排瞬移**：`_layout_portrait_grid()` 直改 global_position → 必须 snap，否则 token 残留偏移。
4. 删除 enemy `visible=false` 前 grep 全仓 `visible` 对 enemy/player 的其它依赖（StageManager 清理走 queue_free，应无依赖；以 grep 结果为准）。
5. 相机加入后确认取景不变：`camera.position = viewport_rect.size * 0.5` 等价原 identity 取景；TownView 在 HUD CanvasLayer 内不受影响。
6. 不引入 `Engine.time_scale`；hit stop 只暂停 token motion tween。
7. `gl_compatibility` 下 additive CanvasItemMaterial 可用；不写 shader。
8. 浮字描边用 `draw_string_outline(...)` 保证 720×1280 可读；随机偏移限 ±12px。
9. 表现层任何路径都不得调用伤害/回合/网格写入 API（只读 + 视觉）。
10. 保留 `hud.show_critical_indicator()`、SubHeroAttackEffect 投射物等既有反馈，不重复造轮子。

## 8. 验证命令

```bash
# 资源导入/脚本编译自检
"D:/IDE/godotEngine/Godot_v4.7.2-stable_win64_console.exe" --headless --editor --quit --path G:/godotproject/darkrpg

# 战斗场景 120 帧启动自检（过滤 error/warning）
"D:/IDE/godotEngine/Godot_v4.7.2-stable_win64_console.exe" --headless --quit-after 120 --path G:/godotproject/darkrpg res://scenes/world/grid_combat.tscn

# 既有测试（headless，见 docs/testing-fixtures.md）
```

## 9. 验收清单

- 角色：静态头像可用；有阴影；移动走 tween；无需任何敌人帧表。
- 攻击：玩家有预备/冲刺/明显命中/回位；逻辑网格坐标不变。
- 命中：闪白+抖动+击退；crit/heavy 更强；死亡缩放淡出倾倒。
- VFX：slash 与 impact 可用；法术 VFX 与敌人类型无关可触发。
- 数字：目标头顶浮字；crit 明显区分；MISS/BLOCK/HEAL 各自样式。
- Hit stop：短冻结且无永久冻结；UI/输入不受影响。
- 相机：强攻击震战斗区；HUD 不震；震动后 offset 归零。
- 架构：敌人脚本无专属动画逻辑；玩法/表现分离；无重复伤害计算；Auto/Farm 照常。
- 安全：无孤儿 tween、无卡死 offset/hit stop/modulate/scale/position；切场景无报错。
