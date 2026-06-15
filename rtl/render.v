//===================================================================
// render.v — STELLAR VANGUARD 像素渲染管线
//===================================================================
// 【功能】多层组合逻辑渲染。每层使用独立的 always @(*) 块，
// 以便 Vivado 并行综合各渲染层。
//
// 图层顺序（从后到前）:
//    1. 背景渐变色
//    2. 星星（32颗）
//    3. 爆炸特效（5个，基于曼哈顿距离的粒子）
//    4. 敌人（20个，按类型不同形状）
//    5. 子弹（5发，亮黄色）
//    6. 玩家飞机（16x16 精灵）
//    7. HUD 抬头显示（SCORE/WAVE/LIVES，在 y=400-479 区域）
//    8. 标题画面（文字 + 装饰线）
//    9. 游戏结束覆盖层
//    最终：优先级多路选择器 → 寄存后 VGA 输出
//===================================================================

module render (
    input  wire         clk,
    input  wire         tick,           // 25MHz enable
    input  wire  [9:0]  h_count,
    input  wire  [9:0]  v_count,
    input  wire         active,
    input  wire  [1:0]  state,
    input  wire  [1:0]  lives,
    input  wire  [7:0]  invincible_timer,  // for blink effect

    input  wire  [9:0]  player_x,
    input  wire  [9:0]  player_y,

    input  wire [199:0]  enemy_x,
    input  wire [179:0]  enemy_y,
    input  wire  [39:0]  enemy_type,
    input  wire  [19:0]  enemy_active,

    input  wire  [49:0]  bullet_x,
    input  wire  [44:0]  bullet_y,
    input  wire   [4:0]  bullet_active,

    input  wire  [49:0]  exp_x,
    input  wire  [44:0]  exp_y,
    input  wire  [24:0]  exp_life,
    input  wire   [4:0]  exp_active,

    input  wire [319:0]  star_x,
    input  wire [287:0]  star_y,
    input  wire  [63:0]  star_bright,

    input  wire [15:0]   score,
    input  wire  [7:0]   wave,
    input  wire  [3:0]   bcd0, bcd1, bcd2, bcd3,   // 十进制分数位（个/十/百/千）

    output reg   [3:0]   vga_r,
    output reg   [3:0]   vga_g,
    output reg   [3:0]   vga_b
);

//———————————————————————————————————————————————————————————————————
// 字体 ROM — 每层使用独立的 wire 避免多驱动错误（Vivado Synth 8-3352）
//———————————————————————————————————————————————————————————————————
reg  [5:0] fc_hud, fc_title, fc_over;
reg  [2:0] fr_hud, fr_title, fr_over;
wire [5:0] font_char;
wire [2:0] font_row;
wire [7:0] font_pixels;

