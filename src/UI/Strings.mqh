// Required Notice: Copyright 2026 stop-loss-enjoyer
// Plainlines is source-available under the PolyForm Shield License 1.0.0.
//
// Every text the panel shows lives here (English; one place to change the language).
// Reasons from the core come from PlReasonText, not from this file.
#property strict

#ifndef PL_UI_STRINGS_MQH
#define PL_UI_STRINGS_MQH


#define PLS_BRAND            "plainlines"
#define PLS_READY            "Ready to trade"
#define PLS_MARKET_CLOSED_SHORT "Market closed, last quote shown"
#define PLS_EA_NOT_ALLOWED_SHORT "Tick Allow Algo Trading (F7 on chart)"
#define PLS_MARKET_CLOSED_CARD  "Market closed"                    // the short forms for the quick card and the status row, see PlAltOfPhrase
#define PLS_EA_NOT_ALLOWED_CARD "Allow Algo Trading: F7"
#define PLS_BLOCKED          "Blocked"
#define PLS_KIND_MARKET      "Market"
#define PLS_KIND_LIMIT       "Limit"
#define PLS_KIND_STOP        "Stop"
#define PLS_KIND_STOPLIMIT   "Stop-Limit"
#define PLS_KIND_STOPLIMIT_SHORT "S-Limit"
#define PLS_SPREAD           "spread"
#define PLS_COSTS            "Costs"
#define PLS_RISK             "Risk"
#define PLS_LOT              "Lot"
#define PLS_ENTRY            "Entry"
#define PLS_LIMIT            "Limit"
#define PLS_SL               "SL"
#define PLS_TP               "TP"
#define PLS_R                "R"
#define PLS_REWARD           "Reward"
#define PLS_RISK_POSITION    "Risk, position"   // a netting add: the whole position at the new SL
#define PLS_REWARD_ADD       "Reward, add"      // and the reward of the added lot only
#define PLS_ASK              "Ask"
#define PLS_BID              "Bid"
#define PLS_PIP              "pip"
#define PLS_PT               "pt"
#define PLS_CANCEL           "Cancel"
#define PLS_USE              "use"
#define PLS_SET_SL           "Move the SL line to pick a side"
#define PLS_SET_SL_CARD      "Move the SL line"
#define PLS_BAD_NUMBER       "Not a number in"

//--- costs block
#define PLS_C_SPREAD         "Spread"
#define PLS_C_COMM           "Commission"
#define PLS_C_SWAP           "Swap"
#define PLS_C_SRC_USER       "your rate"
#define PLS_C_SRC_DEALS      "last deals"
#define PLS_C_SET_IN_MENU    "set in menu"
#define PLS_X3_ON            "x3 on "
#define PLS_SWAP_SP          "Swap "
#define PLS_PER_NIGHT        "/night"
#define PLS_X3_SP            " x3 "
#define PLS_C_KIND           "Kind"
#define PLS_C_RATE           "Rate"
#define PLS_C_SET_BY_BROKER  "Set by the broker, counted in the lot."
#define PLS_C_NOTE_NO_RULE   "Counted in the lot. None means it is not counted."
#define PLS_C_NOT_COUNTED    "not counted"
#define PLS_C_HINT           "last deal on"
#define PLS_C_BROKER         "broker rate"
#define PLS_C_BROKER_SHORT   "broker"
#define PLS_C_BROKER_NONE    "broker, none"
#define PLS_C_MIN            "min"

//--- menu sections
#define PLS_M_TRADE          "Trade"
#define PLS_M_COMMISSION     "Commission"
#define PLS_M_CONFIRM        "Confirm"
#define PLS_M_POSITION       "Position"
#define PLS_M_LIMITS         "Limits"
#define PLS_M_ADVANCED       "Advanced"
#define PLS_M_LOOK           "Look"
#define PLS_M_RESET          "Reset to defaults"
#define PLS_DANGER           "risky"

//--- menu section state, grey at the right of a section title
#define PLS_SUB_ABOVE   "above "
#define PLS_SUB_TP           "TP"
#define PLS_SUB_TPS          "TPs"
#define PLS_SUB_SET          "set"
#define PLS_SUB_SUB_OPEN     "Sub open"
#define PLS_SUB_RARELY       "rarely needed"
#define PLS_SUB_ATR          "ATR "
#define PLS_SUB_GTC          "GTC"
#define PLS_SUB_TODAY        "Today"
#define PLS_SUB_HOURS        " h"
#define PLS_SUB_BROKER       "broker"
#define PLS_SUB_PER_LOT      " / lot"
#define PLS_SUB_NOT_COUNTED  "not counted"
#define PLS_SUB_ON           "on"
#define PLS_SUB_OFF          "off"
#define PLS_SUB_BE           "BE "
#define PLS_SUB_TRAIL        "trail"
#define PLS_SUB_CHANGED      "changed"


//--- trading: confirmation and send results
#define PLS_CONFIRM          "CONFIRM"
#define PLS_SENDING          "Sending the order..."
#define PLS_CONFIRM_TIMEOUT  "Confirmation timed out"
#define PLS_PRICE_MOVED      "Price moved: confirm again"
#define PLS_POS_CHANGED      "Position changed: press again"
#define PLS_CONFIRM_AGAIN    "Plan changed: confirm again"
#define PLS_CANCELLED        "Cancelled"
#define PLS_BUSY             "Another order is still being handled"

