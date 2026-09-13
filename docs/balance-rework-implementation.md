# 属性成长与战斗数值重构：最终实施契约（v4）

> 状态：**设计定案，可进入实现；代码尚未实现**。修订日期：2026-09-13。
> 本文整体取代原 v3，不再保留“部分取代”或相互覆盖的公式。
> [gameplay-spec.md](gameplay-spec.md) 是规则入口；本文细化其数值契约、代码落点与迁移流程。
> [balance-scale-rebase.md](balance-scale-rebase.md) 给出推导与可执行计算。解析检查通过不等于运行时已验收。

## 1. 设计结论与交付范围

保留装备驱动、格子战斗、移动 0..3 格加一次行动、现有技能与自动战斗。采用统一幂律尺度、连续防御公式、真正的装备乘法聚合，修正 EXP、Gold、价格和副英雄的配套成长。所有参数标为 tunable，但本版本已有确定默认值，实现时不再自行选择方案。

本次不新增护甲穿透、转生、Boss 技能、Zone 分段公式、装备槽、Autoload 或插件。副英雄沿用收藏、随机召唤、重复升级和现有出战规则；魔法书沿用独立冷却。本次只调整这些既有系统的数值与伤害入口。

**发布范围为 Stage 1..1000**，角色等级 1..1000，掉落物品等级 1..1003。1000 关通关后允许回刷，推进按钮显示已到当前内容终点，不生成 1001。未来扩展先增加内容与边界验证；幂律不等于数学上的无限游戏。旧存档超范围的处理见 §9。

### 原方案必须修正的问题

- 齐次性只保证相同比例缩放下的解析战斗性质；不保证每一种装备、等级、站位或辅助队伍都平衡。
- `G(x)=((x+20)/21)^4` 的精确逐关倍率是 `G(S+1)/G(S)`，不是 `1+4/(S+20)`；后者仅是一阶近似。
- 在玩家裸值上直接累加 `stat_base(il) × item_power(il)` 的词缀，不能实现所证明的 `G(L)^0.4 × G(il)^0.6`。
- 装备份额 σ=0.6 指**参考状态的对数成长份额**，不是 60% 面板属性，也不是所有状态下的装备贡献。
- `100²/(100+5,000,000)` 取整并设最低伤害后等于 1。平滑防御仍允许弱者刮痧，不承诺任意 ATK/DEF 比都有伤害大于 1。
- 不再声称“L=S+1 恒成立”“所有 I1–I6 已通过”“S500 的 0.46% 装备提升能推 60 关”。
- 单独切换伤害、装备或经济曲线会产生中间失衡；拆分开发与测试，**整套发布**。

## 2. 唯一尺度与精度契约

```text
G(x) = ((max(x, 1) + 20) / 21)^4
r(S) = G(S+1) / G(S) = ((S+21)/(S+20))^4
sigma = 0.60
level_scale(L) = G(L)^0.40
item_scale(il) = G(il)^0.60
count(S) = clamp(1 + floor((S-1)/3), 1, 4)

difficulty(S) = 0.90 + 0.10*(S-1)/9       1 <= S <= 10
              = 1.00 + 0.10*(S-10)/90    10 < S <= 100
              = 1.10                     100 < S <= 1000
```

G 接受实数坐标，只有关卡、主角等级、物品等级为整数；副英雄投入坐标允许小数。G(1)=1，单调递增，S10/S100 边界连续。HP、ATK、DEF、EXP、Gold 与价格的尺度指数均为 1，不保留独立增长率。

中间计算使用 64 位 float，不在等级裸值、词缀求和或各个倍率后逐步取整；最终 HP/ATK/DEF、伤害、奖励为非负 int64。HP/ATK 至少 1，DEF 至少 0；奖励和价格各依原最低值规则。护甲函数使用 `A / (1 + D/A)`，避免整型 A² 溢出；A=0 时返回 0，负 A/D 输入先夹到 0。

`MAX_COMBAT_VALUE=1e12` 是故障保护线，不是正常调参或延长关卡的方法；支持范围的合法最大配置必须在它之前通过。禁止分别截平敌人/玩家属性后继续生成更高关卡。持久化 Gold/EXP 安全上限为 9e15，所有加法、乘法、转换先检查有限性与范围，拒绝 NaN/Infinity；不要将它与敌人当前的 1e12 缩放上限混为一谈。

