
# Building Freemarker Templates for Custom MQL5 Money Management Snippets in SQX

## Overview: Freemarker in StrategyQuant X Export System

StrategyQuant X (SQX) uses a template-based code generation system for exporting strategies to various platforms (MT4, MT5, etc.). These templates are written in **Apache Freemarker** – a scripting language that allows inserting placeholders and logic into text files. In SQX, every strategy component (indicators, signals, money management, etc.) has corresponding template files (.tpl) that define how that component is translated into the target language’s code. When you export a strategy to MQL5, SQX processes the templates with Freemarker, replacing placeholders with actual strategy parameters/logic, and produces a complete .mq5 expert advisor file. This system lets developers customize how strategies are exported by editing or adding templates, rather than modifying the code manually each time.

In the context of **Money Management (MM)**, SQX’s internal engine might use a Java snippet (extending an `MoneyManagementMethod` class) to calculate position sizing during backtests. To replicate that logic in the exported MQL5 code, you must create Freemarker templates for your custom MM snippet. Freemarker’s role here is to inject your snippet’s logic and parameters into the generated MQL5 source, ensuring the EA trades with the same position sizing rules as it did in SQX’s backtest.

## Template File Structure and Naming Conventions

For each custom Money Management snippet, SQX expects specific template files to be present for every supported platform (MT4, MT5, etc.). The templates for MQL5 are typically placed in the **MQL5\MoneyManagement** folder of the SQX **Code** templates directory. Each snippet’s templates are named after the snippet’s class name, with suffixes indicating where the code will be inserted:

* **`<SnippetName>_variables.tpl`** – Defines any input parameters or global variables used by the MM snippet in the MQL5 code.
* **`<SnippetName>_entry.tpl`** – Contains the code to execute when a new trade is initiated (e.g., calculating the lot size before sending an order).
* **`<SnippetName>_exit.tpl`** – Contains the code to execute when a trade is closed or exited (often not needed for simple position sizing logic, but required if your MM method needs to adjust on exit).

For example, if your snippet class is named `ATRVolatilitySizing`, you should have:

```
MQL5/MoneyManagement/ATRVolatilitySizing_variables.tpl  
MQL5/MoneyManagement/ATRVolatilitySizing_entry.tpl  
MQL5/MoneyManagement/ATRVolatilitySizing_exit.tpl  
```

These filenames must match exactly (including case) the snippet class name and the suffix. If any required template is missing, the exporter will throw an error like *“Template inclusion failed (for parameter value ‘MoneyManagement/ATRVolatilitySizing\_variables.tpl’)”* and refuse to generate the code. Ensuring the correct files exist in the proper directory lets SQX include your MM snippet in the output EA.

**Template structure:** A StrategyQuant strategy’s exported EA is composed by assembling various code sections. The `*_variables.tpl` content is typically inserted into the global scope of the EA (for extern/input declarations and global variables). The `*_entry.tpl` content is inserted in the code path where a new position is opened (for example, inside the buy/sell signal handling, before calling order execution). The `*_exit.tpl` content would be inserted when a position exit logic runs (if the MM snippet influences exits or needs cleanup). In many money management scenarios, the main logic goes into the entry template (to compute lot size on trade initiation) while the exit template may remain empty or handle special cases like resetting counters (e.g., in Martingale strategies).

**Tip:** When you create a new Money Management snippet in the SQX Code Editor, the system might generate default placeholder templates for you (sometimes these are blank or generic). Always verify the template filenames and adjust their content to implement your logic. The SQX documentation notes that every custom building block or snippet must have a template for each target platform to be usable in exported code – money management methods are no exception.

## Accessing Snippet Parameters in Freemarker Templates

Within your Freemarker templates, you will need to reference the parameters and variables defined in your Java snippet. SQX exposes snippet parameters to Freemarker, allowing you to print their values or names using special directives. The common pattern is to use Freemarker *macro calls* like `<@printParam>` or related macros.

