<#-- ========== DMCMM class/helper functions ========== -->
double DMCMM_CalcDecimalStep();
double DMCMM_RoundLotToBroker(double rawLots);

double DMCMM_ComputeLot(string symbol, long magicNumber) {
    if(StringLen(symbol) <= 0) {
        symbol = Symbol();
    }

    DMCMM_MinLot  = MarketInfo(symbol, MODE_MINLOT);
    DMCMM_LotStep = MarketInfo(symbol, MODE_LOTSTEP);
    double decimalStep = DMCMM_CalcDecimalStep();
    if(DMCMM_MinLot <= 0.0)  DMCMM_MinLot = decimalStep;
    if(DMCMM_MinLot <= 0.0)  DMCMM_MinLot = 0.01;
    if(DMCMM_LotStep <= 0.0) DMCMM_LotStep = decimalStep;
    if(DMCMM_LotStep <= 0.0) DMCMM_LotStep = DMCMM_MinLot;
    if(DMCMM_LotStep <= 0.0) DMCMM_LotStep = 0.01;
    if(BaseLot <= 0.0) {
        Print("[DMCMM] BaseLot must be positive. Using minimal lot size.");
        double fallback = decimalStep;
        if(fallback <= 0.0) fallback = DMCMM_LotStep;
        if(fallback <= 0.0) fallback = 0.01;
        DMCMM_curBet = NormalizeDouble(fallback, Decimals);
        DMCMM_lastExecutedBet = DMCMM_curBet;
        return DMCMM_RoundLotToBroker(DMCMM_curBet);
    }

    if(!DMCMM_initialized) {
        DMCMM_ResetCycle();
        DMCMM_processedOrdersCount = 0;
        DMCMM_lastCloseTime   = 0;
        DMCMM_lastCloseTicket = -1;
        DMCMM_initialized = true;
    }

    int histTotal = OrdersHistoryTotal();
    datetime orderCloseTimes[];
    int      orderTickets[];
    ArrayResize(orderCloseTimes, 0);
    ArrayResize(orderTickets, 0);

    for(int pos = 0; pos < histTotal; pos++) {
        if(!OrderSelect(pos, SELECT_BY_POS, MODE_HISTORY)) {
            continue;
        }
        if(OrderSymbol() != symbol) {
            continue;
        }
        int orderMagic = OrderMagicNumber();
        if(magicNumber != 0 && (long)orderMagic != magicNumber) {
            continue;
        }

        int insertIndex = ArraySize(orderTickets);
        if(ArrayResize(orderTickets, insertIndex + 1) < 0) {
            continue;
        }
        if(ArrayResize(orderCloseTimes, insertIndex + 1) < 0) {
            ArrayResize(orderTickets, insertIndex);
            continue;
        }
        orderTickets[insertIndex]    = OrderTicket();
        orderCloseTimes[insertIndex] = OrderCloseTime();
    }

    int relevantCount = ArraySize(orderTickets);
    if(relevantCount < DMCMM_processedOrdersCount) {
        DMCMM_processedOrdersCount = relevantCount;
        DMCMM_lastCloseTime   = 0;
        DMCMM_lastCloseTicket = -1;
    }

    if(relevantCount > 1) {
        for(int i = 1; i < relevantCount; i++) {
            datetime timeKey = orderCloseTimes[i];
            int      ticketKey = orderTickets[i];
            int j = i - 1;
            while(j >= 0 && (orderCloseTimes[j] > timeKey || (orderCloseTimes[j] == timeKey && orderTickets[j] > ticketKey))) {
                orderCloseTimes[j + 1] = orderCloseTimes[j];
                orderTickets[j + 1]    = orderTickets[j];
                j--;
            }
            orderCloseTimes[j + 1] = timeKey;
            orderTickets[j + 1]    = ticketKey;
        }
    }

    bool processedAny = false;
    for(int idx = 0; idx < relevantCount; idx++) {
        int ticket = orderTickets[idx];
        datetime closeTime = orderCloseTimes[idx];
        if(closeTime < DMCMM_lastCloseTime) {
            continue;
        }
        if(closeTime == DMCMM_lastCloseTime && ticket <= DMCMM_lastCloseTicket) {
            continue;
        }
        if(!OrderSelect(ticket, SELECT_BY_TICKET, MODE_HISTORY)) {
            continue;
        }

        double openPrice  = OrderOpenPrice();
        double closePrice = OrderClosePrice();
        if(closePrice == openPrice) {
            DMCMM_lastCloseTime   = closeTime;
            DMCMM_lastCloseTicket = ticket;
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

        double betForTrade = DMCMM_lastExecutedBet;
        if(betForTrade <= 0.0) {
            betForTrade = DMCMM_curBet;
        }
        if(betForTrade <= 0.0) {
            betForTrade = OrderLots();
        }
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

        DMCMM_lastCloseTime   = closeTime;
        DMCMM_lastCloseTicket = ticket;
        processedAny = true;
    }

    if(processedAny || DMCMM_processedOrdersCount != relevantCount) {
        DMCMM_processedOrdersCount = relevantCount;
    }

    DMCMM_lastExecutedBet = DMCMM_curBet;
    double lots = DMCMM_RoundLotToBroker(DMCMM_curBet);
    return lots;
}

double DMCMM_CalcDecimalStep() {
    if(Decimals <= 0) {
        return 1.0;
    }
    return MathPow(10.0, -Decimals);
}

double DMCMM_RoundLotToBroker(double rawLots) {
    double step = DMCMM_LotStep;
    if(step <= 0.0) {
        step = DMCMM_CalcDecimalStep();
    }
    if(step <= 0.0) {
        step = 0.01;
    }

    double steps = rawLots / step;
    steps = MathFloor(steps + 1e-8);
    if(steps < 0.0) {
        steps = 0.0;
    }

    double rounded = steps * step;
    rounded = NormalizeDouble(rounded, Decimals);

    double minPositive = step;
    if(minPositive <= 0.0) {
        minPositive = DMCMM_CalcDecimalStep();
    }
    if(minPositive <= 0.0) {
        minPositive = 0.01;
    }
    if(rounded < minPositive) {
        rounded = minPositive;
    }
    if(DMCMM_MinLot > 0.0 && rounded < DMCMM_MinLot) {
        rounded = DMCMM_MinLot;
    }
    return rounded;
}

void DMCMM_ResetCycle() {
    DMCMM_ResetSequence();
    DMCMM_stock       = 0;
    DMCMM_consecWins  = 0;
    DMCMM_cycleProfit = 0.0;
    DMCMM_UpdateCurrentBet();
    DMCMM_lastExecutedBet = DMCMM_curBet;
}

void DMCMM_ResetSequence() {
    DMCMM_sequenceLen = 2;
    ArrayResize(DMCMM_sequence, DMCMM_sequenceLen);
    DMCMM_sequence[0] = 0;
    DMCMM_sequence[1] = 1;
}

void DMCMM_ProcessWin() {
    if(DMCMM_sequenceLen <= 0) {
        DMCMM_ResetSequence();
    }

    int count = DMCMM_sequenceLen;
    if(count <= 0) {
        return;
    }

    long left  = DMCMM_sequence[0];
    long right = DMCMM_sequence[count - 1];

    if(count == 2 && left == 0 && right == 1) {
        DMCMM_consecWins++;
    }

    if(count == 2) {
        DMCMM_ResetSequence();
    } else if(count == 3) {
        DMCMM_SequenceRemoveAt(0);
        DMCMM_SequenceRemoveAt(0);
        if(DMCMM_sequenceLen <= 0) {
            DMCMM_ResetSequence();
        } else {
            long value     = DMCMM_sequence[0];
            long remainder = value % 2;
            long half      = value / 2;
            DMCMM_SequenceClear();
            DMCMM_SequenceAdd(half);
            DMCMM_SequenceAdd(half + remainder);
        }
    } else if(count > 2) {
        DMCMM_SequenceRemoveAt(0);
        if(DMCMM_sequenceLen > 0) {
            DMCMM_SequenceRemoveAt(DMCMM_sequenceLen - 1);
        }
    }

    DMCMM_ApplyAveraging();
}

void DMCMM_ProcessLoss() {
    if(DMCMM_consecWins <= 5) {
        DMCMM_consecWins = 0;
    } else {
        long streakProfit = (((long)DMCMM_consecWins) - 3) * 5 - 8;
        long normalProfit = ((long)DMCMM_consecWins) - 2;
        DMCMM_stock += (streakProfit - normalProfit);
        DMCMM_consecWins = 0;
    }

    if(DMCMM_sequenceLen <= 0) {
        DMCMM_ResetSequence();
    }

    if(DMCMM_sequenceLen <= 0) {
        return;
    }

    long left  = DMCMM_sequence[0];
    long right = DMCMM_sequence[DMCMM_sequenceLen - 1];
    DMCMM_SequenceAdd(left + right);

    DMCMM_ApplyAveraging();
    DMCMM_ConsumeStock();
    DMCMM_RedistributeZero();
}

void DMCMM_ApplyAveraging() {
    if(DMCMM_sequenceLen <= 0) {
        DMCMM_ResetSequence();
    }

    int count = DMCMM_sequenceLen;
    if(count <= 0) {
        return;
    }

    long sum  = DMCMM_SumSequence();
    long left = DMCMM_sequence[0];

    if(left == 0) {
        if(count <= 1) {
            return;
        }
        int denom = count - 1;
        if(denom <= 0) {
            return;
        }
        long denomL = denom;
        long remainder = sum % denomL;
        DMCMM_SequenceRemoveAt(0);
        DMCMM_FillWithZero();
        long average = sum / denomL;
        DMCMM_AddToAll(average);
        if(DMCMM_sequenceLen > 0 && remainder > 0) {
            DMCMM_sequence[0] += remainder;
        }
        DMCMM_SequenceInsertAt(0, 0);
    } else {
        long countL    = count;
        long remainder = sum % countL;
        long average   = sum / countL;
        DMCMM_FillWithZero();
        DMCMM_AddToAll(average);
        if(DMCMM_sequenceLen > 1 && remainder > 0) {
            DMCMM_sequence[1] += remainder;
        }
    }
}

void DMCMM_ConsumeStock() {
    if(DMCMM_sequenceLen <= 0) {
        return;
    }
    long first = DMCMM_sequence[0];
    if(first <= DMCMM_stock) {
        DMCMM_stock -= first;
        DMCMM_sequence[0] = 0;
    }
}

void DMCMM_RedistributeZero() {
    if(DMCMM_sequenceLen <= 0) {
        return;
    }
    long first = DMCMM_sequence[0];
    if(first < 1) {
        return;
    }

    long redistribution = first;
    DMCMM_sequence[0] = 0;
    long total = DMCMM_SumSequence() + redistribution;
    int redistributeCount = DMCMM_sequenceLen - 1;
    if(redistributeCount <= 0) {
        return;
    }

    long redistributeCountL = redistributeCount;
    long remainder   = total % redistributeCountL;
    long distributed = total / redistributeCountL;

    if(redistribution < redistributeCountL) {
        if(DMCMM_sequenceLen > 1) {
            DMCMM_sequence[1] += redistribution;
        }
    } else {
        DMCMM_SequenceRemoveAt(0);
        DMCMM_FillWithZero();
        DMCMM_AddToAll(distributed);
        if(DMCMM_sequenceLen > 0 && remainder > 0) {
            DMCMM_sequence[0] += remainder;
        }
        DMCMM_SequenceInsertAt(0, 0);
    }
}

void DMCMM_UpdateCurrentBet() {
    double coefficient = DMCMM_ComputeBetCoeff();
    DMCMM_curBet = BaseLot * coefficient;
}

double DMCMM_ComputeBetCoeff() {
    if(DMCMM_sequenceLen <= 0) {
        return 0.0;
    }
    long left  = DMCMM_sequence[0];
    long right = (DMCMM_sequenceLen > 1 ? DMCMM_sequence[DMCMM_sequenceLen - 1] : left);
    long base  = left + right;
    double multiplier = 1.0;
    if(DMCMM_consecWins == 3) {
        multiplier = 2.0;
    } else if(DMCMM_consecWins == 4) {
        multiplier = 3.0;
    } else if(DMCMM_consecWins >= 5) {
        multiplier = 5.0;
    }
    return base * multiplier;
}

long DMCMM_SumSequence() {
    long sum = 0;
    for(int i = 0; i < DMCMM_sequenceLen; i++) {
        sum += DMCMM_sequence[i];
    }
    return sum;
}

void DMCMM_FillWithZero() {
    for(int i = 0; i < DMCMM_sequenceLen; i++) {
        DMCMM_sequence[i] = 0;
    }
}

void DMCMM_AddToAll(long value) {
    for(int i = 0; i < DMCMM_sequenceLen; i++) {
        DMCMM_sequence[i] += value;
    }
}

void DMCMM_SequenceClear() {
    DMCMM_sequenceLen = 0;
    ArrayResize(DMCMM_sequence, 0);
}

void DMCMM_SequenceAdd(long value) {
    int newLen = DMCMM_sequenceLen + 1;
    ArrayResize(DMCMM_sequence, newLen);
    DMCMM_sequence[newLen - 1] = value;
    DMCMM_sequenceLen = newLen;
}

void DMCMM_SequenceInsertAt(int index, long value) {
    if(index < 0) {
        index = 0;
    }
    if(index > DMCMM_sequenceLen) {
        index = DMCMM_sequenceLen;
    }
    int newLen = DMCMM_sequenceLen + 1;
    ArrayResize(DMCMM_sequence, newLen);
    for(int i = newLen - 1; i > index; i--) {
        DMCMM_sequence[i] = DMCMM_sequence[i - 1];
    }
    DMCMM_sequence[index] = value;
    DMCMM_sequenceLen = newLen;
}

void DMCMM_SequenceRemoveAt(int index) {
    if(index < 0 || index >= DMCMM_sequenceLen) {
        return;
    }
    for(int i = index; i < DMCMM_sequenceLen - 1; i++) {
        DMCMM_sequence[i] = DMCMM_sequence[i + 1];
    }
    DMCMM_sequenceLen--;
    ArrayResize(DMCMM_sequence, DMCMM_sequenceLen);
}
