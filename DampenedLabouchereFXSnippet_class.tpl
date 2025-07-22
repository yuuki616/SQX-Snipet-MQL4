// Dampened Labouchere FX Money Management implementation

double dlRound(double val, int digits) {
   double factor = MathPow(10.0, digits);
   return MathRound(val * factor) / factor;
}

double sqMMDampenedLabouchereFX(string symbol, ENUM_ORDER_TYPE orderType, double price, double sl,
                                double fNormal, double fDefence, double switchDebt,
                                double switchWR, int switchRec, double multStep, double multMax,
                                double minLot, double initialLot, double multiplier, double sizeStep) {
   static double sequence[];
   static int seqLen = 0;
   static double debt = 0.0;
   static int streak = 0;
   static int cycleId = 1;
   static bool winHist[100];
   static int winHistLen = 0;
   static int mode = 0; // 0 = Normal, 1 = Defence
   static int lastProcessed = -1;
   static double cycleStartBalance = 0.0;

   if(seqLen == 0) {
      ArrayResize(sequence, 2);
      sequence[0] = 0.0;
      sequence[1] = initialLot;
      seqLen = 2;
      cycleStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      lastProcessed = OrdersHistoryTotal() - 1;
   }

   if(lastProcessed == -1)
      lastProcessed = OrdersHistoryTotal() - 1;

   int total = OrdersHistoryTotal();
   for(int i = lastProcessed + 1; i < total; i++) {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY))
         continue;
      ulong  ticket = OrderTicket();
      double openP  = OrderOpenPrice();
      double closeP = OrderClosePrice();
      if(openP == closeP) { lastProcessed = i; continue; }
      double lot    = MathAbs(OrderLots());
      int    type   = OrderType();
      bool win      = (type == ORDER_TYPE_BUY) ? (closeP > openP) : (closeP < openP);

      double betVal = dlRound(sequence[0] + sequence[seqLen-1], 2);
      if(betVal < initialLot) betVal = initialLot;
      double mult = (streak < 3) ? 1.0 : MathMin(1.0 + (streak - 2) * multStep, multMax);

      if(!win) {
         if(winHistLen < 100) winHist[winHistLen++] = false; else { ArrayCopy(winHist, winHist, 0, 1, 99); winHist[99] = false; }
         double sumWins = 0.0; for(int j=0;j<winHistLen;j++) if(winHist[j]) sumWins += 1.0;
         double wr = (winHistLen == 0) ? 0.5 : (sumWins / winHistLen);
         if(mode == 0 && (debt / AccountInfoDouble(ACCOUNT_BALANCE) > switchDebt || wr < switchWR)) mode = 1;
         else if(mode == 1 && (streak >= switchRec || debt / AccountInfoDouble(ACCOUNT_BALANCE) < switchDebt * 0.5)) mode = 0;
         double currentF = (mode == 1 ? fDefence : fNormal);
         double appendVal = MathMax(initialLot, dlRound(betVal * currentF, 2));
         ArrayResize(sequence, seqLen + 1);
         sequence[seqLen++] = appendVal;
         debt = dlRound(debt + lot - appendVal * mult, 2);
         streak = 0;
      } else {
         if(winHistLen < 100) winHist[winHistLen++] = true; else { ArrayCopy(winHist, winHist, 0, 1, 99); winHist[99] = true; }
         double profit = dlRound(lot, 2);
         if(profit >= debt) {
            profit -= debt;
            debt = 0.0;
            if(seqLen <= 2) {
               ArrayResize(sequence, 2);
               sequence[0] = 0.0;
               sequence[1] = initialLot;
               seqLen = 2;
               streak = 0;
            } else {
               for(int j=1;j<seqLen-1;j++) sequence[j-1] = sequence[j];
               seqLen -= 2;
               ArrayResize(sequence, seqLen);
               streak++;
            }
         } else {
            debt = dlRound(debt - profit, 2);
            streak++;
         }
      }

      double balance = AccountInfoDouble(ACCOUNT_BALANCE);
      if(seqLen == 2 && MathAbs(sequence[0]) < 1e-9 && MathAbs(sequence[1] - initialLot) < 1e-9 && MathAbs(debt) < 1e-9 && balance >= cycleStartBalance) {
         cycleId++;
         ArrayResize(sequence, 2);
         sequence[0] = 0.0;
         sequence[1] = initialLot;
         seqLen = 2;
         debt = 0.0;
         streak = 0;
         winHistLen = 0;
         mode = 0;
         lastProcessed = OrdersHistoryTotal() - 1;
         cycleStartBalance = balance;
      }
      lastProcessed = i;
   }

   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double bet = dlRound(sequence[0] + sequence[seqLen-1], 2);
   if(bet < initialLot) bet = initialLot;
   double mult = (streak < 3) ? 1.0 : MathMin(1.0 + (streak - 2) * multStep, multMax);
   double lot = MathMax(minLot, dlRound(bet * mult, 2));

   lot *= multiplier;
   lot = roundDown(lot, sizeStep, 2, symbol);

   double minVol = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double maxVol = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   double stepVol = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);

   if(lot < minVol && lot > 0) lot = minVol;
   lot = MathFloor(lot / stepVol) * stepVol;
   if(lot < minVol && lot > 0) lot = minVol;
   if(lot > maxVol) lot = maxVol;

   return lot;
}
