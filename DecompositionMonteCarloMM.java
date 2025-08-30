package SQ.MoneyManagement;

import java.util.*;
import java.util.concurrent.ConcurrentHashMap;
import java.lang.reflect.Method;
import com.strategyquant.lib.*;
import com.strategyquant.datalib.*;
import com.strategyquant.tradinglib.*;

@ClassConfig(name="Decomposition MonteCarlo MM (RDR)", display="DecompositionMonteCarlo MM (RDR): #BaseLot# × #X#")
@Help("RDR 仕様に完全準拠。WIN/LOSE の数列更新、A/B平均（余りは index1 集約）、ストック消費、0生成、連勝倍率（1/1/2/3/5）を実装。")
@Description("StrategyQuant Build 142準拠。Goodman/Decomp の MODE 切替は廃止。検証用ログを出力。")
public class DecompositionMonteCarloMM extends MoneyManagementMethod {

    // ===== Parameters =====
    @Parameter(defaultValue="0.01", name="BaseLot", minValue=0.00001, maxValue=100.0, step=0.00001, category="Default")
    public double BaseLot;

    @Parameter(defaultValue="100.0", name="MaxDrawdown", minValue=0.0, maxValue=100000.0, step=0.1, category="Default")
    public double MaxDrawdown;

    @Parameter(defaultValue="2", name="Decimals", minValue=0, maxValue=6, step=1, category="Default")
    public int Decimals;

    @Parameter(defaultValue="true", name="DebugLogs", category="Logging")
    public boolean DebugLogs;

    @Parameter(defaultValue="false", name="AuditCSV", category="Logging")
    public boolean AuditCSV;

    // --- Lot cap (default OFF) ---
    @Parameter(defaultValue="false", name="EnforceMaxLot", category="Safety")
    public boolean EnforceMaxLot;

    @Parameter(defaultValue="1.50", name="MaxLotCap", minValue=0.0, maxValue=10000.0, step=0.01, category="Safety")
    public double MaxLotCap;

    // ===== Per-symbol state =====
    private static class SymbolState {
        List<Integer> sequence = new ArrayList<>();
        int stock = 0;
        int winStreak = 0;
        double cyclePL = 0.0;
        long prevOpenTime = 0;
        long prevCloseTime = 0;
        boolean initialized = false;
        double sizeStep = 1.0;
    }

    private final Map<String, SymbolState> symbolStates = new ConcurrentHashMap<>();
    private static final int[] INIT_SEQ = {0, 1};

    private SymbolState getState(String symbol) {
        SymbolState st = symbolStates.get(symbol);
        if (st == null) {
            st = new SymbolState();
            resetAll(st);
            symbolStates.put(symbol, st);
        }
        return st;
    }

    private void resetAll(SymbolState st) {
        st.sequence.clear();
        for (int v : INIT_SEQ) st.sequence.add(v);
        st.stock = 0;
        st.winStreak = 0;
        st.cyclePL = 0.0;
        st.prevOpenTime = 0;
        st.prevCloseTime = 0;
        st.initialized = true;
    }

    // ===== Main =====
    @Override
    public double computeTradeSize(StrategyBase strategy, String symbol, byte orderType,
                                   double price, double sl, double tickSize,
                                   double pointValue, double sizeStep) throws Exception {
        String actualSymbol = symbol;
        if (actualSymbol == null || actualSymbol.isEmpty() || "Current".equals(actualSymbol)) {
            try { actualSymbol = strategy.MarketData.Chart(0).Symbol; }
            catch (Exception e) { actualSymbol = symbol; }
        }
        SymbolState st = getState(actualSymbol);

        // Cycle reset by MaxDrawdown
        if (MaxDrawdown != 0.0 && (!st.initialized || st.cyclePL < -MaxDrawdown)) {
            log("DecompMC", "Resetting cycle: CyclePL=%.5f MaxDD=%.5f", st.cyclePL, MaxDrawdown);
            resetAll(st);
        } else if (st.initialized && MaxDrawdown == 0.0 && st.cyclePL < 0) {
            st.cyclePL = 0.0;
        }

        // Apply last closed order exactly once
        Order last = getLastClosedOrder(strategy, actualSymbol);
        if (last != null) {
            boolean isNew = last.OpenTime != st.prevOpenTime || last.CloseTime != st.prevCloseTime;
            if (isNew) {
                double pl = getPL(last);
                st.cyclePL += pl;
                boolean isWin = pl > 0.0;

                if (DebugLogs) log("DecompMC_DEBUG",
                        "Before update  SEQ=%s  WS=%d  STOCK=%d  PL=%.5f",
                        st.sequence.toString(), st.winStreak, st.stock, pl);

                updateSequence_RDR(st, isWin);

                if (DebugLogs) log("DecompMC_DEBUG",
                        "After  update   SEQ=%s  WS=%d  STOCK=%d",
                        st.sequence.toString(), st.winStreak, st.stock);

                st.prevOpenTime = last.OpenTime;
                st.prevCloseTime = last.CloseTime;
            }
        }

        // Bet = left + right
        int left  = st.sequence.get(0);
        int right = st.sequence.size() > 1 ? st.sequence.get(st.sequence.size() - 1) : st.sequence.get(0);
        int betUnits = left + right;

        // Multiplier by win streak
        int mult = multiplier(st.winStreak);

        // Lot size (raw)
        double lot = betUnits * BaseLot * mult;

        // --- Lot cap (before rounding) ---
        if (EnforceMaxLot && MaxLotCap > 0.0 && lot > MaxLotCap) {
            log("DecompMC", "CAP: lot %.5f > MaxLotCap %.5f -> clamp", lot, MaxLotCap);
            lot = MaxLotCap;
        }

        st.sizeStep = sizeStep;

        log("DecompMC", "SEQ=%s BET=%d WS=%d MULT=%d STOCK=%d LOT=%.5f",
                st.sequence.toString(), betUnits, st.winStreak, mult, st.stock, lot);

        if (AuditCSV) {
            audit("time=%d,symbol=%s,seq=%s,bet=%d,ws=%d,mult=%d,stock=%d,lot=%.5f,baselot=%.5f,step=%.5f,dec=%d,cycle_pl=%.5f",
                    System.currentTimeMillis(), actualSymbol, st.sequence.toString(), betUnits, st.winStreak,
                    mult, st.stock, lot, BaseLot, st.sizeStep, Decimals, st.cyclePL);
        }

        // SQ の round を使ってブローカーのサイズステップ＆小数桁へ丸め
        return round(lot, st.sizeStep, Decimals);
    }

