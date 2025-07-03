
input string smm = "----------- Money Management - Simple Martingale MM -----------";
input bool UseMoneyManagement = true;
input double mmLotsStart = <@printMMVariableNumber "#LotsStart#" />;
input double mmLotsMultiplier = <@printMMVariableNumber "#LotsMultiplier#" />;
input double mmLotsReset = <@printMMVariableNumber "#LotsReset#" />;
input int mmDecimals = <@printMMVariableNumber "#Decimals#" />;
input bool mmSeparateByDirection = <@printMMVariableNumber "#SeparateByDirection#" />;
input double mmLotsIfNoMM = 0.1;
input double mmMultiplier = ${orderSizeMultiplier};
input double mmStep = ${orderSizeStep};