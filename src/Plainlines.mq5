// Required Notice: Copyright 2026 stop-loss-enjoyer
// Plainlines is source-available under the PolyForm Shield License 1.0.0.
//
// Plainlines: an entry panel and lines for MetaTrader 5. It sizes the lot from the risk, sends the orders and manages the positions it opened.
// Demo and dev builds trade only on a demo account; ./build.sh --release makes the build for real accounts (src/Build.mqh).
// SendOrderSafe.mqh is the one place that sends.
#property copyright "stop-loss-enjoyer"
#include "Version.mqh"
#property version   PLAINLINES_VERSION
#property description "Plainlines"
#property icon "Plainlines.ico"

//--- trade sounds, built into the .ex5 (cut from one CC0 recording, see Credits in the README); played as "::Sounds\\<name>.wav"
#resource "Sounds\\PlOpen.wav"
#resource "Sounds\\PlCloseWin.wav"
#resource "Sounds\\PlCloseLoss.wav"
//--- the wordmark of the header, one picture per panel scale (generated, see UI/Wordmark.mqh)
#resource "Images\\PlWordmark.bmp"

#include "Build.mqh"
#ifdef PL_DEV_LOG
 #undef PL_RELEASE                 // the development channel never trades a real account
#endif
#ifdef PL_RELEASE
 #define PL_BUILD_TAG ""
#else
 #ifdef PL_DEV_LOG
  #define PL_BUILD_TAG " dev"
 #else
  #define PL_BUILD_TAG " demo"
 #endif
#endif

#include "Core/Types.mqh"
#include "Core/Num.mqh"
#include "Core/Reasons.mqh"
#include "Core/Prices.mqh"
#include "Core/Lot.mqh"
#include "Terminal/DevLog.mqh"
#include "Core/Guard.mqh"
#include "Terminal/Market.mqh"
#include "Terminal/Exposure.mqh"
#include "Terminal/Account.mqh"
#include "UI/Strings.mqh"
#include "Terminal/OneProgram.mqh"
#include "Trade/TradeTypes.mqh"
#include "Trade/SendOrderSafe.mqh"
#include "UI/Theme.mqh"
#include "UI/State.mqh"
#include "Terminal/Profile.mqh"
#include "Trade/Manage.mqh"
#include "UI/Fields.mqh"
#include "UI/Lines.mqh"
#include "UI/Sound.mqh"
#include "UI/Canvas.mqh"
#include "Trade/CloseSummary.mqh"

CPlPanel g_panel;
bool     g_lbtn=false;              // left mouse button is down
bool     g_press_in_panel=false;    // the left button went down inside the panel (kept until the next press: OBJECT_DRAG comes after the release)
ulong    g_last_live=0;             // throttle of the live recalculation during a drag
ulong    g_t_account=0, g_t_symbol=0, g_t_cmd=0, g_t_atr=0;
string   g_key="";                  // signature of the last drawn result
double   g_last_bid=0, g_last_ask=0;
bool     g_last_open=true;
int      g_atr_h=INVALID_HANDLE;
int      g_atr_period=0;
int      g_chart_w=0, g_chart_h=0;
bool     g_ready=false;
int      g_theme_sig=-1;
bool     g_hint_dirty=false;        // a deal was added: the commission hint may have changed
bool     g_risk_dirty=true;         // open positions or orders changed: work out the open risk again
ulong    g_t_risk=0;
bool     g_scroll_orig=true;        // CHART_MOUSE_SCROLL as the user had it
bool     g_scroll_held=false;       // we switched it off while the pointer is on the panel
string   g_confirm_sig="";          // plan the confirmation was asked for
string   g_confirm_net="";          // its netting position part, to say why it lapsed
bool     g_arm_conn=true;           // connection state when the confirmation was asked for
ulong    g_last_hotkey=0;
ulong    g_t_rc=0, g_t_sec=0, g_t_flow=0, g_t_own=0;


//--- helpers -----------------------------------------------------------------------------------
void PlMessage(const string t,const uint ms=3500,const int kind=0)
  {
   g_msg=t; g_msg_at=GetTickCount64(); g_msg_until=g_msg_at+ms; g_msg_kind=kind; g_msg_sticky=false;
   PLDBG("MSG kind="+(string)kind+" ms="+(string)ms+" "+t);      // dev log only (empty in the release): the tests read the phrase here, not from a picture
  }

//--- the result of a closed position (Trade/CloseSummary.mqh): no timer, it stays until the trader acts or another message comes
void PlMessageSticky(const string t,const int kind)
  {
   g_msg=t; g_msg_at=GetTickCount64(); g_msg_until=ULONG_MAX; g_msg_kind=kind; g_msg_sticky=true;
   PLDBG("MSG kind="+(string)kind+" sticky "+t);
   g_key="";
   if(g_panel.Created()) { g_panel.Redraw(); ChartRedraw(); }
  }

//--- the trader acted on the panel (a click, a key, a dragged line): the result of a closed position has been read
void PlStickyClear()
  {
   if(!g_msg_sticky) return;
   g_msg_sticky=false; g_msg=""; g_msg_until=0;
   g_key="";
   if(g_panel.Created()) { g_panel.Redraw(); ChartRedraw(); }
  }

//--- the one phrase about the account that was just found or made (Profile.mqh): shown once
void PlProfAnnounce()
  {
   if(g_prof_note=="") return;
   PlMessage(g_prof_note,12000,0);
   g_prof_note="";
  }

//--- settings.dat could not be written three laps in a row (State.mqh asks once per session): the status line says so, nothing is blocked
void PlSettingsFailNote()
  {
   if(!g_settings_fail_say) return;
   g_settings_fail_say=false;
   PlMessage(PLS_SETTINGS_NOT_SAVED,8000,2);
   g_key="";
   if(g_panel.Created()) { g_panel.Redraw(); ChartRedraw(); }
  }

//--- the manager and the buttons report here (declared in Manage.mqh). While a confirmation waits for its press a plain or done note
//--- (a trail, a breakeven, a TP part, an expired order) is only logged: the status line keeps the phrase of what the next press
//--- confirms and the positions list shows the new SL anyway; an error (kind 2) still shows
void PlManageNote(const string t,const int kind)
  {
   PLDBG("NOTE kind="+(string)kind+" "+t);
   if(kind<2 && g_flow==PL_FLOW_ARMED) return;
   PlMessage(t,6000,kind);
   g_key="";
   //--- drawn now: nothing else may be dirty on a quiet market, and a note that waits for the next price change is gone before it is seen
   if(g_panel.Created()) { g_panel.Redraw(); ChartRedraw(); }
  }

//--- a trailing move is frequent: it never takes the place of a close result that waits to be read or of an error (nor of the phrase
//--- of an armed confirmation, see PlManageNote), and it is a plain note (kind 0), so the quick strip, which shows done and refused
//--- messages in the place of its button, keeps the button while a trail runs
void PlManageNoteQuiet(const string t)
  {
   if(g_msg!="" && GetTickCount64()<g_msg_until && (g_msg_sticky || g_msg_kind==2)) return;
   PlManageNote(t,0);
  }

void PlFlowSync() { g_panel.confirm_view=(g_flow==PL_FLOW_ARMED); }

//--- the confirmation lapses without sending anything
bool PlCancelArm(const string msg,const bool redraw=true,const int kind=0)
  {
   if(g_flow!=PL_FLOW_ARMED) return false;
   g_flow=PL_FLOW_IDLE;
   PlFlowSync();
   if(msg!="") PlMessage(msg,3500,kind);
   PLDBG("ARM cancelled: "+msg);
   if(redraw && g_panel.Created()) { g_panel.Redraw(); ChartRedraw(); }
   return true;
  }

void PlAtrUpdate()
  {
   if(!g_cfg.atr_on) { g_atr=0.0; return; }
   if(g_atr_h==INVALID_HANDLE || g_atr_period!=g_cfg.atr_period)
     {
      if(g_atr_h!=INVALID_HANDLE) IndicatorRelease(g_atr_h);
      g_atr_h=iATR(_Symbol,_Period,g_cfg.atr_period);
      g_atr_period=g_cfg.atr_period;
     }
   if(g_atr_h==INVALID_HANDLE) { g_atr=0.0; return; }
   double b[];
   if(CopyBuffer(g_atr_h,0,1,1,b)==1) g_atr=b[0]; else g_atr=0.0;
  }

void PlBuildInputs()
  {
   g_in.kind=g_dr.kind;
   g_in.entry=g_px.entry; g_in.limit=g_px.limit; g_in.sl=g_px.sl;
   g_in.no_sl=g_cfg.no_sl; g_in.no_tp=g_cfg.no_tp;
   double sh[PL_MAX_TP];
   sh[0]=100.0; sh[1]=0.0; sh[2]=0.0;
   if(g_cfg.tp_count==2) { sh[1]=g_cfg.tp_share2; sh[0]=100.0-sh[1]; }
   if(g_cfg.tp_count>=3) { sh[1]=g_cfg.tp_share2; sh[2]=g_cfg.tp_share3; sh[0]=100.0-sh[1]-sh[2]; }
   for(int i=0;i<PL_MAX_TP;i++)
     {
      g_in.tp[i].on=(i<g_cfg.tp_count) && !g_cfg.no_tp;
      g_in.tp[i].mode=g_dr.tp_price[i]?PL_TP_PRICE:PL_TP_R;
      g_in.tp[i].r=g_dr.tp_r[i];
      g_in.tp[i].price=g_px.tp[i];
      g_in.tp[i].share=sh[i];
     }
   g_in.risk_mode=g_dr.unit_money?PL_RISK_MONEY:PL_RISK_PERCENT;
   g_in.risk_percent=g_dr.risk_pct; g_in.risk_money=g_dr.risk_money; g_in.lot_fixed=g_cfg.lot_fixed;
   g_in.base=(PlRiskBase)g_cfg.base; g_in.subtract_open=g_cfg.subtract_open;
   g_in.cap_percent=g_cfg.cap; g_in.confirm_above=g_cfg.confirm_on?g_cfg.confirm_above:g_cfg.cap;     // Confirmation off asks nothing for the risk, the cap still blocks
   g_in.over_max=(PlOverMax)g_cfg.over_max;
   g_in.max_spread_share=g_cfg.max_spread/100.0;
   g_in.comm=g_dr.comm;
   //--- sources in order: the broker's accepted rule, the user's setting (the draft), the deal sample (only through "Use"), none.
   //--- The broker's rule wins over a typed rate because one terminal often holds several accounts of one broker with a
   //--- different commission (Bybit Tight Spread and Zero Fee): the rule is read per account, a typed rate belongs to the symbol.
   //--- The rule goes into this calculation only; g_dr stays what the user chose, so the draft file never stores it.
   {
      PlCommKind bk; double brt, bmin; bool bz;
      if(PlCommRuleOf(_Symbol,bk,brt,bmin,bz))
        {
         g_in.comm.kind=bk; g_in.comm.rate=brt; g_in.comm.source=PL_COMMSRC_BROKER; g_in.comm.min_money=bmin;
        }
   }
   g_in.atr_on=g_cfg.atr_on; g_in.atr=g_atr; g_in.atr_mult=g_cfg.atr_mult;
   g_in.calcprofit_ok=false; g_in.calcprofit_loss_1lot=0.0;
  }

//--- rights, connection, demo-only and the symbol mode live outside the core: they join the verdict here.
//--- A stronger verdict replaces the weaker one together with its reason; an equal one is left alone.
void PlVerdictRaise(PlResult &r,const PlVerdict v,const PlReason why)
  {
   if((int)v>(int)r.verdict) { r.verdict=v; r.reason=why; }
  }

//--- the guards (and the checks of a build with more checks) join the verdict
void PlGuardMerge()
  {
   const bool has=(g_plan.ok && g_res.lot>0.0);
   const double nr=has?g_res.risk_add:0.0, nm=has?g_res.margin_needed:0.0;   // risk_add: on a netting add only what the trade adds to the worst case
   PlGuardRunAll(g_acc,nr,nm,g_new_orders,(g_dr.kind==PL_KIND_MARKET)?g_new_orders:0,g_lo);
   g_guard_text="";
   if(!g_plan.ok) return;
   if(g_lo.verdict!=PL_OK)
     {
      g_guard_text=PlWaitPhrase(g_lo,PlGuardPhraseNow(g_lo,nr,has?nr/g_res.lot:g_res.loss_per_lot,g_sym.vol_step,g_acc.currency,g_acc.currency_digits));
      PlVerdictRaise(g_res,g_lo.verdict,PL_R_GUARD);
     }
   else if(g_cfg.subtract_open && g_acc.open_no_sl>0)
     {
      g_guard_text=PLS_LIM_NOT_SUB;
      PlVerdictRaise(g_res,PL_WARN,PL_R_GUARD);
     }
  }

//--- what the confirmation stands for: another symbol, side, kind or price line cancels it. The lot is not
//--- part of it: on a market order it moves with every tick (the send step recounts it anyway)
//--- the open position of a netting account as the confirmation saw it ("" on hedging or with no position)
string PlConfirmNet()
  {
   return (g_acc.margin_mode!=ACCOUNT_MARGIN_MODE_RETAIL_HEDGING && g_sym.net_vol>PL_EPS)
          ?"|"+DoubleToString(g_sym.net_vol,4)+"|"+DoubleToString(g_sym.net_sl,g_sym.digits):"";
  }

string PlConfirmSig()
  {
   const bool mkt=(g_dr.kind==PL_KIND_MARKET);
   const double sl=(mkt && g_cfg.atr_on)?0.0:g_plan.sl;                 // an ATR stop and an R target follow the quote
   const double tp=(mkt && !g_dr.tp_price[0])?0.0:g_plan.tp[0];
   //--- on a netting account the open position is part of the plan (its risk at the new SL): a trailing or breakeven
   //--- step, a partial close or a fill while the confirmation waits asks again, with the risk counted anew
   const string net=PlConfirmNet();
   return g_sym.name+"|"+(string)(int)g_dr.kind+"|"+(string)(int)g_plan.side+"|"
          +DoubleToString(sl,g_sym.digits)+"|"+DoubleToString(tp,g_sym.digits)+"|"
          +DoubleToString(mkt?0.0:g_plan.entry,g_sym.digits)+"|"+DoubleToString(g_plan.limit,g_sym.digits)+net;
  }

string PlKey()
  {
   string k=(string)g_plan.ok+"|"+(string)(int)g_plan.side+"|"+DoubleToString(g_plan.exec,g_sym.digits)+"|"
            +DoubleToString(g_px.sl,g_sym.digits)+"|"+DoubleToString(g_px.tp[0],g_sym.digits)+"|"
            +DoubleToString(g_px.tp[1],g_sym.digits)+"|"+DoubleToString(g_px.tp[2],g_sym.digits)+"|"
            +DoubleToString(g_px.entry,g_sym.digits)+"|"+DoubleToString(g_px.limit,g_sym.digits)+"|"
            +DoubleToString(g_res.lot,4)+"|"+DoubleToString(g_res.risk_money,2)+"|"+DoubleToString(g_res.risk_percent,3)+"|"
            +DoubleToString(g_res.reward_total,2)+"|"+DoubleToString(g_res.rr,3)+"|"+DoubleToString(g_res.spread_money,3)+"|"
            +(string)(int)g_res.verdict+"|"+(string)(int)g_res.reason+"|"+DoubleToString(g_res.margin_needed,2)+"|"
            +DoubleToString(g_res.comm_money,2)+"|"+DoubleToString(g_res.swap_long_night,3)+"|"+DoubleToString(g_res.swap_short_night,3)+"|"
            +DoubleToString(g_acc.balance,2)+"|"+DoubleToString(g_acc.equity,2)+"|"+DoubleToString(g_sym.bid,g_sym.digits)+"|"
            +DoubleToString(g_sym.ask,g_sym.digits)+"|"+(string)g_sym.session_open;
   return k;
  }

//--- first prices of the lines from the market and a distance ---------------------------------------
void PlSetupPrices(const double dist,const int dir,const PlKind kind)
  {
   double mid=(g_sym.ask+g_sym.bid)/2.0;
   double tk=g_sym.tick_size;
   double d=PlTickRound(MathMax(dist,3.0*tk));
   double off=PlTickRound(MathMax(d*0.5,3.0*tk));
   double exec=0;
   g_px.entry=0; g_px.limit=0;
   switch(kind)
     {
      case PL_KIND_MARKET:
         g_px.entry=(dir>0)?g_sym.ask:g_sym.bid; exec=g_px.entry; break;
      case PL_KIND_LIMIT:
         g_px.entry=PlTickRound(mid-dir*off); exec=g_px.entry; break;
      case PL_KIND_STOP:
         g_px.entry=PlTickRound(mid+dir*off); exec=g_px.entry; break;
      default:
         g_px.entry=PlTickRound(mid+dir*off);
         g_px.limit=PlTickRound(g_px.entry-dir*MathMax(off*0.4,tk)); exec=g_px.limit; break;
     }
   g_px.sl=PlTickRound(exec-dir*d);
   for(int i=0;i<PL_MAX_TP;i++)
     {
      g_px.tp[i]=PlTickRound(exec+dir*g_dr.tp_r[i]*d);
      g_dr.tp_price[i]=false;
     }
  }

