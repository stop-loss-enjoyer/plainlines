// Required Notice: Copyright 2026 stop-loss-enjoyer
// Plainlines is source-available under the PolyForm Shield License 1.0.0.
//
// Managing a position by its ticket : breakeven, trailing, parts
// closed at the earlier TP levels (one order for several TPs), the lifetime of a pending order kept by
// the panel, and the buttons of the Positions block. Every request goes through SendOrderSafe.mqh
// (PlSendModifyPos, PlSendClosePos, PlSendDeleteOrder); nothing here sends by itself.
//
// One instance per terminal manages. Leader = lowest ChartID among the charts running this program whose instance may
// trade; an instance that may not trade sets the temporary global variable PL.noalgo.<ChartID>; it leads after one
// second in that place; no stored leader. The others only show. Each position has a record file Plainlines/pos_<id>.dat
// (the key is the POSITION_IDENTIFIER, which a pending order passes to its position by itself). No account number.
#property strict

#ifndef PL_TRADE_MANAGE_MQH
#define PL_TRADE_MANAGE_MQH

#define PL_REC_RETRY_MS  2000          // a failed request is tried again after this
#define PL_TRAIL_GAP_MS  2000          // a trailing stop is moved at most this often per ticket
#define PL_TRAIL_NOTE_MS 5000          // the status line names a trailing move at most this often, for all tickets together
#define PL_REC_FAILS     3             // refused requests of one action in a row before it is switched off for good
#define PL_REC_FAIL_MS   10000         // the wait after a refused request (the day's request budget on FTMO is 2000, SL/TP changes count)
#define PL_NOALGO_GV     "PL.noalgo."  // temporary global variable: the instance of this chart ID may NOT trade
#define PL_LEAD_SETTLE_MS 1000         // a new leader waits this long (four timer laps of 250 ms) so the old one has stopped

//--- how a record is written (PlRecSave)
#define PL_RW_NEW   0                  // the record is created (not in memory yet): everything is written
#define PL_RW_USER  1                  // a button of the panel: only the fields the user sets
#define PL_RW_MGR   2                  // the manager: only the fields it changes
#ifdef PL_DEV_LOG
#define PL_RW_ALL   3                  // everything from memory (the dev command setrec); not in the release build
#endif

//--- the phrase for the status (defined in Plainlines.mq5)
void PlManageNote(const string t,const int kind);
void PlManageNoteQuiet(const string t);
void PlOwnRefresh();

//=================================================================================================
//  the record of one position
//=================================================================================================
struct PlRec
  {
   ulong             id;
   string            symbol;
   int               ptype;            // 0 buy, 1 sell
   long              t_open_msc;       // 0 until the position exists (a pending order)
   long              magic;
   double            sl0;              // the SL at the open
   double            dist0;            // |entry - SL0|
   bool              be_on;
   double            be_r;
   bool              be_done;
   int               trail;            // 0 off, 2 pips (an old 1, ATR, is read as 2 with the distance 0)
   double            trail_val;        // trail distance in the SL field unit of the symbol; 0 means the distance of the initial SL (dist0)
   int               pt_n;             // parts closed at earlier TP levels (one order for several TPs)
   double            pt_price[2];
   double            pt_share[2];      // percent of vol0
   bool              pt_done[2];
   bool              pt_pend[2];       // a part was sent and the answer is not known yet (never sent twice)
   double            pt_vb[2];         // the volume of the position when that part was sent
   long              pt_t[2];          // server time of that send
   double            vol0;
   long              expire_at;        // server time; the panel deletes the pending order then (0 none)
   long              created;          // server time
   bool              be_off;           // the action was refused for good: not tried again (in the file: beo, tro, pto, exo)
   bool              trail_off;
   bool              pt_off;
   bool              exp_off;
   //--- runtime only
   long              last_tick_msc;
   ulong             next_try;
   ulong             last_trail;
   ulong             last_note;
   int               fails;            // refused requests of one action in a row
  };

PlRec     g_rec[];
ulong     g_t_recscan=0;
ulong     g_t_recgc=0;
ulong     g_born=0;
bool      g_lead_now=false;          // the last answer of PlLeadCheck (for the log and the dev commands)

string PlRecFile(const ulong id) { return PL_DIR+"\\pos_"+(string)id+".dat"; }

void PlRecInit(PlRec &r)
  {
   r.id=0; r.symbol=""; r.ptype=0; r.t_open_msc=0; r.magic=0; r.sl0=0.0; r.dist0=0.0;
   r.be_on=false; r.be_r=1.0; r.be_done=false; r.trail=0; r.trail_val=0.0;
   r.pt_n=0;
   for(int i=0;i<2;i++) { r.pt_price[i]=0.0; r.pt_share[i]=0.0; r.pt_done[i]=false; r.pt_pend[i]=false; r.pt_vb[i]=0.0; r.pt_t[i]=0; }
   r.vol0=0.0; r.expire_at=0; r.created=0;
   r.be_off=false; r.trail_off=false; r.pt_off=false; r.exp_off=false;
   r.last_tick_msc=0; r.next_try=0; r.last_trail=0; r.last_note=0; r.fails=0;
  }

int PlRecIndex(const ulong id)
  {
   for(int i=ArraySize(g_rec)-1;i>=0;i--) if(g_rec[i].id==id) return i;
   return -1;
  }

//--- the runtime part of a record (never in the file) goes from one copy to another
void PlRecCarryRuntime(const PlRec &from,PlRec &to)
  {
   to.last_tick_msc=from.last_tick_msc; to.next_try=from.next_try; to.last_trail=from.last_trail;
   to.last_note=from.last_note; to.fails=from.fails;
  }

//--- the whole record to its file (one write, the sum line makes a torn read visible)
bool PlRecWriteAll(const PlRec &r)
  {
   PlKvClear();
   PlKvSet("srv",AccountInfoString(ACCOUNT_SERVER));      // position ids are unique on one server; no account number
   PlKvSet("sym",r.symbol); PlKvSetI("ptype",r.ptype); PlKvSetI("t_open_msc",r.t_open_msc); PlKvSetI("magic",r.magic);
   PlKvSetD("sl0",r.sl0); PlKvSetD("dist0",r.dist0);
   PlKvSetB("be_on",r.be_on); PlKvSetD("be_r",r.be_r); PlKvSetB("be_done",r.be_done);
   PlKvSetI("trail",r.trail); PlKvSetD("trail_val",r.trail_val);
   PlKvSetI("pt_n",r.pt_n);
   for(int i=0;i<2;i++)
     {
      PlKvSetD("ptp"+(string)(i+1),r.pt_price[i]); PlKvSetD("pts"+(string)(i+1),r.pt_share[i]); PlKvSetB("ptd"+(string)(i+1),r.pt_done[i]);
      PlKvSetB("ptq"+(string)(i+1),r.pt_pend[i]); PlKvSetD("ptv"+(string)(i+1),r.pt_vb[i]); PlKvSetI("ptt"+(string)(i+1),r.pt_t[i]);
     }
   PlKvSetD("vol0",r.vol0); PlKvSetI("expire_at",r.expire_at); PlKvSetI("created",r.created);
   PlKvSetB("beo",r.be_off); PlKvSetB("tro",r.trail_off); PlKvSetB("pto",r.pt_off); PlKvSetB("exo",r.exp_off);
   return PlKvSave(PlRecFile(r.id));
  }

bool PlRecLoad(const ulong id,PlRec &r);
int  PlRecLive(PlRec &r);

