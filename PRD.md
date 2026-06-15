# PRD — STELLAR VANGUARD FPGA 飞机射击游戏

## 1. 产品概述

### 1.1 产品定位

在 Digilent Basys3 FPGA 开发板上实现一款经典的纵版卷轴飞机射击游戏，通过 VGA 输出到显示器，使用板载按钮操控。

### 1.2 目标用户

- FPGA 学习者 — 通过完整项目学习 Verilog 硬件设计
- 游戏爱好者 — 在 FPGA 上体验复古风格射击游戏
- 课程项目 — 适合数字系统设计课程大作业

### 1.3 核心指标

| 指标 | 目标值 |
|------|--------|
| 分辨率 | 640x480 @ 60Hz |
| 色彩深度 | 12-bit RGB (4096 色) |
| 同屏敌机数 | 最多 20 个 |
| 同屏子弹数 | 最多 5 个 |
| 同屏爆炸数 | 最多 5 个 |
| 星空粒子 | 32 颗 |
| 帧率 | 60 FPS (固定) |
| LUT 利用率 | < 50% XC7A35T |
| 综合时间 | < 5 分钟 |

---

## 2. 功能需求

### 2.1 游戏状态机

```
TITLE -> PLAYING -> DYING -> GAMEOVER
  ^                          |
  |--------------------------|
```

| 状态 | 描述 | 触发条件 |
|------|------|----------|
| TITLE | 标题画面，显示游戏名和操作提示 | 复位 / GAMEOVER 按开始 |
| PLAYING | 正常游戏 | TITLE 按开始 / DYING 无敌结束 |
| DYING | 受伤无敌闪烁 (2秒) | 玩家与敌机碰撞且还有命 |
| GAMEOVER | 显示最终分数 | 生命值归零 |

### 2.2 玩家飞机

- 初始位置: 屏幕中下方 (x=312, y=350)
- 移动速度: 5 像素/帧
- 碰撞体积: 16x16
- 射击冷却: 8 帧 (~133ms 间隔)
- 子弹速度: 8 像素/帧
- 初始生命: 3 条
- 受伤无敌时间: 120 帧 (2 秒)

### 2.3 敌机类型

| 类型 | 行为 | 速度 | 分值 | 颜色 |
|------|------|------|------|------|
| 基础型 (0) | 直线下降 | 2 px/帧 | 10 | 红 |
| Zigzag型 (1) | 蛇形左右摆动下降 | 1 px/帧 | 20 | 紫 |
| 快速型 (2) | 斜线快速下落 | 3 px/帧 | 15 | 橙 |

波次系统:
- 初始每波 3 个敌机，逐波增加至最大 8 个
- 波间隔 120 帧 (2 秒)
- 敌机 X 坐标随机分布

### 2.4 碰撞检测

- 子弹 vs 敌机: AABB 矩形碰撞 (每帧检测 5x20 = 100 组)
- 玩家 vs 敌机: AABB 矩形碰撞 (每帧检测 1x20 = 20 组)
- 命中效果: 生成爆炸粒子特效

### 2.5 爆炸特效

- 曼哈顿距离判定 (菱形扩散)
- 生命周期 16 帧，半径随时间缩小
- 颜色渐变: 白 -> 黄 -> 橙 -> 红

### 2.6 星空背景

- 32 颗星星持续向下滚动
- LFSR 16-bit 伪随机生成 X 坐标和亮度
- 4 级亮度 (灰阶)

### 2.7 HUD 显示

- 游戏区下方 80 行 (y=400-479) 显示 HUD
- SCORE: 当前分数 (BCD 4 位)
- WAVE: 当前波次
- LIVES: 小型飞机图标 x 剩余生命数

### 2.8 文字渲染

- 8x8 像素字符 ROM (A-Z, 0-9, 符号共 43 字符)
- 支持标题画面、HUD、游戏结束画面文字

### 2.9 7 段数码管

- 显示当前分数 (4 位 BCD)
- 多路复用扫描

---

## 3. 非功能需求

### 3.1 时序约束

| 约束 | 值 |
|------|-----|
| 主时钟 | 100MHz (周期 10ns) |
| VGA 像素时钟 | 25MHz (主时钟 4 分频) |
| 输入延迟 (按钮) | min 1.0ns / max 4.0ns |
| 输出延迟 (VGA) | min 1.0ns / max 4.0ns |

### 3.2 可综合约束 — Vivado 陷阱清单