bool g_prices_ok=false;         // the lines have their first prices

//--- the side of a Market draft is the trader's. On Market the entry follows the price, so the price can go through
//--- the SL line and turn a Buy into a Sell with nobody touching anything. g_side_set is the side the trader set (1 Buy, -1 Sell,
//--- 0 not known: the next plan gives it); the line prices, type and no-SL switch seen at the end of the last count tell a move
//--- of the trader from a move of the price. A terminal restart seeds the side from the saved SL distance (PlSideSeed)
int    g_side_set=0;
double g_side_sl=-1.0;
double g_side_tp=-1.0;
int    g_side_kind=-1;
bool   g_side_nosl=false;
bool   g_side_crossed=false;         // the plan of this count is blocked for it: nothing goes back to the lines or the draft

void PlSideSeed()
  {
   g_side_set=(!g_cfg.no_sl && g_dr.sl_ticks!=0.0)?((g_dr.sl_ticks<0.0)?1:-1):0;
   g_side_sl=-1.0; g_side_tp=-1.0; g_side_kind=-1; g_side_crossed=false;
  }

//--- the top of a panel that was never dragged: 44 leaves the chart caption free, but on a chart too short for the view that
//--- stands (the strip 40, the card 150, the full panel 340 logical px; a laptop or charts in tiles) the panel moves up to 14,
//--- so the lot card and the risk are not cut off below
int PlDefaultTop(const double s)
  {
   const int hi=(int)MathRound(44*s), lo=(int)MathRound(14*s);
   const int ch=(int)ChartGetInteger(0,CHART_HEIGHT_IN_PIXELS);
   const int vh=g_cfg.quick?((g_cfg.quick_style==0)?PL_STRIP_H:PL_QUICK_H):PL_MAIN_H;
   if(ch>0 && ch-hi-6<(int)MathRound(vh*s)) return lo;
   return hi;
  }

//--- the view or the scale changed: a panel that was never dragged takes the top its new height needs
void PlFollowDefaultTop()
  {
   if(g_cfg.py>=0 || !g_panel.Created()) return;
   g_panel.SetY(PlDefaultTop(PlScaleGet(g_cfg.scale)));
   g_panel.Clamp(); g_panel.Place();
   PLDBG("TOP follows the view: y="+(string)g_panel.Y()+" chart h="+(string)ChartGetInteger(0,CHART_HEIGHT_IN_PIXELS)+" quick="+(string)g_cfg.quick+" style="+(string)g_cfg.quick_style+" scale="+(string)g_cfg.scale);
  }

bool PlQuoteReady()
  {
   return (g_sym.bid>0.0 && g_sym.ask>0.0 && g_sym.tick_size>0.0 && g_sym.point>0.0);
  }

//--- first prices: lines of this symbol already on the chart, or new ones from the saved distance
bool PlInitPrices()
  {
   bool adopted=PlLinesAdopt();
   if(!adopted)
     {
      PlLinesDeleteAll();
      double d=MathAbs(g_dr.sl_ticks)*g_sym.tick_size;
      //--- a saved distance that makes no sense for the price (another instrument's file, a changed contract)
      if(d>(g_sym.ask+g_sym.bid)/2.0*0.10) d=0.0;
      if(d<=0.0) PlDefaultLines(g_sym,g_cfg.max_spread/100.0,d);
      int dir=(g_dr.sl_ticks>0.0)?-1:1;
      PlSetupPrices(d,dir,g_dr.kind);
      if(g_dr.tp_price[0] && g_dr.tp_ticks!=0.0)
        {
         double exec=(g_dr.kind==PL_KIND_STOP_LIMIT)?g_px.limit:g_px.entry;
         g_px.tp[0]=PlTickRound(exec+g_dr.tp_ticks*g_sym.tick_size);
        }
     }
   else
     {
      for(int i=0;i<PL_MAX_TP;i++) if(g_px.tp[i]<=0.0) g_px.tp[i]=g_px.entry;
     }
   PlSideSeed();
   return adopted;
  }

//--- recalculation; true when something visible changed ------------------------------------------
bool PlRecalc()
  {
   PlBuildInputs();
   g_in.n_orders=1;
   PlRunCore(g_in,g_sym,g_acc,g_plan,g_res);
   //--- a broker minimum commission is paid by every order, and the number of orders comes from the lot: count again with the
   //--- number of orders of the first result (a larger number only shrinks the lot, so the second result is final)
   if(g_plan.ok && g_in.comm.min_money>PL_EPS && g_res.lot>PL_EPS)
     {
      const int n_min=PlOrdersFor(g_acc.margin_mode==ACCOUNT_MARGIN_MODE_RETAIL_HEDGING,g_in,g_plan,g_res,g_sym.vol_min,g_sym.vol_step);
      if(n_min>1)
        {
         g_in.n_orders=n_min;
         PlRunCore(g_in,g_sym,g_acc,g_plan,g_res);
        }
     }
   if(g_plan.ok)
     {
      PlReason gw;
      PlTradeGate(g_acc,g_sym,false,gw,g_plan.side);
      if(gw!=PL_R_NONE) PlVerdictRaise(g_res,PL_BLOCK,gw);
     }
   //--- the side: taken when the trader moved the SL line (the first TP with no SL), changed the order type or the no-SL switch
   //--- since the last count; a Market plan whose side the price changed is blocked until a line is moved (a pending entry is
   //--- a fixed price, the price cannot change its side). The block names itself first: it is why every other number changed
   g_side_crossed=false;
   if(g_plan.ok && g_plan.side!=PL_SIDE_NONE)
     {
      const int sd=(g_plan.side==PL_SIDE_BUY)?1:-1;
      const bool moved=(g_side_kind>=0 && (g_px.sl!=g_side_sl || (int)g_dr.kind!=g_side_kind || g_cfg.no_sl!=g_side_nosl
                        || (g_cfg.no_sl && g_px.tp[0]!=g_side_tp)));
      if(g_side_set==0 || moved || g_dr.kind!=PL_KIND_MARKET) g_side_set=sd;
      else if(sd!=g_side_set) { g_side_crossed=true; g_res.verdict=PL_BLOCK; g_res.reason=PL_R_SIDE_CROSSED; }
     }
   //--- Split with several TPs on a hedging account: the orders of all parts together may not pass the limit
   g_split_orders=0;
   if(g_plan.ok && g_res.split_n>1)
     {
      bool tp_on[PL_MAX_TP]; double share[PL_MAX_TP];
      for(int i=0;i<PL_MAX_TP;i++) { tp_on[i]=(g_in.tp[i].on && !g_in.no_tp && g_plan.tp[i]>0.0); share[i]=g_in.tp[i].share; }
      double lots[]; int idx[]; string note;
      const int tot=PlSplitOrders(g_acc.margin_mode==ACCOUNT_MARGIN_MODE_RETAIL_HEDGING,g_res,g_sym.vol_min,g_sym.vol_step,tp_on,share,lots,idx,note);
      g_split_orders=tot;
      if(tot>PL_MAX_PARTS) { g_res.split_need=tot; PlVerdictRaise(g_res,PL_BLOCK,PL_R_SPLIT_TOO_MANY); }
     }
   g_new_orders=(g_plan.ok && g_res.lot>0.0)?PlOrdersFor(g_acc.margin_mode==ACCOUNT_MARGIN_MODE_RETAIL_HEDGING,g_in,g_plan,g_res,g_sym.vol_min,g_sym.vol_step):1;
   PlGuardMerge();
   //--- the core's prices go back to the lines
   if(g_plan.ok && g_prices_ok && !g_side_crossed)
     {
      //--- while a line is dragged only that line is left alone: the others (TP in R mode) follow it
      if(g_dr.kind==PL_KIND_MARKET && g_drag_w!=0) g_px.entry=g_plan.entry;
      for(int i=0;i<PL_MAX_TP;i++)
         if(!g_dr.tp_price[i] && g_plan.tp[i]>0.0 && g_drag_w!=3+i) g_px.tp[i]=g_plan.tp[i];
      if(g_cfg.atr_on && g_plan.sl>0.0 && g_drag_w!=2) g_px.sl=g_plan.sl;
      //--- distances for the state file
      if(g_sym.tick_size>0.0)
        {
         g_dr.sl_ticks=MathRound((g_px.sl-g_plan.exec)/g_sym.tick_size);
         g_dr.tp_ticks=MathRound((g_px.tp[0]-g_plan.exec)/g_sym.tick_size);
        }
     }
   else if(!g_side_crossed && g_prices_ok && g_sym.tick_size>0.0 && g_px.sl>0.0)
     {
      g_dr.sl_ticks=MathRound((g_px.sl-PlEstExec())/g_sym.tick_size);
     }
   if(g_prices_ok) { PlLinesSync(); PlLinesLabels(); }
   //--- what the next count compares with: the lines as they stand now, after the core's prices went back to them
   g_side_sl=g_px.sl; g_side_tp=g_px.tp[0]; g_side_kind=(int)g_dr.kind; g_side_nosl=g_cfg.no_sl;
   //--- a confirmation holds only for the plan it was asked for
   bool disarmed=false;
   if(g_flow==PL_FLOW_ARMED && (PlConfirmSig()!=g_confirm_sig || !g_plan.ok || g_res.verdict==PL_BLOCK))
      disarmed=PlCancelArm((g_plan.ok && g_res.verdict==PL_BLOCK)?PlReasonTextG(g_res.reason):(PlConfirmNet()!=g_confirm_net?PLS_POS_CHANGED:""),false,
                           (g_plan.ok && g_res.verdict==PL_BLOCK && g_res.reason!=PL_R_MARKET_CLOSED)?2:0);   // a block shows in the colour of a block
   //--- a new line goes above the panel; not while a field is being typed in (the edits are recreated)
   if(g_lines_created && g_fl_focus<0) { g_lines_created=false; if(g_panel.Created()) g_panel.Raise(); }
   string k=PlKey();
   bool ch=(k!=g_key) || disarmed;
   g_key=k;
   return ch;
  }

//--- the model changed (field, menu, mirror): recalc, redraw, remember --------------------------------
void PlModelChanged()
  {
   PlCancelArm("",false);            // any change of the plan, a field, the menu or a line asks again
   PlRecalc();
   if(g_panel.Created()) g_panel.Redraw();
   ChartRedraw();
   if(g_prices_ok) PlDraftSave(g_sym);
   PLDBG("CALC kind="+(string)(int)g_dr.kind+" side="+(string)(int)g_plan.side+" lot="+DoubleToString(g_res.lot,4)
         +" risk="+DoubleToString(g_res.risk_money,2)+" pct="+DoubleToString(g_res.risk_percent,3)
         +" reward="+DoubleToString(g_res.reward_total,2)+" rr="+DoubleToString(g_res.rr,2)
         +" verdict="+(string)(int)g_res.verdict+" reason="+(string)(int)g_res.reason
         +" sl="+DoubleToString(g_px.sl,g_sym.digits)+" tp1="+DoubleToString(g_px.tp[0],g_sym.digits)
         +" entry="+DoubleToString(g_px.entry,g_sym.digits)+" exec="+DoubleToString(g_plan.exec,g_sym.digits)
         +" comm_kind="+(string)(int)g_in.comm.kind+" comm_rate="+DoubleToString(g_in.comm.rate,6)+" comm_src="+(string)(int)g_in.comm.source
         +" comm_in1="+DoubleToString(g_res.comm_in_1lot,4)+" comm_out1="+DoubleToString(g_res.comm_out_1lot,4)+" comm_money="+DoubleToString(g_res.comm_money,4)
         +" note="+(string)(int)g_res.note);
  }

//--- actions from the panel ------------------------------------------------------------------------
void PlMirror()
  {
   double mid=(g_sym.ask+g_sym.bid)/2.0;
   g_px.entry=PlTickRound(2.0*mid-g_px.entry);
   if(g_px.limit>0.0) g_px.limit=PlTickRound(2.0*mid-g_px.limit);
   g_px.sl=PlTickRound(2.0*mid-g_px.sl);
   for(int i=0;i<PL_MAX_TP;i++) g_px.tp[i]=PlTickRound(2.0*mid-g_px.tp[i]);
   if(g_dr.kind==PL_KIND_MARKET)
     {
      //--- the entry of the other side
      g_px.entry=(g_px.sl<mid)?g_sym.ask:g_sym.bid;
     }
  }

void PlSetKind(const PlKind k)
  {
   if(k==g_dr.kind) return;
   PlRecalc();
   int dir=(g_plan.side==PL_SIDE_SELL)?-1:1;
   if(!g_plan.ok) dir=PlEstDir();
   double exec=g_plan.ok?g_plan.exec:PlEstExec();
   double d=MathAbs(exec-g_px.sl);
   if(d<=0.0 || g_px.sl<=0.0) d=MathAbs(g_dr.sl_ticks)*g_sym.tick_size;
   //--- the price went through the SL line: a new type is no move of the side, the lines go back to the trader's side at
   //--- the distance saved before the crossing
   if(g_side_crossed && g_side_set!=0)
     {
      dir=g_side_set;
      if(g_dr.sl_ticks!=0.0) d=MathAbs(g_dr.sl_ticks)*g_sym.tick_size;
     }
   g_dr.kind=k;
   PlSetupPrices(d,dir,k);          // PlLinesSync moves the lines and adds or removes the Limit line
  }

void PlHandleMenu(const int key,const int opt)
  {
   PlFldClearBad();
   switch(key)
     {
      case MK_BASE:     g_cfg.base=opt; break;
      case MK_SUB_OPEN: g_cfg.subtract_open=!g_cfg.subtract_open; break;
      case MK_OVERMAX:  g_cfg.over_max=(int)PlClampD((double)opt,0,2); break;
      case MK_ATR:      g_cfg.atr_on=!g_cfg.atr_on; PlAtrUpdate(); break;
      case MK_TPCOUNT:
         g_cfg.tp_count=opt+1;
         //--- shares set while there were fewer TPs: the first TP keeps at least 1 percent (the input checks the same sum)
         if(g_cfg.tp_count>=3 && g_cfg.tp_share2+g_cfg.tp_share3>99.0) g_cfg.tp_share3=MathMax(1.0,99.0-g_cfg.tp_share2);
         {
          //--- new TP lines start at their R from the entry
          double exec=g_plan.ok?g_plan.exec:PlEstExec();
          double d=MathAbs(exec-g_px.sl);
          int dir=PlEstDir();
          for(int i=1;i<PL_MAX_TP;i++)
             if(i<g_cfg.tp_count && (g_px.tp[i]<=0.0 || g_dr.tp_price[i]==false))
                g_px.tp[i]=PlTickRound(exec+dir*g_dr.tp_r[i]*d);
         }
         break;
      case MK_NO_SL:    g_cfg.no_sl=!g_cfg.no_sl; break;
      case MK_NO_TP:    g_cfg.no_tp=!g_cfg.no_tp; break;
      case MK_EXPIRY:   g_cfg.expiry_mode=opt; break;
      case MK_CONFIRM:  g_cfg.confirm_on=!g_cfg.confirm_on; break;
      case MK_BE:       g_cfg.be_on=!g_cfg.be_on; break;
      case MK_TRAIL:    g_cfg.trail_on=!g_cfg.trail_on; break;
      case MK_CLOSEBTN: g_cfg.close_btns=!g_cfg.close_btns; break;
      case MK_THEME:    g_cfg.theme=opt; PlThemeApply(g_cfg.theme); break;
      case MK_SCALE:    g_cfg.scale=opt; PlFollowDefaultTop(); break;
      case MK_QSTYLE:   g_cfg.quick_style=(int)PlClampD((double)opt,0,1); PlFollowDefaultTop(); break;
      case MK_SOUNDS:   g_cfg.sounds=!g_cfg.sounds; if(g_cfg.sounds) PlaySound(PL_SND_OPEN); break;       // the switch answers with the sound
     }
   PlSettingsSave();
   PLDBG("MENU key="+(string)key+" opt="+(string)opt);
   PlModelChanged();
  }

