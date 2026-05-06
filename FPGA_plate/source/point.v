`timescale 1ns / 1ps

module plate_center_dot #(
    parameter DOT_SIZE = 5,      // 点的尺寸（建议奇数：1, 3, 5, 7...）
    parameter H_ACT    = 1920,   // 图像宽度
    parameter V_ACT    = 1080    // 图像高度
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        i_de,     // 输入数据有效信号
    input  wire [11:0] x_act,    // 当前扫描像素 X 坐标
    input  wire [11:0] y_act,    // 当前扫描像素 Y 坐标
    input  wire [11:0] cx,       // 颜色中心 X (来自 plate_color_center)
    input  wire [11:0] cy,       // 颜色中心 Y
    input  wire        center_vld,// 中心坐标有效信号 (valid)
    output reg         o_dot      // 输出：1=当前像素是中心点，0=背景
);

    // 计算半宽 (例如 DOT_SIZE=5 -> HALF=2，形成 5x5 的方块)
    localparam HALF_DOT = (DOT_SIZE - 1) / 2;

    // 边界保护后的坐标（防止中心在边缘时溢出）
    wire [11:0] x_start = (cx > HALF_DOT) ? (cx - HALF_DOT) : 12'd0;
    wire [11:0] x_end   = (cx + HALF_DOT < H_ACT) ? (cx + HALF_DOT) : (H_ACT - 1'b1);
    wire [11:0] y_start = (cy > HALF_DOT) ? (cy - HALF_DOT) : 12'd0;
    wire [11:0] y_end   = (cy + HALF_DOT < V_ACT) ? (cy + HALF_DOT) : (V_ACT - 1'b1);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            o_dot <= 1'b0;
        end else begin
            // 只有在 DE 有效、中心坐标有效、且当前扫描坐标在范围内时才拉高
            if (i_de && center_vld && 
                x_act >= x_start && x_act <= x_end &&
                y_act >= y_start && y_act <= y_end) begin
                o_dot <= 1'b1;
            end else begin
                o_dot <= 1'b0;
            end
        end
    end

endmodule