// Required Notice: Copyright 2026 stop-loss-enjoyer
// Plainlines is source-available under the PolyForm Shield License 1.0.0.
//
// Types of the trading layer: the frozen plan taken at the first press, the guard
// verdict, the result of a send. No trading calls here; those live only in SendOrderSafe.mqh.
#property strict

#ifndef PL_TRADE_TYPES_MQH
#define PL_TRADE_TYPES_MQH

//--- the plan frozen at the first press; the send recounts from the live quote and compares with it
struct PlOrderSnap
  {
   string            symbol;
   PlInputs          in;               // copy of the inputs: lines, risk, TPs and shares, commission, ATR
   PlKind            kind;
   PlSide            side;
   int               order_type;       // ENUM_ORDER_TYPE
   double            lot;
   double            risk_money;
   double            risk_pct;
   double            entry;
   double            limit;
   double            sl;
   double            tp[PL_MAX_TP];
   int               tp_count;
   int               parts;            // orders the plan goes out as (hedging with several TPs: one per TP)
   double            mid;              // (bid+ask)/2 at the snapshot
   double            dist;             // plan.dist at the snapshot
   double            trail_val;        // trail distance of the symbol at the press
   double            net_vol;          // netting: volume of the open position of the symbol at the press (0: none, or hedging)
   double            net_sl;           // netting: its SL at the press
   PlVerdict         verdict;
   PlReason          reason;
   long              magic;
   string            comment;
   int               expiry_mode;      // 0 GTC, 1 today, 2 hours
   int               expiry_hours;
   bool              netting_ack;      // the user saw "adds to the open position"
  };

enum PlSendStatus
  {
   PL_SS_DONE=0,        // market order(s) filled
   PL_SS_PLACED,        // pending order(s) placed
   PL_SS_PARTIAL,       // filled less than asked, the rest was not sent
   PL_SS_PARTS_SHORT,   // some of several orders went out, the rest did not
   PL_SS_REJECTED,      // the server or the checks said no
   PL_SS_BLOCKED,       // not sent: a local check said no
   PL_SS_RECONFIRM,     // not sent: the numbers moved, ask again
   PL_SS_UNKNOWN,       // no answer: reconciling
   PL_SS_UNRESOLVED     // no answer and nothing found: outcome unknown, the check has ended
  };

struct PlSendRes
  {
   PlSendStatus      status;
   uint              retcode;
   int               err;
   PlReason          reason;
   int               parts_planned;
   int               parts_sent;
   ulong             ids[PL_MAX_PARTS];    // order tickets (pending) or POSITION_IDENTIFIER (market)
   double            vol_planned;
   double            vol_done;
   double            price_done;
   double            risk_done;
   double            new_lot;
   string            tag;
   string            phrase;
   string            note;              // a second line: merged TP shares, expiry kept by the panel
   //--- for the record of each part (Manage.mqh)
   double            part_lot[PL_MAX_PARTS];
   double            sl_user;             // the SL line of the user
   double            dist_user;           // |exec - user SL|
   datetime          keep_until;          // pending order whose lifetime the panel keeps (0 none)
   int               pt_n;                // one order for several TPs: the panel closes parts at these levels
   double            pt_price[PL_MAX_TP];
   double            pt_share[PL_MAX_TP]; // percent of the lot
   bool              net_add;             // netting: this trade added to an open same-side position
  };

void PlSendResReset(PlSendRes &r)
  {
   r.status=PL_SS_BLOCKED; r.retcode=0; r.err=0; r.reason=PL_R_NONE;
   r.parts_planned=0; r.parts_sent=0;
   for(int i=0;i<PL_MAX_PARTS;i++) r.ids[i]=0;
   r.vol_planned=0.0; r.vol_done=0.0; r.price_done=0.0; r.risk_done=0.0; r.new_lot=0.0;
   r.tag=""; r.phrase=""; r.note="";
   for(int i=0;i<PL_MAX_PARTS;i++) { r.part_lot[i]=0.0; }
   r.sl_user=0.0; r.dist_user=0.0; r.keep_until=0;
   r.pt_n=0; for(int i=0;i<PL_MAX_TP;i++) { r.pt_price[i]=0.0; r.pt_share[i]=0.0; }
   r.net_add=false;
  }

void PlGuardNeutral(PlGuard &g)
  {
   g.verdict=PL_OK; g.reason=PL_R_NONE; g.why=0; g.max_new_risk=-1.0;
   g.room_port=-1.0; g.port_used=0.0; g.port_cap_pct=0.0; g.balance=0.0; g.text="";
  }