//=================================================================================================
//  the order flow: press, confirmation, send, check, cool-down
//=================================================================================================
//--- the frozen plan taken at the first press
void PlTakeSnap()
  {
   g_snap.symbol=PlOwnCopy(g_sym.name);
   g_snap.in=g_in;
   g_snap.kind=g_dr.kind; g_snap.side=g_plan.side; g_snap.order_type=g_plan.order_type;
   g_snap.lot=g_res.lot; g_snap.risk_money=g_res.risk_money; g_snap.risk_pct=g_res.risk_percent;
   g_snap.entry=g_plan.entry; g_snap.limit=g_plan.limit; g_snap.sl=g_plan.sl;
   bool tp_on[PL_MAX_TP]; double share[PL_MAX_TP];
   for(int i=0;i<PL_MAX_TP;i++)
     {
      g_snap.tp[i]=g_plan.tp[i];
      tp_on[i]=(g_in.tp[i].on && !g_in.no_tp && g_plan.tp[i]>0.0);
      share[i]=g_in.tp[i].share;
     }
   g_snap.tp_count=g_cfg.no_tp?0:g_cfg.tp_count;
   double lots[]; int idx[]; string note;
   g_snap.parts=PlSplitOrders(g_acc.margin_mode==ACCOUNT_MARGIN_MODE_RETAIL_HEDGING,g_res,g_sym.vol_min,g_sym.vol_step,tp_on,share,lots,idx,note);
   g_snap.mid=(g_sym.ask+g_sym.bid)/2.0; g_snap.dist=g_plan.dist;
   g_snap.net_vol=g_sym.net_vol; g_snap.net_sl=g_sym.net_sl;
   g_snap.verdict=g_res.verdict; g_snap.reason=g_res.reason;
   g_snap.trail_val=g_dr.trail_dist;
   g_snap.magic=g_cfg.magic; g_snap.comment=g_cfg.comment;
   g_snap.expiry_mode=g_cfg.expiry_mode; g_snap.expiry_hours=g_cfg.expiry_hours;
   g_snap.netting_ack=false;
  }

void PlLogResult()
  {
#ifdef PL_DEV_LOG
   string ids="";
   for(int i=0;i<PL_MAX_PARTS;i++) if(g_sres.ids[i]!=0) ids+=(ids==""?"":",")+(string)g_sres.ids[i];
   PLDBG("RESULT status="+(string)(int)g_sres.status+" rc="+(string)g_sres.retcode+" err="+(string)g_sres.err+" reason="+(string)(int)g_sres.reason
         +" parts="+(string)g_sres.parts_sent+"/"+(string)g_sres.parts_planned+" vol="+DoubleToString(g_sres.vol_done,3)+"/"+DoubleToString(g_sres.vol_planned,3)
         +" price="+DoubleToString(g_sres.price_done,g_sym.digits)+" risk="+DoubleToString(g_sres.risk_done,2)+" new_lot="+DoubleToString(g_sres.new_lot,3)
         +" net_add="+(string)(int)g_sres.net_add+" ids="+ids+" tag="+g_sres.tag+" phrase='"+g_sres.phrase+"' note='"+g_sres.note+"'");
#endif
  }

//--- the chart symbol from the terminal. g_sym_thin is judged on what this read returned (tick value, margin at Ask/Bid),
//--- not on g_sym later: the plan-price margin of PlFillTerminalCalcs overwrites it with 0 when OrderCalcMargin fails there,
//--- and that must not make the timer read the symbol every 2 s for ever (the BLOCK for the margin stays as it is).
bool g_sym_thin=true;
bool PlReadChartSymbol()
  {
   const bool ok=PlReadSymbol(_Symbol,g_sym);
   g_sym_thin=(g_sym.tick_value_loss<=0.0 || g_sym.margin_buy_1lot<=0.0);
   return ok;
  }

//--- fresh symbol and account numbers before a plan is frozen or sent
void PlRefreshFresh()
  {
   PlReadChartSymbol();
   PlDevAdjustSym(g_sym);
   PlReadAccount(g_acc);
   PlDevAdjustAcct(g_acc);
   PlRecalc();
  }

bool PlCanPress()
  {
   return (g_plan.ok && g_plan.side!=PL_SIDE_NONE && g_res.verdict!=PL_BLOCK && !PlAnyBadField());
  }

//--- the order the panel would send is an add to the open position of a netting account (the same test SendOrderSafe makes at its step 6,
//--- from the numbers the panel holds)
bool PlIsNettingAdd()
  {
   return (g_acc.margin_mode!=ACCOUNT_MARGIN_MODE_RETAIL_HEDGING && g_sym.net_vol>PL_EPS
           && g_plan.side!=PL_SIDE_NONE && g_sym.net_buy==(g_plan.side==PL_SIDE_BUY));
  }

void PlArm(const bool netting_ack)
  {
   PlTakeSnap();
   g_snap.netting_ack=netting_ack;
   g_flow=PL_FLOW_ARMED;
   g_armed_at=GetTickCount64();
   g_confirm_sig=PlConfirmSig(); g_confirm_net=PlConfirmNet();
   g_arm_conn=g_acc.connected;
   PlFlowSync();
   PLDBG("ARMED "+PlSideWord()+" kind="+(string)(int)g_snap.kind+" lot="+DoubleToString(g_snap.lot,3)+" parts="+(string)g_snap.parts
         +" sl="+DoubleToString(g_snap.sl,g_sym.digits)+" tp="+DoubleToString(g_snap.tp[0],g_sym.digits)+" risk="+DoubleToString(g_snap.risk_money,2));
  }

void PlFlowAfterSend()
  {
   const ulong now=GetTickCount64();
   PlLogResult();
   switch(g_sres.status)
     {
      case PL_SS_UNKNOWN:
         g_flow=PL_FLOW_CHECKING; g_t_rc=now;
         PlMessage(g_sres.phrase,30000,0);
         break;
      case PL_SS_RECONFIRM:
        {
         const string ph=g_sres.phrase;
         const bool nett=(g_sres.reason==PL_R_NETTING_ADD);
         g_flow=PL_FLOW_IDLE;
         PlRefreshFresh();
         if(PlCanPress()) { PlArm(nett); PlMessage(ph,4000,0); }
         else PlMessage(ph,4000,2);
         break;
        }
      default:
        {
         string rw="";
         PlRecAfterOpen(g_snap,g_sres,rw);
         const bool good=(g_sres.status==PL_SS_DONE || g_sres.status==PL_SS_PLACED);
         const bool lost=(g_sres.status==PL_SS_UNRESOLVED) || (g_sres.status==PL_SS_PARTS_SHORT && g_unk_sym!="" && g_unk_sym==g_snap.symbol);
         string t=g_sres.phrase;
         if(g_sres.note!="") t+=". "+g_sres.note;
         if(g_sres.net_add && (g_cfg.be_on || g_cfg.trail_on)) t+=". "+PLS_NET_ADD_MGMT;
         bool warned=false;
         if(rw!="") { t+=". "+rw; warned=true; }
         PlMessage(t,lost?30000:6000,(good && !warned)?1:2);
         g_flow=PL_FLOW_COOLDOWN; g_cool_until=now+PL_COOLDOWN_MS;
         //--- the lines of the plan lie on the levels of the new position or order, and a drag there would take the level of MT5: they go,
         //--- the eye brings them back for the next trade
         if(good && PlLinesOn()) { g_lines_hid=_Symbol; PLDBG("ACT lines hidden after a fill"); if(g_prices_ok) { PlLinesSync(); PlLinesLabels(); } }
        }
     }
   PlFlowSync();
   g_risk_dirty=true;
   g_key="";
   if(g_panel.Created()) { g_panel.Redraw(); ChartRedraw(); }
  }

void PlDoSend()
  {
   g_flow=PL_FLOW_SENDING;
   PlFlowSync();
   PlMessage(PLS_SENDING,20000,0);
   if(g_panel.Created()) { g_panel.Redraw(); ChartRedraw(); }     // drawn before the call: OrderSend holds the program
   PlReadPositions();                                   // the guard is recounted from this moment
   PlAccount ga; PlReadAccount(ga,false);
   PlGuard g; PlGuardBuild(g,ga);
   PlSendOpen(g_snap,g,g_sres);
   if(!g_cfg.first_sent && g_sres.status!=PL_SS_BLOCKED && g_sres.status!=PL_SS_RECONFIRM) { g_cfg.first_sent=true; PlSettingsSave(); }
   PlFlowAfterSend();
  }

//--- the answer of a lost send arrives by the timer or by a trade event
#ifdef PL_DEV_LOG
ulong g_dev_rc_hold=0;             // development: the check of a lost answer waits until this tick count
#endif
void PlReconcileTick()
  {
   if(g_flow!=PL_FLOW_CHECKING) return;
#ifdef PL_DEV_LOG
   if(GetTickCount64()<g_dev_rc_hold) return;
#endif
   PlSendRes r;
   if(PlTradeReconcileStep(r)) { g_sres=r; PlFlowAfterSend(); }
   else if(r.phrase!=g_msg) { PlMessage(r.phrase,30000,0); g_key=""; if(g_panel.Created()) { g_panel.Redraw(); ChartRedraw(); } }
  }

//--- a click on the action button or Shift+T. ask: Shift+T from an open menu only brings the main view back
//--- and asks first, as if Confirmation were on; the second Shift+T or a click sends
void PlPress(const string source,const bool ask=false)
  {
   const ulong now=GetTickCount64();
   PLDBG("PRESS "+source+" flow="+(string)g_flow);
   if(g_flow==PL_FLOW_SENDING || g_flow==PL_FLOW_CHECKING) return;
   if(g_flow==PL_FLOW_COOLDOWN)
     {
      if(now<g_cool_until) return;
      g_flow=PL_FLOW_IDLE;
     }
   if(g_flow==PL_FLOW_ARMED)
     {
      //--- a press sends only what the panel shows: a red field or one still being typed in refuses it
      if(PlAnyBadField() || g_fl_focus>=0) { PlCancelArm(PlAnyBadField()?PLS_FIX_RED_FIELD:PLS_FINISH_FIELD,true,2); return; }
      const ulong age=now-g_armed_at;
      if(age<PL_ARM_PAUSE_MS) { PLDBG("PRESS too early, ignored"); return; }
      if(age>PL_ARM_WINDOW_MS) { PlCancelArm(PLS_CONFIRM_TIMEOUT); return; }
      if(g_unk_sym!="" && g_unk_sym==g_snap.symbol)
        {
         g_unk_sym="";                                         // the confirmed press is the acknowledgement
         if(g_snap.verdict==PL_CONFIRM) { g_msg=""; PlArm(false); g_panel.Redraw(); ChartRedraw(); return; }     // the plan's own confirmation was hidden by the warning: ask it now
        }
      PlDoSend();
      return;
     }
   if(g_fl_focus>=0) { PlMessage(PLS_FINISH_FIELD,3500,2); g_key=""; g_panel.Redraw(); ChartRedraw(); return; }
   if(PlAnyBadField()) { PlMessage(PLS_FIX_RED_FIELD,3500,2); g_key=""; g_panel.Redraw(); ChartRedraw(); return; }
   PlRefreshFresh();
   if(!PlCanPress()) { PLDBG("PRESS cannot: plan_ok="+(string)g_plan.ok+" verdict="+(string)(int)g_res.verdict+" reason="+(string)(int)g_res.reason); g_panel.Redraw(); ChartRedraw(); return; }
   //--- the last open on this symbol had no answer: this press only arms, and says why (the second press is the acknowledgement)
   const bool unk=(g_unk_sym!="" && g_unk_sym==g_sym.name);
   //--- the very first trade of this terminal asks once, whatever Confirmation says: the button then shows the lot and the risk (g_cfg.first_sent)
   if(g_cfg.confirm_on || ask || !g_cfg.first_sent || g_res.verdict==PL_CONFIRM || g_res.split_n>1 || unk)      // a split always asks first
     {
      //--- an add to a netting position: the confirmation that is asked anyway says "adds to the open position, SL, TP and risk are for all of it"
      //--- (the status line, PlStatusText), so this press is the acknowledgement and the send does not ask a second time. A confirmation of the
      //--- core (high risk, the minimum lot above the risk and the like) keeps the status line for its own warning, so there the add asks again
      //--- after it, as before: a warning about money is never hidden behind another phrase
      PlArm(PlIsNettingAdd() && g_res.verdict!=PL_CONFIRM);
      if(unk) PlMessage(PLS_UNKNOWN_WARN,PL_ARM_WINDOW_MS,2);
      g_panel.Redraw(); ChartRedraw();
      return;
     }
   PlTakeSnap();
   PlDoSend();
  }

//--- Shift+T: the main view first when the menu is open, then it arms the confirmation, also with Confirmation off:
//--- a capital T typed on the chart (TSLA, ETHUSD) is the same key, so one press must never send. The next Shift+T or a click
//--- sends, with the same pause and window as any confirmation; any other key cancels it (PlOnKey), so typing a symbol only arms
//--- and lets go. The button itself stays one click when Confirmation is off.
void PlHotkeyAct()
  {
   const bool from_hidden=(g_panel.menu && !g_cfg.quick);
   if(from_hidden)
     {
      g_panel.menu=false;
      PlFldClearBad();
      g_panel.Redraw(); ChartRedraw();
     }
   PlPress("hotkey",true);
  }

void PlOnKey(const int key,const string sp)
  {
   PLDBG("KEY code="+(string)key+" sparam="+sp+" shift="+(string)TerminalInfoInteger(TERMINAL_KEYSTATE_SHIFT));
   PlStickyClear();
   if(key==27)
     {
      //--- an unfinished edit is forced back to the model text: PlCancelArm redraws nothing while IDLE, so redraw here
      if(g_fl_focus>=0) { g_fl_text[g_fl_focus]="~"; g_fl_focus=-1; g_panel.Redraw(); ChartRedraw(); }
      PlCancelArm(PLS_CANCELLED);
      return;
     }
   //--- Enter is not a confirmation: with the chart in focus MT5 opens its "symbol,period" box on Enter, and once the confirmation
   //--- has lapsed the key would reach the terminal and could change the symbol of the chart at the moment of a trade
   //--- any other key while a confirmation waits cancels it: a capital T typed into a symbol name (TSLA, ETHUSD) arms, the next
   //--- letter lets go. Shift, Ctrl, Alt, Caps Lock and the Windows keys alone change nothing.
   if(key!=84)
     {
      if(g_flow==PL_FLOW_ARMED && key!=16 && key!=17 && key!=18 && key!=20 && key!=91 && key!=92) PlCancelArm(PLS_CANCELLED);
      return;
     }
   if(TerminalInfoInteger(TERMINAL_KEYSTATE_SHIFT)>=0) { if(g_flow==PL_FLOW_ARMED) PlCancelArm(PLS_CANCELLED); return; }     // a plain t is a letter too
   if(TerminalInfoInteger(TERMINAL_KEYSTATE_CONTROL)<0 || TerminalInfoInteger(TERMINAL_KEYSTATE_MENU)<0) return;      // Shift+T only: Ctrl+Shift+T and Alt+Shift+T are other shortcuts
   if((StringToInteger(sp)&0x4000)!=0) { PLDBG("KEY autorepeat ignored"); return; }
   const ulong now=GetTickCount64();
   if(g_last_hotkey!=0 && now-g_last_hotkey<500) return;
   g_last_hotkey=now;
   PlHotkeyAct();
  }

//--- an edit field was left (Enter or a click away): apply it, or mark it red
void PlOnEndEdit(const int f)
  {
   g_fl_focus=-1;
   string t=PlFldGetText(f);
   if(t==g_fl_text[f])       // the text the panel last wrote: nothing to apply, nothing bad
     {
      g_fl_bad[f]=false;
      g_panel.Redraw(); ChartRedraw();
      return;
     }
   g_fl_bad[f]=false;
   if(PlFieldApply(f,t))
     {
      g_fl_text[f]="~";
      g_panel.Redraw();
      ChartRedraw();
      PLDBG("ACT field "+(string)f+" applied '"+t+"'");
     }
   else
     {
      g_fl_bad[f]=true;
      PlCancelArm("",false);
      g_panel.Redraw();
      ChartRedraw();
      PLDBG("ACT field "+(string)f+" rejected '"+t+"'");
     }
  }

