// Required Notice: Copyright 2026 stop-loss-enjoyer
// Plainlines is source-available under the PolyForm Shield License 1.0.0.
//
// What stands open on the account, for the guards:
// one pass over positions and pending orders (PlExpo with the money if closed at the SL, the open
// risk sums, the count without SL), and the deal history of the account (the entry times, in server time).
// Read only. The account number is never read here.
#property strict

#ifndef PL_TERMINAL_EXPOSURE_MQH
#define PL_TERMINAL_EXPOSURE_MQH

PlExpo     g_ex[];                  // one entry per position and pending order of the account (any magic)
int        g_ex_open_count=0;       // positions + pending orders
int        g_ex_no_sl=0;
double     g_ex_open_risk=0.0;      // sum of losses at the SL, positions
double     g_ex_pend_risk=0.0;      // the same, pending orders
int        g_ex_unknown=0;          // entries with an SL whose money at the SL cannot be valued (unknown, never zero)
string     g_ex_unknown_sym="";     // the first such symbol, for the phrase
int        g_ex_comm_zero=0;        // pending orders counted with no commission at all (no sample, no user setting)
string     g_ex_comm_zero_sym="";   // the first such symbol, for the note "Commission not counted"
//--- the user's commission setting of a symbol as money for the round trip of a volume from ex to sl (State.mqh); false: none set
bool PlUserCommMoney(const string sym,const ENUM_ORDER_TYPE ot,const double vol,const double ex,const double sl,double &money);
bool PlUserComm(const string sym,PlCommKind &kind,double &rate);
bool PlCommMoneyOf(const PlCommKind kind,const double rate,const string sym,const ENUM_ORDER_TYPE ot,const double vol,const double ex,const double sl,double &money,const double min_round=0.0);
#ifdef PL_DEV_LOG
double     g_dev_rulemin=0.0;       // development: > 0 makes the broker's rule on every symbol a round rate g_dev_rulerate with this minimum per order
double     g_dev_rulerate=0.0;
bool       g_dev_rulezero=false;    // development: the broker's rule on every symbol is the known zero (US500.cash)
bool       g_dev_norule=false;      // development: the broker's commission rule is "unknown" on every symbol
string     g_dev_calcfail="";       // development: OrderCalcProfit "fails" for this symbol
bool       g_dev_nodeal=false;      // development: the entry deal of a position is not in the history
bool       g_dev_histbad=false;     // development: the history sum is off by 1.0
bool       g_dev_fromstart_off=false; // development: the history is read as not reaching the start
long       g_dev_fpshift=0;         // development: seconds added to the time of the first deposit, so the same account reads as another one
#endif

datetime   g_entry_t[];             // times of the entry deals (trades opened), for "trades today": server time
bool       g_hist_from_start=false; // the history begins with a balance deal
bool       g_hist_dirty=true;       // a deal arrived: read again
ulong      g_hist_event=0;          // when the last deal arrived (the history is read once more a few seconds later)
double     g_hist_sum=0.0;          // sum of profit+commission+swap+fee over every deal but credit, of the last read
bool       g_hist_conn=false;       // the terminal was connected when the last read ended
bool       g_hist_read=false;       // the last HistorySelect worked
ulong      g_hist_last=0;
double     g_hist_diff=0.0;         // the sum of the last read minus the balance then: the number the wait for the history can name
ulong      g_hist_gap=2000;         // ms between two reads of a history that does not add up (2 s, doubled to 60 s); OnTimer owns it
bool       g_fp_found=false;        // first balance deal of the whole history (the account fingerprint)
datetime   g_fp_t=0;
double     g_fp_amount=0.0;

//--- commission paid at the entry of a position, per lot (cache by position id) ---------------------
ulong      g_cm_id[];
double     g_cm_val[];
ulong      g_cm_t[];