// 根据当前游戏状态选择字体输入（同一时间只有一个图层渲染文字）
assign font_char = (state == 2'd0) ? fc_title :
                   (state == 2'd3) ? fc_over  : fc_hud;
assign font_row  = (state == 2'd0) ? fr_title :
                   (state == 2'd3) ? fr_over  : fr_hud;

font_rom u_font (.char_idx(font_char), .row(font_row), .pixels(font_pixels));

//———————————————————————————————————————————————————————————————————
// 局部常量和变量定义
//———————————————————————————————————————————————————————————————————
localparam MAX_ENEMIES    = 6'd12;
localparam MAX_BULLETS    = 3'd5;
localparam MAX_EXPLOSIONS = 3'd5;
localparam NUM_STARS      = 6'd16;

wire [9:0] px, py;
assign px = h_count;
assign py = v_count;

// 各图层颜色输出 (R:G:B 各4位 = 12位)
reg [11:0] l_bg, l_star, l_exp, l_enemy, l_bullet, l_player;
reg [11:0] l_hud, l_title, l_over;
// 各图层使能标志
reg        en_bg, en_star, en_exp, en_enemy, en_bullet, en_player;
reg        en_hud, en_title, en_over;

// always 块中的临时变量（模块级声明以避免 Vivado Synth 8-1873）
reg  [9:0] tmp_dx, tmp_dy, tmp_dist;
reg  [9:0] tmp_ex, tmp_ey, tmp_lx, tmp_ly;
reg  [3:0] tmp_plx, tmp_ply;
reg  [7:0] tmp_cp;
reg  [2:0] tmp_ix, tmp_iy;
reg  [4:0] tmp_val;

//———————————————————————————————————————————————————————————————————
// 图层1: 背景渐变 — 蓝色从深到浅，亮度随 Y 坐标变化
//———————————————————————————————————————————————————————————————————
always @(*) begin
    en_bg = 1'b1;
    l_bg  = {4'd0, 4'd0, py[8:5]};
end

//———————————————————————————————————————————————————————————————————
// 图层2: 星星 — 像素精确匹配，亮度分4级
//———————————————————————————————————————————————————————————————————
integer s2;
always @(*) begin
    l_star = 12'd0; en_star = 1'b0;
    for (s2 = 0; s2 < NUM_STARS; s2 = s2 + 1) begin
        if (px == star_x[s2*10 +: 10] && py == star_y[s2*9 +: 9]) begin
            en_star = 1'b1;
            case (star_bright[s2*2 +: 2])
                2'd0: l_star = {4'd1,  4'd1,  4'd1};
                2'd1: l_star = {4'd4,  4'd4,  4'd4};
                2'd2: l_star = {4'd8,  4'd8,  4'd8};
                2'd3: l_star = {4'd15, 4'd15, 4'd15};
            endcase
        end
    end
end

//———————————————————————————————————————————————————————————————————
// 图层3: 爆炸特效 — 曼哈顿距离粒子，颜色随剩余生命值变化
// 生命值高时白色 → 黄色 → 橙色 → 红色
//———————————————————————————————————————————————————————————————————
integer x3;
always @(*) begin
    l_exp = 12'd0; en_exp = 1'b0;
    for (x3 = 0; x3 < MAX_EXPLOSIONS; x3 = x3 + 1) begin
        if (exp_active[x3]) begin
            tmp_dx = (px > exp_x[x3*10 +: 10]) ? (px - exp_x[x3*10 +: 10]) : (exp_x[x3*10 +: 10] - px);
            tmp_dy = (py > exp_y[x3*9 +: 9])   ? (py - exp_y[x3*9 +: 9])   : (exp_y[x3*9 +: 9] - py);
            tmp_dist = tmp_dx + tmp_dy;
            tmp_val  = exp_life[x3*5 +: 5];
            if (tmp_dist <= {6'd0, tmp_val}) begin
                en_exp = 1'b1;
                case (tmp_val[4:3])
                    2'd3: l_exp = {4'd15, 4'd15, 4'd15};
                    2'd2: l_exp = {4'd15, 4'd15, 4'd0};
                    2'd1: l_exp = {4'd15, 4'd8,  4'd0};
                    2'd0: l_exp = {4'd15, 4'd0,  4'd0};
                endcase
            end
        end
    end
end

//———————————————————————————————————————————————————————————————————
// 图层4: 敌人渲染 — 每种类型有不同形状和颜色
//   类型0: 菱形（红色）  类型1: 十字形（紫色）  类型2: 菱形（橙色）
//———————————————————————————————————————————————————————————————————
integer e4;
always @(*) begin
    l_enemy = 12'd0; en_enemy = 1'b0;
    for (e4 = 0; e4 < MAX_ENEMIES; e4 = e4 + 1) begin
        if (enemy_active[e4]) begin
            tmp_ex = enemy_x[e4*10 +: 10];
            tmp_ey = enemy_y[e4*9 +: 9];
            tmp_lx = px - tmp_ex;
            tmp_ly = py - tmp_ey;
            if (tmp_lx < 16 && tmp_ly < 16) begin
                case (enemy_type[e4*2 +: 2])
                    2'd0: if (tmp_lx+tmp_ly >= 8 && tmp_lx+tmp_ly < 24 && tmp_ly >= tmp_lx-8 && tmp_ly < tmp_lx+8) begin
                        en_enemy = 1'b1; l_enemy = {4'd15, 4'd0, 4'd0}; end
                    2'd1: if ((tmp_lx>=5&&tmp_lx<11)||(tmp_ly>=5&&tmp_ly<11)) begin
                        en_enemy = 1'b1; l_enemy = {4'd15, 4'd0, 4'd15}; end
                    2'd2: if (tmp_lx+tmp_ly >= 4 && tmp_lx+tmp_ly < 20 && tmp_ly >= tmp_lx && tmp_ly < tmp_lx+16) begin
                        en_enemy = 1'b1; l_enemy = {4'd15, 4'd8, 4'd0}; end
                endcase
            end
        end
    end