//--- positions block and management
#define PLS_POSITIONS        "Positions"
#define PLS_POS_WORD         "pos"
#define PLS_ORDER_ONE        "order"
#define PLS_ORDER_MANY       "orders"
#define PLS_RISK_WORD        "risk"
#define PLS_MORE             "more"
#define PLS_NO_SL_ROW        "no SL"
#define PLS_BE_NOW           "BE now"
#define PLS_BE               "BE"
#define PLS_BE_DONE          "BE done"
#define PLS_TRAIL            "Trail"
#define PLS_SURE             "Sure?"
#define PLS_CLOSE_WORD       "Close"
#define PLS_CLOSE_ALL        "Close all"
#define PLS_PARTS_WORD       "parts"
#define PLS_EXPIRING         "expiring"
#define PLS_BUY_WORD         "BUY"
#define PLS_SELL_WORD        "SELL"
#define PLS_LIMIT_WORD       "LIMIT"
#define PLS_LIMIT_SP         "limit "
#define PLS_STOP_WORD        "STOP"
#define PLS_STOP_LIMIT_WORD  "STOP LIMIT"
#define PLS_ORDER_EXPIRED    "Pending order expired and was deleted"
#define PLS_BE_SL_TO         "BE: SL to "
#define PLS_TRAIL_SL_TO      "Trail: SL to "
#define PLS_NOT_PAST_BE      "Price is not past breakeven yet"
#define PLS_ALREADY_BE       "SL is already at breakeven or better"
#define PLS_NOTHING_CLOSE    "Nothing to close"
#define PLS_PART_BELOW_MIN   "Part is below the minimum lot"
#define PLS_OPEN_RISK        "Open risk"
#define PLS_WITH_TRADE       "with this trade"
#define PLS_MARGIN_USED      "Margin used"
#define PLS_AFTER_TRADE      "after this trade"
#define PLS_CLOSED_WORD      "Closed"
#define PLS_OF               "of"
#define PLS_PNL              "P&L"
#define PLS_SLTP_CHANGED     "SL and TP changed"
#define PLS_POS_CLOSED       "Position closed"
#define PLS_ORDER_DELETED    "Order deleted"
#define PLS_ORDER_GONE       "Order is already gone"
#define PLS_ACCT_CHANGED     "Account changed: its own risk and cap are used"
#define PLS_ORDERS           "orders"
#define PLS_CHECKING         "No answer from the server: checking the last order"
#define PLS_WAIT_CONN        "No connection: waiting to check the last order"
#define PLS_NO_SL_OPENED     "Opened WITHOUT SL: set it now"
#define PLS_EXP_DAY_ONLY     "Broker keeps pending orders for the day only"
#define PLS_EXP_KEPT         "Expiry is kept by Plainlines while the terminal runs"
#define PLS_NO_FILL_MODE     "No fill mode accepted"

//--- the guards: portfolio, margin, trades
#define PLS_LIM_NO_HISTORY   "Waiting for account history to match the balance"
#define PLS_LIM_HIST_DIFF    ": history differs from the balance by "
#define PLS_LIM_PORT_UNKNOWN "Total risk unknown: a position has no SL"
#define PLS_LIM_WOULD_MAKE   "Would make "
#define PLS_LIM_OPEN_LIMIT   " open, limit "
#define PLS_LIM_ENTRIES_LIMIT " entries today, limit "
#define PLS_RISK_UNKNOWN     "Open risk unknown on "
#define PLS_PROF_BAD         "Account file damaged: set the limits again"
#define PLS_PROF_NO_ID       "No deposit in history: limits cannot be saved"
#define PLS_PROF_OFF         "New account: Max total risk is off, set it in the menu"
#define PLS_SETTINGS_BAD     "Settings file damaged: defaults in use"
#define PLS_SETTINGS_NOT_SAVED "Settings not saved: write failed"   // settings.dat could not be written three laps in a row; trading goes on
#define PLS_LIM_NOT_SUB      "Open position without SL is not subtracted"

//--- server answer (TRADE_RETCODE_*) to one English phrase
string PlRetcodeText(const uint rc,const int err=0)
  {
   if(rc==0 && err==4752) return "Turn on Algo Trading in the terminal toolbar";
   switch(rc)
     {
      case 10004: return "Requote: not sent, press again";
      case 10006: return "Rejected by the broker";
      case 10007: return "Cancelled";
      case 10013: return "Invalid request";
      case 10014: return "Lot not accepted by the broker";
      case 10015: return "Price not accepted";
      case 10016: return "SL or TP too close or on the wrong side";
      case 10017: return "Trading is disabled for this symbol";
      case 10018: return "Market is closed";
      case 10019: return "Not enough money";
      case 10020: return "Price changed: not sent";
      case 10021: return "No quotes to fill the order";
      case 10022: return "Expiry not accepted";
      case 10024: return "Too many requests: wait a moment";
      case 10026: return "The server disabled Expert Advisors";
      case 10027: return "Turn on Algo Trading in the terminal toolbar";
      case 10028: return "Order is being processed";
      case 10029: return "Too close to the price to change (freeze level)";
      case 10030: return PLS_NO_FILL_MODE;
      case 10033: return "Pending orders limit reached";
      case 10034: return "Symbol volume limit reached";
      case 10036: return "Position is already closed";
      case 10038: return "Close volume is larger than the position";
      case 10040: return "Positions limit reached";
      case 10042: return "This symbol allows buys only";
      case 10043: return "This symbol allows sells only";
      case 10044: return "Close-only";
      case 10045: return "FIFO rule: close the oldest position first";
      case 10046: return "Hedging is not allowed on this account";
     }
   //--- below 100xx (seen once on demo FTMO: OrderCheck rc 2 right after a terminal restart)
   if(rc>0 && rc<10000) return "Check failed (code "+(string)rc+", error "+(string)err+"): try again";
   return "Server answer "+(string)rc;
  }

//--- the separator of the result phrases of a trade: " · " (the middle dot, the same as in the menu states)
string PlDotSep() { return " "+ShortToString(0xB7)+" "; }