For example, to reference a parameter named `RiskPercent` (defined in your Java snippet with `@Parameter`), you can use:

```ftl
<@printParam block "#RiskPercent#" />
```

This Freemarker macro will insert the parameter’s value or code representation at that point in the output. In SQX templates, the `#ParamName#` notation (with the parameter name in quotes after a hash) refers to the Java field, and `<@printParam block "...">` outputs it appropriately in code. Under the hood, if `RiskPercent` is an input setting for the strategy, the template engine might output a variable or constant representing that value in the generated code. For instance, if `RiskPercent` is 2 (%), the macro could output `2` or a variable that holds 2.0 in the final code, depending on context.

**Defining inputs:** In the `*_variables.tpl` file, you’ll usually want to create EA inputs for each user-configurable parameter of your MM snippet. Often, this can be done by writing the line manually using the parameter name. For example, if your snippet has:

```java
@Parameter(defaultValue="2", name="Risk %") 
public double RiskPercent;
```

You might have in `MySnippet_variables.tpl` something like:

```cpp
input double RiskPercent = <@printParam block "#RiskPercent#" />;
```

If the macro `<@printParam>` is used in a variable definition context, it should output the default value (here `2.0`) as a literal. Alternatively, you could simply write the default value directly if needed. The key is that the input name in the MQL5 code matches the snippet’s parameter so that the rest of the template can reference it. Another macro, `<@printParamOptions>`, exists for parameters with enumerated options (it translates an option index to the actual option text), though this is more applicable to things like indicator parameters (e.g., moving average method). For numeric inputs like lot sizes or percentages, `<@printParam>` or direct insertion is sufficient.

**Using parameters in calculations:** In the `*_entry.tpl` (and `*_exit.tpl` if used), you can directly use the parameter names as variables (assuming you declared them as inputs in the variables section). The generated EA code will have those as global variables (because of the input definitions). For example, after defining `RiskPercent` as an input, you can write MQL5 code in the entry template that uses `RiskPercent` in an expression (no special syntax needed since it’s now a normal MQL variable in the EA). If you prefer, you can still use Freemarker to print the parameter value inline. For instance, writing `${RiskPercent}` in the template may insert the number 2.0 directly. However, best practice is to rely on the input variable so that the user can adjust it in the EA settings. In summary, use Freemarker macros to **declare** and **initialize** parameters, then use normal MQL code (possibly with Freemarker injecting any needed snippet-specific logic or function calls) to implement the sizing formula.

## Generating MQL5 Code for Position Sizing Logic

The core of your templates will be the logic that calculates the trade **lot size** based on your strategy’s money management rules. Below, we discuss common MM scenarios and how to implement them in MQL5 via the templates:

### 1. Fixed Lot Size

This is the simplest money management method. The lot size does not change per trade – it’s a fixed value (e.g., always 0.10 lots). In your snippet’s Java code, you might have a parameter like `public double LotSize` (with a default). In the MQL5 templates, you would:

* **Variables template:** Declare an input for the fixed lot size. For example:

  ```cpp
  input double LotSize = <@printParam block "#LotSize#" />;  // default lot size
  ```

  This will appear at the top of the EA code, allowing the user to adjust it if needed.

* **Entry template:** Use the `LotSize` when placing orders. For instance, your code could simply set the trade volume to this value:

  ```cpp
  double tradeVolume = LotSize;
  ```

  Then proceed to call the order execution (more on that in the integration section). Essentially, the Freemarker template for entry might just output `tradeVolume = LotSize;` or directly use `LotSize` in the order send call.

Fixed lot sizing doesn’t require any complex calculation – the template just inserts the constant or variable. The advantage of making it an EA input is flexibility. Note that SQX’s built-in “Fixed size” MM corresponds to this approach, trading a constant number of lots each time.

### 2. Fixed Percentage Risk per Trade

