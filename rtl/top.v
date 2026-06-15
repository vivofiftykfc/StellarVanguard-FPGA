//===================================================================
// top.v — STELLAR VANGUARD 顶层模块集成 (Basys3 开发板)
//===================================================================
// 【功能】顶层模块，将所有子模块组装在一起：
//   - vga_ctrl: VGA 时序控制器
//   - game_engine: 游戏逻辑引擎
//   - render: 像素渲染管线
//   - 按键消抖电路
//   - 时钟分频 (100MHz → 25MHz)
//   - 上电复位 (POR)
//   - 7段数码管 BCD 转换和扫描复用显示分数
//
// 按键映射: btnU=上移, btnL=左移, btnR=右移, btnC=开始+开火, btnD=下移, sw[0]=复位
//===================================================================

module top (
    input  wire         CLK100MHZ,
    input  wire         btnU,           // up
    input  wire         btnL,           // left
    input  wire         btnR,           // right
    input  wire         btnD,           // down
    input  wire         btnC,           // start/fire
    input  wire [15:0]  sw,             // switches (sw[0]=reset)
    output wire  [3:0]  VGA_R,
    output wire  [3:0]  VGA_G,
    output wire  [3:0]  VGA_B,
    output wire         VGA_HS,
    output wire         VGA_VS,
    output wire  [6:0]  seg,            // 7-seg cathodes (active low)
    output wire  [3:0]  an,             // 7-seg anodes (active low)
    output wire  [3:0]  led             // status LEDs
);