    // ===== RDR core =====
    private int multiplier(int ws) {
        if (ws <= 2) return 1;
        if (ws == 3) return 2;
        if (ws == 4) return 3;
        return 5;
    }

    private void updateSequence_RDR(SymbolState st, boolean isWin) {
        List<Integer> seq = st.sequence;
        if (seq.isEmpty()) { seq.add(0); seq.add(1); }

        // Snapshot for LOSE append
        int leftBefore  = seq.get(0);
        int rightBefore = seq.size() > 1 ? seq.get(seq.size() - 1) : seq.get(0);

        if (isWin) {
            // [0,1] の勝ちのみ連勝+1、他の勝ちは ws=0
            if (seq.size() == 2 && seq.get(0) == 0 && seq.get(1) == 1) st.winStreak++;
            else st.winStreak = 0;

            // 1) 左右端を削除
            if (!seq.isEmpty()) seq.remove(0);
            if (!seq.isEmpty()) seq.remove(seq.size() - 1);

            // 2) 残りが1つなら偶奇二分割（偶数→p,p／奇数→floor,ceil）
            if (seq.isEmpty()) {
                seq.add(0); seq.add(1);
            } else if (seq.size() == 1) {
                int v = seq.get(0);
                seq.clear();
                if (v % 2 == 0) { int p = v / 2; seq.add(p); seq.add(p); }
                else            { int l = v / 2; seq.add(l); seq.add(l + 1); }
            }

            // 3) A/B 平均（余りは index1 に集約）／WIN時はストック消費なし
            if (!seq.isEmpty()) {
                if (seq.get(0) == 0) averageA_index1(seq);
                else                  averageB_index1(seq);
            }

        } else {
            // 連勝由来ストックの獲得（ws>=6 の直前連勝があった場合のみ）
            if (st.winStreak <= 5) {
                st.winStreak = 0;
            } else {
                int ws = st.winStreak;
                int winProfit = (ws - 3) * 5 - 8;
                int normalProfit = ws - 2;
                int stockGain = (winProfit - normalProfit);
                st.stock += stockGain;
                st.winStreak = 0;
            }

            // 1) 右端へ (left+right) を追加（最初に必ず実行）
            seq.add(leftBefore + rightBefore);

            // 2) A/B 平均（余りは index1 に集約）
            if (seq.get(0) == 0) averageA_index1(seq);
            else                  averageB_index1(seq);

            // 3) 左>0 の場合のみストック消費（可能な分だけ）
            if (!seq.isEmpty() && seq.get(0) > 0 && st.stock > 0) {
                int use = Math.min(seq.get(0), st.stock);
                seq.set(0, seq.get(0) - use);
                st.stock -= use;
            }

            // 4) 先頭がなお >=1 の場合は 0生成
            if (!seq.isEmpty() && seq.get(0) >= 1) {
                zeroGeneration(seq);
            }
        }

        // セーフガード
        if (seq.isEmpty()) { seq.add(0); seq.add(1); }
    }

    // ===== Averaging : 余りは index1（左から2番目）に集約 =====

    // A平均（左==0）：先頭0は保持し、残り(n-1)を等分。余り r は index1 に集約して +r。
    private void averageA_index1(List<Integer> seq) {
        if (seq.size() < 2 || seq.get(0) != 0) return;
        int nTail = seq.size() - 1;
        long sumTail = 0L;
        for (int i = 1; i < seq.size(); i++) sumTail += seq.get(i);
        int q = (int)(sumTail / nTail);
        int r = (int)(sumTail % nTail);
        for (int i = 1; i < seq.size(); i++) seq.set(i, q);
        if (r > 0) seq.set(1, seq.get(1) + r); // ★ 余りは index1
    }

