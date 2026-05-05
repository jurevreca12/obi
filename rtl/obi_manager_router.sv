
// OBI Manager-Router
module obi_manager_router #(
    parameter obi_pkg::xbar_cfg XbarCfg,
    parameter obi_pkg::obi_cfg  ObiCfg,

    parameter type              obi_a_t,
    parameter type              obi_r_t,
    parameter type              addr_map_t,

    parameter bit [$clog2(XbarCfg.Managers)-1:0] MANAGER_ID = '0
)
(
    input   logic   clk_i,
    input   logic   rstn_i,

// OBI A channels, Switch -OBI-> Subordinate-Router
    output  obi_a_t   [XbarCfg.Subordinates-1:0]  obi_a_channels_o,
// OBI agnt signal, Switch <-OBI- Subordinate-Router
    input   logic   [XbarCfg.Subordinates-1:0]  obi_agnt_array_i,

// OBI R channels, Switch <-OBI- Subordinate-Router
    input   obi_r_t   [XbarCfg.Subordinates-1:0]  obi_r_channels_i,
// OBI rready signal, Switch -OBI-> Subordinate-Router
    output  logic   [XbarCfg.Subordinates-1:0]  obi_rready_array_o,
    
// Manager -OBI_A-> XBAR Manager-Router
    input   logic                           obi_areq_i,
    input   logic   [ObiCfg.AddrWidth-1:0]  obi_aadr_i,
    input   logic                           obi_awe_i,
    input   logic   [NBytes-1:0]            obi_abe_i,
    input   logic   [ObiCfg.DataWidth-1:0]  obi_awdata_i,
    input   logic   [ObiCfg.IdWidth-1:0]    obi_aid_i,
// Manager <-OBI_A- XBAR Manager-Router
    output  logic                           obi_agnt_o,

// Manager -OBI_R-> XBAR Manager-Router
    input   logic                           obi_rready_i,
// Manager <-OBI_R- XBAR Manager-Router
    output  logic   [ObiCfg.DataWidth-1:0]  obi_rdata_o,
    output  logic                           obi_rerr_o,
    output  logic                           obi_rvalid_o,
    output  logic   [ObiCfg.IdWidth-1:0]    obi_rid_o,

// Address map used to map address space to Subordinates
    input   addr_map_t    addr_map_i  [XbarCfg.NoMaps]
);
    localparam int NBytes = ObiCfg.DataWidth / 8;

    logic   obi_rready; // This rready is the value of rready the Subordinate-Router recieves
    logic   obi_agnt;   // This agnt is the value of agnt the Manager-Router recieves
    logic   obi_areq;   // This areq is the value of areq the Subordinate-Router recieves
    logic   obi_rvalid; // this rvalid is the value of rvalid the Manager-Router recieves

// OBI Manager-Router -OBI_A-> Subordinate-Router
    obi_a_t   obi_a;
    always_comb begin
        obi_a.obi_areq   =   obi_areq;
        obi_a.obi_aadr   =   obi_aadr_i;
        obi_a.obi_awe    =   obi_awe_i;
        obi_a.obi_abe    =   obi_abe_i;
        obi_a.obi_awdata =   obi_awdata_i;
        obi_a.obi_aid    =   obi_aid_i;
        obi_a.obi_mid    =   MANAGER_ID;
    end

// OBI Manager-Router <-OBI_A- Subordinate-Router
    obi_r_t   obi_r;
    always_comb begin
        obi_rdata_o      =   obi_r.obi_rdata;
        obi_rerr_o       =   obi_r.obi_rerr;
        obi_rvalid       =   obi_r.obi_rvalid;
        obi_rid_o        =   obi_r.obi_rid;
    end


// Select signals used for switching by the OBI Switch
    logic   [$clog2(XbarCfg.Subordinates)-1:0]    obi_a_sel;
    logic   [XbarCfg.Subordinates-1:0]            obi_r_sel;

// Enable signal for setting next rid
    logic   set_next;

// Array of rid signals used to compare with expected rid for switching
    logic   [ObiCfg.IdWidth-1:0]    rid_array[XbarCfg.Subordinates];

// Addr map
    logic   address_map_err;
    
