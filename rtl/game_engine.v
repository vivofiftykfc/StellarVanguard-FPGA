//===================================================================
// game_engine.v — STELLAR VANGUARD 游戏逻辑核心
//===================================================================
// 【功能】管理所有游戏状态：有限状态机(FSM)、玩家控制、敌人生成与移动、
// 子弹发射、爆炸特效、星空背景滚动、碰撞检测和计分。
//
// 关键设计规则（Vivado 可综合）:
//   - 所有端口使用扁平打包向量（不支持 unpacked array）
//   - for 循环使用 found 标志退出，绝不修改循环变量模拟 break
//   - localparam 位宽已验证（N'dV 要求 V < 2^N）
//   - 每个 reg 都有复位初值
//===================================================================

module game_engine (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         new_frame,      // single-cycle pulse @ 60Hz

    input  wire         btn_left,
    input  wire         btn_right,
    input  wire         btn_up,
    input  wire         btn_down,
    input  wire         btn_fire,
    input  wire         btn_start,

    output wire  [9:0]  player_x,
    output wire  [9:0]  player_y,

    //—— 敌人输出（20个槽位，FLAT PACKED 打包）——
    output wire [199:0]  enemy_x,       // 20个敌人 × 10位X坐标
    output wire [179:0]  enemy_y,       // 20个敌人 ×  9位Y坐标
    output wire  [39:0]  enemy_type,    // 20个敌人 ×  2位类型
    output wire  [19:0]  enemy_active,  // 20个敌人 ×  1位激活标志

    //—— 子弹输出（5个槽位）——
    output wire  [49:0]  bullet_x,      // 5发子弹 × 10位X坐标
    output wire  [44:0]  bullet_y,      // 5发子弹 ×  9位Y坐标
    output wire   [4:0]  bullet_active, // 5发子弹 ×  1位激活标志

    //—— 爆炸特效输出（5个槽位）——
    output wire  [49:0]  exp_x,         // 5个爆炸 × 10位X坐标
    output wire  [44:0]  exp_y,         // 5个爆炸 ×  9位Y坐标
    output wire  [24:0]  exp_life,      // 5个爆炸 ×  5位生命值
    output wire   [4:0]  exp_active,    // 5个爆炸 ×  1位激活标志

    //—— 星空输出（32颗星星）——
    output wire [319:0]  star_x,        // 32颗星 × 10位X坐标
    output wire [287:0]  star_y,        // 32颗星 ×  9位Y坐标
    output wire  [63:0]  star_bright,   // 32颗星 ×  2位亮度

    //—— HUD（抬头显示）——
    output wire [15:0]   score,
    output wire  [7:0]   wave,
    output wire  [1:0]   lives,
    output wire  [1:0]   state,          // 游戏状态：TITLE/PLAYING/DYING/GAMEOVER
    output wire  [7:0]   invincible_timer // 无敌计时器（渲染闪烁用）
);

//———————————————————————————————————————————————————————————————————
// 局部参数 — 位宽已严格验证（Vivado 综合要求）
//———————————————————————————————————————————————————————————————————
localparam MAX_ENEMIES    = 6'd12;     // 20个敌人需要6位（不是5位！）
localparam MAX_BULLETS    = 3'd5;      // 5发子弹需要3位
localparam MAX_EXPLOSIONS = 3'd5;      // 5个爆炸特效需要3位
localparam NUM_STARS      = 6'd16;     // 32颗星星需要6位（不是5位！）

localparam PLAYER_SPEED    = 9'd5;      // 玩家移动速度（像素/帧）
localparam PLAYER_W        = 9'd16;     // 玩家宽度
localparam PLAYER_H        = 9'd16;     // 玩家高度
localparam SHOOT_COOLDOWN  = 4'd8;      // 射击冷却时间（帧数）
localparam INVINCIBLE_TIME = 8'd120;    // 无敌时间（2秒 @ 60fps）
localparam INIT_LIVES      = 2'd3;      // 初始生命数

