module arbiter #(
    parameter int                       NUM_PORTS = 2,

    parameter int                       LFSR_WIDTH  = 16,
    parameter logic [LFSR_WIDTH-1:0]    SEED        = 'b0101010101, // SEED is used as a starting state (period start), CAN NOT BE 0!,  10 bit seed 'b0000000001, b0101010101
    parameter logic [LFSR_WIDTH-1:0]    TAP_MASK    = 'b1011010000000000, // Polinomial representation in bin, should be a max period primitive polinomial 2^(n-1) where n = LFSR_WIDTH


    localparam int                      PrnWidth   = ($clog2(NUM_PORTS)+1), // Is + 1 since the MSB is used in arbitration
    localparam int                      IdxWidth   = ($clog2(NUM_PORTS))
)
(
    input logic clk_i,
    input logic rstn_i,

    input logic [NUM_PORTS-1:0] valid_vector_i,
    input logic                 ready_i,

    output logic                granted_o,
    output logic [IdxWidth-1:0] granted_idx_o
);

    logic   [PrnWidth-1:0]     prn; // The pseudo random number (PRN) generated
    logic                      lfsr_state_hold;
    assign  lfsr_state_hold =  (valid_vector_i[granted_idx_o] == 0 || ready_i == 0);
     lf_lfsr_prng #(
        .LFSR_WIDTH (LFSR_WIDTH ),
        .SEED       (SEED),
        .PRN_WIDTH  (PrnWidth  ),
        .TAP_MASK   (TAP_MASK  )
    ) prng_inst (
        .clk_i          (clk_i),
        .rstn_i         (rstn_i),
        .hold_state_i   (lfsr_state_hold),
        .prn_o          (prn            )
    );

    // Skip Mask
    // The skip mask is used to determine if an active request should be skiped when a part of the PRN generated used to index
    // the valid_vector_i does not result in an active request on that index and the arbiter has to resort to a round robin (RR) way
    // of choosing one of the active requests, it does so by starting the round from the index and progressing either left or right
    // based on the MSB value of the PRN, it grants the request to the first active requestor and its index is marked in the skip mask,
    // the skip mask is reset if it covers the active requests in the valid_vector_i
    // This ensures fairness when arbitering as it mitigates starvation of requestors in certain scenarios
    logic   [NUM_PORTS-1:0] skip_mask;
    logic   [NUM_PORTS-1:0] skip_mask_next;
    logic                   skip_covered_valid_v;

    always_comb begin
        skip_mask_next = skip_mask;
        if (prn_miss & granted_o) begin
            if (skip_covered_valid_v) begin
                skip_mask_next = '0; // Skip mask is reset if it covers the the active requests
            end
            skip_mask_next[granted_idx_o] = 1'b1; // Set skip bit for the granted requestor
        end
    end

    always_ff @(posedge clk_i) begin
        if (~rstn_i) begin
            skip_mask <= '0;
        end else if (prn_miss & granted_o) begin
            skip_mask <= skip_mask_next;
        end
    end

    // Arbiter
    // This arbiter is based on PRN's being generated and granting requests based on their value, 
    // if the value was to grant an inactive request it is considered as a PRN miss and the arbiter
    // resorts to a round robin (RR) way of choosing one of the active requests, it does so by starting 
    // the round from the index generated and progressing either left or right based on the MSB value of 
    // the PRN, it grants the request to the first active requestor and its index is marked in the skip mask
    logic   [IdxWidth-1:0]  idx;
    logic                   prn_miss;
    logic                   valid;
    logic                   skip;

    always_comb begin
        // Reset to defaults
        granted_o               = '0;
        granted_idx_o           = '0;
        idx                     = prn[IdxWidth-1:0];
        prn_miss                = ~valid_vector_i[idx];     // If request is not active, set prn_miss to high and vice versa 
        skip_covered_valid_v    = ((valid_vector_i & skip_mask) == valid_vector_i);
        if (ready_i) begin          // TODO could be a redundant condition
            for (int i = 0; i<NUM_PORTS; ++i) begin // Progress the round
                if (~granted_o) begin
                    valid   = valid_vector_i[idx] == '1;  // Check if request is valid
                    skip    = ~((prn_miss == '1 & skip_mask[idx] == '0) || prn_miss == '0 || skip_covered_valid_v);   // Check if request is to be skipped
                    if (valid & ~skip) begin
                        granted_o    = '1;   // Set granted_o to high to signal the end of the round
                        granted_idx_o  = idx;  // Set active idx to the idx of the granted_o request
                    end else begin  // If request not granted or inactive
                        // Determine the direction of the round based on PRN's MSB value
                        if (int'(idx) >= NUM_PORTS) begin
                            idx = prn[PrnWidth-1] ? '1 : '0;   // Reset idx (overflow)
                        end else begin
                            idx = prn[PrnWidth-1] ? idx-1 : idx+1;
                        end
                    end
                end
            end
        end
    end

endmodule

