// Required Notice: Copyright 2026 stop-loss-enjoyer
// Plainlines is source-available under the PolyForm Shield License 1.0.0.
//
// Step 2 of the core: loss per lot (OrderCalcProfit (c) checked by the tick value (a)), commission, lot, risk, reward,
// margin, spread, swaps, verdict. Pure function of its arguments, never calls the terminal.
#property strict

#ifndef PL_CORE_LOT_MQH
#define PL_CORE_LOT_MQH

#include "Types.mqh"
#include "Num.mqh"

#define PL_STALE_FX_SECONDS    60    // forex and metals tick every few seconds: a tick older than this is stale
#define PL_STALE_QUIET_SECONDS 300   // stocks, CFDs, indexes, commodities, crypto and exchange symbols may sit quiet for minutes
#define PL_SPREAD_SHARE_DEF  0.3     // default max spread share of the SL distance
#define PL_STOPOUT_MARGIN    10.0    // margin level points kept above the stop-out level
#define PL_PATH_TOLERANCE    0.01    // share part of the a/c tolerance; after the SL-rate correction the probes show rounding only

//--- verdict collector: BLOCK over CONFIRM over WARN, inside a class the lower enum value wins
struct PlVerdictAcc
  {
   PlVerdict         verdict;
   PlReason          reason;
  };

void PlAccAdd(PlVerdictAcc &acc,const PlVerdict v,const PlReason r)
  {
   if((int)v>(int)acc.verdict || (v==acc.verdict && (acc.reason==PL_R_NONE || (int)r<(int)acc.reason)))
     {
      acc.verdict=v;
      acc.reason=r;
     }
  }

void PlResultInit(PlResult &r)
  {
   r.verdict=PL_OK;
   r.reason=PL_R_NONE;
   r.note=PL_R_NONE;
   r.lpl_a=0.0;
   r.lpl_c=0.0;
   r.lpl_price=0.0;
   r.comm_in_1lot=0.0;
   r.comm_out_1lot=0.0;
   r.loss_per_lot=0.0;
   r.risk_target=0.0;
   r.lot_raw=0.0;
   r.lot=0.0;
   r.risk_money=0.0;
   r.net_risk=0.0;
   r.risk_add=0.0;
   r.risk_percent=0.0;
   for(int i=0; i<PL_MAX_TP; i++)
      r.reward[i]=0.0;
   r.reward_total=0.0;
   r.rr=0.0;
   r.spread_points=0.0;
   r.spread_money=0.0;
   r.comm_money=0.0;
   r.comm_min_on=false;
   r.swap_long_night=0.0;
   r.swap_short_night=0.0;
   r.swap_ok=true;
   r.margin_needed=0.0;
   r.split_n=0;
   r.split_need=0;
   for(int i=0; i<PL_MAX_PARTS; i++)
      r.split_lot[i]=0.0;
  }

#define PL_CCY_EQ_TOL 1e-4   // two currencies within 0.01% count as one; probes 13.10.2026: USD-base pairs within 1.1e-7, nearest other 0.755
enum PlCcyRel { PL_CCY_NA=0, PL_CCY_PROFIT=1, PL_CCY_BASE=2, PL_CCY_CROSS=3 };

//--- calc modes where profit = (close - open) * contract * lots (MQL5 ENUM_SYMBOL_CALC_MODE)
bool PlDeltaMode(const int m)
  {
   return m==SYMBOL_CALC_MODE_FOREX || m==SYMBOL_CALC_MODE_FOREX_NO_LEVERAGE || m==SYMBOL_CALC_MODE_CFD
          || m==SYMBOL_CALC_MODE_CFDINDEX || m==SYMBOL_CALC_MODE_CFDLEVERAGE || m==SYMBOL_CALC_MODE_EXCH_STOCKS
          || m==SYMBOL_CALC_MODE_EXCH_STOCKS_MOEX;
  }

bool PlForexMode(const int m)
  {
   return m==SYMBOL_CALC_MODE_FOREX || m==SYMBOL_CALC_MODE_FOREX_NO_LEVERAGE;
  }

//--- gold, silver, platinum and palladium: the base currency or the start of the name (a suffix like "+" or ".r" follows it)
bool PlMetalSymbol(const PlSymbol &s)
  {
   const string b=StringSubstr(s.base,0,3), n=StringSubstr(s.name,0,3);
   return (b=="XAU" || b=="XAG" || b=="XPT" || b=="XPD" || n=="XAU" || n=="XAG" || n=="XPT" || n=="XPD");
  }

//--- how old the last tick may be on an open session: by the class of the symbol, from its calc mode and its metal base
int PlStaleSeconds(const PlSymbol &s)
  {
   return (PlForexMode(s.calc_mode) || PlMetalSymbol(s))?PL_STALE_FX_SECONDS:PL_STALE_QUIET_SECONDS;
  }

