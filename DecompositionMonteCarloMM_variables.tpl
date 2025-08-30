<#-- Inputs for DecompositionMonteCarlo Money Management -->
input string smm = "----------- Money Management - DecompositionMonteCarloMM -----------";
input bool   UseMoneyManagement = true;
input double mmBaseLot       = <@printMMVariableNumber "#BaseLot#" />;
input double mmMaxDrawdown   = <@printMMVariableNumber "#MaxDrawdown#" />;
input int    mmDecimals      = <@printMMVariableNumber "#Decimals#" />;
input bool   mmDebugLogs     = <@printMMVariableBool "#DebugLogs#" />;
input bool   mmAuditCSV      = <@printMMVariableBool "#AuditCSV#" />;
input bool   mmEnforceMaxLot = <@printMMVariableBool "#EnforceMaxLot#" />;
input double mmMaxLotCap     = <@printMMVariableNumber "#MaxLotCap#" />;
input double mmStep          = ${orderSizeStep};
