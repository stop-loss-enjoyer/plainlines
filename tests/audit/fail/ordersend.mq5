// expect: OrderSend outside
int OnInit(){ MqlTradeRequest q; MqlTradeResult r; OrderSend(q,r); return(INIT_SUCCEEDED);}
