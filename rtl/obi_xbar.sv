import obi_pkg::obi_a;
import obi_pkg::obi_r;
import obi_pkg::addr_map;

/*
`include "/obi_subordinate_router.sv"
`include "obi_r_if.sv"
`include "obi_a_if.sv"
*/

// OBI XBAR
module obi_xbar #( 
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32,
    parameter int M_ROUTERS = 1,
    parameter int S_ROUTERS = 1,
    parameter int FIFO_DEPTH = 1024,
    parameter int ID_WIDTH = $clog2(FIFO_DEPTH*S_ROUTERS)+1, // ID_WIDTH has to be >$clog2(FIFO_DEPTH*S_ROUTERS)
    parameter int NoMAPS = 1, // Number of mappings in the address map
// Connectivity matrix defines connections between Manager-Routers and Subordinate-Routers
    parameter bit [S_ROUTERS-1:0] [M_ROUTERS-1:0] Connectivity = '1 // By default all managers are connected to all subordinates and vice versa
) 
(
    input   logic clk_i,
    input   logic rstn_i,

// Manager -OBI-> XBAR Manager-Router
    input obi_pkg::obi_a mgr_obi_a_chans [M_ROUTERS], // An OBI A channel for each Manager
    output logic  mgr_obi_agnt_signals [M_ROUTERS],
// Manager <-OBI- XBAR Manager-Router
    output obi_pkg::obi_r mgr_obi_r_chans [M_ROUTERS], // An OBI R channel for each manager
    input logic mgr_obi_rready_signals[M_ROUTERS],

// XBAR Subordinate-Router -OBI-> Subordinate
    output obi_pkg::obi_a sub_obi_a_chans [S_ROUTERS], // An OBI A channel for each Subordinate
    input logic sub_obi_agnt_signals [S_ROUTERS],
// XBAR Subordinate-Router <-OBI- Subordinate
    input obi_pkg::obi_r sub_obi_r_chans [S_ROUTERS], // An OBI R channel for each Subordinate
    output logic sub_obi_rready_signals[S_ROUTERS],

// Address map used to map address space to Subordinates
    input obi_pkg::addr_map addr_map_i [NoMAPS]
);
    localparam int NBytes = DATA_WIDTH / 8;

// XBAR Manager-Routers connections
    obi_pkg::obi_a [M_ROUTERS-1:0] [S_ROUTERS-1:0] mr_obi_a_matrix; // For each Manager there are S_ROUTERS amount of OBI A chan ports (outputs)
    logic [M_ROUTERS-1:0] [S_ROUTERS-1:0]  mr_obi_agnt_matrix;          // For each Manager there are S_ROUTERS amount of OBI agnt signal ports (input)
    obi_pkg::obi_r [M_ROUTERS-1:0] [S_ROUTERS-1:0] mr_obi_r_matrix; // For each Manager there are S_ROUTERS amount of OBI R chan ports (inputs)
    logic [M_ROUTERS-1:0] [S_ROUTERS-1:0]  mr_obi_rready_matrix;        // For each Manager there are S_ROUTERS amount of OBI rready signal ports (output)

// XBAR Subordinate-Routers connections
    obi_pkg::obi_a [S_ROUTERS-1:0] [M_ROUTERS-1:0] sr_obi_a_matrix; // For each Subordinate there are M_ROUTERS amount of OBI A chan ports (inputs)
    logic [S_ROUTERS-1:0] [M_ROUTERS-1:0] sr_obi_agnt_matrix;           // For each Subordinate there are M_ROUTERS amount of OBI agnt signal ports (output)
    obi_pkg::obi_r [S_ROUTERS-1:0] [M_ROUTERS-1:0] sr_obi_r_matrix; // For each Subordinate there are M_ROUTERS amount of OBI R chan ports (outputs)
    logic [S_ROUTERS-1:0] [M_ROUTERS-1:0] sr_obi_rready_matrix;         // For each Subordinate there are M_ROUTERS amount of OBI rready signal ports (input)

