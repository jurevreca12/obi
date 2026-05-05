`define UART_CONF_OFF 7'h00
`define UART_SPEED_OFF 7'h04
`define UART_TX_OFF 7'h08

module obi_uart #(
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
    output logic     obi_rvalid_o,
    input logic      obi_rready_i,
    output logic    [OBI_DATA_WIDTH-1:0] obi_rdata_o,
    output logic                       obi_err_o,
    
    // to fpga pins
    output logic tx
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
    
    // Potential bug here
    // assign local_gnt = (obi_addr_i == `UART_TX_OFF) ? rx_empty : 1'b1; 
    assign obi_gnt_o = rx_empty & !(state == RESP); // when you are in the response phase, you should not accept new requests, so gnt is low. In other states, gnt is high when there is a request
    /*
    always_comb begin
        if(state == ADDR) begin
            if (obi_addr_i[6:0] == `UART_TX_OFF) begin
                obi_gnt_o = rx_empty; // only grant if the tx buffer is not empty and there is a request
            end else if (obi_addr_i[6:0] == `UART_CONF_OFF || obi_addr_i[6:0] == `UART_SPEED_OFF) begin
                obi_gnt_o = 1; // grant for configuration and speed registers without checking the buffer status
            end else begin
                obi_gnt_o = 1'b0; // do not grant for invalid addresses
            end
        end else begin
            obi_gnt_o = 1'b0; // do not grant in response phase
        end
    end
    */
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




    // OBI interface logic
    // Write interface
    logic [2:0] wr_en;
    assign wr_en[0] = state == RESP & latched_we & (latched_addr[6:0] == `UART_CONF_OFF); // Needs to ensure write request is valid and handshake occured in address phase
    assign wr_en[1] = state == RESP & latched_we & (latched_addr[6:0] == `UART_SPEED_OFF); // Needs to ensure write request is valid and handshake occured in address phase
    assign wr_en[2] = state == RESP & latched_we & (latched_addr[6:0] == `UART_TX_OFF); // Needs to ensure write request is valid and handshake occured in address phase
    
    logic tx_start_reg; // register to hold the tx_start signal for the UART FSM, since the tx_start signal needs to be held until the data is transmitted, we need a register for it
    // reg data 0x0
    always_ff @(posedge obi_clk_i) begin
        if (!obi_rstn_i) begin
            tx_start_reg <= 0;
        end else begin
            if (wr_en[0]) begin
                tx_start_reg <= latched_wdata[0];
            end
        end
    end

    // reg data 0x4
    always_ff @(posedge obi_clk_i) begin
        if (!obi_rstn_i) begin
            limit_reg <= 0;
        end else begin
            if (wr_en[1]) begin
                limit_reg <= latched_wdata[15:0];
            end
        end
    end

    // reg data 0x8 
    // interface circuit is register by itself 
    interface_circuit interface_circuit_inst (
        .clock(obi_clk_i),
        .reset(!obi_rstn_i),
        .r_input(latched_wdata[7:0]),
        .write_req(wr_en[2]),
        .read_req(tx_done),
        .rx_empty(rx_empty),
        .r_out(data_out)
    );


    // read interface
    logic rd_en;
    assign rd_en = state == RESP & !latched_we; // read from the GPIO switch register when there is a valid read request and the address is correct

    assign obi_rdata_o = 0; 
    
    
    // APB Slave Error Response
    // write fail, occurs when we write to an invalid address
    logic write_fail;
    assign write_fail = (wr_en && latched_addr[6:0] != `UART_CONF_OFF && latched_addr[6:0] != `UART_SPEED_OFF && latched_addr[6:0] != `UART_TX_OFF) ? 1'b1 : 1'b0;

    assign obi_err_o = 0; // error response for invalid address

    // custom logic for the UART peripheral
    logic rx_empty;
    logic [7:0] data_out;
    logic [15:0] limit_reg;

    
    logic tx_done;
    logic start_uart;

    assign start_uart = tx_start_reg & ~rx_empty;

    transmitter_system transmitter_system_inst (
        .clock(obi_clk_i),
        .reset(!obi_rstn_i),
        .tx_start(start_uart),
        .limit(limit_reg),
        .data_in(data_out),
        .tx(tx),
        .tx_done(tx_done)
    );
endmodule


module baud_rate_generator // General Purpose counter        
    #(parameter PRESCALER_WIDTH = 4)
    (
        input logic clock,
        input logic reset,
        input logic [PRESCALER_WIDTH-1:0] limit,
        output logic baud_rate_tick
    );

    logic [PRESCALER_WIDTH-1:0] count;

    // when the counter reaches the limit, the sample_tick signal is generated

    always_ff @(posedge clock) begin
        if(reset) begin
            count <= 0;
        end else begin
            if(count == limit-1) begin
                count <= 0;
            end else begin
                count <= count + 1;
            end
        end
    end

    assign baud_rate_tick = (count == limit-1);
