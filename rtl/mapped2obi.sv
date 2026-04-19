module mapped2obi #(
  parameter  int ADDR_WIDTH = 32,
  parameter  int DATA_WIDTH = 32,
  parameter  int IDLEN = 4,
  localparam int NBytes = DATA_WIDTH / 8
)(
  input  logic                   clk_i,
  input  logic                   rstn_i,

  input  logic [IDLEN-1:0]       mapped_req_id_i,
  input  logic [ADDR_WIDTH-1:0]  mapped_req_addr_i,
  input  logic [DATA_WIDTH-1:0]  mapped_req_data_i,
  input  logic [NBytes-1:0]      mapped_req_strobe_i,
  input  logic                   mapped_req_write_i,
  input  logic                   mapped_req_valid_i,
  output logic                   mapped_req_ready_o,

  output logic [IDLEN-1:0]       mapped_rsp_id_o,
  output logic [DATA_WIDTH-1:0]  mapped_rsp_data_o,
  output logic                   mapped_rsp_error_o,
  output logic                   mapped_rsp_valid_o,
  input  logic                   mapped_rsp_ready_i,

  output logic [IDLEN-1:0]       obi_aid_o,
  output logic                   obi_areq_o,
  input  logic                   obi_agnt_i,
  output logic [ADDR_WIDTH-1:0]  obi_aaddr_o,
  output logic                   obi_awe_o,
  output logic [NBytes-1:0]      obi_abe_o,
  output logic [DATA_WIDTH-1:0]  obi_awdata_o,

  input  logic [IDLEN-1:0]       obi_rid_i,
  input  logic                   obi_rvalid_i,
  output logic                   obi_rready_o,
  input  logic [DATA_WIDTH-1:0]  obi_rdata_i,
  input  logic                   obi_rerr_i
);
  assign obi_aid_o = mapped_req_id_i;
  assign obi_areq_o = mapped_req_valid_i;
  assign obi_aaddr_o = mapped_req_addr_i;
  assign obi_awe_o = mapped_req_write_i;
  assign obi_abe_o = mapped_req_strobe_i;
  assign obi_awdata_o = mapped_req_data_i;
  assign obi_rready_o = mapped_rsp_ready_i;
 
  assign mapped_rsp_id_o = obi_rid_i;
  assign mapped_req_ready_o = obi_agnt_i;
  assign mapped_rsp_data_o = obi_rdata_i;
  assign mapped_rsp_error_o = obi_rerr_i;
  assign mapped_rsp_valid_o = obi_rvalid_i;
endmodule