// Generate connections between Manager-Routers and Subordinate-Routers based on the Connectivity matrix
    for (genvar s = 0; s<S_ROUTERS; s++) begin : gen_cons_sr
        for (genvar m = 0; m<M_ROUTERS; m++) begin : gen_cons_mr
            if (Connectivity[s][m]) begin : connect
                assign sr_obi_a_matrix[s][m] = mr_obi_a_matrix[m][s];           // Connect mr & sr OBI A chans      
                assign mr_obi_agnt_matrix[m][s] = sr_obi_agnt_matrix[s][m];     // Connect mr & sr OBI agnt signal 

                assign mr_obi_r_matrix[m][s] = sr_obi_r_matrix[s][m];           // Connect mr & sr OBI R chans 
                assign sr_obi_rready_matrix[s][m] = mr_obi_rready_matrix[m][s]; // Connect mr & sr OBI rready signal 
            end
        end
    end
    
// Generate Manager-Routers with defined connections
    for (genvar i = 0; i<M_ROUTERS; i++) begin : gen_mr
        obi_manager_router #(
            ADDR_WIDTH,
            DATA_WIDTH,
            NBytes,
            M_ROUTERS,
            i,
            S_ROUTERS,
            ID_WIDTH,
            NoMAPS
        ) i_manager_router(
            .clk_i(clk_i),
            .rstn_i(rstn_i),
        // Manager-Router <-OBI-> Subordinate-Router
            .obi_a_channels_o(mr_obi_a_matrix[i]),
            .obi_r_channels_i(mr_obi_r_matrix[i]),
            .obi_agnt_array_i(mr_obi_agnt_matrix[i]),
            .obi_rready_array_o(mr_obi_rready_matrix[i]),
        // Manager -OBI-> Manager-Router
            .obi_areq_i(mgr_obi_a_chans[i].obi_areq),
            .obi_aadr_i(mgr_obi_a_chans[i].obi_aadr),
            .obi_awe_i(mgr_obi_a_chans[i].obi_awe),
            .obi_abe_i(mgr_obi_a_chans[i].obi_abe),
            .obi_awdata_i(mgr_obi_a_chans[i].obi_awdata),
            .obi_aid_i(mgr_obi_a_chans[i].obi_aid),
            .obi_agnt_o(mgr_obi_agnt_signals[i]),
        // Manager <-OBI- Manager-Router
            .obi_rready_i(mgr_obi_rready_signals[i]),
            .obi_rdata_o(mgr_obi_r_chans[i].obi_rdata),
            .obi_rerr_o(mgr_obi_r_chans[i].obi_rerr),
            .obi_rvalid_o(mgr_obi_r_chans[i].obi_rvalid),
            .obi_rid_o(mgr_obi_r_chans[i].obi_rid),

            .addr_map_i(addr_map_i)
        );
    end

// Generate Subordinate-Routers with defined connections
    for (genvar i = 0; i<S_ROUTERS; i++) begin : gen_sr
        obi_subordinate_router #(
            M_ROUTERS,
            FIFO_DEPTH,
            ADDR_WIDTH,
            DATA_WIDTH,
            ID_WIDTH,
            M_ROUTERS
        ) i_subordinate_router (
            .clk_i(clk_i),
            .rstn_i(rstn_i),
        // Subordinate-Router <-OBI-> Manager-Router
            .obi_a_channels_i(sr_obi_a_matrix[i]),
            .obi_agnt_array_o(sr_obi_agnt_matrix[i]),
            .obi_r_channels_o(sr_obi_r_matrix[i]),
            .obi_rready_array_i(sr_obi_rready_matrix[i]),
        // Subordinate-Router -OBI-> Subordinate 
            .obi_aadr_o(sub_obi_a_chans[i].obi_aadr),
            .obi_awe_o(sub_obi_a_chans[i].obi_awe),
            .obi_abe_o(sub_obi_a_chans[i].obi_abe),
            .obi_awdata_o(sub_obi_a_chans[i].obi_awdata),
            .req_valid_o(sub_obi_a_chans[i].obi_areq),
            .req_read_i(sub_obi_agnt_signals[i]),
        // Subordinate-Router <-OBI- Subordinate 
            .rsp_write_i(sub_obi_r_chans[i].obi_rvalid),
            .rsp_ready_o(sub_obi_rready_signals[i]),
            .obi_rdata_i(sub_obi_r_chans[i].obi_rdata),
            .obi_rerr_i(sub_obi_r_chans[i].obi_rerr)
        );
    end
endmodule




