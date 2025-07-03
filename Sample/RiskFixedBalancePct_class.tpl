

double sqMMRiskFixedBalancePct(string symbol, ENUM_ORDER_TYPE orderType, double price, double sl, double RiskInPercent, int decimals, double LotsIfNoMM, double MaximumLots, double multiplier, double sizeStep) {
   Verbose("Computing Money Management for order -  Risk fixed % of account balance");
   
   if(UseMoneyManagement == false) {
      Verbose("Use Money Management = false, MM not used");
      return (mmLotsIfNoMM);
   }
      
   string correctedSymbol = correctSymbol(symbol);
   double openPrice = price > 0 ? price : SymbolInfoDouble(correctedSymbol, isLongOrder(orderType) ? SYMBOL_ASK : SYMBOL_BID);
   sl = NormalizeDouble(sl, (int) SymbolInfoInteger(correctedSymbol, SYMBOL_DIGITS));
   
   double slSize = sqConvertToPips(correctedSymbol, MathAbs(NormalizeDouble(openPrice - sl, (int) SymbolInfoInteger(correctedSymbol, SYMBOL_DIGITS))));
   if(slSize <= 0) {
      Verbose("Computing Money Management - Stop Loss is zero, using Lots if no MM: ", DoubleToString(LotsIfNoMM));
      return(LotsIfNoMM);
   }
   
   Verbose("Price: ", DoubleToString(openPrice), ", SL: ", DoubleToString(sl), ", SLSize: ", DoubleToString(slSize), ", RiskInPercent: ", DoubleToString(RiskInPercent));

   double LotSize=0;

   if(RiskInPercent < 0 ) {
      Verbose("Computing Money Management - Incorrect RiskInPercent size, it must be above 0");
      return(0);
   }
   
   double PointValue = SymbolInfoDouble(correctedSymbol, SYMBOL_TRADE_TICK_VALUE) / SymbolInfoDouble(correctedSymbol, SYMBOL_TRADE_TICK_SIZE);      
   double Smallest_Lot = SymbolInfoDouble(correctedSymbol, SYMBOL_VOLUME_MIN);
   double Largest_Lot = SymbolInfoDouble(correctedSymbol, SYMBOL_VOLUME_MAX);    
   double LotStep = SymbolInfoDouble(correctedSymbol, SYMBOL_VOLUME_STEP);

   //Maximum amount of money to risk 
   double moneyToRisk = NormalizeDouble(AccountInfoDouble(ACCOUNT_BALANCE) * RiskInPercent / 100, 7);
		
   //Maximum drawdown of this order if we buy 1 lot 
   double oneLotSLDrawdown = NormalizeDouble(PointValue * MathAbs(openPrice - sl), 7);
		
   if(oneLotSLDrawdown > 0) {
	  LotSize = moneyToRisk / oneLotSLDrawdown;
   }
   else {
	  LotSize = 0;
   }
   
    //Order size multiplier
    LotSize = LotSize * multiplier;
	
    //round computed trade size 
	LotSize = roundDown(LotSize, sizeStep, decimals, symbol);
    
   //--- MAXLOT and MINLOT management

   Verbose("Computing Money Management - Smallest_Lot: ", DoubleToString(Smallest_Lot), ", Largest_Lot: ", DoubleToString(Largest_Lot), ", Computed LotSize: ", DoubleToString(LotSize));
   Verbose("Max money to risk: ", DoubleToString(moneyToRisk), ", SL:", DoubleToString(sl), ", Max 1 lot trade drawdown: ", DoubleToString(oneLotSLDrawdown), ", Point value: ", DoubleToString(PointValue));

   if(LotSize <= 0) {
      Verbose("Calculated LotSize is <= 0. Using LotsIfNoMM value: ", DoubleToString(LotsIfNoMM), ")");
			LotSize = LotsIfNoMM;
	 }
   
   if(LotSize > MaximumLots) {
      Verbose("LotSize is too big. LotSize set to maximal allowed value (MaximumLots): ", DoubleToString(MaximumLots));
      LotSize = MaximumLots;
   }

   //--------------------------------------------

   if (LotSize < Smallest_Lot) {
      Verbose("Calculated LotSize is too small. Minimal allowed lot size from the broker is: ", DoubleToString(Smallest_Lot), ". Please, increase your risk or set fixed LotSize.");
      LotSize = 0;
   }
   else if (LotSize > Largest_Lot) {
      Verbose("LotSize is too big. LotSize set to maximal allowed market value: ", DoubleToString(Largest_Lot));
      LotSize = Largest_Lot;
   }

   return (LotSize);
}