## 3. 主角与装备：把证明变成真实聚合

### 3.1 基础参数与装备固有成长

参考裸等级基础系数为 `b_HP=121.2, b_ATK=51.8, b_DEF=5.0`。这是设计基准，不是全套随机装备的实测均值。

每件装备获得一个由槽位、稀有度、item_level **派生的固有成长**，不占词缀槽，不另做随机 roll。它确保普通装备也能提供相应槽位的成长，避免“缺少某一种随机词缀就失去整条成长曲线”。装备详情明确展示该固有属性，旧装备迁移时同样派生。

| 槽位 | w_HP | w_ATK | w_DEF |
|---|---:|---:|---:|
| Weapon | 0 | 0.60 | 0 |
| Helmet | 0.15 | 0 | 0.25 |
| Armor | 0.40 | 0 | 0.45 |
| Gloves | 0.10 | 0.15 | 0 |
| Boots | 0.20 | 0 | 0.20 |
| Ring | 0.05 | 0.15 | 0.05 |
| Amulet | 0.10 | 0.10 | 0.05 |
| **合计** | **1.00** | **1.00** | **1.00** |

```text
rarity_core(r) = 1 + 0.08*r               r=0..5, Common..Mythic
slot_factor(s) = 1                        空槽
               = rarity_core(r_s) * item_scale(il_s)  已装备
M_X = sum_s(w_X,s * slot_factor(s))
affix.value = affix_base * (1+0.35*r) * roll * item_scale(il)
Flat_X = sum_该属性词缀(affix.value)
effective_X = round(level_scale(L) * (b_X*M_X + Flat_X))
```

v4 的平面 affix.value 已含 rarity、roll、item_scale，**不含 level_scale**；聚合直接求和，不再重乘。保存归一化 roll_ratio=(roll−0.8)/0.4（0..1）。无来源手工词缀另外保存 signed_base 与 source_kind=legacy_authored，以便重算时保留正负及来源。

先汇总再对 HP/ATK/DEF 做最终下限。负面手工词缀沿同一通路，不允许负 HP、负 DEF 或以负值生成回血攻击。

**参考夹具**：7 槽 Common、il=S、无附加词缀，L=S；仅用于隔离尺度的数学测试，不声称它是随机掉落均值。此时 M_X=G(S)^0.6、Flat_X=0，三个属性严格为 b_X×G(S)。实际 Common 仍有 1 条随机词缀。

空槽贡献常数 1；全裸为 b_X×G(L)^0.4。混装逐槽算，禁止用平均 item level 替代。**不要再将已含 item_scale 的 ATK 词缀作为伤害后的 equipment_multiplier 乘一遍。**

### 3.2 词缀与稀有度

沿用 7 槽、每件同属性最多一条、稀有度词缀数量 1/2/3/4/5/5、词缀强度 1+0.35r、roll∈[0.8,1.2]、独特效果概率。HP/ATK/DEF 词缀基数统一为各自 b_X 的 10%，即 **12.12/5.18/0.50**，以浮点保存到最终聚合；原 DEF=4 相对基础 DEF=5 会让同一条防御词缀获得远超其他属性的预算，必须一起重标定。roll weight 是**抽取概率权重**，不能拿来当属性份额。

其他词缀不乘 G，也不乘旧的 1+0.08(il−1)：

| 类别 | 生成与最终聚合限制 |
|---|---|
| 暴击率 | base 3% × 稀有度强度 × roll；含主角基础 5%，最终 0..50% |
| 暴击伤害 | base +15% × 稀有度强度 × roll；含基础 150%，最终 100..250% |
| 闪避、吸血、眩晕 | 各 base 3% × 稀有度强度 × roll；最终上限分别 35% / 10% / 15% |
| 对精英 / Boss 增伤 | 各 base 5% × 稀有度强度 × roll；各自相加后上限 +50% |
| 移动力 / 攻击范围 | 随机词缀每条固定 +1；装备提供的总增量各上限 +2；基础移动 3 不变 |

手工utility保留定义的signed值；各概率、吸血、类型增伤下限0，暴击伤害下限100%，最终移动点下限0、攻击范围下限1。以上限作用于最终有效值，装备面板同时显示原始词缀和实际增量；溢出提示，不偷偷改写物品 roll。独特效果若给同类数值也计入上限；原有效果触发语义不扩展。HP/ATK/DEF 没有额外“百分比成长”新词缀。眩晕仍为命中后概率，持续 1 回合；目标已有眩晕时不延长，解除后的下一个自身回合完成前不能再次被眩晕，避免永久控制。

