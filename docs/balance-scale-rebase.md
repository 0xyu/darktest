# Progression Scale Rebase：最终数学依据（v4）

> 2026-09-13；与 [最终实施契约](balance-rework-implementation.md) 同版。
> 本文整体取代此前的多方案分析、“部分取代”说明和未复现的通过声明。
> 规则入口为 [gameplay-spec.md](gameplay-spec.md)。本轮只修改文档，没有实现或测试游戏运行时。

## 1. 最终判断

采用 **G(x)=((x+20)/21)^4、σ=0.6、统一成长指数1**，不设增长率下限，首版支持S1..1000。这个选择兼顾前期装备提升的辨识度、后期数字规模和已有架构；它不会自动产生好玩的掉落循环。

原方案正确的部分：原有主角线性成长、敌人指数成长和减法护甲存在结构冲突；应把世界尺度、等级/装备份额和战斗目标分开设置。必须补上的部分：装备真实聚合、非伤害词缀预算、离散行动、成长滞后、经济与存档。

我们选择乘法分割是为了参考状态下的**精确可控**，并不是说一切加法方案数学上都不可能。两条同阶曲线相加也可稳定；原文的问题是证明和准备实施的公式不一致。

## 2. 精确公式与适用条件

```text
G(x) = ((x+20)/21)^4
r(S) = G(S+1)/G(S) = (1+1/(S+20))^4
r(S) ≈ 1+4/(S+20)             仅一阶近似，不用于累计成长
P_X = b_X * G(L)^0.4 * G(il)^0.6  仅完整参考装备同级时
damage(A,D) = A/(1+D/A)       A>0
```

r(1)=1.204519，r(100)=1.033752，r(1000)=1.003927。如果将近似逐关连乘，得到的是另一条曲线，不再等于上述G。实现直接计算闭式G。

当战前 L=il=S 且双方 HP/ATK/DEF 同乘G(S)，护甲伤害也同乘G(S)，于是解析战斗比例不变。实际普通遭遇前100关的变化来自人数与 difficulty，而不是 σ。本结论不覆盖整数舍入、不同成长坐标、随机品质、技能/辅助、不同射程或最小伤害。

参考 b_HP=121.2、b_ATK=51.8、b_DEF=5；普通敌150/22/4。装备每槽固有成长和空槽权重按实施契约§3计算，随机平面词缀各以 b_X×10% 为共同预算；DEF词缀不再沿用4，而为0.50。否则基础DEF仅5时，装备会把防御预算放大数倍，破坏属性间的选择价值。

## 3. 战斗指标：工作量、行动次数与生存分开

```text
expected_hit = damage(player_ATK, enemy_DEF) * (1+.05*(1.5-1))
encounter_work = sum(enemy_HP) / expected_hit
static_survival = player_HP / sum(damage(enemy_ATK, player_DEF))
```

encounter_work 是**连续攻击工作量**，不能叫实际回合。四只敌各需1.5次攻击时，逐只击杀至少花8次攻击，而非6次。static_survival 假定所有敌人持续存活同时输出，是压力指标，不能拿它直接判断能否赢；实际战斗击杀会降低后续敌方输出。

下面表格无词缀、辅助、治疗、距离，offset=0、variance=1，战前L=il=S。离散模型每次玩家攻击后，仍存活的每只敌攻击一次；伤害与面板最终取整，不抽暴击。**不是完整格子战斗模拟**。S1采用普通参考敌以便比较；真实训练敌130/12/3另验收。

| S | G(S) | 装备倍率 G^0.6 | 参考ATK | 参考HP | encounter_work | static_survival | 非暴击攻击次数 |
|---|---:|---:|---:|---:|---:|---:|---:|
| 1 | 1.000 | 1.000 | 51.8 | 121.2 | 2.719 | 7.667 | 3 |
| 3 | 1.439 | 1.244 | 74.5 | 174.4 | 2.791 | 7.446 | 3 |
| 10 | 4.165 | 2.354 | 215.7 | 504.8 | 5.299 | 7.052 | 8 |
| 20 | 13.163 | 4.695 | 681.9 | 1,595.4 | 5.362 | 6.943 | 8 |
| 50 | 123.457 | 17.985 | 6,395.1 | 14,963.0 | 5.552 | 6.634 | 8 |
| 100 | 1,066.222 | 65.571 | 55,230.3 | 129,226.2 | 5.870 | 6.173 | 8 |
| 500 | 375,955.286 | 2,213.511 | 19,474,483.8 | 45,565,780.7 | 5.870 | 6.173 | 8 |
| 1000 | 5,565,747.605 | 11,151.007 | 288,305,725.9 | 674,568,609.7 | 5.870 | 6.173 | 8 |

