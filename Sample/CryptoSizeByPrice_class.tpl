

double sqMMCryptoSizeByPrice(string symbol, ENUM_ORDER_TYPE orderType, double price, bool UseAccountBalance, double MaximumLots, int decimals, double multiplier, double sizeStep) {
   Verbose("Computing Money Management for order - Stock size by price");
   
   if(UseMoneyManagement == false) {
      Verbose("Use Money Management = false, MM not used");
      return (mmLotsIfNoMM);
   }
      
   string correctedSymbol = correctSymbol(symbol);
   double openPrice = price > 0 ? price : SymbolInfoDouble(correctedSymbol, isLongOrder(orderType) ? SYMBOL_ASK : SYMBOL_BID);
   
   Verbose("Price: ", DoubleToString(openPrice), ", UseAccountBalance: ", DoubleToString(UseAccountBalance), ", MaximumLots: ", DoubleToString(MaximumLots));

   double LotSize = 0;

   if(UseAccountBalance) {
			LotSize = (AccountInfoDouble(ACCOUNT_BALANCE)) / openPrice;
	 } else {
			LotSize = initialBalance / openPrice;
	 }

    //Order size multiplier
    LotSize = LotSize * multiplier;
	
    //round computed trade size 
	LotSize = roundDown(LotSize, sizeStep, decimals, symbol);
	 
   double Smallest_Lot = SymbolInfoDouble(correctedSymbol, SYMBOL_VOLUME_MIN);
   double Largest_Lot = SymbolInfoDouble(correctedSymbol, SYMBOL_VOLUME_MAX);    
   double LotStep = SymbolInfoDouble(correctedSymbol, SYMBOL_VOLUME_STEP);

   //--- MAXLOT and MINLOT management

   Verbose("Computing Money Management - Smallest_Lot: ", DoubleToString(Smallest_Lot), ", Largest_Lot: ", DoubleToString(Largest_Lot),", Computed LotSize: ", DoubleToString(LotSize));
   
   if(LotSize <= 0) {
			return(0);
	 }
   
   if(LotSize > MaximumLots) {
      Verbose("LotSize is too big. LotSize set to maximal allowed value (MaximumLots): ", DoubleToString(MaximumLots));
      LotSize = MaximumLots;
   }

   //--------------------------------------------

   if (LotSize < Smallest_Lot) {
      Verbose("LotSize is too small. Minimal allowed lot size: ", DoubleToString(Smallest_Lot));
      LotSize = 0;
   }
   else if (LotSize > Largest_Lot) {
      Verbose("LotSize is too big. LotSize set to maximal allowed market value: ", DoubleToString(Largest_Lot));
      LotSize = Largest_Lot;
   }

   return (LotSize);
}
