//===================================================================
// vga_ctrl.v — VGA 640x480@60Hz 时序控制器
//===================================================================
// 【功能】生成 VGA 行同步(HSYNC)和场同步(VSYNC)信号，以及当前像素坐标。
// 采用 25MHz 使能脉冲方式：单个 100MHz 时钟域下，仅在 tick 信号有效时
// 推进状态（每4个时钟周期推进一次）。
//
// VGA 时序（25MHz 像素时钟，实际刷新率约 59.5Hz）：
//   行扫描:  96 同步 + 48 后肩 + 640 显示 + 16 前肩 = 800 像素
//   场扫描:   2 同步 + 33 后肩 + 480 显示 + 10 前肩 = 525 行
//
// 输出信号：h_count[0-799] 行像素计数器, v_count[0-524] 场行计数器
//           active 显示区域标志, new_frame 新帧起始脉冲
//===================================================================

module vga_ctrl (
    input  wire       clk,          // 100MHz system clock
    input  wire       tick,         // 25MHz enable pulse (clk/4)
    input  wire       rst_n,        // active-low reset
    output reg        hsync,        // horizontal sync
    output reg        vsync,        // vertical sync
    output reg  [9:0] h_count,     // horizontal pixel counter [0,799]
    output reg  [9:0] v_count,     // vertical line counter   [0,524]
    output reg        active,       // high during display area
    output reg        new_frame     // single-cycle pulse at frame start
);

//———————————————————————————————————————————————————————————————————
// VGA 时序常数（所有数值以 25MHz 下的像素/行为单位）
//———————————————————————————————————————————————————————————————————
localparam H_DISPLAY   = 10'd640;   // visible area
localparam H_FRONT     = 10'd16;    // front porch
localparam H_SYNC      = 10'd96;    // sync pulse
localparam H_BACK      = 10'd48;    // back porch
localparam H_TOTAL     = 10'd800;   // whole line

localparam V_DISPLAY   = 10'd480;   // visible area
localparam V_FRONT     = 10'd10;    // front porch
localparam V_SYNC      = 10'd2;     // sync pulse
localparam V_BACK      = 10'd33;    // back porch
localparam V_TOTAL     = 10'd525;   // whole frame

//———————————————————————————————————————————————————————————————————
// 行/场计数器 —— 仅在 25MHz tick 使能时递增
// 核心状态机：同步产生 HSYNC、VSYNC、active 和 new_frame 信号
//———————————————————————————————————————————————————————————————————
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        h_count   <= 10'd0;
        v_count   <= 10'd0;
        hsync     <= 1'b1;
        vsync     <= 1'b1;
        active    <= 1'b0;
        new_frame <= 1'b0;
    end else if (tick) begin
        //—— 行计数器：0 → 799 循环 —————————————
        if (h_count == H_TOTAL - 1) begin
            h_count <= 10'd0;
            //—— 场计数器：扫描完一行后递增 ——————
            if (v_count == V_TOTAL - 1)
                v_count <= 10'd0;          // 扫描完一帧，重置
            else
                v_count <= v_count + 10'd1; // 行数+1
        end else begin
            h_count <= h_count + 10'd1;    // 像素列数+1
        end

        //—— HSYNC 行同步信号（低电平有效） ——————
        hsync <= (h_count >= (H_DISPLAY + H_FRONT) &&
                  h_count <  (H_DISPLAY + H_FRONT + H_SYNC)) ? 1'b0 : 1'b1;

        //—— VSYNC 场同步信号（低电平有效） ——————
        vsync <= (v_count >= (V_DISPLAY + V_FRONT) &&
                  v_count <  (V_DISPLAY + V_FRONT + V_SYNC)) ? 1'b0 : 1'b1;

        //—— 显示有效区域标志 ————————————————
        // 当行列都在显示区内时为高电平
        active <= (h_count < H_DISPLAY) && (v_count < V_DISPLAY);

        //—— 新帧脉冲：在 (0,0) 位置产生一个 tick 宽度脉冲
        new_frame <= (h_count == 10'd0) && (v_count == 10'd0);
    end else begin
        new_frame <= 1'b0;  // 脉冲只持续一个 tick
    end
end

endmodule