Risk-% position sizing adjusts the lot size such that a fixed percentage of account equity (or balance) is at risk on each trade. This method is widely recommended for real trading because it compounds position size as the account grows or shrinks. Implementing this in MQL5 requires access to the account balance/equity and the trade’s stop-loss distance:

**Parameters:** Typically you’ll have a parameter for the risk percentage (e.g., `RiskPercent`) and the method of calculation (risk on equity vs balance – equity is more dynamic, including open P/L, whereas balance is fixed until trades close). For simplicity, assume `RiskPercent` and maybe a boolean or enum for equity vs balance.

* **Variables template:** Define `RiskPercent` as an input (as shown earlier). If you need a toggle between equity/balance, that could be another input (or simply decide one method in code).

* **Entry template logic:** When a new trade signal occurs, calculate the lot size as:

  1. **Determine account risk amount** – how much money is X% of the account. In MQL5, you can get account equity or balance via `AccountInfoDouble()`. For example:

     ```cpp
     double accountValue = AccountInfoDouble(ACCOUNT_BALANCE);
     double riskAmount = accountValue * RiskPercent / 100.0;
     ```

     If using equity, replace `ACCOUNT_BALANCE` with `ACCOUNT_EQUITY`. The variable `riskAmount` is the money you’re willing to lose on this trade.

  2. **Determine stop-loss distance** – The snippet should know the stop-loss for the trade. In SQX, the `computeTradeSize` method receives a `double sl` parameter (stop-loss price) and the entry `price`. In MQL5 EA, you need to get the planned SL. If your strategy sets SL as part of the rules, that SL price or distance can be determined in the code. For example, if you have a stop-loss price, compute the distance in points:

     ```cpp
     double entryPrice = ...;  // entry price for the trade (e.g., current market price for market orders)
     double stopLossPrice = ...;  // the price at which SL would be placed
     double stopDistance = MathAbs(entryPrice - stopLossPrice);
     ```

     It’s essential to get this in the same units as tick value (see next step). Often, using points/pips is convenient. MQL5 provides symbol properties for point size and tick value:

     ```cpp
     double pt = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
     double tickVal = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
     double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
     ```

     *Note:* In many FX symbols, `tickSize == pt` (one point is one tick), and `tickVal` gives the value of one tick movement for one lot (in account currency). For risk calculations, a general formula is: **loss per lot = stopDistance/tickSize \* tickVal**. This computes how much money one lot would lose if price moves by `stopDistance`.

  3. **Compute lot size** – Divide the risk amount by the monetary loss per 1 lot:

     ```cpp
     double lossPerLot = 0.0;
     if(stopDistance > 0) {
         lossPerLot = (stopDistance / tickSize) * tickVal;
     }
     double rawLots = 0.0;
     if(lossPerLot > 0) {
         rawLots = riskAmount / lossPerLot;
     } else {
         rawLots = 0.0;
     }
     ```

     Here, `rawLots` is the unadjusted lot size to risk \~`RiskPercent` of the account. We handle the case `lossPerLot=0` (which can happen if no SL or zero distance) by defaulting to 0 lots – meaning if no stop is defined, the risk% MM cannot size the trade. You might choose to fall back to a minimal lot in such a case, or skip trading (depending on strategy requirements).

  4. **Apply broker lot constraints** – It’s crucial to adjust `rawLots` to a valid lot size before trading. Brokers have a minimum lot size, a lot step (increment), and a maximum. Use `SymbolInfoDouble` to retrieve these and then round the lot size:

     ```cpp
     double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
     double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
     double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
     // Ensure not below minimum
     double lots = (rawLots < minLot && rawLots > 0 ? minLot : rawLots);
     // Round down to nearest lot step
     lots = MathFloor(lots / lotStep) * lotStep;
     // Cap at maximum lot
     if(lots > maxLot) lots = maxLot;
     ```

     This will ensure the volume we send is acceptable to the broker (e.g., if min lot is 0.01 and rawLots = 0.005, we set 0.01; if rawLots = 0.027 and step is 0.01, we round to 0.02; if rawLots is huge, cap to max). Rounding **down** is usually safer to not exceed risk. You might also choose `MathRound` if you prefer standard rounding to nearest step, but in risk management, rounding down is conservative.

  5. **Use the lot size** – Finally, the template should output code that uses this computed `lots` value in the trade execution function (e.g., `OrderSend`). For instance:

     ```cpp
     if(lots <= 0) {
         // No trade if size is zero (or you could set lots=minLot to ensure at least one micro lot trades)
         return;
     }
     // Prepare order request with 'lots' as volume...
     ```