void PlHandleAct(const int id,const int arg)
  {
   switch(id)
     {
      case H_MENU:
         PlCancelArm("",false);            // the menu replaces the main view: the confirmation lapses
         g_panel.Redraw(); ChartRedraw();
         return;
      case H_LINES:
         //--- the lines only leave the chart: prices, lot and an armed confirmation stay as they are. After a fill the lines are hidden for this
         //--- chart only (g_lines_hid); the eye brings them back without touching the saved setting, which is the terminal's
         {
            const bool was_hid=(g_lines_hid==_Symbol);
            g_lines_hid="";
            if(!was_hid || !g_cfg.lines) { g_cfg.lines=!g_cfg.lines; PlSettingsSave(); }
         }
         PLDBG("ACT lines="+(string)PlLinesOn());
         if(g_prices_ok) { PlLinesSync(); PlLinesLabels(); }
         g_panel.Redraw(); ChartRedraw();
         return;
      case H_COLLAPSE:
         PlCancelArm("",false);
         PlSettingsSave();
         PLDBG("ACT quick="+(string)g_cfg.quick);
         PlFollowDefaultTop();
         g_panel.Redraw(); ChartRedraw();
         return;
      case H_KIND:
         PlFldClearBad();
         PlCancelArm("",false);
         PlSetKind((PlKind)arg);
         PLDBG("ACT kind="+(string)arg);
         PlModelChanged();
         return;
      case H_QKIND:
         //--- the quick strip: Market, and a second segment that is Limit, Stop or Stop-Limit as the type stands. A click on Market is a click
         //--- on Market of the full panel; a click on the second one while the type is Market sets Limit (the Entry line goes where a Limit
         //--- sits, and PlAutoKind moves on to Stop if the line is dragged across the price); while the type is pending it changes nothing
         if(arg==1 && g_dr.kind!=PL_KIND_MARKET) return;
         PlFldClearBad();
         PlCancelArm("",false);
         PlSetKind((arg==0)?PL_KIND_MARKET:PL_KIND_LIMIT);
         PLDBG("ACT qkind="+(string)arg);
         PlModelChanged();
         return;
      case H_CHIP:
         if(arg>2) return;                 // only the three quick percents are buttons (the strip types any other risk in its field)
         g_dr.unit_money=false; g_dr.risk_pct=(arg==0)?0.5:(arg==1)?1.0:2.0;     // a quick button is a percent, the field shows it
         g_fl_bad[PLF_RISK]=false; g_fl_text[PLF_RISK]="~";
         PlSettingsSave();                 // the last risk is the terminal's, the next symbol opens with it
         PLDBG("ACT chip="+(string)arg);
         PlModelChanged();
         return;
      case H_UNIT:
        {
         //--- the same risk in the other unit: nothing changes but the way it is written
         double base=(g_cfg.base==PL_BASE_EQUITY)?g_acc.equity:g_acc.balance;
         if(arg==1 && !g_dr.unit_money && base>0.0)
            g_dr.risk_money=NormalizeDouble(base*g_dr.risk_pct/100.0,g_acc.currency_digits);
         if(arg==0 && g_dr.unit_money && base>0.0)
            g_dr.risk_pct=NormalizeDouble(g_dr.risk_money/base*100.0,2);
         g_dr.unit_money=(arg==1);
         g_fl_bad[PLF_RISK]=false; g_fl_text[PLF_RISK]="~";
         PlSettingsSave();
         PLDBG("ACT unit_money="+(string)g_dr.unit_money);
         PlModelChanged();
         return;
        }
      case H_SWAP:
         PlCancelArm("",false);
         PlMirror();
         PLDBG("ACT mirror");
         PlModelChanged();
         return;
      case H_ACTION:
         PlPress("click");
         return;
      case H_CANCEL:
         PlCancelArm(PLS_CANCELLED);
         return;
      case H_ROW_X:
        {
         //--- a press on a position row is another action: the confirmation of the new trade lapses, so the answer of the row (a close,
         //--- a breakeven, already at breakeven) is shown and not held back as a note behind an armed phrase
         PlCancelArm("",false);
         //--- the row is the one pressed (by its id), not the one that sits at that index by now
         const int ri=(g_panel.act_tid!=0)?PlOwnFind(g_panel.act_tid):-1;
         if(ri<0) { g_key=""; g_panel.Redraw(); ChartRedraw(); return; }
         if(PlTradeBusy()) { PlMessage(PLS_BUSY,3500,2); g_panel.Redraw(); ChartRedraw(); return; }
         const PlOwn o=g_own[ri];
         if(PlCbClick(1,o.id,false))
           {
            string ph;
            const bool okc=PlOwnClose(o,0.0,ph);
            PlMessage(ph,6000,okc?1:2);
            g_risk_dirty=true;
           }
         g_key="";
         g_panel.Redraw(); ChartRedraw();
         return;
        }
      case H_ROW_BTN:
        {
         PlCancelArm("",false);            // as for the close button of the row
         const int btn=arg%8;
         const int row=(g_panel.act_tid!=0)?PlOwnFind(g_panel.act_tid):-1;
         if(row<0) { g_key=""; g_panel.Redraw(); ChartRedraw(); return; }
         const PlOwn o=g_own[row];
         if(btn==0) PlRecBreakevenNow(row);
         else if(btn==1)
           {
            if(PlTradeBusy()) { PlMessage(PLS_BUSY,3500,2); }
            else if(PlCbClick(3,o.id,false))
              {
               string ph;
               const bool okp=PlOwnClose(o,g_cfg.part_pct,ph);
               PlMessage(ph,6000,okp?1:2);
               g_risk_dirty=true;
              }
           }
         else if(btn==2) PlRecToggleBe(row);
         else if(btn==3) PlRecToggleTrail(row);
         g_key="";
         g_panel.Redraw(); ChartRedraw();
         return;
        }
      case H_BULK:
        {
         PlCancelArm("",false);            // as for the close button of the row
         if(PlTradeBusy()) { PlMessage(PLS_BUSY,3500,2); g_panel.Redraw(); ChartRedraw(); return; }
         if(PlCbClick(2,(ulong)arg,true))
           {
            PlAccount ba; PlReadAccount(ba,false);
            PlMessage(PlBulkClose(arg,g_sym.name,ba),8000,1);
            g_risk_dirty=true;
           }
         g_key="";
         g_panel.Redraw(); ChartRedraw();
         return;
        }
      case H_COMM_KIND:
        {
         PlCommKind k=g_dr.comm.kind;
         if(k==PL_COMM_UNKNOWN) k=PL_COMM_LOT_SIDE;
         else if(k==PL_COMM_LOT_SIDE) k=PL_COMM_LOT_ROUND;
         else if(k==PL_COMM_LOT_ROUND) k=PL_COMM_PERCENT_SIDE;
         else k=PL_COMM_UNKNOWN;
         //--- a rate means nothing in another kind (2.5 per lot is not 2.5 percent): a new kind starts from the broker's
         //--- rate when the broker's rule has that kind, else from 0, shown in the field for the user to type
         PlCommKind bk; double brt, bmin; bool bz;
         const bool seed=(k!=PL_COMM_UNKNOWN && PlCommRuleOf(_Symbol,bk,brt,bmin,bz) && bk==k);
         g_dr.comm.kind=k;
         g_dr.comm.source=(k==PL_COMM_UNKNOWN)?PL_COMMSRC_NONE:PL_COMMSRC_USER;
         g_dr.comm.rate=seed?brt:0.0;
         g_fl_text[PLF_COMM_RATE]="~";
         PLDBG("ACT comm_kind="+(string)(int)k);
         PlModelChanged();
         return;
        }
      case H_COMM_USE:
         if(g_hint_ok)
           {
            PlCommKind hk; double hrt;
            PlHintToComm(g_hint_in,g_hint_out,g_hint_closed,hk,hrt);
            g_dr.comm.kind=hk; g_dr.comm.rate=hrt; g_dr.comm.source=PL_COMMSRC_HINT;
            g_fl_text[PLF_COMM_RATE]="~"; g_fl_bad[PLF_COMM_RATE]=false;
            PlModelChanged();
           }
         return;
      case H_TOG:
         PlHandleMenu(arg,0);
         return;
      case H_SEG:
         PlHandleMenu(arg/8,arg%8);
         return;
      case H_RESET:
         {
          //--- the menu goes back to defaults, the trader's risk stays (it is not a menu setting)
          const bool ru=g_dr.unit_money; const double rp=g_dr.risk_pct, rm=g_dr.risk_money;
          const bool fs=g_cfg.first_sent;                // what the terminal has done is not a menu setting either
          PlSettingsDefaults();
          g_dr.unit_money=ru; g_dr.risk_pct=rp; g_dr.risk_money=rm; g_cfg.first_sent=fs;
         }
         PlThemeApply(g_cfg.theme);
         PlSettingsSave();
         for(int i=0;i<PLF_COUNT;i++) { g_fl_bad[i]=false; g_fl_text[i]="~"; }
         PLDBG("ACT reset to defaults");
         PlModelChanged();
         return;
     }
  }

//--- the entry line was dragged while the kind is Market: pick the pending kind by position
//--- the order type follows where the user put the Entry: Market, Limit and Stop are one choice made from the lines, so a dragged
//--- or typed Entry or SL never leaves a pending order stuck on the wrong side of the price. The side is the core's (SL against
//--- the entry, without SL the first TP), then a buy above Ask is a Stop and below a Limit, a sell below Bid a Stop and above a
//--- Limit; an entry within the tolerance tol of that price (about 6 logical px, PlMarketTol; at least 2 ticks) is Market. Only a user action calls this: a price that moves past a resting
//--- entry keeps the order type and blocks (the order would mean something else), and Stop-Limit is left to its button.
//--- snap=false while the mouse still holds the line: the type follows, the entry is not moved under the pointer.
//--- the Market zone of a dragged Entry as a price tolerance: about 6 logical px (6 times the panel scale in screen pixels) of the chart's own
//--- price scale, the visible price range over the height of the chart; never less than 2 ticks, which is also what a chart without a range gets.
//--- PlAutoKind (a pure choice of the order type) receives only this number.
double PlMarketTol()
  {
   const double lo2=2.0*g_sym.tick_size;
   const double hi=ChartGetDouble(0,CHART_PRICE_MAX), lo=ChartGetDouble(0,CHART_PRICE_MIN);
   const int ch=(int)ChartGetInteger(0,CHART_HEIGHT_IN_PIXELS);
   if(ch<=0 || hi<=lo) return lo2;
   return MathMax(lo2,6.0*PlScaleGet(g_cfg.scale)*(hi-lo)/ch);
  }

void PlAutoKind(const bool entry_moved,const bool snap,const double tol)
  {
   if(g_dr.kind==PL_KIND_STOP_LIMIT) return;
   if(g_dr.kind==PL_KIND_MARKET && !entry_moved) return;      // a market entry is the price itself, an SL alone does not move it
   const double e=g_px.entry;
   if(e<=0.0 || g_sym.ask<=0.0 || g_sym.bid<=0.0) return;
   int dir=0;
   if(!g_cfg.no_sl)
     {
      if(g_px.sl>0.0 && g_px.sl<e-PL_EPS) dir=1;
      else if(g_px.sl>e+PL_EPS) dir=-1;
     }
   else if(!g_cfg.no_tp && g_px.tp[0]>0.0 && MathAbs(g_px.tp[0]-e)>PL_EPS)
      dir=(g_px.tp[0]>e)?1:-1;
   if(dir==0) return;                                        // no side yet: the core says why
   const double ref=(dir>0)?g_sym.ask:g_sym.bid;
   PlKind k;
   if(MathAbs(e-ref)<=tol+PL_EPS) k=PL_KIND_MARKET;
   else if(dir>0) k=(e<ref)?PL_KIND_LIMIT:PL_KIND_STOP;
   else k=(e>ref)?PL_KIND_LIMIT:PL_KIND_STOP;
   if(k==PL_KIND_MARKET)
     {
      if(!snap) return;                                      // decided at the drop
      g_px.entry=ref;
     }
   if(k==g_dr.kind) return;
   g_dr.kind=k;
   PlMessage(PLS_ENTRY_MOVED+string(dir>0?PLS_BUY_SP:PLS_SELL_SP)+PlKindName(k));
   PLDBG("ACT entry moved, kind="+(string)(int)k);
  }

#ifdef PL_DEV_LOG
//--- development driver ---------------------------------------------------------------------------
void PlDevMarker(const bool on)
  {
   string nm="PL_Mark";
   if(!on) { ObjectDelete(0,nm); return; }
   if(ObjectFind(0,nm)>=0) return;
   ObjectCreate(0,nm,OBJ_RECTANGLE_LABEL,0,0,0);
   ObjectSetInteger(0,nm,OBJPROP_XDISTANCE,0);
   ObjectSetInteger(0,nm,OBJPROP_YDISTANCE,0);
   ObjectSetInteger(0,nm,OBJPROP_XSIZE,3);
   ObjectSetInteger(0,nm,OBJPROP_YSIZE,3);
   ObjectSetInteger(0,nm,OBJPROP_BGCOLOR,clrMagenta);
   ObjectSetInteger(0,nm,OBJPROP_COLOR,clrMagenta);
   ObjectSetInteger(0,nm,OBJPROP_BORDER_TYPE,BORDER_FLAT);
   ObjectSetInteger(0,nm,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,nm,OBJPROP_HIDDEN,true);
  }

ENUM_TIMEFRAMES PlDevTf(const string s)
  {
   if(s=="M1") return PERIOD_M1; if(s=="M5") return PERIOD_M5; if(s=="M15") return PERIOD_M15;
   if(s=="M30") return PERIOD_M30; if(s=="H1") return PERIOD_H1; if(s=="H4") return PERIOD_H4;
   if(s=="D1") return PERIOD_D1;
   return PERIOD_CURRENT;
  }

