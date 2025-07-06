/*
 * Copyright (c) 2017-2018, StrategyQuant - All rights reserved.
 *
 * Code in this file was made in a good faith that it is correct and does what it should.
 * If you found a bug in this code OR you have an improvement suggestion OR you want to include
 * your own code snippet into our standard library please contact us at:
 * https://roadmap.strategyquant.com
 *
 * This code can be used only within StrategyQuant products.
 * Every owner of valid (free, trial or commercial) license of any StrategyQuant product
 * is allowed to freely use, copy, modify or make derivative work of this code without limitations,
 * to be used in all StrategyQuant products and share his/her modifications or derivative work
 * with the StrategyQuant community.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED,
 * INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR
 * PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS BE LIABLE FOR ANY CLAIM, DAMAGES
 * OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 */
package SQ.MoneyManagement;

import com.strategyquant.lib.*;
import com.strategyquant.datalib.*;
import com.strategyquant.tradinglib.*;

import java.util.*;

@ClassConfig(name="DampenedLabouchereFX", display="Dampened-Labouchere FX MM")
@Help("<b>Dampened-Labouchere FX版 MoneyManagement</b><br>" +
      "バイナリーオプション向けロジックをFXアレンジなしで流用します。" +
      "SL/TPは戦略側から提供され動的に変化します。")
@SortOrder(100)
@Description("Dampened-Labouchere FX")
@ForEngine("*,-Stockpicker,-Single-asset cloud strategy")
public class DampenedLabouchereFXSnippet extends MoneyManagementMethod {

    @Parameter(defaultValue="0.8", name="F_NORMAL", minValue=0.0d, maxValue=10d, step=0.01d, category="Default")
    @Help("通常モード時の係数")
    public double F_NORMAL;

    @Parameter(defaultValue="0.65", name="F_DEFENCE", minValue=0.0d, maxValue=10d, step=0.01d, category="Default")
    @Help("防御モード時の係数")
    public double F_DEFENCE;

    @Parameter(defaultValue="0.06", name="SWITCH_DEBT", minValue=0.0d, maxValue=1d, step=0.01d, category="Default")
    @Help("debt/balance > 6% で防御モードに切替")
    public double SWITCH_DEBT;

    @Parameter(defaultValue="0.52", name="SWITCH_WR", minValue=0.0d, maxValue=1d, step=0.01d, category="Default")
    @Help("直近100取引の勝率 < 52% で防御モードに切替")
    public double SWITCH_WR;

    @Parameter(defaultValue="2", name="SWITCH_REC", minValue=0d, maxValue=100d, step=1d, category="Default")
    @Help("連勝回数が指定値に達したら通常モードに戻す")
    public int SWITCH_REC;

    @Parameter(defaultValue="0.25", name="MULT_STEP", minValue=0.0d, maxValue=10d, step=0.01d, category="Default")
    @Help("3連勝以降の乗数増分")
    public double MULT_STEP;

    @Parameter(defaultValue="3.0", name="MULT_MAX", minValue=0.0d, maxValue=100d, step=0.1d, category="Default")
    @Help("乗数の上限")
    public double MULT_MAX;

    @Parameter(defaultValue="0.01", name="MIN_LOT", minValue=0.0d, maxValue=100d, step=0.01d, category="Default")
    @Help("最小ロット")
    public double MIN_LOT;

    @Parameter(defaultValue="1.0", name="INITIAL_LOT", minValue=0.0d, maxValue=100d, step=0.01d, category="Default")
    @Help("サイクル開始時の初期ロット（ベット値の下限）")
    public double INITIAL_LOT;

    @Parameter(name="SEPARATE_DIRECTION", defaultValue="false", category="Default")
    @Help("true で買いと売りのロット計算を独立させます")
    public boolean SEPARATE_DIRECTION;

    @Parameter(defaultValue="0.0", name="RESET_DD", minValue=0.0d, maxValue=1000000d, step=0.1d, category="Default")
    @Help("ドローダウンがこの金額に達したらサイクルをリセット (0 で無効)")
    public double RESET_DD;

    private static class State {
        List<Double> sequence;
        double debt;
        int streak;
        int cycleId;
        Deque<Boolean> winHist;
        Mode mode;

