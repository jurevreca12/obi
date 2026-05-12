package obi_pkg;

// Xbar config
    typedef struct packed {
        int unsigned Managers;
        int unsigned Subordinates;
        int unsigned AddrWidth;
        int unsigned DataWidth;
        int unsigned IdWidth;
        int unsigned MidWidth;
        bit unsigned UseIdForRouting; // if UseIdForRouting = 1 => (IdWidth has to be >$clog2(SrFifoDepth*Subordinates))
        bit unsigned UseSrFifo;
        int unsigned MrFifoDepth;
        int unsigned SrFifoDepth;
        int unsigned NoMaps;
        bit unsigned UseDefaultMap;
        int unsigned DefaultMapIdx;
    } xbar_cfg_t;

    function automatic xbar_cfg_t xbar_default_cfg(
        int unsigned Managers,
        int unsigned Subordinates,
        int unsigned AddrWidth,
        int unsigned DataWidth,
        int unsigned IdWidth
    );
        xbar_default_cfg = '{
            Managers: Managers,
            Subordinates: Subordinates,
            AddrWidth: AddrWidth,
            DataWidth: DataWidth,
            IdWidth: IdWidth,
            MidWidth: int'($clog2(Managers)),
            UseIdForRouting: '0,
            UseSrFifo: '0,
            MrFifoDepth: int'($pow(2,IdWidth)),
            SrFifoDepth: '0,
            NoMaps: Subordinates,
            UseDefaultMap: '0,
            DefaultMapIdx: 0
        };
    endfunction

    function automatic xbar_cfg_t xbar_id_routing_cfg(
        int unsigned Managers,
        int unsigned Subordinates,
        int unsigned AddrWidth,
        int unsigned DataWidth,
        int unsigned IdWidth
    );
        xbar_id_routing_cfg = '{
            Managers: Managers,
            Subordinates: Subordinates,
            AddrWidth: AddrWidth,
            DataWidth: DataWidth,
            IdWidth: IdWidth,
            MidWidth: int'($clog2(Managers)),
            UseIdForRouting: '1,
            UseSrFifo: '0,
            MrFifoDepth: '0,
            SrFifoDepth: '0,
            NoMaps: Subordinates,
            UseDefaultMap: '0,
            DefaultMapIdx: 0
        };
    endfunction

    typedef enum  {
        MANAGER,
        SUBORDINATE
    } obi_if_type_e;

    function automatic xbar_cfg_t IfTypeXbarCfg(
        xbar_cfg_t XbarCfg,
        obi_if_type_e Type
    );
        IfTypeXbarCfg = XbarCfg;
        if (Type == SUBORDINATE & ~IfTypeXbarCfg.UseSrFifo) begin
            IfTypeXbarCfg.IdWidth = IfTypeXbarCfg.IdWidth + IfTypeXbarCfg.MidWidth;
        end
    endfunction;

    function automatic xbar_cfg_t SubXbarCfg(
        xbar_cfg_t XbarCfg,
        bit unsigned UseSrFifo
    );
        SubXbarCfg = XbarCfg;
        SubXbarCfg.UseSrFifo = UseSrFifo;
    endfunction;

endpackage








