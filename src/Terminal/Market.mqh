// Required Notice: Copyright 2026 stop-loss-enjoyer
// Plainlines is source-available under the PolyForm Shield License 1.0.0.
//
// Terminal layer: everything the calculation core needs from the terminal, read into PlSymbol,
// PlAccount and PlInputs. Read only. The account number is never read.
#property strict

#ifndef PL_TERMINAL_MARKET_MQH
#define PL_TERMINAL_MARKET_MQH

//--- seconds since midnight of the server day
int PlSecOfDay(const datetime t)
  {
   MqlDateTime d; TimeToStruct(t,d);
   return d.hour*3600+d.min*60+d.sec;
  }

//--- inside a trade session now (server time, day of week of the server). Rules in PlSessionRowsOpen (Core/Num.mqh):
//--- 00:00-00:00 rows are empty slots (CORN.c, GER40). A day with no rows, or a symbol with no rows at all, is closed: no
//--- data says otherwise, so a doubt blocks instead of guessing; on the real symbol sets of both brokers it is never reached for a tradable symbol.
bool PlSessionOpen(const string sym,const datetime server_now)
  {
   MqlDateTime d; TimeToStruct(server_now,d);
   const int sod=PlSecOfDay(server_now);
   long fr[16], to[16];
   int n=0;
   for(int i=0;i<16;i++)
     {
      datetime from,tt;
      if(!SymbolInfoSessionTrade(sym,(ENUM_DAY_OF_WEEK)d.day_of_week,i,from,tt)) break;
      fr[n]=(long)from; to[n]=(long)tt; n++;
     }
   return (n>0 && PlSessionRowsOpen(fr,to,n,sod));
  }

//--- the symbol data the draft file key is made of is there (a terminal start before the symbol specs sync reads empty fields)
bool PlStateKeyReady(const PlSymbol &s)
  {
   return (s.base!="" && s.profit!="" && s.contract>0.0 && s.tick_size>0.0);
  }

//--- volume already open or pending on this symbol per direction (SYMBOL_VOLUME_LIMIT is per direction)
void PlVolumeOnSymbol(const string sym,double &vbuy,double &vsell)
  {
   vbuy=0.0; vsell=0.0;
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong tk=PositionGetTicket(i);
      if(tk==0) continue;
      if(PositionGetString(POSITION_SYMBOL)!=sym) continue;
      if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY) vbuy+=PositionGetDouble(POSITION_VOLUME);
      else vsell+=PositionGetDouble(POSITION_VOLUME);
     }
   for(int i=OrdersTotal()-1;i>=0;i--)
     {
      ulong tk=OrderGetTicket(i);
      if(tk==0) continue;
      if(OrderGetString(ORDER_SYMBOL)!=sym) continue;
      ENUM_ORDER_TYPE ot=(ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      bool buy=(ot==ORDER_TYPE_BUY || ot==ORDER_TYPE_BUY_LIMIT || ot==ORDER_TYPE_BUY_STOP || ot==ORDER_TYPE_BUY_STOP_LIMIT);
      if(buy) vbuy+=OrderGetDouble(ORDER_VOLUME_CURRENT);
      else vsell+=OrderGetDouble(ORDER_VOLUME_CURRENT);
     }
  }

