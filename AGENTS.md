# AGENTS.md — StrategyQuant Money Management（Java）→ MT4 変換テンプレート・リファレンス

**対象**: `DecompositionMonteCarloMM.java`（単数列分解管理モンテカルロ法 / DMCMM）を、StrategyQuant X の **MT4 出力**に対応する **FreeMarker テンプレート（.tpl）**で移植する。

**テンプレートは必ず 3 分割**：
- `DecompositionMonteCarloMM_variables.tpl` … パラメータ（extern）＋内部状態（グローバル）宣言。
- `DecompositionMonteCarloMM_method.tpl` … **ロット算出本体**（都度呼ばれる計算メソッド）。
- `DecompositionMonteCarloMM_class.tpl` … 補助関数群（Win/Loss 処理、平均化、再配布、リセット等）。

> 以降のサンプルは **FreeMarker** コメント（`<#-- ... -->`）を交えた **MQL4** コード断片。必要に応じて `DecompositionMonteCarloMM` をあなたのスニペット名に変更してください。

---

## 0. 置き場所・命名規則
- MT4 用テンプレートは通常、`CodeTemplates/MT4/MoneyManagement/` 配下に置く。
- **ファイル名はクラス名に厳密一致**（拡張子とサフィックスを除く）。
  - `DecompositionMonteCarloMM_variables.tpl`
  - `DecompositionMonteCarloMM_method.tpl`
  - `DecompositionMonteCarloMM_class.tpl`
- StrategyQuant のエクスポート時に自動的にインクルードされる。欠落すると **template inclusion failed** エラーになる。

---

## 1) `DecompositionMonteCarloMM_variables.tpl`
**目的**: Java の `@Parameter` と **内部状態フィールド**を、MQL4 の `extern`／グローバルに対応付け。

```ftl
<#-- ========== DMCMM variables (globals & extern inputs) ========== -->
// ===== User parameters (Java @Parameter 対応) =====
extern double BaseLot     = 0.01;   // Base lot unit used to scale coefficients
extern double MaxDrawdown = 100.0;  // Cycle P/L < -MaxDrawdown でリセット（0 で無効）
extern int    Decimals    = 2;      // ロット小数桁（NormalizeDouble 用）

// ===== Internal persistent state =====
// 注意: すべてグローバル or static で、OnTick 間で永続化
int    DMCMM_sequenceLen = 0;   // 現在の系列長
long   DMCMM_sequence[];        // 系列配列（ArrayResize で可変）
double DMCMM_cycleProfit = 0.0; // サイクル累計（+勝ち/-負け）
double DMCMM_curBet      = 0.0; // 現在の賭け係数×BaseLot
int    DMCMM_consecWins  = 0;   // 連勝数（{0,1} パターン勝利のみ +1）
long   DMCMM_stock       = 0;   // 余剰勝利のプール（Java: stock）
int    DMCMM_histCount   = 0;   // 直近処理済みのヒストリ件数
bool   DMCMM_initialized = false;

// ===== Broker constraints (取得して都度利用) =====
double DMCMM_MinLot  = 0.0;   // MarketInfo(Symbol(), MODE_MINLOT)
double DMCMM_LotStep = 0.0;   // MarketInfo(Symbol(), MODE_LOTSTEP)
```

**ポイント**:
- Java で `long` を使っている箇所は MQL4 でも `long`（ビルド600+は 64bit）で安全側。
- `sequence` は **ArrayList**→**配列＋長さ** で管理（`ArrayResize`／シフト）。
- `MagicNumber` は SQ 生成側の共通変数を使用（本テンプレは参照のみ）。

---

## 2) `DecompositionMonteCarloMM_method.tpl`
**目的**: Java の `computeTradeSize(...)` 相当を MQL4 化。**毎回のロット決定**をここで行う。

> SQ 側の呼び出し位置にインライン展開されることを想定。メソッド名はプロジェクト規約に合わせてください。ここでは `double DMCMM_ComputeLot()` の体裁で示す。