void PlDevCommand(const string cmd)
  {
   string p[];
   int n=StringSplit(cmd,' ',p);
   if(n<1) return;
   PLDBG("CMD "+cmd);
   if(p[0]=="geom") g_panel.LogGeom();
   else if(p[0]=="msg" && n>=3)
     {
      //--- msg <kind 0..2> <text>: shows a status phrase for 20 s (text fit checks without trading)
      string txt=p[2];
      for(int q=3;q<n;q++) txt+=" "+p[q];
      StringReplace(txt," ~ ",PlDotSep());      // the middle dot cannot be typed into the command file
      PlMessage(txt,20000,(int)StringToInteger(p[1]));
      PLDBG("MSG alt "+PlAltOfPhrase(txt));                // the short form of the phrase for the quick card, empty when it has none
      g_panel.Redraw(); ChartRedraw();
     }
   else if(p[0]=="marker") PlDevMarker(n<2 || p[1]!="off");
   else if(p[0]=="sym" && n>=2) { SymbolSelect(p[1],true); PLDBG("CMD chartchange "+p[1]); ChartSetSymbolPeriod(0,p[1],_Period); }
   else if(p[0]=="tf" && n>=2) { PLDBG("CMD tf "+p[1]); ChartSetSymbolPeriod(0,_Symbol,PlDevTf(p[1])); }
   else if(p[0]=="kind" && n>=2) { PlHandleAct(H_KIND,(int)StringToInteger(p[1])); }
   else if(p[0]=="sl" && n>=2) { g_px.sl=PlTickRound(StringToDouble(p[1])); PlModelChanged(); }
   else if(p[0]=="tp" && n>=2) { g_px.tp[0]=PlTickRound(StringToDouble(p[1])); g_dr.tp_price[0]=true; PlModelChanged(); }
   //--- cross: the SL line goes to the other side of the price as if the price had gone through it (not a move of the trader)
   else if(p[0]=="cross") { const double cm=(g_sym.ask+g_sym.bid)/2.0; g_px.sl=PlTickRound(2.0*cm-g_px.sl); g_side_sl=g_px.sl; PlModelChanged(); PLDBG("CROSS sl="+DoubleToString(g_px.sl,g_sym.digits)+" crossed="+(string)g_side_crossed); }
   else if(p[0]=="entry" && n>=2) { g_px.entry=PlTickRound(StringToDouble(p[1])); PlModelChanged(); }
   else if(p[0]=="drag" && n>=3)
     {
      //--- drag <line 0..5> <price>: the line is moved and dropped, the same event path as the mouse
      const int w=(int)StringToInteger(p[1]);
      if(w>=0 && w<PL_LN_COUNT && ObjectFind(0,PlLineName(w))>=0)
        {
         ObjectSetDouble(0,PlLineName(w),OBJPROP_PRICE,StringToDouble(p[2]));
         g_press_in_panel=false;
         const long lp=0; const double dp=0.0; const string nm=PlLineName(w);
         OnChartEvent(CHARTEVENT_OBJECT_DRAG,lp,dp,nm);
        }
     }
   else if(p[0]=="press") PlPress("dev");
   else if(p[0]=="hotkey") PlHotkeyAct();
   else if(p[0]=="cancel") PlCancelArm(PLS_CANCELLED);
   else if(p[0]=="firstsent" && n>=2) { g_cfg.first_sent=(p[1]!="off"); PlSettingsSave(); PlModelChanged(); }      // off: the next trade is the first one of the terminal again
   else if(p[0]=="confirm" && n>=2) { g_cfg.confirm_on=(p[1]!="off"); PlSettingsSave(); PlModelChanged(); }
   else if(p[0]=="fill" && n>=2) g_tr_force_fill=(p[1]=="fok")?ORDER_FILLING_FOK:(p[1]=="ioc")?ORDER_FILLING_IOC:(p[1]=="ret")?ORDER_FILLING_RETURN:-1;
   else if(p[0]=="drop") { if(n>=2) g_tr_dropn=(int)StringToInteger(p[1]); else g_tr_drop=true; }
   else if(p[0]=="reject" && n>=2) { g_tr_rejectn=(int)StringToInteger(p[1]); g_tr_rejectcode=(n>=3)?(uint)StringToInteger(p[2]):TRADE_RETCODE_REJECT; }
   else if(p[0]=="partial") g_tr_partial=true;
   else if(p[0]=="tagoff") g_dev_tagoff=(n<2 || p[1]!="off");
   else if(p[0]=="vslforce") g_dev_vslforce=(n<2 || p[1]!="off");
   else if(p[0]=="fillmask" && n>=2) { g_dev_fillmask=(int)StringToInteger(p[1]); PlRefreshFresh(); }
   else if(p[0]=="expmask" && n>=2) { g_dev_expmask=(int)StringToInteger(p[1]); PlRefreshFresh(); }
   else if(p[0]=="gtcmode" && n>=2) { g_dev_gtcmode=(int)StringToInteger(p[1]); PlRefreshFresh(); }
   else if(p[0]=="stops" && n>=2) { g_dev_stops=(int)StringToInteger(p[1]); PlRefreshFresh(); }       // only the plan and SendOrderSafe: PlSlAllowed reads the terminal
   else if(p[0]=="freeze" && n>=2) { g_dev_freeze=(int)StringToInteger(p[1]); PlRefreshFresh(); }     // the same
   else if(p[0]=="rcclose" && n>=2)
     {
      //--- development: closes a position while a check of a lost answer is held (the reconcile context is saved and put back)
      const bool wa=g_rc_active; const string ws=g_rc_symbol; const string wm=g_rc_match;
      ulong kp[], ko[]; ArrayCopy(kp,g_rc_known_pos); ArrayCopy(ko,g_rc_known_ord);
      g_rc_active=false;
      PlSendRes r; PlSendClosePos((ulong)StringToInteger(p[1]),0.0,r);
      g_rc_active=wa; g_rc_symbol=ws; g_rc_match=wm;
      ArrayResize(g_rc_known_pos,0); ArrayResize(g_rc_known_ord,0); ArrayCopy(g_rc_known_pos,kp); ArrayCopy(g_rc_known_ord,ko);     // ArrayCopy does not shrink
      PLDBG("CMD rcclose "+p[1]+" -> "+r.phrase);
     }
   else if(p[0]=="rcdel" && n>=2)
     {
      g_rc_kind=3; g_rc_ticket=(ulong)StringToInteger(p[1]); PlSendResReset(g_rc_res); g_rc_res.ids[0]=g_rc_ticket;
      g_rc_active=true; g_rc_started=GetTickCount64();
      PLDBG("CMD rcdel started for "+p[1]);
     }
   else if(p[0]=="volmax" && n>=2) { g_dev_volmax=StringToDouble(p[1]); PlRefreshFresh(); }
   else if(p[0]=="rchold" && n>=2) g_dev_rc_hold=GetTickCount64()+(ulong)StringToInteger(p[1]);
   else if(p[0]=="dropfail") g_tr_dropfail=true;
   else if(p[0]=="conn" && n>=2) { g_dev_conn_off=(p[1]=="off"); }
   else if(p[0]=="real" && n>=2) { g_dev_real=(p[1]=="on"); }
   else if(p[0]=="field" && n>=3)
     {
      string txt=p[2];
      for(int q=3;q<n;q++) txt+=" "+p[q];
      bool okf=PlFieldApply((int)StringToInteger(p[1]),txt);
      PLDBG("CMD field "+p[1]+" '"+txt+"' -> "+(string)okf);
     }
   else if(p[0]=="mirror") { PlHandleAct(H_SWAP,0); }
   else if(p[0]=="objdel" && n>=2) { ObjectDelete(0,p[1]); ChartRedraw(); }
   else if(p[0]=="endedit" && n>=2)
     {
      //--- drives the ENDEDIT paths without typing: the text (none: what the edit shows now) goes into the edit, then the same handler as the event
      string txt=(n>=3)?p[2]:"";
      for(int q=3;q<n;q++) txt+=" "+p[q];
      const int ef=(int)StringToInteger(p[1]);
      if(ef>=0 && ef<PLF_COUNT && ObjectFind(0,PlFldName(ef))>=0)
        {
         if(n>=3) ObjectSetString(0,PlFldName(ef),OBJPROP_TEXT,txt);
         PlOnEndEdit(ef);
        }
     }
   else if(p[0]=="focus" && n>=2)
     {
      if(p[1]=="off") g_fl_focus=-1;
      else g_fl_focus=(int)StringToInteger(p[1]);
      PLDBG("FOCUS "+(string)g_fl_focus);
     }
   else if(p[0]=="curshow" && n>=2) { g_dev_cur_show=(p[1]=="off")?"":p[1]; g_panel.Redraw(); ChartRedraw(); }
   else if(p[0]=="fmtcheck")
     {
      const long ls[]={0,59,60,3540,3599,3600,14399,14400,35999,36000,86400,93600};
      string r="FMT left:";
      for(int q=0;q<ArraySize(ls);q++) r+=" "+(string)ls[q]+"->"+PlLeftText(ls[q]);
      PLDBG(r);
      const double ps[]={0.0,0.004,0.0049,0.005,1.234};
      r="FMT pct:";
      for(int q=0;q<ArraySize(ps);q++) r+=" "+DoubleToString(ps[q],4)+"->"+PlPctText(ps[q]);
      PLDBG(r);
      PLDBG("FMT cur: UST->["+PlCurrencyMark("UST")+"] USD->["+PlCurrencyMark("USD")+"] ' UST '->["+PlCurrencyMark(" UST ")+"] sign UST->["+PlCurrencySign("UST")+"]");
     }
   else if(p[0]=="bench")
     {
      //--- bench [symbol] [other symbol]: the cost of the commission reads, 1000 calls each
      const string bs=(n>=2)?p[1]:_Symbol;
      const string bo=(n>=3)?p[2]:"GBPUSD";
      const int bn=1000;
      MqlCommission bc[]; int bok=0;
      const ulong b0=GetMicrosecondCount();
      for(int q=0;q<bn;q++) bok+=SymbolInfoCommissions(bs,bc);
      const ulong b1=GetMicrosecondCount();
      PlCommKind bk=PL_COMM_UNKNOWN; double br=0.0, bmn=0.0; bool bz=false;
      const double bvmin=SymbolInfoDouble(bs,SYMBOL_VOLUME_MIN);
      for(int q=0;q<bn;q++) PlCommRule(bs,bvmin,bk,br,bmn,bz);
      const ulong b2=GetMicrosecondCount();
      bool buh=false;
      for(int q=0;q<bn;q++) buh=PlUserComm(bo,bk,br);
      const ulong b3=GetMicrosecondCount();
      PLDBG("BENCH n="+(string)bn+" "+bs+" SymbolInfoCommissions avg_us="+DoubleToString((double)(b1-b0)/bn,2)+" (returned "+(string)bok+")"
            +" PlCommRule avg_us="+DoubleToString((double)(b2-b1)/bn,2)+" | "+bo+" PlUserComm avg_us="+DoubleToString((double)(b3-b2)/bn,2)+" has="+(string)buh);
     }
   else if(p[0]=="comm" && n>=3)
     {
      //--- comm <kind 0..3> <rate>: the commission setting of this chart's symbol, as the Commission section of the menu would set it
      g_dr.comm.kind=(PlCommKind)(int)PlClampD((double)StringToInteger(p[1]),0,3);
      g_dr.comm.rate=StringToDouble(p[2]); g_dr.comm.source=(g_dr.comm.kind==PL_COMM_UNKNOWN)?PL_COMMSRC_NONE:PL_COMMSRC_USER;
      PlModelChanged();
     }
   else if(p[0]=="act" && n>=3)
     {
      const int aid=(int)StringToInteger(p[1]), aarg=(int)StringToInteger(p[2]);
      const int arow=(aid==H_ROW_BTN)?aarg/8:aarg;
      g_panel.act_tid=((aid==H_ROW_X || aid==H_ROW_BTN || aid==H_ROW_EXP) && arow>=0 && arow<ArraySize(g_own))?g_own[arow].id:0;
      PlHandleAct(aid,aarg);
     }
   else if(p[0]=="undrag") { g_cfg.py=-1; PlFollowDefaultTop(); g_panel.Redraw(); ChartRedraw(); }     // the panel was never dragged: its top follows the view
   else if(p[0]=="nogate" && n>=2) { g_dev_nogate=(p[1]=="on"); }
   else if(p[0]=="algo") PLDBG("ALGO term="+(string)TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)+" mql="+(string)MQLInfoInteger(MQL_TRADE_ALLOWED));
   else if(p[0]=="cfg" && n>=3)
     {
      const bool on=(p[2]!="0" && p[2]!="off");
      if(p[1]=="nosl") g_cfg.no_sl=on;
      else if(p[1]=="subopen") g_cfg.subtract_open=on;
      else if(p[1]=="be") g_cfg.be_on=on;
      else if(p[1]=="closebtn") g_cfg.close_btns=on;
      else if(p[1]=="sounds") g_cfg.sounds=on;
      else if(p[1]=="lines") { g_cfg.lines=on; g_lines_hid=""; }
      else if(p[1]=="trail") g_cfg.trail_on=on;
      else if(p[1]=="atr") { g_cfg.atr_on=on; PlAtrUpdate(); }
      else if(p[1]=="tpcount") g_cfg.tp_count=(int)StringToInteger(p[2]);
      else if(p[1]=="overmax") g_cfg.over_max=(int)PlClampD((double)StringToInteger(p[2]),0,2);
      else if(p[1]=="expiry") g_cfg.expiry_mode=(int)StringToInteger(p[2]);
      PlSettingsSave();
      PlModelChanged();
     }
   else if(p[0]=="sec" && n>=2) { g_panel.OpenSection((int)StringToInteger(p[1]),n>=3); g_panel.Redraw(); ChartRedraw(); }
   else if(p[0]=="wheel" && n>=2) { const int k=(int)StringToInteger(p[1]); for(int q=0;q<MathAbs(k);q++) g_panel.OnWheel(g_panel.X()+10,g_panel.Y()+80,(k>0)?-1.0:1.0); }
   else if(p[0]=="slp" && n>=3)
     {
      //--- SL a number of pips from the market on the side of the trade; an optional TP distance in pips
      const double pip=PlPipSize(g_sym);
      const bool buy=(p[2]=="buy");
      double base=buy?g_sym.ask:g_sym.bid;
      if(g_dr.kind==PL_KIND_LIMIT || g_dr.kind==PL_KIND_STOP) base=g_px.entry;
      else if(g_dr.kind==PL_KIND_STOP_LIMIT) base=g_px.limit;
      g_px.sl=PlTickRound(buy?base-StringToDouble(p[1])*pip:base+StringToDouble(p[1])*pip);
      if(n>=4 && StringToDouble(p[3])>0.0)
        { g_px.tp[0]=PlTickRound(buy?base+StringToDouble(p[3])*pip:base-StringToDouble(p[3])*pip); g_dr.tp_price[0]=true; }
      else g_dr.tp_price[0]=false;
      PlModelChanged();
     }
   else if(p[0]=="entryp" && n>=3)
     {
      const double pip=PlPipSize(g_sym);
      const double mid=(g_sym.ask+g_sym.bid)/2.0;
      g_px.entry=PlTickRound(mid+StringToDouble(p[1])*pip);
      PlModelChanged();
     }
   else if(p[0]=="posblock") { g_cfg.quick=false; g_panel.menu=false; g_panel.costs=false; g_panel.pos_open=(n<2 || p[1]!="off"); g_panel.Redraw(); ChartRedraw(); }      // the full view with Costs closed and the Positions list open (off: collapsed)
   else if(p[0]=="expand" && n>=2) { g_panel.ExpandRow((ulong)StringToInteger(p[1])); g_panel.Redraw(); ChartRedraw(); }
   else if(p[0]=="tpl2" && n>=2)
     {
      //--- a second instance on another chart: this chart's template (with the EA) is applied to it
      const string tn="pl_ea2";
      const bool sv=ChartSaveTemplate(0,tn);
      long id=ChartFirst(); bool ap=false;
      while(id>=0)
        {
         if(id!=ChartID() && ChartSymbol(id)==p[1]) { ap=ChartApplyTemplate(id,tn); break; }
         id=ChartNext(id);
        }
      PLDBG("CMD tpl2 saved="+(string)sv+" applied="+(string)ap);
     }
   else if(p[0]=="closechart" && n>=2)
     {
      long id=ChartFirst();
      while(id>=0)
        {
         if(ChartSymbol(id)==p[1]) { PLDBG("CMD closechart "+p[1]+" id%1000="+(string)(id%1000)); ChartClose(id); break; }
         id=ChartNext(id);
        }
     }
   else if(p[0]=="clone" && n>=2)
     {
      //--- opens a chart of the symbol with this program on it: the template of this chart carries the advisor
      const bool saved=ChartSaveTemplate(0,"pl_clone");
      const long cid=ChartOpen(p[1],(ENUM_TIMEFRAMES)Period());
      PLDBG("CMD clone "+p[1]+" saved="+(string)saved+" chart%1000="+(string)(cid%1000)+" applied="+(string)(cid>0 && ChartApplyTemplate(cid,"pl_clone")));
     }
   else if(p[0]=="closelead")
     {
      //--- closes the chart of the instance that leads (the command file is read by whichever chart polls first)
      PLDBG("CMD closelead symbol="+_Symbol+" was_leader="+(string)g_lead_now);
      if(g_lead_now) ChartClose(0);
     }
   else if(p[0]=="lead")
     {
      const long ld=PlLeaderId();
      string seen="";
      for(long cid=ChartFirst();cid>=0;cid=ChartNext(cid))
         if(ChartGetString(cid,CHART_EXPERT_NAME)==MQLInfoString(MQL_PROGRAM_NAME)) seen+=" "+ChartSymbol(cid)+":"+(string)cid;
      PLDBG("LEAD me="+(string)ChartID()+" leader="+(string)ld+" now="+(string)PlLeadCheck()+" symbol="+_Symbol+" charts="+seen
            +" since="+(string)g_lead_since+" why="+(string)(int)g_lead_why);
      for(long cid=ChartFirst();cid>=0;cid=ChartNext(cid))
         if(ChartGetString(cid,CHART_EXPERT_NAME)==MQLInfoString(MQL_PROGRAM_NAME))
            PLDBG("LEAD chart "+ChartSymbol(cid)+" "+(string)cid+" noalgo="+(string)GlobalVariableCheck(PL_NOALGO_GV+(string)cid));
     }
   else if(p[0]=="own")
     {
      PlOwnRefresh();
      PLDBG("OWN pos="+(string)g_own_pos+" ord="+(string)g_own_ord+" pl="+DoubleToString(g_own_pl,2));
      for(int i=0;i<ArraySize(g_own);i++)
         PLDBG("OWN #"+(string)i+" id="+(string)g_own[i].id+" "+g_own[i].sym+" pending="+(string)g_own[i].pending+" vol="+DoubleToString(g_own[i].vol,2)
               +" open="+DoubleToString(g_own[i].open,5)+" sl="+DoubleToString(g_own[i].sl,5)+" tp="+DoubleToString(g_own[i].tp,5)+" pl="+DoubleToString(g_own[i].pl,2)+" rec="+(string)g_own[i].rec);
     }
   else if(p[0]=="rec")
     {
      PlRecScan();
      PLDBG("REC count="+(string)ArraySize(g_rec));
      for(int i=0;i<ArraySize(g_rec);i++)
         PLDBG("REC id="+(string)g_rec[i].id+" "+g_rec[i].symbol+" type="+(string)g_rec[i].ptype+" t="+(string)g_rec[i].t_open_msc+" dist0="+DoubleToString(g_rec[i].dist0,5)
               +" be="+(string)g_rec[i].be_on+"/"+DoubleToString(g_rec[i].be_r,2)+"/"+(string)g_rec[i].be_done+" trail="+(string)g_rec[i].trail+"/"+DoubleToString(g_rec[i].trail_val,2)
               +" pt="+(string)g_rec[i].pt_n+"/"+DoubleToString(g_rec[i].pt_price[0],5)+","+DoubleToString(g_rec[i].pt_price[1],5)
               +"/"+(string)g_rec[i].pt_done[0]+(string)g_rec[i].pt_done[1]+" expire="+(string)g_rec[i].expire_at+" offs="+(string)g_rec[i].be_off+(string)g_rec[i].trail_off
               +" fails="+(string)g_rec[i].fails+" beo="+(string)g_rec[i].be_off+" tro="+(string)g_rec[i].trail_off+" pto="+(string)g_rec[i].pt_off+" exo="+(string)g_rec[i].exp_off
               +" ptq="+(string)g_rec[i].pt_pend[0]+(string)g_rec[i].pt_pend[1]+" created="+(string)g_rec[i].created);
     }
   else if(p[0]=="setrec" && n>=4)
     {
      const int k=PlRecIndex((ulong)StringToInteger(p[1]));
      if(k>=0)
        {
         if(p[2]=="expire") g_rec[k].expire_at=(long)TimeTradeServer()+StringToInteger(p[3]);
         else if(p[2]=="ber") g_rec[k].be_r=StringToDouble(p[3]);
         else if(p[2]=="trailv") g_rec[k].trail_val=StringToDouble(p[3]);
         else if(p[2]=="trail") g_rec[k].trail=(int)StringToInteger(p[3]);
         else if(p[2]=="be") { g_rec[k].be_on=(p[3]!="0"); g_rec[k].be_done=false; g_rec[k].be_off=false; }
         else if(p[2]=="dist0") g_rec[k].dist0=StringToDouble(p[3]);
         else if(p[2]=="vol0") g_rec[k].vol0=StringToDouble(p[3]);
         else if(p[2]=="ptd1") g_rec[k].pt_done[0]=(p[3]!="0");
         else if(p[2]=="ptd2") g_rec[k].pt_done[1]=(p[3]!="0");
         else if(p[2]=="pt1") g_rec[k].pt_price[0]=StringToDouble(p[3]);
         else if(p[2]=="pt2") g_rec[k].pt_price[1]=StringToDouble(p[3]);
         else if(p[2]=="created") g_rec[k].created=(long)TimeTradeServer()-StringToInteger(p[3]);
         PlRecSave(g_rec[k],PL_RW_ALL);
        }
     }
   else if(p[0]=="recfile" && n>=4)
     {
      //--- edits the record file directly, memory untouched: another chart's write
      const string rf=PlRecFile((ulong)StringToInteger(p[1]));
      if(PlKvLoad(rf) && g_kv_valid) { PlKvSet(p[2],p[3]); PlKvSave(rf); PLDBG("CMD recfile "+p[1]+" "+p[2]+"="+p[3]); }
      else PLDBG("CMD recfile: file not readable");
     }
   else if(p[0]=="recsave" && n>=2)
     {
      const int k=PlRecIndex((ulong)StringToInteger(p[1]));
      if(k>=0) PLDBG("CMD recsave -> "+(string)PlRecSave(g_rec[k],PL_RW_MGR));
     }
   else if(p[0]=="gcnow") { g_t_recgc=0; g_born=1; }
   else if(p[0]=="noalgo" && n>=2)
     {
      const string gv="PL.dev.noalgo."+p[1];
      if(n>=3 && p[2]=="off") { GlobalVariableDel(gv); }
      else if(!GlobalVariableCheck(gv)) GlobalVariableTemp(gv);
     }
   else if(p[0]=="noquote" && n>=2)
     {
      const string gv="PL.dev.noquote."+p[1];
      if(n>=3 && p[2]=="off") { GlobalVariableDel(gv); }
      else if(!GlobalVariableCheck(gv)) GlobalVariableTemp(gv);
     }
   else if(p[0]=="stale" && n>=2) g_dev_stale=(int)StringToInteger(p[1]);
   else if(p[0]=="nodeal") g_dev_nodeal=(n<2 || p[1]!="off");
   else if(p[0]=="rejectall" && n>=2) g_tr_rejectall=(int)StringToInteger(p[1]);
   else if(p[0]=="noexp") g_dev_noexp=(n<2 || p[1]!="off");
   else if(p[0]=="expsec" && n>=2) g_dev_expsec=(int)StringToInteger(p[1]);
   else if(p[0]=="onepos") g_dev_onepos=(n<2 || p[1]!="off");
   else if(p[0]=="netting") { g_dev_netting=(n<2 || p[1]!="off"); PlRefreshFresh(); }
   else if(p[0]=="guards")
     {
      PlGuardCfg c; PlGuardCfgBuild(c);
      PLDBG("GUARDS state="+(string)g_prof_state+" rid="+g_prof_rid+" cap="+DoubleToString(c.portfolio_cap_pct,2)
            +" maxopen="+(string)c.max_open+" maxday="+(string)c.max_day+" muse="+DoubleToString(c.margin_use_pct,1)
            +" hist="+(string)PlHistLoaded()+"/"+(string)g_hist_from_start+" entries="+(string)ArraySize(g_entry_t)+" fp="+(string)g_fp_found+"/"+(string)(long)g_fp_t+"/"+DoubleToString(g_fp_amount,2));
      PLDBG("GUARDS hist sum="+DoubleToString(g_hist_sum,2)+" balance="+DoubleToString(g_acc.balance,2)+" tol="+DoubleToString(PlHistTol(g_acc.currency_digits),4)
            +" unknown="+(string)g_ex_unknown+" profile="+(string)g_prof_state);
      PLDBG("GUARDS out why="+(string)(int)g_lo.why+" verdict="+(string)(int)g_lo.verdict+" max_new="+DoubleToString(g_lo.max_new_risk,2)+" open="+DoubleToString(g_lo.open_risk,2)
            +" pend="+DoubleToString(g_lo.pending_risk,2)+" port="+DoubleToString(g_lo.portfolio_pct,3)+" muse="+DoubleToString(g_lo.margin_use_pct,2)+" no_sl="+(string)g_lo.no_sl);
      string lt="GUARDS text='"+g_guard_text+"' res_verdict="+(string)(int)g_res.verdict+" res_reason="+(string)(int)g_res.reason;
      PLDBG(lt);
     }
   else if(p[0]=="expo")
     {
      PlReadPositions();
      PLDBG("EXPO open_count="+(string)g_ex_open_count+" no_sl="+(string)g_ex_no_sl+" open_risk="+DoubleToString(g_ex_open_risk,2)+" pend_risk="+DoubleToString(g_ex_pend_risk,2)+" unknown="+(string)g_ex_unknown);
      for(int i=0;i<ArraySize(g_ex);i++)
         PLDBG("EXPO #"+(string)i+" pending="+(string)g_ex[i].pending+" has_sl="+(string)g_ex[i].has_sl+" unknown="+(string)g_ex[i].unknown+" pl_at_sl="+DoubleToString(g_ex[i].pl_at_sl,2));
     }
   else if(p[0]=="prof")
     {
      string pf="PROF chart="+(string)(ChartID()%1000)+" state="+(string)g_prof_state+" rid="+g_prof_rid+" cap="+DoubleToString(g_lc.portfolio_cap_pct,2);
      pf+=" seen_len="+(string)StringLen(g_prof_seen)+" any_on="+(string)g_prof_any_on+" fp_found="+(string)g_fp_found;
      PLDBG(pf);
     }
   else if(p[0]=="mk" && n>=3) PlHandleMenu((int)StringToInteger(p[1]),(int)StringToInteger(p[2]));
   else if(p[0]=="rulemin") { g_dev_rulerate=(n>=2)?StringToDouble(p[1]):0.0; g_dev_rulemin=(n>=3)?StringToDouble(p[2]):0.0; PlModelChanged(); }   // rulemin <rate per round> <min per order>, none to clear
   else if(p[0]=="rulezero") { g_dev_rulezero=(n<2 || p[1]!="off"); PlModelChanged(); }
   else if(p[0]=="norule") { g_dev_norule=(n<2 || p[1]!="off"); PlModelChanged(); }
   else if(p[0]=="calcfail") { g_dev_calcfail=(n>=2 && p[1]!="off")?p[1]:""; g_risk_dirty=true; }
   else if(p[0]=="histbad") { g_dev_histbad=(n<2 || p[1]!="off"); g_hist_dirty=true; }
   else if(p[0]=="fpshift" && n>=2)      // fpshift <seconds>: this account reads as another one, handled as a login change (the history is read again)
     {
      g_dev_fpshift=StringToInteger(p[1]);
      PlAccountReset(); PlProfReset();
      g_key="";
     }
   else if(p[0]=="fromstart") { g_dev_fromstart_off=(n>=2 && p[1]=="off"); g_hist_dirty=true; }
   else if(p[0]=="positions")
     {
      int others=0;
      for(int i=PositionsTotal()-1;i>=0;i--)
        {
         ulong tk=PositionGetTicket(i);
         if(tk==0) continue;
         if(PositionGetInteger(POSITION_MAGIC)!=g_cfg.magic) { others++; continue; }
         PLDBG("POS id="+(string)PositionGetInteger(POSITION_IDENTIFIER)+" "+PositionGetString(POSITION_SYMBOL)
               +" type="+(string)PositionGetInteger(POSITION_TYPE)+" vol="+DoubleToString(PositionGetDouble(POSITION_VOLUME),2)
               +" open="+DoubleToString(PositionGetDouble(POSITION_PRICE_OPEN),8)+" sl="+DoubleToString(PositionGetDouble(POSITION_SL),8)
               +" tp="+DoubleToString(PositionGetDouble(POSITION_TP),8)+" cmt="+PositionGetString(POSITION_COMMENT));
        }
      for(int i=OrdersTotal()-1;i>=0;i--)
        {
         ulong tk=OrderGetTicket(i);
         if(tk==0) continue;
         if(OrderGetInteger(ORDER_MAGIC)!=g_cfg.magic) { others++; continue; }
         PLDBG("ORD ticket="+(string)tk+" "+OrderGetString(ORDER_SYMBOL)+" type="+(string)OrderGetInteger(ORDER_TYPE)
               +" vol="+DoubleToString(OrderGetDouble(ORDER_VOLUME_CURRENT),2)+" price="+DoubleToString(OrderGetDouble(ORDER_PRICE_OPEN),8)
               +" stoplimit="+DoubleToString(OrderGetDouble(ORDER_PRICE_STOPLIMIT),8)+" sl="+DoubleToString(OrderGetDouble(ORDER_SL),8)
               +" tp="+DoubleToString(OrderGetDouble(ORDER_TP),8)+" tt="+(string)OrderGetInteger(ORDER_TYPE_TIME)
               +" exp="+(string)OrderGetInteger(ORDER_TIME_EXPIRATION)+" fill="+(string)OrderGetInteger(ORDER_TYPE_FILLING)+" cmt="+OrderGetString(ORDER_COMMENT));
        }
      PLDBG("POS others(not ours)="+(string)others);
     }
   else if(p[0]=="close" && n>=2)
     {
      PlSendRes r; PlSendClosePos((ulong)StringToInteger(p[1]),(n>=3)?StringToDouble(p[2]):0.0,r);
      g_sres=r; PlLogResult(); PlMessage(r.phrase,5000,r.status==PL_SS_DONE?1:2); g_risk_dirty=true; g_panel.Redraw(); ChartRedraw();
     }
   else if(p[0]=="closemagic0") g_dev_closemagic0=(n<2 || p[1]!="off");     // closemagic0 [off]: the next closes go out with magic 0, as the terminal's own window sends them
   else if(p[0]=="modify" && n>=4)
     {
      PlSendRes r; PlSendModifyPos((ulong)StringToInteger(p[1]),StringToDouble(p[2]),StringToDouble(p[3]),r);
      g_sres=r; PlLogResult(); PlMessage(r.phrase,5000,r.status==PL_SS_DONE?1:2); g_panel.Redraw(); ChartRedraw();
     }
   else if(p[0]=="del" && n>=2)
     {
      PlSendRes r; PlSendDeleteOrder((ulong)StringToInteger(p[1]),r);
      g_sres=r; PlLogResult(); PlMessage(r.phrase,5000,r.status==PL_SS_DONE?1:2); g_risk_dirty=true; g_panel.Redraw(); ChartRedraw();
     }
   else if(p[0]=="delord")
     {
      for(int i=OrdersTotal()-1;i>=0;i--)
        {
         ulong tk=OrderGetTicket(i);
         if(tk==0 || OrderGetInteger(ORDER_MAGIC)!=g_cfg.magic) continue;
         PlSendRes r; PlSendDeleteOrder(tk,r); PLDBG("DELORD "+(string)tk+" -> "+r.phrase);
        }
      g_risk_dirty=true;
     }
   else if(p[0]=="flatten")
     {
      int c=0, d=0;
      for(int i=OrdersTotal()-1;i>=0;i--)
        {
         ulong tk=OrderGetTicket(i);
         if(tk==0 || OrderGetInteger(ORDER_MAGIC)!=g_cfg.magic) continue;
         PlSendRes r; PlSendDeleteOrder(tk,r); PLDBG("FLATTEN order "+(string)tk+" -> "+r.phrase); d++;
         if(r.status==PL_SS_DONE) PlRecDelete(tk);
        }
      for(int i=PositionsTotal()-1;i>=0;i--)
        {
         ulong tk=PositionGetTicket(i);
         if(tk==0 || PositionGetInteger(POSITION_MAGIC)!=g_cfg.magic) continue;
         ulong id=(ulong)PositionGetInteger(POSITION_IDENTIFIER);
         PlSendRes r; PlSendClosePos(id,0.0,r); PLDBG("FLATTEN position "+(string)id+" -> "+r.phrase); c++;
         if(r.status==PL_SS_DONE) PlRecDelete(id);
        }
      PLDBG("FLATTEN done: positions "+(string)c+", orders "+(string)d);
      g_risk_dirty=true;
     }
   else if(p[0]=="menu") { g_panel.menu=!g_panel.menu; PlHandleAct(H_MENU,0); }
   else if(p[0]=="costs") { g_panel.costs=!g_panel.costs; g_panel.Redraw(); ChartRedraw(); }
   else if(p[0]=="collapse") { g_cfg.quick=!g_cfg.quick; g_panel.menu=false; g_panel.Redraw(); ChartRedraw(); }
   else if(p[0]=="quickstyle" && n>=2) { g_cfg.quick_style=(StringToInteger(p[1])==0)?0:1; PlSettingsSave(); g_panel.Redraw(); ChartRedraw(); }
   else if(p[0]=="theme" && n>=2) { g_cfg.theme=(int)StringToInteger(p[1]); PlThemeApply(g_cfg.theme); g_panel.Redraw(); ChartRedraw(); }
   else if(p[0]=="scale" && n>=2) { g_cfg.scale=(int)StringToInteger(p[1]); PlFollowDefaultTop(); g_panel.Redraw(); g_panel.Place(); ChartRedraw(); }
   else if(p[0]=="lines")
     {
      string r="LINES";
      for(int w=0;w<PL_LN_COUNT;w++)
         r+=" "+PlLineName(w)+"="+(ObjectFind(0,PlLineName(w))>=0?DoubleToString(ObjectGetDouble(0,PlLineName(w),OBJPROP_PRICE),g_sym.digits):"-");
      PLDBG(r);
     }
   else if(p[0]=="sess")
     {
      MqlDateTime d; datetime sn=TimeTradeServer(); TimeToStruct(sn,d);
      PLDBG("SESS "+_Symbol+" server="+TimeToString(sn,TIME_DATE|TIME_SECONDS)+" dow="+(string)d.day_of_week
            +" trade_mode="+(string)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_MODE)+" open="+(string)PlSessionOpen(_Symbol,sn));
      for(int dw=0;dw<7;dw++)
         for(int k=0;k<6;k++)
           {
            datetime f,t;
            if(!SymbolInfoSessionTrade(_Symbol,(ENUM_DAY_OF_WEEK)dw,k,f,t)) break;
            PLDBG("SESS dow="+(string)dw+" #"+(string)k+" from="+(string)((long)f/60)+"min to="+(string)((long)t/60)+"min");
           }
     }
   else if(p[0]=="open") { g_dev_open=(n<2 || p[1]!="off"); }
   else if(p[0]=="mu" && n>=2) { g_cfg.margin_use=StringToDouble(p[1]); }          // development: the margin threshold changes behind the confirmation
   else if(p[0]=="bump" && n>=2) { g_dev_bump=StringToDouble(p[1]); }
   else if(p[0]=="gate") { PlReason gw; PlTradeGate(g_acc,g_sym,false,gw,g_plan.side); PLDBG("GATE reason="+(string)(int)gw+" '"+PlReasonText(gw)+"' term="+(string)g_acc.term_trade+" mql="+(string)g_acc.mql_trade+" acct="+(string)g_acc.acct_trade+" expert="+(string)g_acc.acct_expert+" conn="+(string)g_acc.connected+" margin_mode="+(string)g_acc.margin_mode+" fill_mask="+(string)g_sym.filling_mode+" exec="+(string)g_sym.exec_mode+" exp_mode="+(string)g_sym.expiration_mode+" stops="+(string)g_sym.stops_level+" freeze="+(string)g_sym.freeze_level); }
   else if(p[0]=="chartbg" && n>=2)
     {
      bool dk=(p[1]=="dark");
      ChartSetInteger(0,CHART_COLOR_BACKGROUND,dk?C'24,26,31':clrWhite);
      ChartSetInteger(0,CHART_COLOR_FOREGROUND,dk?C'200,204,210':clrBlack);
      ChartSetInteger(0,CHART_COLOR_GRID,dk?C'45,49,58':C'227,227,227');
      ChartRedraw();
     }
   else if(p[0]=="remove") { PLDBG("CMD remove"); ExpertRemove(); }                                    // the advisor unloads itself with REASON_PROGRAM
   else if(p[0]=="template" && n>=2) { PLDBG("CMD template "+p[1]+" ok="+(string)ChartApplyTemplate(0,p[1])); }      // the advisor is unloaded with REASON_TEMPLATE
   else if(p[0]=="scrollstate") PLDBG("SCROLL mouse_scroll="+(string)ChartGetInteger(0,CHART_MOUSE_SCROLL)+" held="+(string)g_scroll_held);
   else if(p[0]=="msg")
     {
      //--- msg [unk|unres|text...]: the status line with one of the long phrases (to see that it fits without "..."), 20 s
      string t="test message";
      if(n>=2 && p[1]=="unk") t=PLS_UNKNOWN_WARN;
      else if(n>=2 && p[1]=="unres") t=PLS_UNRESOLVED;
      else if(n>=2) t=StringSubstr(cmd,4);
      PlMessage(t,20000,2); g_panel.Redraw(); ChartRedraw();
     }
   else if(p[0]=="dump")
     {
      PLDBG("DUMP sym="+g_sym.name+" digits="+(string)g_sym.digits+" tick="+DoubleToString(g_sym.tick_size,g_sym.digits)
            +" tv_loss="+DoubleToString(g_sym.tick_value_loss,5)+" contract="+DoubleToString(g_sym.contract,2)
            +" vol_min="+DoubleToString(g_sym.vol_min,3)+" step="+DoubleToString(g_sym.vol_step,3)
            +" bid="+DoubleToString(g_sym.bid,g_sym.digits)+" ask="+DoubleToString(g_sym.ask,g_sym.digits)
            +" open="+(string)g_sym.session_open+" order_mode="+(string)g_sym.order_mode+" rel="+(string)PlCcyRelation(g_sym)+" swap_ok="+(string)g_res.swap_ok
            +" lpl_a="+DoubleToString(g_res.lpl_a,5)+" lpl_c="+DoubleToString(g_res.lpl_c,5)+" margin1="+DoubleToString(g_sym.margin_buy_1lot,2)
            +" calc_mode="+(string)g_sym.calc_mode+" key="+PlStateKey(g_sym));
      PLDBG("DUMP acct cur="+g_acc.currency+" digits="+(string)g_acc.currency_digits+" bal_ok="+(string)(g_acc.balance>0)
            +" lpl_a="+DoubleToString(g_res.lpl_a,4)+" lpl_c="+DoubleToString(g_res.lpl_c,4)+" lpl="+DoubleToString(g_res.loss_per_lot,4)
            +" lot_raw="+DoubleToString(g_res.lot_raw,4)+" spread_pts="+DoubleToString(g_res.spread_points,1)
            +" spread_money="+DoubleToString(g_res.spread_money,3)+" dist="+DoubleToString(g_plan.dist,g_sym.digits)
            +" ticks="+(string)g_plan.ticks+" panel_h="+(string)g_panel.Height()+" draws="+(string)g_panel.Draws()
            +" px="+DoubleToString(g_px.entry,g_sym.digits)+"/"+DoubleToString(g_px.sl,g_sym.digits)+"/"+DoubleToString(g_px.tp[0],g_sym.digits)
            +" plan_reason="+(string)(int)g_plan.reason+" atr="+DoubleToString(g_atr,g_sym.digits)+" kind="+(string)(int)g_dr.kind
            +" hint="+(string)g_hint_ok+" fields_bad="+(string)g_fl_bad[PLF_RISK]
            +" net_risk="+DoubleToString(g_res.net_risk,2)+" risk_add="+DoubleToString(g_res.risk_add,2)+" net_vol="+DoubleToString(g_sym.net_vol,3)
            +" net_buy="+(string)g_sym.net_buy+" net_open="+DoubleToString(g_sym.net_open,g_sym.digits)+" net_sl="+DoubleToString(g_sym.net_sl,g_sym.digits)
            +" net_orders="+(string)g_sym.net_orders
            +" unit_money="+(string)g_dr.unit_money+" dr_risk_pct="+DoubleToString(g_dr.risk_pct,2)+" dr_risk_money="+DoubleToString(g_dr.risk_money,2));
     }
  }