//--- known=false: the entry deals of the position cannot be read (HistorySelectByPosition failed, no entry deal or no volume);
//--- the value is then 0.0 and the caller must not treat it as a real zero. Only a known value is cached (0 for 60 s).
double PlPosCommPerLot(const ulong id,bool &known)
  {
   const ulong now=GetTickCount64();
#ifdef PL_DEV_LOG
   if(g_dev_nodeal) { known=false; return 0.0; }
#endif
   const int n=ArraySize(g_cm_id);
   for(int i=0;i<n;i++)
      if(g_cm_id[i]==id)
        {
         if(g_cm_val[i]>0.0 || (g_cm_val[i]==0.0 && now-g_cm_t[i]<60000)) { known=true; return g_cm_val[i]; }
         break;
        }
   known=false;
   double com=0.0, vol=0.0;
   if(HistorySelectByPosition(id))
     {
      for(int k=HistoryDealsTotal()-1;k>=0;k--)
        {
         ulong tk=HistoryDealGetTicket(k);
         if(tk==0) continue;
         const ENUM_DEAL_ENTRY en=(ENUM_DEAL_ENTRY)HistoryDealGetInteger(tk,DEAL_ENTRY);
         if(en!=DEAL_ENTRY_IN && en!=DEAL_ENTRY_INOUT) continue;
         com+=MathAbs(HistoryDealGetDouble(tk,DEAL_COMMISSION))+MathAbs(HistoryDealGetDouble(tk,DEAL_FEE));
         vol+=HistoryDealGetDouble(tk,DEAL_VOLUME);
        }
     }
   if(vol<=0.0)
     {
      for(int i=0;i<n;i++)
         if(g_cm_id[i]==id) { g_cm_val[i]=-1.0; g_cm_t[i]=now; }
      return 0.0;                       // unknown: not cached as a zero, read again at the next pass
     }
   known=true;
   const double per=com/vol;
   for(int i=0;i<n;i++)
      if(g_cm_id[i]==id) { g_cm_val[i]=per; g_cm_t[i]=now; return per; }
   ArrayResize(g_cm_id,n+1); ArrayResize(g_cm_val,n+1); ArrayResize(g_cm_t,n+1);
   g_cm_id[n]=id; g_cm_val[n]=per; g_cm_t[n]=now;
   return per;
  }

//--- a deal arrived (DEAL_ADD): what was read before may have lacked it
void PlCommCacheReset()
  {
   ArrayResize(g_cm_id,0); ArrayResize(g_cm_val,0); ArrayResize(g_cm_t,0);
  }

//--- the commission sample of a symbol (PlCommSample), kept for ten minutes
string g_ch_sym[];
bool   g_ch_ok[];
double g_ch_in[];
double g_ch_out[];
bool   g_ch_closed[];
ulong  g_ch_t[];

bool PlCommSampleCached(const string sym,double &in_lot,double &out_lot,bool &closed)
  {
   const ulong now=GetTickCount64();
   const int n=ArraySize(g_ch_sym);
   for(int i=0;i<n;i++)
      if(g_ch_sym[i]==sym)
        {
         if(now-g_ch_t[i]>=(g_ch_ok[i]?(ulong)600000:(ulong)10000))   // no sample yet: look again soon
           {
            g_ch_ok[i]=PlCommSample(sym,g_ch_in[i],g_ch_out[i],g_ch_closed[i]);
            g_ch_t[i]=now;
           }
         in_lot=g_ch_in[i]; out_lot=g_ch_out[i]; closed=g_ch_closed[i];
         return g_ch_ok[i];
        }
   ArrayResize(g_ch_sym,n+1); ArrayResize(g_ch_ok,n+1); ArrayResize(g_ch_in,n+1);
   ArrayResize(g_ch_out,n+1); ArrayResize(g_ch_closed,n+1); ArrayResize(g_ch_t,n+1);
   g_ch_sym[n]=PlOwnCopy(sym);
   g_ch_ok[n]=PlCommSample(sym,g_ch_in[n],g_ch_out[n],g_ch_closed[n]);
   g_ch_t[n]=now;
   in_lot=g_ch_in[n]; out_lot=g_ch_out[n]; closed=g_ch_closed[n];
   return g_ch_ok[n];
  }

