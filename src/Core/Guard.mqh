// Required Notice: Copyright 2026 stop-loss-enjoyer
// Plainlines is source-available under the PolyForm Shield License 1.0.0.
//
// The guards of a new trade: Max total risk (the portfolio cap), Max open, Max trades a day and the margin use
// Pure core: nothing here asks the terminal for anything (no TimeGMT,
// TimeCurrent, TimeLocal, no account or deal calls). The terminal layer fills the structs.
//
// Readings chosen where the rules are silent (all of them are conservative or neutral):
//   - A position or order without SL adds 0 to the risk sums and is counted in no_sl. With Max total risk on,
//     no_sl > 0 blocks (PORTFOLIO_UNKNOWN) anyway.
//   - A new trade without SL has unknown risk: it is refused while Max total risk is on.
//   - An entry with an SL whose money at the SL cannot be valued (PlExpo.unknown) is unknown, never zero: it is
//     counted in unknown, left out of the sums, and blocks (RISK_UNKNOWN) while Max total risk or subtract-open-risk is on.
//   - Every threshold comparison goes through PL_EPS: "3.0000000000000004 > 3" must not block.
//     Equality passes for caps and the margin threshold. The two trade counters count what the trade would make:
//     open_count + new_open > max_open and trades_today + new_entries > max_day block (a trade is every entering order,
//     each leg of a hedged multi-TP trade and each part of a Split; new_entries is the market ones only, a pending order
//     enters the count when it is filled).
//   - Max trades a day counts from the midnight of the server clock (PlServerDayStart). Its count is unknown, never
//     zero, while the deal history is not loaded (NO_HISTORY), so it waits for the history.
//   - The profile file of the account (the fingerprint and Max total risk) that fails its checksum blocks (PROFILE_BAD),
//     and while it is being read (profile_wait) a cap that may be on in some file of the server blocks too.
//   - Block order, first match wins: PROFILE_BAD, NO_HISTORY, NEW_NO_SL, RISK_UNKNOWN, PORTFOLIO_UNKNOWN, PORTFOLIO_CAP,
//     TRADES_OPEN, TRADES_DAY; then the confirmation (MARGIN_USE). PlWhyRank is the one place of this order: a build with
//     more checks merges its reasons into it by rank.
#property strict

#ifndef PL_CORE_GUARD_MQH
#define PL_CORE_GUARD_MQH

#include "Types.mqh"
#include "Num.mqh"

#define PL_LIM_BIG       1.0e9    // "percent" when the divisor is zero but the dividend is not

//--- the reasons. A reason belongs to a class by its number: 1-9 BLOCK, 10-19 CONFIRM, 20-39 BLOCK and 40-59 WARN are the
//--- numbers kept for the reasons of a build with more checks (defined there, merged by PlWhyRank)
enum PlGuardWhy
  {
   PL_LW_NONE=0,
   //--- BLOCK
   PL_LW_PROFILE_BAD=1,        // the profile file of this account is damaged
   PL_LW_NO_HISTORY=2,         // Max trades a day on, deals not loaded (or not adding up to the balance), or the profile is being read
   PL_LW_NEW_NO_SL=3,          // the new trade has no SL (Max total risk on)
   PL_LW_RISK_UNKNOWN=4,       // an entry with an SL whose money at the SL cannot be valued
   PL_LW_PORTFOLIO_UNKNOWN=5,  // cap set, a position or order has no SL
   PL_LW_PORTFOLIO_CAP=6,      // total risk with the new trade above the cap
   PL_LW_TRADES_OPEN=7,        // open positions and orders reached the maximum
   PL_LW_TRADES_DAY=8,         // trades opened today reached the maximum
   //--- CONFIRM
   PL_LW_MARGIN_USE=10         // margin use after the trade above the threshold
  };
#define PL_LW_EXT_BLOCK_FIRST  20    // a build with more checks numbers its BLOCK reasons from here ...
#define PL_LW_EXT_WARN_FIRST   40    // ... and its WARN reasons from here

//--- what a build with more checks adds to the three structs below. This build adds nothing; a build with more checks defines the
//--- real ones before this file
struct PlCfgExt { int none; };
struct PlInExt  { int none; };
struct PlOutExt { int none; };

