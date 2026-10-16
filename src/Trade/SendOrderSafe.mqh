// Required Notice: Copyright 2026 stop-loss-enjoyer
// Plainlines is source-available under the PolyForm Shield License 1.0.0.
//
// The ONLY place where orders leave the program (OrderSend and OrderCheck live here and nowhere
// else; audit.sh checks). Open, change SL and TP, close, delete a pending order, and the
// reconciliation after a lost answer.
//
// Rules this file keeps:
//  - every call first runs the gate (demo-only in a demo or dev build, connection, rights, symbol mode);
//  - an open recounts everything from a fresh quote and compares with the frozen plan: if the lot, the
//    risk or the price moved it sends nothing and asks for a new confirmation;
//  - one real send function (PlRawSend) refuses a non-demo account once more in a demo or dev build, right before OrderSend;
//  - a send with no clear answer is never repeated: the last order is looked for by its tag and by new
//    tickets (the window rests on TimeCurrent, a server time). When it is not found after 30 s with a connection
//    the outcome stays UNRESOLVED ("check the Trade tab"), never "not placed": no answer does not say that the
//    request did not run. A new open on that symbol needs a second press.
//  - every price that goes out is put on SYMBOL_TRADE_TICK_SIZE: an SL toward less risk (Buy up, Sell down),
//    an entry, a stop-limit price, a TP and a market price to the nearest tick;
//  - the fill type comes from the symbol mask only (FOK, IOC); Return only for pending orders (rule 12);
//  - a lifetime or GTC mode the symbol does not allow is refused, never invented (rule 12).
// No account number is read here.
#property strict

#ifndef PL_TRADE_SENDORDERSAFE_MQH
#define PL_TRADE_SENDORDERSAFE_MQH

#define PL_RECON_MS       30000     // how long a lost answer is looked for (with a connection)
#define PL_PRICE_MOVE     0.10      // share of the SL distance the price may move between the press and the send (not a fill limit)
#define PL_RISK_MOVE      0.02      // share the risk may move up between the press and the send

//--- the guards live in Terminal/Profile.mqh (included later)
void PlGuardRunAll(const PlAccount &a,const double new_risk,const double new_margin,const int new_open,const int new_entries,PlGuardOut &o);
string PlGuardPhraseNow(const PlGuardOut &o,const double new_risk,const double lpl,const double step,const string cur,const int cd);

//--- state -------------------------------------------------------------------------------------
int    g_tr_force_fill=-1;          // this fill mode first (-1 none); only a development command sets it
#ifdef PL_DEV_LOG
bool   g_tr_drop=false;             // development: the next answer is treated as lost
int    g_tr_dropn=0;                // development: the n-th answer from now is treated as lost
int    g_tr_rejectall=0;          // development: the next n requests are refused as 10006 (not sent)
int    g_tr_rejectn=0;            // development: the n-th request from now is refused by the "server" (not sent)
bool   g_tr_dropfail=false;         // development: the next request is not sent at all and is treated as lost
uint   g_tr_rejectcode=TRADE_RETCODE_REJECT;   // development: the retcode the refused request is classified with
bool   g_tr_partial=false;          // development: the next market request goes out with half the volume and its DONE is DONE_PARTIAL
bool   g_dev_tagoff=false;          // development: the reconcile does not know the tag of the order
bool   g_dev_vslforce=false;        // development: the SL after a fill counts as different
#endif

string   g_unk_sym="";              // symbol of the last open whose outcome stayed unknown; memory only, so a restart starts clean
bool     g_rc_active=false;
int      g_rc_kind=0;               // 0 open, 1 modify, 2 close, 3 delete
string   g_rc_match="";             // tag (with /k) to find in comments
string   g_rc_symbol="";
long     g_rc_magic=0;
int      g_rc_otype=0;              // ENUM_ORDER_TYPE of the lost order
bool     g_rc_pending=false;
datetime g_rc_sent_cur=0;           // TimeCurrent() at the send: formed on the server, independent of the PC clock
ulong    g_rc_started=0;
ulong    g_rc_ticket=0;             // modify, close, delete: the position or order
double   g_rc_sl=0.0, g_rc_tp=0.0, g_rc_vol=0.0, g_rc_tol=0.0;
ulong    g_rc_known_pos[];
ulong    g_rc_known_ord[];
PlSendRes g_rc_res;
double   g_rc_part_lot=0.0;         // lot of the part whose answer was lost
double   g_rc_total_lot=0.0;
double   g_rc_total_risk=0.0;
//--- what the phrases need
bool     g_ph_buy=true;
PlKind   g_ph_kind=PL_KIND_MARKET;
int      g_ph_digits=5, g_ph_lotdg=2, g_ph_cd=2;
string   g_ph_cur="", g_ph_sym="";
bool     g_ph_no_sl=false;          // the order has no SL: its risk is undefined and the phrase says so

double   g_ph_entry=0.0;
double   g_ph_planned=0.0;          // the risk shown on the button at the press: a fill that differs from it by more than 1 percent says so

//=================================================================================================
//  gate
//=================================================================================================
//--- The rights of this program instance: a demo account in a non-release build, no other Plainlines (free or Pro) on a chart of
//--- the terminal, Algo Trading in the terminal and for this program, the account (investor password) and the broker (EAs
//--- allowed). MQL_TRADE_ALLOWED is per instance and cannot be read from another chart. The connection is not
//--- a right: it is the same for every chart.
PlReason PlRightsReason(const PlAccount &a)
  {
#ifndef PL_RELEASE
   if(a.trade_mode!=ACCOUNT_TRADE_MODE_DEMO) return PL_R_NOT_DEMO;
#endif
   if(PlOtherPlainlines()) return PL_R_OTHER_PLAINLINES;
#ifdef PL_DEV_LOG
   if(!g_dev_nogate)       // development: let a request reach the terminal with Algo Trading off, to see what it answers
#endif
     {
      if(!a.term_trade) return PL_R_ALGO_OFF;
      if(!a.mql_trade) return PL_R_EA_NOT_ALLOWED;
     }
   if(!a.acct_trade) return PL_R_INVESTOR;
   if(!a.acct_expert) return PL_R_BROKER_NO_EA;
   return PL_R_NONE;
  }

//--- PL_R_NONE: sending may go on. closing=true lets through only the bans on a NEW side.
void PlTradeGate(const PlAccount &a,const PlSymbol &s,const bool closing,PlReason &why,const PlSide side=PL_SIDE_NONE)
  {
   why=PL_R_NONE;
#ifndef PL_RELEASE
   if(a.trade_mode!=ACCOUNT_TRADE_MODE_DEMO) { why=PL_R_NOT_DEMO; return; }
#endif
   if(!a.connected) { why=PL_R_DISCONNECTED; return; }
   why=PlRightsReason(a);
   if(why!=PL_R_NONE) return;
   if(s.sym_trade_mode==SYMBOL_TRADE_MODE_DISABLED) { why=PL_R_TRADE_DISABLED; return; }
   if(closing) return;
   if(s.sym_trade_mode==SYMBOL_TRADE_MODE_CLOSEONLY) { why=PL_R_SYMBOL_CLOSE_ONLY; return; }
   if(s.sym_trade_mode==SYMBOL_TRADE_MODE_LONGONLY && side==PL_SIDE_SELL) { why=PL_R_SYMBOL_LONG_ONLY; return; }
   if(s.sym_trade_mode==SYMBOL_TRADE_MODE_SHORTONLY && side==PL_SIDE_BUY) { why=PL_R_SYMBOL_SHORT_ONLY; return; }
  }

bool PlTradeBusy() { return g_rc_active; }

//=================================================================================================
//  small helpers
//=================================================================================================
bool PlIdIn(const ulong &arr[],const ulong id)
  {
   for(int i=ArraySize(arr)-1;i>=0;i--) if(arr[i]==id) return true;
   return false;
  }

void PlRcSnapshot()
  {
   const int np=PositionsTotal();
   ArrayResize(g_rc_known_pos,0);
   for(int i=0;i<np;i++)
     {
      ulong tk=PositionGetTicket(i);
      if(tk==0) continue;
      int n=ArraySize(g_rc_known_pos);
      ArrayResize(g_rc_known_pos,n+1);
      g_rc_known_pos[n]=(ulong)PositionGetInteger(POSITION_IDENTIFIER);
     }
   const int no=OrdersTotal();
   ArrayResize(g_rc_known_ord,0);
   for(int i=0;i<no;i++)
     {
      ulong tk=OrderGetTicket(i);
      if(tk==0) continue;
      int n=ArraySize(g_rc_known_ord);
      ArrayResize(g_rc_known_ord,n+1);
      g_rc_known_ord[n]=tk;
     }
  }

//--- selects the open position with this POSITION_IDENTIFIER; true when found
bool PlFindPosition(const ulong id)
  {
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong tk=PositionGetTicket(i);
      if(tk==0) continue;
      if((ulong)PositionGetInteger(POSITION_IDENTIFIER)==id) return true;
     }
   return false;
  }