//--- the broker's commission rule of a symbol, read on every call: SymbolInfoCommissions answers from the terminal's own
//--- data in a few microseconds (measured 3 to 4 us on the demo), so nothing is kept between calls.
//--- The volume is the symbol minimum: the rule is one plain tier, and the order lot is not known before the calculation.
bool PlCommRuleOf(const string sym,PlCommKind &kind,double &rate,double &min_round,bool &known_zero)
  {
#ifdef PL_DEV_LOG
   if(g_dev_norule) { kind=PL_COMM_UNKNOWN; rate=0.0; min_round=0.0; known_zero=false; return false; }
   if(g_dev_rulezero) { kind=PL_COMM_LOT_SIDE; rate=0.0; min_round=0.0; known_zero=true; return true; }
   if(g_dev_rulemin>0.0) { kind=PL_COMM_LOT_ROUND; rate=g_dev_rulerate; min_round=g_dev_rulemin; known_zero=false; return true; }
#endif
   return PlCommRule(sym,SymbolInfoDouble(sym,SYMBOL_VOLUME_MIN),kind,rate,min_round,known_zero);
  }

void PlCommCacheClear()
  {
   ArrayResize(g_ch_sym,0); ArrayResize(g_ch_ok,0); ArrayResize(g_ch_in,0);
   ArrayResize(g_ch_out,0); ArrayResize(g_ch_closed,0); ArrayResize(g_ch_t,0);
  }

//--- commission still to pay at the exit of an open position, per lot. Sources in order: the broker's rule (it is per account,
//--- a typed rate is not), the user's setting, what the symbol's last closed position paid at its exit (Bybit 0); none: the entry rate again (per side, safe).
//--- A per-lot side rate is the exit rate; a round rate is split in half (overestimates the exit of a broker that charges
//--- at the entry only, the safe side); a percent rate has no price here, so the entry commission of this position stands in.
double PlExitCommPerLot(const string sym,const double in_paid_lot)
  {
   PlCommKind k=PL_COMM_UNKNOWN; double rt=0.0, mn=0.0; bool kz=false;
   if(PlCommRuleOf(sym,k,rt,mn,kz) || PlUserComm(sym,k,rt))
     {
      if(k==PL_COMM_LOT_SIDE) return rt;
      if(k==PL_COMM_LOT_ROUND) return rt/2.0;
      return in_paid_lot;
     }
   double i=0.0,o=0.0;
   bool cl=false;
   if(PlCommSampleCached(sym,i,o,cl) && cl) return o;
   return in_paid_lot;
  }

#ifdef PL_DEV_LOG
//--- which source PlExitCommPerLot took, for the BEDBG line only (the second look gives the same answer)
string PlExitCommSrcDev(const string sym)
  {
   PlCommKind k=PL_COMM_UNKNOWN; double rt=0.0, mn=0.0; bool kz=false;
   string src="";
   if(PlCommRuleOf(sym,k,rt,mn,kz)) src="broker_rule";
   else if(PlUserComm(sym,k,rt)) src="user";
   if(src!="")
     {
      if(k==PL_COMM_LOT_SIDE) return src+" lot_side";
      if(k==PL_COMM_LOT_ROUND) return src+" lot_round/2";
      return src+" in_paid_lot";
     }
   double i=0.0,o=0.0;
   bool cl=false;
   if(PlCommSampleCached(sym,i,o,cl) && cl) return "deal_sample";
   return "in_paid_lot";
  }
#endif

