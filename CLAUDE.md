# STELLAR VANGUARD — Verilog FPGA 射击游戏

Basys3 (XC7A35T-1CPG236C) 上的 VGA 射击游戏。使用 Verilog 硬件描述语言，Vivado 综合实现。

## 项目结构

```
d:\study_code\vganew\
├── CLAUDE.md                    # 本文件 — 项目说明和当前状态
├── README.md
├── PRD.md                       # 产品需求文档
├── ARCHITECTURE.md              # 系统架构设计
├── WORKFLOW.md                  # 开发工作流
├── KNOWN_ISSUES.md              # Vivado 综合陷阱与自查清单
├── rtl/                         # RTL 源文件
│   ├── top.v                    # 顶层模块 — 所有子模块的集成
│   ├── vga_ctrl.v               # VGA 640x480@60Hz 时序控制器
│   ├── game_engine.v            # 游戏逻辑核心（状态机、碰撞、敌人AI）
│   ├── render.v                 # 像素渲染管线（9层叠加）
│   └── font_rom.v               # 8x8 字符点阵 ROM（43个字符）
├── sim/
│   └── tb_top.v                 # 仿真测试平台
├── constraints/
│   └── basys3_vga.xdc           # 引脚约束 + 时序约束
└── vganew/                      # Vivado 项目目录
    └── vganew.xpr               # Vivado 项目文件
```

## 架构

```
CLK100MHz → 时钟分频器 ─→ vga_ctrl (行/场计数器)
                           ↓
                    game_engine (游戏状态机 @ new_frame 60Hz)
                           ↓
                    render (9层像素 MUX @ tick 25MHz) → VGA输出

Buttons → 5路消抖器(10ms) → game_engine (控制输入)
Score   → double-dabble BCD → 7段数码管 (扫描复用 ~763Hz)
                             → render (VGA 十进制显示)
SW[0]   → 复位
```

## 按键/操作映射

| 按键 | 引脚 | 功能 | 状态 |
|------|------|------|------|
| btnU | T18 | 上移 + 左移(备份) | ✅ |
| btnL | W18 | 左移 | ❌ 硬件故障（代码中 btnU 作备份） |
| btnR | T17 | 右移 | ✅ |
| btnD | U17 | 下移 | ✅ |
| btnC | U18 | 开始游戏 / 开火 | ✅ |
| SW[0] | V17 | 复位（拨到 ON 再回 OFF） | ✅ |

引脚已验证 vs [Basys3 Master XDC](https://github.com/Digilent/digilent-xdc) 官方定义。

## 关键时序

- 主时钟: 100MHz
- VGA 像素时钟: 25MHz (tick = clk_div==3)
- 帧率: ~60Hz (new_frame 脉冲)
- 消抖: 10ms (1,000,000 周期 @ 100MHz)
- POR: ~2.56µs (255 周期 @ 100MHz)

## 游戏状态机

| 状态 | 编码 | 说明 |
|------|------|------|
| ST_TITLE    | 2'd0 | 标题画面，等待 btnC 开始 |
| ST_PLAYING  | 2'd1 | 游戏中，处理移动/射击/碰撞 |
| ST_DYING    | 2'd2 | 死亡动画，无敌计时中 |
| ST_GAMEOVER | 2'd3 | 游戏结束，按 btnC 回标题 |

## 渲染管线（9 层，从低到高优先级）

1. 背景渐变（蓝色深度随 Y 变化）
2. 星星（16 颗，4 级亮度）
3. 爆炸特效（5 个，曼哈顿距离粒子）
4. 敌人（12 个，3 种类型：红菱/紫十/橙菱）
5. 子弹（5 发，3×8 黄矩形）
6. 玩家飞机（16×16 箭头精灵，无敌闪烁）
7. HUD（SCORE/WAVE/LIVES，y≥400）
8. 标题画面（ST_TITLE 时显示）
9. 游戏结束覆盖层（ST_GAMEOVER 时显示）

## 当前问题与修复记录

### ✅ 已修复

| # | 问题 | 修复 |
|---|------|------|
| 1 | VGA 引脚错误 — 用了 Nexys4 引脚 | 改为 Basys3 官方引脚 |
| 2 | 时序违规 | 添加 `set_multicycle_path -setup 4` |
| 3 | 敌人全挤在同一位置 | LFSR ^ frame_counter + wave_spawned 偏移 |
| 4 | 文字乱码 — case 标签 3'd8/3'd9 截断 | 改为 4'd8/4'd9 |
| 5 | STELLAR VANGUARD 重复 — Y 范围 176→168 | 16 行改为 8 行 |
| 6 | GAME OVER 乱码/重复 — Y 范围 216→208 | case 标签宽度修复 + Y 范围收窄 |
| 7 | latch 问题 — fc_/fr_ 寄存器无默认值 | 添加默认值 |
| 8 | 分数十六进制显示 | BCD 转换后传入 render |
| 9 | LFSR 组合循环致 LUT 暴涨 | 移除 lfsr_next 阻塞赋值 |
| 10 | Wave 除法器耗 LUT | 改回十六进制双字符显示 |
| 11 | ~~碰撞检测变量比较器耗 LUT → 改 PLAYER_Y_FIXED~~ | **已反向**（见 #13） |
| 12 | LUT 超资源 21876>20800 | MAX_ENEMIES 20→12, NUM_STARS 32→16, BCD除法器→double-dabble |
| 13 | 子弹发射和碰撞判定固定在底部 | 恢复使用 `player_y_r` 变量（#11 反向） |
| 14 | 敌人分布不均扎堆下降 | 移除 XOR+×10，改用 `{1'd0, lfsr_r[8:0]}` 直连 LFSR |
| 15 | 敌人刷新"扎堆"且右 128px 空白 | LFSR 每帧推进4步破相关性 + X 坐标 `*5/4` 扩展到 0-638 |

### ⚠️ 待解决 / 已知问题

1. **btnL 左移不可用** — 代码完全对称，怀疑 btnL 硬件故障。已加 btnU 作为左移备份
2. ~~**敌人刷新分布** — 当前用 `{1'd0, lfsr_r[8:0]}` 范围 0-511，屏幕右 128px 无敌人~~ **已修复**：现用 `*5/4` 扩展到 0-638，仅最右 1px 不可达

## Vivado 构建

### 命令行
```tcl
cd D:/study_code/vganew/vganew
open_project vganew.xpr
reset_project  # 清缓存（LUT 超时先试这个）
launch_runs synth_1 -jobs 4
wait_on_run synth_1
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
```

### Bitstream 位置
`vganew/vganew.runs/impl_1/top.bit`

### 常见错误及解决方案
- **资源超（24568 > 20800）**：`reset_project` 清缓存再试；或精简 game_engine 组合逻辑
- **引脚错误**：检查 `basys3_vga.xdc` 引脚是否匹配 Basys3 CPG236
- **时序违规**：如果 `set_multicycle_path` 不够，可添加 pipeline 寄存器

## 引脚约束摘要

所有引脚在 `constraints/basys3_vga.xdc` 中，关键引脚：
- CLK100MHZ: W5 (LVCMOS33)
- btnU/L/R/D/C: T18/W18/T17/U17/U18
- SW[0]: V17
- VGA: 使用电阻梯形 DAC 的 12 位 RGB（引脚参考 Basys3 Master XDC）
- 7段数码管 + LED：见 XDC 文件

## 开发环境

- 开发板: Digilent Basys3 (XC7A35T-1CPG236C)
- 工具: Vivado (2019+)
- 语言: Verilog-2001