string PlMakeTag()
  {
   MathSrand((int)((ulong)GetMicrosecondCount() ^ (ulong)(ChartID() & 0x7FFFFFFF)));
   const string al="0123456789abcdefghijklmnopqrstuvwxyz";
   string t="";
   for(int i=0;i<5;i++) t+=StringSubstr(al,MathRand()%36,1);
   return t;
  }

string PlMoneyText(const double v) { return PlMoney(v,g_ph_cur,g_ph_cd); }
//--- the risk in a phrase: never a number for a trade without SL (the money counted there is only the commission)
string PlRiskText(const double v) { return g_ph_no_sl?PLS_UNDEFINED:PlMoneyText(v); }

void PlFcAdd(int &c[],const int m)
  {
   for(int i=ArraySize(c)-1;i>=0;i--) if(c[i]==m) return;
   int n=ArraySize(c);
   ArrayResize(c,n+1); c[n]=m;
  }

//--- fill types to try: a market order uses FOK and IOC from the symbol mask only, FOK first
//--- because it fills the planned lot or nothing; Return is for pending orders only. Nothing is added that the mask lacks.
void PlFillCandidates(const PlSymbol &s,const bool pending,int &c[])
  {
   ArrayResize(c,0);
   if(pending) PlFcAdd(c,ORDER_FILLING_RETURN);
   if((s.filling_mode&SYMBOL_FILLING_FOK)!=0) PlFcAdd(c,ORDER_FILLING_FOK);
   if((s.filling_mode&SYMBOL_FILLING_IOC)!=0) PlFcAdd(c,ORDER_FILLING_IOC);
   //--- a development override goes first (only when it is in the list)
   const int pref=g_tr_force_fill;
   bool inlist=false;
   for(int i=0;i<ArraySize(c);i++) if(c[i]==pref) inlist=true;
   if(pref>=0 && inlist)
     {
      int tmp[]; ArrayResize(tmp,0);
      PlFcAdd(tmp,pref);
      for(int i=0;i<ArraySize(c);i++) PlFcAdd(tmp,c[i]);
      ArrayResize(c,ArraySize(tmp));
      for(int i=0;i<ArraySize(tmp);i++) c[i]=tmp[i];
     }
  }

string PlFillName(const int m)
  {
   if(m==ORDER_FILLING_FOK) return "FOK";
   if(m==ORDER_FILLING_IOC) return "IOC";
   return "Return";
  }

//--- pending order lifetime from SYMBOL_EXPIRATION_MODE and SYMBOL_ORDER_GTC_MODE. ORDER_TIME_GTC is used
//--- only with the GTC bit. keep: the time the panel deletes the order itself when the broker has no type for the wanted
//--- lifetime (0: nothing to keep). Returns false when no type in the mask fits: nothing is invented.
bool PlExpiry(const PlSymbol &s,const int mode,const int hours,ENUM_ORDER_TYPE_TIME &tt,datetime &exp,string &note,datetime &keep)
  {
   tt=ORDER_TIME_GTC; exp=0; note=""; keep=0;
   const int m=s.expiration_mode;
   const bool b_gtc=((m&SYMBOL_EXPIRATION_GTC)!=0), b_day=((m&SYMBOL_EXPIRATION_DAY)!=0), b_spec=((m&SYMBOL_EXPIRATION_SPECIFIED)!=0);
   MqlDateTime d; TimeToStruct(TimeTradeServer(),d);
   d.hour=23; d.min=59; d.sec=59;
   const datetime eod=StructToTime(d);
   if(mode==1)
     {
      if(b_day) tt=ORDER_TIME_DAY;
      else if(b_spec) { tt=ORDER_TIME_SPECIFIED; exp=eod; }
      else if(b_gtc) { tt=ORDER_TIME_GTC; keep=eod; note=PLS_EXP_KEPT; }
      else return false;
     }
   else if(mode==2)
     {
      long secs=(long)hours*3600;
#ifdef PL_DEV_LOG
      if(g_dev_expsec>0) secs=g_dev_expsec;
#endif
      if(b_spec && !(secs<3600)) { tt=ORDER_TIME_SPECIFIED; exp=TimeTradeServer()+(datetime)secs; }
      else if(b_gtc) { tt=ORDER_TIME_GTC; keep=TimeTradeServer()+(datetime)secs; note=PLS_EXP_KEPT; }
      else return false;
     }
   else
     {
      if(b_gtc) tt=ORDER_TIME_GTC;
      else if(b_day) { tt=ORDER_TIME_DAY; note=PLS_EXP_DAY_ONLY; }
      else return false;
     }
   //--- the broker deletes pending orders at the end of the day under this mode
   if(tt==ORDER_TIME_GTC && s.gtc_mode==SYMBOL_ORDERS_DAILY_EXCLUDING_STOPS) note=PLS_EXP_DAY_ONLY;
   return true;
  }

//--- the refusal text when the chosen lifetime is not allowed: names the lifetimes that do pass (at most two)
string PlExpiryRefusal(const PlSymbol &s,const int hours)
  {
   string names[];
   if(StringSplit(PLS_GTC_TODAY_HOURS,'|',names)!=3) return PLS_EXP_NONE;
   string ok1="", ok2="";
   for(int md=0;md<3;md++)
     {
      ENUM_ORDER_TYPE_TIME tt; datetime ex, kp; string nt;
      if(!PlExpiry(s,md,hours,tt,ex,nt,kp)) continue;
      if(ok1=="") ok1=names[md]; else ok2=names[md];
     }
   if(ok1=="") return PLS_EXP_NONE;
   return PLS_EXP_USE+ok1+((ok2!="")?PLS_OR+ok2:"");
  }

//=================================================================================================
//  the one real send
//=================================================================================================
//--- returns -1: not sent (non-demo account in a demo or dev build); 0: sent, OrderSend said false;
//--- 1: sent, OrderSend said true
int PlRawSend(MqlTradeRequest &rq,MqlTradeResult &tr)
  {
#ifndef PL_RELEASE
   if(AccountInfoInteger(ACCOUNT_TRADE_MODE)!=ACCOUNT_TRADE_MODE_DEMO)
     {
      PLDBG("RAWSEND refused: account is not a demo");
      return -1;
     }
#endif
   ResetLastError();
   bool ok=OrderSend(rq,tr);
   return ok?1:0;
  }

enum PlAttempt { PL_AT_OK=0, PL_AT_PARTIAL, PL_AT_REJECT, PL_AT_UNKNOWN };

//--- what an answer means. OrderSend true only says the basic check passed; a code that does not say
//--- whether the request ran (ERROR, TIMEOUT, CONNECTION, LOCKED) is UNKNOWN, never "not placed".
PlAttempt PlClassify(const int sent,const uint rc,const int err,const ENUM_TRADE_REQUEST_ACTIONS action,const ulong tr_deal)
  {
   if(sent==1 && rc==TRADE_RETCODE_DONE) return PL_AT_OK;
   //--- a market order answered PLACED with no deal ticket may sit in the book (send-5): the reconcile decides
   if(sent==1 && rc==TRADE_RETCODE_PLACED) return (action!=TRADE_ACTION_DEAL || tr_deal>0)?PL_AT_OK:PL_AT_UNKNOWN;
   if(sent==1 && rc==TRADE_RETCODE_DONE_PARTIAL) return PL_AT_PARTIAL;
   if(sent==0 && (rc==TRADE_RETCODE_DONE || rc==TRADE_RETCODE_PLACED || rc==TRADE_RETCODE_DONE_PARTIAL)) return PL_AT_UNKNOWN;   // safeguard (send-9)
   if(rc==TRADE_RETCODE_ERROR || rc==TRADE_RETCODE_TIMEOUT || rc==TRADE_RETCODE_CONNECTION || rc==TRADE_RETCODE_LOCKED) return PL_AT_UNKNOWN;
   if(rc==0)
     {
      //--- OrderSend said false without a server code: a local refusal is clear, anything else is not
      if(err==4752 || err==4110 || err==4111 || err==4109) return PL_AT_REJECT;
      return PL_AT_UNKNOWN;
     }
   return PL_AT_REJECT;
  }