//--- development switches that bend what the terminal reports (only with PL_DEV_LOG)
#ifdef PL_DEV_LOG
double g_dev_bump=0.0;          // shifts the quote by this many ticks
bool   g_dev_open=false;        // pretend the market is open
bool   g_dev_conn_off=false;    // pretend there is no connection
bool   g_dev_real=false;        // pretend the account is not a demo (the gate must refuse)
bool   g_dev_nogate=false;      // skip the Algo Trading checks of the gate (the demo check stays)
bool   g_dev_noexp=false;       // pretend the broker lacks the DAY and SPECIFIED expiry modes (the panel keeps the lifetime)
int    g_dev_expsec=0;          // pending orders live this many seconds when the Hours mode is used
double g_dev_volmax=0.0;        // the broker max lot is this value (Split can be tried with minimal lots)
int    g_dev_fillmask=-1;       // the symbol fill mask is this value (-1 off)
int    g_dev_expmask=-1;        // the symbol expiration mask is this value
int    g_dev_gtcmode=-1;        // SYMBOL_ORDER_GTC_MODE is this value
int    g_dev_stops=-1;          // the stops level is this many points (the manager's PlSlAllowed reads the terminal directly: not affected)
int    g_dev_freeze=-1;         // the freeze level is this many points (the same note)
bool   g_dev_closemagic0=false;  // a close of a position goes out with magic 0 (what a close from the terminal window looks like)
bool   g_dev_onepos=false;      // several TPs go out as one order, the panel closes the parts (what a netting account gets)
int    g_dev_stale=0;           // the last tick of the chart symbol is this many seconds old (0 off)
bool   g_dev_netting=false;     // the account is treated as netting, the chart symbol's single position as the netting position
void PlDevAdjustSym(PlSymbol &s)
  {
   if(g_dev_netting) PlReadNetting(s.name,s,true);
   if(g_dev_bump!=0.0 && s.ask>0.0) { s.ask+=g_dev_bump*s.tick_size; s.bid+=g_dev_bump*s.tick_size; }
   if(g_dev_open) { s.session_open=true; s.tick_time=s.server_now; }
   if(g_dev_stale>0 && s.name==_Symbol) s.tick_time=s.server_now-g_dev_stale;
   if(s.name==_Symbol && GlobalVariableCheck("PL.dev.noquote."+_Symbol)) { s.bid=0.0; s.ask=0.0; }
   if(g_dev_noexp) s.expiration_mode=SYMBOL_EXPIRATION_GTC;
   if(g_dev_volmax>0.0) s.vol_max=g_dev_volmax;
   if(g_dev_fillmask>=0) s.filling_mode=g_dev_fillmask;
   if(g_dev_expmask>=0) s.expiration_mode=g_dev_expmask;
   if(g_dev_gtcmode>=0) s.gtc_mode=g_dev_gtcmode;
   if(g_dev_stops>=0) s.stops_level=g_dev_stops;
   if(g_dev_freeze>=0) s.freeze_level=g_dev_freeze;
  }
void PlDevAdjustAcct(PlAccount &a)
  {
   if(g_dev_conn_off) a.connected=false;
   if(g_dev_real) a.trade_mode=ACCOUNT_TRADE_MODE_REAL;
   if(g_dev_netting) a.margin_mode=ACCOUNT_MARGIN_MODE_RETAIL_NETTING;
   if(GlobalVariableCheck("PL.dev.noalgo."+_Symbol)) a.mql_trade=false;     // this chart's instance may not trade
  }
#else
void PlDevAdjustSym(PlSymbol &s) {}
void PlDevAdjustAcct(PlAccount &a) {}
#endif

