package SQ.MoneyManagement;

import java.lang.reflect.Array;
import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.util.ArrayList;
import java.util.List;

import com.strategyquant.datalib.*;
import com.strategyquant.lib.*;
import com.strategyquant.tradinglib.*;

@ClassConfig(name="Decomposition Monte Carlo MM", display="Decomposition Monte Carlo MM")
@Help("Implements the betting sequence described in 単数列分解管理モンテカルロ法.txt.")
@SortOrder(950)
@Description("Decomposition Monte Carlo money management method")
@ForEngine("*,-Stockpicker,-Single-asset cloud strategy")
public class DecompositionMonteCarloMM extends MoneyManagementMethod {

    @Parameter(name="Base Lot", defaultValue="0.01", minValue=0.0000001d)
    @Help("Base lot unit used to scale the Monte Carlo coefficients.")
    public double BaseLot;

    @Parameter(name="Max Drawdown", defaultValue="100.0", minValue=0d)
    @Help("If cumulative cycle profit drops below -Max Drawdown the sequence resets.")
    public double MaxDrawdown;

    @Parameter(defaultValue="2", minValue=0d, name="Size Decimals", maxValue=6d, step=1d, category="Default")
    @Help("Order size will be rounded to the selected number of decimal places.")
    public int Decimals;

    private final List<Long> sequence = new ArrayList<>();
    private long stock;
    private int consecutiveWins;
    private double cycleProfit;
    private double currentBetAmount;
    private int processedOrdersCount;
    private boolean initialized;

    public DecompositionMonteCarloMM() {
        resetSequence();
        stock = 0L;
        consecutiveWins = 0;
        cycleProfit = 0d;
        currentBetAmount = 0d;
        processedOrdersCount = 0;
        initialized = false;
    }

    @Override
    public double computeTradeSize(StrategyBase strategy, String symbol, byte orderType, double price, double sl,
            double tickSize, double pointValue, double sizeStep) throws Exception {
        if (BaseLot <= 0d) {
            throw new Exception("BaseLot must be positive.");
        }

        ensureInitialized();

        List<Order> closedOrders = collectClosedOrders(strategy);
        if (closedOrders.size() > processedOrdersCount) {
            for (int i = processedOrdersCount; i < closedOrders.size(); i++) {
                Order order = closedOrders.get(i);
                if (order == null) {
                    continue;
                }
                if (order.OpenPrice == order.ClosePrice) {
                    continue;
                }

                boolean isWin = isWinningOrder(order);
                double betForTrade = currentBetAmount;
                if (isWin) {
                    cycleProfit += betForTrade;
                    processWin();
                } else {
                    cycleProfit -= betForTrade;
                    processLoss();
                }

                if (MaxDrawdown > 0d && cycleProfit < -MaxDrawdown) {
                    resetCycle();
                } else {
                    updateCurrentBetAmount();
                }
            }
            processedOrdersCount = closedOrders.size();
        }

        double lotSize = currentBetAmount;
        return round(lotSize, sizeStep, Decimals);
    }

    private void ensureInitialized() {
        if (!initialized) {
            resetCycle();
            processedOrdersCount = 0;
            initialized = true;
        }
    }

    private List<Order> collectClosedOrders(StrategyBase strategy) {
        List<Order> result = new ArrayList<>();
        if (strategy == null) {
            return result;
        }

        if (!collectFromTradeControllers(strategy, result)) {
            collectFromTrader(strategy, result);
        }

        return result;
    }

    private boolean collectFromTradeControllers(StrategyBase strategy, List<Order> target) {
        try {
            Method getter = strategy.getClass().getMethod("getTradeControllers");
            Object controllers = getter.invoke(strategy);
            if (controllers == null) {
                return true;
            }
            if (!controllers.getClass().isArray()) {
                return false;
            }

            String strategyName = strategy.getStrategyName();
            int length = Array.getLength(controllers);
            for (int i = 0; i < length; i++) {
                Object controller = Array.get(controllers, i);
                if (controller == null) {
                    continue;
                }
                Method historyCountMethod = controller.getClass().getMethod("getHistoryOrdersCount");
                Method historyOrderMethod = controller.getClass().getMethod("getHistoryOrder", int.class);
                int historyCount = toInt(historyCountMethod.invoke(controller));
                for (int index = 0; index < historyCount; index++) {
                    Object orderObj = historyOrderMethod.invoke(controller, index);
                    if (!(orderObj instanceof Order)) {
                        continue;
                    }
                    Order order = (Order) orderObj;
                    if (!strategyName.equals(order.StrategyName)) {
                        continue;
                    }
                    target.add(order);
                }
            }
            return true;
        } catch (NoSuchMethodException e) {
            return false;
        } catch (Exception e) {
            return false;
        }
    }

