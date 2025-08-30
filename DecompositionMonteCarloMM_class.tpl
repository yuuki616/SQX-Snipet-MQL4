// =============================================================
// Decomposition Monte Carlo Money Management - MQL4 Class (TPL)
// Java 実装とロジック完全一致版
//   - 勝利時：両端消し込み → 残1要素なら2分割 → A/B平均
//   - 敗北時：WS>=6でstock加算 → 右端に(left+right)追加 → A/B平均
//             → 左端>0 & stock>0を消費 → 必要ならzeroGeneration
//   - BET単位数 = 左端 + 右端（要素1つなら left*2 と同等）
//   - 乗数 MULT = WS: 0–2→1, 3→2, 4→3, 5+→5
//   - 口数 = BET * MULT * baseLot を step/decimals で正規化
// =============================================================

struct DecompositionMonteCarloMM_State
{
   // 進化する数列（Labouchere系）
   int    sequence[];

   // 直近連勝数、ストック
   int    winStreak;
   int    stock;

   // ドローダウン管理用
   double cyclePL;
   datetime prevOpenTime;
   datetime prevCloseTime;
   bool   initialized;

   // ロット計算パラメータ
   double baseLot;
   double step;
   int    decimals;
};

//----------------------------------------------
// 初期化・リセット
//----------------------------------------------
void DMC_reset(DecompositionMonteCarloMM_State &st)
{
   ArrayResize(st.sequence, 2);
   st.sequence[0] = 0;
   st.sequence[1] = 1;
   st.winStreak   = 0;
   st.stock       = 0;
   st.cyclePL     = 0.0;
   st.prevOpenTime  = 0;
   st.prevCloseTime = 0;
   st.initialized   = true;
}

void DMC_init(DecompositionMonteCarloMM_State &st, double baseLot, double step, int decimals)
{
   st.baseLot  = baseLot;
   st.step     = step;
   st.decimals = decimals;
   DMC_reset(st);
}

//----------------------------------------------
// シンボルごとの状態管理
//----------------------------------------------
string DMC_symbols[];
DecompositionMonteCarloMM_State DMC_states[];

bool DMC_debugLogs = false;
bool DMC_auditCSV  = false;

void DMC_log(string tag, string msg)
{
   if (DMC_debugLogs)
      PrintFormat("%s: %s", tag, msg);
}

void DMC_audit(string msg)
{
   if (DMC_auditCSV)
      Print("DecompMC_AUDIT: " + msg);
}

int DMC_getStateIndex(string symbol, double baseLot, double step, int decimals)
{
   for (int i=0; i<ArraySize(DMC_symbols); i++)
   {
      if (DMC_symbols[i] == symbol)
         return i;
   }

   int idx = ArraySize(DMC_symbols);
   ArrayResize(DMC_symbols, idx + 1);
   ArrayResize(DMC_states, idx + 1);
   DMC_init(DMC_states[idx], baseLot, step, decimals);
   DMC_symbols[idx] = symbol;
   return idx;
}

string DMC_baseSymbol(string sym)
{
   if (StringLen(sym) == 0)
      return "";
   int idx = StringFind(sym, "_");
   if (idx < 0)
      idx = StringFind(sym, "-");
   if (idx >= 0)
      return StringSubstr(sym, 0, idx);
   return sym;
}

void DMC_applyLastClosedOrder(string symbol, int magicNumber, DecompositionMonteCarloMM_State &st)
{
   string baseSym = DMC_baseSymbol(symbol);
   int total = OrdersHistoryTotal();
   for (int i = total - 1; i >= 0; i--)
   {
      if (!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY))
         continue;
      if (OrderMagicNumber() != magicNumber)
         continue;
      if (DMC_baseSymbol(OrderSymbol()) != baseSym)
         continue;
      if (OrderOpenPrice() == OrderClosePrice())
         continue;
      if (OrderOpenTime() == st.prevOpenTime && OrderCloseTime() == st.prevCloseTime)
         break; // 既に処理済み

      double pl = (OrderType() == OP_BUY ?
                   OrderClosePrice() - OrderOpenPrice() :
                   OrderOpenPrice()  - OrderClosePrice());
      st.cyclePL += pl;
      bool isWin = (pl > 0.0);
      if (DMC_debugLogs)
         DMC_log("DecompMC_DEBUG", StringFormat("Before update  SEQ=%s  WS=%d  STOCK=%d  PL=%.5f",
                                  DMC_seqToString(st.sequence), st.winStreak, st.stock, pl));
      DMC_updateSequence_RDR(st, isWin);
      if (DMC_debugLogs)
         DMC_log("DecompMC_DEBUG", StringFormat("After  update   SEQ=%s  WS=%d  STOCK=%d",
                                  DMC_seqToString(st.sequence), st.winStreak, st.stock));
      st.prevOpenTime  = OrderOpenTime();
      st.prevCloseTime = OrderCloseTime();
      break;
   }
}

