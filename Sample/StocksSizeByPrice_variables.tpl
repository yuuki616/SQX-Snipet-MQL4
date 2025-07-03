
input string smm = "----------- Money Management - Stocks Size by price -----------";
input bool UseMoneyManagement = true;
input bool mmUseAccountBalance = <@printMMVariableNumber "#UseAccountBalance#" />;
input double mmMaxSize = <@printMMVariableNumber "#MaxSize#" />;
input double mmLotsIfNoMM = 1;
input double mmMultiplier = ${orderSizeMultiplier};
input double mmStep = ${orderSizeStep};