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

    private List<Double> sequence;
    private double debt;
    private int streak;
    private int cycleId;
    private Deque<Boolean> winHist;
    private Mode mode;
    private int lastProcessedOrderIndex;
    private double cycleStartBalance;

    private static final double PAYOUT = 1.0;

    private enum Mode { Normal, Defence }

    /**
     * 初期化コンストラクタ
     */
    public DampenedLabouchereFXSnippet() {
        // parameters are injected after the constructor runs, so initialization
        // using them must be deferred until computeTradeSize() is called
        sequence = null;
        debt     = 0.0;
        streak   = 0;
        cycleId  = 1;
        winHist  = new ArrayDeque<>(100);
        mode     = Mode.Normal;
        lastProcessedOrderIndex = -1;
    }

    @Override
    public double computeTradeSize(StrategyBase strategy, String symbol, byte orderType,
                                  double price, double sl, double tickSize, double pointValue,
                                  double sizeStep) throws Exception {
        if (sequence == null) {
            resetCycle(strategy);
        }

        if (lastProcessedOrderIndex == -1) {
            lastProcessedOrderIndex = strategy.Trader.getHistoryOrdersCount() - 1;
        }

        // update internal state based on newly closed trades
        updateStateFromHistory(strategy);

        double balance = strategy.getAccountBalance();
        double lot = calculateNextLot(balance);
        // debug output disabled
        // debug("MM", "NextLot=" + lot + ", Balance=" + balance + ", Debt=" + debt
        //         + ", Streak=" + streak + ", Mode=" + mode);
        return lot;
    }



    public void resetCycle(StrategyBase strategy) {
        cycleId = 1;
        sequence = new ArrayList<>(Arrays.asList(0.0, INITIAL_LOT));
        debt = 0.0;
        streak = 0;
        winHist = new ArrayDeque<>(100);
        mode = Mode.Normal;
        lastProcessedOrderIndex = strategy.Trader.getHistoryOrdersCount() - 1;
        cycleStartBalance = strategy.getAccountBalance();
        // debug("MM", "ResetCycle: InitialLot=" + INITIAL_LOT + ", CycleId=" + cycleId);
    }

    private double calculateNextLot(double balance) {
        double betVal = round(sequence.get(0) + sequence.get(sequence.size() - 1), 2);
        betVal = Math.max(betVal, INITIAL_LOT);
        double mult = (streak < 3) ? 1.0 : Math.min(1.0 + (streak - 2) * MULT_STEP, MULT_MAX);
        double lot = Math.max(MIN_LOT, round(betVal * mult, 2));
        // debug("MM_Calc", String.format("betVal=%.2f, mult=%.2f, lot=%.2f, debt=%.2f, streak=%d, mode=%s, seq=%s",
        //         betVal, mult, lot, debt, streak, mode, sequence.toString()));
        return lot;
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
            updateState(win, Math.abs(order.Size), strategy.getAccountBalance(), strategy);
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

    private void updateState(boolean win, double lot, double balance, StrategyBase strategy) {
        double betVal = round(sequence.get(0) + sequence.get(sequence.size() - 1), 2);
        betVal = Math.max(betVal, INITIAL_LOT);
        double mult = (streak < 3) ? 1.0 : Math.min(1.0 + (streak - 2) * MULT_STEP, MULT_MAX);

        if (!win) {
            winHist.add(false);
            if (winHist.size() > 100) winHist.pollFirst();
            double currentF = currentF(balance);
            double appendVal = Math.max(INITIAL_LOT, round(betVal * currentF, 2));
            sequence.add(appendVal);
            debt += lot - (appendVal * mult);
            debt = round(debt, 2);
            streak = 0;
            // debug("MM", String.format(
            //         "LOSE: appendVal=%.2f, betVal=%.2f, mult=%.2f, debt=%.2f, streak=%d, mode=%s, seq=%s",
            //         appendVal, betVal, mult, debt, streak, mode, sequence.toString()));
        } else {
            winHist.add(true);
            if (winHist.size() > 100) winHist.pollFirst();
            double profit = round(lot * PAYOUT, 2);
            if (profit >= debt) {
                profit -= debt;
                debt = 0.0;
                if (sequence.size() <= 2) {
                    sequence = new ArrayList<>(Arrays.asList(0.0, INITIAL_LOT));
                    streak = 0;
                } else {
                    sequence = new ArrayList<>(sequence.subList(1, sequence.size() - 1));
                    streak++;
                }
            } else {
                debt -= profit;
                debt = round(debt, 2);
                streak++;
            }
            // debug("MM", String.format(
            //         "WIN: profit=%.2f, betVal=%.2f, mult=%.2f, debt=%.2f, streak=%d, mode=%s, seq=%s",
            //         profit, betVal, mult, debt, streak, mode, sequence.toString()));
        }

        checkCycleCompletion(strategy);
    }

    /**
     * Check if current sequence represents the start state and debt is cleared.
     * If so, consider the Labouchere cycle completed and advance cycleId.
     */
    private void checkCycleCompletion(StrategyBase strategy) {
        double balance = strategy.getAccountBalance();
        if (sequence.size() == 2 &&
            Math.abs(sequence.get(0)) < 1e-9 &&
            Math.abs(sequence.get(1) - INITIAL_LOT) < 1e-9 &&
            Math.abs(debt) < 1e-9 &&
            balance >= cycleStartBalance) {
            onCycleComplete(strategy);
        }
    }

    private void onCycleComplete(StrategyBase strategy) {
        cycleId++;
        sequence = new ArrayList<>(Arrays.asList(0.0, INITIAL_LOT));
        debt = 0.0;
        streak = 0;
        winHist.clear();
        mode = Mode.Normal;
        lastProcessedOrderIndex = strategy.Trader.getHistoryOrdersCount() - 1;
        cycleStartBalance = strategy.getAccountBalance();
        // debug("MM", "Cycle complete -> CycleId=" + cycleId);
    }

    private double currentF(double balance) {
        double sumWins = 0.0;
        for (boolean w : winHist) if (w) sumWins += 1.0;
        double wr = winHist.isEmpty() ? 0.5 : (sumWins / winHist.size());
        if (mode == Mode.Normal && (debt / balance > SWITCH_DEBT || wr < SWITCH_WR)) mode = Mode.Defence;
        else if (mode == Mode.Defence && (streak >= SWITCH_REC || debt / balance < SWITCH_DEBT * 0.5)) mode = Mode.Normal;
        return mode == Mode.Defence ? F_DEFENCE : F_NORMAL;
    }

    private static double round(double val, int decimals) {
        double factor = Math.pow(10, decimals);
        return Math.round(val * factor) / factor;
    }
}