string PlKindName(const int k)
  {
   switch(k)
     {
      case PL_KIND_MARKET:     return PLS_KIND_MARKET;
      case PL_KIND_LIMIT:      return PLS_KIND_LIMIT;
      case PL_KIND_STOP:       return PLS_KIND_STOP;
      case PL_KIND_STOP_LIMIT: return PLS_KIND_STOPLIMIT;
     }
   return "";
  }

string PlDayName(const int d)
  {
   switch(d)
     {
      case 0: return "Sun"; case 1: return "Mon"; case 2: return "Tue"; case 3: return "Wed";
      case 4: return "Thu"; case 5: return "Fri"; case 6: return "Sat";
     }
   return "";
  }

//--- 1234567.891 -> "1,234,567.89"
string PlThousands(const double v,const int digits)
  {
   string s=DoubleToString(MathAbs(v),digits);
   int dot=StringFind(s,".");
   string ip=(dot>=0)?StringSubstr(s,0,dot):s;
   string fp=(dot>=0)?StringSubstr(s,dot):"";
   string out="";
   int n=StringLen(ip);
   for(int i=0;i<n;i++)
     {
      out+=StringSubstr(ip,i,1);
      int left=n-1-i;
      if(left>0 && left%3==0) out+=",";
     }
   return out+fp;
  }

#define PLS_FIX_RED_FIELD                "Fix the red field first"
#define PLS_FINISH_FIELD                 "Press Enter in the field first"
#define PLS_SL_FOLLOWS_ATR               "SL follows the ATR stop"
#define PLS_PCT_TINY                     "<0.01%"
#define PLS_UNDEFINED                    "undefined"
#define PLS_UNKNOWN_WORD                 "unknown"
#define PLS_NO_SL_SIDE                   "No SL: set a TP price to pick a side"
#define PLS_NO_SL_SIDE_CARD              "No SL: set a TP price"
#define PLS_CAP_NEW_NO_SL                "Max total risk is set: a trade needs an SL"

#ifdef PL_DEV_LOG
string g_dev_cur_show="";      // dev only: show another currency code on the panel (display only)
#endif

string PlCurrencySign(const string cur_in)
  {
   string cur=cur_in;
#ifdef PL_DEV_LOG
   if(g_dev_cur_show!="") cur=g_dev_cur_show;
#endif
   if(cur=="USD") return "$";
   if(cur=="EUR") return ShortToString(0x20AC);
   if(cur=="GBP") return ShortToString(0xA3);
   return cur+" ";
  }

//--- the mark of the account currency for a narrow place: the sign of exactly USD, EUR, GBP, else the broker code as is
string PlCurrencyMark(const string cur_in)
  {
   string cur=cur_in;
#ifdef PL_DEV_LOG
   if(g_dev_cur_show!="") cur=g_dev_cur_show;
#endif
   if(cur=="USD") return "$";
   if(cur=="EUR") return ShortToString(0x20AC);
   if(cur=="GBP") return ShortToString(0xA3);
   StringTrimLeft(cur); StringTrimRight(cur);
   return cur;
  }

//--- time left of a pending order, never more than what actually remains (every unit is rounded down):
//--- under a minute "expiring", under 10 h two units ("3h 59m", "4h", "59m"), from 10 h whole hours, from a day "1d 2h"
string PlLeftText(const long secs)
  {
   if(secs<60) return PLS_EXPIRING;
   const long mins=secs/60;
   if(mins>=1440)
     {
      const long d=mins/1440, h=(mins%1440)/60;
      return (string)d+"d"+((h>0)?" "+(string)h+"h":"");
     }
   if(mins>=600) return (string)(mins/60)+"h";
   if(mins>=60)
     {
      const long h=mins/60, mm=mins%60;
      return (string)h+"h"+((mm>0)?" "+(string)mm+"m":"");
     }
   return (string)mins+"m";
  }

//--- a percent that rounds to zero is shown as "<0.01%", never as 0.00%
string PlPctText(const double v)
  {
   return (v>0.0 && v<0.005)?PLS_PCT_TINY:DoubleToString(v,2)+"%";
  }

//--- money with the account currency sign; sign=true prints + or - in front
string PlMoney(const double v,const string cur,const int digits,const bool sign=false)
  {
   string s=PlThousands(v,digits);
   string pre="";
   if(v<-1e-9) pre="-"; else if(sign && v>1e-9) pre="+";
   return pre+PlCurrencySign(cur)+s;
  }

//--- the short form of a money amount for a narrow place: $12.5k, $1.25M (below 10,000 the full form fits)
string PlMoneyShort(const double v,const string cur,const int digits,const bool sign=false)
  {
   double a=MathAbs(v);
   if(a<10000.0) return PlMoney(v,cur,digits,sign);
   string pre="";
   if(v<-1e-9) pre="-"; else if(sign && v>1e-9) pre="+";
   string body;
   if(a>=1000000.0) body=DoubleToString(a/1000000.0,2)+"M";
   else body=DoubleToString(a/1000.0,1)+"k";
   return pre+PlCurrencySign(cur)+body;
  }