//--- one request with the fill type candidates. cands may be empty for SLTP and REMOVE.
//--- rc/err: server code and GetLastError of the last attempt. tr: the last answer.
PlAttempt PlTryRequest(MqlTradeRequest &rq,const int &cands[],MqlTradeResult &tr,uint &rc,int &err)
  {
   const int nc=ArraySize(cands);
   const int loops=(nc>0)?nc:1;
   rc=0; err=0;
   for(int ci=0;ci<loops;ci++)
     {
      if(nc>0) rq.type_filling=(ENUM_ORDER_TYPE_FILLING)cands[ci];
      MqlTradeCheckResult chk; ZeroMemory(chk);
      ResetLastError();
      bool okc=OrderCheck(rq,chk);
      PLDBG("CHECK fill="+PlFillName(rq.type_filling)+" ok="+(string)okc+" rc="+(string)chk.retcode);
      if(!okc)
        {
         if(chk.retcode==TRADE_RETCODE_INVALID_FILL && ci+1<loops) continue;
         rc=chk.retcode; err=GetLastError();
         return PL_AT_REJECT;
        }
      PlRcSnapshot();
      ZeroMemory(tr);
#ifdef PL_DEV_LOG
      if(g_tr_rejectn>0)
        {
         g_tr_rejectn--;
         if(g_tr_rejectn==0)
           {
            rc=g_tr_rejectcode; err=0; g_tr_rejectcode=TRADE_RETCODE_REJECT;
            PLDBG("SEND refused before sending (development) rc="+(string)rc);
            return PlClassify(1,rc,0,rq.action,0);
           }
        }
      if(g_tr_rejectall>0)
        {
         g_tr_rejectall--;
         rc=TRADE_RETCODE_REJECT; err=0;
         PLDBG("SEND refused before sending (development, rejectall) rc="+(string)rc+" left="+(string)g_tr_rejectall);
         return PlClassify(1,rc,0,rq.action,0);
        }
      if(g_tr_dropfail) { g_tr_dropfail=false; rc=0; PLDBG("SEND dropped before sending (development)"); return PL_AT_UNKNOWN; }
      const double dev_vol0=rq.volume;
      bool dev_half=false;
      if(g_tr_partial && rq.action==TRADE_ACTION_DEAL)
        {
         const double st=SymbolInfoDouble(rq.symbol,SYMBOL_VOLUME_STEP), mn=SymbolInfoDouble(rq.symbol,SYMBOL_VOLUME_MIN);
         const double half=PlFloorStep(rq.volume/2.0,st);
         g_tr_partial=false;
         if(half>=mn-PL_EPS && half<rq.volume-PL_EPS) { rq.volume=half; dev_half=true; PLDBG("SEND half volume (development) "+DoubleToString(half,3)); }
        }
#endif
      int sent=PlRawSend(rq,tr);
#ifdef PL_DEV_LOG
      if(dev_half)
        {
         rq.volume=dev_vol0;
         if(sent==1 && tr.retcode==TRADE_RETCODE_DONE) tr.retcode=TRADE_RETCODE_DONE_PARTIAL;     // tr.volume stays the real filled half
        }
#endif
      if(sent<0) { rc=TRADE_RETCODE_REJECT; err=0; return PL_AT_REJECT; }
      err=GetLastError();
      rc=tr.retcode;
      PLDBG("SEND type="+EnumToString(rq.type)+" vol="+DoubleToString(rq.volume,2)+" price="+DoubleToString(rq.price,8)
            +" sl="+DoubleToString(rq.sl,8)+" tp="+DoubleToString(rq.tp,8)+" fill="+PlFillName(rq.type_filling)
            +" magic="+(string)rq.magic+" cmt="+rq.comment+" -> sent="+(string)sent+" rc="+(string)rc+" order="+(string)tr.order
            +" deal="+(string)tr.deal+" vol="+DoubleToString(tr.volume,2)+" price="+DoubleToString(tr.price,8));
#ifdef PL_DEV_LOG
      if(g_tr_dropn>0 && --g_tr_dropn==0) g_tr_drop=true;
      if(g_tr_drop) { g_tr_drop=false; rc=0; PLDBG("SEND answer dropped (development)"); return PL_AT_UNKNOWN; }
#endif
      if(rc==TRADE_RETCODE_INVALID_FILL && ci+1<loops) continue;
      const PlAttempt at=PlClassify(sent,rc,err,rq.action,tr.deal);
      return at;
     }
   return PL_AT_REJECT;
  }

//=================================================================================================
//  phrases
//=================================================================================================
string PlLotsTxt(const double v) { return DoubleToString(v,g_ph_lotdg); }

string PlPriceTxt(const double v) { return DoubleToString(v,g_ph_digits); }

string PlKindTitle()
  {
   string sd=g_ph_buy?PLS_BUY:PLS_SELL;
   switch(g_ph_kind)
     {
      case PL_KIND_LIMIT:      return sd+PLS_LIMIT_SUFFIX;
      case PL_KIND_STOP:       return sd+PLS_STOP_SUFFIX;
      case PL_KIND_STOP_LIMIT: return sd+PLS_STOP_LIMIT_SUFFIX;
     }
   return sd;
  }

//--- the finished phrase for the status of a result; why is the reason of a shortfall
void PlSendPhrase(PlSendRes &r,const string why)
  {
   switch(r.status)
     {
      case PL_SS_DONE:
         //--- the symbol is in the header of the panel: the phrase is the lot, the price and the risk, with the planned risk when
         //--- the fill moved it by more than 1 percent
         if(r.parts_sent<=1) r.phrase=PLS_FILLED+PlLotsTxt(r.vol_done)+PLS_AT+PlPriceTxt(r.price_done)+PlDotSep()+PLS_RISK_SP_LC+PlRiskText(r.risk_done);
         else r.phrase=PLS_FILLED+PlLotsTxt(r.vol_done)+PLS_IN+(string)r.parts_sent+" "+PLS_ORDERS+PlDotSep()+PLS_RISK_SP_LC+PlRiskText(r.risk_done);
         if(!g_ph_no_sl && g_ph_planned>PL_EPS && MathAbs(r.risk_done-g_ph_planned)>g_ph_planned*0.01)
            r.phrase+=PLS_PLANNED_SP+PlRiskText(g_ph_planned)+")";
         break;
      case PL_SS_PLACED:
         if(r.parts_sent<=1) r.phrase=PLS_PLACED_SP+PlKindTitle()+" "+PlLotsTxt(r.vol_done)+PLS_AT+PlPriceTxt(g_ph_entry)+PlDotSep()+PLS_RISK_SP_LC+PlRiskText(r.risk_done);
         else r.phrase=PLS_PLACED_SP+PlKindTitle()+" "+PlLotsTxt(r.vol_done)+PLS_IN+(string)r.parts_sent+" "+PLS_ORDERS+PlDotSep()+PLS_RISK_SP_LC+PlRiskText(r.risk_done);
         break;
      case PL_SS_PARTIAL:
         r.phrase=PLS_FILLED+PlLotsTxt(r.vol_done)+PLS_OF_SP+PlLotsTxt(r.vol_planned)+PLS_LOT_RISK+PlRiskText(r.risk_done)+PLS_THE_REST_WAS_NOT_FILLED;
         break;
      case PL_SS_PARTS_SHORT:
         r.phrase=PLS_SENT+(string)r.parts_sent+PLS_OF_SP+(string)r.parts_planned+" "+PLS_ORDERS+": "+why;
         break;
      default:
         if(why!="") r.phrase=why;
     }
  }

//=================================================================================================
//  reconciliation after a lost answer
//=================================================================================================
//--- the part number ends the tag: "ab12c/1" must not be found in the comment of "ab12c/10"
bool PlCommentHas(const string c,const string tag)
  {
   if(tag=="") return false;
   int from=0;
   while(true)
     {
      const int p=StringFind(c,tag,from);
      if(p<0) return false;
      const int e=p+StringLen(tag);
      if(e>=StringLen(c)) return true;
      const ushort nx=StringGetCharacter(c,e);
      if(nx<'0' || nx>'9') return true;
      from=p+1;
     }
   return false;
  }

//--- true when the id is one of the parts of this open already counted as sent
bool PlIdInRes(const ulong id)
  {
   const int n=MathMin(g_rc_res.parts_sent,PL_MAX_PARTS);
   for(int i=0;i<n;i++) if(g_rc_res.ids[i]==id) return true;
   return false;
  }

//--- the price of the entry deal of a position in the selected history; 0 when there is none
double PlRcEntryPrice(const ulong pid)
  {
   for(int i=HistoryDealsTotal()-1;i>=0;i--)
     {
      const ulong tk=HistoryDealGetTicket(i);
      if(tk==0) continue;
      if((ulong)HistoryDealGetInteger(tk,DEAL_POSITION_ID)!=pid) continue;
      if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(tk,DEAL_ENTRY)!=DEAL_ENTRY_IN) continue;
      return HistoryDealGetDouble(tk,DEAL_PRICE);
     }
   return 0.0;
  }

