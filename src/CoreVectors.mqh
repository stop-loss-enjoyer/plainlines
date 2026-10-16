// Required Notice: Copyright 2026 stop-loss-enjoyer
// Plainlines is source-available under the PolyForm Shield License 1.0.0.
//
// Test vectors of the calculation core.
// Pure data: every expected number below was computed by hand from the formulas (exact
// fractions), independently of src/Core/Prices.mqh and src/Core/Lot.mqh. The derivation of
// every vector is in the comment above its function. Where the spec is ambiguous the literal
// reading is used and the vector carries a QUESTION line (list below).
//
// How a runner (src/PlCoreTests.mq5) uses a vector:
//   PlPlan p; PlResult r;
//   bool ok=PlPrepare(v.in,v.s,p);
//   PlCompute(v.in,v.s,v.a,p,r);
//   then compares every expectation that is not "unchecked":
//   - unchecked: int fields -1, double fields EMPTY_VALUE, chk_prepare_ok false;
//   - exp_prepare_ok against the return of PlPrepare (and p.ok), only when chk_prepare_ok;
//   - exp_plan_reason against p.reason; exp_side, exp_order_type, exp_exec, exp_sl, exp_tp
//     (tp[0]), exp_ticks against the plan (r.plan or p);
//   - lots (exp_lot): |got - exp| < 1e-8;
//   - prices (exp_exec, exp_sl, exp_tp): |got - exp| < v.s.tick_size / 100;
//   - ticks: exact;
//   - money (exp_lpl_*, exp_comm_*, exp_loss_per_lot, exp_risk_money, exp_reward_total,
//     exp_margin_needed, exp_spread_money): |got - exp| <= v.tol_money;
//   - percents and ratios (exp_risk_percent, exp_rr, exp_spread_points):
//     |got - exp| < 1e-4;
//   - exp_verdict, exp_reason, exp_note against r.verdict, r.reason, r.note.
// The core is run with the session open and a fresh tick unless the vector says otherwise.
//
// Open questions on the spec (the vectors follow the literal text):
//   Q1 note vs verdict: the spec sets note = PL_R_COMM_UNKNOWN / PL_R_CROSS_RATE_AT_SL and lets
//      reason decide the verdict; Types.mqh labels both "WARN". Vectors expect PL_OK,
//      PL_R_NONE and the note. A core that turns a note into WARN fails them.
//   Q2 closed session with an old tick: the spec says stale is WARN only in an open session;
//      Types.mqh says BLOCK when closed, and PL_R_STALE_QUOTE precedes PL_R_MARKET_CLOSED in
//      the enum. Vector market_closed_friday_tick expects PL_R_MARKET_CLOSED.
//   Q3 (closed 11.10.2026) SL-rate correction reference: FTMO-Demo USDJPY tick_value_loss
//      0.63175983 = 100/Bid, and OrderCalcProfit agrees on the demo, so Bid is the reference
//      for both sides (the spec updated).
//   Q4 TP by R: the spec says "distance without spread: |exec - SL|", but for a market order
//      |exec - SL| is Ask - SL, the spread-included distance. The formula is used.
//   Q5 LOT_ABOVE_MAX without trim: the spec does not say whether r.lot is the stepped lot or
//      vol_max; vectors expect the stepped lot. Types.mqh says risk_target is "after the
//      base and cap", the spec says BLOCK above the cap without clamping: risk_target unchecked.
//   Q6 cross note scope: the spec defines the cross inside the Forex paragraph; for non-Forex
//      symbols with account currency neither base nor profit (XAUUSD on EUR, GER40 on USD)
//      exp_note is unchecked.
//   Q7 Stop-Limit with the trigger on the wrong side of the market: the spec gives
//      PL_R_LIMIT_WRONG_SIDE (ENTRY_WRONG_SIDE might fit better); vectors follow the spec.
//   Q8 the minimum SL distance for pending orders literally includes 2 spreads; partial
//      TP lots lot*share/100 are not rounded to vol_step. Both used literally.
//   Q9 prepare ok after SL_TOO_CLOSE, ENTRY/LIMIT_WRONG_SIDE, KIND_NOT_ALLOWED,
//      TP_WRONG_SIDE is not defined ("ok=false only when nothing more can be computed"):
//      there only plan reason, verdict and reason are checked.
//   Q10 the ATR stop is normalized like any SL (Buy up, Sell down) although the spec does not
//      say it explicitly.
//   Path (c) is mandatory with an SL: vectors give calcprofit_loss_1lot.
//   Q13 no_sl with no TP: the side is unknown, so nothing can be sent, but the spec gives
//      PL_R_NO_SL the verdict CONFIRM; there the verdict is unchecked.
#property strict

#ifndef PL_CORE_VECTORS_MQH
#define PL_CORE_VECTORS_MQH

#include "Core/Types.mqh"

struct PlVector
  {
   string            name;
   string            what;
   PlInputs          in;
   PlSymbol          s;
   PlAccount         a;
   //--- expected; int -1 and double EMPTY_VALUE mean "do not check"
   bool              chk_prepare_ok;
   bool              exp_prepare_ok;
   int               exp_plan_reason;   // PlReason in PlPlan
   int               exp_side;          // PlSide
   int               exp_order_type;    // ENUM_ORDER_TYPE
   double            exp_exec;
   double            exp_sl;            // normalized SL (ATR stop included)
   double            exp_tp;            // tp[0]
   long              exp_ticks;
   double            exp_lpl_a;
   double            exp_lpl_c;         // OrderCalcProfit path
   double            exp_lpl_price;     // worst path
   double            exp_comm_in;
   double            exp_comm_out;
   double            exp_loss_per_lot;
   double            exp_lot;
   double            exp_risk_money;
   double            exp_net_risk;      // netting add: loss of the open volume at the new SL
   double            exp_risk_add;      // what the trade adds to the worst case of the account
   double            exp_risk_percent;
   double            exp_reward_total;
   double            exp_rr;
   double            exp_margin_needed;
   double            exp_comm_money;    // commission of the trade, topped up to the broker minimum of every order
   int               exp_comm_min_on;   // 1 / 0, -1 unchecked
   double            exp_spread_points;
   double            exp_spread_money;
   double            exp_swap_long;     // swap per night for the lot, account currency
   double            exp_swap_short;
   int               exp_swap_ok;       // 1 / 0, -1 unchecked
   int               exp_verdict;       // PlVerdict
   int               exp_reason;        // PlReason in PlResult
   int               exp_note;          // PlReason in PlResult.note
   int               exp_split_n;       // orders of Split above the broker max (0: not split), -1 unchecked
   int               exp_split_need;    // orders Split would need, -1 unchecked
   double            exp_split[PL_MAX_PARTS]; // lot of each order, EMPTY_VALUE unchecked
   double            tol_money;
  };

//--- everything unchecked
void PlVecUnchecked(PlVector &v)
  {
   v.name="";
   v.what="";
   v.chk_prepare_ok=false;
   v.exp_prepare_ok=false;
   v.exp_plan_reason=-1;
   v.exp_side=-1;
   v.exp_order_type=-1;
   v.exp_exec=EMPTY_VALUE;
   v.exp_sl=EMPTY_VALUE;
   v.exp_tp=EMPTY_VALUE;
   v.exp_ticks=-1;
   v.exp_lpl_a=EMPTY_VALUE;
   v.exp_lpl_c=EMPTY_VALUE;
   v.exp_lpl_price=EMPTY_VALUE;
   v.exp_comm_in=EMPTY_VALUE;
   v.exp_comm_out=EMPTY_VALUE;
   v.exp_loss_per_lot=EMPTY_VALUE;
   v.exp_lot=EMPTY_VALUE;
   v.exp_risk_money=EMPTY_VALUE;
   v.exp_net_risk=EMPTY_VALUE;
   v.exp_risk_add=EMPTY_VALUE;
   v.exp_risk_percent=EMPTY_VALUE;
   v.exp_reward_total=EMPTY_VALUE;
   v.exp_rr=EMPTY_VALUE;
   v.exp_margin_needed=EMPTY_VALUE;
   v.exp_comm_money=EMPTY_VALUE;
   v.exp_comm_min_on=-1;
   v.exp_spread_points=EMPTY_VALUE;
   v.exp_spread_money=EMPTY_VALUE;
   v.exp_swap_long=EMPTY_VALUE;
   v.exp_swap_short=EMPTY_VALUE;
   v.exp_swap_ok=-1;
   v.exp_verdict=-1;
   v.exp_reason=-1;
   v.exp_note=-1;
   v.exp_split_n=-1;
   v.exp_split_need=-1;
   for(int i=0; i<PL_MAX_PARTS; i++)
      v.exp_split[i]=EMPTY_VALUE;
   v.tol_money=0.001;
  }

//--- demo account, stop-out in percent 100/50, hedging, trading allowed, no open risk
void PlVecAccount(PlAccount &a,const string currency,const int digits,const double balance,
                  const double equity,const double margin,const double margin_free)
  {
   a.currency=currency;
   a.currency_digits=digits;
   a.balance=balance;
   a.equity=equity;
   a.margin=margin;
   a.margin_free=margin_free;
   a.so_mode=ACCOUNT_STOPOUT_MODE_PERCENT;
   a.so_call=100.0;
   a.so_so=50.0;
   a.leverage=100;
   a.trade_mode=ACCOUNT_TRADE_MODE_DEMO;
   a.margin_mode=ACCOUNT_MARGIN_MODE_RETAIL_HEDGING;
   a.trade_ok=true;
   a.connected=true;
   a.open_risk_money=0.0;
   a.pending_risk_money=0.0;
  }

//--- menu defaults: market, 1% of balance, cap 5, confirm 2, no TP, default spread share
void PlVecInputs(PlInputs &in)
  {
   in.kind=PL_KIND_MARKET;
   in.entry=0.0;
   in.limit=0.0;
   in.sl=0.0;
   in.no_sl=false;
   for(int k=0; k<PL_MAX_TP; k++)
     {
      in.tp[k].on=false;
      in.tp[k].mode=PL_TP_R;
      in.tp[k].r=0.0;
      in.tp[k].price=0.0;
      in.tp[k].share=0.0;
     }
   in.no_tp=true;
   in.risk_mode=PL_RISK_PERCENT;
   in.risk_percent=1.0;
   in.risk_money=0.0;
   in.lot_fixed=0.0;
   in.base=PL_BASE_BALANCE;
   in.subtract_open=false;
   in.cap_percent=5.0;
   in.confirm_above=2.0;
   in.over_max=PL_OVER_BLOCK;
   in.max_spread_share=0.0;
   in.comm.kind=PL_COMM_LOT_SIDE;
   in.comm.rate=0.0;
   in.comm.source=PL_COMMSRC_USER;
   in.comm.min_money=0.0;
   in.n_orders=0;
   in.atr_on=false;
   in.atr=0.0;
   in.atr_mult=0.0;
   in.calcprofit_ok=false;
   in.calcprofit_loss_1lot=0.0;
   in.net_calc_ok=false;
   in.net_loss_new=0.0;
   in.net_loss_old=0.0;
  }

//--- symbols. EURUSD, USDJPY, XAUUSD, BTCUSD: real FTMO-Demo values
//--- (a probe of the FTMO demo, build 6254, quotes of Friday 09.10.2026);
//--- margin_sell_1lot derived from the buy value at Bid. USDCAD, GBPJPY, GER40: synthetic
//--- (not in the probe), GER40 shaped like a DAX row (point 0.1, tick 0.5, EUR).
void PlVecSymEURUSD(PlSymbol &s)
  {
   s.name="EURUSD";
   s.base="EUR";
   s.profit="USD";
   s.margin="EUR";
   s.calc_mode=SYMBOL_CALC_MODE_FOREX;
   s.digits=5;
   s.point=0.00001;
   s.tick_size=0.00001;
   s.tick_value_loss=1.0;
   s.tick_value_profit=1.0;
   s.contract=100000.0;
   s.vol_min=0.01;
   s.vol_max=50.0;
   s.vol_step=0.01;
   s.vol_limit=0.0;
   s.vol_open_buy=0.0; s.vol_open_sell=0.0;
   s.stops_level=0;
   s.freeze_level=0;
   s.order_mode=127;
   s.filling_mode=3;
   s.exec_mode=SYMBOL_TRADE_EXECUTION_MARKET;
   s.expiration_mode=15;
   s.gtc_mode=SYMBOL_ORDERS_GTC;
   s.bid=1.12018;
   s.ask=1.12024;
   s.session_open=true;
   s.swap_mode=SYMBOL_SWAP_MODE_POINTS;
   s.swap_long=-9.41;
   s.swap_short=0.1;
   s.swap_3day=WEDNESDAY;
   s.margin_buy_1lot=1120.24;
   s.margin_sell_1lot=1120.18;
   s.tick_time=D'2026.10.09 12:00:00';
   s.server_now=D'2026.10.09 12:00:00';
  }

void PlVecSymUSDJPY(PlSymbol &s)
  {
   s.name="USDJPY";
   s.base="USD";
   s.profit="JPY";
   s.margin="USD";
   s.calc_mode=SYMBOL_CALC_MODE_FOREX;
   s.digits=3;
   s.point=0.001;
   s.tick_size=0.001;
   s.tick_value_loss=0.63175983;
   s.tick_value_profit=0.63166805;
   s.contract=100000.0;
   s.vol_min=0.01;
   s.vol_max=50.0;
   s.vol_step=0.01;
   s.vol_limit=0.0;
   s.vol_open_buy=0.0; s.vol_open_sell=0.0;
   s.stops_level=0;
   s.freeze_level=0;
   s.order_mode=127;
   s.filling_mode=3;
   s.exec_mode=SYMBOL_TRADE_EXECUTION_MARKET;
   s.expiration_mode=15;
   s.gtc_mode=SYMBOL_ORDERS_GTC;
   s.bid=158.288;
   s.ask=158.311;
   s.session_open=true;
   s.swap_mode=SYMBOL_SWAP_MODE_POINTS;
   s.swap_long=2.6;
   s.swap_short=-17.58;
   s.swap_3day=WEDNESDAY;
   s.margin_buy_1lot=1000.0;
   s.margin_sell_1lot=1000.0;
   s.tick_time=D'2026.10.09 12:00:00';
   s.server_now=D'2026.10.09 12:00:00';
  }

void PlVecSymXAUUSD(PlSymbol &s)
  {
   s.name="XAUUSD";
   s.base="USD";
   s.profit="USD";
   s.margin="USD";
   s.calc_mode=SYMBOL_CALC_MODE_CFDLEVERAGE;
   s.digits=2;
   s.point=0.01;
   s.tick_size=0.01;
   s.tick_value_loss=1.0;
   s.tick_value_profit=1.0;
   s.contract=100.0;
   s.vol_min=0.01;
   s.vol_max=100.0;
   s.vol_step=0.01;
   s.vol_limit=0.0;
   s.vol_open_buy=0.0; s.vol_open_sell=0.0;
   s.stops_level=0;
   s.freeze_level=0;
   s.order_mode=127;
   s.filling_mode=3;
   s.exec_mode=SYMBOL_TRADE_EXECUTION_MARKET;
   s.expiration_mode=15;
   s.gtc_mode=SYMBOL_ORDERS_GTC;
   s.bid=4195.09;
   s.ask=4195.52;
   s.session_open=true;
   s.swap_mode=SYMBOL_SWAP_MODE_POINTS;
   s.swap_long=-69.25;
   s.swap_short=-4.2;
   s.swap_3day=WEDNESDAY;
   s.margin_buy_1lot=8391.04;
   s.margin_sell_1lot=8390.18;
   s.tick_time=D'2026.10.09 12:00:00';
   s.server_now=D'2026.10.09 12:00:00';
  }

void PlVecSymBTCUSD(PlSymbol &s)
  {
   s.name="BTCUSD";
   s.base="USD";
   s.profit="USD";
   s.margin="USD";
   s.calc_mode=SYMBOL_CALC_MODE_CFDLEVERAGE;
   s.digits=2;
   s.point=0.01;
   s.tick_size=0.01;
   s.tick_value_loss=0.01;
   s.tick_value_profit=0.01;
   s.contract=1.0;
   s.vol_min=0.01;
   s.vol_max=5.0;
   s.vol_step=0.01;
   s.vol_limit=0.0;
   s.vol_open_buy=0.0; s.vol_open_sell=0.0;
   s.stops_level=0;
   s.freeze_level=0;
   s.order_mode=127;
   s.filling_mode=3;
   s.exec_mode=SYMBOL_TRADE_EXECUTION_MARKET;
   s.expiration_mode=15;
   s.gtc_mode=SYMBOL_ORDERS_GTC;
   s.bid=83796.56;
   s.ask=83797.56;
   s.session_open=true;
   s.swap_mode=SYMBOL_SWAP_MODE_INTEREST_CURRENT;
   s.swap_long=-30.0;
   s.swap_short=-30.0;
   s.swap_3day=FRIDAY;
   s.margin_buy_1lot=25139.27;
   s.margin_sell_1lot=25138.97;
   s.tick_time=D'2026.10.09 12:00:00';
   s.server_now=D'2026.10.09 12:00:00';
  }

void PlVecSymUSDCAD(PlSymbol &s)
  {
   s.name="USDCAD";
   s.base="USD";
   s.profit="CAD";
   s.margin="USD";
   s.calc_mode=SYMBOL_CALC_MODE_FOREX;
   s.digits=5;
   s.point=0.00001;
   s.tick_size=0.00001;
   s.tick_value_loss=1.0/1.37;
   s.tick_value_profit=1.0/1.37;
   s.contract=100000.0;
   s.vol_min=0.01;
   s.vol_max=50.0;
   s.vol_step=0.01;
   s.vol_limit=0.0;
   s.vol_open_buy=0.0; s.vol_open_sell=0.0;
   s.stops_level=0;
   s.freeze_level=0;
   s.order_mode=127;
   s.filling_mode=3;
   s.exec_mode=SYMBOL_TRADE_EXECUTION_MARKET;
   s.expiration_mode=15;
   s.gtc_mode=SYMBOL_ORDERS_GTC;
   s.bid=1.3699;
   s.ask=1.37;
   s.session_open=true;
   s.swap_mode=SYMBOL_SWAP_MODE_POINTS;
   s.swap_long=0.0;
   s.swap_short=0.0;
   s.swap_3day=WEDNESDAY;
   s.margin_buy_1lot=1000.0;
   s.margin_sell_1lot=1000.0;
   s.tick_time=D'2026.10.09 12:00:00';
   s.server_now=D'2026.10.09 12:00:00';
  }

void PlVecSymGBPJPY(PlSymbol &s)
  {
   s.name="GBPJPY";
   s.base="GBP";
   s.profit="JPY";
   s.margin="GBP";
   s.calc_mode=SYMBOL_CALC_MODE_FOREX;
   s.digits=3;
   s.point=0.001;
   s.tick_size=0.001;
   s.tick_value_loss=100.0/150.0;
   s.tick_value_profit=100.0/150.0;
   s.contract=100000.0;
   s.vol_min=0.01;
   s.vol_max=50.0;
   s.vol_step=0.01;
   s.vol_limit=0.0;
   s.vol_open_buy=0.0; s.vol_open_sell=0.0;
   s.stops_level=0;
   s.freeze_level=0;
   s.order_mode=127;
   s.filling_mode=3;
   s.exec_mode=SYMBOL_TRADE_EXECUTION_MARKET;
   s.expiration_mode=15;
   s.gtc_mode=SYMBOL_ORDERS_GTC;
   s.bid=200.0;
   s.ask=200.02;
   s.session_open=true;
   s.swap_mode=SYMBOL_SWAP_MODE_POINTS;
   s.swap_long=0.0;
   s.swap_short=0.0;
   s.swap_3day=WEDNESDAY;
   s.margin_buy_1lot=1330.0;
   s.margin_sell_1lot=1330.0;
   s.tick_time=D'2026.10.09 12:00:00';
   s.server_now=D'2026.10.09 12:00:00';
  }

void PlVecSymGER40(PlSymbol &s)
  {
   s.name="GER40";
   s.base="EUR";
   s.profit="EUR";
   s.margin="EUR";
   s.calc_mode=SYMBOL_CALC_MODE_CFDINDEX;
   s.digits=1;
   s.point=0.1;
   s.tick_size=0.5;
   s.tick_value_loss=0.55;
   s.tick_value_profit=0.55;
   s.contract=1.0;
   s.vol_min=0.1;
   s.vol_max=100.0;
   s.vol_step=0.1;
   s.vol_limit=0.0;
   s.vol_open_buy=0.0; s.vol_open_sell=0.0;
   s.stops_level=0;
   s.freeze_level=0;
   s.order_mode=127;
   s.filling_mode=3;
   s.exec_mode=SYMBOL_TRADE_EXECUTION_MARKET;
   s.expiration_mode=15;
   s.gtc_mode=SYMBOL_ORDERS_GTC;
   s.bid=19000.0;
   s.ask=19001.0;
   s.session_open=true;
   s.swap_mode=SYMBOL_SWAP_MODE_POINTS;
   s.swap_long=0.0;
   s.swap_short=0.0;
   s.swap_3day=FRIDAY;
   s.margin_buy_1lot=1045.06;
   s.margin_sell_1lot=1045.0;
   s.tick_time=D'2026.10.09 12:00:00';
   s.server_now=D'2026.10.09 12:00:00';
  }

//+------------------------------------------------------------------+
//| 01 eurusd_usd_buy_round7
//| 6.4 row 1 and section 5 example: EURUSD FTMO data, USD account, risk 1% of 10000, SL 20 pips below Ask, commission $7 per round, TP 2R
//|   Compare price = mid (Bid+Ask)/2 = (1.12018+1.12024)/2 = 1.12021.
//|   SL line 1.11824 < compare price: BUY.
//|   Order type ORDER_TYPE_BUY, exec = 1.12024.
//|   dist = Ask - SL = 0.002.
//|   ticks = round(0.002 / 0.00001) = 200.
//|   TP1 = exec + 2 * |exec - SL| 0.002 = 1.12424.
//|   (a) ticks * tvl = 200 * 1 = 200.
//|   (c) OrderCalcProfit = 200.
//|   worst = 200 (the larger path), the paths agree.
//|   commission per round 7: in 3.5, out 3.5.
//|   loss_per_lot = 200 + 3.5 + 3.5 = 207.
//|   base = balance 10000.
//|   target = floor(10000 * 1 / 100, 2) = floor(100) = 100.
//|   lot_raw = 100 / 207 = 0.48309179; lot = 0.01 + floor((lot_raw - 0.01)/0.01 + 1e-8)*0.01 = 0.48.
//|   risk = 0.48 * 207 = 99.36, 0.9936% of base 10000.
//|   reward TP1 = 0.48*100/100 * (400 ticks * 1) - 0.48*100/100 * (3.5 + 3.5) = 188.64.
//|   reward_total 188.64, rr = 188.64 / 99.36 = 1.89855072.
//|   margin_needed = 0.48 * 1120.24 = 537.7152, margin_free 10000.
//|   level at SL = (10000 - 99.36) / (0 + 537.7152) * 100 = 1841.242353%, limit so_so+10 = 60.
//|   spread = 6 points, money = 0.00006/0.00001 * 1 * 0.48 = 2.88.
//|   Verdict PL_OK, reason PL_R_NONE.
//+------------------------------------------------------------------+
void PlVec01(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="eurusd_usd_buy_round7";
   v.what="6.4 row 1 and section 5 example: EURUSD FTMO data, USD account, risk 1% of 10000, SL 20 pips below Ask, commission $7 per round, TP 2R";
   PlVecSymEURUSD(v.s);
   PlVecAccount(v.a,"USD",2,10000.0,10000.0,0.0,10000.0);
   PlVecInputs(v.in);
   v.in.sl=1.11824;
   v.in.calcprofit_ok=true;
   v.in.calcprofit_loss_1lot=200.0;
   v.in.comm.kind=PL_COMM_LOT_ROUND; v.in.comm.rate=7.0; v.in.comm.source=PL_COMMSRC_USER;
   v.in.no_tp=false;
   v.in.tp[0].on=true; v.in.tp[0].mode=PL_TP_R; v.in.tp[0].r=2.0; v.in.tp[0].price=0.0; v.in.tp[0].share=100.0;
   //--- expected
   v.chk_prepare_ok=true; v.exp_prepare_ok=true;
   v.exp_plan_reason=PL_R_NONE;
   v.exp_side=PL_SIDE_BUY;
   v.exp_order_type=ORDER_TYPE_BUY;
   v.exp_exec=1.12024;
   v.exp_sl=1.11824;
   v.exp_tp=1.12424;
   v.exp_ticks=200;
   v.exp_lpl_a=200.0;
   v.exp_lpl_price=200.0;
   v.exp_comm_in=3.5;
   v.exp_comm_out=3.5;
   v.exp_loss_per_lot=207.0;
   v.exp_lot=0.48;
   v.exp_risk_money=99.36;
   v.exp_risk_percent=0.9936;
   v.exp_reward_total=188.64;
   v.exp_rr=1.89855072;
   v.exp_margin_needed=537.7152;
   v.exp_spread_points=6.0;
   v.exp_spread_money=2.88;
   v.exp_verdict=PL_OK;
   v.exp_reason=PL_R_NONE;
   v.exp_note=PL_R_NONE;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 02 eurusd_usd_sell_round7
//| Sell Market mirror of the first vector: SL 20 pips above Bid
//|   Compare price = mid (Bid+Ask)/2 = (1.12018+1.12024)/2 = 1.12021.
//|   SL line 1.12218 > compare price: SELL.
//|   Order type ORDER_TYPE_SELL, exec = 1.12018.
//|   dist = SL - Bid = 0.002.
//|   ticks = round(0.002 / 0.00001) = 200.
//|   TP1 = exec - 2 * |exec - SL| 0.002 = 1.11618.
//|   (a) ticks * tvl = 200 * 1 = 200.
//|   commission per round 7: in 3.5, out 3.5.
//|   loss_per_lot = 200 + 3.5 + 3.5 = 207.
//|   base = balance 10000.
//|   target = floor(10000 * 1 / 100, 2) = floor(100) = 100.
//|   lot_raw = 100 / 207 = 0.48309179; lot = 0.01 + floor((lot_raw - 0.01)/0.01 + 1e-8)*0.01 = 0.48.
//|   risk = 0.48 * 207 = 99.36, 0.9936% of base 10000.
//|   reward TP1 = 0.48*100/100 * (400 ticks * 1) - 0.48*100/100 * (3.5 + 3.5) = 188.64.
//|   reward_total 188.64, rr = 188.64 / 99.36 = 1.89855072.
//|   margin_needed = 0.48 * 1120.18 = 537.6864, margin_free 10000.
//|   level at SL = (10000 - 99.36) / (0 + 537.6864) * 100 = 1841.340975%, limit so_so+10 = 60.
//|   spread = 6 points, money = 0.00006/0.00001 * 1 * 0.48 = 2.88.
//|   Verdict PL_OK, reason PL_R_NONE.
//+------------------------------------------------------------------+
void PlVec02(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="eurusd_usd_sell_round7";
   v.what="Sell Market mirror of the first vector: SL 20 pips above Bid";
   PlVecSymEURUSD(v.s);
   PlVecAccount(v.a,"USD",2,10000.0,10000.0,0.0,10000.0);
   PlVecInputs(v.in);
   v.in.sl=1.12218;
   v.in.comm.kind=PL_COMM_LOT_ROUND; v.in.comm.rate=7.0; v.in.comm.source=PL_COMMSRC_USER;
   v.in.no_tp=false;
   v.in.tp[0].on=true; v.in.tp[0].mode=PL_TP_R; v.in.tp[0].r=2.0; v.in.tp[0].price=0.0; v.in.tp[0].share=100.0;
   v.in.calcprofit_ok=true; v.in.calcprofit_loss_1lot=200.0;
   //--- expected
   v.chk_prepare_ok=true; v.exp_prepare_ok=true;
   v.exp_plan_reason=PL_R_NONE;
   v.exp_side=PL_SIDE_SELL;
   v.exp_order_type=ORDER_TYPE_SELL;
   v.exp_exec=1.12018;
   v.exp_sl=1.12218;
   v.exp_tp=1.11618;
   v.exp_ticks=200;
   v.exp_lpl_a=200.0;
   v.exp_lpl_price=200.0;
   v.exp_comm_in=3.5;
   v.exp_comm_out=3.5;
   v.exp_loss_per_lot=207.0;
   v.exp_lot=0.48;
   v.exp_risk_money=99.36;
   v.exp_risk_percent=0.9936;
   v.exp_reward_total=188.64;
   v.exp_rr=1.89855072;
   v.exp_margin_needed=537.6864;
   v.exp_spread_points=6.0;
   v.exp_spread_money=2.88;
   v.exp_verdict=PL_OK;
   v.exp_reason=PL_R_NONE;
   v.exp_note=PL_R_NONE;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 03 usdjpy_usd_buy_slrate
//| USDJPY FTMO data on a USD account, Buy Market, SL 30 pips below Bid, $2.50 per side, risk $100.45: path (a) corrected by Bid/SL gives 0.47, uncorrected would give 0.48
//|   Compare price = mid (Bid+Ask)/2 = (158.288+158.311)/2 = 158.2995.
//|   SL line 157.988 < compare price: BUY.
//|   Order type ORDER_TYPE_BUY, exec = 158.311.
//|   dist = Ask - SL = 0.323.
//|   ticks = round(0.323 / 0.001) = 323.
//|   (a) account = base by data (k = tvl/(tick*contract), 1/k within 1e-4 of Bid): ticks * tick * contract / SL = 323 * 0.001 * 100000 / 157.988 = 204.44590728.
//|   (c) OrderCalcProfit = 204.44590728.
//|   commission per side 2.5: in 2.5, out 2.5.
//|   loss_per_lot = 204.44590728 + 2.5 + 2.5 = 209.44590722.
//|   base = balance 10000.
//|   target = risk_money 100.45.
//|   lot_raw = 100.45 / 209.44590722 = 0.47959877; lot = 0.01 + floor((lot_raw - 0.01)/0.01 + 1e-8)*0.01 = 0.47.
//|   risk = 0.47 * 209.44590722 = 98.439576, 0.98439576% of base 10000.
//|   margin_needed = 0.47 * 1000 = 470, margin_free 10000.
//|   level at SL = (10000 - 98.439576) / (0 + 470) * 100 = 2106.712013%, limit so_so+10 = 60.
//|   spread = 23 points, money = 0.023/0.001 * 0.63175983 * 0.47 = 6.82932376.
//|   Verdict PL_OK, reason PL_R_NONE.
//| Q3 closed: FTMO tick_value_loss 0.63175983 equals 100/Bid (158.288), so Bid is the reference for both sides (demo run 11.10.2026: OrderCalcProfit agrees).
//+------------------------------------------------------------------+
void PlVec03(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="usdjpy_usd_buy_slrate";
   v.what="USDJPY FTMO data on a USD account, Buy Market, SL 30 pips below Bid, $2.50 per side, risk $100.45: path (a) corrected by Bid/SL gives 0.47, uncorrected would give 0.48";
   PlVecSymUSDJPY(v.s);
   PlVecAccount(v.a,"USD",2,10000.0,10000.0,0.0,10000.0);
   PlVecInputs(v.in);
   v.in.sl=157.988;
   v.in.risk_mode=PL_RISK_MONEY;
   v.in.risk_money=100.45;
   v.in.comm.kind=PL_COMM_LOT_SIDE; v.in.comm.rate=2.5; v.in.comm.source=PL_COMMSRC_USER;
   v.in.calcprofit_ok=true; v.in.calcprofit_loss_1lot=204.44590728;
   //--- expected
   v.chk_prepare_ok=true; v.exp_prepare_ok=true;
   v.exp_plan_reason=PL_R_NONE;
   v.exp_side=PL_SIDE_BUY;
   v.exp_order_type=ORDER_TYPE_BUY;
   v.exp_exec=158.311;
   v.exp_sl=157.988;
   v.exp_ticks=323;
   v.exp_lpl_a=204.44590728;
   v.exp_lpl_price=204.44590728;
   v.exp_comm_in=2.5;
   v.exp_comm_out=2.5;
   v.exp_loss_per_lot=209.44590728;
   v.exp_lot=0.47;
   v.exp_risk_money=98.43957640;
   v.exp_risk_percent=0.98439576;
   v.exp_margin_needed=470.0;
   v.exp_spread_points=23.0;
   v.exp_spread_money=6.82932376;
   v.exp_verdict=PL_OK;
   v.exp_reason=PL_R_NONE;
   v.exp_note=PL_R_NONE;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 04 usdjpy_usd_sell_slrate
//| USDJPY FTMO data, Sell Market, SL 30 pips above Ask, $2.50 per side, risk $100.25: path (a) corrected by Bid/SL gives 0.48, uncorrected would give 0.47
//|   Compare price = mid (Bid+Ask)/2 = (158.288+158.311)/2 = 158.2995.
//|   SL line 158.611 > compare price: SELL.
//|   Order type ORDER_TYPE_SELL, exec = 158.288.
//|   dist = SL - Bid = 0.323.
//|   ticks = round(0.323 / 0.001) = 323.
//|   (a) account = base by data: ticks * tick * contract / SL = 323 * 0.001 * 100000 / 158.611 = 203.64287471.
//|   (c) OrderCalcProfit = 203.64287471.
//|   commission per side 2.5: in 2.5, out 2.5.
//|   loss_per_lot = 203.64287471 + 2.5 + 2.5 = 208.64287465.
//|   base = balance 10000.
//|   target = risk_money 100.25.
//|   lot_raw = 100.25 / 208.64287465 = 0.48048609; lot = 0.01 + floor((lot_raw - 0.01)/0.01 + 1e-8)*0.01 = 0.48.
//|   risk = 0.48 * 208.64287465 = 100.14858, 1.0014858% of base 10000.
//|   margin_needed = 0.48 * 1000 = 480, margin_free 10000.
//|   level at SL = (10000 - 100.14858) / (0 + 480) * 100 = 2062.469046%, limit so_so+10 = 60.
//|   spread = 23 points, money = 0.023/0.001 * 0.63175983 * 0.48 = 6.97462852.
//|   Verdict PL_OK, reason PL_R_NONE.
//+------------------------------------------------------------------+
void PlVec04(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="usdjpy_usd_sell_slrate";
   v.what="USDJPY FTMO data, Sell Market, SL 30 pips above Ask, $2.50 per side, risk $100.25: path (a) corrected by Bid/SL gives 0.48, uncorrected would give 0.47";
   PlVecSymUSDJPY(v.s);
   PlVecAccount(v.a,"USD",2,10000.0,10000.0,0.0,10000.0);
   PlVecInputs(v.in);
   v.in.sl=158.611;
   v.in.risk_mode=PL_RISK_MONEY;
   v.in.risk_money=100.25;
   v.in.comm.kind=PL_COMM_LOT_SIDE; v.in.comm.rate=2.5; v.in.comm.source=PL_COMMSRC_USER;
   v.in.calcprofit_ok=true; v.in.calcprofit_loss_1lot=203.64287471;
   //--- expected
   v.chk_prepare_ok=true; v.exp_prepare_ok=true;
   v.exp_plan_reason=PL_R_NONE;
   v.exp_side=PL_SIDE_SELL;
   v.exp_order_type=ORDER_TYPE_SELL;
   v.exp_exec=158.288;
   v.exp_sl=158.611;
   v.exp_ticks=323;
   v.exp_lpl_a=203.64287471;
   v.exp_lpl_price=203.64287471;
   v.exp_comm_in=2.5;
   v.exp_comm_out=2.5;
   v.exp_loss_per_lot=208.64287471;
   v.exp_lot=0.48;
   v.exp_risk_money=100.14857983;
   v.exp_risk_percent=1.0014858;
   v.exp_margin_needed=480.0;
   v.exp_spread_points=23.0;
   v.exp_spread_money=6.97462852;
   v.exp_verdict=PL_OK;
   v.exp_reason=PL_R_NONE;
   v.exp_note=PL_R_NONE;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 05 usdjpy_plan_example
//| 6.4 row 2 numbers: Bid = Ask = 150.000, SL 149.700, tick value 100/150; uncorrected lot would sit on the 0.50 boundary, corrected lot 0.49
//|   Compare price = mid (Bid+Ask)/2 = (150+150)/2 = 150.
//|   SL line 149.7 < compare price: BUY.
//|   Order type ORDER_TYPE_BUY, exec = 150.
//|   dist = Ask - SL = 0.3.
//|   ticks = round(0.3 / 0.001) = 300.
//|   (a) Forex, account = base: ticks * tvl * Bid/SL = 300 * 0.6666666667 * 150/149.7 = 200.4008016.
//|   commission per side 0: in 0, out 0.
//|   loss_per_lot = 200.4008016 + 0 + 0 = 200.4008016.
//|   base = balance 10000.
//|   target = floor(10000 * 1 / 100, 2) = floor(100) = 100.
//|   lot_raw = 100 / 200.4008016 = 0.499; lot = 0.01 + floor((lot_raw - 0.01)/0.01 + 1e-8)*0.01 = 0.49.
//|   risk = 0.49 * 200.4008016 = 98.196393, 0.98196393% of base 10000.
//|   margin_needed = 0.49 * 1000 = 490, margin_free 10000.
//|   level at SL = (10000 - 98.196393) / (0 + 490) * 100 = 2020.776246%, limit so_so+10 = 60.
//|   spread = 0 points, money = 0/0.001 * 0.6666666667 * 0.49 = 0.
//|   Verdict PL_OK, reason PL_R_NONE.
//+------------------------------------------------------------------+
void PlVec05(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="usdjpy_plan_example";
   v.what="6.4 row 2 numbers: Bid = Ask = 150.000, SL 149.700, tick value 100/150; uncorrected lot would sit on the 0.50 boundary, corrected lot 0.49";
   PlVecSymUSDJPY(v.s);
   v.s.bid=150.0;
   v.s.ask=150.0;
   v.s.tick_value_loss=100.0/150.0;
   v.s.tick_value_profit=100.0/150.0;
   PlVecAccount(v.a,"USD",2,10000.0,10000.0,0.0,10000.0);
   PlVecInputs(v.in);
   v.in.sl=149.7;
   v.in.comm.kind=PL_COMM_LOT_SIDE; v.in.comm.rate=0.0; v.in.comm.source=PL_COMMSRC_USER;
   v.in.calcprofit_ok=true; v.in.calcprofit_loss_1lot=200.4008016;
   //--- expected
   v.chk_prepare_ok=true; v.exp_prepare_ok=true;
   v.exp_plan_reason=PL_R_NONE;
   v.exp_side=PL_SIDE_BUY;
   v.exp_order_type=ORDER_TYPE_BUY;
   v.exp_exec=150.0;
   v.exp_sl=149.7;
   v.exp_ticks=300;
   v.exp_lpl_a=200.4008016;
   v.exp_lpl_price=200.4008016;
   v.exp_comm_in=0.0;
   v.exp_comm_out=0.0;
   v.exp_loss_per_lot=200.4008016;
   v.exp_lot=0.49;
   v.exp_risk_money=98.19639279;
   v.exp_risk_percent=0.98196393;
   v.exp_margin_needed=490.0;
   v.exp_spread_points=0.0;
   v.exp_spread_money=0.0;
   v.exp_verdict=PL_OK;
   v.exp_reason=PL_R_NONE;
   v.exp_note=PL_R_NONE;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 06 xauusd_usd_buy_boundary
//| 6.4 row 3: XAUUSD FTMO data, risk 1% of 10000, SL $5.00 below Ask, explicit zero commission: lot exactly 0.20 (deliberate step boundary, needs the 1e-8)
//|   Compare price = mid (Bid+Ask)/2 = (4195.09+4195.52)/2 = 4195.305.
//|   SL line 4190.52 < compare price: BUY.
//|   Order type ORDER_TYPE_BUY, exec = 4195.52.
//|   dist = Ask - SL = 5.
//|   ticks = round(5 / 0.01) = 500.
//|   (a) ticks * tvl = 500 * 1 = 500.
//|   (c) OrderCalcProfit = 500.
//|   worst = 500 (the larger path), the paths agree.
//|   commission per side 0: in 0, out 0.
//|   loss_per_lot = 500 + 0 + 0 = 500.
//|   base = balance 10000.
//|   target = floor(10000 * 1 / 100, 2) = floor(100) = 100.
//|   lot_raw = 100 / 500 = 0.2; lot = 0.01 + floor((lot_raw - 0.01)/0.01 + 1e-8)*0.01 = 0.2.
//|   risk = 0.2 * 500 = 100, 1% of base 10000.
//|   margin_needed = 0.2 * 8391.04 = 1678.208, margin_free 10000.
//|   level at SL = (10000 - 100) / (0 + 1678.208) * 100 = 589.914957%, limit so_so+10 = 60.
//|   spread = 43 points, money = 0.43/0.01 * 1 * 0.2 = 8.6.
//|   Verdict PL_OK, reason PL_R_NONE.
//+------------------------------------------------------------------+
void PlVec06(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="xauusd_usd_buy_boundary";
   v.what="6.4 row 3: XAUUSD FTMO data, risk 1% of 10000, SL $5.00 below Ask, explicit zero commission: lot exactly 0.20 (deliberate step boundary, needs the 1e-8)";
   PlVecSymXAUUSD(v.s);
   PlVecAccount(v.a,"USD",2,10000.0,10000.0,0.0,10000.0);
   PlVecInputs(v.in);
   v.in.sl=4190.52;
   v.in.calcprofit_ok=true;
   v.in.calcprofit_loss_1lot=500.0;
   v.in.comm.kind=PL_COMM_LOT_SIDE; v.in.comm.rate=0.0; v.in.comm.source=PL_COMMSRC_USER;
   //--- expected
   v.chk_prepare_ok=true; v.exp_prepare_ok=true;
   v.exp_plan_reason=PL_R_NONE;
   v.exp_side=PL_SIDE_BUY;
   v.exp_order_type=ORDER_TYPE_BUY;
   v.exp_exec=4195.52;
   v.exp_sl=4190.52;
   v.exp_ticks=500;
   v.exp_lpl_a=500.0;
   v.exp_lpl_price=500.0;
   v.exp_comm_in=0.0;
   v.exp_comm_out=0.0;
   v.exp_loss_per_lot=500.0;
   v.exp_lot=0.2;
   v.exp_risk_money=100.0;
   v.exp_risk_percent=1.0;
   v.exp_margin_needed=1678.208;
   v.exp_spread_points=43.0;
   v.exp_spread_money=8.6;
   v.exp_verdict=PL_OK;
   v.exp_reason=PL_R_NONE;
   v.exp_note=PL_R_NONE;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 07 ger40_eur_on_usd_buy
//| 6.4 row 4: GER40 (EUR, point 0.1, tick 0.5, contract 1) on a USD account, EURUSD 1.10, tick value $0.55, SL 50.0 = 100 ticks; with point instead of tick the lot would be 0.36
//|   Compare price = mid (Bid+Ask)/2 = (19000+19001)/2 = 19000.5.
//|   SL line 18951 < compare price: BUY.
//|   Order type ORDER_TYPE_BUY, exec = 19001.
//|   dist = Ask - SL = 50.
//|   ticks = round(50 / 0.5) = 100.
//|   (a) ticks * tvl = 100 * 0.55 = 55.
//|   (c) OrderCalcProfit = 55.
//|   worst = 55 (the larger path), the paths agree.
//|   commission per side 0: in 0, out 0.
//|   loss_per_lot = 55 + 0 + 0 = 55.
//|   base = balance 10000.
//|   target = floor(10000 * 1 / 100, 2) = floor(100) = 100.
//|   lot_raw = 100 / 55 = 1.81818182; lot = 0.1 + floor((lot_raw - 0.1)/0.1 + 1e-8)*0.1 = 1.8.
//|   risk = 1.8 * 55 = 99, 0.99% of base 10000.
//|   margin_needed = 1.8 * 1045.06 = 1881.108, margin_free 10000.
//|   level at SL = (10000 - 99) / (0 + 1881.108) * 100 = 526.338732%, limit so_so+10 = 60.
//|   spread = 10 points, money = 1/0.5 * 0.55 * 1.8 = 1.98.
//|   Verdict PL_OK, reason PL_R_NONE.
//| QUESTION Q6: account USD is neither base nor profit (EUR), but the symbol is not Forex; the spec defines the cross note only in the Forex paragraph. note not checked.
//+------------------------------------------------------------------+
void PlVec07(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="ger40_eur_on_usd_buy";
   v.what="6.4 row 4: GER40 (EUR, point 0.1, tick 0.5, contract 1) on a USD account, EURUSD 1.10, tick value $0.55, SL 50.0 = 100 ticks; with point instead of tick the lot would be 0.36";
   PlVecSymGER40(v.s);
   PlVecAccount(v.a,"USD",2,10000.0,10000.0,0.0,10000.0);
   PlVecInputs(v.in);
   v.in.sl=18951.0;
   v.in.comm.kind=PL_COMM_LOT_SIDE; v.in.comm.rate=0.0; v.in.comm.source=PL_COMMSRC_USER;
   v.in.calcprofit_ok=true; v.in.calcprofit_loss_1lot=55.0;
   //--- expected
   v.chk_prepare_ok=true; v.exp_prepare_ok=true;
   v.exp_plan_reason=PL_R_NONE;
   v.exp_side=PL_SIDE_BUY;
   v.exp_order_type=ORDER_TYPE_BUY;
   v.exp_exec=19001.0;
   v.exp_sl=18951.0;
   v.exp_ticks=100;
   v.exp_lpl_a=55.0;
   v.exp_lpl_price=55.0;
   v.exp_comm_in=0.0;
   v.exp_comm_out=0.0;
   v.exp_loss_per_lot=55.0;
   v.exp_lot=1.8;
   v.exp_risk_money=99.0;
   v.exp_risk_percent=0.99;
   v.exp_margin_needed=1881.108;
   v.exp_spread_points=10.0;
   v.exp_spread_money=1.98;
   v.exp_verdict=PL_OK;
   v.exp_reason=PL_R_NONE;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 08 btcusd_ftmo_buy_pct
//| 6.4 row 5 on real FTMO BTCUSD data (Ask 83797.56): risk 1% of 10000, SL $500 below Ask, commission 0.0325% per side
//|   Compare price = mid (Bid+Ask)/2 = (83796.56+83797.56)/2 = 83797.06.
//|   SL line 83297.56 < compare price: BUY.
//|   Order type ORDER_TYPE_BUY, exec = 83797.56.
//|   dist = Ask - SL = 500.
//|   ticks = round(500 / 0.01) = 50000.
//|   (a) ticks * tvl = 50000 * 0.01 = 500.
//|   (c) OrderCalcProfit = 500.
//|   worst = 500 (the larger path), the paths agree.
//|   percent 0.0325% per side, k = 1 (profit currency = account currency): in = 83797.56 * 1 * 0.0325/100 * k = 27.234207; out = 83297.56 * 1 * 0.0325/100 * k = 27.071707.
//|   loss_per_lot = 500 + 27.234207 + 27.071707 = 554.305914.
//|   base = balance 10000.
//|   target = floor(10000 * 1 / 100, 2) = floor(100) = 100.
//|   lot_raw = 100 / 554.305914 = 0.1804058; lot = 0.01 + floor((lot_raw - 0.01)/0.01 + 1e-8)*0.01 = 0.18.
//|   risk = 0.18 * 554.305914 = 99.775065, 0.99775065% of base 10000.
//|   margin_needed = 0.18 * 25139.27 = 4525.0686, margin_free 10000.
//|   level at SL = (10000 - 99.775065) / (0 + 4525.0686) * 100 = 218.786184%, limit so_so+10 = 60.
//|   spread = 100 points, money = 1/0.01 * 0.01 * 0.18 = 0.18.
//|   Verdict PL_OK, reason PL_R_NONE.
//+------------------------------------------------------------------+
void PlVec08(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="btcusd_ftmo_buy_pct";
   v.what="6.4 row 5 on real FTMO BTCUSD data (Ask 83797.56): risk 1% of 10000, SL $500 below Ask, commission 0.0325% per side";
   PlVecSymBTCUSD(v.s);
   PlVecAccount(v.a,"USD",2,10000.0,10000.0,0.0,10000.0);
   PlVecInputs(v.in);
   v.in.sl=83297.56;
   v.in.calcprofit_ok=true;
   v.in.calcprofit_loss_1lot=500.0;
   v.in.comm.kind=PL_COMM_PERCENT_SIDE; v.in.comm.rate=0.0325; v.in.comm.source=PL_COMMSRC_USER;
   //--- expected
   v.chk_prepare_ok=true; v.exp_prepare_ok=true;
   v.exp_plan_reason=PL_R_NONE;
   v.exp_side=PL_SIDE_BUY;
   v.exp_order_type=ORDER_TYPE_BUY;
   v.exp_exec=83797.56;
   v.exp_sl=83297.56;
   v.exp_ticks=50000;
   v.exp_lpl_a=500.0;
   v.exp_lpl_price=500.0;
   v.exp_comm_in=27.234207;
   v.exp_comm_out=27.071707;
   v.exp_loss_per_lot=554.305914;
   v.exp_lot=0.18;
   v.exp_risk_money=99.77506452;
   v.exp_risk_percent=0.99775065;
   v.exp_margin_needed=4525.0686;
   v.exp_spread_points=100.0;
   v.exp_spread_money=0.18;
   v.exp_verdict=PL_OK;
   v.exp_reason=PL_R_NONE;
   v.exp_note=PL_R_NONE;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 09 btcusd_plan_example
//| 6.4 row 5 plan numbers: Ask 60000, Bid 59990, SL 59490 ($500 from Bid, dist 510), 0.0325% per side: LossPerLot 548.83, lot 0.18, risk $98.79
//|   Compare price = mid (Bid+Ask)/2 = (59990+60000)/2 = 59995.
//|   SL line 59490 < compare price: BUY.
//|   Order type ORDER_TYPE_BUY, exec = 60000.
//|   dist = Ask - SL = 510.
//|   ticks = round(510 / 0.01) = 51000.
//|   (a) ticks * tvl = 51000 * 0.01 = 510.
//|   (c) OrderCalcProfit = 510.
//|   worst = 510 (the larger path), the paths agree.
//|   percent 0.0325% per side, k = 1 (profit currency = account currency): in = 60000 * 1 * 0.0325/100 * k = 19.5; out = 59490 * 1 * 0.0325/100 * k = 19.33425.
//|   loss_per_lot = 510 + 19.5 + 19.33425 = 548.83425.
//|   base = balance 10000.
//|   target = floor(10000 * 1 / 100, 2) = floor(100) = 100.
//|   lot_raw = 100 / 548.83425 = 0.18220437; lot = 0.01 + floor((lot_raw - 0.01)/0.01 + 1e-8)*0.01 = 0.18.
//|   risk = 0.18 * 548.83425 = 98.790165, 0.98790165% of base 10000.
//|   margin_needed = 0.18 * 18000 = 3240, margin_free 10000.
//|   level at SL = (10000 - 98.790165) / (0 + 3240) * 100 = 305.592896%, limit so_so+10 = 60.
//|   spread = 1000 points, money = 10/0.01 * 0.01 * 0.18 = 1.8.
//|   Verdict PL_OK, reason PL_R_NONE.
//+------------------------------------------------------------------+
void PlVec09(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="btcusd_plan_example";
   v.what="6.4 row 5 plan numbers: Ask 60000, Bid 59990, SL 59490 ($500 from Bid, dist 510), 0.0325% per side: LossPerLot 548.83, lot 0.18, risk $98.79";
   PlVecSymBTCUSD(v.s);
   v.s.bid=59990.0;
   v.s.ask=60000.0;
   v.s.margin_buy_1lot=18000.0;
   v.s.margin_sell_1lot=17997.0;
   PlVecAccount(v.a,"USD",2,10000.0,10000.0,0.0,10000.0);
   PlVecInputs(v.in);
   v.in.sl=59490.0;
   v.in.comm.kind=PL_COMM_PERCENT_SIDE; v.in.comm.rate=0.0325; v.in.comm.source=PL_COMMSRC_USER;
   v.in.calcprofit_ok=true; v.in.calcprofit_loss_1lot=510.0;
   //--- expected
   v.chk_prepare_ok=true; v.exp_prepare_ok=true;
   v.exp_plan_reason=PL_R_NONE;
   v.exp_side=PL_SIDE_BUY;
   v.exp_order_type=ORDER_TYPE_BUY;
   v.exp_exec=60000.0;
   v.exp_sl=59490.0;
   v.exp_ticks=51000;
   v.exp_lpl_a=510.0;
   v.exp_lpl_price=510.0;
   v.exp_comm_in=19.5;
   v.exp_comm_out=19.33425;
   v.exp_loss_per_lot=548.83425;
   v.exp_lot=0.18;
   v.exp_risk_money=98.790165;
   v.exp_risk_percent=0.98790165;
   v.exp_margin_needed=3240.0;
   v.exp_spread_points=1000.0;
   v.exp_spread_money=1.8;
   v.exp_verdict=PL_OK;
   v.exp_reason=PL_R_NONE;
   v.exp_note=PL_R_NONE;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 10 usdcad_usd_buy_slrate
//| 6.1 example: USDCAD Buy Ask 1.37000, SL 1.36000 (1000 ticks): 1000 CAD = $735.29 at the SL rate, not $729.93; risk 1% of 73000 = 730 gives 0.98 (uncorrected 0.99)
//|   Compare price = mid (Bid+Ask)/2 = (1.3699+1.37)/2 = 1.36995.
//|   SL line 1.36 < compare price: BUY.
//|   Order type ORDER_TYPE_BUY, exec = 1.37.
//|   dist = Ask - SL = 0.01.
//|   ticks = round(0.01 / 0.00001) = 1000.
//|   (a) account = base by data (fixture tvl 1/1.37 against Bid 1.3699: 1/k within 1e-4 of Bid): ticks * tick * contract / SL = 1000 * 0.00001 * 100000 / 1.36 = 735.29411765.
//|   (c) OrderCalcProfit = 735.29411765.
//|   commission per side 2.5: in 2.5, out 2.5.
//|   loss_per_lot = 735.29411765 + 2.5 + 2.5 = 740.29411765.
//|   base = balance 73000.
//|   target = floor(73000 * 1 / 100, 2) = floor(730) = 730.
//|   lot_raw = 730 / 740.29411765 = 0.98609456; lot = 0.01 + floor((lot_raw - 0.01)/0.01 + 1e-8)*0.01 = 0.98.
//|   risk = 0.98 * 740.29411765 = 725.488235, 0.99381950% of base 73000.
//|   margin_needed = 0.98 * 1000 = 980, margin_free 73000.
//|   level at SL = (73000 - 725.488235) / (0 + 980) * 100 = 7374.95018%, limit so_so+10 = 60.
//|   spread = 10 points, money = 0.0001/0.00001 * 0.7299270073 * 0.98 = 7.15328467.
//|   Verdict PL_OK, reason PL_R_NONE.
//+------------------------------------------------------------------+
void PlVec10(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="usdcad_usd_buy_slrate";
   v.what="6.1 example: USDCAD Buy Ask 1.37000, SL 1.36000 (1000 ticks): 1000 CAD = $735.29 at the SL rate, not $729.93; risk 1% of 73000 = 730 gives 0.98 (uncorrected 0.99)";
   PlVecSymUSDCAD(v.s);
   PlVecAccount(v.a,"USD",2,73000.0,73000.0,0.0,73000.0);
   PlVecInputs(v.in);
   v.in.sl=1.36;
   v.in.comm.kind=PL_COMM_LOT_SIDE; v.in.comm.rate=2.5; v.in.comm.source=PL_COMMSRC_USER;
   v.in.calcprofit_ok=true; v.in.calcprofit_loss_1lot=735.29411765;
   //--- expected
   v.chk_prepare_ok=true; v.exp_prepare_ok=true;
   v.exp_plan_reason=PL_R_NONE;
   v.exp_side=PL_SIDE_BUY;
   v.exp_order_type=ORDER_TYPE_BUY;
   v.exp_exec=1.37;
   v.exp_sl=1.36;
   v.exp_ticks=1000;
   v.exp_lpl_a=735.29411765;
   v.exp_lpl_price=735.29411765;
   v.exp_comm_in=2.5;
   v.exp_comm_out=2.5;
   v.exp_loss_per_lot=740.29411765;
   v.exp_lot=0.98;
   v.exp_risk_money=725.48823529;
   v.exp_risk_percent=0.99381950;
   v.exp_margin_needed=980.0;
   v.exp_spread_points=10.0;
   v.exp_spread_money=7.15328467;
   v.exp_verdict=PL_OK;
   v.exp_reason=PL_R_NONE;
   v.exp_note=PL_R_NONE;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 11 gbpjpy_usd_cross
//| Cross GBPJPY on a USD account (USDJPY 150): no SL-rate correction, note PL_R_CROSS_RATE_AT_SL
//|   Compare price = mid (Bid+Ask)/2 = (200+200.02)/2 = 200.01.
//|   SL line 199.67 < compare price: BUY.
//|   Order type ORDER_TYPE_BUY, exec = 200.02.
//|   dist = Ask - SL = 0.35.
//|   ticks = round(0.35 / 0.001) = 350.
//|   (a) ticks * tvl = 350 * 0.6666666667 = 233.33333333.
//|   Cross (account neither base nor profit): note PL_R_CROSS_RATE_AT_SL.
//|   commission per side 2.5: in 2.5, out 2.5.
//|   loss_per_lot = 233.33333333 + 2.5 + 2.5 = 238.33333333.
//|   base = balance 10000.
//|   target = floor(10000 * 1 / 100, 2) = floor(100) = 100.
//|   lot_raw = 100 / 238.33333333 = 0.41958042; lot = 0.01 + floor((lot_raw - 0.01)/0.01 + 1e-8)*0.01 = 0.41.
//|   risk = 0.41 * 238.33333333 = 97.716667, 0.97716667% of base 10000.
//|   margin_needed = 0.41 * 1330 = 545.3, margin_free 10000.
//|   level at SL = (10000 - 97.716667) / (0 + 545.3) * 100 = 1815.933125%, limit so_so+10 = 60.
//|   spread = 20 points, money = 0.02/0.001 * 0.6666666667 * 0.41 = 5.46666667.
//|   Verdict PL_OK, reason PL_R_NONE, note PL_R_CROSS_RATE_AT_SL.
//| QUESTION Q1: note vs verdict. The spec writes note = PL_R_CROSS_RATE_AT_SL, Types labels it WARN. Literal: verdict PL_OK, reason PL_R_NONE, note checked.
//+------------------------------------------------------------------+
void PlVec11(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="gbpjpy_usd_cross";
   v.what="Cross GBPJPY on a USD account (USDJPY 150): no SL-rate correction, note PL_R_CROSS_RATE_AT_SL";
   PlVecSymGBPJPY(v.s);
   PlVecAccount(v.a,"USD",2,10000.0,10000.0,0.0,10000.0);
   PlVecInputs(v.in);
   v.in.sl=199.67;
   v.in.comm.kind=PL_COMM_LOT_SIDE; v.in.comm.rate=2.5; v.in.comm.source=PL_COMMSRC_USER;
   v.in.calcprofit_ok=true; v.in.calcprofit_loss_1lot=233.33333333;
   //--- expected
   v.chk_prepare_ok=true; v.exp_prepare_ok=true;
   v.exp_plan_reason=PL_R_NONE;
   v.exp_side=PL_SIDE_BUY;
   v.exp_order_type=ORDER_TYPE_BUY;
   v.exp_exec=200.02;
   v.exp_sl=199.67;
   v.exp_ticks=350;
   v.exp_lpl_a=233.33333333;
   v.exp_lpl_price=233.33333333;
   v.exp_comm_in=2.5;
   v.exp_comm_out=2.5;
   v.exp_loss_per_lot=238.33333333;
   v.exp_lot=0.41;
   v.exp_risk_money=97.71666667;
   v.exp_risk_percent=0.97716667;
   v.exp_margin_needed=545.3;
   v.exp_spread_points=20.0;
   v.exp_spread_money=5.46666667;
   v.exp_verdict=PL_OK;
   v.exp_reason=PL_R_NONE;
   v.exp_note=PL_R_CROSS_RATE_AT_SL;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 12 eurusd_eur_buy_slrate
//| 6.5: EURUSD on a EUR account, Bid = Ask = 1.10000, SL 1.09800, risk EUR 100: uncorrected 0.55 boundary, corrected pip EUR 9.107, LossPerLot 182.15, lot 0.54, risk 98.36
//|   Compare price = mid (Bid+Ask)/2 = (1.1+1.1)/2 = 1.1.
//|   SL line 1.098 < compare price: BUY.
//|   Order type ORDER_TYPE_BUY, exec = 1.1.
//|   dist = Ask - SL = 0.002.
//|   ticks = round(0.002 / 0.00001) = 200.
//|   (a) Forex, account = base: ticks * tvl * Bid/SL = 200 * 0.9090909091 * 1.1/1.098 = 182.14936248.
//|   commission per side 0: in 0, out 0.
//|   loss_per_lot = 182.14936248 + 0 + 0 = 182.14936248.
//|   base = balance 10000.
//|   target = floor(10000 * 1 / 100, 2) = floor(100) = 100.
//|   lot_raw = 100 / 182.14936248 = 0.549; lot = 0.01 + floor((lot_raw - 0.01)/0.01 + 1e-8)*0.01 = 0.54.
//|   risk = 0.54 * 182.14936248 = 98.360656, 0.98360656% of base 10000.
//|   margin_needed = 0.54 * 1000 = 540, margin_free 10000.
//|   level at SL = (10000 - 98.360656) / (0 + 540) * 100 = 1833.636916%, limit so_so+10 = 60.
//|   spread = 0 points, money = 0/0.00001 * 0.9090909091 * 0.54 = 0.
//|   Verdict PL_OK, reason PL_R_NONE.
//+------------------------------------------------------------------+
void PlVec12(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="eurusd_eur_buy_slrate";
   v.what="6.5: EURUSD on a EUR account, Bid = Ask = 1.10000, SL 1.09800, risk EUR 100: uncorrected 0.55 boundary, corrected pip EUR 9.107, LossPerLot 182.15, lot 0.54, risk 98.36";
   PlVecSymEURUSD(v.s);
   v.s.bid=1.1;
   v.s.ask=1.1;
   v.s.tick_value_loss=1.0/1.1;
   v.s.tick_value_profit=1.0/1.1;
   v.s.margin_buy_1lot=1000.0;
   v.s.margin_sell_1lot=1000.0;
   PlVecAccount(v.a,"EUR",2,10000.0,10000.0,0.0,10000.0);
   PlVecInputs(v.in);
   v.in.sl=1.098;
   v.in.comm.kind=PL_COMM_LOT_SIDE; v.in.comm.rate=0.0; v.in.comm.source=PL_COMMSRC_USER;
   v.in.calcprofit_ok=true; v.in.calcprofit_loss_1lot=182.14936248;
   //--- expected
   v.chk_prepare_ok=true; v.exp_prepare_ok=true;
   v.exp_plan_reason=PL_R_NONE;
   v.exp_side=PL_SIDE_BUY;
   v.exp_order_type=ORDER_TYPE_BUY;
   v.exp_exec=1.1;
   v.exp_sl=1.098;
   v.exp_ticks=200;
   v.exp_lpl_a=182.14936248;
   v.exp_lpl_price=182.14936248;
   v.exp_comm_in=0.0;
   v.exp_comm_out=0.0;
   v.exp_loss_per_lot=182.14936248;
   v.exp_lot=0.54;
   v.exp_risk_money=98.36065574;
   v.exp_risk_percent=0.98360656;
   v.exp_margin_needed=540.0;
   v.exp_spread_points=0.0;
   v.exp_spread_money=0.0;
   v.exp_verdict=PL_OK;
   v.exp_reason=PL_R_NONE;
   v.exp_note=PL_R_NONE;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 13 xauusd_eur_buy
//| XAUUSD on a EUR account, EURUSD 1.10: tick value EUR 0.909091, paths (a) and (c) agree, risk 1.2% = EUR 120 (1% would sit on the 0.22 boundary), SL $5.00
//|   Compare price = mid (Bid+Ask)/2 = (4195.09+4195.52)/2 = 4195.305.
//|   SL line 4190.52 < compare price: BUY.
//|   Order type ORDER_TYPE_BUY, exec = 4195.52.
//|   dist = Ask - SL = 5.
//|   ticks = round(5 / 0.01) = 500.
//|   (a) ticks * tvl = 500 * 0.9090909091 = 454.54545455.
//|   (c) OrderCalcProfit = 454.54545455.
//|   worst = 454.54545455 (the larger path), the paths agree.
//|   commission per side 0: in 0, out 0.
//|   loss_per_lot = 454.54545455 + 0 + 0 = 454.54545455.
//|   base = balance 10000.
//|   target = floor(10000 * 1.2 / 100, 2) = floor(120) = 120.
//|   lot_raw = 120 / 454.54545455 = 0.264; lot = 0.01 + floor((lot_raw - 0.01)/0.01 + 1e-8)*0.01 = 0.26.
//|   risk = 0.26 * 454.54545455 = 118.181818, 1.18181818% of base 10000.
//|   margin_needed = 0.26 * 7628.22 = 1983.3372, margin_free 10000.
//|   level at SL = (10000 - 118.181818) / (0 + 1983.3372) * 100 = 498.241962%, limit so_so+10 = 60.
//|   spread = 43 points, money = 0.43/0.01 * 0.9090909091 * 0.26 = 10.16363636.
//|   Verdict PL_OK, reason PL_R_NONE.
//| QUESTION Q6: non-Forex symbol with account neither base nor profit, note not checked.
//+------------------------------------------------------------------+
void PlVec13(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="xauusd_eur_buy";
   v.what="XAUUSD on a EUR account, EURUSD 1.10: tick value EUR 0.909091, paths (a) and (c) agree, risk 1.2% = EUR 120 (1% would sit on the 0.22 boundary), SL $5.00";
   PlVecSymXAUUSD(v.s);
   v.s.tick_value_loss=1.0/1.1;
   v.s.tick_value_profit=1.0/1.1;
   v.s.margin_buy_1lot=7628.22;
   v.s.margin_sell_1lot=7627.44;
   PlVecAccount(v.a,"EUR",2,10000.0,10000.0,0.0,10000.0);
   PlVecInputs(v.in);
   v.in.sl=4190.52;
   v.in.risk_percent=1.2;
   v.in.comm.kind=PL_COMM_LOT_SIDE; v.in.comm.rate=0.0; v.in.comm.source=PL_COMMSRC_USER;
   v.in.calcprofit_ok=true; v.in.calcprofit_loss_1lot=454.54545455;
   //--- expected
   v.chk_prepare_ok=true; v.exp_prepare_ok=true;
   v.exp_plan_reason=PL_R_NONE;
   v.exp_side=PL_SIDE_BUY;
   v.exp_order_type=ORDER_TYPE_BUY;
   v.exp_exec=4195.52;
   v.exp_sl=4190.52;
   v.exp_ticks=500;
   v.exp_lpl_a=454.54545455;
   v.exp_lpl_price=454.54545455;
   v.exp_comm_in=0.0;
   v.exp_comm_out=0.0;
   v.exp_loss_per_lot=454.54545455;
   v.exp_lot=0.26;
   v.exp_risk_money=118.18181818;
   v.exp_risk_percent=1.18181818;
   v.exp_margin_needed=1983.3372;
   v.exp_spread_points=43.0;
   v.exp_spread_money=10.16363636;
   v.exp_verdict=PL_OK;
   v.exp_reason=PL_R_NONE;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 14 usdjpy_jpy_account
//| USDJPY on a JPY account (currency_digits 0): tick value 100 JPY, target floor(1234567 * 1% , 0) = 12345, SL 50 pips below Bid
//|   Compare price = mid (Bid+Ask)/2 = (158.288+158.311)/2 = 158.2995.
//|   SL line 157.788 < compare price: BUY.
//|   Order type ORDER_TYPE_BUY, exec = 158.311.
//|   dist = Ask - SL = 0.523.
//|   ticks = round(0.523 / 0.001) = 523.
//|   (a) ticks * tvl = 523 * 100 = 52300.
//|   commission per side 0: in 0, out 0.
//|   loss_per_lot = 52300 + 0 + 0 = 52300.
//|   base = balance 1234567.
//|   target = floor(1234567 * 1 / 100, 0) = floor(12345.67) = 12345.
//|   lot_raw = 12345 / 52300 = 0.23604207; lot = 0.01 + floor((lot_raw - 0.01)/0.01 + 1e-8)*0.01 = 0.23.
//|   risk = 0.23 * 52300 = 12029, 0.97434971% of base 1234567.
//|   margin_needed = 0.23 * 158311 = 36411.53, margin_free 1234567.
//|   level at SL = (1234567 - 12029) / (0 + 36411.53) * 100 = 3357.557345%, limit so_so+10 = 60.
//|   spread = 23 points, money = 0.023/0.001 * 100 * 0.23 = 529.
//|   Verdict PL_OK, reason PL_R_NONE.
//+------------------------------------------------------------------+
void PlVec14(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="usdjpy_jpy_account";
   v.what="USDJPY on a JPY account (currency_digits 0): tick value 100 JPY, target floor(1234567 * 1% , 0) = 12345, SL 50 pips below Bid";
   PlVecSymUSDJPY(v.s);
   v.s.tick_value_loss=100.0;
   v.s.tick_value_profit=100.0;
   v.s.margin_buy_1lot=158311.0;
   v.s.margin_sell_1lot=158288.0;
   PlVecAccount(v.a,"JPY",0,1234567.0,1234567.0,0.0,1234567.0);
   PlVecInputs(v.in);
   v.in.sl=157.788;
   v.in.comm.kind=PL_COMM_LOT_SIDE; v.in.comm.rate=0.0; v.in.comm.source=PL_COMMSRC_USER;
   v.in.calcprofit_ok=true; v.in.calcprofit_loss_1lot=52300.0;
   //--- expected
   v.chk_prepare_ok=true; v.exp_prepare_ok=true;
   v.exp_plan_reason=PL_R_NONE;
   v.exp_side=PL_SIDE_BUY;
   v.exp_order_type=ORDER_TYPE_BUY;
   v.exp_exec=158.311;
   v.exp_sl=157.788;
   v.exp_ticks=523;
   v.exp_lpl_a=52300.0;
   v.exp_lpl_price=52300.0;
   v.exp_comm_in=0.0;
   v.exp_comm_out=0.0;
   v.exp_loss_per_lot=52300.0;
   v.exp_lot=0.23;
   v.exp_risk_money=12029.0;
   v.exp_risk_percent=0.97434971;
   v.exp_margin_needed=36411.53;
   v.exp_spread_points=23.0;
   v.exp_spread_money=529.0;
   v.exp_verdict=PL_OK;
   v.exp_reason=PL_R_NONE;
   v.exp_note=PL_R_NONE;
   v.tol_money=0.01;
  }

//+------------------------------------------------------------------+
//| 15 base_balance_floor
//| Base balance 12345.67 while equity is 11800: target floor(123.4567, 2) = 123.45, SL 23 pips, zero commission
//|   Compare price = mid (Bid+Ask)/2 = (1.12018+1.12024)/2 = 1.12021.
//|   SL line 1.11794 < compare price: BUY.
//|   Order type ORDER_TYPE_BUY, exec = 1.12024.
//|   dist = Ask - SL = 0.0023.
//|   ticks = round(0.0023 / 0.00001) = 230.
//|   (a) ticks * tvl = 230 * 1 = 230.
//|   commission per side 0: in 0, out 0.
//|   loss_per_lot = 230 + 0 + 0 = 230.
//|   base = balance 12345.67.
//|   target = floor(12345.67 * 1 / 100, 2) = floor(123.4567) = 123.45.
//|   lot_raw = 123.45 / 230 = 0.53673913; lot = 0.01 + floor((lot_raw - 0.01)/0.01 + 1e-8)*0.01 = 0.53.
//|   risk = 0.53 * 230 = 121.9, 0.98739072% of base 12345.67.
//|   margin_needed = 0.53 * 1120.24 = 593.7272, margin_free 11800.
//|   level at SL = (11800 - 121.9) / (0 + 593.7272) * 100 = 1966.913424%, limit so_so+10 = 60.
//|   spread = 6 points, money = 0.00006/0.00001 * 1 * 0.53 = 3.18.
//|   Verdict PL_OK, reason PL_R_NONE.
//+------------------------------------------------------------------+
void PlVec15(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="base_balance_floor";
   v.what="Base balance 12345.67 while equity is 11800: target floor(123.4567, 2) = 123.45, SL 23 pips, zero commission";
   PlVecSymEURUSD(v.s);
   PlVecAccount(v.a,"USD",2,12345.67,11800.0,0.0,11800.0);
   PlVecInputs(v.in);
   v.in.sl=1.11794;
   v.in.comm.kind=PL_COMM_LOT_SIDE; v.in.comm.rate=0.0; v.in.comm.source=PL_COMMSRC_USER;
   v.in.calcprofit_ok=true; v.in.calcprofit_loss_1lot=230.0;
   //--- expected
   v.chk_prepare_ok=true; v.exp_prepare_ok=true;
   v.exp_plan_reason=PL_R_NONE;
   v.exp_side=PL_SIDE_BUY;
   v.exp_order_type=ORDER_TYPE_BUY;
   v.exp_exec=1.12024;
   v.exp_sl=1.11794;
   v.exp_ticks=230;
   v.exp_lpl_a=230.0;
   v.exp_lpl_price=230.0;
   v.exp_comm_in=0.0;
   v.exp_comm_out=0.0;
   v.exp_loss_per_lot=230.0;
   v.exp_lot=0.53;
   v.exp_risk_money=121.9;
   v.exp_risk_percent=0.98739072;
   v.exp_margin_needed=593.7272;
   v.exp_spread_points=6.0;
   v.exp_spread_money=3.18;
   v.exp_verdict=PL_OK;
   v.exp_reason=PL_R_NONE;
   v.exp_note=PL_R_NONE;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 16 base_equity_loss
//| Base equity with an open position in loss: balance 10000, equity 9500, 1% = 95
//|   Compare price = mid (Bid+Ask)/2 = (1.12018+1.12024)/2 = 1.12021.
//|   SL line 1.11794 < compare price: BUY.
//|   Order type ORDER_TYPE_BUY, exec = 1.12024.
//|   dist = Ask - SL = 0.0023.
//|   ticks = round(0.0023 / 0.00001) = 230.
//|   (a) ticks * tvl = 230 * 1 = 230.
//|   commission per side 0: in 0, out 0.
//|   loss_per_lot = 230 + 0 + 0 = 230.
//|   base = equity 9500.
//|   target = floor(9500 * 1 / 100, 2) = floor(95) = 95.
//|   lot_raw = 95 / 230 = 0.41304348; lot = 0.01 + floor((lot_raw - 0.01)/0.01 + 1e-8)*0.01 = 0.41.
//|   risk = 0.41 * 230 = 94.3, 0.99263158% of base 9500.
//|   margin_needed = 0.41 * 1120.24 = 459.2984, margin_free 9500.
//|   level at SL = (9500 - 94.3) / (0 + 459.2984) * 100 = 2047.840794%, limit so_so+10 = 60.
//|   spread = 6 points, money = 0.00006/0.00001 * 1 * 0.41 = 2.46.
//|   Verdict PL_OK, reason PL_R_NONE.
//+------------------------------------------------------------------+
void PlVec16(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="base_equity_loss";
   v.what="Base equity with an open position in loss: balance 10000, equity 9500, 1% = 95";
   PlVecSymEURUSD(v.s);
   PlVecAccount(v.a,"USD",2,10000.0,9500.0,0.0,9500.0);
   PlVecInputs(v.in);
   v.in.sl=1.11794;
   v.in.base=PL_BASE_EQUITY;
   v.in.comm.kind=PL_COMM_LOT_SIDE; v.in.comm.rate=0.0; v.in.comm.source=PL_COMMSRC_USER;
   v.in.calcprofit_ok=true; v.in.calcprofit_loss_1lot=230.0;
   //--- expected
   v.chk_prepare_ok=true; v.exp_prepare_ok=true;
   v.exp_plan_reason=PL_R_NONE;
   v.exp_side=PL_SIDE_BUY;
   v.exp_order_type=ORDER_TYPE_BUY;
   v.exp_exec=1.12024;
   v.exp_sl=1.11794;
   v.exp_ticks=230;
   v.exp_lpl_a=230.0;
   v.exp_lpl_price=230.0;
   v.exp_comm_in=0.0;
   v.exp_comm_out=0.0;
   v.exp_loss_per_lot=230.0;
   v.exp_lot=0.41;
   v.exp_risk_money=94.3;
   v.exp_risk_percent=0.99263158;
   v.exp_margin_needed=459.2984;
   v.exp_spread_points=6.0;
   v.exp_spread_money=2.46;
   v.exp_verdict=PL_OK;
   v.exp_reason=PL_R_NONE;
   v.exp_note=PL_R_NONE;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 17 base_equity_profit
//| Base equity with an open position in profit: balance 10000, equity 10500, 1% = 105
//|   Compare price = mid (Bid+Ask)/2 = (1.12018+1.12024)/2 = 1.12021.
//|   SL line 1.11794 < compare price: BUY.
//|   Order type ORDER_TYPE_BUY, exec = 1.12024.
//|   dist = Ask - SL = 0.0023.
//|   ticks = round(0.0023 / 0.00001) = 230.
//|   (a) ticks * tvl = 230 * 1 = 230.
//|   commission per side 0: in 0, out 0.
//|   loss_per_lot = 230 + 0 + 0 = 230.
//|   base = equity 10500.
//|   target = floor(10500 * 1 / 100, 2) = floor(105) = 105.
//|   lot_raw = 105 / 230 = 0.45652174; lot = 0.01 + floor((lot_raw - 0.01)/0.01 + 1e-8)*0.01 = 0.45.
//|   risk = 0.45 * 230 = 103.5, 0.98571429% of base 10500.
//|   margin_needed = 0.45 * 1120.24 = 504.108, margin_free 10500.
//|   level at SL = (10500 - 103.5) / (0 + 504.108) * 100 = 2062.355686%, limit so_so+10 = 60.
//|   spread = 6 points, money = 0.00006/0.00001 * 1 * 0.45 = 2.7.
//|   Verdict PL_OK, reason PL_R_NONE.
//+------------------------------------------------------------------+
void PlVec17(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="base_equity_profit";
   v.what="Base equity with an open position in profit: balance 10000, equity 10500, 1% = 105";
   PlVecSymEURUSD(v.s);
   PlVecAccount(v.a,"USD",2,10000.0,10500.0,0.0,10500.0);
   PlVecInputs(v.in);
   v.in.sl=1.11794;
   v.in.base=PL_BASE_EQUITY;
   v.in.comm.kind=PL_COMM_LOT_SIDE; v.in.comm.rate=0.0; v.in.comm.source=PL_COMMSRC_USER;
   v.in.calcprofit_ok=true; v.in.calcprofit_loss_1lot=230.0;
   //--- expected
   v.chk_prepare_ok=true; v.exp_prepare_ok=true;
   v.exp_plan_reason=PL_R_NONE;
   v.exp_side=PL_SIDE_BUY;
   v.exp_order_type=ORDER_TYPE_BUY;
   v.exp_exec=1.12024;
   v.exp_sl=1.11794;
   v.exp_ticks=230;
   v.exp_lpl_a=230.0;
   v.exp_lpl_price=230.0;
   v.exp_comm_in=0.0;
   v.exp_comm_out=0.0;
   v.exp_loss_per_lot=230.0;
   v.exp_lot=0.45;
   v.exp_risk_money=103.5;
   v.exp_risk_percent=0.98571429;
   v.exp_margin_needed=504.108;
   v.exp_spread_points=6.0;
   v.exp_spread_money=2.7;
   v.exp_verdict=PL_OK;
   v.exp_reason=PL_R_NONE;
   v.exp_note=PL_R_NONE;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 18 subtract_open
//| subtract_open: balance 10000 minus open risk 150 and pending risk 50 = 9800, 1% = 98; risk percent of the reduced base
//|   Compare price = mid (Bid+Ask)/2 = (1.12018+1.12024)/2 = 1.12021.
//|   SL line 1.11794 < compare price: BUY.
//|   Order type ORDER_TYPE_BUY, exec = 1.12024.
//|   dist = Ask - SL = 0.0023.
//|   ticks = round(0.0023 / 0.00001) = 230.
//|   (a) ticks * tvl = 230 * 1 = 230.
//|   commission per side 0: in 0, out 0.
//|   loss_per_lot = 230 + 0 + 0 = 230.
//|   base = balance 10000.
//|   subtract_open: base - 150 - 50 = 9800.
//|   target = floor(9800 * 1 / 100, 2) = floor(98) = 98.
//|   lot_raw = 98 / 230 = 0.42608696; lot = 0.01 + floor((lot_raw - 0.01)/0.01 + 1e-8)*0.01 = 0.42.
//|   risk = 0.42 * 230 = 96.6, 0.98571429% of base 9800.
//|   margin_needed = 0.42 * 1120.24 = 470.5008, margin_free 10000.
//|   level at SL = (10000 - 96.6) / (0 + 470.5008) * 100 = 2104.863584%, limit so_so+10 = 60.
//|   spread = 6 points, money = 0.00006/0.00001 * 1 * 0.42 = 2.52.
//|   Verdict PL_OK, reason PL_R_NONE.
//+------------------------------------------------------------------+
void PlVec18(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="subtract_open";
   v.what="subtract_open: balance 10000 minus open risk 150 and pending risk 50 = 9800, 1% = 98; risk percent of the reduced base";
   PlVecSymEURUSD(v.s);
   PlVecAccount(v.a,"USD",2,10000.0,10000.0,0.0,10000.0);
   v.a.open_risk_money=150.0;
   v.a.pending_risk_money=50.0;
   PlVecInputs(v.in);
   v.in.sl=1.11794;
   v.in.subtract_open=true;
   v.in.comm.kind=PL_COMM_LOT_SIDE; v.in.comm.rate=0.0; v.in.comm.source=PL_COMMSRC_USER;
   v.in.calcprofit_ok=true; v.in.calcprofit_loss_1lot=230.0;
   //--- expected
   v.chk_prepare_ok=true; v.exp_prepare_ok=true;
   v.exp_plan_reason=PL_R_NONE;
   v.exp_side=PL_SIDE_BUY;
   v.exp_order_type=ORDER_TYPE_BUY;
   v.exp_exec=1.12024;
   v.exp_sl=1.11794;
   v.exp_ticks=230;
   v.exp_lpl_a=230.0;
   v.exp_lpl_price=230.0;
   v.exp_comm_in=0.0;
   v.exp_comm_out=0.0;
   v.exp_loss_per_lot=230.0;
   v.exp_lot=0.42;
   v.exp_risk_money=96.6;
   v.exp_risk_percent=0.98571429;
   v.exp_margin_needed=470.5008;
   v.exp_spread_points=6.0;
   v.exp_spread_money=2.52;
   v.exp_verdict=PL_OK;
   v.exp_reason=PL_R_NONE;
   v.exp_note=PL_R_NONE;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 19 risk_money
//| Risk in money: $150 on a 10000 balance, SL 23 pips
//|   Compare price = mid (Bid+Ask)/2 = (1.12018+1.12024)/2 = 1.12021.
//|   SL line 1.11794 < compare price: BUY.
//|   Order type ORDER_TYPE_BUY, exec = 1.12024.
//|   dist = Ask - SL = 0.0023.
//|   ticks = round(0.0023 / 0.00001) = 230.
//|   (a) ticks * tvl = 230 * 1 = 230.
//|   commission per side 0: in 0, out 0.
//|   loss_per_lot = 230 + 0 + 0 = 230.
//|   base = balance 10000.
//|   target = risk_money 150.
//|   lot_raw = 150 / 230 = 0.65217391; lot = 0.01 + floor((lot_raw - 0.01)/0.01 + 1e-8)*0.01 = 0.65.
//|   risk = 0.65 * 230 = 149.5, 1.495% of base 10000.
//|   margin_needed = 0.65 * 1120.24 = 728.156, margin_free 10000.
//|   level at SL = (10000 - 149.5) / (0 + 728.156) * 100 = 1352.800773%, limit so_so+10 = 60.
//|   spread = 6 points, money = 0.00006/0.00001 * 1 * 0.65 = 3.9.
//|   Verdict PL_OK, reason PL_R_NONE.
//+------------------------------------------------------------------+
void PlVec19(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="risk_money";
   v.what="Risk in money: $150 on a 10000 balance, SL 23 pips";
   PlVecSymEURUSD(v.s);
   PlVecAccount(v.a,"USD",2,10000.0,10000.0,0.0,10000.0);
   PlVecInputs(v.in);
   v.in.sl=1.11794;
   v.in.risk_mode=PL_RISK_MONEY;
   v.in.risk_money=150.0;
   v.in.comm.kind=PL_COMM_LOT_SIDE; v.in.comm.rate=0.0; v.in.comm.source=PL_COMMSRC_USER;
   v.in.calcprofit_ok=true; v.in.calcprofit_loss_1lot=230.0;
   //--- expected
   v.chk_prepare_ok=true; v.exp_prepare_ok=true;
   v.exp_plan_reason=PL_R_NONE;
   v.exp_side=PL_SIDE_BUY;
   v.exp_order_type=ORDER_TYPE_BUY;
   v.exp_exec=1.12024;
   v.exp_sl=1.11794;
   v.exp_ticks=230;
   v.exp_lpl_a=230.0;
   v.exp_lpl_price=230.0;
   v.exp_comm_in=0.0;
   v.exp_comm_out=0.0;
   v.exp_loss_per_lot=230.0;
   v.exp_lot=0.65;
   v.exp_risk_money=149.5;
   v.exp_risk_percent=1.495;
   v.exp_margin_needed=728.156;
   v.exp_spread_points=6.0;
   v.exp_spread_money=3.9;
   v.exp_verdict=PL_OK;
   v.exp_reason=PL_R_NONE;
   v.exp_note=PL_R_NONE;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 22 lot_below_min_confirm
//| Lot below the minimum: XAUUSD, balance 800, 1% = 8, SL $10.00: lot_raw 0.008, min lot 0.01 means 1.25% (below cap): CONFIRM
//|   Compare price = mid (Bid+Ask)/2 = (4195.09+4195.52)/2 = 4195.305.
//|   SL line 4185.52 < compare price: BUY.
//|   Order type ORDER_TYPE_BUY, exec = 4195.52.
//|   dist = Ask - SL = 10.
//|   ticks = round(10 / 0.01) = 1000.
//|   (a) ticks * tvl = 1000 * 1 = 1000.
//|   (c) OrderCalcProfit = 1000.
//|   worst = 1000 (the larger path), the paths agree.
//|   commission per side 0: in 0, out 0.
//|   loss_per_lot = 1000 + 0 + 0 = 1000.
//|   base = balance 800.
//|   target = floor(800 * 1 / 100, 2) = floor(8) = 8.
//|   lot_raw = 8 / 1000 = 0.008 < vol_min 0.01: lot = vol_min, PL_R_LOT_BELOW_MIN (CONFIRM).
//|   risk = 0.01 * 1000 = 10, 1.25% of base 800.
//|   margin_needed = 0.01 * 8391.04 = 83.9104, margin_free 800.
//|   level at SL = (800 - 10) / (0 + 83.9104) * 100 = 941.480436%, limit so_so+10 = 60.
//|   spread = 43 points, money = 0.43/0.01 * 1 * 0.01 = 0.43.
//|   Verdict PL_CONFIRM, reason PL_R_LOT_BELOW_MIN.
//+------------------------------------------------------------------+
void PlVec22(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="lot_below_min_confirm";
   v.what="Lot below the minimum: XAUUSD, balance 800, 1% = 8, SL $10.00: lot_raw 0.008, min lot 0.01 means 1.25% (below cap): CONFIRM";
   PlVecSymXAUUSD(v.s);
   PlVecAccount(v.a,"USD",2,800.0,800.0,0.0,800.0);
   PlVecInputs(v.in);
   v.in.sl=4185.52;
   v.in.comm.kind=PL_COMM_LOT_SIDE; v.in.comm.rate=0.0; v.in.comm.source=PL_COMMSRC_USER;
   v.in.calcprofit_ok=true; v.in.calcprofit_loss_1lot=1000.0;
   //--- expected
   v.chk_prepare_ok=true; v.exp_prepare_ok=true;
   v.exp_plan_reason=PL_R_NONE;
   v.exp_side=PL_SIDE_BUY;
   v.exp_order_type=ORDER_TYPE_BUY;
   v.exp_exec=4195.52;
   v.exp_sl=4185.52;
   v.exp_ticks=1000;
   v.exp_lpl_a=1000.0;
   v.exp_lpl_price=1000.0;
   v.exp_comm_in=0.0;
   v.exp_comm_out=0.0;
   v.exp_loss_per_lot=1000.0;
   v.exp_lot=0.01;
   v.exp_risk_money=10.0;
   v.exp_risk_percent=1.25;
   v.exp_margin_needed=83.9104;
   v.exp_spread_points=43.0;
   v.exp_spread_money=0.43;
   v.exp_verdict=PL_CONFIRM;
   v.exp_reason=PL_R_LOT_BELOW_MIN;
   v.exp_note=PL_R_NONE;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 23 lot_below_min_above_cap
//| 6.3 example: gold, balance 500, SL $50: min lot 0.01 is 10%, above the 5% cap: BLOCK
//|   Compare price = mid (Bid+Ask)/2 = (4195.09+4195.52)/2 = 4195.305.
//|   SL line 4145.52 < compare price: BUY.
//|   Order type ORDER_TYPE_BUY, exec = 4195.52.
//|   dist = Ask - SL = 50.
//|   ticks = round(50 / 0.01) = 5000.
//|   (a) ticks * tvl = 5000 * 1 = 5000.
//|   (c) OrderCalcProfit = 5000.
//|   worst = 5000 (the larger path), the paths agree.
//|   commission per side 0: in 0, out 0.
//|   loss_per_lot = 5000 + 0 + 0 = 5000.
//|   base = balance 500.
//|   target = floor(500 * 1 / 100, 2) = floor(5) = 5.
//|   lot_raw = 5 / 5000 = 0.001 < vol_min 0.01: lot = vol_min, PL_R_LOT_BELOW_MIN (CONFIRM).
//|   risk = 0.01 * 5000 = 50, 10% of base 500.
//|   10% > cap 5%: PL_R_RISK_ABOVE_CAP (BLOCK).
//|   10% > 2%: PL_R_RISK_HIGH (CONFIRM).
//|   margin_needed = 0.01 * 8391.04 = 83.9104, margin_free 500.
//|   level at SL = (500 - 50) / (0 + 83.9104) * 100 = 536.286324%, limit so_so+10 = 60.
//|   spread = 43 points, money = 0.43/0.01 * 1 * 0.01 = 0.43.
//|   Verdict PL_BLOCK, reason PL_R_RISK_ABOVE_CAP.
//+------------------------------------------------------------------+
void PlVec23(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="lot_below_min_above_cap";
   v.what="6.3 example: gold, balance 500, SL $50: min lot 0.01 is 10%, above the 5% cap: BLOCK";
   PlVecSymXAUUSD(v.s);
   PlVecAccount(v.a,"USD",2,500.0,500.0,0.0,500.0);
   PlVecInputs(v.in);
   v.in.sl=4145.52;
   v.in.comm.kind=PL_COMM_LOT_SIDE; v.in.comm.rate=0.0; v.in.comm.source=PL_COMMSRC_USER;
   v.in.calcprofit_ok=true; v.in.calcprofit_loss_1lot=5000.0;
   //--- expected
   v.chk_prepare_ok=true; v.exp_prepare_ok=true;
   v.exp_plan_reason=PL_R_NONE;
   v.exp_side=PL_SIDE_BUY;
   v.exp_order_type=ORDER_TYPE_BUY;
   v.exp_exec=4195.52;
   v.exp_sl=4145.52;
   v.exp_ticks=5000;
   v.exp_lpl_a=5000.0;
   v.exp_lpl_price=5000.0;
   v.exp_comm_in=0.0;
   v.exp_comm_out=0.0;
   v.exp_loss_per_lot=5000.0;
   v.exp_lot=0.01;
   v.exp_risk_money=50.0;
   v.exp_risk_percent=10.0;
   v.exp_margin_needed=83.9104;
   v.exp_spread_points=43.0;
   v.exp_spread_money=0.43;
   v.exp_verdict=PL_BLOCK;
   v.exp_reason=PL_R_RISK_ABOVE_CAP;
   v.exp_note=PL_R_NONE;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 24 lot_above_max_block
//| Lot above the maximum: BTCUSD vol_max 5, balance 1000000, 0.1% = 1000, SL $110, zero commission: 9.09 lots, BLOCK
//|   Compare price = mid (Bid+Ask)/2 = (83796.56+83797.56)/2 = 83797.06.
//|   SL line 83687.56 < compare price: BUY.
//|   Order type ORDER_TYPE_BUY, exec = 83797.56.
//|   dist = Ask - SL = 110.
//|   ticks = round(110 / 0.01) = 11000.
//|   (a) ticks * tvl = 11000 * 0.01 = 110.
//|   (c) OrderCalcProfit = 110.
//|   worst = 110 (the larger path), the paths agree.
//|   commission per side 0: in 0, out 0.
//|   loss_per_lot = 110 + 0 + 0 = 110.
//|   base = balance 1000000.
//|   target = floor(1000000 * 0.1 / 100, 2) = floor(1000) = 1000.
//|   lot_raw = 1000 / 110 = 9.09090909; lot = 0.01 + floor((lot_raw - 0.01)/0.01 + 1e-8)*0.01 = 9.09.
//|   lot 9.09 > vol_max 5: PL_R_LOT_ABOVE_MAX (BLOCK), lot kept as computed (literal).
//|   risk = 9.09 * 110 = 999.9, 0.09999% of base 1000000.
//|   margin_needed = 9.09 * 25139.27 = 228515.9643, margin_free 1000000.
//|   level at SL = (1000000 - 999.9) / (0 + 228515.9643) * 100 = 437.168625%, limit so_so+10 = 60.
//|   spread = 100 points, money = 1/0.01 * 0.01 * 9.09 = 9.09.
//|   Verdict PL_BLOCK, reason PL_R_LOT_ABOVE_MAX.
//| QUESTION Q5: the spec does not say whether r.lot is the stepped lot or vol_max when BLOCK LOT_ABOVE_MAX; literal: the computed lot 9.09.
//+------------------------------------------------------------------+
void PlVec24(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="lot_above_max_block";
   v.what="Lot above the maximum: BTCUSD vol_max 5, balance 1000000, 0.1% = 1000, SL $110, zero commission: 9.09 lots, BLOCK";
   PlVecSymBTCUSD(v.s);
   PlVecAccount(v.a,"USD",2,1000000.0,1000000.0,0.0,1000000.0);
   PlVecInputs(v.in);
   v.in.sl=83687.56;
   v.in.risk_percent=0.1;
   v.in.comm.kind=PL_COMM_LOT_SIDE; v.in.comm.rate=0.0; v.in.comm.source=PL_COMMSRC_USER;
   v.in.calcprofit_ok=true; v.in.calcprofit_loss_1lot=110.0;
   //--- expected
   v.chk_prepare_ok=true; v.exp_prepare_ok=true;
   v.exp_plan_reason=PL_R_NONE;
   v.exp_side=PL_SIDE_BUY;
   v.exp_order_type=ORDER_TYPE_BUY;
   v.exp_exec=83797.56;
   v.exp_sl=83687.56;
   v.exp_ticks=11000;
   v.exp_lpl_a=110.0;
   v.exp_lpl_price=110.0;
   v.exp_comm_in=0.0;
   v.exp_comm_out=0.0;
   v.exp_loss_per_lot=110.0;
   v.exp_lot=9.09;
   v.exp_risk_money=999.9;
   v.exp_risk_percent=0.09999;
   v.exp_margin_needed=228515.9643;
   v.exp_spread_points=100.0;
   v.exp_spread_money=9.09;
   v.exp_verdict=PL_BLOCK;
   v.exp_reason=PL_R_LOT_ABOVE_MAX;
   v.exp_note=PL_R_NONE;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 25 lot_above_max_trim
//| Same with trim_to_max: lot 5.00 (vol_max), WARN
//|   Compare price = mid (Bid+Ask)/2 = (83796.56+83797.56)/2 = 83797.06.
//|   SL line 83687.56 < compare price: BUY.
//|   Order type ORDER_TYPE_BUY, exec = 83797.56.
//|   dist = Ask - SL = 110.
//|   ticks = round(110 / 0.01) = 11000.
//|   (a) ticks * tvl = 11000 * 0.01 = 110.
//|   (c) OrderCalcProfit = 110.
//|   worst = 110 (the larger path), the paths agree.
//|   commission per side 0: in 0, out 0.
//|   loss_per_lot = 110 + 0 + 0 = 110.
//|   base = balance 1000000.
//|   target = floor(1000000 * 0.1 / 100, 2) = floor(1000) = 1000.
//|   lot_raw = 1000 / 110 = 9.09090909; lot = 0.01 + floor((lot_raw - 0.01)/0.01 + 1e-8)*0.01 = 9.09.
//|   lot 9.09 > vol_max 5: trim_to_max, lot = 5, PL_R_LOT_ABOVE_MAX (WARN).
//|   risk = 5 * 110 = 550, 0.055% of base 1000000.
//|   margin_needed = 5 * 25139.27 = 125696.35, margin_free 1000000.
//|   level at SL = (1000000 - 550) / (0 + 125696.35) * 100 = 795.130487%, limit so_so+10 = 60.
//|   spread = 100 points, money = 1/0.01 * 0.01 * 5 = 5.
//|   Verdict PL_WARN, reason PL_R_LOT_ABOVE_MAX.
//+------------------------------------------------------------------+
void PlVec25(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="lot_above_max_trim";
   v.what="Same with trim_to_max: lot 5.00 (vol_max), WARN";
   PlVecSymBTCUSD(v.s);
   PlVecAccount(v.a,"USD",2,1000000.0,1000000.0,0.0,1000000.0);
   PlVecInputs(v.in);
   v.in.sl=83687.56;
   v.in.risk_percent=0.1;
   v.in.over_max=PL_OVER_TRIM;
   v.in.comm.kind=PL_COMM_LOT_SIDE; v.in.comm.rate=0.0; v.in.comm.source=PL_COMMSRC_USER;
   v.in.calcprofit_ok=true; v.in.calcprofit_loss_1lot=110.0;
   //--- expected
   v.chk_prepare_ok=true; v.exp_prepare_ok=true;
   v.exp_plan_reason=PL_R_NONE;
   v.exp_side=PL_SIDE_BUY;
   v.exp_order_type=ORDER_TYPE_BUY;
   v.exp_exec=83797.56;
   v.exp_sl=83687.56;
   v.exp_ticks=11000;
   v.exp_lpl_a=110.0;
   v.exp_lpl_price=110.0;
   v.exp_comm_in=0.0;
   v.exp_comm_out=0.0;
   v.exp_loss_per_lot=110.0;
   v.exp_lot=5.0;
   v.exp_risk_money=550.0;
   v.exp_risk_percent=0.055;
   v.exp_margin_needed=125696.35;
   v.exp_spread_points=100.0;
   v.exp_spread_money=5.0;
   v.exp_verdict=PL_WARN;
   v.exp_reason=PL_R_LOT_ABOVE_MAX;
   v.exp_note=PL_R_NONE;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 26 volume_limit
//| SYMBOL_VOLUME_LIMIT 1.00 with 0.80 already open: 0.43 more is 1.23: BLOCK
//|   Compare price = mid (Bid+Ask)/2 = (1.12018+1.12024)/2 = 1.12021.
//|   SL line 1.11794 < compare price: BUY.
//|   Order type ORDER_TYPE_BUY, exec = 1.12024.
//|   dist = Ask - SL = 0.0023.
//|   ticks = round(0.0023 / 0.00001) = 230.
//|   (a) ticks * tvl = 230 * 1 = 230.
//|   commission per side 0: in 0, out 0.
//|   loss_per_lot = 230 + 0 + 0 = 230.
//|   base = balance 10000.
//|   target = floor(10000 * 1 / 100, 2) = floor(100) = 100.
//|   lot_raw = 100 / 230 = 0.43478261; lot = 0.01 + floor((lot_raw - 0.01)/0.01 + 1e-8)*0.01 = 0.43.
//|   vol_open 0.8 + lot 0.43 > vol_limit 1: PL_R_VOLUME_LIMIT.
//|   risk = 0.43 * 230 = 98.9, 0.989% of base 10000.
//|   margin_needed = 0.43 * 1120.24 = 481.7032, margin_free 10000.
//|   level at SL = (10000 - 98.9) / (0 + 481.7032) * 100 = 2055.435795%, limit so_so+10 = 60.
//|   spread = 6 points, money = 0.00006/0.00001 * 1 * 0.43 = 2.58.
//|   Verdict PL_BLOCK, reason PL_R_VOLUME_LIMIT.
//+------------------------------------------------------------------+
void PlVec26(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="volume_limit";
   v.what="SYMBOL_VOLUME_LIMIT 1.00 with 0.80 already open: 0.43 more is 1.23: BLOCK";
   PlVecSymEURUSD(v.s);
   v.s.vol_limit=1.0;
   v.s.vol_open_buy=0.8;
   PlVecAccount(v.a,"USD",2,10000.0,10000.0,0.0,10000.0);
   PlVecInputs(v.in);
   v.in.sl=1.11794;
   v.in.comm.kind=PL_COMM_LOT_SIDE; v.in.comm.rate=0.0; v.in.comm.source=PL_COMMSRC_USER;
   v.in.calcprofit_ok=true; v.in.calcprofit_loss_1lot=230.0;
   //--- expected
   v.chk_prepare_ok=true; v.exp_prepare_ok=true;
   v.exp_plan_reason=PL_R_NONE;
   v.exp_side=PL_SIDE_BUY;
   v.exp_order_type=ORDER_TYPE_BUY;
   v.exp_exec=1.12024;
   v.exp_sl=1.11794;
   v.exp_ticks=230;
   v.exp_lpl_a=230.0;
   v.exp_lpl_price=230.0;
   v.exp_comm_in=0.0;
   v.exp_comm_out=0.0;
   v.exp_loss_per_lot=230.0;
   v.exp_lot=0.43;
   v.exp_risk_money=98.9;
   v.exp_risk_percent=0.989;
   v.exp_margin_needed=481.7032;
   v.exp_spread_points=6.0;
   v.exp_spread_money=2.58;
   v.exp_verdict=PL_BLOCK;
   v.exp_reason=PL_R_VOLUME_LIMIT;
   v.exp_note=PL_R_NONE;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 27 money_above_cap
//| Cap in money mode: $600 on 10000 = 5.98% after rounding, above the 5% cap: BLOCK (not clamped)
//|   Compare price = mid (Bid+Ask)/2 = (1.12018+1.12024)/2 = 1.12021.
//|   SL line 1.11794 < compare price: BUY.
//|   Order type ORDER_TYPE_BUY, exec = 1.12024.
//|   dist = Ask - SL = 0.0023.
//|   ticks = round(0.0023 / 0.00001) = 230.
//|   (a) ticks * tvl = 230 * 1 = 230.
//|   commission per side 0: in 0, out 0.
//|   loss_per_lot = 230 + 0 + 0 = 230.
//|   base = balance 10000.
//|   target = risk_money 600.
//|   lot_raw = 600 / 230 = 2.60869565; lot = 0.01 + floor((lot_raw - 0.01)/0.01 + 1e-8)*0.01 = 2.6.
//|   risk = 2.6 * 230 = 598, 5.98% of base 10000.
//|   5.98% > cap 5%: PL_R_RISK_ABOVE_CAP (BLOCK).
//|   5.98% > 2%: PL_R_RISK_HIGH (CONFIRM).
//|   margin_needed = 2.6 * 1120.24 = 2912.624, margin_free 10000.
//|   level at SL = (10000 - 598) / (0 + 2912.624) * 100 = 322.801707%, limit so_so+10 = 60.
//|   spread = 6 points, money = 0.00006/0.00001 * 1 * 2.6 = 15.6.
//|   Verdict PL_BLOCK, reason PL_R_RISK_ABOVE_CAP.
//| QUESTION Q5b: Types says risk_target is 'after the base and cap', the spec says BLOCK above the cap; risk_target not checked.
//+------------------------------------------------------------------+
void PlVec27(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="money_above_cap";
   v.what="Cap in money mode: $600 on 10000 = 5.98% after rounding, above the 5% cap: BLOCK (not clamped)";
   PlVecSymEURUSD(v.s);
   PlVecAccount(v.a,"USD",2,10000.0,10000.0,0.0,10000.0);
   PlVecInputs(v.in);
   v.in.sl=1.11794;
   v.in.risk_mode=PL_RISK_MONEY;
   v.in.risk_money=600.0;
   v.in.comm.kind=PL_COMM_LOT_SIDE; v.in.comm.rate=0.0; v.in.comm.source=PL_COMMSRC_USER;
   v.in.calcprofit_ok=true; v.in.calcprofit_loss_1lot=230.0;
   //--- expected
   v.chk_prepare_ok=true; v.exp_prepare_ok=true;
   v.exp_plan_reason=PL_R_NONE;
   v.exp_side=PL_SIDE_BUY;
   v.exp_order_type=ORDER_TYPE_BUY;
   v.exp_exec=1.12024;
   v.exp_sl=1.11794;
   v.exp_ticks=230;
   v.exp_lpl_a=230.0;
   v.exp_lpl_price=230.0;
   v.exp_comm_in=0.0;
   v.exp_comm_out=0.0;
   v.exp_loss_per_lot=230.0;
   v.exp_lot=2.6;
   v.exp_risk_money=598.0;
   v.exp_risk_percent=5.98;
   v.exp_margin_needed=2912.624;
   v.exp_spread_points=6.0;
   v.exp_spread_money=15.6;
   v.exp_verdict=PL_BLOCK;
   v.exp_reason=PL_R_RISK_ABOVE_CAP;
   v.exp_note=PL_R_NONE;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 28 percent_above_confirm
//| 2.5% risk: actual 2.484% > confirm_above 2%: CONFIRM PL_R_RISK_HIGH
//|   Compare price = mid (Bid+Ask)/2 = (1.12018+1.12024)/2 = 1.12021.
//|   SL line 1.11794 < compare price: BUY.
//|   Order type ORDER_TYPE_BUY, exec = 1.12024.
//|   dist = Ask - SL = 0.0023.
//|   ticks = round(0.0023 / 0.00001) = 230.
//|   (a) ticks * tvl = 230 * 1 = 230.
//|   commission per side 0: in 0, out 0.
//|   loss_per_lot = 230 + 0 + 0 = 230.
//|   base = balance 10000.
//|   target = floor(10000 * 2.5 / 100, 2) = floor(250) = 250.
//|   lot_raw = 250 / 230 = 1.08695652; lot = 0.01 + floor((lot_raw - 0.01)/0.01 + 1e-8)*0.01 = 1.08.
//|   risk = 1.08 * 230 = 248.4, 2.484% of base 10000.
//|   2.484% > 2%: PL_R_RISK_HIGH (CONFIRM).
//|   margin_needed = 1.08 * 1120.24 = 1209.8592, margin_free 10000.
//|   level at SL = (10000 - 248.4) / (0 + 1209.8592) * 100 = 806.011146%, limit so_so+10 = 60.
//|   spread = 6 points, money = 0.00006/0.00001 * 1 * 1.08 = 6.48.
//|   Verdict PL_CONFIRM, reason PL_R_RISK_HIGH.
//+------------------------------------------------------------------+
void PlVec28(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="percent_above_confirm";
   v.what="2.5% risk: actual 2.484% > confirm_above 2%: CONFIRM PL_R_RISK_HIGH";
   PlVecSymEURUSD(v.s);
   PlVecAccount(v.a,"USD",2,10000.0,10000.0,0.0,10000.0);
   PlVecInputs(v.in);
   v.in.sl=1.11794;
   v.in.risk_percent=2.5;
   v.in.comm.kind=PL_COMM_LOT_SIDE; v.in.comm.rate=0.0; v.in.comm.source=PL_COMMSRC_USER;
   v.in.calcprofit_ok=true; v.in.calcprofit_loss_1lot=230.0;
   //--- expected
   v.chk_prepare_ok=true; v.exp_prepare_ok=true;
   v.exp_plan_reason=PL_R_NONE;
   v.exp_side=PL_SIDE_BUY;
   v.exp_order_type=ORDER_TYPE_BUY;
   v.exp_exec=1.12024;
   v.exp_sl=1.11794;
   v.exp_ticks=230;
   v.exp_lpl_a=230.0;
   v.exp_lpl_price=230.0;
   v.exp_comm_in=0.0;
   v.exp_comm_out=0.0;
   v.exp_loss_per_lot=230.0;
   v.exp_lot=1.08;
   v.exp_risk_money=248.4;
   v.exp_risk_percent=2.484;
   v.exp_margin_needed=1209.8592;
   v.exp_spread_points=6.0;
   v.exp_spread_money=6.48;
   v.exp_verdict=PL_CONFIRM;
   v.exp_reason=PL_R_RISK_HIGH;
   v.exp_note=PL_R_NONE;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 29 sl_one_tick_limit
//| SL one tick from a Buy Limit entry: dist 0.00001 < max(0, 2*spread 0.00012, 3 ticks): PL_R_SL_TOO_CLOSE
//|   Compare price = entry 1.115.
//|   SL line 1.11499 < compare price: BUY.
//|   Order type ORDER_TYPE_BUY_LIMIT, exec = 1.115.
//|   dist = |exec - SL| = 0.00001.
//|   ticks = round(0.00001 / 0.00001) = 1.
//|   min dist = max(stops*point, 2*spread, 3*tick) = 0.00012 > 0.00001: PL_R_SL_TOO_CLOSE.
//|   (a) ticks * tvl = 1 * 1 = 1.
//|   commission per round 7: in 3.5, out 3.5.
//|   loss_per_lot = 1 + 3.5 + 3.5 = 8.
//|   base = balance 10000.
//|   target = floor(10000 * 1 / 100, 2) = floor(100) = 100.
//|   lot_raw = 100 / 8 = 12.5; lot = 0.01 + floor((lot_raw - 0.01)/0.01 + 1e-8)*0.01 = 12.5.
//|   risk = 12.5 * 8 = 100, 1% of base 10000.
//|   margin_needed = 12.5 * 1120.24 = 14003, margin_free 10000.
//|   margin_needed > margin_free: PL_R_MARGIN (BLOCK).
//|   level at SL = (10000 - 100) / (0 + 14003) * 100 = 70.699136%, limit so_so+10 = 60.
//|   spread = 6 points, money = 0.00006/0.00001 * 1 * 12.5 = 75.
//|   spread 0.00006 > 0.3 * dist 0.00001: PL_R_SPREAD_WIDE (WARN).
//|   Verdict PL_BLOCK, reason PL_R_SL_TOO_CLOSE.
//| QUESTION Q9: prepare ok and the numbers after SL_TOO_CLOSE are not defined by the spec (3.2: block, not divide); only plan reason and verdict are checked. Q8: the minimum for pendings literally includes 2*spread.
//+------------------------------------------------------------------+
void PlVec29(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="sl_one_tick_limit";
   v.what="SL one tick from a Buy Limit entry: dist 0.00001 < max(0, 2*spread 0.00012, 3 ticks): PL_R_SL_TOO_CLOSE";
   PlVecSymEURUSD(v.s);
   PlVecAccount(v.a,"USD",2,10000.0,10000.0,0.0,10000.0);
   PlVecInputs(v.in);
   v.in.kind=PL_KIND_LIMIT;
   v.in.entry=1.115;
   v.in.sl=1.11499;
   v.in.comm.kind=PL_COMM_LOT_ROUND; v.in.comm.rate=7.0; v.in.comm.source=PL_COMMSRC_USER;
   //--- expected
   v.exp_plan_reason=PL_R_SL_TOO_CLOSE;
   v.exp_verdict=PL_BLOCK;
   v.exp_reason=PL_R_SL_TOO_CLOSE;
   v.exp_note=PL_R_NONE;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 30 sl_too_close_market
//| Buy Market with SL one tick below Bid: dist = Ask - SL = 7 ticks < 2*spread 12 ticks: PL_R_SL_TOO_CLOSE
//|   Compare price = mid (Bid+Ask)/2 = (1.12018+1.12024)/2 = 1.12021.
//|   SL line 1.12017 < compare price: BUY.
//|   Order type ORDER_TYPE_BUY, exec = 1.12024.
//|   dist = Ask - SL = 0.00007.
//|   ticks = round(0.00007 / 0.00001) = 7.
//|   min dist = max(stops*point, 2*spread, 3*tick) = 0.00012 > 0.00007: PL_R_SL_TOO_CLOSE.
//|   (a) ticks * tvl = 7 * 1 = 7.
//|   commission per round 7: in 3.5, out 3.5.
//|   loss_per_lot = 7 + 3.5 + 3.5 = 14.
//|   base = balance 10000.
//|   target = floor(10000 * 1 / 100, 2) = floor(100) = 100.
//|   lot_raw = 100 / 14 = 7.14285714; lot = 0.01 + floor((lot_raw - 0.01)/0.01 + 1e-8)*0.01 = 7.14.
//|   risk = 7.14 * 14 = 99.96, 0.9996% of base 10000.
//|   margin_needed = 7.14 * 1120.24 = 7998.5136, margin_free 10000.
//|   level at SL = (10000 - 99.96) / (0 + 7998.5136) * 100 = 123.773497%, limit so_so+10 = 60.
//|   spread = 6 points, money = 0.00006/0.00001 * 1 * 7.14 = 42.84.
//|   spread 0.00006 > 0.3 * dist 0.00007: PL_R_SPREAD_WIDE (WARN).
//|   Verdict PL_BLOCK, reason PL_R_SL_TOO_CLOSE.
//+------------------------------------------------------------------+
void PlVec30(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="sl_too_close_market";
   v.what="Buy Market with SL one tick below Bid: dist = Ask - SL = 7 ticks < 2*spread 12 ticks: PL_R_SL_TOO_CLOSE";
   PlVecSymEURUSD(v.s);
   PlVecAccount(v.a,"USD",2,10000.0,10000.0,0.0,10000.0);
   PlVecInputs(v.in);
   v.in.sl=1.12017;
   v.in.comm.kind=PL_COMM_LOT_ROUND; v.in.comm.rate=7.0; v.in.comm.source=PL_COMMSRC_USER;
   //--- expected
   v.exp_plan_reason=PL_R_SL_TOO_CLOSE;
   v.exp_verdict=PL_BLOCK;
   v.exp_reason=PL_R_SL_TOO_CLOSE;
   v.exp_note=PL_R_NONE;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 31 sl_wrong_side_mid
//| SL exactly on the mid price (Bid+Ask)/2 = 1.12021: side unknown, PL_R_SL_WRONG_SIDE
//|   Compare price = mid (Bid+Ask)/2 = (1.12018+1.12024)/2 = 1.12021.
//|   Prepare: PL_R_SL_WRONG_SIDE (SL equals the compare price, side unknown), ok=false.
//|   Verdict PL_BLOCK, reason PL_R_SL_WRONG_SIDE.
//+------------------------------------------------------------------+
void PlVec31(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="sl_wrong_side_mid";
   v.what="SL exactly on the mid price (Bid+Ask)/2 = 1.12021: side unknown, PL_R_SL_WRONG_SIDE";
   PlVecSymEURUSD(v.s);
   PlVecAccount(v.a,"USD",2,10000.0,10000.0,0.0,10000.0);
   PlVecInputs(v.in);
   v.in.sl=1.12021;
   v.in.comm.kind=PL_COMM_LOT_ROUND; v.in.comm.rate=7.0; v.in.comm.source=PL_COMMSRC_USER;
   //--- expected
   v.chk_prepare_ok=true; v.exp_prepare_ok=false;
   v.exp_plan_reason=PL_R_SL_WRONG_SIDE;
   v.exp_verdict=PL_BLOCK;
   v.exp_reason=PL_R_SL_WRONG_SIDE;
   v.exp_note=PL_R_NONE;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 32 zero_tick_value
//| tick_value_loss 0: PL_R_NO_SYMBOL_DATA, nothing to compute
//|   Prepare: PL_R_NO_SYMBOL_DATA (tick_size, tick_value_loss or contract is 0), ok=false.
//|   Verdict PL_BLOCK, reason PL_R_NO_SYMBOL_DATA.
//+------------------------------------------------------------------+
void PlVec32(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="zero_tick_value";
   v.what="tick_value_loss 0: PL_R_NO_SYMBOL_DATA, nothing to compute";
   PlVecSymEURUSD(v.s);
   v.s.tick_value_loss=0.0;
   v.s.tick_value_profit=0.0;
   PlVecAccount(v.a,"USD",2,10000.0,10000.0,0.0,10000.0);
   PlVecInputs(v.in);
   v.in.sl=1.11824;
   v.in.comm.kind=PL_COMM_LOT_ROUND; v.in.comm.rate=7.0; v.in.comm.source=PL_COMMSRC_USER;
   //--- expected
   v.chk_prepare_ok=true; v.exp_prepare_ok=false;
   v.exp_plan_reason=PL_R_NO_SYMBOL_DATA;
   v.exp_verdict=PL_BLOCK;
   v.exp_reason=PL_R_NO_SYMBOL_DATA;
   v.exp_note=PL_R_NONE;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 33 zero_quote
//| Bid 0 (no quote): PL_R_NO_QUOTE, nothing to compute
//|   Prepare: PL_R_NO_QUOTE (bid or ask is 0), ok=false.
//|   Verdict PL_BLOCK, reason PL_R_NO_QUOTE.
//+------------------------------------------------------------------+
void PlVec33(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="zero_quote";
   v.what="Bid 0 (no quote): PL_R_NO_QUOTE, nothing to compute";
   PlVecSymEURUSD(v.s);
   v.s.bid=0.0;
   PlVecAccount(v.a,"USD",2,10000.0,10000.0,0.0,10000.0);
   PlVecInputs(v.in);
   v.in.sl=1.11824;
   v.in.comm.kind=PL_COMM_LOT_ROUND; v.in.comm.rate=7.0; v.in.comm.source=PL_COMMSRC_USER;
   //--- expected
   v.chk_prepare_ok=true; v.exp_prepare_ok=false;
   v.exp_plan_reason=PL_R_NO_QUOTE;
   v.exp_verdict=PL_BLOCK;
   v.exp_reason=PL_R_NO_QUOTE;
   v.exp_note=PL_R_NONE;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 34 paths_disagree
//| XAUUSD: path (a) gives 500, OrderCalcProfit (c) 510: 2% apart: BLOCK, numbers by the worst (510)
//|   Compare price = mid (Bid+Ask)/2 = (4195.09+4195.52)/2 = 4195.305.
//|   SL line 4190.52 < compare price: BUY.
//|   Order type ORDER_TYPE_BUY, exec = 4195.52.
//|   dist = Ask - SL = 5.
//|   ticks = round(5 / 0.01) = 500.
//|   (a) ticks * tvl = 500 * 1 = 500.
//|   (c) OrderCalcProfit = 510.
//|   worst = 510 (the larger path).
//|   |a - c| = 10 > 1% of 510 + 0.005 = 5.105: PL_R_PATHS_DISAGREE (BLOCK), numbers by the worst.
//|   commission per side 0: in 0, out 0.
//|   loss_per_lot = 510 + 0 + 0 = 510.
//|   base = balance 10000.
//|   target = floor(10000 * 1 / 100, 2) = floor(100) = 100.
//|   lot_raw = 100 / 510 = 0.19607843; lot = 0.01 + floor((lot_raw - 0.01)/0.01 + 1e-8)*0.01 = 0.19.
//|   risk = 0.19 * 510 = 96.9, 0.969% of base 10000.
//|   margin_needed = 0.19 * 8391.04 = 1594.2976, margin_free 10000.
//|   level at SL = (10000 - 96.9) / (0 + 1594.2976) * 100 = 621.157556%, limit so_so+10 = 60.
//|   spread = 43 points, money = 0.43/0.01 * 1 * 0.19 = 8.17.
//|   Verdict PL_BLOCK, reason PL_R_PATHS_DISAGREE.
//+------------------------------------------------------------------+
void PlVec34(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="paths_disagree";
   v.what="XAUUSD: path (a) gives 500, OrderCalcProfit (c) 510: 2% apart: BLOCK, numbers by the worst (510)";
   PlVecSymXAUUSD(v.s);
   PlVecAccount(v.a,"USD",2,10000.0,10000.0,0.0,10000.0);
   PlVecInputs(v.in);
   v.in.sl=4190.52;
   v.in.calcprofit_ok=true;
   v.in.calcprofit_loss_1lot=510.0;
   v.in.comm.kind=PL_COMM_LOT_SIDE; v.in.comm.rate=0.0; v.in.comm.source=PL_COMMSRC_USER;
   //--- expected
   v.chk_prepare_ok=true; v.exp_prepare_ok=true;
   v.exp_plan_reason=PL_R_NONE;
   v.exp_side=PL_SIDE_BUY;
   v.exp_order_type=ORDER_TYPE_BUY;
   v.exp_exec=4195.52;
   v.exp_sl=4190.52;
   v.exp_ticks=500;
   v.exp_lpl_a=500.0;
   v.exp_lpl_price=510.0;
   v.exp_comm_in=0.0;
   v.exp_comm_out=0.0;
   v.exp_loss_per_lot=510.0;
   v.exp_lot=0.19;
   v.exp_risk_money=96.9;
   v.exp_risk_percent=0.969;
   v.exp_margin_needed=1594.2976;
   v.exp_spread_points=43.0;
   v.exp_spread_money=8.17;
   v.exp_verdict=PL_BLOCK;
   v.exp_reason=PL_R_PATHS_DISAGREE;
   v.exp_note=PL_R_NONE;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 35 paths_agree_worst
//| XAUUSD: (a) 500, (c) 504, 0.8% apart: OK, the worst path 504 is used
//|   Compare price = mid (Bid+Ask)/2 = (4195.09+4195.52)/2 = 4195.305.
//|   SL line 4190.52 < compare price: BUY.
//|   Order type ORDER_TYPE_BUY, exec = 4195.52.
//|   dist = Ask - SL = 5.
//|   ticks = round(5 / 0.01) = 500.
//|   (a) ticks * tvl = 500 * 1 = 500.
//|   (c) OrderCalcProfit = 504.
//|   worst = 504 (the larger path), |a - c| = 4 <= 1% of 504 + 0.005 = 5.045: the paths agree.
//|   commission per side 0: in 0, out 0.
//|   loss_per_lot = 504 + 0 + 0 = 504.
//|   base = balance 10000.
//|   target = floor(10000 * 1 / 100, 2) = floor(100) = 100.
//|   lot_raw = 100 / 504 = 0.1984127; lot = 0.01 + floor((lot_raw - 0.01)/0.01 + 1e-8)*0.01 = 0.19.
//|   risk = 0.19 * 504 = 95.76, 0.9576% of base 10000.
//|   margin_needed = 0.19 * 8391.04 = 1594.2976, margin_free 10000.
//|   level at SL = (10000 - 95.76) / (0 + 1594.2976) * 100 = 621.22906%, limit so_so+10 = 60.
//|   spread = 43 points, money = 0.43/0.01 * 1 * 0.19 = 8.17.
//|   Verdict PL_OK, reason PL_R_NONE.
//+------------------------------------------------------------------+
void PlVec35(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="paths_agree_worst";
   v.what="XAUUSD: (a) 500, (c) 504, 0.8% apart: OK, the worst path 504 is used";
   PlVecSymXAUUSD(v.s);
   PlVecAccount(v.a,"USD",2,10000.0,10000.0,0.0,10000.0);
   PlVecInputs(v.in);
   v.in.sl=4190.52;
   v.in.calcprofit_ok=true;
   v.in.calcprofit_loss_1lot=504.0;
   v.in.comm.kind=PL_COMM_LOT_SIDE; v.in.comm.rate=0.0; v.in.comm.source=PL_COMMSRC_USER;
   //--- expected
   v.chk_prepare_ok=true; v.exp_prepare_ok=true;
   v.exp_plan_reason=PL_R_NONE;
   v.exp_side=PL_SIDE_BUY;
   v.exp_order_type=ORDER_TYPE_BUY;
   v.exp_exec=4195.52;
   v.exp_sl=4190.52;
   v.exp_ticks=500;
   v.exp_lpl_a=500.0;
   v.exp_lpl_price=504.0;
   v.exp_comm_in=0.0;
   v.exp_comm_out=0.0;
   v.exp_loss_per_lot=504.0;
   v.exp_lot=0.19;
   v.exp_risk_money=95.76;
   v.exp_risk_percent=0.9576;
   v.exp_margin_needed=1594.2976;
   v.exp_spread_points=43.0;
   v.exp_spread_money=8.17;
   v.exp_verdict=PL_OK;
   v.exp_reason=PL_R_NONE;
   v.exp_note=PL_R_NONE;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 36 no_calcprofit_blocks
//| GER40 (EUR) on a USD account with an SL but no OrderCalcProfit result: path (c) is mandatory, PL_R_NO_CALC
//|   Compare price = mid (Bid+Ask)/2 = (19000+19001)/2 = 19000.5.
//|   SL line 18951 < compare price: BUY.
//|   Order type ORDER_TYPE_BUY, exec = 19001.
//|   dist = Ask - SL = 50.
//|   ticks = round(50 / 0.5) = 100.
//|   (a) ticks * tvl = 100 * 0.55 = 55.
//|   (c) the terminal gave no OrderCalcProfit: PL_R_NO_CALC (the block lifts by itself when a later recalculation has it).
//|   commission per side 0: in 0, out 0.
//|   loss_per_lot = 55 + 0 + 0 = 55.
//|   base = balance 10000.
//|   target = floor(10000 * 1 / 100, 2) = floor(100) = 100.
//|   lot_raw = 100 / 55 = 1.81818182; lot = 0.1 + floor((lot_raw - 0.1)/0.1 + 1e-8)*0.1 = 1.8.
//|   risk = 1.8 * 55 = 99, 0.99% of base 10000.
//|   margin_needed = 1.8 * 1045.06 = 1881.108, margin_free 10000.
//|   level at SL = (10000 - 99) / (0 + 1881.108) * 100 = 526.338732%, limit so_so+10 = 60.
//|   spread = 10 points, money = 1/0.5 * 0.55 * 1.8 = 1.98.
//|   lpl_price = max(a, c) = 55. Verdict PL_BLOCK, reason PL_R_NO_CALC.
//+------------------------------------------------------------------+
void PlVec36(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="no_calcprofit_blocks";
   v.what="GER40 (EUR) on a USD account with an SL but no OrderCalcProfit result: PL_BLOCK PL_R_NO_CALC";
   PlVecSymGER40(v.s);
   PlVecAccount(v.a,"USD",2,10000.0,10000.0,0.0,10000.0);
   PlVecInputs(v.in);
   v.in.sl=18951.0;
   v.in.comm.kind=PL_COMM_LOT_SIDE; v.in.comm.rate=0.0; v.in.comm.source=PL_COMMSRC_USER;
   //--- expected
   v.chk_prepare_ok=true; v.exp_prepare_ok=true;
   v.exp_plan_reason=PL_R_NONE;
   v.exp_side=PL_SIDE_BUY;
   v.exp_order_type=ORDER_TYPE_BUY;
   v.exp_exec=19001.0;
   v.exp_sl=18951.0;
   v.exp_ticks=100;
   v.exp_lpl_a=55.0;
   v.exp_lpl_price=55.0;
   v.exp_verdict=PL_BLOCK;
   v.exp_reason=PL_R_NO_CALC;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 37 comm_unknown
//| Commission UNKNOWN: counted as 0, note PL_R_COMM_UNKNOWN, SL 23 pips
//|   Compare price = mid (Bid+Ask)/2 = (1.12018+1.12024)/2 = 1.12021.
//|   SL line 1.11794 < compare price: BUY.
//|   Order type ORDER_TYPE_BUY, exec = 1.12024.
//|   dist = Ask - SL = 0.0023.
//|   ticks = round(0.0023 / 0.00001) = 230.
//|   (a) ticks * tvl = 230 * 1 = 230.
//|   commission UNKNOWN: 0, note PL_R_COMM_UNKNOWN.
//|   loss_per_lot = 230 + 0 + 0 = 230.
//|   base = balance 10000.
//|   target = floor(10000 * 1 / 100, 2) = floor(100) = 100.
//|   lot_raw = 100 / 230 = 0.43478261; lot = 0.01 + floor((lot_raw - 0.01)/0.01 + 1e-8)*0.01 = 0.43.
//|   risk = 0.43 * 230 = 98.9, 0.989% of base 10000.
//|   margin_needed = 0.43 * 1120.24 = 481.7032, margin_free 10000.
//|   level at SL = (10000 - 98.9) / (0 + 481.7032) * 100 = 2055.435795%, limit so_so+10 = 60.
//|   spread = 6 points, money = 0.00006/0.00001 * 1 * 0.43 = 2.58.
//|   Verdict PL_OK, reason PL_R_NONE, note PL_R_COMM_UNKNOWN.
//| QUESTION Q1: note only, verdict PL_OK literal.
//+------------------------------------------------------------------+
void PlVec37(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="comm_unknown";
   v.what="Commission UNKNOWN: counted as 0, note PL_R_COMM_UNKNOWN, SL 23 pips";
   PlVecSymEURUSD(v.s);
   PlVecAccount(v.a,"USD",2,10000.0,10000.0,0.0,10000.0);
   PlVecInputs(v.in);
   v.in.sl=1.11794;
   v.in.comm.kind=PL_COMM_UNKNOWN; v.in.comm.rate=0.0; v.in.comm.source=PL_COMMSRC_NONE;
   v.in.calcprofit_ok=true; v.in.calcprofit_loss_1lot=230.0;
   //--- expected
   v.chk_prepare_ok=true; v.exp_prepare_ok=true;
   v.exp_plan_reason=PL_R_NONE;
   v.exp_side=PL_SIDE_BUY;
   v.exp_order_type=ORDER_TYPE_BUY;
   v.exp_exec=1.12024;
   v.exp_sl=1.11794;
   v.exp_ticks=230;
   v.exp_lpl_a=230.0;
   v.exp_lpl_price=230.0;
   v.exp_comm_in=0.0;
   v.exp_comm_out=0.0;
   v.exp_loss_per_lot=230.0;
   v.exp_lot=0.43;
   v.exp_risk_money=98.9;
   v.exp_risk_percent=0.989;
   v.exp_margin_needed=481.7032;
   v.exp_spread_points=6.0;
   v.exp_spread_money=2.58;
   v.exp_verdict=PL_OK;
   v.exp_reason=PL_R_NONE;
   v.exp_note=PL_R_COMM_UNKNOWN;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 38 comm_percent_conv
//| Percent commission with a currency rate: GER40 (EUR) on a USD account, 0.01% per side, k = tvl/(tick*contract) = 0.55/0.5 = 1.10
//|   Compare price = mid (Bid+Ask)/2 = (19000+19001)/2 = 19000.5.
//|   SL line 18951 < compare price: BUY.
//|   Order type ORDER_TYPE_BUY, exec = 19001.
//|   dist = Ask - SL = 50.
//|   ticks = round(50 / 0.5) = 100.
//|   (a) ticks * tvl = 100 * 0.55 = 55.
//|   (c) OrderCalcProfit = 55.
//|   worst = 55 (the larger path), the paths agree.
//|   percent 0.01% per side, k = 1.1: in = 19001 * 1 * 0.01/100 * k = 2.09011; out = 18951 * 1 * 0.01/100 * k = 2.08461.
//|   loss_per_lot = 55 + 2.09011 + 2.08461 = 59.17472.
//|   base = balance 10000.
//|   target = floor(10000 * 1 / 100, 2) = floor(100) = 100.
//|   lot_raw = 100 / 59.17472 = 1.68991083; lot = 0.1 + floor((lot_raw - 0.1)/0.1 + 1e-8)*0.1 = 1.6.
//|   risk = 1.6 * 59.17472 = 94.679552, 0.94679552% of base 10000.
//|   margin_needed = 1.6 * 1045.06 = 1672.096, margin_free 10000.
//|   level at SL = (10000 - 94.679552) / (0 + 1672.096) * 100 = 592.389459%, limit so_so+10 = 60.
//|   spread = 10 points, money = 1/0.5 * 0.55 * 1.6 = 1.76.
//|   Verdict PL_OK, reason PL_R_NONE.
//+------------------------------------------------------------------+
void PlVec38(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="comm_percent_conv";
   v.what="Percent commission with a currency rate: GER40 (EUR) on a USD account, 0.01% per side, k = tvl/(tick*contract) = 0.55/0.5 = 1.10";
   PlVecSymGER40(v.s);
   PlVecAccount(v.a,"USD",2,10000.0,10000.0,0.0,10000.0);
   PlVecInputs(v.in);
   v.in.sl=18951.0;
   v.in.comm.kind=PL_COMM_PERCENT_SIDE; v.in.comm.rate=0.01; v.in.comm.source=PL_COMMSRC_USER;
   v.in.calcprofit_ok=true; v.in.calcprofit_loss_1lot=55.0;
   //--- expected
   v.chk_prepare_ok=true; v.exp_prepare_ok=true;
   v.exp_plan_reason=PL_R_NONE;
   v.exp_side=PL_SIDE_BUY;
   v.exp_order_type=ORDER_TYPE_BUY;
   v.exp_exec=19001.0;
   v.exp_sl=18951.0;
   v.exp_ticks=100;
   v.exp_lpl_a=55.0;
   v.exp_lpl_price=55.0;
   v.exp_comm_in=2.09011;
   v.exp_comm_out=2.08461;
   v.exp_loss_per_lot=59.17472;
   v.exp_lot=1.6;
   v.exp_risk_money=94.679552;
   v.exp_risk_percent=0.94679552;
   v.exp_margin_needed=1672.096;
   v.exp_spread_points=10.0;
   v.exp_spread_money=1.76;
   v.exp_verdict=PL_OK;
   v.exp_reason=PL_R_NONE;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 39 comm_percent_k_tickvalue
//| Percent commission with k from tick value: USDJPY on a USD account, 0.002% per side, k = tvl/(tick_size*contract)
//|   Compare price = mid (Bid+Ask)/2 = (158.288+158.311)/2 = 158.2995.
//|   SL line 157.988 < compare price: BUY.
//|   Order type ORDER_TYPE_BUY, exec = 158.311.
//|   dist = Ask - SL = 0.323.
//|   ticks = round(0.323 / 0.001) = 323.
//|   (a) account = base by data: ticks * tick * contract / SL = 323 * 0.001 * 100000 / 157.988 = 204.44590728.
//|   (c) OrderCalcProfit = 204.44590728.
//|   percent 0.002% per side, k = tvl/(tick_size*contract) = 0.63175983/(0.001*100000) = 0.0063175983: in = 158.311 * 100000 * 0.002/100 * k = 2.00029061; out = 157.988 * 100000 * 0.002/100 * k = 1.99620944.
//|   loss_per_lot = 204.44590728 + 2.00029061 + 1.99620944 = 208.44240733.
//|   base = balance 10000.
//|   target = floor(10000 * 1 / 100, 2) = floor(100) = 100.
//|   lot_raw = 100 / 208.44240733 = 0.47974883; lot = 0.01 + floor((lot_raw - 0.01)/0.01 + 1e-8)*0.01 = 0.47.
//|   risk = 0.47 * 208.44240733 = 97.967931, 0.97967931% of base 10000.
//|   margin_needed = 0.47 * 1000 = 470, margin_free 10000.
//|   level at SL = (10000 - 97.967931) / (0 + 470) * 100 = 2106.812363%, limit so_so+10 = 60.
//|   spread = 23 points, money = 0.023/0.001 * 0.63175983 * 0.47 = 6.82932376.
//|   Verdict PL_OK, reason PL_R_NONE.
//+------------------------------------------------------------------+
void PlVec39(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="comm_percent_k_tickvalue";
   v.what="Percent commission with k from tick value: USDJPY on a USD account, 0.002% per side, k = tvl/(tick_size*contract)";
   PlVecSymUSDJPY(v.s);
   PlVecAccount(v.a,"USD",2,10000.0,10000.0,0.0,10000.0);
   PlVecInputs(v.in);
   v.in.sl=157.988;
   v.in.comm.kind=PL_COMM_PERCENT_SIDE; v.in.comm.rate=0.002; v.in.comm.source=PL_COMMSRC_USER;
   v.in.calcprofit_ok=true; v.in.calcprofit_loss_1lot=204.44590728;
   //--- expected
   v.chk_prepare_ok=true; v.exp_prepare_ok=true;
   v.exp_plan_reason=PL_R_NONE;
   v.exp_side=PL_SIDE_BUY;
   v.exp_order_type=ORDER_TYPE_BUY;
   v.exp_exec=158.311;
   v.exp_sl=157.988;
   v.exp_ticks=323;
   v.exp_lpl_a=204.44590728;
   v.exp_lpl_price=204.44590728;
   v.exp_comm_in=2.00029061;
   v.exp_comm_out=1.99620944;
   v.exp_loss_per_lot=208.44240733;
   v.exp_lot=0.47;
   v.exp_risk_money=97.96793145;
   v.exp_risk_percent=0.97967931;
   v.exp_margin_needed=470.0;
   v.exp_spread_points=23.0;
   v.exp_spread_money=6.82932376;
   v.exp_verdict=PL_OK;
   v.exp_reason=PL_R_NONE;
   v.exp_note=PL_R_NONE;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 40 buy_limit
//| Buy Limit at 1.11800 (below Ask), SL 1.11600: exec = entry, dist 200 ticks without spread, $2.50 per side
//|   Compare price = entry 1.118.
//|   SL line 1.116 < compare price: BUY.
//|   Order type ORDER_TYPE_BUY_LIMIT, exec = 1.118.
//|   dist = |exec - SL| = 0.002.
//|   ticks = round(0.002 / 0.00001) = 200.
//|   (a) ticks * tvl = 200 * 1 = 200.
//|   commission per side 2.5: in 2.5, out 2.5.
//|   loss_per_lot = 200 + 2.5 + 2.5 = 205.
//|   base = balance 10000.
//|   target = floor(10000 * 1 / 100, 2) = floor(100) = 100.
//|   lot_raw = 100 / 205 = 0.48780488; lot = 0.01 + floor((lot_raw - 0.01)/0.01 + 1e-8)*0.01 = 0.48.
//|   risk = 0.48 * 205 = 98.4, 0.984% of base 10000.
//|   margin_needed = 0.48 * 1120.24 = 537.7152, margin_free 10000.
//|   level at SL = (10000 - 98.4) / (0 + 537.7152) * 100 = 1841.420886%, limit so_so+10 = 60.
//|   spread = 6 points, money = 0.00006/0.00001 * 1 * 0.48 = 2.88.
//|   Verdict PL_OK, reason PL_R_NONE.
//+------------------------------------------------------------------+
void PlVec40(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="buy_limit";
   v.what="Buy Limit at 1.11800 (below Ask), SL 1.11600: exec = entry, dist 200 ticks without spread, $2.50 per side";
   PlVecSymEURUSD(v.s);
   PlVecAccount(v.a,"USD",2,10000.0,10000.0,0.0,10000.0);
   PlVecInputs(v.in);
   v.in.kind=PL_KIND_LIMIT;
   v.in.entry=1.118;
   v.in.sl=1.116;
   v.in.comm.kind=PL_COMM_LOT_SIDE; v.in.comm.rate=2.5; v.in.comm.source=PL_COMMSRC_USER;
   v.in.calcprofit_ok=true; v.in.calcprofit_loss_1lot=200.0;
   //--- expected
   v.chk_prepare_ok=true; v.exp_prepare_ok=true;
   v.exp_plan_reason=PL_R_NONE;
   v.exp_side=PL_SIDE_BUY;
   v.exp_order_type=ORDER_TYPE_BUY_LIMIT;
   v.exp_exec=1.118;
   v.exp_sl=1.116;
   v.exp_ticks=200;
   v.exp_lpl_a=200.0;
   v.exp_lpl_price=200.0;
   v.exp_comm_in=2.5;
   v.exp_comm_out=2.5;
   v.exp_loss_per_lot=205.0;
   v.exp_lot=0.48;
   v.exp_risk_money=98.4;
   v.exp_risk_percent=0.984;
   v.exp_margin_needed=537.7152;
   v.exp_spread_points=6.0;
   v.exp_spread_money=2.88;
   v.exp_verdict=PL_OK;
   v.exp_reason=PL_R_NONE;
   v.exp_note=PL_R_NONE;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 41 sell_limit
//| Sell Limit at 1.12300 (above Bid), SL 1.12500
//|   Compare price = entry 1.123.
//|   SL line 1.125 > compare price: SELL.
//|   Order type ORDER_TYPE_SELL_LIMIT, exec = 1.123.
//|   dist = |exec - SL| = 0.002.
//|   ticks = round(0.002 / 0.00001) = 200.
//|   (a) ticks * tvl = 200 * 1 = 200.
//|   commission per side 2.5: in 2.5, out 2.5.
//|   loss_per_lot = 200 + 2.5 + 2.5 = 205.
//|   base = balance 10000.
//|   target = floor(10000 * 1 / 100, 2) = floor(100) = 100.
//|   lot_raw = 100 / 205 = 0.48780488; lot = 0.01 + floor((lot_raw - 0.01)/0.01 + 1e-8)*0.01 = 0.48.
//|   risk = 0.48 * 205 = 98.4, 0.984% of base 10000.
//|   margin_needed = 0.48 * 1120.18 = 537.6864, margin_free 10000.
//|   level at SL = (10000 - 98.4) / (0 + 537.6864) * 100 = 1841.519518%, limit so_so+10 = 60.
//|   spread = 6 points, money = 0.00006/0.00001 * 1 * 0.48 = 2.88.
//|   Verdict PL_OK, reason PL_R_NONE.
//+------------------------------------------------------------------+
void PlVec41(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="sell_limit";
   v.what="Sell Limit at 1.12300 (above Bid), SL 1.12500";
   PlVecSymEURUSD(v.s);
   PlVecAccount(v.a,"USD",2,10000.0,10000.0,0.0,10000.0);
   PlVecInputs(v.in);
   v.in.kind=PL_KIND_LIMIT;
   v.in.entry=1.123;
   v.in.sl=1.125;
   v.in.comm.kind=PL_COMM_LOT_SIDE; v.in.comm.rate=2.5; v.in.comm.source=PL_COMMSRC_USER;
   v.in.calcprofit_ok=true; v.in.calcprofit_loss_1lot=200.0;
   //--- expected
   v.chk_prepare_ok=true; v.exp_prepare_ok=true;
   v.exp_plan_reason=PL_R_NONE;
   v.exp_side=PL_SIDE_SELL;
   v.exp_order_type=ORDER_TYPE_SELL_LIMIT;
   v.exp_exec=1.123;
   v.exp_sl=1.125;
   v.exp_ticks=200;
   v.exp_lpl_a=200.0;
   v.exp_lpl_price=200.0;
   v.exp_comm_in=2.5;
   v.exp_comm_out=2.5;
   v.exp_loss_per_lot=205.0;
   v.exp_lot=0.48;
   v.exp_risk_money=98.4;
   v.exp_risk_percent=0.984;
   v.exp_margin_needed=537.6864;
   v.exp_spread_points=6.0;
   v.exp_spread_money=2.88;
   v.exp_verdict=PL_OK;
   v.exp_reason=PL_R_NONE;
   v.exp_note=PL_R_NONE;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 42 buy_stop
//| Buy Stop at 1.12300 (above Ask), SL 1.12100
//|   Compare price = entry 1.123.
//|   SL line 1.121 < compare price: BUY.
//|   Order type ORDER_TYPE_BUY_STOP, exec = 1.123.
//|   dist = |exec - SL| = 0.002.
//|   ticks = round(0.002 / 0.00001) = 200.
//|   (a) ticks * tvl = 200 * 1 = 200.
//|   commission per side 2.5: in 2.5, out 2.5.
//|   loss_per_lot = 200 + 2.5 + 2.5 = 205.
//|   base = balance 10000.
//|   target = floor(10000 * 1 / 100, 2) = floor(100) = 100.
//|   lot_raw = 100 / 205 = 0.48780488; lot = 0.01 + floor((lot_raw - 0.01)/0.01 + 1e-8)*0.01 = 0.48.
//|   risk = 0.48 * 205 = 98.4, 0.984% of base 10000.
//|   margin_needed = 0.48 * 1120.24 = 537.7152, margin_free 10000.
//|   level at SL = (10000 - 98.4) / (0 + 537.7152) * 100 = 1841.420886%, limit so_so+10 = 60.
//|   spread = 6 points, money = 0.00006/0.00001 * 1 * 0.48 = 2.88.
//|   Verdict PL_OK, reason PL_R_NONE.
//+------------------------------------------------------------------+
void PlVec42(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="buy_stop";
   v.what="Buy Stop at 1.12300 (above Ask), SL 1.12100";
   PlVecSymEURUSD(v.s);
   PlVecAccount(v.a,"USD",2,10000.0,10000.0,0.0,10000.0);
   PlVecInputs(v.in);
   v.in.kind=PL_KIND_STOP;
   v.in.entry=1.123;
   v.in.sl=1.121;
   v.in.comm.kind=PL_COMM_LOT_SIDE; v.in.comm.rate=2.5; v.in.comm.source=PL_COMMSRC_USER;
   v.in.calcprofit_ok=true; v.in.calcprofit_loss_1lot=200.0;
   //--- expected
   v.chk_prepare_ok=true; v.exp_prepare_ok=true;
   v.exp_plan_reason=PL_R_NONE;
   v.exp_side=PL_SIDE_BUY;
   v.exp_order_type=ORDER_TYPE_BUY_STOP;
   v.exp_exec=1.123;
   v.exp_sl=1.121;
   v.exp_ticks=200;
   v.exp_lpl_a=200.0;
   v.exp_lpl_price=200.0;
   v.exp_comm_in=2.5;
   v.exp_comm_out=2.5;
   v.exp_loss_per_lot=205.0;
   v.exp_lot=0.48;
   v.exp_risk_money=98.4;
   v.exp_risk_percent=0.984;
   v.exp_margin_needed=537.7152;
   v.exp_spread_points=6.0;
   v.exp_spread_money=2.88;
   v.exp_verdict=PL_OK;
   v.exp_reason=PL_R_NONE;
   v.exp_note=PL_R_NONE;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 43 sell_stop
//| Sell Stop at 1.11800 (below Bid), SL 1.12000
//|   Compare price = entry 1.118.
//|   SL line 1.12 > compare price: SELL.
//|   Order type ORDER_TYPE_SELL_STOP, exec = 1.118.
//|   dist = |exec - SL| = 0.002.
//|   ticks = round(0.002 / 0.00001) = 200.
//|   (a) ticks * tvl = 200 * 1 = 200.
//|   commission per side 2.5: in 2.5, out 2.5.
//|   loss_per_lot = 200 + 2.5 + 2.5 = 205.
//|   base = balance 10000.
//|   target = floor(10000 * 1 / 100, 2) = floor(100) = 100.
//|   lot_raw = 100 / 205 = 0.48780488; lot = 0.01 + floor((lot_raw - 0.01)/0.01 + 1e-8)*0.01 = 0.48.
//|   risk = 0.48 * 205 = 98.4, 0.984% of base 10000.
//|   margin_needed = 0.48 * 1120.18 = 537.6864, margin_free 10000.
//|   level at SL = (10000 - 98.4) / (0 + 537.6864) * 100 = 1841.519518%, limit so_so+10 = 60.
//|   spread = 6 points, money = 0.00006/0.00001 * 1 * 0.48 = 2.88.
//|   Verdict PL_OK, reason PL_R_NONE.
//+------------------------------------------------------------------+
void PlVec43(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="sell_stop";
   v.what="Sell Stop at 1.11800 (below Bid), SL 1.12000";
   PlVecSymEURUSD(v.s);
   PlVecAccount(v.a,"USD",2,10000.0,10000.0,0.0,10000.0);
   PlVecInputs(v.in);
   v.in.kind=PL_KIND_STOP;
   v.in.entry=1.118;
   v.in.sl=1.12;
   v.in.comm.kind=PL_COMM_LOT_SIDE; v.in.comm.rate=2.5; v.in.comm.source=PL_COMMSRC_USER;
   v.in.calcprofit_ok=true; v.in.calcprofit_loss_1lot=200.0;
   //--- expected
   v.chk_prepare_ok=true; v.exp_prepare_ok=true;
   v.exp_plan_reason=PL_R_NONE;
   v.exp_side=PL_SIDE_SELL;
   v.exp_order_type=ORDER_TYPE_SELL_STOP;
   v.exp_exec=1.118;
   v.exp_sl=1.12;
   v.exp_ticks=200;
   v.exp_lpl_a=200.0;
   v.exp_lpl_price=200.0;
   v.exp_comm_in=2.5;
   v.exp_comm_out=2.5;
   v.exp_loss_per_lot=205.0;
   v.exp_lot=0.48;
   v.exp_risk_money=98.4;
   v.exp_risk_percent=0.984;
   v.exp_margin_needed=537.6864;
   v.exp_spread_points=6.0;
   v.exp_spread_money=2.88;
   v.exp_verdict=PL_OK;
   v.exp_reason=PL_R_NONE;
   v.exp_note=PL_R_NONE;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 44 buy_stop_limit
//| Buy Stop Limit: trigger 1.12300 > Ask, limit 1.12250 <= trigger, SL 1.12050: exec = limit, side by the limit price
//|   Compare price = limit 1.1225.
//|   SL line 1.1205 < compare price: BUY.
//|   Order type ORDER_TYPE_BUY_STOP_LIMIT, exec = 1.1225.
//|   dist = |exec - SL| = 0.002.
//|   ticks = round(0.002 / 0.00001) = 200.
//|   (a) ticks * tvl = 200 * 1 = 200.
//|   commission per side 2.5: in 2.5, out 2.5.
//|   loss_per_lot = 200 + 2.5 + 2.5 = 205.
//|   base = balance 10000.
//|   target = floor(10000 * 1 / 100, 2) = floor(100) = 100.
//|   lot_raw = 100 / 205 = 0.48780488; lot = 0.01 + floor((lot_raw - 0.01)/0.01 + 1e-8)*0.01 = 0.48.
//|   risk = 0.48 * 205 = 98.4, 0.984% of base 10000.
//|   margin_needed = 0.48 * 1120.24 = 537.7152, margin_free 10000.
//|   level at SL = (10000 - 98.4) / (0 + 537.7152) * 100 = 1841.420886%, limit so_so+10 = 60.
//|   spread = 6 points, money = 0.00006/0.00001 * 1 * 0.48 = 2.88.
//|   Verdict PL_OK, reason PL_R_NONE.
//+------------------------------------------------------------------+
void PlVec44(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="buy_stop_limit";
   v.what="Buy Stop Limit: trigger 1.12300 > Ask, limit 1.12250 <= trigger, SL 1.12050: exec = limit, side by the limit price";
   PlVecSymEURUSD(v.s);
   PlVecAccount(v.a,"USD",2,10000.0,10000.0,0.0,10000.0);
   PlVecInputs(v.in);
   v.in.kind=PL_KIND_STOP_LIMIT;
   v.in.entry=1.123;
   v.in.limit=1.1225;
   v.in.sl=1.1205;
   v.in.comm.kind=PL_COMM_LOT_SIDE; v.in.comm.rate=2.5; v.in.comm.source=PL_COMMSRC_USER;
   v.in.calcprofit_ok=true; v.in.calcprofit_loss_1lot=200.0;
   //--- expected
   v.chk_prepare_ok=true; v.exp_prepare_ok=true;
   v.exp_plan_reason=PL_R_NONE;
   v.exp_side=PL_SIDE_BUY;
   v.exp_order_type=ORDER_TYPE_BUY_STOP_LIMIT;
   v.exp_exec=1.1225;
   v.exp_sl=1.1205;
   v.exp_ticks=200;
   v.exp_lpl_a=200.0;
   v.exp_lpl_price=200.0;
   v.exp_comm_in=2.5;
   v.exp_comm_out=2.5;
   v.exp_loss_per_lot=205.0;
   v.exp_lot=0.48;
   v.exp_risk_money=98.4;
   v.exp_risk_percent=0.984;
   v.exp_margin_needed=537.7152;
   v.exp_spread_points=6.0;
   v.exp_spread_money=2.88;
   v.exp_verdict=PL_OK;
   v.exp_reason=PL_R_NONE;
   v.exp_note=PL_R_NONE;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 45 sell_stop_limit
//| Sell Stop Limit: trigger 1.11800 < Bid, limit 1.11850 >= trigger, SL 1.12050
//|   Compare price = limit 1.1185.
//|   SL line 1.1205 > compare price: SELL.
//|   Order type ORDER_TYPE_SELL_STOP_LIMIT, exec = 1.1185.
//|   dist = |exec - SL| = 0.002.
//|   ticks = round(0.002 / 0.00001) = 200.
//|   (a) ticks * tvl = 200 * 1 = 200.
//|   commission per side 2.5: in 2.5, out 2.5.
//|   loss_per_lot = 200 + 2.5 + 2.5 = 205.
//|   base = balance 10000.
//|   target = floor(10000 * 1 / 100, 2) = floor(100) = 100.
//|   lot_raw = 100 / 205 = 0.48780488; lot = 0.01 + floor((lot_raw - 0.01)/0.01 + 1e-8)*0.01 = 0.48.
//|   risk = 0.48 * 205 = 98.4, 0.984% of base 10000.
//|   margin_needed = 0.48 * 1120.18 = 537.6864, margin_free 10000.
//|   level at SL = (10000 - 98.4) / (0 + 537.6864) * 100 = 1841.519518%, limit so_so+10 = 60.
//|   spread = 6 points, money = 0.00006/0.00001 * 1 * 0.48 = 2.88.
//|   Verdict PL_OK, reason PL_R_NONE.
//+------------------------------------------------------------------+
void PlVec45(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="sell_stop_limit";
   v.what="Sell Stop Limit: trigger 1.11800 < Bid, limit 1.11850 >= trigger, SL 1.12050";
   PlVecSymEURUSD(v.s);
   PlVecAccount(v.a,"USD",2,10000.0,10000.0,0.0,10000.0);
   PlVecInputs(v.in);
   v.in.kind=PL_KIND_STOP_LIMIT;
   v.in.entry=1.118;
   v.in.limit=1.1185;
   v.in.sl=1.1205;
   v.in.comm.kind=PL_COMM_LOT_SIDE; v.in.comm.rate=2.5; v.in.comm.source=PL_COMMSRC_USER;
   v.in.calcprofit_ok=true; v.in.calcprofit_loss_1lot=200.0;
   //--- expected
   v.chk_prepare_ok=true; v.exp_prepare_ok=true;
   v.exp_plan_reason=PL_R_NONE;
   v.exp_side=PL_SIDE_SELL;
   v.exp_order_type=ORDER_TYPE_SELL_STOP_LIMIT;
   v.exp_exec=1.1185;
   v.exp_sl=1.1205;
   v.exp_ticks=200;
   v.exp_lpl_a=200.0;
   v.exp_lpl_price=200.0;
   v.exp_comm_in=2.5;
   v.exp_comm_out=2.5;
   v.exp_loss_per_lot=205.0;
   v.exp_lot=0.48;
   v.exp_risk_money=98.4;
   v.exp_risk_percent=0.984;
   v.exp_margin_needed=537.6864;
   v.exp_spread_points=6.0;
   v.exp_spread_money=2.88;
   v.exp_verdict=PL_OK;
   v.exp_reason=PL_R_NONE;
   v.exp_note=PL_R_NONE;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 46 buy_limit_wrong_side
//| Buy Limit with entry 1.12300 above Ask (SL below entry makes it a Buy): PL_R_ENTRY_WRONG_SIDE
//|   Compare price = entry 1.123.
//|   SL line 1.121 < compare price: BUY.
//|   Limit entry 1.123 on the wrong side of Ask: PL_R_ENTRY_WRONG_SIDE.
//|   Order type ORDER_TYPE_BUY_LIMIT, exec = 1.123.
//|   dist = |exec - SL| = 0.002.
//|   ticks = round(0.002 / 0.00001) = 200.
//|   (a) ticks * tvl = 200 * 1 = 200.
//|   commission per side 2.5: in 2.5, out 2.5.
//|   loss_per_lot = 200 + 2.5 + 2.5 = 205.
//|   base = balance 10000.
//|   target = floor(10000 * 1 / 100, 2) = floor(100) = 100.
//|   lot_raw = 100 / 205 = 0.48780488; lot = 0.01 + floor((lot_raw - 0.01)/0.01 + 1e-8)*0.01 = 0.48.
//|   risk = 0.48 * 205 = 98.4, 0.984% of base 10000.
//|   margin_needed = 0.48 * 1120.24 = 537.7152, margin_free 10000.
//|   level at SL = (10000 - 98.4) / (0 + 537.7152) * 100 = 1841.420886%, limit so_so+10 = 60.
//|   spread = 6 points, money = 0.00006/0.00001 * 1 * 0.48 = 2.88.
//|   Verdict PL_BLOCK, reason PL_R_ENTRY_WRONG_SIDE.
//+------------------------------------------------------------------+
void PlVec46(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="buy_limit_wrong_side";
   v.what="Buy Limit with entry 1.12300 above Ask (SL below entry makes it a Buy): PL_R_ENTRY_WRONG_SIDE";
   PlVecSymEURUSD(v.s);
   PlVecAccount(v.a,"USD",2,10000.0,10000.0,0.0,10000.0);
   PlVecInputs(v.in);
   v.in.kind=PL_KIND_LIMIT;
   v.in.entry=1.123;
   v.in.sl=1.121;
   v.in.comm.kind=PL_COMM_LOT_SIDE; v.in.comm.rate=2.5; v.in.comm.source=PL_COMMSRC_USER;
   //--- expected
   v.exp_plan_reason=PL_R_ENTRY_WRONG_SIDE;
   v.exp_verdict=PL_BLOCK;
   v.exp_reason=PL_R_ENTRY_WRONG_SIDE;
   v.exp_note=PL_R_NONE;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 47 stop_limit_limit_above_trigger
//| Buy Stop Limit with limit 1.12350 above trigger 1.12300: PL_R_LIMIT_WRONG_SIDE
//|   Compare price = limit 1.1235.
//|   SL line 1.1215 < compare price: BUY.
//|   Stop-Limit trigger 1.123 / limit 1.1235 break the rule: PL_R_LIMIT_WRONG_SIDE.
//|   Order type ORDER_TYPE_BUY_STOP_LIMIT, exec = 1.1235.
//|   dist = |exec - SL| = 0.002.
//|   ticks = round(0.002 / 0.00001) = 200.
//|   (a) ticks * tvl = 200 * 1 = 200.
//|   commission per side 2.5: in 2.5, out 2.5.
//|   loss_per_lot = 200 + 2.5 + 2.5 = 205.
//|   base = balance 10000.
//|   target = floor(10000 * 1 / 100, 2) = floor(100) = 100.
//|   lot_raw = 100 / 205 = 0.48780488; lot = 0.01 + floor((lot_raw - 0.01)/0.01 + 1e-8)*0.01 = 0.48.
//|   risk = 0.48 * 205 = 98.4, 0.984% of base 10000.
//|   margin_needed = 0.48 * 1120.24 = 537.7152, margin_free 10000.
//|   level at SL = (10000 - 98.4) / (0 + 537.7152) * 100 = 1841.420886%, limit so_so+10 = 60.
//|   spread = 6 points, money = 0.00006/0.00001 * 1 * 0.48 = 2.88.
//|   Verdict PL_BLOCK, reason PL_R_LIMIT_WRONG_SIDE.
//+------------------------------------------------------------------+
void PlVec47(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="stop_limit_limit_above_trigger";
   v.what="Buy Stop Limit with limit 1.12350 above trigger 1.12300: PL_R_LIMIT_WRONG_SIDE";
   PlVecSymEURUSD(v.s);
   PlVecAccount(v.a,"USD",2,10000.0,10000.0,0.0,10000.0);
   PlVecInputs(v.in);
   v.in.kind=PL_KIND_STOP_LIMIT;
   v.in.entry=1.123;
   v.in.limit=1.1235;
   v.in.sl=1.1215;
   v.in.comm.kind=PL_COMM_LOT_SIDE; v.in.comm.rate=2.5; v.in.comm.source=PL_COMMSRC_USER;
   //--- expected
   v.exp_plan_reason=PL_R_LIMIT_WRONG_SIDE;
   v.exp_verdict=PL_BLOCK;
   v.exp_reason=PL_R_LIMIT_WRONG_SIDE;
   v.exp_note=PL_R_NONE;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 48 stop_limit_trigger_wrong_side
//| Buy Stop Limit with trigger 1.11900 below Ask: the spec gives PL_R_LIMIT_WRONG_SIDE for the trigger too
//|   Compare price = limit 1.1185.
//|   SL line 1.1165 < compare price: BUY.
//|   Stop-Limit trigger 1.119 / limit 1.1185 break the rule: PL_R_LIMIT_WRONG_SIDE.
//|   Order type ORDER_TYPE_BUY_STOP_LIMIT, exec = 1.1185.
//|   dist = |exec - SL| = 0.002.
//|   ticks = round(0.002 / 0.00001) = 200.
//|   (a) ticks * tvl = 200 * 1 = 200.
//|   commission per side 2.5: in 2.5, out 2.5.
//|   loss_per_lot = 200 + 2.5 + 2.5 = 205.
//|   base = balance 10000.
//|   target = floor(10000 * 1 / 100, 2) = floor(100) = 100.
//|   lot_raw = 100 / 205 = 0.48780488; lot = 0.01 + floor((lot_raw - 0.01)/0.01 + 1e-8)*0.01 = 0.48.
//|   risk = 0.48 * 205 = 98.4, 0.984% of base 10000.
//|   margin_needed = 0.48 * 1120.24 = 537.7152, margin_free 10000.
//|   level at SL = (10000 - 98.4) / (0 + 537.7152) * 100 = 1841.420886%, limit so_so+10 = 60.
//|   spread = 6 points, money = 0.00006/0.00001 * 1 * 0.48 = 2.88.
//|   Verdict PL_BLOCK, reason PL_R_LIMIT_WRONG_SIDE.
//| QUESTION Q7: a wrong trigger also gives PL_R_LIMIT_WRONG_SIDE by the spec wording (ENTRY_WRONG_SIDE might fit better).
//+------------------------------------------------------------------+
void PlVec48(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="stop_limit_trigger_wrong_side";
   v.what="Buy Stop Limit with trigger 1.11900 below Ask: the spec gives PL_R_LIMIT_WRONG_SIDE for the trigger too";
   PlVecSymEURUSD(v.s);
   PlVecAccount(v.a,"USD",2,10000.0,10000.0,0.0,10000.0);
   PlVecInputs(v.in);
   v.in.kind=PL_KIND_STOP_LIMIT;
   v.in.entry=1.119;
   v.in.limit=1.1185;
   v.in.sl=1.1165;
   v.in.comm.kind=PL_COMM_LOT_SIDE; v.in.comm.rate=2.5; v.in.comm.source=PL_COMMSRC_USER;
   //--- expected
   v.exp_plan_reason=PL_R_LIMIT_WRONG_SIDE;
   v.exp_verdict=PL_BLOCK;
   v.exp_reason=PL_R_LIMIT_WRONG_SIDE;
   v.exp_note=PL_R_NONE;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 49 kind_not_allowed
//| Buy Stop on a symbol whose order_mode 123 lacks SYMBOL_ORDER_STOP (4): PL_R_KIND_NOT_ALLOWED
//|   order_mode 123 has no bit 4 for PL_KIND_STOP: PL_R_KIND_NOT_ALLOWED.
//|   Compare price = entry 1.123.
//|   SL line 1.121 < compare price: BUY.
//|   Order type ORDER_TYPE_BUY_STOP, exec = 1.123.
//|   dist = |exec - SL| = 0.002.
//|   ticks = round(0.002 / 0.00001) = 200.
//|   (a) ticks * tvl = 200 * 1 = 200.
//|   commission per side 2.5: in 2.5, out 2.5.
//|   loss_per_lot = 200 + 2.5 + 2.5 = 205.
//|   base = balance 10000.
//|   target = floor(10000 * 1 / 100, 2) = floor(100) = 100.
//|   lot_raw = 100 / 205 = 0.48780488; lot = 0.01 + floor((lot_raw - 0.01)/0.01 + 1e-8)*0.01 = 0.48.
//|   risk = 0.48 * 205 = 98.4, 0.984% of base 10000.
//|   margin_needed = 0.48 * 1120.24 = 537.7152, margin_free 10000.
//|   level at SL = (10000 - 98.4) / (0 + 537.7152) * 100 = 1841.420886%, limit so_so+10 = 60.
//|   spread = 6 points, money = 0.00006/0.00001 * 1 * 0.48 = 2.88.
//|   Verdict PL_BLOCK, reason PL_R_KIND_NOT_ALLOWED.
//+------------------------------------------------------------------+
void PlVec49(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="kind_not_allowed";
   v.what="Buy Stop on a symbol whose order_mode 123 lacks SYMBOL_ORDER_STOP (4): PL_R_KIND_NOT_ALLOWED";
   PlVecSymEURUSD(v.s);
   v.s.order_mode=123;
   PlVecAccount(v.a,"USD",2,10000.0,10000.0,0.0,10000.0);
   PlVecInputs(v.in);
   v.in.kind=PL_KIND_STOP;
   v.in.entry=1.123;
   v.in.sl=1.121;
   v.in.comm.kind=PL_COMM_LOT_SIDE; v.in.comm.rate=2.5; v.in.comm.source=PL_COMMSRC_USER;
   //--- expected
   v.exp_plan_reason=PL_R_KIND_NOT_ALLOWED;
   v.exp_verdict=PL_BLOCK;
   v.exp_reason=PL_R_KIND_NOT_ALLOWED;
   v.exp_note=PL_R_NONE;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 50 sell_tp_price
//| Sell Market with TP by price 1.11718 (300 ticks from Bid), SL 1.12218, $7 per round
//|   Compare price = mid (Bid+Ask)/2 = (1.12018+1.12024)/2 = 1.12021.
//|   SL line 1.12218 > compare price: SELL.
//|   Order type ORDER_TYPE_SELL, exec = 1.12018.
//|   dist = SL - Bid = 0.002.
//|   ticks = round(0.002 / 0.00001) = 200.
//|   TP1 price 1.11718.
//|   (a) ticks * tvl = 200 * 1 = 200.
//|   commission per round 7: in 3.5, out 3.5.
//|   loss_per_lot = 200 + 3.5 + 3.5 = 207.
//|   base = balance 10000.
//|   target = floor(10000 * 1 / 100, 2) = floor(100) = 100.
//|   lot_raw = 100 / 207 = 0.48309179; lot = 0.01 + floor((lot_raw - 0.01)/0.01 + 1e-8)*0.01 = 0.48.
//|   risk = 0.48 * 207 = 99.36, 0.9936% of base 10000.
//|   reward TP1 = 0.48*100/100 * (300 ticks * 1) - 0.48*100/100 * (3.5 + 3.5) = 140.64.
//|   reward_total 140.64, rr = 140.64 / 99.36 = 1.41545894.
//|   margin_needed = 0.48 * 1120.18 = 537.6864, margin_free 10000.
//|   level at SL = (10000 - 99.36) / (0 + 537.6864) * 100 = 1841.340975%, limit so_so+10 = 60.
//|   spread = 6 points, money = 0.00006/0.00001 * 1 * 0.48 = 2.88.
//|   Verdict PL_OK, reason PL_R_NONE.
//+------------------------------------------------------------------+
void PlVec50(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="sell_tp_price";
   v.what="Sell Market with TP by price 1.11718 (300 ticks from Bid), SL 1.12218, $7 per round";
   PlVecSymEURUSD(v.s);
   PlVecAccount(v.a,"USD",2,10000.0,10000.0,0.0,10000.0);
   PlVecInputs(v.in);
   v.in.sl=1.12218;
   v.in.comm.kind=PL_COMM_LOT_ROUND; v.in.comm.rate=7.0; v.in.comm.source=PL_COMMSRC_USER;
   v.in.no_tp=false;
   v.in.tp[0].on=true; v.in.tp[0].mode=PL_TP_PRICE; v.in.tp[0].r=0.0; v.in.tp[0].price=1.11718; v.in.tp[0].share=100.0;
   v.in.calcprofit_ok=true; v.in.calcprofit_loss_1lot=200.0;
   //--- expected
   v.chk_prepare_ok=true; v.exp_prepare_ok=true;
   v.exp_plan_reason=PL_R_NONE;
   v.exp_side=PL_SIDE_SELL;
   v.exp_order_type=ORDER_TYPE_SELL;
   v.exp_exec=1.12018;
   v.exp_sl=1.12218;
   v.exp_tp=1.11718;
   v.exp_ticks=200;
   v.exp_lpl_a=200.0;
   v.exp_lpl_price=200.0;
   v.exp_comm_in=3.5;
   v.exp_comm_out=3.5;
   v.exp_loss_per_lot=207.0;
   v.exp_lot=0.48;
   v.exp_risk_money=99.36;
   v.exp_risk_percent=0.9936;
   v.exp_reward_total=140.64;
   v.exp_rr=1.41545894;
   v.exp_margin_needed=537.6864;
   v.exp_spread_points=6.0;
   v.exp_spread_money=2.88;
   v.exp_verdict=PL_OK;
   v.exp_reason=PL_R_NONE;
   v.exp_note=PL_R_NONE;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 51 three_tp
//| Three TP by R 1/2/3 with shares 50/30/20: rewards on lot*share/100 (not stepped), commission per share
//|   Compare price = mid (Bid+Ask)/2 = (1.12018+1.12024)/2 = 1.12021.
//|   SL line 1.11824 < compare price: BUY.
//|   Order type ORDER_TYPE_BUY, exec = 1.12024.
//|   dist = Ask - SL = 0.002.
//|   ticks = round(0.002 / 0.00001) = 200.
//|   TP1 = exec + 1 * |exec - SL| 0.002 = 1.12224.
//|   TP2 = exec + 2 * |exec - SL| 0.002 = 1.12424.
//|   TP3 = exec + 3 * |exec - SL| 0.002 = 1.12624.
//|   (a) ticks * tvl = 200 * 1 = 200.
//|   commission per round 7: in 3.5, out 3.5.
//|   loss_per_lot = 200 + 3.5 + 3.5 = 207.
//|   base = balance 10000.
//|   target = floor(10000 * 1 / 100, 2) = floor(100) = 100.
//|   lot_raw = 100 / 207 = 0.48309179; lot = 0.01 + floor((lot_raw - 0.01)/0.01 + 1e-8)*0.01 = 0.48.
//|   risk = 0.48 * 207 = 99.36, 0.9936% of base 10000.
//|   reward TP1 = 0.48*50/100 * (200 ticks * 1) - 0.48*50/100 * (3.5 + 3.5) = 46.32.
//|   reward TP2 = 0.48*30/100 * (400 ticks * 1) - 0.48*30/100 * (3.5 + 3.5) = 56.592.
//|   reward TP3 = 0.48*20/100 * (600 ticks * 1) - 0.48*20/100 * (3.5 + 3.5) = 56.928.
//|   reward_total 159.84, rr = 159.84 / 99.36 = 1.60869565.
//|   margin_needed = 0.48 * 1120.24 = 537.7152, margin_free 10000.
//|   level at SL = (10000 - 99.36) / (0 + 537.7152) * 100 = 1841.242353%, limit so_so+10 = 60.
//|   spread = 6 points, money = 0.00006/0.00001 * 1 * 0.48 = 2.88.
//|   Verdict PL_OK, reason PL_R_NONE.
//| QUESTION Q8b: partial lots 0.24/0.144/0.096 are not on vol_step; the spec formula used literally.
//+------------------------------------------------------------------+
void PlVec51(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="three_tp";
   v.what="Three TP by R 1/2/3 with shares 50/30/20: rewards on lot*share/100 (not stepped), commission per share";
   PlVecSymEURUSD(v.s);
   PlVecAccount(v.a,"USD",2,10000.0,10000.0,0.0,10000.0);
   PlVecInputs(v.in);
   v.in.sl=1.11824;
   v.in.comm.kind=PL_COMM_LOT_ROUND; v.in.comm.rate=7.0; v.in.comm.source=PL_COMMSRC_USER;
   v.in.no_tp=false;
   v.in.tp[0].on=true; v.in.tp[0].mode=PL_TP_R; v.in.tp[0].r=1.0; v.in.tp[0].price=0.0; v.in.tp[0].share=50.0;
   v.in.tp[1].on=true; v.in.tp[1].mode=PL_TP_R; v.in.tp[1].r=2.0; v.in.tp[1].price=0.0; v.in.tp[1].share=30.0;
   v.in.tp[2].on=true; v.in.tp[2].mode=PL_TP_R; v.in.tp[2].r=3.0; v.in.tp[2].price=0.0; v.in.tp[2].share=20.0;
   v.in.calcprofit_ok=true; v.in.calcprofit_loss_1lot=200.0;
   //--- expected
   v.chk_prepare_ok=true; v.exp_prepare_ok=true;
   v.exp_plan_reason=PL_R_NONE;
   v.exp_side=PL_SIDE_BUY;
   v.exp_order_type=ORDER_TYPE_BUY;
   v.exp_exec=1.12024;
   v.exp_sl=1.11824;
   v.exp_tp=1.12224;
   v.exp_ticks=200;
   v.exp_lpl_a=200.0;
   v.exp_lpl_price=200.0;
   v.exp_comm_in=3.5;
   v.exp_comm_out=3.5;
   v.exp_loss_per_lot=207.0;
   v.exp_lot=0.48;
   v.exp_risk_money=99.36;
   v.exp_risk_percent=0.9936;
   v.exp_reward_total=159.84;
   v.exp_rr=1.60869565;
   v.exp_margin_needed=537.7152;
   v.exp_spread_points=6.0;
   v.exp_spread_money=2.88;
   v.exp_verdict=PL_OK;
   v.exp_reason=PL_R_NONE;
   v.exp_note=PL_R_NONE;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 52 tp_wrong_side
//| Buy Market with TP price 1.11900 below Ask: PL_R_TP_WRONG_SIDE
//|   Compare price = mid (Bid+Ask)/2 = (1.12018+1.12024)/2 = 1.12021.
//|   SL line 1.11824 < compare price: BUY.
//|   Order type ORDER_TYPE_BUY, exec = 1.12024.
//|   dist = Ask - SL = 0.002.
//|   ticks = round(0.002 / 0.00001) = 200.
//|   TP1 price 1.119.
//|   TP on the wrong side: PL_R_TP_WRONG_SIDE.
//|   (a) ticks * tvl = 200 * 1 = 200.
//|   commission per round 7: in 3.5, out 3.5.
//|   loss_per_lot = 200 + 3.5 + 3.5 = 207.
//|   base = balance 10000.
//|   target = floor(10000 * 1 / 100, 2) = floor(100) = 100.
//|   lot_raw = 100 / 207 = 0.48309179; lot = 0.01 + floor((lot_raw - 0.01)/0.01 + 1e-8)*0.01 = 0.48.
//|   risk = 0.48 * 207 = 99.36, 0.9936% of base 10000.
//|   reward TP1 = 0.48*100/100 * (124 ticks * 1) - 0.48*100/100 * (3.5 + 3.5) = 56.16.
//|   reward_total 56.16, rr = 56.16 / 99.36 = 0.56521739.
//|   margin_needed = 0.48 * 1120.24 = 537.7152, margin_free 10000.
//|   level at SL = (10000 - 99.36) / (0 + 537.7152) * 100 = 1841.242353%, limit so_so+10 = 60.
//|   spread = 6 points, money = 0.00006/0.00001 * 1 * 0.48 = 2.88.
//|   Verdict PL_BLOCK, reason PL_R_TP_WRONG_SIDE.
//+------------------------------------------------------------------+
void PlVec52(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="tp_wrong_side";
   v.what="Buy Market with TP price 1.11900 below Ask: PL_R_TP_WRONG_SIDE";
   PlVecSymEURUSD(v.s);
   PlVecAccount(v.a,"USD",2,10000.0,10000.0,0.0,10000.0);
   PlVecInputs(v.in);
   v.in.sl=1.11824;
   v.in.comm.kind=PL_COMM_LOT_ROUND; v.in.comm.rate=7.0; v.in.comm.source=PL_COMMSRC_USER;
   v.in.no_tp=false;
   v.in.tp[0].on=true; v.in.tp[0].mode=PL_TP_PRICE; v.in.tp[0].r=0.0; v.in.tp[0].price=1.119; v.in.tp[0].share=100.0;
   //--- expected
   v.exp_plan_reason=PL_R_TP_WRONG_SIDE;
   v.exp_verdict=PL_BLOCK;
   v.exp_reason=PL_R_TP_WRONG_SIDE;
   v.exp_note=PL_R_NONE;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 53 atr_stop
//| ATR stop: Buy Market (SL line below), atr 0.0012345 x 1.5 = 0.00185175, SL = Ask - 0.00185175 = 1.11838825, normalized up to 1.11839
//|   Compare price = mid (Bid+Ask)/2 = (1.12018+1.12024)/2 = 1.12021.
//|   SL line 1.119 < compare price: BUY.
//|   Order type ORDER_TYPE_BUY, exec = 1.12024.
//|   ATR stop: SL = exec - 0.0012345 * 1.5 = 1.11838825.
//|   SL 1.11838825 normalized up to the tick: 1.11839.
//|   dist = Ask - SL = 0.00185.
//|   ticks = round(0.00185 / 0.00001) = 185.
//|   (a) ticks * tvl = 185 * 1 = 185.
//|   commission per side 2.5: in 2.5, out 2.5.
//|   loss_per_lot = 185 + 2.5 + 2.5 = 190.
//|   base = balance 10000.
//|   target = floor(10000 * 1 / 100, 2) = floor(100) = 100.
//|   lot_raw = 100 / 190 = 0.52631579; lot = 0.01 + floor((lot_raw - 0.01)/0.01 + 1e-8)*0.01 = 0.52.
//|   risk = 0.52 * 190 = 98.8, 0.988% of base 10000.
//|   margin_needed = 0.52 * 1120.24 = 582.5248, margin_free 10000.
//|   level at SL = (10000 - 98.8) / (0 + 582.5248) * 100 = 1699.704459%, limit so_so+10 = 60.
//|   spread = 6 points, money = 0.00006/0.00001 * 1 * 0.52 = 3.12.
//|   Verdict PL_OK, reason PL_R_NONE.
//| QUESTION Q10: the spec does not say the ATR SL is normalized to the tick; literal rule 'SL rounds toward the price' applied to it.
//+------------------------------------------------------------------+
void PlVec53(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="atr_stop";
   v.what="ATR stop: Buy Market (SL line below), atr 0.0012345 x 1.5 = 0.00185175, SL = Ask - 0.00185175 = 1.11838825, normalized up to 1.11839";
   PlVecSymEURUSD(v.s);
   PlVecAccount(v.a,"USD",2,10000.0,10000.0,0.0,10000.0);
   PlVecInputs(v.in);
   v.in.sl=1.119;
   v.in.atr_on=true;
   v.in.atr=0.0012345;
   v.in.atr_mult=1.5;
   v.in.comm.kind=PL_COMM_LOT_SIDE; v.in.comm.rate=2.5; v.in.comm.source=PL_COMMSRC_USER;
   v.in.calcprofit_ok=true; v.in.calcprofit_loss_1lot=185.0;
   //--- expected
   v.chk_prepare_ok=true; v.exp_prepare_ok=true;
   v.exp_plan_reason=PL_R_NONE;
   v.exp_side=PL_SIDE_BUY;
   v.exp_order_type=ORDER_TYPE_BUY;
   v.exp_exec=1.12024;
   v.exp_sl=1.11839;
   v.exp_ticks=185;
   v.exp_lpl_a=185.0;
   v.exp_lpl_price=185.0;
   v.exp_comm_in=2.5;
   v.exp_comm_out=2.5;
   v.exp_loss_per_lot=190.0;
   v.exp_lot=0.52;
   v.exp_risk_money=98.8;
   v.exp_risk_percent=0.988;
   v.exp_margin_needed=582.5248;
   v.exp_spread_points=6.0;
   v.exp_spread_money=3.12;
   v.exp_verdict=PL_OK;
   v.exp_reason=PL_R_NONE;
   v.exp_note=PL_R_NONE;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 54 no_sl_with_tp
//| no_sl: side from TP (above mid: Buy), lot_fixed 0.10, risk 0, PL_R_NO_SL CONFIRM, TP 1.12524, $2.50 per side
//|   Compare price = mid (Bid+Ask)/2 = (1.12018+1.12024)/2 = 1.12021.
//|   no_sl: side from TP 1.12524 vs 1.12021: BUY.
//|   Order type ORDER_TYPE_BUY, exec = 1.12024.
//|   TP1 price 1.12524.
//|   no_sl: lot = lot_fixed 0.1, risk 0, PL_R_NO_SL (CONFIRM).
//|   commission per side 2.5: in 2.5, out 2.5.
//|   reward TP1 = 0.1*100/100 * (500 ticks * 1) - 0.1*100/100 * (2.5 + 2.5) = 49.5.
//|   margin_needed = 0.1 * 1120.24 = 112.024, margin_free 10000.
//|   spread = 6 points, money = 0.00006/0.00001 * 1 * 0.1 = 0.6.
//|   Verdict PL_CONFIRM, reason PL_R_NO_SL.
//+------------------------------------------------------------------+
void PlVec54(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="no_sl_with_tp";
   v.what="no_sl: side from TP (above mid: Buy), lot_fixed 0.10, risk 0, PL_R_NO_SL CONFIRM, TP 1.12524, $2.50 per side";
   PlVecSymEURUSD(v.s);
   PlVecAccount(v.a,"USD",2,10000.0,10000.0,0.0,10000.0);
   PlVecInputs(v.in);
   v.in.sl=0.0;
   v.in.no_sl=true;
   v.in.lot_fixed=0.1;
   v.in.comm.kind=PL_COMM_LOT_SIDE; v.in.comm.rate=2.5; v.in.comm.source=PL_COMMSRC_USER;
   v.in.no_tp=false;
   v.in.tp[0].on=true; v.in.tp[0].mode=PL_TP_PRICE; v.in.tp[0].r=0.0; v.in.tp[0].price=1.12524; v.in.tp[0].share=100.0;
   //--- expected
   v.chk_prepare_ok=true; v.exp_prepare_ok=true;
   v.exp_plan_reason=PL_R_NONE;
   v.exp_side=PL_SIDE_BUY;
   v.exp_order_type=ORDER_TYPE_BUY;
   v.exp_exec=1.12024;
   v.exp_tp=1.12524;
   v.exp_comm_in=2.5;
   v.exp_lot=0.1;
   v.exp_risk_money=0.0;
   v.exp_reward_total=49.5;
   v.exp_margin_needed=112.024;
   v.exp_spread_points=6.0;
   v.exp_spread_money=0.6;
   v.exp_verdict=PL_CONFIRM;
   v.exp_reason=PL_R_NO_SL;
   v.exp_note=PL_R_NONE;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 55 no_sl_no_tp
//| no_sl and no TP: side unknown, PL_R_NO_SL, nothing to compute
//|   Compare price = mid (Bid+Ask)/2 = (1.12018+1.12024)/2 = 1.12021.
//|   Prepare: PL_R_NO_SL (no_sl and no TP: side unknown), ok=false.
//|   Verdict PL_BLOCK, reason PL_R_NO_SL.
//| QUESTION Q13: side unknown, nothing can be sent, but the spec gives PL_R_NO_SL the verdict CONFIRM; verdict not checked, reason and prepare ok=false checked.
//+------------------------------------------------------------------+
void PlVec55(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="no_sl_no_tp";
   v.what="no_sl and no TP: side unknown, PL_R_NO_SL, nothing to compute";
   PlVecSymEURUSD(v.s);
   PlVecAccount(v.a,"USD",2,10000.0,10000.0,0.0,10000.0);
   PlVecInputs(v.in);
   v.in.sl=0.0;
   v.in.no_sl=true;
   v.in.lot_fixed=0.1;
   v.in.comm.kind=PL_COMM_LOT_SIDE; v.in.comm.rate=2.5; v.in.comm.source=PL_COMMSRC_USER;
   //--- expected
   v.chk_prepare_ok=true; v.exp_prepare_ok=false;
   v.exp_plan_reason=PL_R_NO_SL;
   v.exp_reason=PL_R_NO_SL;
   v.exp_note=PL_R_NONE;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 56 market_closed_fresh
//| Session closed with a fresh tick: numbers as in the first vector, BLOCK PL_R_MARKET_CLOSED
//|   Compare price = mid (Bid+Ask)/2 = (1.12018+1.12024)/2 = 1.12021.
//|   SL line 1.11824 < compare price: BUY.
//|   Order type ORDER_TYPE_BUY, exec = 1.12024.
//|   dist = Ask - SL = 0.002.
//|   ticks = round(0.002 / 0.00001) = 200.
//|   TP1 = exec + 2 * |exec - SL| 0.002 = 1.12424.
//|   (a) ticks * tvl = 200 * 1 = 200.
//|   commission per round 7: in 3.5, out 3.5.
//|   loss_per_lot = 200 + 3.5 + 3.5 = 207.
//|   base = balance 10000.
//|   target = floor(10000 * 1 / 100, 2) = floor(100) = 100.
//|   lot_raw = 100 / 207 = 0.48309179; lot = 0.01 + floor((lot_raw - 0.01)/0.01 + 1e-8)*0.01 = 0.48.
//|   risk = 0.48 * 207 = 99.36, 0.9936% of base 10000.
//|   reward TP1 = 0.48*100/100 * (400 ticks * 1) - 0.48*100/100 * (3.5 + 3.5) = 188.64.
//|   reward_total 188.64, rr = 188.64 / 99.36 = 1.89855072.
//|   margin_needed = 0.48 * 1120.24 = 537.7152, margin_free 10000.
//|   level at SL = (10000 - 99.36) / (0 + 537.7152) * 100 = 1841.242353%, limit so_so+10 = 60.
//|   spread = 6 points, money = 0.00006/0.00001 * 1 * 0.48 = 2.88.
//|   session closed: PL_R_MARKET_CLOSED (BLOCK), numbers kept.
//|   Verdict PL_BLOCK, reason PL_R_MARKET_CLOSED.
//+------------------------------------------------------------------+
void PlVec56(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="market_closed_fresh";
   v.what="Session closed with a fresh tick: numbers as in the first vector, BLOCK PL_R_MARKET_CLOSED";
   PlVecSymEURUSD(v.s);
   v.s.session_open=false;
   PlVecAccount(v.a,"USD",2,10000.0,10000.0,0.0,10000.0);
   PlVecInputs(v.in);
   v.in.sl=1.11824;
   v.in.comm.kind=PL_COMM_LOT_ROUND; v.in.comm.rate=7.0; v.in.comm.source=PL_COMMSRC_USER;
   v.in.no_tp=false;
   v.in.tp[0].on=true; v.in.tp[0].mode=PL_TP_R; v.in.tp[0].r=2.0; v.in.tp[0].price=0.0; v.in.tp[0].share=100.0;
   v.in.calcprofit_ok=true; v.in.calcprofit_loss_1lot=200.0;
   //--- expected
   v.chk_prepare_ok=true; v.exp_prepare_ok=true;
   v.exp_plan_reason=PL_R_NONE;
   v.exp_side=PL_SIDE_BUY;
   v.exp_order_type=ORDER_TYPE_BUY;
   v.exp_exec=1.12024;
   v.exp_sl=1.11824;
   v.exp_tp=1.12424;
   v.exp_ticks=200;
   v.exp_lpl_a=200.0;
   v.exp_lpl_price=200.0;
   v.exp_comm_in=3.5;
   v.exp_comm_out=3.5;
   v.exp_loss_per_lot=207.0;
   v.exp_lot=0.48;
   v.exp_risk_money=99.36;
   v.exp_risk_percent=0.9936;
   v.exp_reward_total=188.64;
   v.exp_rr=1.89855072;
   v.exp_margin_needed=537.7152;
   v.exp_spread_points=6.0;
   v.exp_spread_money=2.88;
   v.exp_verdict=PL_BLOCK;
   v.exp_reason=PL_R_MARKET_CLOSED;
   v.exp_note=PL_R_NONE;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 57 market_closed_friday_tick
//| Sunday evening: session closed, last tick Friday 23:54:59, now Sunday 20:59:18: still PL_R_MARKET_CLOSED (stale is WARN only in an open session)
//|   Compare price = mid (Bid+Ask)/2 = (1.12018+1.12024)/2 = 1.12021.
//|   SL line 1.11824 < compare price: BUY.
//|   Order type ORDER_TYPE_BUY, exec = 1.12024.
//|   dist = Ask - SL = 0.002.
//|   ticks = round(0.002 / 0.00001) = 200.
//|   TP1 = exec + 2 * |exec - SL| 0.002 = 1.12424.
//|   (a) ticks * tvl = 200 * 1 = 200.
//|   commission per round 7: in 3.5, out 3.5.
//|   loss_per_lot = 200 + 3.5 + 3.5 = 207.
//|   base = balance 10000.
//|   target = floor(10000 * 1 / 100, 2) = floor(100) = 100.
//|   lot_raw = 100 / 207 = 0.48309179; lot = 0.01 + floor((lot_raw - 0.01)/0.01 + 1e-8)*0.01 = 0.48.
//|   risk = 0.48 * 207 = 99.36, 0.9936% of base 10000.
//|   reward TP1 = 0.48*100/100 * (400 ticks * 1) - 0.48*100/100 * (3.5 + 3.5) = 188.64.
//|   reward_total 188.64, rr = 188.64 / 99.36 = 1.89855072.
//|   margin_needed = 0.48 * 1120.24 = 537.7152, margin_free 10000.
//|   level at SL = (10000 - 99.36) / (0 + 537.7152) * 100 = 1841.242353%, limit so_so+10 = 60.
//|   spread = 6 points, money = 0.00006/0.00001 * 1 * 0.48 = 2.88.
//|   session closed: PL_R_MARKET_CLOSED (BLOCK), numbers kept.
//|   Verdict PL_BLOCK, reason PL_R_MARKET_CLOSED.
//| QUESTION Q2: Types says stale is BLOCK when closed; STALE_QUOTE precedes MARKET_CLOSED in the enum, so a Types-following core returns STALE_QUOTE. Literal spec: MARKET_CLOSED.
//+------------------------------------------------------------------+
void PlVec57(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="market_closed_friday_tick";
   v.what="Sunday evening: session closed, last tick Friday 23:54:59, now Sunday 20:59:18: still PL_R_MARKET_CLOSED (stale is WARN only in an open session)";
   PlVecSymEURUSD(v.s);
   v.s.session_open=false;
   v.s.tick_time=D'2026.10.09 23:54:59';
   v.s.server_now=D'2026.10.11 20:59:18';
   PlVecAccount(v.a,"USD",2,10000.0,10000.0,0.0,10000.0);
   PlVecInputs(v.in);
   v.in.sl=1.11824;
   v.in.comm.kind=PL_COMM_LOT_ROUND; v.in.comm.rate=7.0; v.in.comm.source=PL_COMMSRC_USER;
   v.in.no_tp=false;
   v.in.tp[0].on=true; v.in.tp[0].mode=PL_TP_R; v.in.tp[0].r=2.0; v.in.tp[0].price=0.0; v.in.tp[0].share=100.0;
   v.in.calcprofit_ok=true; v.in.calcprofit_loss_1lot=200.0;
   //--- expected
   v.chk_prepare_ok=true; v.exp_prepare_ok=true;
   v.exp_plan_reason=PL_R_NONE;
   v.exp_side=PL_SIDE_BUY;
   v.exp_order_type=ORDER_TYPE_BUY;
   v.exp_exec=1.12024;
   v.exp_sl=1.11824;
   v.exp_tp=1.12424;
   v.exp_ticks=200;
   v.exp_lpl_a=200.0;
   v.exp_lpl_price=200.0;
   v.exp_comm_in=3.5;
   v.exp_comm_out=3.5;
   v.exp_loss_per_lot=207.0;
   v.exp_lot=0.48;
   v.exp_risk_money=99.36;
   v.exp_risk_percent=0.9936;
   v.exp_reward_total=188.64;
   v.exp_rr=1.89855072;
   v.exp_margin_needed=537.7152;
   v.exp_spread_points=6.0;
   v.exp_spread_money=2.88;
   v.exp_verdict=PL_BLOCK;
   v.exp_reason=PL_R_MARKET_CLOSED;
   v.exp_note=PL_R_NONE;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 58 stale_quote_open
//| Open session, last tick 120 s old, market order: BLOCK PL_R_STALE_QUOTE, numbers as usual
//|   Compare price = mid (Bid+Ask)/2 = (1.12018+1.12024)/2 = 1.12021.
//|   SL line 1.11824 < compare price: BUY.
//|   Order type ORDER_TYPE_BUY, exec = 1.12024.
//|   dist = Ask - SL = 0.002.
//|   ticks = round(0.002 / 0.00001) = 200.
//|   (a) ticks * tvl = 200 * 1 = 200.
//|   commission per round 7: in 3.5, out 3.5.
//|   loss_per_lot = 200 + 3.5 + 3.5 = 207.
//|   base = balance 10000.
//|   target = floor(10000 * 1 / 100, 2) = floor(100) = 100.
//|   lot_raw = 100 / 207 = 0.48309179; lot = 0.01 + floor((lot_raw - 0.01)/0.01 + 1e-8)*0.01 = 0.48.
//|   risk = 0.48 * 207 = 99.36, 0.9936% of base 10000.
//|   margin_needed = 0.48 * 1120.24 = 537.7152, margin_free 10000.
//|   level at SL = (10000 - 99.36) / (0 + 537.7152) * 100 = 1841.242353%, limit so_so+10 = 60.
//|   spread = 6 points, money = 0.00006/0.00001 * 1 * 0.48 = 2.88.
//|   tick 120 s old, session open, market order: PL_R_STALE_QUOTE (BLOCK).
//|   Verdict PL_BLOCK, reason PL_R_STALE_QUOTE.
//+------------------------------------------------------------------+
void PlVec58(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="stale_quote_open";
   v.what="Open session, last tick 120 s old, market order: BLOCK PL_R_STALE_QUOTE, numbers as usual";
   PlVecSymEURUSD(v.s);
   v.s.tick_time=D'2026.10.09 11:58:00';
   PlVecAccount(v.a,"USD",2,10000.0,10000.0,0.0,10000.0);
   PlVecInputs(v.in);
   v.in.sl=1.11824;
   v.in.comm.kind=PL_COMM_LOT_ROUND; v.in.comm.rate=7.0; v.in.comm.source=PL_COMMSRC_USER;
   v.in.calcprofit_ok=true; v.in.calcprofit_loss_1lot=200.0;
   //--- expected
   v.chk_prepare_ok=true; v.exp_prepare_ok=true;
   v.exp_plan_reason=PL_R_NONE;
   v.exp_side=PL_SIDE_BUY;
   v.exp_order_type=ORDER_TYPE_BUY;
   v.exp_exec=1.12024;
   v.exp_sl=1.11824;
   v.exp_ticks=200;
   v.exp_lpl_a=200.0;
   v.exp_lpl_price=200.0;
   v.exp_comm_in=3.5;
   v.exp_comm_out=3.5;
   v.exp_loss_per_lot=207.0;
   v.exp_lot=0.48;
   v.exp_risk_money=99.36;
   v.exp_risk_percent=0.9936;
   v.exp_margin_needed=537.7152;
   v.exp_spread_points=6.0;
   v.exp_spread_money=2.88;
   v.exp_verdict=PL_BLOCK;
   v.exp_reason=PL_R_STALE_QUOTE;
   v.exp_note=PL_R_NONE;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 59 margin_block
//| Margin: equity 10000, used margin 9500, free 500; 0.48 lot needs 537.72: BLOCK PL_R_MARGIN, max by margin 0.44
//|   Compare price = mid (Bid+Ask)/2 = (1.12018+1.12024)/2 = 1.12021.
//|   SL line 1.11824 < compare price: BUY.
//|   Order type ORDER_TYPE_BUY, exec = 1.12024.
//|   dist = Ask - SL = 0.002.
//|   ticks = round(0.002 / 0.00001) = 200.
//|   (a) ticks * tvl = 200 * 1 = 200.
//|   commission per round 7: in 3.5, out 3.5.
//|   loss_per_lot = 200 + 3.5 + 3.5 = 207.
//|   base = balance 10000.
//|   target = floor(10000 * 1 / 100, 2) = floor(100) = 100.
//|   lot_raw = 100 / 207 = 0.48309179; lot = 0.01 + floor((lot_raw - 0.01)/0.01 + 1e-8)*0.01 = 0.48.
//|   risk = 0.48 * 207 = 99.36, 0.9936% of base 10000.
//|   margin_needed = 0.48 * 1120.24 = 537.7152, margin_free 500.
//|   margin_needed > margin_free: PL_R_MARGIN (BLOCK).
//|   level at SL = (10000 - 99.36) / (9500 + 537.7152) * 100 = 98.634398%, limit so_so+10 = 60.
//|   spread = 6 points, money = 0.00006/0.00001 * 1 * 0.48 = 2.88.
//|   Verdict PL_BLOCK, reason PL_R_MARGIN.
//+------------------------------------------------------------------+
void PlVec59(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="margin_block";
   v.what="Margin: equity 10000, used margin 9500, free 500; 0.48 lot needs 537.72: BLOCK PL_R_MARGIN, max by margin 0.44";
   PlVecSymEURUSD(v.s);
   PlVecAccount(v.a,"USD",2,10000.0,10000.0,9500.0,500.0);
   PlVecInputs(v.in);
   v.in.sl=1.11824;
   v.in.comm.kind=PL_COMM_LOT_ROUND; v.in.comm.rate=7.0; v.in.comm.source=PL_COMMSRC_USER;
   v.in.calcprofit_ok=true; v.in.calcprofit_loss_1lot=200.0;
   //--- expected
   v.chk_prepare_ok=true; v.exp_prepare_ok=true;
   v.exp_plan_reason=PL_R_NONE;
   v.exp_side=PL_SIDE_BUY;
   v.exp_order_type=ORDER_TYPE_BUY;
   v.exp_exec=1.12024;
   v.exp_sl=1.11824;
   v.exp_ticks=200;
   v.exp_lpl_a=200.0;
   v.exp_lpl_price=200.0;
   v.exp_comm_in=3.5;
   v.exp_comm_out=3.5;
   v.exp_loss_per_lot=207.0;
   v.exp_lot=0.48;
   v.exp_risk_money=99.36;
   v.exp_risk_percent=0.9936;
   v.exp_margin_needed=537.7152;
   v.exp_spread_points=6.0;
   v.exp_spread_money=2.88;
   v.exp_verdict=PL_BLOCK;
   v.exp_reason=PL_R_MARGIN;
   v.exp_note=PL_R_NONE;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 60 stopout_before_sl
//| Stop-out before SL: balance 10000, equity 400 (floating loss), margin 100, free 300, risk $340, SL 300 pips: level at SL 31.4% < 60: BLOCK, max 0.09
//|   Compare price = mid (Bid+Ask)/2 = (1.12018+1.12024)/2 = 1.12021.
//|   SL line 1.09024 < compare price: BUY.
//|   Order type ORDER_TYPE_BUY, exec = 1.12024.
//|   dist = Ask - SL = 0.03.
//|   ticks = round(0.03 / 0.00001) = 3000.
//|   (a) ticks * tvl = 3000 * 1 = 3000.
//|   commission per side 0: in 0, out 0.
//|   loss_per_lot = 3000 + 0 + 0 = 3000.
//|   base = balance 10000.
//|   target = risk_money 340.
//|   lot_raw = 340 / 3000 = 0.11333333; lot = 0.01 + floor((lot_raw - 0.01)/0.01 + 1e-8)*0.01 = 0.11.
//|   risk = 0.11 * 3000 = 330, 3.3% of base 10000.
//|   3.3% > 2%: PL_R_RISK_HIGH (CONFIRM).
//|   margin_needed = 0.11 * 1120.24 = 123.2264, margin_free 300.
//|   level at SL = (400 - 330) / (100 + 123.2264) * 100 = 31.358298%, limit so_so+10 = 60.
//|   below: PL_R_STOPOUT_BEFORE_SL (BLOCK).
//|   spread = 6 points, money = 0.00006/0.00001 * 1 * 0.11 = 0.66.
//|   Verdict PL_BLOCK, reason PL_R_STOPOUT_BEFORE_SL.
//+------------------------------------------------------------------+
void PlVec60(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="stopout_before_sl";
   v.what="Stop-out before SL: balance 10000, equity 400 (floating loss), margin 100, free 300, risk $340, SL 300 pips: level at SL 31.4% < 60: BLOCK, max 0.09";
   PlVecSymEURUSD(v.s);
   PlVecAccount(v.a,"USD",2,10000.0,400.0,100.0,300.0);
   PlVecInputs(v.in);
   v.in.sl=1.09024;
   v.in.risk_mode=PL_RISK_MONEY;
   v.in.risk_money=340.0;
   v.in.comm.kind=PL_COMM_LOT_SIDE; v.in.comm.rate=0.0; v.in.comm.source=PL_COMMSRC_USER;
   v.in.calcprofit_ok=true; v.in.calcprofit_loss_1lot=3000.0;
   //--- expected
   v.chk_prepare_ok=true; v.exp_prepare_ok=true;
   v.exp_plan_reason=PL_R_NONE;
   v.exp_side=PL_SIDE_BUY;
   v.exp_order_type=ORDER_TYPE_BUY;
   v.exp_exec=1.12024;
   v.exp_sl=1.09024;
   v.exp_ticks=3000;
   v.exp_lpl_a=3000.0;
   v.exp_lpl_price=3000.0;
   v.exp_comm_in=0.0;
   v.exp_comm_out=0.0;
   v.exp_loss_per_lot=3000.0;
   v.exp_lot=0.11;
   v.exp_risk_money=330.0;
   v.exp_risk_percent=3.3;
   v.exp_margin_needed=123.2264;
   v.exp_spread_points=6.0;
   v.exp_spread_money=0.66;
   v.exp_verdict=PL_BLOCK;
   v.exp_reason=PL_R_STOPOUT_BEFORE_SL;
   v.exp_note=PL_R_NONE;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 61 spread_wide
//| XAUUSD SL $1.30 with spread 0.43: 0.43 > 0.3 * 1.30: WARN PL_R_SPREAD_WIDE
//|   Compare price = mid (Bid+Ask)/2 = (4195.09+4195.52)/2 = 4195.305.
//|   SL line 4194.22 < compare price: BUY.
//|   Order type ORDER_TYPE_BUY, exec = 4195.52.
//|   dist = Ask - SL = 1.3.
//|   ticks = round(1.3 / 0.01) = 130.
//|   (a) ticks * tvl = 130 * 1 = 130.
//|   (c) OrderCalcProfit = 130.
//|   worst = 130 (the larger path), the paths agree.
//|   commission per side 0: in 0, out 0.
//|   loss_per_lot = 130 + 0 + 0 = 130.
//|   base = balance 10000.
//|   target = floor(10000 * 1 / 100, 2) = floor(100) = 100.
//|   lot_raw = 100 / 130 = 0.76923077; lot = 0.01 + floor((lot_raw - 0.01)/0.01 + 1e-8)*0.01 = 0.76.
//|   risk = 0.76 * 130 = 98.8, 0.988% of base 10000.
//|   margin_needed = 0.76 * 8391.04 = 6377.1904, margin_free 10000.
//|   level at SL = (10000 - 98.8) / (0 + 6377.1904) * 100 = 155.259595%, limit so_so+10 = 60.
//|   spread = 43 points, money = 0.43/0.01 * 1 * 0.76 = 32.68.
//|   spread 0.43 > 0.3 * dist 1.3: PL_R_SPREAD_WIDE (WARN).
//|   Verdict PL_WARN, reason PL_R_SPREAD_WIDE.
//+------------------------------------------------------------------+
void PlVec61(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="spread_wide";
   v.what="XAUUSD SL $1.30 with spread 0.43: 0.43 > 0.3 * 1.30: WARN PL_R_SPREAD_WIDE";
   PlVecSymXAUUSD(v.s);
   PlVecAccount(v.a,"USD",2,10000.0,10000.0,0.0,10000.0);
   PlVecInputs(v.in);
   v.in.sl=4194.22;
   v.in.comm.kind=PL_COMM_LOT_SIDE; v.in.comm.rate=0.0; v.in.comm.source=PL_COMMSRC_USER;
   v.in.calcprofit_ok=true; v.in.calcprofit_loss_1lot=130.0;
   //--- expected
   v.chk_prepare_ok=true; v.exp_prepare_ok=true;
   v.exp_plan_reason=PL_R_NONE;
   v.exp_side=PL_SIDE_BUY;
   v.exp_order_type=ORDER_TYPE_BUY;
   v.exp_exec=4195.52;
   v.exp_sl=4194.22;
   v.exp_ticks=130;
   v.exp_lpl_a=130.0;
   v.exp_lpl_price=130.0;
   v.exp_comm_in=0.0;
   v.exp_comm_out=0.0;
   v.exp_loss_per_lot=130.0;
   v.exp_lot=0.76;
   v.exp_risk_money=98.8;
   v.exp_risk_percent=0.988;
   v.exp_margin_needed=6377.1904;
   v.exp_spread_points=43.0;
   v.exp_spread_money=32.68;
   v.exp_verdict=PL_WARN;
   v.exp_reason=PL_R_SPREAD_WIDE;
   v.exp_note=PL_R_NONE;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 62 ger40_sell_normalize
//| GER40 Sell Market, SL line 19050.7 is off the 0.5 grid: normalized down to 19050.5, dist = SL - Bid = 50.5 = 101 ticks, risk 1.2%
//|   Compare price = mid (Bid+Ask)/2 = (19000+19001)/2 = 19000.5.
//|   SL line 19050.7 > compare price: SELL.
//|   Order type ORDER_TYPE_SELL, exec = 19000.
//|   SL 19050.7 normalized down to the tick: 19050.5.
//|   dist = SL - Bid = 50.5.
//|   ticks = round(50.5 / 0.5) = 101.
//|   (a) ticks * tvl = 101 * 0.55 = 55.55.
//|   (c) OrderCalcProfit = 55.55.
//|   worst = 55.55 (the larger path), the paths agree.
//|   commission per side 0: in 0, out 0.
//|   loss_per_lot = 55.55 + 0 + 0 = 55.55.
//|   base = balance 10000.
//|   target = floor(10000 * 1.2 / 100, 2) = floor(120) = 120.
//|   lot_raw = 120 / 55.55 = 2.16021602; lot = 0.1 + floor((lot_raw - 0.1)/0.1 + 1e-8)*0.1 = 2.1.
//|   risk = 2.1 * 55.55 = 116.655, 1.16655% of base 10000.
//|   margin_needed = 2.1 * 1045 = 2194.5, margin_free 10000.
//|   level at SL = (10000 - 116.655) / (0 + 2194.5) * 100 = 450.368877%, limit so_so+10 = 60.
//|   spread = 10 points, money = 1/0.5 * 0.55 * 2.1 = 2.31.
//|   Verdict PL_OK, reason PL_R_NONE.
//+------------------------------------------------------------------+
void PlVec62(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="ger40_sell_normalize";
   v.what="GER40 Sell Market, SL line 19050.7 is off the 0.5 grid: normalized down to 19050.5, dist = SL - Bid = 50.5 = 101 ticks, risk 1.2%";
   PlVecSymGER40(v.s);
   PlVecAccount(v.a,"USD",2,10000.0,10000.0,0.0,10000.0);
   PlVecInputs(v.in);
   v.in.sl=19050.7;
   v.in.risk_percent=1.2;
   v.in.comm.kind=PL_COMM_LOT_SIDE; v.in.comm.rate=0.0; v.in.comm.source=PL_COMMSRC_USER;
   v.in.calcprofit_ok=true; v.in.calcprofit_loss_1lot=55.55;
   //--- expected
   v.chk_prepare_ok=true; v.exp_prepare_ok=true;
   v.exp_plan_reason=PL_R_NONE;
   v.exp_side=PL_SIDE_SELL;
   v.exp_order_type=ORDER_TYPE_SELL;
   v.exp_exec=19000.0;
   v.exp_sl=19050.5;
   v.exp_ticks=101;
   v.exp_lpl_a=55.55;
   v.exp_lpl_price=55.55;
   v.exp_comm_in=0.0;
   v.exp_comm_out=0.0;
   v.exp_loss_per_lot=55.55;
   v.exp_lot=2.1;
   v.exp_risk_money=116.655;
   v.exp_risk_percent=1.16655;
   v.exp_margin_needed=2194.5;
   v.exp_spread_points=10.0;
   v.exp_spread_money=2.31;
   v.exp_verdict=PL_OK;
   v.exp_reason=PL_R_NONE;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 63 base_zero_money
//| Open risk equal to the balance with subtract_open: base 0, MONEY 600 on EURUSD SL 23 pips: the cap cannot be kept, BLOCK
//|   Buy Market, SL 1.11794: dist = Ask - SL = 0.0023, ticks 230, lpl 230, commission 0.
//|   base = 10000 - open risk 10000 = 0, so no percent exists to hold the cap against: BLOCK PL_R_RISK_ABOVE_CAP.
//|   lot_raw = 600 / 230 = 2.6086957, lot 2.60, risk 598.0, margin_needed 2.6 * 1120.24 = 2912.624.
//+------------------------------------------------------------------+
void PlVec63(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="base_zero_money";
   v.what="Open risk equal to the balance with subtract_open: base 0, MONEY 600 on EURUSD SL 23 pips: the cap cannot be kept, BLOCK";
   PlVecSymEURUSD(v.s);
   PlVecAccount(v.a,"USD",2,10000.0,10000.0,0.0,10000.0);
   PlVecInputs(v.in);
   v.a.open_risk_money=10000.0;
   v.in.subtract_open=true;
   v.in.sl=1.11794;
   v.in.risk_mode=PL_RISK_MONEY;
   v.in.risk_money=600.0;
   //--- expected
   v.chk_prepare_ok=true; v.exp_prepare_ok=true;
   v.exp_side=PL_SIDE_BUY;
   v.exp_ticks=230;
   v.exp_lot=2.60000000;
   v.exp_risk_money=598.00000000;
   v.exp_margin_needed=2912.62400000;
   v.exp_verdict=PL_BLOCK;
   v.exp_reason=PL_R_RISK_ABOVE_CAP;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 64 base_zero_percent
//| Same base 0 in PERCENT mode: target 0, minimum lot, CONFIRM would apply but the cap BLOCK wins
//|   Buy Market, SL 1.11794, ticks 230, lpl 230. base 0, target floor(0) = 0, lot_raw 0 < vol_min: lot 0.01.
//|   risk = 0.01 * 230 = 2.3. base 0: BLOCK PL_R_RISK_ABOVE_CAP over CONFIRM PL_R_LOT_BELOW_MIN.
//+------------------------------------------------------------------+
void PlVec64(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="base_zero_percent";
   v.what="Same base 0 in PERCENT mode: target 0, minimum lot, CONFIRM would apply but the cap BLOCK wins";
   PlVecSymEURUSD(v.s);
   PlVecAccount(v.a,"USD",2,10000.0,10000.0,0.0,10000.0);
   PlVecInputs(v.in);
   v.a.open_risk_money=10000.0;
   v.in.subtract_open=true;
   v.in.sl=1.11794;
   //--- expected
   v.chk_prepare_ok=true; v.exp_prepare_ok=true;
   v.exp_side=PL_SIDE_BUY;
   v.exp_ticks=230;
   v.exp_lot=0.01000000;
   v.exp_risk_money=2.30000000;
   v.exp_verdict=PL_BLOCK;
   v.exp_reason=PL_R_RISK_ABOVE_CAP;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 67 lot_raw_hair_below_min
//| lot_raw a hair under vol_min (inside the 1e-8 tolerance): lot is vol_min, never 0
//|   Buy Market, SL 1.11794, ticks 230, lpl 230. risk_money 2.29999885 -> lot_raw = 0.009999995, inside vol_min - 1e-8.
//|   The step floor is clamped at 0: lot = 0.01 (not 0.00), risk 2.3, verdict OK.
//+------------------------------------------------------------------+
void PlVec67(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="lot_raw_hair_below_min";
   v.what="lot_raw a hair under vol_min (inside the 1e-8 tolerance): lot is vol_min, never 0";
   PlVecSymEURUSD(v.s);
   PlVecAccount(v.a,"USD",2,10000.0,10000.0,0.0,10000.0);
   PlVecInputs(v.in);
   v.in.sl=1.11794;
   v.in.risk_mode=PL_RISK_MONEY;
   v.in.risk_money=2.29999885;
   v.in.calcprofit_ok=true; v.in.calcprofit_loss_1lot=230.0;
   //--- expected
   v.chk_prepare_ok=true; v.exp_prepare_ok=true;
   v.exp_side=PL_SIDE_BUY;
   v.exp_ticks=230;
   v.exp_lot=0.01000000;
   v.exp_risk_money=2.30000000;
   v.exp_verdict=PL_OK;
   v.exp_reason=PL_R_NONE;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 68 cross_comm_unknown_note
//| Cross GBPJPY on a USD account with the commission unknown: the note says commission is not counted (it moves the risk), not the cross rate
//|   Same as vector 11 but commission kind UNKNOWN (0 money, no rate): lpl 233.33333333, lot_raw 100 / 233.33333333 = 0.4285714, lot 0.42.
//|   risk = 0.42 * 233.33333333 = 98.0. note PL_R_COMM_UNKNOWN wins over PL_R_CROSS_RATE_AT_SL.
//+------------------------------------------------------------------+
void PlVec68(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="cross_comm_unknown_note";
   v.what="Cross GBPJPY on a USD account with the commission unknown: the note says commission is not counted (it moves the risk), not the cross rate";
   PlVecSymGBPJPY(v.s);
   PlVecAccount(v.a,"USD",2,10000.0,10000.0,0.0,10000.0);
   PlVecInputs(v.in);
   v.in.sl=199.67;
   v.in.comm.kind=PL_COMM_UNKNOWN; v.in.comm.rate=0.0; v.in.comm.source=PL_COMMSRC_NONE;
   v.in.calcprofit_ok=true; v.in.calcprofit_loss_1lot=233.33333333;
   //--- expected
   v.chk_prepare_ok=true; v.exp_prepare_ok=true;
   v.exp_side=PL_SIDE_BUY;
   v.exp_ticks=350;
   v.exp_lpl_a=233.33333333;
   v.exp_loss_per_lot=233.33333333;
   v.exp_lot=0.42000000;
   v.exp_risk_money=98.00000000;
   v.exp_verdict=PL_OK;
   v.exp_reason=PL_R_NONE;
   v.exp_note=PL_R_COMM_UNKNOWN;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 69 margin_missing_blocks
//| The terminal gave no margin for 1 lot (OrderCalcMargin failed): the margin and stop-out checks cannot run, BLOCK
//|   Buy Market, SL 1.11794, 1%: lot 0.43, risk 98.9. margin_buy_1lot = 0: BLOCK PL_R_NO_SYMBOL_DATA (never a silent OK).
//+------------------------------------------------------------------+
void PlVec69(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="margin_missing_blocks";
   v.what="The terminal gave no margin for 1 lot (OrderCalcMargin failed): the margin and stop-out checks cannot run, BLOCK";
   PlVecSymEURUSD(v.s);
   PlVecAccount(v.a,"USD",2,10000.0,10000.0,0.0,10000.0);
   PlVecInputs(v.in);
   v.s.margin_buy_1lot=0.0; v.s.margin_sell_1lot=0.0;
   v.in.sl=1.11794;
   //--- expected
   v.chk_prepare_ok=true; v.exp_prepare_ok=true;
   v.exp_side=PL_SIDE_BUY;
   v.exp_ticks=230;
   v.exp_lot=0.43000000;
   v.exp_risk_money=98.90000000;
   v.exp_verdict=PL_BLOCK;
   v.exp_reason=PL_R_NO_SYMBOL_DATA;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 70 swap_symbol_currency
//| Swap in the base currency of the symbol (EUR) on a USD account: converted at the mid price
//|   Buy Market, SL 1.11794, 1%: ticks 230, lpl 230, lot 0.43 (100 / 230 = 0.4347826).
//|   mid = (1.12018 + 1.12024) / 2 = 1.12021. swap_long -5 * 0.43 * 1.12021 = -2.40845150, swap_short 1 * 0.43 * 1.12021 = 0.48169030.
//+------------------------------------------------------------------+
void PlVec70(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="swap_symbol_currency";
   v.what="Swap in the base currency of the symbol (EUR) on a USD account: converted at the mid price";
   PlVecSymEURUSD(v.s);
   PlVecAccount(v.a,"USD",2,10000.0,10000.0,0.0,10000.0);
   PlVecInputs(v.in);
   v.s.swap_mode=SYMBOL_SWAP_MODE_CURRENCY_SYMBOL; v.s.swap_long=-5.0; v.s.swap_short=1.0;
   v.in.sl=1.11794;
   v.in.calcprofit_ok=true; v.in.calcprofit_loss_1lot=230.0;
   //--- expected
   v.chk_prepare_ok=true; v.exp_prepare_ok=true;
   v.exp_side=PL_SIDE_BUY;
   v.exp_ticks=230;
   v.exp_lot=0.43000000;
   v.exp_swap_long=-2.40845150;
   v.exp_swap_short=0.48169030;
   v.exp_swap_ok=1;
   v.exp_verdict=PL_OK;
   v.exp_reason=PL_R_NONE;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 71 swap_margin_currency
//| Swap in the margin currency (here USD, equal to the account currency): no conversion
//|   Buy Market, SL 1.11794, 1%: ticks 230, lpl 230, lot 0.43 (100 / 230 = 0.4347826).
//|   margin currency USD = account currency: swap_long -3 * 0.43 = -1.29, swap_short 0.5 * 0.43 = 0.215.
//+------------------------------------------------------------------+
void PlVec71(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="swap_margin_currency";
   v.what="Swap in the margin currency (here USD, equal to the account currency): no conversion";
   PlVecSymEURUSD(v.s);
   PlVecAccount(v.a,"USD",2,10000.0,10000.0,0.0,10000.0);
   PlVecInputs(v.in);
   v.s.margin="USD"; v.s.swap_mode=SYMBOL_SWAP_MODE_CURRENCY_MARGIN; v.s.swap_long=-3.0; v.s.swap_short=0.5;
   v.in.sl=1.11794;
   v.in.calcprofit_ok=true; v.in.calcprofit_loss_1lot=230.0;
   //--- expected
   v.chk_prepare_ok=true; v.exp_prepare_ok=true;
   v.exp_side=PL_SIDE_BUY;
   v.exp_ticks=230;
   v.exp_lot=0.43000000;
   v.exp_swap_long=-1.29000000;
   v.exp_swap_short=0.21500000;
   v.exp_swap_ok=1;
   v.exp_verdict=PL_OK;
   v.exp_reason=PL_R_NONE;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 72 swap_margin_currency_eur
//| Swap in the margin currency EUR on a USD account: converted at the mid price
//|   Buy Market, SL 1.11794, 1%: ticks 230, lpl 230, lot 0.43 (100 / 230 = 0.4347826).
//|   margin currency EUR = base: swap_long -3 * 0.43 * 1.12021 = -1.44507090, swap_short 0.5 * 0.43 * 1.12021 = 0.24084515.
//+------------------------------------------------------------------+
void PlVec72(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="swap_margin_currency_eur";
   v.what="Swap in the margin currency EUR on a USD account: converted at the mid price";
   PlVecSymEURUSD(v.s);
   PlVecAccount(v.a,"USD",2,10000.0,10000.0,0.0,10000.0);
   PlVecInputs(v.in);
   v.s.swap_mode=SYMBOL_SWAP_MODE_CURRENCY_MARGIN; v.s.swap_long=-3.0; v.s.swap_short=0.5;
   v.in.sl=1.11794;
   v.in.calcprofit_ok=true; v.in.calcprofit_loss_1lot=230.0;
   //--- expected
   v.chk_prepare_ok=true; v.exp_prepare_ok=true;
   v.exp_side=PL_SIDE_BUY;
   v.exp_ticks=230;
   v.exp_lot=0.43000000;
   v.exp_swap_long=-1.44507090;
   v.exp_swap_short=0.24084515;
   v.exp_swap_ok=1;
   v.exp_verdict=PL_OK;
   v.exp_reason=PL_R_NONE;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 73 swap_deposit_currency
//| Swap in the deposit currency: used as it is
//|   Buy Market, SL 1.11794, 1%: ticks 230, lpl 230, lot 0.43 (100 / 230 = 0.4347826).
//|   swap_long -4 * 0.43 = -1.72, swap_short 0.5 * 0.43 = 0.215.
//+------------------------------------------------------------------+
void PlVec73(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="swap_deposit_currency";
   v.what="Swap in the deposit currency: used as it is";
   PlVecSymEURUSD(v.s);
   PlVecAccount(v.a,"USD",2,10000.0,10000.0,0.0,10000.0);
   PlVecInputs(v.in);
   v.s.swap_mode=SYMBOL_SWAP_MODE_CURRENCY_DEPOSIT; v.s.swap_long=-4.0; v.s.swap_short=0.5;
   v.in.sl=1.11794;
   v.in.calcprofit_ok=true; v.in.calcprofit_loss_1lot=230.0;
   //--- expected
   v.chk_prepare_ok=true; v.exp_prepare_ok=true;
   v.exp_side=PL_SIDE_BUY;
   v.exp_ticks=230;
   v.exp_lot=0.43000000;
   v.exp_swap_long=-1.72000000;
   v.exp_swap_short=0.21500000;
   v.exp_swap_ok=1;
   v.exp_verdict=PL_OK;
   v.exp_reason=PL_R_NONE;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 74 swap_points
//| Swap in points (FTMO EURUSD -9.41 / 0.1): points * point / tick_size * tick_value_profit * lot
//|   Buy Market, SL 1.11794, 1%: ticks 230, lpl 230, lot 0.43 (100 / 230 = 0.4347826).
//|   swap_long -9.41 * 0.00001 / 0.00001 * 1 * 0.43 = -4.0463, swap_short 0.1 * 0.43 = 0.043.
//+------------------------------------------------------------------+
void PlVec74(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="swap_points";
   v.what="Swap in points (FTMO EURUSD -9.41 / 0.1): points * point / tick_size * tick_value_profit * lot";
   PlVecSymEURUSD(v.s);
   PlVecAccount(v.a,"USD",2,10000.0,10000.0,0.0,10000.0);
   PlVecInputs(v.in);
   v.in.sl=1.11794;
   v.in.calcprofit_ok=true; v.in.calcprofit_loss_1lot=230.0;
   //--- expected
   v.chk_prepare_ok=true; v.exp_prepare_ok=true;
   v.exp_side=PL_SIDE_BUY;
   v.exp_ticks=230;
   v.exp_lot=0.43000000;
   v.exp_swap_long=-4.04630000;
   v.exp_swap_short=0.04300000;
   v.exp_swap_ok=1;
   v.exp_verdict=PL_OK;
   v.exp_reason=PL_R_NONE;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 75 swap_interest_btc
//| BTCUSD interest swap: price * contract * swap / 100 / 360 * k * lot
//|   Buy Market, SL 83000.00: dist = Ask - SL = 797.56, ticks 79756, lpl 79756 * 0.01 = 797.56. lot_raw 100 / 797.56 = 0.1253, lot 0.12.
//|   mid = 83797.06. swap -30 percent: 83797.06 * 1 * (-30) / 100 / 360 * 1 * 0.12 = -8.37970600.
//+------------------------------------------------------------------+
void PlVec75(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="swap_interest_btc";
   v.what="BTCUSD interest swap: price * contract * swap / 100 / 360 * k * lot";
   PlVecSymBTCUSD(v.s);
   PlVecAccount(v.a,"USD",2,10000.0,10000.0,0.0,10000.0);
   PlVecInputs(v.in);
   v.in.sl=83000.0;
   v.in.calcprofit_ok=true; v.in.calcprofit_loss_1lot=797.56000000;
   //--- expected
   v.chk_prepare_ok=true; v.exp_prepare_ok=true;
   v.exp_side=PL_SIDE_BUY;
   v.exp_ticks=79756;
   v.exp_lpl_a=797.56000000;
   v.exp_lot=0.12000000;
   v.exp_swap_long=-8.37970600;
   v.exp_swap_short=-8.37970600;
   v.exp_swap_ok=1;
   v.exp_verdict=PL_OK;
   v.exp_reason=PL_R_NONE;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 76 stops_market_sl_closing
//| StopsLevel counts from the closing price: Buy market SL 1.11992 is 32 points under Ask but only 26 under Bid, so SL_TOO_CLOSE
//|   EURUSD with stops_level 30 points = 0.0003. Buy Market, SL 1.11992: dist = Ask - SL = 0.00032 (32 ticks, passes 2 spreads 0.00012 and 3 ticks).
//|   Closing distance Bid - SL = 1.12018 - 1.11992 = 0.00026 < 0.0003: PL_R_SL_TOO_CLOSE, BLOCK.
//+------------------------------------------------------------------+
void PlVec76(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="stops_market_sl_closing";
   v.what="StopsLevel counts from the closing price: Buy market SL 1.11992 is 32 points under Ask but only 26 under Bid, so SL_TOO_CLOSE";
   PlVecSymEURUSD(v.s);
   PlVecAccount(v.a,"USD",2,10000.0,10000.0,0.0,10000.0);
   PlVecInputs(v.in);
   v.s.stops_level=30;
   v.in.sl=1.11992;
   //--- expected
   v.exp_plan_reason=PL_R_SL_TOO_CLOSE;
   v.exp_side=PL_SIDE_BUY;
   v.exp_ticks=32;
   v.exp_verdict=PL_BLOCK;
   v.exp_reason=PL_R_SL_TOO_CLOSE;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 77 stops_market_sl_ok
//| Buy market SL 1.11980: 44 points under Ask, 38 under Bid: passes StopsLevel 30
//|   EURUSD with stops_level 30 points = 0.0003. Buy Market, SL 1.11980: dist 0.00044, ticks 44, lpl 44. Closing distance 0.00038 >= 0.0003.
//|   lot_raw = 100 / 44 = 2.2727, lot 2.27, risk 99.88.
//+------------------------------------------------------------------+
void PlVec77(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="stops_market_sl_ok";
   v.what="Buy market SL 1.11980: 44 points under Ask, 38 under Bid: passes StopsLevel 30";
   PlVecSymEURUSD(v.s);
   PlVecAccount(v.a,"USD",2,10000.0,10000.0,0.0,10000.0);
   PlVecInputs(v.in);
   v.s.stops_level=30;
   v.in.sl=1.1198;
   v.in.calcprofit_ok=true; v.in.calcprofit_loss_1lot=44.0;
   //--- expected
   v.chk_prepare_ok=true; v.exp_prepare_ok=true;
   v.exp_plan_reason=PL_R_NONE;
   v.exp_side=PL_SIDE_BUY;
   v.exp_ticks=44;
   v.exp_lot=2.27000000;
   v.exp_risk_money=99.88000000;
   v.exp_verdict=PL_OK;
   v.exp_reason=PL_R_NONE;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 78 stops_pending_boundary_ok
//| Buy Limit 1.11800, SL 1.11769: distance 31 points (StopsLevel plus one point): allowed
//|   EURUSD with stops_level 30 points. Buy Limit 1.118 (below Ask), SL 1.11769: dist = |exec - SL| = 0.00031, ticks 31, lpl 31.
//|   lot_raw = 100 / 31 = 3.2258, lot 3.22, risk 3.22 * 31 = 99.82. (exactly 30 points is refused now: vector 79 is 29, the new boundary vector 107 is 30)
//+------------------------------------------------------------------+
void PlVec78(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="stops_pending_boundary_ok";
   v.what="Buy Limit 1.11800, SL 1.11769: distance 31 points (StopsLevel 30 plus one): allowed";
   PlVecSymEURUSD(v.s);
   PlVecAccount(v.a,"USD",2,10000.0,10000.0,0.0,10000.0);
   PlVecInputs(v.in);
   v.s.stops_level=30;
   v.in.kind=PL_KIND_LIMIT; v.in.entry=1.118;
   v.in.sl=1.11769;
   v.in.calcprofit_ok=true; v.in.calcprofit_loss_1lot=31.0;
   //--- expected
   v.chk_prepare_ok=true; v.exp_prepare_ok=true;
   v.exp_plan_reason=PL_R_NONE;
   v.exp_side=PL_SIDE_BUY;
   v.exp_ticks=31;
   v.exp_lot=3.22000000;
   v.exp_risk_money=99.82000000;
   v.exp_verdict=PL_OK;
   v.exp_reason=PL_R_NONE;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 79 stops_pending_too_close
//| Buy Limit 1.11800, SL 1.11771: 29 points: SL_TOO_CLOSE
//|   EURUSD with stops_level 30 points = 0.0003. Buy Limit 1.118, SL 1.11771: dist 0.00029 < 0.0003: PL_R_SL_TOO_CLOSE, BLOCK.
//+------------------------------------------------------------------+
void PlVec79(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="stops_pending_too_close";
   v.what="Buy Limit 1.11800, SL 1.11771: 29 points: SL_TOO_CLOSE";
   PlVecSymEURUSD(v.s);
   PlVecAccount(v.a,"USD",2,10000.0,10000.0,0.0,10000.0);
   PlVecInputs(v.in);
   v.s.stops_level=30;
   v.in.kind=PL_KIND_LIMIT; v.in.entry=1.118;
   v.in.sl=1.11771;
   //--- expected
   v.exp_plan_reason=PL_R_SL_TOO_CLOSE;
   v.exp_side=PL_SIDE_BUY;
   v.exp_ticks=29;
   v.exp_verdict=PL_BLOCK;
   v.exp_reason=PL_R_SL_TOO_CLOSE;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 80 stops_market_tp_ok
//| Buy market TP 1.12052: 34 points over Bid (the closing price), 28 over Ask: allowed by StopsLevel 30
//|   EURUSD with stops_level 30 points = 0.0003. Buy Market, SL 1.117: dist = Ask - SL = 0.00324, ticks 324, lpl 324. lot_raw 100 / 324 = 0.3086, lot 0.30, risk 97.2.
//|   TP price 1.12052: TP - Bid = 0.00034 >= 0.0003. Reward = 0.30 * (28 ticks * 1) = 8.4, rr = 8.4 / 97.2 = 0.08641975.
//+------------------------------------------------------------------+
void PlVec80(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="stops_market_tp_ok";
   v.what="Buy market TP 1.12052: 34 points over Bid (the closing price), 28 over Ask: allowed by StopsLevel 30";
   PlVecSymEURUSD(v.s);
   PlVecAccount(v.a,"USD",2,10000.0,10000.0,0.0,10000.0);
   PlVecInputs(v.in);
   v.s.stops_level=30;
   v.in.sl=1.117;
   v.in.no_tp=false;
   v.in.tp[0].on=true; v.in.tp[0].mode=PL_TP_PRICE; v.in.tp[0].price=1.12052; v.in.tp[0].share=100.0;
   v.in.calcprofit_ok=true; v.in.calcprofit_loss_1lot=324.0;
   //--- expected
   v.chk_prepare_ok=true; v.exp_prepare_ok=true;
   v.exp_plan_reason=PL_R_NONE;
   v.exp_side=PL_SIDE_BUY;
   v.exp_tp=1.12052000;
   v.exp_ticks=324;
   v.exp_lot=0.30000000;
   v.exp_risk_money=97.20000000;
   v.exp_reward_total=8.40000000;
   v.exp_rr=0.08641975;
   v.exp_verdict=PL_OK;
   v.exp_reason=PL_R_NONE;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 81 stops_market_tp_too_close
//| Buy market TP 1.12040: 22 points over Bid: TP_TOO_CLOSE
//|   EURUSD with stops_level 30 points = 0.0003. Buy Market, SL 1.117. TP price 1.1204: TP - Bid = 0.00022 < 0.0003: PL_R_TP_TOO_CLOSE, BLOCK.
//+------------------------------------------------------------------+
void PlVec81(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="stops_market_tp_too_close";
   v.what="Buy market TP 1.12040: 22 points over Bid: TP_TOO_CLOSE";
   PlVecSymEURUSD(v.s);
   PlVecAccount(v.a,"USD",2,10000.0,10000.0,0.0,10000.0);
   PlVecInputs(v.in);
   v.s.stops_level=30;
   v.in.sl=1.117;
   v.in.no_tp=false;
   v.in.tp[0].on=true; v.in.tp[0].mode=PL_TP_PRICE; v.in.tp[0].price=1.1204; v.in.tp[0].share=100.0;
   //--- expected
   v.exp_plan_reason=PL_R_TP_TOO_CLOSE;
   v.exp_side=PL_SIDE_BUY;
   v.exp_ticks=324;
   v.exp_verdict=PL_BLOCK;
   v.exp_reason=PL_R_TP_TOO_CLOSE;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 82 stopout_money_block
//| Stop-out level in money 9500 (assumed meaning: free margin at the SL must stay at or above it): BLOCK
//|   Buy Market, SL 1.11794, 1%: lot 0.43, risk 98.9, margin_needed 481.7032.
//|   Free margin at SL = 10000 - 98.9 - 0 - 481.7032 = 9419.3968 < 9500: PL_R_STOPOUT_BEFORE_SL.
//|   max lot = (10000 - 0 - 9500) / (230 + 1120.24) = 0.37032, floored to 0.37.
//+------------------------------------------------------------------+
void PlVec82(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="stopout_money_block";
   v.what="Stop-out level in money 9500 (assumed meaning: free margin at the SL must stay at or above it): BLOCK";
   PlVecSymEURUSD(v.s);
   PlVecAccount(v.a,"USD",2,10000.0,10000.0,0.0,10000.0);
   PlVecInputs(v.in);
   v.a.so_mode=ACCOUNT_STOPOUT_MODE_MONEY; v.a.so_call=0.0; v.a.so_so=9500.0;
   v.in.sl=1.11794;
   //--- expected
   v.chk_prepare_ok=true; v.exp_prepare_ok=true;
   v.exp_side=PL_SIDE_BUY;
   v.exp_ticks=230;
   v.exp_lot=0.43000000;
   v.exp_risk_money=98.90000000;
   v.exp_margin_needed=481.70320000;
   v.exp_verdict=PL_BLOCK;
   v.exp_reason=PL_R_STOPOUT_BEFORE_SL;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 83 stopout_money_ok
//| Stop-out level in money 3000: far away, OK and the max lot from the money formula
//|   Buy Market, SL 1.11794, 1%: lot 0.43. Free margin at SL 9419.3968 >= 3000.
//|   max lot = min(10000 / 1120.24 = 8.93, (10000 - 3000) / 1350.24 = 5.18416) = 5.18.
//+------------------------------------------------------------------+
void PlVec83(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="stopout_money_ok";
   v.what="Stop-out level in money 3000: far away, OK and the max lot from the money formula";
   PlVecSymEURUSD(v.s);
   PlVecAccount(v.a,"USD",2,10000.0,10000.0,0.0,10000.0);
   PlVecInputs(v.in);
   v.a.so_mode=ACCOUNT_STOPOUT_MODE_MONEY; v.a.so_call=0.0; v.a.so_so=3000.0;
   v.in.sl=1.11794;
   v.in.calcprofit_ok=true; v.in.calcprofit_loss_1lot=230.0;
   //--- expected
   v.chk_prepare_ok=true; v.exp_prepare_ok=true;
   v.exp_side=PL_SIDE_BUY;
   v.exp_ticks=230;
   v.exp_lot=0.43000000;
   v.exp_verdict=PL_OK;
   v.exp_reason=PL_R_NONE;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 84 cap_percent_mode
//| PERCENT 6 with the cap at 5: 2.60 lots, risk 598 = 5.98% of 10000: BLOCK
//|   Buy Market, SL 1.11794, ticks 230, lpl 230. target floor(10000 * 6 / 100) = 600, lot_raw 2.6087, lot 2.60, risk 598.0, 5.98% > cap 5.
//+------------------------------------------------------------------+
void PlVec84(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="cap_percent_mode";
   v.what="PERCENT 6 with the cap at 5: 2.60 lots, risk 598 = 5.98% of 10000: BLOCK";
   PlVecSymEURUSD(v.s);
   PlVecAccount(v.a,"USD",2,10000.0,10000.0,0.0,10000.0);
   PlVecInputs(v.in);
   v.in.sl=1.11794;
   v.in.risk_percent=6.0;
   //--- expected
   v.chk_prepare_ok=true; v.exp_prepare_ok=true;
   v.exp_side=PL_SIDE_BUY;
   v.exp_ticks=230;
   v.exp_lot=2.60000000;
   v.exp_risk_money=598.00000000;
   v.exp_risk_percent=5.98000000;
   v.exp_verdict=PL_BLOCK;
   v.exp_reason=PL_R_RISK_ABOVE_CAP;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 85 nikkei_rounding_tolerance
//| Nikkei225-like CFD on a UST account (PROBE-B shape): (a) 0.3162 and (c) 0.32 differ by rounding of OrderCalcProfit to 2 digits, no PATHS_DISAGREE
//|   Compare price = mid = 48005; SL 47960 below: BUY, exec = Ask 48010.
//|   dist = 50.00 = 5000 ticks of 0.01.
//|   (a) 5000 * 0.00006324 = 0.3162; (c) OrderCalcProfit rounds to the account digits: 0.32.
//|   |a - c| = 0.0038 <= 0.01 * 0.32 + 0.5 * 10^-2 = 0.0082: agree (the old flat 1 percent would have blocked: 1.2 percent).
//|   Relation is cross (tick value is not a USD rate) but the mode is CFD: no cross note.
//|   lpl_price = max(a, c) = 0.32. Commission 0. RISK_MONEY 10: lot_raw = 10 / 0.32 = 31.25, lot 31.2, risk 31.2 * 0.32 = 9.984.
//|   Spread 10.00 = 1000 ticks, 2 spreads = 2000 ticks < 5000; spread share 10 / 50 = 20 percent < 30.
//|   Verdict PL_OK, reason PL_R_NONE, note PL_R_NONE.
//+------------------------------------------------------------------+
void PlVec85(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="nikkei_rounding_tolerance";
   v.what="Nikkei225-like CFD on a UST account: tick value 0.3162 against OrderCalcProfit 0.32 (rounding to 2 digits) must agree";
   v.s.name="Nikkei225";
   v.s.base="JPY";
   v.s.profit="JPY";
   v.s.margin="JPY";
   v.s.calc_mode=SYMBOL_CALC_MODE_CFD;
   v.s.digits=2;
   v.s.point=0.01;
   v.s.tick_size=0.01;
   v.s.tick_value_loss=0.00006324;
   v.s.tick_value_profit=0.00006324;
   v.s.contract=1.0;
   v.s.vol_min=0.1;
   v.s.vol_max=100.0;
   v.s.vol_step=0.1;
   v.s.vol_limit=0.0;
   v.s.vol_open_buy=0.0; v.s.vol_open_sell=0.0;
   v.s.stops_level=0;
   v.s.freeze_level=0;
   v.s.order_mode=127;
   v.s.filling_mode=3;
   v.s.exec_mode=SYMBOL_TRADE_EXECUTION_MARKET;
   v.s.expiration_mode=15;
   v.s.gtc_mode=SYMBOL_ORDERS_GTC;
   v.s.bid=48000.00;
   v.s.ask=48010.00;
   v.s.session_open=true;
   v.s.swap_mode=SYMBOL_SWAP_MODE_DISABLED;
   v.s.swap_3day=WEDNESDAY;
   v.s.margin_buy_1lot=10.0;
   v.s.margin_sell_1lot=10.0;
   v.s.tick_time=D'2026.10.09 12:00:00';
   v.s.server_now=D'2026.10.09 12:00:00';
   PlVecAccount(v.a,"UST",2,10000.0,10000.0,0.0,10000.0);
   PlVecInputs(v.in);
   v.in.sl=47960.00;
   v.in.risk_mode=PL_RISK_MONEY;
   v.in.risk_money=10.0;
   v.in.comm.kind=PL_COMM_LOT_SIDE; v.in.comm.rate=0.0; v.in.comm.source=PL_COMMSRC_USER;
   v.in.calcprofit_ok=true; v.in.calcprofit_loss_1lot=0.32;
   //--- expected
   v.chk_prepare_ok=true; v.exp_prepare_ok=true;
   v.exp_side=PL_SIDE_BUY;
   v.exp_ticks=5000;
   v.exp_lpl_a=0.3162;
   v.exp_lpl_c=0.32;
   v.exp_lpl_price=0.32;
   v.exp_lot=31.2;
   v.exp_risk_money=9.984;
   v.exp_verdict=PL_OK;
   v.exp_reason=PL_R_NONE;
   v.exp_note=PL_R_NONE;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 86 limit_entry_off_tick
//| GER40 Buy Limit typed at 18949.8 (tick 0.5): exec is the nearest tick 18950.0
//|   Buy Limit 18949.8 -> 18950.0 (below Ask 19001). SL 18900: dist = 50 = 100 ticks.
//|   (a) 100 * 0.55 = 55, (c) 55. lot_raw 100 / 55 = 1.818, lot 1.8, risk 99.0, margin 1.8 * 1045.06 = 1881.108.
//|   spread 1.0 = 10 points, money 1.0 / 0.5 * 0.55 * 1.8 = 1.98.
//+------------------------------------------------------------------+
void PlVec86(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="limit_entry_off_tick";
   v.what="GER40 Buy Limit typed at 18949.8 (tick 0.5): exec is the nearest tick 18950.0";
   PlVecSymGER40(v.s);
   PlVecAccount(v.a,"USD",2,10000.0,10000.0,0.0,10000.0);
   PlVecInputs(v.in);
   v.in.kind=PL_KIND_LIMIT; v.in.entry=18949.8;
   v.in.sl=18900.0;
   v.in.comm.kind=PL_COMM_LOT_SIDE; v.in.comm.rate=0.0; v.in.comm.source=PL_COMMSRC_USER;
   v.in.calcprofit_ok=true; v.in.calcprofit_loss_1lot=55.00000000;
   //--- expected
   v.chk_prepare_ok=true; v.exp_prepare_ok=true;
   v.exp_side=PL_SIDE_BUY;
   v.exp_exec=18950.00000000;
   v.exp_sl=18900.00000000;
   v.exp_ticks=100;
   v.exp_lpl_a=55.00000000;
   v.exp_lot=1.80000000;
   v.exp_risk_money=99.00000000;
   v.exp_margin_needed=1881.10800000;
   v.exp_spread_points=10.00000000;
   v.exp_spread_money=1.98000000;
   v.exp_verdict=PL_OK;
   v.exp_reason=PL_R_NONE;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 87 usdjpy_buy_calcprofit_3pct
//| USDJPY Buy with a 3% SL on the Sunday open quote (Bid 158.232, Ask 158.358), path (c) given: (a) with the SL-rate correction (account = base by data) and OrderCalcProfit agree
//|   Numbers from the demo probe 11.10.2026: tick_value_loss = 100 / Bid = 0.63198342, SL 153.547, ticks 4811.
//|   (a) = 4811 * 0.001 * 100000 / 153.547 = 3133.24259022, (c) OrderCalcProfit = 4811 * 0.001 * 100000 / 153.547 = 3133.24259022 (loss in USD at the SL rate).
//|   Paths agree to 1e-8: no PATHS_DISAGREE. Commission 0. lot_raw = 100 / 3133.2426, lot 0.03.
//+------------------------------------------------------------------+
void PlVec87(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="usdjpy_buy_calcprofit_3pct";
   v.what="USDJPY Buy with a 3% SL on the Sunday open quote (Bid 158.232, Ask 158.358), path (c) given: (a) with the SL-rate correction and OrderCalcProfit agree";
   PlVecSymUSDJPY(v.s);
   v.s.bid=158.232; v.s.ask=158.358; v.s.tick_value_loss=0.63198342; v.s.tick_value_profit=100.0/158.358;
   PlVecAccount(v.a,"USD",2,10000.0,10000.0,0.0,10000.0);
   PlVecInputs(v.in);
   v.in.sl=153.547;
   v.in.calcprofit_ok=true;
   v.in.calcprofit_loss_1lot=3133.24259022;
   v.in.comm.kind=PL_COMM_LOT_SIDE; v.in.comm.rate=0.0; v.in.comm.source=PL_COMMSRC_USER;
   //--- expected
   v.chk_prepare_ok=true; v.exp_prepare_ok=true;
   v.exp_side=PL_SIDE_BUY;
   v.exp_ticks=4811;
   v.exp_lpl_a=3133.24259022;
   v.exp_lpl_c=3133.24259022;
   v.exp_lpl_price=3133.24259022;
   v.exp_lot=0.03000000;
   v.exp_risk_money=93.99727771;
   v.exp_verdict=PL_OK;
   v.exp_reason=PL_R_NONE;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 88 usdjpy_sell_calcprofit_3pct
//| USDJPY Sell with a 3% SL on the Sunday open quote (Bid 158.232, Ask 158.358), path (c) given: (a) with the SL-rate correction (account = base by data) and OrderCalcProfit agree
//|   Numbers from the demo probe 11.10.2026: tick_value_loss = 100 / Bid = 0.63198342, SL 162.98, ticks 4748.
//|   (a) = 4748 * 0.001 * 100000 / 162.98 = 2913.24088845, (c) OrderCalcProfit = 4748 * 0.001 * 100000 / 162.98 = 2913.24088845 (loss in USD at the SL rate).
//|   Paths agree to 1e-8: no PATHS_DISAGREE. Commission 0. lot_raw = 100 / 2913.2409, lot 0.03.
//+------------------------------------------------------------------+
void PlVec88(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="usdjpy_sell_calcprofit_3pct";
   v.what="USDJPY Sell with a 3% SL on the Sunday open quote (Bid 158.232, Ask 158.358), path (c) given: (a) with the SL-rate correction and OrderCalcProfit agree";
   PlVecSymUSDJPY(v.s);
   v.s.bid=158.232; v.s.ask=158.358; v.s.tick_value_loss=0.63198342; v.s.tick_value_profit=100.0/158.358;
   PlVecAccount(v.a,"USD",2,10000.0,10000.0,0.0,10000.0);
   PlVecInputs(v.in);
   v.in.sl=162.98;
   v.in.calcprofit_ok=true;
   v.in.calcprofit_loss_1lot=2913.24088845;
   v.in.comm.kind=PL_COMM_LOT_SIDE; v.in.comm.rate=0.0; v.in.comm.source=PL_COMMSRC_USER;
   //--- expected
   v.chk_prepare_ok=true; v.exp_prepare_ok=true;
   v.exp_side=PL_SIDE_SELL;
   v.exp_ticks=4748;
   v.exp_lpl_a=2913.24088845;
   v.exp_lpl_c=2913.24088845;
   v.exp_lpl_price=2913.24088845;
   v.exp_lot=0.03000000;
   v.exp_risk_money=87.39722665;
   v.exp_verdict=PL_OK;
   v.exp_reason=PL_R_NONE;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 89 split_exactly_max
//| Split on, lot exactly the broker max 50.00: one order, no split, OK
//|   EURUSD (vol_min 0.01, step 0.01, vol_max 50), Ask 1.12024, SL 1.11824, 20 pips, 200 USD per lot.
//|   Risk in money = lot * 200, so the lot comes out exactly (loss 200 per lot, no commission), balance 100 000 000 so no cap, confirmation or margin check can interfere.
//|   Split: n = ceil(lot / vol_max), floor(lot / n) steps each, the remainder one step to the first parts.
//|   Lot 50.00 = vol_max: not above it, so no split: split_n 0, lot 50.00, risk 50 * 200 = 10000, OK.
//+------------------------------------------------------------------+
void PlVec89(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="split_exactly_max";
   v.what="Split on, lot exactly the broker max 50.00: one order, no split, OK";
   PlVecSymEURUSD(v.s);
   PlVecAccount(v.a,"USD",2,100000000.0,100000000.0,0.0,100000000.0);
   PlVecInputs(v.in);
   v.in.sl=1.11824;
   v.in.calcprofit_ok=true;
   v.in.calcprofit_loss_1lot=200.0;
   v.in.risk_mode=PL_RISK_MONEY;
   v.in.risk_money=10000.0;   // lot 50.00 at 200 per lot
   v.in.over_max=PL_OVER_SPLIT;
   v.in.comm.kind=PL_COMM_LOT_SIDE; v.in.comm.rate=0.0; v.in.comm.source=PL_COMMSRC_USER;
   //--- expected
   v.chk_prepare_ok=true; v.exp_prepare_ok=true;
   v.exp_side=PL_SIDE_BUY;
   v.exp_lot=50.00;
   v.exp_risk_money=10000.0;
   v.exp_verdict=PL_OK;
   v.exp_reason=PL_R_NONE;
   v.exp_split_n=0;
   v.exp_split_need=0;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 90 split_two_full_orders
//| Split on, lot 100.00 = two times max: two orders of 50.00, CONFIRM
//|   EURUSD (vol_min 0.01, step 0.01, vol_max 50), Ask 1.12024, SL 1.11824, 20 pips, 200 USD per lot.
//|   Risk in money = lot * 200, so the lot comes out exactly (loss 200 per lot, no commission), balance 100 000 000 so no cap, confirmation or margin check can interfere.
//|   Split: n = ceil(lot / vol_max), floor(lot / n) steps each, the remainder one step to the first parts.
//|   Steps: 100.00 / 0.01 = 10000; vol_max = 5000 steps; n = ceil(10000 / 5000) = 2.
//|   floor(10000 / 2) = 5000 steps, remainder 0: 50.00 and 50.00 (sum 100.00).
//|   Lot stays 100.00 (the whole lot), risk 100 * 200 = 20000. Verdict CONFIRM, reason PL_R_SPLIT_ORDERS.
//+------------------------------------------------------------------+
void PlVec90(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="split_two_full_orders";
   v.what="Split on, lot 100.00 = two times max: two orders of 50.00, CONFIRM";
   PlVecSymEURUSD(v.s);
   PlVecAccount(v.a,"USD",2,100000000.0,100000000.0,0.0,100000000.0);
   PlVecInputs(v.in);
   v.in.sl=1.11824;
   v.in.calcprofit_ok=true;
   v.in.calcprofit_loss_1lot=200.0;
   v.in.risk_mode=PL_RISK_MONEY;
   v.in.risk_money=20000.0;   // lot 100.00 at 200 per lot
   v.in.over_max=PL_OVER_SPLIT;
   v.in.comm.kind=PL_COMM_LOT_SIDE; v.in.comm.rate=0.0; v.in.comm.source=PL_COMMSRC_USER;
   //--- expected
   v.chk_prepare_ok=true; v.exp_prepare_ok=true;
   v.exp_side=PL_SIDE_BUY;
   v.exp_lot=100.00;
   v.exp_risk_money=20000.0;
   v.exp_verdict=PL_CONFIRM;
   v.exp_reason=PL_R_SPLIT_ORDERS;
   v.exp_split_n=2;
   v.exp_split_need=2;
   v.exp_split[0]=50.0;
   v.exp_split[1]=50.0;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 91 split_max_plus_step
//| Split on, lot 50.01 = max plus one step: 25.01 and 25.00
//|   EURUSD (vol_min 0.01, step 0.01, vol_max 50), Ask 1.12024, SL 1.11824, 20 pips, 200 USD per lot.
//|   Risk in money = lot * 200, so the lot comes out exactly (loss 200 per lot, no commission), balance 100 000 000 so no cap, confirmation or margin check can interfere.
//|   Split: n = ceil(lot / vol_max), floor(lot / n) steps each, the remainder one step to the first parts.
//|   Steps: 5001; n = ceil(5001 / 5000) = 2; floor(5001 / 2) = 2500 steps, remainder 5001 - 5000 = 1.
//|   First order 2501 steps = 25.01, second 2500 steps = 25.00; sum 50.01. Risk 50.01 * 200 = 10002.
//+------------------------------------------------------------------+
void PlVec91(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="split_max_plus_step";
   v.what="Split on, lot 50.01 = max plus one step: 25.01 and 25.00";
   PlVecSymEURUSD(v.s);
   PlVecAccount(v.a,"USD",2,100000000.0,100000000.0,0.0,100000000.0);
   PlVecInputs(v.in);
   v.in.sl=1.11824;
   v.in.calcprofit_ok=true;
   v.in.calcprofit_loss_1lot=200.0;
   v.in.risk_mode=PL_RISK_MONEY;
   v.in.risk_money=10002.0;   // lot 50.01 at 200 per lot
   v.in.over_max=PL_OVER_SPLIT;
   v.in.comm.kind=PL_COMM_LOT_SIDE; v.in.comm.rate=0.0; v.in.comm.source=PL_COMMSRC_USER;
   //--- expected
   v.chk_prepare_ok=true; v.exp_prepare_ok=true;
   v.exp_side=PL_SIDE_BUY;
   v.exp_lot=50.01;
   v.exp_risk_money=10002.0;
   v.exp_verdict=PL_CONFIRM;
   v.exp_reason=PL_R_SPLIT_ORDERS;
   v.exp_split_n=2;
   v.exp_split_need=2;
   v.exp_split[0]=25.01;
   v.exp_split[1]=25.0;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 92 split_two_and_a_half_max
//| Split on, lot 125.00 = 2.5 times max: three orders 41.67, 41.67, 41.66
//|   EURUSD (vol_min 0.01, step 0.01, vol_max 50), Ask 1.12024, SL 1.11824, 20 pips, 200 USD per lot.
//|   Risk in money = lot * 200, so the lot comes out exactly (loss 200 per lot, no commission), balance 100 000 000 so no cap, confirmation or margin check can interfere.
//|   Split: n = ceil(lot / vol_max), floor(lot / n) steps each, the remainder one step to the first parts.
//|   Steps: 12500; n = ceil(12500 / 5000) = ceil(2.5) = 3; floor(12500 / 3) = 4166 steps, remainder 12500 - 3 * 4166 = 2.
//|   First two orders 4167 steps = 41.67, third 4166 steps = 41.66; sum 125.00. Risk 125 * 200 = 25000.
//+------------------------------------------------------------------+
void PlVec92(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="split_two_and_a_half_max";
   v.what="Split on, lot 125.00 = 2.5 times max: three orders 41.67, 41.67, 41.66";
   PlVecSymEURUSD(v.s);
   PlVecAccount(v.a,"USD",2,100000000.0,100000000.0,0.0,100000000.0);
   PlVecInputs(v.in);
   v.in.sl=1.11824;
   v.in.calcprofit_ok=true;
   v.in.calcprofit_loss_1lot=200.0;
   v.in.risk_mode=PL_RISK_MONEY;
   v.in.risk_money=25000.0;   // lot 125.00 at 200 per lot
   v.in.over_max=PL_OVER_SPLIT;
   v.in.comm.kind=PL_COMM_LOT_SIDE; v.in.comm.rate=0.0; v.in.comm.source=PL_COMMSRC_USER;
   //--- expected
   v.chk_prepare_ok=true; v.exp_prepare_ok=true;
   v.exp_side=PL_SIDE_BUY;
   v.exp_lot=125.00;
   v.exp_risk_money=25000.0;
   v.exp_verdict=PL_CONFIRM;
   v.exp_reason=PL_R_SPLIT_ORDERS;
   v.exp_split_n=3;
   v.exp_split_need=3;
   v.exp_split[0]=41.67;
   v.exp_split[1]=41.67;
   v.exp_split[2]=41.66;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 93 split_ten_orders_allowed
//| Split on, lot 500.00 = ten times max: ten orders of 50.00, the limit allows it
//|   EURUSD (vol_min 0.01, step 0.01, vol_max 50), Ask 1.12024, SL 1.11824, 20 pips, 200 USD per lot.
//|   Risk in money = lot * 200, so the lot comes out exactly (loss 200 per lot, no commission), balance 100 000 000 so no cap, confirmation or margin check can interfere.
//|   Split: n = ceil(lot / vol_max), floor(lot / n) steps each, the remainder one step to the first parts.
//|   Steps: 50000; n = ceil(50000 / 5000) = 10 = PL_MAX_PARTS: allowed; each order 5000 steps = 50.00. CONFIRM.
//+------------------------------------------------------------------+
void PlVec93(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="split_ten_orders_allowed";
   v.what="Split on, lot 500.00 = ten times max: ten orders of 50.00, the limit allows it";
   PlVecSymEURUSD(v.s);
   PlVecAccount(v.a,"USD",2,100000000.0,100000000.0,0.0,100000000.0);
   PlVecInputs(v.in);
   v.in.sl=1.11824;
   v.in.calcprofit_ok=true;
   v.in.calcprofit_loss_1lot=200.0;
   v.in.risk_mode=PL_RISK_MONEY;
   v.in.risk_money=100000.0;   // lot 500.00 at 200 per lot
   v.in.over_max=PL_OVER_SPLIT;
   v.in.comm.kind=PL_COMM_LOT_SIDE; v.in.comm.rate=0.0; v.in.comm.source=PL_COMMSRC_USER;
   //--- expected
   v.chk_prepare_ok=true; v.exp_prepare_ok=true;
   v.exp_side=PL_SIDE_BUY;
   v.exp_lot=500.00;
   v.exp_verdict=PL_CONFIRM;
   v.exp_reason=PL_R_SPLIT_ORDERS;
   v.exp_split_n=10;
   v.exp_split_need=10;
   v.exp_split[0]=50.0;
   v.exp_split[1]=50.0;
   v.exp_split[2]=50.0;
   v.exp_split[3]=50.0;
   v.exp_split[4]=50.0;
   v.exp_split[5]=50.0;
   v.exp_split[6]=50.0;
   v.exp_split[7]=50.0;
   v.exp_split[8]=50.0;
   v.exp_split[9]=50.0;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 94 split_eleven_orders_block
//| Split on, lot 501.00: would need 11 orders, BLOCK
//|   EURUSD (vol_min 0.01, step 0.01, vol_max 50), Ask 1.12024, SL 1.11824, 20 pips, 200 USD per lot.
//|   Risk in money = lot * 200, so the lot comes out exactly (loss 200 per lot, no commission), balance 100 000 000 so no cap, confirmation or margin check can interfere.
//|   Split: n = ceil(lot / vol_max), floor(lot / n) steps each, the remainder one step to the first parts.
//|   Steps: 50100; n = ceil(50100 / 5000) = ceil(10.02) = 11 > 10: BLOCK, reason PL_R_SPLIT_TOO_MANY, split_need 11, no lots.
//|   Lot stays 501.00.
//+------------------------------------------------------------------+
void PlVec94(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="split_eleven_orders_block";
   v.what="Split on, lot 501.00: would need 11 orders, BLOCK";
   PlVecSymEURUSD(v.s);
   PlVecAccount(v.a,"USD",2,100000000.0,100000000.0,0.0,100000000.0);
   PlVecInputs(v.in);
   v.in.sl=1.11824;
   v.in.calcprofit_ok=true;
   v.in.calcprofit_loss_1lot=200.0;
   v.in.risk_mode=PL_RISK_MONEY;
   v.in.risk_money=100200.0;   // lot 501.00 at 200 per lot
   v.in.over_max=PL_OVER_SPLIT;
   v.in.comm.kind=PL_COMM_LOT_SIDE; v.in.comm.rate=0.0; v.in.comm.source=PL_COMMSRC_USER;
   //--- expected
   v.chk_prepare_ok=true; v.exp_prepare_ok=true;
   v.exp_side=PL_SIDE_BUY;
   v.exp_lot=501.00;
   v.exp_verdict=PL_BLOCK;
   v.exp_reason=PL_R_SPLIT_TOO_MANY;
   v.exp_split_n=0;
   v.exp_split_need=11;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 95 split_min_lot_last_order
//| Split on, vol_max 0.02, lot 0.05: 0.02, 0.02 and 0.01 (the minimum lot) last
//|   EURUSD with vol_min 0.01, step 0.01, vol_max 0.02. Risk in money = 0.05 * 200 = 10, so the lot comes out 0.05, balance 100 000 000.
//|   Steps: 5; vol_max = 2 steps; n = ceil(5 / 2) = 3; floor(5 / 3) = 1 step, remainder 5 - 3 = 2.
//|   First two orders 2 steps = 0.02, third 1 step = 0.01 = vol_min; sum 0.05. Risk 0.05 * 200 = 10.
//+------------------------------------------------------------------+
void PlVec95(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="split_min_lot_last_order";
   v.what="Split on, vol_max 0.02, lot 0.05: 0.02, 0.02 and 0.01 (the minimum lot) last";
   PlVecSymEURUSD(v.s);
   v.s.vol_max=0.02;
   PlVecAccount(v.a,"USD",2,100000000.0,100000000.0,0.0,100000000.0);
   PlVecInputs(v.in);
   v.in.sl=1.11824;
   v.in.calcprofit_ok=true;
   v.in.calcprofit_loss_1lot=200.0;
   v.in.risk_mode=PL_RISK_MONEY;
   v.in.risk_money=10.0;   // lot 0.05 at 200 per lot
   v.in.over_max=PL_OVER_SPLIT;
   v.in.comm.kind=PL_COMM_LOT_SIDE; v.in.comm.rate=0.0; v.in.comm.source=PL_COMMSRC_USER;
   //--- expected
   v.chk_prepare_ok=true; v.exp_prepare_ok=true;
   v.exp_side=PL_SIDE_BUY;
   v.exp_lot=0.05;
   v.exp_risk_money=10.0;
   v.exp_verdict=PL_CONFIRM;
   v.exp_reason=PL_R_SPLIT_ORDERS;
   v.exp_split_n=3;
   v.exp_split_need=3;
   v.exp_split[0]=0.02;
   v.exp_split[1]=0.02;
   v.exp_split[2]=0.01;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 96 split_refused_on_netting
//| Split on, lot 125.00 on a netting account: BLOCK
//|   EURUSD (vol_min 0.01, step 0.01, vol_max 50), Ask 1.12024, SL 1.11824, 20 pips, 200 USD per lot.
//|   Risk in money = lot * 200, so the lot comes out exactly (loss 200 per lot, no commission), balance 100 000 000 so no cap, confirmation or margin check can interfere.
//|   Split: n = ceil(lot / vol_max), floor(lot / n) steps each, the remainder one step to the first parts.
//|   Netting account: one position per symbol, the broker would net the orders: BLOCK, reason PL_R_SPLIT_NETTING, lot stays 125.00, no lots.
//+------------------------------------------------------------------+
void PlVec96(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="split_refused_on_netting";
   v.what="Split on, lot 125.00 on a netting account: BLOCK";
   PlVecSymEURUSD(v.s);
   PlVecAccount(v.a,"USD",2,100000000.0,100000000.0,0.0,100000000.0);
   v.a.margin_mode=ACCOUNT_MARGIN_MODE_RETAIL_NETTING;
   PlVecInputs(v.in);
   v.in.sl=1.11824;
   v.in.calcprofit_ok=true;
   v.in.calcprofit_loss_1lot=200.0;
   v.in.risk_mode=PL_RISK_MONEY;
   v.in.risk_money=25000.0;   // lot 125.00 at 200 per lot
   v.in.over_max=PL_OVER_SPLIT;
   v.in.comm.kind=PL_COMM_LOT_SIDE; v.in.comm.rate=0.0; v.in.comm.source=PL_COMMSRC_USER;
   //--- expected
   v.chk_prepare_ok=true; v.exp_prepare_ok=true;
   v.exp_side=PL_SIDE_BUY;
   v.exp_lot=125.00;
   v.exp_verdict=PL_BLOCK;
   v.exp_reason=PL_R_SPLIT_NETTING;
   v.exp_split_n=0;
   v.exp_split_need=0;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 97 block_above_max_default
//| Block (default), lot 125.00: BLOCK with the stepped lot, no split
//|   EURUSD (vol_min 0.01, step 0.01, vol_max 50), Ask 1.12024, SL 1.11824, 20 pips, 200 USD per lot.
//|   Risk in money = lot * 200, so the lot comes out exactly (loss 200 per lot, no commission), balance 100 000 000 so no cap, confirmation or margin check can interfere.
//|   Split: n = ceil(lot / vol_max), floor(lot / n) steps each, the remainder one step to the first parts.
//|   Block: lot 125.00 > vol_max 50: BLOCK, reason PL_R_LOT_ABOVE_MAX, lot 125.00 as asked, split_n 0.
//+------------------------------------------------------------------+
void PlVec97(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="block_above_max_default";
   v.what="Block (default), lot 125.00: BLOCK with the stepped lot, no split";
   PlVecSymEURUSD(v.s);
   PlVecAccount(v.a,"USD",2,100000000.0,100000000.0,0.0,100000000.0);
   PlVecInputs(v.in);
   v.in.sl=1.11824;
   v.in.calcprofit_ok=true;
   v.in.calcprofit_loss_1lot=200.0;
   v.in.risk_mode=PL_RISK_MONEY;
   v.in.risk_money=25000.0;   // lot 125.00 at 200 per lot
   v.in.over_max=PL_OVER_BLOCK;
   v.in.comm.kind=PL_COMM_LOT_SIDE; v.in.comm.rate=0.0; v.in.comm.source=PL_COMMSRC_USER;
   //--- expected
   v.chk_prepare_ok=true; v.exp_prepare_ok=true;
   v.exp_side=PL_SIDE_BUY;
   v.exp_lot=125.00;
   v.exp_verdict=PL_BLOCK;
   v.exp_reason=PL_R_LOT_ABOVE_MAX;
   v.exp_split_n=0;
   v.exp_split_need=0;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 98 no_sl_lot_below_min_block
//| EURUSD with vol_min 1.0, no SL, fixed lot 0.1: nothing bounds the risk, the typed lot is never raised, PL_BLOCK PL_R_LOT_BELOW_MIN
//|   no_sl: side from TP 1.12524 above mid: BUY, exec 1.12024, grid vol_min 1.0 step 0.01 max 50 ok.
//|   lot_fixed 0.1 < vol_min 1.0: lot shown as vol_min 1.0, below_min without an SL: BLOCK.
//|   margin_needed = 1.0 * 1120.24 = 1120.24, free 10000.
//+------------------------------------------------------------------+
void PlVec98(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="no_sl_lot_below_min_block";
   v.what="EURUSD vol_min 1.0, no SL, fixed lot 0.1: BLOCK PL_R_LOT_BELOW_MIN";
   PlVecSymEURUSD(v.s);
   v.s.vol_min=1.0;
   PlVecAccount(v.a,"USD",2,10000.0,10000.0,0.0,10000.0);
   PlVecInputs(v.in);
   v.in.sl=0.0;
   v.in.no_sl=true;
   v.in.lot_fixed=0.1;
   v.in.no_tp=false;
   v.in.tp[0].on=true; v.in.tp[0].mode=PL_TP_PRICE; v.in.tp[0].r=0.0; v.in.tp[0].price=1.12524; v.in.tp[0].share=100.0;
   //--- expected
   v.chk_prepare_ok=true; v.exp_prepare_ok=true;
   v.exp_side=PL_SIDE_BUY;
   v.exp_lot=1.0;
   v.exp_margin_needed=1120.24;
   v.exp_verdict=PL_BLOCK;
   v.exp_reason=PL_R_LOT_BELOW_MIN;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 99 cfd_ust_profit_eq
//| XAUUSD fixture on an account named UST: the tick value says profit currency = account currency, so no correction and no note (the currency string is never compared)
//|   SL 4190.52, Buy, exec 4195.52, ticks 500. k = 1 / (0.01 * 100) = 1: relation PROFIT.
//|   (a) 500 * 1 = 500, (c) OrderCalcProfit = 500. lot_raw 100 / 500 = 0.2, lot 0.2, risk 100.
//|   Verdict PL_OK, reason PL_R_NONE, note PL_R_NONE.
//+------------------------------------------------------------------+
void PlVec99(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="cfd_ust_profit_eq";
   v.what="XAUUSD fixture on a UST account: profit currency equals the account currency by the tick value, no correction";
   PlVecSymXAUUSD(v.s);
   PlVecAccount(v.a,"UST",2,10000.0,10000.0,0.0,10000.0);
   PlVecInputs(v.in);
   v.in.sl=4190.52;
   v.in.comm.kind=PL_COMM_LOT_SIDE; v.in.comm.rate=0.0; v.in.comm.source=PL_COMMSRC_USER;
   v.in.calcprofit_ok=true; v.in.calcprofit_loss_1lot=500.0;
   //--- expected
   v.chk_prepare_ok=true; v.exp_prepare_ok=true;
   v.exp_side=PL_SIDE_BUY;
   v.exp_ticks=500;
   v.exp_lpl_a=500.0;
   v.exp_lpl_c=500.0;
   v.exp_lpl_price=500.0;
   v.exp_lot=0.2;
   v.exp_risk_money=100.0;
   v.exp_verdict=PL_OK;
   v.exp_reason=PL_R_NONE;
   v.exp_note=PL_R_NONE;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 100 usdjpy_ust_base_eq
//| USDJPY fixture on a UST account: the tick value says the base currency is the account currency, SL-rate corrected (a) agrees with a rounded (c)
//|   Buy, SL 157.988, exec 158.311, ticks 323. k = 0.63175983 / (0.001 * 100000), 1/k = 158.288 = Bid: relation BASE.
//|   (a) = 323 * 0.001 * 100000 / 157.988 = 204.44590728; (c) rounded to 2 digits = 204.45; |a - c| = 0.0041 inside the tolerance.
//|   lpl_price = 204.45; commission 2.5 per side; loss_per_lot = 209.45; lot_raw = 100.45 / 209.45 = 0.47959; lot 0.47; risk = 0.47 * 209.45 = 98.4415.
//|   Verdict PL_OK, note PL_R_NONE.
//+------------------------------------------------------------------+
void PlVec100(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="usdjpy_ust_base_eq";
   v.what="USDJPY fixture on a UST account: base currency equals the account currency by the tick value, (c) rounded";
   PlVecSymUSDJPY(v.s);
   PlVecAccount(v.a,"UST",2,10000.0,10000.0,0.0,10000.0);
   PlVecInputs(v.in);
   v.in.sl=157.988;
   v.in.risk_mode=PL_RISK_MONEY;
   v.in.risk_money=100.45;
   v.in.comm.kind=PL_COMM_LOT_SIDE; v.in.comm.rate=2.5; v.in.comm.source=PL_COMMSRC_USER;
   v.in.calcprofit_ok=true; v.in.calcprofit_loss_1lot=204.45;
   //--- expected
   v.chk_prepare_ok=true; v.exp_prepare_ok=true;
   v.exp_side=PL_SIDE_BUY;
   v.exp_ticks=323;
   v.exp_lpl_a=204.44590728;
   v.exp_lpl_c=204.45;
   v.exp_lpl_price=204.45;
   v.exp_loss_per_lot=209.45;
   v.exp_lot=0.47;
   v.exp_risk_money=98.4415;
   v.exp_verdict=PL_OK;
   v.exp_reason=PL_R_NONE;
   v.exp_note=PL_R_NONE;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 101 paths_disagree_beyond_tol
//| EURUSD, SL 230 ticks, (a) 230 and (c) 233: |a - c| = 3 > 0.01 * 233 + 0.005 = 2.335, BLOCK PL_R_PATHS_DISAGREE
//|   lpl_price = max(a, c) = 233.
//+------------------------------------------------------------------+
void PlVec101(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="paths_disagree_beyond_tol";
   v.what="EURUSD (a) 230, (c) 233: beyond the tolerance, BLOCK PL_R_PATHS_DISAGREE";
   PlVecSymEURUSD(v.s);
   PlVecAccount(v.a,"USD",2,10000.0,10000.0,0.0,10000.0);
   PlVecInputs(v.in);
   v.in.sl=1.11794;
   v.in.calcprofit_ok=true; v.in.calcprofit_loss_1lot=233.0;
   //--- expected
   v.chk_prepare_ok=true; v.exp_prepare_ok=true;
   v.exp_ticks=230;
   v.exp_lpl_a=230.0;
   v.exp_lpl_c=233.0;
   v.exp_lpl_price=233.0;
   v.exp_verdict=PL_BLOCK;
   v.exp_reason=PL_R_PATHS_DISAGREE;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 102 lot_grid_block
//| EURUSD with vol_min 0.015 and vol_step 0.01: the minimum is off the step grid, BLOCK PL_R_LOT_GRID (c given: NO_CALC sits before LOT_GRID in the enum)
//|   (a) = (c) = 230, so the grid is the only block.
//+------------------------------------------------------------------+
void PlVec102(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="lot_grid_block";
   v.what="EURUSD vol_min 0.015, step 0.01: BLOCK PL_R_LOT_GRID";
   PlVecSymEURUSD(v.s);
   v.s.vol_min=0.015;
   PlVecAccount(v.a,"USD",2,10000.0,10000.0,0.0,10000.0);
   PlVecInputs(v.in);
   v.in.sl=1.11794;
   v.in.calcprofit_ok=true; v.in.calcprofit_loss_1lot=230.0;
   //--- expected
   v.chk_prepare_ok=true; v.exp_prepare_ok=true;
   v.exp_verdict=PL_BLOCK;
   v.exp_reason=PL_R_LOT_GRID;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 103 calc_mode_bonds_block
//| EURUSD fixture with the calc mode EXCH_BONDS: the profit formula is not supported, BLOCK PL_R_CALC_MODE
//|   Relation NA (not a delta mode), (a) = ticks * tvl = 230, (c) = 230 given.
//+------------------------------------------------------------------+
void PlVec103(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="calc_mode_bonds_block";
   v.what="EURUSD fixture with calc mode EXCH_BONDS: BLOCK PL_R_CALC_MODE";
   PlVecSymEURUSD(v.s);
   v.s.calc_mode=SYMBOL_CALC_MODE_EXCH_BONDS;
   PlVecAccount(v.a,"USD",2,10000.0,10000.0,0.0,10000.0);
   PlVecInputs(v.in);
   v.in.sl=1.11794;
   v.in.calcprofit_ok=true; v.in.calcprofit_loss_1lot=230.0;
   //--- expected
   v.chk_prepare_ok=true; v.exp_prepare_ok=true;
   v.exp_lpl_a=230.0;
   v.exp_verdict=PL_BLOCK;
   v.exp_reason=PL_R_CALC_MODE;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 104 percent_comm_futures_block
//| GER40 fixture with the calc mode FUTURES, percent commission 0.01: no profit currency rate in that mode, BLOCK PL_R_NO_CONVERSION; the swap in the profit currency cannot be worked out either (swap_ok false)
//|   (a) = 100 * 0.55 = 55 (tick value is per tick in account money), (c) = 55 given.
//+------------------------------------------------------------------+
void PlVec104(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="percent_comm_futures_block";
   v.what="GER40 fixture with calc mode FUTURES, percent commission: BLOCK PL_R_NO_CONVERSION, swap n/a";
   PlVecSymGER40(v.s);
   v.s.calc_mode=SYMBOL_CALC_MODE_FUTURES;
   v.s.swap_mode=SYMBOL_SWAP_MODE_CURRENCY_PROFIT; v.s.swap_long=-1.0; v.s.swap_short=0.5;
   PlVecAccount(v.a,"USD",2,10000.0,10000.0,0.0,10000.0);
   PlVecInputs(v.in);
   v.in.sl=18951.0;
   v.in.comm.kind=PL_COMM_PERCENT_SIDE; v.in.comm.rate=0.01; v.in.comm.source=PL_COMMSRC_USER;
   v.in.calcprofit_ok=true; v.in.calcprofit_loss_1lot=55.0;
   //--- expected
   v.chk_prepare_ok=true; v.exp_prepare_ok=true;
   v.exp_lpl_a=55.0;
   v.exp_swap_ok=0;
   v.exp_verdict=PL_BLOCK;
   v.exp_reason=PL_R_NO_CONVERSION;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 105 fill_mask_ioc_only_market
//| Market order, fill mask 2 (IOC only, the Bybit mask): not blocked, same lot as with mask 3
//|   EURUSD Buy Market, SL 1.1198: dist 44 points, lot_raw 100 / 44 = 2.2727, lot 2.27, risk 99.88. The mask only decides the fill type at the send.
//+------------------------------------------------------------------+
void PlVec105(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="fill_mask_ioc_only_market";
   v.what="Market order, fill mask 2 (IOC only, the Bybit mask): not blocked, same lot as with mask 3";
   PlVecSymEURUSD(v.s);
   PlVecAccount(v.a,"USD",2,10000.0,10000.0,0.0,10000.0);
   PlVecInputs(v.in);
   v.s.filling_mode=2;
   v.in.sl=1.1198;
   v.in.calcprofit_ok=true; v.in.calcprofit_loss_1lot=44.0;
   //--- expected
   v.chk_prepare_ok=true; v.exp_prepare_ok=true;
   v.exp_plan_reason=PL_R_NONE;
   v.exp_side=PL_SIDE_BUY;
   v.exp_ticks=44;
   v.exp_lot=2.27000000;
   v.exp_risk_money=99.88000000;
   v.exp_verdict=PL_OK;
   v.exp_reason=PL_R_NONE;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 106 fill_mask_zero_market_block
//| Market order, fill mask 0: BLOCK PL_R_NO_FILL_MODE
//|   No FOK and no IOC in the mask: a market order has no fill type to use (Return is forbidden for market orders on Market execution).
//+------------------------------------------------------------------+
void PlVec106(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="fill_mask_zero_market_block";
   v.what="Market order, fill mask 0: BLOCK PL_R_NO_FILL_MODE";
   PlVecSymEURUSD(v.s);
   PlVecAccount(v.a,"USD",2,10000.0,10000.0,0.0,10000.0);
   PlVecInputs(v.in);
   v.s.filling_mode=0;
   v.in.sl=1.1198;
   v.in.calcprofit_ok=true; v.in.calcprofit_loss_1lot=44.0;
   //--- expected
   v.chk_prepare_ok=true; v.exp_prepare_ok=true;
   v.exp_plan_reason=PL_R_NONE;
   v.exp_side=PL_SIDE_BUY;
   v.exp_verdict=PL_BLOCK;
   v.exp_reason=PL_R_NO_FILL_MODE;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 107 stops_pending_sl_boundary_block
//| Buy Limit 1.11800, SL 1.1177: distance exactly 30 points with StopsLevel 30: SL_TOO_CLOSE
//|   The reference sample uses a strict ">", so a distance equal to the level is refused: the minimum is level plus one point (31).
//+------------------------------------------------------------------+
void PlVec107(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="stops_pending_sl_boundary_block";
   v.what="Buy Limit 1.11800, SL 1.1177: distance exactly 30 points with StopsLevel 30: SL_TOO_CLOSE";
   PlVecSymEURUSD(v.s);
   PlVecAccount(v.a,"USD",2,10000.0,10000.0,0.0,10000.0);
   PlVecInputs(v.in);
   v.s.stops_level=30;
   v.in.kind=PL_KIND_LIMIT; v.in.entry=1.118;
   v.in.sl=1.1177;
   v.in.calcprofit_ok=true; v.in.calcprofit_loss_1lot=30.0;
   //--- expected
   v.exp_plan_reason=PL_R_SL_TOO_CLOSE;
   v.exp_side=PL_SIDE_BUY;
   v.exp_ticks=30;
   v.exp_verdict=PL_BLOCK;
   v.exp_reason=PL_R_SL_TOO_CLOSE;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 108 fill_mask_zero_pending_ok
//| Buy Limit, fill mask 0: no NO_FILL_MODE block (a pending order uses Return)
//|   Buy Limit 1.118, SL 1.1177: dist 30, lot_raw 100 / 30 = 3.3333, lot 3.33, risk 99.9.
//+------------------------------------------------------------------+
void PlVec108(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="fill_mask_zero_pending_ok";
   v.what="Buy Limit, fill mask 0: no NO_FILL_MODE block (a pending order uses Return)";
   PlVecSymEURUSD(v.s);
   PlVecAccount(v.a,"USD",2,10000.0,10000.0,0.0,10000.0);
   PlVecInputs(v.in);
   v.s.filling_mode=0;
   v.in.kind=PL_KIND_LIMIT; v.in.entry=1.118;
   v.in.sl=1.1177;
   v.in.calcprofit_ok=true; v.in.calcprofit_loss_1lot=30.0;
   //--- expected
   v.chk_prepare_ok=true; v.exp_prepare_ok=true;
   v.exp_plan_reason=PL_R_NONE;
   v.exp_side=PL_SIDE_BUY;
   v.exp_ticks=30;
   v.exp_lot=3.33000000;
   v.exp_risk_money=99.90000000;
   v.exp_verdict=PL_OK;
   v.exp_reason=PL_R_NONE;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 109 gtc_daily_market_block
//| SYMBOL_ORDERS_DAILY, market order: BLOCK PL_R_ORDERS_DAILY
//|   The broker deletes SL and TP at the end of each day: a position would lose its broker SL overnight.
//+------------------------------------------------------------------+
void PlVec109(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="gtc_daily_market_block";
   v.what="SYMBOL_ORDERS_DAILY, market order: BLOCK PL_R_ORDERS_DAILY";
   PlVecSymEURUSD(v.s);
   PlVecAccount(v.a,"USD",2,10000.0,10000.0,0.0,10000.0);
   PlVecInputs(v.in);
   v.s.gtc_mode=SYMBOL_ORDERS_DAILY;
   v.in.sl=1.1198;
   v.in.calcprofit_ok=true; v.in.calcprofit_loss_1lot=44.0;
   //--- expected
   v.chk_prepare_ok=true; v.exp_prepare_ok=true;
   v.exp_plan_reason=PL_R_NONE;
   v.exp_side=PL_SIDE_BUY;
   v.exp_verdict=PL_BLOCK;
   v.exp_reason=PL_R_ORDERS_DAILY;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 110 gtc_daily_pending_block
//| SYMBOL_ORDERS_DAILY, pending order: BLOCK PL_R_ORDERS_DAILY
//|   The block applies to every order kind.
//+------------------------------------------------------------------+
void PlVec110(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="gtc_daily_pending_block";
   v.what="SYMBOL_ORDERS_DAILY, pending order: BLOCK PL_R_ORDERS_DAILY";
   PlVecSymEURUSD(v.s);
   PlVecAccount(v.a,"USD",2,10000.0,10000.0,0.0,10000.0);
   PlVecInputs(v.in);
   v.s.gtc_mode=SYMBOL_ORDERS_DAILY;
   v.in.kind=PL_KIND_LIMIT; v.in.entry=1.118;
   v.in.sl=1.1177;
   v.in.calcprofit_ok=true; v.in.calcprofit_loss_1lot=30.0;
   //--- expected
   v.chk_prepare_ok=true; v.exp_prepare_ok=true;
   v.exp_plan_reason=PL_R_NONE;
   v.exp_side=PL_SIDE_BUY;
   v.exp_verdict=PL_BLOCK;
   v.exp_reason=PL_R_ORDERS_DAILY;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 111 gtc_daily_excluding_stops_ok
//| SYMBOL_ORDERS_DAILY_EXCLUDING_STOPS, market order: no block
//|   Only pending orders are deleted at the end of the day under this mode; SL and TP stay. Same numbers as vector 105.
//+------------------------------------------------------------------+
void PlVec111(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="gtc_daily_excluding_stops_ok";
   v.what="SYMBOL_ORDERS_DAILY_EXCLUDING_STOPS, market order: no block";
   PlVecSymEURUSD(v.s);
   PlVecAccount(v.a,"USD",2,10000.0,10000.0,0.0,10000.0);
   PlVecInputs(v.in);
   v.s.gtc_mode=SYMBOL_ORDERS_DAILY_EXCLUDING_STOPS;
   v.in.sl=1.1198;
   v.in.calcprofit_ok=true; v.in.calcprofit_loss_1lot=44.0;
   //--- expected
   v.chk_prepare_ok=true; v.exp_prepare_ok=true;
   v.exp_plan_reason=PL_R_NONE;
   v.exp_side=PL_SIDE_BUY;
   v.exp_ticks=44;
   v.exp_lot=2.27000000;
   v.exp_risk_money=99.88000000;
   v.exp_verdict=PL_OK;
   v.exp_reason=PL_R_NONE;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 112 stops_market_closing_30_block
//| StopsLevel 30, Buy market, closing distance exactly 30 points: SL_TOO_CLOSE
//|   EURUSD Ask 1.12024, Bid 1.12018 (spread 6). SL 1.11988: dist = Ask - SL = 36 points, closing distance = 36 - 6 = 30 (Bid - SL) = the level: refused (needs 31).
//+------------------------------------------------------------------+
void PlVec112(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="stops_market_closing_30_block";
   v.what="StopsLevel 30, Buy market, closing distance exactly 30 points: SL_TOO_CLOSE";
   PlVecSymEURUSD(v.s);
   PlVecAccount(v.a,"USD",2,10000.0,10000.0,0.0,10000.0);
   PlVecInputs(v.in);
   v.s.stops_level=30;
   v.in.sl=1.11988;
   //--- expected
   v.exp_plan_reason=PL_R_SL_TOO_CLOSE;
   v.exp_side=PL_SIDE_BUY;
   v.exp_ticks=36;
   v.exp_verdict=PL_BLOCK;
   v.exp_reason=PL_R_SL_TOO_CLOSE;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 113 stops_market_closing_31_ok
//| StopsLevel 30, Buy market, closing distance 31 points: passes
//|   SL 1.11987: dist 37 points, closing 31 >= 31. lot_raw 100 / 37 = 2.7027, lot 2.70, risk 2.70 * 37 = 99.9.
//+------------------------------------------------------------------+
void PlVec113(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="stops_market_closing_31_ok";
   v.what="StopsLevel 30, Buy market, closing distance 31 points: passes";
   PlVecSymEURUSD(v.s);
   PlVecAccount(v.a,"USD",2,10000.0,10000.0,0.0,10000.0);
   PlVecInputs(v.in);
   v.s.stops_level=30;
   v.in.sl=1.11987;
   v.in.calcprofit_ok=true; v.in.calcprofit_loss_1lot=37.0;
   //--- expected
   v.chk_prepare_ok=true; v.exp_prepare_ok=true;
   v.exp_plan_reason=PL_R_NONE;
   v.exp_side=PL_SIDE_BUY;
   v.exp_ticks=37;
   v.exp_lot=2.70000000;
   v.exp_risk_money=99.90000000;
   v.exp_verdict=PL_OK;
   v.exp_reason=PL_R_NONE;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 114 stops_limit_entry_30_block
//| StopsLevel 30, Buy Limit at Ask minus 30 points: ENTRY_TOO_CLOSE
//|   Ask 1.12024, entry 1.11994 = 30 points under Ask (measured from Ask for buys): refused in the plan, before pressing. SL 100 points under the entry.
//+------------------------------------------------------------------+
void PlVec114(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="stops_limit_entry_30_block";
   v.what="StopsLevel 30, Buy Limit at Ask minus 30 points: ENTRY_TOO_CLOSE";
   PlVecSymEURUSD(v.s);
   PlVecAccount(v.a,"USD",2,10000.0,10000.0,0.0,10000.0);
   PlVecInputs(v.in);
   v.s.stops_level=30;
   v.in.kind=PL_KIND_LIMIT; v.in.entry=1.11994;
   v.in.sl=1.11894;
   //--- expected
   v.exp_plan_reason=PL_R_ENTRY_TOO_CLOSE;
   v.exp_side=PL_SIDE_BUY;
   v.exp_ticks=100;
   v.exp_verdict=PL_BLOCK;
   v.exp_reason=PL_R_ENTRY_TOO_CLOSE;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 115 stops_limit_entry_31_ok
//| StopsLevel 30, Buy Limit at Ask minus 31 points: passes
//|   Entry 1.11993 is 31 points under Ask. SL 1.11893: dist 100, lot_raw 100 / 100 = 1.0, risk 100.
//+------------------------------------------------------------------+
void PlVec115(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="stops_limit_entry_31_ok";
   v.what="StopsLevel 30, Buy Limit at Ask minus 31 points: passes";
   PlVecSymEURUSD(v.s);
   PlVecAccount(v.a,"USD",2,10000.0,10000.0,0.0,10000.0);
   PlVecInputs(v.in);
   v.s.stops_level=30;
   v.in.kind=PL_KIND_LIMIT; v.in.entry=1.11993;
   v.in.sl=1.11893;
   v.in.calcprofit_ok=true; v.in.calcprofit_loss_1lot=100.0;
   //--- expected
   v.chk_prepare_ok=true; v.exp_prepare_ok=true;
   v.exp_plan_reason=PL_R_NONE;
   v.exp_side=PL_SIDE_BUY;
   v.exp_ticks=100;
   v.exp_lot=1.00000000;
   v.exp_risk_money=100.00000000;
   v.exp_verdict=PL_OK;
   v.exp_reason=PL_R_NONE;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 116 stops_stoplimit_tp_from_trigger
//| StopsLevel 30, Buy Stop Limit: TP 20 points from the trigger but 120 from the limit: TP_TOO_CLOSE
//|   Trigger 1.1260, limit 1.1250 (100 apart), SL 1.1240, TP 1.1262. The distance from the limit alone would pass; the TP must keep the level from both prices.
//+------------------------------------------------------------------+
void PlVec116(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="stops_stoplimit_tp_from_trigger";
   v.what="StopsLevel 30, Buy Stop Limit: TP 20 points from the trigger but 120 from the limit: TP_TOO_CLOSE";
   PlVecSymEURUSD(v.s);
   PlVecAccount(v.a,"USD",2,10000.0,10000.0,0.0,10000.0);
   PlVecInputs(v.in);
   v.s.stops_level=30;
   v.in.kind=PL_KIND_STOP_LIMIT; v.in.entry=1.126; v.in.limit=1.125;
   v.in.sl=1.124;
   v.in.no_tp=false;
   v.in.tp[0].on=true; v.in.tp[0].mode=PL_TP_PRICE; v.in.tp[0].price=1.1262; v.in.tp[0].share=100.0;
   //--- expected
   v.exp_plan_reason=PL_R_TP_TOO_CLOSE;
   v.exp_side=PL_SIDE_BUY;
   v.exp_ticks=100;
   v.exp_verdict=PL_BLOCK;
   v.exp_reason=PL_R_TP_TOO_CLOSE;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 117 stops_stoplimit_gap_30_block
//| StopsLevel 30, Buy Stop Limit with the limit 30 points from the trigger: ENTRY_TOO_CLOSE
//|   Trigger 1.1260, limit 1.1257, SL 1.1247 (no source for this gap, kept conservative, unverified).
//+------------------------------------------------------------------+
void PlVec117(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="stops_stoplimit_gap_30_block";
   v.what="StopsLevel 30, Buy Stop Limit with the limit 30 points from the trigger: ENTRY_TOO_CLOSE";
   PlVecSymEURUSD(v.s);
   PlVecAccount(v.a,"USD",2,10000.0,10000.0,0.0,10000.0);
   PlVecInputs(v.in);
   v.s.stops_level=30;
   v.in.kind=PL_KIND_STOP_LIMIT; v.in.entry=1.126; v.in.limit=1.1257;
   v.in.sl=1.1247;
   //--- expected
   v.exp_plan_reason=PL_R_ENTRY_TOO_CLOSE;
   v.exp_side=PL_SIDE_BUY;
   v.exp_ticks=100;
   v.exp_verdict=PL_BLOCK;
   v.exp_reason=PL_R_ENTRY_TOO_CLOSE;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 118 stops_market_tp_30_block
//| StopsLevel 30, Buy market, TP exactly 30 points over Bid: TP_TOO_CLOSE
//|   TP 1.12048 - Bid 1.12018 = 30 points = the level: refused (needs 31). SL 1.117 as in vector 80.
//+------------------------------------------------------------------+
void PlVec118(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="stops_market_tp_30_block";
   v.what="StopsLevel 30, Buy market, TP exactly 30 points over Bid: TP_TOO_CLOSE";
   PlVecSymEURUSD(v.s);
   PlVecAccount(v.a,"USD",2,10000.0,10000.0,0.0,10000.0);
   PlVecInputs(v.in);
   v.s.stops_level=30;
   v.in.sl=1.117;
   v.in.no_tp=false;
   v.in.tp[0].on=true; v.in.tp[0].mode=PL_TP_PRICE; v.in.tp[0].price=1.12048; v.in.tp[0].share=100.0;
   //--- expected
   v.exp_plan_reason=PL_R_TP_TOO_CLOSE;
   v.exp_side=PL_SIDE_BUY;
   v.exp_ticks=324;
   v.exp_verdict=PL_BLOCK;
   v.exp_reason=PL_R_TP_TOO_CLOSE;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 119 stops_market_tp_31_ok
//| StopsLevel 30, Buy market, TP 31 points over Bid: passes
//|   TP 1.12049 - Bid 1.12018 = 31 points. SL 1.117: dist 324, lot_raw 100 / 324 = 0.3086, lot 0.30, risk 97.2.
//+------------------------------------------------------------------+
void PlVec119(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="stops_market_tp_31_ok";
   v.what="StopsLevel 30, Buy market, TP 31 points over Bid: passes";
   PlVecSymEURUSD(v.s);
   PlVecAccount(v.a,"USD",2,10000.0,10000.0,0.0,10000.0);
   PlVecInputs(v.in);
   v.s.stops_level=30;
   v.in.sl=1.117;
   v.in.no_tp=false;
   v.in.tp[0].on=true; v.in.tp[0].mode=PL_TP_PRICE; v.in.tp[0].price=1.12049; v.in.tp[0].share=100.0;
   v.in.calcprofit_ok=true; v.in.calcprofit_loss_1lot=324.0;
   //--- expected
   v.chk_prepare_ok=true; v.exp_prepare_ok=true;
   v.exp_plan_reason=PL_R_NONE;
   v.exp_side=PL_SIDE_BUY;
   v.exp_tp=1.12049000;
   v.exp_ticks=324;
   v.exp_lot=0.30000000;
   v.exp_risk_money=97.20000000;
   v.exp_verdict=PL_OK;
   v.exp_reason=PL_R_NONE;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 120 netting_add_old_sl_inside
//| Netting add, old SL 1.11900 (loss 100): lot from the room left, risk of the whole position
//|   Base: EURUSD (vol_min 0.01, step 0.01, vol_max 50), Ask 1.12024, SL 1.11824 = 20 pips = 200 USD per lot.
//|   USD account, balance = equity = free margin 100 000, risk 1% so target 1000, commission 0, one TP none, RETAIL_NETTING.
//|   Open position 1.00 lot buy at 1.12000: loss at the new SL 1.11824 is 0.00176 * 100000 = 176.
//|   Old SL 1.11900: loss_old 0.00100 * 100000 = 100. net_risk = 176 (commission 0).
//|   avail = 1000 - 176 = 824, lot = 824 / 200 = 4.12. risk_money = 4.12 * 200 + 176 = 1000.
//|   risk_add = 824 + (176 - 100) = 900: the worst case of the account grows by the new lot and by the SL moved from 100 to 176.
//+------------------------------------------------------------------+
void PlVec120(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="netting_add_old_sl_inside";
   v.what="Netting add, old SL 1.11900 (loss 100): lot from the room left, risk of the whole position";
   PlVecSymEURUSD(v.s);
   PlVecAccount(v.a,"USD",2,100000.0,100000.0,0.0,100000.0);
   v.a.margin_mode=ACCOUNT_MARGIN_MODE_RETAIL_NETTING;
   PlVecInputs(v.in);
   v.in.sl=1.11824;
   v.in.calcprofit_ok=true;
   v.in.calcprofit_loss_1lot=200.0;
   v.in.comm.kind=PL_COMM_LOT_SIDE; v.in.comm.rate=0.0; v.in.comm.source=PL_COMMSRC_USER;
   v.chk_prepare_ok=true; v.exp_prepare_ok=true;
   v.s.net_vol=1.0; v.s.net_buy=true; v.s.net_open=1.12000; v.s.net_sl=1.11900;
   v.in.net_calc_ok=true; v.in.net_loss_new=176.0; v.in.net_loss_old=100.0;
   v.exp_side=PL_SIDE_BUY;
   v.exp_lot=4.12;
   v.exp_risk_money=1000.0;
   v.exp_risk_add=900.0;
   v.exp_net_risk=176.0;
   v.exp_verdict=PL_OK;
   v.exp_reason=PL_R_NONE;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 121 netting_add_old_sl_in_profit
//| Netting add, old SL 1.12100 in profit: the given-up profit is added to risk_add
//|   Base: EURUSD (vol_min 0.01, step 0.01, vol_max 50), Ask 1.12024, SL 1.11824 = 20 pips = 200 USD per lot.
//|   USD account, balance = equity = free margin 100 000, risk 1% so target 1000, commission 0, one TP none, RETAIL_NETTING.
//|   Open position 1.00 lot buy at 1.12000: loss at the new SL 1.11824 is 0.00176 * 100000 = 176.
//|   Old SL 1.12100 above the open: profit 100, loss_old = -100. net_risk = 176, lot 4.12, risk_money 1000.
//|   risk_add = 824 + (176 - (-100)) = 824 + 276 = 1100: moving the SL from +100 to -176 costs 276 of the worst case of the account.
//+------------------------------------------------------------------+
void PlVec121(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="netting_add_old_sl_in_profit";
   v.what="Netting add, old SL 1.12100 in profit: the given-up profit is added to risk_add";
   PlVecSymEURUSD(v.s);
   PlVecAccount(v.a,"USD",2,100000.0,100000.0,0.0,100000.0);
   v.a.margin_mode=ACCOUNT_MARGIN_MODE_RETAIL_NETTING;
   PlVecInputs(v.in);
   v.in.sl=1.11824;
   v.in.calcprofit_ok=true;
   v.in.calcprofit_loss_1lot=200.0;
   v.in.comm.kind=PL_COMM_LOT_SIDE; v.in.comm.rate=0.0; v.in.comm.source=PL_COMMSRC_USER;
   v.chk_prepare_ok=true; v.exp_prepare_ok=true;
   v.s.net_vol=1.0; v.s.net_buy=true; v.s.net_open=1.12000; v.s.net_sl=1.12100;
   v.in.net_calc_ok=true; v.in.net_loss_new=176.0; v.in.net_loss_old=-100.0;
   v.exp_side=PL_SIDE_BUY;
   v.exp_lot=4.12;
   v.exp_risk_money=1000.0;
   v.exp_risk_add=1100.0;
   v.exp_net_risk=176.0;
   v.exp_verdict=PL_OK;
   v.exp_reason=PL_R_NONE;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 122 netting_add_no_old_sl
//| Netting add, the open position has no SL: risk_add equals risk_money
//|   Base: EURUSD (vol_min 0.01, step 0.01, vol_max 50), Ask 1.12024, SL 1.11824 = 20 pips = 200 USD per lot.
//|   USD account, balance = equity = free margin 100 000, risk 1% so target 1000, commission 0, one TP none, RETAIL_NETTING.
//|   Open position 1.00 lot buy at 1.12000: loss at the new SL 1.11824 is 0.00176 * 100000 = 176.
//|   No old SL (net_sl 0, loss_old 0): the volume was in no_sl and enters the sum of the risk only now, with its whole loss 176.
//|   lot 4.12, risk_money = 824 + 176 = 1000, risk_add = 824 + 176 = 1000.
//+------------------------------------------------------------------+
void PlVec122(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="netting_add_no_old_sl";
   v.what="Netting add, the open position has no SL: risk_add equals risk_money";
   PlVecSymEURUSD(v.s);
   PlVecAccount(v.a,"USD",2,100000.0,100000.0,0.0,100000.0);
   v.a.margin_mode=ACCOUNT_MARGIN_MODE_RETAIL_NETTING;
   PlVecInputs(v.in);
   v.in.sl=1.11824;
   v.in.calcprofit_ok=true;
   v.in.calcprofit_loss_1lot=200.0;
   v.in.comm.kind=PL_COMM_LOT_SIDE; v.in.comm.rate=0.0; v.in.comm.source=PL_COMMSRC_USER;
   v.chk_prepare_ok=true; v.exp_prepare_ok=true;
   v.s.net_vol=1.0; v.s.net_buy=true; v.s.net_open=1.12000; v.s.net_sl=0.0;
   v.in.net_calc_ok=true; v.in.net_loss_new=176.0; v.in.net_loss_old=0.0;
   v.exp_side=PL_SIDE_BUY;
   v.exp_lot=4.12;
   v.exp_risk_money=1000.0;
   v.exp_risk_add=1000.0;
   v.exp_net_risk=176.0;
   v.exp_verdict=PL_OK;
   v.exp_reason=PL_R_NONE;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 123 netting_add_old_sl_farther
//| Netting add, old SL farther than the new one: the tighter SL is not credited
//|   Base: EURUSD (vol_min 0.01, step 0.01, vol_max 50), Ask 1.12024, SL 1.11824 = 20 pips = 200 USD per lot.
//|   USD account, balance = equity = free margin 100 000, risk 1% so target 1000, commission 0, one TP none, RETAIL_NETTING.
//|   Open position 1.00 lot buy at 1.12000: loss at the new SL 1.11824 is 0.00176 * 100000 = 176.
//|   Old SL 1.11700: loss_old 0.00300 * 100000 = 300 > 176. net_risk 176, lot 4.12, risk_money 1000.
//|   risk_add = 824 + max(0, 176 - 300) = 824: no credit for a tighter SL.
//+------------------------------------------------------------------+
void PlVec123(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="netting_add_old_sl_farther";
   v.what="Netting add, old SL farther than the new one: the tighter SL is not credited";
   PlVecSymEURUSD(v.s);
   PlVecAccount(v.a,"USD",2,100000.0,100000.0,0.0,100000.0);
   v.a.margin_mode=ACCOUNT_MARGIN_MODE_RETAIL_NETTING;
   PlVecInputs(v.in);
   v.in.sl=1.11824;
   v.in.calcprofit_ok=true;
   v.in.calcprofit_loss_1lot=200.0;
   v.in.comm.kind=PL_COMM_LOT_SIDE; v.in.comm.rate=0.0; v.in.comm.source=PL_COMMSRC_USER;
   v.chk_prepare_ok=true; v.exp_prepare_ok=true;
   v.s.net_vol=1.0; v.s.net_buy=true; v.s.net_open=1.12000; v.s.net_sl=1.11700;
   v.in.net_calc_ok=true; v.in.net_loss_new=176.0; v.in.net_loss_old=300.0;
   v.exp_side=PL_SIDE_BUY;
   v.exp_lot=4.12;
   v.exp_risk_money=1000.0;
   v.exp_risk_add=824.0;
   v.exp_net_risk=176.0;
   v.exp_verdict=PL_OK;
   v.exp_reason=PL_R_NONE;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 124 netting_add_no_room
//| Netting add, the open position already uses the whole target: BLOCK NO_ROOM
//|   Base: EURUSD (vol_min 0.01, step 0.01, vol_max 50), Ask 1.12024, SL 1.11824 = 20 pips = 200 USD per lot.
//|   USD account, balance = equity = free margin 100 000, risk 1% so target 1000, commission 0, one TP none, RETAIL_NETTING.
//|   Open position 1.00 lot buy at 1.12000: loss at the new SL 1.11824 is 0.00176 * 100000 = 176.
//|   Open 10.00 lots: loss at the new SL 10 * 176 = 1760 >= target 1000, avail < 0: BLOCK PL_R_NETTING_NO_ROOM, lot 0.
//+------------------------------------------------------------------+
void PlVec124(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="netting_add_no_room";
   v.what="Netting add, the open position already uses the whole target: BLOCK NO_ROOM";
   PlVecSymEURUSD(v.s);
   PlVecAccount(v.a,"USD",2,100000.0,100000.0,0.0,100000.0);
   v.a.margin_mode=ACCOUNT_MARGIN_MODE_RETAIL_NETTING;
   PlVecInputs(v.in);
   v.in.sl=1.11824;
   v.in.calcprofit_ok=true;
   v.in.calcprofit_loss_1lot=200.0;
   v.in.comm.kind=PL_COMM_LOT_SIDE; v.in.comm.rate=0.0; v.in.comm.source=PL_COMMSRC_USER;
   v.chk_prepare_ok=true; v.exp_prepare_ok=true;
   v.s.net_vol=10.0; v.s.net_buy=true; v.s.net_open=1.12000; v.s.net_sl=1.11900;
   v.in.net_calc_ok=true; v.in.net_loss_new=1760.0; v.in.net_loss_old=1000.0;
   v.exp_side=PL_SIDE_BUY;
   v.exp_lot=0.0;
   v.exp_verdict=PL_BLOCK;
   v.exp_reason=PL_R_NETTING_NO_ROOM;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 125 netting_add_commission
//| Netting add with commission 5 per lot per side: exit commission of the open volume in net_risk
//|   Base: EURUSD (vol_min 0.01, step 0.01, vol_max 50), Ask 1.12024, SL 1.11824 = 20 pips = 200 USD per lot.
//|   USD account, balance = equity = free margin 100 000, risk 1% so target 1000, commission 0, one TP none, RETAIL_NETTING.
//|   Open position 1.00 lot buy at 1.12000: loss at the new SL 1.11824 is 0.00176 * 100000 = 176.
//|   Commission LOT_SIDE 5: comm_in = comm_out = 5, loss_per_lot = 210. net_risk = 176 + 1.00 * 5 = 181.
//|   avail = 1000 - 181 = 819, lot = 819 / 210 = 3.90. risk_money = 3.90 * 210 + 181 = 819 + 181 = 1000.
//|   risk_add = 819 + (176 - 100) = 895 (the exit commission is the same on both SLs and cancels).
//+------------------------------------------------------------------+
void PlVec125(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="netting_add_commission";
   v.what="Netting add with commission 5 per lot per side: exit commission of the open volume in net_risk";
   PlVecSymEURUSD(v.s);
   PlVecAccount(v.a,"USD",2,100000.0,100000.0,0.0,100000.0);
   v.a.margin_mode=ACCOUNT_MARGIN_MODE_RETAIL_NETTING;
   PlVecInputs(v.in);
   v.in.sl=1.11824;
   v.in.calcprofit_ok=true;
   v.in.calcprofit_loss_1lot=200.0;
   v.in.comm.kind=PL_COMM_LOT_SIDE; v.in.comm.rate=0.0; v.in.comm.source=PL_COMMSRC_USER;
   v.chk_prepare_ok=true; v.exp_prepare_ok=true;
   v.s.net_vol=1.0; v.s.net_buy=true; v.s.net_open=1.12000; v.s.net_sl=1.11900;
   v.in.net_calc_ok=true; v.in.net_loss_new=176.0; v.in.net_loss_old=100.0;
   v.in.comm.rate=5.0;
   v.exp_side=PL_SIDE_BUY;
   v.exp_lot=3.9;
   v.exp_risk_money=1000.0;
   v.exp_risk_add=895.0;
   v.exp_net_risk=181.0;
   v.exp_verdict=PL_OK;
   v.exp_reason=PL_R_NONE;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 127 netting_add_below_min
//| Netting add, room left below the minimum lot: CONFIRM LOT_BELOW_MIN at 0.01
//|   Base: EURUSD (vol_min 0.01, step 0.01, vol_max 50), Ask 1.12024, SL 1.11824 = 20 pips = 200 USD per lot.
//|   USD account, balance = equity = free margin 100 000, risk 1% so target 1000, commission 0, one TP none, RETAIL_NETTING.
//|   Open position 1.00 lot buy at 1.12000: loss at the new SL 1.11824 is 0.00176 * 100000 = 176.
//|   loss_new 999 (synthetic): net_risk 999, avail = 1, lot_raw = 1 / 200 = 0.005 < 0.01: lot 0.01, CONFIRM PL_R_LOT_BELOW_MIN.
//|   risk_money = 0.01 * 200 + 999 = 1001.
//+------------------------------------------------------------------+
void PlVec127(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="netting_add_below_min";
   v.what="Netting add, room left below the minimum lot: CONFIRM LOT_BELOW_MIN at 0.01";
   PlVecSymEURUSD(v.s);
   PlVecAccount(v.a,"USD",2,100000.0,100000.0,0.0,100000.0);
   v.a.margin_mode=ACCOUNT_MARGIN_MODE_RETAIL_NETTING;
   PlVecInputs(v.in);
   v.in.sl=1.11824;
   v.in.calcprofit_ok=true;
   v.in.calcprofit_loss_1lot=200.0;
   v.in.comm.kind=PL_COMM_LOT_SIDE; v.in.comm.rate=0.0; v.in.comm.source=PL_COMMSRC_USER;
   v.chk_prepare_ok=true; v.exp_prepare_ok=true;
   v.s.net_vol=1.0; v.s.net_buy=true; v.s.net_open=1.12000; v.s.net_sl=1.11900;
   v.in.net_calc_ok=true; v.in.net_loss_new=999.0; v.in.net_loss_old=100.0;
   v.exp_side=PL_SIDE_BUY;
   v.exp_lot=0.01;
   v.exp_risk_money=1001.0;
   v.exp_net_risk=999.0;
   v.exp_verdict=PL_CONFIRM;
   v.exp_reason=PL_R_LOT_BELOW_MIN;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 128 netting_add_two_tps
//| Netting add with two TPs: BLOCK NETTING_TPS
//|   Base: EURUSD (vol_min 0.01, step 0.01, vol_max 50), Ask 1.12024, SL 1.11824 = 20 pips = 200 USD per lot.
//|   USD account, balance = equity = free margin 100 000, risk 1% so target 1000, commission 0, one TP none, RETAIL_NETTING.
//|   Open position 1.00 lot buy at 1.12000: loss at the new SL 1.11824 is 0.00176 * 100000 = 176.
//|   Two TP levels (70/30) on an add: the panel cannot split a merged position by plan: BLOCK PL_R_NETTING_TPS.
//+------------------------------------------------------------------+
void PlVec128(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="netting_add_two_tps";
   v.what="Netting add with two TPs: BLOCK NETTING_TPS";
   PlVecSymEURUSD(v.s);
   PlVecAccount(v.a,"USD",2,100000.0,100000.0,0.0,100000.0);
   v.a.margin_mode=ACCOUNT_MARGIN_MODE_RETAIL_NETTING;
   PlVecInputs(v.in);
   v.in.sl=1.11824;
   v.in.calcprofit_ok=true;
   v.in.calcprofit_loss_1lot=200.0;
   v.in.comm.kind=PL_COMM_LOT_SIDE; v.in.comm.rate=0.0; v.in.comm.source=PL_COMMSRC_USER;
   v.chk_prepare_ok=true; v.exp_prepare_ok=true;
   v.s.net_vol=1.0; v.s.net_buy=true; v.s.net_open=1.12000; v.s.net_sl=1.11900;
   v.in.net_calc_ok=true; v.in.net_loss_new=176.0; v.in.net_loss_old=100.0;
   v.in.no_tp=false;
   v.in.tp[0].on=true; v.in.tp[0].mode=PL_TP_R; v.in.tp[0].r=1.0; v.in.tp[0].share=70.0;
   v.in.tp[1].on=true; v.in.tp[1].mode=PL_TP_R; v.in.tp[1].r=2.0; v.in.tp[1].share=30.0;
   v.exp_side=PL_SIDE_BUY;
   v.exp_verdict=PL_BLOCK;
   v.exp_reason=PL_R_NETTING_TPS;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 129 netting_add_no_sl
//| Netting add without SL: BLOCK NETTING_NO_SL
//|   Base: EURUSD (vol_min 0.01, step 0.01, vol_max 50), Ask 1.12024, SL 1.11824 = 20 pips = 200 USD per lot.
//|   USD account, balance = equity = free margin 100 000, risk 1% so target 1000, commission 0, one TP none, RETAIL_NETTING.
//|   Open position 1.00 lot buy at 1.12000: loss at the new SL 1.11824 is 0.00176 * 100000 = 176.
//|   no_sl with the side from a TP price 1.12524, lot 0.50 typed: the risk of the whole position is undefined: BLOCK PL_R_NETTING_NO_SL.
//+------------------------------------------------------------------+
void PlVec129(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="netting_add_no_sl";
   v.what="Netting add without SL: BLOCK NETTING_NO_SL";
   PlVecSymEURUSD(v.s);
   PlVecAccount(v.a,"USD",2,100000.0,100000.0,0.0,100000.0);
   v.a.margin_mode=ACCOUNT_MARGIN_MODE_RETAIL_NETTING;
   PlVecInputs(v.in);
   v.in.sl=1.11824;
   v.in.calcprofit_ok=true;
   v.in.calcprofit_loss_1lot=200.0;
   v.in.comm.kind=PL_COMM_LOT_SIDE; v.in.comm.rate=0.0; v.in.comm.source=PL_COMMSRC_USER;
   v.chk_prepare_ok=true; v.exp_prepare_ok=true;
   v.s.net_vol=1.0; v.s.net_buy=true; v.s.net_open=1.12000; v.s.net_sl=1.11900;
   v.in.net_calc_ok=true; v.in.net_loss_new=176.0; v.in.net_loss_old=100.0;
   v.in.no_sl=true; v.in.sl=0.0; v.in.lot_fixed=0.50;
   v.in.no_tp=false;
   v.in.tp[0].on=true; v.in.tp[0].mode=PL_TP_PRICE; v.in.tp[0].price=1.12524; v.in.tp[0].share=100.0;
   v.exp_side=PL_SIDE_BUY;
   v.exp_verdict=PL_BLOCK;
   v.exp_reason=PL_R_NETTING_NO_SL;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 130 netting_reverse_at_press
//| Sell plan against the open buy position: BLOCK NETTING_REVERSE
//|   Base: EURUSD (vol_min 0.01, step 0.01, vol_max 50), Ask 1.12024, SL 1.11824 = 20 pips = 200 USD per lot.
//|   USD account, balance = equity = free margin 100 000, risk 1% so target 1000, commission 0, one TP none, RETAIL_NETTING.
//|   Open position 1.00 lot buy at 1.12000: loss at the new SL 1.11824 is 0.00176 * 100000 = 176.
//|   SL 1.12218 above Bid: a sell. The open position is a buy: it would close or reverse it: BLOCK PL_R_NETTING_REVERSE.
//+------------------------------------------------------------------+
void PlVec130(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="netting_reverse_at_press";
   v.what="Sell plan against the open buy position: BLOCK NETTING_REVERSE";
   PlVecSymEURUSD(v.s);
   PlVecAccount(v.a,"USD",2,100000.0,100000.0,0.0,100000.0);
   v.a.margin_mode=ACCOUNT_MARGIN_MODE_RETAIL_NETTING;
   PlVecInputs(v.in);
   v.in.sl=1.11824;
   v.in.calcprofit_ok=true;
   v.in.calcprofit_loss_1lot=200.0;
   v.in.comm.kind=PL_COMM_LOT_SIDE; v.in.comm.rate=0.0; v.in.comm.source=PL_COMMSRC_USER;
   v.chk_prepare_ok=true; v.exp_prepare_ok=true;
   v.s.net_vol=1.0; v.s.net_buy=true; v.s.net_open=1.12000; v.s.net_sl=1.11900;
   v.in.net_calc_ok=true; v.in.net_loss_new=176.0; v.in.net_loss_old=100.0;
   v.in.sl=1.12218;
   v.exp_side=PL_SIDE_SELL;
   v.exp_verdict=PL_BLOCK;
   v.exp_reason=PL_R_NETTING_REVERSE;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 131 netting_add_pending
//| Buy Limit while a buy position is open: BLOCK NETTING_PENDING
//|   Base: EURUSD (vol_min 0.01, step 0.01, vol_max 50), Ask 1.12024, SL 1.11824 = 20 pips = 200 USD per lot.
//|   USD account, balance = equity = free margin 100 000, risk 1% so target 1000, commission 0, one TP none, RETAIL_NETTING.
//|   Open position 1.00 lot buy at 1.12000: loss at the new SL 1.11824 is 0.00176 * 100000 = 176.
//|   Buy Limit at 1.11900 with SL 1.11700 (200 ticks wide, 200 USD per lot): the SL at the fill is unknown: BLOCK PL_R_NETTING_PENDING.
//+------------------------------------------------------------------+
void PlVec131(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="netting_add_pending";
   v.what="Buy Limit while a buy position is open: BLOCK NETTING_PENDING";
   PlVecSymEURUSD(v.s);
   PlVecAccount(v.a,"USD",2,100000.0,100000.0,0.0,100000.0);
   v.a.margin_mode=ACCOUNT_MARGIN_MODE_RETAIL_NETTING;
   PlVecInputs(v.in);
   v.in.sl=1.11824;
   v.in.calcprofit_ok=true;
   v.in.calcprofit_loss_1lot=200.0;
   v.in.comm.kind=PL_COMM_LOT_SIDE; v.in.comm.rate=0.0; v.in.comm.source=PL_COMMSRC_USER;
   v.chk_prepare_ok=true; v.exp_prepare_ok=true;
   v.s.net_vol=1.0; v.s.net_buy=true; v.s.net_open=1.12000; v.s.net_sl=1.11900;
   v.in.net_calc_ok=true; v.in.net_loss_new=176.0; v.in.net_loss_old=100.0;
   v.in.kind=PL_KIND_LIMIT; v.in.entry=1.11900; v.in.sl=1.11700;
   v.exp_side=PL_SIDE_BUY;
   v.exp_verdict=PL_BLOCK;
   v.exp_reason=PL_R_NETTING_PENDING;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 132 netting_order_open
//| No position, a pending order already open on the symbol: BLOCK NETTING_ORDER_OPEN
//|   Base: EURUSD (vol_min 0.01, step 0.01, vol_max 50), Ask 1.12024, SL 1.11824 = 20 pips = 200 USD per lot.
//|   USD account, balance = equity = free margin 100 000, risk 1% so target 1000, commission 0, one TP none, RETAIL_NETTING.
//|   Open position 1.00 lot buy at 1.12000: loss at the new SL 1.11824 is 0.00176 * 100000 = 176.
//|   net_vol 0, net_orders 1: the order would merge into what this trade opens: BLOCK PL_R_NETTING_ORDER_OPEN.
//+------------------------------------------------------------------+
void PlVec132(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="netting_order_open";
   v.what="No position, a pending order already open on the symbol: BLOCK NETTING_ORDER_OPEN";
   PlVecSymEURUSD(v.s);
   PlVecAccount(v.a,"USD",2,100000.0,100000.0,0.0,100000.0);
   v.a.margin_mode=ACCOUNT_MARGIN_MODE_RETAIL_NETTING;
   PlVecInputs(v.in);
   v.in.sl=1.11824;
   v.in.calcprofit_ok=true;
   v.in.calcprofit_loss_1lot=200.0;
   v.in.comm.kind=PL_COMM_LOT_SIDE; v.in.comm.rate=0.0; v.in.comm.source=PL_COMMSRC_USER;
   v.chk_prepare_ok=true; v.exp_prepare_ok=true;
   v.s.net_orders=1;
   v.exp_side=PL_SIDE_BUY;
   v.exp_verdict=PL_BLOCK;
   v.exp_reason=PL_R_NETTING_ORDER_OPEN;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 133 netting_add_no_value
//| Netting add, the terminal gave no value of the open position: BLOCK NETTING_NO_VALUE
//|   Base: EURUSD (vol_min 0.01, step 0.01, vol_max 50), Ask 1.12024, SL 1.11824 = 20 pips = 200 USD per lot.
//|   USD account, balance = equity = free margin 100 000, risk 1% so target 1000, commission 0, one TP none, RETAIL_NETTING.
//|   Open position 1.00 lot buy at 1.12000: loss at the new SL 1.11824 is 0.00176 * 100000 = 176.
//|   net_calc_ok false: no OrderCalcProfit for the open volume at the new SL: refuse, never guess: BLOCK PL_R_NETTING_NO_VALUE.
//+------------------------------------------------------------------+
void PlVec133(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="netting_add_no_value";
   v.what="Netting add, the terminal gave no value of the open position: BLOCK NETTING_NO_VALUE";
   PlVecSymEURUSD(v.s);
   PlVecAccount(v.a,"USD",2,100000.0,100000.0,0.0,100000.0);
   v.a.margin_mode=ACCOUNT_MARGIN_MODE_RETAIL_NETTING;
   PlVecInputs(v.in);
   v.in.sl=1.11824;
   v.in.calcprofit_ok=true;
   v.in.calcprofit_loss_1lot=200.0;
   v.in.comm.kind=PL_COMM_LOT_SIDE; v.in.comm.rate=0.0; v.in.comm.source=PL_COMMSRC_USER;
   v.chk_prepare_ok=true; v.exp_prepare_ok=true;
   v.s.net_vol=1.0; v.s.net_buy=true; v.s.net_open=1.12000; v.s.net_sl=1.11900;
   v.in.net_calc_ok=false; v.in.net_loss_new=0.0; v.in.net_loss_old=0.0;
   v.exp_side=PL_SIDE_BUY;
   v.exp_verdict=PL_BLOCK;
   v.exp_reason=PL_R_NETTING_NO_VALUE;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 134 hedging_ignores_net_fields
//| The inputs of vector 120 on a hedging account: net fields ignored, nothing changes
//|   Base: EURUSD (vol_min 0.01, step 0.01, vol_max 50), Ask 1.12024, SL 1.11824 = 20 pips = 200 USD per lot.
//|   USD account, balance = equity = free margin 100 000, risk 1% so target 1000, commission 0, one TP none, RETAIL_NETTING.
//|   Open position 1.00 lot buy at 1.12000: loss at the new SL 1.11824 is 0.00176 * 100000 = 176.
//|   RETAIL_HEDGING: the net_* fields are ignored. lot = 1000 / 200 = 5.00, risk_money = risk_add = 1000, net_risk 0.
//+------------------------------------------------------------------+
void PlVec134(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="hedging_ignores_net_fields";
   v.what="The inputs of vector 120 on a hedging account: net fields ignored, nothing changes";
   PlVecSymEURUSD(v.s);
   PlVecAccount(v.a,"USD",2,100000.0,100000.0,0.0,100000.0);
   v.a.margin_mode=ACCOUNT_MARGIN_MODE_RETAIL_NETTING;
   PlVecInputs(v.in);
   v.in.sl=1.11824;
   v.in.calcprofit_ok=true;
   v.in.calcprofit_loss_1lot=200.0;
   v.in.comm.kind=PL_COMM_LOT_SIDE; v.in.comm.rate=0.0; v.in.comm.source=PL_COMMSRC_USER;
   v.chk_prepare_ok=true; v.exp_prepare_ok=true;
   v.s.net_vol=1.0; v.s.net_buy=true; v.s.net_open=1.12000; v.s.net_sl=1.11900;
   v.in.net_calc_ok=true; v.in.net_loss_new=176.0; v.in.net_loss_old=100.0;
   v.a.margin_mode=ACCOUNT_MARGIN_MODE_RETAIL_HEDGING;
   v.exp_side=PL_SIDE_BUY;
   v.exp_lot=5.0;
   v.exp_risk_money=1000.0;
   v.exp_risk_add=1000.0;
   v.exp_net_risk=0.0;
   v.exp_verdict=PL_OK;
   v.exp_reason=PL_R_NONE;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 135 netting_tp_parts_below_min
//| Netting, no position, lot 0.01 with TP shares 70/30: BLOCK TP_PARTS
//|   Base: EURUSD data, netting account, no open position, balance 100 000, risk in money = lot * 200 so the lot comes out exactly, far below the cap.
//|   Level 1 closes floor(0.01 - 0.01 * 30 / 100 = 0.007) on step 0.01 = 0 < vol_min 0.01: the share cannot close: BLOCK PL_R_NETTING_TP_PARTS.
//+------------------------------------------------------------------+
void PlVec135(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="netting_tp_parts_below_min";
   v.what="Netting, no position, lot 0.01 with TP shares 70/30: BLOCK TP_PARTS";
   PlVecSymEURUSD(v.s);
   PlVecAccount(v.a,"USD",2,100000.0,100000.0,0.0,100000.0);
   v.a.margin_mode=ACCOUNT_MARGIN_MODE_RETAIL_NETTING;
   PlVecInputs(v.in);
   v.in.sl=1.11824;
   v.in.calcprofit_ok=true;
   v.in.calcprofit_loss_1lot=200.0;
   v.in.comm.kind=PL_COMM_LOT_SIDE; v.in.comm.rate=0.0; v.in.comm.source=PL_COMMSRC_USER;
   v.chk_prepare_ok=true; v.exp_prepare_ok=true;
   v.in.risk_mode=PL_RISK_MONEY;
   v.in.risk_money=2.0;   // lot 0.01 at 200 per lot
   v.in.no_tp=false;
   v.in.tp[0].on=true; v.in.tp[0].mode=PL_TP_R; v.in.tp[0].r=1.0; v.in.tp[0].share=70.0;
   v.in.tp[1].on=true; v.in.tp[1].mode=PL_TP_R; v.in.tp[1].r=2.0; v.in.tp[1].share=30.0;
   v.exp_side=PL_SIDE_BUY;
   v.exp_lot=0.01;
   v.exp_verdict=PL_BLOCK;
   v.exp_reason=PL_R_NETTING_TP_PARTS;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 136 netting_tp_parts_fit
//| Netting, no position, lot 0.02 with TP shares 70/30: OK
//|   Base: EURUSD data, netting account, no open position, balance 100 000, risk in money = lot * 200 so the lot comes out exactly, far below the cap.
//|   Level 1 closes floor(0.02 - 0.006 = 0.014) = 0.01 >= vol_min, the rest 0.01 >= vol_min: OK.
//+------------------------------------------------------------------+
void PlVec136(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="netting_tp_parts_fit";
   v.what="Netting, no position, lot 0.02 with TP shares 70/30: OK";
   PlVecSymEURUSD(v.s);
   PlVecAccount(v.a,"USD",2,100000.0,100000.0,0.0,100000.0);
   v.a.margin_mode=ACCOUNT_MARGIN_MODE_RETAIL_NETTING;
   PlVecInputs(v.in);
   v.in.sl=1.11824;
   v.in.calcprofit_ok=true;
   v.in.calcprofit_loss_1lot=200.0;
   v.in.comm.kind=PL_COMM_LOT_SIDE; v.in.comm.rate=0.0; v.in.comm.source=PL_COMMSRC_USER;
   v.chk_prepare_ok=true; v.exp_prepare_ok=true;
   v.in.risk_mode=PL_RISK_MONEY;
   v.in.risk_money=4.0;   // lot 0.02 at 200 per lot
   v.in.no_tp=false;
   v.in.tp[0].on=true; v.in.tp[0].mode=PL_TP_R; v.in.tp[0].r=1.0; v.in.tp[0].share=70.0;
   v.in.tp[1].on=true; v.in.tp[1].mode=PL_TP_R; v.in.tp[1].r=2.0; v.in.tp[1].share=30.0;
   v.exp_side=PL_SIDE_BUY;
   v.exp_lot=0.02;
   v.exp_verdict=PL_OK;
   v.exp_reason=PL_R_NONE;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 137 netting_tp_parts_stock_grid_below
//| Netting, grid 1/1 (FTMO stock shape), lot 1, shares 50/50: BLOCK TP_PARTS
//|   Base: EURUSD data, netting account, no open position, balance 100 000, risk in money = lot * 200 so the lot comes out exactly, far below the cap.
//|   Grid vol_min 1, step 1, vol_max 1000 (the shape of the FTMO stock symbols; the price data are EURUSD's).
//|   Level 1 closes floor(1 - 0.5) = 0 < 1: BLOCK PL_R_NETTING_TP_PARTS.
//+------------------------------------------------------------------+
void PlVec137(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="netting_tp_parts_stock_grid_below";
   v.what="Netting, grid 1/1 (FTMO stock shape), lot 1, shares 50/50: BLOCK TP_PARTS";
   PlVecSymEURUSD(v.s);
   PlVecAccount(v.a,"USD",2,100000.0,100000.0,0.0,100000.0);
   v.a.margin_mode=ACCOUNT_MARGIN_MODE_RETAIL_NETTING;
   PlVecInputs(v.in);
   v.in.sl=1.11824;
   v.in.calcprofit_ok=true;
   v.in.calcprofit_loss_1lot=200.0;
   v.in.comm.kind=PL_COMM_LOT_SIDE; v.in.comm.rate=0.0; v.in.comm.source=PL_COMMSRC_USER;
   v.chk_prepare_ok=true; v.exp_prepare_ok=true;
   v.in.risk_mode=PL_RISK_MONEY;
   v.in.risk_money=200.0;   // lot 1.0 at 200 per lot
   v.in.no_tp=false;
   v.s.vol_min=1.0; v.s.vol_step=1.0; v.s.vol_max=1000.0;
   v.in.tp[0].on=true; v.in.tp[0].mode=PL_TP_R; v.in.tp[0].r=1.0; v.in.tp[0].share=50.0;
   v.in.tp[1].on=true; v.in.tp[1].mode=PL_TP_R; v.in.tp[1].r=2.0; v.in.tp[1].share=50.0;
   v.exp_side=PL_SIDE_BUY;
   v.exp_lot=1.0;
   v.exp_verdict=PL_BLOCK;
   v.exp_reason=PL_R_NETTING_TP_PARTS;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 138 netting_tp_parts_stock_grid_fit
//| Netting, grid 1/1, lot 2, shares 50/50: OK
//|   Base: EURUSD data, netting account, no open position, balance 100 000, risk in money = lot * 200 so the lot comes out exactly, far below the cap.
//|   Level 1 closes floor(2 - 1) = 1 >= 1, the rest 1 >= 1: OK.
//+------------------------------------------------------------------+
void PlVec138(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="netting_tp_parts_stock_grid_fit";
   v.what="Netting, grid 1/1, lot 2, shares 50/50: OK";
   PlVecSymEURUSD(v.s);
   PlVecAccount(v.a,"USD",2,100000.0,100000.0,0.0,100000.0);
   v.a.margin_mode=ACCOUNT_MARGIN_MODE_RETAIL_NETTING;
   PlVecInputs(v.in);
   v.in.sl=1.11824;
   v.in.calcprofit_ok=true;
   v.in.calcprofit_loss_1lot=200.0;
   v.in.comm.kind=PL_COMM_LOT_SIDE; v.in.comm.rate=0.0; v.in.comm.source=PL_COMMSRC_USER;
   v.chk_prepare_ok=true; v.exp_prepare_ok=true;
   v.in.risk_mode=PL_RISK_MONEY;
   v.in.risk_money=400.0;   // lot 2.0 at 200 per lot
   v.in.no_tp=false;
   v.s.vol_min=1.0; v.s.vol_step=1.0; v.s.vol_max=1000.0;
   v.in.tp[0].on=true; v.in.tp[0].mode=PL_TP_R; v.in.tp[0].r=1.0; v.in.tp[0].share=50.0;
   v.in.tp[1].on=true; v.in.tp[1].mode=PL_TP_R; v.in.tp[1].r=2.0; v.in.tp[1].share=50.0;
   v.exp_side=PL_SIDE_BUY;
   v.exp_lot=2.0;
   v.exp_verdict=PL_OK;
   v.exp_reason=PL_R_NONE;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 139 netting_tp_parts_bybit_grid_below
//| Netting, grid 0.1/0.1 (Bybit shape), lot 0.1, shares 70/30: BLOCK TP_PARTS
//|   Base: EURUSD data, netting account, no open position, balance 100 000, risk in money = lot * 200 so the lot comes out exactly, far below the cap.
//|   Grid vol_min 0.1, step 0.1, vol_max 100. Level 1 closes floor(0.1 - 0.03 = 0.07 on step 0.1) = 0 < 0.1: BLOCK PL_R_NETTING_TP_PARTS.
//+------------------------------------------------------------------+
void PlVec139(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="netting_tp_parts_bybit_grid_below";
   v.what="Netting, grid 0.1/0.1 (Bybit shape), lot 0.1, shares 70/30: BLOCK TP_PARTS";
   PlVecSymEURUSD(v.s);
   PlVecAccount(v.a,"USD",2,100000.0,100000.0,0.0,100000.0);
   v.a.margin_mode=ACCOUNT_MARGIN_MODE_RETAIL_NETTING;
   PlVecInputs(v.in);
   v.in.sl=1.11824;
   v.in.calcprofit_ok=true;
   v.in.calcprofit_loss_1lot=200.0;
   v.in.comm.kind=PL_COMM_LOT_SIDE; v.in.comm.rate=0.0; v.in.comm.source=PL_COMMSRC_USER;
   v.chk_prepare_ok=true; v.exp_prepare_ok=true;
   v.in.risk_mode=PL_RISK_MONEY;
   v.in.risk_money=20.0;   // lot 0.1 at 200 per lot
   v.in.no_tp=false;
   v.s.vol_min=0.1; v.s.vol_step=0.1; v.s.vol_max=100.0;
   v.in.tp[0].on=true; v.in.tp[0].mode=PL_TP_R; v.in.tp[0].r=1.0; v.in.tp[0].share=70.0;
   v.in.tp[1].on=true; v.in.tp[1].mode=PL_TP_R; v.in.tp[1].r=2.0; v.in.tp[1].share=30.0;
   v.exp_side=PL_SIDE_BUY;
   v.exp_lot=0.1;
   v.exp_verdict=PL_BLOCK;
   v.exp_reason=PL_R_NETTING_TP_PARTS;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 140 netting_tp_parts_bybit_grid_fit
//| Netting, grid 0.1/0.1, lot 0.2, shares 70/30: OK
//|   Base: EURUSD data, netting account, no open position, balance 100 000, risk in money = lot * 200 so the lot comes out exactly, far below the cap.
//|   Level 1 closes floor(0.2 - 0.06 = 0.14 on step 0.1) = 0.1 >= 0.1, the rest 0.1 >= 0.1: OK.
//+------------------------------------------------------------------+
void PlVec140(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="netting_tp_parts_bybit_grid_fit";
   v.what="Netting, grid 0.1/0.1, lot 0.2, shares 70/30: OK";
   PlVecSymEURUSD(v.s);
   PlVecAccount(v.a,"USD",2,100000.0,100000.0,0.0,100000.0);
   v.a.margin_mode=ACCOUNT_MARGIN_MODE_RETAIL_NETTING;
   PlVecInputs(v.in);
   v.in.sl=1.11824;
   v.in.calcprofit_ok=true;
   v.in.calcprofit_loss_1lot=200.0;
   v.in.comm.kind=PL_COMM_LOT_SIDE; v.in.comm.rate=0.0; v.in.comm.source=PL_COMMSRC_USER;
   v.chk_prepare_ok=true; v.exp_prepare_ok=true;
   v.in.risk_mode=PL_RISK_MONEY;
   v.in.risk_money=40.0;   // lot 0.2 at 200 per lot
   v.in.no_tp=false;
   v.s.vol_min=0.1; v.s.vol_step=0.1; v.s.vol_max=100.0;
   v.in.tp[0].on=true; v.in.tp[0].mode=PL_TP_R; v.in.tp[0].r=1.0; v.in.tp[0].share=70.0;
   v.in.tp[1].on=true; v.in.tp[1].mode=PL_TP_R; v.in.tp[1].r=2.0; v.in.tp[1].share=30.0;
   v.exp_side=PL_SIDE_BUY;
   v.exp_lot=0.2;
   v.exp_verdict=PL_OK;
   v.exp_reason=PL_R_NONE;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 141 netting_tp_parts_three_fit
//| Netting, three TPs 50/30/20, lot 0.03: OK
//|   Base: EURUSD data, netting account, no open position, balance 100 000, risk in money = lot * 200 so the lot comes out exactly, far below the cap.
//|   Level 1: floor(0.03 - 0.015 = 0.015) = 0.01, left 0.02. Level 2: floor(0.02 - 0.006 = 0.014) = 0.01, left 0.01 >= vol_min: OK.
//+------------------------------------------------------------------+
void PlVec141(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="netting_tp_parts_three_fit";
   v.what="Netting, three TPs 50/30/20, lot 0.03: OK";
   PlVecSymEURUSD(v.s);
   PlVecAccount(v.a,"USD",2,100000.0,100000.0,0.0,100000.0);
   v.a.margin_mode=ACCOUNT_MARGIN_MODE_RETAIL_NETTING;
   PlVecInputs(v.in);
   v.in.sl=1.11824;
   v.in.calcprofit_ok=true;
   v.in.calcprofit_loss_1lot=200.0;
   v.in.comm.kind=PL_COMM_LOT_SIDE; v.in.comm.rate=0.0; v.in.comm.source=PL_COMMSRC_USER;
   v.chk_prepare_ok=true; v.exp_prepare_ok=true;
   v.in.risk_mode=PL_RISK_MONEY;
   v.in.risk_money=6.0;   // lot 0.03 at 200 per lot
   v.in.no_tp=false;
   v.in.tp[0].on=true; v.in.tp[0].mode=PL_TP_R; v.in.tp[0].r=1.0; v.in.tp[0].share=50.0;
   v.in.tp[1].on=true; v.in.tp[1].mode=PL_TP_R; v.in.tp[1].r=2.0; v.in.tp[1].share=30.0;
   v.in.tp[2].on=true; v.in.tp[2].mode=PL_TP_R; v.in.tp[2].r=3.0; v.in.tp[2].share=20.0;
   v.exp_side=PL_SIDE_BUY;
   v.exp_lot=0.03;
   v.exp_verdict=PL_OK;
   v.exp_reason=PL_R_NONE;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 142 netting_tp_parts_three_below
//| Netting, three TPs 50/30/20, lot 0.02: BLOCK TP_PARTS
//|   Base: EURUSD data, netting account, no open position, balance 100 000, risk in money = lot * 200 so the lot comes out exactly, far below the cap.
//|   Level 1: floor(0.02 - 0.01) = 0.01, left 0.01. Level 2: floor(0.01 - 0.004 = 0.006) = 0 < vol_min: BLOCK PL_R_NETTING_TP_PARTS.
//+------------------------------------------------------------------+
void PlVec142(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="netting_tp_parts_three_below";
   v.what="Netting, three TPs 50/30/20, lot 0.02: BLOCK TP_PARTS";
   PlVecSymEURUSD(v.s);
   PlVecAccount(v.a,"USD",2,100000.0,100000.0,0.0,100000.0);
   v.a.margin_mode=ACCOUNT_MARGIN_MODE_RETAIL_NETTING;
   PlVecInputs(v.in);
   v.in.sl=1.11824;
   v.in.calcprofit_ok=true;
   v.in.calcprofit_loss_1lot=200.0;
   v.in.comm.kind=PL_COMM_LOT_SIDE; v.in.comm.rate=0.0; v.in.comm.source=PL_COMMSRC_USER;
   v.chk_prepare_ok=true; v.exp_prepare_ok=true;
   v.in.risk_mode=PL_RISK_MONEY;
   v.in.risk_money=4.0;   // lot 0.02 at 200 per lot
   v.in.no_tp=false;
   v.in.tp[0].on=true; v.in.tp[0].mode=PL_TP_R; v.in.tp[0].r=1.0; v.in.tp[0].share=50.0;
   v.in.tp[1].on=true; v.in.tp[1].mode=PL_TP_R; v.in.tp[1].r=2.0; v.in.tp[1].share=30.0;
   v.in.tp[2].on=true; v.in.tp[2].mode=PL_TP_R; v.in.tp[2].r=3.0; v.in.tp[2].share=20.0;
   v.exp_side=PL_SIDE_BUY;
   v.exp_lot=0.02;
   v.exp_verdict=PL_BLOCK;
   v.exp_reason=PL_R_NETTING_TP_PARTS;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 143 stale_quote_open_pending
//| Open session, last tick 120 s old, Buy Limit below the market: WARN PL_R_STALE_QUOTE (a pending order is placed, not filled now)
//|   Same data as 58 with the entry 1.115 and the SL 1.113.
//+------------------------------------------------------------------+
void PlVec143(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="stale_quote_open_pending";
   v.what="Open session, last tick 120 s old, Buy Limit below the market: WARN PL_R_STALE_QUOTE";
   PlVecSymEURUSD(v.s);
   v.s.tick_time=D'2026.10.09 11:58:00';
   PlVecAccount(v.a,"USD",2,10000.0,10000.0,0.0,10000.0);
   PlVecInputs(v.in);
   v.in.kind=PL_KIND_LIMIT;
   v.in.entry=1.115;
   v.in.sl=1.113;
   v.in.comm.kind=PL_COMM_LOT_ROUND; v.in.comm.rate=7.0; v.in.comm.source=PL_COMMSRC_USER;
   v.in.calcprofit_ok=true; v.in.calcprofit_loss_1lot=200.0;
   v.exp_verdict=PL_WARN;
   v.exp_reason=PL_R_STALE_QUOTE;
   v.exp_note=PL_R_NONE;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 144 no_sl_percent_mode
//| Same as 54 but the risk mode is percent (1%): without an SL the lot is still lot_fixed 0.1, risk 0, CONFIRM PL_R_NO_SL
//|   Lot.mqh takes lot_fixed whenever there is no SL, whatever the risk mode says.
//+------------------------------------------------------------------+
void PlVec144(PlVector &v)
  {
   PlVec54(v);
   v.name="no_sl_percent_mode";
   v.what="no_sl with risk mode percent 1: lot is lot_fixed 0.1, risk 0, CONFIRM PL_R_NO_SL";
   v.in.risk_mode=PL_RISK_PERCENT;
   v.in.risk_percent=1.0;
  }

//+------------------------------------------------------------------+
//| 145 atr_not_ready, 146 atr_mult_zero
//| ATR stop is on but the indicator value (or the multiplier) is 0: the plan refuses, the old SL is never used
//+------------------------------------------------------------------+
void PlVec145(PlVector &v)
  {
   PlVec53(v);
   PlVecUnchecked(v);
   v.name="atr_not_ready";
   v.what="atr_on with atr 0: PL_R_ATR_NOT_READY, no fallback to the typed SL";
   v.in.atr=0.0;
   v.chk_prepare_ok=true; v.exp_prepare_ok=false;
   v.exp_plan_reason=PL_R_ATR_NOT_READY;
   v.exp_verdict=PL_BLOCK;
   v.exp_reason=PL_R_ATR_NOT_READY;
   v.exp_note=PL_R_NONE;
   v.tol_money=0.001;
  }

void PlVec146(PlVector &v)
  {
   PlVec53(v);
   PlVecUnchecked(v);
   v.name="atr_mult_zero";
   v.what="atr_on with multiplier 0: PL_R_ATR_NOT_READY, no fallback to the typed SL";
   v.in.atr_mult=0.0;
   v.chk_prepare_ok=true; v.exp_prepare_ok=false;
   v.exp_plan_reason=PL_R_ATR_NOT_READY;
   v.exp_verdict=PL_BLOCK;
   v.exp_reason=PL_R_ATR_NOT_READY;
   v.exp_note=PL_R_NONE;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 147 broker_pct_btcusd
//| The broker's PERCENT rule (BTCUSD, FTMO demo 13.10.2026: value 0.0325, INOUT) reaches PlCompute as the same percent
//| setting as vector 08 (PlBrokerCommRule gives PL_COMM_PERCENT_SIDE, 0.0325, checked in PlCoreTests); only the source
//| differs (PL_COMMSRC_BROKER), so every expected number is that of vector 08.
//+------------------------------------------------------------------+
void PlVec147(PlVector &v)
  {
   PlVec08(v);
   v.name="broker_pct_btcusd";
   v.what="Broker PERCENT rule 0.0325 INOUT as the commission: same lot and numbers as the user setting of vector 08";
   v.in.comm.kind=PL_COMM_PERCENT_SIDE; v.in.comm.rate=0.0325; v.in.comm.source=PL_COMMSRC_BROKER;
  }

//+------------------------------------------------------------------+
//| 148 broker_money_usdjpy
//| The broker's MONEY_SPECIFIED rule (USDJPY, FTMO demo 13.10.2026: value 2.5, INOUT) is PL_COMM_LOT_SIDE 2.5, the same
//| as vector 03; only the source differs (PL_COMMSRC_BROKER), every expected number is that of vector 03.
//+------------------------------------------------------------------+
void PlVec148(PlVector &v)
  {
   PlVec03(v);
   v.name="broker_money_usdjpy";
   v.what="Broker MONEY_SPECIFIED rule 2.5 INOUT as the commission: same lot and numbers as the user setting of vector 03";
   v.in.comm.kind=PL_COMM_LOT_SIDE; v.in.comm.rate=2.5; v.in.comm.source=PL_COMMSRC_BROKER;
  }

//--- a share on an account in UST, the shape of the Bybit shares of the probe of 14.10.2026 (AALG: CFD, 2 digits, tick 0.01 worth
//--- 0.01, contract 1, lot 0.1 step 0.1); the quote is synthetic (the probe held none), the tier of its commission is in USD
void PlVecSymShare(PlSymbol &s)
  {
   s.name="SHARE";
   s.base="USD";
   s.profit="USD";
   s.margin="USD";
   s.calc_mode=SYMBOL_CALC_MODE_CFD;
   s.digits=2;
   s.point=0.01;
   s.tick_size=0.01;
   s.tick_value_loss=0.01;
   s.tick_value_profit=0.01;
   s.contract=1.0;
   s.vol_min=0.1;
   s.vol_max=1000.0;
   s.vol_step=0.1;
   s.vol_limit=0.0;
   s.vol_open_buy=0.0; s.vol_open_sell=0.0;
   s.stops_level=0;
   s.freeze_level=0;
   s.order_mode=127;
   s.filling_mode=3;
   s.exec_mode=SYMBOL_TRADE_EXECUTION_MARKET;
   s.expiration_mode=15;
   s.gtc_mode=SYMBOL_ORDERS_GTC;
   s.bid=100.00;
   s.ask=100.05;
   s.session_open=true;
   s.swap_mode=SYMBOL_SWAP_MODE_DISABLED;
   s.swap_long=0.0;
   s.swap_short=0.0;
   s.swap_3day=FRIDAY;
   s.margin_buy_1lot=100.05;
   s.margin_sell_1lot=100.00;
   s.tick_time=D'2026.10.09 12:00:00';
   s.server_now=D'2026.10.09 12:00:00';
  }

//--- the base of the minimum-commission vectors 149-156: EURUSD data, hedging USD account, balance 10000, Buy at Ask 1.12024, SL 1.11824
//--- (200 ticks worth 1 each, loss 200 per lot from OrderCalcProfit), commission per round 0.50 per lot (in 0.25, out 0.25) with a broker
//--- minimum of 20.00 per order, risk 100.00 (1%). Each vector says what it changes.
void PlVecMinBase(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   PlVecSymEURUSD(v.s);
   PlVecAccount(v.a,"USD",2,10000.0,10000.0,0.0,10000.0);
   PlVecInputs(v.in);
   v.in.sl=1.11824;
   v.in.calcprofit_ok=true;
   v.in.calcprofit_loss_1lot=200.0;
   v.in.comm.kind=PL_COMM_LOT_ROUND; v.in.comm.rate=0.5; v.in.comm.min_money=20.0; v.in.comm.source=PL_COMMSRC_BROKER;
   v.chk_prepare_ok=true; v.exp_prepare_ok=true;
   v.exp_plan_reason=PL_R_NONE;
   v.exp_side=PL_SIDE_BUY;
   v.exp_order_type=ORDER_TYPE_BUY;
   v.exp_exec=1.12024;
   v.exp_sl=1.11824;
   v.exp_ticks=200;
   v.exp_lpl_price=200.0;
   v.exp_verdict=PL_OK;
   v.exp_reason=PL_R_NONE;
   v.exp_note=PL_R_NONE;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 149 comm_min_not_acting
//| A minimum far below the commission of the lot changes nothing: same lot, risk and commission as with no minimum
//|   Rate 7.00 per round (in 3.5, out 3.5), minimum 0.50, n_orders 0 (one). loss_per_lot = 200 + 7 = 207.
//|   lot_raw = 100 / 207 = 0.48309179; commission of lot_raw = 0.48309179 * 7 = 3.38 >= 0.50: linear. lot = 0.48.
//|   commission = 0.48 * 7 = 3.36 >= 0.50: the rate decides. risk = 0.48 * 207 = 99.36.
//+------------------------------------------------------------------+
void PlVec149(PlVector &v)
  {
   PlVecMinBase(v);
   v.name="comm_min_not_acting";
   v.what="Minimum commission 0.50 below the commission of the lot: linear lot 0.48, commission 3.36, minimum not on";
   v.in.comm.rate=7.0; v.in.comm.min_money=0.5;
   v.exp_comm_in=3.5; v.exp_comm_out=3.5; v.exp_loss_per_lot=207.0;
   v.exp_lot=0.48; v.exp_risk_money=99.36; v.exp_risk_add=99.36; v.exp_risk_percent=0.9936;
   v.exp_comm_money=3.36; v.exp_comm_min_on=0;
  }

//+------------------------------------------------------------------+
//| 150 comm_min_acting
//| The commission of the lot is below the minimum: the minimum is a fixed sum, the lot is what is left after it
//|   Rate 0.50 per round (in 0.25, out 0.25), minimum 20.00. loss_per_lot = 200.5.
//|   lot_raw linear = 100 / 200.5 = 0.49875; its commission 0.49875 * 0.5 = 0.249 < 20.00: the minimum acts.
//|   lot_raw = (100 - 20) / 200 = 0.4; lot = 0.01 + floor(0.39 / 0.01) * 0.01 = 0.40.
//|   commission = max(0.4 * 0.5 = 0.20, 20.00) = 20.00. risk = 0.4 * 200 + 20.00 = 100.00 = 0.4 * 200.5 + (20.00 - 0.20) = 100.00.
//|   TP 2R share 100: reward = 0.4 * 400 - 20.00 = 140.00, rr = 1.4. margin = 0.4 * 1120.24 = 448.096. spread 6 points = 0.4 * 6 = 2.40.
//+------------------------------------------------------------------+
void PlVec150(PlVector &v)
  {
   PlVecMinBase(v);
   v.name="comm_min_acting";
   v.what="Minimum commission 20.00 above the commission of the lot: lot (100-20)/200 = 0.40, commission 20.00, risk exactly 100.00";
   v.in.no_tp=false;
   v.in.tp[0].on=true; v.in.tp[0].mode=PL_TP_R; v.in.tp[0].r=2.0; v.in.tp[0].price=0.0; v.in.tp[0].share=100.0;
   v.exp_tp=1.12424;
   v.exp_comm_in=0.25; v.exp_comm_out=0.25; v.exp_loss_per_lot=200.5;
   v.exp_lot=0.40; v.exp_risk_money=100.0; v.exp_risk_add=100.0; v.exp_risk_percent=1.0;
   v.exp_reward_total=140.0; v.exp_rr=1.4; v.exp_margin_needed=448.096; v.exp_spread_points=6.0; v.exp_spread_money=2.4;
   v.exp_comm_money=20.0; v.exp_comm_min_on=1;
  }

//+------------------------------------------------------------------+
//| 151 comm_min_two_orders
//| Two orders each pay the minimum: n_orders 2 of vector 150
//|   Minimum for the press = 2 * 20.00 = 40.00; commission of lot_raw linear 0.249 < 40.00: the minimum acts.
//|   lot_raw = (100 - 40) / 200 = 0.3; lot = 0.01 + floor(0.29 / 0.01) * 0.01 = 0.30.
//|   commission = max(0.3 * 0.5 = 0.15, 40.00) = 40.00. risk = 0.3 * 200.5 + (40.00 - 0.15) = 60.15 + 39.85 = 100.00.
//+------------------------------------------------------------------+
void PlVec151(PlVector &v)
  {
   PlVecMinBase(v);
   v.name="comm_min_two_orders";
   v.what="Minimum 20.00 and n_orders 2: 40.00 for the press, lot (100-40)/200 = 0.30, risk exactly 100.00";
   v.in.n_orders=2;
   v.exp_comm_in=0.25; v.exp_comm_out=0.25; v.exp_loss_per_lot=200.5;
   v.exp_lot=0.30; v.exp_risk_money=100.0; v.exp_risk_add=100.0; v.exp_risk_percent=1.0;
   v.exp_comm_money=40.0; v.exp_comm_min_on=1;
  }

//+------------------------------------------------------------------+
//| 152 comm_min_one_order_linear
//| One order: the lot's commission is above the minimum, linear. The same rate, minimum 20.00, n_orders 1
//|   Rate 60.00 per round (in 30, out 30), loss_per_lot = 260. lot_raw = 100 / 260 = 0.384615; commission 0.384615 * 60 = 23.08 >= 20.00: linear.
//|   lot = 0.01 + floor(0.374615 / 0.01) * 0.01 = 0.38. commission = 0.38 * 60 = 22.80 >= 20.00: the rate decides. risk = 0.38 * 260 = 98.80.
//+------------------------------------------------------------------+
void PlVec152(PlVector &v)
  {
   PlVecMinBase(v);
   v.name="comm_min_one_order_linear";
   v.what="Rate 60 per round, minimum 20.00, one order: the commission of the lot (22.80) is above the minimum, lot 0.38, risk 98.80";
   v.in.comm.rate=60.0;
   v.exp_comm_in=30.0; v.exp_comm_out=30.0; v.exp_loss_per_lot=260.0;
   v.exp_lot=0.38; v.exp_risk_money=98.8; v.exp_risk_add=98.8; v.exp_risk_percent=0.988;
   v.exp_comm_money=22.8; v.exp_comm_min_on=0;
  }

//+------------------------------------------------------------------+
//| 153 comm_min_per_order_two
//| The same rate as vector 152 with two orders: the total commission of the lot is above 20.00 but each order is below it
//|   Minimum for the press = 2 * 20.00 = 40.00. Linear lot_raw = 0.384615: its commission 23.08 < 40.00: the minimum acts
//|   (each order carries 0.19 * 60 = 11.5 < 20.00; a test of the whole lot against one minimum would call this linear).
//|   lot_raw = (100 - 40) / 200 = 0.3; lot = 0.30. commission = max(0.3 * 60 = 18.00, 40.00) = 40.00. risk = 0.3 * 200 + 40.00 = 100.00.
//+------------------------------------------------------------------+
void PlVec153(PlVector &v)
  {
   PlVecMinBase(v);
   v.name="comm_min_per_order_two";
   v.what="Rate 60 per round, minimum 20.00, two orders: the minimum acts per order, lot (100-40)/200 = 0.30, commission 40.00";
   v.in.comm.rate=60.0;
   v.in.n_orders=2;
   v.exp_comm_in=30.0; v.exp_comm_out=30.0; v.exp_loss_per_lot=260.0;
   v.exp_lot=0.30; v.exp_risk_money=100.0; v.exp_risk_add=100.0; v.exp_risk_percent=1.0;
   v.exp_comm_money=40.0; v.exp_comm_min_on=1;
  }

//+------------------------------------------------------------------+
//| 154 comm_min_no_room
//| The money for the trade is no more than the minimum: the lot goes to the minimal lot and asks to confirm, no new reason
//|   Risk 15.00 in money, minimum 20.00, one order. avail = 15 <= 20: lot_raw = max(0, (15 - 20) / 200) = 0 < vol_min 0.01.
//|   lot = 0.01, below the minimum: verdict CONFIRM, reason LOT_BELOW_MIN.
//|   commission = max(0.01 * 0.5 = 0.005, 20.00) = 20.00. risk = 0.01 * 200 + 20.00 = 22.00 (the true risk), 0.22% of 10000.
//+------------------------------------------------------------------+
void PlVec154(PlVector &v)
  {
   PlVecMinBase(v);
   v.name="comm_min_no_room";
   v.what="Risk 15.00 under the minimum commission 20.00: lot 0.01, CONFIRM LOT_BELOW_MIN, risk shown 22.00";
   v.in.risk_mode=PL_RISK_MONEY; v.in.risk_money=15.0;
   v.exp_comm_in=0.25; v.exp_comm_out=0.25; v.exp_loss_per_lot=200.5;
   v.exp_lot=0.01; v.exp_risk_money=22.0; v.exp_risk_add=22.0; v.exp_risk_percent=0.22;
   v.exp_comm_money=20.0; v.exp_comm_min_on=1;
   v.exp_verdict=PL_CONFIRM; v.exp_reason=PL_R_LOT_BELOW_MIN;
  }

//+------------------------------------------------------------------+
//| 156 comm_min_two_tps
//| Reward with two TP levels and two orders: the commission of the press (40.00) is shared by the shares
//|   As vector 151: lot 0.30, commission 40.00. TP1 1R (200 ticks) share 50: 0.15 * 200 - 40.00 * 50 / 100 = 30 - 20 = 10.00.
//|   TP2 2R (400 ticks) share 50: 0.15 * 400 - 20 = 60 - 20 = 40.00. reward_total 50.00, rr = 50 / 100 = 0.5.
//+------------------------------------------------------------------+
void PlVec156(PlVector &v)
  {
   PlVecMinBase(v);
   v.name="comm_min_two_tps";
   v.what="Minimum 20.00, two orders, TP 1R 50% and 2R 50%: commission 40.00 split by shares, reward 50.00";
   v.in.n_orders=2;
   v.in.no_tp=false;
   v.in.tp[0].on=true; v.in.tp[0].mode=PL_TP_R; v.in.tp[0].r=1.0; v.in.tp[0].price=0.0; v.in.tp[0].share=50.0;
   v.in.tp[1].on=true; v.in.tp[1].mode=PL_TP_R; v.in.tp[1].r=2.0; v.in.tp[1].price=0.0; v.in.tp[1].share=50.0;
   v.exp_lot=0.30; v.exp_risk_money=100.0; v.exp_risk_add=100.0; v.exp_risk_percent=1.0;
   v.exp_reward_total=50.0; v.exp_rr=0.5;
   v.exp_comm_money=40.0; v.exp_comm_min_on=1;
  }

//+------------------------------------------------------------------+
//| 157 comm_min_share_ust
//| A Bybit-like share on a UST account: rate 0.02 per round (the broker's USD tier converted at k = 1), minimum 0.20
//|   Buy at Ask 100.05, SL 99.00 (105 ticks of 0.01 worth 0.01): loss 1.05 per lot. Risk 5.00 in money. Rate round 0.02: in 0.01, out 0.01,
//|   loss_per_lot = 1.07. Linear lot_raw = 5 / 1.07 = 4.6729; its commission 4.6729 * 0.02 = 0.0935 < 0.20: the minimum acts.
//|   lot_raw = (5.00 - 0.20) / 1.05 = 4.571428; lot = 0.1 + floor((4.571428 - 0.1) / 0.1) * 0.1 = 0.1 + 44 * 0.1 = 4.5.
//|   commission = max(4.5 * 0.02 = 0.09, 0.20) = 0.20. risk = 4.5 * 1.05 + 0.20 = 4.925 = 4.5 * 1.07 + (0.20 - 0.09). 0.04925% of 10000.
//|   margin = 4.5 * 100.05 = 450.225. spread = 0.05 / 0.01 = 5 points, money 5 * 0.01 * 4.5 = 0.225.
//+------------------------------------------------------------------+
void PlVec157(PlVector &v)
  {
   ZeroMemory(v.in);
   ZeroMemory(v.s);
   ZeroMemory(v.a);
   PlVecUnchecked(v);
   v.name="comm_min_share_ust";
   v.what="Share on a UST account, rate 0.02 per round with a minimum 0.20: lot 4.5, commission 0.20, risk 4.925";
   PlVecSymShare(v.s);
   PlVecAccount(v.a,"UST",2,10000.0,10000.0,0.0,10000.0);
   PlVecInputs(v.in);
   v.in.sl=99.0;
   v.in.calcprofit_ok=true;
   v.in.calcprofit_loss_1lot=1.05;
   v.in.risk_mode=PL_RISK_MONEY; v.in.risk_money=5.0;
   v.in.comm.kind=PL_COMM_LOT_ROUND; v.in.comm.rate=0.02; v.in.comm.min_money=0.2; v.in.comm.source=PL_COMMSRC_BROKER;
   v.chk_prepare_ok=true; v.exp_prepare_ok=true;
   v.exp_plan_reason=PL_R_NONE;
   v.exp_side=PL_SIDE_BUY;
   v.exp_order_type=ORDER_TYPE_BUY;
   v.exp_exec=100.05;
   v.exp_sl=99.0;
   v.exp_ticks=105;
   v.exp_lpl_price=1.05;
   v.exp_comm_in=0.01; v.exp_comm_out=0.01; v.exp_loss_per_lot=1.07;
   v.exp_lot=4.5; v.exp_risk_money=4.925; v.exp_risk_add=4.925; v.exp_risk_percent=0.04925;
   v.exp_margin_needed=450.225; v.exp_spread_points=5.0; v.exp_spread_money=0.225;
   v.exp_comm_money=0.2; v.exp_comm_min_on=1;
   v.exp_verdict=PL_OK; v.exp_reason=PL_R_NONE;
   v.tol_money=0.001;
  }

//+------------------------------------------------------------------+
//| 158-164 stale quote by class of symbol
//| Forex and metals: a tick older than 60 s is stale. Stocks, CFDs, indexes, commodities, crypto: older than 300 s.
//|   The numbers are those of the base vector (57 and 06, 08, 157 with their own data); only the tick age changes. The test is
//|   strictly older than the limit: a tick exactly 60 s (forex) or 300 s (the rest) old is not stale.
//+------------------------------------------------------------------+
void PlVecStaleAge(PlVector &v,const int age,const bool stale,const string name,const string what)
  {
   v.name=name;
   v.what=what;
   v.s.tick_time=(datetime)((long)v.s.server_now-age);
   v.exp_verdict=stale?PL_BLOCK:PL_OK;
   v.exp_reason=stale?PL_R_STALE_QUOTE:PL_R_NONE;
  }

void PlVec158(PlVector &v)
  {
   PlVec157(v);
   PlVecStaleAge(v,200,false,"stale_share_200s_open","A quiet share, last tick 200 s old on an open session: not stale (the limit is 300 s), the vector 157 numbers");
  }

void PlVec159(PlVector &v)
  {
   PlVec157(v);
   PlVecStaleAge(v,301,true,"stale_share_301s","A share, last tick 301 s old: BLOCK PL_R_STALE_QUOTE, numbers as usual");
  }

void PlVec160(PlVector &v)
  {
   PlVec157(v);
   PlVecStaleAge(v,300,false,"stale_share_300s_edge","A share, last tick exactly 300 s old: not stale, the vector 157 numbers");
  }

void PlVec161(PlVector &v)
  {
   PlVec58(v);
   PlVecStaleAge(v,61,true,"stale_forex_61s","EURUSD (forex), last tick 61 s old: BLOCK PL_R_STALE_QUOTE");
  }

void PlVec162(PlVector &v)
  {
   PlVec58(v);
   PlVecStaleAge(v,60,false,"stale_forex_60s_edge","EURUSD (forex), last tick exactly 60 s old: not stale, the vector 58 numbers with an OK verdict");
  }

void PlVec163(PlVector &v)
  {
   PlVec06(v);
   PlVecStaleAge(v,61,true,"stale_gold_61s","XAUUSD (a CFD calc mode, USD base, a metal by its name), last tick 61 s old: BLOCK PL_R_STALE_QUOTE");
  }

void PlVec164(PlVector &v)
  {
   PlVec08(v);
   PlVecStaleAge(v,200,false,"stale_crypto_200s_open","BTCUSD (crypto), last tick 200 s old on an open session: not stale (the limit is 300 s), the vector 08 numbers");
  }

int PlVectorCount() { return(158); }

bool PlVectorGet(const int i, PlVector &v)
  {
   switch(i)
     {
      case 0: PlVec01(v); return(true);
      case 1: PlVec02(v); return(true);
      case 2: PlVec03(v); return(true);
      case 3: PlVec04(v); return(true);
      case 4: PlVec05(v); return(true);
      case 5: PlVec06(v); return(true);
      case 6: PlVec07(v); return(true);
      case 7: PlVec08(v); return(true);
      case 8: PlVec09(v); return(true);
      case 9: PlVec10(v); return(true);
      case 10: PlVec11(v); return(true);
      case 11: PlVec12(v); return(true);
      case 12: PlVec13(v); return(true);
      case 13: PlVec14(v); return(true);
      case 14: PlVec15(v); return(true);
      case 15: PlVec16(v); return(true);
      case 16: PlVec17(v); return(true);
      case 17: PlVec18(v); return(true);
      case 18: PlVec19(v); return(true);
      case 19: PlVec22(v); return(true);
      case 20: PlVec23(v); return(true);
      case 21: PlVec24(v); return(true);
      case 22: PlVec25(v); return(true);
      case 23: PlVec26(v); return(true);
      case 24: PlVec27(v); return(true);
      case 25: PlVec28(v); return(true);
      case 26: PlVec29(v); return(true);
      case 27: PlVec30(v); return(true);
      case 28: PlVec31(v); return(true);
      case 29: PlVec32(v); return(true);
      case 30: PlVec33(v); return(true);
      case 31: PlVec34(v); return(true);
      case 32: PlVec35(v); return(true);
      case 33: PlVec36(v); return(true);
      case 34: PlVec37(v); return(true);
      case 35: PlVec38(v); return(true);
      case 36: PlVec39(v); return(true);
      case 37: PlVec40(v); return(true);
      case 38: PlVec41(v); return(true);
      case 39: PlVec42(v); return(true);
      case 40: PlVec43(v); return(true);
      case 41: PlVec44(v); return(true);
      case 42: PlVec45(v); return(true);
      case 43: PlVec46(v); return(true);
      case 44: PlVec47(v); return(true);
      case 45: PlVec48(v); return(true);
      case 46: PlVec49(v); return(true);
      case 47: PlVec50(v); return(true);
      case 48: PlVec51(v); return(true);
      case 49: PlVec52(v); return(true);
      case 50: PlVec53(v); return(true);
      case 51: PlVec54(v); return(true);
      case 52: PlVec55(v); return(true);
      case 53: PlVec56(v); return(true);
      case 54: PlVec57(v); return(true);
      case 55: PlVec58(v); return(true);
      case 56: PlVec59(v); return(true);
      case 57: PlVec60(v); return(true);
      case 58: PlVec61(v); return(true);
      case 59: PlVec62(v); return(true);
      case 60: PlVec63(v); return(true);
      case 61: PlVec64(v); return(true);
      case 62: PlVec67(v); return(true);
      case 63: PlVec68(v); return(true);
      case 64: PlVec69(v); return(true);
      case 65: PlVec70(v); return(true);
      case 66: PlVec71(v); return(true);
      case 67: PlVec72(v); return(true);
      case 68: PlVec73(v); return(true);
      case 69: PlVec74(v); return(true);
      case 70: PlVec75(v); return(true);
      case 71: PlVec76(v); return(true);
      case 72: PlVec77(v); return(true);
      case 73: PlVec78(v); return(true);
      case 74: PlVec79(v); return(true);
      case 75: PlVec80(v); return(true);
      case 76: PlVec81(v); return(true);
      case 77: PlVec82(v); return(true);
      case 78: PlVec83(v); return(true);
      case 79: PlVec84(v); return(true);
      case 80: PlVec85(v); return(true);
      case 81: PlVec86(v); return(true);
      case 82: PlVec87(v); return(true);
      case 83: PlVec88(v); return(true);
      case 84: PlVec89(v); return(true);
      case 85: PlVec90(v); return(true);
      case 86: PlVec91(v); return(true);
      case 87: PlVec92(v); return(true);
      case 88: PlVec93(v); return(true);
      case 89: PlVec94(v); return(true);
      case 90: PlVec95(v); return(true);
      case 91: PlVec96(v); return(true);
      case 92: PlVec97(v); return(true);
      case 93: PlVec98(v); return(true);
      case 94: PlVec99(v); return(true);
      case 95: PlVec100(v); return(true);
      case 96: PlVec101(v); return(true);
      case 97: PlVec102(v); return(true);
      case 98: PlVec103(v); return(true);
      case 99: PlVec104(v); return(true);
      case 100: PlVec105(v); return(true);
      case 101: PlVec106(v); return(true);
      case 102: PlVec107(v); return(true);
      case 103: PlVec108(v); return(true);
      case 104: PlVec109(v); return(true);
      case 105: PlVec110(v); return(true);
      case 106: PlVec111(v); return(true);
      case 107: PlVec112(v); return(true);
      case 108: PlVec113(v); return(true);
      case 109: PlVec114(v); return(true);
      case 110: PlVec115(v); return(true);
      case 111: PlVec116(v); return(true);
      case 112: PlVec117(v); return(true);
      case 113: PlVec118(v); return(true);
      case 114: PlVec119(v); return(true);
      case 115: PlVec120(v); return(true);
      case 116: PlVec121(v); return(true);
      case 117: PlVec122(v); return(true);
      case 118: PlVec123(v); return(true);
      case 119: PlVec124(v); return(true);
      case 120: PlVec125(v); return(true);
      case 121: PlVec127(v); return(true);
      case 122: PlVec128(v); return(true);
      case 123: PlVec129(v); return(true);
      case 124: PlVec130(v); return(true);
      case 125: PlVec131(v); return(true);
      case 126: PlVec132(v); return(true);
      case 127: PlVec133(v); return(true);
      case 128: PlVec134(v); return(true);
      case 129: PlVec135(v); return(true);
      case 130: PlVec136(v); return(true);
      case 131: PlVec137(v); return(true);
      case 132: PlVec138(v); return(true);
      case 133: PlVec139(v); return(true);
      case 134: PlVec140(v); return(true);
      case 135: PlVec141(v); return(true);
      case 136: PlVec142(v); return(true);
      case 137: PlVec143(v); return(true);
      case 138: PlVec144(v); return(true);
      case 139: PlVec145(v); return(true);
      case 140: PlVec146(v); return(true);
      case 141: PlVec147(v); return(true);
      case 142: PlVec148(v); return(true);
      case 143: PlVec149(v); return(true);
      case 144: PlVec150(v); return(true);
      case 145: PlVec151(v); return(true);
      case 146: PlVec152(v); return(true);
      case 147: PlVec153(v); return(true);
      case 148: PlVec154(v); return(true);
      case 149: PlVec156(v); return(true);
      case 150: PlVec157(v); return(true);
      case 151: PlVec158(v); return(true);
      case 152: PlVec159(v); return(true);
      case 153: PlVec160(v); return(true);
      case 154: PlVec161(v); return(true);
      case 155: PlVec162(v); return(true);
      case 156: PlVec163(v); return(true);
      case 157: PlVec164(v); return(true);
     }
   return(false);
  }
#endif