**致命 (CRITICAL — 综合直接失败):**

| # | 禁止事项 | 原因 | 正确做法 |
|---|---------|------|----------|
| 1 | 模块端口使用 unpacked 数组 `wire [9:0] foo [0:19]` | Vivado Synth 8-2539 | 展平为 packed vector `wire [199:0] foo` + part-select `[i*10 +: 10]` |
| 2 | for 循环内修改循环变量模拟 break `ei = MAX` | Vivado Synth 8-3380 无法判定收敛 | 用 `found` 标志: `if (!active[i] && !found)` |
| 3 | localparam 值超出位宽 `5'd32` (32 需 6 bits) | 值截断为 0, 循环零次迭代 | 验证: `N'dV` 要求 V < 2^N |
| 4 | 纯组合逻辑 always @(*) 块超大 (>200 行) | Vivado 单线程优化, 综合极慢 | 拆为每个图层独立 always @(*) 块 |

**重要 (HIGH):**

| # | 要求 | 原因 |
|---|------|------|
| 5 | 所有寄存器有复位值 | 避免 X 态传播 |
| 6 | 单 always 块单信号赋值 | 避免多驱动冲突 |
| 7 | 时序逻辑用 `<=` (NBA) | 避免仿真-综合不匹配 |
| 8 | 整数不用 `integer` 声明不必要的大位宽 | 32-bit integer 可能引起 Vivado 循环分析困难 |

### 3.3 资源约束

| 资源 | 预算 | XC7A35T 总量 |
|------|------|-------------|
| LUT | < 10,400 (50%) | 20,800 |
| FF | < 20,800 (50%) | 41,600 |
| BRAM | < 25 (50%) | 50 |
| IO | < 50 | 250 |

---

## 4. 开发流程 & 多 Agent 编排

### 4.1 Agent 使用策略

本项目的 Claude Code Agent 编排采用 **分层并行** 策略：

```
                    ┌─────────────┐
                    │  Planner    │  Phase 0: 需求分析 + 任务拆分
                    └──────┬──────┘
                           │
              ┌────────────┼────────────┐
              │            │            │
         ┌────▼────┐ ┌────▼────┐ ┌────▼────┐
         │ Agent A │ │ Agent B │ │ Agent C │  Phase 1: 并行实现
         │ 游戏引擎│ │ 渲染器  │ │ 顶层+外设│
         └────┬────┘ └────┬────┘ └────┬────┘
              │            │            │
              └────────────┼────────────┘
                           │
              ┌────────────▼────────────┐
              │   Code-Reviewer (×3)   │  Phase 2: 并行审查
              │   Security-Reviewer     │  (代码写出后立即触发)
              │   Silent-Failure-Hunter │
              └────────────┬────────────┘
                           │
              ┌────────────▼────────────┐
              │  Build-Error-Resolver   │  Phase 3: 综合修复
              └────────────┬────────────┘
                           │
              ┌────────────▼────────────┐
              │  E2E-Runner / 上板测试  │  Phase 4: 验证
              └─────────────────────────┘
```

### 4.2 各 Phase 的 Agent 调用细则

#### Phase 0: 规划 (每次新 feature 触发)

```markdown
# 触发条件: 用户提出 feature 请求
1. 调用 planner agent — 生成实现计划
2. 调用 architect agent — 评估架构影响
# 两者可并行进行，结果汇总后进入 Phase 1
```

#### Phase 1: 并行实现 (3 Agent 同时工作)

```markdown
# 触发条件: PRD 明确, 架构评审通过
并行启动 3 个 agent:
| Agent | 负责文件 | Agent 类型 |
|-------|---------|-----------|
| game_logic | game_engine.v | claude (general-purpose) |
| renderer   | render.v      | claude (general-purpose) |
| infra      | top.v, vga_ctrl.v, font_rom.v, .xdc | claude (general-purpose) |

# 每个 Agent 完成后立即触发:
| Agent | 用途 |
|-------|------|
| code-reviewer | 代码质量审查 (命名/结构/风格) |
| security-reviewer | 安全检查 (无硬编码密钥/密码) |
| comment-analyzer | 注释完整性与准确性 |
```

#### Phase 2: 交叉审查 (Phase 1 全部完成后)

