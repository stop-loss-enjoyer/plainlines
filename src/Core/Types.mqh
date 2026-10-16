// Required Notice: Copyright 2026 stop-loss-enjoyer
// Plainlines is source-available under the PolyForm Shield License 1.0.0.
//
// Shared types of the calculation core. The core never calls the terminal: every number it
// needs arrives in these structs, filled by src/Terminal/ (or by a test vector). Anything the
// terminal must compute (OrderCalcProfit, OrderCalcMargin, conversion rates, ATR) arrives as a
// precomputed field with a validity flag.
#property strict

#ifndef PL_CORE_TYPES_MQH
#define PL_CORE_TYPES_MQH

#define PL_EPS        1e-8
#define PL_MAX_TP     3      // take profit levels (multiple TP, partial close)
#define PL_MAX_PARTS  10     // orders one trade may go out as (split above the broker max lot, several TPs)

//--- what to do with a lot above the broker max lot (menu: Above broker max lot)
enum PlOverMax
  {
   PL_OVER_BLOCK=0,
   PL_OVER_TRIM=1,
   PL_OVER_SPLIT=2
  };

//--- what the user picked on the panel
enum PlKind
  {
   PL_KIND_MARKET=0,
   PL_KIND_LIMIT=1,
   PL_KIND_STOP=2,
   PL_KIND_STOP_LIMIT=3
  };

enum PlSide { PL_SIDE_NONE=0, PL_SIDE_BUY=1, PL_SIDE_SELL=2 };

enum PlRiskMode
  {
   PL_RISK_PERCENT=0,   // risk = base * percent
   PL_RISK_MONEY=1      // risk = fixed money in account currency
  };

enum PlRiskBase { PL_BASE_BALANCE=0, PL_BASE_EQUITY=1 };

enum PlTpMode { PL_TP_R=0, PL_TP_PRICE=1 };

enum PlCommKind
  {
   PL_COMM_UNKNOWN=0,        // no rate set and no hint: status "commission not counted"
   PL_COMM_LOT_SIDE=1,       // money per lot per side (FTMO forex $2.50)
   PL_COMM_LOT_ROUND=2,      // money per lot per round turn (Bybit $6), split in half in and out
   PL_COMM_PERCENT_SIDE=3    // percent of notional per side (FTMO crypto 0.0325)
  };

enum PlCommSource { PL_COMMSRC_NONE=0, PL_COMMSRC_USER=1, PL_COMMSRC_HINT=2,
                      PL_COMMSRC_BROKER=3 };   // BROKER: the broker's rule, never written to the draft (the load clamps comm_src to 0..2, so a stray 3 would read as HINT)

//--- verdict: OK sends, WARN sends with the phrase shown, CONFIRM needs the extra confirmation,
//--- BLOCK never sends. The panel shows numbers in every verdict where they exist.
enum PlVerdict { PL_OK=0, PL_WARN=1, PL_CONFIRM=2, PL_BLOCK=3 };

