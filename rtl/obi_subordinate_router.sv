
// OBI slave module
module obi_subordinate_router #( 
    parameter obi_pkg::xbar_cfg XbarCfg,
    parameter obi_pkg::obi_cfg  ObiCfg,

    parameter type              obi_a_t,
    parameter type              obi_r_t,

    parameter int MANAGERS_CONS = 1 // No. of Manager-Routers connected to Subordinate-Router
)
(
    input   logic   clk_i,
    input   logic   rstn_i,

// OBI A channels Slave<-Masters
    input   obi_a_t   [MANAGERS_CONS-1:0]     obi_a_channels_i,
    output  logic   [MANAGERS_CONS-1:0]     obi_agnt_array_o,

// OBI R channels Slave->Masters
    output  obi_r_t   [MANAGERS_CONS-1:0]     obi_r_channels_o,
    input   logic   [MANAGERS_CONS-1:0]     obi_rready_array_i,

// OBI XBAR Slave->OBI Slave
    output  logic   [ObiCfg.AddrWidth-1:0]  obi_aadr_o,
    output  logic                           obi_awe_o,
    output  logic   [NBytes-1:0]            obi_abe_o,
    output  logic   [ObiCfg.DataWidth-1:0]  obi_awdata_o,
    output  logic                           req_valid_o,
    input   logic                           req_read_i,

// OBI XBAR Slave<-OBI Slave
    input   logic                           rsp_write_i,
    output  logic                           rsp_ready_o,
    input   logic   [ObiCfg.DataWidth-1:0]  obi_rdata_i,
    input   logic                           obi_rerr_i

);
    localparam int ManagersConsWidth    = $clog2(MANAGERS_CONS);
    localparam int NBytes               = ObiCfg.AddrWidth/8;

// Leap Forward LFSR PRNG
    localparam int                   LFSR_WIDTH = 10;
    localparam int                   PRN_WIDTH  = ($clog2(MANAGERS_CONS)+1); // Is + 1 since the MSB is used in arbitering
    localparam logic[LFSR_WIDTH-1:0] SEED       = 'b0101010101;              // SEED is used as a starting state (period start),  10 bit seed 'b0000000001, b0101010101
    localparam logic[LFSR_WIDTH-1:0] TAP_MASK   = LFSR_WIDTH'('b1001000000); // 16 bit lfsr tap mask 'b1011010000000000, 10 bit tap 'b1001000000
    // Polinomial representation in bin, should be a max period primitive polinomial (2^n)-1 where n = LFSR_WIDTH
    // eg. LFSR_WIDTH = 4, x^4 + x^3 + 1 = 1100 = TAP_MASK 
    // List of taps: https://www.physics.otago.ac.nz/reports/electronics/ETR2012-1.pdf

    logic   [LFSR_WIDTH-1:0]    lfsr_state_in; // Input state to LFSR
    logic   [LFSR_WIDTH-1:0]    lfsr_state_out; // State that the LFSR ended up in after 1 clock cycle
    logic   [PRN_WIDTH-1:0]     prn; // The pseudo random number (PRN) generated
    lf_lfsr_prng #(
        .LFSR_WIDTH (LFSR_WIDTH ),
        .PRN_WIDTH  (PRN_WIDTH  ),
        .TAP_MASK   (TAP_MASK  )
    ) prng_inst (
        .state_i    (lfsr_state_in  ),
        .state_o    (lfsr_state_out ),
        .prn_o      (prn            )
    );

    // Seed LFSR each cycle to generate a new prn
    always_ff @(posedge clk_i) begin
        if (~rstn_i) begin
            lfsr_state_in <= SEED;  // On reset set LFSR state to SEED (period start)
        end else begin
            if (req_fifo_empty && ~req_wr_en) begin // If req FIFO is empty and there are no active requests, hold LFSR state to ensure the PRN's distribution
                lfsr_state_in <= lfsr_state_in;     // remains consistant when choosing which requester get's the grant (arbiter)
            end else if (~req_fifo_full && ~id_fifo_full) begin // While the slave module is able to grant requests, the LFSR 
                lfsr_state_in <= lfsr_state_out;                // continues to generate PRN's starting from the last state in the active period
            end else begin
                lfsr_state_in <= lfsr_state_in;
            end
        end
    end

