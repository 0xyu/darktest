# UI Development Harness（Headless UI 开发与验证基础设施）

为 UI（Inventory / Character / Shop / Quest / Settings / Battle HUD 等）提供一套
**默认 headless、可重复**的验证方式，让开发时不依赖 MCP、不反复启动游戏、不靠截图。

## 核心原则

1. **能 headless 验证的，绝不用 MCP。**
2. **截图只用于视觉验收（Rendering / Responsive Layout / 最终效果），不是常规调试手段。**
3. MCP 只用于真实 Runtime、真实 Input、Rendering、Responsive Layout 和最终视觉验收。

## 一次运行

```powershell
# 全部 suite
powershell -ExecutionPolicy Bypass -File G:\godotproject\darkrpg\tools\ui_harness\run_ui_harness.ps1

# 只跑一个 suite（按文件名，不含 .gd）
powershell -ExecutionPolicy Bypass -File G:\godotproject\darkrpg\tools\ui_harness\run_ui_harness.ps1 -Suite test_inventory_panel
```

等价的原生命令（包装脚本内部就是这个）：

```text
D:\IDE\godotEngine\Godot_v4.7.2-stable_win64_console.exe --headless --path G:\godotproject\darkrpg \
    --script res://tools/ui_harness/ui_harness_runner.gd [++ --suite <name>]
```

- 使用 `_console` 版引擎才能拿到 stdout。
- **退出码**：`0` = 全部通过；`1` = 有失败或 suite 加载失败（适合接入 CI）。

## 目录结构

```text
tools/ui_harness/
├── ui_harness_suite.gd        # 基类（RefCounted，无 class_name）
├── ui_harness_runner.gd       # SceneTree 入口（发现 + 驱动 suite + 汇总 + quit）
├── run_ui_harness.ps1         # 便捷包装
└── suites/
    └── test_inventory_panel.gd  # 参考 suite：EquipmentInventoryPanel
```

suite 命名约定：`test_<ui>.gd`，每个 `test_*` 方法是一个测试（coroutine）。
发现规则：扫描 `res://tools/ui_harness/suites/` 下所有 `.gd`，且必须继承基类
（通过 `get_base_script()` 链校验，不依赖全局 class 缓存）。

## 一个 suite 覆盖什么（五个维度）

| 维度 | 验证内容 | 参考实现 |
|---|---|---|
| **Scene** | 场景能 load、实例化、根节点类型正确 | `test_scene_loads` |
| **Script** | 根脚本存在、公开方法 / 信号齐全 | `test_public_api` |
| **State** | 注入 fixture 后，show/hide/选择/装备/丢弃等状态正确 | `test_open_close_and_selection` |
| **Interaction** | 点击格子（emit `cell_pressed` 或合成输入事件）触发正确行为 | `test_cell_interaction_emit` / `test_click_cell_via_synthetic_input` |
| **Data Binding** | label / 计数 与数据源（player stats / inventory）一致 | `test_data_binding` |

## 如何新增一个 UI suite（模板）

```gdscript
extends "res://tools/ui_harness/ui_harness_suite.gd"

const UIFixtureScript := preload("res://tests/fixtures/ui_fixture.gd")

var _player: PlayerController
var _panel: Control

func _mount_panel() -> void:
	_player = PlayerController.new()
	track_node(_player)                                   # 测试结束自动释放
	UIFixtureScript.apply_character_to_player(_player)    # 固定、可重复的测试数据
	var mounted: Node = await mount_scene("res://scenes/ui/YourPanel.tscn")
	_panel = mounted as Control
	_panel.call("set_player", _player)                    # apply_character 后必须重绑
	_panel.call("show_panel")
	await flush_frames(2)                                 # 让 deferred refresh / 布局落定

func test_something() -> void:
	await _mount_panel()
	expect(_panel.visible, "panel opens")
	expect_eq(_panel.get("_count_label").text, "8/60", "count binds to inventory")
```

- 断言：`expect` / `expect_eq` / `expect_ne` / `expect_contains` / `skip`。
- 交互：`click_cell(cell)`（emit 信号，主路径）、`push_click(control)`（合成鼠标事件走 viewport，证明输入真的路由到了 `_gui_input`）。
- 数据用 `UIFixture`（`res://tests/fixtures/ui_fixture.gd`，无 RNG、可重复）。

## 已知陷阱（务必遵守）

1. **`UIFixture.apply_character_to_player(player)` 会替换 inventory 对象**，面板缓存的 `_inventory` 变成孤儿 → 之后必须重调 `panel.set_player(player)`。（`test_apply_character_rebind` 是回归示例）
2. **面板每次 `_refresh()` 会 `queue_free()` 并重建所有格子** → 数据变化后**绝不复用旧格子引用**，必须重新 `get_child()`。（`test_slot_filter_toggles` 演示）
3. **不要给基类/suite 加新的 `class_name`**：冷 `--headless --script` 启动时全局 class 缓存未重建，新 class_name 不可见。子类用路径 `extends "res://tools/ui_harness/ui_harness_suite.gd"`。
4. **`MobileCombatHUD` 无父节点会崩**（`_ready()` 里 `get_parent()`）→ 只测面板本身，不直接挂 HUD；如确需 HUD，先挂到含 `StageManager/TurnManager/Player` 兄弟节点的假父节点下。
5. **面板节点是代码构建、无稳定节点名** → 用白盒 `panel.get("_member")` 读内部状态，公开行为用 `panel.call("public_method")`。
6. `EnemyBestiaryPanel` 在 headless 下 `CharacterSpriteCatalog.get_image()` 返回 null → 标本数退化为 0（不崩），只能验证开/关/结构，不能验证标本内容。
7. 合成鼠标事件用 `root.push_input(ev)`（`Input.parse_input_event` 会走 headless DisplayServer stub，可能丢事件）。
8. GDScript 无 try/catch：测试内脚本错误无法捕获 → 内置了「0 断言记失败」兜底；如需更硬可在 CI 外层加进程超时。
9. **游戏有存档，harness 每个测试前会重置它**：`grid_combat` 开机读 `StageProgressSave`（玩家侧关卡进度：位置 / 解锁上限 / 通关集合 / 一次性内容消费集合）并从存档关号继续战斗。所以基类 `run_all()` 在每个测试前调用 `_reset_game_save()`：把游戏的存档路径重定向到 harness 自己的 scratch 文件（`res://.godot/ui_harness/stage_progress.json`，在 gitignore 的 `.godot/` 内）并删除它。效果有两个 —— 每个测试都从"全新玩家"开始（否则上一个测试打过的关会被下一个测试读档恢复，测试就依赖执行顺序），且**测试永远不会读写 `user://` 里的真存档**。要在单个测试里验证"关掉再开"，就在该测试内卸载再挂载场景（见 `suites/test_stage_save.gd`）。

## 与 MCP / 现有测试的关系

- **纯数据 suite**（如 `res://tests/test_ui_fixture.gd`）继续走原路径：MCP `test_run` 或
  `McpTestRunner.run_suites(...)` headless 一条命令。这些 suite 不需要 frame。
- **UI suite**（本 harness）需要 frame 推进，`McpTestRunner` 的同步路径不 pump
  `process_frame`，所以**必须**用本 harness 的 SceneTree runner。
- 什么时候用 MCP：真实运行时的 Rendering / 输入手感 / 响应式布局 / 最终视觉验收。
  其余能在 headless 里断定的，全部 headless 解决。