Putting it together, a simplified snippet for the entry template could be:

```cpp
double accountValue = AccountInfoDouble(ACCOUNT_BALANCE);
double riskAmount = accountValue * RiskPercent / 100.0;
double entryPrice = Bid;  // assuming a sell order example, use Ask for buy
double stopLossPrice = entryPrice - (StopLossPoints * _Point);  // if StopLossPoints is defined
double stopDistance = MathAbs(entryPrice - stopLossPrice);
double tickVal = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
double lossPerLot = (stopDistance / tickSize) * tickVal;
double rawLots = (lossPerLot > 0 ? riskAmount / lossPerLot : 0);
double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
if(rawLots < minLot && rawLots > 0) rawLots = minLot;
double lots = MathFloor(rawLots / lotStep) * lotStep;
if(lots < minLot && rawLots > 0) lots = minLot;  // ensure at least min lot if we had a positive rawLots
if(lots > maxLot) lots = maxLot;
```

This code would be inserted by the Freemarker template. Notice we used `RiskPercent` (which is assumed to be defined as input earlier) directly in the expression. If your snippet had any fixed constants (like a default SL distance if none provided), you could also include those as parameters or hard-code as needed.

**Important:** The above uses Balance for risk calculation. If you wanted to risk based on Equity, simply switch to `ACCOUNT_EQUITY` when fetching `accountValue`. You could make that conditional via a parameter (e.g., a boolean `UseEquity`) and using Freemarker if/else in the template to choose the appropriate account field.

### 3. ATR-Based Position Sizing

ATR-based sizing is a volatility-adjusted method. One common technique is to alter the lot size based on a short-term ATR versus a long-term ATR – for example, trade larger when volatility is low and smaller when volatility is high, or vice versa. Another interpretation is setting the position size such that a move of 1 ATR corresponds to a fixed percentage of equity.

A concrete example from SQX is the **ATR Volatility Sizing** snippet, which compares a fast ATR to a slow ATR and adjusts the lot accordingly. The Java snippet for that logic looked like: *if short-term ATR > long-term ATR, then trade size = Size \* Multiplier; else trade size = Size*\*. We can implement similar logic in MQL5:

**Parameters:** Let’s say the snippet defines:

* `Size` – base lot size (e.g., 0.1 lots)
* `Multiplier` – factor by which to increase the lot if volatility is higher
* `FastATRPeriod` – period for fast ATR (e.g., 5)
* `SlowATRPeriod` – period for slow ATR (e.g., 20)

You would declare these in the variables template as inputs:

```cpp
input double Size = <@printParam block "#Size#" />;  
input double Multiplier = <@printParam block "#Multiplier#" />;  
input int FastATRPeriod = <@printParam block "#FastATRPeriod#" />;  
input int SlowATRPeriod = <@printParam block "#SlowATRPeriod#" />;
```

**Entry template logic:** Use MQL5’s ATR indicator or your own ATR calculation to get the values for the current symbol/timeframe:

```cpp
double fastATR = iATR(_Symbol, PERIOD_CURRENT, FastATRPeriod, 1);  // ATR of last completed bar
double slowATR = iATR(_Symbol, PERIOD_CURRENT, SlowATRPeriod, 1);
double lots = Size;
if(fastATR > slowATR) {
    lots = Size * Multiplier;
} else {
    lots = Size;
}
```

