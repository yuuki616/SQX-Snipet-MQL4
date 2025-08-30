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
input double mmBaseLot       = <@printMMVariableNumber BaseLot!0/>;
input double mmMaxDrawdown   = <@printMMVariableNumber MaxDrawdown!0/>;
input int    mmDecimals      = <@printMMVariableNumber Decimals!0/>;
input bool   mmDebugLogs     = <@printMMVariableBool DebugLogs!false/>;
input bool   mmAuditCSV      = <@printMMVariableBool AuditCSV!false/>;
input bool   mmEnforceMaxLot = <@printMMVariableBool EnforceMaxLot!false/>;
input double mmMaxLotCap     = <@printMMVariableNumber MaxLotCap!0/>;
input double mmStep          = ${orderSizeStep!0};
