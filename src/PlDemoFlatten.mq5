// Required Notice: Copyright 2026 stop-loss-enjoyer
// Plainlines is source-available under the PolyForm Shield License 1.0.0.
//
// Development script: closes every position and deletes every pending order with the given magic
// (the Plainlines magic by default) on a DEMO account, so the next test starts from a clean account.
// Its own check in OnStart refuses a non-demo account, and it never includes Build.mqh, so the shared
// lock in SendOrderSafe also holds. Writes MQL5/Files/PlDemoFlatten.json (counts and errors, no account number).
#property copyright "stop-loss-enjoyer"
#include "Version.mqh"
#property version   PLAINLINES_VERSION
#property strict
#property script_show_inputs

#include "Core/Types.mqh"
#include "Core/Num.mqh"
#include "Core/Reasons.mqh"
#include "Core/Prices.mqh"
#include "Core/Lot.mqh"
#include "Terminal/DevLog.mqh"
#include "Core/Guard.mqh"
#include "Terminal/Market.mqh"
#include "Terminal/Exposure.mqh"
#include "UI/Strings.mqh"
#include "Terminal/OneProgram.mqh"
#include "Trade/TradeTypes.mqh"
#include "Trade/SendOrderSafe.mqh"

input long InpMagic=20261011;   // magic of the positions and orders to clear

//--- Exposure.mqh declares the commission settings of the user, which live in the panel (UI/State.mqh). A script has none: "none set".
bool PlUserComm(const string sym,PlCommKind &kind,double &rate) { return false; }
bool PlUserCommMoney(const string sym,const ENUM_ORDER_TYPE ot,const double vol,const double ex,const double sl,double &money) { money=0.0; return false; }
bool PlCommMoneyOf(const PlCommKind kind,const double rate,const string sym,const ENUM_ORDER_TYPE ot,const double vol,const double ex,const double sl,double &money,const double min_round=0.0) { money=0.0; return false; }

string JsonText(const string t)
  {
   string o="";
   const int n=StringLen(t);
   for(int i=0;i<n;i++)
     {
      const ushort c=StringGetCharacter(t,i);
      if(c=='"' || c=='\\') o+="\\";
      if(c<32) continue;
      o+=ShortToString(c);
     }
   return o;
  }

void OnStart()
  {
   int pos_before=0, ord_before=0, closed=0, deleted=0;
   string errs="";
   string refused="";
   if(AccountInfoInteger(ACCOUNT_TRADE_MODE)!=ACCOUNT_TRADE_MODE_DEMO) refused="demo account only";
   //--- run from a startup ini the script can start before the terminal has its connection: wait for it (30 s at most)
   for(int w=0;w<60 && !TerminalInfoInteger(TERMINAL_CONNECTED);w++) Sleep(500);
   if(refused=="")
     {
      PlAccount acc;
      PlReadAccount(acc,false);
      PlReason why=PL_R_NONE;
      PlSymbol s;
      s.sym_trade_mode=SYMBOL_TRADE_MODE_FULL;
      PlTradeGate(acc,s,true,why);
      if(why!=PL_R_NONE) refused=PlReasonText(why);
     }
   if(refused=="")
     {
      for(int round=0;round<3;round++)
        {
         ulong pids[]; ulong oids[];
         ArrayResize(pids,0); ArrayResize(oids,0);
         for(int i=PositionsTotal()-1;i>=0;i--)
           {
            ulong tk=PositionGetTicket(i);
            if(tk==0 || PositionGetInteger(POSITION_MAGIC)!=InpMagic) continue;
            int n=ArraySize(pids); ArrayResize(pids,n+1); pids[n]=(ulong)PositionGetInteger(POSITION_IDENTIFIER);
           }
         for(int i=OrdersTotal()-1;i>=0;i--)
           {
            ulong tk=OrderGetTicket(i);
            if(tk==0 || OrderGetInteger(ORDER_MAGIC)!=InpMagic) continue;
            int n=ArraySize(oids); ArrayResize(oids,n+1); oids[n]=tk;
           }
         if(round==0) { pos_before=ArraySize(pids); ord_before=ArraySize(oids); }
         if(ArraySize(pids)==0 && ArraySize(oids)==0) break;
         for(int i=0;i<ArraySize(oids);i++)
           {
            PlSendRes r; PlSendDeleteOrder(oids[i],r);
            if(r.status==PL_SS_DONE) deleted++; else errs+=(errs==""?"":"; ")+"order: "+r.phrase;
           }
         for(int i=0;i<ArraySize(pids);i++)
           {
            PlSendRes r; PlSendClosePos(pids[i],0.0,r);
            if(r.status==PL_SS_DONE) closed++; else errs+=(errs==""?"":"; ")+"position: "+r.phrase;
            //--- a lost answer: wait for the check to finish before the next request
            for(int w=0;w<80 && PlTradeBusy();w++) { Sleep(500); PlSendRes q; PlTradeReconcileStep(q); }
           }
         Sleep(500);
        }
     }
   int pos_left=0, ord_left=0;
   for(int i=PositionsTotal()-1;i>=0;i--) { ulong tk=PositionGetTicket(i); if(tk!=0 && PositionGetInteger(POSITION_MAGIC)==InpMagic) pos_left++; }
   for(int i=OrdersTotal()-1;i>=0;i--) { ulong tk=OrderGetTicket(i); if(tk!=0 && OrderGetInteger(ORDER_MAGIC)==InpMagic) ord_left++; }
   string js="{\"magic\":"+(string)InpMagic+",\"refused\":\""+JsonText(refused)+"\",\"positions_before\":"+(string)pos_before
             +",\"orders_before\":"+(string)ord_before+",\"closed\":"+(string)closed+",\"deleted\":"+(string)deleted
             +",\"positions_left\":"+(string)pos_left+",\"orders_left\":"+(string)ord_left+",\"errors\":\""+JsonText(errs)+"\"}";
   int h=FileOpen("PlDemoFlatten.json",FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(h!=INVALID_HANDLE) { FileWriteString(h,js+"\r\n"); FileClose(h); }
   Print("PlDemoFlatten: ",js);
  }
