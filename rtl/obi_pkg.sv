package obi_pkg;
    
// Xbar config
    typedef struct packed {
        int unsigned Managers;
        int unsigned Subordinates;
        bit unsigned UseSrFifo;
        //bit unsigned UseSrFifoMask;
        //bit unsigned Connectivity; // Connectivity matrix defines connections between Manager-Routers and Subordinate-Routers
        int unsigned NoMaps;
    } xbar_cfg;

    function automatic xbar_cfg xbar_default_cfg(
        int unsigned Managers,
        int unsigned Subordinates 
    );
        xbar_default_cfg = '{
            Managers: Managers,
            Subordinates: Subordinates,
            UseSrFifo: '0,
            //UseSrFifoMask: Subordinates'('0),
            //Connectivity: Subordinates*Managers'('1),
            NoMaps: Subordinates
        };
    endfunction
    
// Obi config
    typedef struct packed {
        int unsigned AddrWidth;
        int unsigned DataWidth;
        int unsigned IdWidth;
        bit unsigned UseIdForRouting; // if UseIdForRouting = 1 => (IdWidth has to be >$clog2(SrFifoDepth*Subordinates))
        int unsigned MrFifoDepth;
        int unsigned SrFifoDepth;
    } obi_cfg;

    function automatic obi_cfg obi_default_cfg( 
        int unsigned AddrWidth, 
        int unsigned DataWidth,
        int unsigned IdWidth
    );
        obi_default_cfg = '{
            AddrWidth: AddrWidth,
            DataWidth: DataWidth,
            IdWidth: IdWidth,
            UseIdForRouting: '0, 
            MrFifoDepth: int'($pow(2,IdWidth)),
            SrFifoDepth: int'($pow(2,IdWidth))
        };
    endfunction

/*

    typedef struct packed{
        logic                           obi_areq;
        logic [ADDR_WIDTH-1:0]          obi_aadr;
        logic                           obi_awe;
        logic [NBytes-1:0]              obi_abe;
        logic [DATA_WIDTH-1:0]          obi_awdata;
        logic [ID_WIDTH-1:0]            obi_aid;
        logic [$clog2(MANAGERS)-1:0]    obi_mid;
    } obi_a;

    typedef struct packed{
        logic                    obi_rvalid;
        logic [DATA_WIDTH-1:0]   obi_rdata;
        logic                    obi_rerr;
        logic [ID_WIDTH-1:0]     obi_rid;
    } obi_r;

    typedef struct {  
        logic [$clog2(SUBORDINATES)-1:0]    idx;
        logic [ADDR_WIDTH-1:0]              base;
        logic [ADDR_WIDTH-1:0]              mask;
    } addr_map;

*/

endpackage