//--- settings of the guards
struct PlGuardCfg
  {
   double            portfolio_cap_pct;   // 0 = off
   int               max_open;            // 0 = off
   int               max_day;             // 0 = off
   double            margin_use_pct;      // CONFIRM above this, 0 = off
   bool              subtract_open;       // the panel subtracts the open risk: unknown risk blocks
   PlCfgExt          ext;
  };

//--- one open position or pending order
struct PlExpo
  {
   bool              pending;
   bool              has_sl;
   double            pl_at_sl;            // money if closed at SL now, loss negative
   bool              unknown;             // has_sl, but the money at the SL cannot be valued
  };

struct PlGuardIn
  {
   bool              deals_loaded;
   bool              profile_bad;         // the profile file of this account is damaged
   bool              profile_wait;        // the profile is being read and a file of the server may hold a cap
   double            balance;
   double            equity;
   double            margin;
   double            new_risk;            // risk of the trade the panel is about to send
   double            new_margin;          // its margin
   bool              new_no_sl;           // the new trade has no SL: its risk is unknown
   int               open_count;          // all positions and orders of the account
   int               trades_today;        // entering deals since the midnight of the server clock
   int               new_open;            // orders the press puts on the account (1 for a single order)
   int               new_entries;         // of them the market ones, which enter at once (0 for a pending order)
   PlInExt           ext;
  };

struct PlGuardOut
  {
   PlVerdict         verdict;
   PlGuardWhy        why;
   double            max_new_risk;        // -1: no limit from the guards that set one (a build with more checks sets its own)
   double            open_risk;
   double            pending_risk;
   double            portfolio_pct;
   double            margin_use_pct;
   int               no_sl;
   int               unknown;
   int               open_after;          // open_count + new_open
   int               entries_after;       // trades_today + new_entries
   PlOutExt          ext;
  };

//--- the checks of a build with more checks; this build has none

//--- the day of the server clock: the last midnight of the server clock at or before the server time t.
//--- The deal times of the history and TimeTradeServer are both server time, so the two compare without any offset.
datetime PlServerDayStart(const datetime t_server)
  {
   const long t=(long)t_server;
   return (datetime)(t-(((t%86400)+86400)%86400));
  }

//--- how many of the entry times (server time) are at or after the day start
int PlCountSince(const datetime &t[],const int n,const datetime since)
  {
   int c=0;
   for(int i=n-1; i>=0; i--)
      if(t[i]>=since)
         c++;
   return c;
  }

//--- where a reason stands in the order of the checks (smaller is checked first); the gaps are for the reasons of a build with more checks.
//--- Inside one class (BLOCK, CONFIRM, WARN) the smallest rank wins
int PlWhyRank(const PlGuardWhy w)
  {
   switch(w)
     {
      case PL_LW_NONE:               return 0;
      case PL_LW_PROFILE_BAD:        return 100;
      case PL_LW_NO_HISTORY:         return 200;
      case PL_LW_NEW_NO_SL:          return 900;
      case PL_LW_RISK_UNKNOWN:       return 1000;
      case PL_LW_PORTFOLIO_UNKNOWN:  return 1300;
      case PL_LW_PORTFOLIO_CAP:      return 1400;
      case PL_LW_TRADES_OPEN:        return 1500;
      case PL_LW_TRADES_DAY:         return 1600;
      case PL_LW_MARGIN_USE:         return 2000;
     }
   return 9999;
  }

//--- the verdict class of a reason
PlVerdict PlGuardWhyVerdict(const PlGuardWhy w)
  {
   if(w==PL_LW_NONE)
      return PL_OK;
   if(w==PL_LW_MARGIN_USE)
      return PL_CONFIRM;
   if((int)w<PL_LW_EXT_BLOCK_FIRST)
      return PL_BLOCK;
   return PL_BLOCK;     // a number nobody defines: refuse
  }

