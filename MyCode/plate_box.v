module plate_box_overlay(
    input               pix_clk,
    input               rst_n,

    input               i_de,
    input      [11:0]   x_act,
    input      [11:0]   y_act,

    input      [11:0]   x1,
    input      [11:0]   y1,
    input      [11:0]   x2,
    input      [11:0]   y2,

    output reg          o_de,
    output reg          o_box   // 是否画框
);

parameter THICK = 9;  // 边框厚度（可调）

wire in_box_area;
assign in_box_area =
    (x_act >= x1) && (x_act <= x2) &&
    (y_act >= y1) && (y_act <= y2);

// 四条边判断
wire top_edge    = in_box_area && (y_act >= y1) && (y_act < y1 + THICK);
wire bottom_edge = in_box_area && (y_act <= y2) && (y_act > y2 - THICK);
wire left_edge   = in_box_area && (x_act >= x1) && (x_act < x1 + THICK);
wire right_edge  = in_box_area && (x_act <= x2) && (x_act > x2 - THICK);

wire box_flag = top_edge | bottom_edge | left_edge | right_edge;

// 输出（打一拍对齐）
reg box_d;

always @(posedge pix_clk or negedge rst_n) begin
    if(!rst_n) begin
        box_d <= 0;
        o_box <= 0;
    end else begin
        box_d <= box_flag;
        o_box <= box_d;
    end
end

// DE 对齐
reg [1:0] de_pipe;
always @(posedge pix_clk or negedge rst_n) begin
    if(!rst_n) begin
        de_pipe <= 0;
        o_de <= 0;
    end else begin
        de_pipe <= {de_pipe[0], i_de};
        o_de <= de_pipe[1];
    end
end

endmodule