比较卡用同一重算函数预览换装后 HP/ATK/DEF 与有效 utility 的差异；保留构筑信息，item score 不作为战力判定。固有成长和词缀影响必须分列，原有含绝对词缀值的 score 只能作为旧显示值，不能继续用于 AUTO 换装或价值判断。

### 3.3 重算事件与 HP

新增幂等 `recompute_stats_from_level_and_equipment()`；新角色初始化、升级、读档、换装、卸装与迁移都走它。禁止减掉“上次加成”再增量叠加。

升级保留现有明确的升级回满语义；初始化/复活按各自规则回满。其余重算：new_max_hp=old_max_hp 时直接保留 old_hp，保证幂等；否则投影为 `floor(old_hp * new_max_hp / old_max_hp)`（中间用float，且最终不超过new_max_hp）。死亡保持0；活角色若投影不足1则拒绝本次换装/卸装并提示先恢复生命，不用max(1)补血。换装往返允许保守的舍入损耗，不允许任何回血；同一输入重复重算不再计算比例。读档按既有“重新开始该关、状态恢复”流程初始化，不能读取一半装备就重算。UI 预览是无副作用纯函数。

## 4. 伤害与敌人

### 4.1 统一伤害入口

```text
raw = A/(1 + D/A)                         A > 0
modified = raw * skill_multiplier * applicable_damage_modifiers
final = max(1, round(modified * (critical ? critical_damage : 1)))
```

一次最终取整；普通攻击 skill_multiplier=1。暴击、闪避、精英/Boss 增伤、命中特效按已有攻击来源规则执行，实际吸血基于造成的 HP 损失，过量伤害不吸血。敌人不暴击。伤害最低 1 是低攻防比时的保底，不是“永远没有硬墙”的证明。

主角普通攻击、主动技能、魔法书与副英雄必须共用护甲结算函数。魔法书保留免行动、独立冷却、可暴击、无吸血/眩晕/命中特效；副英雄不获得主角暴击或主角装备触发。当前技能上限 5，保留现有倍率和冷却，不在本轮把旋风斩 0.8 改成 0.9。

### 4.2 关卡与敌人系数的职责

普通参考敌人为 `HP=150, ATK=22, DEF=4, EXP=100`。24 个生成敌人的战斗属性按旧值顺序压缩至参考值的 0.9..1.1：

`new_X = reference_X * (0.9 + 0.2*(old_X-pool_min_X)/(pool_max_X-pool_min_X))`。

分母为 0 时取 reference_X；资源按需要取整，校验整型后范围。HP/ATK/DEF 各自计算；EXP 归一为 100，Gold 保留现有定义基数。旧值从迁移前资源读取，此变换只执行一次，不能在导出/每次生成时反复压缩。

```text
enemy_level = max(1, S + sampled_offset)   offset 分布沿用 0:40%, ±1:15%, ±2:10%, ±3:5%
o = enemy_level - S                       使用夹取后的真实偏移
offset_mult = 1 + 0.06*o
HP  = base_hp  * G(S) * c^-0.60 * difficulty(S) * offset_mult * hp_variance
ATK = base_atk * G(S) * c^-0.80 * difficulty(S) * offset_mult * atk_variance
DEF = base_def * G(S)             * difficulty(S) * offset_mult * def_variance
```

普通遭遇 c=实际开场敌人数，在关卡建立时冻结；击杀后不重算存活敌人强度。每种属性方差独立均匀 [0.85,1.15]。per-entry/type 修正在上式对应属性上**只应用一次**；DEF 不做群体折扣。显示等级通过 offset_mult 同时影响风险与 EXP/Gold，不再额外计算 G(enemy_level)。

既有 `StageDefinition.difficulty_multiplier` 承载 difficulty(S)，固定关与生成关都采用此值；不在 provider 与 stage manager 再乘两次。已有特殊遭遇的 entry 修正保留为配置，但不纳入普通遭遇不变量。

S1–2 训练敌固定基数 HP130/ATK12/DEF3/EXP100，offset=0、variance=1，无过渡子池；S3 起使用压缩后的普通池。压缩池替代“选最低五只”的临时方案。