//--- looks for the lost order of an open: true and the id/price/volume when found. The tag is only a hint;
//--- the main match is magic + symbol + side + an id that did not exist before the send, in a window anchored on TimeCurrent
//--- (a server time) taken at the send. POSITION_COMMENT is never an identity: a partial close with a request comment
//--- overwrites it (demo FTMO 13.10.2026, E14).
bool PlRcFindOpen(ulong &id,double &price,double &vol)
  {
   id=0; price=0.0; vol=0.0;
   const bool buy=(g_rc_otype==ORDER_TYPE_BUY || g_rc_otype==ORDER_TYPE_BUY_LIMIT || g_rc_otype==ORDER_TYPE_BUY_STOP || g_rc_otype==ORDER_TYPE_BUY_STOP_LIMIT);
   const datetime lo=g_rc_sent_cur-1;
   //--- positions (a pending order may also have filled already)
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong tk=PositionGetTicket(i);
      if(tk==0) continue;
      if(PositionGetString(POSITION_SYMBOL)!=g_rc_symbol || PositionGetInteger(POSITION_MAGIC)!=g_rc_magic) continue;
      ulong pid=(ulong)PositionGetInteger(POSITION_IDENTIFIER);
      bool hit=PlCommentHas(PositionGetString(POSITION_COMMENT),g_rc_match);
      if(!hit && !g_rc_pending && !PlIdIn(g_rc_known_pos,pid) && !PlIdInRes(pid)
         && ((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY)==buy
         && (datetime)PositionGetInteger(POSITION_TIME)>=lo) hit=true;
      //--- netting add: the position is the whole of it, its volume and its average price are not those of this order (a lost
      //--- answer found here said "Filled 10.88" for an add of 8.21 and scaled the risk by the whole volume). The history pass
      //--- below finds the order and its deal; until it is there the check goes on.
      if(hit && g_rc_res.net_add && !g_rc_pending) continue;
      if(hit) { id=pid; price=PositionGetDouble(POSITION_PRICE_OPEN); vol=PositionGetDouble(POSITION_VOLUME); return true; }
     }
   if(g_rc_pending)
     {
      for(int i=OrdersTotal()-1;i>=0;i--)
        {
         ulong tk=OrderGetTicket(i);
         if(tk==0) continue;
         if(OrderGetString(ORDER_SYMBOL)!=g_rc_symbol || OrderGetInteger(ORDER_MAGIC)!=g_rc_magic) continue;
         bool hit=PlCommentHas(OrderGetString(ORDER_COMMENT),g_rc_match);
         if(!hit && !PlIdIn(g_rc_known_ord,tk) && (int)OrderGetInteger(ORDER_TYPE)==g_rc_otype
            && (datetime)OrderGetInteger(ORDER_TIME_SETUP)>=lo) hit=true;
         if(hit) { id=tk; price=OrderGetDouble(ORDER_PRICE_OPEN); vol=OrderGetDouble(ORDER_VOLUME_CURRENT); return true; }
        }
     }
   //--- history: the order or deal may already be done and gone (stopped out, expired, cancelled)
   if(HistorySelect(g_rc_sent_cur-60,TimeCurrent()+86400))
     {
      for(int i=HistoryOrdersTotal()-1;i>=0;i--)
        {
         ulong tk=HistoryOrderGetTicket(i);
         if(tk==0) continue;
         if(HistoryOrderGetString(tk,ORDER_SYMBOL)!=g_rc_symbol || HistoryOrderGetInteger(tk,ORDER_MAGIC)!=g_rc_magic) continue;
         bool hit=PlCommentHas(HistoryOrderGetString(tk,ORDER_COMMENT),g_rc_match);
         const ulong opid=(ulong)HistoryOrderGetInteger(tk,ORDER_POSITION_ID);
         //--- the close order or stop-out order of an unrelated position has the opposite type and that position's id (in the snapshot)
         if(!hit && (int)HistoryOrderGetInteger(tk,ORDER_TYPE)==g_rc_otype
            && (datetime)HistoryOrderGetInteger(tk,ORDER_TIME_SETUP)>=lo
            && !PlIdIn(g_rc_known_ord,tk) && !PlIdIn(g_rc_known_pos,tk) && !PlIdInRes(tk)
            && !PlIdIn(g_rc_known_pos,opid)) hit=true;
         if(hit)
           {
            double hp=HistoryOrderGetDouble(tk,ORDER_PRICE_OPEN);
            if(!g_rc_pending)
              {
               //--- a market order reports ORDER_PRICE_OPEN 0: the price is the entry deal of its position. No such deal
               //--- (an order that never filled): not a hit here, the deals pass below decides.
               hp=(opid>0)?PlRcEntryPrice(opid):0.0;
               if(hp<=0.0) continue;
              }
            id=(g_rc_pending)?tk:((opid>0)?opid:tk);
            price=hp; vol=HistoryOrderGetDouble(tk,ORDER_VOLUME_INITIAL);
            return true;
           }
        }
      for(int i=HistoryDealsTotal()-1;i>=0;i--)
        {
         ulong tk=HistoryDealGetTicket(i);
         if(tk==0) continue;
         if(HistoryDealGetString(tk,DEAL_SYMBOL)!=g_rc_symbol || HistoryDealGetInteger(tk,DEAL_MAGIC)!=g_rc_magic) continue;
         if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(tk,DEAL_ENTRY)!=DEAL_ENTRY_IN) continue;
         bool hit=PlCommentHas(HistoryDealGetString(tk,DEAL_COMMENT),g_rc_match);
         const ulong dpid=(ulong)HistoryDealGetInteger(tk,DEAL_POSITION_ID);
         if(!hit && (ENUM_DEAL_TYPE)HistoryDealGetInteger(tk,DEAL_TYPE)==(buy?DEAL_TYPE_BUY:DEAL_TYPE_SELL)
            && (datetime)HistoryDealGetInteger(tk,DEAL_TIME)>=lo
            && !PlIdIn(g_rc_known_pos,dpid) && !PlIdInRes(dpid)) hit=true;
         if(hit)
           { id=dpid; price=HistoryDealGetDouble(tk,DEAL_PRICE); vol=HistoryDealGetDouble(tk,DEAL_VOLUME); return true; }
        }
     }
   return false;
  }

//--- the open part found (or given up): fill g_rc_res and the phrase
void PlRcFinishOpen(const bool found,const ulong id,const double price,const double vol)
  {
   PlSendRes r=g_rc_res;
   if(found)
     {
      const double v=(vol>0.0)?vol:g_rc_part_lot;
      if(r.parts_sent<PL_MAX_PARTS) { r.ids[r.parts_sent]=id; if(!g_rc_pending) r.part_lot[r.parts_sent]=v; }
      r.parts_sent++;
      r.vol_done+=v;
      r.price_done=price;
      if(g_rc_total_lot>0.0) r.risk_done+=g_rc_total_risk*v/g_rc_total_lot;
      if(r.net_add) r.note=(r.note!="")?r.note+". "+PLS_NET_CHECK_SLTP:PLS_NET_CHECK_SLTP;     // a lost-answer add did not pass PlVerifySl
      if(r.parts_sent>=r.parts_planned) r.status=g_rc_pending?PL_SS_PLACED:PL_SS_DONE;
      else r.status=PL_SS_PARTS_SHORT;
      PlSendPhrase(r,PLS_ANSWER_LOST_REST_NOT_SENT);
     }
   else
     {
      //--- no answer and nothing found: the outcome is unknown, not "not placed"
      if(r.parts_sent==0) { r.status=PL_SS_UNRESOLVED; r.phrase=PLS_UNRESOLVED; }
      else { r.status=PL_SS_PARTS_SHORT; PlSendPhrase(r,PLS_LAST_UNKNOWN); }
      g_unk_sym=PlOwnCopy(g_rc_symbol);
     }
   g_rc_res=r;
   g_rc_active=false;
  }

//--- an account change while a check is running: the check ends, the outcome stays unresolved
void PlTradeReconcileAbort(const string phrase)
  {
   g_unk_sym="";
   if(!g_rc_active) return;
   PlSendRes r=g_rc_res; r.status=PL_SS_UNRESOLVED; r.phrase=phrase; g_rc_res=r;
   g_rc_active=false;
  }