//--- the short form of a reason for the grey button: "Blocked: no SL". The full phrase stays in the status line above.
string PlReasonShort(const PlReason r)
  {
   switch(r)
     {
      case PL_R_NO_QUOTE:           return "no quote";
      case PL_R_NO_SYMBOL_DATA:     return "no symbol data";
      case PL_R_NO_CONVERSION:      return "no rate";
      case PL_R_STALE_QUOTE:        return "old quote";
      case PL_R_MARKET_CLOSED:      return "market closed";
      case PL_R_SL_WRONG_SIDE:      return "SL side";
      case PL_R_SL_TOO_CLOSE:       return "SL too close";
      case PL_R_TP_WRONG_SIDE:      return "TP side";
      case PL_R_TP_TOO_CLOSE:       return "TP too close";
      case PL_R_ENTRY_WRONG_SIDE:   return "entry side";
      case PL_R_LIMIT_WRONG_SIDE:   return "limit side";
      case PL_R_KIND_NOT_ALLOWED:   return "order type";
      case PL_R_LOT_BELOW_MIN:      return "lot below min";
      case PL_R_LOT_ABOVE_MAX:      return "lot above max";
      case PL_R_RISK_ABOVE_CAP:     return "risk cap";
      case PL_R_PATHS_DISAGREE:     return "loss mismatch";
      case PL_R_MARGIN:             return "no margin";
      case PL_R_STOPOUT_BEFORE_SL:  return "stop-out";
      case PL_R_NO_SL:              return "no SL";
      case PL_R_TRADE_DISABLED:     return "trading off";
      case PL_R_NOT_DEMO:           return "demo only";
      case PL_R_DISCONNECTED:       return "no connection";
      case PL_R_VOLUME_LIMIT:       return "volume limit";
      case PL_R_BAD_INPUT:          return "bad number";
      case PL_R_ALGO_OFF:           return "Algo Trading off";
      case PL_R_EA_NOT_ALLOWED:     return "algo not allowed";
      case PL_R_INVESTOR:           return "read-only login";
      case PL_R_BROKER_NO_EA:       return "no EAs here";
      case PL_R_SYMBOL_CLOSE_ONLY:  return "close only";
      case PL_R_SYMBOL_LONG_ONLY:   return "buys only";
      case PL_R_SYMBOL_SHORT_ONLY:  return "sells only";
      case PL_R_ENTRY_TOO_CLOSE:    return "entry too close";
      case PL_R_NETTING_REVERSE:
      case PL_R_NETTING_ADD:
      case PL_R_NETTING_ORDER_OPEN:
      case PL_R_NETTING_PENDING:
      case PL_R_NETTING_NO_SL:
      case PL_R_NETTING_TPS:
      case PL_R_NETTING_NO_ROOM:
      case PL_R_NETTING_NO_VALUE:
      case PL_R_NETTING_TP_PARTS:   return "netting";
      case PL_R_GUARD:              return "limit";
      case PL_R_SPLIT_TOO_MANY:     return "too many orders";
      case PL_R_SPLIT_NETTING:      return "needs hedging";
      case PL_R_NO_CALC:            return "no loss data";
      case PL_R_CALC_MODE:          return "not supported";
      case PL_R_LOT_GRID:           return "lot step";
      case PL_R_NO_FILL_MODE:       return "no fill type";
      case PL_R_ORDERS_DAILY:       return "daily orders";
      case PL_R_ATR_NOT_READY:      return "ATR not ready";
      case PL_R_SIDE_CROSSED:       return "price crossed SL";
      case PL_R_OTHER_PLAINLINES:   return "other Plainlines";
     }
   return "";
  }

//--- the text of the grey button: "Blocked: no SL", or just "Blocked" for a reason with no short form
string PlBlockedText(const PlReason r)
  {
   const string w=PlReasonShort(r);
   return (w!="")?PLS_BLOCKED+": "+w:PLS_BLOCKED;
  }

//--- the short reason of a BLOCK of the account guards for the grey button. No guard block stands without
//--- its own word (the reason is on the button); "limit" is only for a block the list does not know
string PlGuardShort(const PlGuardWhy w)
  {
   switch(w)
     {
      case PL_LW_PROFILE_BAD:       return "account file";
      case PL_LW_NO_HISTORY:        return "history";
      case PL_LW_NEW_NO_SL:         return "needs an SL";
      case PL_LW_RISK_UNKNOWN:      return "risk unknown";
      case PL_LW_PORTFOLIO_UNKNOWN: return "risk unknown";
      case PL_LW_PORTFOLIO_CAP:     return "total risk";
      case PL_LW_TRADES_OPEN:       return "max open";
      case PL_LW_TRADES_DAY:        return "max entries a day";
     }
   return "limit";
  }

//--- the phrase of a send stopped because the new risk does not fit a room (the lot is recounted at the send)
string PlGuardRoomPhrase(const PlGuard &g,const double risk,const double lpl,const double step,const string cur,const int cd)
  {
   if(g.room_port>=0.0 && risk>g.room_port+PL_EPS)
     {
      const double pct=(g.balance>PL_EPS)?(g.port_used+risk)/g.balance*100.0:0.0;
      return "Total risk would be "+DoubleToString(pct,2)+"% (cap "+DoubleToString(g.port_cap_pct,2)+"%)";
     }
   return PlReasonText(PL_R_GUARD);
  }

//--- the phrase for a result of the guards (the reason is o.why)
string PlGuardPhrase(const PlGuardOut &o,const PlGuardCfg &c,const double new_risk,const double lpl,const double step,
                     const string cur,const int cd)
  {
   switch(o.why)
     {
      case PL_LW_PROFILE_BAD:       return PLS_PROF_BAD;
      case PL_LW_RISK_UNKNOWN:      return PLS_RISK_UNKNOWN+g_ex_unknown_sym;
      case PL_LW_NO_HISTORY:        return (g_hist_read && g_hist_conn && MathAbs(g_hist_diff)>PlHistTol(cd))?PLS_LIM_NO_HISTORY+PLS_LIM_HIST_DIFF+PlMoney(MathAbs(g_hist_diff),cur,cd):PLS_LIM_NO_HISTORY;
      case PL_LW_NEW_NO_SL:         return PLS_CAP_NEW_NO_SL;
      case PL_LW_PORTFOLIO_UNKNOWN: return PLS_LIM_PORT_UNKNOWN;
      case PL_LW_PORTFOLIO_CAP:     return "Total risk would be "+DoubleToString(o.portfolio_pct,2)+"% (cap "+DoubleToString(c.portfolio_cap_pct,2)+"%)";
      case PL_LW_TRADES_OPEN:       return PLS_LIM_WOULD_MAKE+(string)o.open_after+PLS_LIM_OPEN_LIMIT+(string)c.max_open;
      case PL_LW_TRADES_DAY:        return PLS_LIM_WOULD_MAKE+(string)o.entries_after+PLS_LIM_ENTRIES_LIMIT+(string)c.max_day;
      case PL_LW_MARGIN_USE:        return "Margin use "+DoubleToString(o.margin_use_pct,(o.margin_use_pct<10.0)?1:0)+"% after this trade: confirm";
     }
   return "";
  }

