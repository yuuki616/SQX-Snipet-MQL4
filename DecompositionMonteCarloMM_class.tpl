<#-- ========== Decomposition Monte Carlo MM helper routines ========== -->

void DMCMM_ResetCycle() {
    DMCMM_ResetSequence();
    DMCMM_stock      = 0;
    DMCMM_consecWins = 0;
    DMCMM_cycleProfit = 0.0;
    DMCMM_UpdateCurrentBet();
}

void DMCMM_ResetSequence() {
    DMCMM_sequenceLen = 2;
    ArrayResize(DMCMM_sequence, DMCMM_sequenceLen);
    DMCMM_sequence[0] = 0;
    DMCMM_sequence[1] = 1;
}

void DMCMM_ProcessWin() {
    if(DMCMM_sequenceLen <= 0) DMCMM_ResetSequence();

    int count = DMCMM_sequenceLen;
    long left  = DMCMM_sequence[0];
    long right = DMCMM_sequence[count - 1];

    if(count == 2 && left == 0 && right == 1) {
        DMCMM_consecWins++;
    }

    if(count == 2) {
        DMCMM_ResetSequence();
    } else if(count == 3) {
        DMCMM_RemoveFirst();
        DMCMM_RemoveFirst();
        if(DMCMM_sequenceLen <= 0) {
            DMCMM_ResetSequence();
        } else {
            long value     = DMCMM_sequence[0];
            long remainder = value % 2;
            long half      = value / 2;
            DMCMM_ClearSequence();
            DMCMM_Append(half);
            DMCMM_Append(half + remainder);
        }
    } else if(count > 2) {
        DMCMM_RemoveFirst();
        if(DMCMM_sequenceLen > 0) {
            DMCMM_RemoveLast();
        }
    }

    DMCMM_ApplyAveraging();
}

void DMCMM_ProcessLoss() {
    if(DMCMM_consecWins <= 5) {
        DMCMM_consecWins = 0;
    } else {
        long streakProfit = (long)(DMCMM_consecWins - 3) * 5 - 8;
        long normalProfit = (long)DMCMM_consecWins - 2;
        DMCMM_stock += (streakProfit - normalProfit);
        DMCMM_consecWins = 0;
    }

    if(DMCMM_sequenceLen <= 0) DMCMM_ResetSequence();
    if(DMCMM_sequenceLen <= 0) return;

    long left  = DMCMM_sequence[0];
    long right = DMCMM_sequence[DMCMM_sequenceLen - 1];
    DMCMM_Append(left + right);

    DMCMM_ApplyAveraging();
    DMCMM_ConsumeStock();
    DMCMM_RedistributeZero();
}

void DMCMM_ApplyAveraging() {
    if(DMCMM_sequenceLen <= 0) DMCMM_ResetSequence();

    int count = DMCMM_sequenceLen;
    if(count <= 0) return;

    long sum  = DMCMM_SumSequence();
    long left = DMCMM_sequence[0];

    if(left == 0) {
        if(count <= 1) return;
        long remainder = sum % (count - 1);
        DMCMM_RemoveFirst();
        DMCMM_FillWithZero();
        long average = sum / (count - 1);
        DMCMM_AddToAll(average);
        if(DMCMM_sequenceLen > 0 && remainder > 0) {
            DMCMM_sequence[0] += remainder;
        }
        DMCMM_InsertFront(0);
    } else {
        long remainder = sum % count;
        DMCMM_FillWithZero();
        long average = sum / count;
        DMCMM_AddToAll(average);
        if(DMCMM_sequenceLen > 1 && remainder > 0) {
            DMCMM_sequence[1] += remainder;
        }
    }
}

void DMCMM_ConsumeStock() {
    if(DMCMM_sequenceLen <= 0) return;
    long first = DMCMM_sequence[0];
    if(first <= DMCMM_stock) {
        DMCMM_stock -= first;
        DMCMM_sequence[0] = 0;
    }
}

void DMCMM_RedistributeZero() {
    if(DMCMM_sequenceLen <= 0) return;

    long first = DMCMM_sequence[0];
    if(first < 1) return;

    long redistribution = first;
    DMCMM_sequence[0] = 0;

    long total = DMCMM_SumSequence() + redistribution;
    int  redistributeCount = DMCMM_sequenceLen - 1;
    if(redistributeCount <= 0) return;

    long remainder   = total % redistributeCount;
    long distributed = total / redistributeCount;

    if(redistribution < redistributeCount) {
        if(DMCMM_sequenceLen > 1) {
            DMCMM_sequence[1] += redistribution;
        }
    } else {
        DMCMM_RemoveFirst();
        DMCMM_FillWithZero();
        DMCMM_AddToAll(distributed);
        if(DMCMM_sequenceLen > 0 && remainder > 0) {
            DMCMM_sequence[0] += remainder;
        }
        DMCMM_InsertFront(0);
    }
}

void DMCMM_UpdateCurrentBet() {
    double coeff = DMCMM_ComputeBetCoeff();
    DMCMM_curBet = BaseLot * coeff;
}

double DMCMM_ComputeBetCoeff() {
    if(DMCMM_sequenceLen <= 0) return(0.0);
    long left  = DMCMM_sequence[0];
    long right = (DMCMM_sequenceLen > 1 ? DMCMM_sequence[DMCMM_sequenceLen - 1] : left);
    long betValue = left + right;
    double multiplier = 1.0;
    if(DMCMM_consecWins == 3)      multiplier = 2.0;
    else if(DMCMM_consecWins == 4) multiplier = 3.0;
    else if(DMCMM_consecWins >= 5) multiplier = 5.0;
    return(betValue * multiplier);
}

long DMCMM_SumSequence() {
    long sum = 0;
    for(int i = 0; i < DMCMM_sequenceLen; i++) {
        sum += DMCMM_sequence[i];
    }
    return(sum);
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

void DMCMM_RemoveFirst() {
    if(DMCMM_sequenceLen <= 0) return;
    for(int i = 0; i < DMCMM_sequenceLen - 1; i++) {
        DMCMM_sequence[i] = DMCMM_sequence[i + 1];
    }
    DMCMM_sequenceLen--;
    ArrayResize(DMCMM_sequence, DMCMM_sequenceLen);
}

void DMCMM_RemoveLast() {
    if(DMCMM_sequenceLen <= 0) return;
    DMCMM_sequenceLen--;
    ArrayResize(DMCMM_sequence, DMCMM_sequenceLen);
}

void DMCMM_Append(long value) {
    ArrayResize(DMCMM_sequence, DMCMM_sequenceLen + 1);
    DMCMM_sequence[DMCMM_sequenceLen] = value;
    DMCMM_sequenceLen++;
}

void DMCMM_InsertFront(long value) {
    ArrayResize(DMCMM_sequence, DMCMM_sequenceLen + 1);
    for(int i = DMCMM_sequenceLen; i > 0; i--) {
        DMCMM_sequence[i] = DMCMM_sequence[i - 1];
    }
    DMCMM_sequence[0] = value;
    DMCMM_sequenceLen++;
}

void DMCMM_ClearSequence() {
    DMCMM_sequenceLen = 0;
    ArrayResize(DMCMM_sequence, DMCMM_sequenceLen);
}
