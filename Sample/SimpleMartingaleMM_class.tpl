double sqMMSimpleMartingale(string symbol, int orderType, int magicNo, double multiplier, double sizeStep, int decimals) {
   Verbose("Computing Money Management for order - Simple Martingale MM");
   
   if(UseMoneyManagement == false) {
      Verbose("Use Money Management = false, MM not used");
      return roundDown(mmLotsIfNoMM * multiplier, sizeStep, decimals, symbol);
   }
      
   symbol = correctSymbol(symbol);
   
   int direction = 0;
   if(mmSeparateByDirection) {
      direction = (orderType == ORDER_TYPE_BUY || orderType == ORDER_TYPE_BUY_LIMIT || orderType == ORDER_TYPE_BUY_STOP || orderType == ORDER_TYPE_BUY_STOP_LIMIT) ? 1 : -1;
   }
      
   direction = -direction; //we must look for the opposite direction as out deals have opposite order type than the original order
   
   ulong dealTicket = sqSelectOutDeal(magicNo, symbol, direction, "");
   
   if(dealTicket <= 0) {
      // there is no previous order
      Verbose("Simple Martingale MM - no previous order found");
      return roundDown(mmLotsStart * multiplier, sizeStep, decimals, symbol);
   }

   double PL = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
   double lastOrderSize = HistoryDealGetDouble(dealTicket, DEAL_VOLUME);
   Verbose("Simple Martingale MM - previous order found, PL: " + DoubleToString(PL) + ", size: " + DoubleToString(lastOrderSize));
   if(PL > 0) {
      // it was profit, reset
      return roundDown(mmLotsStart * multiplier, sizeStep, decimals, symbol);
   }
   
   double newSize = lastOrderSize * mmLotsMultiplier;
   
   if(newSize > mmLotsReset) {
      // we reached maximum allowed size, reset it back to the start one
      Verbose("Simple Martingale MM - exceeded maximum allowed size, resetting to start");
      return roundDown(mmLotsStart * multiplier, sizeStep, decimals, symbol);
   }
   
   return roundDown(newSize * multiplier, sizeStep, decimals, symbol);
}
