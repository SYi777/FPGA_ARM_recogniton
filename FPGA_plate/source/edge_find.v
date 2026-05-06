`timescale 1ns / 1ps
module plate_edge_box #(
    parameter H_ACT          = 1920,
    parameter V_ACT          = 1080,
    parameter HALF_SCREEN_W  = 1080,        // 半屏宽（兜底用）
    parameter HALF_SCREEN_H  = 540,        // 半屏高
    parameter SIM_THRESH     = 85          // 峰对相似度百分比
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        bin_vs,
    input  wire        bin_de,
    input  wire        bin_pix,
    input  wire [11:0] cx,                // 颜色中心 X (0 无效)
    input  wire [11:0] cy,                // 颜色中心 Y
    output reg  [11:0] x1,
    output reg  [11:0] y1,
    output reg  [11:0] x2,
    output reg  [11:0] y2
);

    // 行列计数器
    reg [11:0] cnt_col, cnt_row;
    reg        de_d0;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt_col <= 0; cnt_row <= 0; de_d0 <= 0;
        end else begin
            de_d0 <= bin_de;
            if (bin_vs) begin cnt_col <= 0; cnt_row <= 0; end
            else if (bin_de) cnt_col <= cnt_col + 1'b1;
            if (de_d0 && !bin_de) cnt_row <= cnt_row + 1'b1;
        end
    end

    // 场同步边沿检测
    reg vs_d0;
    wire vs_rise = bin_vs && !vs_d0;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) vs_d0 <= 0;
        else vs_d0 <= bin_vs;
    end

    // 帧结束脉冲
    reg frame_end;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) frame_end <= 0;
        else if (vs_rise) frame_end <= 0;
        else if (de_d0 && !bin_de && cnt_row == V_ACT-1) frame_end <= 1;
        else frame_end <= 0;
    end

    // 行投影（第一帧）
    reg [15:0] row_sum_tmp;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) row_sum_tmp <= 0;
        else if (vs_rise) row_sum_tmp <= 0;
        else if (bin_de) begin
            if (bin_pix) row_sum_tmp <= row_sum_tmp + 1'b1;
        end else if (de_d0 && !bin_de) row_sum_tmp <= 0;
    end

    reg [15:0] row_proj [0:V_ACT-1];
    always @(posedge clk) if (de_d0 && !bin_de) row_proj[cnt_row] <= row_sum_tmp;

    // 列投影（第二帧，限定行范围）
    reg [15:0] col_proj [0:H_ACT-1];
    reg        col_proj_en;
    reg [11:0] y1_bound, y2_bound;        // 第一帧确定的 Y 范围
    integer ci;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (ci = 0; ci < H_ACT; ci = ci+1) col_proj[ci] <= 0;
        end else if (vs_rise) begin
            for (ci = 0; ci < H_ACT; ci = ci+1) col_proj[ci] <= 0;
            col_proj_en <= 0;
        end else if (bin_de) begin
            if (col_proj_en && cnt_row >= y1_bound && cnt_row <= y2_bound) begin
                if (bin_pix) col_proj[cnt_col] <= col_proj[cnt_col] + 1'b1;
            end
        end
    end

    // 状态机定义
    localparam S_IDLE         = 3'd0;
    localparam S_FRAME1_WAIT  = 3'd1;   // 等待第一帧结束
    localparam S_ANALYZE_Y    = 3'd2;   // 分析 Y 方向峰对
    localparam S_FRAME2_WAIT  = 3'd3;   // 等待第二帧结束
    localparam S_ANALYZE_X    = 3'd4;   // 分析 X 方向峰对
    localparam S_OUTPUT       = 3'd5;   // 输出最终框

    reg [2:0] state, next_state;

    // 内部控制信号
    reg        full_screen;             // 颜色无效，直接全屏框
    reg [11:0] cx_l, cy_l;              // 锁存的中心坐标

    // Y 搜索相关
    reg [11:0] y_peak1_pos, y_peak2_pos;
    reg [15:0] y_peak1_val, y_peak2_val;
    reg        y_found;
    reg [11:0] y_search_addr;
    reg [15:0] y_search_max;
    reg [11:0] y_search_max_pos;
    reg [2:0]  y_phase;                // 0:向上, 1:向下, 2:完成

    // X 搜索相关
    reg [11:0] x_peak1_pos, x_peak2_pos;
    reg [15:0] x_peak1_val, x_peak2_val;
    reg        x_found;
    reg [11:0] x_search_addr;
    reg [15:0] x_search_max;
    reg [11:0] x_search_max_pos;
    reg [2:0]  x_phase;

    // 时序逻辑
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= S_IDLE;
            cx_l       <= 0; cy_l <= 0;
            full_screen <= 0;
            // Y 信号
            y_peak1_val <= 0; y_peak1_pos <= 0;
            y_peak2_val <= 0; y_peak2_pos <= 0;
            y_found    <= 0;
            y_search_addr <= 0; y_search_max <= 0; y_search_max_pos <= 0;
            y_phase    <= 0;
            // X 信号
            x_peak1_val <= 0; x_peak1_pos <= 0;
            x_peak2_val <= 0; x_peak2_pos <= 0;
            x_found    <= 0;
            x_search_addr <= 0; x_search_max <= 0; x_search_max_pos <= 0;
            x_phase    <= 0;
        end else begin
            state <= next_state;
            case (state)
                S_IDLE: begin
                    if (vs_rise) begin
                        // 锁存中心，判断是否全屏
                        cx_l <= cx; cy_l <= cy;
                        if (cx == 0 && cy == 0) full_screen <= 1;
                        else full_screen <= 0;
                    end
                end

                S_FRAME1_WAIT: begin
                    if (frame_end) begin
                        // 准备 Y 分析：从中心向上开始
                        y_search_addr <= cy_l;
                        y_search_max  <= 0;
                        y_search_max_pos <= 0;
                        y_phase   <= 0;
                        y_found   <= 0;
                    end
                end

                S_ANALYZE_Y: begin
                    case (y_phase)
                        0: begin  // 向上找第一峰
                            if (y_search_addr > 0) begin
                                if (row_proj[y_search_addr] > y_search_max) begin
                                    y_search_max <= row_proj[y_search_addr];
                                    y_search_max_pos <= y_search_addr;
                                end
                                y_search_addr <= y_search_addr - 1;
                            end else begin
                                // 到达顶部
                                if (y_search_max > 0) begin
                                    y_peak1_val <= y_search_max;
                                    y_peak1_pos <= y_search_max_pos;
                                end else begin
                                    y_peak1_val <= 0; y_peak1_pos <= 0;
                                end
                                // 准备向下找第二峰
                                y_search_addr <= (cy_l + 1 < V_ACT) ? cy_l + 1 : V_ACT-1;
                                y_search_max <= 0;
                                y_phase <= 1;
                            end
                        end
                        1: begin  // 向下找第二峰
                            if (y_search_addr < V_ACT) begin
                                if (row_proj[y_search_addr] > y_search_max) begin
                                    y_search_max <= row_proj[y_search_addr];
                                    y_search_max_pos <= y_search_addr;
                                end
                                y_search_addr <= y_search_addr + 1;
                            end else begin
                                // 到底部
                                if (y_search_max > 0) begin
                                    y_peak2_val <= y_search_max;
                                    y_peak2_pos <= y_search_max_pos;
                                    // 相似度检查
                                    if ((y_search_max * 100) >= y_peak1_val * SIM_THRESH &&
                                        (y_peak1_val * 100) >= y_search_max * SIM_THRESH)
                                        y_found <= 1;
                                    else
                                        y_found <= 0;
                                end else begin
                                    y_peak2_val <= 0; y_peak2_pos <= 0;
                                    y_found <= 0;
                                end
                                y_phase <= 2;  // 完成
                            end
                        end
                        default: ;
                    endcase
                end

                S_FRAME2_WAIT: begin
                    if (frame_end) begin
                        // 准备 X 分析
                        x_search_addr <= cx_l;
                        x_search_max  <= 0;
                        x_phase   <= 0;
                        x_found   <= 0;
                    end
                end

                S_ANALYZE_X: begin
                    case (x_phase)
                        0: begin  // 向左找第一峰
                            if (x_search_addr > 0) begin
                                if (col_proj[x_search_addr] > x_search_max) begin
                                    x_search_max <= col_proj[x_search_addr];
                                    x_search_max_pos <= x_search_addr;
                                end
                                x_search_addr <= x_search_addr - 1;
                            end else begin
                                if (x_search_max > 0) begin
                                    x_peak1_val <= x_search_max;
                                    x_peak1_pos <= x_search_max_pos;
                                end else begin
                                    x_peak1_val <= 0; x_peak1_pos <= 0;
                                end
                                x_search_addr <= (cx_l + 1 < H_ACT) ? cx_l + 1 : H_ACT-1;
                                x_search_max <= 0;
                                x_phase <= 1;
                            end
                        end
                        1: begin  // 向右找第二峰
                            if (x_search_addr < H_ACT) begin
                                if (col_proj[x_search_addr] > x_search_max) begin
                                    x_search_max <= col_proj[x_search_addr];
                                    x_search_max_pos <= x_search_addr;
                                end
                                x_search_addr <= x_search_addr + 1;
                            end else begin
                                if (x_search_max > 0) begin
                                    x_peak2_val <= x_search_max;
                                    x_peak2_pos <= x_search_max_pos;
                                    if ((x_search_max * 100) >= x_peak1_val * SIM_THRESH &&
                                        (x_peak1_val * 100) >= x_search_max * SIM_THRESH)
                                        x_found <= 1;
                                    else
                                        x_found <= 0;
                                end else begin
                                    x_peak2_val <= 0; x_peak2_pos <= 0;
                                    x_found <= 0;
                                end
                                x_phase <= 2;
                            end
                        end
                        default: ;
                    endcase
                end

                S_OUTPUT: begin
                    // 保持输出
                end

                default: ;
            endcase
        end
    end

    // 组合逻辑：状态跳转
    always @(*) begin
        next_state = state;
        case (state)
            S_IDLE: begin
                if (vs_rise) begin
                    if (full_screen)
                        next_state = S_OUTPUT;   // 颜色无效直接输出全屏
                    else
                        next_state = S_FRAME1_WAIT;
                end
            end
            S_FRAME1_WAIT:  if (frame_end) next_state = S_ANALYZE_Y;
            S_ANALYZE_Y:    if (y_phase == 2) next_state = S_FRAME2_WAIT;
            S_FRAME2_WAIT:  if (frame_end) next_state = S_ANALYZE_X;
            S_ANALYZE_X:    if (x_phase == 2) next_state = S_OUTPUT;
            S_OUTPUT:       if (vs_rise) next_state = S_IDLE;
            default:        next_state = S_IDLE;
        endcase
    end

    // 锁存 Y 范围供第二帧使用
    always @(posedge clk) begin
        if (state == S_ANALYZE_Y && y_phase == 2) begin
            if (y_found) begin
                y1_bound <= (y_peak1_pos < y_peak2_pos) ? y_peak1_pos : y_peak2_pos;
                y2_bound <= (y_peak1_pos > y_peak2_pos) ? y_peak1_pos : y_peak2_pos;
            end else begin
                // 兜底半屏高
                if (cy_l > HALF_SCREEN_H)  y1_bound <= cy_l - HALF_SCREEN_H;
                else                       y1_bound <= 0;
                if (cy_l + HALF_SCREEN_H < V_ACT) y2_bound <= cy_l + HALF_SCREEN_H;
                else                              y2_bound <= V_ACT - 1;
            end
        end
    end

    // 最终输出赋值
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            x1 <= 0; y1 <= 0; x2 <= H_ACT-1; y2 <= V_ACT-1;
        end else if (state == S_OUTPUT) begin
            if (full_screen) begin
                x1 <= 0; x2 <= H_ACT-1;
                y1 <= 0; y2 <= V_ACT-1;
            end else begin
                // --- Y 方向 ---
                if (y_found) begin
                    y1 <= (y_peak1_pos < y_peak2_pos) ? y_peak1_pos : y_peak2_pos;
                    y2 <= (y_peak1_pos > y_peak2_pos) ? y_peak1_pos : y_peak2_pos;
                end else begin
                    // 半屏兜底
                    if (cy_l > HALF_SCREEN_H)
                        y1 <= cy_l - HALF_SCREEN_H;
                    else
                        y1 <= 0;
                    if (cy_l + HALF_SCREEN_H < V_ACT)
                        y2 <= cy_l + HALF_SCREEN_H;
                    else
                        y2 <= V_ACT - 1;
                end

                // --- X 方向 ---
                if (x_found) begin
                    x1 <= (x_peak1_pos < x_peak2_pos) ? x_peak1_pos : x_peak2_pos;
                    x2 <= (x_peak1_pos > x_peak2_pos) ? x_peak1_pos : x_peak2_pos;
                end else begin
                    // 半屏兜底
                    if (cx_l > HALF_SCREEN_W)
                        x1 <= cx_l - HALF_SCREEN_W;
                    else
                        x1 <= 0;
                    if (cx_l + HALF_SCREEN_W < H_ACT)
                        x2 <= cx_l + HALF_SCREEN_W;
                    else
                        x2 <= H_ACT - 1;
                end
            end
        end
    end

endmodule