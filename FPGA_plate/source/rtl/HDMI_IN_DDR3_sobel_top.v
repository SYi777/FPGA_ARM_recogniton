`timescale 1ns / 1ps

module HDMI_IN_DDR3_sobel_top#(
	parameter MEM_ROW_ADDR_WIDTH   = 15         ,
	parameter MEM_COL_ADDR_WIDTH   = 10         ,
	parameter MEM_BADDR_WIDTH      = 3          ,
	parameter MEM_DQ_WIDTH         =  32        ,
	parameter MEM_DQS_WIDTH        =  32/8
)(
	input                                sys_clk              ,//27Mhz
    input                                clk_p ,
    input                                clk_n ,
    input                                rst_in ,

//DDR
    output                               mem_rst_n                 ,
    output                               mem_ck                    ,
    output                               mem_ck_n                  ,
    output                               mem_cke                   ,
    output                               mem_cs_n                  ,
    output                               mem_ras_n                 ,
    output                               mem_cas_n                 ,
    output                               mem_we_n                  ,
    output                               mem_odt                   ,
    output      [MEM_ROW_ADDR_WIDTH-1:0] mem_a                     ,
    output      [MEM_BADDR_WIDTH-1:0]    mem_ba                    ,
    inout       [MEM_DQ_WIDTH/8-1:0]     mem_dqs                   ,
    inout       [MEM_DQ_WIDTH/8-1:0]     mem_dqs_n                 ,
    inout       [MEM_DQ_WIDTH-1:0]       mem_dq                    ,
    output      [MEM_DQ_WIDTH/8-1:0]     mem_dm                    ,
    output reg                           heart_beat_led            ,
    output                               ddr_init_done             ,
    output                               init_over_rx              ,
//MS72xx       
    output                               rstn_out                  ,
    output                               hd_scl                ,
    inout                                hd_sda                ,
    output                               hdmi_int_led              ,//HDMI_OUT初始化完成

    //HDMI_in
    input             pixclk_in    ,                            
    input             vs_in    , 
    input             hs_in    , 
    input             de_in    ,
    input     [7:0]   r_in    , 
    input     [7:0]   g_in    , 
    input     [7:0]   b_in    , 
//HDMI_OUT
    output                               pix_clk   /*synthesis PAP_MARK_DEBUG="1"*/                ,//pixclk                           
    output    reg                           vs_out    /*synthesis PAP_MARK_DEBUG="1"*/                , 
    output    reg                           hs_out    /*synthesis PAP_MARK_DEBUG="1"*/                , 
    output    reg                           de_out    /*synthesis PAP_MARK_DEBUG="1"*/                ,
    output    reg    [7:0]                  r_out     /*synthesis PAP_MARK_DEBUG="1"*/                , 
    output    reg    [7:0]                  g_out     /*synthesis PAP_MARK_DEBUG="1"*/                , 
    output    reg    [7:0]                  b_out     /*synthesis PAP_MARK_DEBUG="1"*/    
);
/////////////////////////////////////////////////////////////////////////////////////
// ENABLE_DDR
    parameter CTRL_ADDR_WIDTH = MEM_ROW_ADDR_WIDTH + MEM_BADDR_WIDTH + MEM_COL_ADDR_WIDTH;//28
    parameter TH_1S = 27'd33000000;
/////////////////////////////////////////////////////////////////////////////////////
    reg  [15:0]                 rstn_1ms            ;
    wire[15:0]                  o_rgb565            ;

    wire        de_o;               // DDR 输出有效 DE
    wire [7:0]  rgb_data_r;         // 最终 R
    wire [7:0]  rgb_data_g;         // 最终 G
    wire [7:0]  rgb_data_b;         // 最终 B

//axi bus   
    wire [CTRL_ADDR_WIDTH-1:0]  axi_awaddr                 ;
    wire                        axi_awuser_ap              ;
    wire [3:0]                  axi_awuser_id              ;
    wire [3:0]                  axi_awlen                  ;
    wire                        axi_awready                ;/*synthesis PAP_MARK_DEBUG="1"*/
    wire                        axi_awvalid                ;/*synthesis PAP_MARK_DEBUG="1"*/
    wire [MEM_DQ_WIDTH*8-1:0]   axi_wdata                  ;
    wire [MEM_DQ_WIDTH*8/8-1:0] axi_wstrb                  ;
    wire                        axi_wready                 ;/*synthesis PAP_MARK_DEBUG="1"*/
    wire [3:0]                  axi_wusero_id              ;
    wire                        axi_wusero_last            ;
    wire [CTRL_ADDR_WIDTH-1:0]  axi_araddr                 ;
    wire                        axi_aruser_ap              ;
    wire [3:0]                  axi_aruser_id              ;
    wire [3:0]                  axi_arlen                  ;
    wire                        axi_arready                ;/*synthesis PAP_MARK_DEBUG="1"*/
    wire                        axi_arvalid                ;/*synthesis PAP_MARK_DEBUG="1"*/
    wire [MEM_DQ_WIDTH*8-1:0]   axi_rdata                   /* synthesis syn_keep = 1 */;
    wire                        axi_rvalid                  /* synthesis syn_keep = 1 */;
    wire [3:0]                  axi_rid                    ;
    wire                        axi_rlast                  ;
    reg  [26:0]                 cnt                        ;
    reg  [15:0]                 cnt_1                      ;
/////////////////////////////////////////////////////////////////////////////////////
//PLL
pll pll_gen_clk (
    .clkin1   (  sys_clk    ),//27MHz
    .clkout0  (  pix_clk    ),//148.5

    .lock (  locked     )
);


cfg_pll cfg_pll_inst (
  .clkout0(cfg_clk),    // output
  .lock(),          // output
  .clkin1(sys_clk)       // input
);




ms72xx_ctl ms72xx_ctl(
    .clk         (  cfg_clk    ), //input       clk,
    .rst_n       (  rstn_out   ), //input       rstn,
           
    .init_over_rx(  rx_init_done),                 
    .init_over   (  init_over  ), //output      init_over,
    .iic_scl     (  hd_scl    ), //output      iic_scl,
    .iic_sda     (  hd_sda    )  //inout       iic_sda
);
    assign   init_over_rx = rx_init_done;
   assign    hdmi_int_led    =    init_over; 
    
    always @(posedge cfg_clk)
    begin
    	if(!locked)
    	    rstn_1ms <= 16'd0;
    	else
    	begin
    		if(rstn_1ms == 16'h2710)
    		    rstn_1ms <= rstn_1ms;
    		else
    		    rstn_1ms <= rstn_1ms + 1'b1;
    	end
    end
    



    reg    rstn_d0;
    reg    rstn_d1;




    assign rstn_out = (rstn_1ms == 16'h2710);


 reg  rst_reg ;
    always @ (posedge sys_clk )
        if (~rst_in)
            rst_reg <= 1'b1 ;
        else
            rst_reg <= 1'b0 ;

wire    [15:0]    hdmi_data_in;
assign    hdmi_data_in = {r_in[7:3],g_in[7:2],b_in[7:3]};


wire    vs_reg;
wire    hs_reg;
wire    rd_en ;


// Gamma 校正
wire [7:0] r_gamma, g_gamma, b_gamma;
wire       de_gamma_r, de_gamma_g, de_gamma_b;

// R 通道 Gamma
gamma_lookuptable u_gamma_r (
    .video_clk   (pixclk_in),
    .video_data  (r_in),
    .video_de    (de_in),
    .gamma_de    (de_gamma_r),
    .gamma_data  (r_gamma)
);

// G 通道 Gamma
gamma_lookuptable u_gamma_g (
    .video_clk   (pixclk_in),
    .video_data  (g_in),
    .video_de    (de_in),
    .gamma_de    (de_gamma_g),
    .gamma_data  (g_gamma)
);

// B 通道 Gamma
gamma_lookuptable u_gamma_b (
    .video_clk   (pixclk_in),
    .video_data  (b_in),
    .video_de    (de_in),
    .gamma_de    (de_gamma_b),
    .gamma_data  (b_gamma)
);

//灰度化
wire    y_vs;
wire    y_de;
wire    y_hs;
wire    [7:0]    y_data;

RGB2YCbCr RGB2YCbCr_inst
    (
    .clk(pixclk_in),              // input
    .rst_n(rstn_out),          // input
    .vsync_in(vs_in),    // input
    .hsync_in(de_in),    // input
    .de_in(de_gamma_g), // Gamma 后的 DE 对齐
    .red(r_gamma[7:3]),  // Gamma 后的 R (取高5位)
    .green(g_gamma[7:2]),// Gamma 后的 G (取高6位)
    .blue(b_gamma[7:3]), // Gamma 后的 B (取高5位)
    .vsync_out(y_vs),  // output
    .hsync_out(y_hs),  // output
    .de_out(y_de),        // output
    .y(y_data),                  // output[7:0]
    .cb(),                // output[7:0]
    .cr()                 // output[7:0]
);

wire [7:0]  gauss_data;
wire        gauss_de;
wire        gauss_vs;

gaussian_filter u_gaussian_filter(
    .video_clk (pixclk_in),
    .rst_n     (rstn_out),
    .video_vs  (y_vs),
    .video_de  (y_de),
    .pixel_in  (y_data),    // 灰度图输入

    .filter_de (gauss_de),
    .pixel_out (gauss_data) // 高斯滤波输出
);

assign gauss_vs = y_vs;

wire    [7:0]    matrix11;
wire    [7:0]    matrix12;
wire    [7:0]    matrix13;
                         
wire    [7:0]    matrix21;
wire    [7:0]    matrix22;
wire    [7:0]    matrix23;
    		          
wire    [7:0]    matrix31;
wire    [7:0]    matrix32;
wire    [7:0]    matrix33;
wire             matrix_de;
//3x3矩阵
matrix_3x3#(
    .IMG_WIDTH   ( 11'd1920 ),
    .IMG_HEIGHT  ( 11'd1080 )
)u_matrix_3x3(
    .video_clk   ( pixclk_in       ),
    .rst_n       ( rstn_out   ),
    .video_vs    ( gauss_vs        ),
    .video_de    ( gauss_de        ),
    .video_data  ( gauss_data      ),
    .matrix_de   ( matrix_de   ),
    .matrix11    ( matrix11    ),
    .matrix12    ( matrix12    ),
    .matrix13    ( matrix13    ),
    .matrix21    ( matrix21    ),
    .matrix22    ( matrix22    ),
    .matrix23    ( matrix23    ),
    .matrix31    ( matrix31    ),
    .matrix32    ( matrix32    ),
    .matrix33    ( matrix33    )
);

//sobel算子
wire    [7:0]    sobel_data;
wire             sobel_vs  ;
wire             sobel_de  ;
wire             sobel_hs  ;
sobel#(
    .SOBEL_THRESHOLD ( 73 )
)u_sobel(
    .video_clk  ( pixclk_in  ),
    .rst_n      ( rstn_out      ),
    .matrix_de  ( matrix_de  ),
    .matrix_vs  ( gauss_vs  ),
    .matrix11   ( matrix11   ),
    .matrix12   ( matrix12   ),
    .matrix13   ( matrix13   ),
    .matrix21   ( matrix21   ),
    .matrix22   ( matrix22   ),
    .matrix23   ( matrix23   ),
    .matrix31   ( matrix31   ),
    .matrix32   ( matrix32   ),
    .matrix33   ( matrix33   ),
    .sobel_vs   ( sobel_vs   ),
    .sobel_de   ( sobel_de   ),
    .sobel_data  ( sobel_data  )
);

// 膨胀
wire             dil_vs;
wire             dil_de;
wire    [7:0]    dil_data;

dilation u_dilation(
    .clk        (pixclk_in),
    .rst_n      (rstn_out),

    .in_vs      (sobel_vs),
    .in_de      (sobel_de),
    .in_data    (sobel_data),

    .out_vs     (dil_vs),
    .out_de     (dil_de),
    .out_data   (dil_data)
);

// 第一次腐蚀
wire             ero1_vs;
wire             ero1_de;
wire    [7:0]    ero1_data;

erosion u_ero1(
    .clk        (pixclk_in),
    .rst_n      (rstn_out),
    .in_vs      (dil_vs),
    .in_de      (dil_de),
    .in_data    (dil_data),
    .out_vs     (ero1_vs),
    .out_de     (ero1_de),
    .out_data   (ero1_data)
);

// 第二次腐蚀
wire             ero2_vs;
wire             ero2_de;
wire    [7:0]    ero2_data;

erosion u_ero2(
    .clk        (pixclk_in),
    .rst_n      (rstn_out),
    .in_vs      (ero1_vs),
    .in_de      (ero1_de),
    .in_data    (ero1_data),
    .out_vs     (ero2_vs),
    .out_de     (ero2_de),
    .out_data   (ero2_data)
);

// 声明最终形态学输出信号 (用于DDR写入和边缘检测)
wire             ero_final_vs;
wire             ero_final_de;
wire    [7:0]    ero_final_data;

assign ero_final_vs = ero1_vs;
assign ero_final_de = ero1_de;
assign ero_final_data = ero1_data;

// 颜色中心定位模块
wire [11:0] pcc_cx;
wire [11:0] pcc_cy;
wire        pcc_valid;
wire [11:0] pcc_left;
wire [11:0] pcc_right;
wire [11:0] pcc_top;
wire [11:0] pcc_bottom;

wire pcc_vs = vs_in; 
wire pcc_de = de_gamma_g;

plate_color_center_rgb_ratio #(
    // 图像分辨率
    .H_ACT          ( 1920   ),
    .V_ACT          ( 1080   ),
    .BORDER         ( 128    ),

    // 蓝牌 RGB 比例系数
    .BLUE_MUL       ( 4      ),
    .BLUE_DIV       ( 5      ),
    .BLUE_MIN_B     ( 135     ),

    // 绿牌 RGB 比例系数
    .GREEN_MUL      ( 8      ),
    .GREEN_DIV      ( 9      ),
    .GREEN_MIN_G    ( 140     ),

    // 黄牌 RGB 比例系数
    .YELLOW_MUL     ( 3      ),
    .YELLOW_DIV     ( 1      ),
    .YELLOW_MIN_R   ( 80     ),
    .YELLOW_MIN_G   ( 80     ),

    // 滑动窗口边界检测
    .WINDOW_SIZE    ( 11     ),
    .AVG_TH_HIGH    ( 80     ),
    .AVG_TH_LOW     ( 30     ),

    // 车牌长宽比约束
    .MIN_ASPECT     ( 3      ),
    .MAX_ASPECT     ( 5      )
) u_plate_color_center (
    .clk            ( pixclk_in   ),
    .rst_n          ( rstn_out    ),
    .bin_vs         ( vs_in       ),
    .bin_de         ( de_gamma_g  ),   // Gamma 对齐后的 DE
    .r              ( r_gamma     ),
    .g              ( g_gamma     ),
    .b              ( b_gamma     ),
    .cx             ( pcc_cx      ),
    .cy             ( pcc_cy      ),
    .valid          ( pcc_valid   ),
    .left           ( pcc_left    ),
    .right          ( pcc_right   ),
    .top            ( pcc_top     ),
    .bottom         ( pcc_bottom  )
);

// 边缘定位模块
wire [11:0] plate_x1, plate_x2, plate_y1, plate_y2;

plate_edge_box #(
    .H_ACT          ( 1920 ),
    .V_ACT          ( 1080 ),
    .HALF_SCREEN_W  ( 960  ),
    .HALF_SCREEN_H  ( 540  ),
    .SIM_THRESH     ( 85   )
) u_plate_edge_box (
    .clk            ( pixclk_in     ),
    .rst_n          ( rstn_out      ),
    .bin_vs         ( ero_final_vs  ),
    .bin_de         ( ero_final_de  ),
    .bin_pix        ( ero_final_data > 8'd127 ),
    .cx             ( pcc_cx        ),
    .cy             ( pcc_cy        ),
    .x1             ( plate_x1      ),
    .y1             ( plate_y1      ),
    .x2             ( plate_x2      ),
    .y2             ( plate_y2      )
);

// 帧锁存，保证一帧内坐标稳定
reg [11:0] color_x1_latch, color_y1_latch, color_x2_latch, color_y2_latch;
reg [11:0] edge_x1_latch,  edge_y1_latch,  edge_x2_latch,  edge_y2_latch;
reg [11:0] center_cx_latch, center_cy_latch;
reg        center_vld_latch;

// 输入帧场同步边沿检测
reg vs_in_d0;
wire vs_in_rise = vs_in && !vs_in_d0;
always @(posedge pixclk_in or negedge rstn_out) begin
    if(!rstn_out) vs_in_d0 <= 0;
    else vs_in_d0 <= vs_in;
end

// 帧结束时锁存坐标
always @(posedge pixclk_in or negedge rstn_out) begin
    if(!rstn_out) begin
        color_x1_latch <= 0; color_y1_latch <= 0;
        color_x2_latch <= 0; color_y2_latch <= 0;
        edge_x1_latch  <= 0; edge_y1_latch  <= 0;
        edge_x2_latch  <= 0; edge_y2_latch  <= 0;
        center_cx_latch <= 0; center_cy_latch <= 0;
        center_vld_latch <= 0;
    end else if(vs_in_rise) begin // 新帧开始时，锁存上一帧的最终结果
        color_x1_latch <= pcc_left;
        color_y1_latch <= pcc_top;
        color_x2_latch <= pcc_right;
        color_y2_latch <= pcc_bottom;
        edge_x1_latch  <= plate_x1;
        edge_y1_latch  <= plate_y1;
        edge_x2_latch  <= plate_x2;
        edge_y2_latch  <= plate_y2;
        center_cx_latch <= pcc_cx;
        center_cy_latch <= pcc_cy;
        center_vld_latch <= pcc_valid;
    end
end

// 跨时钟域同步逻辑
// 同步寄存器（仅声明一次）
reg [11:0] color_x1_sync1, color_x1_sync2;
reg [11:0] color_y1_sync1, color_y1_sync2;
reg [11:0] color_x2_sync1, color_x2_sync2;
reg [11:0] color_y2_sync1, color_y2_sync2;

reg [11:0] edge_x1_sync1, edge_x1_sync2;
reg [11:0] edge_y1_sync1, edge_y1_sync2;
reg [11:0] edge_x2_sync1, edge_x2_sync2;
reg [11:0] edge_y2_sync1, edge_y2_sync2;

reg [11:0] center_cx_sync1, center_cx_sync2;
reg [11:0] center_cy_sync1, center_cy_sync2;
reg        center_vld_sync1, center_vld_sync2, center_vld_sync3;

// 唯一的同步always块
always @(posedge pix_clk) begin
    // 颜色边界同步
    color_x1_sync1 <= color_x1_latch;
    color_x1_sync2 <= color_x1_sync1;
    color_y1_sync1 <= color_y1_latch;
    color_y1_sync2 <= color_y1_sync1;
    color_x2_sync1 <= color_x2_latch;
    color_x2_sync2 <= color_x2_sync1;
    color_y2_sync1 <= color_y2_latch;
    color_y2_sync2 <= color_y2_sync1;

    // 边缘边界同步
    edge_x1_sync1 <= edge_x1_latch;
    edge_x1_sync2 <= edge_x1_sync1;
    edge_y1_sync1 <= edge_y1_latch;
    edge_y1_sync2 <= edge_y1_sync1;
    edge_x2_sync1 <= edge_x2_latch;
    edge_x2_sync2 <= edge_x2_sync1;
    edge_y2_sync1 <= edge_y2_latch;
    edge_y2_sync2 <= edge_y2_sync1;

    // 中心坐标同步
    center_cx_sync1 <= center_cx_latch;
    center_cx_sync2 <= center_cx_sync1;
    center_cy_sync1 <= center_cy_latch;
    center_cy_sync2 <= center_cy_sync1;

    // 有效信号同步
    center_vld_sync1 <= center_vld_latch;
    center_vld_sync2 <= center_vld_sync1;
    center_vld_sync3 <= center_vld_sync2;
end
localparam BORDER = 128;
// ==================================================================
// 加权平均流水线 + 大框/小框选择
// ==================================================================
parameter W_COLOR = 9;                  // 颜色权重
parameter W_EDGE  = 1;                  // 边缘权重
localparam W_TOTAL = W_COLOR + W_EDGE;

// 同步后的坐标
wire [11:0] color_x1_final = color_x1_sync2;
wire [11:0] color_y1_final = color_y1_sync2;
wire [11:0] color_x2_final = color_x2_sync2;
wire [11:0] color_y2_final = color_y2_sync2;
wire [11:0] edge_x1_final  = edge_x1_sync2;
wire [11:0] edge_y1_final  = edge_y1_sync2;
wire [11:0] edge_x2_final  = edge_x2_sync2;
wire [11:0] edge_y2_final  = edge_y2_sync2;

// 第一拍：乘加
reg [23:0] prod_x1, prod_y1, prod_x2, prod_y2;
reg        prod_valid1, prod_valid2;

always @(posedge pix_clk) begin
    prod_x1 <= color_x1_final * W_COLOR + edge_x1_final * W_EDGE;
    prod_y1 <= color_y1_final * W_COLOR + edge_y1_final * W_EDGE;
    prod_x2 <= color_x2_final * W_COLOR + edge_x2_final * W_EDGE;
    prod_y2 <= color_y2_final * W_COLOR + edge_y2_final * W_EDGE;
    prod_valid1 <= center_vld_sync2;
    prod_valid2 <= prod_valid1;
end

// 第二拍：除法，得到加权小框
reg [11:0] weighted_x1, weighted_y1, weighted_x2, weighted_y2;
reg        draw_valid;

always @(posedge pix_clk) begin
    weighted_x1 <= prod_x1 / W_TOTAL;
    weighted_y1 <= prod_y1 / W_TOTAL;
    weighted_x2 <= prod_x2 / W_TOTAL;
    weighted_y2 <= prod_y2 / W_TOTAL;
    draw_valid  <= prod_valid2;
end

// 固定大框坐标（内部有效区域）
wire [11:0] big_x1 = BORDER;
wire [11:0] big_y1 = BORDER;
wire [11:0] big_x2 = H_ACT - BORDER - 1;
wire [11:0] big_y2 = V_ACT - BORDER - 1;

// 最终画框坐标选择：valid用小框，无效用大框
wire [11:0] draw_x1 = draw_valid ? weighted_x1 : big_x1;
wire [11:0] draw_y1 = draw_valid ? weighted_y1 : big_y1;
wire [11:0] draw_x2 = draw_valid ? weighted_x2 : big_x2;
wire [11:0] draw_y2 = draw_valid ? weighted_y2 : big_y2;

// 画框叠加模块
wire box_flag, box_de;

plate_box_overlay u_plate_box(
    .pix_clk ( pix_clk       ),
    .rst_n   ( ddr_init_done ),
    .i_de    ( de_o          ),
    .x_act   ( act_x         ),
    .y_act   ( act_y         ),
    .x1      ( draw_x1       ),
    .y1      ( draw_y1       ),
    .x2      ( draw_x2       ),
    .y2      ( draw_y2       ),
    .o_de    ( box_de        ),
    .o_box   ( box_flag      )
);

// 画中心点模块
wire dot_flag;

// 同步后的中心坐标
wire [11:0] dot_cx = center_cx_sync2;
wire [11:0] dot_cy = center_cy_sync2;
wire        dot_vld = center_vld_sync2 || center_vld_sync3;

plate_center_dot #(
    .DOT_SIZE   ( 10      ),
    .H_ACT      ( 1920   ),
    .V_ACT      ( 1080   )
) u_plate_center_dot (
    .clk        ( pix_clk       ),
    .rst_n      ( ddr_init_done ),
    .i_de       ( de_o          ),
    .x_act      ( act_x         ),
    .y_act      ( act_y         ),
    .cx         ( dot_cx        ),
    .cy         ( dot_cy        ),
    .center_vld ( dot_vld       ),
    .o_dot      ( dot_flag      )
);

// DDR3读写控制（完全保留原有逻辑，无修改）
wire [15:0] write_data;
assign write_data = {r_gamma[7:3], g_gamma[7:2], b_gamma[7:3]};

fram_buf fram_buf(
    .ddr_clk        (  core_clk             ),
    .ddr_rstn       (  ddr_init_done        ),
    .vin_clk        (  pixclk_in         ),
    .wr_fsync       (  ~vs_in           ),
    .wr_en          (  de_gamma_g           ),
    .wr_data        (  write_data             ),
    .vout_clk       (  pix_clk              ),
    .rd_fsync       (  vs_reg               ),
    .rd_en          (  rd_en                ),
    .vout_de        (  de_o               ),
    .vout_data      (  o_rgb565             ),
    .init_done      (  init_done            ),
    .axi_awaddr     (  axi_awaddr           ),
    .axi_awid       (  axi_awuser_id        ),
    .axi_awlen      (  axi_awlen            ),
    .axi_awsize     (                       ),
    .axi_awburst    (                       ),
    .axi_awready    (  axi_awready          ),
    .axi_awvalid    (  axi_awvalid          ),
    .axi_wdata      (  axi_wdata            ),
    .axi_wstrb      (  axi_wstrb            ),
    .axi_wlast      (  axi_wusero_last      ),
    .axi_wvalid     (                       ),
    .axi_wready     (  axi_wready           ),
    .axi_bid        (  4'd0                 ),
    .axi_araddr     (  axi_araddr           ),
    .axi_arid       (  axi_aruser_id        ),
    .axi_arlen      (  axi_arlen            ),
    .axi_arsize     (                       ),
    .axi_arburst    (                       ),
    .axi_arvalid    (  axi_arvalid          ),
    .axi_arready    (  axi_arready          ),
    .axi_rready     (                       ),
    .axi_rdata      (  axi_rdata            ),
    .axi_rvalid     (  axi_rvalid           ),
    .axi_rlast      (  axi_rlast            ),
    .axi_rid        (  axi_rid              )
);

// 最终图像输出叠加
parameter COLOR_DOT = 24'hFF0000; // 红色中心点
parameter COLOR_BOX = 24'hFF0000; // 绿色车牌框

// 优先级：Dot > Box > 背景图像
wire [23:0] final_rgb = (dot_flag) ? COLOR_DOT : 
                         (box_flag) ? COLOR_BOX : 
                         {o_rgb565[15:11], 3'd0, o_rgb565[10:5], 2'd0, o_rgb565[4:0], 3'd0};

always @(posedge pix_clk) begin
    vs_out <= vs_reg;
    hs_out <= hs_reg;
    de_out <= de_o;
    r_out  <= final_rgb[23:16];
    g_out  <= final_rgb[15:8];
    b_out  <= final_rgb[7:0];
end

/////////////////////////////////////////////////////////////////////////////////////
// 时序生成模块
/////////////////////////////////////////////////////////////////////////////////////
parameter V_TOTAL = 12'd1125;
parameter V_FP = 12'd4;
parameter V_BP = 12'd36;
parameter V_SYNC = 12'd5;
parameter V_ACT = 12'd1080;
parameter H_TOTAL = 12'd2200;
parameter H_FP = 12'd88;
parameter H_BP = 12'd148;
parameter H_SYNC = 12'd44;
parameter H_ACT = 12'd1920;
parameter HV_OFFSET = 12'd0;   
parameter   X_WIDTH = 4'd12;
parameter   Y_WIDTH = 4'd12; 

wire [X_WIDTH - 1'b1:0]     act_x      ;
wire [Y_WIDTH - 1'b1:0]     act_y      ;  

sync_vg #(
    .X_BITS               (  X_WIDTH              ), 
    .Y_BITS               (  Y_WIDTH              ),
    .V_TOTAL              (  V_TOTAL              ),
    .V_FP                 (  V_FP                 ),
    .V_BP                 (  V_BP                 ),
    .V_SYNC               (  V_SYNC               ),
    .V_ACT                (  V_ACT                ),
    .H_TOTAL              (  H_TOTAL              ),
    .H_FP                 (  H_FP                 ),
    .H_BP                 (  H_BP                 ),
    .H_SYNC               (  H_SYNC               ),
    .H_ACT                (  H_ACT                )
) sync_vg                                         
(                                                 
    .clk                  (  pix_clk               ),
    .rstn                 (  ddr_init_done         ),
    .vs_out               (  vs_reg                ),
    .hs_out               (  hs_reg                ),
    .de_out               (  rd_en                 ),
    .x_act                (  act_x                 ),
    .y_act                (  act_y                 )
); 

////////////////////////////////////////////////////////////////////////////////////////////
// DDR3 PHY 相关
////////////////////////////////////////////////////////////////////////////////////////////
wire clk_125Mhz ;

GTP_INBUFGDS #(
    .IOSTANDARD("DEFAULT"),
    .TERM_DIFF("ON")
) u_gtp (
    .O(clk_125Mhz),
    .I(clk_p),
    .IB(clk_n)
);

wire core_clk;
wire pll_lock;
wire phy_pll_lock;
wire gpll_lock;
wire rst_gpll_lock;
wire ddrphy_cpd_lock;

ddr3_test u_ddr3_test_h (
    .ref_clk                   (clk_125Mhz            ),
    .resetn                    (rstn_out               ),
    .ddr_init_done             (ddr_init_done          ),
    .pll_lock                  (pll_lock               ),
    .core_clk                  (core_clk               ),
    .phy_pll_lock              (phy_pll_lock           ),
    .gpll_lock                 (gpll_lock              ),
    .rst_gpll_lock             (rst_gpll_lock          ),
    .ddrphy_cpd_lock           (ddrphy_cpd_lock        ),
    .axi_awaddr                (axi_awaddr             ),
    .axi_awuser_ap             (1'b0                   ),
    .axi_awuser_id             (axi_awuser_id          ),
    .axi_awlen                 (axi_awlen              ),
    .axi_awready               (axi_awready            ),
    .axi_awvalid               (axi_awvalid            ),
    .axi_wdata                 (axi_wdata              ),
    .axi_wstrb                 (axi_wstrb              ),
    .axi_wready                (axi_wready             ),
    .axi_wusero_id             (                       ),
    .axi_wusero_last           (axi_wusero_last        ),
    .axi_araddr                (axi_araddr             ),
    .axi_aruser_ap             (1'b0                   ),
    .axi_aruser_id             (axi_aruser_id          ),
    .axi_arlen                 (axi_arlen              ),
    .axi_arready               (axi_arready            ),
    .axi_arvalid               (axi_arvalid            ),
    .axi_rdata                 (axi_rdata              ),
    .axi_rid                   (axi_rid                ),
    .axi_rlast                 (axi_rlast              ),
    .axi_rvalid                (axi_rvalid             ),
    .apb_clk                   (1'b0                   ),
    .apb_rst_n                 (1'b1                   ),
    .apb_sel                   (1'b0                   ),
    .apb_enable                (1'b0                   ),
    .apb_addr                  (8'b0                   ),
    .apb_write                 (1'b0                   ),
    .apb_ready                 (                       ),
    .apb_wdata                 (16'b0                  ),
    .apb_rdata                 (                       ),
    .mem_rst_n                 (mem_rst_n              ),
    .mem_ck                    (mem_ck                 ),
    .mem_ck_n                  (mem_ck_n               ),
    .mem_cke                   (mem_cke                ),
    .mem_cs_n                  (mem_cs_n               ),
    .mem_ras_n                 (mem_ras_n              ),
    .mem_cas_n                 (mem_cas_n              ),
    .mem_we_n                  (mem_we_n               ),
    .mem_odt                   (mem_odt                ),
    .mem_a                     (mem_a                  ),
    .mem_ba                    (mem_ba                 ),
    .mem_dqs                   (mem_dqs                ),
    .mem_dqs_n                 (mem_dqs_n              ),
    .mem_dq                    (mem_dq                 ),
    .mem_dm                    (mem_dm                 ),
    .dbg_gate_start(1'b0),
    .dbg_cpd_start(1'b0),
    .dbg_ddrphy_rst_n(1'b1),
    .dbg_gpll_scan_rst(1'b0),
    .samp_position_dyn_adj(1'b0),
    .init_samp_position_even(32'd0),
    .init_samp_position_odd(32'd0),
    .wrcal_position_dyn_adj(1'b0),
    .init_wrcal_position(32'd0),
    .force_read_clk_ctrl(1'b0),
    .init_slip_step(16'd0),
    .init_read_clk_ctrl(12'd0),
    .debug_calib_ctrl(),
    .dbg_slice_status(),
    .dbg_slice_state(),
    .debug_data(),
    .dbg_dll_upd_state(),
    .debug_gpll_dps_phase(),
    .dbg_rst_dps_state(),
    .dbg_tran_err_rst_cnt(),
    .dbg_ddrphy_init_fail(),
    .debug_cpd_offset_adj(1'b0),
    .debug_cpd_offset_dir(1'b0),
    .debug_cpd_offset(10'd0),
    .debug_dps_cnt_dir0(),
    .debug_dps_cnt_dir1(),
    .ck_dly_en(1'b0),
    .init_ck_dly_step(8'h0),
    .ck_dly_set_bin(),
    .align_error(),
    .debug_rst_state(),
    .debug_cpd_state()
);

// 心跳信号
always@(posedge core_clk) begin
    if (!ddr_init_done)
        cnt <= 27'd0;
    else if ( cnt >= TH_1S )
        cnt <= 27'd0;
    else
        cnt <= cnt + 27'd1;
end

always @(posedge core_clk) begin
    if (!ddr_init_done)
        heart_beat_led <= 1'd1;
    else if ( cnt >= TH_1S )
        heart_beat_led <= ~heart_beat_led;
end
                 
/////////////////////////////////////////////////////////////////////////////////////
endmodule