S100及以上离散参考战斗结束剩约35.2%HP。Mini Boss按实施契约§4.3计算，非暴击9次攻击；它的HP由四怪中单体基准×6得出，不是把完整四怪遭遇再乘6。

这些参考值取代原表中使用战后L=S+1的结果。参考套装无随机词缀，所以它用于尺度隔离，并不证明实际稀有度、掉落和构筑的平均强度。

## 4. σ、装备落后与真实奖励空间

对于同一种参考装备，设等级与物品级的偏差导致共同属性比率q：

```text
q = [G(L)/G(S)]^0.4 * [G(il)/G(S)]^0.6
```

只有q=1时σ才从总属性表达式消失；只要存在等级或装备落后，σ就直接影响战斗难度。混装还要按槽位权重算，不能把il取简单平均。

| S | 整套装备落后 | q（L=S） | encounter_work | static_survival |
|---|---:|---:|---:|---:|
| 20 | 5级 | 0.726 | 7.590 | 4.479 |
| 20 | 10级 | 0.501 | 11.465 | 2.777 |
| 100 | 10级 | 0.812 | 7.365 | 4.646 |
| 500 | 10级 | 0.954 | 6.173 | 5.788 |
| 1000 | 10级 | 0.977 | 6.022 | 5.974 |

全裸与“7件il1 Common无词缀”在此夹具下同为q=1/G(S)^0.6；S20静态生存约1.01次敌方齐攻。真实il1装备有词缀，两者不应称为同一实际构筑。装备的必要性需报告正常出装相对全裸的推进差异，不再把“所有S≥20裸装生存<2”冒充全构筑定理。

### 后期爽感的真实代价

S500整套装备全部+1 il，乘区提升约0.461%；单换一个槽还要乘该槽权重。把**所有战斗属性共同提高m倍**映射成同difficulty区间的等效关卡空间：

```text
delta_S = (S+20) * (m^(1/4)-1)
```

S500、m=1.00461，delta_S约**0.60关**，不是60关。单武器+1 il只提高部分ATK，不能直接套这个全属性公式。在S100，整套从il100换成110为 (130/120)^2.4−1≈21.18%，也不是旧表的23.2%。

常速率会强化每件+1il的数字跳跃，但更早触顶；幂律会弱化后期il差异。因此上线需要实际测量装备替换间隔、稀有度/词缀带来的有效属性增量和可推进距离，不以数字可读性替代玩家动机。

Common到Mythic的“5条×2.75=13.75倍”只是极端词缀数量强度比；不是整件、整套或角色的13.75倍战力。实际效果受属性分布、槽权重、基础值和概率上限影响。稀有度是有限的奖励空间，也不能永久补偿所有后期成长衰减。

## 5. EXP、经济和辅助系统

**EXP。** need=100×count(L)×G(L)，每次击杀按G(S)、offset、type与catchup结算。普通完美参考关才有战后L=S+1恒等式。附录的100个固定seed、每条1000关（含每10关Boss）的“全清EXP轨迹”结果：战前等级差P95=1、最大1。它假定每关都能清，无掉落、战败或特殊事件，不能代替实施契约M5。

**经济。** 收入和价格统一G只消除结构性的尺度漂移；不会自动保证期望收入、低级物品出售cap、掉落offset与购买力。最高+3il相对价格增幅在S1为1.706，高于旧曲线1.643。沿用roll_ratio和Buy/Sell结构，但期望必须用E[Rarity×Affix]，不能把有相关性的两项均值相乘。按当前12词缀的加权不放回抽样，联合期望约2.136384474；原1.705×1.190约2.02895，低估约5.3%。BaseItemValue重定为30，普通卖装目标为战斗Gold的5..18%。

原k50还用Mythic平均词缀质量证明最高roll不截断，论证不成立。用AffixMultiplier≤3和最高il偏移得到k≥83.85，定为100；附录枚举联合期望并检查这个保守界。生产代码仍须验证槽位过滤、手工物品和取整。

**副英雄。** 原250固定召唤价遇到G增长收入会失去约束，原线性伤害又无法跟上敌人。因此定价取收藏的累计投入坐标，伤害按每角色期望投入归一的坐标，并受主角等级限制；仍保留原抽取和重复升级机制。具体常量已在实施契约§6.2定案。其攻击间隔是秒，不能塞进“每回合DPS”表。

