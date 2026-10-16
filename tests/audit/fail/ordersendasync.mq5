// expect: OrderSendAsync outside
int OnInit(){ MqlTradeRequest q; MqlTradeResult r; OrderSendAsync(q,r); return(INIT_SUCCEEDED);}