//--- money if a position closes at its SL: the price move from OrderCalcProfit only (the broker's own conversion).
//--- No tick-value guess: false means the money cannot be valued (also p==0 with from!=to), which is unknown, never zero.
bool PlProfitAtPrice(const ENUM_ORDER_TYPE ot,const string sym,const double vol,const double from,const double to,double &p)
  {
#ifdef PL_DEV_LOG
   if(sym==g_dev_calcfail) { p=0.0; return false; }
#endif
   if(OrderCalcProfit(ot,sym,vol,from,to,p) && (p!=0.0 || from==to)) return true;
   p=0.0;
   return false;
  }

//--- one pass over positions and pending orders
void PlReadPositions()
  {
   ArrayResize(g_ex,0);
   g_ex_open_count=0; g_ex_no_sl=0; g_ex_open_risk=0.0; g_ex_pend_risk=0.0;
   g_ex_unknown=0; g_ex_unknown_sym="";
   g_ex_comm_zero=0; g_ex_comm_zero_sym="";
   const int np=PositionsTotal();
   for(int i=0;i<np;i++)
     {
      ulong tk=PositionGetTicket(i);
      if(tk==0) continue;
      PlExpo e; e.pending=false; e.has_sl=false; e.pl_at_sl=0.0; e.unknown=false;
      const double sl=PositionGetDouble(POSITION_SL);
      g_ex_open_count++;
      if(sl>0.0)
        {
         const string sy=PositionGetString(POSITION_SYMBOL);
         const ENUM_POSITION_TYPE pt=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         const double vol=PositionGetDouble(POSITION_VOLUME);
         const ulong id=(ulong)PositionGetInteger(POSITION_IDENTIFIER);
         const double swp=PositionGetDouble(POSITION_SWAP);
         double p=0.0;
         e.has_sl=true;
         if(!PlProfitAtPrice(pt==POSITION_TYPE_BUY?ORDER_TYPE_BUY:ORDER_TYPE_SELL,sy,vol,PositionGetDouble(POSITION_PRICE_OPEN),sl,p))
           {
            e.unknown=true; e.pl_at_sl=0.0; g_ex_unknown++;
            if(g_ex_unknown_sym=="") g_ex_unknown_sym=sy;
           }
         else
           {
            bool ck=false;
            const double cin=PlPosCommPerLot(id,ck);
            if(!ck)      // the entry commission cannot be read: the loss at the SL is unknown, never a zero commission
              {
               e.unknown=true; e.pl_at_sl=0.0; g_ex_unknown++;
               if(g_ex_unknown_sym=="") g_ex_unknown_sym=sy;
              }
            else
              {
               e.pl_at_sl=p+swp-PlExitCommPerLot(sy,cin)*vol;
               if(e.pl_at_sl<0.0) g_ex_open_risk-=e.pl_at_sl;
              }
           }
        }
      else g_ex_no_sl++;
      const int k=ArraySize(g_ex);
      ArrayResize(g_ex,k+1); g_ex[k]=e;
     }
   const int no=OrdersTotal();
   for(int i=0;i<no;i++)
     {
      ulong tk=OrderGetTicket(i);
      if(tk==0) continue;
      PlExpo e; e.pending=true; e.has_sl=false; e.pl_at_sl=0.0; e.unknown=false;
      const double sl=OrderGetDouble(ORDER_SL);
      g_ex_open_count++;
      if(sl>0.0)
        {
         const ENUM_ORDER_TYPE ot=(ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
         const bool buy=(ot==ORDER_TYPE_BUY_LIMIT || ot==ORDER_TYPE_BUY_STOP || ot==ORDER_TYPE_BUY_STOP_LIMIT);
         const bool sl_ord=(ot==ORDER_TYPE_BUY_STOP_LIMIT || ot==ORDER_TYPE_SELL_STOP_LIMIT);
         const string sy=OrderGetString(ORDER_SYMBOL);
         const double vol=OrderGetDouble(ORDER_VOLUME_CURRENT);
         const double ex=sl_ord?OrderGetDouble(ORDER_PRICE_STOPLIMIT):OrderGetDouble(ORDER_PRICE_OPEN);
         double p=0.0;
         e.has_sl=true;
         if(!PlProfitAtPrice(buy?ORDER_TYPE_BUY:ORDER_TYPE_SELL,sy,vol,ex,sl,p))
           {
            e.unknown=true; e.pl_at_sl=0.0; g_ex_unknown++;
            if(g_ex_unknown_sym=="") g_ex_unknown_sym=sy;
           }
         else
           {
            //--- the commission as the panel has it for a new trade on this symbol: the broker's rule, else the user's setting,
            //--- else the last deals' sample, else none counted (zero, with the note "Commission not counted"). Never a block:
            //--- the loss at the SL is known. A rule or setting that cannot be valued (a percent without OrderCalcProfit) falls on.
            double hi=0.0,ho=0.0,cm=0.0,brt=0.0,bmn=0.0;
            bool hc=false,bz=false;
            PlCommKind bk=PL_COMM_UNKNOWN;
            const ENUM_ORDER_TYPE pot=buy?ORDER_TYPE_BUY:ORDER_TYPE_SELL;
            if(PlCommRuleOf(sy,bk,brt,bmn,bz) && PlCommMoneyOf(bk,brt,sy,pot,vol,ex,sl,cm,bmn))
               e.pl_at_sl=p-cm;
            else if(PlUserCommMoney(sy,pot,vol,ex,sl,cm))
               e.pl_at_sl=p-cm;
            else if(PlCommSampleCached(sy,hi,ho,hc))
              {
               const double cpl=hc?(hi+ho):2.0*hi;
               e.pl_at_sl=p-cpl*vol;
              }
            else
              {
               e.pl_at_sl=p;
               g_ex_comm_zero++;
               if(g_ex_comm_zero_sym=="") g_ex_comm_zero_sym=sy;
              }
            if(e.pl_at_sl<0.0) g_ex_pend_risk-=e.pl_at_sl;
           }
        }
      else g_ex_no_sl++;
      const int k=ArraySize(g_ex);
      ArrayResize(g_ex,k+1); g_ex[k]=e;
     }
  }

//--- the open risk sums for the panel's "subtract open risk" (replaces the old PlReadOpenRisk)
void PlExposureRisk(PlAccount &a)
  {
   PlReadPositions();
   a.open_risk_money=g_ex_open_risk;
   a.pending_risk_money=g_ex_pend_risk;
   a.open_no_sl=g_ex_no_sl;
  }

//--- the history counts as loaded only when it adds up to the balance: read while connected and
//--- the sum of profit+commission+swap+fee over every deal but credit equal to ACCOUNT_BALANCE within one unit of the
//--- account currency digits. Credit moves ACCOUNT_CREDIT, not the balance. A history that never adds up keeps the
//--- Max total risk and Max trades a day on refusal, with the reason on screen.
double PlHistTol(const int cd) { return MathPow(10.0,-MathMax(0,MathMin(8,cd)))+1e-9; }

bool PlHistAddsUp(const PlAccount &a)
  {
   return g_hist_read && g_hist_conn && a.connected && MathAbs(g_hist_sum-a.balance)<=PlHistTol(a.currency_digits);
  }

//--- the deal history of the whole account. true when it is read and adds up to the balance
bool PlReadHistory(const PlAccount &a)
  {
   g_hist_last=GetTickCount64();
   g_hist_read=false; g_hist_sum=0.0;
   if(!HistorySelect(0,TimeTradeServer()+86400)) { g_hist_dirty=true; return false; }
   const int n=HistoryDealsTotal();
   //--- sized once for every deal and cut to what was kept after the loop: one growing resize per deal costs a reallocation each
   ArrayResize(g_entry_t,n);
   int m=0, me=0;
   g_fp_found=false; g_fp_t=0; g_fp_amount=0.0;
   g_hist_from_start=false;
   datetime earliest_t=0; ulong earliest_tk=0;       // the earliest deal by time (tie: lower ticket) decides from_start
   ENUM_DEAL_TYPE earliest_dt=DEAL_TYPE_BUY; double earliest_amt=0.0;
   ulong fp_tk=0;                                     // the earliest BALANCE deal (the fingerprint)
   for(int i=0;i<n;i++)
     {
      ulong tk=HistoryDealGetTicket(i);
      if(tk==0) continue;
      const ENUM_DEAL_TYPE dt=(ENUM_DEAL_TYPE)HistoryDealGetInteger(tk,DEAL_TYPE);
      if(dt==DEAL_TYPE_CREDIT) continue;
      const datetime t=(datetime)HistoryDealGetInteger(tk,DEAL_TIME);
      const double amt=HistoryDealGetDouble(tk,DEAL_PROFIT)+HistoryDealGetDouble(tk,DEAL_COMMISSION)
                       +HistoryDealGetDouble(tk,DEAL_SWAP)+HistoryDealGetDouble(tk,DEAL_FEE);
      const bool trade=(dt==DEAL_TYPE_BUY || dt==DEAL_TYPE_SELL);
      const datetime tu=t;     // the free build counts on the server clock, no offset
      m++;
      g_hist_sum+=amt;
      if(m==1 || t<earliest_t || (t==earliest_t && tk<earliest_tk))
        { earliest_t=t; earliest_tk=tk; earliest_dt=dt; earliest_amt=amt; }
      if(dt==DEAL_TYPE_BALANCE && (!g_fp_found || t<g_fp_t || (t==g_fp_t && tk<fp_tk)))
        { g_fp_found=true; g_fp_t=t; fp_tk=tk; g_fp_amount=HistoryDealGetDouble(tk,DEAL_PROFIT); }
      if(trade)
        {
         const ENUM_DEAL_ENTRY en=(ENUM_DEAL_ENTRY)HistoryDealGetInteger(tk,DEAL_ENTRY);
         if(en==DEAL_ENTRY_IN || en==DEAL_ENTRY_INOUT)
           { g_entry_t[me]=tu; me++; }
        }
     }
   ArrayResize(g_entry_t,me);
   if(m>0) g_hist_from_start=(earliest_dt==DEAL_TYPE_BALANCE && earliest_amt>0.0);
#ifdef PL_DEV_LOG
   if(g_dev_histbad) g_hist_sum+=1.0;
   if(g_dev_fromstart_off) g_hist_from_start=false;
   if(g_fp_found) g_fp_t+=(datetime)g_dev_fpshift;
#endif
   g_hist_read=true;
   g_hist_conn=a.connected;
   g_hist_diff=g_hist_sum-a.balance;
   const bool loaded=PlHistAddsUp(a);
   g_hist_dirty=!loaded;
   PLDBG("HISTORY read deals="+(string)m+" sum="+DoubleToString(g_hist_sum,2)+" balance="+DoubleToString(a.balance,2)+" loaded="+(string)loaded);
   return loaded;
  }

//--- the entries at or after the day start, in the clock the entry times are kept in (server time)
int PlTradesToday(const datetime day_start)
  {
   return PlCountSince(g_entry_t,ArraySize(g_entry_t),day_start);
  }

//--- a new account: forget everything read
void PlExposureReset()
  {
   ArrayResize(g_ex,0); ArrayResize(g_entry_t,0);
   ArrayResize(g_cm_id,0); ArrayResize(g_cm_val,0); ArrayResize(g_cm_t,0);
   g_hist_from_start=false; g_hist_dirty=true; g_hist_sum=0.0; g_hist_conn=false; g_hist_read=false;
   g_hist_last=0; g_hist_event=0; g_hist_diff=0.0; g_hist_gap=2000;
   g_fp_found=false; g_fp_t=0; g_fp_amount=0.0;
  }

#endif
