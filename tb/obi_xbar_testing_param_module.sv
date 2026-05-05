//`include "../rtl/obi_typedef.svh"

module obi_xbar_testing_param_module import obi_pkg::*; #( // TODO rename this module
    
)
(
    input   logic clk_i,
    input   logic rstn_i,

// IFU signals
    // request channel
    input   logic [ADDR_WIDTH-1:0]  ifu_req_addr_i,
    input   logic [DATA_WIDTH-1:0]  ifu_req_data_i,
    input   logic [NBytes-1:0]      ifu_req_strobe_i,
    input   logic                   ifu_req_write_i,
    input   logic                   ifu_req_valid_i,
    input   logic [ID_WIDTH-1:0]    ifu_req_id_i,
    output  logic                   ifu_req_ready_o,

    // response channel
    output  logic [ADDR_WIDTH-1:0]  ifu_rsp_data_o,
    output  logic                   ifu_rsp_error_o,
    output  logic                   ifu_rsp_valid_o,
    output  logic [ID_WIDTH-1:0]    ifu_rsp_id_o,
    input   logic                   ifu_rsp_ready_i,
    

// LSU signals
    // request channel
    input   logic [ADDR_WIDTH-1:0]  lsu_req_addr_i,
    input   logic [DATA_WIDTH-1:0]  lsu_req_data_i,
    input   logic [NBytes-1:0]      lsu_req_strobe_i,
    input   logic                   lsu_req_write_i,
    input   logic                   lsu_req_valid_i,
    input   logic [ID_WIDTH-1:0]    lsu_req_id_i,
    output  logic                   lsu_req_ready_o,

    // response channel
    output  logic [ADDR_WIDTH-1:0]  lsu_rsp_data_o,
    output  logic                   lsu_rsp_error_o,
    output  logic                   lsu_rsp_valid_o,
    output  logic [ID_WIDTH-1:0]    lsu_rsp_id_o,
    input   logic                   lsu_rsp_ready_i,

// M2 signals
    // request channel
    input   logic [ADDR_WIDTH-1:0]  m2_req_addr_i,
    input   logic [DATA_WIDTH-1:0]  m2_req_data_i,
    input   logic [NBytes-1:0]      m2_req_strobe_i,
    input   logic                   m2_req_write_i,
    input   logic                   m2_req_valid_i,
    input   logic [ID_WIDTH-1:0]    m2_req_id_i,
    output  logic                   m2_req_ready_o,

    // response channel
    output  logic [ADDR_WIDTH-1:0]  m2_rsp_data_o,
    output  logic                   m2_rsp_error_o,
    output  logic                   m2_rsp_valid_o,
    output  logic [ID_WIDTH-1:0]    m2_rsp_id_o,
    input   logic                   m2_rsp_ready_i,


// S0
    output logic [ADDR_WIDTH-1:0]           s0_obi_aadr_o,
    output logic                            s0_obi_awe_o,
    output logic [NBytes-1:0]               s0_obi_abe_o,
    output logic [DATA_WIDTH-1:0]           s0_obi_awdata_o,
    output logic                            s0_obi_areq_o,
    input  logic                            s0_obi_agnt_i,

    output logic                            s0_obi_rready_o,
    input  logic                            s0_obi_rvalid_i,
    input  logic [DATA_WIDTH-1:0]           s0_obi_rdata_i,
    input  logic                            s0_obi_rerr_i,

// S1
    output logic [ADDR_WIDTH-1:0]           s1_obi_aadr_o,
    output logic                            s1_obi_awe_o,
    output logic [NBytes-1:0]               s1_obi_abe_o,
    output logic [DATA_WIDTH-1:0]           s1_obi_awdata_o,
    output logic                            s1_obi_areq_o,
    input  logic                            s1_obi_agnt_i,

    output logic                            s1_obi_rready_o,
    input  logic                            s1_obi_rvalid_i,
    input  logic [DATA_WIDTH-1:0]           s1_obi_rdata_i,
    input  logic                            s1_obi_rerr_i

);
    
    localparam int ADDR_WIDTH = 32;
    localparam int DATA_WIDTH = 32;
    localparam int MANAGERS = 4;
    localparam int MID_WIDTH = $clog2(MANAGERS);
    localparam int SUBORDINATES = 2;
    localparam int SR_FIFO_DEPTH = 1024;
    localparam bit USE_ID_FOR_ROUTING = '0;
    localparam int MR_FIFO_DEPTH = 1024;
    localparam int ID_WIDTH = $clog2(SR_FIFO_DEPTH * SUBORDINATES)+1;
    localparam int NBytes = DATA_WIDTH / 8;
    //localparam bit [SUBORDINATES-1:0] [MANAGERS-1:0] Connectivity = {{4'b0111}, {4'b0011}};
    

    localparam obi_pkg::xbar_cfg xbar_cfg = obi_pkg::xbar_default_cfg(MANAGERS, SUBORDINATES);

    localparam obi_pkg::obi_cfg obi_cfg = obi_pkg::obi_default_cfg(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH);

    `TYPEDEF_OBI_A_CHAN(obi_a, ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, MANAGERS);

    `TYPEDEF_OBI_R_CHAN(obi_r, DATA_WIDTH, ID_WIDTH);

    `TYPEDEF_XBAR_ADDR_MAP(addr_map, ADDR_WIDTH, SUBORDINATES);

    `TYPEDEF_XBAR_CONNECTIVITY(Connectivity, SUBORDINATES, MANAGERS, {{4'b0111}, {4'b0011}});

    //`TYPEDEF_XBAR_CONNECTIVITY(Connectivity, SUBORDINATES, MANAGERS, {{4'b1111}, {4'b1111}});

    //assign Connectivity = {{4'b0111}, {4'b0011}};

    //localparam int NoMAPS  = 2; 
    localparam int SUB_WIDTH = $clog2(xbar_cfg.Subordinates);
    addr_map address_map [xbar_cfg.NoMaps];
    assign address_map[0] = '{idx: SUB_WIDTH'('d0),base: 32'h0000_0000,mask: 32'h4000_0000};
    assign address_map[1] = '{idx: SUB_WIDTH'('d1),base: 32'h4000_0000,mask: 32'h4000_0000};






    obi_a obi_a_chans_mgr [MANAGERS];
    logic obi_agnt_signals_mgr [MANAGERS];
    
    // IFU
    assign obi_a_chans_mgr[0].obi_areq = ifu_req_valid_i;
    assign ifu_req_ready_o = obi_agnt_signals_mgr[0];
    assign obi_a_chans_mgr[0].obi_aadr = ifu_req_addr_i;
    assign obi_a_chans_mgr[0].obi_awe =  ifu_req_write_i;
    assign obi_a_chans_mgr[0].obi_abe = ifu_req_strobe_i;
    assign obi_a_chans_mgr[0].obi_awdata = ifu_req_data_i;
    assign obi_a_chans_mgr[0].obi_aid = ifu_req_id_i;

    // LSU
    assign obi_a_chans_mgr[1].obi_areq = lsu_req_valid_i;
    assign lsu_req_ready_o = obi_agnt_signals_mgr[1];
    assign obi_a_chans_mgr[1].obi_aadr = lsu_req_addr_i;
    assign obi_a_chans_mgr[1].obi_awe =  lsu_req_write_i;
    assign obi_a_chans_mgr[1].obi_abe = lsu_req_strobe_i;
    assign obi_a_chans_mgr[1].obi_awdata = lsu_req_data_i;
    assign obi_a_chans_mgr[1].obi_aid = lsu_req_id_i;

    // M2
    assign obi_a_chans_mgr[2].obi_areq = m2_req_valid_i;
    assign m2_req_ready_o = obi_agnt_signals_mgr[2];
    assign obi_a_chans_mgr[2].obi_aadr = m2_req_addr_i;
    assign obi_a_chans_mgr[2].obi_awe =  m2_req_write_i;
    assign obi_a_chans_mgr[2].obi_abe = m2_req_strobe_i;
    assign obi_a_chans_mgr[2].obi_awdata = m2_req_data_i;
    assign obi_a_chans_mgr[2].obi_aid = m2_req_id_i;
        
    obi_r obi_r_chans_mgr [MANAGERS];
    logic obi_rready_signals_mgr [MANAGERS];

    // IFU
    assign ifu_rsp_valid_o = obi_r_chans_mgr[0].obi_rvalid;
    assign obi_rready_signals_mgr[0] = ifu_rsp_ready_i;
    assign ifu_rsp_data_o = obi_r_chans_mgr[0].obi_rdata;
    assign ifu_rsp_error_o = obi_r_chans_mgr[0].obi_rerr;
    assign ifu_rsp_id_o = obi_r_chans_mgr[0].obi_rid;

    // LSU
    assign lsu_rsp_valid_o = obi_r_chans_mgr[1].obi_rvalid;
    assign obi_rready_signals_mgr[1] = lsu_rsp_ready_i;
    assign lsu_rsp_data_o = obi_r_chans_mgr[1].obi_rdata;
    assign lsu_rsp_error_o = obi_r_chans_mgr[1].obi_rerr;
    assign lsu_rsp_id_o = obi_r_chans_mgr[1].obi_rid;

    // M2
    assign m2_rsp_valid_o = obi_r_chans_mgr[2].obi_rvalid;
    assign obi_rready_signals_mgr[2] = m2_rsp_ready_i;
    assign m2_rsp_data_o = obi_r_chans_mgr[2].obi_rdata;
    assign m2_rsp_error_o = obi_r_chans_mgr[2].obi_rerr;
    assign m2_rsp_id_o = obi_r_chans_mgr[2].obi_rid;


    obi_a obi_a_chans_sub [SUBORDINATES];
    logic obi_agnt_signals_sub [SUBORDINATES];

    // S0
    assign obi_agnt_signals_sub[0] = s0_obi_agnt_i;
    assign s0_obi_areq_o = obi_a_chans_sub[0].obi_areq;
    assign s0_obi_aadr_o = obi_a_chans_sub[0].obi_aadr;
    assign s0_obi_awe_o = obi_a_chans_sub[0].obi_awe;
    assign s0_obi_abe_o = obi_a_chans_sub[0].obi_abe;
    assign s0_obi_awdata_o = obi_a_chans_sub[0].obi_awdata;

    // S1
    assign obi_agnt_signals_sub[1] = s1_obi_agnt_i;
    assign s1_obi_areq_o = obi_a_chans_sub[1].obi_areq;
    assign s1_obi_aadr_o = obi_a_chans_sub[1].obi_aadr;
    assign s1_obi_awe_o = obi_a_chans_sub[1].obi_awe;
    assign s1_obi_abe_o = obi_a_chans_sub[1].obi_abe;
    assign s1_obi_awdata_o = obi_a_chans_sub[1].obi_awdata;


    obi_r obi_r_chans_sub [SUBORDINATES];
    logic obi_rready_signals_sub [SUBORDINATES];

    // S0
    assign s0_obi_rready_o = obi_rready_signals_sub[0];
    assign obi_r_chans_sub[0].obi_rvalid = s0_obi_rvalid_i;
    assign obi_r_chans_sub[0].obi_rdata = s0_obi_rdata_i;
    assign obi_r_chans_sub[0].obi_rerr = s0_obi_rerr_i;

    // S1
    assign s1_obi_rready_o = obi_rready_signals_sub[1];
    assign obi_r_chans_sub[1].obi_rvalid = s1_obi_rvalid_i;
    assign obi_r_chans_sub[1].obi_rdata = s1_obi_rdata_i;
    assign obi_r_chans_sub[1].obi_rerr = s1_obi_rerr_i;

    obi_xbar #(
        .XbarCfg(xbar_cfg),
        .ObiCfg(obi_cfg),

        .obi_a_t(obi_a),
        .obi_r_t(obi_r),
        .addr_map_t(addr_map),

        .CONNECTIVITY(Connectivity)
    ) xbar_param (
        .clk_i(clk_i),
        .rstn_i(rstn_i),
        
        .mgr_obi_a_chans(obi_a_chans_mgr),
        .mgr_obi_agnt_signals(obi_agnt_signals_mgr),
        .mgr_obi_r_chans(obi_r_chans_mgr),
        .mgr_obi_rready_signals(obi_rready_signals_mgr),

        .sub_obi_a_chans(obi_a_chans_sub),
        .sub_obi_agnt_signals(obi_agnt_signals_sub),
        .sub_obi_r_chans(obi_r_chans_sub),
        .sub_obi_rready_signals(obi_rready_signals_sub),

        .addr_map_i(address_map)

    );

    


endmodule