//--- Writes the record to its file. Several charts write these files and each field has one owner:
//---  NEW   the record is created (not in memory yet): everything. A file of another server with the same id is overwritten.
//---  USER  a button of the panel: re-reads the file, takes over only be_on, be_r, be_done, be_off, trail, trail_val, trail_off, sl0, dist0
//---  MGR   the manager: re-reads the file, takes over only t_open_msc, vol0, expire_at, be_done, be_off, trail_off, pt_done[], pt_pend[],
//---        pt_vb[], pt_t[], pt_off, exp_off, and pt_n when it goes down (the TP parts of a grown position are switched off)
//---  (a dev build also has ALL: everything from memory, the command setrec)
//--- Fixed after the creation (NEW only): srv, sym, ptype, magic, created, pt_price[], pt_share[]. After USER and MGR the
//--- memory copy is the file as written, so it is fresh. An existing record is never written once it was deleted (memory or
//--- file): a late save would bring the file back from the dead. false: nothing was written.
bool PlRecSave(PlRec &r,const int how)
  {
#ifdef PL_DEV_LOG
   if(how==PL_RW_ALL) return PlRecWriteAll(r);
#endif
   if(how==PL_RW_NEW) return PlRecWriteAll(r);
   if(PlRecIndex(r.id)<0 || !FileIsExist(PlRecFile(r.id))) return false;
   PlRec d;
   if(!PlRecLoad(r.id,d)) return false;               // mid-write by another chart or damaged: not written, tried again later
   if(how==PL_RW_USER)
     {
      d.be_on=r.be_on; d.be_r=r.be_r; d.be_done=r.be_done; d.be_off=r.be_off;
      d.trail=r.trail; d.trail_val=r.trail_val; d.trail_off=r.trail_off;
      d.sl0=r.sl0; d.dist0=r.dist0;
     }
   else
     {
      d.t_open_msc=r.t_open_msc; d.vol0=r.vol0; d.expire_at=r.expire_at;
      d.be_done=r.be_done; d.be_off=r.be_off; d.trail_off=r.trail_off;
      for(int i=0;i<2;i++) { d.pt_done[i]=r.pt_done[i]; d.pt_pend[i]=r.pt_pend[i]; d.pt_vb[i]=r.pt_vb[i]; d.pt_t[i]=r.pt_t[i]; }
      d.pt_off=r.pt_off; d.exp_off=r.exp_off;
      if(r.pt_n<d.pt_n) d.pt_n=r.pt_n;
     }
   if(!PlRecWriteAll(d)) return false;
   PlRecCarryRuntime(r,d);
   r=d;
   return true;
  }

//--- reads a record; false when the file belongs to another server, is not readable or is not complete (the sum line:
//--- a read during another chart's write fails it). The record is judged by the position itself (PlRecLive: symbol, side
//--- and open time), so it needs no profile of the account.
bool PlRecLoad(const ulong id,PlRec &r)
  {
   if(!PlKvLoad(PlRecFile(id)) || !g_kv_valid) return false;
   const string fsrv=PlKvGet("srv","");
   if(fsrv!="" && fsrv!=AccountInfoString(ACCOUNT_SERVER)) return false;
   PlRecInit(r);
   r.id=id; r.symbol=PlKvGet("sym",""); r.ptype=(int)PlKvI("ptype",0); r.t_open_msc=PlKvI("t_open_msc",0); r.magic=PlKvI("magic",0);
   r.sl0=PlKvD("sl0",0.0); r.dist0=PlKvD("dist0",0.0);
   r.be_on=PlKvB("be_on",false); r.be_r=PlKvD("be_r",1.0); r.be_done=PlKvB("be_done",false);
   r.trail=(int)PlKvI("trail",0); r.trail_val=PlKvD("trail_val",0.0);
   if(r.trail==1) { r.trail=2; r.trail_val=0.0; }     // an ATR trail of the earlier version: pips, the distance of the initial SL
   r.pt_n=(int)PlClampD((double)PlKvI("pt_n",0),0,2);
   for(int i=0;i<2;i++)
     {
      r.pt_price[i]=PlKvD("ptp"+(string)(i+1),0.0); r.pt_share[i]=PlKvD("pts"+(string)(i+1),0.0); r.pt_done[i]=PlKvB("ptd"+(string)(i+1),false);
      r.pt_pend[i]=PlKvB("ptq"+(string)(i+1),false); r.pt_vb[i]=PlKvD("ptv"+(string)(i+1),0.0); r.pt_t[i]=PlKvI("ptt"+(string)(i+1),0);
     }
   r.vol0=PlKvD("vol0",0.0); r.expire_at=PlKvI("expire_at",0); r.created=PlKvI("created",0);
   r.be_off=PlKvB("beo",false); r.trail_off=PlKvB("tro",false); r.pt_off=PlKvB("pto",false); r.exp_off=PlKvB("exo",false);
   return (r.symbol!="");
  }

//--- the memory copy of record k is made equal to its file (the runtime part stays). false: the file cannot be read now.
bool PlRecFresh(const int k)
  {
   if(k<0 || k>=ArraySize(g_rec)) return false;
   PlRec d;
   if(!PlRecLoad(g_rec[k].id,d)) return false;
   PlRecCarryRuntime(g_rec[k],d);
   g_rec[k]=d;
   return true;
  }

void PlRecDelete(const ulong id)
  {
   FileDelete(PlRecFile(id));
   const int k=PlRecIndex(id);
   if(k<0) return;
   const int n=ArraySize(g_rec);
   for(int i=k;i<n-1;i++) g_rec[i]=g_rec[i+1];
   ArrayResize(g_rec,n-1);
   PlOwnRefresh();                  // the rows of the panel point into g_rec by index
  }

//--- every record file of this account into memory (the runtime parts of known records stay; the off flags are in the file)
void PlRecScan()
  {
   string names[];
   ArrayResize(names,0);
   string nm;
   long h=FileFindFirst(PL_DIR+"\\pos_*.dat",nm);
   if(h!=INVALID_HANDLE)
     {
      do { const int n=ArraySize(names); ArrayResize(names,n+1); names[n]=nm; }
      while(FileFindNext(h,nm));
      FileFindClose(h);
     }
   PlRec fresh[];
   ArrayResize(fresh,0);
   for(int i=0;i<ArraySize(names);i++)
     {
      string s=names[i];
      if(StringLen(s)<9) continue;
      const string idtxt=StringSubstr(s,4,StringLen(s)-8);
      const ulong id=(ulong)StringToInteger(idtxt);
      if(id==0 || (string)id!=idtxt) continue;
      PlRec r;
      const int old=PlRecIndex(id);
      if(!PlRecLoad(id,r))
        {
         //--- unreadable now (another chart is writing it): a record already in memory stays as it is; only an id never loaded is skipped
         if(old>=0) { const int q=ArraySize(fresh); ArrayResize(fresh,q+1); fresh[q]=g_rec[old]; }
         continue;
        }
      //--- a record whose id is an open position but whose symbol, side or open time are not that position's is a dead one: a netting
      //--- position that a deal of the other side turned over (DEAL_ENTRY_INOUT) keeps its id, and the break-even, the trailing and
      //--- the TP parts planned for the old side would show in the panel as active and never be applied. The file goes, the new side starts clean.
      if(PlFindPosition(id) && PlRecLive(r)==0)
        {
         FileDelete(PlRecFile(id));
         PLDBG("MANAGE record "+(string)id+" dropped: the position is no longer the one it was made for");
         continue;
        }
      if(old>=0) PlRecCarryRuntime(g_rec[old],r);
      const int k=ArraySize(fresh);
      ArrayResize(fresh,k+1); fresh[k]=r;
     }
   ArrayResize(g_rec,ArraySize(fresh));
   for(int i=0;i<ArraySize(fresh);i++) g_rec[i]=fresh[i];
   PlOwnRefresh();                  // the order in g_rec may have changed
  }

//=================================================================================================
//  the leader
//=================================================================================================
ulong     g_lead_since=0;            // when this chart became the lowest able one (0: it is not)
PlReason  g_lead_why=PL_R_NONE;      // why this instance may not trade (PL_R_NONE: it may)
ulong     g_t_paused=0;              // the last "positions not managed" note