//--- one reason per result; the phrase text lives in Core/Reasons.mqh (PlReasonText)
enum PlReason
  {
   PL_R_NONE=0,
   PL_R_NO_QUOTE,            // bid or ask is zero
   PL_R_NO_SYMBOL_DATA,      // tick size, tick value or contract size is zero
   PL_R_NO_CONVERSION,       // percent commission needs a rate and the calc mode gives none
   PL_R_STALE_QUOTE,         // last tick too old (WARN in an open session, BLOCK when closed)
   PL_R_MARKET_CLOSED,       // session closed: numbers shown, sending blocked
   PL_R_SL_WRONG_SIDE,       // SL on the wrong side of the execution price for the chosen kind
   PL_R_SL_TOO_CLOSE,        // distance below max(StopsLevel, 2 spreads, N ticks)
   PL_R_TP_WRONG_SIDE,
   PL_R_TP_TOO_CLOSE,
   PL_R_ENTRY_WRONG_SIDE,    // Limit/Stop entry on the wrong side of the market for the side
   PL_R_LIMIT_WRONG_SIDE,    // Stop-Limit: limit price on the wrong side of the trigger
   PL_R_KIND_NOT_ALLOWED,    // SYMBOL_ORDER_MODE does not allow this kind
   PL_R_LOT_BELOW_MIN,       // CONFIRM with an SL; BLOCK without an SL
   PL_R_LOT_ABOVE_MAX,       // BLOCK unless Trim is on (WARN) or Split works
   PL_R_RISK_ABOVE_CAP,      // hard cap, nothing overrides it
   PL_R_RISK_HIGH,           // CONFIRM: above 2 percent
   PL_R_PATHS_DISAGREE,      // tick value and OrderCalcProfit differ beyond the tolerance
   PL_R_MARGIN,              // not enough free margin for the lot
   PL_R_STOPOUT_BEFORE_SL,   // margin level at SL below stop-out: "max X lots"
   PL_R_SPREAD_WIDE,         // spread above the max share of the SL distance
   PL_R_COMM_UNKNOWN,        // WARN: commission not counted
   PL_R_CROSS_RATE_AT_SL,    // note: forex cross, the account currency is neither base nor profit
   PL_R_NO_SL,               // CONFIRM: trade without SL, risk undefined (opt-in in the menu)
   PL_R_TRADE_DISABLED,      // terminal / program / account trading off, investor password
   PL_R_NOT_DEMO,            // demo or dev build: sending only on a demo account
   PL_R_DISCONNECTED,
   PL_R_VOLUME_LIMIT,        // SYMBOL_VOLUME_LIMIT with open positions and orders
   PL_R_BAD_INPUT,           // a field holds something that is not a number
   //--- the trading layer (appended: the order inside a verdict class is the order of this list)
   PL_R_ALGO_OFF,            // Algo Trading is off in the terminal toolbar
   PL_R_EA_NOT_ALLOWED,      // the program may not trade (properties, Common tab)
   PL_R_INVESTOR,            // read-only login
   PL_R_BROKER_NO_EA,        // the broker does not allow Expert Advisors on this account
   PL_R_SYMBOL_CLOSE_ONLY,
   PL_R_SYMBOL_LONG_ONLY,
   PL_R_SYMBOL_SHORT_ONLY,
   PL_R_ENTRY_TOO_CLOSE,     // pending entry closer to the price than StopsLevel
   PL_R_NETTING_REVERSE,     // netting account: the order would close or reverse the open position
   PL_R_NETTING_ADD,         // CONFIRM: netting account, the order adds to the open position
   PL_R_GUARD,               // account limit (fallback text; the phrase comes from the guard)
   PL_R_SPLIT_ORDERS,        // CONFIRM: the lot goes out in several orders (above the broker max lot, Split)
   PL_R_SPLIT_TOO_MANY,      // BLOCK: Split would need more than PL_MAX_PARTS orders
   PL_R_SPLIT_NETTING,       // BLOCK: Split is not allowed on a netting account
   PL_R_NO_CALC,             // BLOCK: the terminal gave no OrderCalcProfit for the SL (path c), retried every recalc
   PL_R_CALC_MODE,           // BLOCK: bond or collateral calc mode, profit formula not supported
   PL_R_LOT_GRID,            // BLOCK: vol_min or vol_max is not on the vol_step grid
   PL_R_NO_FILL_MODE,        // BLOCK: a market order has neither FOK nor IOC in the symbol fill mask
   PL_R_ORDERS_DAILY,        // BLOCK: the broker deletes SL and TP at the end of each day (SYMBOL_ORDERS_DAILY)
   //--- netting group (appended: the numbering above is kept); all BLOCK
   PL_R_NETTING_ORDER_OPEN,  // netting: a pending order is already open on this symbol
   PL_R_NETTING_PENDING,     // netting: no pending order while a position is open here
   PL_R_NETTING_NO_SL,       // netting: adding to the open position needs an SL
   PL_R_NETTING_TPS,         // netting: one TP when adding to the open position
   PL_R_NETTING_NO_ROOM,     // netting: the open position already uses the risk at this SL
   PL_R_NETTING_NO_VALUE,    // netting: the terminal gave no value of the open position at this SL
   PL_R_NETTING_TP_PARTS,    // netting: a TP share is below the minimum lot
   PL_R_ATR_NOT_READY,       // BLOCK: ATR stop is on but the indicator value or multiplier is not usable
   //--- appended 16.10.2026: the numbering above is kept; BLOCK
   PL_R_SIDE_CROSSED,        // the price went through the SL line of a Market draft: the side is no longer the one the trader set
   //--- appended 16.10.2026; BLOCK
   PL_R_OTHER_PLAINLINES     // the other Plainlines (free or Pro) is on a chart of this terminal: one Plainlines per terminal
  };