void PlDevPoll()
  {
   string f="Plainlines_dev_cmd.txt";
   ResetLastError();
   int h=FileOpen(f,FILE_READ|FILE_TXT|FILE_ANSI|FILE_SHARE_READ|FILE_SHARE_WRITE);
   if(h==INVALID_HANDLE) return;
   string lines[]; int n=0;
   while(!FileIsEnding(h))
     {
      string ln=FileReadString(h);
      StringTrimLeft(ln); StringTrimRight(ln);
      if(ln=="") continue;
      ArrayResize(lines,n+1); lines[n]=ln; n++;
     }
   FileClose(h);
   FileDelete(f);
   //--- "@SYMBOL command" runs only on the chart of that symbol; the instance of another chart puts the line back
   string back[]; int nb=0;
   for(int i=0;i<n;i++)
     {
      string ln=lines[i];
      if(StringGetCharacter(ln,0)=='@')
        {
         const int sp=StringFind(ln," ");
         const string who=(sp>1)?StringSubstr(ln,1,sp-1):"";
         if(who!=_Symbol) { ArrayResize(back,nb+1); back[nb]=ln; nb++; continue; }
         ln=StringSubstr(ln,sp+1);
        }
      PlDevCommand(ln);
     }
   if(nb>0)
     {
      int hw=FileOpen(f,FILE_READ|FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_SHARE_READ|FILE_SHARE_WRITE);
      if(hw!=INVALID_HANDLE)
        {
         FileSeek(hw,0,SEEK_END);
         for(int i=0;i<nb;i++) FileWriteString(hw,back[i]+"\r\n");
         FileClose(hw);
        }
     }
  }