// Configure module based on ObiCfg.UseIdForRouting parameter 
    localparam CntRstValue  = 1'b1;
    localparam UseCntNext   = ObiCfg.UseIdForRouting;

    logic   [ObiCfg.IdWidth-1:0]    outstanding_id;
    if (ObiCfg.UseIdForRouting) begin : gen_id_cnt
        logic   cnt_next; // Signal used to increment counter (id)
        assign  cnt_next = obi_rready_i & obi_rvalid_o;
        always_comb begin
            obi_rready      =   obi_rready_i;
            obi_agnt_o      =   obi_agnt;
            obi_areq        =   obi_areq_i;
            obi_rvalid_o    =   obi_rvalid;
        end
        linear_cnt #(
            .RESET_VALUE    (CntRstValue    ),
            .WIDTH          (ObiCfg.IdWidth ),
            .USE_CNT_NEXT   (UseCntNext     )
        ) id_cnt (
            .clk_i          (clk_i          ),
            .rstn_i         (rstn_i         ),
            .cnt_next_i     (cnt_next       ),
            .cnt_value_o    (outstanding_id )
        );
    end 
    else begin : gen_id_fifo
        logic   id_wr_en;
        logic   id_rd_en;
        logic   [ObiCfg.IdWidth-1:0]    id_data_in;
        logic   [ObiCfg.IdWidth-1:0]    id_data_out;
        logic   id_fifo_empty;
        logic   id_fifo_full;

        assign  id_wr_en        =   obi_areq_i & obi_agnt_o;
        assign  id_rd_en        =   obi_rvalid_o & obi_rready;
        assign  id_data_in      =   obi_aid_i;
        assign  outstanding_id  =   id_data_out;
        
        always_comb begin
            obi_agnt_o      =   obi_agnt;
            obi_rready      =   obi_rready_i;
            obi_areq        =   obi_areq_i;
            obi_rvalid_o    =   obi_rvalid;
            if (id_fifo_full) begin
                obi_agnt_o  =   '0;
                obi_areq    =   '0;
            end
            if (id_fifo_empty) begin
                obi_rready  =   '0;
            end       
        end
            
        fifo #(
            .DTYPE      (logic [ObiCfg.IdWidth-1:0] ),
            .DEPTH      (ObiCfg.MrFifoDepth         )
        ) id_fifo (
            .clk_i      (clk_i          ),
            .rstn_i     (rstn_i         ),
            .wr_en_i    (id_wr_en       ),
            .rd_en_i    (id_rd_en       ),
            .full_o     (id_fifo_full   ),
            .empty_o    (id_fifo_empty  ),
            .w_data_i   (id_data_in     ),
            .r_data_o   (id_data_out    )
        );
    end

// OBI Manager-Router Switch
    obi_mr_switch #(
        .obi_a_t              (obi_a_t                  ),
        .obi_r_t              (obi_r_t                  ),

        .SUBORDINATES       (XbarCfg.Subordinates   ),
        .ID_WIDTH           (ObiCfg.IdWidth         ),
        .USE_ID_FOR_ROUTING (ObiCfg.UseIdForRouting )
    ) obi_mr_switch_inst (
        .obi_a_i            (obi_a              ),
        .obi_r_o            (obi_r              ),
        .obi_agnt_o         (obi_agnt           ),
        .obi_rready_i       (obi_rready         ),
        .obi_a_channels_o   (obi_a_channels_o   ),
        .obi_r_channels_i   (obi_r_channels_i   ),
        .obi_agnt_array_i   (obi_agnt_array_i   ),
        .obi_rready_array_o (obi_rready_array_o ),
        .obi_a_sel_i        (obi_a_sel          ),
        .address_map_err_i  (address_map_err    ),
        .obi_r_sel_i        (obi_r_sel          ),
        .set_next_o         (set_next           ),
        .rid_array_o        (rid_array          )
    );

// OBI A channel decoder 
    obi_a_decoder #(
        .addr_map_t         (addr_map_t             ),

        .SUBORDINATES       (XbarCfg.Subordinates   ), 
        .ADDR_WIDTH         (ObiCfg.AddrWidth       ),
        .NoMAPS             (XbarCfg.NoMaps         )
    ) obi_a_decoder_inst (
        .req_address_i      (obi_aadr_i         ),
        .address_maps_i     (addr_map_i         ),
        .config_ready_i     (1'b1               ),
        .default_sel_en_i   ('0                 ),
        .default_sel_i      ('0                 ),
        .address_map_err_o  (address_map_err    ),
        .obi_a_sel_o        (obi_a_sel          )
    );

// OBI R channel decoder
    obi_r_decoder #(
        .SUBORDINATES   (XbarCfg.Subordinates   ),
        .ID_WIDTH       (ObiCfg.IdWidth         )
    ) obi_r_decoder_inst(
        .clk_i          (clk_i          ),
        .rstn_i         (rstn_i         ),
        .outstanding_id (outstanding_id ),
        .rid_array_i    (rid_array      ),
        .obi_r_sel_o    (obi_r_sel      )
    );

endmodule