//--- how many orders a lot goes out as, and the lot and the TP level of each.
//--- Hedging with several TP levels: one order per level, each with its own TP at the broker; a share
//--- below the minimum lot merges into the order before it. Netting (or one level): one order with the
//--- TP of the last level (the panel closes the parts at the earlier levels).
//--- tp_on[i]: level i is on; lots[] and tp_idx[] get n entries (tp_idx -1: no TP).
int PlSplitParts(const bool hedging,const double lot,const double vol_min,const double vol_step,
                 const bool &tp_on[],const double &share[],double &lots[],int &tp_idx[],string &note)
  {
   note="";
   int lv[PL_MAX_TP]; int nl=0;
   for(int i=0;i<PL_MAX_TP;i++) if(tp_on[i]) { lv[nl]=i; nl++; }
   ArrayResize(lots,PL_MAX_TP); ArrayResize(tp_idx,PL_MAX_TP);
   if(nl<=1 || !hedging)
     {
      lots[0]=lot; tp_idx[0]=(nl==0)?-1:(hedging?lv[0]:lv[nl-1]);
      return 1;
     }
   const int dg=PlStepDigits(vol_step);
   double l[PL_MAX_TP];
   double sum=0.0;
   for(int k=1;k<nl;k++) { l[k]=PlFloorStep(lot*share[lv[k]]/100.0,vol_step); sum+=l[k]; }
   l[0]=PlRoundDigits(lot-sum,dg);
   for(int k=nl-1;k>=1;k--)
      if(l[k]<vol_min-PL_EPS)
        {
         l[k-1]=PlRoundDigits(l[k-1]+l[k],dg); l[k]=0.0;
         note=PLS_TP+(string)(k+1)+PLS_SHARE_IS_BELOW_THE_MINIMUM_LOT+(string)k;
        }
   if(l[0]<vol_min-PL_EPS)
     {
      for(int k=1;k<nl;k++)
         if(l[k]>0.0) { l[k]=PlRoundDigits(l[k]+l[0],dg); l[0]=0.0; note=PLS_TP1_BELOW_MIN_LOT; break; }
     }
   int n=0;
   for(int k=0;k<nl;k++)
      if(l[k]>0.0) { lots[n]=l[k]; tp_idx[n]=lv[k]; n++; }
   if(n==0) { lots[0]=lot; tp_idx[0]=lv[0]; n=1; }
   return n;
  }

//--- every order a trade goes out as. Above the broker max lot with Split (r.split_n >= 2) the lot is cut into the
//--- core's equal parts and each part is divided by the TP levels as PlSplitParts does; otherwise it is PlSplitParts
//--- of the whole lot. Returns the number of orders; when it is above PL_MAX_PARTS nothing is filled.
int PlSplitOrders(const bool hedging,const PlResult &r,const double vol_min,const double vol_step,
                  const bool &tp_on[],const double &share[],double &lots[],int &tp_idx[],string &note)
  {
   note="";
   if(r.split_n<2)
     {
      double l1[]; int t1[];
      const int n1=PlSplitParts(hedging,r.lot,vol_min,vol_step,tp_on,share,l1,t1,note);
      if(n1>PL_MAX_PARTS) return n1;
      ArrayResize(lots,PL_MAX_PARTS); ArrayResize(tp_idx,PL_MAX_PARTS);
      for(int i=0;i<n1;i++) { lots[i]=l1[i]; tp_idx[i]=t1[i]; }
      return n1;
     }
   double ll[PL_MAX_PARTS]; int tt[PL_MAX_PARTS];
   int total=0;
   for(int k=0;k<r.split_n && k<PL_MAX_PARTS;k++)
     {
      double l1[]; int t1[]; string pn;
      const int n1=PlSplitParts(hedging,r.split_lot[k],vol_min,vol_step,tp_on,share,l1,t1,pn);
      if(note=="") note=pn;
      for(int i=0;i<n1;i++)
        {
         if(total<PL_MAX_PARTS) { ll[total]=l1[i]; tt[total]=t1[i]; }
         total++;
        }
     }
   if(total>PL_MAX_PARTS) return total;
   ArrayResize(lots,PL_MAX_PARTS); ArrayResize(tp_idx,PL_MAX_PARTS);
   for(int i=0;i<total;i++) { lots[i]=ll[i]; tp_idx[i]=tt[i]; }
   return total;
  }

//--- the number of orders the trade goes out as, for the trade counters of the guards
int PlOrdersFor(const bool hedging,const PlInputs &in,const PlPlan &plan,const PlResult &r,const double vol_min,const double vol_step)
  {
   bool tp_on[PL_MAX_TP]; double share[PL_MAX_TP];
   for(int i=0;i<PL_MAX_TP;i++) { tp_on[i]=(in.tp[i].on && !in.no_tp && plan.tp[i]>0.0); share[i]=in.tp[i].share; }
   double lots[]; int idx[]; string note;
   return MathMax(1,PlSplitOrders(hedging,r,vol_min,vol_step,tp_on,share,lots,idx,note));
  }

#endif
