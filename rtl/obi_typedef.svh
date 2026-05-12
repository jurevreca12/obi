
// OBI channels structs
`define TYPEDEF_OBI_CHANS(obi_a, obi_r, TYPE, CFG)                  \
    `TYPEDEF_OBI_A_CHAN(obi_a, obi_pkg::IfTypeXbarCfg(CFG, TYPE));  \
    `TYPEDEF_OBI_R_CHAN(obi_r, obi_pkg::IfTypeXbarCfg(CFG, TYPE));  \

// OBI A channel struct
`define TYPEDEF_OBI_A_CHAN(obi_a, CFG)   \
  typedef struct packed{                                                            \
        logic                               obi_areq;                               \
        logic [CFG.AddrWidth-1:0]           obi_aadr;                               \
        logic                               obi_awe;                                \
        logic [CFG.DataWidth/8-1:0]         obi_abe;                                \
        logic [CFG.DataWidth-1:0]           obi_awdata;                             \
        logic [CFG.IdWidth-1:0]             obi_aid;                                \
    } obi_a;

// OBI R channel struct
`define TYPEDEF_OBI_R_CHAN(obi_r, CFG) \
  typedef struct packed{                                    \
        logic                       obi_rvalid;            \
        logic                       obi_rerr;              \
        logic [CFG.DataWidth-1:0]   obi_rdata;             \
        logic [CFG.IdWidth-1:0]     obi_rid;               \
    } obi_r;

// XBAR address map struct
`define TYPEDEF_XBAR_ADDR_MAP(addr_map, ADDR_WIDTH, SUBORDINATES)   \
  typedef struct {                                                  \
        logic [$clog2(SUBORDINATES)-1:0]    idx;                    \
        logic [ADDR_WIDTH-1:0]              base;                   \
        logic [ADDR_WIDTH-1:0]              mask;                   \
    } addr_map;

// XBAR Connectivity
`define TYPEDEF_XBAR_CONNECTIVITY(connectivity, SUBORDINATES, MANAGERS, CONS_MATRIX) \
    localparam bit unsigned [SUBORDINATES-1:0] [MANAGERS-1:0] connectivity = CONS_MATRIX;