        State() {
            sequence = null;
            debt = 0.0;
            streak = 0;
            cycleId = 1;
            winHist = new ArrayDeque<>(100);
            mode = Mode.Normal;
        }
    }

    private State longState;
    private State shortState;
    private int lastProcessedOrderIndex;
    private double cycleStartBalance;
    private double cyclePeakBalance;

    private static final double PAYOUT = 1.0;

    private enum Mode { Normal, Defence }

    /**
     * 初期化コンストラクタ
     */
    public DampenedLabouchereFXSnippet() {
        longState = new State();
        shortState = new State();
        lastProcessedOrderIndex = -1;
        cyclePeakBalance = 0.0;
    }

    @Override
    public double computeTradeSize(StrategyBase strategy, String symbol, byte orderType,
                                  double price, double sl, double tickSize, double pointValue,
                                  double sizeStep) throws Exception {
        if (longState.sequence == null) {
            resetCycle(strategy);
        }

        if (lastProcessedOrderIndex == -1) {
            lastProcessedOrderIndex = strategy.Trader.getHistoryOrdersCount() - 1;
        }

        // update internal state based on newly closed trades
        updateStateFromHistory(strategy);

        double balance = strategy.getAccountBalance();
        cyclePeakBalance = Math.max(cyclePeakBalance, balance);
        if (RESET_DD > 0.0 && cyclePeakBalance - balance >= RESET_DD) {
            resetCycle(strategy);
            balance = strategy.getAccountBalance();
            cyclePeakBalance = balance;
        }

        State state = getState(orderType);
        double lot = calculateNextLot(state);
        // debug output disabled
        // debug("MM", "NextLot=" + lot + ", Balance=" + balance + ", Debt=" + state.debt
        //         + ", Streak=" + state.streak + ", Mode=" + state.mode);
        return lot;
    }



    public void resetCycle(StrategyBase strategy) {
        resetState(longState);
        resetState(shortState);
        lastProcessedOrderIndex = strategy.Trader.getHistoryOrdersCount() - 1;
        cycleStartBalance = strategy.getAccountBalance();
        cyclePeakBalance = cycleStartBalance;
    }

    private void resetState(State s) {
        s.sequence = new ArrayList<>(Arrays.asList(0.0, INITIAL_LOT));
        s.debt = 0.0;
        s.streak = 0;
        s.cycleId = 1;
        s.winHist = new ArrayDeque<>(100);
        s.mode = Mode.Normal;
    }

    private double calculateNextLot(State s) {
        double betVal = round(s.sequence.get(0) + s.sequence.get(s.sequence.size() - 1), 2);
        betVal = Math.max(betVal, INITIAL_LOT);
        double mult = (s.streak < 3) ? 1.0 : Math.min(1.0 + (s.streak - 2) * MULT_STEP, MULT_MAX);
        double lot = Math.max(MIN_LOT, round(betVal * mult, 2));
        return lot;
    }

    private State getState(byte orderType) {
        if (SEPARATE_DIRECTION) {
            return OrderTypes.isLongOrder(orderType) ? longState : shortState;
        }
        return longState;
    }

    private State getState(Order order) {
        if (SEPARATE_DIRECTION) {
            return order.isLong() ? longState : shortState;
        }
        return longState;
    }

    // ------------------------------------------------------------------
    // Update internal state from closed trade history
    // ------------------------------------------------------------------
    private void updateStateFromHistory(StrategyBase strategy) {
        int historyCount = strategy.Trader.getHistoryOrdersCount();
        if (historyCount <= 0) return;

        for (int i = lastProcessedOrderIndex + 1; i < historyCount; i++) {
            Order order = strategy.Trader.getHistoryOrder(i);
            if (order.OpenPrice == order.ClosePrice) {
                lastProcessedOrderIndex = i;
                continue;
            }
            double pl = getPL(order);
            boolean win = pl > 0;
            State s = getState(order);
            updateState(s, win, Math.abs(order.Size), strategy.getAccountBalance(), strategy);
            lastProcessedOrderIndex = i;
        }
    }

    // ------------------------------------------------------------------
    // Helper to compute order P/L
    // ------------------------------------------------------------------
    private double getPL(Order order) {
        if (order.isLong()) {
            return order.ClosePrice - order.OpenPrice;
        } else {
            return order.OpenPrice - order.ClosePrice;
        }
    }