//--- cheap refresh of the quote and the session only. cached: the timer's round, where the session is looked at once per server
//--- second (its borders lie on whole minutes); every other caller (a press, a send) reads it again.
void PlRefreshQuote(PlSymbol &s,const bool cached=false)
  {
   MqlTick tk;
   if(SymbolInfoTick(s.name,tk)) { s.bid=tk.bid; s.ask=tk.ask; s.tick_time=tk.time; }
   else { s.bid=0.0; s.ask=0.0; s.tick_time=0; }          // never keep the quote of a previous symbol
   s.server_now=TimeTradeServer();
   if(cached)
     {
      static string c_sym="";
      static datetime c_t=0;
      static bool c_open=false;
      if(s.name!=c_sym || s.server_now!=c_t) { c_open=PlSessionOpen(s.name,s.server_now); c_sym=PlOwnCopy(s.name); c_t=s.server_now; }
      s.session_open=c_open;
     }
   else s.session_open=PlSessionOpen(s.name,s.server_now);
   s.tick_value_loss=SymbolInfoDouble(s.name,SYMBOL_TRADE_TICK_VALUE_LOSS);     // k and path (a) stay as fresh as the quote
   s.tick_value_profit=SymbolInfoDouble(s.name,SYMBOL_TRADE_TICK_VALUE_PROFIT);
  }