### 4.3 Mini Boss 定案

每 10 关仍为 Mini Boss，保留现有技能、位置和保底掉落。使用普通参考敌数据，群体基准固定 c=4，然后只对 HP×6、ATK×1.5、DEF×1.25；offset=0、variance=1，替代旧 Boss 基数与重复 tier 伤害倍率。它不是“普通单怪再乘六倍完整遭遇 HP”。

奖励 EXP×4、Gold×4，相对单个普通敌基数；不再额外乘人数 4。中高关参考夹具需 9 次非暴击普通攻击，静态接战存活；真实 Boss 阻挡、走位和技能另测。其他特殊类型保留现有配置，独立记录实际动作与成功率，不能用普通敌平均值替它们担保。

## 5. EXP 与升级：锚定不是锁级

```text
need(L) = round(100 * count(L) * G(L))
catchup(S,L) = clamp(1 + 0.10*(S-L), 0.25, 2.0)
kill_exp = max(1, round(100 * G(S) * offset_mult * type_exp * catchup(S,L)))
```

type_exp 沿用 normal1 / elite2 / special2.5 / mini_boss4 / treasure1.5 / gold1.5 / cursed2。EXP 仅在击杀奖励入口缩放一次；enemy runtime 可保存未含 catchup 的已缩放值，结算时不得再次乘 G 或类型倍率。L 在**每次击杀奖励结算前**采样，超额 EXP 保留并可连续升级。

每级仍给 1 skill point，等级上限时不再累计 EXP、不再发升级奖励。主角和副英雄击杀走同一奖励入口并且只发一次。

理想普通关起手 L=S、EXP=0、offset=0 时，一关总 EXP 正好等于 need(S)，末次击杀后 L=S+1；这是**战后恒等式**，不能拿战后等级计算该关战斗。真实推进包括 offset、特殊关、重复刷关和败退，必须模拟轨迹，不宣称每关必升一级。

不设置“低于某关就无 EXP”的硬开关；回刷仍有收益。主目标为从新角色出发、逐关全清的普通/每10关Boss轨迹上，95% 战前采样满足 |L−S|≤3，单次偏离≤6；随机特殊关轨迹单独报告。未通过时先查奖励重复与 count/type 口径，再调 catchup，不改 G 来补 EXP 问题。

## 6. Gold、价格与副英雄必须同批切换

### 6.1 Gold 与物价

```text
stage_clear_gold = round(50 * G(S))
enemy_gold = round(base_gold * G(S) * offset_mult * type_gold)
item_level_multiplier = G(il)
potion_level_multiplier = G(potion_level)
```

Gold 无玩家等级 catchup。既有角色池 gold 基数、type_gold 保留（Mini Boss 用 §4.3）；属性方差不影响奖励。阶段奖励每次合法通关发一次；原来可回刷的奖励仍可回刷。

保留 EconomyConfig 的 BaseItemValue30、PotionValue25、稀有度经济倍率 [1,1.5,3,7,15,35]、slot 倍率1、AffixMultiplier=clamp(1+0.15Σ(roll_ratio×economic_weight),1,3)。经济质量由 roll_ratio（0..1；当前Stun经济权重2.2，其余沿用spec表）决定，不从被重标定的战斗 affix.value 反推价格；固有成长不再额外计一次价格。

`Buy=max(floor(Value×4),Sell+1,1)`；`Sell=max(1,floor(min(Value×0.25,100×StageExpectedSell)))`。

`StageExpectedSell=30×G(S)×E_normal[RarityMultiplier×AffixMultiplier]×0.25`。按每档稀有度的词缀数、当前加权不放回抽取、mean roll_ratio=0.5计算**联合期望**，当前12属性完整目录为约2.136384474；不能用原1.705×1.190替代，因为稀有度与词缀数相关。若槽位过滤候选属性，按真实槽位概率重算条件期望。不要从随机样本均值反过来定价；这些有限组合可以直接枚举或动态规划。物品基础价值按自身 il，出售 cap 按原规则“当前合法关卡”取值；回低关 cap 更低，不得用新曲线重置物品等级。

