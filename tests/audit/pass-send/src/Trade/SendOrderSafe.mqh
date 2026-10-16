// Fixture: the one file allowed to use OrderSend and CTrade.
#include <Trade\Trade.mqh>
CTrade g_trade;
bool SendIt(MqlTradeRequest &q, MqlTradeResult &r) { return(OrderSend(q, r)); }