//--- netting (anything but hedging): the one position of the symbol and the pending orders on it. On hedging all zero,
//--- unless force (the dev switch). A market order being executed is not a pending order (the rule of PlOwnRefresh).
void PlReadNetting(const string sym,PlSymbol &s,const bool force=false)
  {
   s.net_vol=0.0; s.net_buy=false; s.net_open=0.0; s.net_sl=0.0; s.net_orders=0;
   if(!force && AccountInfoInteger(ACCOUNT_MARGIN_MODE)==ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
      return;
   if(PositionSelect(sym))
     {
      s.net_vol=PositionGetDouble(POSITION_VOLUME);
      s.net_buy=((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY);
      s.net_open=PositionGetDouble(POSITION_PRICE_OPEN);
      s.net_sl=PositionGetDouble(POSITION_SL);
     }
   for(int i=OrdersTotal()-1;i>=0;i--)
     {
      const ulong tk=OrderGetTicket(i);
      if(tk==0) continue;
      if(OrderGetString(ORDER_SYMBOL)!=sym) continue;
      const ENUM_ORDER_TYPE ot=(ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      if(ot==ORDER_TYPE_BUY || ot==ORDER_TYPE_SELL || ot==ORDER_TYPE_CLOSE_BY) continue;
      s.net_orders++;
     }
  }

bool PlReadSymbol(const string sym,PlSymbol &s)
  {
   SymbolSelect(sym,true);
   s.name=PlOwnCopy(sym);
   s.base=SymbolInfoString(sym,SYMBOL_CURRENCY_BASE);
   s.profit=SymbolInfoString(sym,SYMBOL_CURRENCY_PROFIT);
   s.margin=SymbolInfoString(sym,SYMBOL_CURRENCY_MARGIN);
   s.calc_mode=(int)SymbolInfoInteger(sym,SYMBOL_TRADE_CALC_MODE);
   s.digits=(int)SymbolInfoInteger(sym,SYMBOL_DIGITS);
   s.point=SymbolInfoDouble(sym,SYMBOL_POINT);
   s.tick_size=SymbolInfoDouble(sym,SYMBOL_TRADE_TICK_SIZE);
   s.tick_value_loss=SymbolInfoDouble(sym,SYMBOL_TRADE_TICK_VALUE_LOSS);
   s.tick_value_profit=SymbolInfoDouble(sym,SYMBOL_TRADE_TICK_VALUE_PROFIT);
   s.contract=SymbolInfoDouble(sym,SYMBOL_TRADE_CONTRACT_SIZE);
   s.vol_min=SymbolInfoDouble(sym,SYMBOL_VOLUME_MIN);
   s.vol_max=SymbolInfoDouble(sym,SYMBOL_VOLUME_MAX);
   s.vol_step=SymbolInfoDouble(sym,SYMBOL_VOLUME_STEP);
   s.vol_limit=SymbolInfoDouble(sym,SYMBOL_VOLUME_LIMIT);
   PlVolumeOnSymbol(sym,s.vol_open_buy,s.vol_open_sell);
   s.stops_level=(int)SymbolInfoInteger(sym,SYMBOL_TRADE_STOPS_LEVEL);
   s.freeze_level=(int)SymbolInfoInteger(sym,SYMBOL_TRADE_FREEZE_LEVEL);
   s.order_mode=(int)SymbolInfoInteger(sym,SYMBOL_ORDER_MODE);
   s.filling_mode=(int)SymbolInfoInteger(sym,SYMBOL_FILLING_MODE);
   s.exec_mode=(int)SymbolInfoInteger(sym,SYMBOL_TRADE_EXEMODE);
   s.sym_trade_mode=(int)SymbolInfoInteger(sym,SYMBOL_TRADE_MODE);
   s.expiration_mode=(int)SymbolInfoInteger(sym,SYMBOL_EXPIRATION_MODE);
   s.gtc_mode=(int)SymbolInfoInteger(sym,SYMBOL_ORDER_GTC_MODE);
   s.swap_mode=(int)SymbolInfoInteger(sym,SYMBOL_SWAP_MODE);
   s.swap_long=SymbolInfoDouble(sym,SYMBOL_SWAP_LONG);
   s.swap_short=SymbolInfoDouble(sym,SYMBOL_SWAP_SHORT);
   s.swap_3day=(int)SymbolInfoInteger(sym,SYMBOL_SWAP_ROLLOVER3DAYS);
   PlRefreshQuote(s);
   //--- margin for one lot at the current price
   s.margin_buy_1lot=0.0; s.margin_sell_1lot=0.0;
   double m=0.0;
   if(s.ask>0.0 && OrderCalcMargin(ORDER_TYPE_BUY,sym,1.0,s.ask,m)) s.margin_buy_1lot=m;
   if(s.bid>0.0 && OrderCalcMargin(ORDER_TYPE_SELL,sym,1.0,s.bid,m)) s.margin_sell_1lot=m;
   PlReadNetting(sym,s);
   return (s.tick_size>0.0 && s.point>0.0);
  }

//--- open risk of positions and orders (Exposure.mqh): the sums, the count without SL
void PlExposureRisk(PlAccount &a);

//--- the account numbers; with_risk=false keeps the open risk worked out earlier
void PlReadAccount(PlAccount &a,const bool with_risk=true)
  {
   a.currency=AccountInfoString(ACCOUNT_CURRENCY);
   a.currency_digits=(int)AccountInfoInteger(ACCOUNT_CURRENCY_DIGITS);
   a.balance=AccountInfoDouble(ACCOUNT_BALANCE);
   a.equity=AccountInfoDouble(ACCOUNT_EQUITY);
   a.margin=AccountInfoDouble(ACCOUNT_MARGIN);
   a.margin_free=AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   a.so_mode=(int)AccountInfoInteger(ACCOUNT_MARGIN_SO_MODE);
   a.so_call=AccountInfoDouble(ACCOUNT_MARGIN_SO_CALL);
   a.so_so=AccountInfoDouble(ACCOUNT_MARGIN_SO_SO);
   a.leverage=AccountInfoInteger(ACCOUNT_LEVERAGE);
   a.trade_mode=(int)AccountInfoInteger(ACCOUNT_TRADE_MODE);
   a.margin_mode=(int)AccountInfoInteger(ACCOUNT_MARGIN_MODE);
   a.term_trade=(TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)!=0);
   a.mql_trade=(MQLInfoInteger(MQL_TRADE_ALLOWED)!=0);
   a.acct_trade=(AccountInfoInteger(ACCOUNT_TRADE_ALLOWED)!=0);
   a.acct_expert=(AccountInfoInteger(ACCOUNT_TRADE_EXPERT)!=0);
   a.trade_ok=(a.term_trade && a.mql_trade && a.acct_trade && a.acct_expert);
   a.connected=(TerminalInfoInteger(TERMINAL_CONNECTED)!=0);
   if(with_risk) PlExposureRisk(a);
  }

//--- shown only, never used for the lot: on a netting add the open volume valued from its open price to the new first TP, before
//--- the commission of its exit (the card subtracts that with the per-lot exit commission of the core). false: not known, the card
//--- then shows the reward of the added lot under its own label
bool   g_net_gain_ok=false;
double g_net_gain=0.0;

//--- OrderCalcProfit for 1 lot from the execution price to the SL (positive money) and OrderCalcMargin for 1 lot at the order price
void PlFillTerminalCalcs(PlSymbol &s,const PlPlan &p,PlInputs &in)
  {
   in.calcprofit_ok=false; in.calcprofit_loss_1lot=0.0;
   in.net_calc_ok=false; in.net_loss_new=0.0; in.net_loss_old=0.0;
   g_net_gain_ok=false; g_net_gain=0.0;
   if(!p.ok || p.side==PL_SIDE_NONE || p.exec<=0.0) return;
   const ENUM_ORDER_TYPE t=(p.side==PL_SIDE_BUY)?ORDER_TYPE_BUY:ORDER_TYPE_SELL;
   if(p.sl>0.0)
     {
      double pr=0.0;
      if(OrderCalcProfit(t,s.name,1.0,p.exec,p.sl,pr) && pr<0.0)
        {
         in.calcprofit_ok=true;
         in.calcprofit_loss_1lot=-pr;
        }
     }
   //--- netting add: the open volume valued from its open price to the new SL and to its own SL. Zero where a move exists is
   //--- missing data: then net_calc_ok stays false and the core refuses.
   if(p.sl>0.0 && s.net_vol>PL_EPS && s.net_open>0.0)
     {
      const ENUM_ORDER_TYPE nt=s.net_buy?ORDER_TYPE_BUY:ORDER_TYPE_SELL;
      double pn=0.0, po=0.0;
      bool ok=OrderCalcProfit(nt,s.name,s.net_vol,s.net_open,p.sl,pn);
      if(ok && pn==0.0 && MathAbs(s.net_open-p.sl)>=s.tick_size*0.5) ok=false;
      if(ok && s.net_sl>0.0)
        {
         ok=OrderCalcProfit(nt,s.name,s.net_vol,s.net_open,s.net_sl,po);
         if(ok && po==0.0 && MathAbs(s.net_open-s.net_sl)>=s.tick_size*0.5) ok=false;
        }
      if(ok)
        {
         in.net_calc_ok=true;
         in.net_loss_new=-pn;
         in.net_loss_old=(s.net_sl>0.0)?-po:0.0;
        }
     }
   if(p.tp[0]>0.0 && s.net_vol>PL_EPS && s.net_open>0.0)
     {
      const ENUM_ORDER_TYPE gt=s.net_buy?ORDER_TYPE_BUY:ORDER_TYPE_SELL;
      double g=0.0;
      bool ok=OrderCalcProfit(gt,s.name,s.net_vol,s.net_open,p.tp[0],g);
      if(ok && g==0.0 && MathAbs(s.net_open-p.tp[0])>=s.tick_size*0.5) ok=false;     // zero where a move exists: missing data
      if(ok) { g_net_gain_ok=true; g_net_gain=g; }
     }
   //--- margin at the order price; only the plan side is read by the core, both get the same value
   double m=0.0;
   if(OrderCalcMargin(t,s.name,1.0,p.exec,m) && m>0.0) { s.margin_buy_1lot=m; s.margin_sell_1lot=m; }
   else { s.margin_buy_1lot=0.0; s.margin_sell_1lot=0.0; }
  }

//--- prepare, terminal numbers at the plan price, core, final-volume margin
bool PlRunCore(PlInputs &in,PlSymbol &s,const PlAccount &a,PlPlan &plan,PlResult &r)
  {
   const bool okp=PlPrepare(in,s,plan);
   if(okp) PlFillTerminalCalcs(s,plan,in);
   PlCompute(in,s,a,plan,r);
   if(okp && plan.ok && r.lot>PL_EPS)
     {
      double m=0.0;
      const ENUM_ORDER_TYPE t=(plan.side==PL_SIDE_BUY)?ORDER_TYPE_BUY:ORDER_TYPE_SELL;
      const bool ok=OrderCalcMargin(t,s.name,r.lot,plan.exec,m);
      PlApplyFinalMargin(r,a,ok,m);
     }
   return okp;
  }

//--- sensible first SL distance in price: 1.5 times the mean H1 range of the last 24 hours
//--- spread_share is the max spread share of the SL distance (0.3): the first SL is not allowed to sit
//--- inside the spread warning, so it is at least spread / share with a 20% margin
void PlDefaultLines(const PlSymbol &s,const double spread_share,double &sl_dist)
  {
   if(s.tick_size<=0.0) { sl_dist=0.0; return; }     // the callers check the quote first; the divisions below must never see a zero tick
   const double spread=s.ask-s.bid;
   const double share=(spread_share>0.0)?spread_share:0.3;
   double mind=MathMax(((s.stops_level>0)?((double)s.stops_level+1.0)*s.point:0.0)+spread,MathMax(2.5*spread,MathMax(spread/share*1.2,3.0*s.tick_size)));
   double d=0.0;
   MqlRates r[];
   int n=CopyRates(s.name,PERIOD_H1,0,24,r);
   if(n>=6)
     {
      double sum=0.0;
      for(int i=0;i<n;i++) sum+=r[i].high-r[i].low;
      d=sum/n*1.5;
     }
   if(d<=0.0)
     {
      double px=(s.ask+s.bid)/2.0;
      d=px*0.002;
     }
   if(s.tick_size>0.0) d=MathCeil(d/s.tick_size)*s.tick_size;
   if(d<mind) d=MathCeil(mind/s.tick_size)*s.tick_size;
   sl_dist=NormalizeDouble(d,s.digits);
  }

//--- a string that must survive a change of the chart's symbol or timeframe: a real copy. The terminal rewrites the text of _Symbol in
//--- place, and a string taken from it (g_sym.name, snap.symbol) keeps pointing at the same storage, so a stored context would
//--- start naming the NEW symbol (found 13.10.2026: the check of a lost answer looked for the order on the wrong symbol and never ended).
string PlOwnCopy(const string s)
  {
   uchar b[];
   const int n=StringToCharArray(s,b,0,WHOLE_ARRAY,CP_UTF8);
   return (n>1)?CharArrayToString(b,0,n-1,CP_UTF8):"";
  }

//--- the broker's commission rule of a symbol (SymbolInfoCommissions) for a volume, through the pure PlBrokerCommRule.
//--- false: no rule, or a shape the core does not accept (the caller falls back to the deal sample); see Lot.mqh.
bool PlCommRule(const string sym,const double vol,PlCommKind &kind,double &rate,double &min_round,bool &known_zero)
  {
   kind=PL_COMM_UNKNOWN; rate=0.0; min_round=0.0; known_zero=false;
   MqlCommission c[];
   ResetLastError();
   const int n=SymbolInfoCommissions(sym,c);
   PlBrokerRule r[];
   if(n==1 && ArraySize(c)==1)
     {
      ArrayResize(r,1);
      r[0].currency=c[0].currency;
      r[0].mode_charge=(int)c[0].mode_charge;
      r[0].mode_direction=(int)c[0].mode_direction;
      r[0].mode_entry=(int)c[0].mode_entry;
      r[0].mode_profit=(int)c[0].mode_profit;
      r[0].mode_range=(int)c[0].mode_range;
      r[0].tier_count=ArraySize(c[0].tiers);
      r[0].range_from=0.0; r[0].range_to=0.0; r[0].min_value=0.0; r[0].max_value=0.0; r[0].value=0.0;
      r[0].tier_mode=-1; r[0].volume_type=-1; r[0].tier_currency="";
      if(r[0].tier_count>=1)
        {
         r[0].range_from=c[0].tiers[0].range_from; r[0].range_to=c[0].tiers[0].range_to;
         r[0].min_value=c[0].tiers[0].min_value; r[0].max_value=c[0].tiers[0].max_value;
         r[0].value=c[0].tiers[0].value;
         r[0].tier_mode=(int)c[0].tiers[0].mode;
         r[0].volume_type=(int)c[0].tiers[0].volume_type;
         r[0].tier_currency=c[0].tiers[0].currency;
        }
     }
   //--- the symbol's own data for a tier in another currency (the currency conversion of PlCcyRate): read only when the tier names one
   PlSymbol s;
   bool k_ok=false;
   double k=0.0;
   if(n==1 && ArraySize(r)==1 && r[0].tier_currency!="" && r[0].tier_currency!=AccountInfoString(ACCOUNT_CURRENCY))
     {
      s.base=SymbolInfoString(sym,SYMBOL_CURRENCY_BASE);
      s.profit=SymbolInfoString(sym,SYMBOL_CURRENCY_PROFIT);
      s.calc_mode=(int)SymbolInfoInteger(sym,SYMBOL_TRADE_CALC_MODE);
      s.tick_size=SymbolInfoDouble(sym,SYMBOL_TRADE_TICK_SIZE);
      s.tick_value_loss=SymbolInfoDouble(sym,SYMBOL_TRADE_TICK_VALUE_LOSS);
      s.contract=SymbolInfoDouble(sym,SYMBOL_TRADE_CONTRACT_SIZE);
      s.bid=SymbolInfoDouble(sym,SYMBOL_BID);
      s.ask=SymbolInfoDouble(sym,SYMBOL_ASK);
      k_ok=PlRateK(s,k);
     }
   return PlBrokerCommRule(n,r,AccountInfoString(ACCOUNT_CURRENCY),vol,s,k_ok,k,kind,rate,min_round,known_zero);
  }

//--- commission per lot from the deals of one position on the symbol: money is
//--- |DEAL_COMMISSION| + |DEAL_FEE|. The newest closed position (an OUT or OUT_BY deal) in the last 90 days with its
//--- IN deals in the same window gives in_lot and out_lot, closed=true (Bybit: out 0, the round turn at entry).
//--- Otherwise the newest IN deal gives in_lot, out_lot=0, closed=false; a zero in_lot there is no sample. false: no sample.
bool PlCommSample(const string sym,double &in_lot,double &out_lot,bool &closed)
  {
   in_lot=0.0; out_lot=0.0; closed=false;
   const datetime now=TimeCurrent();
   if(!HistorySelect(now-90*86400,now+86400)) return false;
   const int n=HistoryDealsTotal();
   ulong pid=0;
   bool found=false;
   for(int i=n-1;i>=0;i--)
     {
      const ulong tk=HistoryDealGetTicket(i);
      if(tk==0) continue;
      if(HistoryDealGetString(tk,DEAL_SYMBOL)!=sym) continue;
      const ENUM_DEAL_TYPE dt=(ENUM_DEAL_TYPE)HistoryDealGetInteger(tk,DEAL_TYPE);
      if(dt!=DEAL_TYPE_BUY && dt!=DEAL_TYPE_SELL) continue;
      const ENUM_DEAL_ENTRY en=(ENUM_DEAL_ENTRY)HistoryDealGetInteger(tk,DEAL_ENTRY);
      if(en!=DEAL_ENTRY_OUT && en!=DEAL_ENTRY_OUT_BY) continue;
      pid=(ulong)HistoryDealGetInteger(tk,DEAL_POSITION_ID);
      found=true;
      break;
     }
   if(found)
     {
      double cin=0.0,cout=0.0,vin=0.0,vout=0.0;
      for(int i=0;i<n;i++)
        {
         const ulong tk=HistoryDealGetTicket(i);
         if(tk==0) continue;
         if((ulong)HistoryDealGetInteger(tk,DEAL_POSITION_ID)!=pid) continue;
         const ENUM_DEAL_TYPE dt=(ENUM_DEAL_TYPE)HistoryDealGetInteger(tk,DEAL_TYPE);
         if(dt!=DEAL_TYPE_BUY && dt!=DEAL_TYPE_SELL) continue;
         const ENUM_DEAL_ENTRY en=(ENUM_DEAL_ENTRY)HistoryDealGetInteger(tk,DEAL_ENTRY);
         const double money=MathAbs(HistoryDealGetDouble(tk,DEAL_COMMISSION))+MathAbs(HistoryDealGetDouble(tk,DEAL_FEE));
         const double vol=HistoryDealGetDouble(tk,DEAL_VOLUME);
         if(en==DEAL_ENTRY_IN) { cin+=money; vin+=vol; }
         else if(en==DEAL_ENTRY_OUT || en==DEAL_ENTRY_OUT_BY) { cout+=money; vout+=vol; }
        }
      if(vin>0.0 && vout>0.0)
        {
         in_lot=cin/vin; out_lot=cout/vout; closed=true;
         return true;
        }
     }
   for(int i=n-1;i>=0;i--)
     {
      const ulong tk=HistoryDealGetTicket(i);
      if(tk==0) continue;
      if(HistoryDealGetString(tk,DEAL_SYMBOL)!=sym) continue;
      const ENUM_DEAL_TYPE dt=(ENUM_DEAL_TYPE)HistoryDealGetInteger(tk,DEAL_TYPE);
      if(dt!=DEAL_TYPE_BUY && dt!=DEAL_TYPE_SELL) continue;
      if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(tk,DEAL_ENTRY)!=DEAL_ENTRY_IN) continue;
      const double vol=HistoryDealGetDouble(tk,DEAL_VOLUME);
      if(vol<=0.0) continue;
      in_lot=(MathAbs(HistoryDealGetDouble(tk,DEAL_COMMISSION))+MathAbs(HistoryDealGetDouble(tk,DEAL_FEE)))/vol;
      //--- an entry with no commission and no closed position proves nothing (the charge may come at the exit): no sample, never a guessed 0
      if(in_lot<=0.0) { in_lot=0.0; return false; }
      return true;
     }
   return false;
  }

//--- symbol name without the broker suffix: the leading letters and digits ("US500.cash" -> "US500")
string PlNameStem(const string name)
  {
   int n=StringLen(name), i=0;
   for(;i<n;i++)
     {
      ushort c=StringGetCharacter(name,i);
      bool alnum=(c>='0' && c<='9') || (c>='A' && c<='Z') || (c>='a' && c<='z');
      if(!alnum) break;
     }
   return StringSubstr(name,0,i);
  }

//--- key of the per-symbol state file: base_profit_calcmode_contract_digits_tick, and the name without its
//--- suffix when base and profit currency are the same (CFD on USD: BTCUSD and US500.cash must not share a file)
string PlStateKey(const PlSymbol &s)
  {
   string k=s.base+"_"+s.profit+"_"+IntegerToString(s.calc_mode)+"_"+DoubleToString(s.contract,2)
            +"_"+IntegerToString(s.digits)+"_"+DoubleToString(s.tick_size,8);
   if(s.base==s.profit) k+="_"+PlNameStem(s.name);
   StringReplace(k,"/","-");
   StringReplace(k,"\\","-");
   StringReplace(k," ","");
   return k;
  }

//--- the unit of SL and TP distances: pips for Forex, points otherwise
bool PlIsForex(const PlSymbol &s)
  {
   return PlIsForexMode((ENUM_SYMBOL_CALC_MODE)s.calc_mode);
  }

double PlPipSize(const PlSymbol &s)
  {
   return PlPipFrom(s.point,s.digits,(ENUM_SYMBOL_CALC_MODE)s.calc_mode);
  }

#endif
