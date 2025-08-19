struct DecompositionMonteCarloMM_State {
   int    sequence[];
   int    stock;
   int    winStreak;
   double cyclePL;
   ulong  prevTicket;
   bool   initialized;
   double sizeStep;
};

string DecompositionMonteCarloMM_symbols[];
DecompositionMonteCarloMM_State DecompositionMonteCarloMM_states[];

int DecompositionMonteCarloMM_findState(string symbol) {
   for(int i=0;i<ArraySize(DecompositionMonteCarloMM_symbols);i++)
      if(DecompositionMonteCarloMM_symbols[i]==symbol) return i;
   return -1;
}

void DecompositionMonteCarloMM_resetAll(int index) {
   ArrayResize(DecompositionMonteCarloMM_states[index].sequence,2);
   DecompositionMonteCarloMM_states[index].sequence[0]=0;
   DecompositionMonteCarloMM_states[index].sequence[1]=1;
   DecompositionMonteCarloMM_states[index].stock=0;
   DecompositionMonteCarloMM_states[index].winStreak=0;
   DecompositionMonteCarloMM_states[index].cyclePL=0.0;
   DecompositionMonteCarloMM_states[index].prevTicket=0;
   DecompositionMonteCarloMM_states[index].initialized=true;
}

int DecompositionMonteCarloMM_getState(string symbol) {
   int idx=DecompositionMonteCarloMM_findState(symbol);
   if(idx<0) {
      idx=ArraySize(DecompositionMonteCarloMM_symbols);
      ArrayResize(DecompositionMonteCarloMM_symbols,idx+1);
      ArrayResize(DecompositionMonteCarloMM_states,idx+1);
      DecompositionMonteCarloMM_symbols[idx]=symbol;
      DecompositionMonteCarloMM_resetAll(idx);
   }
   return idx;
}

void DMC_arrayRemoveFirst(int &arr[]) {
   int n=ArraySize(arr); if(n<=0) return;
   for(int i=1;i<n;i++) arr[i-1]=arr[i];
   ArrayResize(arr,n-1);
}

void DMC_arrayRemoveLast(int &arr[]) {
   int n=ArraySize(arr); if(n<=0) return;
   ArrayResize(arr,n-1);
}

void DMC_arrayAddFirst(int &arr[],int v) {
   int n=ArraySize(arr);
   ArrayResize(arr,n+1);
   for(int i=n;i>0;i--) arr[i]=arr[i-1];
   arr[0]=v;
}

string DMC_seqToString(int &arr[]) {
   string out="[";
   for(int i=0;i<ArraySize(arr);i++) {
      if(i>0) out+=",";
      out+=IntegerToString(arr[i]);
   }
   out+="]";
   return out;
}

string DMC_baseSymbol(string sym) {
   int idx=StringFind(sym,"_");
   if(idx<0) idx=StringFind(sym,"-");
   if(idx<0) return sym;
   return StringSubstr(sym,0,idx);
}

int DecompositionMonteCarloMM_multiplier(int ws) {
   if(ws<=2) return 1;
   if(ws==3) return 2;
   if(ws==4) return 3;
   return 5;
}

void DecompositionMonteCarloMM_averageA_index1(int &seq[]) {
   if(ArraySize(seq)<2 || seq[0]!=0) return;
   int nTail=ArraySize(seq)-1;
   long sumTail=0; for(int i=1;i<ArraySize(seq);i++) sumTail+=seq[i];
   int q=(int)(sumTail/nTail);
   int r=(int)(sumTail%nTail);
   for(int i=1;i<ArraySize(seq);i++) seq[i]=q;
   if(r>0) seq[1]+=r;
}

void DecompositionMonteCarloMM_averageB_index1(int &seq[]) {
   int n=ArraySize(seq);
   if(n==0){ArrayResize(seq,2);seq[0]=0;seq[1]=1;return;}
   long S=0; for(int i=0;i<n;i++) S+=seq[i];
   int q=(int)(S/n);
   int r=(int)(S%n);
   for(int i=0;i<n;i++) seq[i]=q;
   if(r>0) {
      if(n>=2) seq[1]+=r; else seq[0]+=r;
   }
}

