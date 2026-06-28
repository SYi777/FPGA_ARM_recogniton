`timescale 1ns / 1ps

module erosion(
    input         clk,
    input         rst_n,

    input         in_vs,
    input         in_de,
    input  [7:0]  in_data,

    output        out_vs,
    output        out_de,
    output reg [7:0] out_data
);

// 例化 3x3 矩阵生成
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

// 组合逻辑：找 3x3 最小值
wire [7:0] min1 = (m11 < m12) ? m11 : m12;
wire [7:0] min2 = (min1 < m13) ? min1 : m13;
wire [7:0] min3 = (min2 < m21) ? min2 : m21;
wire [7:0] min4 = (min3 < m22) ? min3 : m22;
wire [7:0] min5 = (min4 < m23) ? min4 : m23;
wire [7:0] min6 = (min5 < m31) ? min5 : m31;
wire [7:0] min7 = (min6 < m32) ? min6 : m32;
wire [7:0] min_val = (min7 < m33) ? min7 : m33;

// 时序对齐 (延迟 3 拍，与 matrix_3x3 内部延迟匹配)
reg [2:0] de_dly;
reg [2:0] vs_dly;

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        de_dly <= 0;
        vs_dly <= 0;
        out_data <= 0;
    end else begin
        de_dly <= {de_dly[1:0], matrix_de};
        vs_dly <= {vs_dly[1:0], in_vs};
        out_data <= min_val;
    end
end

assign out_de = de_dly[2];
assign out_vs = vs_dly[2];

endmodule