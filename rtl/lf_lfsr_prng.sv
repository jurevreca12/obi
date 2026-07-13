
// Leap forward LFSR PRNG
module lf_lfsr_prng#(
    parameter int                       LFSR_WIDTH  = 16,
    parameter logic[LFSR_WIDTH-1:0]     SEED        = 'b0101010101, // SEED is used as a starting state (period start), CAN NOT BE 0!,  10 bit seed 'b0000000001, b0101010101
    parameter logic [LFSR_WIDTH-1:0]    TAP_MASK    = 'b1011010000000000, // Polinomial representation in bin, should be a max period primitive polinomial 2^(n-1) where n = LFSR_WIDTH
    parameter int                       PRN_WIDTH   = 2
    // eg. LFSR_WIDTH = 4, x^4 + x^3 + 1 = 1100 = TAP_MASK
    // List of taps: https://www.physics.otago.ac.nz/reports/electronics/ETR2012-1.pdf
)
(
    input logic clk_i,
    input logic rstn_i,

    input logic hold_state_i,

    output  logic [PRN_WIDTH-1:0]   prn_o   // Pseudo random number
);
    logic                   feedback;   // Is fed back into the LFSR each LFSR cycle
    logic [LFSR_WIDTH-1:0]  state;      // Is the current state of the LFSR
    logic [LFSR_WIDTH-1:0]  state_prev; // Is the previous state of the LFSR
    logic                   hold_state; // Used to hold the state of the LFSR
    logic [PRN_WIDTH-1:0]   prn_prev;

    always_comb begin
        state = state_prev;
        prn_o = prn_prev;
        feedback = '0;
        if (~hold_state) begin
            for (int i=0; i<LFSR_WIDTH; i++) begin  // interleave
                feedback = ^(state & TAP_MASK);     // Calculate feedback
                if (i < PRN_WIDTH) begin
                    prn_o[i] = state[LFSR_WIDTH-1]; // Set prn bit i = LFSR output bit each LFSR cycle
                end
                state = {state[LFSR_WIDTH-2:0], feedback};  // Shift LFSR by 1 bit and feed back the new bit
            end
        end
    end

    // Seed LFSR each cycle to generate a new prn
    register #(
      .DTYPE      (logic[LFSR_WIDTH-1:0]), 
      .RESET_VALUE(SEED)
    ) state_reg (
      .clk(clk_i), .rstn(rstn_i), .ce(1'b1), .in(state),        .out(state_prev)
    );
    register hold_state_reg (
      .clk(clk_i), .rstn(rstn_i), .ce(1'b1), .in(hold_state_i), .out(hold_state)
    );
    register #(
      .DTYPE(logic [PRN_WIDTH-1:0])
    ) prn_reg (
      .clk(clk_i), .rstn(rstn_i), .ce(1'b1), .in(prn_o),        .out(prn_prev)
    );

endmodule