//--- symbol data, filled by Terminal/Market.mqh from SymbolInfo*, SymbolInfoTick, OrderCalc*
struct PlSymbol
  {
   string            name;
   string            base;           // SYMBOL_CURRENCY_BASE
   string            profit;         // SYMBOL_CURRENCY_PROFIT
   string            margin;         // SYMBOL_CURRENCY_MARGIN
   int               calc_mode;      // ENUM_SYMBOL_CALC_MODE
   int               digits;
   double            point;
   double            tick_size;      // SYMBOL_TRADE_TICK_SIZE: the unit of every price
   double            tick_value_loss;   // SYMBOL_TRADE_TICK_VALUE_LOSS, account currency, current rate
   double            tick_value_profit; // SYMBOL_TRADE_TICK_VALUE_PROFIT
   double            contract;       // SYMBOL_TRADE_CONTRACT_SIZE
   double            vol_min;
   double            vol_max;
   double            vol_step;
   double            vol_limit;      // 0 = no limit
   double            vol_open_buy;   // buy volume already open plus pending (buy limit/stop) on this symbol (for vol_limit)
   double            vol_open_sell;  // the same for the sell side: SYMBOL_VOLUME_LIMIT is per direction
   int               stops_level;    // points
   int               freeze_level;   // points
   int               order_mode;     // SYMBOL_ORDER_MODE mask
   int               filling_mode;   // SYMBOL_FILLING_MODE mask
   int               exec_mode;      // SYMBOL_TRADE_EXEMODE
   int               sym_trade_mode; // SYMBOL_TRADE_MODE
   int               expiration_mode;
   int               gtc_mode;       // SYMBOL_ORDER_GTC_MODE
   double            bid;
   double            ask;
   datetime          tick_time;      // SYMBOL_TIME of the last tick (server time)
   datetime          server_now;     // TimeTradeServer() when the struct was filled
   bool              session_open;   // inside a trade session now (SymbolInfoSessionTrade)
   //--- swaps, shown in "Costs" only
   int               swap_mode;
   double            swap_long;
   double            swap_short;
   int               swap_3day;      // ENUM_DAY_OF_WEEK
   //--- margin for 1 lot from OrderCalcMargin: at the plan's execution price after PlFillTerminalCalcs, at Ask/Bid before (0 when unavailable)
   double            margin_buy_1lot;
   double            margin_sell_1lot;
   //--- netting: the one position of this symbol and the pending orders on it (Terminal/Market.mqh PlReadNetting; 0 on hedging)
   double            net_vol;        // volume of the open position on this symbol (0: none, or hedging)
   bool              net_buy;        // its side
   double            net_open;       // POSITION_PRICE_OPEN (averaged on netting)
   double            net_sl;         // POSITION_SL, 0 none
   int               net_orders;     // netting: pending orders open on this symbol (any magic)
  };

struct PlAccount
  {
   string            currency;
   int               currency_digits; // ACCOUNT_CURRENCY_DIGITS (JPY 0)
   double            balance;
   double            equity;
   double            margin;
   double            margin_free;
   int               so_mode;         // ACCOUNT_MARGIN_SO_MODE
   double            so_call;
   double            so_so;
   long              leverage;
   int               trade_mode;      // ACCOUNT_TRADE_MODE (DEMO 0)
   int               margin_mode;     // ACCOUNT_MARGIN_MODE (hedging or netting)
   bool              trade_ok;        // terminal, program and account allow trading, not investor
   bool              term_trade;      // TERMINAL_TRADE_ALLOWED (Algo Trading button)
   bool              mql_trade;       // MQL_TRADE_ALLOWED (the program's own permission)
   bool              acct_trade;      // ACCOUNT_TRADE_ALLOWED (false: investor password)
   bool              acct_expert;     // ACCOUNT_TRADE_EXPERT (false: the broker bans Expert Advisors)
   int               open_no_sl;      // positions and orders without SL (filled by the guards)
   bool              connected;       // TERMINAL_CONNECTED
   //--- for "subtract open positions / pending" and portfolio risk (the terminal layer fills these)
   double            open_risk_money; // sum of money at risk of open positions with SL
   double            pending_risk_money;
  };

//--- commission setting for the current symbol
struct PlCommission
  {
   PlCommKind        kind;
   double            rate;            // money per lot (side or round) or percent per side
   PlCommSource      source;
   double            min_money;       // broker minimum: account money per order for the whole round (0: none); only the broker's rule sets it
  };

//--- one take profit level; share is the part of the lot closed there (sums to 100)
struct PlTpLevel
  {
   bool              on;
   PlTpMode          mode;
   double            r;               // multiple of the SL distance when mode is PL_TP_R
   double            price;           // when mode is PL_TP_PRICE
   double            share;           // percent of the lot
  };

