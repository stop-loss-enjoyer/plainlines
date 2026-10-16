// Required Notice: Copyright 2026 stop-loss-enjoyer
// Plainlines is source-available under the PolyForm Shield License 1.0.0.
//
// The result of a closed position of Plainlines: when the exit deal of a position of ours arrives in
// OnTradeTransaction, by any road (SL, TP, a button of the panel, the terminal's own window, a stop out), the status line says
// how it ended: "TP hit · +2.0R · +$190.40 net", "SL hit · -1.0R · -$96.80 net", "Closed · +0.4R · +$38.10 net",
// "Stop out · ...". Net is the sum of profit, commission, swap and fee of EVERY deal of the position, entry and exit together.
// R is net divided by the initial risk: the loss of the entered volume from its entry price to the SL of the entry deal
// (OrderCalcProfit) plus the module of all commissions and fees of the position, so a clean SL comes out near -1.0R. With no SL
// on the entry deal the SL of the position's record is used, else there is no R and the phrase says "no SL". A partial close
// (the position lives on) says "Closed part · +$12.30 net" for that exit deal alone, with no R. Everything is read from the
// broker's history (HistorySelectByPosition); nothing is stored and nothing is sent. A terminal restarted after the close does
// not show it: the event was before the start.
#property strict

#ifndef PL_TRADE_CLOSESUMMARY_MQH
#define PL_TRADE_CLOSESUMMARY_MQH

//--- the status message that stays until the trader acts (Plainlines.mq5)
void PlMessageSticky(const string t,const int kind);

//--- R with one decimal and a sign; a result that rounds to zero is a plain 0.0R
string PlRText(const double r)
  {
   const string a=DoubleToString(MathAbs(r),1);
   if(r>=0.05) return "+"+a+"R";
   if(r<=-0.05) return "-"+a+"R";
   return "0.0R";
  }

//--- the one status phrase of a closed position; kind of the message: 3 profit, 4 loss, 0 zero
string PlCloseText(const long reason,const bool closed,const bool has_r,const double r,const bool no_sl,
                   const double net,const string cur,const int digits)
  {
   string head=PLS_CLOSE_CLOSED;
   if(!closed) head=PLS_CLOSE_PART;
   else if(reason==DEAL_REASON_TP) head=PLS_CLOSE_TP_HIT;
   else if(reason==DEAL_REASON_SL) head=PLS_CLOSE_SL_HIT;
   else if(reason==DEAL_REASON_SO) head=PLS_CLOSE_STOP_OUT;
   string t=head+PlDotSep();
   if(closed && has_r) t+=PlRText(r)+PlDotSep();
   t+=PlMoney(net,cur,digits,true)+PLS_NET_SP;
   if(closed && no_sl) t+=PLS_NO_SL_COMMA;
   return t;
  }

//--- the one phrase of a bulk close ("Closed 3 · -$12.40 net"; "Closed 2 of 3 ..." when one stayed open): the sum of the nets that
//--- the positions of the batch reported, colour by its sign
void PlBulkSay()
  {
   if(g_bulk_got<=0) { ArrayResize(g_bulk_id,0); return; }
   string t=PLS_CLOSE_CLOSED+" "+(string)g_bulk_got;
   if(g_bulk_got<g_bulk_planned) t+=" "+PLS_OF+" "+(string)g_bulk_planned;
   t+=PlDotSep()+PlMoney(g_bulk_net,AccountInfoString(ACCOUNT_CURRENCY),(int)AccountInfoInteger(ACCOUNT_CURRENCY_DIGITS),true)+PLS_NET_SP;
   ArrayResize(g_bulk_id,0);
   PlMessageSticky(t,(g_bulk_net>0.005)?3:(g_bulk_net<-0.005)?4:0);
  }

//--- an exit deal of position pid ended with this net: it belongs to the batch when its id waits there
void PlBulkNet(const ulong pid,const bool closed,const double net)
  {
   if(!closed) return;
   const int n=ArraySize(g_bulk_id);
   for(int i=0;i<n;i++)
      if(g_bulk_id[i]==pid)
        {
         g_bulk_id[i]=g_bulk_id[n-1]; ArrayResize(g_bulk_id,n-1);
         g_bulk_got++; g_bulk_net+=net;
         if(n-1==0) PlBulkSay();
         return;
        }
  }

//--- the lap: an exit deal that did not arrive (a part only, a slow history) does not hold the sum back for ever
void PlBulkTick(const ulong now)
  {
   if(ArraySize(g_bulk_id)>0 && now-g_bulk_at>=4000) PlBulkSay();
  }

