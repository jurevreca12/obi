module obi_timer #(
    parameter int unsigned ADDR_WIDTH = 32,
    parameter int unsigned DATA_WIDTH = 32
) (
    input logic clk_i,
    input logic rstn_i,

    input   logic                     obi_areq_i,
    output  logic                     obi_agnt_o,
    input   logic [ADDR_WIDTH-1:0]    obi_aaddr_i,
    input   logic [DATA_WIDTH-1:0]    obi_awdata_i,

    input   logic                     obi_awe_i,
    input   logic [DATA_WIDTH/8-1:0]  obi_abe_i,

    output  logic                     obi_rvalid_o,
    input   logic                     obi_rready_i,
    output  logic [DATA_WIDTH-1:0]    obi_rdata_o,
    output  logic                     obi_rerr_o,

    // Output complete
    output  logic                     overflow_o
);
    
    localparam int unsigned mTimerConfRegOffset = 0;
    localparam int unsigned mTimerLow32RegOffset = 4; 
    localparam int unsigned mTimerHigh32RegOffset = 8;
    localparam int unsigned mTimerCMPLow32RegOffset = 12; 
    localparam int unsigned mTimerCMPHigh32RegOffset = 16;

    logic [DATA_WIDTH-1:0] counter_low;
    logic [DATA_WIDTH-1:0] counter_high;
    logic [DATA_WIDTH-1:0] compare_low;
    logic [DATA_WIDTH-1:0] compare_high;
    logic [DATA_WIDTH-1:0] timer_conf;
    logic [63:0] cnt_reg; 

    // OBI wrapper signals
    typedef enum logic {
        ADDR,
        RESP
    } state_t;
    state_t state, next_state;

    logic obi_a_fire;
    logic obi_r_fire;
    logic capture;


    // Write interface signals
    logic wr_en[2:0]; 
    logic [DATA_WIDTH-1:0] write_data_mask;


    // Read interface signals
    logic rd_en;


    // BEGIN: OBI wrapper
    register  #(
        .DTYPE(state_t),
        .RESET_VALUE(ADDR)     
    ) obi_fsm_state_reg
        (
        .clk(clk_i),
        .rstn(rstn_i),
        .ce(1'b1), // Always enable to capture the input state
        .in(next_state),
        .out(state)
    );

    assign obi_a_fire = obi_areq_i && obi_agnt_o;
    assign obi_r_fire = obi_rready_i && obi_rvalid_o;

    // State transition logic
    always_comb begin : OBI_SLAVE_next_state
        next_state = state;
        case (state)
            ADDR: begin
                if (obi_a_fire) begin // handshake for address phase, when there is a valid request and the slave is granted access to the bus, move to response phase
                    next_state = RESP;
                end
            end
            RESP: begin
                if (obi_r_fire) begin // handshake for response phase, when there is a valid response and the master is ready to accept it, move back to address phase
                    next_state = ADDR;
                end
            end
        endcase
    end

    assign obi_agnt_o = (state == ADDR); // Grant access to the bus during address phase
    assign obi_rvalid_o = (state == RESP); // Grant access to the bus during response phase

    // END: OBI wrapper

    // BEGIN: OBI write interface
    
    assign wr_en[0] = state == RESP & obi_awe_i & (obi_aaddr_i[6:0] == mTimerConfRegOffset); // Needs to ensure write request is valid and handshake occured in address phase
    assign wr_en[1] = state == RESP & obi_awe_i & (obi_aaddr_i[6:0] == mTimerCMPLow32RegOffset); // Write enable for compare low register
    assign wr_en[2] = state == RESP & obi_awe_i & (obi_aaddr_i[6:0] == mTimerCMPHigh32RegOffset); // Write enable for compare high register

    assign write_data_mask = {{8{obi_abe_i[3]}},{8{obi_abe_i[2]}},{8{obi_abe_i[1]}},{8{obi_abe_i[0]}}}; 


    register  #(
        .DTYPE(logic [DATA_WIDTH-1:0]),
        .RESET_VALUE('0)     
    ) timer_conf_reg
        (
        .clk(clk_i),
        .rstn(rstn_i),
        .ce(wr_en[0]),
        .in(obi_awdata_i[DATA_WIDTH-1:0] & write_data_mask[DATA_WIDTH-1:0]),
        .out(timer_conf)
    );


    register  #(
        .DTYPE(logic [DATA_WIDTH-1:0]),
        .RESET_VALUE('0)     
    ) compare_low_reg
        (
        .clk(clk_i),
        .rstn(rstn_i),
        .ce(wr_en[1]),
        .in(obi_awdata_i & write_data_mask), // Apply byte-enable mask to the incoming data
        .out(compare_low)
    );

    register  #(
        .DTYPE(logic [DATA_WIDTH-1:0]),
        .RESET_VALUE('0)     
    ) compare_high_reg
        (
        .clk(clk_i),
        .rstn(rstn_i),
        .ce(wr_en[2]),
        .in(obi_awdata_i & write_data_mask), // Apply byte-enable mask to the incoming data
        .out(compare_high)
    );
    // END: OBI write interface

    // BEGIN: OBI read interface
    assign rd_en = state == RESP & !obi_awe_i ; 

    always_comb begin 
        obi_rdata_o = '0; // Default to zero
        if(rd_en) begin
            case(obi_aaddr_i[6:0])
                mTimerConfRegOffset: obi_rdata_o =  timer_conf; // Zero-extend timer config register
                mTimerCMPLow32RegOffset: obi_rdata_o = compare_low; // Zero-extend compare low register
                mTimerCMPHigh32RegOffset: obi_rdata_o =  compare_high; // Zero-extend compare high register
                mTimerLow32RegOffset: obi_rdata_o =  counter_low; // Zero-extend counter low register
                mTimerHigh32RegOffset: obi_rdata_o =  counter_high; // Zero-extend counter high register
                default: obi_rdata_o = '0; // Default to zero for unmapped addresses
            endcase
        end 
    end


    // END: logic for OBI read interface

    // Counter logic

    cntr #(
        .WORD_WIDTH(64),
        .RESET_VALUE(0)
    ) counter (
        .clk(clk_i),
        .rstn(rstn_i & ~timer_conf[1]), // Reset counter 
        .ce(timer_conf[0]), // Always enable the counter to count every cycle
        .count(cnt_reg)
    );

    assign counter_low = cnt_reg[DATA_WIDTH-1:0];
    assign counter_high = cnt_reg[63:DATA_WIDTH];

    assign overflow_o = cnt_reg >= {compare_high, compare_low};


    // error handling logic
    always_comb begin 
        obi_rerr_o = 1'b0; // Default to no error
        if (state == RESP) begin // Only check for read errors during response phase for read transactions
            case(obi_aaddr_i[6:0])
                mTimerConfRegOffset, mTimerCMPLow32RegOffset, mTimerCMPHigh32RegOffset, mTimerLow32RegOffset, mTimerHigh32RegOffset: obi_rerr_o = 1'b0; // Valid addresses
                default: obi_rerr_o = 1'b1; // Invalid address
            endcase
        end
    end

endmodule


// -----------------------------------------------------------------------------
// Instantiation template: obi_timer
// -----------------------------------------------------------------------------
/*
obi_timer #(
    .ADDR_WIDTH(32),
    .DATA_WIDTH(32)
) i_obi_timer (
    .clk_i       (),
    .rstn_i      (),
    .obi_areq_i  (),
    .obi_agnt_o  (),
    .obi_aaddr_i (),
    .obi_awdata_i(),
    .obi_awe_i   (),
    .obi_abe_i   (),
    .obi_rvalid_o(),
    .obi_rready_i(obi_rready_i),
    .obi_rdata_o (obi_rdata_o),
    .obi_rerr_o  (obi_rerr_o),
    .overflow_o  (overflow_o)
);
*/