//--- called by the timer (every 500 ms is enough) and by OnTradeTransaction while the status is UNKNOWN.
//--- true when the answer is found or given up: res holds the final result then.
bool PlTradeReconcileStep(PlSendRes &res)
  {
   if(!g_rc_active) { res=g_rc_res; return true; }
   const bool conn=(TerminalInfoInteger(TERMINAL_CONNECTED)!=0);
   if(!conn)
     {
      g_rc_started=GetTickCount64();     // the 30 s count again from the moment the connection is back
      res=g_rc_res; res.status=PL_SS_UNKNOWN; res.phrase=PLS_WAIT_CONN;
      return false;
     }
   if(g_rc_kind==0)
     {
      ulong id; double price, vol;
      if(PlRcFindOpen(id,price,vol)) { PlRcFinishOpen(true,id,price,vol); res=g_rc_res; return true; }
      if(GetTickCount64()-g_rc_started>=PL_RECON_MS) { PlRcFinishOpen(false,0,0,0); res=g_rc_res; return true; }
      res=g_rc_res; res.status=PL_SS_UNKNOWN; res.phrase=PLS_CHECKING;
      return false;
     }
   //--- change, close, delete: judged by the ticket
   bool done=false;
   string part_sym="";
   if(g_rc_kind==1)
     {
      if(PlFindPosition(g_rc_ticket))
         done=(MathAbs(PositionGetDouble(POSITION_SL)-g_rc_sl)<=g_rc_tol && MathAbs(PositionGetDouble(POSITION_TP)-g_rc_tp)<=g_rc_tol);
     }
   else if(g_rc_kind==2)
     {
      if(!PlFindPosition(g_rc_ticket)) done=true;
      else
        {
         done=(PositionGetDouble(POSITION_VOLUME)<g_rc_vol-PL_EPS);
         if(done) part_sym=PositionGetString(POSITION_SYMBOL);       // a part closed, the position is still there
        }
     }
   else
     {
      //--- a pending order that is gone may have been cancelled or filled: judged by its state (ORDER_STATE)
      bool filled=false;
      if(!OrderSelect(g_rc_ticket))
        {
         bool hs=HistoryOrderSelect(g_rc_ticket);
         if(!hs && HistorySelect(0,TimeCurrent()+86400)) hs=HistoryOrderSelect(g_rc_ticket);
         if(hs)
           {
            const ENUM_ORDER_STATE st=(ENUM_ORDER_STATE)HistoryOrderGetInteger(g_rc_ticket,ORDER_STATE);
            if(st==ORDER_STATE_CANCELED || st==ORDER_STATE_EXPIRED) done=true;
            else if(st==ORDER_STATE_FILLED || st==ORDER_STATE_PARTIAL) filled=true;
           }
        }
      if(filled)
        {
         PlSendRes r=g_rc_res; r.status=PL_SS_REJECTED; r.phrase=PLS_ORDER_FILLED_NOT_DELETED;
         g_rc_res=r; g_rc_active=false; res=r;
         return true;
        }
     }
   if(done)
     {
      PlSendRes r=g_rc_res;
      r.status=PL_SS_DONE; r.phrase=(g_rc_kind==1)?PLS_SLTP_CHANGED:(g_rc_kind==2)?(part_sym!=""?PLS_CLOSED_PART_OF+part_sym+PLS_REST_STILL_OPEN:PLS_POS_CLOSED):PLS_ORDER_DELETED;
      g_rc_res=r; g_rc_active=false; res=r;
      return true;
     }
   if(GetTickCount64()-g_rc_started>=PL_RECON_MS)
     {
      PlSendRes r=g_rc_res;
      r.status=PL_SS_UNRESOLVED; r.phrase=PLS_UNRESOLVED;
      g_rc_res=r; g_rc_active=false; res=r;
      return true;
     }
   res=g_rc_res; res.status=PL_SS_UNKNOWN; res.phrase=PLS_CHECKING;
   return false;
  }

//=================================================================================================
//  open
//=================================================================================================
void PlBlocked(PlSendRes &res,const PlReason why)
  {
   res.status=PL_SS_BLOCKED; res.reason=why; res.phrase=PlReasonText(why);
  }

//--- the position id of a filled deal (hedging: equals the order ticket)
ulong PlDealPosition(const ulong deal,const ulong order)
  {
   if(deal!=0)
     {
      if(HistoryDealSelect(deal)) return (ulong)HistoryDealGetInteger(deal,DEAL_POSITION_ID);
      if(HistorySelect(TimeTradeServer()-300,TimeTradeServer()+60) && HistoryDealSelect(deal))
         return (ulong)HistoryDealGetInteger(deal,DEAL_POSITION_ID);
     }
   return order;
  }

void PlSendModifyPos(const ulong pos_id,const double sl,const double tp,PlSendRes &res);

