input string smm = "----------- Money Management - Risk Fixed % Of Balance -----------";
input bool UseMoneyManagement = true;
input double mmRiskPercent = <@printMMVariableNumber "#Risk#" />;
input int mmDecimals = <@printMMVariableNumber "#Decimals#" />;
input double mmLotsIfNoMM = <@printMMVariableNumber "#LotsIfNoMM#" />;
input double mmMaxLots = <@printMMVariableNumber "#MaxLots#" />;
input double mmMultiplier = ${orderSizeMultiplier};
input double mmStep = ${orderSizeStep};