```markdown
# 3 个审查 agent 并行:
| Agent | 审查维度 |
|-------|---------|
| code-reviewer (senior) | 模块间接口一致性、数据流正确性 |
| silent-failure-hunter  | 错误吞没、bad fallback、reset 不完整 |
| refactor-cleaner       | 死代码检测、重复逻辑合并 |

# 审查结果分级:
| Level | 含义 | 动作 |
|-------|------|------|
| CRITICAL | 综合失败 / 功能错误 | BLOCK — 必须修复 |
| HIGH | 设计缺陷 / 资源浪费 | WARN — 应在合并前修复 |
| MEDIUM | 风格 / 可维护性 | INFO — 考虑修复 |
```

#### Phase 3: 综合验证

```markdown
# 触发条件: Phase 2 CRITICAL 全部清零
1. Vivado Run Synthesis
2. 如失败 -> build-error-resolver agent 分析并修复
3. 循环直到综合通过 + 无 CRITICAL warning
```

#### Phase 4: 功能验证

```markdown
# 触发条件: 综合通过 + 比特流生成成功
1. 上板测试 (Basys3 实机)
2. e2e-runner agent 编写测试用例
3. 验收标准全部通过 -> Done
```

### 4.3 Skill 使用策略

| Skill | 触发时机 | 用途 |
|-------|---------|------|
| `/code-review` | 每次 Agent 写出代码后 | 代码质量 + bug 检测 |
| `/security-review` | 代码涉及输入/状态机/引脚 | 安全检查 |
| `/simplify` | Phase 1 完成后 | 简化冗余逻辑 |
| `/ecc:build-fix` | Vivado 综合报错时 | 自动诊断修复 |
| `/ecc:refactor-clean` | Phase 2 | 死代码清理 |
| `/ecc:security-scan` | 提交前 | 无硬编码密钥/密码 |

### 4.4 并行 Skill 编排示例

当完成 game_engine.v 后，**同时**调用以下 Skill (各独立不冲突):

```
并行调用:
  /code-review game_engine.v        # 代码质量
  /security-review game_engine.v    # 安全检查
  /simplify game_engine.v           # 简化优化
```

---

## 5. 验收标准

### 5.1 综合验收

- [ ] 无 `Synth 8-2539` (unpacked array port)
- [ ] 无 `Synth 8-3380` (loop non-convergence)
- [ ] 无 `Synth 8-285` (synthesis failure)
- [ ] 无 `Synth 8-970` (argument count mismatch)
- [ ] 无 critical warning
- [ ] LUT 利用率 < 50%
- [ ] 时序收敛 (无负 slack)

### 5.2 功能验收

- [ ] 标题画面显示 "STELLAR VANGUARD" + 操作提示
- [ ] 按 btnC 开始游戏
- [ ] 飞机左右移动流畅 (btnL/btnR)
- [ ] 按 btnU 发射子弹 (有冷却间隔)
- [ ] 敌机按波次生成 (3 种类型混合)
- [ ] 子弹命中敌机: 敌机消失 + 加分 + 爆炸特效
- [ ] 玩家碰撞敌机: 减命 + 无敌闪烁 2 秒
- [ ] 3 条命用完: GAMEOVER + 显示最终分数
- [ ] GAMEOVER 按 btnC: 回到标题
- [ ] 7 段数码管显示当前分数
- [ ] VGA 画面稳定 60Hz 无闪烁
- [ ] 星空背景持续滚动
- [ ] HUD 显示 SCORE / WAVE / LIVES
- [ ] 3 种敌机颜色和行为各不相同

---

## 6. 风险 & 缓解

| 风险 | 概率 | 影响 | 缓解 |
|------|------|------|------|
| Vivado 综合时间过长 (>10min) | 中 | 中 | 拆分组合块 + maxThreads=16 |
| unpacked array port 报错 | 已规避 | — | flat packed vec + part-select |
| for-break 不可综合 | 已规避 | — | found 标志 |
| localparam 位宽溢出 | 已规避 | — | Code review 检查点 |
| Basys3 引脚约束不匹配 | 低 | 高 | 对照 Digilent 官方 master XDC |
| 时序不收敛 | 低 | 高 | 25MHz 极低频率, 余量巨大 |
| Agent 间接口不匹配 | 中 | 中 | Phase 2 交叉审查 + top.v 类型检查 |

---

## 7. 修订历史

| 版本 | 日期 | 变更 |
|------|------|------|
| v1.0 | 2026-06-10 | 初始 PRD, 包含 Agent/Skill 编排策略 |