// ID FIFO
    // The ID FIFO holds values of obi_aid and obi_mid signals from the granted request + rsp_sel for dmux
    // The aid value is transmitted back to the manager as the obi_rid signal

    typedef struct packed { // Data type stored in id_fifo
        logic   [ObiCfg.IdWidth-1:0]            aid;
        logic   [$clog2(XbarCfg.Managers)-1:0]  mid;
        logic   [ManagersConsWidth-1:0]         rsp_sel;      
    } id_data;
    
    logic   id_wr_en;
    logic   id_rd_en;
    id_data id_data_in;
    id_data id_data_out;
    logic   id_fifo_empty;
    logic   id_fifo_full;

    fifo #(
        .DTYPE      (id_data            ),
        .DEPTH      (ObiCfg.SrFifoDepth )
    ) id_fifo (
        .clk_i      (clk_i          ),
        .rstn_i     (rstn_i         ),
        .wr_en_i    (id_wr_en       ),
        .rd_en_i    (id_rd_en       ),
        .full_o     (id_fifo_full   ),
        .empty_o    (id_fifo_empty  ),
        .w_data_i   (id_data_in     ),
        .r_data_o   (id_data_out    )
    );

// REQ FIFO
    // The REQ FIFO holds values of obi_aadr, obi_awdata, obi_abe, obi_awe signals from the granted request
    // These values are read by the OBI Slave

    typedef struct packed { // Data type stored in request_fifo
        logic   [ObiCfg.AddrWidth-1:0]      aadr;        
        logic                               awe;
        logic   [ObiCfg.DataWidth/8-1:0]    abe;
        logic   [ObiCfg.DataWidth-1:0]      awdata;
    } req_data;

    logic       req_wr_en;
    logic       req_rd_en;
    req_data    req_data_in;
    req_data    req_data_out;
    logic       req_fifo_empty;
    logic       req_fifo_full;

    fifo #(
        .DTYPE      (req_data           ),
        .DEPTH      (ObiCfg.SrFifoDepth )
    ) request_fifo (
        .clk_i      (clk_i          ),
        .rstn_i     (rstn_i         ),
        .wr_en_i    (req_wr_en      ),
        .rd_en_i    (req_rd_en      ),
        .full_o     (req_fifo_full  ),
        .empty_o    (req_fifo_empty ),
        .w_data_i   (req_data_in    ),
        .r_data_o   (req_data_out   )
    );
    assign  req_valid_o     = ~req_fifo_empty;
    assign  req_rd_en       = req_valid_o & req_read_i; // REQ FIFO read enable 
    // Assign OBI req signal values, Subordinate-router -OBI_A-> Subordinate 
    assign  obi_aadr_o      = req_data_out.aadr;
    assign  obi_awe_o       = req_data_out.awe;
    assign  obi_abe_o       = req_data_out.abe;
    assign  obi_awdata_o    = req_data_out.awdata;

// RSP FIFO
    // The RSP FIFO holds values of obi_rdata, obi_rerr signals from the OBI Slave response
    // These values along with obi_rid are transmitted back to the manager

    typedef struct packed {
        logic                           rerr;
        logic   [ObiCfg.DataWidth-1:0]  rdata;
    } rsp_data;

    logic       rsp_wr_en;
    logic       rsp_rd_en;
    rsp_data    rsp_data_in;
    rsp_data    rsp_data_out;
    logic       rsp_fifo_empty;
    logic       rsp_fifo_full;

    fifo #(
        .DTYPE      (rsp_data           ),
        .DEPTH      (ObiCfg.SrFifoDepth )
    ) response_fifo (
        .clk_i      (clk_i          ),
        .rstn_i     (rstn_i         ),
        .wr_en_i    (rsp_wr_en      ),
        .rd_en_i    (rsp_rd_en      ),
        .full_o     (rsp_fifo_full  ),
        .empty_o    (rsp_fifo_empty ),
        .w_data_i   (rsp_data_in    ),
        .r_data_o   (rsp_data_out   )
    );
    assign  rsp_ready_o         = ~rsp_fifo_full;
    assign  rsp_wr_en           = rsp_ready_o & rsp_write_i; // RSP FIFO write enable
    // Assign rsp_data signal values, Subordinate-router <-OBI_R- Subordinate
    assign  rsp_data_in.rerr    = obi_rerr_i;
    assign  rsp_data_in.rdata   = obi_rdata_i;

