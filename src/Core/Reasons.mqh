// Required Notice: Copyright 2026 stop-loss-enjoyer
// Plainlines is source-available under the PolyForm Shield License 1.0.0.
//
// One English phrase per PlReason. All panel texts live in src/UI/Strings.mqh too; this is the
// core's own short wording, used by tests and by the status line.
#property strict

#ifndef PL_CORE_REASONS_MQH
#define PL_CORE_REASONS_MQH

#include "Types.mqh"

//--- the stale quote phrase names how long the symbol was allowed to be quiet: 1 min, 5 min
string PlStaleText(const int seconds)
  {
   return "No new quote for "+IntegerToString((seconds+30)/60)+" min, waiting for a tick";
  }

string PlReasonText(const PlReason r)
  {
   switch(r)
     {
      case PL_R_NONE:               return "";
      case PL_R_NO_QUOTE:           return "No quote for this symbol";
      case PL_R_NO_SYMBOL_DATA:     return "Symbol data missing";
      case PL_R_NO_CONVERSION:      return "No rate to the account currency for this commission";
      case PL_R_STALE_QUOTE:        return "No new quote, waiting for a tick";     // without a symbol; PlStaleText names the time
      case PL_R_MARKET_CLOSED:      return "Market closed, numbers are from the last quote";
      case PL_R_SL_WRONG_SIDE:      return "SL sits on the price";
      case PL_R_SL_TOO_CLOSE:       return "SL is too close to the price";
      case PL_R_TP_WRONG_SIDE:      return "TP is on the wrong side";
      case PL_R_TP_TOO_CLOSE:       return "TP is too close to the price";
      case PL_R_ENTRY_WRONG_SIDE:   return "Entry is on the wrong side of the market";
      case PL_R_LIMIT_WRONG_SIDE:   return "Limit is on the wrong side of the trigger";
      case PL_R_KIND_NOT_ALLOWED:   return "Broker does not allow this order type";
      case PL_R_LOT_BELOW_MIN:      return "Lot below minimum, risk is higher";
      case PL_R_LOT_ABOVE_MAX:      return "Lot above the broker maximum";
      case PL_R_RISK_ABOVE_CAP:     return "Risk above the hard cap";
      case PL_R_RISK_HIGH:          return "High risk: confirm";
      case PL_R_PATHS_DISAGREE:     return "Tick value and terminal loss disagree";
      case PL_R_MARGIN:             return "Not enough free margin";
      case PL_R_STOPOUT_BEFORE_SL:  return "Stop-out comes before the SL";
      case PL_R_SPREAD_WIDE:        return "Spread is wide for this SL";
      case PL_R_COMM_UNKNOWN:       return "Commission not counted";
      case PL_R_CROSS_RATE_AT_SL:   return "Cross pair: risk depends on the rate at SL";
      case PL_R_NO_SL:              return "No SL: risk undefined";
      case PL_R_TRADE_DISABLED:     return "Trading is disabled for this symbol";
      case PL_R_NOT_DEMO:           return "Demo build: demo accounts only";
      case PL_R_DISCONNECTED:       return "No connection to the server";
      case PL_R_VOLUME_LIMIT:       return "Symbol volume limit reached";
      case PL_R_BAD_INPUT:          return "A field holds something that is not a number";
      case PL_R_ALGO_OFF:           return "Turn on Algo Trading in the terminal toolbar";
      case PL_R_EA_NOT_ALLOWED:     return "Allow Algo Trading in the Plainlines properties";
      case PL_R_INVESTOR:           return "This login is read-only (investor password)";
      case PL_R_BROKER_NO_EA:       return "The broker does not allow Expert Advisors here";
      case PL_R_SYMBOL_CLOSE_ONLY:  return "This symbol is close-only now";
      case PL_R_SYMBOL_LONG_ONLY:   return "This symbol allows buys only";
      case PL_R_SYMBOL_SHORT_ONLY:  return "This symbol allows sells only";
      case PL_R_ENTRY_TOO_CLOSE:    return "Entry is too close to the price for this broker";
      case PL_R_NETTING_REVERSE:    return "Netting account: this would close or reverse the open position";
      case PL_R_NETTING_ADD:        return "Netting account: adds to the open position, SL, TP and risk are for all of it";
      case PL_R_GUARD:              return "Account limit";
      case PL_R_SPLIT_ORDERS:       return "The lot goes out in several orders";
      case PL_R_SPLIT_TOO_MANY:     return "Split would need too many orders";
      case PL_R_SPLIT_NETTING:      return "Split needs a hedging account";
      case PL_R_NO_CALC:            return "Terminal gives no loss for this SL yet";
      case PL_R_CALC_MODE:          return "This instrument type is not supported";
      case PL_R_LOT_GRID:           return "Broker lot step does not fit its min or max lot";
      case PL_R_NO_FILL_MODE:       return "This symbol allows no fill type for market orders";
      case PL_R_ORDERS_DAILY:       return "Broker deletes SL and TP at the end of each day: not supported";
      case PL_R_NETTING_ORDER_OPEN: return "Netting account: a pending order is already open on this symbol";
      case PL_R_NETTING_PENDING:    return "Netting account: no pending order while a position is open here";
      case PL_R_NETTING_NO_SL:      return "Netting account: adding to the open position needs an SL";
      case PL_R_NETTING_TPS:        return "Netting account: one TP when adding to the open position";
      case PL_R_NETTING_NO_ROOM:    return "Netting account: the open position already uses the risk at this SL";
      case PL_R_NETTING_NO_VALUE:   return "Netting account: cannot value the open position at this SL";
      case PL_R_ATR_NOT_READY:      return "ATR is not ready yet";
      case PL_R_SIDE_CROSSED:       return "Price crossed the SL line: move it";
      case PL_R_NETTING_TP_PARTS:   return "Netting account: a TP share is below the minimum lot, use fewer TPs";
      case PL_R_OTHER_PLAINLINES:   return "Remove Plainlines Pro first: one Plainlines per terminal";
     }
   return "";
  }

#endif
