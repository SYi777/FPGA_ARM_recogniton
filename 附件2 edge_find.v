// This open-source top-level logic is licensed under GPLv3
// The external encrypted IP core instantiated here is closed-source proprietary IP,
// users must obtain independent commercial license from the IP vendor separately.
// GPLv3 copyleft only applies to HDL code written by the author, not third-party encrypted IP.
`timescale 1ns / 1ps

// ==========================================================
// 模块功能：基于二值边缘图像的双帧投影车牌精定位
// 第一帧：确定垂直上下边界
// 第二帧：限定行范围确定水平左右边界
// 输出最终精准车牌外接矩形
// ==========================================================
module plate_edge_box #(
    parameter H_ACT          = 1920,
    parameter V_ACT          = 1080,
    parameter HALF_SCREEN_W  = 1080,
    parameter HALF_SCREEN_H  = 540,
    parameter SIM_THRESH     = 85         // 峰对相似度阈值（%）
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        bin_vs,           // 场同步
    input  wire        bin_de,           // 数据有效
    input  wire        bin_pix,          // 二值边缘像素
    input  wire [11:0] cx,               // 颜色定位中心 X
    input  wire [11:0] cy,               // 颜色定位中心 Y
    
    output reg  [11:0] x1,               // 最终左
    output reg  [11:0] y1,               // 最终上
    output reg  [11:0] x2,               // 最终右
    output reg  [11:0] y2                // 最终下
);

// ==========================================================
// 行列像素计数器
// ==========================================================
reg [11:0] cnt_col, cnt_row;
reg        de_d0;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin cnt_col<=0; cnt_row<=0; de_d0<=0; end
    else begin
        de_d0 <= bin_de;
        if (bin_vs) begin cnt_col<=0; cnt_row<=0; end
        else if (bin_de) cnt_col <= cnt_col + 1'b1;
        if (de_d0 && !bin_de) cnt_row <= cnt_row + 1'b1;
    end
end

// ==========================================================
// 场同步上升沿
// ==========================================================
reg vs_d0;
wire vs_rise = bin_vs && !vs_d0;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) vs_d0 <=0; else vs_d0 <= bin_vs;
end

// ==========================================================
// 帧结束标志
// ==========================================================
reg frame_end;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) frame_end <=0;
    else if (vs_rise) frame_end <=0;
    else if (de_d0 && !bin_de && cnt_row == V_ACT-1) frame_end <=1;
    else frame_end <=0;
end

// ==========================================================
// 第一帧：行投影（垂直方向）
// ==========================================================
reg [15:0] row_sum_tmp;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) row_sum_tmp <=0;
    else if (vs_rise) row_sum_tmp <=0;
    else if (bin_de && bin_pix) row_sum_tmp <= row_sum_tmp +1'b1;
    else if (de_d0 && !bin_de) row_sum_tmp <=0;
end

reg [15:0] row_proj [0:V_ACT-1];
always @(posedge clk) if (de_d0 && !bin_de) row_proj[cnt_row] <= row_sum_tmp;

// ==========================================================
// 第二帧：列投影（水平方向，限定行范围）
// ==========================================================
reg [15:0] col_proj [0:H_ACT-1];
reg        col_proj_en;
reg [11:0] y1_bound, y2_bound;
integer ci;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) for(ci=0;ci<H_ACT;ci=ci+1) col_proj[ci]<=0;
    else if (vs_rise) begin
        for(ci=0;ci<H_ACT;ci=ci+1) col_proj[ci]<=0;
        col_proj_en <=0;
    end else if (bin_de && col_proj_en && cnt_row>=y1_bound && cnt_row<=y2_bound && bin_pix)
        col_proj[cnt_col] <= col_proj[cnt_col] +1'b1;
end

// ==========================================================
// 主状态机
// ==========================================================
localparam S_IDLE         = 3'd0;
localparam S_FRAME1_WAIT  = 3'd1;    // 等待第一帧
localparam S_ANALYZE_Y    = 3'd2;    // 分析 Y 边界
localparam S_FRAME2_WAIT  = 3'd3;    // 等待第二帧
localparam S_ANALYZE_X    = 3'd4;    // 分析 X 边界
localparam S_OUTPUT       = 3'd5;    // 输出结果

reg [2:0] state, next_state;

// ==========================================================
// 内部控制变量
// ==========================================================
reg        full_screen;
reg [11:0] cx_l, cy_l;
reg [11:0] y_peak1_pos, y_peak2_pos, x_peak1_pos, x_peak2_pos;
reg [15:0] y_peak1_val, y_peak2_val, x_peak1_val, x_peak2_val;
reg        y_found, x_found;
reg [11:0] y_search_addr, y_search_max_pos, x_search_addr, x_search_max_pos;
reg [15:0] y_search_max, x_search_max;
reg [2:0]  y_phase, x_phase;

// ==========================================================
// 时序控制
// ==========================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state<=S_IDLE; cx_l<=0; cy_l<=0; full_screen<=0;
    end else begin
        state <= next_state;
        case (state)
            S_IDLE: begin
                if (vs_rise) begin
                    cx_l <= cx; cy_l <= cy;
                    full_screen <= (cx==0 && cy==0);
                end
            end
            
            S_FRAME1_WAIT: begin
                if (frame_end) begin
                    y_search_addr <= cy_l;
                    y_search_max <=0;
                    y_phase <=0; y_found<=0;
                end
            end
            
            S_ANALYZE_Y: begin
                if(y_phase==0) begin // 向上搜索
                    if(y_search_addr>0) begin
                        if(row_proj[y_search_addr]>y_search_max) begin
                            y_search_max <= row_proj[y_search_addr];
                            y_search_max_pos <= y_search_addr;
                        end
                        y_search_addr <= y_search_addr -1;
                    end else begin
                        y_peak1_val <= y_search_max;
                        y_peak1_pos <= y_search_max_pos;
                        y_search_addr <= cy_l+1;
                        y_search_max <=0;
                        y_phase <=1;
                    end
                end else if(y_phase==1) begin // 向下搜索
                    if(y_search_addr < V_ACT) begin
                        if(row_proj[y_search_addr]>y_search_max) begin
                            y_search_max <= row_proj[y_search_addr];
                            y_search_max_pos <= y_search_addr;
                        end
                        y_search_addr <= y_search_addr +1;
                    end else begin
                        y_peak2_val <= y_search_max;
                        y_peak2_pos <= y_search_max_pos;
                        y_found <= ((y_search_max*100) >= y_peak1_val*SIM_THRESH) 
                                && ((y_peak1_val*100)>=y_search_max*SIM_THRESH);
                        y_phase <=2;
                    end
                end
            end
            
            S_FRAME2_WAIT: begin
                if(frame_end) begin
                    x_search_addr <= cx_l;
                    x_search_max <=0;
                    x_phase <=0; x_found<=0;
                end
            end
            
            S_ANALYZE_X: begin
                if(x_phase==0) begin // 向左搜索
                    if(x_search_addr>0) begin
                        if(col_proj[x_search_addr]>x_search_max) begin
                            x_search_max <= col_proj[x_search_addr];
                            x_search_max_pos <= x_search_addr;
                        end
                        x_search_addr <= x_search_addr -1;
                    end else begin
                        x_peak1_val <= x_search_max;
                        x_peak1_pos <= x_search_max_pos;
                        x_search_addr <= cx_l+1;
                        x_search_max <=0;
                        x_phase <=1;
                    end
                end else if(x_phase==1) begin // 向右搜索
                    if(x_search_addr < H_ACT) begin
                        if(col_proj[x_search_addr]>x_search_max) begin
                            x_search_max <= col_proj[x_search_addr];
                            x_search_max_pos <= x_search_addr;
                        end
                        x_search_addr <= x_search_addr +1;
                    end else begin
                        x_peak2_val <= x_search_max;
                        x_peak2_pos <= x_search_max_pos;
                        x_found <= ((x_search_max*100) >= x_peak1_val*SIM_THRESH) 
                                && ((x_peak1_val*100)>=x_search_max*SIM_THRESH);
                        x_phase <=2;
                    end
                end
            end
            
            S_OUTPUT: ;
        endcase
    end
end

// ==========================================================
// 组合状态跳转
// ==========================================================
always @(*) begin
    next_state = state;
    case(state)
        S_IDLE: if(vs_rise) next_state = full_screen ? S_OUTPUT : S_FRAME1_WAIT;
        S_FRAME1_WAIT: if(frame_end) next_state = S_ANALYZE_Y;
        S_ANALYZE_Y: if(y_phase==2) next_state = S_FRAME2_WAIT;
        S_FRAME2_WAIT: if(frame_end) next_state = S_ANALYZE_X;
        S_ANALYZE_X: if(x_phase==2) next_state = S_OUTPUT;
        S_OUTPUT: if(vs_rise) next_state = S_IDLE;
        default: next_state = S_IDLE;
    endcase
end

// ==========================================================
// 锁存垂直范围
// ==========================================================
always @(posedge clk) begin
    if(state==S_ANALYZE_Y && y_phase==2) begin
        if(y_found) begin
            y1_bound <= (y_peak1_pos < y_peak2_pos) ? y_peak1_pos : y_peak2_pos;
            y2_bound <= (y_peak1_pos > y_peak2_pos) ? y_peak1_pos : y_peak2_pos;
        end else begin
            y1_bound <= (cy_l > HALF_SCREEN_H) ? cy_l - HALF_SCREEN_H : 0;
            y2_bound <= (cy_l + HALF_SCREEN_H < V_ACT) ? cy_l + HALF_SCREEN_H : V_ACT-1;
        end
        col_proj_en <= 1;
    end
end

// ==========================================================
// 最终输出精准矩形
// ==========================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin x1<=0; y1<=0; x2<=H_ACT-1; y2<=V_ACT-1; end
    else if(state == S_OUTPUT) begin
        if(full_screen) begin x1<=0; x2<=H_ACT-1; y1<=0; y2<=V_ACT-1; end
        else begin
            // Y 方向输出
            if(y_found) begin
                y1 <= (y_peak1_pos < y_peak2_pos) ? y_peak1_pos : y_peak2_pos;
                y2 <= (y_peak1_pos > y_peak2_pos) ? y_peak1_pos : y_peak2_pos;
            end else begin
                y1 <= (cy_l > HALF_SCREEN_H) ? cy_l - HALF_SCREEN_H : 0;
                y2 <= (cy_l + HALF_SCREEN_H < V_ACT) ? cy_l + HALF_SCREEN_H : V_ACT-1;
            end
            
            // X 方向输出
            if(x_found) begin
                x1 <= (x_peak1_pos < x_peak2_pos) ? x_peak1_pos : x_peak2_pos;
                x2 <= (x_peak1_pos > x_peak2_pos) ? x_peak1_pos : x_peak2_pos;
            end else begin
                x1 <= (cx_l > HALF_SCREEN_W) ? cx_l - HALF_SCREEN_W : 0;
                x2 <= (cx_l + HALF_SCREEN_W < H_ACT) ? cx_l + HALF_SCREEN_W : H_ACT-1;
            end
        end
    end
end

endmodule