#endif

//--- the chart must not scroll under the panel: wheel over the menu, a drag of the header
void PlScrollGuard(const int mx,const int my)
  {
   bool over=g_panel.Dragging() || g_panel.Inside(mx,my);
   if(over && !g_scroll_held)
     {
      g_scroll_orig=(ChartGetInteger(0,CHART_MOUSE_SCROLL)!=0);
      if(g_scroll_orig) ChartSetInteger(0,CHART_MOUSE_SCROLL,false);
      g_scroll_held=true;
     }
   else if(!over && g_scroll_held)
     {
      ChartSetInteger(0,CHART_MOUSE_SCROLL,g_scroll_orig);
      g_scroll_held=false;
     }
  }

void PlScrollRestore()
  {
   if(g_scroll_held) { ChartSetInteger(0,CHART_MOUSE_SCROLL,g_scroll_orig); g_scroll_held=false; }
  }

//=================================================================================================
int OnInit()
  {
   PlDevOpen();
   PLDBG("INIT reason="+(string)UninitializeReason()+" symbol="+_Symbol+" tf="+EnumToString((ENUM_TIMEFRAMES)_Period)
         +" build="+(string)TerminalInfoInteger(TERMINAL_BUILD)+" dpi="+(string)TerminalInfoInteger(TERMINAL_SCREEN_DPI));
   ChartSetInteger(0,CHART_EVENT_MOUSE_MOVE,true);
   ChartSetInteger(0,CHART_EVENT_OBJECT_DELETE,true);
   ChartSetInteger(0,CHART_EVENT_MOUSE_WHEEL,true);
   FolderCreate(PL_DIR);
   if(UninitializeReason()==REASON_CHARTCHANGE)     // a symbol change keeps this chart's panel place and fold (globals survive)
     {
      const bool vc=g_cfg.quick; const int vx=g_cfg.px, vy=g_cfg.py;
      PlSettingsLoad();
      g_cfg.quick=vc; g_cfg.px=vx; g_cfg.py=vy;
     }
   else
      PlSettingsLoad();
   if(g_settings_bad) PlMessage(PLS_SETTINGS_BAD,8000,2);
   const bool acct_new=PlAccountChanged();
   const bool acct_busy=acct_new && PlTradeBusy();
   if(acct_new) PlTradeReconcileAbort(PLS_ACCT_CHANGED_CHECK);          // a check of the old account must not run on the new one
   if(acct_new) { PlAccountReset(); PlCommCacheClear(); PlCommCacheReset(); g_risk_rid=""; g_cfg.cap=PL_CAP_DEFAULT; }       // a new account: the terminal's last risk stands until its id is known, the hard cap is the default (another account's raised cap never carries over)   // a rule or a setting read under the old account
   //--- a send whose answer is still being looked for (the symbol or the timeframe was changed meanwhile) keeps its
   //--- state: the end of the check must still write the records of the position (breakeven, trailing)
   if(PlTradeBusy() && g_rc_kind==0) g_flow=PL_FLOW_CHECKING;
   else { g_flow=PL_FLOW_IDLE; }
   PLDBG("INIT flow="+(string)(int)g_flow+" busy="+(string)PlTradeBusy()+" rc_kind="+(string)g_rc_kind);
   PlThemeApply(g_cfg.theme);
   g_theme_sig=g_th.dark?1:0;
   PlReadAccount(g_acc,false);          // the open risk is worked out by the pass over positions below
   PlDevAdjustAcct(g_acc);
   PlProfReset();
   PlReadHistory(g_acc);
   if(g_hist_read)                      // read, adding up or not: an exact match or no file of this server need not wait (PlProfFind)
     {
      PlProfResolve();
      if(UninitializeReason()==REASON_CHARTCHANGE) g_prof_note="";   // said once at the start, not at every symbol change
      PlProfAnnounce();
     }
   PlReadPositions();
   g_acc.open_risk_money=g_ex_open_risk; g_acc.pending_risk_money=g_ex_pend_risk; g_acc.open_no_sl=g_ex_no_sl;
   g_risk_dirty=false; g_t_risk=GetTickCount64(); g_hint_dirty=false; g_drag_w=-1; g_scroll_held=false;
   g_panel.confirm_view=false;       // a new symbol or a restart never opens in the confirmation state
   if(g_lines_hid!=_Symbol) g_lines_hid="";     // the lines taken off after a fill are that symbol's alone
   if(!PlReadChartSymbol())
     {
      PLDBG("INIT symbol data not ready, will retry");
     }
   PlDevAdjustSym(g_sym);
   g_draft_ok=PlStateKeyReady(g_sym);
   if(g_draft_ok) PlDraftLoad(g_sym);
   else { PlDraftDefaults(); PLDBG("INIT symbol key not ready, draft waits"); }
   g_hint_ok=PlCommSample(_Symbol,g_hint_in,g_hint_out,g_hint_closed);
   //--- lines: take over those of this symbol or place new ones
   g_ln_sig=-1;                       // adopted lines get the colors and width of this chart now
   bool adopted=false;
   g_prices_ok=false;
   g_px.entry=0; g_px.limit=0; g_px.sl=0;
   for(int i=0;i<PL_MAX_TP;i++) g_px.tp[i]=0;
   if(PlQuoteReady())
     {
      adopted=PlInitPrices();
      g_prices_ok=true;
     }
   else
     {
      PLDBG("INIT no quote yet, lines wait for the first tick");
      //--- lines of the old symbol (a symbol change) must not show old prices until then
      if(ObjectFind(0,PlLineName(0))>=0 && ObjectGetString(0,PlLineName(0),OBJPROP_TEXT)!=_Symbol) PlLinesDeleteAll();
     }
   PlAtrUpdate();
   PlFldInit();
   double s=PlScaleGet(g_cfg.scale);
   int px=(g_cfg.px>=0)?g_cfg.px:(int)MathRound(14*s);
   int py=(g_cfg.py>=0)?g_cfg.py:PlDefaultTop(s);
   if(!g_panel.Create(px,py)) { PLDBG("INIT panel create failed"); return INIT_FAILED; }
   g_panel.Clamp();
   PlRecalc();
   g_panel.Redraw();
   g_panel.Place();
   g_chart_w=(int)ChartGetInteger(0,CHART_WIDTH_IN_PIXELS);
   g_chart_h=(int)ChartGetInteger(0,CHART_HEIGHT_IN_PIXELS);
   g_last_bid=g_sym.bid; g_last_ask=g_sym.ask; g_last_open=g_sym.session_open;
   ulong now=GetTickCount64();
   g_t_account=now; g_t_symbol=now; g_t_cmd=now; g_t_atr=now;
   g_ready=true;
   if(!EventSetMillisecondTimer(250)) { PLDBG("INIT no timer"); return INIT_FAILED; }     // without it the manager, the guards and the history reading stand silent
   ChartRedraw();
   PLDBG("INIT done adopted="+(string)adopted+" kind="+(string)(int)g_dr.kind+" plan_ok="+(string)g_plan.ok
         +" lot="+DoubleToString(g_res.lot,3)+" reason="+(string)(int)g_plan.reason+" ask="+DoubleToString(g_sym.ask,g_sym.digits)+" px="+DoubleToString(g_px.entry,g_sym.digits)+"/"+DoubleToString(g_px.sl,g_sym.digits)+" panel="+(string)g_panel.X()+","+(string)g_panel.Y()+" "+(string)g_panel.Width()+"x"+(string)g_panel.Height());
   if(acct_busy) PlMessage(PLS_ACCT_CHANGED_CHECK,30000,2);
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
   GlobalVariableDel(PL_NOALGO_GV+(string)ChartID());       // every reason: this instance no longer says it cannot trade
   PlScrollRestore();
   if(g_ready)
     {
      if(g_prof_dirty && !PlProfLoading() && g_prof_state!=PL_PS_BAD && g_fp_found) PlProfileSave(true);   // a failed user write goes first
      if(g_settings_retry) PlSettingsSave();       // every change is saved when it is made; only a save that failed is still owed
      if(g_prices_ok) PlDraftSave(g_sym);
     }
   PLDBG("DEINIT reason="+(string)reason);
   g_panel.Destroy();
   ObjectDelete(0,"PL_Mark");
   //--- the lines stay only when this advisor starts again on this chart at once: a symbol or timeframe change, new
   //--- parameters, a recompile, an account change. OnInit then adopts them (same symbol, PlInitPrices) or clears them
   //--- (another symbol), also on the first tick when there is no quote yet. Every other reason (a template, a failed
   //--- start, a closed chart or terminal, removal, ExpertRemove) leaves the lines without an owner: they go with the labels.
   switch(reason)
     {
      case REASON_CHARTCHANGE:
      case REASON_PARAMETERS:
      case REASON_RECOMPILE:
      case REASON_ACCOUNT:
         for(int w=0;w<PL_LN_COUNT;w++) PlLabelDelete(w);          // only the labels go, they are drawn again
         break;
      default:
         PlLinesDeleteAll();
     }
   if(g_atr_h!=INVALID_HANDLE) { IndicatorRelease(g_atr_h); g_atr_h=INVALID_HANDLE; }
   g_ready=false;
   PlDevClose();
  }

void OnTick()
  {
  }