要逐档验证 Buy>Sell、同条件价格单调、il=S..S+3、最高 roll 和手工/负面词缀。早期最大等级偏移价比为 (24/21)^4=1.706，**略高于**旧 1.18³=1.643，不能引用“下降后必然更安全”。原k=50还把Mythic词缀均值当成最大值；使用AffixMultiplier≤3的保守界，k≥35×3×1.706/2.136384474≈83.85，故定为**100**。BaseItemValue从32调为30，使普通卖装收入目标仍为战斗Gold的5..18%。完整经济测试验证这一目标以及无档内截断；卖装/战斗收入比不再声称严格与Stage无关。

### 6.2 副英雄的投入坐标与召唤定价

副英雄没有 HP，继续沿用当前 real-time attack_interval、出战限制与 8 人池，不创造一套虚拟回合 HP。仅将直接扣血改为 §4.1 的护甲入口。

沿用品质抽取 70/25/5、品质池人数 3/3/2，每角色概率 p 分别为 0.7/3、0.25/3、0.05/2。重复规则仍每 3 次同角色重复升一级，余数保留。

```text
investment_level_i = 1 + (hero_level_i-1)/(8*p_i)
combat_level_i = min(main_player_level, investment_level_i)
hero_attack_i = base_damage_i * quality_multiplier_i * G(combat_level_i)
owned_draws = sum_owned(1 + 3*(hero_level_i-1) + duplicate_count_i)
price_coordinate = min(1000, 1 + owned_draws/24)
summon_cost = max(250, ceil(10 * G(price_coordinate)))
```

24=8×3。该坐标按获得同角色的期望投入归一，避免低概率角色必须付数倍召唤数才能获得相同成长；仍然保留其基础 damage、间隔与品质倍率 1/1.1/1.2。余数影响后续价格，但只在满 3 次升级时改变伤害。主角等级限制阻止单靠超额重复跳过主线。

price_coordinate在1000封顶以保护旧超范围收藏的价格计算；超过主角等级对应的投入仍可保留，但当前战斗坐标不再提高。读取收藏时先验证非负整数与既有序列化范围，再用int64求和；不得先转换一个已溢出的价格。

定价在抽取和扣款**之前**按整个已有收藏计算，和当前关卡无关；固定最低250保留起步门槛，后期动态部分把期望 24 次召唤的一档投入成本锚在约 240G 附近。高关可以快速补低投入收藏，但不能永久用250购买无限指数战力。失败抽取不扣款，成功召唤原子更新 Gold/收藏；不允许重置收藏降价。DEV fixtures 必须标记并排除经济与自然成长验收。

这不是已证明的辅助战斗平衡：验收要用真实秒间隔、AUTO速度、主动魔法书和当前出战人数。主角独立基准不能被助手掩盖；充足投资的队伍应提升已通关内容效率，不取代装备推进。

## 7. 代码落点与依赖注入

| 范围 | 现有入口 / 最小改动 |
|---|---|
| 集中参数 | 新增 BalanceProfile Resource 类与默认 .tres；新建 BalanceFormulas 静态纯函数；不新增 autoload |
| Player | player_stats.gd / player_controller.gd：保留数据角色，替换 _refresh_equipment_stats / _adjust_stats 的增量聚合，提供同源预览 |
| EXP | experience_system.gd / player_progression.gd：need、reward、幂等升级重算与上限 |
| Enemy | enemy_scaling.gd / level_provider.gd / stage_manager.gd：G、冻结 count、offset、difficulty、方差，禁止重复倍率 |
| Combat | combat_system.gd：统一护甲；SubHeroCombatManager：攻击来源标识与同源 DamageResult；保留 Tome 来源语义 |
| Items | equipment_affix.gd / equipment_generator.gd / equipment_instance.gd：派生 core、词缀分类、保留 roll 身份、版本与预览 |
| Economy | economy_config.gd / item_economy.gd / 召唤服务：替换 level multiplier、同步 expected sell 与动态 summon cost |
| Persistence | stage_progress_save.gd：v3→v4 原子迁移、备份、EXP比例、金币与物品映射、最终一次重算 |
| Data/UI/tests | 24敌资源、训练敌、固定关/Boss资源；面板与比较；定向 smoke/UI suites |

BalanceProfile 由既有 LevelProvider 的导出引用持有，经现有 configure/init 调用显式传给 ExperienceSystem、生成器、经济与战斗消费者；Resource/静态工具函数参数也传 profile。不要让静态 EquipmentAffix 到处找场景节点，也不要在每个消费者复制默认常量。新增参数前经 CodeMap 和源码定位所有调用与序列化路径；未列出的文件仅在属于这些依赖时修改。