bool PlUnsupportedMode(const int m)
  {
   return m==SYMBOL_CALC_MODE_EXCH_BONDS || m==SYMBOL_CALC_MODE_EXCH_BONDS_MOEX || m==SYMBOL_CALC_MODE_SERV_COLLATERAL;
  }

//--- how the account currency relates to the symbol, from the tick value alone (no currency strings):
//--- k = tvl/(tick*contract) is the profit currency rate, ref = tick*contract/tvl the price the tick value was taken at
int PlCcyRelation(const PlSymbol &s)
  {
   if(!PlDeltaMode(s.calc_mode) || s.tick_size<=0.0 || s.contract<=0.0 || s.tick_value_loss<=0.0 || s.bid<=0.0)
      return PL_CCY_NA;
   const double k=s.tick_value_loss/(s.tick_size*s.contract);
   if(MathAbs(k-1.0)<=PL_CCY_EQ_TOL)
      return PL_CCY_PROFIT;          // first: base = profit symbols (XAUUSD on USD) must not be corrected
   const double ref=1.0/k;
   if(MathAbs(ref/s.bid-1.0)<=PL_CCY_EQ_TOL)
      return PL_CCY_BASE;
   return PL_CCY_CROSS;
  }

//--- path (a) for 1 lot: tick value, or at the SL rate when the base currency is the account currency
//--- (OrderCalcProfit converts at the close price there: USDCHF+ 120.25 = 100/(0.83259-0.001))
double PlLossA(const PlSymbol &s,const double sl,const long ticks)
  {
   if(PlCcyRelation(s)==PL_CCY_BASE && sl>0.0)
      return (double)ticks*s.tick_size*s.contract/sl;
   return (double)ticks*s.tick_value_loss;
  }

//--- (a) and (c) agree: share tolerance plus half a unit of the account currency (OrderCalcProfit rounds to it)
bool PlPathsAgree(const double a,const double c,const int digits)
  {
   const double half=0.5/PlPow10(digits);
   return MathAbs(a-c)<=PL_PATH_TOLERANCE*MathMax(a,c)+half+PL_EPS;
  }

//--- lot grid as the broker defines it: min and max on the step grid counted from min
bool PlVolumeGridOk(const PlSymbol &s)
  {
   if(s.vol_step<=0.0 || s.vol_min<=0.0 || s.vol_max<s.vol_min-PL_EPS)
      return false;
   const double u=s.vol_min/s.vol_step, w=(s.vol_max-s.vol_min)/s.vol_step;
   return MathAbs(u-MathRound(u))<=1e-6 && MathAbs(w-MathRound(w))<=1e-6;
  }

//--- profit currency -> account currency, from the tick value; false outside the dPrice modes
bool PlRateK(const PlSymbol &s,double &k)
  {
   k=0.0;
   if(!PlDeltaMode(s.calc_mode) || s.tick_size<=0.0 || s.contract<=0.0 || s.tick_value_loss<=0.0)
      return false;
   k=s.tick_value_loss/(s.tick_size*s.contract);
   return true;
  }

//--- account money per unit of a currency of the symbol; false when unknown. Equal strings of the symbol's own
//--- fields are the same currency; the account currency string is never compared.
bool PlCcyRate(const string cur,const PlSymbol &s,const bool k_ok,const double k,double &rate)
  {
   rate=0.0;
   if(!k_ok)
      return false;
   if(cur==s.profit)
     {
      rate=k;
      return true;
     }
   if(cur==s.base && PlForexMode(s.calc_mode))
     {
      rate=(s.bid+s.ask)/2.0*k;    // 1 base = price profit units
      return true;
     }
   return false;
  }

//--- swap per night for the lot, account money; ok=false when it cannot be worked out (shown as n/a)
double PlSwapNight(const PlSymbol &s,const double swap,const double lot,const bool k_ok,const double k,bool &ok)
  {
   ok=true;
   double r=0.0;
   switch(s.swap_mode)
     {
      case SYMBOL_SWAP_MODE_DISABLED:
         return 0.0;
      case SYMBOL_SWAP_MODE_POINTS:
         if(s.tick_size>0.0)
            return swap*s.point/s.tick_size*s.tick_value_profit*lot;
         break;
      case SYMBOL_SWAP_MODE_CURRENCY_SYMBOL:
         if(PlCcyRate(s.base,s,k_ok,k,r))
            return swap*lot*r;
         break;
      case SYMBOL_SWAP_MODE_CURRENCY_MARGIN:
         if(PlCcyRate(s.margin,s,k_ok,k,r))
            return swap*lot*r;
         break;
      case SYMBOL_SWAP_MODE_CURRENCY_DEPOSIT:
         return swap*lot;
      case SYMBOL_SWAP_MODE_CURRENCY_PROFIT:
         if(k_ok)
            return swap*lot*k;
         break;
      case SYMBOL_SWAP_MODE_INTEREST_CURRENT:
      case SYMBOL_SWAP_MODE_INTEREST_OPEN:
         if(k_ok)
            return (s.bid+s.ask)/2.0*s.contract*swap/100.0/360.0*k*lot;
         break;
     }
   ok=false;                                  // REOPEN_*, unknown currency or mode
   return 0.0;
  }