//--- trade events only mark the work; the timer does it
void OnTradeTransaction(const MqlTradeTransaction &trans,const MqlTradeRequest &request,const MqlTradeResult &result)
  {
   if(!g_ready) return;
   g_risk_dirty=true;
   if(trans.type==TRADE_TRANSACTION_DEAL_ADD) { g_hint_dirty=true; PlCommCacheClear(); PlCommCacheReset(); g_hist_dirty=true; g_hist_gap=2000; g_hist_event=GetTickCount64(); PlSoundDeal(trans.deal); PlCloseSummary(trans.deal); }
   if(g_flow==PL_FLOW_CHECKING) PlReconcileTick();
  }

//--- the rights of the account in one number: a change of any of them is worth a redraw
int PlRightsSig(const PlAccount &a)
  {
   return (a.term_trade?1:0)|(a.mql_trade?2:0)|(a.acct_trade?4:0)|(a.acct_expert?8:0)|(a.trade_mode<<4);
  }

void OnTimer()
  {
   if(!g_ready) return;
   ulong now=GetTickCount64();
   bool dirty=false;
   //--- quote
   PlRefreshQuote(g_sym,true);
   PlReadNetting(_Symbol,g_sym);    // netting only (a no-op on hedging): the panel's numbers follow a manual trade
   PlDevAdjustSym(g_sym);           // development switches only; nothing in a release
   //--- a terminal start before the symbol specs sync: the draft waits for a ready symbol key
   if(!g_draft_ok)
     {
      PlReadChartSymbol();
      PlDevAdjustSym(g_sym);
      if(PlStateKeyReady(g_sym))
        {
         g_draft_ok=true;
         PlDraftLoad(g_sym);
         dirty=true; g_key="";
         PLDBG("INIT symbol key ready, draft loaded");
        }
     }
   if(!g_prices_ok)
     {
      if(g_sym.bid>0.0 && g_sym.ask>0.0)
        {
         PlReadChartSymbol();
         if(PlQuoteReady())
           {
            PlInitPrices();
            g_prices_ok=true;
            PLDBG("INIT first quote arrived, lines placed");
            PlRecalc();
            g_panel.Redraw();
            ChartRedraw();
           }
        }
     }
   if(g_sym.bid!=g_last_bid || g_sym.ask!=g_last_ask || g_sym.session_open!=g_last_open)
     {
      g_last_bid=g_sym.bid; g_last_ask=g_sym.ask; g_last_open=g_sym.session_open;
      dirty=true;
     }
   //--- while a confirmation waits, the rights and the connection are read on every lap (250 ms), so a BLOCK takes it down at once
   if(now-g_t_account>=(g_flow==PL_FLOW_ARMED?(ulong)0:(ulong)2000))
     {
      g_t_account=now;
      double b=g_acc.balance, e=g_acc.equity;
      const bool was_conn=g_acc.connected;
      const int rights=PlRightsSig(g_acc);
      PlReadAccount(g_acc,false);
      PlDevAdjustAcct(g_acc);
      //--- the history counts only while it adds up to the balance and the connection stayed: look again on a change
      if(was_conn!=g_acc.connected || !PlHistAddsUp(g_acc)) g_hist_dirty=true;
      const int rights_now=PlRightsSig(g_acc);
      if(MathAbs(b-g_acc.balance)>0.004 || MathAbs(e-g_acc.equity)>0.004 || was_conn!=g_acc.connected || rights!=rights_now) dirty=true;
     }
   //--- once a second: the account, settings written by another chart (the account's hard cap among them)
   if(now-g_t_sec>=1000)
     {
      g_t_sec=now;
      if(PlAccountChanged())
        {
         const bool was_busy=PlTradeBusy();
         PlTradeReconcileAbort(PLS_ACCT_CHANGED_CHECK);
         if(g_flow==PL_FLOW_CHECKING) { g_flow=PL_FLOW_IDLE; PlFlowSync(); }
         PlAccountReset();
         g_risk_rid="";                          // a new account: the terminal's last risk stands until its id is known
         PlCommCacheClear(); PlCommCacheReset();   // the deal samples of the old account must not stand ten minutes
         PlProfReset();
         g_cfg.cap=PL_CAP_DEFAULT;
         ArrayResize(g_rec,0);
         PlReadAccount(g_acc); PlDevAdjustAcct(g_acc);
         PlCancelArm("",false);
         PlMessage(was_busy?PLS_ACCT_CHANGED_CHECK:PLS_ACCT_CHANGED,was_busy?30000:6000,was_busy?2:0);
         g_fl_text[PLF_CAP]="~";
         dirty=true; g_key="";
        }
      //--- a damaged profile file may have been a torn read at the start: look again
      if(PlProfNeedsResolve() && PlHistLoaded())
        {
         const int was_ps=PlProfSig();
         PlProfResolve();
         if(PlProfSig()!=was_ps && !PlProfLoading()) PlProfAnnounce();
         if(PlProfSig()!=was_ps) { for(int fi=0;fi<PLF_COUNT;fi++) g_fl_text[fi]="~"; dirty=true; g_key=""; }
        }
      if(g_prof_rid!="" && g_prof_rid!=g_risk_rid) { PlRiskForAccount(); g_fl_text[PLF_CAP]="~"; dirty=true; g_key=""; }     // settings.dat was mid-write when the account was found
      if(g_settings_retry) PlSettingsSave();       // a save that failed or met a torn file goes first, before the file is read back over it
      PlSettingsFailNote();
      if(PlProfChangedByOther())
        {
         PlCancelArm("",false);
         for(int fi=0;fi<PLF_COUNT;fi++) g_fl_text[fi]="~";
         dirty=true; g_key="";
        }
      if(PlSettingsChangedByOther())
        {
         //--- the quick or full view and the position stay per chart: another chart's switch or move never reaches this one
         const bool vc=g_cfg.quick; const int vx=g_cfg.px, vy=g_cfg.py;
         PlSettingsLoad();
         g_cfg.quick=vc; g_cfg.px=vx; g_cfg.py=vy;
         PlThemeApply(g_cfg.theme);
         PlCancelArm("",false);
         for(int fi=0;fi<PLF_COUNT;fi++) g_fl_text[fi]="~";
         PLDBG("SETTINGS reread (another chart wrote them)");
         dirty=true; g_key="";
        }
     }
   //--- the order flow
   if(g_flow==PL_FLOW_ARMED)
     {
      if(now-g_armed_at>PL_ARM_WINDOW_MS) PlCancelArm(PLS_CONFIRM_TIMEOUT);
      else if(g_acc.connected!=g_arm_conn) PlCancelArm("");
      else
        {
         const double mid=(g_sym.ask+g_sym.bid)/2.0;
         if(g_snap.kind==PL_KIND_MARKET && g_snap.dist>0.0 && MathAbs(mid-g_snap.mid)>PL_PRICE_MOVE*g_snap.dist) PlCancelArm(PLS_PRICE_MOVED);
         else if(g_panel.Created()) { g_panel.Redraw(); ChartRedraw(); }       // the countdown strip
        }
     }
   else if(g_flow==PL_FLOW_COOLDOWN && now>=g_cool_until) { g_flow=PL_FLOW_IDLE; PlFlowSync(); }
   else if(g_flow==PL_FLOW_CHECKING && now-g_t_rc>=500) { g_t_rc=now; PlReconcileTick(); }
   //--- the manager (leader only), the list of own positions, the arming of the close buttons
   PlManageTick();
   if(PlTradeBusy() && g_flow!=PL_FLOW_CHECKING)
     {
      PlSendRes rr;
      if(PlTradeReconcileStep(rr)) { PlMessage(rr.phrase,6000,rr.status==PL_SS_DONE?1:2); dirty=true; g_risk_dirty=true; }
     }
   if(now-g_t_own>=1000)
     {
      g_t_own=now;
      const string was=g_own_sig;
      PlOwnRefresh();
      if(was!=g_own_sig) { dirty=true; g_key=""; }
      else if(g_panel.positions) dirty=true;
     }
   if(g_cb_kind!=0 && now-g_cb_at>3000) { g_cb_kind=0; dirty=true; g_key=""; }
   //--- positions and orders: on a trade event, else every ten seconds
   if(g_risk_dirty || now-g_t_risk>=(g_ex_unknown>0?(ulong)2000:(ulong)10000))
     {
      g_risk_dirty=false; g_t_risk=now;
      PlReadPositions();
      g_acc.open_risk_money=g_ex_open_risk; g_acc.pending_risk_money=g_ex_pend_risk; g_acc.open_no_sl=g_ex_no_sl;
      dirty=true;
     }
   //--- the deal history: until it has come, and again after every deal; then the profile of the account is found
   //--- the server may add a deal to the history a moment after the event: read once more a few seconds later
   if(g_hist_event!=0 && now-g_hist_event>=4000) { g_hist_event=0; g_hist_dirty=true; }
   const bool hist_ok=PlHistLoaded();
   if((!hist_ok || g_hist_dirty) && now-g_hist_last>=(hist_ok?(ulong)1000:g_hist_gap))
     {
      const bool hist_got=PlReadHistory(g_acc);
      //--- a history that was read while connected and still does not add up is read again after 2, 4, 8 ... 60 s, not every 2 s
      if(hist_got || !g_hist_read || !g_hist_conn) g_hist_gap=2000;
      else g_hist_gap=MathMin((ulong)60000,g_hist_gap*2);
      if(g_hist_read && PlProfLoading())
        {
         PlProfResolve(); g_key="";
         PlProfAnnounce();
        }
      dirty=true;
     }
   if(g_prof_dirty && !PlProfLoading() && g_prof_state!=PL_PS_BAD) PlProfileSave(true);
   if(g_hint_dirty)
     {
      g_hint_dirty=false;
      g_hint_ok=PlCommSample(_Symbol,g_hint_in,g_hint_out,g_hint_closed);
      dirty=true;
     }
   if(now-g_t_symbol>=(g_sym_thin?(ulong)2000:(ulong)10000))
     {
      g_t_symbol=now;
      PlReadChartSymbol();
      PlDevAdjustSym(g_sym);
      dirty=true;
     }
   if(g_cfg.atr_on && now-g_t_atr>=5000)
     {
      g_t_atr=now;
      double a=g_atr;
      PlAtrUpdate();
      if(a!=g_atr) dirty=true;
     }
   PlBulkTick(now);
   {
      //--- the quick strip shows a result in place of the open button for a few seconds: draw again when it comes and when it goes
      static bool strip_res=false;
      const bool sr=PlStripResult();
      if(sr!=strip_res) { strip_res=sr; dirty=true; g_key=""; }
   }
   //--- a status message expired
   if(g_msg!="" && now>=g_msg_until) { g_msg=""; dirty=true; g_key=""; }
   //--- a redraw wanted while the left button is down waits for its release (the flags that asked for it are already cleared)
   static bool redraw_owed=false;
   if(dirty) redraw_owed=true;
   if(redraw_owed && !g_lbtn)
     {
      redraw_owed=false;
      if(PlRecalc() || g_key=="")
        {
         g_panel.Redraw();
         ChartRedraw();
        }
     }
   if(now-g_t_cmd>=1000)
     {
      g_t_cmd=now;
      g_panel.Ensure();
      //--- the chart background changed by hand: Auto theme follows
      bool dk=PlChartIsDark();
      if(g_cfg.theme==0 && (dk?1:0)!=g_theme_sig)
        {
         PlThemeApply(0); g_theme_sig=dk?1:0;
         PlLinesLabels();
         g_panel.Redraw(); ChartRedraw();
        }
      //--- the lines follow the chart background whatever the panel theme is
      if(PlLinesRestyle()) { PlLinesLabels(); ChartRedraw(); }
#ifdef PL_DEV_LOG
      PlDevPoll();
#endif
     }
  }

//--- the mouse is down on a line: follow it ------------------------------------------------------
void PlLiveDrag()
  {
   ulong now=GetTickCount64();
   if(now-g_last_live<40) return;
   if(!PlLinesPull()) return;
   g_last_live=now;
   PlCancelArm("",false);
   if(g_drag_w==0 || g_drag_w==2) PlAutoKind(g_drag_w==0,false,PlMarketTol());
   //--- a dragged TP leaves the R mode
   PlRecalc();
   g_panel.Redraw();
   ChartRedraw();
  }

void OnChartEvent(const int id,const long &lparam,const double &dparam,const string &sparam)
  {
   if(!g_ready) return;
   switch(id)
     {
      case CHARTEVENT_MOUSE_MOVE:
        {
         int mx=(int)lparam, my=(int)dparam;
         int fl=(int)StringToInteger(sparam);
         bool left=((fl&1)!=0);
         if(left && !g_lbtn) { g_press_in_panel=g_panel.Inside(mx,my); if(g_press_in_panel) PlStickyClear(); }
         g_lbtn=left;
         if(!left) g_drag_w=-1;
         PlScrollGuard(mx,my);
         g_panel.OnMouse(mx,my,fl);
         if(g_panel.act_id!=0)
           {
            int a=g_panel.act_id, b=g_panel.act_arg;
            g_panel.act_id=0;
            PlHandleAct(a,b);
           }
         if(g_panel.moved)
           {
            g_panel.moved=false;
            g_cfg.px=g_panel.X(); g_cfg.py=g_panel.Y();
            PlSettingsSave();
            PLDBG("ACT panel moved "+(string)g_cfg.px+","+(string)g_cfg.py);
           }
         if(left && !g_panel.Dragging() && !g_press_in_panel) PlLiveDrag();
         break;
        }
      case CHARTEVENT_OBJECT_DRAG:
      case CHARTEVENT_OBJECT_CHANGE:      // a price typed into the properties window of a line is taken like a drag
        {
         int w=PlLineFromName(sparam);
         if(w<0) break;
         if(!g_press_in_panel) PlStickyClear();
         if(id==CHARTEVENT_OBJECT_DRAG && g_press_in_panel)
           {
            g_lbtn=false; g_drag_w=-1;
            PlLinesSync(); PlLinesLabels(); ChartRedraw();
            PLDBG("ACT line drag from the panel ignored "+sparam);
            break;
           }
         if(w==2 && g_cfg.atr_on) PlMessage(PLS_SL_FOLLOWS_ATR,3500,0);
         PlLinesPull();
         PlLinesSnap();
         //--- a dragged TP is a price now, not an R multiple
         if(w>=3) g_dr.tp_price[w-3]=true;
         if(w==0 || w==2) PlAutoKind(w==0,true,(id==CHARTEVENT_OBJECT_DRAG)?PlMarketTol():2.0*g_sym.tick_size);
         g_lbtn=false; g_drag_w=-1;
         PLDBG("ACT line "+(id==CHARTEVENT_OBJECT_DRAG?"dragged ":"changed ")+sparam);
         PlModelChanged();
         break;
        }
      case CHARTEVENT_OBJECT_ENDEDIT:
        {
         int f=PlFldFromName(sparam);
         if(f<0) break;
         PlOnEndEdit(f);
         break;
        }
      case CHARTEVENT_OBJECT_CLICK:
        {
         int f=PlFldFromName(sparam);
         if(f>=0) g_fl_focus=f;
         break;
        }
      case CHARTEVENT_OBJECT_DELETE:
        {
         if(sparam==PL_PANEL_NAME) { g_panel.Ensure(); ChartRedraw(); break; }
         int w=PlLineFromName(sparam);
         if(w>=0 && PlLineShown(w) && g_ready && !PlSelfDeleted(sparam))
           {
            PLDBG("ACT line deleted by the user, recreating "+sparam);
            PlLinesSync(); PlLinesLabels(); ChartRedraw();
           }
         break;
        }
      case CHARTEVENT_CHART_CHANGE:
        {
         int cw=(int)ChartGetInteger(0,CHART_WIDTH_IN_PIXELS), ch=(int)ChartGetInteger(0,CHART_HEIGHT_IN_PIXELS);
         bool dark=PlChartIsDark();
         bool redraw=false;
         if(cw!=g_chart_w || ch!=g_chart_h)
           {
            g_chart_w=cw; g_chart_h=ch;
            if(g_cfg.py<0) g_panel.SetY(PlDefaultTop(PlScaleGet(g_cfg.scale)));     // a panel never dragged follows the chart height
            g_panel.Clamp(); g_panel.Place(); redraw=true;
           }
         if(g_cfg.theme==0 && (dark?1:0)!=g_theme_sig) { PlThemeApply(0); g_theme_sig=dark?1:0; redraw=true; }
         if(redraw) g_panel.Redraw();
         PlLinesLabels();
         ChartRedraw();
         break;
        }
      case CHARTEVENT_KEYDOWN:
         PlOnKey((int)lparam,sparam);
         break;
      case CHARTEVENT_MOUSE_WHEEL:
        {
         int wx=(int)(lparam&0xFFFF), wy=(int)((lparam>>16)&0xFFFF);
         g_panel.OnWheel(wx,wy,dparam);
         break;
        }
     }
  }
