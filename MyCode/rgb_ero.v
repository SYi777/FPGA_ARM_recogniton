`timescale 1ns / 1ps

module new_erosion #(
    parameter ERODE_THR = 4   // 黑色个数阈值：3x3 中黑点数 ≥ 此值才输出 0
)(
    input         clk,
    input         rst_n,
    input         in_vs,
    input         in_de,
    input  [7:0]  in_data,
    output        out_vs,
    output        out_de,
    output reg [7:0] out_data
);

// 1. 3x3 矩阵生成
wire [7:0] m11, m12, m13;
wire [7:0] m21, m22, m23;
wire [7:0] m31, m32, m33;
wire        matrix_de;

matrix_3x3 #(
    .IMG_WIDTH  (11'd1920),
    .IMG_HEIGHT (11'd1080)
) u_matrix (
    .video_clk  (clk),
    .rst_n      (rst_n),
    .video_vs   (in_vs),
    .video_de   (in_de),
    .video_data (in_data),
    .matrix_de  (matrix_de),
    .matrix11   (m11),.matrix12 (m12),.matrix13 (m13),
    .matrix21   (m21),.matrix22 (m22),.matrix23 (m23),
    .matrix31   (m31),.matrix32 (m32),.matrix33 (m33)
);

// 2. 统计 3x3 中黑色像素个数（假设 0 为黑，255 为白）
wire [3:0] black_cnt = (m11 == 0) + (m12 == 0) + (m13 == 0) +
                       (m21 == 0) + (m22 == 0) + (m23 == 0) +
                       (m31 == 0) + (m32 == 0) + (m33 == 0);

// 3. 腐蚀结果：若黑色个数 >= 阈值，输出黑（0），否则输出白（255）
wire [7:0] min_val = (black_cnt >= ERODE_THR) ? 8'd0 : 8'd255;

// 4. 时序对齐（与标准矩阵延迟匹配）
reg [2:0] de_dly;
reg [2:0] vs_dly;

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        de_dly   <= 0;
        vs_dly   <= 0;
        out_data <= 0;
    end else begin
        de_dly   <= {de_dly[1:0], matrix_de};
        vs_dly   <= {vs_dly[1:0], in_vs};
        out_data <= min_val;
    end
end

assign out_de = de_dly[2];
assign out_vs = vs_dly[2];

endmodule