```ftl
<#-- ========== DMCMM method (lot sizing entry point) ========== -->
// 呼び出し例: double lots = DMCMM_ComputeLot();

double DMCMM_ComputeLot() {
    // --- broker constraints ---
    DMCMM_MinLot  = MarketInfo(Symbol(), MODE_MINLOT);
    DMCMM_LotStep = MarketInfo(Symbol(), MODE_LOTSTEP);
    if(DMCMM_MinLot <= 0)  DMCMM_MinLot = 0.01;
    if(DMCMM_LotStep <= 0) DMCMM_LotStep = 0.01;

    // --- parameter guard (Java: throw) ---
    if(BaseLot <= 0.0) {
        Print("[DMCMM] BaseLot must be positive. Fallback to MinLot.");
        DMCMM_curBet = DMCMM_MinLot;
    }

    // --- first-time init ---
    if(!DMCMM_initialized) {
        DMCMM_ResetCycle();
        DMCMM_histCount   = OrdersHistoryTotal();
        DMCMM_initialized = true;
    }

    // --- process new closed orders since last call ---
    int histTotal = OrdersHistoryTotal();
    if(histTotal > DMCMM_histCount) {
        for(int i=DMCMM_histCount; i<histTotal; i++) {
            if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY)) continue;
            if(OrderSymbol() != Symbol())                 continue;
            // MagicNumber は SQ 生成の共通変数を想定
            if(OrderMagicNumber() != MagicNumber)         continue;

            double openP  = OrderOpenPrice();
            double closeP = OrderClosePrice();
            if(closeP == openP) continue; // 価格差 0 はスキップ（Java 同等）

            bool isWin;
            int  type = OrderType();
            if(type==OP_BUY||type==OP_BUYLIMIT||type==OP_BUYSTOP)  isWin = (closeP > openP);
            else                                                   isWin = (closeP < openP);

            double betForTrade = DMCMM_curBet; // 直前に使用した賭け額（= lots 相当）
            if(isWin) { DMCMM_cycleProfit += betForTrade; DMCMM_ProcessWin(); }
            else       { DMCMM_cycleProfit -= betForTrade; DMCMM_ProcessLoss(); }

            if(MaxDrawdown > 0.0 && DMCMM_cycleProfit < -MaxDrawdown) DMCMM_ResetCycle();
            else                                                      DMCMM_UpdateCurrentBet();
        }
        DMCMM_histCount = histTotal;
    }

    // --- output lot (round to step & decimals) ---
    double lots = DMCMM_curBet;
    lots = MathFloor(lots / DMCMM_LotStep) * DMCMM_LotStep; // step 下方丸め（要件に応じて近似丸めに変更可）
    lots = NormalizeDouble(lots, Decimals);
    if(lots < DMCMM_MinLot) lots = DMCMM_MinLot;
    return(lots);
}
```

**注意**:
- Java では `computeTradeSize(strategy, symbol, orderType, price, sl, tickSize, pointValue, sizeStep)` 引数で `sizeStep` が来るが、MT4 では **MarketInfo** から都度取得。
- 「勝ち判定」は **価格の差**で行い、手数料・スワップは無視（原典 Java に準拠）。
- `processedOrdersCount` はここでは **履歴総数**をキャッシュして追跡。

---

## 3) `DecompositionMonteCarloMM_class.tpl`
**目的**: Java の各メソッドを MQL4 の**補助関数**として実装。ローカル状態は `*_variables.tpl` のグローバルを参照。