    private void collectFromTrader(StrategyBase strategy, List<Order> target) {
        Object trader = tryGetTrader(strategy);
        if (trader == null) {
            return;
        }
        if (collectFromTraderHistory(trader, strategy, target)) {
            return;
        }
        collectFromTraderHistoryList(trader, strategy, target);
    }

    private Object tryGetTrader(StrategyBase strategy) {
        try {
            Method method = strategy.getClass().getMethod("getTrader");
            return method.invoke(strategy);
        } catch (Exception e) {
            try {
                Field field = strategy.getClass().getField("Trader");
                return field.get(strategy);
            } catch (Exception ex) {
                return null;
            }
        }
    }

    private boolean collectFromTraderHistory(Object trader, StrategyBase strategy, List<Order> target) {
        try {
            Method countMethod = trader.getClass().getMethod("getHistoryOrdersCount");
            Method orderMethod = trader.getClass().getMethod("getHistoryOrder", int.class);
            int historyCount = toInt(countMethod.invoke(trader));
            String strategyName = strategy.getStrategyName();
            for (int i = 0; i < historyCount; i++) {
                Object orderObj = orderMethod.invoke(trader, i);
                if (!(orderObj instanceof Order)) {
                    continue;
                }
                Order order = (Order) orderObj;
                if (!strategyName.equals(order.StrategyName)) {
                    continue;
                }
                target.add(order);
            }
            return true;
        } catch (NoSuchMethodException e) {
            return false;
        } catch (Exception e) {
            return false;
        }
    }

    private void collectFromTraderHistoryList(Object trader, StrategyBase strategy, List<Order> target) {
        try {
            Method listMethod = trader.getClass().getMethod("getHistoryOrders");
            Object ordersList = listMethod.invoke(trader);
            if (ordersList == null) {
                return;
            }
            Method sizeMethod = findSizeMethod(ordersList.getClass());
            Method getMethod = findGetMethod(ordersList.getClass());
            if (sizeMethod == null || getMethod == null) {
                return;
            }
            int size = toInt(sizeMethod.invoke(ordersList));
            String strategyName = strategy.getStrategyName();
            for (int i = 0; i < size; i++) {
                Object orderObj = getMethod.invoke(ordersList, i);
                if (!(orderObj instanceof Order)) {
                    continue;
                }
                Order order = (Order) orderObj;
                if (!strategyName.equals(order.StrategyName)) {
                    continue;
                }
                target.add(order);
            }
        } catch (Exception e) {
            // no further fallback available
        }
    }

    private Method findSizeMethod(Class<?> clazz) {
        try {
            return clazz.getMethod("size");
        } catch (NoSuchMethodException e) {
            // ignore
        }
        try {
            return clazz.getMethod("getCount");
        } catch (NoSuchMethodException e) {
            // ignore
        }
        try {
            return clazz.getMethod("getSize");
        } catch (NoSuchMethodException e) {
            return null;
        }
    }

    private Method findGetMethod(Class<?> clazz) {
        try {
            return clazz.getMethod("get", int.class);
        } catch (NoSuchMethodException e) {
            // ignore
        }
        try {
            return clazz.getMethod("getOrder", int.class);
        } catch (NoSuchMethodException e) {
            return null;
        }
    }

    private int toInt(Object value) {
        if (value instanceof Number) {
            return ((Number) value).intValue();
        }
        if (value instanceof Boolean) {
            return ((Boolean) value) ? 1 : 0;
        }
        return 0;
    }

    private boolean isWinningOrder(Order order) {
        double profit = order.ClosePrice - order.OpenPrice;
        if (!order.isLong()) {
            profit = -profit;
        }
        return profit > 0d;
    }