//--- moved here from the other files (one place for every text)
#define PLS_RISK_SP                       "Risk "
#define PLS_PCT_CONFIRM                  "%: confirm"
#define PLS_PRESS_AGAIN_TO_SEND_AT_MARKET "Press again to send at market"
#define PLS_PRESS_AGAIN_CARD              "Press again to send"
#define PLS_EXPIRES_TODAY                "expires today"
#define PLS_EXPIRES_IN                   "expires in "
#define PLS_GOOD_TILL_CANCELLED          "good till cancelled"
#define PLS_ENTRY_SP                      "Entry "
#define PLS_BUY_SELL                     "BUY / SELL"
#define PLS_AT_MARKET                    " at market"
#define PLS_LIMIT_CAPS                      " LIMIT "
#define PLS_STOP_CAPS                         " STOP "
#define PLS_STOP_LIMIT_CAPS                   " STOP LIMIT "
#define PLS_BUY                          "Buy"
#define PLS_SELL                         "Sell"
#define PLS_LIMIT_SUFFIX                      " Limit"
#define PLS_STOP_SUFFIX                       " Stop"
#define PLS_STOP_LIMIT_SUFFIX                 " Stop-Limit"
#define PLS_STOP_LIMIT_SHORT_SUFFIX           " S-Limit"      // a result phrase that is too long for its line
#define PLS_RISK_LC                       "risk "
#define PLS_RISK_UNDEFINED               "risk undefined"
#define PLS_OF_SP                         " of "
#define PLS_TRIGGER_BARE                    "trigger"
#define PLS_LIMIT_PRICE                  "limit"
#define PLS_LOT_CAPS                        "LOT"
#define PLS_ADD_CAPS                        "ADD"       // a netting add: the lot above is the added one (the caption is "LOT · ADD")
#define PLS_NET_BASE                        "Base after open risk "
#define PLS_VERSION_WORD                    "Version"
#define PLS_TP_SEP                         "  TP "
#define PLS_SL_SP                         "SL "
#define PLS_RISK_SEP                       "  risk "
#define PLS_PARTS_X                        " x"
#define PLS_LOT_WORD                        " lot"
#define PLS_NONE                         "none"
#define PLS_PER_LOT_SIDE                 "per lot / side"
#define PLS_PER_LOT_ROUND                "per lot / round"
#define PLS_PCT_NOTIONAL_SIDE            "% notional / side"
#define PLS_SIDE                         " / side"
#define PLS_ROUND                        " / round"
#define PLS_NA                           "n/a"
#define PLS_PRICE_FAR                    "Price is too far from the market, check the number"
#define PLS_LOT_BELOW_BROKER_MIN         "Lot is below the broker minimum of "
#define PLS_NIGHT                        " / night"
#define PLS_RISK_BASE                    "Risk base"
#define PLS_BALANCE_EQUITY               "Balance|Equity"
#define PLS_HARD_CAP                     "Hard cap"
#define PLS_CONFIRM_ABOVE                "Confirm above"
#define PLS_SUBTRACT_OPEN_RISK           "Subtract open risk"
#define PLS_ABOVE_BROKER_MAX_LOT         "Above broker max lot"
#define PLS_BLOCK_TRIM_SPLIT             "Block|Trim|Split"
#define PLS_LOT_WORD_UP                  "Lot "
#define PLS_Q_NO_SL                      "No SL"
#define PLS_QUICK_PANEL                  "Quick panel"
#define PLS_STRIP_CARD                   "Strip|Card"
#define PLS_KIND_MKT_S                   "Mkt"
#define PLS_KIND_LMT_S                   "Lmt"
#define PLS_KIND_STP_S                   "Stp"
#define PLS_KIND_SL_S                    "S-L"
#define PLS_IS_ABOVE_THE_BROKER_MAX      " is above the broker max "
#define PLS_SPLIT_WOULD_NEED             "Split would need "
#define PLS_ORDERS_THE_LIMIT_IS          " orders, the limit is "
#define PLS_GOES_OUT_IN                  " goes out in "
#define PLS_SPLIT_NEEDS_HEDGING          "Split needs a hedging account: this one nets positions"
#define PLS_MAX_TOTAL_RISK               "Max total risk"
#define PLS_MAX_OPEN_TRADES              "Max open incl. orders"
#define PLS_COUNTS_EACH_ORDER            "Each order counts, a TP leg too"
#define PLS_MAX_TRADES_A_DAY             "Max entries a day"
#define PLS_MARGIN_USE_CONFIRM_ABOVE     "Confirm margin above"
#define PLS_ATR_STOP                     "ATR stop"
#define PLS_ATR_MULTIPLIER               "ATR multiplier"
#define PLS_ATR_PERIOD                   "ATR period"
#define PLS_TAKE_PROFITS                 "Take profits"
#define PLS_TP1_SHARE                    "TP1 share"
#define PLS_TP2_TARGET                   "TP2 target"
#define PLS_TP2_SHARE                    "TP2 share"
#define PLS_TP3_TARGET                   "TP3 target"
#define PLS_TP3_SHARE                    "TP3 share"
#define PLS_TRADE_WITHOUT_SL             "Trade without SL"
#define PLS_NO_TP                        "No TP"
#define PLS_MAGIC                        "Magic"
#define PLS_MAGIC_NOTE                   "Positions of another magic are not listed or closed here"
#define PLS_COMMENT                      "Comment"
#define PLS_PENDING_EXPIRY               "Pending expiry"
#define PLS_GTC_TODAY_HOURS              "GTC|Today|Hours"
#define PLS_EXPIRE_AFTER                 "Expire after"
#define PLS_MAX_SPREAD_PCT_OF_SL         "Max spread, % of SL"
#define PLS_CONFIRMATION                 "Confirmation"
#define PLS_HOTKEY_NOTE                  "Shift+T opens the trade from the chart"
#define PLS_SOUNDS                       "Sounds"
#define PLS_MOVE_SL_TO_BREAKEVEN         "Move SL to breakeven"
#define PLS_BREAKEVEN_AT                 "Breakeven at"
#define PLS_TRAILING                     "Trailing"
#define PLS_TRAIL_DISTANCE               "Trail distance"
#define PLS_TRAIL_ZERO_NOTE              "Kept per symbol, 0 = the initial SL distance"
#define PLS_PIPS                         "pips"
#define PLS_PARTIAL_CLOSE                "Partial close"
#define PLS_CLOSE_BUTTONS                "Close buttons"
#define PLS_THEME                        "Theme"
#define PLS_AUTO_LIGHT_DARK              "Auto|Light|Dark"
#define PLS_SCALE                        "Scale"
#define PLS_AUTO_100_125_150             "Auto|100|125|150"
#define PLS_ENTRY_MOVED                  "Entry moved: "
#define PLS_BUY_SP                        "Buy "
#define PLS_SELL_SP                       "Sell "
#define PLS_SL_DISTANCE                  "SL distance"
#define PLS_TP_DISTANCE                  "TP distance"
#define PLS_TP2_R                        "TP2 R"
#define PLS_TP3_R                        "TP3 R"
#define PLS_EXPIRY_HOURS                 "Expiry hours"
#define PLS_MAX_SPREAD                   "Max spread"
#define PLS_BREAKEVEN_R                  "Breakeven R"
#define PLS_MARGIN_USE                   "Margin use"
#define PLS_TRAIL_PIPS                   "Trail distance"
#define PLS_AT                           " at "
#define PLS_IN                           " in "
#define PLS_FILLED                       "Filled "
#define PLS_PLACED_SP                    "Placed "
#define PLS_RISK_SP_LC                   "risk "
#define PLS_PLANNED_SP                   " (planned "
#define PLS_CLOSE_TP_HIT                 "TP hit"
#define PLS_CLOSE_SL_HIT                 "SL hit"
#define PLS_CLOSE_STOP_OUT               "Stop out"
#define PLS_CLOSE_CLOSED                 "Closed"
#define PLS_CLOSE_PART                   "Closed part"
#define PLS_NET_SP                       " net"
#define PLS_NO_SL_COMMA                  ", no SL"
#define PLS_LOT_RISK                     " lot, risk "
#define PLS_THE_REST_WAS_NOT_FILLED      ". The rest was not filled"
#define PLS_SENT                         "Sent "
#define PLS_ANSWER_LOST_REST_NOT_SENT "the answer of the last one was lost, the rest was not sent"
#define PLS_UNRESOLVED              "No answer in 30 s: check the Trade tab"
#define PLS_LAST_UNKNOWN            "no answer for the last one, check the Trade tab"
#define PLS_UNKNOWN_WARN            "No answer: check Trade tab, press again"
#define PLS_ACCT_CHANGED_CHECK      "Account changed before the last order was answered: check the previous account"
#define PLS_ORDER_FILLED_NOT_DELETED "Order filled before it could be deleted: the position is open"
#define PLS_SL_FIX_UNKNOWN          "SL correction had no answer: check the SL"
#define PLS_SL_FIX_REST             "SL correction had no answer, the rest was not sent"
#define PLS_MOVED_REST_NOT_SENT     "price moved, the rest was not sent"
#define PLS_NO_QUOTE_REST           "no quote, the rest was not sent"
#define PLS_SLIPPAGE                "Slipped"   // after "risk $X": the status line is narrow, a longer note is cut
#define PLS_REST_STILL_OPEN         ": the rest is still open"
#define PLS_CLOSED_PART_OF          "Closed part of "
#define PLS_EXP_USE                 "This lifetime is not allowed on this symbol: use "
#define PLS_EXP_NONE                "This symbol allows no pending order lifetime the panel can use"
#define PLS_OR                      " or "
#define PLS_FILLED_ONLY_PART_OF_AN_ORDER "Filled only part of an order"
#define PLS_SHARE_IS_BELOW_THE_MINIMUM_LOT " share is below the minimum lot: merged with TP"
#define PLS_TP1_BELOW_MIN_LOT "TP1 share is below the minimum lot: merged with TP2"