This mirrors the snippet’s logic (increase lot to `Size*Multiplier` when short-term volatility exceeds long-term volatility). Here we used `iATR` which is a built-in MQL5 function returning the ATR value; the `1` index gets the ATR of the previous bar (assuming we are executing on a new tick of the current bar and want the last full bar’s ATR).

We should also ensure the calculated `lots` respects broker constraints as described earlier. In this case, `Size` itself should likely be set to a valid minimal lot (like 0.1), and multiplying it by `Multiplier` should still yield a sane number, but it’s good practice to run the rounding logic on `lots` as well:

```cpp
// ... after computing lots:
double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
if(lots < minLot && lots > 0) lots = minLot;
lots = MathFloor(lots / lotStep) * lotStep;
if(lots < minLot && lots > 0) lots = minLot;
if(lots > maxLot) lots = maxLot;
```

In ATR sizing, `Size` is usually already a multiple of min lot, so this is mostly to catch edge cases (e.g., if `Size=0.03` and min lot=0.01, it’s fine; but if `Size=0.03` and broker min is 0.10, we’d bump it up).

**Alternative ATR sizing approaches:** Another ATR-based method is to tie the stop-loss to ATR and then use the risk% formula. For example, some strategies set SL = X \* ATR, and then use fixed risk%. In that scenario, you combine the two methods: use ATR to determine `stopDistance` (instead of a fixed pip value), then apply the risk-percent formula to compute lots. This effectively risks a fixed % on an ATR-based stop. The template code could call `iATR` to get the ATR value and use it in place of (or to calculate) `stopDistance`. For instance:

```cpp
double atr = iATR(_Symbol, PERIOD_CURRENT, ATRPeriod, 1);
double stopDistance = atr * ATRMultiplier;  // ATRMultiplier could be a parameter like 1.5 for 1.5*ATR SL
// then proceed with risk% calculation as above, using stopDistance.
```

This way, on each trade the lot size will naturally be larger when ATR (volatility) is low (because stopDistance is smaller, yielding a larger `rawLots` for the same risk%) and smaller when ATR is high.

When implementing such logic, make sure all needed parameters (ATR period, multipliers, etc.) are exposed as inputs in the variables template, and use them in the entry template computations.

## Best Practices for MQL5 Trade Execution Integration

After computing the lot size, the final step is integrating it into the **order execution** in MQL5. StrategyQuant’s exported code typically handles order sending via the MQL5 API (either using the `CTrade` class or the `OrderSend` function with an `MqlTradeRequest`). Here are some best practices to follow in your templates:

* **Use MqlTradeRequest and MqlTradeResult (or CTrade)**: In MQL5 (hedging mode), you place trades by filling an `MqlTradeRequest` structure and calling `OrderSend`. Your template can either output a block of code to fill this request or call a SQX-provided wrapper if one exists. For clarity, an example of a direct approach:

  ```cpp
  MqlTradeRequest request;
  MqlTradeResult result;
  ZeroMemory(request);
  request.action   = TRADE_ACTION_DEAL;                  // immediate trade
  request.symbol   = _Symbol;
  request.volume   = lots;                               // volume computed by MM
  request.type     = ORDER_TYPE_BUY;                     // or ORDER_TYPE_SELL
  request.price    = (request.type == ORDER_TYPE_BUY ? Ask : Bid);
  request.sl       = stopLossPrice;
  request.tp       = takeProfitPrice;
  request.deviation= SlippagePoints;                     // slippage tolerance in points (input or constant)
  request.magic    = MAGIC;                              // EA magic number (if defined)
  OrderSend(request, result);
  ```

  In many SQX templates, `SlippagePoints` and `MAGIC` might be predefined inputs or constants in the strategy template. Ensure you integrate with those if available (you can add them in variables tpl if not). The key is to use the `lots` variable in the request. Also, check `result.retcode` after `OrderSend` for success or failure, and handle accordingly if needed (logging an error, etc.).

