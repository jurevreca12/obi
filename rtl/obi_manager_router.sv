
// OBI Manager-Router
module obi_manager_router #(
    parameter obi_pkg::xbar_cfg_t XbarCfg,
    //parameter obi_pkg::obi_cfg  ObiCfg,

    parameter type              obi_a_t,
    parameter type              obi_r_t,
    parameter type              mgr_obi_a_t,
    parameter type              mgr_obi_r_t,
    parameter type              addr_map_t,

    parameter bit [$clog2(XbarCfg.Managers)-1:0] MANAGER_ID = '0,

    localparam int SelWidth = $clog2(XbarCfg.Subordinates)
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
    input   mgr_obi_a_t                     mgr_obi_a_i,
// Manager <-OBI_A- XBAR Manager-Router
    output  logic                           obi_agnt_o,

// Manager -OBI_R-> XBAR Manager-Router
    input   logic                           obi_rready_i,
// Manager <-OBI_R- XBAR Manager-Router
    output  mgr_obi_r_t                     mgr_obi_r_o,

// Address map used to map address space to Subordinates
    input   addr_map_t    addr_map_i  [XbarCfg.NoMaps]
);

// OBI Manager-Router -OBI_A-> Subordinate-Router
    obi_a_t   obi_a;
    always_comb begin
        obi_a.obi_areq   =   mgr_obi_a_i.obi_areq;
        obi_a.obi_aadr   =   mgr_obi_a_i.obi_aadr;
        obi_a.obi_awe    =   mgr_obi_a_i.obi_awe;
        obi_a.obi_abe    =   mgr_obi_a_i.obi_abe;
        obi_a.obi_awdata =   mgr_obi_a_i.obi_awdata;
        obi_a.obi_aid    =   mgr_obi_a_i.obi_aid;
        obi_a.obi_mid    =   MANAGER_ID;
    end

// OBI Manager-Router <-OBI_A- Subordinate-Router
    obi_r_t   obi_r;
    always_comb begin
        mgr_obi_r_o.obi_rdata   =   obi_r.obi_rdata;
        mgr_obi_r_o.obi_rerr    =   obi_r.obi_rerr;
        mgr_obi_r_o.obi_rvalid  =   obi_r.obi_rvalid;
        mgr_obi_r_o.obi_rid     =   obi_r.obi_rid;
    end

    // Select signals used for routing
    logic   [SelWidth-1:0]    obi_a_sel;
    logic   [SelWidth-1:0]    obi_r_sel;
    // Addr map
    logic   address_map_err;
    // Outstanding id that, can be aid value or idx of OBI chan
    logic   [XbarCfg.IdWidth-1:0]   outstanding_id;
    // Signal is high when a response was granted
    logic rsp_granted;
    // Signal is high when a request is able to be routed
    logic request_route;
    // Signal is high when a response is able to be routed
    logic response_route;

    // OBI A channel decoder
    always_comb begin
        obi_a_sel = XbarCfg.UseDefaultMap ? XbarCfg.DefaultMapIdx : '0;    // Default obi_a_sel signal value (default subordinate)
        for (int i=0; i<XbarCfg.NoMaps; i++) begin
            // Check if req_address is a member of any of the maps, if overlap, higher index has priority
            if ((addr_map_i[i].base & addr_map_i[i].mask) == (obi_a.obi_aadr & addr_map_i[i].mask)) begin
                obi_a_sel = addr_map_i[i].idx;    // Set select signal = idx of matching map
            end
        end
    end

    // OBI R channel decoder
    always_comb begin
        rsp_granted = '0;
        obi_r_sel   = '0;
        if (XbarCfg.UseIdForRouting) begin
            for (int i=0; i<XbarCfg.Subordinates; i++) begin
                if (obi_r_channels_i[i].obi_rvalid & (obi_r_channels_i[i].obi_rid == outstanding_id)) begin
                    obi_r_sel   = i;
                    rsp_granted = '1;
                end
            end
        end else if (~XbarCfg.UseIdForRouting) begin
            obi_r_sel   = outstanding_id;
            rsp_granted = '1;
        end
    end


    // OBI A channel routing
    always_comb begin
        obi_a_channels_o = '{default: '0};
        obi_agnt_o = '0;
        if (request_route) begin
            obi_a_channels_o[obi_a_sel] = obi_a;
            obi_agnt_o = obi_agnt_array_i[obi_a_sel];
        end
    end

    // OBI R channel routing
    always_comb begin
        obi_rready_array_o = '{default: '0};
        obi_r = '0;
        if (response_route) begin
            obi_r = obi_r_channels_i[obi_r_sel];
            obi_rready_array_o[obi_r_sel] = obi_rready_i;
        end
    end

    if (XbarCfg.UseIdForRouting) begin : gen_id_cnt
        localparam int CntRstValue  = '0;

        logic   cnt_next; // Signal used to increment counter (id)
        assign  cnt_next = obi_rready_i & obi_r.obi_rvalid;

        linear_cnt #(
            .RESET_VALUE    (CntRstValue    ),
            .WIDTH          (XbarCfg.IdWidth ),
            .USE_CNT_NEXT   (XbarCfg.UseIdForRouting     )
        ) id_cnt (
            .clk_i          (clk_i          ),
            .rstn_i         (rstn_i         ),
            .cnt_next_i     (cnt_next       ),
            .cnt_value_o    (outstanding_id )
        );

        assign request_route = obi_a.obi_areq;
        assign response_route = rsp_granted;
    end

    if (~XbarCfg.UseIdForRouting) begin : gen_id_fifo
        logic   id_wr_en;
        logic   id_rd_en;
        logic   [XbarCfg.IdWidth-1:0]    id_data_in;
        logic   [XbarCfg.IdWidth-1:0]    id_data_out;
        logic   id_fifo_empty;
        logic   id_fifo_full;

        assign  id_wr_en        =   obi_a.obi_areq & obi_agnt_o;
        assign  id_rd_en        =   obi_r.obi_rvalid & obi_rready_i;
        assign  id_data_in      =   obi_a_sel;

        fifo_lop #(
            .DTYPE      (logic [SelWidth-1:0] ),
            .DEPTH      (XbarCfg.MrFifoDepth         )
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

        assign  outstanding_id  = id_data_out;
        assign  request_route   = obi_a.obi_areq & ~id_fifo_full;
        assign  response_route  = rsp_granted & ~id_fifo_empty;

    end

endmodule