//--- the final-volume margin check after the core: may only raise the verdict
void PlApplyFinalMargin(PlResult &r,const PlAccount &a,const bool ok,const double m_lot)
  {
   if(r.lot<=PL_EPS)
      return;
   PlVerdictAcc acc;
   acc.verdict=r.verdict;
   acc.reason=r.reason;
   if(!ok || m_lot<=0.0)
      PlAccAdd(acc,PL_BLOCK,PL_R_NO_SYMBOL_DATA);
   else
     {
      r.margin_needed=MathMax(r.margin_needed,m_lot);
      if(r.margin_needed>a.margin_free+PL_EPS)
         PlAccAdd(acc,PL_BLOCK,PL_R_MARGIN);
     }
   r.verdict=acc.verdict;
   r.reason=acc.reason;
  }

//--- the hint as a commission setting: a closed position with both sides charged is per side (the larger side, safe
//--- when they differ); one side charged is once per round; entry only (no closed position yet): per side, which
//--- counts the entry twice (safe for the lot, the exit is unknown)
void PlHintToComm(const double in_lot,const double out_lot,const bool closed,PlCommKind &kind,double &rate)
  {
   if(closed && (in_lot>PL_EPS)!=(out_lot>PL_EPS))
     {
      kind=PL_COMM_LOT_ROUND;
      rate=in_lot+out_lot;
      return;
     }
   kind=PL_COMM_LOT_SIDE;
   rate=closed?MathMax(in_lot,out_lot):in_lot;
  }

//--- the broker's own commission rule (SymbolInfoCommissions) as plain data: one rule with its first tier and the number of
//--- tiers. The integers are the terminal enums (SYMBOL_COMMISSION_*), copied by Terminal/Market.mqh PlCommRule.
struct PlBrokerRule
  {
   string            currency;         // the rule currency
   int               mode_charge;      // SYMBOL_COMMISSION_CHARGE_*
   int               mode_direction;   // SYMBOL_COMMISSION_DIRECTION_*
   int               mode_entry;       // SYMBOL_COMMISSION_ENTRY_*
   int               mode_profit;      // SYMBOL_COMMISSION_PROFIT_*
   int               mode_range;       // SYMBOL_COMMISSION_RANGE_*
   int               tier_count;
   double            range_from;
   double            range_to;
   double            min_value;
   double            max_value;
   double            value;
   int               tier_mode;        // SYMBOL_COMMISSION_PERCENT, _MONEY_SPECIFIED, _MONEY_DEPOSIT ...
   int               volume_type;      // SYMBOL_COMMISSION_VOLUME_TYPE_*
   string            tier_currency;    // "" when the tier names none
  };