    private void updateState(State s, boolean win, double lot, double balance, StrategyBase strategy) {
        double betVal = round(s.sequence.get(0) + s.sequence.get(s.sequence.size() - 1), 2);
        betVal = Math.max(betVal, INITIAL_LOT);
        double mult = (s.streak < 3) ? 1.0 : Math.min(1.0 + (s.streak - 2) * MULT_STEP, MULT_MAX);

        if (!win) {
            s.winHist.add(false);
            if (s.winHist.size() > 100) s.winHist.pollFirst();
            double currentF = currentF(s, balance);
            double appendVal = Math.max(INITIAL_LOT, round(betVal * currentF, 2));
            s.sequence.add(appendVal);
            s.debt += lot - (appendVal * mult);
            s.debt = round(s.debt, 2);
            s.streak = 0;
            // debug("MM", String.format(
            //         "LOSE: appendVal=%.2f, betVal=%.2f, mult=%.2f, debt=%.2f, streak=%d, mode=%s, seq=%s",
            //         appendVal, betVal, mult, s.debt, s.streak, s.mode, s.sequence.toString()));
        } else {
            s.winHist.add(true);
            if (s.winHist.size() > 100) s.winHist.pollFirst();
            double profit = round(lot * PAYOUT, 2);
            if (profit >= s.debt) {
                profit -= s.debt;
                s.debt = 0.0;
                if (s.sequence.size() <= 2) {
                    s.sequence = new ArrayList<>(Arrays.asList(0.0, INITIAL_LOT));
                    s.streak = 0;
                } else {
                    s.sequence = new ArrayList<>(s.sequence.subList(1, s.sequence.size() - 1));
                    s.streak++;
                }
            } else {
                s.debt -= profit;
                s.debt = round(s.debt, 2);
                s.streak++;
            }
            // debug("MM", String.format(
            //         "WIN: profit=%.2f, betVal=%.2f, mult=%.2f, debt=%.2f, streak=%d, mode=%s, seq=%s",
            //         profit, betVal, mult, s.debt, s.streak, s.mode, s.sequence.toString()));
        }

        checkCycleCompletion(strategy, s);
    }

    /**
     * Check if current sequence represents the start state and debt is cleared.
     * If so, consider the Labouchere cycle completed and advance cycleId.
     */
    private void checkCycleCompletion(StrategyBase strategy, State s) {
        double balance = strategy.getAccountBalance();
        if (s.sequence.size() == 2 &&
            Math.abs(s.sequence.get(0)) < 1e-9 &&
            Math.abs(s.sequence.get(1) - INITIAL_LOT) < 1e-9 &&
            Math.abs(s.debt) < 1e-9 &&
            balance >= cycleStartBalance) {
            onCycleComplete(strategy, s);
        }
    }

    private void onCycleComplete(StrategyBase strategy, State s) {
        s.cycleId++;
        s.sequence = new ArrayList<>(Arrays.asList(0.0, INITIAL_LOT));
        s.debt = 0.0;
        s.streak = 0;
        s.winHist.clear();
        s.mode = Mode.Normal;
        lastProcessedOrderIndex = strategy.Trader.getHistoryOrdersCount() - 1;
        cycleStartBalance = strategy.getAccountBalance();
        cyclePeakBalance = cycleStartBalance;
    }

    private double currentF(State s, double balance) {
        double sumWins = 0.0;
        for (boolean w : s.winHist) if (w) sumWins += 1.0;
        double wr = s.winHist.isEmpty() ? 0.5 : (sumWins / s.winHist.size());
        if (s.mode == Mode.Normal && (s.debt / balance > SWITCH_DEBT || wr < SWITCH_WR)) s.mode = Mode.Defence;
        else if (s.mode == Mode.Defence && (s.streak >= SWITCH_REC || s.debt / balance < SWITCH_DEBT * 0.5)) s.mode = Mode.Normal;
        return s.mode == Mode.Defence ? F_DEFENCE : F_NORMAL;
    }

    private static double round(double val, int decimals) {
        double factor = Math.pow(10, decimals);
        return Math.round(val * factor) / factor;
    }
}
