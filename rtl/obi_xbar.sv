
// OBI XBAR
module obi_xbar #(
    parameter obi_pkg::xbar_cfg_t   XbarCfg,

    parameter type                  mgr_obi_a_t,
    parameter type                  mgr_obi_r_t,
    parameter type                  sub_obi_a_t,
    parameter type                  sub_obi_r_t,


    parameter type                  addr_map_t,

    parameter bit unsigned [XbarCfg.Subordinates-1:0] [XbarCfg.Managers-1:0] CONNECTIVITY = '1,
    parameter bit unsigned [XbarCfg.Subordinates-1:0] USE_SR_FIFO_MASK = '0,
    parameter int unsigned SR_FIFO_DEPTHS [XbarCfg.Subordinates] = '{default: '0},

    localparam int NBytes = XbarCfg.DataWidth / 8
)
(
    input   logic   clk_i,
    input   logic   rstn_i,

// Manager -OBI-> XBAR Manager-Router
    input   mgr_obi_a_t   mgr_obi_a_chans         [XbarCfg.Managers], // An OBI A channel for each Manager
    output  logic   mgr_obi_agnt_signals    [XbarCfg.Managers],
// Manager <-OBI- XBAR Manager-Router
    output  mgr_obi_r_t   mgr_obi_r_chans         [XbarCfg.Managers], // An OBI R channel for each manager
    input   logic   mgr_obi_rready_signals  [XbarCfg.Managers],

// XBAR Subordinate-Router -OBI-> Subordinate
    output  sub_obi_a_t   sub_obi_a_chans         [XbarCfg.Subordinates], // An OBI A channel for each Subordinate
    input   logic   sub_obi_agnt_signals    [XbarCfg.Subordinates],
// XBAR Subordinate-Router <-OBI- Subordinate
    input   sub_obi_r_t   sub_obi_r_chans         [XbarCfg.Subordinates], // An OBI R channel for each Subordinate
    output  logic   sub_obi_rready_signals  [XbarCfg.Subordinates],

// Address map used to map address space to Subordinates
    input   addr_map_t    addr_map_i          [XbarCfg.NoMaps]
);

// XBAR OBI A channel struct
  typedef struct packed{
        logic                                   obi_areq;
        logic [XbarCfg.AddrWidth-1:0]           obi_aadr;
        logic                                   obi_awe;
        logic [XbarCfg.DataWidth/8-1:0]         obi_abe;
        logic [XbarCfg.DataWidth-1:0]           obi_awdata;
        logic [XbarCfg.IdWidth-1:0]             obi_aid;
        logic [$clog2(XbarCfg.Managers)-1:0]    obi_mid;
  } xbar_obi_a_t;

// XBAR OBI R channel struct
  typedef struct packed{
        logic                           obi_rvalid;
        logic                           obi_rerr;
        logic [XbarCfg.DataWidth-1:0]   obi_rdata;
        logic [XbarCfg.IdWidth-1:0]     obi_rid;
  } xbar_obi_r_t;

// XBAR Manager-Routers connections
    xbar_obi_a_t    [XbarCfg.Managers-1:0] [XbarCfg.Subordinates-1:0] mr_obi_a_matrix;        // For each Manager there are XbarCfg.Subordinates amount of OBI A chan ports (outputs)
    logic           [XbarCfg.Managers-1:0] [XbarCfg.Subordinates-1:0] mr_obi_agnt_matrix;     // For each Manager there are XbarCfg.Subordinates amount of OBI agnt signal ports (input)
    xbar_obi_r_t    [XbarCfg.Managers-1:0] [XbarCfg.Subordinates-1:0] mr_obi_r_matrix;        // For each Manager there are XbarCfg.Subordinates amount of OBI R chan ports (inputs)
    logic           [XbarCfg.Managers-1:0] [XbarCfg.Subordinates-1:0] mr_obi_rready_matrix;   // For each Manager there are XbarCfg.Subordinates amount of OBI rready signal ports (output)

// XBAR Subordinate-Routers connections
    xbar_obi_a_t    [XbarCfg.Subordinates-1:0] [XbarCfg.Managers-1:0] sr_obi_a_matrix;        // For each Subordinate there are XbarCfg.Managers amount of OBI A chan ports (inputs)
    logic           [XbarCfg.Subordinates-1:0] [XbarCfg.Managers-1:0] sr_obi_agnt_matrix;     // For each Subordinate there are XbarCfg.Managers amount of OBI agnt signal ports (output)
    xbar_obi_r_t    [XbarCfg.Subordinates-1:0] [XbarCfg.Managers-1:0] sr_obi_r_matrix;        // For each Subordinate there are XbarCfg.Managers amount of OBI R chan ports (outputs)
    logic           [XbarCfg.Subordinates-1:0] [XbarCfg.Managers-1:0] sr_obi_rready_matrix;   // For each Subordinate there are XbarCfg.Managers amount of OBI rready signal ports (input)

