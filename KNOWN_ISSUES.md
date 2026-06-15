# KNOWN ISSUES — 已知问题与修复记录

本文档用于新对话中 Agent 的上下文参考，避免重复踩坑。

---

## 已修复 Issue 清单

### Issue #1: Synth 8-2539 — unpacked array port

**根因:** Vivado 不支持模块端口用 unpacked 数组 `wire [9:0] foo [0:19]`

**修复:** 展平为 packed vector: `wire [199:0] foo`, 索引用 `foo[i*10 +: 10]`

**展平位宽表:**

| 信号 | 条目x位宽 | 展平 | 索引 |
|------|----------|------|------|
| enemy_x | 20x10 | [199:0] | `[i*10 +: 10]` |
| enemy_y | 20x9 | [179:0] | `[i*9 +: 9]` |
| enemy_type | 20x2 | [39:0] | `[i*2 +: 2]` |
| bullet_x | 5x10 | [49:0] | `[i*10 +: 10]` |
| bullet_y | 5x9 | [44:0] | `[i*9 +: 9]` |
| exp_x | 5x10 | [49:0] | `[i*10 +: 10]` |
| exp_y | 5x9 | [44:0] | `[i*9 +: 9]` |
| exp_life | 5x5 | [24:0] | `[i*5 +: 5]` |
| star_x | 32x10 | [319:0] | `[i*10 +: 10]` |
| star_y | 32x9 | [287:0] | `[i*9 +: 9]` |
| star_bright | 32x2 | [63:0] | `[i*2 +: 2]` |

---

### Issue #2: Synth 8-3380 — loop non-convergence

**根因:** for 循环内修改循环变量模拟 break (`ej = MAX_ENEMIES`)

**修复:** 用 `found` 标志:
```verilog
found = 1'b0;
for (ej = 0; ej < MAX; ej = ej + 1) begin
    if (!active[ej] && !found) begin
        // ... action ...
        found = 1'b1;
    end
end
```

**影响位置:** 敌机spawn, 子弹spawn, 爆炸生成x2 (共4处)

---

### Issue #3: Synth 8-970 — function arg count mismatch

**根因:** `str_char(str, n, len)` 定义3参数, 调用时传了4个

**修复:** 统一为3参数调用: `str_char(str, (px-x)>>3, len)`

---

### Issue #4: localparam 位宽溢出 — `5'd32 = 0`

**根因:** 32 需要6 bits, `5'd32` 截断为 0

**修复:** `5'd32` → `6'd32`

**检查规则:** N'dV 要求 V < 2^N. 边界值: 16需5bit, 32需6bit

---

### Issue #5: 巨型组合逻辑块 — 综合极慢

**根因:** render.v 284行 single always @(*) — Vivado 单线程优化

**修复:** 拆为10个独立 always @(*) 块 (背景/星星/爆炸/敌机/子弹/玩家/HUD/标题/结束/最终MUX)

---

### Issue #6: 敌人刷新扎堆 + X 范围不足

**根因 (双重问题):**
1. **X 范围仅 0-511**: `{1'd0, lfsr_r[8:0]}` 只用 9bit → 屏幕右 128px 空白
2. **相邻帧高度相关**: LFSR 每帧只移 1 位，连续 spawn 的 X 高 8 位几乎相同 → 扎堆

**修复 (2026-06-14):**
1. **X 范围** → 0-638: `{1'd0, lfsr_r[8:0]} + {3'd0, lfsr_r[8:2]}` = `x*5/4` 缩放
2. **破相关性** → LFSR 每帧推进 4 步: 用多项式 `(x^16 + x^14 + x^13 + x^11 + 1)^4` 的 4 个反馈位

**注意:** 仍遗留 639 这一列无法覆盖（640 的整数倍问题，不影响游戏体验）

---

### Issue #7: btnL 硬件故障

**现象:** btnL (W18) 左移不可用，代码逻辑完全对称

**修复:** btnU 作为左移备份（`btn_left || btn_up`）

## Agent 代码自查清单

### CRITICAL (不通过=综合失败)
- [ ] 端口无 unpacked 数组
- [ ] for 循环无修改循环变量
- [ ] localparam 位宽 >= 值所需
- [ ] 函数调用参数数量正确

### HIGH (时序/功能风险)
- [ ] 组合块 < 150行
- [ ] 所有 reg 有复位值
- [ ] case 有 default
- [ ] 时序用 `<=`
- [ ] 碰撞/子弹发射用 `player_y_r` 而非 `PLAYER_Y_FIXED`（用常数省 LUT 但功能错误）

## Vivado 错误速查

| 错误码 | 含义 | 见 Issue |
|--------|------|---------|
| Synth 8-2539 | unpacked array port | #1 |
| Synth 8-3380 | loop non-convergence | #2 |
| Synth 8-970 | function arg mismatch | #3 |
| Synth 8-285 | synthesis failure | 查前置错误 |
| Synth 8-3352 | multi-driven net | 同一信号多处赋值 |
