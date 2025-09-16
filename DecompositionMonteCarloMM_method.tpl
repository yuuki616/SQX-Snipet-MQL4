<#-- ========== DMCMM method (lot sizing entry point) ========== -->
double DMCMM_ComputeLot() {
    // --- broker constraints ---
    DMCMM_MinLot  = MarketInfo(Symbol(), MODE_MINLOT);
    DMCMM_LotStep = MarketInfo(Symbol(), MODE_LOTSTEP);
    if(DMCMM_MinLot <= 0.0)  DMCMM_MinLot = 0.01;
    if(DMCMM_LotStep <= 0.0) DMCMM_LotStep = 0.01;

    // --- parameter guard ---
    if(BaseLot <= 0.0) {
        Print("[DMCMM] BaseLot must be positive. Using minimal lot size.");
        double fallback = DMCMM_MinLot;
        if(fallback <= 0.0) fallback = DMCMM_LotStep;
        if(fallback <= 0.0) fallback = 0.01;
        DMCMM_curBet = NormalizeDouble(fallback, Decimals);
        return DMCMM_curBet;
    }

    // --- first-time init ---
    if(!DMCMM_initialized) {
        DMCMM_ResetCycle();
        DMCMM_processedOrdersCount = 0;
        DMCMM_initialized = true;
    }

    // --- process new closed orders ---
    int histTotal = OrdersHistoryTotal();
    if(histTotal < DMCMM_processedOrdersCount) {
        DMCMM_processedOrdersCount = 0;
    }
    if(histTotal > DMCMM_processedOrdersCount) {
        for(int index = DMCMM_processedOrdersCount; index < histTotal; index++) {
            if(!OrderSelect(index, SELECT_BY_POS, MODE_HISTORY)) {
                continue;
            }
            if(OrderSymbol() != Symbol()) {
                continue;
            }
            if(OrderMagicNumber() != MagicNumber) {
                continue;
            }

            double openPrice  = OrderOpenPrice();
            double closePrice = OrderClosePrice();
            if(closePrice == openPrice) {
                continue;
            }

            int type = OrderType();
            bool isWin = false;
            if(type == OP_BUY || type == OP_BUYLIMIT || type == OP_BUYSTOP) {
                isWin = (closePrice > openPrice);
            } else if(type == OP_SELL || type == OP_SELLLIMIT || type == OP_SELLSTOP) {
                isWin = (closePrice < openPrice);
            } else {
                isWin = (closePrice > openPrice);
            }

            double betForTrade = DMCMM_curBet;
            if(isWin) {
                DMCMM_cycleProfit += betForTrade;
                DMCMM_ProcessWin();
            } else {
                DMCMM_cycleProfit -= betForTrade;
                DMCMM_ProcessLoss();
            }

            if(MaxDrawdown > 0.0 && DMCMM_cycleProfit < -MaxDrawdown) {
                DMCMM_ResetCycle();
            } else {
                DMCMM_UpdateCurrentBet();
            }
        }
        DMCMM_processedOrdersCount = histTotal;
    }

    // --- output lot (rounded) ---
    double lots = DMCMM_curBet;
    if(DMCMM_LotStep > 0.0) {
        lots = MathFloor(lots / DMCMM_LotStep + 1e-8) * DMCMM_LotStep;
    }
    lots = NormalizeDouble(lots, Decimals);
    if(lots < DMCMM_MinLot) {
        lots = DMCMM_MinLot;
    }
    return lots;
}
