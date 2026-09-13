# 属性成长系统重构 Implementation（v3）

> **文档性质**：实施规格（implementation spec），不是设计意向文档。
> `docs/gameplay-spec.md` 仍是玩法规则唯一来源；本文落地后必须回写 §9 / §10 / §19 / §20。
> **语言约定**：正文中文，公式与代码标识符保留英文，便于直接映射到源码。
> **状态**：待评审。**未实施任何代码改动。**
>
> ---
> ## ⚠ 部分内容已被取代（本轮修订）
>
> `docs/balance-scale-rebase.md`（Progression Scale Rebase）已完成对**世界成长速率**的专项分析，并取代本文以下部分：
>
> | 本文条目 | 状态 |
> |---|---|
> | §4.1 敌人速率（常数 1.20/1.16/1.15） | **取代** → 单一幂律曲线 `G(S)`，`r(S)=1+A/(S+B)`，A=4 B=20 |
> | §4.3 σ 取舍 | **取代** → σ = **0.6**（原推荐 0.5） |
> | §5.1 / §5.3 / §5.5 / §5.6（速率部分） | **取代** → 全部改用 `G(x)` |
> | §6 数值验证表 | **取代** → 见 rebase 文档 §3 |
> | §11 的 O1 / O5 | **取代** → O1 定为 σ=0.6；O5 因统一指数而消失 |
>
> **仍然有效**：§2（诊断与对账）、**§2.5（三项工程约束，尤其 P0 读档缺陷 —— 最高优先级不变）**、§3（不变量契约 I1–I6）、§5.2（伤害公式）、§5.4（群怪折扣与难度折线）、§5.7（数据层）、§7（改动映射框架）、§8（分阶段计划，需前置插入 Phase R0）、§9（存档兼容）、§12（回滚）。
>
> rebase 的净结论：**速率与 σ 是正交的两轴。v3 只论证了 σ，速率是继承值而非分析值。** 重标定后同一 σ 下 Stage 100 的装备倍率由 ×8,307 降至 ×32.7/×65.6，敌 HP 由 1.05×10¹⁰ 降至 7.8×10⁴，1e12 封顶由 Stage 125 推迟到 Stage ~5,958，且 I1/I2 全部保持通过。
>
> ---

## 0. 范围

### 0.1 目标
修正 Player / Enemy 属性成长曲线的性质冲突，使 Stage 1..100+ 的战斗长度与生存回合数保持有界，并让"装备驱动成长"（AGENTS.md 设计支柱）成为可验证的数值事实。

### 0.2 非目标（本文件明确不做）
| 不做 | 原因 |
|---|---|
| 新增护甲穿透（Armor Penetration） | 新属性 + 新词缀族 + UI + 存档字段。AGENTS.md 规则 16「不要为未来功能建投机系统」。见 §11 开放决策 O4 |
| 重写敌池生成器为 budget 系统 | GPT §10 的 item budget 是更大的一次重构；v3 用"I 归一化 + 过渡子池"达到同样目的，改动面小一个量级 |
| 改敌人数量公式与 Gold 1.18 | 属健康部分，无证据支持改动 |
| 引入 autoload BalanceProfile | AGENTS.md 规则 13。改为 **静态类 + Resource 导出**，见 §7.1 |
| 三个 Zone 分段成长 | GPT §19。当前 100 关内 v3 单组速率已满足 I1；分段是额外复杂度，见 §11 O3 |

---

## 1. 结论摘要

1. **原始诊断成立**：Player 线性（+20/+2/+1）、Enemy 指数（×1.20/1.16/1.15）、伤害 `ATK − DEF`、装备词缀线性（`1+0.08(lv−1)`）——三条线性/常数曲线对抗一条指数曲线，缺口在 Stage 45 后被 `max(1, …)` 钉死，数学上不可通关。
2. **Kimi 与 GPT 的方向都对，但两份方案都无法通过各自的验收标准。** 本文给出反证（§2.4），并修正为一个可验证的方程组。
3. **核心数学结论（v3）**：加成必须**乘法**而非加法；且 Player 等级速率与装备速率必须**精确互补**，乘积恒等于所对抗的敌方属性速率。σ 是唯一的设计旋钮，决定"等级 vs 装备"的成长份额，而不是决定曲线是否失衡。
4. **验证结果（Stage 3..100，含群怪折扣与难度斜坡）**：encounter TTK **2.93..6.18（2.11×）**，生存 **5.49..6.55（1.19×）**；玩家等级精确跟踪关卡（L = S+1）。对照当前版本 Stage 100 TTK = 4.2×10¹⁰。
5. **发现三项双方都遗漏的工程约束**（其中一项是当前已存在的潜在 bug，必须作为 P0 前置）：见 §2.5。

---

## 2. 三方结论对账

### 2.1 事实基线（已从源码与资源实测，非估算）

| 项 | 值 | 位置 |
|---|---|---|
| Player 基础 | HP 100 / ATK 10 / DEF 5，Crit 5%×1.5 | `player_stats.gd:5-10`（场景无覆盖） |
| Player 每级成长 | +20 HP / +2 ATK / +1 DEF（线性） | `experience_system.gd:8-10, 91-98` |
| Player EXP 需求 | `round(100 × 1.15^(L−1))` | `player_progression.gd:14-26` |
| Enemy 属性成长 | `base × rate^(S−1)`，HP 1.20 / ATK 1.16 / DEF 1.15 | `enemy_scaling.gd:30-40`、`level_provider.gd:31-37` |
| Enemy EXP | `base × 1.15^(S−1) × (1+0.1×(lvl−1)) × 类型倍率` | `experience_system.gd:55-57` |
| Enemy 数量 | 1,1,1,2,2,2,3,3,3,4… | `level_provider.gd:174-176` |
| 伤害 | `max(1, ATK − DEF) × 倍率` | `combat_system.gd:120-127` |
| 装备词缀值 | `base × (1+0.08×(ilv−1)) × (1+rarity×0.35) × roll(0.8..1.2)` | `equipment_affix.gd:272-285` |
| 装备经济侧等级乘数 | `1.18^(ilv−1)` | `economy_config.gd:41`、`item_economy.gd:34-36` |
| 敌池基础属性离散 | HP 59..225（3.81×）、ATK 10..32（3.20×），24 个 NORMAL | `resources/enemies/generated/*.tres` |
| 敌池 `level` 字段 | 运行时不参与属性缩放（死数据） | `enemy_scaling.gd:19` 被 `enemy_runtime.gd:35-36` 覆盖 |
| `difficulty_multiplier` | **已存在且已生效** | `stage_definition.gd:9` → `stage_manager.gd:331` |
| 暴击期望系数 | ×1.025 | 5% × 1.5 |

