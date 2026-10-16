// Required Notice: Copyright 2026 stop-loss-enjoyer
// Plainlines is source-available under the PolyForm Shield License 1.0.0.
//
// Rounding and comparison helpers of the calculation core. Pure functions, no terminal calls.
// Every comparison uses PL_EPS; no (int)MathPow(10,digits) anywhere.
#property strict

#ifndef PL_CORE_NUM_MQH
#define PL_CORE_NUM_MQH

#include "Types.mqh"

//--- FNV-1a checksums: an integrity check of a file and a stable profile id, not security.
//--- One step per UTF-16 code unit of the string; the unsigned arithmetic wraps.
uint PlFnv32(const string s)
  {
   uint h=2166136261;
   const int n=StringLen(s);
   for(int i=0; i<n; i++)
     {
      h^=(uint)StringGetCharacter(s,i);
      h*=16777619;
     }
   return h;
  }

string PlHexOf(const ulong v,const int digits)
  {
   const string al="0123456789abcdef";
   string r="";
   for(int i=digits-1; i>=0; i--)
      r+=StringSubstr(al,(int)((v>>(4*i))&0xF),1);
   return r;
  }

string PlFnv32Hex(const string s)
  {
   return PlHexOf((ulong)PlFnv32(s),8);
  }

string PlFnv64Hex(const string s)
  {
   ulong h=0xcbf29ce484222325;
   const int n=StringLen(s);
   for(int i=0; i<n; i++)
     {
      h^=(ulong)StringGetCharacter(s,i);
      h*=0x100000001b3;
     }
   return PlHexOf(h,16);
  }

//--- 10^digits as a double (digits clamped to 0..15)
double PlPow10(const int digits)
  {
   int d=digits;
   if(d<0) d=0;
   if(d>15) d=15;
   double p=1.0;
   for(int i=0; i<d; i++)
      p*=10.0;
   return p;
  }

//--- number of decimals of a step such as 0.01 or 0.5 (0 for 1, 2 for 0.01), at most 8
int PlStepDigits(const double step)
  {
   if(step<=0.0)
      return 2;
   double x=step;
   int d=0;
   while(d<8 && MathAbs(x-MathRound(x))>1e-9*MathMax(1.0,MathAbs(x)))
     {
      x*=10.0;
      d++;
     }
   return d;
  }

//--- round to a number of decimals (half away from zero), tolerant to binary noise
double PlRoundDigits(const double x,const int digits)
  {
   const double p=PlPow10(digits);
   return MathRound(x*p)/p;
  }

//--- floor to a number of decimals; value that is a hair below an exact decimal counts as exact
double PlFloorDigits(const double x,const int digits)
  {
   const double p=PlPow10(digits);
   return MathFloor(x*p+1e-7)/p;
  }

//--- floor to a multiple of step (step > 0), tolerant at the boundary
double PlFloorStep(const double x,const double step)
  {
   if(step<=0.0)
      return x;
   return PlRoundDigits(MathFloor(x/step+1e-8)*step,PlStepDigits(step));
  }

//--- price to the nearest tick, then to the symbol digits
double PlTickNearest(const double price,const double tick,const int digits)
  {
   if(tick<=0.0)
      return NormalizeDouble(price,digits);
   return NormalizeDouble(MathRound(price/tick)*tick,digits);
  }

//--- price up to a tick (ceil), tolerant to binary noise
double PlTickUp(const double price,const double tick,const int digits)
  {
   if(tick<=0.0)
      return NormalizeDouble(price,digits);
   return NormalizeDouble(MathCeil(price/tick-1e-6)*tick,digits);
  }

//--- price down to a tick (floor), tolerant to binary noise
double PlTickDown(const double price,const double tick,const int digits)
  {
   if(tick<=0.0)
      return NormalizeDouble(price,digits);
   return NormalizeDouble(MathFloor(price/tick+1e-6)*tick,digits);
  }

//--- StopsLevel with one point of margin: the reference sample (mql5.com/en/articles/2555) uses a strict ">", so a distance
//--- equal to the level is refused. 0 means the broker sets no level.
bool PlStopsTooClose(const double d,const int stops_level,const double point)
  {
   return (stops_level>0 && d<((double)stops_level+1.0)*point-PL_EPS);
  }

//--- the unit of SL and TP distances: a pip for Forex symbols with 3 or 5 digits, the point otherwise (one rule for the panel and the trailing)
bool PlIsForexMode(const ENUM_SYMBOL_CALC_MODE mode)
  {
   return (mode==SYMBOL_CALC_MODE_FOREX || mode==SYMBOL_CALC_MODE_FOREX_NO_LEVERAGE);
  }

double PlPipFrom(const double point,const int digits,const ENUM_SYMBOL_CALC_MODE mode)
  {
   if(PlIsForexMode(mode) && (digits==3 || digits==5)) return point*10.0;
   return point;
  }

//--- Is the second of the day inside one of the session rows of a day? SymbolInfoSessionTrade from/to are seconds
//--- from 00:00 and the date part is ignored (mql5 docs). Real data: FTMO CORN.c, SOYBEAN.c and WHEAT.c
//--- have Mon-Fri [00:00-00:00, 03:05-15:45, 16:35-21:20] and Bybit GER40 [00:00-00:00, 00:00-00:00, 03:15-00:00]:
//--- a row with from==to is an empty slot, never a whole day (a whole-day reading would make the other rows meaningless).
//--- to==00:00 with from>0 means until midnight. A row that ends past midnight with to>0 is undocumented: counted as closed.
//--- The one exception: a day with exactly ONE row 00:00 to 24:00 (raw to=86400) is the whole day. MetaQuotes-Demo, the default
//--- server of a new MT5, gives EURUSD that row on every weekday (demo stand 15.10.2026); in the probes of Bybit and FTMO a
//--- single 00:00-00:00 day exists only on USTUSD, which cannot be traded, and the empty slots always sit next to other rows.
bool PlSessionRowsOpen(const long &from[],const long &to[],const int n,const int sod)
  {
   if(n==1 && from[0]==0 && to[0]==86400) return (sod>=0 && sod<86400);
   for(int i=0;i<n;i++)
     {
      const int f=(int)(from[i]%86400);
      int t=(int)(to[i]%86400);
      if(f==t) continue;
      if(t==0) t=86400;
      if(t<f) continue;
      if(sod>=f && sod<t) return true;
     }
   return false;
  }

#endif