* **Slippage handling**: Slippage is specified via the `deviation` field in `MqlTradeRequest` (as points). If the user has a slippage setting (say, 5 points), include it. This is especially important for market orders on fast-moving symbols. If using the `CTrade` class (from `<Trade\Trade.mqh>`), you can set slippage by `trade.SetDeviationInPoints(x)` or by passing it as a parameter to `PositionOpen` if that API is used. In any case, make slippage configurable (input) if the strategy might need tuning for different brokers.

* **Volume normalization**: We already covered ensuring `lots` is aligned with `SYMBOL_VOLUME_STEP` and min/max. **Never skip this check** – broker requirements are strict and MQL5 will refuse `OrderSend` with invalid volume, leading to runtime errors. Also consider the case `lots` becomes 0 (e.g., very small account or very tight stop with low risk%). It’s wise to handle `if(lots <= 0)` as a no-trade condition or set it to the minimum lot as a fallback. For example:

  ```cpp
  if(lots <= 0) {
      lots = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
  }
  ```

  or decide not to trade at all in that case (to preserve the risk management intent).

* **Rounding**: Use `MathFloor` or `MathRound` as needed to match the desired behavior. Remember that floating-point rounding can introduce tiny errors (like 0.099999 instead of 0.1). MQL5 has a `NormalizeDouble(value, digits)` function which can help ensure the lot value has the correct precision (for example, `NormalizeDouble(lots, (int) SymbolInfoInteger(_Symbol,SYMBOL_VOLUME_DIGITS))`). This isn’t always necessary, but for printing or logging it may present cleaner numbers.

* **Order context**: If your strategy allows multiple orders (hedging mode, multiple entries), ensure the code using `OrderSend` handles that properly (MQL5 hedging can have many positions per symbol, netting cannot). In netting mode (one position per symbol), if an order is sent in the opposite direction, it will close or reduce the existing position. SQX strategies typically assume hedging mode for MT5 (since SQX can generate multiple entry signals). Just be aware: *the money management logic might need to consider existing positions in netting mode.* For example, if you try to “add” a position in netting mode, you’re actually changing the size of the single position (this could affect risk calculations, since part of the position is already open). Covering that thoroughly might be beyond your snippet’s scope, but it’s a constraint to note for advanced scenarios.

* **StopLoss/TakeProfit setting**: Ensure that if you calculate lots assuming a certain stop-loss, you actually apply that stop-loss in the order. The above request snippet sets `request.sl`. If your strategy’s SL is defined in points or as a ratio, convert it to price and assign. This ensures the risk management logic (which relied on that SL) matches the actual trade in MetaTrader. Inconsistency here could result in taking on a different risk than intended.

* **Testing in Strategy Tester**: Once integrated, compile the EA and run it in MT5’s Strategy Tester. Check that the position sizes match what you expect from your logic. If something seems off (e.g., all trades still use fixed size or volumes don’t change with equity), it might indicate the template didn’t correctly reference the right variables or there’s a logic bug. Use `Print()` statements in your template (which will appear in the MQL5 code) to output debug info such as `RiskPercent`, `accountValue`, `stopDistance`, `rawLots`, etc., during a test run. This can help verify each step of the calculation at runtime.

## Debugging and Verifying the Generated Code

Developing custom templates may involve a few iterations to get everything working. Here are some tips for debugging:

* **Use SQX’s Source Code preview**: After adding your templates, open a strategy that uses your custom MM snippet in StrategyQuant’s **Results** section and go to the **Source code** tab. Select MetaTrader 5 (MQL5) as the target code. SQX will attempt to generate the EA code on the fly. If your templates are correctly placed, you should see the MQL5 code (with your snippet’s logic embedded). This is a quick way to verify that the syntax looks correct. You can scroll through and find your MM snippet’s section (for example, look for your parameter names or comment placeholders you added).