#define PLS_NET_ADD_MGMT      "Check the BE and trailing of the position in its row"
#define PLS_NET_CHECK_SLTP    "Check the SL and TP of the position"
#define PLS_REC_EXISTS        "A record for this ticket already exists, kept as it is"
#define PLS_PARTS_OFF_NO_VOL  "Filled volume unknown, TP parts are off"
#define PLS_POS_GREW          "Position grew, its TP parts are off"
#define PLS_ORDER_MERGED      "Order filled into the open position, its BE, trailing and TP parts are off"
#define PLS_MANAGE_PAUSED     "Positions not managed: "
#define PLS_REC_SYM_CHANGED   "Breakeven, trailing and TP parts not set: symbol changed during the check"
#define PLS_OFF_BE            "Breakeven off for "
#define PLS_OFF_TRAIL         "Trailing off for "
#define PLS_OFF_PT            "TP parts off for "
#define PLS_OFF_EXP           "Delete the expired order by hand on "
#define PLS_PART_REST_MIN     "Rest would be below the minimum lot"
#define PLS_NEED_LOSS_SL      "BE and Trail need an SL on the loss side of the entry"
#define PLS_BE_WAIT_DEAL      "Breakeven not ready: entry deal not in history yet"
#define PLS_TP_PART_BELOW_MIN ": share below the minimum lot, nothing closed"