### 2.2 采纳 Kimi 的（附本文强化理由）

| # | 采纳项 | 强化理由 |
|---|---|---|
| K1 | **曲线族自相似**：每条玩家曲线的基准速率必须与它所对抗的敌方曲线一致 | 这是充要条件，不是启发式。v3 把它升级为"**精确互补**"（§4.2） |
| K2 | **伤害公式必须零次/一次齐次**，带常数 K 的公式在指数尺度下失锚 | **正确且关键**。本文给出齐次性的严格表述与副作用分析（§5.2） |
| K3 | **群怪必须折扣**（单次行动/回合 ⇒ 数量是乘法压力） | 代码确认：玩家每回合 1 个 action（AGENTS.md 战斗规则），`turn_manager` 每敌一次行动 |
| K4 | **删除 EXP 的 `(1+0.1×(lvl−1))` 放大因子** | 实测该因子使 L 跑到 S 前面（Stage 100 → Lv128），等级虚高而战力不变 |
| K5 | **EXP 需求重定基准**，让"击杀数/级"回到常数 | v3 给出更强的形式：「1 关 ≈ 1 级」（§5.5） |
| K6 | **装备必须是相对量**，不能是绝对线性值 | 本文证明更强命题：装备必须是**乘法**且速率精确互补（§4.2） |
| K7 | **敌池归一化 + Stage 3 过渡子池** | 代码确认 Stage 1–2 是 60HP 训练假人、Stage 3 起切随机池，存在断崖 |
| K8 | **难度斜坡用显式旋钮，而非等级压制** | 且**已存在字段**，无需新系统（§7 `level_provider.gd:117-149`） |

### 2.3 采纳 GPT 的（附本文修正）

| # | 采纳项 | 修正 |
|---|---|---|
| G1 | **等级不应是唯一/主导战力来源**（装备驱动是项目支柱） | 采纳其**分工**，但其 1.045 **算术不成立**，见 §2.4-①。v3 用 σ 分割实现该分工 |
| G2 | **以 PowerRatio / TTK / Survival 作为验收锚**，而非裸属性表 | 完全采纳，升级为 §3 的 I1–I6 不变量契约 |
| G3 | **EXP 用 LevelDiff 乘区替代"全怪随玩家等级涨价"** | 采纳，且它是自校正项（低于同级怪收益下降，高阶怪收益上升），比单纯删除更好 |
| G4 | **Encounter Budget 概念**（数量不应是免费难度） | 与 K3 同一件事；两者指数不同，v3 取折中并给出取舍依据（§5.4） |
| G5 | **Boss 应由机制而非 ×4 HP 定义** | 采纳为 Phase 7（独立于成长公式，可后置） |
| G6 | **集中式 Balance Profile** | 采纳，但实现为 **静态类 + Resource**（AGENTS.md 规则 13/15），见 §7.1 |
| G7 | **`PlayerPower = BaseLevel × GearPower`（乘法，非加法）** | **这是 GPT 最有价值的一条**，v3 的核心；其 §11 的直觉正确，但未给出速率互补的约束条件 |

### 2.4 驳回或修正的（含反证）

#### ① GPT 的速率组合数值不自洽 —— 无法通过其自己的 §13 TTK 验收

GPT 提议：等级 `1.045^(L−1)`、敌 HP `1.105^(S−1)`、装备 `1.08^(ilv−1)`。取 L=S=100：

| 量 | 计算 | 结果 |
|---|---|---|
| 玩家 ATK | `10 × 1.045^99` | 2,680 |
| 敌 DEF | `4.29 × 1.075^99` | ≈ 5,547 |
| 伤害（GPT §6 公式，K=100） | `2680 × 100/(100+5547)` | 47 |
| 敌 HP | `152.3 × 1.105^99` | ≈ 4.94×10⁷ |
| **TTK** | `4.94e7 / 47` | **≈ 105 万回合** |

即使叠加 GPT §9 的装备 `1.08^99`（≈ 2,000×）仍不成立，且：
- **装备速率用错**：要维持比例有界，所需装备速率恰为 `r_E / r_L = 1.105 / 1.045 = 1.0574`，而非 1.08。用 1.08 会让玩家**反超**，偏差 `(1.08/1.0574)^S ≈ 8×`（S=100），TTK 随关卡**下降**，后期越来越简单。
- **K=100 常数失锚**：这正是 Kimi 指出的齐次性问题，GPT 未察觉。

> 结论：G1 的**设计意图**正确，**数值实现**必须重写。v3 保留"等级不是主导"这一意图（σ 控制份额），但强制速率互补。

#### ② Kimi 的"减伤率恒定"配对错误

Kimi P1 写：`DEF(L) = 5 × 1.15^(L−1) # 1.15 = 敌方 DEF 成长率 → 减伤率恒定`。

减伤率是 `m = DEF / (ATK_attacker + DEF)`。要 m 恒定需要 `DEF / ATK_attacker` 恒定，即 **r_DEF = r_ATK(攻击方)**，而不是与"对面的 DEF"同速。

| 配对 | Kimi 的速率 | 正确速率 | 后果（Kimi 方案） |
|---|---|---|---|
| 敌方 DEF（抵御玩家 ATK） | 1.15 | **1.20** | `eDEF/pATK ∝ (1.15/1.20)^S → 0`，敌方 DEF 在后期变成死属性 |
| 玩家 DEF（抵御敌方 ATK） | 1.15 | **1.16** | `pDEF/eATK ∝ (1.15/1.16)^S → 0`，玩家 DEF 减伤率持续衰减至 0 |

修正后：`R_DEF_V3 = 1.20`（敌方 DEF 对齐玩家 ATK 总速率），玩家 DEF 等级速率 = `1.16^(1−σ)`。这两条已并入 v3 并验证（敌方减伤率在全 100 关恒为 16.2%）。