//--- the broker's commission rule as a commission setting (decision of 13.10.2026, demo FTMO facts; the tier currency and the
//--- minimum since 15.10.2026, Bybit facts of 14.10.2026). Only the one plain shape is accepted: exactly 1 rule with 1 tier,
//--- charged instantly, both directions, all profit, by volume, the volume inside the tier range, no max money, and the rule
//--- currency EXACTLY equal to the account currency (the same string is the same currency; USD against UST is not).
//--- The currency of the TIER may differ (Bybit shares: the rule is in UST, the tier 0.02 and the minimum 0.2 in USD): then it
//--- must be a currency of the symbol itself, the profit currency or, on Forex modes, the base currency, and the rate and the
//--- minimum are converted to account money by PlCcyRate, the path the swap takes (k from the tick value). Only MONEY_SPECIFIED
//--- has a currency of its own to convert; MONEY_DEPOSIT and PERCENT with a foreign tier currency are refused. Without a rate
//--- of conversion the rule is refused. Anything else: false, the caller falls back to the deal sample or the user.
//--- n is the return of SymbolInfoCommissions (-1 error). The value is already in percent for PERCENT (0.0007 is 0.0007 percent).
//---   PERCENT + INOUT -> PL_COMM_PERCENT_SIDE;  MONEY_* + INOUT -> PL_COMM_LOT_SIDE;
//---   MONEY_* + IN -> PL_COMM_LOT_ROUND: Lot.mqh splits a round in half in and out, so the round total is right and the
//---   exit cost of an already open position is overestimated, the safe side.
//--- A minimum (min_value > 0) is accepted only for MONEY_* + IN: it is the money one order pays once for the round
//--- (min_round, account money). With INOUT or PERCENT the minimum would be per deal and per side with a price-dependent rate:
//--- not known to hold, refused.
//--- known_zero: the rule says 0 (US500.cash): kind LOT_SIDE with rate 0, counted as zero with no "not counted" note.
//--- A zero rate with a minimum is not a zero: LOT_ROUND with rate 0 and the minimum, known_zero false.
bool PlBrokerCommRule(const int n,const PlBrokerRule &r[],const string account_ccy,const double vol,
                      const PlSymbol &s,const bool k_ok,const double k,
                      PlCommKind &kind,double &rate,double &min_round,bool &known_zero)
  {
   kind=PL_COMM_UNKNOWN; rate=0.0; min_round=0.0; known_zero=false;
   if(n!=1 || ArraySize(r)<1 || account_ccy=="")
      return false;
   if(r[0].tier_count!=1)
      return false;
   if(r[0].mode_charge!=SYMBOL_COMMISSION_CHARGE_INSTANT || r[0].mode_direction!=SYMBOL_COMMISSION_DIRECTION_BOTH
      || r[0].mode_profit!=SYMBOL_COMMISSION_PROFIT_ALL || r[0].mode_range!=SYMBOL_COMMISSION_RANGE_VOLUME
      || r[0].volume_type!=SYMBOL_COMMISSION_VOLUME_TYPE_VOLUME)
      return false;
   if(r[0].currency!=account_ccy)
      return false;
   if(r[0].max_value!=0.0)
      return false;
   if(!(vol>0.0) || vol<r[0].range_from-PL_EPS || vol>r[0].range_to+PL_EPS)
      return false;
   if(!MathIsValidNumber(r[0].value) || r[0].value<0.0 || !MathIsValidNumber(r[0].min_value) || r[0].min_value<0.0)
      return false;
   const int m=r[0].tier_mode;
   const int e=r[0].mode_entry;
   //--- the tier currency: the account's own, or one of the symbol converted by the swap's path
   double cf=1.0;
   if(r[0].tier_currency!="" && r[0].tier_currency!=account_ccy)
     {
      if(m!=SYMBOL_COMMISSION_MONEY_SPECIFIED)
         return false;
      if(!PlCcyRate(r[0].tier_currency,s,k_ok,k,cf) || !(cf>0.0))
         return false;
     }
   if(m==SYMBOL_COMMISSION_PERCENT && e==SYMBOL_COMMISSION_ENTRY_INOUT)
      kind=PL_COMM_PERCENT_SIDE;
   else if((m==SYMBOL_COMMISSION_MONEY_SPECIFIED || m==SYMBOL_COMMISSION_MONEY_DEPOSIT) && e==SYMBOL_COMMISSION_ENTRY_INOUT)
      kind=PL_COMM_LOT_SIDE;
   else if((m==SYMBOL_COMMISSION_MONEY_SPECIFIED || m==SYMBOL_COMMISSION_MONEY_DEPOSIT) && e==SYMBOL_COMMISSION_ENTRY_IN)
      kind=PL_COMM_LOT_ROUND;
   else
      return false;
   if(r[0].min_value>0.0 && kind!=PL_COMM_LOT_ROUND)
     {
      kind=PL_COMM_UNKNOWN;
      return false;
     }
   rate=r[0].value*cf;
   min_round=r[0].min_value*cf;
   if(r[0].value==0.0 && min_round==0.0)
     {
      kind=PL_COMM_LOT_SIDE;
      known_zero=true;
     }
   return true;
  }

//--- a lot above the broker max cut into equal orders on the lot step: n = ceil(lot / vol_max), every order gets
//--- floor(lot / n) steps and the first (lot mod n) orders one step more. Returns n; the lots are written only
//--- when n <= PL_MAX_PARTS. 0: cannot be cut (no step, an order below vol_min, an order off the lot grid).
int PlSplitLots(const double lot,const double vol_min,const double vol_max,const double vol_step,double &parts[])
  {
   if(vol_step<=0.0 || vol_max<vol_step-PL_EPS)
      return 0;
   const long u=(long)MathRound(lot/vol_step);
   const long vm=(long)MathFloor(vol_max/vol_step+1e-8);
   if(u<=vm || vm<1)
      return 0;
   const long n=(u+vm-1)/vm;
   const long base=u/n, rem=u%n;
   if((double)base*vol_step<vol_min-PL_EPS)
      return 0;
   const int dg=PlStepDigits(vol_step);
   if(MathAbs(MathRound(vol_min/vol_step)*vol_step-vol_min)>PL_EPS)
      return 0;                                       // a minimum off the step grid: the parts could be off the grid
   if(n>PL_MAX_PARTS)
      return (int)n;
   for(int i=0; i<(int)n; i++)
      parts[i]=PlRoundDigits((double)(base+((long)i<rem?1:0))*vol_step,dg);
   return (int)n;
  }