void DecompositionMonteCarloMM_zeroGeneration(int &seq[]) {
   int n=ArraySize(seq); if(n==0) return;
   int redistribute=seq[0];
   seq[0]=0;
   int S=0; for(int i=0;i<n;i++) S+=seq[i];
   int subCount=n-1; if(subCount<=0) subCount=1;
   int totalInc=S+redistribute;
   int check=totalInc%subCount;
   int avg=totalInc/subCount;
   if(redistribute<subCount) {
      if(n>=2) seq[1]+=redistribute;
   } else if(check==0) {
      DMC_arrayRemoveFirst(seq);
      n=ArraySize(seq);
      for(int i=0;i<n;i++) seq[i]=0;
      for(int i=0;i<n;i++) seq[i]+=avg;
      DMC_arrayAddFirst(seq,0);
   } else {
      DMC_arrayRemoveFirst(seq);
      n=ArraySize(seq);
      for(int i=0;i<n;i++) seq[i]=0;
      for(int i=0;i<n;i++) seq[i]+=avg;
      if(n>0) seq[0]+=check;
      DMC_arrayAddFirst(seq,0);
   }
}

void DecompositionMonteCarloMM_updateSequence_RDR(DecompositionMonteCarloMM_State &st,bool isWin) {
   int &seq[]=st.sequence;
   if(ArraySize(seq)==0){ArrayResize(seq,2);seq[0]=0;seq[1]=1;}
   int leftBefore=seq[0];
   int rightBefore=ArraySize(seq)>1?seq[ArraySize(seq)-1]:seq[0];
   if(isWin) {
      if(ArraySize(seq)==2 && seq[0]==0 && seq[1]==1) st.winStreak++; else st.winStreak=0;
      if(ArraySize(seq)>0) DMC_arrayRemoveFirst(seq);
      if(ArraySize(seq)>0) DMC_arrayRemoveLast(seq);
      if(ArraySize(seq)==0){ArrayResize(seq,2);seq[0]=0;seq[1]=1;}
      else if(ArraySize(seq)==1){int v=seq[0];ArrayResize(seq,0);if(v%2==0){int p=v/2;ArrayResize(seq,2);seq[0]=p;seq[1]=p;}else{int l=v/2;ArrayResize(seq,2);seq[0]=l;seq[1]=l+1;}}
      if(ArraySize(seq)>0){if(seq[0]==0) DecompositionMonteCarloMM_averageA_index1(seq); else DecompositionMonteCarloMM_averageB_index1(seq);}
   } else {
      if(st.winStreak<=5) st.winStreak=0; else {int ws=st.winStreak;int winProfit=(ws-3)*5-8;int normalProfit=ws-2;int stockGain=(winProfit-normalProfit);st.stock+=stockGain;st.winStreak=0;}
      int n=ArraySize(seq);ArrayResize(seq,n+1);seq[n]=leftBefore+rightBefore;
      if(seq[0]==0) DecompositionMonteCarloMM_averageA_index1(seq); else DecompositionMonteCarloMM_averageB_index1(seq);
      if(ArraySize(seq)>0 && seq[0]>0 && st.stock>0){int use=MathMin(seq[0],st.stock);seq[0]-=use;st.stock-=use;}
      if(ArraySize(seq)>0 && seq[0]>=1) DecompositionMonteCarloMM_zeroGeneration(seq);
   }
   if(ArraySize(seq)==0){ArrayResize(seq,2);seq[0]=0;seq[1]=1;}
}

ulong DecompositionMonteCarloMM_getLastClosedDeal(string symbol) {
   HistorySelect(0,TimeCurrent());
   string base=DMC_baseSymbol(symbol);
   for(int i=HistoryDealsTotal()-1;i>=0;i--) {
      ulong ticket=HistoryDealGetTicket(i);
      string sym=HistoryDealGetString(ticket,DEAL_SYMBOL);
      if(DMC_baseSymbol(sym)!=base) continue;
      if((int)HistoryDealGetInteger(ticket,DEAL_ENTRY)!=DEAL_ENTRY_OUT) continue;
      if((int)HistoryDealGetInteger(ticket,DEAL_TYPE)==DEAL_TYPE_BALANCE) continue;
      if(HistoryDealGetDouble(ticket,DEAL_PROFIT)==0.0) continue;
      return ticket;
   }
   return 0;
}