## 8. 实施顺序与发布门槛

| 阶段 | 工作与检查 |
|---|---|
| P0 | 保持旧公式，先修升级/读档幂等重算；用读档前后与换装往返用例验证。可独立发布的 bugfix |
| R0 | Profile、G、伤害纯函数、边界与解析夹具；读取权威参数生成对照表 |
| R1 | 主角、装备 core/affix 聚合、敌人/训练/Boss统一切换；逐一验证反序换装和混装 |
| R2 | EXP/Gold/价格/副英雄、动作来源、所有奖励只结算一次；完成v4迁移 |
| R3 | 生产公式驱动的数值模拟、存档/装备/经济集成、定向UI验收；全部通过后作为一个数值版本发布 |

R0–R3 可以分小改动开发，但不把半套数值投到玩家存档。每个中间状态保持工程可运行，不把“能启动”称为“可发布”。本次文档任务不创建提交、不执行上述代码改动。

### 验收矩阵（实现后的必需检查）

| ID | 层级 | 输入、判定 |
|---|---|---|
| M1 | 纯函数 | G(1)=1、单调、精确 r、难度边界连续；float护甲齐次，最终整数允许最多1舍入误差；A=0/D=0/极大DEF/1e12边界 |
| M2 | 解析基准 | L=il=S，7槽Common无词缀，普通参考敌，offset=0/variance=1；S3..9 encounter-work 2..6，S10..1000 4..8；静态 survival 4..9 |
| M3 | 动作模拟 | 每次一次攻击、逐只击杀、死敌不反击、每次行动后存活敌各攻击一次、无暴击/辅助/治疗/距离；S10..1000 8次攻击且存活，Boss 8..12次且存活 |
| M4 | 装备 | 每槽权重和1；混装/空槽/负词缀/所有稀有度；L与il分别变化；概率不随il增长；最高词缀和特殊效果受有效上限约束 |
| M5 | 推进 | 100个固定seed×S1..1000，包含真实掉落/换装、offset、方差、每10关Boss；分别记录战前L、装备龄、成功率、攻击行动数与移动回合，不注入未来装备 |
| M6 | EXP | §5的等级偏差分位数；失败/重刷不重复奖励、超额跨级、上限、主角与副英雄击杀恰好一次 |
| M7 | 经济/存档 | §6全部价格条件；回低关召唤价不变；v3迁移一次与二次载入一致；EXP比例、金币购买力、物品身份、技能/收藏保留 |
| M8 | 集成 | 普攻/3技能/Tome/Sub Hero同源护甲；眩晕解除免连续锁；吸血无过量；升阶、AUTO各速度、Boss掉落、UI预览与实装一致；检查Godot新增错误/警告 |

M5 常规发布目标：≥90%的轨迹在S10首次挑战前填满7个可用槽位，含推进途中的掉落与至多5次额外回刷；S20后相同策略连续20关的普通遭遇成功率≥90%，每次推进前最多允许5次已通关关卡回刷；普通胜局攻击行动中位数4..10、P90≤14，Mini Boss中位数8..14。模型包含实际升级、保留已有装备与合法换装；为防隐式“完美装备”，必须公开每槽 il、稀有度、掉落次数与替换策略。

M5战斗策略固定：使用主角普通攻击与现有最短合法移动接近最低HP可达敌人，不使用主动技能、药水、魔法书或副英雄；保留装备自带暴击/闪避/吸血等真实规则。单次遭遇100次玩家回合内未清场视为失败。攻击行动数和移动回合分开记录，避免把有无走位混入伤害目标。M8另测正常AUTO技能与辅助玩法。

M5推进与换装策略固定：无死亡时直接推进；失败后回刷最高已通关普通关，最多5次后再试；每件掉落只在同槽替换使当前普通参考敌的 `effective_ATK*effective_HP` 增大且预计静态 survival≥4时装备，平手保留旧件；首次空槽优先填满。该策略只是可复现验收代理，不写入玩家AUTO逻辑。另跑固定偏防御、偏输出与只换较高il的敏感性轨迹，报告差异，不要求所有构筑同样强。

