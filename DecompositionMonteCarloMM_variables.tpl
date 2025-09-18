<#-- ========== DMCMM variables (globals & extern inputs) ========== -->
// ===== User parameters (Java @Parameter 対応) =====
extern double BaseLot     = 0.01;   // Base lot unit used to scale coefficients
extern double MaxDrawdown = 100.0;  // Reset sequence when cycle P/L < -MaxDrawdown (0 disables)
extern int    Decimals    = 2;      // Lot precision for NormalizeDouble

// ===== Internal persistent state =====
int    DMCMM_sequenceLen          = 0;   // Current length of the decomposition sequence
long   DMCMM_sequence[];                // Sequence storage (dynamic array)
long   DMCMM_stock                = 0;   // Surplus wins pool
int    DMCMM_consecWins           = 0;   // Consecutive win counter
double DMCMM_cycleProfit          = 0.0; // Accumulated profit within the current cycle
double DMCMM_curBet               = 0.0; // Current bet amount (lots)
double DMCMM_lastExecutedBet      = 0.0; // Last theoretical bet used for closed order evaluation
double DMCMM_stepRatio            = 1.0; // Scaling ratio between Java step and broker lot step
int    DMCMM_processedOrdersCount = 0;   // Processed history orders counter
datetime DMCMM_lastCloseTime      = 0;   // Last processed order close time
int      DMCMM_lastCloseTicket    = -1;  // Last processed order ticket (for tie-break)
bool   DMCMM_initialized          = false;

// ===== Broker constraints =====
double DMCMM_MinLot  = 0.0;
double DMCMM_LotStep = 0.0;