//----------------------------------------------
// 文字列化（任意：ログ向け）
//----------------------------------------------
string DMC_seqToString(int &seq[])
{
   int n = ArraySize(seq);
   string s = "[";
   for (int i=0; i<n; i++)
   {
      if (i > 0) s += ",";
      s += IntegerToString(seq[i]);
   }
   s += "]";
   return s;
}

//----------------------------------------------
// BET（単位数）＝ 左端 + 右端（要素1つのときは left*2 相当）
//----------------------------------------------
int DMC_getBetUnits(const int &seq[])
{
   int n = ArraySize(seq);
   if (n == 0) return 0;
   int left  = seq[0];
   int right = (n >= 2 ? seq[n-1] : left);
   return left + right;
}

//----------------------------------------------
// 乗数＝WS: 0–2→1, 3→2, 4→3, 5+→5（Java同様）
//----------------------------------------------
int DMC_getMultiplier(int winStreak)
{
   if (winStreak <= 2) return 1;
   if (winStreak == 3) return 2;
   if (winStreak == 4) return 3;
   return 5;
}

//----------------------------------------------
// ロット計算：BET * MULT * baseLot を step/decimals で正規化
//----------------------------------------------
double DMC_computeLot(const DecompositionMonteCarloMM_State &st)
{
   int betUnits = DMC_getBetUnits(st.sequence);
   int mult     = DMC_getMultiplier(st.winStreak);
   double lot   = (double)betUnits * (double)mult * st.baseLot;

   if (st.step > 0.0)
      lot = MathRound(lot / st.step) * st.step;

   return NormalizeDouble(lot, st.decimals);
}

// BET・MULT を与えてロット計算（こちらを推奨）
double DMC_computeLotFromBM(int betUnits, int multiplier, const DecompositionMonteCarloMM_State &st)
{
   double lot = (double)betUnits * (double)multiplier * st.baseLot;

   if (st.step > 0.0)
      lot = MathRound(lot / st.step) * st.step;

   return NormalizeDouble(lot, st.decimals);
}

//----------------------------------------------
// A平均（左==0）：先頭0は保持し、残り(n-1)を等分。余りは index1 に集約
//----------------------------------------------
void DMC_averageA_index1(int &seq[])
{
   int n = ArraySize(seq);
   if (n < 2 || seq[0] != 0) return;

   int  nTail   = n - 1;
   long sumTail = 0;
   for (int i=1; i<n; i++) sumTail += seq[i];

   int q = (int)(sumTail / nTail);
   int r = (int)(sumTail % nTail);

   for (int i=1; i<n; i++) seq[i] = q;
   if (r > 0) seq[1] += r; // 余りは index1
}

//----------------------------------------------
// B平均（左>=1）：全要素 n を等分。余りは index1 に集約
//----------------------------------------------
void DMC_averageB_index1(int &seq[])
{
   int n = ArraySize(seq);
   if (n <= 0)
   {
      ArrayResize(seq, 2);
      seq[0] = 0;
      seq[1] = 1;
      return;
   }

   long S = 0;
   for (int i=0; i<n; i++) S += seq[i];

   int q = (int)(S / n);
   int r = (int)(S % n);

   for (int i=0; i<n; i++) seq[i] = q;
   if (r > 0)
   {
      if (n >= 2) seq[1] += r;  // 余りは index1
      else         seq[0] += r;  // 要素が1つだけの場合
   }
}