//--- a short form of a long status phrase, for the quick card header and the status row when the long one does not fit its place
//--- (the full panel keeps the long one whenever it fits). Only the reasons whose long phrase is over about 24 characters have one;
//--- "" for the rest. The core wording is in Core/Reasons.mqh, so a phrase is matched by PlAltOfPhrase against PlReasonText
string PlReasonStatusShort(const PlReason r)
  {
   switch(r)
     {
      case PL_R_NO_CONVERSION:      return "No rate for the commission";
      case PL_R_STALE_QUOTE:        return "No new quote";
      case PL_R_SL_TOO_CLOSE:       return "SL too close";
      case PL_R_TP_WRONG_SIDE:      return "TP on the wrong side";
      case PL_R_TP_TOO_CLOSE:       return "TP too close";
      case PL_R_ENTRY_WRONG_SIDE:   return "Entry on the wrong side";
      case PL_R_LIMIT_WRONG_SIDE:   return "Limit on the wrong side";
      case PL_R_KIND_NOT_ALLOWED:   return "Order type not allowed";
      case PL_R_PATHS_DISAGREE:     return "Loss figures disagree";
      case PL_R_STOPOUT_BEFORE_SL:  return "Stop-out before the SL";
      case PL_R_CROSS_RATE_AT_SL:   return "Cross pair: rate at SL";
      case PL_R_TRADE_DISABLED:     return "Trading disabled here";
      case PL_R_ALGO_OFF:           return "Turn on Algo Trading";
      case PL_R_INVESTOR:           return "Read-only login";
      case PL_R_BROKER_NO_EA:       return "Broker blocks EAs";
      case PL_R_SYMBOL_CLOSE_ONLY:  return "Symbol is close-only";
      case PL_R_ENTRY_TOO_CLOSE:    return "Entry too close";
      case PL_R_NETTING_REVERSE:    return "Netting: would reverse it";
      case PL_R_NETTING_ADD:        return "Netting add: SL, TP for all";
      case PL_R_NETTING_ORDER_OPEN: return "Netting: an order is open";
      case PL_R_NETTING_PENDING:    return "Netting: no pending order";
      case PL_R_NETTING_NO_SL:      return "Netting: the add needs an SL";
      case PL_R_NETTING_TPS:        return "Netting: one TP only";
      case PL_R_NETTING_NO_ROOM:    return "Netting: no room in the risk";
      case PL_R_NETTING_NO_VALUE:   return "Netting: cannot value it";
      case PL_R_NETTING_TP_PARTS:   return "Netting: use fewer TPs";
      case PL_R_NO_CALC:            return "No loss figure yet";
      case PL_R_CALC_MODE:          return "Instrument not supported";
      case PL_R_LOT_GRID:           return "Lot step does not fit";
      case PL_R_NO_FILL_MODE:       return "No fill type allowed";
      case PL_R_ORDERS_DAILY:       return "SL, TP deleted daily";
      case PL_R_LOT_BELOW_MIN:      return "Min lot: risk is higher";
      case PL_R_LOT_ABOVE_MAX:      return "Lot above broker max";
      case PL_R_NOT_DEMO:           return "Demo accounts only";
      case PL_R_SPLIT_ORDERS:       return "Split in several orders";
      case PL_R_SPLIT_TOO_MANY:     return "Too many split orders";
      case PL_R_SPLIT_NETTING:      return "Split needs hedging";
      case PL_R_SIDE_CROSSED:       return "Price crossed SL: move it";
      case PL_R_OTHER_PLAINLINES:   return "Remove Plainlines Pro first";
     }
   return "";
  }

//--- the same for the sentences of this file that are not a reason of the core: a fixed sentence by its text, "" when it has none.
//--- Every short form is about 120 or less wide at the smallest font (70, in logical pixels at Scale 100), so that it fits the quick card beside a symbol
string PlAltOfSentence(const string t)
  {
   if(t==PLS_SPLIT_NEEDS_HEDGING)           return "Split needs hedging";
   if(t==PLS_ACCT_CHANGED_CHECK)            return "Account changed: check order";
   if(t==PLS_ACCT_CHANGED)                  return "Account changed";
   if(t==PLS_SETTINGS_BAD)                  return "Settings damaged, defaults";
   if(t==PLS_SETTINGS_NOT_SAVED)            return "Settings not saved";
   if(t==PLS_PROF_OFF)                      return "New account: no total risk cap";
   if(t==PLS_PROF_BAD)                      return "Account file damaged: reset it";
   if(t==PLS_PROF_NO_ID)                    return "No deposit: limits not saved";
   if(t==PLS_LIM_NOT_SUB)                   return "No-SL trade not subtracted";
   if(t==PLS_LIM_PORT_UNKNOWN)              return "Total risk unknown: no SL";
   if(t==PLS_CAP_NEW_NO_SL)                 return "Total risk cap: SL needed";
   if(t==PLS_NEED_LOSS_SL)                  return "BE, Trail: SL on the loss side";
   if(t==PLS_BE_WAIT_DEAL)                  return "Breakeven: no deal in history";
   if(t==PLS_ALREADY_BE)                    return "SL already at breakeven";
   if(t==PLS_NOT_PAST_BE)                   return "Not past breakeven yet";
   if(t==PLS_PART_REST_MIN)                 return "Rest below min lot";
   if(t==PLS_PART_BELOW_MIN)                return "Part below min lot";
   if(t==PLS_ORDER_EXPIRED)                 return "Order expired and deleted";
   if(t==PLS_CHECKING)                      return "No answer: checking order";
   if(t==PLS_WAIT_CONN)                     return "No connection: check waits";
   if(t==PLS_UNKNOWN_WARN || t==PLS_UNRESOLVED) return "No answer: check Trade tab";
   if(t==PLS_BUSY)                          return "Another order in progress";
   if(t==PLS_ORDER_FILLED_NOT_DELETED)      return "Order filled, position is open";
   if(t==PLS_PRICE_FAR)                     return "Price too far: check it";
   if(t==PLS_EXP_NONE)                      return "No usable order lifetime";
   return "";
  }

