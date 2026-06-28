`timescale 1ns / 1ps

// 3x3 高斯滤波模块 —— 修复阻塞/非阻塞赋值冲突
module gaussian_filter(
    input         video_clk,
    input         rst_n,
    input         video_vs,
    input         video_de,
    input  [7:0]  pixel_in,  // 输入灰度像素

    output        filter_de,
    output [7:0]  pixel_out // 输出高斯滤波后像素
);

// 3x3矩阵生成
wire [7:0] matrix11, matrix12, matrix13;
wire [7:0] matrix21, matrix22, matrix23;
wire [7:0] matrix31, matrix32, matrix33;
wire        matrix_de_out;

matrix_3x3#(
    .IMG_WIDTH (1920),
    .IMG_HEIGHT(1080)
) u_matrix_3x3 (
    .video_clk (video_clk),
    .rst_n     (rst_n),
    .video_vs  (video_vs),
    .video_de  (video_de),
    .video_data(pixel_in),
    .matrix_de (matrix_de_out),
    .matrix11  (matrix11),
    .matrix12  (matrix12),
    .matrix13  (matrix13),
    .matrix21  (matrix21),
    .matrix22  (matrix22),
    .matrix23  (matrix23),
    .matrix31  (matrix31),
    .matrix32  (matrix32),
    .matrix33  (matrix33)
);

// 高斯核  1 2 1
//        2 4 2
//        1 2 1   总和 16
reg [11:0] gauss_sum;

always @(posedge video_clk or negedge rst_n) begin
    if(!rst_n)
        gauss_sum <= 12'd0;
    else begin
        gauss_sum <= (matrix11)       + (matrix12<<1) + (matrix13)       +
                     (matrix21<<1)    + (matrix22<<2) + (matrix23<<1)    +
                     (matrix31)       + (matrix32<<1) + (matrix33);
    end
end

reg [7:0]  pixel_out_r;
reg        de_delay;

always @(posedge video_clk or negedge rst_n) begin
    if(!rst_n) begin
        pixel_out_r <= 8'd0;
        de_delay    <= 1'b0;
    end else begin
        pixel_out_r <= gauss_sum >> 4; // 除以16
        de_delay    <= matrix_de_out;
    end
end

assign pixel_out = pixel_out_r;
assign filter_de = de_delay;

endmodule