```ftl
<#-- ========== DMCMM helpers (class-level functions) ========== -->

void DMCMM_ResetSequence() {
    ArrayResize(DMCMM_sequence, 2);
    DMCMM_sequence[0] = 0; // left
    DMCMM_sequence[1] = 1; // right
    DMCMM_sequenceLen = 2;
}

void DMCMM_ResetCycle() {
    DMCMM_ResetSequence();
    DMCMM_stock      = 0;
    DMCMM_consecWins = 0;
    DMCMM_cycleProfit= 0.0;
    DMCMM_UpdateCurrentBet();
}

void DMCMM_ProcessWin() {
    if(DMCMM_sequenceLen <= 0) { DMCMM_ResetSequence(); return; }
    long left  = DMCMM_sequence[0];
    long right = DMCMM_sequence[DMCMM_sequenceLen-1];

    // {0,1} パターン勝利のみ連勝をカウント
    if(DMCMM_sequenceLen==2 && left==0 && right==1) DMCMM_consecWins++;

    if(DMCMM_sequenceLen==2) {
        // 2 要素ならリセット
        DMCMM_ResetSequence();
    } else if(DMCMM_sequenceLen==3) {
        // [a,b,c] -> c を二分割
        long value = DMCMM_sequence[2];
        DMCMM_sequence[0] = value; // 圧縮
        DMCMM_sequenceLen = 1;
        long half = value / 2;
        long rem  = value % 2;
        ArrayResize(DMCMM_sequence, 2);
        DMCMM_sequence[0] = half;
        DMCMM_sequence[1] = half + rem;
        DMCMM_sequenceLen = 2;
    } else if(DMCMM_sequenceLen > 3) {
        // 先頭と末尾を除去
        // 先頭を落とす
        for(int j=0; j<DMCMM_sequenceLen-1; j++) DMCMM_sequence[j] = DMCMM_sequence[j+1];
        DMCMM_sequenceLen--;
        // 末尾を落とす（長さだけ減らす）
        DMCMM_sequenceLen--;
        ArrayResize(DMCMM_sequence, DMCMM_sequenceLen);
    }
    DMCMM_ApplyAveraging();
}

void DMCMM_ProcessLoss() {
    if(DMCMM_consecWins <= 5) {
        DMCMM_consecWins = 0;
    } else {
        long streakProfit = (DMCMM_consecWins - 3) * 5 - 8;
        long normalProfit = (DMCMM_consecWins - 2);
        DMCMM_stock += (streakProfit - normalProfit);
        DMCMM_consecWins = 0;
    }

    if(DMCMM_sequenceLen<=0) DMCMM_ResetSequence();

    long left  = DMCMM_sequence[0];
    long right = DMCMM_sequence[DMCMM_sequenceLen-1];
    long add   = left + right;
    ArrayResize(DMCMM_sequence, DMCMM_sequenceLen+1);
    DMCMM_sequence[DMCMM_sequenceLen] = add;
    DMCMM_sequenceLen++;

    DMCMM_ApplyAveraging();
    DMCMM_ConsumeStock();
    DMCMM_RedistributeZero();
}

void DMCMM_ApplyAveraging() {
    if(DMCMM_sequenceLen<=0) { DMCMM_ResetSequence(); return; }
    int  n = DMCMM_sequenceLen;
    long sum = 0; for(int i=0;i<n;i++) sum += DMCMM_sequence[i];
    long left = DMCMM_sequence[0];

    if(left==0) {
        if(n<=1) return;
        // 先頭 0 を一時除去 → 残り (n-1) 要素で平均
        for(int j=0;j<n-1;j++) DMCMM_sequence[j] = DMCMM_sequence[j+1];
        DMCMM_sequenceLen = n-1; n = DMCMM_sequenceLen;
        for(int j=0;j<n;j++) DMCMM_sequence[j] = 0;
        long avg = sum / n; // Java 実装と同じく整数商
        long rem = sum % n;
        for(int j=0;j<n;j++) DMCMM_sequence[j] += avg;
        if(n>0 && rem>0) DMCMM_sequence[0] += rem; // 余りは左から
        // 先頭 0 を復帰
        ArrayResize(DMCMM_sequence, n+1);
        for(int j=n;j>0;j--) DMCMM_sequence[j] = DMCMM_sequence[j-1];
        DMCMM_sequence[0] = 0; DMCMM_sequenceLen = n+1;
    } else {
        long avg = sum / n;
        long rem = sum % n;
        for(int j=0;j<n;j++) DMCMM_sequence[j] = 0;
        for(int j=0;j<n;j++) DMCMM_sequence[j] += avg;
        if(n>1 && rem>0) DMCMM_sequence[1] += rem; // 余りは 2 番目へ
    }
}

void DMCMM_ConsumeStock() {
    if(DMCMM_sequenceLen<=0) return;
    long first = DMCMM_sequence[0];
    if(first <= DMCMM_stock) {
        DMCMM_stock -= first;
        DMCMM_sequence[0] = 0;
    }
}

void DMCMM_RedistributeZero() {
    if(DMCMM_sequenceLen<=0) return;
    long first = DMCMM_sequence[0];
    if(first < 1) return; // 0 以下なら何もしない

    long redist = first;       // 再配布量
    DMCMM_sequence[0] = 0;     // 先頭を 0 に

    // 総和（0 にした後の合計 + 再配布量）
    long sum = 0; for(int i=0;i<DMCMM_sequenceLen;i++) sum += DMCMM_sequence[i];
    long total = sum + redist;
    int  slots = DMCMM_sequenceLen - 1; // 先頭を除くスロット
    if(slots<=0) return;

    if(redist < slots) {
        if(DMCMM_sequenceLen>1) DMCMM_sequence[1] += redist; // 少量なら第2要素に寄せる
        return;
    }

    long avg = total / slots;
    long rem = total % slots;

    // 先頭要素を物理的に削除 → 等分配 → 先頭 0 を戻す
    for(int j=0;j<DMCMM_sequenceLen-1;j++) DMCMM_sequence[j] = DMCMM_sequence[j+1];
    DMCMM_sequenceLen--; ArrayResize(DMCMM_sequence, DMCMM_sequenceLen);

    for(int j=0;j<DMCMM_sequenceLen;j++) DMCMM_sequence[j] = 0;
    for(int j=0;j<DMCMM_sequenceLen;j++) DMCMM_sequence[j] += avg;
    if(DMCMM_sequenceLen>0 && rem>0) DMCMM_sequence[0] += rem;

    ArrayResize(DMCMM_sequence, DMCMM_sequenceLen+1);
    for(int j=DMCMM_sequenceLen;j>0;j--) DMCMM_sequence[j] = DMCMM_sequence[j-1];
    DMCMM_sequence[0] = 0; DMCMM_sequenceLen++;
}

void DMCMM_UpdateCurrentBet() {
    double coeff = DMCMM_ComputeBetCoeff();
    DMCMM_curBet = BaseLot * coeff;
}

double DMCMM_ComputeBetCoeff() {
    if(DMCMM_sequenceLen<=0) return(0.0);
    long left  = DMCMM_sequence[0];
    long right = (DMCMM_sequenceLen>1 ? DMCMM_sequence[DMCMM_sequenceLen-1] : left);
    long base  = left + right;
    double mul = 1.0;
    if(DMCMM_consecWins==3)      mul = 2.0;
    else if(DMCMM_consecWins==4) mul = 3.0;
    else if(DMCMM_consecWins>=5) mul = 5.0;
    return( base * mul );
}
```