//--- t if it starts with the fixed head, else ""; the rest after the head
bool PlAltRest(const string t,const string head,string &rest)
  {
   if(StringFind(t,head,0)!=0) return false;
   rest=StringSubstr(t,StringLen(head));
   return true;
  }

//--- the sentences that carry a number or a symbol after a fixed head (a lot, a limit, a symbol of the manager note): the short form
//--- keeps that part as it is. "" when t is none of them
string PlAltOfNumbered(const string t)
  {
   string r;
   //--- the manager notes end in ": SYMBOL"
   if(PlAltRest(t,PLS_REC_EXISTS,r))          return (StringFind(r,": ",0)==0)?"Record exists, kept"+r:"";
   if(PlAltRest(t,PLS_PARTS_OFF_NO_VOL,r))    return (StringFind(r,": ",0)==0)?"No volume, TP off"+r:"";
   if(PlAltRest(t,PLS_POS_GREW,r))            return (StringFind(r,": ",0)==0)?"Grew, TP parts off"+r:"";
   if(PlAltRest(t,PLS_ORDER_MERGED,r))        return (StringFind(r,": ",0)==0)?"Merged, BE, TP off"+r:"";
   if(PlAltRest(t,PLS_OFF_EXP,r))
     {
      const int c=StringFind(r,": ",0);
      return "Delete expired order: "+((c>0)?StringSubstr(r,0,c):r);
     }
   if(PlAltRest(t,PLS_EXP_USE,r))             return "Lifetime: use "+r;
   if(PlAltRest(t,PLS_LOT_BELOW_BROKER_MIN,r)) return "Lot below broker min "+r;
   if(PlAltRest(t,PLS_SPLIT_WOULD_NEED,r))
     {
      StringReplace(r,PLS_ORDERS_THE_LIMIT_IS," orders, limit ");
      return "Split: "+r;
     }
   if(PlAltRest(t,PLS_LOT_WORD_UP,r))
     {
      //--- "Lot 12.00 is above the broker max 10.00" and "Lot 3.00 goes out in 4 orders"
      const int a=StringFind(r,PLS_IS_ABOVE_THE_BROKER_MAX,0);
      if(a>0) return "Lot over broker max "+StringSubstr(r,a+StringLen(PLS_IS_ABOVE_THE_BROKER_MAX));
      if(StringFind(r,PLS_GOES_OUT_IN,0)>0)
        {
         StringReplace(r,PLS_GOES_OUT_IN," in ");
         return "Lot "+r;
        }
      return "";
     }
   //--- the guards
   if(StringFind(t,PLS_LIM_NO_HISTORY,0)==0)  return "Waiting for account history";
   if(PlAltRest(t,"Total risk would be ",r))
     {
      StringReplace(r," (cap ",", cap ");
      StringReplace(r,")","");
      return "Total risk "+r;
     }
   if(PlAltRest(t,"Margin use ",r))
     {
      StringReplace(r," after this trade: confirm"," after: confirm");
      return "Margin use "+r;
     }
   if(PlAltRest(t,PLS_LIM_WOULD_MAKE,r) && StringFind(r,PLS_LIM_ENTRIES_LIMIT,0)>0) return r;
   return "";
  }

//--- the short form of a status phrase as the panel has it now, "" when it has none: a phrase of the core by its text (the stale one
//--- also with the minutes in it), the sentences of this file that the status row shortens
string PlAltOfPhrase(const string t)
  {
   if(t=="") return "";
   if(StringFind(t,"No new quote",0)==0) return PlReasonStatusShort(PL_R_STALE_QUOTE);
   for(int i=1;i<=(int)PL_R_OTHER_PLAINLINES;i++)
     {
      const PlReason r=(PlReason)i;
      if(PlReasonText(r)==t) return PlReasonStatusShort(r);
     }
   if(t==PLS_MARKET_CLOSED_SHORT) return PLS_MARKET_CLOSED_CARD;
   if(t==PLS_EA_NOT_ALLOWED_SHORT) return PLS_EA_NOT_ALLOWED_CARD;
   if(t==PLS_SET_SL) return PLS_SET_SL_CARD;
   if(t==PLS_NO_SL_SIDE) return PLS_NO_SL_SIDE_CARD;
   if(t==PLS_PRESS_AGAIN_TO_SEND_AT_MARKET) return PLS_PRESS_AGAIN_CARD;
   const string st=PlAltOfSentence(t);
   if(st!="") return st;
   return PlAltOfNumbered(t);
  }

#endif
