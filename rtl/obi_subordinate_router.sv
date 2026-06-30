
// OBI slave module
module obi_subordinate_router #(
    parameter obi_pkg::xbar_cfg_t XbarCfg,

    parameter type              obi_a_t,
    parameter type              obi_r_t,

    parameter type              sub_obi_a_t,
    parameter type              sub_obi_r_t,

    parameter int MANAGERS_CONS = 1, // No. of Manager-Routers connected to Subordinate-Router

    localparam int ManagersConsWidth    = $clog2(MANAGERS_CONS),
    localparam int NBytes               = XbarCfg.AddrWidth/8,

    // Leap Forward LFSR PRNG
    localparam int                   LFSR_WIDTH = 10,
    localparam int                   PRN_WIDTH  = ($clog2(MANAGERS_CONS)+1), // Is + 1 since the MSB is used in arbitering
    localparam logic[LFSR_WIDTH-1:0] SEED       = 'b0101010101,              // SEED is used as a starting state (period start),  10 bit seed 'b0000000001, b0101010101
    localparam logic[LFSR_WIDTH-1:0] TAP_MASK   = LFSR_WIDTH'('b1001000000) // 16 bit lfsr tap mask 'b1011010000000000, 10 bit tap 'b1001000000
    // Polinomial representation in bin, should be a max period primitive polinomial (2^n)-1 where n = LFSR_WIDTH
    // eg. LFSR_WIDTH = 4, x^4 + x^3 + 1 = 1100 = TAP_MASK
    // List of taps: https://www.physics.otago.ac.nz/reports/electronics/ETR2012-1.pdf
)
(
    input   logic   clk_i,
    input   logic   rstn_i,

// OBI A channels Slave<-Masters
    input   obi_a_t [MANAGERS_CONS-1:0]                         obi_a_channels_i,
    output  logic   [MANAGERS_CONS-1:0]                         obi_agnt_array_o,

// OBI R channels Slave->Masters
    output  obi_r_t [MANAGERS_CONS-1:0]                         obi_r_channels_o,
    input   logic   [MANAGERS_CONS-1:0]                         obi_rready_array_i,

// OBI XBAR Slave->OBI Slave
    output  sub_obi_a_t                                         sub_obi_a,
    input   logic                                               obi_agnt_i,

// OBI XBAR Slave<-OBI Slave
    output  logic                                               obi_rready_o,
    input   sub_obi_r_t                                         sub_obi_r
);
    // Type that is used to add/strip mid bits from aid/rid
    typedef struct packed {
        logic [XbarCfg.IdWidth-1:0]             obi_aid;
        logic [XbarCfg.MidWidth-1:0]            obi_mid;
    } obi_sub_id_t;

    // Signal that selects the R channel of response transaction
    logic [ManagersConsWidth-1:0] rsp_sel;
    // Vector of all A channel areq values
    logic   [MANAGERS_CONS-1:0] areq_vector;
    // Signal that is active when SR is ready to transact, used to enable arbitration
    logic ready;
    // Signal that is active when arbitration succeded (request was granted)
    logic granted;
    // Signal that selects the A channel of request transaction
    logic [ManagersConsWidth-1:0] granted_idx;

    // Vector of OBI A channels obi_areq signal
    always_comb begin : assign_areq_vector
        for (int i = 0; i<MANAGERS_CONS; ++i) begin
            areq_vector[i] = obi_a_channels_i[i].obi_areq;
        end
    end

    // Arbiter instance, used for arbitration of requests on A channels
    arbiter #(
        .NUM_PORTS  (MANAGERS_CONS),
        .LFSR_WIDTH (LFSR_WIDTH ),
        .SEED       (SEED),
        .TAP_MASK   (TAP_MASK  )
    ) arbiter (
        .clk_i          (clk_i),
        .rstn_i         (rstn_i),

        .valid_vector_i (areq_vector),
        .ready_i        (ready),
        .granted_o      (granted),
        .granted_idx_o  (granted_idx)
    );

    if (XbarCfg.UseSrFifo) begin : gen_fifos_sr
    // ID FIFO
        // Data type stored in id_fifo
        typedef struct packed {
            logic   [XbarCfg.IdWidth-1:0]           aid;
            //logic   [$clog2(XbarCfg.Managers)-1:0]  mid;
            logic   [ManagersConsWidth-1:0]         rsp_sel;
        } id_data_t;

        // Signals of id_fifo
        logic   id_wr_en;
        logic   id_rd_en;
        id_data_t id_data_in;
        id_data_t id_data_out;
        logic   id_fifo_empty;
        logic   id_fifo_full;

        // Instance of id_fifo
        fifo_lop #(
            .DTYPE      (id_data_t            ),
            .DEPTH      (XbarCfg.SrFifoDepth )
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
        // Data type stored in request_fifo
        typedef struct packed {
            logic   [XbarCfg.AddrWidth-1:0]     aadr;
            logic                               awe;
            logic   [XbarCfg.DataWidth/8-1:0]   abe;
            logic   [XbarCfg.DataWidth-1:0]     awdata;
        } req_data_t;

        // Signals of request_fifo
        logic       req_wr_en;
        logic       req_rd_en;
        req_data_t    req_data_in;
        req_data_t    req_data_out;
        logic       req_fifo_empty;
        logic       req_fifo_full;

        // Instance of request_fifo
        fifo_lop #(
            .DTYPE      (req_data_t           ),
            .DEPTH      (XbarCfg.SrFifoDepth )
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

    // RSP FIFO
        // Data type stored in response_fifo
        typedef struct packed {
            logic                           rerr;
            logic   [XbarCfg.DataWidth-1:0] rdata;
        } rsp_data_t;

        // Signals of response_fifo
        logic       rsp_wr_en;
        logic       rsp_rd_en;
        rsp_data_t  rsp_data_in;
        rsp_data_t  rsp_data_out;
        logic       rsp_fifo_empty;
        logic       rsp_fifo_full;

        // Instance of response_fifo
        fifo_lop #(
            .DTYPE      (rsp_data_t          ),
            .DEPTH      (XbarCfg.SrFifoDepth )
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

        assign  rsp_sel     = id_data_out.rsp_sel;
        assign  ready       = (~req_fifo_full & ~id_fifo_full);

        // Store arbitrated request
        always_comb begin
            obi_agnt_array_o    = '{default: '0};
            id_wr_en            = '0;
            req_wr_en           = '0;
            id_data_in          = '0;
            req_data_in         = '0;
            if (granted) begin
                obi_agnt_array_o[granted_idx] = '1;  // Set grant to high
                // Data to be written into the REQ FIFO
                req_data_in.aadr    = obi_a_channels_i[granted_idx].obi_aadr;
                req_data_in.awe     = obi_a_channels_i[granted_idx].obi_awe;
                req_data_in.abe     = obi_a_channels_i[granted_idx].obi_abe;
                req_data_in.awdata  = obi_a_channels_i[granted_idx].obi_awdata;
                // Data to be written into the ID FIFO
                id_data_in.aid      = obi_a_channels_i[granted_idx].obi_aid;
                //id_data_in.mid      = obi_a_channels_i[granted_idx].obi_mid;
                id_data_in.rsp_sel  = granted_idx;
                // Write enable
                id_wr_en            = '1;
                req_wr_en           = '1;
            end
        end

        // Read & Transact request
        always_comb begin
            sub_obi_a               = '0;
            sub_obi_a.obi_areq      = ~req_fifo_empty;
            req_rd_en               = '0;
            if (sub_obi_a.obi_areq) begin
                // Data to be read from REQ FIFO
                sub_obi_a.obi_aadr      = req_data_out.aadr;
                sub_obi_a.obi_awe       = req_data_out.awe;
                sub_obi_a.obi_abe       = req_data_out.abe;
                sub_obi_a.obi_awdata    = req_data_out.awdata;
                sub_obi_a.obi_aid       = '0;
                if (obi_agnt_i) begin
                    // Read enable
                    req_rd_en               = '1;
                end
            end
        end

        // Transact & Store response
        always_comb begin
            obi_rready_o = ~rsp_fifo_full;
            rsp_wr_en   = '0;
            rsp_data_in = '0;
            if (sub_obi_r.obi_rvalid & obi_rready_o) begin
                // Data to be written into the RSP FIFO
                rsp_data_in.rerr    = sub_obi_r.obi_rerr;
                rsp_data_in.rdata   = sub_obi_r.obi_rdata;
                // Write enable
                rsp_wr_en = '1;
            end
        end

        // Read & Route response
        always_comb begin
            obi_r_channels_o    = '{default: '0};
            rsp_rd_en           = '0;
            id_rd_en            = '0;
            if (~rsp_fifo_empty & ~id_fifo_empty) begin
                // Data to be read from RSP & ID FIFO's
                obi_r_channels_o[rsp_sel].obi_rvalid    = '1;
                obi_r_channels_o[rsp_sel].obi_rdata     = rsp_data_out.rdata;
                obi_r_channels_o[rsp_sel].obi_rerr      = rsp_data_out.rerr;
                obi_r_channels_o[rsp_sel].obi_rid       = id_data_out.aid;
                if (obi_rready_array_i[rsp_sel]) begin
                    // Read enable
                    rsp_rd_en   = '1;
                    id_rd_en    = '1;
                end
            end
        end

    end

    if (~XbarCfg.UseSrFifo) begin : gen_comb_sr
        localparam int MidWidth = XbarCfg.MidWidth;

        obi_sub_id_t id;
        assign  id      = obi_sub_id_t'(sub_obi_r.obi_rid);
        assign  rsp_sel = ManagersConsWidth'(id.obi_mid);
        assign  ready   = obi_agnt_i;

        // Transact arbitrated request
        always_comb begin
            obi_agnt_array_o    = '{default: '0};
            sub_obi_a           = '0;
            if (granted) begin
                obi_agnt_array_o[granted_idx]   = obi_agnt_i;
                sub_obi_a.obi_areq              = obi_a_channels_i[granted_idx].obi_areq;
                sub_obi_a.obi_aadr              = obi_a_channels_i[granted_idx].obi_aadr;
                sub_obi_a.obi_awe               = obi_a_channels_i[granted_idx].obi_awe;
                sub_obi_a.obi_abe               = obi_a_channels_i[granted_idx].obi_abe;
                sub_obi_a.obi_awdata            = obi_a_channels_i[granted_idx].obi_awdata;
                //sub_obi_a.obi_aid               = obi_sub_id_t'({obi_a_channels_i[granted_idx].obi_aid, obi_a_channels_i[granted_idx].obi_mid}); 
                sub_obi_a.obi_aid               = obi_sub_id_t'({obi_a_channels_i[granted_idx].obi_aid, MidWidth'(granted_idx)}); 
            end
        end

        // Route response
        always_comb begin
            // Response data
            obi_r_channels_o = '{default: '0};
            obi_rready_o                             = obi_rready_array_i[rsp_sel];
            if (sub_obi_r.obi_rvalid) begin
                obi_r_channels_o[rsp_sel].obi_rvalid    = sub_obi_r.obi_rvalid;
                obi_r_channels_o[rsp_sel].obi_rdata     = sub_obi_r.obi_rdata;
                obi_r_channels_o[rsp_sel].obi_rerr      = sub_obi_r.obi_rerr;
                obi_r_channels_o[rsp_sel].obi_rid       = id.obi_aid;
            end
    end
    end

endmodule