// Vector of obi_areq signals
    logic   [MANAGERS_CONS-1:0] areq_vector;
    always_comb begin
        areq_vector = '0;
        for (int i = 0; i<MANAGERS_CONS; ++i) begin
            areq_vector[i] = obi_a_channels_i[i].obi_areq;
        end
    end

// Skip Mask
    // The skip mask is used to determine if an active request should be skiped when a part of the PRN generated used to index 
    // the areq_vector does not result in an active request on that index and the arbiter has to resort to a round robin (RR) way
    // of choosing one of the active requests, it does so by starting the round from the index and progressing either left or right
    // based on the MSB value of the PRN, it grants the request to the first active requestor and its index is marked in the skip mask,
    // the skip mask is reset if it covers the active requests in the areq_vector
    // This ensures fairness when arbitering as it mitigates starvation of requestors in certain scenarios 
    logic   [MANAGERS_CONS-1:0] skip_mask;
    logic   [MANAGERS_CONS-1:0] skip_mask_next;

    always_comb begin
        skip_mask_next = skip_mask;
        if (prn_miss & selected) begin
            skip_mask_next[active_idx] = 1'b1; // Set skip bit for the granted requestor
            if (((areq_vector & skip_mask_next) == areq_vector) ) begin 
                skip_mask_next = '0; // Skip mask is reset if it covers the the active requests
            end
        end
    end

    always_ff @(posedge clk_i) begin
        if (~rstn_i) begin
            skip_mask <= '0;   
        end else if (prn_miss & selected) begin
            skip_mask <= skip_mask_next;
        end
        
    end