// Generate connections between Manager-Routers and Subordinate-Routers based on the Connectivity matrix
    for (genvar s = 0; s<XbarCfg.Subordinates; s++) begin : gen_cons_sr
        for (genvar m = 0; m<XbarCfg.Managers; m++) begin : gen_cons_mr
            if (CONNECTIVITY[s][m]) begin : gen_connect
                assign  sr_obi_a_matrix[s][m]       = mr_obi_a_matrix[m][s];        // Connect mr & sr OBI A chans      
                assign  mr_obi_agnt_matrix[m][s]    = sr_obi_agnt_matrix[s][m];     // Connect mr & sr OBI agnt signal 

                assign  mr_obi_r_matrix[m][s]       = sr_obi_r_matrix[s][m];        // Connect mr & sr OBI R chans 
                assign  sr_obi_rready_matrix[s][m]  = mr_obi_rready_matrix[m][s];   // Connect mr & sr OBI rready signal 
            end
        end
    end

// Generate Manager-Routers with defined connections
    for (genvar i = 0; i<XbarCfg.Managers; i++) begin : gen_mr
        obi_manager_router #(
            .XbarCfg            (XbarCfg    ),
            .obi_a_t            (xbar_obi_a_t      ),
            .obi_r_t            (xbar_obi_r_t      ),
            .mgr_obi_a_t        (mgr_obi_a_t),
            .mgr_obi_r_t        (mgr_obi_r_t),
            .addr_map_t         (addr_map_t   ),
            .MANAGER_ID         (i          ) // Manager id (mid)
        ) i_manager_router(
            .clk_i              (clk_i                          ),
            .rstn_i             (rstn_i                         ),
        // Manager-Router <-OBI-> Subordinate-Router
            .obi_a_channels_o   (mr_obi_a_matrix[i]             ),
            .obi_r_channels_i   (mr_obi_r_matrix[i]             ),
            .obi_agnt_array_i   (mr_obi_agnt_matrix[i]          ),
            .obi_rready_array_o (mr_obi_rready_matrix[i]        ),
        // Manager -OBI-> Manager-Router
            .mgr_obi_a_i        (mgr_obi_a_chans[i]             ),
            .obi_agnt_o         (mgr_obi_agnt_signals[i]        ),
        // Manager <-OBI- Manager-Router
            .mgr_obi_r_o        (mgr_obi_r_chans[i]),
            .obi_rready_i       (mgr_obi_rready_signals[i]      ),

            .addr_map_i         (addr_map_i                     )
        );
    end


// Generate Subordinate-Routers with defined connections
    for (genvar i = 0; i<XbarCfg.Subordinates; i++) begin : gen_sr
        obi_subordinate_router #(
            .XbarCfg            (obi_pkg::SubXbarCfg(XbarCfg, USE_SR_FIFO_MASK[i], SR_FIFO_DEPTHS[i])),
            .obi_a_t            (xbar_obi_a_t                                       ),
            .obi_r_t            (xbar_obi_r_t                                       ),
            .sub_obi_a_t        (sub_obi_a_t                                        ),
            .sub_obi_r_t        (sub_obi_r_t                                        ),
            .MANAGERS_CONS      ($countones(CONNECTIVITY[i])                        )
            //.MANAGERS_CONS      (XbarCfg.Managers                                   )
        ) i_subordinate_router (
            .clk_i              (clk_i                          ),
            .rstn_i             (rstn_i                         ),
        // Subordinate-Router <-OBI-> Manager-Router
            .obi_a_channels_i   (sr_obi_a_matrix[i]             ),
            .obi_agnt_array_o   (sr_obi_agnt_matrix[i]          ),
            .obi_r_channels_o   (sr_obi_r_matrix[i]             ),
            .obi_rready_array_i (sr_obi_rready_matrix[i]        ),
        // Subordinate-Router -OBI-> Subordinate
            .sub_obi_a          (sub_obi_a_chans[i]             ),
            .obi_agnt_i         (sub_obi_agnt_signals[i]        ),
        // Subordinate-Router <-OBI- Subordinate
            .sub_obi_r          (sub_obi_r_chans[i]             ),
            .obi_rready_o       (sub_obi_rready_signals[i]      )
        );
    end
endmodule