//----------------------------------------------
// zeroGeneration（左端を0にし、その値を残りへ再配分）
//----------------------------------------------
void DMC_zeroGeneration(int &seq[])
{
   int n = ArraySize(seq);
   if (n <= 0) return;

   int redistribute = seq[0];
   seq[0] = 0;

   int S = 0;
   for (int i=0; i<n; i++) S += seq[i];

   int subCount = n - 1;
   if (subCount <= 0) subCount = 1;

   int totalInc = S + redistribute;
   int check    = totalInc % subCount;
   int avg      = totalInc / subCount;
   if (redistribute < subCount)
   {
      // 先頭の値を index1 に集約
      if (n >= 2) seq[1] += redistribute;
   }
   else if (check == 0)
   {
      // 先頭を除去→残りを0埋め→+avg→先頭0を追加
      for (int i=1; i<n; i++) seq[i-1] = seq[i];
      n -= 1;
      ArrayResize(seq, n);
      for (int i=0; i<n; i++) seq[i] = 0;
      for (int i=0; i<n; i++) seq[i] += avg;
      ArrayResize(seq, n+1);
      for (int i=n; i>=1; i--) seq[i] = seq[i-1];
      seq[0] = 0;
   }
   else // check >= 1
   {
      // 先頭を除去→残りを0埋め→+avg→先頭側にcheck→先頭0追加
      for (int i=1; i<n; i++) seq[i-1] = seq[i];
      n -= 1;
      ArrayResize(seq, n);
      for (int i=0; i<n; i++) seq[i] = 0;
      for (int i=0; i<n; i++) seq[i] += avg;
      if (n >= 1) seq[0] += check; // 残りの check は先頭側へ
      ArrayResize(seq, n+1);
      for (int i=n; i>=1; i--) seq[i] = seq[i-1];
      seq[0] = 0;
   }
}

//----------------------------------------------
// RDR 更新（勝敗判定に基づく数列進化）※Java完全準拠
//----------------------------------------------
void DMC_updateSequence_RDR(DecompositionMonteCarloMM_State &st, bool isWin)
{
   int n = ArraySize(st.sequence);
   if (n == 0)
   {
      ArrayResize(st.sequence, 2);
      st.sequence[0] = 0;
      st.sequence[1] = 1;
      n = 2;
   }

   int leftBefore  = st.sequence[0];
   int rightBefore = (n >= 2 ? st.sequence[n - 1] : st.sequence[0]);

   if (isWin)
   {
      // 1) 勝利時WSの扱い（[0,1]でのみ連勝カウント）
      if (n == 2 && leftBefore == 0 && rightBefore == 1) st.winStreak++;
      else                                               st.winStreak = 0;

      // 2) 両端を削除
      if (n >= 2)
      {
         // 左右端を除去するために内部要素をシフト
         for (int i=1; i<n-1; i++)
            st.sequence[i-1] = st.sequence[i];
         ArrayResize(st.sequence, n - 2);
      }
      else
      {
         ArrayResize(st.sequence, 0);
      }

      // 3) 空なら [0,1]、要素1つなら二分割
      n = ArraySize(st.sequence);
      if (n == 0)
      {
         ArrayResize(st.sequence, 2);
         st.sequence[0] = 0;
         st.sequence[1] = 1;
      }
      else if (n == 1)
      {
         int v = st.sequence[0];
         int l = v / 2;
         ArrayResize(st.sequence, 2);
         if (v % 2 == 0)
         {
            st.sequence[0] = l;
            st.sequence[1] = l;
         }
         else
         {
            st.sequence[0] = l;
            st.sequence[1] = l + 1;
         }
      }

      // 4) A/B平均化（左0ならA、左>0ならB）
      n = ArraySize(st.sequence);
      if (n > 0)
      {
         if (st.sequence[0] == 0) DMC_averageA_index1(st.sequence);
         else                     DMC_averageB_index1(st.sequence);
      }
   }
   else
   {
      // ---- 敗北時 ----

      // 0) WS>=6 のときだけ Java式で stock に上乗せして WS を0に戻す
      if (st.winStreak > 5)
      {
         int ws           = st.winStreak;
         int winProfit    = (ws - 3) * 5 - 8;
         int normalProfit =  ws - 2;
         int stockGain    =  winProfit - normalProfit;
         st.stock += stockGain;
      }
      st.winStreak = 0;

      // 1) 右端へ (left+right) を追加
      int idxAppend = ArraySize(st.sequence);
      ArrayResize(st.sequence, idxAppend + 1);
      st.sequence[idxAppend] = leftBefore + rightBefore;

      // 2) A/B平均化
      n = ArraySize(st.sequence);
      if (n > 0)
      {
         if (st.sequence[0] == 0) DMC_averageA_index1(st.sequence);
         else                     DMC_averageB_index1(st.sequence);
      }

      // 3) 左端>0 かつ stock>0 なら、左端から stock を消費
      n = ArraySize(st.sequence);
      if (n > 0 && st.sequence[0] > 0 && st.stock > 0)
      {
         int use = (st.sequence[0] < st.stock ? st.sequence[0] : st.stock);
         st.sequence[0] -= use;
         st.stock       -= use;
      }

      // 4) 左端がなお >=1 の場合は zeroGeneration
      if (ArraySize(st.sequence) > 0 && st.sequence[0] >= 1)
         DMC_zeroGeneration(st.sequence);
   }

   // 5) 念のための保険
   if (ArraySize(st.sequence) == 0)
   {
      ArrayResize(st.sequence, 2);
      st.sequence[0] = 0;
      st.sequence[1] = 1;
   }
}