// Arbiter
    // This arbiter is based on PRN's being generated and granting requests based on their value, 
    // if the value was to grant an inactive request it is considered as a PRN miss and the arbiter
    // resorts to a round robin (RR) way of choosing one of the active requests, it does so by starting 
    // the round from the index generated and progressing either left or right based on the MSB value of 
    // the PRN, it grants the request to the first active requestor and its index is marked in the skip mask
    logic   [PRN_WIDTH-2:0] idx;
    logic   [PRN_WIDTH-2:0] active_idx;
    logic                   prn_miss;
    logic                   selected;
    always_comb begin
        // Reset to defaults
        req_wr_en           = '0;
        id_wr_en            = '0;
        id_data_in          = '0;
        req_data_in         = '0;
        obi_agnt_array_o    = '{default: '0};
        idx                 = prn[PRN_WIDTH-2:0];
        active_idx          = '0;
        prn_miss            = '0;
        selected            = '0;
        if (~req_fifo_full && ~id_fifo_full) begin          // Only arbiter if REQ & ID FIFO's are not full
            prn_miss = ~obi_a_channels_i[idx].obi_areq;     // If request is not active, set prn_miss to high and vice versa 
            if (prn[PRN_WIDTH-1] == 0) begin                // Determines the direction of the round based on PRN's MSB value
                for (int i = 0; i<MANAGERS_CONS; ++i) begin // Progress the round
                    if (    (obi_a_channels_i[idx].obi_areq == '1) & ~selected &     // Check if request is active and if one has already been granted (selected)
                            ((prn_miss == '1 & skip_mask[idx] == '0) || prn_miss == '0 || ((areq_vector & skip_mask) == areq_vector))   // Check if request is to be skipped
                        ) begin
                        selected    = '1;   // Set selected to high to signal the end of the round
                        active_idx  = idx;  // Set active idx to the id of the selected request

                        // Data to be written into the REQ FIFO
                        req_data_in.aadr    = obi_a_channels_i[idx].obi_aadr;
                        req_data_in.awe     = obi_a_channels_i[idx].obi_awe;
                        req_data_in.abe     = obi_a_channels_i[idx].obi_abe;
                        req_data_in.awdata  = obi_a_channels_i[idx].obi_awdata;
                        
                        // Data to be written into the ID FIFO
                        id_data_in.aid      = obi_a_channels_i[idx].obi_aid;
                        id_data_in.mid      = obi_a_channels_i[idx].obi_mid;
                        id_data_in.rsp_sel  = active_idx;
                        
                        req_wr_en   = '1;   // Set the req write enable signal to high so request gets written to REQ FIFO
                        id_wr_en    = '1;   // Set the id write enable signal to high so request id's get written to ID FIFO
                    end else begin  // If request not granted or inactive
                        obi_agnt_array_o[idx] = '0; // Disconnect grant
                        if (int'(idx) >= MANAGERS_CONS) begin
                            idx = '0;               // Reset idx (overflow)
                        end else begin
                            idx = idx + 1'b1;       // Increment idx
                        end
                    end
                end
            end else begin
                for (int i = 0; i<MANAGERS_CONS; ++i) begin // Progress the round
                    if (    (obi_a_channels_i[idx].obi_areq == '1) & ~selected &    // Check if request is active and if one has already been granted (selected)
                            ((prn_miss == '1 & skip_mask[idx] == '0) || prn_miss == '0 || ((areq_vector & skip_mask) == areq_vector))   // Check if request is to be skipped
                        ) begin
                        selected    = '1;   // Set selected to high to signal the end of the round
                        active_idx  = idx;  // Set active idx to the id of the selected request

                        // Data to be written into the REQ FIFO
                        req_data_in.aadr    = obi_a_channels_i[idx].obi_aadr;
                        req_data_in.awe     = obi_a_channels_i[idx].obi_awe;
                        req_data_in.abe     = obi_a_channels_i[idx].obi_abe;
                        req_data_in.awdata  = obi_a_channels_i[idx].obi_awdata;
                        
                        // Data to be written into the ID FIFO
                        id_data_in.aid      = obi_a_channels_i[idx].obi_aid;
                        id_data_in.mid      = obi_a_channels_i[idx].obi_mid;
                        id_data_in.rsp_sel  = active_idx;
                        
                        req_wr_en   = '1;   // Set the req write enable signal to high so request gets written to REQ FIFO
                        id_wr_en    = '1;   // Set the id write enable signal to high so request id's get written to ID FIFO
                    end else begin  // If request not granted or inactive
                        obi_agnt_array_o[idx] = '0; // Disconnect grant
                        if (int'(idx) >= MANAGERS_CONS) begin
                            idx = '1;               // Reset idx (overflow)
                        end else begin
                            idx = idx - 1'b1;       // Decrement idx
                        end
                    end
                end
            end
            if (selected) begin     // If a request has been granted
                obi_agnt_array_o[active_idx] = '1;  // Set grant to high
            end
        end
    end

// OBI R channel DMUX
    always_comb begin
        // Reset to defaults
        obi_r_channels_o    = '{default: '0}; // Disconnect
        rsp_rd_en           = '0;
        id_rd_en            = '0;
        if (~rsp_fifo_empty && ~id_fifo_empty) begin // If RSP FIFO has a valid response, set the selected R channel signal values
            // Set the response signals
            obi_r_channels_o[id_data_out.rsp_sel].obi_rvalid    = '1;
            obi_r_channels_o[id_data_out.rsp_sel].obi_rdata     = rsp_data_out.rdata;
            obi_r_channels_o[id_data_out.rsp_sel].obi_rerr      = rsp_data_out.rerr;
            obi_r_channels_o[id_data_out.rsp_sel].obi_rid       = id_data_out.aid;
            if (obi_rready_array_i[id_data_out.rsp_sel] == '1) begin // When manager is ready to recieve the response, read from RSP & ID FIFO
                rsp_rd_en   = '1;
                id_rd_en    = '1;
            end
        end
    end
    
endmodule