装备滞后容忍按 G 比率解释，不统一限定“落后10级”：S20 整套落后10级只剩约50.1%参考属性，S100落后10级仍有81.2%；掉落刷新率必须覆盖前者。M5失败先调整既有保底掉落的槽位覆盖与掉落参数，不新增付费保底或转生；任何调参更新 Profile/spec 并重跑受影响用例。

先纯数据 smoke，再 `tools/ui_harness/run_ui_harness.ps1 -List` 选择实际存在的相关 suite 并用 `-Suite ... -Quiet`；新增测试名在创建前均为计划项。禁止用文档的独立计算脚本替代对生产GDScript的测试，不运行无关全套 harness。

## 9. 存档迁移、失败处理与回滚

当前写出格式3（loader仍兼容1/2），目标格式4，另存 `balance_version=4`。v1/v2先按现有缺省字段兼容规则归一到v3逻辑结构，再走同一转换；首次迁移前原子保留只写一次的**原始版本**文件备份；所有转换在临时内存完成，验证成功后以临时文件+原子替换落盘，最后才更新版本。中断/无效数据保留旧档，不写半迁移档。

| 数据 | v3→v4 明确规则 |
|---|---|
| 主角等级/技能 | 支持范围内保留level、skill points、技能等级（现有上限5）和角色身份；由新公式重建面板 |
| 等级内EXP | 用旧 need_old=round(100×1.15^(L−1)) 求 f=clamp(old_exp/need_old,0,1)，new_exp=min(need_new−1,floor(f×need_new))；最高等级清零。大L用log比较，禁止先算溢出的旧指数 |
| Gold | 锚点 H=max(1,旧最高已解锁关)，new_gold=floor(old_gold×G(min(H,1000))/1.18^(H−1))；log域求比率，允许变为0，保存迁移前后值。保留以H档服务/物品计的近似购买力，不能保证混合来源货币的每一种购买力都不变 |
| 装备 | 保留ID、槽、il、rarity、词缀stat_id、roll_ratio、独特效果；按新公式重算派生值/core；旧生成词缀缺roll时先使用旧il与旧基数反解roll并夹到0.8..1.2，再转换成0..1的roll_ratio；旧整数utility无法反解时取中性0.5；最后才应用il上限与新公式；禁止重抽词缀 |
| 手工/负面词缀 | 有原始定义则按定义的signed base×item_scale重建平面词缀，utility按§3.2处理；无来源的旧signed值以old_value/旧item_level_multiplier恢复signed base，记录legacy来源，不能误判为正向随机roll |
| 药水/物品价格 | 保留物品身份与数量；价格派生重算，不把旧卖价当新base。若存有buyback的历史成交价，按同一Gold换算因子转换并以最低1记录为v4历史价格，之后保持不变。战斗药水效果沿原有已声明规则，不新增长 |
| 副英雄 | 保留hero_id/level/duplicate_count，重建投入坐标与召唤价格，品质仍从定义读取 |
| 超支持范围 | 当前可玩stage/主角level夹至1000，物品il夹至1003；原highest stage/level/il完整保存在legacy快照与备份，展示迁移说明。副英雄收藏不丢重复；攻击坐标受主角等级限制。高等级EXP不额外发技能点 |
| HP/场景 | 不存派生面板；先恢复完整收藏/装备/进度，再一次重算，再按既有载入关卡流程初始化生命与场景 |

不能声称“保留旧绝对词缀，等新装备替换就是无损兼容”；旧尺度可能压倒新经济，也可能让高关玩家无法生存。迁移必须测试低中高等级、背包和已装备物品、传奇效果、负面手工装备、零Gold、旧大Gold、非法浮点和超范围记录。

回滚必须同时恢复旧代码、旧资源和**迁移前备份**；不让旧版本读v4档，不宣称修改一个Profile即可恢复旧游戏。本轮不承诺把v4游玩新进度反向转换到v3；发布说明明确这一边界。

## 10. 完成定义

完成不是“表中平均值好看”。需 M1–M8 对生产实现全部通过，迁移可重入且备份可恢复，Godot新增错误/警告清零，规格与实际行为对齐；再将 implementation-status 中的待实现项逐项关闭。

文档本轮只报告解析算例和一致性检查结果。真实掉落长期体验、辅助战斗及UI集成仍由上述发布门槛验证，不提前标记已完成。