* **Common errors**: If the source code tab reports an error like *“One or more blocks the strategy uses isn’t implemented in MQL code”* or *“Template inclusion failed for ...tpl”*, it means SQX could not find or process your template files. Double-check the file naming, directory, and that you restarted SQX after adding them (SQX loads templates at startup). The error message usually specifies which file is missing, so you know where to look. Ensure that all three templates (\_variables, \_entry, \_exit) are present even if one of them is essentially empty (an empty file is acceptable if nothing is needed for that part, but the file must exist).

* **Freemarker syntax issues**: If the code generation runs but the output code has mistakes (e.g., missing commas, incorrect variable names), you might have a typo or syntax issue in templates. Freemarker will generally insert exactly what you put around the macros. For example, forgetting a semicolon at end of a line in the template will lead to a compilation error in MQL5. Check the generated code for any red highlights or compile it in MetaEditor to catch such errors. You can edit the template, restart SQX, and refresh the source code to see if the issue is resolved.

* **Runtime verification**: After exporting the strategy to an .mq5 file and compiling in MetaTrader, run a backtest. Compare the trade history with SQX’s backtest to ensure the position sizing matches. For instance, if SQX backtest showed increasing lot sizes as equity grew (for a risk % method), the MT5 backtest should reflect that as well. Small differences can occur due to calculation rounding or broker-specific conditions, but they should be minor if done correctly. If you see a big discrepancy (e.g., MT5 EA always trades 0.01 lots when SQX was varying), it suggests the code isn’t using the right values – perhaps the EA isn’t reading equity correctly or a parameter didn’t carry over. In such cases, insert `Print` statements in the EA (via the template) to output the values of key variables each trade. For example:

  ```cpp
  Print("Balance=", AccountInfoDouble(ACCOUNT_BALANCE),
        " Equity=", AccountInfoDouble(ACCOUNT_EQUITY),
        " Risk%=", RiskPercent,
        " CalcLots=", lots);
  ```

  This will show in the MT5 Journal what the EA is seeing and doing, helping you pinpoint any logic issue.

* **SQX Backtest vs MT5 Differences**: Note that SQX’s internal backtester might yield slightly different results from MT5 even with identical logic, due to different data handling or execution modeling. However, the money management logic should be equivalent if implemented correctly. The SQX team notes that differences are normal and not necessarily a mistake, but your goal is to have the logic itself aligned. Use a simple scenario to test (e.g., fixed 2% risk on a single trade) and confirm both SQX and MT5 would compute the same lot size.

* **Logging in SQX**: If needed, you can use the SQX Java snippet’s debugging tools (like `DebugConsole.log()` or similar) to ensure the snippet itself works as expected internally, but since our focus is the export, the main debugging is on the template/MQL side.

## Constraints and Known Issues

When exporting custom money management snippets to MQL5, keep in mind some limitations and quirks:

* **Platform differences**: MQL5 (especially in netting mode) is different from SQX’s internal engine. SQX can simulate multiple simultaneous positions regardless of account mode, but if your target account is netting, opening a new trade in the opposite direction will merge or close with the existing position. This could affect certain MM strategies (like Martingale or grid systems). SQX’s export doesn’t automatically adjust for netting mode, so you may need to include logic in the EA to handle position updates. For example, a Martingale snippet that doubles lot after a loss should, in netting mode, either use Buy/Sell stops in one direction or calculate how to increase an existing position. This is an advanced use-case, but worth noting as a constraint of the target platform rather than SQX itself.

* **Data availability**: Some snippet logic might depend on data that’s available in SQX but not directly in MQL5. For instance, SQX can easily get *previous trade results, portfolio-level equity, or custom metrics*. In MQL5, to replicate that, you might need to code additional tracking. Example: a snippet that risks % of **initial** account balance (instead of current) – in SQX you have initial capital stored; in MT5, once the account is live, initial balance isn’t readily available (you’d have to store it at EA start). Be prepared to augment your EA code to carry such info (e.g., saving initial balance in an `OnInit` function variable).