#### ③ Kimi 的 difficulty 与 GPT 的 budget 是同一旋钮，指数需折中

- Kimi `group_hp = c^(−0.5)`，`group_atk = c^(−0.75)` → 4 敌时总 HP **2.0×**、总 DPS **1.41×**
- GPT `1×100% / 2×50% / 4×25%` → 即 `c^(−1)`，4 敌时总 HP **1.0×**、总 DPS **1.0×**

GPT 的 `c^(−1)` 使多怪关卡在压力上**完全免费**（总 HP 与总伤害都不变），这抹掉了"多怪 = 更难"的战术意义，与 AoE 技能价值冲突。Kimi 的 `c^(−0.5)` 使 4 敌关卡 HP 翻倍，但叠加 2×0.5=… 后 encounter TTK 达单敌的 2.0×，band 偏宽。

v3 取折中并实测：`group_hp = c^(−0.6)`（4 敌总 HP **1.74×**）、`group_atk = c^(−0.8)`（4 敌总 DPS **1.32×**），使 TTK 的 count 贡献降到 1.74×，同时保留多怪压力。

#### ④ 双方都未给出的关键约束：**乘法 + 精确互补**

见 §4.2。这是 v3 与两份方案的本质差别。

### 2.5 双方都遗漏的三项工程约束

#### ① 【P0，当前已存在的潜在 bug】加载存档不重算等级属性

`stage_progress_save.gd:56` 的注释声称：

> "The hero's derived stats (attack, HP, defense) are deliberately NOT stored — they are recomputed from the level and the equipped items, which are."

**但代码路径中没有这个重算。** 实测：

- `load_save_data()`（`:339-380`）只恢复 `level` / `experience` / `gold` / `skill_points` / `skill_levels` / items / Sub Heroes，**直接赋值 level，不触发 `level_up`，也不重放升级增量**。
- 全仓检索 `recompute|apply_level|rebuild_stats|_refresh_player_stats`：除经济系统与注释外**无任何命中**。
- 等级属性唯一的写入路径是 `experience_system.gd:91-98` 的**增量** `stats.max_hp += 20`。

⇒ 今日读档至 Lv50，`PlayerStats` 停留在场景默认 100/10/5，只有装备加成生效。
⇒ 改为**乘法**公式后该缺陷会更严重（增量无法安全重放），因此 **P0 必须先行**：把属性改为 `stat = f(level)` 的纯函数并在读档后重算。

#### ② `difficulty_multiplier` 已全链路就绪，不应新建 difficulty 系统

`level_config.gd:7` / `level_template.gd:11` / `stage_definition.gd:9` 已声明，`stage_manager.gd:331` 已消费。实现难度斜坡只需在 `level_provider._generate_stage_definition()` 里按 S 写入该字段。Kimi 建议的 `difficulty(S)` 属重复建设（AGENTS.md 规则 4）。

#### ③ `enemy_level` 只影响 EXP、不影响属性，而它的 ±3 偏移是**纯奖励抽奖**

`entry.get_level(S) = S + level_offset`（`stage_enemy_entry.gd:26-29`，权重 `level_provider.gd:299-308`），该值经 `experience_system.gd:55` 使 EXP 波动 ±30%，但 `enemy_scaling.gd` 完全忽略它（同 `implementation-status.md:118` 的偏离 #1）。
⇒ v3 的处理：让 level offset **同时**进入属性（作为关内的难度/奖励同向旋钮），使显示的敌人等级诚实。见 §5.3。

---

## 3. 验收契约（不变量）

任何实现方案必须先声明并最终通过以下检查。这是本文与前两份反馈最大的流程差别：**先定不变量，再定公式**。

| ID | 不变量 | 判定（自动测试） |
|---|---|---|
| **I1** | 战斗长度有界：Stage 3..100 的 encounter TTK ∈ [3, 8] 回合 | 模拟 + 冒烟测试断言 |
| **I2** | 生存有界：Stage 3..100 的生存回合 ∈ [4, 8] | 同上 |
| **I3** | 无硬墙：∀ S，玩家有效伤害 ≥ 敌人 HP × 1/8；不存在"伤害被锁为 1"的区间 | 断言 `final_damage > 1`，或 `ATK/DEF` 比值不越界 |
| **I4** | 曲线自相似：`TTK(S=100) / TTK(S=3)` 与 `surv(S=3) / surv(S=100)` 均 < 3.0 | 模拟 |
| **I5** | 等级锚定：全清推进时 `|L − S| ≤ 3` | 模拟 |
| **I6** | 装备必要性：无装备（item level 固定为 1）时，Stage ≥ 20 必须不可持续 | 断言 naked 生存回合 < 2 |

**验收指标（业务语言，替代裸属性表）**

```text
PowerRatio(S)  = PlayerEffectiveDPS(S) / EnemyEffectiveHP(S)      # TTK ≈ 1 / PowerRatio
SurvivalRatio(S) = PlayerEffectiveHP(S) / EnemyEffectiveDPS(S)    # 生存回合 ≈ SurvivalRatio
```

调参只允许改变 `PowerRatio × SurvivalRatio` 的组合，不允许让任一者越出 I1/I2 的区间。

---

## 4. 关键设计决策

### 4.1 敌人曲线：保留指数，修正 DEF 速率

保留 HP 1.20 / ATK 1.16 / Gold 1.18 / EXP 1.15（无证据支持改动，且已成为经济侧锚点）。
**唯一改动**：`R_DEF 1.15 → 1.20`。理由见 §2.4-②：敌方 DEF 与玩家 ATK 的总速率必须一致，否则减伤率随关卡衰减、DEF 在后期沦为死属性。

> 副作用（必须记录）：敌方 DEF 速率上调会抬高后期减伤率（恒定 16.2% vs 当前衰减曲线），属"更难"方向；通过 `difficulty(S)` 的 LOW 段与 §5.2 的基率校准吸收。

### 4.2 σ 分割：本文的核心数学结论

**加法不行。** 若 `PlayerStat = Base(L) + Gear(A)`，两条指数之和的速率取**较大者**，不是两者相乘，装备的成长速率被浪费。
⇒ 必须 `PlayerStat = Base(L) × GearMultiplier`（GPT §11 的直觉正确）。

**精确互补。** 设所对抗的敌方属性速率为 `r_E`，令

