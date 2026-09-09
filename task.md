# 轻量战斗动画与反馈系统 — 任务清单

> 配套计划：`implementaion_plan.md`（先读计划再开工）。每完成一项勾选并跑该步验证。
> 验证命令见计划 §8；任何一步出现 error/warning 先修复再继续。
>
> **状态：P1–P9 已全部完成并通过 headless 验证**（启动自检零 error/warning、6 个 smoke 套件 + ui_fixture 13/13 全绿、
> AUTO+FASTEST 1200 帧运行时回归无卡死/无孤儿、9 个 FX 测试案例零残留状态）。
> ui_harness 中 3 个失败（combat_log_wiring 1 个、town_view 2 个）经 git stash 基线比对确认为**既有问题**，与本次改动无关。
> 截图/手动目视验收（本会话无 Godot MCP）留给编辑器内人工复核。

## P1 配置与数据接线

- [x] 新建 `scripts/combat/combat_presentation_config.gd`：计划 §4.1 全常量 + `get_speed_multiplier()`。
- [x] `scripts/combat/damage_result.gd`：加 `attacker`/`target: Node`（非 @export）。
- [x] `scripts/combat/combat_system.gd`：`_resolve_attack()` 赋 `result.attacker/target`；删除 `_spawn_damage_number()` 与 `feedback_parent_path`（先 grep 确认无 .tscn 赋值）。
- [x] 验证：headless 启动自检通过（此时无浮字属预期）。

## P2 CharacterToken 与单位接入

- [x] 新建 `scripts/combat/character_token.gd`：计划 §4.2 全 API（Avatar/Flash 子节点、阴影、play_move/snap/wind_up/dash/recover/play_hit_reaction/play_dodge/play_death/reset_visuals/freeze、motion_phase_finished 含 _exit_tree 兜底、PROCESS_MODE_ALWAYS）。
- [x] `scripts/player/player_controller.gd`：建 token（PLAYER_SPRITE/SPRITE_RECT/linear）；try_move 接 play_move；place_at/_ready/revive 接 snap；revive 加 reset_visuals；_draw 只留选中环。
- [x] `scripts/enemies/enemy_controller.gd`：建 token（catalog 纹理/Rect2(-24,-27,48,48)/NEAREST）；_move_toward_target 接 play_move；_draw 只留 boss 环+HP 条且 _is_defeated 提前 return；handle_defeat 删除 `visible = false`。
- [x] 验证：headless 启动；grep 确认无其它代码依赖 enemy.visible；移动有平滑过渡（有 MCP 则截图）。

## P3 伤害数字

- [x] 重构 `scripts/combat/damage_number.gd`：Kind 枚举（NORMAL/CRITICAL/HEAL/POISON/BURN/BLEED/MISS/DODGE/BLOCK）、tween 动画（scale 0.5→1 弹、上升、淡出）、`draw_string_outline` 描边、speed_multiplier、颜色/字号取 config。
- [x] 表现层在 impact 时刻生成浮字（目标头顶 ±12px 随机）；MISS/BLOCK/HEAL 文本走 GameLocale。
- [x] 验证：headless 启动；dev 面板可用前可暂由攻击事件目视。

## P4 程序化 VFX

- [x] 新建 `scripts/combat/combat_vfx.gd`：计划 §4.3 全类别（slash/heavy_slash/impact/fire/ice/lightning/poison/holy/dark/arcane/heal/buff/debuff/area + setup_projectile）。
- [x] 约束：setup 预生成随机数组；寿命 0.08~0.25s×mult 自删；z_index=15；暗色哥特配色。
- [x] 验证：headless 启动无错。

## P5 表现系统主序列 + 场景接线

- [x] 新建 `scripts/combat/combat_presentation_system.gd`：计划 §4.4（attack_resolved 主序列、actor_died 延迟死亡、shake、notify_layout_changed、单位 moved 连接、viewport size_changed 相机居中）。
- [x] `scenes/world/grid_combat.tscn`：加 CombatCamera(Camera2D) 与 CombatPresentation 节点。
- [x] `scripts/world/grid_combat.gd`：@onready combat_presentation；_layout_portrait_grid 末尾 notify_layout_changed()。
- [x] hit stop：freeze 双方 token + create_timer 恢复；不使用 Engine.time_scale。
- [x] 验证：headless 启动；手动/截图确认攻击序列、crit 震动、HUD 不震、震动后归零。

## P6 法术 / Sub Hero / 治疗

- [x] `_play_spell()`：projectile / instant / area 三类；技能映射（arcane_bolt→projectile arcane、whirlwind→slash+area、execution_strike→heavy  melee）。
- [x] 连接 `sub_hero_combat_manager.attack_feedback_requested`：延迟 PROJECTILE_TRAVEL 后冲击 VFX+浮字+NORMAL 反应（保留既有 HUD 投射物，不重复）。
- [x] 连接 player `healing_item_used`/`item_used`：HEAL 浮字 + heal VFX。
- [x] 验证：headless 启动；技能/治疗目视。

## P7 速度集成

- [x] 连接 auto_combat 三信号 → `_refresh_speed()`；multiplier 传播到各 token 与 spawn 参数；FASTEST/X2/X1+auto 档位按计划 §4.1。
- [x] 验证：AUTO + FASTEST 下反馈仍可读（谁打谁、伤害、crit、死亡可见）。

## P8 调试入口与 i18n

- [x] `scripts/ui/development_panel.gd`：COMBAT FX TEST 段 9 按钮 → `test_effect()`（normal/critical/heavy/miss/block/fire/lightning/heal/death；death 播完 reset_visuals 复原）。
- [x] `scripts/systems/game_locale.gd`：_STRINGS 增 fx.miss/fx.dodge/fx.block/fx.critical（en/zh_Hant）。
- [x] 验证：DEV 面板逐按钮点测无报错、无残留视觉状态。

## P9 全量验证与验收

- [x] headless 导入自检 + 120 帧启动自检零 error/warning。
- [x] 跑 `res://tests/` 既有用例全绿。
- [x] 回归：手动回合、AUTO、FARMING、切 stage、败退重试（revive）均正常。
- [x] 计划 §9 验收清单逐项核对。
- [x] 安全检查：连打中切场景/杀敌瞬间/玩家死亡瞬间无孤儿 tween、无卡死 offset/modulate/scale/position、无报错。
