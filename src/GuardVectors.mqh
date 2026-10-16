// Required Notice: Copyright 2026 stop-loss-enjoyer
// Plainlines is source-available under the PolyForm Shield License 1.0.0.
//
// Test vectors of the guards Max total risk, Max open, Max trades a day, the
// margin use, the profile wait and the order of the reasons. Pure data. Every expected number was derived by hand from
// the rules, never copied from the output of the core. Most of them are the vectors the guards had before the split;
// the others are new.
//
// Conventions: 100000 balance and equity, one market order, the guards off unless the vector sets them.
//   - Unchecked: double EMPTY_VALUE, int -1.
#property strict

#ifndef PL_GUARD_VECTORS_MQH
#define PL_GUARD_VECTORS_MQH

#include "Core/Types.mqh"
#include "Core/Guard.mqh"

struct PlGuardVec
  {
   string            name;
   PlGuardCfg        c;
   PlGuardIn         in;
   PlExpo            ex[12];
   int               ne;
   //--- expected
   double            exp_max_new;
   double            exp_open_risk;
   double            exp_pending_risk;
   double            exp_portfolio_pct;
   double            exp_margin_pct;
   int               exp_no_sl;
   int               exp_unknown;
   int               exp_verdict;
   int               exp_why;
  };

//--- 100000 balance and equity, a single market order, every guard off; nothing expected yet except verdict OK
void LvOff(PlGuardVec &v,const string name)
  {
   v.name=name;
   ZeroMemory(v.c);
   ZeroMemory(v.in);
   v.in.new_open=1;           // a single market order unless a vector says otherwise
   v.in.new_entries=1;
   v.in.deals_loaded=true;
   v.in.balance=100000.0;
   v.in.equity=100000.0;
   v.ne=0;
   v.exp_max_new=EMPTY_VALUE;
   v.exp_open_risk=EMPTY_VALUE;
   v.exp_pending_risk=EMPTY_VALUE;
   v.exp_portfolio_pct=EMPTY_VALUE;
   v.exp_margin_pct=EMPTY_VALUE;
   v.exp_no_sl=-1;
   v.exp_unknown=-1;
   v.exp_verdict=PL_OK;
   v.exp_why=PL_LW_NONE;
  }

void LvEx(PlGuardVec &v,const bool pending,const bool has_sl,const double pl)
  {
   v.ex[v.ne].pending=pending;
   v.ex[v.ne].has_sl=has_sl;
   v.ex[v.ne].pl_at_sl=pl;
   v.ex[v.ne].unknown=false;
   v.ne++;
  }

//--- an entry with an SL whose money at the SL cannot be valued
void LvExUnk(PlGuardVec &v,const bool pending)
  {
   v.ex[v.ne].pending=pending;
   v.ex[v.ne].has_sl=true;
   v.ex[v.ne].pl_at_sl=0.0;
   v.ex[v.ne].unknown=true;
   v.ne++;
  }

void LvExpect(PlGuardVec &v,const int verdict,const int why)
  {
   v.exp_verdict=verdict;
   v.exp_why=why;
  }

int PlGuardVecCount()
  {
   return 46;
  }