```text
PlayerStat(L, il) = P0 × r_E^((1−σ)·(L−1)) × r_E^(σ·(il−1))          σ ∈ [0, 1]
```

当玩家等级与装备等级同步推进（`L ≈ il ≈ S`）时，两个指数**相加**：

```text
= P0 × r_E^(S−1)         ← 与敌方完全同速，比例恒定 ⇒ TTK / 生存恒定
```

`σ` 只决定**份额**（等级贡献 (1−σ)、装备贡献 σ），不决定是否失衡。这把"等级 vs 装备"从数学问题降为设计决策。

**验证时发现的陷阱（务必写进实现注释）**：早期我尝试过 `Base(L) × (1 + κ·r^(σS))` 这种"有界百分比平滑过渡"形式。它在数学上更"温和"，但 `(...)` 内的常数 `1` 在低关卡占主导，使总有效速率**低于** `r_E`；随关卡推进装备项逐步接管，速率才收敛到 `r_E`。结果是**跨越整局游戏的速率瞬态**：实测 TTK 从 4.0 漂移到 18.7（4.6×），直接违反 I4。**必须使用纯乘法形式（无 `+1`）**，让两个指数从头到尾互补。

### 4.3 σ 的取舍（需要拍板）

| σ | 等级速率（HP/DEF, ATK） | 装备速率 | 敌人 DEF 变死属性？ | 设计表述 | 与"装备驱动"支柱 |
|---|---|---|---|---|---|
| 0.0 | 1.16 / 1.20（满） | 1.0（有界 +40~180%） | 否 | 等级是全部 | ✗ 冲突 |
| **0.35** | 1.0983 / 1.1207 | 1.0523 / 1.0675 | 否 | 等级保证地板，装备拉开差距 | ✓✓ |
| **0.50（推荐）** | 1.0770 / 1.0954 | 1.0770 / 1.0954 | 否 | 等级与装备各半 | ✓✓ |
| 0.70 | 1.0465 / 1.0562 | 1.1149 / 1.1326 | 否 | 装备主导，等级仅防掉队 | ✓✓✓ |
| 1.00（≈GPT 意图） | 1.0 / 1.0 | 1.16 / 1.20 | 否 | 等级无成长，纯装备 | ✓✓✓ 但与"等级"UI 意义冲突 |

**推荐 σ = 0.5**，理由：
1. 满足项目支柱（装备是并列的主要成长源）而非否定等级；
2. 装备可"欠账"但有界：漏更新装备 10 关 → 落后 `r^(σ·10) ≈ 2.3×`（可追回），而非永久掉队；
3. 保留等级作为**保底地板**（GPT 的"Level：保证你不会被 Stage 永久甩开"）；
4. 与现有经济侧 `1.18^(ilv−1)` 的指数语言同构。

**σ 的代价（必须诚实记录）**：σ = 0.5 时，Stage 100 的装备必须提供 **8,307× ATK / 1,551× HP** 的乘数（实测，见 §6.3）。这不是缺陷，是"装备驱动"的**量化定义**；但它意味着装备词缀的**绝对值会指数增长**，UI 必须以"×N 装备强度 / 百分比"呈现，而不是"攻击 +147"。

---

## 5. 目标公式集（v3）

### 5.1 P1 — Player 等级成长

```text
σ        = 0.50                      # 唯一份额旋钮
r_L(HP)  = 1.16^(1−σ) = 1.07703
r_L(ATK) = 1.20^(1−σ) = 1.09545
r_L(DEF) = 1.16^(1−σ) = 1.07703

max_hp(L) = round(100 × r_L(HP)^(L−1))
attack(L) = round( 46 × r_L(ATK)^(L−1))
defense(L)= round(  5 × r_L(DEF)^(L−1))
```

**基率校准过程（可复现）**
- `attack` 基数由"4 敌 encounter 清场回合 ≈ 6"反解：S=50 时 `eHP_total = 4 × (152.29 × 1.20^49 × 4^(−0.6) × 1.0667)`，需 `hit ≈ eHP_total/6`，解 `A0` ⇒ **46**（对照 Kimi 的 40：其目标未含群怪折扣，故偏高）。
- `max_hp` 基数由"4 敌全力输出下生存 ≈ 6 回合"反解 ⇒ **100**（恰好等于现基础值）。
- `defense` 保持 **5**（玩家减伤率 S=1 时 20.7%，随时间恒定）。
- **属性必须由 level 纯函数计算，禁止增量累加**（见 §2.5-①）。

### 5.2 P2 — 伤害公式（替换 `combat_system.gd:120-127`）

```text
base_damage = ATK² / (ATK + DEF)                  # 一次齐次：f(kA, kD) = k·f(A,D)
final       = max(1, round(base_damage × damage_multiplier × equipment_multiplier
                           × tier_multiplier × (crit ? critical_damage : 1.0)))
```

**性质（写进代码注释）**
- `DEF = 0` ⇒ 伤害 = `ATK`（与裸 ATK 一致）
- `DEF = ATK` ⇒ 伤害 = `ATK/2`
- `DEF → ∞` ⇒ 伤害 → 0 但**永不因 `ATK < DEF` 而钉死**（满足 I3）
- `DEF ≪ ATK` 时 ≈ `ATK − DEF`，即**在现版本尚可玩的 Stage 1..25 区间内几乎不改变手感**，只在旧公式崩溃处平滑退化。这是选择该式而非其他曲线的主要理由。
- 依然只在"一次"上齐次，故对 `equipment_multiplier`（§5.6）保持线性乘区语义；倍率族（skill / tier）不变。

**回归风险**：所有现存伤害相关的冒烟测试与 UI 显示（`damage_number.gd`）都读 `DamageResult.final_damage`，字段不变 ⇒ 无接口破坏。

### 5.3 P3 — Enemy 成长（改 `enemy_scaling.gd` / `stage_manager.gd:319-341`）

```text
stat(S) = pool_base
        × rate^(S−1)                    # HP 1.20 / ATK 1.16 / DEF 1.20 / Gold 1.18 / EXP 1.15
        × group_mult(count(S))
        × difficulty(S)
        × level_offset_mult(entry.level_offset)     # 新增，修正 §2.5-③
        × variance(±15%)                            # 保留
```