    // B平均（左>=1）：全体 n を等分。余り r は index1 に集約して +r。
    private void averageB_index1(List<Integer> seq) {
        if (seq.isEmpty()) { seq.add(0); seq.add(1); return; }
        int n = seq.size();
        long S = 0L; for (int v : seq) S += v;
        int q = (int)(S / n);
        int r = (int)(S % n);
        for (int i = 0; i < n; i++) seq.set(i, q);
        if (r > 0) {
            if (n >= 2) seq.set(1, seq.get(1) + r); // ★ 余りは index1
            else        seq.set(0, seq.get(0) + r);
        }
    }

    // ===== 0生成（RDRの3分岐） =====
    private void zeroGeneration(List<Integer> seq) {
        if (seq.isEmpty()) return;
        int redistribute = seq.get(0);
        seq.set(0, 0);

        int S = 0; for (int i = 0; i < seq.size(); i++) S += seq.get(i);
        int subCount = seq.size() - 1;
        if (subCount <= 0) subCount = 1;

        int totalInc = S + redistribute;
        int check = totalInc % subCount;
        int avg   = totalInc / subCount;

        if (redistribute < subCount) {
            // 先頭の値を index1 に集約
            if (seq.size() >= 2) seq.set(1, seq.get(1) + redistribute);
        } else if (check == 0) {
            // 先頭を除去→残りを 0 埋め→+avg→先頭0を追加
            if (!seq.isEmpty()) seq.remove(0);
            for (int i = 0; i < seq.size(); i++) seq.set(i, 0);
            for (int i = 0; i < seq.size(); i++) seq.set(i, seq.get(i) + avg);
            seq.add(0, 0);
        } else { // check >= 1
            if (!seq.isEmpty()) seq.remove(0);
            for (int i = 0; i < seq.size(); i++) seq.set(i, 0);
            for (int i = 0; i < seq.size(); i++) seq.set(i, seq.get(i) + avg);
            if (!seq.isEmpty()) seq.set(0, seq.get(0) + check); // 残りの check は先頭側へ
            seq.add(0, 0);
        }
    }

    // ===== Logging =====
    private void log(String tag, String fmt, Object... args) {
        if (DebugLogs) fdebug(tag, String.format(fmt, args));
    }
    private void audit(String fmt, Object... args) {
        if (AuditCSV) fdebug("DecompMC_AUDIT", String.format(fmt, args));
    }

    // ===== P/L & orders =====
    private double getPL(Order order) {
        return order.isLong() ? order.ClosePrice - order.OpenPrice
                              : order.OpenPrice - order.ClosePrice;
    }

    private String baseSymbol(String sym) {
        if (sym == null) return "";
        int idx = sym.indexOf('_');
        if (idx < 0) idx = sym.indexOf('-');
        return idx >= 0 ? sym.substring(0, idx) : sym;
    }

    private Order getLastClosedOrder(StrategyBase strategy, String symbol) {
        if (symbol == null || symbol.isEmpty() || "Current".equals(symbol)) {
            try { symbol = strategy.MarketData.Chart(0).Symbol; } catch (Exception e) { /* ignore */ }
        }
        String sName = strategy.getStrategyName();

        // TradeControllers
        try {
            Method m = strategy.getClass().getMethod("getTradeControllers");
            Object r = m.invoke(strategy);
            if (r instanceof Object[]) {
                Object[] ctrls = (Object[]) r;
                for (Object c : ctrls) {
                    try {
                        Method mCount = c.getClass().getMethod("getHistoryOrdersCount");
                        Method mOrder = c.getClass().getMethod("getHistoryOrder", int.class);
                        int count = (Integer) mCount.invoke(c);
                        for (int i = count - 1; i >= 0; i--) {
                            Order o = (Order) mOrder.invoke(c, i);
                            if (o.StrategyName == null || !o.StrategyName.startsWith(sName)) continue;
                            if (!baseSymbol(o.Symbol).equals(baseSymbol(symbol))) continue;
                            if (o.OpenPrice == o.ClosePrice) continue;
                            return o;
                        }
                    } catch (Exception ignore) {}
                }
            }
        } catch (Exception ignore) {}

        // Fallback: Trader
        if (strategy.Trader == null) return null;
        for (int i = strategy.Trader.getHistoryOrdersCount() - 1; i >= 0; i--) {
            Order o = strategy.Trader.getHistoryOrder(i);
            if (o.StrategyName == null || !o.StrategyName.startsWith(sName)) continue;
            if (!baseSymbol(o.Symbol).equals(baseSymbol(symbol))) continue;
            if (o.OpenPrice == o.ClosePrice) continue;
            return o;
        }
        return null;
    }
}