bool PlGuardVecGet(const int i,PlGuardVec &v)
  {
   switch(i)
     {
      case 0:    // P1 (1500+500+1200)/100000 = 3.2 % > 3
         LvOff(v,"P1a portfolio 3.2 percent above the cap 3");
         v.c.portfolio_cap_pct=3.0;
         LvEx(v,false,true,-1500.0);
         LvEx(v,true,true,-500.0);
         v.in.new_risk=1200.0;
         v.exp_portfolio_pct=3.2;
         v.exp_open_risk=1500.0;
         v.exp_pending_risk=500.0;
         LvExpect(v,PL_BLOCK,PL_LW_PORTFOLIO_CAP);
         return true;
      case 1:    // P1 (1500+500+1000)/100000 = 3.0 % equal to the cap passes
         LvOff(v,"P1b portfolio exactly at the cap");
         v.c.portfolio_cap_pct=3.0;
         LvEx(v,false,true,-1500.0);
         LvEx(v,true,true,-500.0);
         v.in.new_risk=1000.0;
         v.exp_portfolio_pct=3.0;
         return true;
      case 2:    // binary noise: 3500/100000*100 computes as 3.5000000000000004, still equal to the cap 3.5
         LvOff(v,"P1c portfolio at the cap with float noise");
         v.c.portfolio_cap_pct=3.5;
         LvEx(v,false,true,-2000.0);
         LvEx(v,true,true,-500.0);
         v.in.new_risk=1000.0;
         v.exp_portfolio_pct=3.5;
         return true;
      case 3:    // P2 cap set, a position without SL
         LvOff(v,"P2 portfolio unknown, position without SL");
         v.c.portfolio_cap_pct=3.0;
         LvEx(v,false,false,0.0);
         v.in.new_risk=100.0;
         v.exp_no_sl=1;
         LvExpect(v,PL_BLOCK,PL_LW_PORTFOLIO_UNKNOWN);
         return true;
      case 4:
         LvOff(v,"X28 balance zero, risk present");
         v.in.balance=0.0;
         v.in.equity=0.0;
         v.c.portfolio_cap_pct=3.0;
         v.in.new_risk=100.0;
         v.exp_portfolio_pct=PL_LIM_BIG;
         LvExpect(v,PL_BLOCK,PL_LW_PORTFOLIO_CAP);
         return true;
      case 5:
         LvOff(v,"X28b balance zero, no risk");
         v.in.balance=0.0;
         v.in.equity=0.0;
         v.c.portfolio_cap_pct=3.0;
         v.exp_portfolio_pct=0.0;
         v.exp_margin_pct=0.0;
         return true;
      case 6:    // portfolio off (cap 0): never blocks, even with no SL and large risk
         LvOff(v,"X30 portfolio cap 0 is off");
         LvEx(v,false,false,0.0);
         v.in.new_risk=50000.0;
         v.exp_no_sl=1;
         return true;
      case 7:    // V2b unknown entry, extra checks off, portfolio cap on
         LvOff(v,"V2b unknown risk, cap 3");
         v.c.portfolio_cap_pct=3.0;
         LvExUnk(v,true);
         v.exp_unknown=1;
         LvExpect(v,PL_BLOCK,PL_LW_RISK_UNKNOWN);
         return true;
      case 8:    // N2 extra checks off, total risk cap set: a trade without SL has no risk to put under the cap
         LvOff(v,"N2 new trade without SL, cap on");
         v.c.portfolio_cap_pct=3.0;
         v.in.new_no_sl=true;
         LvExpect(v,PL_BLOCK,PL_LW_NEW_NO_SL);
         return true;
      case 9:    // N3 extra checks off, no cap: the new rule is silent, the margin rule still applies
         LvOff(v,"N3 new trade without SL, extra checks and cap off");
         v.c.margin_use_pct=50.0;
         v.in.margin=20000.0;
         v.in.new_margin=40000.0;
         v.in.new_no_sl=true;
         v.exp_margin_pct=60.0;
         LvExpect(v,PL_CONFIRM,PL_LW_MARGIN_USE);
         return true;
      case 10:    // M1 (20000+35000)/100000 = 55 % > 50
         LvOff(v,"M1 margin use 55 percent");
         v.c.margin_use_pct=50.0;
         v.in.margin=20000.0;
         v.in.new_margin=35000.0;
         v.exp_margin_pct=55.0;
         LvExpect(v,PL_CONFIRM,PL_LW_MARGIN_USE);
         return true;
      case 11:    // margin exactly 50 % passes
         LvOff(v,"M1b margin use exactly 50 percent");
         v.c.margin_use_pct=50.0;
         v.in.margin=25000.0;
         v.in.new_margin=25000.0;
         v.exp_margin_pct=50.0;
         return true;
      case 12:    // threshold 0 = off
         LvOff(v,"M1c margin threshold 0 is off");
         v.c.margin_use_pct=0.0;
         v.in.margin=20000.0;
         v.in.new_margin=35000.0;
         v.exp_margin_pct=55.0;
         return true;
      case 13:
         LvOff(v,"X29 equity zero, margin needed");
         v.in.equity=0.0;
         v.c.margin_use_pct=50.0;
         v.in.new_margin=100.0;
         v.exp_margin_pct=PL_LIM_BIG;
         LvExpect(v,PL_CONFIRM,PL_LW_MARGIN_USE);
         return true;
      case 14:    // 700/100000*100 computes as 0.7000000000000001, still equal to the threshold 0.7
         LvOff(v,"M1d margin use at the threshold with float noise");
         v.c.margin_use_pct=0.7;
         v.in.margin=300.0;
         v.in.new_margin=400.0;
         v.exp_margin_pct=0.7;
         return true;
      case 15:    // C1 open count reached
         LvOff(v,"C1a open trades reached");
         v.c.max_open=3;
         v.in.open_count=3;
         LvExpect(v,PL_BLOCK,PL_LW_TRADES_OPEN);
         return true;
      case 16:
         LvOff(v,"C1a2 open trades below the maximum");
         v.c.max_open=3;
         v.in.open_count=2;
         return true;
      case 17:
         LvOff(v,"C2a three TPs on a hedge, max open 3, two open: blocked");
         v.c.max_open=3;
         v.in.open_count=2;
         v.in.new_open=3;
         v.in.new_entries=3;
         LvExpect(v,PL_BLOCK,PL_LW_TRADES_OPEN);
         return true;
      case 18:
         LvOff(v,"C2b one order, max open 3, two open: passes");
         v.c.max_open=3;
         v.in.open_count=2;
         v.in.new_open=1;
         v.in.new_entries=1;
         return true;
      case 19:
         LvOff(v,"C2f split into two orders reaching max open exactly: passes");
         v.c.max_open=3;
         v.in.open_count=1;
         v.in.new_open=2;
         v.in.new_entries=2;
         return true;
      case 20:
         LvOff(v,"C2g split into two orders over max open: blocked");
         v.c.max_open=3;
         v.in.open_count=2;
         v.in.new_open=2;
         v.in.new_entries=2;
         LvExpect(v,PL_BLOCK,PL_LW_TRADES_OPEN);
         return true;
      case 21:
         LvOff(v,"C1b trades today reached");
         v.c.max_day=5;
         v.in.trades_today=5;
         LvExpect(v,PL_BLOCK,PL_LW_TRADES_DAY);
         return true;
      case 22:
         LvOff(v,"C1b2 trades today below the maximum");
         v.c.max_day=5;
         v.in.trades_today=4;
         return true;
      case 23:
         LvOff(v,"C2c pending order at the full daily count: passes");
         v.c.max_day=3;
         v.in.trades_today=3;
         v.in.new_open=1;
         v.in.new_entries=0;
         return true;
      case 24:
         LvOff(v,"C2d market order at the full daily count: blocked");
         v.c.max_day=3;
         v.in.trades_today=3;
         v.in.new_open=1;
         v.in.new_entries=1;
         LvExpect(v,PL_BLOCK,PL_LW_TRADES_DAY);
         return true;
      case 25:
         LvOff(v,"C2e split into two market orders count for two a day");
         v.c.max_day=5;
         v.in.trades_today=4;
         v.in.new_open=2;
         v.in.new_entries=2;
         LvExpect(v,PL_BLOCK,PL_LW_TRADES_DAY);
         return true;
      case 26:    // V4 Max trades a day waits for the history
         LvOff(v,"V4 max trades a day, history not loaded");
         v.c.max_day=3;
         v.in.deals_loaded=false;
         LvExpect(v,PL_BLOCK,PL_LW_NO_HISTORY);
         return true;
      case 27:    // a CONFIRM loses to a BLOCK
         LvOff(v,"X4 margin confirm loses to a block");
         v.c.margin_use_pct=50.0;
         v.c.max_open=1;
         v.in.open_count=1;
         v.in.margin=20000.0;
         v.in.new_margin=35000.0;
         LvExpect(v,PL_BLOCK,PL_LW_TRADES_OPEN);
         return true;
      case 28:    // extra checks off, a position without SL, no cap: no block
         LvOff(v,"X10 extra checks off, no SL and no cap");
         LvEx(v,false,false,0.0);
         v.exp_no_sl=1;
         return true;
      case 29:    // pending order with a profitable (negative-risk) stop does not reduce pending risk
         LvOff(v,"X36 pending with a stop in profit");
         LvEx(v,true,true,200.0);
         LvEx(v,true,true,-400.0);
         v.exp_pending_risk=400.0;
         v.exp_open_risk=0.0;
         return true;
      case 30:    // V2c unknown entry, only subtract-open on
         LvOff(v,"V2c unknown risk, subtract open");
         v.c.subtract_open=true;
         LvExUnk(v,false);
         v.exp_unknown=1;
         LvExpect(v,PL_BLOCK,PL_LW_RISK_UNKNOWN);
         return true;
      case 31:    // V2d unknown entry, everything off: nothing to protect
         LvOff(v,"V2d unknown risk, all off");
         LvExUnk(v,false);
         v.exp_unknown=1;
         return true;
      case 32:    // all four counters violated: the portfolio comes first
         LvOff(v,"X1 priority: portfolio cap first");
         v.c.portfolio_cap_pct=1.0;
         v.c.max_open=1;
         v.c.max_day=1;
         LvEx(v,false,true,-2000.0);
         v.in.open_count=1;
         v.in.trades_today=1;
         v.exp_portfolio_pct=2.0;
         LvExpect(v,PL_BLOCK,PL_LW_PORTFOLIO_CAP);
         return true;
      case 33:
         LvOff(v,"X2 priority: open trades before trades today");
         v.c.max_open=1;
         v.c.max_day=1;
         v.in.open_count=1;
         v.in.trades_today=1;
         LvExpect(v,PL_BLOCK,PL_LW_TRADES_OPEN);
         return true;
      case 34:
         LvOff(v,"X3 priority: trades today (no competitor)");
         v.c.max_day=1;
         v.in.trades_today=1;
         LvExpect(v,PL_BLOCK,PL_LW_TRADES_DAY);
         return true;
      case 35:    // the margin confirm stands alone
         LvOff(v,"X5 margin confirm, nothing to lose to");
         v.c.margin_use_pct=50.0;
         v.in.margin=20000.0;
         v.in.new_margin=35000.0;
         LvExpect(v,PL_CONFIRM,PL_LW_MARGIN_USE);
         return true;
      //--- the guards off: nothing but the sums -------------------------------------------------------------
      case 36:     // L10 the guards off: the exposure sums are still computed
         LvOff(v,"L10 guards off, the exposure sums are still computed");
         LvEx(v,false,true,-700.0);
         LvEx(v,true,true,-300.0);
         v.in.new_risk=1000000.0;
         v.exp_max_new=-1.0;
         v.exp_open_risk=700.0;
         v.exp_pending_risk=300.0;
         v.exp_no_sl=0;
         return true;
      case 37:     // X14b the history is not loaded, Max trades a day off: nothing waits
         LvOff(v,"X14b history not loaded, no Max trades a day");
         v.in.deals_loaded=false;
         v.exp_max_new=-1.0;
         return true;
      case 38:     // X32 a pending order without SL and no cap: no block, the sums stay
         LvOff(v,"X32 extra pending without SL, cap 0");
         LvEx(v,false,true,-700.0);
         LvEx(v,true,true,-300.0);
         LvEx(v,true,false,0.0);
         v.exp_no_sl=1;
         v.exp_open_risk=700.0;
         v.exp_pending_risk=300.0;
         v.exp_max_new=-1.0;
         return true;
      //--- the profile of the account: a damaged file, a file still being read -------------------------------
      case 39:     // V1 damaged profile blocks, nothing may be opened
         LvOff(v,"V1 profile damaged");
         v.in.profile_bad=true;
         v.exp_max_new=0.0;
         LvExpect(v,PL_BLOCK,PL_LW_PROFILE_BAD);
         return true;
      case 40:     // V1b damaged profile beats every other block
         LvOff(v,"V1b profile damaged before the cap and the counters");
         v.in.profile_bad=true;
         v.c.portfolio_cap_pct=1.0;
         v.c.max_open=1;
         v.in.open_count=1;
         LvEx(v,false,true,-2000.0);
         v.exp_portfolio_pct=2.0;
         v.exp_max_new=0.0;
         LvExpect(v,PL_BLOCK,PL_LW_PROFILE_BAD);
         return true;
      case 41:     // W1 the profile is being read while a cap may be on in some file: waits, even with the history loaded
         LvOff(v,"W1 profile being read, a cap may be on");
         v.in.profile_wait=true;
         v.exp_max_new=0.0;
         LvExpect(v,PL_BLOCK,PL_LW_NO_HISTORY);
         return true;
      case 42:     // W1b the wait beats the cap
         LvOff(v,"W1b profile being read before the cap");
         v.in.profile_wait=true;
         v.c.portfolio_cap_pct=1.0;
         LvEx(v,false,true,-2000.0);
         v.exp_portfolio_pct=2.0;
         v.exp_max_new=0.0;
         LvExpect(v,PL_BLOCK,PL_LW_NO_HISTORY);
         return true;
      //--- priority: neighbours, the earlier reason wins ------------------------------------------------------
      case 43:     // X6 a new trade without SL under a cap beats the unknown risk
         LvOff(v,"X6 new trade without SL before the unknown risk");
         v.c.portfolio_cap_pct=3.0;
         v.in.new_no_sl=true;
         LvExUnk(v,false);
         v.exp_unknown=1;
         LvExpect(v,PL_BLOCK,PL_LW_NEW_NO_SL);
         return true;
      case 44:     // X7 the unknown risk beats the portfolio checks
         LvOff(v,"X7 unknown risk before the cap");
         v.c.portfolio_cap_pct=1.0;
         LvEx(v,false,true,-2000.0);
         LvExUnk(v,true);
         v.exp_unknown=1;
         v.exp_open_risk=2000.0;
         v.exp_portfolio_pct=2.0;
         LvExpect(v,PL_BLOCK,PL_LW_RISK_UNKNOWN);
         return true;
      case 45:     // X8 Max trades a day waits for the history before it counts
         LvOff(v,"X8 history before the counters");
         v.c.max_open=1;
         v.c.max_day=1;
         v.in.open_count=1;
         v.in.trades_today=1;
         v.in.deals_loaded=false;
         LvExpect(v,PL_BLOCK,PL_LW_NO_HISTORY);
         return true;
     }
   return false;
  }