//+------------------------------------------------------------------+
//| the guards                                                       |
//+------------------------------------------------------------------+
void PlGuardRun(const PlGuardCfg &c,const PlGuardIn &in,const PlExpo &ex[],PlGuardOut &o
                )
  {
   ZeroMemory(o);
   o.verdict=PL_OK;
   o.why=PL_LW_NONE;
   o.max_new_risk=-1.0;
   o.open_after=in.open_count+in.new_open;
   o.entries_after=in.trades_today+in.new_entries;

   //--- exposure: money at SL, risk sums, positions and orders without SL
   double pl_sum=0.0;
   const int ne=ArraySize(ex);
   for(int i=0; i<ne; i++)
     {
      if(!ex[i].has_sl)
        {
         o.no_sl++;
         continue;
        }
      if(ex[i].unknown)
        {
         o.unknown++;
         continue;
        }
      pl_sum+=ex[i].pl_at_sl;
      if(ex[i].pl_at_sl<0.0)
        {
         if(ex[i].pending)
            o.pending_risk-=ex[i].pl_at_sl;
         else
            o.open_risk-=ex[i].pl_at_sl;
        }
     }

   //--- portfolio and margin percents
   const double risk_all=o.open_risk+o.pending_risk+in.new_risk;
   if(in.balance>PL_EPS)
      o.portfolio_pct=risk_all/in.balance*100.0;
   else
      o.portfolio_pct=(risk_all>PL_EPS)?PL_LIM_BIG:0.0;
   const double marg_all=in.margin+in.new_margin;
   if(in.equity>PL_EPS)
      o.margin_use_pct=marg_all/in.equity*100.0;
   else
      o.margin_use_pct=(marg_all>PL_EPS)?PL_LIM_BIG:0.0;

   //--- a damaged file or a profile still being read: nothing may be opened
   if(in.profile_bad || in.profile_wait)
      o.max_new_risk=0.0;

   //--- reasons in priority order: first BLOCK, first CONFIRM, first WARN
   PlGuardWhy block=PL_LW_NONE;
   PlGuardWhy conf=PL_LW_NONE;
   PlGuardWhy warn=PL_LW_NONE;

   if(in.profile_bad)
      block=PL_LW_PROFILE_BAD;
   if(block==PL_LW_NONE && ((c.max_day>0 && !in.deals_loaded) || in.profile_wait))
      block=PL_LW_NO_HISTORY;
   if(block==PL_LW_NONE && in.new_no_sl && c.portfolio_cap_pct>PL_EPS)
      block=PL_LW_NEW_NO_SL;
   if(block==PL_LW_NONE && (c.portfolio_cap_pct>PL_EPS || c.subtract_open) && o.unknown>0)
      block=PL_LW_RISK_UNKNOWN;
   if(block==PL_LW_NONE && c.portfolio_cap_pct>PL_EPS && o.no_sl>0)
      block=PL_LW_PORTFOLIO_UNKNOWN;
   if(block==PL_LW_NONE && c.portfolio_cap_pct>PL_EPS && o.portfolio_pct>c.portfolio_cap_pct+PL_EPS)
      block=PL_LW_PORTFOLIO_CAP;
   if(block==PL_LW_NONE && c.max_open>0 && o.open_after>c.max_open)
      block=PL_LW_TRADES_OPEN;
   if(block==PL_LW_NONE && c.max_day>0 && o.entries_after>c.max_day)
      block=PL_LW_TRADES_DAY;

   if(c.margin_use_pct>PL_EPS && o.margin_use_pct>c.margin_use_pct+PL_EPS)
      conf=PL_LW_MARGIN_USE;


   if(block!=PL_LW_NONE)
      o.why=block;
   else if(conf!=PL_LW_NONE)
      o.why=conf;
   else
      o.why=warn;
   o.verdict=PlGuardWhyVerdict(o.why);
  }

//--- a profile file that fails its checksum: is it surely another account's (skip it) or not (it may be ours, torn: BAD)?
//--- PlProfWrite writes rid, fp_server, fp_cur, fp_t in this order, so when fp_t is there the fp_server and fp_cur lines
//--- were complete and can be trusted; a cut inside them proves nothing.
bool PlProfSurelyOther(const bool has_fp_t,const string fp_server,const string fp_cur,const string srv,const string cur)
  {
   return (has_fp_t && (fp_server!=srv || fp_cur!=cur));
  }

#endif