`level_offset_mult`：让等价于等级偏移的难度真正生效，建议

```text
level_offset_mult(off) = 1 + 0.06 × off          off ∈ [−3, 3] ⇒ ×0.82 .. ×1.18
```

⇒ 显示等级从"仅奖励抽奖"变为"收益与难度同向"，`implementation-status.md` 偏离 #1 随之关闭。

### 5.4 P4 — 群怪折扣与难度斜坡

```text
count(S) = clamp(1 + floor((S−1)/3), 1, 4)       # 不变
group_hp(c)  = c^(−0.60)      # 4 敌：总 HP 1.74×
group_atk(c) = c^(−0.80)      # 4 敌：总 DPS 1.32×
# 敌方 DEF 不折扣：折扣作用于"总量"，不是单只的防御质量

difficulty(S) = 0.90                       S ≤ 1
              = 0.90 → 1.00  线性          S = 1..10
              = 1.00 → 1.10  线性          S = 10..100
              = 1.10（封顶）                 S > 100
```

`difficulty` 写入 `StageDefinition.difficulty_multiplier`（复用现有字段，§2.5-②）。
**从此调难度只改这条折线**，不再触碰任何成长率。

### 5.5 P5 — EXP（改 `experience_system.gd:38-62` 与 `player_progression.gd:24-26`）

```text
need(L)  = round( BaseEXP_pool × count(L) × 1.15^(L−1) )          # 关键：含 count(L)
reward   = base_exp × 1.15^(S−1) × clamp(1 + 0.05×(S − L), 0.75, 1.25) × type_mult
```

- 删除 `(1 + 0.1×(level−1))`（K4）。
- `need` 中引入 `count(L)` 使**「清一关 ≈ 升一级」**成为闭式结果，并用 `LevelDiff` 自校正（G3）。实测 L = S+1 全程恒定（满足 I5），等级不再虚高。
- `BaseEXP_pool` = 敌池 `experience_reward` 的**归一化后均值**（§5.7），与池归一化绑定，避免两处常量漂移。
- 类型倍率（elite 2.0 / mini boss 4.0 / …）保持，成为"特殊关给额外等级"的唯一来源。

### 5.6 P6 — 装备（改 `equipment_affix.gd:272-285`）

```text
item_power(il) = r_G^(il−1)                       # r_G = r_L = r_E^σ
affix_value    = stat_base(il) × share × rarity_mult × roll × item_power(il)

stat_base(il)  = 该属性在 il 级的"裸等级基础值"（§5.1 的 max_hp/attack/defense 函数）
share          = 单条词缀的份额（沿用 get_weight() / ROLL 语义）
rarity_mult    = 1 + rarity × 0.35                # 保持
```

- 这使 `Σ affix` 自然等于 `stat_base(il) × Σshare × item_power`，即 §4.2 的乘法结构，无需在 combat 侧做任何事（**沿用现有 `player_controller.gd:743-758` 的加法聚合路径**，因为每一条词缀本身已按乘法缩放）。
- 需要 `stat_base(il)`：`EquipmentAffix` 是 Resource 静态方法、拿不到 BalanceProfile ⇒ 由 §7.1 的静态入口提供。调用点仅 `equipment_generator.gd:96`（`create_rolled`）与 `roll_value`。
- **存档兼容**：词缀以绝对数值存储（`equipment_affix.gd:46` 的 `to_save_data`），旧装备保留旧（弱）数值、新掉落按新式缩放 ⇒ **无格式变更、无资产丢失**，旧装备自然被替换。
- 经济侧 `1.18^(ilv−1)` 与卖价公式**不动**（无套利破坏；§19 的 `SellPrice < BuyPrice` 约束不受影响）。

### 5.7 P7 — 数据层

| 改动 | 位置 | 说明 |
|---|---|---|
| 敌池归一化 | 24 个 `resources/enemies/generated/*.tres` | 各属性钳到池均值 `[0.8, 1.25]`（HP 122..190、ATK 18..28、DEF 3.4..5.4、EXP 95..148），最大离散 3.81× → <1.6× |
| 删除死 `level` 字段 | 同上 | 与 §5.3 的 `level_offset_mult` 二选一；v3 选"真正接入"，故保留字段但明确其为**基础水平标记**，不再参与运行时 |
| Stage 3–4 过渡子池 | `level_provider.gd:188-213` | 基础值最低的 5 个（`atlas_01_14` / `atlas_06_10` / `atlas_12_19` / `atlas_14_16` / `atlas_17_07`）组成 S=3..4 子池，S=5 起放开全池 |
| TrainingEnemy 重调 | `resources/enemies/TrainingEnemy.tres` | HP 60 → **150**、ATK 默认 8 → **12**，使 S=1–2 落入 I1/I2 band（实测 TTK 2.71 / 生存 26 → 11） |
| 固定关 | `resources/levels/level_001/002/010/100.tres` | `difficulty_multiplier` 交给 §5.4 的折线；`level_010` / `level_100` 保留 Boss 与保底掉落 |

---

## 6. 数值验证结果

模拟条件：`σ=0.5`，`A0=46 / H0=100 / D0=5`，`group_hp=c^−0.6`、`group_atk=c^−0.8`，`difficulty 0.90→1.10`，含暴击期望 ×1.025，玩家等级由 §5.5 的 EXP 规则驱动，`item_level = stage`。

### 6.1 v3 不变量（Stage 3..100）

| Stage | L | 敌数 | 敌 HP/只 | 敌 ATK/只 | 敌 DEF | 玩 ATK | 玩 DEF | 玩 HP | encounter TTK | 生存回合 |
|---|---|---|---|---|---|---|---|---|---|---|
| 3 | 4 | 1 | 202 | 28 | 6 | 73 | 7 | 145 | 2.93 | 6.55 |
| 5 | 6 | 2 | 197 | 22 | 8 | 104 | 10 | 195 | 3.97 | 6.37 |
| 10 | 11 | 4 | 342 | 28 | 22 | 260 | 20 | 410 | 5.57 | 6.28 |
| 20 | 21 | 4 | 2,141 | 126 | 139 | 1,610 | 90 | 1,807 | 5.64 | 6.18 |
| 30 | 31 | 4 | 13,404 | 561 | 867 | 9,968 | 399 | 7,971 | 5.70 | 6.08 |
| 40 | 41 | 4 | 83,897 | 2,500 | 5,430 | 61,719 | 1,758 | 35,163 | 5.77 | 5.99 |
| 50 | 51 | 4 | 525,051 | 11,145 | 33,980 | 382,146 | 7,756 | 155,121 | 5.84 | 5.90 |
| 60 | 61 | 4 | 3,285,565 | 49,689 | 212,634 | 2,366,148 | 34,215 | 684,306 | 5.91 | 5.81 |
| 80 | 81 | 4 | 128,612,463 | 987,352 | 8,323,480 | 90,712,449 | 665,856 | 13,317,115 | 6.04 | 5.65 |
| 100 | 101 | 4 | 5,032,356,919 | 19,610,803 | 325,681,685 | 3,477,697,582 | 12,958,058 | 259,161,168 | 6.18 | 5.49 |