//--- netting: the TP parts of a new position fit the lot. Mirrors the manager (Manage.mqh PlRecManage step 1): level j
//--- closes floor(vol - lot*(100-cum)/100) on the lot step and is done when that is below the minimum lot; the last
//--- part is what stays (PlSendClosePos closes the whole position when the rest would be below the minimum).
bool PlTpPartsFit(const double lot,const double vol_min,const double vol_step,const PlInputs &in,const PlPlan &plan)
  {
   int lv[PL_MAX_TP];
   int nl=0;
   for(int i=0; i<PL_MAX_TP; i++)
      if(in.tp[i].on && !in.no_tp && plan.tp[i]>0.0)
        {
         lv[nl]=i;
         nl++;
        }
   if(nl<2)
      return true;
   const int dg=PlStepDigits(vol_step);
   double vol=lot, cum=0.0;
   for(int j=0; j<nl-1; j++)
     {
      cum+=in.tp[lv[j]].share;
      const double target=lot*MathMax(0.0,100.0-cum)/100.0;
      const double part=(vol_step>0.0)?PlFloorStep(vol-target,vol_step):(vol-target);
      if(part<vol_min-PL_EPS)
         return false;
      vol=PlRoundDigits(vol-part,dg);
     }
   return (vol>=vol_min-PL_EPS);
  }

//--- netting: did the position grow after the plan was made? The volume the done TP parts leave is replayed with the
//--- same arithmetic the manager uses to close a part (floor on the lot step, a part below the minimum lot is not sent),
//--- so the rounding left over is not mistaken for an add. An add is at least the minimum lot, so it shows above that
//--- volume by vmin minus half a step. Needs no state beyond vol0 and the done flags of the record.
bool PlPosGrew(const double vol,const double vol0,const double &share[],const bool &done[],const int n,const double vmin,const double step)
  {
   double v=vol0, cum=0.0;
   for(int j=0; j<n && j<2; j++)
     {
      cum+=share[j];
      if(!done[j])
         continue;
      const double target=vol0*MathMax(0.0,100.0-cum)/100.0;
      const double part=(step>0.0)?PlFloorStep(v-target,step):(v-target);
      if(part>=vmin-PL_EPS)
         v-=part;
     }
   return (vol>v+MathMax(vmin-step*0.5,PL_EPS));
  }

//--- the volume a new record starts from (vol0): the volume of the position when it was found, else the lot the send
//--- put down for that part. 0: unknown, the caller must not keep TP parts on such a record (a part of 0 would close all).
double PlRecStartVol(const bool pos_found,const double pos_vol,const double part_lot)
  {
   if(pos_found && pos_vol>0.0)
      return pos_vol;
   return (part_lot>0.0)?part_lot:0.0;
  }