//--- Leader = lowest ChartID among the charts running this program whose instance may trade. MQL_TRADE_ALLOWED is per
//--- program instance and cannot be read from another chart; the only shared state is the temporary global
//--- variable PL.noalgo.<ChartID>, which exists while that instance may NOT trade (it vanishes when the terminal closes).
//--- No heartbeat: a chart that no longer runs the program is not in the list, so a flag left behind is ignored.
//--- Returns 0 when no chart can trade; there is no fallback.
long PlLeaderId()
  {
   const string prog=MQLInfoString(MQL_PROGRAM_NAME);
   long best=0;
   long id=ChartFirst();
   while(id>=0)
     {
      if(ChartGetString(id,CHART_EXPERT_NAME)==prog && !GlobalVariableCheck(PL_NOALGO_GV+(string)id) && (best==0 || id<best)) best=id;
      id=ChartNext(id);
     }
   return best;
  }

//--- true when this instance manages. Called every timer lap. Leader = lowest ChartID among the charts running this program
//--- whose instance may trade; an instance that may not trade sets the temporary global variable PL.noalgo.<ChartID>; it
//--- leads after one second in that place; no stored leader. The wait means an old leader sees the change on its next lap
//--- and stops before the new one starts: two leaders never act in the same moment. The tester chart always manages its own.
bool PlLeadCheck()
  {
   bool lead=true;
   if(!MQLInfoInteger(MQL_TESTER))
     {
      PlAccount a;
      PlReadAccount(a,false);
      PlDevAdjustAcct(a);
      g_lead_why=PlRightsReason(a);
      const string me=PL_NOALGO_GV+(string)ChartID();
      if(g_lead_why!=PL_R_NONE) { if(!GlobalVariableCheck(me)) GlobalVariableTemp(me); }
      else if(GlobalVariableCheck(me)) GlobalVariableDel(me);
      const ulong now=GetTickCount64();
      if(PlLeaderId()!=ChartID()) g_lead_since=0;
      else if(g_lead_since==0) g_lead_since=now;
      lead=(g_lead_since!=0 && now-g_lead_since>=PL_LEAD_SETTLE_MS);
     }
   if(lead!=g_lead_now) { PLDBG(lead?"LEAD this chart manages now":"LEAD this chart does not manage now"); }
   //--- a chart that starts to manage counts every trailing stop as just moved: the old leader or this chart before a restart
   //--- may have moved it a moment ago, and that time lives only in the memory of the instance that moved it
   if(lead && !g_lead_now) { const ulong t=GetTickCount64(); for(int i=0;i<ArraySize(g_rec);i++) g_rec[i].last_trail=t; }
   g_lead_now=lead;
   return lead;
  }

//=================================================================================================
//  the list of positions and pending orders of Plainlines (every instance builds it, for the panel)
//=================================================================================================
struct PlOwn
  {
   bool              pending;
   ulong             id;            // POSITION_IDENTIFIER or the order ticket
   string            sym;
   int               type;          // position: 0 buy 1 sell; order: ENUM_ORDER_TYPE
   bool              buy;
   double            vol;
   double            open;          // price of the position, or the entry of the order
   double            lim;           // the limit price of a Stop-Limit order, else 0
   double            sl;
   double            tp;
   double            pl;            // profit + swap
   datetime          expire;        // the order's expiration or the panel's (0 none)
   int               rec;           // index in g_rec or -1
   double            be;            // a position: its breakeven SL (PlBreakevenSl, commission and swap in), 0 when not known yet
   bool              be_safe;       // a position: its SL is set and closing at it gives zero or more by the open risk measure (PlPlAtSl): the BE button hides
  };

PlOwn   g_own[];
double  g_own_pl=0.0;
int     g_own_pos=0;
int     g_own_ord=0;
string  g_own_sig="";

bool PlOwnMine(const long magic,const ulong id)
  {
   if(magic==g_cfg.magic) return true;
   return (PlRecIndex(id)>=0);
  }

