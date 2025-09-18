<#-- ========== Decomposition Monte Carlo MM variables (globals & extern inputs) ========== -->
// ===== User parameters (Java @Parameter 対応) =====
extern double BaseLot     = 0.01;   // Base lot unit used to scale coefficients
extern double MaxDrawdown = 100.0;  // Cycle P/L < -MaxDrawdown でリセット（0 で無効）
extern int    Decimals    = 2;      // ロット小数桁（NormalizeDouble 用）

// ===== Internal persistent state =====
int    DMCMM_sequenceLen = 0;
long   DMCMM_sequence[];
double DMCMM_cycleProfit = 0.0;
double DMCMM_curBet      = 0.0;
int    DMCMM_consecWins  = 0;
long   DMCMM_stock       = 0;
int    DMCMM_histCount   = 0;
bool   DMCMM_initialized = false;

double DMCMM_MinLot  = 0.0;
double DMCMM_LotStep = 0.0;