//--- everything the user set on the panel and in the menu that the calculation needs
struct PlInputs
  {
   PlKind            kind;
   double            entry;           // pending: the line; market: ignored (Ask or Bid is used)
   double            limit;           // Stop-Limit only: execution (limit) price; entry is the trigger
   double            sl;              // price of the SL line; 0 with no_sl
   bool              no_sl;           // opt-in in the menu, risk undefined, lot by hand
   PlTpLevel         tp[PL_MAX_TP];   // tp[0] is the main TP line; [1],[2] only with multi TP on
   bool              no_tp;
   PlRiskMode        risk_mode;
   double            risk_percent;    // e.g. 1.0
   double            risk_money;      // account currency
   double            lot_fixed;       // the lot of a trade without an SL (typed by the trader; the risk mode does not matter then)
   PlRiskBase        base;
   bool              subtract_open;   // Subtract OPV/POV: base minus risk of open positions / pending
   double            cap_percent;     // hard cap, default 5
   double            confirm_above;   // 2.0: CONFIRM above this
   PlOverMax         over_max;        // lot above SYMBOL_VOLUME_MAX: block, trim to it, or split into equal orders
   double            max_spread_share;// max spread as a share of the SL distance, 0 = default
   PlCommission      comm;
   int               n_orders;        // orders the press would put on the account (0 or 1: one); each of them pays the minimum commission
   //--- ATR stop: SL distance = atr * atr_mult from the execution price (atr from the terminal)
   bool              atr_on;
   double            atr;             // value of iATR on the chart timeframe, price units
   double            atr_mult;
   //--- precomputed by the terminal for the normalized plan (two-step call)
   bool              calcprofit_ok;
   double            calcprofit_loss_1lot; // OrderCalcProfit for 1 lot from exec price to SL, positive money
   bool              net_calc_ok;     // the two values below were given by the terminal
   double            net_loss_new;    // -OrderCalcProfit(side, net_vol, net_open -> plan SL); signed, + is a loss
   double            net_loss_old;    // -OrderCalcProfit(side, net_vol, net_open -> net_sl); 0 when net_sl==0
  };

//--- step 1 result: normalized prices and the order the plan stands for
struct PlPlan
  {
   bool              ok;
   PlReason          reason;
   PlSide            side;
   int               order_type;      // ENUM_ORDER_TYPE that will be sent
   double            entry;           // normalized; market: Ask for buy, Bid for sell
   double            exec;            // price the position opens at: market Ask/Bid, Limit/Stop entry, Stop-Limit limit
   double            sl;
   double            tp[PL_MAX_TP];
   double            limit;
   double            dist;            // |exec - sl| in price, spread included for market
   long              ticks;           // MathRound(dist / tick_size)
  };

//--- step 2 result: every number the panel shows
struct PlResult
  {
   PlVerdict         verdict;
   PlReason          reason;          // the one that decides the verdict
   PlReason          note;            // a secondary WARN (commission not counted, cross rate at SL)
   //--- loss per lot, account currency
   double            lpl_a;           // path (a): tick value, SL-rate corrected when the base currency is the account currency
   double            lpl_c;           // path (c): OrderCalcProfit
   double            lpl_price;       // max(a, c)
   double            comm_in_1lot;    // commission per lot, entry side
   double            comm_out_1lot;   // commission per lot, exit at SL
   double            loss_per_lot;    // lpl_price + comm_in + comm_out
   //--- lot and risk
   double            risk_target;     // money the user asked for (after the base and cap)
   double            lot_raw;
   double            lot;             // after step and min/max; 0 when it cannot be computed (the whole lot, also when split)
   int               split_n;         // Split above the broker max: number of orders (>= 2), else 0
   int               split_need;      // orders Split would need (also when more than PL_MAX_PARTS)
   double            split_lot[PL_MAX_PARTS]; // lot of each order, sums to lot; first orders get the remainder
   double            risk_money;      // lot * loss_per_lot (+ net_risk on a netting add: the whole position at the new SL)
   double            net_risk;        // loss of the already open volume at the new SL, its exit commission included, never below 0; part of risk_money
   double            risk_add;        // what this trade adds to the loss if every SL is hit (the new_risk of the guards); equals risk_money except for a netting add
   double            risk_percent;    // of the base
   //--- reward
   double            reward[PL_MAX_TP];  // money at each TP for its share, commission subtracted
   double            reward_total;
   double            rr;              // reward_total / risk_money
   //--- costs (shown in "Costs", never on the lot except the commission)
   double            spread_points;
   double            spread_money;    // spread for this lot, account currency
   double            comm_money;      // in + out for this lot, topped up to the broker minimum of every order
   bool              comm_min_on;     // the broker minimum, not the rate, sets comm_money
   double            swap_long_night; // money per night for this lot
   double            swap_short_night;
   bool              swap_ok;         // false: the swap mode or its currency cannot be worked out, the panel shows n/a
   double            margin_needed;   // for this lot
  };

//--- what the guards say about a new entry; a caller without guards passes a neutral one
struct PlGuard
  {
   PlVerdict         verdict;
   PlReason          reason;
   int               why;
   double            max_new_risk;     // < 0: no limit
   //--- what is left under each limit (< 0: not set), so that the send can name the one that stopped it
   double            room_port;        // portfolio cap: money of new risk that still fits
   double            port_used;        // risk already open and pending, money
   double            port_cap_pct;     // portfolio cap, percent of the balance (0 off)
   double            balance;
   string            text;             // the phrase of a BLOCK from the guards
  };

#endif
