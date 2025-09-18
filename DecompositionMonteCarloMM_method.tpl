<#-- ========== Decomposition Monte Carlo MM method (lot sizing entry point) ========== -->
// 呼び出し例: double lots = DMCMM_ComputeLot();

double DMCMM_ComputeLot() {
    DMCMM_MinLot  = MarketInfo(Symbol(), MODE_MINLOT);
    DMCMM_LotStep = MarketInfo(Symbol(), MODE_LOTSTEP);
    if(DMCMM_MinLot <= 0.0)  DMCMM_MinLot  = 0.01;
    if(DMCMM_LotStep <= 0.0) DMCMM_LotStep = 0.01;

    if(BaseLot <= 0.0) {
        Print("[DMCMM] BaseLot must be positive. Fallback to minimum lot.");
        DMCMM_curBet = DMCMM_MinLot;
    }

    if(!DMCMM_initialized) {
        DMCMM_ResetCycle();
        DMCMM_histCount   = OrdersHistoryTotal();
        DMCMM_initialized = true;
    }

    int histTotal = OrdersHistoryTotal();
    if(histTotal > DMCMM_histCount) {
        for(int i = DMCMM_histCount; i < histTotal; i++) {
            if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY)) continue;
            if(OrderSymbol() != Symbol())                  continue;
            if(OrderMagicNumber() != MagicNumber)          continue;

            double openPrice  = OrderOpenPrice();
            double closePrice = OrderClosePrice();
            if(closePrice == openPrice) continue;

            int  orderType = OrderType();
            bool isWin;
            if(orderType == OP_BUY || orderType == OP_BUYLIMIT || orderType == OP_BUYSTOP) {
                isWin = (closePrice > openPrice);
            } else {
                isWin = (closePrice < openPrice);
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
        DMCMM_histCount = histTotal;
    }

    double lots = DMCMM_curBet;
    lots = MathFloor(lots / DMCMM_LotStep) * DMCMM_LotStep;
    lots = NormalizeDouble(lots, Decimals);
    if(lots < DMCMM_MinLot) lots = DMCMM_MinLot;
    return(lots);
}
