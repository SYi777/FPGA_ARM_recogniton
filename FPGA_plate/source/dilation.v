// 膨胀模块（3x3 全1核，连接断开的边缘）
module dilation(
    input         clk,
    input         rst_n,

    input         in_vs,
    input         in_de,
    input  [7:0]  in_data,    // 来自 sobel 二值图

    output        out_vs,
    output        out_de,
    output [7:0]  out_data    // 膨胀后图像
);

// 例化 3x3 矩阵缓存
wire [7:0] m11, m12, m13;
wire [7:0] m21, m22, m23;
wire [7:0] m31, m32, m33;
wire matrix_de;

matrix_3x3#(
    .IMG_WIDTH   ( 11'd1920 ),
    .IMG_HEIGHT  ( 11'd1080 )
)u_matrix_3x3(
    .video_clk   ( clk       ),
    .rst_n       ( rst_n     ),
    .video_vs    ( in_vs     ),
    .video_de    ( in_de     ),
    .video_data  ( in_data   ),
    .matrix_de   ( matrix_de ),
    .matrix11    ( m11       ),
    .matrix12    ( m12       ),
    .matrix13    ( m13       ),
    .matrix21    ( m21       ),
    .matrix22    ( m22       ),
    .matrix23    ( m23       ),
    .matrix31    ( m31       ),
    .matrix32    ( m32       ),
    .matrix33    ( m33       )
);

// 时序对齐
reg [2:0] vs_dly, de_dly;
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        vs_dly <= 0;
        de_dly <= 0;
    end else begin
        vs_dly <= {vs_dly[1:0], in_vs};
        de_dly <= {de_dly[1:0], in_de};
    end
end

// 3x3 全1核膨胀：只要9个像素里有1个是白的，输出就是白的
reg dil_pix;
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        dil_pix <= 0;
    else
        dil_pix <= (m11 | m12 | m13 | 
                    m21 | m22 | m23 | 
                    m31 | m32 | m33) > 0;
end

assign out_vs   = vs_dly[2];
assign out_de   = de_dly[2];
assign out_data = dil_pix ? 8'd255 : 8'd0;

endmodule