**魔法书。** 不消耗一次行动，改变真实战斗节奏；主角裸攻击基准与含魔法书/副英雄的测试必须分别报告，不能靠辅助输出掩盖主角成长错误。

## 6. 数值范围与发布地平线

G始终无界，任意正次幂最终都会撞有限存储范围。“S≈5958安全上限”只可能对应某一个未说明的属性基数；Boss、词缀、倍率链与累计货币会有不同边界，不能用它承诺整个游戏可玩到那里。

本版在S1000、il1003、所有槽Mythic并各拥有该属性最高roll的保守界：
`stat_X <= b_X * G(1000)^0.4 * G(1003)^0.6 * (1.4 + 7*0.1*2.75*1.2)`。
主动技能最高1.9、对应类型增伤1.5、暴击2.5后也低于1e12；附录检查这个上界。独特效果和运行时重复触发仍要在生产测试覆盖。

设计采用明确Stage1000发布边界，保存旧档备份，超范围历史记录保留；不会通过分别钳制双方属性伪装“无尽”。未来扩展需要重新评估收益粒度、资源规模与完整伤害链，不能只提高一个上限。

## 7. 可复现计算

下面是**文档模型**，只依赖Python标准库；正数取整与Godot规则对齐。复制代码块到临时文件运行，或提取本文件唯一python代码块执行。它不读取生产资源，不代表GDScript测试通过。

检查范围：精确G、权重、护甲边界、S1..1000解析与离散参考、Boss、EXP-only轨迹、经济联合期望和保守数值上界。实际装备掉落、特殊事件、格子移动、辅助计时、经济和迁移留给实施契约M5–M8。

