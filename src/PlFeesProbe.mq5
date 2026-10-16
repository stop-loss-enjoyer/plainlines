// Required Notice: Copyright 2026 stop-loss-enjoyer
// Plainlines is source-available under the PolyForm Shield License 1.0.0.
//
// PlFeesProbe: the commission and fee the broker really took on ONE closed position, next to what the Plainlines core makes of
// the broker's own commission rule for the same symbol and volume. Run by the account holder on his own terminal: read, never trade.
// RULES, absolute:
// - No trade functions at all: no order sending, no order check, no position closing, no CTrade.
// - No open positions, no open orders.
// - Of the history only the newest closed position of the last 90 days: per deal its entry (in or out), volume, price,
//   DEAL_COMMISSION and DEAL_FEE, and the day. No tickets, no position id, no profit, no swap, no comment, no magic.
// - Of the account only its currency. No account number, name, server, balance, equity, margin.
// - No network, no imports, no common folder. Includes the pure core only (Core/*.mqh: no terminal calls).
// Writes MQL5/Files/PlFeesProbe.txt. Build: ./build.sh src/PlFeesProbe.mq5
#property strict
#include "Core/Lot.mqh"

string F(const double v,const int d=8) { return DoubleToString(v,d); }

void OnStart()
  {
   const int h=FileOpen("PlFeesProbe.txt",FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(h==INVALID_HANDLE) { Print("PlFeesProbe: cannot write ",GetLastError()); return; }
   const string acur=AccountInfoString(ACCOUNT_CURRENCY);
   FileWriteString(h,"account_currency="+acur+"\r\n");
   const datetime now=TimeCurrent();
   //--- the newest closing deal of the last 90 days, kept in memory only
   long pid=-1;
   string sym="";
   if(HistorySelect(now-90*86400,now+86400))
      for(int i=HistoryDealsTotal()-1;i>=0;i--)
        {
         const ulong tk=HistoryDealGetTicket(i);
         if(tk==0) continue;
         const long type=HistoryDealGetInteger(tk,DEAL_TYPE);
         if(type!=DEAL_TYPE_BUY && type!=DEAL_TYPE_SELL) continue;
         const long ent=HistoryDealGetInteger(tk,DEAL_ENTRY);
         if(ent!=DEAL_ENTRY_OUT && ent!=DEAL_ENTRY_OUT_BY) continue;
         pid=HistoryDealGetInteger(tk,DEAL_POSITION_ID);
         sym=HistoryDealGetString(tk,DEAL_SYMBOL);
         break;
        }
   if(pid<0 || !HistorySelectByPosition(pid))
     {
      FileWriteString(h,"no closed position in the last 90 days\r\n");
      FileClose(h);
      return;
     }
   FileWriteString(h,"symbol="+sym+"\r\n");
   double in_vol=0.0,in_price=0.0;
   for(int i=0;i<HistoryDealsTotal();i++)
     {
      const ulong tk=HistoryDealGetTicket(i);
      if(tk==0) continue;
      const long type=HistoryDealGetInteger(tk,DEAL_TYPE);
      if(type!=DEAL_TYPE_BUY && type!=DEAL_TYPE_SELL) continue;
      const long ent=HistoryDealGetInteger(tk,DEAL_ENTRY);
      const double vol=HistoryDealGetDouble(tk,DEAL_VOLUME);
      const double price=HistoryDealGetDouble(tk,DEAL_PRICE);
      if(ent==DEAL_ENTRY_IN) { in_vol+=vol; in_price=price; }
      FileWriteString(h,"deal entry="+((ent==DEAL_ENTRY_IN)?"IN":(ent==DEAL_ENTRY_OUT)?"OUT":(ent==DEAL_ENTRY_OUT_BY)?"OUT_BY":"INOUT")
                      +" side="+((type==DEAL_TYPE_BUY)?"BUY":"SELL")
                      +" day="+TimeToString((datetime)HistoryDealGetInteger(tk,DEAL_TIME),TIME_DATE)
                      +" volume="+F(vol,2)+" price="+F(price,(int)SymbolInfoInteger(sym,SYMBOL_DIGITS))
                      +" commission="+F(HistoryDealGetDouble(tk,DEAL_COMMISSION),2)
                      +" fee="+F(HistoryDealGetDouble(tk,DEAL_FEE),2)+"\r\n");
     }
   //--- the broker's rule for the symbol, shaped as Terminal/Market.mqh PlCommRule does it
   MqlCommission c[];
   ResetLastError();
   const int n=SymbolInfoCommissions(sym,c);
   FileWriteString(h,"rules n="+IntegerToString(n)+" err="+IntegerToString(n<0?GetLastError():0)+"\r\n");
   PlBrokerRule r[];
   if(n==1 && ArraySize(c)==1)
     {
      ArrayResize(r,1);
      r[0].currency=c[0].currency;
      r[0].mode_charge=(int)c[0].mode_charge;
      r[0].mode_direction=(int)c[0].mode_direction;
      r[0].mode_entry=(int)c[0].mode_entry;
      r[0].mode_profit=(int)c[0].mode_profit;
      r[0].mode_range=(int)c[0].mode_range;
      r[0].tier_count=ArraySize(c[0].tiers);
      r[0].range_from=0.0; r[0].range_to=0.0; r[0].min_value=0.0; r[0].max_value=0.0; r[0].value=0.0;
      r[0].tier_mode=-1; r[0].volume_type=-1; r[0].tier_currency="";
      if(r[0].tier_count>=1)
        {
         r[0].range_from=c[0].tiers[0].range_from; r[0].range_to=c[0].tiers[0].range_to;
         r[0].min_value=c[0].tiers[0].min_value; r[0].max_value=c[0].tiers[0].max_value;
         r[0].value=c[0].tiers[0].value;
         r[0].tier_mode=(int)c[0].tiers[0].mode;
         r[0].volume_type=(int)c[0].tiers[0].volume_type;
         r[0].tier_currency=c[0].tiers[0].currency;
        }
      FileWriteString(h,"rule currency="+r[0].currency+" charge="+IntegerToString(r[0].mode_charge)
                      +" direction="+IntegerToString(r[0].mode_direction)+" entry="+IntegerToString(r[0].mode_entry)
                      +" profit="+IntegerToString(r[0].mode_profit)+" range="+IntegerToString(r[0].mode_range)
                      +" tiers="+IntegerToString(r[0].tier_count)+" tier_mode="+IntegerToString(r[0].tier_mode)
                      +" volume_type="+IntegerToString(r[0].volume_type)+" tier_currency="+r[0].tier_currency
                      +" from="+F(r[0].range_from,4)+" to="+F(r[0].range_to,4)+" value="+F(r[0].value)
                      +" min="+F(r[0].min_value,4)+" max="+F(r[0].max_value,4)+"\r\n");
     }
   //--- the symbol data the core needs for a tier in another currency
   PlSymbol s;
   s.base=SymbolInfoString(sym,SYMBOL_CURRENCY_BASE);
   s.profit=SymbolInfoString(sym,SYMBOL_CURRENCY_PROFIT);
   s.calc_mode=(int)SymbolInfoInteger(sym,SYMBOL_TRADE_CALC_MODE);
   s.tick_size=SymbolInfoDouble(sym,SYMBOL_TRADE_TICK_SIZE);
   s.tick_value_loss=SymbolInfoDouble(sym,SYMBOL_TRADE_TICK_VALUE_LOSS);
   s.contract=SymbolInfoDouble(sym,SYMBOL_TRADE_CONTRACT_SIZE);
   s.bid=SymbolInfoDouble(sym,SYMBOL_BID);
   s.ask=SymbolInfoDouble(sym,SYMBOL_ASK);
   double k=0.0;
   const bool k_ok=PlRateK(s,k);
   FileWriteString(h,"symbol base="+s.base+" profit="+s.profit+" calc_mode="+IntegerToString(s.calc_mode)
                   +" contract="+F(s.contract,4)+" tick_size="+F(s.tick_size,10)+" tick_value_loss="+F(s.tick_value_loss)
                   +" k_ok="+(k_ok?"1":"0")+" k="+F(k,10)+"\r\n");
   PlCommKind kind=PL_COMM_UNKNOWN;
   double rate=0.0,min_round=0.0;
   bool known_zero=false;
   const bool ok=PlBrokerCommRule(n,r,acur,in_vol,s,k_ok,k,kind,rate,min_round,known_zero);
   FileWriteString(h,"core ok="+(ok?"1":"0")+" kind="+IntegerToString((int)kind)+" rate="+F(rate)
                   +" min_round="+F(min_round,4)+" known_zero="+(known_zero?"1":"0")
                   +" in_volume="+F(in_vol,2)+" in_price="+F(in_price,(int)SymbolInfoInteger(sym,SYMBOL_DIGITS))+"\r\n");
   FileClose(h);
   Print("PlFeesProbe: written to MQL5/Files/PlFeesProbe.txt");
  }