endmodule

module uart_fsm #(
    parameter DATA_WIDTH = 8
    ) 
(
    input logic clock,
    input logic reset,
    input logic [DATA_WIDTH-1:0] data_in,
    input logic baud_rate_tick,
    input logic tx_start,
    output logic tx,
    output logic tx_done,
    output logic baud_rst // used for baud rate generator reset
);

    // define the states
    typedef enum logic [1:0] { // binary encoding
        IDLE,
        START,
        DATA,
        STOP
    } state_uart_t;
    
 
    state_uart_t state, next_state;

    // signal declarations 
    logic [DATA_WIDTH-1:0] b_reg, b_reg_next;
    logic [3:0] n_counter, n_counter_next; // counter for number of symbols 
    logic tx_done_next, tx_reg, tx_reg_next;


    // state register
    always_ff @(posedge clock) begin
        if (reset) begin
            state <= IDLE;
            b_reg <= 0;
            n_counter <= 0;
            tx_reg <= 1; // idle state state of the tx line
        end
        else begin
            state <= next_state;
            b_reg <= b_reg_next;
            n_counter <= n_counter_next;
            tx_reg <= tx_reg_next;
        end
    end

    // state transition logic
    always_comb begin
        next_state = state;
        b_reg_next = b_reg;
        n_counter_next = n_counter;
        tx_done = 0;
        tx_reg_next = tx_reg;
        baud_rst = 1'b0;

        case (state)
            IDLE : begin
                if(tx_start) begin
                    next_state = START;
                    b_reg_next = data_in;
                    baud_rst = 1'b1;
                end
            end 
            START : begin
                tx_reg_next = 1'b0;
                if (baud_rate_tick) begin
                    next_state = DATA;
                    n_counter_next = 0;
                end
            end
            DATA : begin
                tx_reg_next = b_reg[0];
                if (baud_rate_tick) begin
                    if (n_counter == DATA_WIDTH-1) begin
                        next_state = STOP;
                    end
                    else begin
                        n_counter_next = n_counter + 1;
                        b_reg_next = {1'b0, b_reg[7:1]};
                    end
                end
            end
            STOP : begin
                tx_reg_next = 1'b1;
                if (baud_rate_tick) begin
                    begin
                        next_state = IDLE;
                        tx_done= 1'b1;
                    end
                end
            end
        endcase
    end

    assign tx = tx_reg;
endmodule

module transmitter_system(
    input logic clock,
    input logic reset,
    input logic [15:0] limit, 
    input logic tx_start,
    input logic [7:0] data_in,
    output logic tx,
    output logic tx_done
);

    logic baud_rate_tick;
    logic baud_rst;
    logic local_reset;

    
    assign local_reset = reset | baud_rst;

    baud_rate_generator #(
        .PRESCALER_WIDTH(16)
    ) baud_rate_generator_inst (
        .clock(clock),
        .reset(local_reset),
        .limit(limit),
        .baud_rate_tick(baud_rate_tick)
    );

    uart_fsm #(
        .DATA_WIDTH(8)
    ) uart_fsm_inst (
        .clock(clock),
        .reset(reset),
        .data_in(data_in),
        .baud_rate_tick(baud_rate_tick),
        .tx_start(tx_start),
        .tx(tx),
        .tx_done(tx_done),
        .baud_rst(baud_rst)
    );


endmodule


module interface_circuit #(
    parameter DATA_WIDTH = 8
) (
    input logic clock, 
    input logic reset,
    input logic [DATA_WIDTH-1:0] r_input, 
    input logic write_req, // receiving done  
    input logic read_req, // read uart request 
    output logic rx_empty,
    output logic [DATA_WIDTH-1:0] r_out
);
    
    // one word buffer 
    always_ff @(posedge clock) begin : OneWordBuffer
        if (reset) begin
            r_out <= 0;
        end else begin
            if (write_req) begin
                r_out <= r_input;
            end
        end
    end

    // rx_empty signal generation 
    logic counter;

    always_ff @( posedge clock ) begin : blockName
        if(reset) begin
            counter <= 0;
        end else begin
            if (write_req) begin
                counter <= 1; // data is written to the buffer, not empty anymore
            end else if (read_req) begin
                counter <= 0; // data is read from the buffer, empty again
            end
        end
    end

    assign rx_empty = counter == 0;

endmodule
