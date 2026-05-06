`timescale 1ns / 1ps

// ==========================================================
// 模块功能：基于 RGB 比例无除法颜色分割 + 滑动窗口边界检测
// 实现蓝牌、绿牌、黄牌自动识别，输出车牌中心与外接矩形
// 适用：1080P@60fps 实时视频流车牌定位
// ==========================================================
module plate_color_center_rgb_ratio #(
    // 图像分辨率配置
    parameter H_ACT          = 1920,      // 水平有效像素
    parameter V_ACT          = 1080,      // 垂直有效像素
    parameter BORDER         = 128,       // 边缘屏蔽宽度，避免边界干扰
    
    // 蓝牌 RGB 比例判定系数（无除法）
    parameter BLUE_MUL       = 5,
    parameter BLUE_DIV       = 3,
    parameter BLUE_MIN_B     = 60,        // B 通道最小值，避免暗部误判
    
    // 绿牌 RGB 比例判定系数
    parameter GREEN_MUL      = 5,
    parameter GREEN_DIV      = 3,
    parameter GREEN_MIN_G    = 60,        // G 通道最小值
    
    // 黄牌 RGB 比例判定系数
    parameter YELLOW_MUL     = 3,
    parameter YELLOW_DIV     = 1,
    parameter YELLOW_MIN_R   = 80,        // R 通道最小值
    parameter YELLOW_MIN_G   = 80,        // G 通道最小值
    
    // 滑动窗口边界检测参数
    parameter WINDOW_SIZE    = 11,        // 窗口长度
    parameter AVG_TH_HIGH    = 88,        // 进入区域阈值
    parameter AVG_TH_LOW     = 33,        // 离开区域阈值
    
    // 车牌长宽比约束（3~5 倍）
    parameter MIN_ASPECT     = 3,
    parameter MAX_ASPECT     = 5
)
(
    input               clk,            // 系统时钟
    input               rst_n,          // 复位（低有效）
    input               bin_vs,         // 场同步信号
    input               bin_de,         // 数据有效信号
    input       [7:0]   r,              // 红色通道输入
    input       [7:0]   g,              // 绿色通道输入
    input       [7:0]   b,              // 蓝色通道输入
    
    output reg  [11:0]  cx,             // 车牌中心 X
    output reg  [11:0]  cy,             // 车牌中心 Y
    output reg          valid,          // 检测有效（10 帧滤波后）
    output reg  [11:0]  left,           // 左边界
    output reg  [11:0]  right,          // 右边界
    output reg  [11:0]  top,            // 上边界
    output reg  [11:0]  bottom          // 下边界
);

// ==========================================================
// 内部状态定义
// ==========================================================
reg  [1:0]  color_state;                // 0:蓝 1:绿 2:黄 3:无效
wire        is_blue, is_green, is_yellow;
wire        mask_raw;

// ==========================================================
// 蓝牌判定逻辑：B 远大于 R、G
// ==========================================================
wire [15:0] b_mul_blue = b * BLUE_MUL;
wire [15:0] r_mul_blue = r * BLUE_DIV;
wire [15:0] g_mul_blue = g * BLUE_DIV;
assign is_blue = (b_mul_blue > r_mul_blue) && (b_mul_blue > g_mul_blue) && (b >= BLUE_MIN_B);

// ==========================================================
// 绿牌判定逻辑：G 远大于 R、B
// ==========================================================
wire [15:0] g_mul_green = g * GREEN_MUL;
wire [15:0] r_mul_green = r * GREEN_DIV;
wire [15:0] b_mul_green = b * GREEN_DIV;
assign is_green = (g_mul_green > r_mul_green) && (g_mul_green > b_mul_green) && (g >= GREEN_MIN_G);

// ==========================================================
// 黄牌判定逻辑：R、G 远大于 B
// ==========================================================
wire [15:0] r_mul_yellow = r * YELLOW_MUL;
wire [15:0] g_mul_yellow = g * YELLOW_MUL;
wire [15:0] b_mul_yellow = b * YELLOW_DIV;
assign is_yellow = (r_mul_yellow > b_mul_yellow) && (g_mul_yellow > b_mul_yellow) 
                && (r >= YELLOW_MIN_R) && (g >= YELLOW_MIN_G);

// 颜色掩膜选择
assign mask_raw = (color_state == 2'd0) ? is_blue : 
                  (color_state == 2'd1) ? is_green : 
                  (color_state == 2'd2) ? is_yellow : 1'b0;

// ==========================================================
// 形态学闭运算：先膨胀 → 后腐蚀
// ==========================================================
wire [7:0] mask_8b = {8{mask_raw}};
wire [7:0] mask_dil, mask_final_8b;
wire       vs_dil, de_dil, vs_final, de_final;

// 膨胀：连接断裂区域
dilation u_dilation_close (
    .clk(clk),.rst_n(rst_n),.in_vs(bin_vs),.in_de(bin_de),.in_data(mask_8b),
    .out_vs(vs_dil),.out_de(de_dil),.out_data(mask_dil)
);

// 腐蚀：恢复尺寸，消除噪声
erosion u_erosion_close (
    .clk(clk),.rst_n(rst_n),.in_vs(vs_dil),.in_de(de_dil),.in_data(mask_dil),
    .out_vs(vs_final),.out_de(de_final),.out_data(mask_final_8b)
);

wire mask = mask_final_8b[0];

// ==========================================================
// 像素坐标计数器 X/Y
// ==========================================================
reg [11:0] x_cnt, y_cnt;
reg de_d1, vs_d1;
wire de_neg = ~de_final & de_d1;
wire vs_pos = bin_vs & ~vs_d1;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        x_cnt <= 0; y_cnt <= 0; de_d1 <= 0; vs_d1 <= 0;
    end else begin
        de_d1 <= de_final; vs_d1 <= bin_vs;
        if (vs_pos) begin x_cnt <= 0; y_cnt <= 0; end
        else if (de_final) x_cnt <= x_cnt + 1'b1;
        else if (de_neg) begin x_cnt <= 0; y_cnt <= y_cnt + 1'b1; end
    end
end

// ==========================================================
// 行投影 RAM
// ==========================================================
(* ram_style = "block" *) reg [11:0] row_ram [0:V_ACT-1];
reg [11:0] row_acc;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) row_acc <= 0;
    else begin
        if (vs_pos) row_acc <= 0;
        else if (de_final) row_acc <= row_acc + mask;
        else if (de_neg) row_acc <= 0;
    end
end

always @(posedge clk) if (de_neg) row_ram[y_cnt] <= row_acc;

// ==========================================================
// 列投影 RAM
// ==========================================================
(* ram_style = "block" *) reg [11:0] col_ram [0:H_ACT-1];

// ==========================================================
// 主状态机
// ==========================================================
localparam 
    S_CLEAR     = 4'd0,     // 清零列RAM
    S_ACCUM     = 4'd1,     // 投影累积
    S_FIND_Y    = 4'd2,     // 找上下边界
    S_FIND_X    = 4'd3,     // 找左右边界
    S_CHECK     = 4'd4,     // 计算宽高
    S_CHECK2    = 4'd8,     // 长宽比校验
    S_OUT       = 4'd5,     // 检测成功
    S_NEXT_COLOR= 4'd6,     // 切换颜色
    S_INVALID   = 4'd7;     // 全部无效

reg [3:0]  state;
reg [11:0] addr_cnt;
reg [11:0] w0,w1,w2,w3,w4,w5,w6,w7,w8,w9,w10;
reg [15:0] sum;
reg        in_region;
reg [11:0] left_bound, right_bound, top_bound, bottom_bound;
reg [11:0] left_latch, right_latch, top_latch, bottom_latch;
reg [11:0] ram_data_d1;
reg [11:0] plate_w, plate_h;
reg [23:0] w_mul_min, w_mul_max;

// ==========================================================
// RAM 数据预取
// ==========================================================
always @(posedge clk) begin
    if (state == S_FIND_Y) ram_data_d1 <= row_ram[addr_cnt];
    else if (state == S_FIND_X) ram_data_d1 <= col_ram[addr_cnt];
    else ram_data_d1 <= 0;
end

// ==========================================================
// 主状态机时序逻辑
// ==========================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state <= S_CLEAR; addr_cnt <= 0; color_state <= 0;
        left_bound <= 0; right_bound <= 0; top_bound <= 0; bottom_bound <= 0;
    end else begin
        case (state)
            S_CLEAR: begin
                addr_cnt <= addr_cnt + 1'b1;
                if (addr_cnt == H_ACT-1) begin state <= S_ACCUM; addr_cnt <= 0; end
            end
            
            S_ACCUM: begin
                if (de_neg && y_cnt == V_ACT-1) begin
                    state <= S_FIND_Y; addr_cnt <= BORDER;
                end
                if (vs_pos) begin state <= S_CLEAR; addr_cnt <= 0; color_state <= 0; end
            end
            
            S_FIND_Y: begin
                if (addr_cnt < V_ACT - BORDER) begin
                    {w0,w1,w2,w3,w4,w5,w6,w7,w8,w9,w10} <= {ram_data_d1,w0,w1,w2,w3,w4,w5,w6,w7,w8,w9};
                    sum <= w0+w1+w2+w3+w4+w5+w6+w7+w8+w9+w10;
                    if (!in_region && sum > AVG_TH_HIGH) begin
                        top_bound <= addr_cnt - WINDOW_SIZE/2; in_region <= 1;
                    end
                    if (in_region && sum < AVG_TH_LOW) begin
                        bottom_bound <= addr_cnt - WINDOW_SIZE; in_region <= 0;
                    end
                    addr_cnt <= addr_cnt + 1'b1;
                end else begin
                    state <= S_FIND_X; addr_cnt <= BORDER;
                end
            end
            
            S_FIND_X: begin
                if (addr_cnt < H_ACT - BORDER) begin
                    {w0,w1,w2,w3,w4,w5,w6,w7,w8,w9,w10} <= {ram_data_d1,w0,w1,w2,w3,w4,w5,w6,w7,w8,w9};
                    sum <= w0+w1+w2+w3+w4+w5+w6+w7+w8+w9+w10;
                    if (!in_region && sum > AVG_TH_HIGH) begin
                        left_bound <= addr_cnt - WINDOW_SIZE/2; in_region <= 1;
                    end
                    if (in_region && sum < AVG_TH_LOW) begin
                        right_bound <= addr_cnt - WINDOW_SIZE; in_region <= 0;
                    end
                    addr_cnt <= addr_cnt + 1'b1;
                end else begin
                    left_latch <= left_bound; right_latch <= right_bound;
                    top_latch <= top_bound; bottom_latch <= bottom_bound;
                    state <= S_CHECK;
                end
            end
            
            S_CHECK: begin
                plate_w   <= right_latch - left_latch;
                plate_h   <= bottom_latch - top_latch;
                w_mul_min <= (right_latch - left_latch) * MIN_ASPECT;
                w_mul_max <= (right_latch - left_latch) * MAX_ASPECT;
                state     <= S_CHECK2;
            end
            
            S_CHECK2: begin
                if (plate_h>20 && plate_w>60 && w_mul_min>=plate_h && plate_w<=w_mul_max)
                    state <= S_OUT;
                else
                    state <= S_NEXT_COLOR;
            end
            
            S_OUT: begin
                if (vs_pos) begin state <= S_CLEAR; color_state <= 0; addr_cnt <= 0; end
            end
            
            S_NEXT_COLOR: begin
                if (color_state == 2'd2) state <= S_INVALID;
                else begin color_state <= color_state + 1'b1; state <= S_CLEAR; addr_cnt <= 0; end
            end
            
            S_INVALID: begin
                if (vs_pos) begin state <= S_CLEAR; color_state <=0; addr_cnt <=0; end
            end
        endcase
    end
end

// ==========================================================
// 10 帧滤波抗抖动
// ==========================================================
reg [9:0] valid_hist;
reg       filtered_valid_reg;
wire [9:0] next_hist = {valid_hist[8:0], state == S_OUT};
wire [3:0] next_ones = next_hist[0]+next_hist[1]+next_hist[2]+next_hist[3]+next_hist[4]+
                       next_hist[5]+next_hist[6]+next_hist[7]+next_hist[8]+next_hist[9];

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin valid_hist <=0; filtered_valid_reg <=0; end
    else if (vs_pos) begin
        valid_hist <= next_hist;
        filtered_valid_reg <= (next_ones > 4'd3);
    end
end

// ==========================================================
// 检测成功时锁存坐标
// ==========================================================
reg [11:0] cx_latched, cy_latched, left_latched, right_latched, top_latched, bottom_latched;
reg [3:0]  prev_state;
wire detect_event = (state == S_OUT) && (prev_state != S_OUT);

always @(posedge clk) prev_state <= state;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        cx_latched <=0; cy_latched <=0; left_latched<=0; right_latched<=0; top_latched<=0; bottom_latched<=0;
    end else if (detect_event) begin
        cx_latched <= (left_latch + right_latch) >> 1;
        cy_latched <= (top_latch + bottom_latch) >> 1;
        left_latched <= left_latch;
        right_latched <= right_latch;
        top_latched <= top_latch;
        bottom_latched <= bottom_latch;
    end
end

// ==========================================================
// 最终输出
// ==========================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        valid<=0; cx<=0; cy<=0; left<=0; right<=0; top<=0; bottom<=0;
    end else begin
        valid  <= filtered_valid_reg;
        cx     <= cx_latched;
        cy     <= cy_latched;
        left   <= left_latched;
        right  <= right_latched;
        top    <= top_latched;
        bottom <= bottom_latched;
    end
end

endmodule