//+------------------------------------------------------------------+
//| the midnight of the server clock (Max trades a day)               |
//+------------------------------------------------------------------+
//--- server time | expected day start. The deal times of the history and TimeTradeServer are both server time
string g_pl_srvday_rows[]=
  {
   "2026.10.16 12:34:56|2026.10.16 00:00:00",
   "2026.10.16 00:00:00|2026.10.16 00:00:00",     // the midnight second starts the new day
   "2026.10.15 23:59:59|2026.10.15 00:00:00",     // one second before it is the day before
   "2026.10.16 00:00:01|2026.10.16 00:00:00",
   "2026.10.25 03:30:00|2026.10.25 00:00:00",     // the weekend the EU changes its clocks: the server clock is just a clock
   "2026.12.31 23:59:59|2026.12.31 00:00:00",
   "2027.01.01 00:00:00|2027.01.01 00:00:00",
   "2028.02.29 10:00:00|2028.02.29 00:00:00"      // a leap day
  };

//--- the entries at the border of the server day: name | now (server time) | entry times | max a day | the count today,
//--- then the verdict of a market order now (3 BLOCK, 0 OK)
string g_pl_srvcount_rows[]=
  {
   "S1 one second before the midnight and one after, limit 2|2026.10.16 10:00:00|2026.10.15 23:59:59,2026.10.16 00:00:01|2|1|0",
   "S2 the same with a limit of 1: only the entry after the midnight counts|2026.10.16 10:00:00|2026.10.15 23:59:59,2026.10.16 00:00:01|1|1|3",
   "S3 an entry at the midnight second belongs to the new day|2026.10.16 10:00:00|2026.10.16 00:00:00|1|1|3",
   "S4 an entry a second before the midnight belongs to the old day|2026.10.16 10:00:00|2026.10.15 23:59:59|1|0|0",
   "S5 none today, three yesterday|2026.10.16 00:30:00|2026.10.15 12:00:00,2026.10.15 18:00:00,2026.10.15 23:59:59|1|0|0",
   "S6 just before the next midnight the day still counts|2026.10.16 23:59:59|2026.10.16 00:00:00,2026.10.16 23:59:58|2|2|3",
   "S7 the midnight second after that starts empty|2026.10.17 00:00:00|2026.10.16 00:00:00,2026.10.16 23:59:58|2|0|0"
  };

//--- PlGuardWhy | expected verdict, the reasons of the core (a build with more checks runs the list with its own reasons too)
string g_pl_free_why_rows[]=
  {
   "0|0", "1|3", "2|3", "3|3", "4|3", "5|3", "6|3", "7|3", "8|3", "10|2"
  };

//--- text | FNV-1a 32 | FNV-1a 64 (computed with a Python reference, one step per code unit)
string g_pl_fnv_rows[]=
  {
   "|811c9dc5|cbf29ce484222325",
   "a|e40c292c|af63dc4c8601ec8c"
  };

#endif
