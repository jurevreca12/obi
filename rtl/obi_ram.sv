module obi_ram #(
  parameter  string INIT_FILE="",
  parameter  int    INIT_FILE_BIN=0,
  parameter  int    DATA_WIDTH=32,
  parameter  int    ADDR_WIDTH=32,
  parameter  int    BASE_ADDR,
  parameter  int    MEM_SIZE_WORDS,
  localparam int    NBytes=(DATA_WIDTH / 8),
  localparam int    MemSizeBytes=(MEM_SIZE_WORDS / 8)
  localparam int    EndAddr = BASE_ADDR + MemSizeBytes
) (
  input  logic clk_i,
  input  logic rstn_i,

  input  logic                  obi_areq_i,
  output logic                  obi_agnt_o,
  input  logic [ADDR_WIDTH-1:0] obi_aaddr_i,
  input  logic                  obi_awe_i,
  input  logic [NBytes-1:0]     obi_abe_i,
  input  logic [DATA_WIDTH-1:0] obi_awdata_i,


  output logic                  obi_rvalid_o,
  input  logic                  obi_rready_i,
  output logic [DATA_WIDTH-1:0] obi_rdata_o
);

  typedef struct packed {
    logic [$clog2(MemSizeBytes)-1:2] addr;
    logic [DATA_WIDTH-1:0]           data;
    logic [NBytes-1:0]               strobe;
    logic                            write;
  } obi_req_t;

  obi_req_t act_req;
  logic act_req_valid, act_req_ready, act_req_fire, act_req_fire_r; 

  logic [DATA_WIDTH-1:0] mem_data;
  logic                  rsp_buff_inp_ready; 

  skidbuffer #(
    .DTYPE(obi_req_t)
  ) request_buffer (
    .clk        (clk_i),
    .rstn       (rstn_i),

    .input_valid (obi_areq_i),
    .input_ready (obi_agnt_o),
    .input_data  ({obi_aaddr_i[$clog2(MemSizeBytes)-1:2], obi_awdata_i, obi_abe_i, obi_awe_i}),

    .output_valid(act_req_valid),
    .output_ready(act_req_ready),
    .output_data (act_req)

    // verilator lint_off PINCONNECTEMPTY
    .empty ()
    // verilator lint_on PINCONNECTEMPTY
  );
  assign act_req_ready = obi_rready_i;
  assign act_req_fire = act_req_valid && act_req_ready;

  bytewrite_sram #(
    .WORD_SIZE      (DATA_WIDTH),
    .MEM_INIT_FILE  (INIT_FILE),
    .INIT_FILE_BIN  (INIT_FILE_BIN),
    .MEM_SIZE_WORDS (MEM_SIZE_WORDS)
  ) mem (
    .clk    (clk_i),
    .strobe (act_req.strobe),
    .write  (act_req.write),
    .valid  (act_req_fire),
    .addr   (act_req.addr),
    .din    (act_req.data),
    .dout   (mem_data)
  );

  register req_fire_reg (
    .clk(clk_i), .rstn(rstn_i), .ce(1'b1), .in(act_req_fire), .out(act_req_fire_r)
  );

  skidbuffer #(
    .DTYPE(logic [DATA_WIDHT-1:0])
  ) response_buffer (
    .clk        (clk_i),
    .rstn       (rstn_i),

    .input_valid (act_req_fire_r),
    .input_ready (rsp_buff_inp_ready),
    .input_data  (mem_data),

    .output_valid(obi_rvalid_o),
    .output_ready(obi_rready_i),
    .output_data (obi_rdata_o)

    // verilator lint_off PINCONNECTEMPTY
    .empty ()
    // verilator lint_on PINCONNECTEMPTY
  );

  `ifdef ASSERTIONS
    always_ff @(posedge clk_i) begin
      if (act_req_fire_r)
        no_req_dropped: assert(rsp_buff_inp_ready);
    end
  `endif
endmodule
