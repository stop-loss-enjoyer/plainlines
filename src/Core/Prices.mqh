// Required Notice: Copyright 2026 stop-loss-enjoyer
// Plainlines is source-available under the PolyForm Shield License 1.0.0.
//
// Step 1 of the core: side, order type, normalized prices, distance.
// Pure function of its arguments, never calls the terminal.
#property strict

#ifndef PL_CORE_PRICES_MQH
#define PL_CORE_PRICES_MQH

#include "Types.mqh"
#include "Num.mqh"

//--- keep the reason that comes first in the PlReason enum (the more basic problem)
void PlPlanReason(PlPlan &p,const PlReason r)
  {
   if(p.reason==PL_R_NONE || (int)r<(int)p.reason)
      p.reason=r;
  }

int PlKindMask(const PlKind k)
  {
   switch(k)
     {
      case PL_KIND_MARKET:     return 1;   // SYMBOL_ORDER_MODE_MARKET
      case PL_KIND_LIMIT:      return 2;   // SYMBOL_ORDER_MODE_LIMIT
      case PL_KIND_STOP:       return 4;   // SYMBOL_ORDER_MODE_STOP
      case PL_KIND_STOP_LIMIT: return 8;   // SYMBOL_ORDER_MODE_STOP_LIMIT
     }
   return 0;
  }

