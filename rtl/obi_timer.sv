`define TIMER_CONF_OFF 7'h00
`define TIMER_COUNTL_OFF 7'h04
`define TIMER_COUNTH_OFF 7'h08


module obi_timer #(
    parameter OBI_ADDR_WIDTH = 32,
    parameter OBI_DATA_WIDTH = 32

) (
    // OBI SLAVE INTERFACE
    //***************************************
    input logic obi_clk_i,
    input logic obi_rstn_i,

    // ADDRESS CHANNEL
    input logic                         obi_req_i,
    output  logic                       obi_gnt_o,
    input logic [OBI_ADDR_WIDTH-1:0]    obi_addr_i,
    input logic                         obi_we_i,
    input logic [OBI_DATA_WIDTH-1:0]    obi_wdata_i,
    input logic [               3:0]    obi_be_i,

    // RESPONSE CHANNEL
    input logic      obi_rready_i,
    output logic    obi_rvalid_o,
    output logic    [OBI_DATA_WIDTH-1:0] obi_rdata_o,
    output logic                       obi_err_o

);
    
    logic latch_addr; // control signals to latch address and response data at the end of address and response phases respectively

    // slave FSM states
    typedef enum logic {
        ADDR,
        RESP
    } state_t;
    state_t state, next_state;

    always_ff @(posedge obi_clk_i) begin
        if (!obi_rstn_i) begin
            state <= ADDR;
        end else begin
            state <= next_state;
        end
    end

    always_comb begin : OBI_SLAVE_next_state
        next_state = state;
        latch_addr = 1'b0; // default value for latch_addr
        case (state)
            ADDR: begin
                if (obi_gnt_o & obi_req_i) begin
                    next_state = RESP;
                    latch_addr = 1'b1; // latch address at the end of address phase
                end
            end
            RESP: begin
                if (obi_rvalid_o & obi_rready_i) begin
                    next_state = ADDR;
                end
            end
        endcase
    end

    // generate grant and rvalid signals based on the current state of the FSM
    
    assign obi_gnt_o = 1'b1 & !(state == RESP); // when you are in the response phase, you should not accept new requests, so gnt is low. In other states, gnt is high when there is a request
    assign obi_rvalid_o = 1'b1 & (state == RESP); // rvalid is high when you are in the response phase and there is no error
    
    
    // OBI Write interface 
    // Latching address and write data at the end of address phase to use in response phase

    logic [OBI_ADDR_WIDTH-1:0] latched_addr;
    logic [OBI_DATA_WIDTH-1:0] latched_wdata;
    logic latched_we;

    always_ff @(posedge obi_clk_i) begin
        if (!obi_rstn_i) begin
            latched_addr <= 0;
            latched_wdata <= 0;
            latched_we <= 0;
        end else begin
            if (latch_addr) begin
                latched_addr <= obi_addr_i;
                latched_wdata <= obi_wdata_i;
                latched_we <= obi_we_i;
            end 
        end
    end 



    logic [31:0] timer_config;
    logic wr_en;
    assign wr_en = state == RESP & latched_we & (latched_addr[6:0] == `TIMER_CONF_OFF); // Needs to ensure write request is valid and handshake occured in address phase

  
    // reg data 0x0
    always_ff @(posedge obi_clk_i) begin
        if (!obi_rstn_i) begin
            timer_config <= 0;
        end else begin
            if (wr_en) begin
                timer_config <= latched_wdata;
            end
        end
    end

    // OBI read interface
    logic rd_en[1:0];
    assign rd_en[0] = state == RESP & !latched_we & (latched_addr[6:0] == `TIMER_COUNTL_OFF); // read from the TIMER_COUNTL register when there is a valid read request and the address is correct
    assign rd_en[1] = state == RESP & !latched_we & (latched_addr[6:0] == `TIMER_COUNTH_OFF); // read from the TIMER_COUNTH register when there is a valid read request and the address is correct  
    
    // forwarding response data
    logic [OBI_DATA_WIDTH-1:0] latched_rdata;
    always_comb begin
        if(rd_en[0]) begin
            obi_rdata_o = timer_count[31:0];
        end else if (rd_en[1]) begin
            obi_rdata_o = timer_count[63:32];
        end else begin
            obi_rdata_o = 32'b0; // for invalid read requests, return 0
        end
    end


    // Timer logic
    logic [63:0] timer_count;
    logic timer_start, timer_reset;

    assign timer_start = timer_config[0];
    assign timer_reset = timer_config[1]; 

    always_ff @(posedge obi_clk_i) begin
        if (!obi_rstn_i) begin
            timer_count <= 0;
        end else begin
            if(timer_start) begin
                if(timer_reset) begin
                    timer_count <= 0;
                end else begin
                    timer_count <= timer_count + 1;
                end
            end
        end
    end
  
    
    logic invalid_read;
    assign invalid_read = !latched_we & (obi_gnt_o & obi_req_i) & !( (latched_addr[6:0] == `TIMER_COUNTL_OFF) | (latched_addr[6:0] == `TIMER_COUNTH_OFF) ); // invalid read when there is a read request but the address is not correct

    logic invalid_write;
    assign invalid_write = latched_we & (obi_gnt_o & obi_req_i) & !(latched_addr[6:0] == `TIMER_CONF_OFF);
    assign obi_err_o = invalid_write | invalid_read; // error response for invalid address

endmodule