//--- after a fill the broker may have trimmed the SL: put it right at once
//--- net_add (netting, the trade added to the open position): the whole position is forced to the plan's SL and TP, whatever the
//--- server did with the add (not documented); POSITION_PRICE_OPEN is then the average, so the fill price stays as it is
void PlVerifySl(const ulong pos_id,const PlSymbol &s,const double sl,const double tp,const bool net_add,double &open_price,PlSendRes &res)
  {
   if(pos_id==0) return;
   bool seen=false;
   for(int i=0;i<4 && !seen;i++)
     {
      if(PlFindPosition(pos_id)) { seen=true; break; }
      Sleep(100);
     }
   if(!seen && net_add && PositionSelect(s.name)) seen=true;     // the deal may not be in the history yet; on netting the symbol's position is the one
   if(!seen)
     {
      if(net_add) res.note=(res.note!="")?res.note+". "+PLS_NET_CHECK_SLTP:PLS_NET_CHECK_SLTP;
      return;
     }
   const ulong pid=(ulong)PositionGetInteger(POSITION_IDENTIFIER);
   if(!net_add) open_price=PositionGetDouble(POSITION_PRICE_OPEN);     // the answer of a deal carries no price on some servers
   if(sl<=0.0) return;
   const double cur=PositionGetDouble(POSITION_SL);
   bool differs=(MathAbs(cur-sl)>s.tick_size*0.5 || (net_add && MathAbs(PositionGetDouble(POSITION_TP)-tp)>s.tick_size*0.5));
#ifdef PL_DEV_LOG
   if(g_dev_vslforce) differs=true;
#endif
   if(!differs) return;
   PLDBG("VERIFY SL differs: wanted "+DoubleToString(sl,s.digits)+" got "+DoubleToString(cur,s.digits)+", correcting");
   double sl_fix=sl;
#ifdef PL_DEV_LOG
   //--- development: the forced correction asks for an SL one tick off, so that the request is a real change the server accepts
   if(g_dev_vslforce) sl_fix=((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY)?sl+s.tick_size:sl-s.tick_size;
#endif
   PlSendRes m;
   PlSendModifyPos(pid,sl_fix,tp,m);
   if(m.status==PL_SS_UNKNOWN) res.note=PLS_SL_FIX_UNKNOWN;
   else if(m.status!=PL_SS_DONE) res.note=net_add?PLS_NET_CHECK_SLTP:PLS_NO_SL_OPENED;
  }

void PlSendOpen(PlOrderSnap &snap,const PlGuard &g,PlSendRes &res)
  {
   PlSendResReset(res);
   if(g_rc_active) { res.status=PL_SS_BLOCKED; res.phrase=PLS_BUSY; return; }
   PlAccount acc; PlSymbol s;
   PlReadAccount(acc);
   PlDevAdjustAcct(acc);
   if(!PlReadSymbol(snap.symbol,s)) { PlBlocked(res,PL_R_NO_SYMBOL_DATA); return; }
   PlDevAdjustSym(s);
   //--- on a netting account the open position is part of what was pressed for (its risk at the new SL is in the plan):
   //--- a trailing or breakeven step (also from another chart), a partial close or a fill since the press asks again instead of
   //--- sending on numbers nobody saw. On hedging net_vol is 0 on both sides
   if(MathAbs(s.net_vol-snap.net_vol)>PL_EPS || (s.net_vol>PL_EPS && MathAbs(s.net_sl-snap.net_sl)>s.tick_size*0.5))
     { res.status=PL_SS_BLOCKED; res.phrase=PLS_POS_CHANGED; return; }
   //--- 1. gate
   PlReason why;
   PlTradeGate(acc,s,false,why,snap.side);
   if(why!=PL_R_NONE) { PlBlocked(res,why); return; }
   //--- 2. recount from the live quote
   PlInputs in=snap.in;
   PlPlan plan; PlResult r;
   const bool hedging=(acc.margin_mode==ACCOUNT_MARGIN_MODE_RETAIL_HEDGING);
   bool split_hedge=hedging;
#ifdef PL_DEV_LOG
   if(g_dev_onepos) split_hedge=false;
#endif
   if(PlPrepare(in,s,plan)) PlFillTerminalCalcs(s,plan,in);
   //--- the side is the one the trader pressed for. On Market the recount takes the live price, and a price that went
   //--- through the SL line since the press would turn a Buy into a Sell: refused, the trader moves the line
   if(plan.ok && snap.side!=PL_SIDE_NONE && plan.side!=snap.side) { PlBlocked(res,PL_R_SIDE_CROSSED); return; }
   PlCompute(in,s,acc,plan,r);
   //--- a broker minimum commission is paid by every order and the number of orders depends on the lot: if the lot of the recount
   //--- goes out as more orders than the count the calculation assumed, count again with the larger number (it only shrinks the lot)
   if(plan.ok && in.comm.min_money>PL_EPS && r.lot>PL_EPS)
     {
      const int n_now=PlOrdersFor(split_hedge,in,plan,r,s.vol_min,s.vol_step);
      if(n_now>MathMax(1,in.n_orders))
        {
         in.n_orders=n_now;
         PlCompute(in,s,acc,plan,r);
        }
     }
   if(!plan.ok) { PlBlocked(res,plan.reason); return; }
   if(r.verdict==PL_BLOCK)
     {
      PlBlocked(res,r.reason);
      if(r.reason==PL_R_STALE_QUOTE) res.phrase=PlStaleText(PlStaleSeconds(s));
      return;
     }
   if(plan.side!=snap.side || plan.order_type!=snap.order_type || r.lot<=0.0)
     { PlBlocked(res,PL_R_ENTRY_WRONG_SIDE); return; }
   //--- 3. has anything moved since the press?
   const double mid=(s.ask+s.bid)/2.0;
   if(snap.kind==PL_KIND_MARKET && snap.dist>0.0 && MathAbs(mid-snap.mid)>PL_PRICE_MOVE*snap.dist)
     { res.status=PL_SS_RECONFIRM; res.phrase=PLS_PRICE_MOVED; res.new_lot=r.lot; return; }
   //--- the trade goes out at the risk the trader asked for: the lot of the recount on the fresh quote is sent,
   //--- not the lot shown on the CONFIRM button. The price gate above bounds the change (about a tenth either way); a new
   //--- block or a new confirmation asks again below, and the risk may not be above the confirmed one.
   if(MathAbs(r.lot-snap.lot)>s.vol_step*0.5)
     { PLDBG("SEND recount lot "+DoubleToString(r.lot,3)+" (confirmed "+DoubleToString(snap.lot,3)+")"); }
   if(r.risk_money>snap.risk_money*(1.0+PL_RISK_MOVE)+PL_EPS)
     { res.status=PL_SS_RECONFIRM; res.new_lot=r.lot; res.phrase=PLS_CONFIRM_AGAIN; return; }
   if(r.verdict==PL_CONFIRM && snap.verdict!=PL_CONFIRM)
     { res.status=PL_SS_RECONFIRM; res.new_lot=r.lot; res.phrase=PlReasonText(r.reason); return; }
   //--- 4. the account guards
   if(g.verdict==PL_BLOCK)
     {
      PlBlocked(res,g.reason!=PL_R_NONE?g.reason:PL_R_GUARD);
      if(g.text!="") res.phrase=g.text;
      return;
     }
   const double risk_eff=r.risk_add;     // netting add: what the trade adds to the worst case, not the whole position
   if(g.max_new_risk>=0.0 && risk_eff>g.max_new_risk+PL_EPS)
     {
      PlBlocked(res,PL_R_GUARD);
      res.phrase=PlGuardRoomPhrase(g,risk_eff,(r.lot>0.0)?risk_eff/r.lot:r.loss_per_lot,s.vol_step,acc.currency,acc.currency_digits);
      return;
     }
   //--- 4b. the guards and the margin guard again with the risk and the margin of THIS trade: a block stops it, a
   //--- confirmation that was not asked for at the press asks again
   {
    const int n_open=PlOrdersFor(split_hedge,in,plan,r,s.vol_min,s.vol_step);
    PlGuardOut lo; PlGuardRunAll(acc,risk_eff,r.margin_needed,n_open,(snap.kind==PL_KIND_MARKET)?n_open:0,lo);
    const string lph=(lo.verdict!=PL_OK)?PlGuardPhraseNow(lo,risk_eff,(r.lot>0.0)?risk_eff/r.lot:r.loss_per_lot,s.vol_step,acc.currency,acc.currency_digits):"";
    if(lo.verdict==PL_BLOCK)
      {
       PlBlocked(res,PL_R_GUARD);
       if(lph!="") res.phrase=lph;
       return;
      }
    if(lo.verdict==PL_CONFIRM && snap.verdict!=PL_CONFIRM)
      {
       res.status=PL_SS_RECONFIRM; res.new_lot=r.lot; res.reason=PL_R_GUARD; res.phrase=(lph!="")?lph:PLS_CONFIRM_AGAIN;
       return;
      }
   }
   //--- 5. (the broker distance of a pending entry, the SL and the TP is checked in the plan, by the recount of step 2)
   const bool buy=(plan.side==PL_SIDE_BUY);
   const bool pending=(plan.order_type!=ORDER_TYPE_BUY && plan.order_type!=ORDER_TYPE_SELL);
   //--- 6. netting: the opposite side would close or reverse the position, the same side changes its SL and TP
   if(!hedging && PositionSelect(snap.symbol))
     {
      const bool pbuy=((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY);
      if(pbuy!=buy) { PlBlocked(res,PL_R_NETTING_REVERSE); return; }
      res.net_add=true;
      if(!snap.netting_ack)
        { res.status=PL_SS_RECONFIRM; res.reason=PL_R_NETTING_ADD; res.new_lot=r.lot; res.phrase=PlReasonText(PL_R_NETTING_ADD); return; }
     }
   //--- 7. parts, lifetime, tag
   bool tp_on[PL_MAX_TP]; double share[PL_MAX_TP];
   for(int i=0;i<PL_MAX_TP;i++)
     {
      tp_on[i]=(in.tp[i].on && !in.no_tp && plan.tp[i]>0.0);
      share[i]=in.tp[i].share;
     }
   double lots[]; int tpi[]; string pnote;
   const int np=PlSplitOrders(split_hedge,r,s.vol_min,s.vol_step,tp_on,share,lots,tpi,pnote);
   if(!split_hedge && np>1) { PlBlocked(res,PL_R_SPLIT_NETTING); return; }     // defensive: only the dev switch onepos gets here
   if(np>PL_MAX_PARTS)
     { PlBlocked(res,PL_R_SPLIT_TOO_MANY); res.phrase=PLS_SPLIT_WOULD_NEED+(string)np+PLS_ORDERS_THE_LIMIT_IS+(string)PL_MAX_PARTS; return; }
   //--- last guard before the first order: the parts add up to the lot and each one is allowed by the broker
   {
    double sum=0.0; bool okp=(np>=1);
    for(int k=0;k<np && okp;k++)
      {
       sum+=lots[k];
       if(lots[k]>s.vol_max+PL_EPS || lots[k]<s.vol_min-PL_EPS) okp=false;
      }
    if(!okp || MathAbs(sum-r.lot)>s.vol_step*0.5) { PlBlocked(res,PL_R_LOT_ABOVE_MAX); return; }
   }
   if(np==1 && !split_hedge)
     {
      int lv[PL_MAX_TP]; int nl=0;
      for(int i=0;i<PL_MAX_TP;i++) if(tp_on[i]) { lv[nl]=i; nl++; }
      for(int j=0;j<nl-1;j++) { res.pt_price[j]=plan.tp[lv[j]]; res.pt_share[j]=share[lv[j]]; res.pt_n=j+1; }
     }
   ENUM_ORDER_TYPE_TIME ttype=ORDER_TIME_GTC; datetime exp=0; string enote="";
   datetime keep=0;
   if(pending && !PlExpiry(s,snap.expiry_mode,snap.expiry_hours,ttype,exp,enote,keep))
     { PlBlocked(res,PL_R_NONE); res.phrase=PlExpiryRefusal(s,snap.expiry_hours); return; }
   const string tag=PlMakeTag();
   string base=snap.comment;
   if(StringLen(base)>20) base=StringSubstr(base,0,20);
   int cands[]; PlFillCandidates(s,pending,cands);
   if(ArraySize(cands)==0) { PlBlocked(res,PL_R_NO_FILL_MODE); return; }
   //--- the phrase context
   g_ph_buy=buy; g_ph_kind=snap.kind; g_ph_digits=s.digits; g_ph_lotdg=PlStepDigits(s.vol_step);
   g_ph_planned=snap.risk_money; g_ph_no_sl=(plan.sl<=0.0); g_ph_cur=PlOwnCopy(acc.currency); g_ph_cd=acc.currency_digits; g_ph_sym=PlOwnCopy(s.name); g_ph_entry=plan.entry;
   res.tag=tag; res.parts_planned=np; res.vol_planned=r.lot;
   res.keep_until=keep; res.sl_user=plan.sl; res.dist_user=plan.dist;
   //--- the SL and TP always go to the broker in the order itself
   const double sl_broker=(plan.sl>0.0)?(buy?PlTickUp(plan.sl,s.tick_size,s.digits):PlTickDown(plan.sl,s.tick_size,s.digits)):0.0;
   res.note=pnote; if(enote!="") res.note=(res.note!="")?res.note+". "+enote:enote;
   g_rc_total_lot=r.lot; g_rc_total_risk=r.risk_money;
   //--- deviation: read only on Request and Instant execution; Market and Exchange execution ignore it, so it is no cap on slippage
   const ulong dev=(ulong)MathMax(1.0,MathRound(PL_PRICE_MOVE*plan.dist/s.point));
   string shortfall="";
   for(int k=0;k<np;k++)
     {
      //--- every market part after the first goes out on a fresh quote (the first uses the quote of the recount)
      if(!pending && k>0)
        {
         PlRefreshQuote(s); PlDevAdjustSym(s);
         if(s.bid<=0.0 || s.ask<=0.0) { res.status=PL_SS_PARTS_SHORT; PlSendPhrase(res,PLS_NO_QUOTE_REST); return; }
         if(snap.dist>0.0 && MathAbs((s.ask+s.bid)/2.0-snap.mid)>PL_PRICE_MOVE*snap.dist)
           { res.status=PL_SS_PARTS_SHORT; PlSendPhrase(res,PLS_MOVED_REST_NOT_SENT); return; }
        }
      MqlTradeRequest rq; ZeroMemory(rq);
      rq.symbol=snap.symbol; rq.volume=lots[k]; rq.magic=snap.magic;
      rq.type=(ENUM_ORDER_TYPE)plan.order_type;
      rq.sl=sl_broker;
      const double ptp=(tpi[k]>=0)?PlTickNearest(plan.tp[tpi[k]],s.tick_size,s.digits):0.0;
      rq.tp=ptp;
      res.part_lot[k]=lots[k];
      string cm=base;
      string part=tag+((np>1)?"/"+(string)(k+1):"");
      rq.comment=(cm!="")?cm+" "+part:part;
      if(!pending)
        {
         rq.action=TRADE_ACTION_DEAL; rq.price=PlTickNearest(buy?s.ask:s.bid,s.tick_size,s.digits); rq.deviation=dev;
        }
      else
        {
         rq.action=TRADE_ACTION_PENDING; rq.price=PlTickNearest(plan.entry,s.tick_size,s.digits);
         if(plan.order_type==ORDER_TYPE_BUY_STOP_LIMIT || plan.order_type==ORDER_TYPE_SELL_STOP_LIMIT)
            rq.stoplimit=PlTickNearest(plan.limit,s.tick_size,s.digits);
         rq.type_time=ttype; rq.expiration=exp;
        }
      //--- the context for the reconciliation, set before the send
      g_rc_kind=0; g_rc_symbol=PlOwnCopy(snap.symbol); g_rc_magic=snap.magic; g_rc_otype=(int)rq.type; g_rc_pending=pending;
      g_rc_match=part; g_rc_sent_cur=TimeCurrent(); g_rc_part_lot=lots[k];
#ifdef PL_DEV_LOG
      if(g_dev_tagoff) g_rc_match="";      // development: only the non-comment matches can find the order
#endif
      MqlTradeResult tr; uint rc=0; int err=0;
      PlAttempt at=PlTryRequest(rq,cands,tr,rc,err);
      res.retcode=rc; res.err=err;
      if(at==PL_AT_UNKNOWN)
        {
         g_rc_active=true; g_rc_started=GetTickCount64(); g_rc_res=res;
         res.status=PL_SS_UNKNOWN; res.phrase=PLS_CHECKING; g_rc_res=res;
         return;
        }
      if(at==PL_AT_OK || at==PL_AT_PARTIAL)
        {
         double vdone=(tr.volume>0.0)?tr.volume:lots[k];
         if(at==PL_AT_PARTIAL && tr.volume<=0.0) vdone=0.0;
         ulong id=pending?tr.order:PlDealPosition(tr.deal,tr.order);
         if(res.parts_sent<PL_MAX_PARTS) res.ids[res.parts_sent]=id;
         if(!pending && res.parts_sent<PL_MAX_PARTS) res.part_lot[res.parts_sent]=vdone;     // the record's vol0 is what filled, not what was planned
         res.parts_sent++;
         res.vol_done+=vdone;
         res.price_done=(tr.price>0.0)?tr.price:(pending?plan.entry:(buy?s.ask:s.bid));
         if(!pending) PlVerifySl(id,s,rq.sl,rq.tp,res.net_add,res.price_done,res);
         //--- the risk named in the phrase is worked out from the price the position really opened at
         double lpl_done=r.loss_per_lot;
         if(!pending && plan.sl>0.0 && plan.dist>PL_EPS && res.price_done>0.0)
            lpl_done=r.lpl_price*MathAbs(res.price_done-plan.sl)/plan.dist+r.comm_in_1lot+r.comm_out_1lot;
         res.risk_done+=vdone*lpl_done+((res.net_add && k==0)?r.net_risk:0.0);
         //--- an order that pays the broker minimum commission adds what the minimum is above its rate
         if(in.comm.min_money>PL_EPS)
            res.risk_done+=MathMax(0.0,in.comm.min_money-vdone*(r.comm_in_1lot+r.comm_out_1lot));     // netting add: the phrase names the risk of the whole position, as the confirmation did
         //--- deviation is no cap on Market execution: say so when the real open price made the risk higher than confirmed.
         //--- Two bases: the recount at the send, and the larger of the risk asked for and the risk shown on the CONFIRM button
         //--- (a lot rounded down shows less than asked; a move before the send and the fill can add up).
         if(!pending && plan.sl>0.0 && StringFind(res.note,PLS_SLIPPAGE)<0
            && (lpl_done>r.loss_per_lot*(1.0+PL_RISK_MOVE)+PL_EPS
                || (snap.risk_money>PL_EPS && res.risk_done>MathMax(snap.risk_money,r.risk_target)*(1.0+PL_RISK_MOVE)+PL_EPS)))
            res.note=(res.note!="")?res.note+". "+PLS_SLIPPAGE:PLS_SLIPPAGE;
         if(at==PL_AT_PARTIAL && vdone<lots[k]-PL_EPS)
           {
            res.status=(np==1)?PL_SS_PARTIAL:PL_SS_PARTS_SHORT;
            res.vol_planned=r.lot;
            PlSendPhrase(res,PLS_FILLED_ONLY_PART_OF_AN_ORDER);
            return;
           }
         //--- the SL correction of this part had no answer: its check owns the reconcile context now, a next part would overwrite it
         if(g_rc_active && k+1<np) { res.status=PL_SS_PARTS_SHORT; PlSendPhrase(res,PLS_SL_FIX_REST); return; }
         continue;
        }
      //--- refused
      shortfall=(rc==TRADE_RETCODE_INVALID_FILL)?PLS_NO_FILL_MODE:PlRetcodeText(rc,err);
      if(res.parts_sent==0) { res.status=PL_SS_REJECTED; res.phrase=shortfall; return; }
      res.status=PL_SS_PARTS_SHORT;
      PlSendPhrase(res,shortfall);
      return;
     }
   res.status=pending?PL_SS_PLACED:PL_SS_DONE;
   PlSendPhrase(res,"");
  }

//=================================================================================================
//  change, close, delete
//=================================================================================================
bool PlSimpleStart(const bool closing,PlAccount &acc,PlSymbol &s,const string sym,PlSendRes &res)
  {
   PlSendResReset(res);
   if(g_rc_active) { res.status=PL_SS_BLOCKED; res.phrase=PLS_BUSY; return false; }
   PlReadAccount(acc,false);
   PlDevAdjustAcct(acc);
   if(!PlReadSymbol(sym,s)) { PlBlocked(res,PL_R_NO_SYMBOL_DATA); return false; }
   PlDevAdjustSym(s);
   PlReason why;
   PlTradeGate(acc,s,closing,why);
   if(why!=PL_R_NONE) { PlBlocked(res,why); return false; }
   return true;
  }

void PlSimpleResult(const PlAttempt at,const uint rc,const int err,const ulong ticket,const int kind,
                    const double sl,const double tp,const double vol,const double tol,const string okphrase,PlSendRes &res)
  {
   res.retcode=rc; res.err=err;
   if(at==PL_AT_OK || at==PL_AT_PARTIAL) { res.status=PL_SS_DONE; res.phrase=okphrase; return; }
   if(at==PL_AT_UNKNOWN)
     {
      g_rc_kind=kind; g_rc_ticket=ticket; g_rc_sl=sl; g_rc_tp=tp; g_rc_vol=vol; g_rc_tol=tol;
      g_rc_active=true; g_rc_started=GetTickCount64();
      res.status=PL_SS_UNKNOWN; res.phrase=PLS_CHECKING; g_rc_res=res;
      return;
     }
   res.status=PL_SS_REJECTED; res.phrase=(rc==TRADE_RETCODE_INVALID_FILL)?PLS_NO_FILL_MODE:PlRetcodeText(rc,err);
  }

void PlSendModifyPos(const ulong pos_id,const double sl,const double tp,PlSendRes &res)
  {
   PlSendResReset(res);
   if(!PlFindPosition(pos_id)) { res.status=PL_SS_REJECTED; res.phrase=PlRetcodeText(10036); return; }
   const ulong tk=(ulong)PositionGetInteger(POSITION_TICKET);
   const string sym=PositionGetString(POSITION_SYMBOL);
   const bool pbuy=((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY);
   const double osl=PositionGetDouble(POSITION_SL), otp=PositionGetDouble(POSITION_TP);
   PlAccount acc; PlSymbol s;
   if(!PlSimpleStart(true,acc,s,sym,res)) return;
   const double cp=pbuy?s.bid:s.ask;
   const double frz=(double)s.freeze_level*s.point;
   //--- the values that go out, on the tick grid: an SL toward less risk, a TP to the nearest tick
   const double rsl=(sl>0.0)?(pbuy?PlTickUp(sl,s.tick_size,s.digits):PlTickDown(sl,s.tick_size,s.digits)):0.0;
   const double rtp=(tp>0.0)?PlTickNearest(tp,s.tick_size,s.digits):0.0;
   if(frz>0.0 && ((osl>0.0 && MathAbs(cp-osl)<=frz) || (otp>0.0 && MathAbs(cp-otp)<=frz)))
     { res.status=PL_SS_BLOCKED; res.phrase=PlRetcodeText(10029); return; }
   if(rsl>0.0)
     {
      const double d=pbuy?(cp-rsl):(rsl-cp);
      if(d<=PL_EPS || PlStopsTooClose(d,s.stops_level,s.point)) { res.status=PL_SS_BLOCKED; res.phrase=PlRetcodeText(10016); return; }
     }
   if(rtp>0.0)
     {
      const double d=pbuy?(rtp-cp):(cp-rtp);
      if(d<=PL_EPS || PlStopsTooClose(d,s.stops_level,s.point)) { res.status=PL_SS_BLOCKED; res.phrase=PlRetcodeText(10016); return; }
     }
   MqlTradeRequest rq; ZeroMemory(rq);
   rq.action=TRADE_ACTION_SLTP; rq.position=tk; rq.symbol=sym;
   rq.sl=rsl; rq.tp=rtp;
   int none[]; ArrayResize(none,0);
   MqlTradeResult tr; uint rc=0; int err=0;
   g_rc_symbol=PlOwnCopy(sym);
   PlAttempt at=PlTryRequest(rq,none,tr,rc,err);
   res.ids[0]=pos_id;
   PlSimpleResult(at,rc,err,pos_id,1,rq.sl,rq.tp,0.0,s.tick_size*0.5,PLS_SLTP_CHANGED,res);
  }

//--- volume>0: that volume (a rest below the minimum lot goes with it). part_pct>0: that percent of the volume of THIS moment (read
//--- here, not by the caller), never the whole position: a rest below the minimum lot refuses.
void PlSendClosePos(const ulong pos_id,const double volume,PlSendRes &res,const double part_pct=0.0)
  {
   PlSendResReset(res);
   if(!PlFindPosition(pos_id)) { res.status=PL_SS_REJECTED; res.phrase=PlRetcodeText(10036); return; }
   const ulong tk=(ulong)PositionGetInteger(POSITION_TICKET);
   const string sym=PositionGetString(POSITION_SYMBOL);
   const bool pbuy=((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY);
   const double pvol=PositionGetDouble(POSITION_VOLUME);
   const long pmagic=PositionGetInteger(POSITION_MAGIC);
   const double osl=PositionGetDouble(POSITION_SL), otp=PositionGetDouble(POSITION_TP);     // before PlSimpleStart: it changes the selection
   PlAccount acc; PlSymbol s;
   if(!PlSimpleStart(true,acc,s,sym,res)) return;
   double v=pvol;
   const double asked=(part_pct>0.0)?pvol*part_pct/100.0:volume;
   if(asked>0.0 && asked<pvol-PL_EPS)
     {
      v=PlFloorStep(asked,s.vol_step);
      if(v<s.vol_min-PL_EPS) { res.status=PL_SS_REJECTED; res.phrase=PLS_PART_BELOW_MIN; return; }     // never the whole position
      if(pvol-v<s.vol_min-PL_EPS)
        {
         if(part_pct>0.0) { res.status=PL_SS_REJECTED; res.phrase=PLS_PART_REST_MIN; return; }          // a percent never closes the whole position
         v=pvol;                                                                                         // a volume: only a rest below the minimum goes with it
        }
     }
   double want=v;                                            // what the caller asked for (the whole position or the part)
   if(s.vol_max>0.0 && v>s.vol_max+PL_EPS)                  // vol_max 0 means not reported: no cap, the server decides
     {
      //--- one capped close per press, never a loop of chunks: each chunk could lose its answer
      v=PlFloorStep(s.vol_max,s.vol_step);
      if(pvol-v<s.vol_min-PL_EPS) v=PlFloorStep(pvol-s.vol_min,s.vol_step);
      if(v<s.vol_min-PL_EPS) { res.status=PL_SS_REJECTED; res.phrase=PLS_PART_BELOW_MIN; return; }
     }
   int cands[]; PlFillCandidates(s,false,cands);
   if(ArraySize(cands)==0) { res.status=PL_SS_REJECTED; res.phrase=PlReasonText(PL_R_NO_FILL_MODE); return; }
   //--- no change inside the freeze level of the position's SL or TP
   const double cp=pbuy?s.bid:s.ask, frz=(double)s.freeze_level*s.point;
   if(frz>0.0 && ((osl>0.0 && MathAbs(cp-osl)<=frz) || (otp>0.0 && MathAbs(cp-otp)<=frz)))
     { res.status=PL_SS_BLOCKED; res.phrase=PlRetcodeText(10029); return; }
   MqlTradeRequest rq; ZeroMemory(rq);
   rq.action=TRADE_ACTION_DEAL; rq.position=tk; rq.symbol=sym; rq.volume=v; rq.magic=pmagic;
   rq.type=pbuy?ORDER_TYPE_SELL:ORDER_TYPE_BUY;
   rq.price=PlTickNearest(pbuy?s.bid:s.ask,s.tick_size,s.digits);
   rq.deviation=(ulong)MathMax(10.0,MathRound(3.0*(s.ask-s.bid)/s.point));
   rq.comment="Plainlines close";
#ifdef PL_DEV_LOG
   if(g_dev_closemagic0) rq.magic=0;
#endif
   MqlTradeResult tr; uint rc=0; int err=0;
   g_rc_symbol=PlOwnCopy(sym);
   PlAttempt at=PlTryRequest(rq,cands,tr,rc,err);
   res.ids[0]=pos_id; res.vol_planned=want; res.price_done=tr.price;
   if(at==PL_AT_OK || at==PL_AT_PARTIAL)
     {
      //--- the position volume is not read again: it may not be updated yet
      const double closed=(tr.volume>0.0)?tr.volume:((at==PL_AT_OK)?v:0.0);
      res.vol_done=closed; res.retcode=rc; res.err=err;
      const int ld=PlStepDigits(s.vol_step);
      if(closed<want-s.vol_step*0.5)
        {
         res.status=PL_SS_PARTIAL;
         res.phrase=(closed>0.0)?(PLS_CLOSED_WORD+" "+DoubleToString(closed,ld)+PLS_OF_SP+DoubleToString(want,ld)+" "+sym+PLS_REST_STILL_OPEN)
                                :(PLS_CLOSED_PART_OF+sym+PLS_REST_STILL_OPEN);
        }
      else { res.status=PL_SS_DONE; res.phrase=PLS_CLOSED_WORD+" "+sym+" "+DoubleToString(closed,ld); }
      return;
     }
   PlSimpleResult(at,rc,err,pos_id,2,0.0,0.0,pvol,0.0,"",res);
  }

void PlSendDeleteOrder(const ulong ticket,PlSendRes &res)
  {
   PlSendResReset(res);
   if(!OrderSelect(ticket)) { res.status=PL_SS_REJECTED; res.phrase=PLS_ORDER_GONE; return; }
   const string sym=OrderGetString(ORDER_SYMBOL);
   const double oprice=OrderGetDouble(ORDER_PRICE_OPEN);
   const ENUM_ORDER_TYPE oty=(ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);   // before PlSimpleStart: it changes the selection
   const bool obuy=(oty==ORDER_TYPE_BUY_LIMIT || oty==ORDER_TYPE_BUY_STOP || oty==ORDER_TYPE_BUY_STOP_LIMIT);
   PlAccount acc; PlSymbol s;
   if(!PlSimpleStart(true,acc,s,sym,res)) return;
   const double frz=(double)s.freeze_level*s.point;
   const double ref=obuy?s.ask:s.bid;
   if(frz>0.0 && MathAbs(ref-oprice)<=frz) { res.status=PL_SS_BLOCKED; res.phrase=PlRetcodeText(10029); return; }
   MqlTradeRequest rq; ZeroMemory(rq);
   rq.action=TRADE_ACTION_REMOVE; rq.order=ticket;
   int none[]; ArrayResize(none,0);
   MqlTradeResult tr; uint rc=0; int err=0;
   g_rc_symbol=PlOwnCopy(sym);
   PlAttempt at=PlTryRequest(rq,none,tr,rc,err);
   res.ids[0]=ticket;
   PlSimpleResult(at,rc,err,ticket,3,0.0,0.0,0.0,0.0,PLS_ORDER_DELETED,res);
  }

#endif
