<#--
  SQX のテンプレート処理では `printMMVariableNumber` や `printMMVariableBool`
  マクロが定義されていない場合、null 参照エラーとなってしまう。
  ここでは簡易的なフォールバックマクロを用意し、値が未定義でも
  テンプレート展開が失敗しないようにする。
-->
<#macro printMMVariableNumber v>${v?default(0)}</#macro>
<#macro printMMVariableBool v>${v?default(false)}</#macro>

<#-- Inputs for DecompositionMonteCarlo Money Management -->
input string smm = "----------- Money Management - DecompositionMonteCarloMM -----------";
input bool   UseMoneyManagement = true;
input double mmBaseLot       = <@printMMVariableNumber BaseLot/>;
input double mmMaxDrawdown   = <@printMMVariableNumber MaxDrawdown/>;
input int    mmDecimals      = <@printMMVariableNumber Decimals/>;
input bool   mmDebugLogs     = <@printMMVariableBool DebugLogs/>;
input bool   mmAuditCSV      = <@printMMVariableBool AuditCSV/>;
input bool   mmEnforceMaxLot = <@printMMVariableBool EnforceMaxLot/>;
input double mmMaxLotCap     = <@printMMVariableNumber MaxLotCap/>;
input double mmStep          = ${orderSizeStep!0};