**実装ノート**:
- ここに示した関数は **グローバル状態**（`*_variables.tpl`）を直接操作。
- Java の `ensureInitialized()` は `DMCMM_ComputeLot()` 側で `DMCMM_initialized` を見て `DMCMM_ResetCycle()` を呼ぶ設計に置換。
- Java の `collectClosedOrders(...)` は MT4 では `OrdersHistoryTotal()`＋`OrderSelect(..., MODE_HISTORY)` で代替。

---

## 4) Java→MQL4 マッピング要点（FreeMarker 観点）
- **例外**: `throw new Exception(...)` → EA では `Print()` ログ＋フォールバック（トレード自体を止めたい場合は lots=0 を返す設計も可）。
- **List/Array**: `List<Long>` → `long[]`＋`int length` 管理。`remove(0)` はシフトで代替。
- **整数割り算**: Java の整数除算・剰余を **同じ意味**で実装（`/` と `%`）。
- **丸め**: Java `round(lot, sizeStep, Decimals)` → `MarketInfo(...,MODE_LOTSTEP)` と `NormalizeDouble` で再現。必要なら最近傍丸め（`MathFloor(x/step+0.5)`）に変更。
- **FreeMarker**: 本テンプレはほぼリテラル MQL4。必要なら `<#if>` で機能トグル、`${Symbol}` 等の変数出力も可能。SQ 固有マクロ（例: `<@printParam>`）はブロック系で主に使用されるため、本 MM では使用最小化が安定。

---

## 5) 連勝倍率・平均化・再配布の仕様（DMCMM）
- **連勝カウント**: 系列が `{0,1}` の勝利のみ `consecWins++`。
- **倍率**: `≤2: ×1`、`3: ×2`、`4: ×3`、`≥5: ×5` を **ComputeBetCoeff** で適用。
- **Loss 時**: `left+right` を末尾追加→**平均化**→`stock` 消費→**ゼロ再配布**。平均化では **先頭 0 を一旦除去**してから等分配→余りを先頭へ加算→先頭 0 を戻す（ダブルカウント防止）。

---

## 6) 組み込み手順チェックリスト
1. 3 つの .tpl を所定フォルダに配置（ファイル名・大文字小文字一致）。
2. StrategyQuant のスニペットとして DMCMM を選択して MT4 へエクスポート。
3. 生成された `.mq4` を MetaEditor で **ビルド**。未定義シンボルやセミコロン欠落がないか確認。
4. ストラテジーテスターで、勝ち負けの推移と `Lots` 出力が Java 実装と一致するか確認（短い検証データで逐次比較）。

---

## 7) 参考：注文発行側の呼び出し（例）
```mql4
// エントリ直前
double lots = DMCMM_ComputeLot();
// OrderSend(Symbol(), OP_BUY/OP_SELL, lots, ...);
```

---

## 8) よくある落とし穴
- **テンプレ名のタイポ** → inclusion 失敗。
- **配列サイズ管理** → `ArrayResize` 忘れでアクセス違反。
- **LotStep 未考慮** → ブローカーで拒否。
- **MagicNumber 未フィルタ** → 他戦略の履歴を誤カウント。

---

### 付記
- 本テンプレは **StrategyQuant Build 142** での MT4 出力を想定。ビルド差異でメソッド挿入位置が変わる場合は、`*_method.tpl` のメソッド名・戻り値の合流ポイントをプロジェクトの既存テンプレ仕様に合わせて調整してください。
- `DecompositionMonteCarloMM.java` 側のパラメータが増減した場合は、`*_variables.tpl` の extern と内部状態を同期更新すること。