```python
import math

def g(x):
    return ((max(x, 1) + 20) / 21) ** 4

def count(s):
    return min(4, 1 + (s - 1) // 3)

def difficulty(s):
    if s <= 10:
        return .9 + .1 * (s - 1) / 9
    if s <= 100:
        return 1 + .1 * (s - 10) / 90
    return 1.1

def hit(a, d):
    return a / (1 + max(d, 0) / a) if a > 0 else 0.

def iround(x):  # nonnegative Godot-style rounding
    return math.floor(x + .5)

def case(s, il=None, level=None, boss=False):
    il = s if il is None else il
    level = s if level is None else level
    k = g(level) ** .4 * g(il) ** .6
    pa, ph, pd = [b * k for b in (51.8, 121.2, 5)]
    c = 4 if boss else count(s)
    eh = 150 * g(s) * c ** -.6 * difficulty(s)
    ea = 22 * g(s) * c ** -.8 * difficulty(s)
    ed = 4 * g(s) * difficulty(s)
    if boss:
        eh, ea, ed, c = eh * 6, ea * 1.5, ed * 1.25, 1
    work = c * eh / (hit(pa, ed) * 1.025)
    survival = ph / (c * hit(ea, pd))
    # Discrete final integer stats, no criticals, all in range.
    pa, ph, pd, eh, ea, ed = map(iround, (pa, ph, pd, eh, ea, ed))
    dealt, received = max(1, iround(hit(pa, ed))), max(1, iround(hit(ea, pd)))
    hp, actions = ph, 0
    enemies = [eh] * c
    while enemies and hp > 0:
        enemies[0] -= dealt
        actions += 1
        if enemies[0] <= 0:
            enemies.pop(0)
        hp -= len(enemies) * received
    return work, survival, actions, hp / ph

assert g(1) == 1
assert hit(0, 0) == 0 and hit(100, 0) == 100
assert hit(100, 100) == 50
assert max(1, iround(hit(100, 5e6))) == 1
assert math.isclose(hit(3e8, 7e8), 1e6 * hit(300, 700))
weights = ((0,.15,.4,.1,.2,.05,.1),
           (.6,0,0,.15,0,.15,.1),
           (0,.25,.45,0,.2,.05,.05))
assert all(math.isclose(sum(w), 1) for w in weights)
for s in range(1, 1001):
    assert g(s+1) > g(s)
    assert math.isclose(g(s+1)/g(s), ((s+21)/(s+20))**4)
    if s >= 3:
        w, v, actions, hp = case(s)
        assert (2 <= w <= 6) if s < 10 else (4 <= w <= 8)
        assert 4 <= v <= 9
        if s >= 10:
            assert actions == 8 and hp > 0
    if s % 10 == 0:
        w, v, actions, hp = case(s, boss=True)
        assert 8 <= actions <= 12 and hp > 0
# A conservative numerical bound, not proof of content balance.
max_scale = g(1000)**.4 * g(1003)**.6
max_stats = [b * (1.4 + 7*.1*2.75*1.2) * max_scale
             for b in (51.8, 121.2, 5)]
assert max(max_stats) < 1e12
assert max_stats[0] * 1.9 * 1.5 * 2.5 < 1e12

# Experience-only seeded trajectory: assumes every encounter is cleared.
# Stable LCG keeps this probe independent from Python random versions.
deltas = []
for seed in range(100):
    state, level, xp = seed + 1, 1, 0
    for s in range(1, 1001):
        deltas.append(abs(level - s))
        boss = s % 10 == 0
        for _ in range(1 if boss else count(s)):
            state = (1664525 * state + 1013904223) & 0xffffffff
            u = state / 2**32
            off = (0 if u < .4 else 1 if u < .55 else -1 if u < .7
                   else 2 if u < .8 else -2 if u < .9 else 3 if u < .95 else -3)
            off = 0 if s <= 2 or boss else max(1, s + off) - s
            reward = iround(100*g(s)*(1+.06*off)*(4 if boss else 1)
                           * max(.25, min(2, 1+.1*(s-level))))
            xp += max(1, reward)
            while level < 1000 and xp >= iround(100*count(level)*g(level)):
                xp -= iround(100*count(level)*g(level))
                level += 1
            if level == 1000:
                xp = 0
deltas.sort()
p95 = deltas[math.floor(.95*(len(deltas)-1))]
assert p95 <= 3 and max(deltas) <= 6
# Exact expected economic weight for weighted sampling without replacement.
roll_weights = (1.2,1.2,1.1,.9,.8,.7,.6,.55,.45,.45,.25,.35)
econ_weights = (1,.9,.8,1.3,1.5,1.4,2,1.5,2.5,1.8,2,2.2)
distribution, expected_sum = {0:1.0}, [0.0]
total_weight = sum(roll_weights)
for draws in range(1,6):
    next_distribution = {}
    for mask, probability in distribution.items():
        used = sum(w for i,w in enumerate(roll_weights) if mask & (1<<i))
        for i,w in enumerate(roll_weights):
            if not mask & (1<<i):
                nxt = mask | (1<<i)
                next_distribution[nxt] = next_distribution.get(nxt,0) + probability*w/(total_weight-used)
    distribution = next_distribution
    expected_sum.append(sum(probability*sum(w for i,w in enumerate(econ_weights)
                                           if mask & (1<<i))
                            for mask,probability in distribution.items()))
rarity_probs = (.6,.25,.1,.04,.01,0)
rarity_values = (1,1.5,3,7,15,35)
affix_counts = (1,2,3,4,5,5)
mu = sum(p*r*(1+.075*expected_sum[n])
         for p,r,n in zip(rarity_probs,rarity_values,affix_counts))
assert math.isclose(mu,2.1363844737892865)
assert 100 >= 35*3*g(4)/mu
print(f"Economy model: joint mean={mu:.9f}, conservative k bound={35*3*g(4)/mu:.3f}")

print("stage | G | item_scale | work | survival | actions | HP remaining")
for s in (1, 3, 10, 20, 50, 100, 500, 1000):
    w, v, a, hp = case(s)
    print(f"{s:4} | {g(s):.3f} | {g(s)**.6:.3f} | {w:.3f} | {v:.3f} | {a} | {hp:.1%}")
print(f"EXP-only: 100 seeds, P95 gap={p95}, max gap={max(deltas)}")
print(f"S500 all-slot +1 il: equivalent stages={520*((g(501)/g(500))**.6)**.25-520:.6f}")
print("PASS: analytic, discrete reference, EXP-only, economy-model and numeric-bound probes")
```

预期最后一行：`PASS: analytic, discrete reference, EXP-only, economy-model and numeric-bound probes`。本轮执行结果与表格一致。后续修改参数必须重新运行本计算并由生产实现生成同一输入的对照，不能只手工改表。

## 8. 给实现者的最终反馈

先修重算一致性，再完成整套数值切换；装备聚合、经济和迁移与新曲线是同一个发布单元。用基准算例保证数学方向，用生产数据与逐行动测试保证能玩，用真实掉落轨迹验证“打到装备后愿意继续推进”。

本稿已关闭参数选择和旧文互相覆盖的问题。尚未执行的运行时检查被明确保留为发布验收，而不是写成设计已经证明的事实。