//----------------------------------------------
// 外部呼び出し用：勝敗反映＆ロット計算のワンショット
//   - isWin: 直近トレードの結果
//   - 戻り値 : 次回トレードのロット
//----------------------------------------------
double DMC_updateAndCalcLot(DecompositionMonteCarloMM_State &st, bool isWin)
{
   // 勝敗で数列更新
   DMC_updateSequence_RDR(st, isWin);

   // 次回BET/MULTとロット
   int bet  = DMC_getBetUnits(st.sequence);
   int mult = DMC_getMultiplier(st.winStreak);

   return DMC_computeLotFromBM(bet, mult, st);
}

//----------------------------------------------
// SQ呼び出し用メイン関数（Java computeTradeSize 対応）
//----------------------------------------------
double sqMMDecompositionMonteCarloMM(string symbol, ENUM_ORDER_TYPE orderType, double price, double sl,
                                     double baseLot, double maxDrawdown, int decimals,
                                     bool debugLogs, bool auditCSV,
                                     bool enforceMaxLot, double maxLotCap, double step,
                                     int magicNumber)
{
   if (UseMoneyManagement == false)
      return baseLot;

   string correctedSymbol = correctSymbol(symbol);
   int idx = DMC_getStateIndex(correctedSymbol, baseLot, step, decimals);
   DecompositionMonteCarloMM_State st = DMC_states[idx];
   st.baseLot  = baseLot;
   st.step     = step;
   st.decimals = decimals;
   DMC_debugLogs = debugLogs;
   DMC_auditCSV  = auditCSV;

   // MaxDrawdown によるサイクルリセット
   if (maxDrawdown != 0.0 && (!st.initialized || st.cyclePL < -maxDrawdown))
   {
      DMC_log("DecompMC", StringFormat("Resetting cycle: CyclePL=%.5f MaxDD=%.5f", st.cyclePL, maxDrawdown));
      DMC_reset(st);
   }
   else if (st.initialized && maxDrawdown == 0.0 && st.cyclePL < 0)
   {
      st.cyclePL = 0.0;
   }

   // 最新のクローズドオーダーを反映
   DMC_applyLastClosedOrder(correctedSymbol, magicNumber, st);

   int betUnits = DMC_getBetUnits(st.sequence);
   int mult     = DMC_getMultiplier(st.winStreak);
   double lot   = (double)betUnits * (double)mult * baseLot;
   DMC_log("DecompMC", StringFormat("SEQ=%s BET=%d WS=%d MULT=%d STOCK=%d LOT=%.5f",
                                    DMC_seqToString(st.sequence), betUnits, st.winStreak,
                                    mult, st.stock, lot));
   if (DMC_auditCSV)
      DMC_audit(StringFormat("time=%d,symbol=%s,seq=%s,bet=%d,ws=%d,mult=%d,stock=%d,lot=%.5f,baselot=%.5f,step=%.5f,dec=%d,cycle_pl=%.5f",
                             TimeCurrent(), correctedSymbol, DMC_seqToString(st.sequence), betUnits,
                             st.winStreak, mult, st.stock, lot, baseLot, st.step, decimals, st.cyclePL));

   if (enforceMaxLot && maxLotCap > 0.0 && lot > maxLotCap)
      lot = maxLotCap;

   // round using stored step/decimals (Javaの round 相当)
   if (st.step > 0.0)
      lot = MathRound(lot / st.step) * st.step;

   DMC_states[idx] = st;
   return NormalizeDouble(lot, st.decimals);
}