//--- called for every new deal (TRADE_TRANSACTION_DEAL_ADD). Only the exit deal of a position of ours does anything.
void PlCloseSummary(const ulong deal)
  {
   if(deal==0) return;
   if(!HistoryDealSelect(deal))
     {
      if(!HistorySelect(TimeCurrent()-3600,TimeCurrent()+86400) || !HistoryDealSelect(deal)) return;
     }
   const long dtype=HistoryDealGetInteger(deal,DEAL_TYPE);
   if(dtype!=DEAL_TYPE_BUY && dtype!=DEAL_TYPE_SELL) return;
   const long entry=HistoryDealGetInteger(deal,DEAL_ENTRY);
   if(entry!=DEAL_ENTRY_OUT && entry!=DEAL_ENTRY_OUT_BY) return;
   const ulong pid=(ulong)HistoryDealGetInteger(deal,DEAL_POSITION_ID);
   if(pid==0) return;
   //--- this deal's own numbers before the history selection changes
   const long reason=HistoryDealGetInteger(deal,DEAL_REASON);
   const string sym=HistoryDealGetString(deal,DEAL_SYMBOL);
   const double d_net=HistoryDealGetDouble(deal,DEAL_PROFIT)+HistoryDealGetDouble(deal,DEAL_COMMISSION)
                      +HistoryDealGetDouble(deal,DEAL_SWAP)+HistoryDealGetDouble(deal,DEAL_FEE);
   const double d_vol=HistoryDealGetDouble(deal,DEAL_VOLUME);
   if(!PlSoundMine(deal,pid)) return;                       // the same sign of "ours" as the counter and the sound: the magic or a record
   if(!HistorySelectByPosition(pid)) return;
   double vol_in=0.0, vol_out=0.0, net=0.0, cf=0.0;
   bool seen=false, inout=false;
   ulong in_tk[]; int nin=0;
   const int nd=HistoryDealsTotal();
   for(int i=0;i<nd;i++)
     {
      const ulong tk=HistoryDealGetTicket(i);
      if(tk==0) continue;
      const long ty=HistoryDealGetInteger(tk,DEAL_TYPE);
      if(ty!=DEAL_TYPE_BUY && ty!=DEAL_TYPE_SELL) continue;
      const long en=HistoryDealGetInteger(tk,DEAL_ENTRY);
      if(en==DEAL_ENTRY_INOUT) inout=true;
      const double v=HistoryDealGetDouble(tk,DEAL_VOLUME);
      if(en==DEAL_ENTRY_IN) { vol_in+=v; ArrayResize(in_tk,nin+1); in_tk[nin]=tk; nin++; }
      else if(en==DEAL_ENTRY_OUT || en==DEAL_ENTRY_OUT_BY) vol_out+=v;
      if(tk==deal) seen=true;
      const double c=HistoryDealGetDouble(tk,DEAL_COMMISSION)+HistoryDealGetDouble(tk,DEAL_FEE);
      cf+=c;
      net+=HistoryDealGetDouble(tk,DEAL_PROFIT)+HistoryDealGetDouble(tk,DEAL_SWAP)+c;
     }
   if(inout) return;                                        // a netting reversal mixes two positions in one deal: no honest result of one
   if(!seen)                                                // the history did not have the deal yet: count it from its own numbers
     {
      vol_out+=d_vol;
      net+=d_net; cf+=HistoryDealGetDouble(deal,DEAL_COMMISSION)+HistoryDealGetDouble(deal,DEAL_FEE);
     }
   const double step=SymbolInfoDouble(sym,SYMBOL_VOLUME_STEP);
   const double eps=(step>0.0)?step*0.5:1e-8;
   const bool closed=(vol_in-vol_out<=eps);
   const string cur=AccountInfoString(ACCOUNT_CURRENCY);
   const int cd=(int)AccountInfoInteger(ACCOUNT_CURRENCY_DIGITS);
   double r=0.0, risk0=0.0;
   bool has_r=false, no_sl=false, calc_fail=false;
   if(closed)
     {
      //--- the initial risk: the loss of every entered volume from its price to the SL of its entry deal
      const int k=PlRecIndex(pid);
      for(int j=0;j<nin;j++)
        {
         const ulong tk=in_tk[j];
         double sl=HistoryDealGetDouble(tk,DEAL_SL);
         if(sl<=0.0 && k>=0 && g_rec[k].sl0>0.0) sl=g_rec[k].sl0;
         if(sl<=0.0) { no_sl=true; break; }
         const long ty=HistoryDealGetInteger(tk,DEAL_TYPE);
         double p=0.0;
         if(!OrderCalcProfit(ty==DEAL_TYPE_BUY?ORDER_TYPE_BUY:ORDER_TYPE_SELL,sym,HistoryDealGetDouble(tk,DEAL_VOLUME),
                             HistoryDealGetDouble(tk,DEAL_PRICE),sl,p))
           { calc_fail=true; break; }
         risk0+=MathMax(0.0,-p);
        }
      if(!no_sl && !calc_fail)
        {
         risk0+=MathAbs(cf);
         if(risk0>PL_EPS) { r=net/risk0; has_r=true; }
        }
     }
   const double shown=closed?net:d_net;
   string t=PlCloseText(reason,closed,has_r,r,no_sl,shown,cur,cd);
   if(sym!="" && sym!=_Symbol) t=sym+": "+t;                // another chart's symbol: the header does not name it
   PLDBG("CLOSESUM deal="+(string)deal+" pos="+(string)pid+" sym="+sym+" reason="+(string)reason+" closed="+(string)closed
         +" vol_in="+DoubleToString(vol_in,4)+" vol_out="+DoubleToString(vol_out,4)+" net="+DoubleToString(net,2)+" comm_fee="+DoubleToString(cf,2)
         +" risk0="+DoubleToString(risk0,2)+" R="+(has_r?DoubleToString(r,3):"-")+" no_sl="+(string)no_sl+" phrase='"+t+"'");
   //--- a close that rounds to 0.0R is no win and no loss: the neutral colour, not the red of a few cents of cost
   const bool flat=(closed && has_r && MathAbs(r)<0.05);
   PlMessageSticky(t,flat?0:(shown>0.005)?3:(shown<-0.005)?4:0);
   PlBulkNet(pid,closed,net);
  }

#endif