void DMC_log(bool enabled,string msg){ if(enabled) Verbose(msg); }
void DMC_audit(bool enabled,string msg){ if(enabled) Verbose(msg); }

double sqMMDecompositionMonteCarloMM(string symbol, ENUM_ORDER_TYPE orderType, double price, double sl,
                                      double baseLot,double maxDrawdown,int decimals,bool debugLogs,bool auditCSV,
                                      bool enforceMaxLot,double maxLotCap,double sizeStep) {
   if(!UseMoneyManagement)
      return roundDown(baseLot,sizeStep,decimals,symbol);

   string actualSymbol=symbol;
   if(actualSymbol=="" || actualSymbol=="Current") actualSymbol=Symbol();
   int idx=DecompositionMonteCarloMM_getState(actualSymbol);
   DecompositionMonteCarloMM_State &st=DecompositionMonteCarloMM_states[idx];

   if(maxDrawdown!=0.0 && (!st.initialized || st.cyclePL<-maxDrawdown)) {
      DMC_log(debugLogs,StringFormat("DecompMC: Resetting cycle: CyclePL=%.5f MaxDD=%.5f",st.cyclePL,maxDrawdown));
      DecompositionMonteCarloMM_resetAll(idx);
   } else if(st.initialized && maxDrawdown==0.0 && st.cyclePL<0) {
      st.cyclePL=0.0;
   }

   ulong deal=DecompositionMonteCarloMM_getLastClosedDeal(actualSymbol);
   if(deal>0 && deal!=st.prevTicket) {
      double profit=HistoryDealGetDouble(deal,DEAL_PROFIT);
      double vol=HistoryDealGetDouble(deal,DEAL_VOLUME);
      double tv=SymbolInfoDouble(actualSymbol,SYMBOL_TRADE_TICK_VALUE);
      double ts=SymbolInfoDouble(actualSymbol,SYMBOL_TRADE_TICK_SIZE);
      double pl=0.0;
      if(vol>0 && tv>0 && ts>0) pl=profit*ts/(tv*vol);
      st.cyclePL+=pl;
      bool isWin=(pl>0.0);
      if(debugLogs) DMC_log(true,StringFormat("Before update SEQ=%s WS=%d STOCK=%d PL=%.5f",DMC_seqToString(st.sequence),st.winStreak,st.stock,pl));
      DecompositionMonteCarloMM_updateSequence_RDR(st,isWin);
      if(debugLogs) DMC_log(true,StringFormat("After  update SEQ=%s WS=%d STOCK=%d",DMC_seqToString(st.sequence),st.winStreak,st.stock));
      st.prevTicket=deal;
   }

   int left=st.sequence[0];
   int right=(ArraySize(st.sequence)>1)?st.sequence[ArraySize(st.sequence)-1]:st.sequence[0];
   int betUnits=left+right;
   int mult=DecompositionMonteCarloMM_multiplier(st.winStreak);
   double lot=betUnits*baseLot*mult;
   if(enforceMaxLot && maxLotCap>0.0 && lot>maxLotCap){
      DMC_log(debugLogs,StringFormat("DecompMC: CAP lot %.5f > MaxLotCap %.5f -> clamp",lot,maxLotCap));
      lot=maxLotCap;
   }

   st.sizeStep=sizeStep;
   DMC_log(debugLogs,StringFormat("DecompMC: SEQ=%s BET=%d WS=%d MULT=%d STOCK=%d LOT=%.5f",DMC_seqToString(st.sequence),betUnits,st.winStreak,mult,st.stock,lot));
   if(auditCSV) DMC_audit(true,StringFormat("time=%d,symbol=%s,seq=%s,bet=%d,ws=%d,mult=%d,stock=%d,lot=%.5f,baselot=%.5f,step=%.5f,dec=%d,cycle_pl=%.5f",TimeCurrent(),actualSymbol,DMC_seqToString(st.sequence),betUnits,st.winStreak,mult,st.stock,lot,baseLot,st.sizeStep,decimals,st.cyclePL));

   return roundDown(lot,st.sizeStep,decimals,symbol);
}
