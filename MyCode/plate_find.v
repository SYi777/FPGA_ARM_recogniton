`timescale 1ns / 1ps
module plate_find (
    input            clk,
    input            rst_n,
    input            bin_vs,
    input            bin_de,
    input            bin_pix,
    output reg [11:0] plate_x1,
    output reg [11:0] plate_x2,
    output reg [11:0] plate_y1,
    output reg [11:0] plate_y2
);

    // ===================== 参数 =====================
    parameter H_ACT          = 12'd1920;
    parameter V_ACT          = 12'd1080;
    parameter TOP_MASK       = 12'd100;   // 顶部屏蔽 100 行
    parameter BOT_MASK       = 12'd980;   // 底部屏蔽 100 行
    parameter PLATE_HEIGHT   = 12'd60;    // 期望车牌高度，用于打分
    parameter PLATE_WIDTH    = 12'd160;   // X 方向固定宽度
    parameter MIN_GAP        = 12'd30;    // 峰对最小间距
    parameter MAX_GAP        = 12'd200;   // 峰对最大间距
    parameter PEAK_THRESH_RATIO = 5'd30;  // 峰值至少为全局最大值的 30%
    parameter SIMILARITY_RATIO  = 5'd85;  // 两个峰值的相似度 >= 85%
    parameter MID_PEAK_RATIO    = 5'd60;  // 中间峰值需低于较小峰值的 60%

    // ===================== 行列计数器 =====================
    reg [11:0] cnt_col;
    reg [11:0] cnt_row;
    reg        de_d0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt_col <= 0;
            cnt_row <= 0;
            de_d0   <= 0;
        end else begin
            de_d0 <= bin_de;
            if (bin_vs) begin
                cnt_col <= 0;
                cnt_row <= 0;
            end else if (bin_de) begin
                cnt_col <= cnt_col + 1'b1;
            end
            if (de_d0 && !bin_de) begin
                cnt_row <= cnt_row + 1'b1;
            end
        end
    end

    // ===================== 当前行投影和 =====================
    reg [15:0] row_sum;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            row_sum <= 0;
        end else begin
            if (bin_vs)
                row_sum <= 0;
            else if (bin_de) begin
                if (bin_pix)
                    row_sum <= row_sum + 1'b1;
            end else begin
                row_sum <= 0;
            end
        end
    end

    // ===================== 行投影 RAM =====================
    reg [15:0] row_sum_ram [0:V_ACT-1];

    always @(posedge clk) begin
        if (de_d0 && !bin_de)
            row_sum_ram[cnt_row] <= row_sum;
    end

    // ===================== 帧结束脉冲 =====================
    reg frame_end;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            frame_end <= 0;
        end else if (bin_vs) begin
            frame_end <= 0;
        end else if (de_d0 && !bin_de && cnt_row == V_ACT - 1) begin
            frame_end <= 1;
        end else begin
            frame_end <= 0;
        end
    end

    // ===================== 第一遍：全局最大值扫描 =====================
    reg [15:0] global_max;
    reg [11:0] pass1_addr;
    reg        pass1_done;
    reg [15:0] pass1_rd_data;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pass1_addr    <= TOP_MASK;
            global_max    <= 0;
            pass1_done    <= 0;
            pass1_rd_data <= 0;
        end else if (frame_end) begin
            pass1_addr    <= TOP_MASK;
            global_max    <= 0;
            pass1_done    <= 0;
        end else if (!pass1_done) begin
            pass1_rd_data <= row_sum_ram[pass1_addr];
            if (pass1_rd_data > global_max)
                global_max <= pass1_rd_data;
            if (pass1_addr < BOT_MASK - 1)
                pass1_addr <= pass1_addr + 1'b1;
            else begin
                if (row_sum_ram[BOT_MASK - 1] > global_max)
                    global_max <= row_sum_ram[BOT_MASK - 1];
                pass1_done <= 1;
            end
        end
    end

    // ===================== 第二遍：提取所有峰值 =====================
    // 峰值 RAM：最多 V_ACT 个，存储 {row[11:0], val[15:0]} → 28 bit
    reg [27:0] peak_ram [0:V_ACT-1];
    wire [15:0] threshold = (global_max * PEAK_THRESH_RATIO) / 100;

    // 峰值提取状态机（清晰版）
    reg [11:0] rd_addr2;
    reg [15:0] val0, val1, val2;
    wire       local_max = (val1 > val0) && (val1 > val2) && (val1 >= threshold);

    localparam PK_S_IDLE  = 3'd0;
    localparam PK_S_READ0 = 3'd1;
    localparam PK_S_READ1 = 3'd2;
    localparam PK_S_READ2 = 3'd3;
    localparam PK_S_JUDGE = 3'd4;
    localparam PK_S_DONE  = 3'd5;
    reg [2:0] pk_state, pk_next;
    reg [11:0] pk_count;
    reg [11:0] pk_waddr;
    reg        extract_done;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pk_state  <= PK_S_IDLE;
            rd_addr2  <= TOP_MASK;
            val0      <= 0;
            val1      <= 0;
            val2      <= 0;
            pk_count  <= 0;
            pk_waddr  <= 0;
            extract_done <= 0;
        end else begin
            pk_state <= pk_next;
            case (pk_state)
                PK_S_IDLE: begin
                    extract_done <= 0;
                    if (pass1_done) begin
                        rd_addr2 <= TOP_MASK;
                        pk_count <= 0;
                        pk_waddr <= 0;
                    end
                end

                PK_S_READ0: begin
                    val0 <= row_sum_ram[rd_addr2];
                    rd_addr2 <= rd_addr2 + 1'b1;
                end

                PK_S_READ1: begin
                    val1 <= row_sum_ram[rd_addr2];
                    rd_addr2 <= rd_addr2 + 1'b1;
                end

                PK_S_READ2: begin
                    val2 <= row_sum_ram[rd_addr2];
                    if (local_max) begin
                        peak_ram[pk_count] <= {rd_addr2 - 1, val1};
                        pk_count <= pk_count + 1;
                    end
                    val0 <= val1;
                    val1 <= val2;
                    val2 <= 0;
                    rd_addr2 <= rd_addr2 + 1'b1;
                end

                PK_S_JUDGE: begin
                    if (local_max) begin
                        peak_ram[pk_count] <= {rd_addr2 - 2, val1};
                        pk_count <= pk_count + 1;
                    end
                    val0 <= val1;
                    val1 <= val2;
                    val2 <= row_sum_ram[rd_addr2];
                    if (rd_addr2 < BOT_MASK - 1) begin
                        rd_addr2 <= rd_addr2 + 1'b1;
                    end else begin
                        if (local_max) begin
                            peak_ram[pk_count] <= {rd_addr2 - 1, val1};
                            pk_count <= pk_count + 1;
                        end
                        extract_done <= 1;
                    end
                end

                PK_S_DONE: begin
                    // 等待下一帧
                end

                default: ;
            endcase
        end
    end

    always @(*) begin
        pk_next = pk_state;
        case (pk_state)
            PK_S_IDLE:   if (pass1_done) pk_next = PK_S_READ0;
            PK_S_READ0:  pk_next = PK_S_READ1;
            PK_S_READ1:  pk_next = PK_S_READ2;
            PK_S_READ2:  if (rd_addr2 >= BOT_MASK) pk_next = PK_S_DONE; else pk_next = PK_S_JUDGE;
            PK_S_JUDGE:  if (rd_addr2 >= BOT_MASK) pk_next = PK_S_DONE; else pk_next = PK_S_JUDGE;
            PK_S_DONE:   if (bin_vs) pk_next = PK_S_IDLE;
            default:     pk_next = PK_S_IDLE;
        endcase
    end

    // ===================== 第三遍：双指针对寻找最佳峰对 =====================
    reg [11:0] ptr_i, ptr_j;
    reg [11:0] peak_cnt_reg;
    reg [27:0] pi_val, pj_val;
    reg [11:0] row_i, row_j;
    reg [15:0] val_i, val_j;
    reg        pending_check_mid;
    reg [11:0] mid_ptr;
    reg        mid_fail;
    reg [15:0] best_score;
    reg [11:0] best_y1, best_y2;
    reg [15:0] best_val1, best_val2;
    reg        found_any;

    wire [15:0] gap = row_j - row_i;
    wire [15:0] sim_val = (val_i < val_j) ? val_i : val_j;
    wire match_sim = (sim_val * 100) >= (((val_i > val_j) ? val_i : val_j) * SIMILARITY_RATIO);
    wire match_gap = (gap >= MIN_GAP) && (gap <= MAX_GAP);

    // 计算得分的组合逻辑（避免在过程块内声明）
    wire [15:0] diff  = (gap > PLATE_HEIGHT) ? (gap - PLATE_HEIGHT) : (PLATE_HEIGHT - gap);
    wire [15:0] score = 16'd1000 - {4'd0, diff[11:0]} + ((val_i + val_j) >> 9);

    localparam DP_IDLE       = 4'd0;
    localparam DP_INIT       = 4'd1;
    localparam DP_READ_I     = 4'd2;
    localparam DP_READ_J     = 4'd3;
    localparam DP_COMPARE    = 4'd4;
    localparam DP_CHECK_MID0 = 4'd5;
    localparam DP_CHECK_MID1 = 4'd6;
    localparam DP_EVAL       = 4'd7;
    localparam DP_NEXT_PAIR  = 4'd8;
    localparam DP_DONE       = 4'd9;
    reg [3:0] dp_state, dp_next;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dp_state    <= DP_IDLE;
            ptr_i       <= 0;
            ptr_j       <= 0;
            peak_cnt_reg <= 0;
            pi_val      <= 0;
            pj_val      <= 0;
            row_i       <= 0; row_j <= 0;
            val_i       <= 0; val_j <= 0;
            pending_check_mid <= 0;
            mid_ptr     <= 0;
            mid_fail    <= 0;
            best_score  <= 0;
            best_y1     <= TOP_MASK;
            best_y2     <= BOT_MASK - 1;
            best_val1   <= 0; best_val2 <= 0;
            found_any   <= 0;
        end else begin
            dp_state <= dp_next;
            case (dp_state)
                DP_IDLE: begin
                    found_any <= 0;
                    best_score <= 0;
                    if (extract_done) begin
                        peak_cnt_reg <= pk_count;
                        ptr_i <= 0;
                        ptr_j <= 0;
                    end
                end

                DP_INIT: begin end

                DP_READ_I: begin
                    pi_val <= peak_ram[ptr_i];
                end

                DP_READ_J: begin
                    pj_val <= peak_ram[ptr_j];
                end

                DP_COMPARE: begin
                    row_i <= pi_val[27:16];
                    val_i <= pi_val[15:0];
                    row_j <= pj_val[27:16];
                    val_j <= pj_val[15:0];
                    if (match_sim && match_gap) begin
                        pending_check_mid <= 1;
                        mid_ptr <= ptr_i + 1;
                        mid_fail <= 0;
                    end else begin
                        pending_check_mid <= 0;
                    end
                end

                DP_CHECK_MID0: begin
                    if (mid_ptr < ptr_j) begin
                        pi_val <= peak_ram[mid_ptr];
                    end else begin
                        pending_check_mid <= 0;
                    end
                end

                DP_CHECK_MID1: begin
                    if (pi_val[15:0] > ((sim_val * MID_PEAK_RATIO) / 100))
                        mid_fail <= 1;
                    mid_ptr <= mid_ptr + 1;
                end

                DP_EVAL: begin
                    if (!mid_fail) begin
                        if (score > best_score || !found_any) begin
                            best_score <= score;
                            found_any <= 1;
                            if (row_i < row_j) begin
                                best_y1 <= row_i;
                                best_y2 <= row_j;
                            end else begin
                                best_y1 <= row_j;
                                best_y2 <= row_i;
                            end
                            best_val1 <= val_i;
                            best_val2 <= val_j;
                        end
                    end
                    pending_check_mid <= 0;
                end

                DP_NEXT_PAIR: begin
                    if (ptr_j < peak_cnt_reg - 1) begin
                        ptr_j <= ptr_j + 1;
                    end else if (ptr_i < peak_cnt_reg - 2) begin
                        ptr_i <= ptr_i + 1;
                        ptr_j <= ptr_i + 1;
                    end
                end

                DP_DONE: begin end

                default: ;
            endcase
        end
    end

    always @(*) begin
        dp_next = dp_state;
        case (dp_state)
            DP_IDLE:   if (extract_done) dp_next = DP_INIT;
            DP_INIT:   dp_next = DP_READ_I;
            DP_READ_I: dp_next = DP_READ_J;
            DP_READ_J: dp_next = DP_COMPARE;
            DP_COMPARE: begin
                if (pending_check_mid)  dp_next = DP_CHECK_MID0;
                else if (match_sim && match_gap) dp_next = DP_EVAL;
                else dp_next = DP_NEXT_PAIR;
            end
            DP_CHECK_MID0: begin
                if (mid_ptr < ptr_j) dp_next = DP_CHECK_MID1;
                else dp_next = DP_EVAL;
            end
            DP_CHECK_MID1: begin
                if (mid_fail || mid_ptr >= ptr_j) dp_next = DP_EVAL;
                else dp_next = DP_CHECK_MID0;
            end
            DP_EVAL: dp_next = DP_NEXT_PAIR;
            DP_NEXT_PAIR: begin
                if (ptr_j < peak_cnt_reg - 1 || ptr_i < peak_cnt_reg - 2)
                    dp_next = DP_READ_I;
                else
                    dp_next = DP_DONE;
            end
            DP_DONE: if (bin_vs) dp_next = DP_IDLE;
            default: dp_next = DP_IDLE;
        endcase
    end

    // ===================== 输出车牌框 =====================
    reg scan_done;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            scan_done <= 0;
        end else if (bin_vs) begin
            scan_done <= 0;
        end else if (dp_state == DP_DONE) begin
            scan_done <= 1;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            plate_x1 <= 12'd880;
            plate_x2 <= 12'd1040;
            plate_y1 <= TOP_MASK;
            plate_y2 <= BOT_MASK - 1;
        end else if (scan_done) begin
            plate_x1 <= 12'd880;
            plate_x2 <= 12'd1040;
            if (found_any) begin
                plate_y1 <= best_y1;
                plate_y2 <= best_y2;
            end else begin
                plate_y1 <= V_ACT/2 - PLATE_HEIGHT/2;
                plate_y2 <= V_ACT/2 + PLATE_HEIGHT/2;
            end
        end
    end

endmodule