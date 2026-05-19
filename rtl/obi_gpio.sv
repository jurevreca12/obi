
`define GPIO_SW_OFF 7'h00
`define GPIO_LEDS_OFF 7'h04



module obi_gpio #(
    parameter OBI_ADDR_WIDTH = 32,
    parameter OBI_DATA_WIDTH = 32

) (
    // GPIO interface
    input logic [15:0] switches,          // GPIO input line
    output logic [15:0] leds,             // GPIO output line
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
                if (obi_gnt_o & obi_req_i) begin // handshake for address phase, when there is a valid request and the slave is granted access to the bus, move to response phase
                    next_state = RESP;
                    latch_addr = 1'b1; // latch address at the end of address phase
                end
            end
            RESP: begin
                if (obi_rvalid_o & obi_rready_i) begin // handshake for response phase, when there is a valid response and the master is ready to accept it, move back to address phase
                    next_state = ADDR;
                end
            end
        endcase
    end

    // generate grant and rvalid signals based on the current state of the FSM
    
    assign obi_gnt_o = 1'b1 & !(state == RESP); // when you are in the response phase, you should not accept new requests, so gnt is low. In other states, gnt is high when there is a request
    assign obi_rvalid_o = 1'b1 & (state == RESP); // rvalid is high when you are in the response phase and there is no error
    
    
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


    // forwarding response data
    logic [OBI_DATA_WIDTH-1:0] latched_rdata;
    always_comb begin
        if (state == RESP) begin
            if (!latched_we && (latched_addr[6:0] == `GPIO_SW_OFF)) begin
                obi_rdata_o = {16'b0, switches}; // read response with switch states in the lower 16 bits
            end else begin
                obi_rdata_o = 32'b0; // for invalid read requests, return 0
            end
         end else begin 
            obi_rdata_o = 32'b0; // when not in response phase, rdata is 0
         end
    end

    // OBI interface logic
    // Write interface
    logic wr_en;
    assign wr_en = state == RESP & latched_we & (latched_addr[6:0] == `GPIO_LEDS_OFF); // Needs to ensure write request is valid and handshake occured in address phase

  
    // reg data 0x0
    always_ff @(posedge obi_clk_i) begin
        if (!obi_rstn_i) begin
            leds <= 0;
        end else begin
            if (wr_en) begin
                leds <= latched_wdata[15:0];
            end
        end
    end

    logic rd_en;
    assign rd_en = state == RESP & !latched_we & (latched_addr[6:0] == `GPIO_SW_OFF); // read from the GPIO switch register when there is a valid read request and the address is correct

    // generation of read data for read response
    always_comb begin
        if (rd_en) begin
            latched_rdata = {16'b0, switches};
        end else begin
            latched_rdata = 32'b0;
        end
    end
    
    logic invalid_read;
    assign invalid_read = !latched_we & (obi_gnt_o & obi_req_i) & !(latched_addr[6:0] == `GPIO_SW_OFF); // invalid read when there is a read request but the address is not correct

    logic invalid_write;
    assign invalid_write = latched_we & (obi_gnt_o & obi_req_i) & !(latched_addr[6:0] == `GPIO_LEDS_OFF);
    assign obi_err_o = invalid_write | invalid_read; // error response for invalid address

endmodule


