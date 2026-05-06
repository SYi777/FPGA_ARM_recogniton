`timescale 1ns / 1ps

module plate_color_center_rgb_ratio #(
    // 图像分辨率参数
    parameter H_ACT          = 1920,
    parameter V_ACT          = 1080,
    parameter BORDER         = 128,
    
    // 蓝牌RGB比例系数 交叉乘法
    // 约束：B * BLUE_MUL > R * BLUE_DIV 且 B * BLUE_MUL > G * BLUE_DIV
    parameter BLUE_MUL       = 5,
    parameter BLUE_DIV       = 3,
    parameter BLUE_MIN_B     = 60,  // 最低B通道阈值，避免黑夜暗部误判
    
    // 绿牌RGB比例系数
    // 约束：G * GREEN_MUL > R * GREEN_DIV 且 G * GREEN_MUL > B * GREEN_DIV
    parameter GREEN_MUL      = 5,
    parameter GREEN_DIV      = 3,
    parameter GREEN_MIN_G    = 60,
    
    // 黄牌RGB比例系数
    parameter YELLOW_MUL     = 2,
    parameter YELLOW_DIV     = 5,
    parameter YELLOW_MIN_R   = 140,
    parameter YELLOW_MIN_G   = 140,
    parameter YELLOW_DIFF_MAX= 80,
    
    // 滑动窗口边界检测参数
    parameter WINDOW_SIZE    = 11,
    parameter AVG_TH_HIGH    = 88,
    parameter AVG_TH_LOW     = 33,
    
    // 车牌长宽比硬约束（3~5倍）
    parameter MIN_ASPECT     = 3,
    parameter MAX_ASPECT     = 5
)
(
    input               clk,
    input               rst_n,
    input               bin_vs,    // 输入场同步
    input               bin_de,    // 输入数据有效
    input       [7:0]   r,         // 输入R通道
    input       [7:0]   g,         // 输入G通道
    input       [7:0]   b,         // 输入B通道
    output reg  [11:0]  cx,        // 车牌中心X坐标
    output reg  [11:0]  cy,        // 车牌中心Y坐标
    output reg          valid,     // 车牌检测有效标志（经10帧滤波后输出）
    output reg  [11:0]  left,      // 车牌左边界
    output reg  [11:0]  right,     // 车牌右边界
    output reg  [11:0]  top,       // 车牌上边界
    output reg  [11:0]  bottom     // 车牌下边界
);

// 颜色轮询状态与RGB掩膜生成
reg  [1:0]  color_state;  // 0:蓝牌检测 1:绿牌检测 2:黄牌检测 3:全检测失败
wire        is_blue, is_green, is_yellow;
wire        mask_raw;

// 蓝牌判别：B通道主导
wire [15:0] b_mul_blue = b * BLUE_MUL;
wire [15:0] r_mul_blue = r * BLUE_DIV;
wire [15:0] g_mul_blue = g * BLUE_DIV;
assign is_blue = (b_mul_blue > r_mul_blue) && (b_mul_blue > g_mul_blue) && (b >= BLUE_MIN_B);

// 绿牌判别：G通道主导
wire [15:0] g_mul_green = g * GREEN_MUL;
wire [15:0] r_mul_green = r * GREEN_DIV;
wire [15:0] b_mul_green = b * GREEN_DIV;
assign is_green = (g_mul_green > r_mul_green) && (g_mul_green > b_mul_green) && (g >= GREEN_MIN_G);

// 黄牌判别：R/G通道主导，且R与G分量接近
wire [15:0] r_mul_yellow = r * YELLOW_MUL;
wire [15:0] g_mul_yellow = g * YELLOW_MUL;
wire [15:0] b_mul_yellow = b * YELLOW_DIV;
wire [7:0]  rg_diff = (r > g) ? (r - g) : (g - r);
assign is_yellow = (r >= YELLOW_MIN_R) && (g >= YELLOW_MIN_G) && (rg_diff < YELLOW_DIFF_MAX);
// 判定逻辑：R和G的值均高于140且R和G的差异不超过60
// 按当前颜色状态选通掩膜
assign mask_raw = (color_state == 2'd0) ? is_blue : 
                  (color_state == 2'd1) ? is_green : 
                  (color_state == 2'd2) ? is_yellow : 1'b0;

// 形态学闭运算
wire [7:0] mask_8b = {8{mask_raw}};

wire [7:0] mask_dil;
wire       vs_dil, de_dil;

wire [7:0] mask_final_8b;
wire       vs_final, de_final;

//膨胀
dilation u_dilation_close (
    .clk        (clk),
    .rst_n      (rst_n),
    .in_vs      (bin_vs),
    .in_de      (bin_de),
    .in_data    (mask_8b),
    .out_vs     (vs_dil),
    .out_de     (de_dil),
    .out_data   (mask_dil)
);

//腐蚀
erosion u_erosion_close (
    .clk        (clk),
    .rst_n      (rst_n),
    .in_vs      (vs_dil),
    .in_de      (de_dil),
    .in_data    (mask_dil),
    .out_vs     (vs_final),
    .out_de     (de_final),
    .out_data   (mask_final_8b)
);

// 最终二值掩膜
wire mask = mask_final_8b[0];

// 像素坐标生成与行列投影RAM
reg [11:0] x_cnt, y_cnt;
reg de_d1, vs_d1;
wire de_neg = ~de_final & de_d1;  // de下降沿（行结束）
wire vs_pos = bin_vs & ~vs_d1;     // 场同步上升沿（帧起始）

// 像素坐标计数器
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        x_cnt <= 12'd0;
        y_cnt <= 12'd0;
        de_d1 <= 1'b0;
        vs_d1 <= 1'b0;
    end else begin
        de_d1 <= de_final;
        vs_d1 <= bin_vs;
        if (vs_pos) begin
            x_cnt <= 12'd0;
            y_cnt <= 12'd0;
        end else if (de_final) begin
            x_cnt <= x_cnt + 1'b1;
        end else if (de_neg) begin
            x_cnt <= 12'd0;
            y_cnt <= y_cnt + 1'b1;
        end
    end
end

// 行投影RAM：存储每行的掩膜像素总数
(* ram_style = "block" *) reg [11:0] row_ram [0:V_ACT-1];
reg [11:0] row_acc;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        row_acc <= 12'd0;
    end else begin
        if (vs_pos) begin
            row_acc <= 12'd0;
        end else if (de_final) begin
            row_acc <= row_acc + mask;
        end else if (de_neg) begin
            row_acc <= 12'd0;
        end
    end
end
always @(posedge clk) begin
    if (de_neg) row_ram[y_cnt] <= row_acc;
end

// 列投影RAM（合并清零与累积，单端口写）
(* ram_style = "block" *) reg [11:0] col_ram [0:H_ACT-1];
always @(posedge clk) begin
    if (state == S_CLEAR) begin
        col_ram[addr_cnt] <= 12'd0;          // 清零阶段
    end else if (state == S_ACCUM && de_final) begin
        col_ram[x_cnt] <= col_ram[x_cnt] + mask; // 累积阶段
    end
end

// 状态机定义
localparam 
    S_CLEAR     = 4'd0,  // 清零列RAM
    S_ACCUM     = 4'd1,  // 帧数据积累，生成行列投影
    S_FIND_Y    = 4'd2,  // 滑动窗口找垂直上下边界
    S_FIND_X    = 4'd3,  // 滑动窗口找水平左右边界
    S_CHECK     = 4'd4,  // 长宽比计算（非阻塞赋值）
    S_CHECK2    = 4'd8,  // 长宽比合法性判断
    S_OUT       = 4'd5,  // 检测成功，等待下一帧
    S_NEXT_COLOR= 4'd6,  // 当前颜色检测失败，切换下一个颜色
    S_INVALID   = 4'd7;  // 所有颜色检测失败，输出无效

reg [3:0]  state;
reg [11:0] addr_cnt;
// 滑动窗口寄存器
reg [11:0] w0,w1,w2,w3,w4,w5,w6,w7,w8,w9,w10;
reg [15:0] sum;
reg        in_region;
// 边界寄存器
reg [11:0] left_bound, right_bound, top_bound, bottom_bound;
reg [11:0] left_latch, right_latch, top_latch, bottom_latch;
// RAM预取寄存器
reg [11:0] ram_data_d1;

reg [11:0] plate_w, plate_h;
reg [23:0] w_mul_min, w_mul_max;

// RAM数据预取，保证滑动窗口时序对齐
always @(posedge clk) begin
    if (state == S_FIND_Y) begin
        ram_data_d1 <= row_ram[addr_cnt];
    end else if (state == S_FIND_X) begin
        ram_data_d1 <= col_ram[addr_cnt];
    end else begin
        ram_data_d1 <= 12'd0;
    end
end

// 主状态机时序逻辑（不再直接输出valid和坐标）
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state <= S_CLEAR;
        addr_cnt <= 12'd0;
        left_bound <= 12'd0;
        right_bound <= 12'd0;
        top_bound <= 12'd0;
        bottom_bound <= 12'd0;
        left_latch <= 12'd0;
        right_latch <= 12'd0;
        top_latch <= 12'd0;
        bottom_latch <= 12'd0;
        in_region <= 1'b0;
        color_state <= 2'd0;
        sum <= 16'd0;
        w0 <= 12'd0; w1 <= 12'd0; w2 <= 12'd0; w3 <= 12'd0; w4 <= 12'd0; w5 <= 12'd0;
        w6 <= 12'd0; w7 <= 12'd0; w8 <= 12'd0; w9 <= 12'd0; w10 <= 12'd0;
        plate_w <= 0; plate_h <= 0; w_mul_min <= 0; w_mul_max <= 0;
    end else begin
        case (state)
            // 阶段1：清零列投影RAM，为当前颜色检测做准备
            S_CLEAR: begin
                // col_ram 清零已由独立的 always 块完成，这里只控制地址递增
                addr_cnt <= addr_cnt + 1'b1;
                if (addr_cnt == H_ACT-1) begin
                    state <= S_ACCUM;
                    addr_cnt <= 12'd0;
                end
            end

            // 阶段2：逐像素积累行列投影数据
            S_ACCUM: begin
                // 帧结束，进入边界检测
                if (de_neg && y_cnt == V_ACT-1) begin
                    state <= S_FIND_Y;
                    addr_cnt <= BORDER;
                    in_region <= 1'b0;
                    left_bound <= 12'd0;
                    right_bound <= 12'd0;
                    top_bound <= 12'd0;
                    bottom_bound <= 12'd0;
                    w0 <= 12'd0; w1 <= 12'd0; w2 <= 12'd0; w3 <= 12'd0; w4 <= 12'd0; w5 <= 12'd0;
                    w6 <= 12'd0; w7 <= 12'd0; w8 <= 12'd0; w9 <= 12'd0; w10 <= 12'd0;
                end
                // 新帧到来，重置状态机，但不重置颜色轮询状态
                if (vs_pos) begin
                    state <= S_CLEAR;
                    addr_cnt <= 12'd0;
                end
            end

            // 阶段3：滑动窗口找垂直方向（Y轴）上下边界
            S_FIND_Y: begin
                if (addr_cnt < V_ACT - BORDER) begin
                    // 滑动窗口移位更新
                    {w0,w1,w2,w3,w4,w5,w6,w7,w8,w9,w10} <= {ram_data_d1,w0,w1,w2,w3,w4,w5,w6,w7,w8,w9};
                    // 窗口内像素和计算
                    sum <= w0+w1+w2+w3+w4+w5+w6+w7+w8+w9+w10;
                    
                    // 施密特触发找边界，抗抖动
                    if (addr_cnt > BORDER + WINDOW_SIZE) begin
                        // 进入边界：锁定上边界
                        if (!in_region && (sum > AVG_TH_HIGH)) begin
                            top_bound <= addr_cnt - (WINDOW_SIZE/2);
                            in_region <= 1'b1;
                        end
                        // 离开边界：锁定下边界
                        if (in_region && (sum < AVG_TH_LOW) && (top_bound != 12'd0)) begin
                            bottom_bound <= addr_cnt - WINDOW_SIZE;
                            in_region <= 1'b0;
                        end
                    end
                    addr_cnt <= addr_cnt + 1'b1;
                end else begin
                    // 边界兜底，避免无边界导致逻辑卡死
                    if (top_bound != 12'd0 && bottom_bound == 12'd0) bottom_bound <= top_bound + 12'd80;
                    if (bottom_bound != 12'd0 && top_bound == 12'd0) top_bound <= bottom_bound - 12'd80;
                    if (top_bound == 12'd0 && bottom_bound == 12'd0) begin top_bound <= V_ACT/2; bottom_bound <= V_ACT/2 + 12'd80; end
                    
                    // 进入水平边界检测
                    state <= S_FIND_X;
                    addr_cnt <= BORDER;
                    in_region <= 1'b0;
                    w0 <= 12'd0; w1 <= 12'd0; w2 <= 12'd0; w3 <= 12'd0; w4 <= 12'd0; w5 <= 12'd0;
                    w6 <= 12'd0; w7 <= 12'd0; w8 <= 12'd0; w9 <= 12'd0; w10 <= 12'd0;
                end
            end

            // 阶段4：滑动窗口找水平方向（X轴）左右边界
            S_FIND_X: begin
                if (addr_cnt < H_ACT - BORDER) begin
                    // 滑动窗口移位更新
                    {w0,w1,w2,w3,w4,w5,w6,w7,w8,w9,w10} <= {ram_data_d1,w0,w1,w2,w3,w4,w5,w6,w7,w8,w9};
                    // 窗口内像素和计算
                    sum <= w0+w1+w2+w3+w4+w5+w6+w7+w8+w9+w10;
                    
                    // 施密特触发找边界，抗抖动
                    if (addr_cnt > BORDER + WINDOW_SIZE) begin
                        // 进入边界：锁定左边界
                        if (!in_region && (sum > AVG_TH_HIGH)) begin
                            left_bound <= addr_cnt - (WINDOW_SIZE/2);
                            in_region <= 1'b1;
                        end
                        // 离开边界：锁定右边界
                        if (in_region && (sum < AVG_TH_LOW) && (left_bound != 12'd0)) begin
                            right_bound <= addr_cnt - WINDOW_SIZE;
                            in_region <= 1'b0;
                        end
                    end
                    addr_cnt <= addr_cnt + 1'b1;
                end else begin
                    // 边界兜底，避免无边界导致逻辑卡死
                    if (left_bound != 12'd0 && right_bound == 12'd0) right_bound <= left_bound + 12'd200;
                    if (right_bound != 12'd0 && left_bound == 12'd0) left_bound <= right_bound - 12'd200;
                    if (left_bound == 12'd0 && right_bound == 12'd0) begin left_bound <= H_ACT/2; right_bound <= H_ACT/2 + 12'd200; end
                    
                    // 锁存边界，进入合法性校验
                    left_latch <= left_bound;
                    right_latch <= right_bound;
                    top_latch <= top_bound;
                    bottom_latch <= bottom_bound;
                    state <= S_CHECK;
                end
            end

            // 阶段5：车牌宽高计算（纯非阻塞赋值）
            S_CHECK: begin
                plate_w   <= right_latch - left_latch;
                plate_h   <= bottom_latch - top_latch;
                w_mul_min <= (right_latch - left_latch) * MIN_ASPECT;
                w_mul_max <= (right_latch - left_latch) * MAX_ASPECT;
                state     <= S_CHECK2;   // 无条件进入下一状态进行判断
            end

            // 新增：长宽比合法性判断（使用上一周期计算好的值）
            S_CHECK2: begin
                if (plate_h > 12'd20 && plate_w > 12'd60 && 
                    (w_mul_min >= plate_h) && (plate_w <= w_mul_max)) begin
                    state <= S_OUT;
                end else begin
                    state <= S_NEXT_COLOR;
                end
            end

            // 阶段6：检测成功，等待下一帧到来（坐标和有效标志由滤波模块管理）
            S_OUT: begin
                if (vs_pos) begin
                    state <= S_CLEAR;
                    color_state <= 2'd0;
                    addr_cnt <= 12'd0;
                end
            end

            // 阶段7：当前颜色检测失败，切换下一个颜色
            S_NEXT_COLOR: begin
                if (color_state == 2'd2) begin
                    // 蓝/绿/黄三色均检测失败，进入无效状态
                    state <= S_INVALID;
                end else begin
                    // 切换下一个颜色，重新开始检测
                    color_state <= color_state + 1'b1;
                    state <= S_CLEAR;
                    addr_cnt <= 12'd0;
                end
            end

            // 阶段8：所有颜色检测失败，等待下一帧
            S_INVALID: begin
                if (vs_pos) begin
                    state <= S_CLEAR;
                    color_state <= 2'd0;
                    addr_cnt <= 12'd0;
                end
            end
        endcase
    end
end

// 帧级检测历史滤波：连续记录10个valid状态，若超过6个为1则输出1
reg [9:0] valid_hist;            // 10比特历史，每比特代表一帧的检测结果（1=检测到）
reg       filtered_valid_reg;    // 滤波后的有效信号

// 下一帧历史值：左移一位，新帧的检测状态（状态机处于S_OUT表示当前帧检测成功）
wire [9:0] next_hist = {valid_hist[8:0], (state == S_OUT)};

// 统计历史中1的个数
wire [3:0] next_ones = next_hist[0] + next_hist[1] + next_hist[2] + next_hist[3] + next_hist[4] +
                       next_hist[5] + next_hist[6] + next_hist[7] + next_hist[8] + next_hist[9];

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        valid_hist         <= 10'd0;
        filtered_valid_reg <= 1'b0;
    end else if (vs_pos) begin                // 每帧开始时更新历史并重评估滤波结果
        valid_hist         <= next_hist;
        filtered_valid_reg <= (next_ones > 4'd3);  // 超过6个1（即≥7）则滤波后valid=1
    end
end

// 检测坐标锁存：一旦检测到车牌，锁存当前坐标值
reg [11:0] cx_latched, cy_latched, left_latched, right_latched, top_latched, bottom_latched;
reg [3:0]  prev_state;   // 用于检测状态跳变

always @(posedge clk) prev_state <= state;

// 当状态刚从其他状态进入S_OUT时，锁存边界并计算中心
wire detect_event = (state == S_OUT) && (prev_state != S_OUT);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        cx_latched     <= 12'd0;
        cy_latched     <= 12'd0;
        left_latched   <= 12'd0;
        right_latched  <= 12'd0;
        top_latched    <= 12'd0;
        bottom_latched <= 12'd0;
    end else if (detect_event) begin
        cx_latched     <= (left_latch + right_latch) >> 1;
        cy_latched     <= (top_latch + bottom_latch) >> 1;
        left_latched   <= left_latch;
        right_latched  <= right_latch;
        top_latched    <= top_latch;
        bottom_latched <= bottom_latch;
    end
end

// 输出驱动：滤波后的valid与锁存的坐标
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        valid  <= 1'b0;
        cx     <= 12'd0;
        cy     <= 12'd0;
        left   <= 12'd0;
        right  <= 12'd0;
        top    <= 12'd0;
        bottom <= 12'd0;
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