localparam ENEMY_W         = 9'd16;     // 敌人宽度
localparam ENEMY_H         = 9'd16;     // 敌人高度
localparam WAVE_INTERVAL   = 8'd120;    // 波次间隔（帧数）
localparam INIT_WAVE_SIZE  = 4'd3;      // 初始每波敌人数
localparam MAX_WAVE_SIZE   = 4'd8;      // 最大每波敌人数

localparam BULLET_SPEED    = 8'd8;      // 子弹速度（像素/帧）
localparam BULLET_W        = 4'd3;      // 子弹宽度
localparam BULLET_H        = 8'd8;      // 子弹高度

localparam EXP_MAX_LIFE    = 5'd16;     // 爆炸特效最大生命值（16帧 ≈ 0.27秒）

localparam SCREEN_W        = 10'd640;   // 屏幕宽度
localparam PLAY_AREA_H     = 10'd400;   // 游戏区域高度（顶部400行）
localparam PLAYER_Y_FIXED  = 10'd350;   // 玩家固定Y坐标（底部区域）

// 游戏状态编码
localparam ST_TITLE    = 2'd0;  // 标题画面
localparam ST_PLAYING  = 2'd1;  // 游戏中
localparam ST_DYING    = 2'd2;  // 死亡动画
localparam ST_GAMEOVER = 2'd3;  // 游戏结束

//———————————————————————————————————————————————————————————————————
// 内部寄存器定义
//———————————————————————————————————————————————————————————————————
reg  [1:0] state_r;              // 游戏状态寄存器
reg  [9:0] player_x_r;           // 玩家X坐标
reg  [9:0] player_y_r;           // 玩家Y坐标（可上下移动）
reg  [1:0] lives_r;              // 剩余生命数
reg  [7:0] invincible_timer_r;   // 无敌计时器
reg  [3:0] shoot_cooldown_r;     // 射击冷却计数器
reg [15:0] score_r;              // 得分（最大65535）
reg  [7:0] wave_r;               // 当前波次数
reg  [7:0] wave_timer_r;         // 波次生成计时器
reg  [3:0] wave_size_r;          // 当前波次的敌人数
reg  [3:0] wave_spawned_r;       // 当前波次已生成的敌人数
reg  [7:0] frame_counter_r;      // 帧计数器
reg [15:0] lfsr_r;               // 伪随机数生成器（LFSR）状态

// 扁平打包的对象寄存器（每个对象的数据按位连续排列）
reg [199:0] enemy_x_r,      enemy_base_x_r;
reg [179:0] enemy_y_r;
reg  [39:0] enemy_type_r;
reg  [19:0] enemy_active_r;
reg  [49:0] bullet_x_r;
reg  [44:0] bullet_y_r;
reg   [4:0] bullet_active_r;
reg  [49:0] exp_x_r;
reg  [44:0] exp_y_r;
reg  [24:0] exp_life_r;
reg   [4:0] exp_active_r;
reg [319:0] star_x_r;
reg [287:0] star_y_r;
reg  [63:0] star_bright_r;

//———————————————————————————————————————————————————————————————————
// 输出连线：将内部寄存器连接到模块输出端口
//———————————————————————————————————————————————————————————————————
assign player_x      = player_x_r;
assign player_y      = player_y_r;
assign enemy_x       = enemy_x_r;
assign enemy_y       = enemy_y_r;
assign enemy_type    = enemy_type_r;
assign enemy_active  = enemy_active_r;
assign bullet_x      = bullet_x_r;
assign bullet_y      = bullet_y_r;
assign bullet_active = bullet_active_r;
assign exp_x         = exp_x_r;
assign exp_y         = exp_y_r;
assign exp_life      = exp_life_r;
assign exp_active    = exp_active_r;
assign star_x        = star_x_r;
assign star_y        = star_y_r;
assign star_bright   = star_bright_r;
assign score         = score_r;
assign wave          = wave_r;
assign lives         = lives_r;
assign state            = state_r;
assign invincible_timer = invincible_timer_r;