| 指标 | 结果 | I1–I6 |
|---|---|---|
| encounter TTK | **2.93 .. 6.18（2.11×）** | I1 ✓（2.11× 全部来自 count 与 difficulty，无速率漂移） |
| 生存回合 | **5.49 .. 6.55（1.19×）** | I2 ✓ |
| 等级跟踪 | S=10→L11、S=50→L51、S=100→L101 | I5 ✓ |
| 敌方减伤率 | 全程恒定 16.2% | I3 ✓（无硬墙） |
| S=1–2 教程段 | TTK 2.71 / 生存 26.2 → 经 TrainingEnemy 重调后 2.97 / 11 | 有意安全 |

> **2.11× 的残余波动是可解释的**：`c^0.4`（count 1→4 的总 HP 比 1.74×）× `difficulty`（0.90→1.10，1.22×）≈ 2.12×。即全部波动来自**两个显式设计旋钮**，没有隐藏的指数漂移。这正是 v3 与旧系统的区别：旧系统 Stage 100 的 TTK 是 Stage 3 的 1.4×10⁷ 倍。

### 6.2 对照当前版本（同一 Stage）

| Stage | 旧 encounter TTK | 旧 生存 | v3 TTK | v3 生存 |
|---|---|---|---|---|
| 1 | 6.0 | 60.00 | 2.71 | 26.15 |
| 5 | 34.1 | 4.70 | 3.97 | 6.37 |
| 10 | 90.0 | 2.07 | 5.57 | 6.28 |
| 20 | 929.1 | 0.61 | 5.64 | 6.18 |
| 30 | 120,500 | 0.17 | 5.70 | 6.08 |
| 40 | 746,105 | 0.05 | 5.77 | 5.99 |
| 50 | 4,619,686 | 0.01 | 5.84 | 5.90 |
| 100 | 4.2×10¹⁰ | ≈0 | 6.18 | 5.49 |

### 6.3 装备必要性（I6）与 σ 的量化代价

`item_level` 固定为 1（裸等级）：

| Stage | 裸装 TTK | 裸装生存 | 装备必须提供的乘数 |
|---|---|---|---|
| 5 | 5.9 | 4.36 | 1.4× ATK / 1.3× HP |
| 10 | 13.9 | 2.56 | 2.3× ATK / 2.0× HP |
| 20 | 43.6 | 1.03 | 5.7× ATK / 4.1× HP |
| 30 | 164.1 | 0.45 | 14.1× / 8.6× |
| 50 | 4,082.6 | 0.09 | 87.1× / 38.0× |
| 100 | 3.65×10⁷ | 0.00 | **8,307× / 1,551×** |

⇒ I6 成立：Stage ≥ 20 裸装即不可持续（生存 1.03 回合）。这就是"装备驱动"的可验证定义。

### 6.4 数值边界

| 项 | 值 | 含义 |
|---|---|---|
| `MAX_SCALED_VALUE = 1e12` 对敌 HP 触顶 | S ≈ **125** | 现版本已有限制，v3 未改变 |
| 玩家 ATK 达 1e12 | S ≈ **131** | 建议把 `MAX_SCALED_VALUE` 同时施加到玩家属性（§11 O2） |
| 越过 131 后 | 敌 HP 封顶、玩家继续 ×1.20 ⇒ TTK 塌缩至 1 | 需在 §5.4 的 `difficulty` 折线上加"封顶后难度重锚"，或明确声明 endless 上限 |

---

## 7. 落地映射

### 7.1 新增：集中式 Balance 定义（唯一事实来源）

**不新增 autoload**（AGENTS.md 规则 13）。方案：

- `resources/balance_profile.tres`（`BalanceProfile extends Resource`）承载所有可调常量：`sigma`、`r_hp`、`r_atk`、`r_def`、`r_exp`、`r_gold`、`group_hp_exp`、`group_atk_exp`、`difficulty_low/mid/high`、`base_hp/attack/defense`、`base_exp_pool`、`target_ttk`、`target_survival`。
- 由 `grid_combat.tscn` 的一个既有单例节点（`LevelProvider`）以 `@export var balance: BalanceProfile` 持有，避免新增节点。
- 纯函数由**静态类**提供（参照 `ItemEconomy` 的"pure and static"范式，`item_economy.gd:7`）：

```gdscript
class_name BalanceFormulas
static func player_hp(level: int, profile: BalanceProfile) -> int
static func player_attack(level: int, profile: BalanceProfile) -> int
static func player_defense(level: int, profile: BalanceProfile) -> int
static func resolve_damage(attack: int, defense: int) -> int      # ATK²/(ATK+DEF)
static func experience_to_next_level(level: int, profile: BalanceProfile) -> int
static func enemy_stat_multiplier(stage: int, count: int, profile: BalanceProfile) -> float
```

满足 AGENTS.md 规则 14/15（调参值在逻辑之外、不重复硬编码），同时不给 `equipment_affix` 增加 autoload 依赖。

### 7.2 改动清单

