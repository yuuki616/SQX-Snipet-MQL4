input string smm = "----------- Money Management - Fixed Amount -----------";
input bool UseMoneyManagement = true;
input double mmRiskedMoney = <@printMMVariableNumber "#RiskedMoney#" />;
input int mmDecimals = <@printMMVariableNumber "#Decimals#" />;
input double mmLotsIfNoMM = <@printMMVariableNumber "#LotsIfNoMM#" />;
input double mmMaxLots = <@printMMVariableNumber "#MaxLots#" />;
input double mmMultiplier = ${orderSizeMultiplier};
input double mmStep = ${orderSizeStep};