//———————————————————————————————————————————————————————————————————
// LFSR 伪随机数发生器: 多项式 x^16 + x^14 + x^13 + x^11 + 1
// 用于生成敌人位置、类型等随机参数
//———————————————————————————————————————————————————————————————————
wire lfsr_fb;
assign lfsr_fb = lfsr_r[15] ^ lfsr_r[14] ^ lfsr_r[13] ^ lfsr_r[11];
wire [4:0] zigzag_phase_base;
assign zigzag_phase_base = frame_counter_r[4:0];  // 锯齿波相位基准

//———————————————————————————————————————————————————————————————————
// 主状态机 — 每个新帧(new_frame)触发一次更新
//———————————————————————————————————————————————————————————————————
integer ei, bi, xi, si;
reg        found_b, found_e, found_x, found_px;
reg  [5:0] zigzag_phase;
reg  [4:0] zigzag_tri;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state_r          <= ST_TITLE;
        player_x_r       <= 10'd312;
        player_y_r       <= PLAYER_Y_FIXED;
        lives_r          <= INIT_LIVES;
        invincible_timer_r <= 8'd0;
        shoot_cooldown_r <= 4'd0;
        score_r          <= 16'd0;
        wave_r           <= 8'd0;
        wave_timer_r     <= 8'd0;
        wave_size_r      <= INIT_WAVE_SIZE;
        wave_spawned_r   <= 4'd0;
        frame_counter_r  <= 8'd0;
        lfsr_r           <= 16'hACE1;

        for (ei = 0; ei < MAX_ENEMIES; ei = ei + 1) begin
            enemy_x_r[ei*10 +: 10]      <= 10'd0;
            enemy_base_x_r[ei*10 +: 10] <= 10'd0;
            enemy_y_r[ei*9 +: 9]        <= 9'd0;
            enemy_type_r[ei*2 +: 2]     <= 2'd0;
            enemy_active_r[ei]          <= 1'b0;
        end
        for (bi = 0; bi < MAX_BULLETS; bi = bi + 1) begin
            bullet_x_r[bi*10 +: 10] <= 10'd0;
            bullet_y_r[bi*9 +: 9]   <= 9'd0;
            bullet_active_r[bi]     <= 1'b0;
        end
        for (xi = 0; xi < MAX_EXPLOSIONS; xi = xi + 1) begin
            exp_x_r[xi*10 +: 10] <= 10'd0;
            exp_y_r[xi*9 +: 9]   <= 9'd0;
            exp_life_r[xi*5 +: 5] <= 5'd0;
            exp_active_r[xi]     <= 1'b0;
        end
        // Init stars
        for (si = 0; si < NUM_STARS; si = si + 1) begin
            star_x_r[si*10 +: 10]   <= {lfsr_r[9:0]};
            star_y_r[si*9 +: 9]     <= {lfsr_r[8:0]};
            star_bright_r[si*2 +: 2] <= lfsr_r[1:0];
            lfsr_r <= {lfsr_r[14:0], lfsr_fb};
        end

    end else if (new_frame) begin
        // 每帧推进 4 步 LFSR - 破开相邻帧的相关性，避免敌人扎堆
        lfsr_r <= {lfsr_r[11:0],
                   lfsr_r[12] ^ lfsr_r[11] ^ lfsr_r[10] ^ lfsr_r[8],
                   lfsr_r[13] ^ lfsr_r[12] ^ lfsr_r[11] ^ lfsr_r[9],
                   lfsr_r[14] ^ lfsr_r[13] ^ lfsr_r[12] ^ lfsr_r[10],
                   lfsr_r[15] ^ lfsr_r[14] ^ lfsr_r[13] ^ lfsr_r[11]};
        frame_counter_r <= frame_counter_r + 8'd1;
        if (shoot_cooldown_r > 0)   shoot_cooldown_r <= shoot_cooldown_r - 4'd1;
        if (invincible_timer_r > 0) invincible_timer_r <= invincible_timer_r - 8'd1;

        case (state_r)
            //———— 标题画面 (ST_TITLE) ———————————————————————————
            // 等待按开始键进入游戏，初始化所有游戏参数
            ST_TITLE: begin
                if (btn_start) begin
                    state_r    <= ST_PLAYING;
                    player_x_r <= 10'd312;
                    player_y_r <= PLAYER_Y_FIXED;
                    lives_r    <= INIT_LIVES;
                    score_r    <= 16'd0;
                    wave_r     <= 8'd1;
                    wave_timer_r   <= 8'd0;
                    wave_size_r    <= INIT_WAVE_SIZE;
                    wave_spawned_r <= 4'd0;
                    invincible_timer_r <= 8'd0;
                    shoot_cooldown_r   <= 4'd0;
                    for (ei = 0; ei < MAX_ENEMIES; ei = ei + 1)
                        enemy_active_r[ei] <= 1'b0;
                    for (bi = 0; bi < MAX_BULLETS; bi = bi + 1)
                        bullet_active_r[bi] <= 1'b0;
                    for (xi = 0; xi < MAX_EXPLOSIONS; xi = xi + 1)
                        exp_active_r[xi] <= 1'b0;
                end
            end

            //———— 游戏中 (ST_PLAYING) ——————————————————————————————
            // 处理：玩家移动、射击、子弹更新、敌人AI、碰撞检测、计分
            ST_PLAYING: begin
                //--- 玩家移动（边界检测，支持同时斜向移动） ---
                if ((btn_left || btn_up) && player_x_r > PLAYER_SPEED)
                    player_x_r <= player_x_r - PLAYER_SPEED;
                else if (btn_right && player_x_r < SCREEN_W - PLAYER_W - PLAYER_SPEED)
                    player_x_r <= player_x_r + PLAYER_SPEED;
                if (btn_up   && player_y_r > PLAYER_SPEED)
                    player_y_r <= player_y_r - PLAYER_SPEED;
                else if (btn_down && player_y_r < PLAY_AREA_H - PLAYER_H - PLAYER_SPEED)
                    player_y_r <= player_y_r + PLAYER_SPEED;

                //--- 射击逻辑：查找空闲子弹槽位并发射 ---
                if (btn_fire && shoot_cooldown_r == 0) begin
                    shoot_cooldown_r <= SHOOT_COOLDOWN;
                    found_b = 1'b0;
                    for (bi = 0; bi < MAX_BULLETS; bi = bi + 1) begin
                        if (!bullet_active_r[bi] && !found_b) begin
                            bullet_x_r[bi*10 +: 10] <= player_x_r + 9'd6;
                            bullet_y_r[bi*9 +: 9]   <= player_y_r;
                            bullet_active_r[bi]     <= 1'b1;
                            found_b = 1'b1;
                        end
                    end
                end

                //--- 子弹更新：每帧向上移动，超出屏幕则销毁 ---
                for (bi = 0; bi < MAX_BULLETS; bi = bi + 1) begin
                    if (bullet_active_r[bi]) begin
                        if (bullet_y_r[bi*9 +: 9] >= BULLET_SPEED)
                            bullet_y_r[bi*9 +: 9] <= bullet_y_r[bi*9 +: 9] - BULLET_SPEED;
                        else
                            bullet_active_r[bi] <= 1'b0;
                    end
                end

                //--- 爆炸特效更新：每帧减少生命值，归零后消失 ---
                for (xi = 0; xi < MAX_EXPLOSIONS; xi = xi + 1) begin
                    if (exp_active_r[xi]) begin
                        if (exp_life_r[xi*5 +: 5] > 0)
                            exp_life_r[xi*5 +: 5] <= exp_life_r[xi*5 +: 5] - 5'd1;
                        else
                            exp_active_r[xi] <= 1'b0;
                    end
                end

                //--- 敌人更新：移动 + 锯齿波晃动 + 超出区域销毁 ---
                for (ei = 0; ei < MAX_ENEMIES; ei = ei + 1) begin
                    if (enemy_active_r[ei]) begin
                        // 敌人下落速度依类型而异：基础型=2，锯齿型=1，快速型=3
                        enemy_y_r[ei*9 +: 9] <= enemy_y_r[ei*9 +: 9] +
                            ((enemy_type_r[ei*2 +: 2] == 2'd2) ? 9'd3 :
                             (enemy_type_r[ei*2 +: 2] == 2'd1) ? 9'd1 : 9'd2);

                        // 锯齿型敌人：三角波 X 方向摆动
                        if (enemy_type_r[ei*2 +: 2] == 2'd1) begin
                            zigzag_phase = zigzag_phase_base + (ei << 2);
                            zigzag_tri   = (zigzag_phase[5] == 0) ? zigzag_phase[4:0] : (5'd31 - zigzag_phase[4:0]);
                            enemy_x_r[ei*10 +: 10] <= enemy_base_x_r[ei*10 +: 10]
                                + {5'd0, zigzag_tri} - 10'd16;
                        end

                        if (enemy_y_r[ei*9 +: 9] >= PLAY_AREA_H)
                            enemy_active_r[ei] <= 1'b0;
                    end
                end

                //--- 波次生成器：定时生成敌人，每波数量递增 ---
                if (wave_timer_r == 0) begin
                    if (wave_spawned_r < wave_size_r) begin
                        found_e = 1'b0;
                        for (ei = 0; ei < MAX_ENEMIES; ei = ei + 1) begin
                            if (!enemy_active_r[ei] && !found_e) begin
                                // x*5/4 缩放: 0-511 => 0-638，覆盖全屏宽度
                                enemy_x_r[ei*10 +: 10]      <= {1'd0, lfsr_r[8:0]} + {3'd0, lfsr_r[8:2]};
                                enemy_base_x_r[ei*10 +: 10] <= {1'd0, lfsr_r[8:0]} + {3'd0, lfsr_r[8:2]};
                                enemy_y_r[ei*9 +: 9]        <= 9'd0;
                                enemy_type_r[ei*2 +: 2]     <= lfsr_r[7:6] ^ wave_spawned_r[1:0];
                                enemy_active_r[ei]          <= 1'b1;
                                                                found_e = 1'b1;
                            end
                        end
                        wave_spawned_r <= wave_spawned_r + 4'd1;
                    end else begin
                        wave_timer_r <= WAVE_INTERVAL;
                        wave_spawned_r <= 4'd0;
                        wave_r <= wave_r + 8'd1;
                        if (wave_size_r < MAX_WAVE_SIZE)
                            wave_size_r <= wave_size_r + 4'd1;
                    end
                end else begin
                    wave_timer_r <= wave_timer_r - 8'd1;
                end

                //=== 子弹 vs 敌人碰撞检测（矩形相交检测）===
                for (bi = 0; bi < MAX_BULLETS; bi = bi + 1) begin
                    if (bullet_active_r[bi]) begin
                        for (ei = 0; ei < MAX_ENEMIES; ei = ei + 1) begin
                            if (enemy_active_r[ei] && bullet_active_r[bi]) begin
                                if (bullet_x_r[bi*10 +: 10] + BULLET_W >= enemy_x_r[ei*10 +: 10] &&
                                    bullet_x_r[bi*10 +: 10] <= enemy_x_r[ei*10 +: 10] + ENEMY_W &&
                                    bullet_y_r[bi*9 +: 9] + BULLET_H >= enemy_y_r[ei*9 +: 9] &&
                                    bullet_y_r[bi*9 +: 9] <= enemy_y_r[ei*9 +: 9] + ENEMY_H) begin

                                    bullet_active_r[bi] <= 1'b0;
                                    enemy_active_r[ei]  <= 1'b0;

                                    case (enemy_type_r[ei*2 +: 2])
                                        2'd0: score_r <= score_r + 16'd10;
                                        2'd1: score_r <= score_r + 16'd20;
                                        2'd2: score_r <= score_r + 16'd15;
                                        default: score_r <= score_r + 16'd10;
                                    endcase

                                    found_x = 1'b0;
                                    for (xi = 0; xi < MAX_EXPLOSIONS; xi = xi + 1) begin
                                        if (!exp_active_r[xi] && !found_x) begin
                                            exp_x_r[xi*10 +: 10] <= enemy_x_r[ei*10 +: 10];
                                            exp_y_r[xi*9 +: 9]   <= enemy_y_r[ei*9 +: 9];
                                            exp_life_r[xi*5 +: 5] <= EXP_MAX_LIFE;
                                            exp_active_r[xi]     <= 1'b1;
                                            found_x = 1'b1;
                                        end
                                    end
                                end
                            end
                        end
                    end
                end

                //=== 玩家 vs 敌人碰撞检测（无敌时跳过）===
                if (invincible_timer_r == 0) begin
                    for (ei = 0; ei < MAX_ENEMIES; ei = ei + 1) begin
                        if (enemy_active_r[ei]) begin
                            if (player_x_r + PLAYER_W >= enemy_x_r[ei*10 +: 10] &&
                                player_x_r <= enemy_x_r[ei*10 +: 10] + ENEMY_W &&
                                player_y_r + PLAYER_H >= enemy_y_r[ei*9 +: 9] &&
                                player_y_r <= enemy_y_r[ei*9 +: 9] + ENEMY_H) begin

                                enemy_active_r[ei] <= 1'b0;

                                found_px = 1'b0;
                                for (xi = 0; xi < MAX_EXPLOSIONS; xi = xi + 1) begin
                                    if (!exp_active_r[xi] && !found_px) begin
                                        exp_x_r[xi*10 +: 10] <= enemy_x_r[ei*10 +: 10];
                                        exp_y_r[xi*9 +: 9]   <= enemy_y_r[ei*9 +: 9];
                                        exp_life_r[xi*5 +: 5] <= EXP_MAX_LIFE;
                                        exp_active_r[xi]     <= 1'b1;
                                        found_px = 1'b1;
                                    end
                                end

                                if (lives_r > 2'd1) begin
                                    lives_r <= lives_r - 2'd1;
                                    invincible_timer_r <= INVINCIBLE_TIME;
                                    state_r <= ST_DYING;
                                end else begin
                                    lives_r <= 2'd0;
                                    state_r <= ST_GAMEOVER;
                                end
                            end
                        end
                    end
                end
            end // ST_PLAYING

            //———— 死亡动画 (ST_DYING) ——————————————————————————————
            // 仍可移动，等待无敌倒计时归零后回到 PLAYING 状态
            ST_DYING: begin
                if ((btn_left || btn_up) && player_x_r > PLAYER_SPEED)
                    player_x_r <= player_x_r - PLAYER_SPEED;
                else if (btn_right && player_x_r < SCREEN_W - PLAYER_W - PLAYER_SPEED)
                    player_x_r <= player_x_r + PLAYER_SPEED;
                if (btn_up   && player_y_r > PLAYER_SPEED)
                    player_y_r <= player_y_r - PLAYER_SPEED;
                else if (btn_down && player_y_r < PLAY_AREA_H - PLAYER_H - PLAYER_SPEED)
                    player_y_r <= player_y_r + PLAYER_SPEED;
                for (xi = 0; xi < MAX_EXPLOSIONS; xi = xi + 1) begin
                    if (exp_active_r[xi]) begin
                        if (exp_life_r[xi*5 +: 5] > 0)
                            exp_life_r[xi*5 +: 5] <= exp_life_r[xi*5 +: 5] - 5'd1;
                        else
                            exp_active_r[xi] <= 1'b0;
                    end
                end
                if (invincible_timer_r == 0)
                    state_r <= ST_PLAYING;
                else
                    invincible_timer_r <= invincible_timer_r - 8'd1;
            end

            //———— 游戏结束 (ST_GAMEOVER) ——————————————————————————————
            // 按开始键返回标题画面
            ST_GAMEOVER: begin
                if (btn_start) state_r <= ST_TITLE;
            end

            default: state_r <= ST_TITLE;
        endcase

        //—— 星空滚动：所有星星每帧下移1像素，超出底部则回到顶部 ——
        for (si = 0; si < NUM_STARS; si = si + 1) begin
            if (star_y_r[si*9 +: 9] >= 10'd480)
                star_y_r[si*9 +: 9] <= 9'd0;
            else
                star_y_r[si*9 +: 9] <= star_y_r[si*9 +: 9] + 9'd1;
        end
    end
end

endmodule