end

//———————————————————————————————————————————————————————————————————
// 图层5: 子弹 — 3x8 亮黄色矩形，中心高亮为白色
//———————————————————————————————————————————————————————————————————
integer b5;
always @(*) begin
    l_bullet = 12'd0; en_bullet = 1'b0;
    for (b5 = 0; b5 < MAX_BULLETS; b5 = b5 + 1) begin
        if (bullet_active[b5]) begin
            if (px >= bullet_x[b5*10 +: 10] && px < bullet_x[b5*10 +: 10] + 3 &&
                py >= bullet_y[b5*9 +: 9]   && py < bullet_y[b5*9 +: 9] + 8) begin
                en_bullet = 1'b1;
                l_bullet = {4'd15, 4'd15, 4'd0};
                if (px == bullet_x[b5*10 +: 10] + 1)
                    l_bullet = {4'd15, 4'd15, 4'd15};
            end
        end
    end
end

//———————————————————————————————————————————————————————————————————
// 图层6: 玩家飞机精灵（16x16 像素箭头造型）
// 无敌闪烁效果：invincible_timer[2] 为高时交替显示白色
//———————————————————————————————————————————————————————————————————
always @(*) begin
    l_player = 12'd0; en_player = 1'b0;
    if (px >= player_x && px < player_x + 16 && py >= player_y && py < player_y + 16) begin
        tmp_plx = px[3:0] - player_x[3:0];
        tmp_ply = py[3:0] - player_y[3:0];
        case (tmp_ply)
            4'd0,4'd1:   if (tmp_plx >= 7 && tmp_plx <= 9)  en_player = 1'b1;
            4'd2,4'd3:   if (tmp_plx >= 6 && tmp_plx <= 10) en_player = 1'b1;
            4'd4,4'd5:   if (tmp_plx >= 3 && tmp_plx <= 13) en_player = 1'b1;
            4'd6,4'd7:   if (tmp_plx >= 4 && tmp_plx <= 12) en_player = 1'b1;
            4'd8,4'd9:   if (tmp_plx >= 5 && tmp_plx <= 11) en_player = 1'b1;
            4'd10,4'd11: if (tmp_plx >= 6 && tmp_plx <= 10) en_player = 1'b1;
            4'd12:       if (tmp_plx >= 4 && tmp_plx <= 12) en_player = 1'b1;
            4'd13,4'd14: if ((tmp_plx>=4&&tmp_plx<=5)||(tmp_plx>=11&&tmp_plx<=12)) en_player = 1'b1;
            4'd15:       if ((tmp_plx>=4&&tmp_plx<=5)||(tmp_plx>=11&&tmp_plx<=12)) en_player = 1'b1;
            default: en_player = 1'b0;
        endcase
        if (en_player) begin
            l_player = invincible_timer[2] ? {4'd15,4'd15,4'd15} : {4'd0,4'd15,4'd15};
        end
    end
end

//———————————————————————————————————————————————————————————————————
// 图层7: HUD 抬头显示 — 屏幕底部 (y=400-479)
// 显示: SCORE 分数、WAVE 波次、LIVES 生命图标（小飞机造型）
// 使用 font_rom 渲染字符文本
//———————————————————————————————————————————————————————————————————
wire in_hud = (py >= 10'd400);
always @(*) begin
    l_hud = 12'd0; en_hud = 1'b0; fc_hud = 6'd36; fr_hud = 3'd0;
    if (in_hud && active) begin
        en_hud = 1'b1; l_hud = {4'd0, 4'd0, 4'd4};

        // "SCORE:" at (8,408), char_width=8
        if (py >= 408 && py < 416) begin
            tmp_cp = px[2:0];
            case ((px - 10'd8) >> 3)
                3'd0: fc_hud = 6'd28; // S
                3'd1: fc_hud = 6'd12; // C
                3'd2: fc_hud = 6'd24; // O
                3'd3: fc_hud = 6'd27; // R
                3'd4: fc_hud = 6'd14; // E
                3'd5: fc_hud = 6'd39; // :
                default: fc_hud = 6'd36;
            endcase
            fr_hud = py[2:0];
            if (font_pixels[7 - tmp_cp]) l_hud = {4'd15,4'd15,4'd15};
        end

        // Score digits at (64,408)
        if (py >= 408 && py < 416 && px >= 64 && px < 96) begin
            case ((px - 64) >> 3)
                3'd0: fc_hud = {2'd0, bcd3};
                3'd1: fc_hud = {2'd0, bcd2};
                3'd2: fc_hud = {2'd0, bcd1};
                3'd3: fc_hud = {2'd0, bcd0};
                default: fc_hud = 6'd0;
            endcase
            fr_hud = py[2:0];
            if (font_pixels[7 - ((px-64)&7)]) l_hud = {4'd15,4'd15,4'd0};
        end

        // "WAVE:" at (8,424)
        if (py >= 424 && py < 432) begin
            case ((px - 10'd8) >> 3)
                3'd0: fc_hud = 6'd32; // W
                3'd1: fc_hud = 6'd10; // A
                3'd2: fc_hud = 6'd31; // V
                3'd3: fc_hud = 6'd14; // E
                3'd4: fc_hud = 6'd39; // :
                default: fc_hud = 6'd36;
            endcase
            fr_hud = py[2:0];
            if (font_pixels[7 - px[2:0]]) l_hud = {4'd15,4'd15,4'd15};
        end

        // Wave number at (56,424) — 2位十六进制显示 (高4位+低4位)
        if (py >= 424 && py < 432 && px >= 56 && px < 72) begin
            case ((px - 56) >> 3)
                4'd0: fc_hud = {2'd0, wave[7:4]};  // 高4位
                4'd1: fc_hud = {2'd0, wave[3:0]};  // 低4位
                default: fc_hud = 6'd0;
            endcase
            fr_hud = py[2:0];
            if (font_pixels[7 - ((px-56)&7)]) l_hud = {4'd15,4'd15,4'd0};
        end

        // "LIVES:" at (8,440)
        if (py >= 440 && py < 448) begin
            case ((px - 10'd8) >> 3)
                3'd0: fc_hud = 6'd21; // L
                3'd1: fc_hud = 6'd18; // I
                3'd2: fc_hud = 6'd31; // V
                3'd3: fc_hud = 6'd14; // E
                3'd4: fc_hud = 6'd28; // S
                3'd5: fc_hud = 6'd39; // :
                default: fc_hud = 6'd36;
            endcase
            fr_hud = py[2:0];
            if (font_pixels[7 - px[2:0]]) l_hud = {4'd15,4'd15,4'd15};
        end

        // Life icons at (64,440) — small planes
        if (py >= 440 && py < 448 && px >= 64) begin
            if ((lives >= 1 && px >= 64 && px < 72) ||
                (lives >= 2 && px >= 80 && px < 88) ||
                (lives >= 3 && px >= 96 && px < 104)) begin
                tmp_ix = px[2:0]; tmp_iy = py[2:0] - 3'd0;
                if ((tmp_iy < 3 && tmp_ix >= 3 && tmp_ix <= 5) ||
                    (tmp_iy >= 3 && tmp_ix >= 2 && tmp_ix <= 6) ||
                    (tmp_iy >= 6 && tmp_ix >= 3 && tmp_ix <= 5))
                    l_hud = {4'd0,4'd15,4'd0};
            end
        end
    end
end

//———————————————————————————————————————————————————————————————————
// 图层8: 标题画面 — 显示游戏名称"STELLAR VANGUARD"、
// "PRESS START"提示、操作说明和装饰分割线
//———————————————————————————————————————————————————————————————————
always @(*) begin
    l_title = 12'd0; en_title = 1'b0; fc_title = 6'd36; fr_title = 3'd0;
    if (state == 2'd0 && active) begin
        en_title = 1'b1; l_title = {4'd0, 4'd0, 4'd2};

        // "STELLAR VANGUARD" at y=160, x=128 (8行高，只渲染一次)
        if (py >= 160 && py < 168 && px >= 128 && px < 256) begin
            case ((px - 128) >> 3)
                4'd0: fc_title=6'd28; 4'd1: fc_title=6'd29; 4'd2: fc_title=6'd14;
                4'd3: fc_title=6'd21; 4'd4: fc_title=6'd21; 4'd5: fc_title=6'd10;
                4'd6: fc_title=6'd27; 4'd7: fc_title=6'd36; 4'd8: fc_title=6'd31;
                4'd9: fc_title=6'd10; 4'd10:fc_title=6'd23; 4'd11:fc_title=6'd16;
                4'd12:fc_title=6'd30; 4'd13:fc_title=6'd10; 4'd14:fc_title=6'd27; 4'd15:fc_title=6'd13;
            endcase
            fr_title = py[2:0];
            if (font_pixels[7 - ((px-128)&7)]) l_title = {4'd15,4'd15,4'd15};
        end

        // "PRESS START" at y=240, x=240
        if (py >= 240 && py < 248 && px >= 240 && px < 320) begin
            case ((px - 240) >> 3)
                4'd0:fc_title=6'd25; 4'd1:fc_title=6'd27; 4'd2:fc_title=6'd14;
                4'd3:fc_title=6'd28; 4'd4:fc_title=6'd28; 4'd5:fc_title=6'd36;
                4'd6:fc_title=6'd28; 4'd7:fc_title=6'd29; 4'd8:fc_title=6'd10; 4'd9:fc_title=6'd27;
            endcase
            fr_title = py[2:0];
            if (font_pixels[7 - ((px-240)&7)]) l_title = {4'd0,4'd15,4'd0};
        end

        // Controls hint at y=300
        if (py >= 300 && py < 308 && px >= 104 && px < 536) begin
            case ((px - 104) >> 3)
                5'd0:fc_title=6'd21; 5'd1:fc_title=6'd14; 5'd2:fc_title=6'd15; 5'd3:fc_title=6'd29;
                5'd4:fc_title=6'd36; 5'd5:fc_title=6'd41; 5'd6:fc_title=6'd36;
                5'd7:fc_title=6'd27; 5'd8:fc_title=6'd18; 5'd9:fc_title=6'd16; 5'd10:fc_title=6'd17; 5'd11:fc_title=6'd29;
                5'd12:fc_title=6'd36; 5'd13:fc_title=6'd36;
                5'd14:fc_title=6'd30; 5'd15:fc_title=6'd25; 5'd16:fc_title=6'd36;
                5'd17:fc_title=6'd36; 5'd18:fc_title=6'd29; 5'd19:fc_title=6'd24; 5'd20:fc_title=6'd36;
                5'd21:fc_title=6'd15; 5'd22:fc_title=6'd18; 5'd23:fc_title=6'd27; 5'd24:fc_title=6'd14;
                default: fc_title=6'd36;
            endcase
            fr_title = py[2:0];
            if (font_pixels[7 - ((px-104)&7)]) l_title = {4'd10,4'd10,4'd10};
        end

        // Decorative lines
        if ((py == 140 || py == 350) && px >= 100 && px < 540)
            l_title = {4'd8,4'd8,4'd8};
    end
end

//———————————————————————————————————————————————————————————————————
// 图层9: 游戏结束画面 — 显示"GAME OVER"、"FINAL SCORE"和"PRESS START"
// 红色背景覆盖层
//———————————————————————————————————————————————————————————————————
always @(*) begin
    l_over = 12'd0; en_over = 1'b0; fc_over = 6'd36; fr_over = 3'd0;
    if (state == 2'd3 && active) begin
        en_over = 1'b1; l_over = {4'd2, 4'd0, 4'd0};

        // "GAME OVER" at y=200 (8行高，避免重复)
        if (py >= 200 && py < 208 && px >= 220 && px < 420) begin
            case ((px - 220) >> 3)
                4'd0:fc_over=6'd16; 4'd1:fc_over=6'd10; 4'd2:fc_over=6'd22;
                4'd3:fc_over=6'd14; 4'd4:fc_over=6'd36; 4'd5:fc_over=6'd24;
                4'd6:fc_over=6'd31; 4'd7:fc_over=6'd14; 4'd8:fc_over=6'd27;
                default:fc_over=6'd36;
            endcase
            fr_over = py[2:0];
            if (font_pixels[7 - ((px-220)&7)]) l_over = {4'd15,4'd0,4'd0};
        end

        // "FINAL SCORE:" at y=270
        if (py >= 270 && py < 278 && px >= 220 && px < 420) begin
            case ((px - 220) >> 3)
                4'd0:fc_over=6'd15; 4'd1:fc_over=6'd18; 4'd2:fc_over=6'd23;
                4'd3:fc_over=6'd10; 4'd4:fc_over=6'd21; 4'd5:fc_over=6'd36;
                4'd6:fc_over=6'd28; 4'd7:fc_over=6'd12; 4'd8:fc_over=6'd24;
                4'd9:fc_over=6'd27; 4'd10:fc_over=6'd14; default:fc_over=6'd36;
            endcase
            fr_over = py[2:0];
            if (font_pixels[7 - ((px-220)&7)]) l_over = {4'd15,4'd15,4'd15};
        end

        // Score value at y=286
        if (py >= 286 && py < 294 && px >= 300 && px < 340) begin
            case ((px - 300) >> 3)
                4'd0:fc_over={2'd0,bcd3}; 4'd1:fc_over={2'd0,bcd2};
                4'd2:fc_over={2'd0,bcd1};  4'd3:fc_over={2'd0,bcd0};
                default:fc_over=6'd0;
            endcase
            fr_over = py[2:0];
            if (font_pixels[7 - ((px-300)&7)]) l_over = {4'd15,4'd15,4'd0};
        end

        // "PRESS START" at y=340
        if (py >= 340 && py < 348 && px >= 160 && px < 480) begin
            case ((px - 160) >> 3)
                4'd0:fc_over=6'd25; 4'd1:fc_over=6'd27; 4'd2:fc_over=6'd14;
                4'd3:fc_over=6'd28; 4'd4:fc_over=6'd28; 4'd5:fc_over=6'd36;
                4'd6:fc_over=6'd28; 4'd7:fc_over=6'd29; 4'd8:fc_over=6'd10; 4'd9:fc_over=6'd27;
                default:fc_over=6'd36;
            endcase
            fr_over = py[2:0];
            if (font_pixels[7 - ((px-160)&7)]) l_over = {4'd10,4'd10,4'd10};
        end
    end
end

//———————————————————————————————————————————————————————————————————
// 最终输出：优先级多路选择器 + 输出寄存器
// 优先级从高到低：标题 → 游戏结束 → HUD → 玩家 → 子弹 → 敌人 → 爆炸 → 星星 → 背景
// 非显示区域输出黑色
//———————————————————————————————————————————————————————————————————
always @(posedge clk) begin
    if (tick) begin
        if (!active) begin
            {vga_r, vga_g, vga_b} <= 12'd0;
        end else if (en_title && state == 2'd0) begin
            {vga_r, vga_g, vga_b} <= l_title;
        end else if (en_over && state == 2'd3) begin
            {vga_r, vga_g, vga_b} <= l_over;
        end else if (en_hud) begin
            {vga_r, vga_g, vga_b} <= l_hud;
        end else if (en_player) begin
            {vga_r, vga_g, vga_b} <= l_player;
        end else if (en_bullet) begin
            {vga_r, vga_g, vga_b} <= l_bullet;
        end else if (en_enemy) begin
            {vga_r, vga_g, vga_b} <= l_enemy;
        end else if (en_exp) begin
            {vga_r, vga_g, vga_b} <= l_exp;
        end else if (en_star) begin
            {vga_r, vga_g, vga_b} <= l_star;
        end else begin
            {vga_r, vga_g, vga_b} <= l_bg;
        end
    end
end

endmodule