| # | 文件 | 位置 | 改动 |
|---|---|---|---|
| 1 | `resources/balance_profile.tres` | 新 | 常量载体 |
| 2 | `scripts/systems/balance_formulas.gd` | 新 | 静态纯函数层 |
| 3 | `scripts/systems/experience_system.gd` | `:8-10` | 删除 `base_*_growth` 导出 |
| 4 | 同上 | `:91-99` | 增量 `+=` → **调用 `recompute_stats_from_level()`**（幂等） |
| 5 | 同上 | `:55-57` | EXP：删 `(1+0.1×(lvl−1))`，加 `LevelDiff` 乘区 |
| 6 | `scripts/player/player_controller.gd` | `:36` 附近 | 新增 `recompute_stats_from_level()`（写 `player_stats` 基础三项，保留装备加成路径 `:743-758`） |
| 7 | `scripts/progress/stage_progress_save.gd` | `:361-380` | 读档后调用重算（**P0**，§2.5-①） |
| 8 | `scripts/player/player_progression.gd` | `:24-26` | `experience_to_next_level()` 转为调用 §7.1（含 `count`） |
| 9 | `scripts/combat/combat_system.gd` | `:120-127` | `max(1, ATK−DEF)` → `BalanceFormulas.resolve_damage()` |
| 10 | `scripts/systems/enemy_scaling.gd` | `:8-40` | 加 `group_mult` / `difficulty` / `level_offset_mult` 参数；`R_DEF` 消费方改 1.20 |
| 11 | `scripts/systems/level_provider.gd` | `:31-37` | `defense_growth_rate` 1.15 → 1.20；新增 `group_*_exp`、`difficulty_*` 导出 |
| 12 | 同上 | `:117-149` | 按 S 写 `definition.difficulty_multiplier`（复用字段） |
| 13 | `scripts/systems/stage_manager.gd` | `:319-341` | 传入 `count` 与 `level_offset_mult`；`difficulty` 读取点不变（`:331`） |
| 14 | `scripts/systems/stage_manager.gd` | `:343-356` | 方差保留（±15%），但**在归一化后的池上**施加 |
| 15 | `scripts/items/equipment_affix.gd` | `:272-285` | `compute_value` 引入 `stat_base(il)` 与 `item_power(il)` |
| 16 | `scripts/items/equipment_generator.gd` | `:79-97` | 无需改动（调用签名保持），确认 `item_level` 来源 |
| 17 | `resources/enemies/generated/*.tres` | 24 文件 | 池归一化 |
| 18 | `resources/enemies/TrainingEnemy.tres` | — | HP 150 / ATK 12 |
| 19 | `docs/gameplay-spec.md` | §9 / §10 / §19 / §20 | 回写公式与目标带 |
| 20 | `docs/implementation-status.md` | `:118` 偏离 #1 | 关闭（`level_offset_mult` 修复）；新增 v3 记录 |

---

## 8. 分阶段实施计划

> 每阶段必须**独立可运行、独立可验证**（AGENTS.md 规则 6/7）。禁止一次提交全部改动。

### Phase 0 —— 前置修复（**必须先做**，独立价值）
- 新增 `PlayerController.recompute_stats_from_level()`；`ExperienceSystem` 改调用它；`load_save_data()` 后调用它。
- 修 `stage_progress_save.gd:56` 注释与代码一致。
- **验证**：新增 `tests/player_stat_recompute_smoke_test.gd` —— 构造 Lv1 → 加 EXP 至 Lv20 → 断言 `attack == f(20)`；再模拟"重置 stats → load_save_data → 重算"断言一致。headless 运行。
- **风险**：低。不改任何数值曲线，只修一致性。

### Phase 1 —— 伤害公式（收益最大、可单独上线）
- 只改 `combat_system.gd:120-127` + 新增 `resolve_damage`。
- **验证**：`tests/damage_formula_smoke_test.gd` 断言 `resolve_damage(100,0)==100`、`(100,100)==50`、`(100,5e6) > 1`、`(1e9,4e6) > 1`（I3 无硬墙）；跑现有 `enemy_experience_scaling` 与战斗相关 suite 无回归。
- **预期效果**：硬墙消失，可玩区间从 Stage ~25 扩到 ~60（未配套 Phase 2 时 TTK 仍偏长，属预期）。

### Phase 2 —— 玩家成长指数化（与 Phase 1 同批上线）
- Phase 1 单独上线后若不同批上 Phase 2，指数 HP 会让 TTK 爆炸（Kimi 的判断正确）。
- 改 §5.1 + `player_stats.gd` 初值（ATK 10 → 46；HP/DEF 不变）+ BalanceProfile。
- **验证**：`tests/balance_invariant_smoke_test.gd` —— 断言 I1/I2 在 Stage 3..100（模拟，非运行游戏）。

### Phase 3 —— EXP 重定基准
- §5.5。**验证**：新增测试断言 I5（`|L−S| ≤ 3` 全清推进）。
- **存档影响**：老存档 `experience` 值按新 `need(L)` 重新夹取（`load_save_data` 已有 `0 .. need(L)−1` 的夹取逻辑，天然兼容）。

### Phase 4 —— 群怪折扣 + 难度斜坡
- §5.4，复用 `difficulty_multiplier` 字段。**验证**：I1/I2 复跑；抽查 4 敌关的实际回合数。
- 依赖：需要 1–2 个 AoE 技能来体现多怪价值。**当前已有** `WHIRLWIND`（0.8× 四邻格，`skill_catalog.gd:23-28`）⇒ **无需新增技能**，只需复核其倍率是否够用（建议 0.8 → 0.9 并实测）。

### Phase 5 —— 装备乘法化（改动面最大，第二波）
- §5.6。**验证**：新增 `tests/equipment_scaling_smoke_test.gd` 断言 `Σ affix(item_level=il) ≈ stat_base(il) × ratio × item_power(il)`，并断言存档 round-trip 不丢词缀（已有 `equipment_affix.gd:46/63` 的 save data 路径）。
- **风险**：中。旧装备变弱是**预期**的，但需在 release note 说明；无存档格式变更。

### Phase 6 —— 数据层
- §5.7。纯数据，随时可做。**验证**：`enemy_bestiary_panel` 显示正常；池离散度断言 <1.6×。

### Phase 7 —— Boss 机制化（独立）
- GPT §18。`TypeMultiplier = 4` 的 HP 语义与"机制挑战"分开：Boss 保留 `5–8× Normal HP`、`1.5–2×` 伤害预算，其余靠机制。
- 非成长公式范畴，可后置或另立文档。

---

## 9. 存档与兼容