//--- ok=false only when nothing more can be computed; other problems set out.reason and keep ok
bool PlPrepare(const PlInputs &in,const PlSymbol &s,PlPlan &out)
  {
   out.ok=false;
   out.reason=PL_R_NONE;
   out.side=PL_SIDE_NONE;
   out.order_type=-1;
   out.entry=0.0;
   out.exec=0.0;
   out.sl=0.0;
   out.limit=0.0;
   out.dist=0.0;
   out.ticks=0;
   for(int i=0; i<PL_MAX_TP; i++)
      out.tp[i]=0.0;

   if(s.bid<=0.0 || s.ask<=0.0)
     {
      out.reason=PL_R_NO_QUOTE;
      return false;
     }
   if(s.tick_size<=0.0 || s.tick_value_loss<=0.0 || s.contract<=0.0)
     {
      out.reason=PL_R_NO_SYMBOL_DATA;
      return false;
     }

   const double tick=s.tick_size;
   const int    dg=s.digits;

   //--- price the SL (or TP without SL) is compared with, by kind
   double cmp=(s.bid+s.ask)/2.0;
   if(in.kind==PL_KIND_LIMIT || in.kind==PL_KIND_STOP)
      cmp=PlTickNearest(in.entry,tick,dg);
   else if(in.kind==PL_KIND_STOP_LIMIT)
      cmp=PlTickNearest(in.limit,tick,dg);

   //--- side
   if(!in.no_sl)
     {
      if(in.sl<=0.0)
        {
         out.reason=PL_R_NO_SL;
         return false;
        }
      if(in.sl<cmp-PL_EPS)
         out.side=PL_SIDE_BUY;
      else if(in.sl>cmp+PL_EPS)
         out.side=PL_SIDE_SELL;
      else
        {
         out.reason=PL_R_SL_WRONG_SIDE;
         return false;
        }
     }
   else
     {
      //--- no SL: the side comes from the first TP given as a price
      if(!in.no_tp && in.tp[0].on && in.tp[0].mode==PL_TP_PRICE && in.tp[0].price>0.0
         && MathAbs(in.tp[0].price-cmp)>PL_EPS)
         out.side=(in.tp[0].price>cmp)?PL_SIDE_BUY:PL_SIDE_SELL;
      else
        {
         out.reason=PL_R_NO_SL;
         return false;
        }
     }
   const bool buy=(out.side==PL_SIDE_BUY);

   //--- order type allowed by the broker
   if((s.order_mode&PlKindMask(in.kind))==0)
      PlPlanReason(out,PL_R_KIND_NOT_ALLOWED);

   //--- execution price and order type
   switch(in.kind)
     {
      case PL_KIND_MARKET:
         out.entry=buy?s.ask:s.bid;
         out.exec=out.entry;
         out.order_type=buy?ORDER_TYPE_BUY:ORDER_TYPE_SELL;
         break;
      case PL_KIND_LIMIT:
         out.entry=PlTickNearest(in.entry,tick,dg);
         out.exec=out.entry;
         out.order_type=buy?ORDER_TYPE_BUY_LIMIT:ORDER_TYPE_SELL_LIMIT;
         if(buy?(out.entry>=s.ask-PL_EPS):(out.entry<=s.bid+PL_EPS))
            PlPlanReason(out,PL_R_ENTRY_WRONG_SIDE);
         break;
      case PL_KIND_STOP:
         out.entry=PlTickNearest(in.entry,tick,dg);
         out.exec=out.entry;
         out.order_type=buy?ORDER_TYPE_BUY_STOP:ORDER_TYPE_SELL_STOP;
         if(buy?(out.entry<=s.ask+PL_EPS):(out.entry>=s.bid-PL_EPS))
            PlPlanReason(out,PL_R_ENTRY_WRONG_SIDE);
         break;
      default:
         out.entry=PlTickNearest(in.entry,tick,dg);
         out.limit=PlTickNearest(in.limit,tick,dg);
         out.exec=out.limit;
         out.order_type=buy?ORDER_TYPE_BUY_STOP_LIMIT:ORDER_TYPE_SELL_STOP_LIMIT;
         //--- both a trigger on the wrong side of the market and a limit past the trigger are refused
         if(buy?(out.entry<=s.ask+PL_EPS):(out.entry>=s.bid-PL_EPS))
            PlPlanReason(out,PL_R_LIMIT_WRONG_SIDE);
         if(buy?(out.limit>out.entry+PL_EPS):(out.limit<out.entry-PL_EPS))
            PlPlanReason(out,PL_R_LIMIT_WRONG_SIDE);
         break;
     }

   //--- a pending entry keeps the broker distance from Ask (buys) or Bid (sells), measured in the plan so the user sees the
   //--- refusal before pressing
   if(in.kind!=PL_KIND_MARKET)
     {
      const double ref=buy?s.ask:s.bid;
      if(PlStopsTooClose(MathAbs(out.entry-ref),s.stops_level,s.point))
         PlPlanReason(out,PL_R_ENTRY_TOO_CLOSE);
      if(in.kind==PL_KIND_STOP_LIMIT && PlStopsTooClose(MathAbs(out.limit-out.entry),s.stops_level,s.point))
         PlPlanReason(out,PL_R_ENTRY_TOO_CLOSE);     // no source, conservative, unverified
     }

   //--- SL: normalized toward the price (Buy up, Sell down); the ATR stop is set from exec
   if(!in.no_sl)
     {
      double raw=in.sl;
      if(in.atr_on && !(in.atr>0.0 && in.atr_mult>0.0))
        {
         out.reason=PL_R_ATR_NOT_READY;     // never fall back to the old SL under an ATR label
         return false;
        }
      if(in.atr_on)
         raw=buy?(out.exec-in.atr*in.atr_mult):(out.exec+in.atr*in.atr_mult);
      out.sl=buy?PlTickUp(raw,tick,dg):PlTickDown(raw,tick,dg);
      //--- signed distance: market Buy Ask-SL, Sell SL-Bid (spread inside), pending by side
      out.dist=buy?(out.exec-out.sl):(out.sl-out.exec);
      if(out.dist<=PL_EPS)
        {
         out.reason=PL_R_SL_WRONG_SIDE;
         return false;
        }
      out.ticks=(long)MathRound(out.dist/tick);
      //--- the broker measures StopsLevel from the closing price: for a market order that is the distance
      //--- without the spread (Buy Bid-SL, Sell SL-Ask), for a pending order the distance from the price
      const double mind=MathMax(2.0*(s.ask-s.bid),3.0*tick);
      const double closing=(in.kind==PL_KIND_MARKET)?out.dist-(s.ask-s.bid):out.dist;
      if(out.dist<mind-PL_EPS || PlStopsTooClose(closing,s.stops_level,s.point))
         PlPlanReason(out,PL_R_SL_TOO_CLOSE);
     }

   //--- take profits
   for(int i=0; i<PL_MAX_TP; i++)
     {
      if(in.no_tp || !in.tp[i].on)
         continue;
      double p=0.0;
      if(in.tp[i].mode==PL_TP_R)
        {
         if(in.no_sl || in.tp[i].r<=0.0)
            continue;
         const double d=MathAbs(out.exec-out.sl);
         p=buy?(out.exec+in.tp[i].r*d):(out.exec-in.tp[i].r*d);
        }
      else
         p=in.tp[i].price;
      if(p<=0.0)
         continue;
      p=PlTickNearest(p,tick,dg);
      out.tp[i]=p;
      if(buy?(p<=out.exec+PL_EPS):(p>=out.exec-PL_EPS))
         PlPlanReason(out,PL_R_TP_WRONG_SIDE);
      else if(s.stops_level>0)
        {
         //--- market order: from the closing price (Buy TP-Bid, Sell Ask-TP), pending: from the order price
         double tpd=MathAbs(p-out.exec);
         if(in.kind==PL_KIND_MARKET)
            tpd=buy?(p-s.bid):(s.ask-p);
         if(in.kind==PL_KIND_STOP_LIMIT)
            tpd=MathMin(tpd,MathAbs(p-out.entry));      // a stop-limit TP keeps the level from both prices
         if(PlStopsTooClose(tpd,s.stops_level,s.point))
            PlPlanReason(out,PL_R_TP_TOO_CLOSE);
        }
     }

   out.ok=true;
   return true;
  }

#endif
