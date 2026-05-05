module linear_cnt #(
    parameter bit RESET_VALUE   = '0,
    parameter int WIDTH         = 1,
    parameter bit USE_CNT_NEXT  = '0,
    parameter int MAX_VALUE     = (1 << WIDTH) - 1
)(
    input   logic               clk_i,
    input   logic               rstn_i,
    input   logic               cnt_next_i,
    output  logic [WIDTH-1:0]   cnt_value_o
);
    always_ff @(posedge clk_i) begin
        if (~rstn_i) begin
            cnt_value_o <= WIDTH'(RESET_VALUE);
        end else begin
            if ((USE_CNT_NEXT && cnt_next_i) || (~USE_CNT_NEXT)) begin
                if (cnt_value_o == WIDTH'(MAX_VALUE)) begin
                    cnt_value_o <= WIDTH'(RESET_VALUE);
                end else begin
                    cnt_value_o <= cnt_value_o + 1;
                end
            end
        end
    end

endmodule
