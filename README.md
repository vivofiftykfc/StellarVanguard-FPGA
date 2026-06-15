# STELLAR VANGUARD — FPGA 飞机射击游戏

基于 Xilinx Artix-7 (Basys3) 的 VGA 飞机射击游戏。纯 Verilog 实现，640×480 @ 60Hz。

## 快速导航

| 文档 | 内容 |
|------|------|
| [PRD.md](PRD.md) | 产品需求文档 — 功能规格、游戏设计、验收标准 |
| [ARCHITECTURE.md](ARCHITECTURE.md) | 系统架构 — 模块划分、数据流、时钟域、资源估算 |
| [WORKFLOW.md](WORKFLOW.md) | 开发工作流 — 多 Agent 并行策略、Code Review、Skill 调度 |
| [KNOWN_ISSUES.md](KNOWN_ISSUES.md) | 已知问题 & 修复记录 — Vivado 综合陷阱、Verilog 最佳实践 |

## 项目结构

```
vganew/
├── README.md              -- 本文件
├── PRD.md                 -- 产品需求文档
├── ARCHITECTURE.md        -- 架构设计文档
├── WORKFLOW.md            -- 开发工作流 (Agent/Skill 编排)
├── KNOWN_ISSUES.md        -- 已知问题与修复记录
├── rtl/                   -- Verilog RTL 源码
│   ├── top.v              # 顶层模块
│   ├── game_engine.v      # 游戏逻辑核心
│   ├── render.v           # VGA 像素渲染器
│   ├── vga_ctrl.v         # VGA 时序控制器
│   └── font_rom.v         # 8x8 字库 ROM
├── constraints/           -- XDC 引脚约束
│   └── basys3_vga.xdc
└── sim/                   -- 仿真测试台 (待补充)
    └── tb_top.v
```

## 平台信息

| 项目 | 详情 |
|------|------|
| **FPGA 芯片** | Xilinx Artix-7 XC7A35T-1CPG236C |
| **开发板** | Digilent Basys3 |
| **综合工具** | Vivado 2018.3+ (推荐 2022.1+) |
| **语言** | Verilog-2001 (可综合子集) |
| **显示** | VGA 640x480 @ 60Hz, 4-bit RGB (4096 色) |
| **输入** | 4 颗按钮 (左/右/发射/开始) + 复位 |
| **输出** | VGA 视频 + 7 段数码管 (分数显示) |
| **时钟** | 100MHz 片载晶振 -> 25MHz VGA 像素时钟 |