* **Precision and rounding**: Differences in floating-point arithmetic between Java (SQX) and MQL5 could lead to tiny differences in calculated lot sizes. Usually this isn’t significant (0.0999 vs 0.1 lot will be rounded by our code anyway). Just be aware when verifying results; focus on the major differences.

* **No stop-loss provided**: If the strategy does not define a stop-loss but you apply a risk% MM, the formula breaks down (division by zero distance). SQX’s own “Risk fixed %” snippet would normally not be used without a stop-loss in the strategy – it assumes a SL exists so that risk can be measured. If you attempt to use it without SL, SQX might simply trade a minimum lot (in backtest possibly fixed size). In your exported EA, you should handle this scenario. One approach is to **default to a fixed lot** when no SL is present (or use an ATR-based stop guess). Clearly document this constraint: “If no Stop Loss is set, the EA will use X lots (or skip trade) because risk% sizing can’t be computed.” This is a logical constraint of the MM method.

* **Testing with different symbols**: Ensure your code accounts for different instrument properties. For example, on indices or stocks, `SYMBOL_TRADE_TICK_VALUE` might be in quote currency or USD, etc., and `SYMBOL_POINT` might not be a pip but e.g. 1 index point. The formulas still work, but always test on the instrument types you intend (forex, CFD, crypto, etc.). If your snippet is only meant for forex, that simplifies things. If it’s intended for futures or others, be cautious with point vs pip (some futures have weird tick sizes).

* **Integration with strategy logic**: Make sure the placement of your MM code in the template aligns with the strategy’s order logic. In SQX’s standard export templates, typically the sequence is: check entry conditions -> if true and no conflicting trades -> **compute position size** -> send order. You want your code to run at the correct time. If you put code in the wrong section (say in `_exit.tpl` when it should be in `_entry.tpl`), it won’t have an effect. Usually, money management is purely an entry concern (deciding how many lots to trade). The `_exit.tpl` could be used if your MM snippet needs to do something on trade exit – for example, a **trailing equity stop** might adjust something when trades close, or a Martingale might reset after a win. If you don’t need any exit handling, you can leave `_exit.tpl` essentially empty (maybe just a comment or nothing at all). The exporter will include it but it won’t add any code (which is fine).

* **Multiple strategies and reuse**: If you plan to use the same custom MM snippet across many strategies, it’s great – that’s what snippets are for. But note that if you ever rename the snippet class or its parameters, you must update the templates accordingly. Similarly, if you share the snippet with someone else, they must place the templates in the correct folder structure for it to work on their system. The Code Editor’s import/export of snippets (`.sxp` files) should include the templates if done properly. Always test an imported snippet on a fresh SQX installation by generating code, to ensure no missing pieces.

* **SQX updates**: Occasionally, new SQX versions might change how templates work or add new macros. Keep an eye on release notes. The fundamentals (Freemarker, .tpl files) have remained consistent, but for example, if SQX introduces a new platform or changes the strategy template architecture, you might need to adjust your custom templates.

By following the above guidelines, you can create a robust **Agent\_mq5.md** style guide (as we have here) and the actual Freemarker templates to support exporting your custom money management logic to MQL5. With the templates in place, StrategyQuant X will seamlessly include your position sizing rules in the generated expert advisor, enabling your strategy to trade with the intended lot sizing on MetaTrader 5 just as it did in the SQX backtester. Good luck, and happy coding!

**Sources:**

* StrategyQuant X Extending Guide – Freemarker template system
* StrategyQuant Documentation – Money Management overview
* StrategyQuant Code Example – ATR volatility MM logic (Java)
* StrategyQuant Forum – Template inclusion error example
* StrategyQuant Documentation – Exporting strategy to MetaTrader (procedure)