void PlCompute(const PlInputs &in,const PlSymbol &s,const PlAccount &a,const PlPlan &plan,PlResult &r)
  {
   PlResultInit(r);
   if(!plan.ok)
     {
      r.verdict=PL_BLOCK;
      r.reason=plan.reason;
      return;
     }

   PlVerdictAcc acc;
   acc.verdict=PL_OK;
   acc.reason=PL_R_NONE;
   if(plan.reason!=PL_R_NONE)
      PlAccAdd(acc,PL_BLOCK,plan.reason);
   //--- fill type only from the symbol mask: a market order needs FOK or IOC
   if(in.kind==PL_KIND_MARKET && (s.filling_mode&(SYMBOL_FILLING_FOK|SYMBOL_FILLING_IOC))==0)
      PlAccAdd(acc,PL_BLOCK,PL_R_NO_FILL_MODE);
   //--- the broker deletes SL and TP at the end of the day: a position would lose its stop overnight
   if(s.gtc_mode==SYMBOL_ORDERS_DAILY)
      PlAccAdd(acc,PL_BLOCK,PL_R_ORDERS_DAILY);

   const bool buy=(plan.side==PL_SIDE_BUY);
   const bool with_sl=!in.no_sl;

   //--- netting (anything but hedging): one position per symbol.
   const bool net=(a.margin_mode!=ACCOUNT_MARGIN_MODE_RETAIL_HEDGING);
   const bool has_pos=(net && s.net_vol>PL_EPS);
   const bool same=(has_pos && s.net_buy==buy);
   const bool pend=(plan.order_type!=ORDER_TYPE_BUY && plan.order_type!=ORDER_TYPE_SELL);
   int ntp=0;
   for(int i=0; i<PL_MAX_TP; i++)
      if(in.tp[i].on && !in.no_tp && plan.tp[i]>0.0)
         ntp++;
   if(net && s.net_orders>0)
      PlAccAdd(acc,PL_BLOCK,PL_R_NETTING_ORDER_OPEN);   // the order would merge into whatever this trade opens or adds to, with an SL nobody controls
   if(has_pos && !same)
      PlAccAdd(acc,PL_BLOCK,PL_R_NETTING_REVERSE);      // would close or reverse the position
   if(same && pend)
      PlAccAdd(acc,PL_BLOCK,PL_R_NETTING_PENDING);      // the SL at the fill is unknown and the position may change first
   if(same && !with_sl)
      PlAccAdd(acc,PL_BLOCK,PL_R_NETTING_NO_SL);        // the risk of the whole position would be undefined
   if(same && ntp>1)
      PlAccAdd(acc,PL_BLOCK,PL_R_NETTING_TPS);          // the panel cannot split a merged position by plan

   //--- base and money target
   double base=(in.base==PL_BASE_EQUITY)?a.equity:a.balance;
   if(in.subtract_open)
      base-=a.open_risk_money+a.pending_risk_money;
   if(base<0.0)
      base=0.0;

   //--- account and symbol data the formulas rest on
   if(a.currency_digits<0 || a.currency_digits>8)
      PlAccAdd(acc,PL_BLOCK,PL_R_NO_SYMBOL_DATA);
   if(PlUnsupportedMode(s.calc_mode))
      PlAccAdd(acc,PL_BLOCK,PL_R_CALC_MODE);
   if(!PlVolumeGridOk(s))
      PlAccAdd(acc,PL_BLOCK,PL_R_LOT_GRID);
   double k=0.0;
   const bool k_ok=PlRateK(s,k);
   const int rel=PlCcyRelation(s);

   //--- loss per lot: (c) OrderCalcProfit is the source, (a) the tick value checks it
   if(with_sl)
     {
      r.lpl_a=PlLossA(s,plan.sl,plan.ticks);
      if(rel==PL_CCY_CROSS && PlForexMode(s.calc_mode))
         r.note=PL_R_CROSS_RATE_AT_SL;
      const bool have_c=(in.calcprofit_ok && in.calcprofit_loss_1lot>0.0);
      if(have_c)
         r.lpl_c=in.calcprofit_loss_1lot;
      r.lpl_price=MathMax(r.lpl_a,r.lpl_c);
      if(!have_c)
         PlAccAdd(acc,PL_BLOCK,PL_R_NO_CALC);
      else if(!PlPathsAgree(r.lpl_a,r.lpl_c,a.currency_digits))
         PlAccAdd(acc,PL_BLOCK,PL_R_PATHS_DISAGREE);
     }

   //--- commission per lot, entry and exit
   switch(in.comm.kind)
     {
      case PL_COMM_LOT_SIDE:
         r.comm_in_1lot=in.comm.rate;
         r.comm_out_1lot=in.comm.rate;
         break;
      case PL_COMM_LOT_ROUND:
         r.comm_in_1lot=in.comm.rate/2.0;
         r.comm_out_1lot=in.comm.rate/2.0;
         break;
      case PL_COMM_PERCENT_SIDE:
         if(!k_ok)
            PlAccAdd(acc,PL_BLOCK,PL_R_NO_CONVERSION);
         else
           {
            r.comm_in_1lot=plan.exec*s.contract*in.comm.rate/100.0*k;
            r.comm_out_1lot=(with_sl?plan.sl:plan.exec)*s.contract*in.comm.rate/100.0*k;
           }
         break;
      default:
         r.note=PL_R_COMM_UNKNOWN;     // moves the risk, so it wins over the cross rate note
         break;
     }
   r.loss_per_lot=r.lpl_price+r.comm_in_1lot+r.comm_out_1lot;
   //--- the broker minimum: every order of the press pays at least min_money for the round, so the commission of a lot over n
   //--- orders is max(lot * (in + out), n * min_money) (equal parts; the real parts differ a little, see PlOrdersFor)
   const double comm_1lot=r.comm_in_1lot+r.comm_out_1lot;
   const double min_all=(in.comm.min_money>PL_EPS)?in.comm.min_money*(double)MathMax(1,in.n_orders):0.0;

   //--- netting add: the whole position sits at the new SL. net_delta is what the guards must add to
   //--- the worst case of the account: the loss at the new SL minus the loss at the old SL (a given-up profit counts, an SL
   //--- moved closer is never credited); with no old SL the volume enters the sum of the risk only now, with its whole loss.
   double net_delta=0.0;
   if(same && with_sl && !pend)
     {
      if(!in.net_calc_ok)
         PlAccAdd(acc,PL_BLOCK,PL_R_NETTING_NO_VALUE);
      else
        {
         r.net_risk=MathMax(0.0,in.net_loss_new+s.net_vol*r.comm_out_1lot);
         net_delta=(s.net_sl>0.0)?MathMax(0.0,in.net_loss_new-in.net_loss_old):r.net_risk;
        }
     }

   //--- lot
   double lot=0.0;
   bool below_min=false;
   const int sdg=PlStepDigits(s.vol_step);
   if(!with_sl)       // no SL: the lot is the typed one, whatever the risk mode says
     {
      lot=in.lot_fixed;
      r.risk_target=0.0;
      if(lot>PL_EPS)
        {
         if(lot<s.vol_min-PL_EPS)
           {
            lot=s.vol_min;
            below_min=true;
           }
         else if(s.vol_step>0.0)
            lot=PlRoundDigits(s.vol_min+MathMax(0.0,MathFloor((lot-s.vol_min)/s.vol_step+1e-8))*s.vol_step,sdg);
        }
     }
   else
     {
      if(in.risk_mode==PL_RISK_MONEY)
         r.risk_target=in.risk_money;
      else
         r.risk_target=PlFloorDigits(base*in.risk_percent/100.0,a.currency_digits);
      const double avail=r.risk_target-r.net_risk;     // netting add: the open volume has used part of the target
      if(r.loss_per_lot>PL_EPS && r.net_risk>0.0 && avail<=PL_EPS)
         PlAccAdd(acc,PL_BLOCK,PL_R_NETTING_NO_ROOM);
      else if(r.loss_per_lot>PL_EPS)
        {
         r.lot_raw=avail/r.loss_per_lot;
         //--- the minimum acts where the linear commission of this lot is below it: then the commission is the minimum, a fixed
         //--- sum, and the lot is what is left of the money after it (the smaller of the two lots, as the loss only grows with the lot)
         if(min_all>0.0 && r.lot_raw*comm_1lot<min_all-PL_EPS)
            r.lot_raw=(r.lpl_price>PL_EPS)?MathMax(0.0,(avail-min_all)/r.lpl_price):0.0;
         if(r.lot_raw<s.vol_min-PL_EPS)
           {
            lot=s.vol_min;
            below_min=true;
           }
         else if(s.vol_step>0.0)
            lot=PlRoundDigits(s.vol_min+MathMax(0.0,MathFloor((r.lot_raw-s.vol_min)/s.vol_step+1e-8))*s.vol_step,sdg);
         else
            lot=r.lot_raw;
        }
      else
         PlAccAdd(acc,PL_BLOCK,PL_R_NO_SYMBOL_DATA);
     }
   if(below_min && !with_sl)
      PlAccAdd(acc,PL_BLOCK,PL_R_LOT_BELOW_MIN);   // no SL: nothing bounds the risk, never raise the typed lot
   if(lot>s.vol_max+PL_EPS)
     {
      if(in.over_max==PL_OVER_TRIM)
        {
         lot=s.vol_max;
         PlAccAdd(acc,PL_WARN,PL_R_LOT_ABOVE_MAX);
        }
      else if(in.over_max==PL_OVER_SPLIT)
        {
         if(a.margin_mode!=ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
            PlAccAdd(acc,PL_BLOCK,PL_R_SPLIT_NETTING);
         else
           {
            const int n=PlSplitLots(lot,s.vol_min,s.vol_max,s.vol_step,r.split_lot);
            if(n<=0)
               PlAccAdd(acc,PL_BLOCK,PL_R_LOT_ABOVE_MAX);     // cannot be cut evenly on the lot step: do not guess
            else if(n>PL_MAX_PARTS)
              {
               r.split_need=n;
               PlAccAdd(acc,PL_BLOCK,PL_R_SPLIT_TOO_MANY);
              }
            else
              {
               r.split_n=n;
               r.split_need=n;
               PlAccAdd(acc,PL_CONFIRM,PL_R_SPLIT_ORDERS);
              }
           }
        }
      else
         PlAccAdd(acc,PL_BLOCK,PL_R_LOT_ABOVE_MAX);
     }
   r.lot=lot;
   if(net && !has_pos && ntp>=2 && lot>PL_EPS && !PlTpPartsFit(lot,s.vol_min,s.vol_step,in,plan))
      PlAccAdd(acc,PL_BLOCK,PL_R_NETTING_TP_PARTS);    // a share would be below the minimum lot and the panel cannot merge parts on netting
   const double vol_side=buy?s.vol_open_buy:s.vol_open_sell;
   if(s.vol_limit>PL_EPS && vol_side+lot>s.vol_limit+PL_EPS)
      PlAccAdd(acc,PL_BLOCK,PL_R_VOLUME_LIMIT);

   //--- commission of the trade: the linear sum, or the minimum of every order when that is more (comm_top: what the minimum adds)
   r.comm_money=lot*comm_1lot;
   double comm_top=0.0;
   if(min_all>0.0 && lot>PL_EPS && r.comm_money<min_all)
     {
      comm_top=min_all-r.comm_money;
      r.comm_money=min_all;
      r.comm_min_on=true;
     }

   //--- risk
   if(with_sl)
     {
      //--- known and accepted on a netting add: reward and rr count the new lot only (shown, understated);
      //--- subtract_open already removes the old-SL risk from the base, so the target is a little smaller (safe);
      //--- the stop-out check measures the old volume from its open, as for every other open position.
      r.risk_money=lot*r.loss_per_lot+r.net_risk+comm_top;
      r.risk_add=lot*r.loss_per_lot+net_delta+comm_top;
      r.risk_percent=(base>PL_EPS)?r.risk_money/base*100.0:0.0;
      if(below_min)
        {
         PlAccAdd(acc,PL_CONFIRM,PL_R_LOT_BELOW_MIN);
        }
      if(base>PL_EPS)
        {
         if(r.risk_percent>in.cap_percent+PL_EPS)
            PlAccAdd(acc,PL_BLOCK,PL_R_RISK_ABOVE_CAP);
         else if(r.risk_percent>in.confirm_above+PL_EPS)
            PlAccAdd(acc,PL_CONFIRM,PL_R_RISK_HIGH);
        }
      else if(lot>PL_EPS)
         PlAccAdd(acc,PL_BLOCK,PL_R_RISK_ABOVE_CAP);   // no base to measure against: the cap cannot be kept
     }
   else
      PlAccAdd(acc,PL_CONFIRM,PL_R_NO_SL);

   //--- reward at each TP for its share, commission of that share subtracted
   for(int i=0; i<PL_MAX_TP; i++)
     {
      if(in.no_tp || !in.tp[i].on || plan.tp[i]<=0.0)
         continue;
      const double part=lot*in.tp[i].share/100.0;
      const double tk=MathAbs(plan.tp[i]-plan.exec)/s.tick_size;
      const double per=(rel==PL_CCY_BASE)?tk*s.tick_size*s.contract/plan.tp[i]:tk*s.tick_value_profit;
      r.reward[i]=part*per-((comm_top>0.0)?r.comm_money*in.tp[i].share/100.0:part*comm_1lot);
      r.reward_total+=r.reward[i];
     }
   if(r.risk_money>PL_EPS)
      r.rr=r.reward_total/r.risk_money;

   //--- spread
   const double spread=s.ask-s.bid;
   if(s.point>0.0)
      r.spread_points=spread/s.point;
   r.spread_money=spread/s.tick_size*s.tick_value_loss*lot;
   if(with_sl && plan.dist>PL_EPS)
     {
      const double share=(in.max_spread_share>0.0)?in.max_spread_share:PL_SPREAD_SHARE_DEF;
      if(spread>plan.dist*share+PL_EPS)
         PlAccAdd(acc,PL_WARN,PL_R_SPREAD_WIDE);
     }

   //--- swaps (the commission money is above, with the risk)
   bool okl=true,oks=true;
   r.swap_long_night=PlSwapNight(s,s.swap_long,lot,k_ok,k,okl);
   r.swap_short_night=PlSwapNight(s,s.swap_short,lot,k_ok,k,oks);
   r.swap_ok=(okl && oks);

   //--- margin and stop-out before the SL
   const double m1=buy?s.margin_buy_1lot:s.margin_sell_1lot;
   r.margin_needed=lot*m1;
   if(m1>PL_EPS)
     {
      if(r.margin_needed>a.margin_free+PL_EPS)
         PlAccAdd(acc,PL_BLOCK,PL_R_MARGIN);
      if(with_sl && a.so_mode==ACCOUNT_STOPOUT_MODE_PERCENT)
        {
         const double lvl=a.so_so+PL_STOPOUT_MARGIN;
         if(a.margin+r.margin_needed>PL_EPS)
           {
            const double at_sl=(a.equity-r.risk_money)/(a.margin+r.margin_needed)*100.0;
            if(at_sl<lvl-PL_EPS)
               PlAccAdd(acc,PL_BLOCK,PL_R_STOPOUT_BEFORE_SL);
           }
        }
      else if(with_sl && a.so_mode==ACCOUNT_STOPOUT_MODE_MONEY)
        {
         //--- stop-out level in money (assumption, no broker here uses it): free margin at the SL
         //--- must stay at or above the level
         const double free_at_sl=a.equity-r.risk_money-a.margin-r.margin_needed;
         if(free_at_sl<a.so_so-PL_EPS)
            PlAccAdd(acc,PL_BLOCK,PL_R_STOPOUT_BEFORE_SL);
        }
     }
   else if(lot>PL_EPS)
      PlAccAdd(acc,PL_BLOCK,PL_R_NO_SYMBOL_DATA);   // the terminal gave no margin: nothing to check against

   //--- session and freshness (the send step acts on it; here only the verdict)
   if(!s.session_open)
      PlAccAdd(acc,PL_BLOCK,PL_R_MARKET_CLOSED);
   else
     {
      //--- a frozen quote on an open session (a holiday the session table does not know: USDBRL+ last ticked 3.7 days
      //--- before its Monday session) blocks a market order and only warns for a pending one
      if(s.tick_time<=0 || s.server_now-s.tick_time>PlStaleSeconds(s))
         PlAccAdd(acc,in.kind==PL_KIND_MARKET?PL_BLOCK:PL_WARN,PL_R_STALE_QUOTE);
     }

   r.verdict=acc.verdict;
   r.reason=acc.reason;
  }

#endif