//———————————————————————————————————————————————————————————————————
// 时钟分频: 100MHz → 25MHz 使能脉冲（每4个时钟周期产生1个 tick）
//———————————————————————————————————————————————————————————————————
reg [1:0] clk_div;        // 2位计数器，从0计数到3
wire tick;                 // 25MHz 使能信号
assign tick = (clk_div == 2'd3);  // 当计数值为3时产生tick脉冲

always @(posedge CLK100MHZ) begin
    clk_div <= clk_div + 2'd1;  // 每个时钟周期递增
end

//———————————————————————————————————————————————————————————————————
// 上电复位 (POR): 配置完成后将 rst_n 保持低电平约 2.56µs
//———————————————————————————————————————————————————————————————————
reg [7:0] por_cnt;        // POR 计数器（8位，计数到255）
reg       por_rst_n;       // POR 产生的复位信号（低电平有效）

always @(posedge CLK100MHZ) begin
    if (por_cnt < 8'd255) begin
        por_cnt   <= por_cnt + 8'd1;  // 递增计数器
        por_rst_n <= 1'b0;            // 保持复位状态
    end else begin
        por_cnt   <= por_cnt;          // 计数到255后停止
        por_rst_n <= 1'b1;            // 释放复位
    end
end

wire rst_n;
assign rst_n = por_rst_n && !sw[0];  // 全局复位 = POR 复位 && SW[0]=OFF（SW[0]=ON时手动复位）

//———————————————————————————————————————————————————————————————————
// 按键消抖: 10ms 去抖动（100MHz 下计数 1,000,000 个周期）
//———————————————————————————————————————————————————————————————————
localparam DB_LIMIT = 20'd1_000_000;  // 消抖计数阈值：20位宽，100万次（10ms）

genvar gi;                           // 生成块的循环变量
generate
    for (gi = 0; gi < 5; gi = gi + 1) begin : gen_db  // 生成5个消抖器（含 btnD）
        reg        stable;    // 去抖动后的稳定按键值
        reg [19:0] cnt;       // 消抖计数器

        wire raw;             // 原始按键输入
        assign raw = (gi == 0) ? btnU :
                     (gi == 1) ? btnL :
                     (gi == 2) ? btnR :
	                     (gi == 3) ? btnC : btnD;

        always @(posedge CLK100MHZ or negedge rst_n) begin
            if (!rst_n) begin
                stable <= 1'b0;   // 复位时清零
                cnt    <= 20'd0;
            end else begin
                if (raw != stable) begin        // 检测到电平变化
                    if (cnt < DB_LIMIT)
                        cnt <= cnt + 20'd1;     // 持续计数直到阈值
                    else begin
                        stable <= raw;           // 达到阈值 → 更新稳定值
                        cnt    <= 20'd0;          // 重置计数器
                    end
                end else begin
                    cnt <= 20'd0;                 // 电平未变 → 清零计数器
                end
            end
        end
    end
endgenerate

wire btn_fire_d, btn_left_d, btn_right_d, btn_start_d, btn_up_d, btn_down_d;
assign btn_up_d    = gen_db[0].stable;  // 消抖后上移键（btnU）
assign btn_left_d  = gen_db[1].stable;  // 消抖后左移键（btnL）
assign btn_right_d = gen_db[2].stable;  // 消抖后右移键（btnR）
assign btn_fire_d  = gen_db[3].stable;  // 消抖后开火键（btnC，游戏中开火）
assign btn_start_d = gen_db[3].stable;  // 消抖后开始键（btnC，标题画面开始）
assign btn_down_d  = gen_db[4].stable;  // 消抖后下移键（btnD）

//———————————————————————————————————————————————————————————————————
// VGA 控制器：生成 640x480@60Hz 的同步信号和像素坐标
//———————————————————————————————————————————————————————————————————
wire        vga_hs, vga_vs;
wire [9:0]  h_count, v_count;
wire        active, new_frame;

vga_ctrl u_vga (
    .clk      (CLK100MHZ),
    .tick     (tick),
    .rst_n    (rst_n),
    .hsync    (vga_hs),
    .vsync    (vga_vs),
    .h_count  (h_count),
    .v_count  (v_count),
    .active   (active),
    .new_frame(new_frame)
);

//———————————————————————————————————————————————————————————————————
// 游戏引擎 —— 使用扁平打包（flat-packed）向量传输游戏状态数据
// 因为 Verilog 模块端口不支持 unpacked array，所以所有数组都按位展开
//———————————————————————————————————————————————————————————————————
wire  [9:0]  player_x, player_y;
wire [199:0] enemy_x;     wire [179:0] enemy_y;
wire  [39:0] enemy_type;  wire  [19:0] enemy_active;
wire  [49:0] bullet_x;    wire  [44:0] bullet_y;
wire   [4:0] bullet_active;
wire  [49:0] exp_x;       wire  [44:0] exp_y;
wire  [24:0] exp_life;    wire   [4:0] exp_active;
wire [319:0] star_x;      wire [287:0] star_y;
wire  [63:0] star_bright;
wire [15:0]  score;
wire  [7:0]  wave_num, invincible;
wire  [1:0]  lives, state;

game_engine u_game (
    .clk              (CLK100MHZ),
    .rst_n            (rst_n),
    .new_frame        (new_frame),
    .btn_left         (btn_left_d),
    .btn_right        (btn_right_d),
    .btn_fire         (btn_fire_d),
    .btn_up           (btn_up_d),
    .btn_down         (btn_down_d),
    .btn_start        (btn_start_d),
    .player_x         (player_x),
    .player_y         (player_y),
    .enemy_x          (enemy_x),
    .enemy_y          (enemy_y),
    .enemy_type       (enemy_type),
    .enemy_active     (enemy_active),
    .bullet_x         (bullet_x),
    .bullet_y         (bullet_y),
    .bullet_active    (bullet_active),
    .exp_x            (exp_x),
    .exp_y            (exp_y),
    .exp_life         (exp_life),
    .exp_active       (exp_active),
    .star_x           (star_x),
    .star_y           (star_y),
    .star_bright      (star_bright),
    .score            (score),
    .wave             (wave_num),
    .lives            (lives),
    .state            (state),
    .invincible_timer (invincible)
);

//———————————————————————————————————————————————————————————————————
// 渲染管线：将游戏状态转换为 VGA 像素颜色 (R/G/B 各4位)
//———————————————————————————————————————————————————————————————————
wire [3:0] vr, vg, vb;

render u_render (
    .clk              (CLK100MHZ),
    .tick             (tick),
    .h_count          (h_count),
    .v_count          (v_count),
    .active           (active),
    .state            (state),
    .lives            (lives),
    .invincible_timer (invincible),
    .player_x         (player_x),
    .player_y         (player_y),
    .enemy_x          (enemy_x),
    .enemy_y          (enemy_y),
    .enemy_type       (enemy_type),
    .enemy_active     (enemy_active),
    .bullet_x         (bullet_x),
    .bullet_y         (bullet_y),
    .bullet_active    (bullet_active),
    .exp_x            (exp_x),
    .exp_y            (exp_y),
    .exp_life         (exp_life),
    .exp_active       (exp_active),
    .star_x           (star_x),
    .star_y           (star_y),
    .star_bright      (star_bright),
    .score            (score),
    .wave             (wave_num),
    .bcd0             (bcd0),
    .bcd1             (bcd1),
    .bcd2             (bcd2),
    .bcd3             (bcd3),
    .vga_r            (vr),
    .vga_g            (vg),
    .vga_b            (vb)
);

//———————————————————————————————————————————————————————————————————
// VGA 输出消隐：在非显示区域（active=0）时输出黑色
//———————————————————————————————————————————————————————————————————
assign VGA_HS = vga_hs;
assign VGA_VS = vga_vs;
assign VGA_R  = active ? vr : 4'd0;
assign VGA_G  = active ? vg : 4'd0;
assign VGA_B  = active ? vb : 4'd0;

//———————————————————————————————————————————————————————————————————
// 7段数码管 —— BCD 码转换 + 扫描复用（约763Hz刷新率）
// 显示分数（0~9999），超过9999则钳位到9999
//———————————————————————————————————————————————————————————————————
wire [13:0] s_clamp;
assign s_clamp = (score > 14'd9999) ? 14'd9999 : score[13:0];

wire [3:0] bcd3, bcd2, bcd1, bcd0;
// double-dabble (shift-add-3) 替代昂贵的除法器
reg  [3:0] bcd3_r, bcd2_r, bcd1_r, bcd0_r;
integer bcd_i;
always @(*) begin
    bcd3_r = 4'd0; bcd2_r = 4'd0; bcd1_r = 4'd0; bcd0_r = 4'd0;
    for (bcd_i = 13; bcd_i >= 0; bcd_i = bcd_i - 1) begin
        if (bcd3_r >= 4'd5) bcd3_r = bcd3_r + 4'd3;
        if (bcd2_r >= 4'd5) bcd2_r = bcd2_r + 4'd3;
        if (bcd1_r >= 4'd5) bcd1_r = bcd1_r + 4'd3;
        if (bcd0_r >= 4'd5) bcd0_r = bcd0_r + 4'd3;
        bcd3_r = {bcd3_r[2:0], bcd2_r[3]};
        bcd2_r = {bcd2_r[2:0], bcd1_r[3]};
        bcd1_r = {bcd1_r[2:0], bcd0_r[3]};
        bcd0_r = {bcd0_r[2:0], s_clamp[bcd_i]};
    end
end
assign bcd3 = bcd3_r;
assign bcd2 = bcd2_r;
assign bcd1 = bcd1_r;
assign bcd0 = bcd0_r;

reg [16:0] mux_cnt;
always @(posedge CLK100MHZ) begin
    mux_cnt <= mux_cnt + 17'd1;
end
wire [1:0] digit_sel = mux_cnt[16:15];

reg [3:0] an_r;
always @(*) begin
    case (digit_sel)
        2'd0: an_r = 4'b1110;
        2'd1: an_r = 4'b1101;
        2'd2: an_r = 4'b1011;
        2'd3: an_r = 4'b0111;
    endcase
end
assign an = an_r;

wire [3:0] digit_val;
assign digit_val = (digit_sel == 2'd0) ? bcd0 :
                   (digit_sel == 2'd1) ? bcd1 :
                   (digit_sel == 2'd2) ? bcd2 : bcd3;

reg [6:0] seg_r;
always @(*) begin
    case (digit_val)
        4'd0: seg_r = 7'b1000000;  4'd1: seg_r = 7'b1111001;
        4'd2: seg_r = 7'b0100100;  4'd3: seg_r = 7'b0110000;
        4'd4: seg_r = 7'b0011001;  4'd5: seg_r = 7'b0010010;
        4'd6: seg_r = 7'b0000010;  4'd7: seg_r = 7'b1111000;
        4'd8: seg_r = 7'b0000000;  4'd9: seg_r = 7'b0010000;
        default: seg_r = 7'b1111111;
    endcase
end
assign seg = seg_r;

//———————————————————————————————————————————————————————————————————
// 状态指示灯 LED：显示当前游戏状态
//   led[0] = 标题画面 (ST_TITLE)
//   led[1] = 游戏中   (ST_PLAYING)
//   led[2] = 死亡动画 (ST_DYING)
//   led[3] = 游戏结束 (ST_GAMEOVER)
//———————————————————————————————————————————————————————————————————
assign led[0] = (state == 2'd0);
assign led[1] = (state == 2'd1);
assign led[2] = (state == 2'd2);
assign led[3] = (state == 2'd3);

endmodule