void PlOwnRefresh()
  {
   ArrayResize(g_own,0);
   g_own_pl=0.0; g_own_pos=0; g_own_ord=0;
   const int np=PositionsTotal();
   for(int i=0;i<np;i++)
     {
      ulong tk=PositionGetTicket(i);
      if(tk==0) continue;
      const ulong id=(ulong)PositionGetInteger(POSITION_IDENTIFIER);
      if(!PlOwnMine(PositionGetInteger(POSITION_MAGIC),id)) continue;
      PlOwn o;
      o.pending=false; o.id=id; o.sym=PositionGetString(POSITION_SYMBOL);
      o.type=(int)PositionGetInteger(POSITION_TYPE); o.buy=(o.type==POSITION_TYPE_BUY);
      o.vol=PositionGetDouble(POSITION_VOLUME); o.open=PositionGetDouble(POSITION_PRICE_OPEN);
      o.sl=PositionGetDouble(POSITION_SL); o.tp=PositionGetDouble(POSITION_TP);
      const double swp=PositionGetDouble(POSITION_SWAP);
      o.pl=PositionGetDouble(POSITION_PROFIT)+swp;
      o.expire=0; o.rec=PlRecIndex(id); o.lim=0.0;
      //--- the BE now button: the level it aims at, and whether the SL stands safe already by the measure of the open risk line.
      //--- All of it from the position itself (no record needed); every PositionGet* is read above, the commission reads below may select another position
      o.be=PlBreakevenSl(o.sym,o.buy,o.open,o.vol,swp,id,false);
      double pls=0.0;
      o.be_safe=(o.sl>0.0 && PlPlAtSl(o.buy,o.sym,o.vol,o.open,o.sl,swp,id,pls) && pls>=0.0);
      g_own_pl+=o.pl; g_own_pos++;
      const int k=ArraySize(g_own);
      ArrayResize(g_own,k+1); g_own[k]=o;
     }
   const int no=OrdersTotal();
   for(int i=0;i<no;i++)
     {
      ulong tk=OrderGetTicket(i);
      if(tk==0) continue;
      if(!PlOwnMine(OrderGetInteger(ORDER_MAGIC),tk)) continue;
      PlOwn o;
      const ENUM_ORDER_TYPE ot=(ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      //--- a market order that is being executed shows in the list for a moment: it is not a pending order
      if(ot==ORDER_TYPE_BUY || ot==ORDER_TYPE_SELL || ot==ORDER_TYPE_CLOSE_BY) continue;
      o.pending=true; o.id=tk; o.sym=OrderGetString(ORDER_SYMBOL); o.type=(int)ot;
      o.buy=(ot==ORDER_TYPE_BUY_LIMIT || ot==ORDER_TYPE_BUY_STOP || ot==ORDER_TYPE_BUY_STOP_LIMIT);
      o.vol=OrderGetDouble(ORDER_VOLUME_CURRENT); o.open=OrderGetDouble(ORDER_PRICE_OPEN);
      o.lim=(ot==ORDER_TYPE_BUY_STOP_LIMIT || ot==ORDER_TYPE_SELL_STOP_LIMIT)?OrderGetDouble(ORDER_PRICE_STOPLIMIT):0.0;
      o.sl=OrderGetDouble(ORDER_SL); o.tp=OrderGetDouble(ORDER_TP); o.pl=0.0;
      o.expire=(datetime)OrderGetInteger(ORDER_TIME_EXPIRATION);
      o.rec=PlRecIndex(tk); o.be=0.0; o.be_safe=false;
      if(o.rec>=0 && g_rec[o.rec].expire_at>0) o.expire=(datetime)g_rec[o.rec].expire_at;
      g_own_ord++;
      const int k=ArraySize(g_own);
      ArrayResize(g_own,k+1); g_own[k]=o;
     }
   g_own_sig=(string)g_own_pos+"|"+(string)g_own_ord+"|"+DoubleToString(g_own_pl,2);
  }

//--- the row of g_own with this id (a position id or an order ticket), -1 when it is gone
int PlOwnFind(const ulong id)
  {
   for(int i=ArraySize(g_own)-1;i>=0;i--) if(g_own[i].id==id) return i;
   return -1;
  }

//=================================================================================================
//  helpers on a symbol
//=================================================================================================
double PlTickOf(const string sym) { return SymbolInfoDouble(sym,SYMBOL_TRADE_TICK_SIZE); }
int    PlDigitsOf(const string sym) { return (int)SymbolInfoInteger(sym,SYMBOL_DIGITS); }

double PlPipOf(const string sym)
  {
   return PlPipFrom(SymbolInfoDouble(sym,SYMBOL_POINT),PlDigitsOf(sym),(ENUM_SYMBOL_CALC_MODE)SymbolInfoInteger(sym,SYMBOL_TRADE_CALC_MODE));
  }

//--- a new SL must keep StopsLevel from the price; no change inside the freeze level of the current SL or TP
bool PlSlAllowed(const string sym,const bool buy,const double px,const double newsl,const double cursl,const double curtp)
  {
   const double pt=SymbolInfoDouble(sym,SYMBOL_POINT);
   const double frz=(double)SymbolInfoInteger(sym,SYMBOL_TRADE_FREEZE_LEVEL)*pt;
   const double d=buy?(px-newsl):(newsl-px);
   if(d<=PL_EPS || PlStopsTooClose(d,(int)SymbolInfoInteger(sym,SYMBOL_TRADE_STOPS_LEVEL),pt)) return false;
   if(frz>0.0 && ((cursl>0.0 && MathAbs(px-cursl)<=frz) || (curtp>0.0 && MathAbs(px-curtp)<=frz))) return false;
   return true;
  }

//--- 0.0: not known yet (the entry deal is not in the history, or no tick size, or the money cannot be valued); the caller waits.
//--- The SL of a breakeven. It starts at the entry plus the commission paid in and still to pay out, in ticks rounded up, plus the
//--- negative swap, plus one tick, then goes on tick by tick toward the profit until the money at that SL is zero or more by the
//--- measure of the open risk line (PlPlAtSl), so a click on BE and the line "Open risk" never disagree. It never goes back
//--- toward the loss. A position needs no record: the arguments are the position itself.
#define PL_BE_STEPS 12             // rounds of the search for the level; each round moves by the whole shortfall
double PlBreakevenSl(const string sym,const bool buy,const double open,const double vol,const double swap,const ulong id,const bool log=true)
  {
   const double tk=PlTickOf(sym);
   const int dg=PlDigitsOf(sym);
   if(tk<=0.0 || vol<=0.0) return 0.0;
   //--- money of one tick of one lot by the terminal's own profit (100 ticks, then per tick): a server that publishes the tick value per
   //--- unit of the contract (XAUUSD on FundingPips, 19.10.2026) would make every step below 100 times too long. The tick value only if
   //--- that cannot be valued
   double tv=SymbolInfoDouble(sym,SYMBOL_TRADE_TICK_VALUE_PROFIT), p100=0.0;
   if(OrderCalcProfit(buy?ORDER_TYPE_BUY:ORDER_TYPE_SELL,sym,1.0,open,buy?open+100.0*tk:open-100.0*tk,p100) && p100>0.0) tv=p100/100.0;
   double ticks=1.0;
   bool known=false;
   const double cpl=PlPosCommPerLot(id,known);
   if(!known) return 0.0;                         // the entry deal is not in the history yet (the commission is charged at the entry on some brokers): wait, never guess
   const double cexit=PlExitCommPerLot(sym,cpl);
   const double cround=cpl+cexit;
   if(cround>0.0 && tv>0.0) ticks+=MathCeil(cround/tv-1e-9);
   //--- a negative swap already paid moves the breakeven further (read by the caller, while its position was selected: the commission rule above may select another)
   if(swap<0.0 && tv>0.0 && vol>0.0) ticks+=MathCeil(-swap/vol/tv-1e-9);
   const double off=ticks*tk;
   double lv=buy?PlTickUp(open+off,tk,dg):PlTickDown(open-off,tk,dg);     // away from the loss, on the grid: an averaged netting open may sit off it
   //--- the exact test: the money at this level by the one measure; short of zero, move by the shortfall in ticks (per tick from tick value, else one tick)
   double pl=0.0;
   int rounds=0;
   bool ok=false;
   for(;rounds<PL_BE_STEPS;rounds++)
     {
      const bool val=PlPlAtSl(buy,sym,vol,open,lv,swap,id,pl);              // not valued: a move of under a cent on a tiny lot, or no conversion; one tick on, and a level never valued stays unknown
      if(val && pl>=0.0) { ok=true; break; }
      const double per=(tv>0.0)?tv*vol:0.0;                                 // money of one tick of the whole position
      const double n=(val && per>0.0)?MathMax(1.0,MathCeil(-pl/per-1e-9)):((per>0.0)?MathMax(1.0,MathCeil(0.01/per-1e-9)):1.0);     // not valued: on by the ticks worth a cent, then the shortfall is known
      lv=buy?PlTickUp(lv+n*tk,tk,dg):PlTickDown(lv-n*tk,tk,dg);
     }
   if(!ok) lv=0.0;                                // not found in the rounds: unknown, never a guess
   if(log) { PLDBG("BEDBG "+sym+" in_paid_lot="+DoubleToString(cpl,4)+" exit_per_lot="+DoubleToString(cexit,4)+" src="+PlExitCommSrcDev(sym)+" round="+DoubleToString(cround,4)
         +" swap="+DoubleToString(swap,2)+" tick_value="+DoubleToString(tv,5)+" ticks="+DoubleToString(ticks,0)+" off="+DoubleToString(off,PlDigitsOf(sym))
         +" rounds="+(string)rounds+" level="+DoubleToString(lv,dg)+" pl_at_level="+DoubleToString(pl,2)); }
   return lv;
  }

//=================================================================================================
//  results of the requests of the manager
//=================================================================================================
//--- By the status of the answer only, no lists of codes (a persistent refusal is bounded by PlRecTried, not guessed at):
//--- 0 done; 3 unknown (reconciling); 1 progress or never sent (a part of a close was done, or the gate, a busy check, the local
//--- stops or freeze level stopped it): try again later; 2 sent and refused: counted against the action.
int PlManageOutcome(const PlSendRes &res)
  {
   if(res.status==PL_SS_DONE) return 0;
   if(res.status==PL_SS_UNKNOWN) return 3;
   if(res.status==PL_SS_PARTIAL) return 1;
   if(res.status==PL_SS_BLOCKED) return 1;
   return 2;
  }

//--- what a try did to the record k: done clears the count; progress or never sent waits (a position then waits for a new
//--- tick); unknown waits and takes the next tick again; a refusal counts and waits longer. true: the action was refused
//--- PL_REC_FAILS times in a row, the caller switches it off (and says so).
bool PlRecTried(const int k,const int oc,const ulong now)
  {
   if(k<0 || k>=ArraySize(g_rec)) return false;
   if(oc==0) { g_rec[k].fails=0; return false; }
   if(oc==1) { g_rec[k].next_try=now+PL_REC_RETRY_MS; return false; }
   if(oc==3) { g_rec[k].next_try=now+PL_REC_RETRY_MS; g_rec[k].last_tick_msc=0; return false; }
   g_rec[k].fails++;
   g_rec[k].next_try=now+PL_REC_FAIL_MS;
   if(g_rec[k].fails>=PL_REC_FAILS) { g_rec[k].fails=0; return true; }
   return false;
  }

//--- "BE: SL to 1.12345", "Trail: SL to 1.12345"; a position of another chart's symbol names it, as a close result does
ulong g_trail_note_at=0;
string PlSlMoveText(const string head,const string sym,const double sl,const int digits)
  {
   string t=head+DoubleToString(sl,digits);
   if(sym!="" && sym!=_Symbol) t=sym+": "+t;
   return t;
  }

void PlRecNote(PlRec &r,const string t,const int kind)
  {
   const ulong now=GetTickCount64();
   if(r.last_note!=0 && now-r.last_note<60000) return;
   r.last_note=now;
   PlManageNote(t,kind);
  }

//=================================================================================================
//  one record, one pass
//=================================================================================================
//--- the position of a record is selected when this returns 1; 2: the pending order is selected; 0: neither
int PlRecLive(PlRec &r)
  {
   if(PlFindPosition(r.id))
     {
      if(PositionGetString(POSITION_SYMBOL)!=r.symbol) return 0;
      if((int)PositionGetInteger(POSITION_TYPE)!=r.ptype) return 0;
      const long tm=PositionGetInteger(POSITION_TIME_MSC);
      if(r.t_open_msc!=0 && tm!=r.t_open_msc) return 0;
      return 1;
     }
   if(OrderSelect(r.id)) return 2;
   return 0;
  }

//--- One pass over one record. true: a request was sent (PlSend* was called, whatever the answer): the caller sends at most
//--- one request per lap and looks again at the leadership before the next.
bool PlRecManage(const int idx)
  {
   if(idx<0 || idx>=ArraySize(g_rec)) return false;
   const ulong now=GetTickCount64();
   const ulong id=g_rec[idx].id;
   const int live=PlRecLive(g_rec[idx]);
   if(live==0) return false;
   if(live==2)
     {
      //--- a pending order: only its lifetime. Nothing is sent while the session of its symbol is closed (it would only answer 10018).
      if(g_rec[idx].expire_at>0 && !g_rec[idx].exp_off && now>=g_rec[idx].next_try && (long)TimeTradeServer()>=g_rec[idx].expire_at)
        {
         const string osym=g_rec[idx].symbol;
         if(!PlSessionOpen(osym,TimeTradeServer())) return false;
         PlSendRes res;
         PlSendDeleteOrder(id,res);
         const int oc=PlManageOutcome(res);
         PLDBG("MANAGE expire order "+(string)id+" -> "+res.phrase+" oc="+(string)oc);
         const int k=PlRecIndex(id);
         if(k<0) return true;
         if(oc==0) { PlManageNote(PLS_ORDER_EXPIRED,1); PlRecDelete(id); }
         else if(PlRecTried(k,oc,now))
           {
            g_rec[k].exp_off=true;
            PlRecSave(g_rec[k],PL_RW_MGR);
            PlManageNote(PLS_OFF_EXP+osym+": "+res.phrase,2);
           }
         return true;
        }
      return false;
     }
   //--- a position. The record learns the open time when the pending order has just filled.
   if(g_rec[idx].t_open_msc==0)
     {
      g_rec[idx].t_open_msc=PositionGetInteger(POSITION_TIME_MSC);
      g_rec[idx].expire_at=0;
      if(g_rec[idx].vol0<=0.0) g_rec[idx].vol0=PositionGetDouble(POSITION_VOLUME);
      PlRecSave(g_rec[idx],PL_RW_MGR);
     }
   //--- the position grew (a panel add, a manual add, a pending order merged into it): the TP parts were planned for the
   //--- volume of vol0, so they are off. The volume is compared with what the done parts leave (PlPosGrew), so an add made
   //--- after a part has closed is seen too, not only one that takes the total above vol0. This is the only guard of an
   //--- existing record's TP parts on a netting account.
   if(g_rec[idx].pt_n>0 && g_rec[idx].vol0>0.0)
     {
      const double vs0=SymbolInfoDouble(g_rec[idx].symbol,SYMBOL_VOLUME_STEP), vm0=SymbolInfoDouble(g_rec[idx].symbol,SYMBOL_VOLUME_MIN);
      if(PlPosGrew(PositionGetDouble(POSITION_VOLUME),g_rec[idx].vol0,g_rec[idx].pt_share,g_rec[idx].pt_done,g_rec[idx].pt_n,vm0,vs0))
        {
         g_rec[idx].pt_n=0;
         PlRecSave(g_rec[idx],PL_RW_MGR);
         PlManageNote(PLS_POS_GREW+": "+g_rec[idx].symbol,2);
        }
     }
   if(now<g_rec[idx].next_try) return false;
   const string sym=PlOwnCopy(g_rec[idx].symbol);
   //--- the tick first: most timer rounds have no new one, and the session (up to 16 terminal calls) is then not looked at.
   //--- A tick that came in a closed session is marked seen and passed over; the next one after the opening is acted on.
   MqlTick tk;
   if(!SymbolInfoTick(sym,tk)) return false;
   if(tk.time_msc==g_rec[idx].last_tick_msc) return false;
   g_rec[idx].last_tick_msc=tk.time_msc;
   if(!PlSessionOpen(sym,TimeTradeServer())) return false;       // nothing is sent into a closed session
   const bool buy=(g_rec[idx].ptype==0);
   const double px=buy?tk.bid:tk.ask;               // the price a close would get
   const double open=PositionGetDouble(POSITION_PRICE_OPEN);
   const double cursl=PositionGetDouble(POSITION_SL), curtp=PositionGetDouble(POSITION_TP);
   const double vol=PositionGetDouble(POSITION_VOLUME);
   const double tick=PlTickOf(sym);
   const int dg=PlDigitsOf(sym);
   if(px<=0.0 || tick<=0.0) return false;
   //--- 1. parts closed at the earlier TP levels. A part is written into the record as sent BEFORE the send; it is
   //--- never sent twice. The size is what brings the volume down to what the levels up to this one leave.
   if(!g_rec[idx].pt_off)
     {
      for(int j=0;j<g_rec[idx].pt_n && j<2;j++)
        {
         if(!g_rec[idx].pt_pend[j]) continue;
         //--- the answer of an earlier send was lost: judged by the volume after the reconciliation (30 s) is over
         if((long)TimeTradeServer()-g_rec[idx].pt_t[j]<PL_RECON_MS/1000+5) return false;
         //--- done when the volume is down to what this level leaves (not merely lower than before: a partial fill is not done)
         double cumj=0.0;
         for(int q=0;q<=j;q++) cumj+=g_rec[idx].pt_share[q];
         const double tgt=g_rec[idx].vol0*MathMax(0.0,100.0-cumj)/100.0;
         const double vs=SymbolInfoDouble(sym,SYMBOL_VOLUME_STEP);
         if(vol<=tgt+MathMax(vs*0.5,PL_EPS)) g_rec[idx].pt_done[j]=true;
         g_rec[idx].pt_pend[j]=false;
         PlRecSave(g_rec[idx],PL_RW_MGR);
         PLDBG("MANAGE partial TP"+(string)(j+1)+" judged by the volume: done="+(string)g_rec[idx].pt_done[j]);
         return false;
        }
      for(int j=0;j<g_rec[idx].pt_n && j<2;j++)
        {
         if(g_rec[idx].pt_done[j] || g_rec[idx].pt_price[j]<=0.0) continue;
         if(!(buy?(px>=g_rec[idx].pt_price[j]-PL_EPS):(px<=g_rec[idx].pt_price[j]+PL_EPS))) continue;
         double cum=0.0;
         for(int q=0;q<=j;q++) cum+=g_rec[idx].pt_share[q];
         const double target=g_rec[idx].vol0*MathMax(0.0,100.0-cum)/100.0;       // what stays after this level
         const double vstep=SymbolInfoDouble(sym,SYMBOL_VOLUME_STEP), vmin=SymbolInfoDouble(sym,SYMBOL_VOLUME_MIN);
         const double part=(vstep>0.0)?PlFloorStep(vol-target,vstep):(vol-target);
         if(part<vmin-PL_EPS)
           {
            //--- nothing to close (done already, or the part is below the minimum lot): the level counts as done
            if(vol-target>PL_EPS) PlRecNote(g_rec[idx],PLS_TP+(string)(j+1)+PLS_TP_PART_BELOW_MIN,2);     // something should close but is below the minimum lot: say so
            g_rec[idx].pt_done[j]=true; PlRecSave(g_rec[idx],PL_RW_MGR);
            PLDBG("MANAGE partial TP"+(string)(j+1)+" "+(string)id+" nothing to close (part "+DoubleToString(vol-target,4)+")");
            return false;
           }
         //--- the file is the truth: another chart may have marked this part sent (or switched the parts off) since the last scan.
         //--- A part that is not on disk as sent is never sent.
         if(!PlRecFresh(idx) || g_rec[idx].pt_done[j] || g_rec[idx].pt_pend[j] || g_rec[idx].pt_off) return false;
         g_rec[idx].pt_pend[j]=true; g_rec[idx].pt_vb[j]=vol; g_rec[idx].pt_t[j]=(long)TimeTradeServer();
         if(!PlRecSave(g_rec[idx],PL_RW_MGR)) { PlRecFresh(idx); return false; }
         PlSendRes res;
         PlSendClosePos(id,part,res);
         const int oc=PlManageOutcome(res);
         PLDBG("MANAGE partial TP"+(string)(j+1)+" "+(string)id+" vol="+DoubleToString(part,3)+" -> "+res.phrase+" oc="+(string)oc);
         const int k=PlRecIndex(id);
         if(k<0) return true;
         if(oc==0) { g_rec[k].pt_done[j]=true; g_rec[k].pt_pend[j]=false; PlRecTried(k,0,now); PlRecSave(g_rec[k],PL_RW_MGR); PlManageNote(PLS_TP+(string)(j+1)+": "+res.phrase,1); }
         else if(oc==3) PlRecTried(k,3,now);                      // stays marked as sent: judged later
         else
           {
            g_rec[k].pt_pend[j]=false;
            const bool giveup=PlRecTried(k,oc,now);
            if(giveup) g_rec[k].pt_off=true;
            PlRecSave(g_rec[k],PL_RW_MGR);
            if(giveup) PlManageNote(PLS_OFF_PT+sym+": "+res.phrase,2);
           }
         return true;
        }
     }
   //--- 2. breakeven and trailing: both start when the price is be_r times the risk distance in profit
   const double moved=buy?(px-open):(open-px);
   const double trig=g_rec[idx].be_r*g_rec[idx].dist0;
   if(g_rec[idx].dist0<=0.0 || moved<trig-PL_EPS) return false;
   const double curstop=cursl;                      // the stop that is moved
   if(g_rec[idx].be_on && !g_rec[idx].be_done && !g_rec[idx].be_off)
     {
      const double nsl=PlBreakevenSl(sym,buy,open,vol,PositionGetDouble(POSITION_SWAP),id);
      if(nsl<=0.0) return false;                    // the entry deal is not known yet: wait for the next tick, be_done stays false
      const bool better=(curstop<=0.0) || (buy?(nsl>curstop+tick*0.999):(nsl<curstop-tick*0.999));
      if(!better) { g_rec[idx].be_done=true; PlRecSave(g_rec[idx],PL_RW_MGR); }
      else if(PlSlAllowed(sym,buy,px,nsl,cursl,curtp))
        {
         PlSendRes res;
         PlSendModifyPos(id,nsl,curtp,res);
         const int oc=PlManageOutcome(res);
         PLDBG("MANAGE breakeven "+(string)id+" sl="+DoubleToString(nsl,dg)+" -> "+res.phrase+" oc="+(string)oc);
         const int k=PlRecIndex(id);
         if(k<0) return true;
         if(oc==0) { g_rec[k].be_done=true; g_rec[k].last_trail=now; PlRecTried(k,0,now); PlRecSave(g_rec[k],PL_RW_MGR); PlManageNote(PlSlMoveText(PLS_BE_SL_TO,sym,nsl,dg),1); }   // the trailing waits its gap after the breakeven too
         else if(PlRecTried(k,oc,now))
           {
            g_rec[k].be_off=true;
            PlRecSave(g_rec[k],PL_RW_MGR);
            PlManageNote(PLS_OFF_BE+sym+": "+res.phrase,2);
           }
         return true;
        }
     }
   if(g_rec[idx].trail>0 && !g_rec[idx].trail_off && now-g_rec[idx].last_trail>=PL_TRAIL_GAP_MS)
     {
      const double d=(g_rec[idx].trail_val>0.0)?g_rec[idx].trail_val*PlPipOf(sym):g_rec[idx].dist0;   // 0 pips: the distance of the initial SL
      if(d<=0.0) return false;
      double nsl=buy?px-d:px+d;
      nsl=buy?PlTickDown(nsl,tick,dg):PlTickUp(nsl,tick,dg);
      const double step=MathMax(tick,0.1*d);
      const bool better=(curstop<=0.0) || (buy?(nsl>=curstop+step-PL_EPS):(nsl<=curstop-step+PL_EPS));
      if(!better) return false;
      if(!PlSlAllowed(sym,buy,px,nsl,cursl,curtp)) return false;
      g_rec[idx].last_trail=now;
      PlSendRes res;
      PlSendModifyPos(id,nsl,curtp,res);
      const int oc=PlManageOutcome(res);
      PLDBG("MANAGE trail "+(string)id+" sl="+DoubleToString(nsl,dg)+" -> "+res.phrase+" oc="+(string)oc);
      const int k=PlRecIndex(id);
      if(k<0) return true;
      if(oc==0 && now-g_trail_note_at>=PL_TRAIL_NOTE_MS)
        {
         g_trail_note_at=now;
         PlManageNoteQuiet(PlSlMoveText(PLS_TRAIL_SL_TO,sym,nsl,dg));
        }
      if(PlRecTried(k,oc,now))
        {
         g_rec[k].trail_off=true;
         PlRecSave(g_rec[k],PL_RW_MGR);
         PlManageNote(PLS_OFF_TRAIL+sym+": "+res.phrase,2);
        }
      return true;
     }
   return false;
  }

//--- the account's own history knows this position or order is over (it ran, closed, was cancelled or expired)
bool PlRecGone(const ulong id)
  {
   if(HistorySelectByPosition(id) && (HistoryDealsTotal()>0 || HistoryOrdersTotal()>0)) return true;
   if(HistorySelect(0,TimeTradeServer()+86400) && HistoryOrderSelect(id)) return true;
   return false;
  }

//--- garbage: records whose position and order are not alive: gone in this account's history, or older than 90 days (another
//--- account of the same server). A live record is never deleted, however old. Only every ten minutes, never right after the
//--- start, while the terminal is connected.
void PlRecGarbage()
  {
   const ulong now=GetTickCount64();
   if(now-g_born<60000) return;
   if(now-g_t_recgc<600000) return;
   g_t_recgc=now;
   if(TerminalInfoInteger(TERMINAL_CONNECTED)==0) return;
   const long srv=(long)TimeTradeServer();
   for(int i=ArraySize(g_rec)-1;i>=0;i--)
     {
      const ulong id=g_rec[i].id;
      const bool alive=(PlFindPosition(id) || OrderSelect(id));
      const bool old=(g_rec[i].created>0 && srv-g_rec[i].created>90*86400);
      if(!alive && (old || PlRecGone(id)))
        {
         //--- a pending order that filled into an open netting position gets that position's id, not its own ticket:
         //--- the record never learned an open time and its BE, trailing and TP parts cannot be applied to the merged position
         if(!alive && g_rec[i].t_open_msc==0 && (g_rec[i].be_on || g_rec[i].trail>0 || g_rec[i].pt_n>0) && HistoryOrderSelect(id))
           {
            const ulong pid=(ulong)HistoryOrderGetInteger(id,ORDER_POSITION_ID);
            if(pid!=0 && pid!=id) PlManageNote(PLS_ORDER_MERGED+": "+g_rec[i].symbol,2);
           }
         PLDBG("MANAGE garbage record "+(string)id);
         PlRecDelete(id);
        }
     }
  }

//--- one lap of the manager (the timer): the leader acts, every instance rescans the files. At most one request per lap.
void PlManageTick()
  {
   const ulong now=GetTickCount64();
   if(g_born==0) g_born=now;
   if(now-g_t_recscan>=2000 || g_t_recscan==0) { g_t_recscan=now; PlRecScan(); }
   if(!PlLeadCheck())
     {
      //--- nobody can trade: every chart says so (each one is unable then), once a minute, only when records are waiting
      if(PlLeaderId()==0 && g_lead_why!=PL_R_NONE && now-g_t_paused>=60000)
        {
         bool waiting=false;
         for(int i=0;i<ArraySize(g_own);i++) if(g_own[i].rec>=0) { waiting=true; break; }
         if(waiting) { g_t_paused=now; PlManageNote(PLS_MANAGE_PAUSED+PlReasonText(g_lead_why),2); }
        }
      return;
     }
   if(PlTradeBusy()) return;
   for(int i=0;i<ArraySize(g_rec);i++)
     {
      const int n0=ArraySize(g_rec);
      const bool sent=PlRecManage(i);
      if(ArraySize(g_rec)<n0) i--;                  // the record was deleted: the next one moved into this place
      if(sent) break;                               // one request per lap: the next lap looks at the leadership again
      if(PlTradeBusy()) break;
     }
   PlRecGarbage();
  }

//=================================================================================================
//  records made at the open
//=================================================================================================
bool PlRecWanted(const PlOrderSnap &snap,const PlSendRes &r,const int k)
  {
   if(g_cfg.be_on || g_cfg.trail_on) return true;
   if(r.pt_n>0) return true;
   if(r.keep_until>0) return true;
   return false;
  }

//--- after an open (DONE or PLACED): a record for every part that has a ticket. The symbol of the record is what the server says
//--- for that ticket (the chart's symbol string could move under a stored copy). warn: a text for the status line.
void PlRecAfterOpen(const PlOrderSnap &snap,const PlSendRes &r,string &warn)
  {
   warn="";
   if(r.status!=PL_SS_DONE && r.status!=PL_SS_PLACED && r.status!=PL_SS_PARTIAL && r.status!=PL_SS_PARTS_SHORT) return;
   if(r.net_add) return;           // a netting add gets no record of its own: its vol0 and plan would be wrong for the merged position
   const bool pending=(r.status==PL_SS_PLACED || snap.kind!=PL_KIND_MARKET);
   const long srv=(long)TimeTradeServer();
   for(int k=0;k<r.parts_sent && k<PL_MAX_PARTS;k++)
     {
      if(r.ids[k]==0) continue;
      if(!PlRecWanted(snap,r,k)) continue;
      if(PlRecIndex(r.ids[k])>=0) { PlManageNote(PLS_REC_EXISTS+": "+snap.symbol,2); continue; }     // one g_rec entry per id; a file of another server is not in g_rec and is overwritten
      //--- the symbol from the server: the position, else the order; not visible yet: the snapshot's (PlRecLive and the GC judge it later)
      string ssym=PlOwnCopy(snap.symbol);
      bool from_server=false;
      long t_open=0;
      double pos_vol=0.0;
      bool pos_found=false;
      if(PlFindPosition(r.ids[k]))
        {
         ssym=PlOwnCopy(PositionGetString(POSITION_SYMBOL)); from_server=true;
         t_open=PositionGetInteger(POSITION_TIME_MSC);
         pos_vol=PositionGetDouble(POSITION_VOLUME); pos_found=true;
        }
      else if(OrderSelect(r.ids[k]))
        {
         ssym=PlOwnCopy(OrderGetString(ORDER_SYMBOL)); from_server=true;
        }
      if(from_server && ssym!=snap.symbol)
        {
         warn=PLS_REC_SYM_CHANGED;
         PLDBG("RECORD not saved id="+(string)r.ids[k]+": server symbol "+ssym+" differs from "+snap.symbol);
         continue;
        }
      PlRec rc; PlRecInit(rc);
      rc.id=r.ids[k]; rc.symbol=ssym; rc.ptype=(snap.side==PL_SIDE_BUY)?0:1; rc.magic=snap.magic;
      rc.sl0=r.sl_user; rc.dist0=r.dist_user;
      rc.be_on=g_cfg.be_on; rc.be_r=g_cfg.be_r;
      rc.trail=g_cfg.trail_on?2:0; rc.trail_val=snap.trail_val;
      //--- vol0 is what really filled (the position as found), else the lot put down for the part; 0 keeps no TP parts
      rc.vol0=pending?r.part_lot[k]:PlRecStartVol(pos_found,pos_vol,r.part_lot[k]);
      if(r.pt_n>0 && k==0 && !pending && rc.vol0<=0.0)
         PlManageNote(PLS_PARTS_OFF_NO_VOL+": "+snap.symbol,2);
      else if(r.pt_n>0 && k==0)
        {
         rc.pt_n=MathMin(r.pt_n,2);
         for(int j=0;j<rc.pt_n;j++) { rc.pt_price[j]=r.pt_price[j]; rc.pt_share[j]=r.pt_share[j]; }
        }
      if(pending) rc.expire_at=(long)r.keep_until;
      rc.created=srv;
      if(!pending) rc.t_open_msc=t_open;
      if(PlRecSave(rc,PL_RW_NEW))
        {
         const int n=ArraySize(g_rec);
         ArrayResize(g_rec,n+1); g_rec[n]=rc;
         PLDBG("RECORD saved id="+(string)rc.id+" "+rc.symbol+" be="+(string)rc.be_on+" trail="+(string)rc.trail+"  pt="+(string)rc.pt_n+" expire="+(string)rc.expire_at);
        }
     }
  }

//=================================================================================================
//  buttons of the Positions block
//=================================================================================================
//--- the loss distance of an item: the SL on the loss side of the entry. 0: no SL, or the SL is at or past the entry.
double PlLossDist(const PlOwn &o)
  {
   if(o.sl<=0.0) return 0.0;
   const double d=o.buy?(o.open-o.sl):(o.sl-o.open);
   return (d>PL_EPS)?d:0.0;
  }

//--- a record for a position that has none (the user switches BE or Trail on for it, or presses BE now)
int PlRecEnsure(const PlOwn &o)
  {
   int k=PlRecIndex(o.id);
   if(k>=0) return k;
   PlRec rc; PlRecInit(rc);
   rc.id=o.id; rc.symbol=PlOwnCopy(o.sym); rc.ptype=o.buy?0:1; rc.magic=g_cfg.magic;
   if(!o.pending) rc.t_open_msc=0;
   rc.dist0=PlLossDist(o);                          // only an SL on the loss side is a risk distance
   rc.sl0=(rc.dist0>0.0)?o.sl:0.0;
   rc.be_r=g_cfg.be_r;
   rc.vol0=o.vol; rc.created=(long)TimeTradeServer();
   if(!o.pending && PlFindPosition(o.id)) rc.t_open_msc=PositionGetInteger(POSITION_TIME_MSC);
   if(!PlRecSave(rc,PL_RW_NEW)) return -1;
   const int n=ArraySize(g_rec);
   ArrayResize(g_rec,n+1); g_rec[n]=rc;
   return n;
  }

void PlRecToggleBe(const int own)
  {
   if(own<0 || own>=ArraySize(g_own)) return;
   const PlOwn o=g_own[own];
   int k=PlRecIndex(o.id);
   if(k>=0) PlRecFresh(k);                          // the file is the truth (another chart may have changed it)
   const bool on=(k<0 || !g_rec[k].be_on);
   if(on && (k<0 || g_rec[k].dist0<=0.0) && PlLossDist(o)<=0.0) { PlManageNote(PLS_NEED_LOSS_SL,2); return; }
   k=PlRecEnsure(o);
   if(k<0) return;
   g_rec[k].be_on=on;
   if(on) { g_rec[k].be_done=false; g_rec[k].be_off=false; }
   if(g_rec[k].dist0<=0.0) { g_rec[k].dist0=PlLossDist(o); if(g_rec[k].dist0>0.0) g_rec[k].sl0=o.sl; }
   PlRecSave(g_rec[k],PL_RW_USER);
   PLDBG("BUTTON BE toggle id="+(string)o.id+" now "+(string)g_rec[k].be_on);
  }

void PlRecToggleTrail(const int own)
  {
   if(own<0 || own>=ArraySize(g_own)) return;
   const PlOwn o=g_own[own];
   int k=PlRecIndex(o.id);
   if(k>=0) PlRecFresh(k);
   const bool on=(k<0 || g_rec[k].trail<=0);
   if(on && (k<0 || g_rec[k].dist0<=0.0) && PlLossDist(o)<=0.0) { PlManageNote(PLS_NEED_LOSS_SL,2); return; }
   k=PlRecEnsure(o);
   if(k<0) return;
   if(!on) g_rec[k].trail=0;
   else
     {
      g_rec[k].trail=2;
      g_rec[k].trail_val=(o.sym==g_sym.name)?g_dr.trail_dist:0.0;
      g_rec[k].trail_off=false;
     }
   if(g_rec[k].dist0<=0.0) { g_rec[k].dist0=PlLossDist(o); if(g_rec[k].dist0>0.0) g_rec[k].sl0=o.sl; }
   PlRecSave(g_rec[k],PL_RW_USER);
   PLDBG("BUTTON Trail toggle id="+(string)o.id+" now "+(string)g_rec[k].trail);
  }

//--- "BE now": the SL goes to the breakeven level at once, when the price is past it. The level and the "already" test are the
//--- one measure of the open risk line (PlPlAtSl); no record of the position is needed (and none is made)
void PlRecBreakevenNow(const int own)
  {
   if(own<0 || own>=ArraySize(g_own) || g_own[own].pending) return;
   const PlOwn o=g_own[own];
   if(!PlFindPosition(o.id)) return;
   const double cursl=PositionGetDouble(POSITION_SL), curtp=PositionGetDouble(POSITION_TP);
   const double vol=PositionGetDouble(POSITION_VOLUME);
   const double opn=PositionGetDouble(POSITION_PRICE_OPEN);
   const double swp=PositionGetDouble(POSITION_SWAP);
   const double nsl=PlBreakevenSl(o.sym,o.buy,opn,vol,swp,o.id);
   if(nsl<=0.0) { PlManageNote(PLS_BE_WAIT_DEAL,2); return; }
   const double px=SymbolInfoDouble(o.sym,o.buy?SYMBOL_BID:SYMBOL_ASK);
   const double tick=PlTickOf(o.sym);
   //--- the SL already gives zero or more at the exit: nothing to do (the row hides the button at this moment); never loosened either
   double pls=0.0;
   if(cursl>0.0 && PlPlAtSl(o.buy,o.sym,vol,opn,cursl,swp,o.id,pls) && pls>=0.0) { PlManageNote(PLS_ALREADY_BE,0); return; }
   if(px<=0.0 || !(o.buy?(px>nsl+tick*0.999):(px<nsl-tick*0.999))) { PlManageNote(PLS_NOT_PAST_BE,2); return; }
   if(cursl>0.0 && !(o.buy?(nsl>cursl+tick*0.999):(nsl<cursl-tick*0.999))) { PlManageNote(PLS_ALREADY_BE,0); return; }
   PlSendRes res;
   PlSendModifyPos(o.id,nsl,curtp,res);
   PLDBG("BUTTON BE now id="+(string)o.id+" sl="+DoubleToString(nsl,PlDigitsOf(o.sym))+" -> "+res.phrase);
   if(res.status==PL_SS_DONE)
     {
      const int kk=PlRecIndex(o.id);
      if(kk>=0) { PlRecFresh(kk); g_rec[kk].be_done=true; PlRecSave(g_rec[kk],PL_RW_USER); }     // the file is the truth, as in the toggles
      PlManageNote(PlSlMoveText(PLS_BE_SL_TO,o.sym,nsl,PlDigitsOf(o.sym)),1);
     }
   else PlManageNote(res.phrase,2);
  }

//--- closes one item: a position (all or a part) or a pending order. Returns the profit closed (0 for an order).
bool PlOwnClose(const PlOwn &o,const double part_pct,string &phrase)
  {
   PlSendRes res;
   if(o.pending) PlSendDeleteOrder(o.id,res);
   else PlSendClosePos(o.id,0.0,res,part_pct);        // a percent of the volume of this moment, read at the send
   phrase=res.phrase;
   const bool ok=(res.status==PL_SS_DONE);
   PLDBG("BUTTON close id="+(string)o.id+" pending="+(string)o.pending+" part="+DoubleToString(part_pct,0)+" -> "+res.phrase);
   if(ok && part_pct<=0.0) { const int k=PlRecIndex(o.id); if(k>=0) PlRecDelete(o.id); }
   return ok;
  }

//--- a bulk close of two positions or more ends in one sticky phrase, "Closed 3 · -$12.40 net" (CloseSummary.mqh): the ids that were
//--- closed wait here, each exit deal adds its position's net as it arrives, and the last one (or a lap 4 s later) says the sum
ulong  g_bulk_id[];
int    g_bulk_planned=0;
int    g_bulk_got=0;
double g_bulk_net=0.0;
ulong  g_bulk_at=0;

//--- the bulk buttons: 0 all, 1 chart symbol. One by one; the summary is one phrase.
string PlBulkClose(const int what,const string chart_sym,const PlAccount &acc)
  {
   PlOwnRefresh();
   PlOwn list[];
   ArrayResize(list,0);
   for(int i=0;i<ArraySize(g_own);i++)
     {
      const PlOwn o=g_own[i];
      bool take=false;
      switch(what)
        {
         case 0: take=true; break;
         case 1: take=(o.sym==chart_sym); break;
        }
      if(!take) continue;
      const int n=ArraySize(list);
      ArrayResize(list,n+1); list[n]=o;
     }
   int done=0; double pl=0.0; string last="";
   int npos=0;
   ArrayResize(g_bulk_id,0);
   for(int i=0;i<ArraySize(list);i++)
     {
      string ph;
      const double p=list[i].pl;
      if(!list[i].pending) npos++;
      if(PlOwnClose(list[i],0.0,ph))
        {
         done++; pl+=p;
         if(!list[i].pending) { const int nb=ArraySize(g_bulk_id); ArrayResize(g_bulk_id,nb+1); g_bulk_id[nb]=list[i].id; }
        }
      else { last=ph; if(PlTradeBusy()) break; }
     }
   if(ArraySize(list)==0) return PLS_NOTHING_CLOSE;
   if(npos<2) ArrayResize(g_bulk_id,0);                // one position says its own result
   g_bulk_planned=npos; g_bulk_got=0; g_bulk_net=0.0; g_bulk_at=GetTickCount64();
   string t=PLS_CLOSED_WORD+" "+(string)done+" "+PLS_OF+" "+(string)ArraySize(list);
   t+=", "+PLS_PNL+" "+PlMoney(pl,acc.currency,acc.currency_digits,true);
   if(done<ArraySize(list) && last!="") t+=": "+last;
   return t;
  }

//=================================================================================================
//  two-step arming of the close buttons (500 ms to 3 s, always for the bulk buttons)
//=================================================================================================
int    g_cb_kind=0;            // 0 none, 1 a row, 2 a bulk button, 3 "Close 50%" of a row
ulong  g_cb_arg=0;             // the id of the row, or the number of the bulk button
ulong  g_cb_at=0;
ulong  g_cb_last=0;            // the last fired close (a double click does not fire twice)

bool PlCbArmed(const int kind,const ulong arg)
  {
   return (g_cb_kind==kind && g_cb_arg==arg && GetTickCount64()-g_cb_at<=3000);
  }

//--- one click on a close button: true when this click is the one that fires
bool PlCbClick(const int kind,const ulong arg,const bool always)
  {
   const ulong now=GetTickCount64();
   if(now-g_cb_last<1000) return false;
   if(!always && !g_cfg.confirm_on) { g_cb_last=now; g_cb_kind=0; return true; }
   if(g_cb_kind==kind && g_cb_arg==arg)
     {
      const ulong age=now-g_cb_at;
      if(age<500) return false;
      if(age<=3000) { g_cb_kind=0; g_cb_last=now; return true; }
     }
   g_cb_kind=kind; g_cb_arg=arg; g_cb_at=now;
   return false;
  }

#endif
