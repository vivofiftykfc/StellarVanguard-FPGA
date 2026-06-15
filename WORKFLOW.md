# WORKFLOW — 开发工作流 & Agent/Skill 编排

## 1. 开发流程总览

```
REQUEST --> Phase 0: Plan --> Phase 1: Implement --> Phase 2: Review
                │                     │                      │
                ▼                     ▼                      ▼
          planner + architect   3 Agent 并行编码        3 Agent 交叉审查
                                                       + security-review
                                                       + silent-failure-hunt
                                                              │
                                                              ▼
          DEPLOY <-- Phase 4: Verify <-- Phase 3: Build
                          │                    │
                          ▼                    ▼
                   e2e-runner + 上板    build-error-resolver
                                        + Vivado Synthesis
```

## 2. 各 Phase 详细操作

### Phase 0: Plan

**Agent 调用** (可并行):

| Agent | 输入 | 输出 |
|-------|------|------|
| `planner` | feature 需求 | 实现计划 (文件列表/修改范围/依赖/风险) |
| `architect` | 现有架构 + feature | 架构影响评估 (接口/数据流/资源变更) |

---

### Phase 1: Implement (3 Agent 并行)

```markdown
## Agent A — 游戏逻辑 (game_engine.v)
  职责: 状态机, 玩家, 敌机, 子弹, 碰撞, 爆炸, 星空, 计分
  关键约束:
    - 端口用 flat packed vector, 禁止 unpacked array port
    - for 循环用 found 标志, 禁止修改变量模拟 break
    - localparam 位宽充足 (32 需 6 bits, 不可 5'd32)
    - 输出信号展平规范见 ARCHITECTURE.md 第5节

## Agent B — 渲染管线 (render.v)
  职责: 9 层独立 always @(*) + 最终 MUX + 文字渲染
  关键约束:
    - 每层独立 always @(*) (不超 150 行)
    - font_rom 在最终层共享查询
    - 函数参数数量正确 (str_char:3, text_draw:7)
    - 与 game_engine 接口对齐

## Agent C — 顶层 & 外设 (top.v, vga_ctrl.v, font_rom.v, .xdc)
  职责: 时钟分频, 按钮消抖, VGA 时序, 顶层连线, 引脚约束
  关键约束:
    - top.v 内部 wire 匹配 game_engine 的 flat vector 端口
    - XDC 引脚对照 Basys3 官方 master XDC
    - vga_ctrl 640x480@60Hz 标准时序
```

**每个 Agent 完成后立即触发** (3 Skill 并行):

```bash
/code-review <agent's file>       # 代码质量
/security-review <agent's file>   # 安全检查
/simplify <agent's file>          # 简化 & 去冗余
```

---

### Phase 2: Review (3 Agent 并行交叉审查)

| Agent | 检查维度 | 关键检查项 |
|-------|---------|-----------|
| `code-reviewer` | 全项目质量 | 接口一致性, 位宽匹配, 命名规范, 函数参数正确 |
| `silent-failure-hunter` | 静默故障 | 复位完整性, case default, if-else 缺失, 隐式 latch, 边界条件 |
| `security-reviewer` | 安全可靠性 | 无硬编码密钥, 引脚约束正确, 输入消抖, 无无限循环 |

**审查结果分级:**

| Level | 示例 | 动作 |
|-------|------|------|
| CRITICAL | Synth 8-2539/3380/285/970 | **BLOCK** — 必须修复 |
| HIGH | render 单块 >150 行 | **WARN** — 应修复 |
| MEDIUM | 注释不完整 | **INFO** — 考虑修复 |
| LOW | 命名可优化 | **NOTE** — 可选 |

---

### Phase 3: Build

```tcl
# Vivado Tcl Console
set_param general.maxThreads 16
set_param synth.elaboration.rodir false
# → Run Synthesis → Run Implementation → Generate Bitstream
```

如综合失败 → `build-error-resolver` agent 分析修复 → 循环至通过。

---

### Phase 4: Verify

上板测试 (Basys3) + 按 PRD.md 第5节验收清单逐项检查。

---

## 3. Agent & Skill 速查表

### 本项目 Agent

| Agent | 用途 | Phase |
|-------|------|-------|
| `planner` | 实现计划 | 0 |
| `architect` | 架构评估 | 0 |
| `claude` (general) | RTL 编码 | 1 |
| `code-reviewer` | 代码审查 | 1后, 2 |
| `security-reviewer` | 安全审查 | 2 |
| `build-error-resolver` | 综合错误修复 | 3 |
| `silent-failure-hunter` | 静默故障扫描 | 2 |
| `e2e-runner` | 功能验证 | 4 |

### 本项目 Skill

| Skill | 触发命令 | Phase |
|-------|---------|-------|
| code-review | `/code-review` | 1后, 2 |
| security-review | `/security-review` | 2 |
| simplify | `/simplify` | 1后 |
| ecc:build-fix | `/ecc:build-fix` | 3 |
| ecc:refactor-clean | `/ecc:refactor-clean` | 2 |
| ecc:security-scan | `/ecc:security-scan` | 2 |

### 并行调用模板

```bash
# Phase 1 完成后 — 对同一文件并行执行 3 个 Skill
/code-review rtl/game_engine.v
/security-review rtl/game_engine.v
/simplify rtl/game_engine.v

# Phase 2 — 3 个 Agent 并行审查全项目
Agent: code-reviewer       → 全项目质量
Agent: silent-failure-hunter → 静默故障
Agent: security-reviewer   → 安全可靠性
```

### 文件修改 → 审查映射

| 修改文件 | 触发审查 |
|---------|---------|
| game_engine.v | code-reviewer + security-reviewer |
| render.v | code-reviewer |
| top.v | code-reviewer + security-reviewer |
| .xdc | security-reviewer |
| 多文件 | 全部 3 Agent |

---

## 4. Vivado 快速参考

```tcl
set_param general.maxThreads 16
set_param synth.elaboration.rodir false
set_param synth.opt.retiming false
report_utilization -file utilization.rpt
report_timing_summary -file timing.rpt
```

---

## 5. 修订历史

| 版本 | 日期 | 变更 |
|------|------|------|
| v1.0 | 2026-06-10 | 初始工作流文档 |
