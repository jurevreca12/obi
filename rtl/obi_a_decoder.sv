import obi_pkg::addr_map;

// OBI A channel decoder
module obi_a_decoder #(
    parameter int SUBORDINATES = 8,
    parameter int ADDR_WIDTH = 32,
    parameter int NoMAPS = 8
)
(
    input   logic [ADDR_WIDTH-1:0]              req_address_i,
    input   obi_pkg::addr_map                   address_maps_i [NoMAPS], 
    input   logic                               config_ready_i,     
    input   logic                               default_sel_en_i,
    input   logic [SEL_WIDTH-1:0]               default_sel_i,
    output  logic                               address_map_err_o,
    output  logic [SEL_WIDTH-1:0]               obi_a_sel_o

);
    localparam int SEL_WIDTH = $clog2(SUBORDINATES);

    always_comb begin
        obi_a_sel_o = default_sel_en_i ? default_sel_i : '1; // Default obi_a_sel_o signal value
        address_map_err_o = default_sel_en_i ? '0 : 1'b1;   
        for (int i=0; i<NoMAPS; i++) begin
            if (config_ready_i) begin 
            // If overlap, higher index has priority
                if ((address_maps_i[i].base & address_maps_i[i].mask) == (req_address_i & address_maps_i[i].mask)) begin
                    obi_a_sel_o = address_maps_i[i].idx;
                end
            end else begin
                address_map_err_o = 1'b1; // Set err in case of ongoing config
            end
        end
    end

endmodule


