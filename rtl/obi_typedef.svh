
// OBI A channel struct
`define TYPEDEF_OBI_A_CHAN(obi_a, ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, MANAGERS)   \
  typedef struct packed{                                                        \
        logic                           obi_areq;                               \
        logic [ADDR_WIDTH-1:0]          obi_aadr;                               \
        logic                           obi_awe;                                \
        logic [DATA_WIDTH/8-1:0]        obi_abe;                                \
        logic [DATA_WIDTH-1:0]          obi_awdata;                             \
        logic [ID_WIDTH-1:0]            obi_aid;                                \
        logic [$clog2(MANAGERS)-1:0]    obi_mid;                                \
    } obi_a;            

// OBI R channel struct
`define TYPEDEF_OBI_R_CHAN(obi_r, DATA_WIDTH, ID_WIDTH) \
  typedef struct packed{                                \
        logic                    obi_rvalid;            \
        logic                    obi_rerr;              \
        logic [DATA_WIDTH-1:0]   obi_rdata;             \
        logic [ID_WIDTH-1:0]     obi_rid;               \
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