    private void processWin() {
        if (sequence.isEmpty()) {
            resetSequence();
        }

        int count = sequence.size();
        long left = sequence.get(0);
        long right = sequence.get(sequence.size() - 1);

        if (count == 2 && left == 0 && right == 1) {
            consecutiveWins++;
        }

        if (count == 2) {
            resetSequence();
        } else if (count == 3) {
            sequence.remove(0);
            sequence.remove(0);
            if (sequence.isEmpty()) {
                resetSequence();
            } else {
                long value = sequence.get(0);
                long remainder = value % 2L;
                long half = value / 2L;
                sequence.clear();
                sequence.add(half);
                sequence.add(half + remainder);
            }
        } else if (count > 2) {
            sequence.remove(0);
            if (!sequence.isEmpty()) {
                sequence.remove(sequence.size() - 1);
            }
        }

        applyAveraging();
    }

    private void processLoss() {
        if (consecutiveWins <= 5) {
            consecutiveWins = 0;
        } else {
            long streakProfit = (long) (consecutiveWins - 3) * 5L - 8L;
            long normalProfit = consecutiveWins - 2L;
            stock += (streakProfit - normalProfit);
            consecutiveWins = 0;
        }

        if (sequence.isEmpty()) {
            resetSequence();
        }

        long left = sequence.get(0);
        long right = sequence.get(sequence.size() - 1);
        sequence.add(left + right);

        applyAveraging();

        consumeStock();
        redistributeZero();
    }

    private void applyAveraging() {
        if (sequence.isEmpty()) {
            resetSequence();
        }

        int count = sequence.size();
        if (count == 0) {
            return;
        }

        long sum = sumSequence();
        long left = sequence.get(0);

        if (left == 0) {
            if (count <= 1) {
                return;
            }
            long remainder = sum % (count - 1L);
            sequence.remove(0);
            fillWithZero();
            long average = sum / (count - 1L);
            addToAll(average);
            if (!sequence.isEmpty() && remainder > 0) {
                sequence.set(0, sequence.get(0) + remainder);
            }
            sequence.add(0, 0L);
        } else {
            long remainder = sum % count;
            fillWithZero();
            long average = sum / count;
            addToAll(average);
            if (sequence.size() > 1 && remainder > 0) {
                sequence.set(1, sequence.get(1) + remainder);
            }
        }
    }

    private void consumeStock() {
        if (sequence.isEmpty()) {
            return;
        }
        long first = sequence.get(0);
        if (first <= stock) {
            stock -= first;
            sequence.set(0, 0L);
        }
    }

    private void redistributeZero() {
        if (sequence.isEmpty()) {
            return;
        }
        long first = sequence.get(0);
        if (first < 1L) {
            return;
        }

        long redistribution = first;
        sequence.set(0, 0L);
        long total = sumSequence() + redistribution;
        int redistributeCount = sequence.size() - 1;
        if (redistributeCount <= 0) {
            return;
        }
        long remainder = total % redistributeCount;
        long distributed = total / redistributeCount;

        if (redistribution < redistributeCount) {
            if (sequence.size() > 1) {
                sequence.set(1, sequence.get(1) + redistribution);
            }
        } else {
            sequence.remove(0);
            fillWithZero();
            addToAll(distributed);
            if (!sequence.isEmpty() && remainder > 0) {
                sequence.set(0, sequence.get(0) + remainder);
            }
            sequence.add(0, 0L);
        }
    }

    private void resetCycle() {
        resetSequence();
        stock = 0L;
        consecutiveWins = 0;
        cycleProfit = 0d;
        updateCurrentBetAmount();
    }

    private void resetSequence() {
        sequence.clear();
        sequence.add(0L);
        sequence.add(1L);
    }

    private void updateCurrentBetAmount() {
        double coefficient = computeBetCoefficient();
        currentBetAmount = BaseLot * coefficient;
    }

    private double computeBetCoefficient() {
        if (sequence.isEmpty()) {
            return 0d;
        }
        long left = sequence.get(0);
        long right = sequence.size() > 1 ? sequence.get(sequence.size() - 1) : left;
        long betValue = left + right;
        double multiplier = 1d;
        if (consecutiveWins == 3) {
            multiplier = 2d;
        } else if (consecutiveWins == 4) {
            multiplier = 3d;
        } else if (consecutiveWins >= 5) {
            multiplier = 5d;
        }
        return betValue * multiplier;
    }

    private long sumSequence() {
        long sum = 0L;
        for (Long value : sequence) {
            sum += value;
        }
        return sum;
    }

    private void fillWithZero() {
        for (int i = 0; i < sequence.size(); i++) {
            sequence.set(i, 0L);
        }
    }

    private void addToAll(long value) {
        for (int i = 0; i < sequence.size(); i++) {
            sequence.set(i, sequence.get(i) + value);
        }
    }
}