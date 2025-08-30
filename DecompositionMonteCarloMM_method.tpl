sqMMDecompositionMonteCarloMM(
    Symbol(),
    OP_BUY,       // 注文種別はロット計算に影響しないためダミーで可
    Ask,          // 価格もロット計算に未使用。将来互換のため渡す
    0.0,          // SL 未使用
    mmBaseLot,
    mmMaxDrawdown,
    mmDecimals,
    mmDebugLogs,
    mmAuditCSV,
    mmEnforceMaxLot,
    mmMaxLotCap,
    mmStep)