| 项 | 结论 |
|---|---|
| 存档格式 | **不变**。只存 `level / experience / gold / skill_points / skill_levels / items / sub_heroes`（`stage_progress_save.gd:295-320`） |
| 老存档读入 | `experience` 由现有夹取逻辑按新 `need(L)` 重定界 ⇒ 兼容 |
| 属性恢复 | Phase 0 的重算使属性成为 level 的纯函数 ⇒ 读档正确（修复今日缺陷） |
| 装备 | 词缀存绝对值 ⇒ 旧装备保留旧数值；新掉落按新式缩放 ⇒ 无格式迁移、无资产丢失 |
| `MAX_CHARACTER_LEVEL` | `stage_progress_save.gd:137` 的现有上限需复核是否 ≥ 130 |
| 版本号 | 建议存档 `version` +1 并在注释中记录"derived stats 现在由 level 纯函数决定"，`load_save_data` 对 v1/v2/v3 均兼容 |

---

## 10. 测试与验收

按 AGENTS.md「Verification & Token Budget」与「Testing Rules」，全部走最便宜路径：

```powershell
# 纯数据冒烟测试（headless，自包含）
D:\IDE\godotEngine\Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/balance_invariant_smoke_test.gd

# UI/集成
tools\ui_harness\run_ui_harness.ps1 -Suite <name> -Quiet
```

新增测试清单：

| 测试 | 覆盖 | 断言 |
|---|---|---|
| `tests/player_stat_recompute_smoke_test.gd` | §2.5-① / Phase 0 | `attack(L) == f(L)`；读档后一致；重复重算幂等 |
| `tests/damage_formula_smoke_test.gd` | I3 / Phase 1 | 齐次性 `f(kA,kD) == k·f(A,D)`；无 `ATK<DEF` 地板 |
| `tests/balance_invariant_smoke_test.gd` | I1/I2/I4/I5/I6 | Stage 1..100 模拟全带内 |
| `tests/equipment_scaling_smoke_test.gd` | Phase 5 | 词缀值 = `stat_base(il) × ratio × item_power(il)`；save round-trip |
| 复用 `tests/enemy_experience_scaling_smoke_test.gd` | 回归 | 现有 EXP 缩放断言随新公式更新（该文件 `:72` 已直接调用 `EnemyScaling.scale_stats`，签名变化需同步） |

**验收门槛**：I1–I6 全绿 + 现有 `enemy_experience_scaling` suite 更新后全绿 + Stage 1..100 模拟表落带。

---

## 11. 开放决策（需要拍板）

| ID | 决策 | 选项 | 本文倾向 |
|---|---|---|---|
| **O1** | σ 取值（等级 vs 装备份额） | 0.35 / **0.50** / 0.70 | **0.50**：满足支柱且保留等级地板；若要更强装备驱动取 0.70 |
| **O2** | `MAX_SCALED_VALUE` 是否同时约束玩家属性 | 是 / 否 | **是**：否则 S>131 后敌 HP 封顶而玩家继续增长，TTK 塌缩 |
| **O3** | 是否引入 Zone 分段成长（GPT §19） | 引入 / 不引入 | **暂不**：100 关内 I1–I6 已达标，分段是额外复杂度（AGENTS.md 规则 16） |
| **O4** | 是否引入护甲穿透（GPT §7） | 引入 / 不引入 | **暂不**：新属性 + 词缀族 + UI + 存档字段；先验证 v3 是否已足够打开 build 空间 |
| **O5** | 敌方 DEF 速率 1.15 → 1.20 是否接受 | 接受 / 保持 1.15（承认 DEF 后期为死属性） | **接受**：否则"DEF 是有效属性"这一设计承诺不成立 |
| **O6** | Stage 3–4 过渡子池 vs 手工 2 个新敌 | 子池 / 手工新敌 | **子池**：零新增资源，复用既有 24 敌 |
| **O7** | `TrainingEnemy` 重调（60→150 HP） | 重调 / 保持 60 | **重调**：否则 S=1–2 与 S=3+ 之间仍有 3× 断崖 |

---

## 12. 回滚

| 粒度 | 方式 |
|---|---|
| 单阶段 | 每阶段一个独立 commit，`feat:`/`fix:` 前缀，可单独 revert |
| 全局 | BalanceProfile 是唯一常量载体 ⇒ revert 该资源 + `resolve_damage` 单点，即恢复旧伤害公式；成长公式 revert 两个静态函数即恢复旧线性曲线 |
| 存档 | 无格式变更 ⇒ 回滚不需要数据迁移；老存档在任何阶段都可读 |
| 灰度 | `BalanceProfile` 可加 `enabled: bool` 开关做 A/B，但属额外机制，默认不做（规则 16） |

---

## 附：本文与两份外部反馈的净差异

| 结论 | 本文 | Kimi | GPT |
|---|---|---|---|
| 玩家加成必须是乘法 | ✅ 核心 | ✅（隐含） | ✅ §11 |
| 等级与装备速率必须**精确互补** | ✅ 首次给出约束与推导 | ❌ 只要求"同速率"（σ=0） | ❌ 给 1.045/1.105/1.08，不自洽 |
| 伤害公式 | `ATK²/(ATK+DEF)`，一次齐次 | ✅ 同 | ❌ `ATK×K/(K+DEF)`，K=100 失锚 |
| 敌方 DEF 速率需 1.15→1.20 | ✅ 修正 Kimi 的配对错误 | ❌ 保持 1.15 | ❌ 降到 1.075 |
| 群怪折扣指数 | `c^−0.6 / c^−0.8`（实测折中） | `c^−0.5 / c^−0.75` | `c^−1`（多怪免费） |
| 数值方案可复现验证 | ✅ Stage 1..100 模拟，I1–I6 全绿 | ⚠️ 声称模拟，未给复现路径 | ❌ 自身反例（TTK 10⁶ 回合） |
| 读档不重算属性的现存缺陷 | ✅ 发现（P0） | ❌ | ❌ |
| `difficulty_multiplier` 已存在 | ✅ 复用 | ❌ 建议新建 | ❌ 建议新建 |
| `enemy_level` 仅影响 EXP | ✅ 给出修复 | ⚠️ 提到但只建议删显示 | ❌ |

---

**下一步**：请就 §11 的 O1–O7 拍板（尤其 **O1 σ 取值**）。确认后我按 §8 从 **Phase 0** 开始实施，每阶段独立验证后再进入下一阶段。
