// Required Notice: Copyright 2026 stop-loss-enjoyer
// Plainlines is source-available under the PolyForm Shield License 1.0.0.
//
// Input fields: a pool of OBJ_EDIT objects laid over the canvas, strict number parsing, and the
// mapping between each field and the model (text shown, value applied). A wrong entry changes
// nothing: the field gets a red frame and PL_R_BAD_INPUT shows in the status.
#property strict

#ifndef PL_UI_FIELDS_MQH
#define PL_UI_FIELDS_MQH

enum PlField
  {
   PLF_RISK=0, PLF_LOT, PLF_ENTRY, PLF_LIMIT, PLF_SL_PRICE, PLF_SL_PIPS, PLF_TP_PRICE, PLF_TP_PIPS, PLF_TP_R,
   PLF_COMM_RATE, PLF_CAP, PLF_CONF_ABOVE, PLF_ATR_MULT, PLF_ATR_PERIOD,
   PLF_TP2_R, PLF_TP2_SHARE, PLF_TP3_R, PLF_TP3_SHARE, PLF_MAGIC, PLF_COMMENT, PLF_EXP_HOURS, PLF_MAX_SPREAD,
   PLF_BE_R,
   PLF_RESERVED1, PLF_RESERVED2, PLF_RESERVED3,     // reserved ids: the numbers of the other fields stay as they are
   PLF_PORT_CAP, PLF_MAX_OPEN, PLF_MAX_DAY, PLF_MARGIN_USE, PLF_TRAIL_PIPS, PLF_PART_PCT,
   PLF_COUNT
  };

//--- names used in the "Not a number in ..." status
string PlFieldTitle(const int id)
  {
   switch(id)
     {
      case PLF_RISK: return PLS_RISK;           case PLF_LOT: return PLS_LOT;
      case PLF_ENTRY: return PLS_ENTRY;         case PLF_LIMIT: return PLS_KIND_LIMIT;
      case PLF_SL_PRICE: return PLS_SL;         case PLF_SL_PIPS: return PLS_SL_DISTANCE;
      case PLF_TP_PRICE: return PLS_TP;         case PLF_TP_PIPS: return PLS_TP_DISTANCE;
      case PLF_TP_R: return "R";              case PLF_COMM_RATE: return PLS_C_COMM;
      case PLF_CAP: return PLS_HARD_CAP;        case PLF_CONF_ABOVE: return PLS_CONFIRM_ABOVE;
      case PLF_ATR_MULT: return PLS_ATR_MULTIPLIER; case PLF_ATR_PERIOD: return PLS_ATR_PERIOD;
      case PLF_TP2_R: return PLS_TP2_R;         case PLF_TP2_SHARE: return PLS_TP2_SHARE;
      case PLF_TP3_R: return PLS_TP3_R;         case PLF_TP3_SHARE: return PLS_TP3_SHARE;
      case PLF_MAGIC: return PLS_MAGIC;         case PLF_COMMENT: return PLS_COMMENT;
      case PLF_EXP_HOURS: return PLS_EXPIRY_HOURS; case PLF_MAX_SPREAD: return PLS_MAX_SPREAD;
      case PLF_BE_R: return PLS_BREAKEVEN_R;    
      case PLF_PORT_CAP: return PLS_MAX_TOTAL_RISK;   case PLF_MAX_OPEN: return PLS_MAX_OPEN_TRADES;
      case PLF_MAX_DAY: return PLS_MAX_TRADES_A_DAY;  case PLF_MARGIN_USE: return PLS_MARGIN_USE;
      case PLF_TRAIL_PIPS: return PLS_TRAIL_PIPS;     case PLF_PART_PCT: return PLS_PARTIAL_CLOSE;
     }
   return "field";
  }

//--- the edit pool -----------------------------------------------------------------------------
bool   g_fl_bad[PLF_COUNT];        // last entry was not accepted
string g_fl_note="";               // why the last typed value was refused, "" = not a number
bool   g_fl_used[PLF_COUNT];       // placed in the current layout
bool   g_fl_vis[PLF_COUNT];        // currently visible on the chart
bool   g_fl_made[PLF_COUNT];
string g_fl_text[PLF_COUNT];       // text last written into the object
int    g_fl_x[PLF_COUNT];          // panel-relative pixel rect
int    g_fl_y[PLF_COUNT];
int    g_fl_w[PLF_COUNT];
int    g_fl_h[PLF_COUNT];
string g_fl_new[PLF_COUNT];        // text wanted by the layout
bool   g_fl_left[PLF_COUNT];       // left aligned (text fields)
int    g_fl_pt[PLF_COUNT];         // font size in points of this edit; 0 = the panel default (g_fl_font10/10)
int    g_fl_focus=-1;
int    g_fl_font10=95;             // edit font in tenths of a point, set by the panel
string g_fl_font="Segoe UI";

string PlFldName(const int id) { return "PL_F"+IntegerToString(id); }

int PlFldFromName(const string nm)
  {
   if(StringFind(nm,"PL_F")!=0) return -1;
   string r=StringSubstr(nm,4);
   int v=(int)StringToInteger(r);
   if(v<0 || v>=PLF_COUNT || IntegerToString(v)!=r) return -1;
   return v;
  }

void PlFldInit()
  {
   for(int i=0;i<PLF_COUNT;i++)
     {
      g_fl_bad[i]=false; g_fl_used[i]=false; g_fl_vis[i]=false; g_fl_made[i]=false; g_fl_text[i]="~"; g_fl_left[i]=false; g_fl_pt[i]=0;
      g_fl_x[i]=0; g_fl_y[i]=0; g_fl_w[i]=10; g_fl_h[i]=10; g_fl_new[i]="";
     }
   g_fl_focus=-1;
  }

void PlFldStyle(const int id)
  {
   string nm=PlFldName(id);
   ObjectSetString(0,nm,OBJPROP_FONT,g_fl_font);
   ObjectSetInteger(0,nm,OBJPROP_FONTSIZE,(g_fl_pt[id]>0)?g_fl_pt[id]:g_fl_font10/10);
   ObjectSetInteger(0,nm,OBJPROP_BGCOLOR,g_th.bg);
   ObjectSetInteger(0,nm,OBJPROP_BORDER_COLOR,g_th.bg);
   ObjectSetInteger(0,nm,OBJPROP_COLOR,g_th.text);
   ObjectSetInteger(0,nm,OBJPROP_ALIGN,g_fl_left[id]?ALIGN_LEFT:ALIGN_RIGHT);
  }

void PlFldRestyleAll()
  {
   for(int i=0;i<PLF_COUNT;i++) if(g_fl_made[i]) PlFldStyle(i);
  }

void PlFldCreate(const int id)
  {
   string nm=PlFldName(id);
   ObjectDelete(0,nm);
   if(!ObjectCreate(0,nm,OBJ_EDIT,0,0,0)) return;
   ObjectSetInteger(0,nm,OBJPROP_READONLY,false);
   ObjectSetInteger(0,nm,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,nm,OBJPROP_HIDDEN,true);
   ObjectSetInteger(0,nm,OBJPROP_ZORDER,10);
   ObjectSetInteger(0,nm,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,nm,OBJPROP_TIMEFRAMES,OBJ_NO_PERIODS);
   g_fl_made[id]=true; g_fl_text[id]="~"; g_fl_vis[id]=false;
   PlFldStyle(id);
  }

void PlFldDeleteAll()
  {
   for(int i=0;i<PLF_COUNT;i++) { ObjectDelete(0,PlFldName(i)); g_fl_made[i]=false; g_fl_vis[i]=false; }
   g_fl_focus=-1;      // the edits are gone: no ENDEDIT can come; recreated edits show the model value
  }

void PlFldBegin()
  {
   for(int i=0;i<PLF_COUNT;i++) g_fl_used[i]=false;
  }

//--- register a field in the current layout (panel-relative pixels)
void PlFldReg(const int id,const int x,const int y,const int w,const int h,const string text,const bool left=false,const int pt=0)
  {
   if(id<0 || id>=PLF_COUNT) return;
   g_fl_used[id]=true;
   if(g_fl_pt[id]!=pt) { g_fl_pt[id]=pt; if(g_fl_made[id]) PlFldStyle(id); }
   g_fl_x[id]=x; g_fl_y[id]=y; g_fl_w[id]=w; g_fl_h[id]=h;
   g_fl_new[id]=text;
   if(g_fl_left[id]!=left) { g_fl_left[id]=left; if(g_fl_made[id]) PlFldStyle(id); }
  }

//--- put every registered edit where the layout says, hide the others
void PlFldCommit(const int px,const int py)
  {
   for(int i=0;i<PLF_COUNT;i++)
     {
      string nm=PlFldName(i);
      if(!g_fl_used[i])
        {
         if(g_fl_vis[i]) { ObjectSetInteger(0,nm,OBJPROP_TIMEFRAMES,OBJ_NO_PERIODS); g_fl_vis[i]=false; }
         if(g_fl_focus==i) { g_fl_focus=-1; g_fl_text[i]="~"; }     // hidden while typed in: no ENDEDIT will come, show the model value when it returns
         continue;
        }
      if(!g_fl_made[i] || ObjectFind(0,nm)<0) PlFldCreate(i);
      ObjectSetInteger(0,nm,OBJPROP_XDISTANCE,px+g_fl_x[i]);
      ObjectSetInteger(0,nm,OBJPROP_YDISTANCE,py+g_fl_y[i]);
      ObjectSetInteger(0,nm,OBJPROP_XSIZE,g_fl_w[i]);
      ObjectSetInteger(0,nm,OBJPROP_YSIZE,g_fl_h[i]);
      //--- never overwrite what the user is typing, or a rejected entry
      bool keep=(g_fl_focus==i) || g_fl_bad[i];
      if(!keep && g_fl_text[i]!=g_fl_new[i])
        {
         ObjectSetString(0,nm,OBJPROP_TEXT,g_fl_new[i]);
         g_fl_text[i]=g_fl_new[i];
        }
      if(!g_fl_vis[i]) { ObjectSetInteger(0,nm,OBJPROP_TIMEFRAMES,OBJ_ALL_PERIODS); g_fl_vis[i]=true; }
     }
  }

//--- only the position (panel dragged)
void PlFldMove(const int px,const int py)
  {
   for(int i=0;i<PLF_COUNT;i++)
     {
      if(!g_fl_used[i] || !g_fl_vis[i]) continue;
      string nm=PlFldName(i);
      ObjectSetInteger(0,nm,OBJPROP_XDISTANCE,px+g_fl_x[i]);
      ObjectSetInteger(0,nm,OBJPROP_YDISTANCE,py+g_fl_y[i]);
     }
  }

string PlFldGetText(const int id)
  {
   return ObjectGetString(0,PlFldName(id),OBJPROP_TEXT);
  }

bool PlAnyBadField()
  {
   for(int i=0;i<PLF_COUNT;i++) if(g_fl_bad[i]) return true;
   return false;
  }

//--- a view changed: red marks of fields that are no longer on screen would stay for good
void PlFldClearBad()
  {
   g_fl_note="";
   for(int i=0;i<PLF_COUNT;i++) if(g_fl_bad[i]) { g_fl_bad[i]=false; g_fl_text[i]="~"; }
  }

//--- a comma is always the decimal point; the panel never writes a thousands separator (REV ui-2).
//--- No comma: as is. Exactly one comma and no dot: the comma becomes the dot. Anything else with a comma: not a number.
bool PlNormalizeSeparators(const string raw,string &out)
  {
   string s=raw;
   int commas=0, dots=0;
   int n=StringLen(s);
   for(int i=0;i<n;i++)
     {
      ushort c=StringGetCharacter(s,i);
      if(c==',') commas++;
      else if(c=='.') dots++;
     }
   if(commas==0) { out=s; return true; }
   if(commas==1 && dots==0)
     {
      StringReplace(s,",",".");
      out=s;
      return true;
     }
   return false;
  }

//--- typed prices must sit between half and twice the mid price
bool PlPriceSane(const double p)
  {
   const double mid=(g_sym.ask+g_sym.bid)/2.0;
   if(mid<=0.0) { g_fl_note=PlReasonText(PL_R_NO_QUOTE); return false; }
   if(p>=mid*0.5 && p<=mid*2.0) return true;
   g_fl_note=PLS_PRICE_FAR;
   return false;
  }

//--- strict number: optional sign, digits, one separator, nothing else
bool PlParseNum(const string raw,double &v)
  {
   string s0=raw;
   StringTrimLeft(s0); StringTrimRight(s0);
   string s;
   if(!PlNormalizeSeparators(s0,s)) return false;
   int n=StringLen(s);
   if(n==0 || n>24) return false;
   int digits=0, dots=0;
   for(int i=0;i<n;i++)
     {
      ushort c=StringGetCharacter(s,i);
      if(c>='0' && c<='9') { digits++; continue; }
      if(c=='.') { dots++; if(dots>1) return false; continue; }
      if((c=='-' || c=='+') && i==0) continue;
      return false;
     }
   if(digits==0) return false;
   v=StringToDouble(s);
   return true;
  }

bool PlParseInt(const string raw,long &v)
  {
   string s=raw;
   StringTrimLeft(s); StringTrimRight(s);
   int n=StringLen(s);
   if(n==0 || n>15) return false;
   for(int i=0;i<n;i++)
     {
      ushort c=StringGetCharacter(s,i);
      if(c<'0' || c>'9') return false;
     }
   v=StringToInteger(s);
   return true;
  }

//--- 2.0, 2.5, 2.25 (at least one decimal, at most two)
string PlTrimNum(const double v)
  {
   string s=DoubleToString(v,2);
   if(StringGetCharacter(s,StringLen(s)-1)=='0') s=StringSubstr(s,0,StringLen(s)-1);
   return s;
  }

//--- the model changed: recalc, push to the lines, redraw (implemented in Plainlines.mq5)
void PlModelChanged();
//--- the order type follows a moved Entry or SL (implemented in Plainlines.mq5)
void PlAutoKind(const bool entry_moved,const bool snap,const double tol);
double PlMarketTol();

//--- estimates the controller needs before the core runs ----------------------------------------
double PlEstExec()
  {
   double mid=(g_sym.ask+g_sym.bid)/2.0;
   switch(g_dr.kind)
     {
      case PL_KIND_LIMIT:
      case PL_KIND_STOP:       return g_px.entry;
      case PL_KIND_STOP_LIMIT: return g_px.limit;
     }
   //--- market: Ask for a buy (SL below the middle), Bid for a sell
   return (g_px.sl<mid || g_px.sl<=0.0)?g_sym.ask:g_sym.bid;
  }

//--- +1 buy, -1 sell, by the SL against the reference price
int PlEstDir()
  {
   double mid=(g_sym.ask+g_sym.bid)/2.0;
   double ref=mid;
   if(g_dr.kind==PL_KIND_LIMIT || g_dr.kind==PL_KIND_STOP) ref=g_px.entry;
   if(g_dr.kind==PL_KIND_STOP_LIMIT) ref=g_px.limit;
   if(g_px.sl>ref) return -1;
   return 1;
  }

//--- the trader sets the SL (its line, its price tag, the SL field): the TPs stay where they are (PlTpHold). Only when the SL went
//--- through the entry the side turns and no TP of the old side can stand: then each TP goes to the other side of the entry at the
//--- same distance (mirrored around the price the side is judged by, PlEstDir), and stays there while the drag goes on. A mirror
//--- at or below zero falls back to its R on the new side, as on the first lines.
void PlSlMovedTo(const double sl)
  {
   const int before=PlEstDir();
   PlTpHold();
   g_px.sl=sl;
   if(PlEstDir()==before)
      return;
   double ref=(g_sym.ask+g_sym.bid)/2.0;
   if(g_dr.kind==PL_KIND_LIMIT || g_dr.kind==PL_KIND_STOP) ref=g_px.entry;
   if(g_dr.kind==PL_KIND_STOP_LIMIT) ref=g_px.limit;
   for(int i=0;i<PL_MAX_TP;i++)
     {
      if(g_px.tp[i]<=0.0) continue;
      const double m=PlTickRound(2.0*ref-g_px.tp[i]);
      if(m>0.0) g_px.tp[i]=m;
      else g_dr.tp_price[i]=false;
     }
  }

double PlTickRound(const double p)
  {
   if(g_sym.tick_size<=0.0) return p;
   return NormalizeDouble(MathRound(p/g_sym.tick_size)*g_sym.tick_size,g_sym.digits);
  }

int PlLotDigits()
  {
   return PlStepDigits(g_sym.vol_step);
  }

//--- distance in the chosen unit (pip or point) for a price distance
double PlToUnit(const double dist) { double u=PlPipSize(g_sym); return (u>0.0)?dist/u:0.0; }
//--- values from 1000 drop the decimal: "1040.0" is 6 characters and the 46 px point field holds 5
string PlFmtUnitField(const double v) { return DoubleToString(v,(MathAbs(v)>=1000.0)?0:1); }

//--- text for each field --------------------------------------------------------------------------
//--- the R of TP i as its line stands now (a TP is a price once placed: the SL or the price may have moved since);
//--- the stored R only while the TP has no price yet
double PlTpRShown(const int i,const double exec)
  {
   if(!g_dr.tp_price[i]) return g_dr.tp_r[i];
   const double d=MathAbs(exec-g_px.sl);
   return (d>PL_EPS && g_px.tp[i]>0.0)?MathAbs(g_px.tp[i]-exec)/d:0.0;
  }

string PlFieldText(const int id)
  {
   int dg=g_sym.digits;
   double exec=(g_plan.ok && g_plan.exec>0.0)?g_plan.exec:PlEstExec();
   switch(id)
     {
      case PLF_RISK:      return g_dr.unit_money?DoubleToString(g_dr.risk_money,g_acc.currency_digits):DoubleToString(g_dr.risk_pct,2);
      case PLF_LOT:       return DoubleToString(g_cfg.lot_fixed,PlLotDigits());
      case PLF_ENTRY:     return DoubleToString(g_px.entry,dg);
      case PLF_LIMIT:     return DoubleToString(g_px.limit,dg);
      case PLF_SL_PRICE:  return DoubleToString(g_px.sl,dg);
      case PLF_SL_PIPS:   return PlFmtUnitField(PlToUnit(MathAbs(exec-g_px.sl)));
      case PLF_TP_PRICE:  return DoubleToString(g_px.tp[0],dg);
      case PLF_TP_PIPS:   return PlFmtUnitField(PlToUnit(MathAbs(g_px.tp[0]-exec)));
      case PLF_TP_R:      return PlTrimNum(PlTpRShown(0,exec));
      case PLF_COMM_RATE: return DoubleToString(g_dr.comm.rate,(g_dr.comm.kind==PL_COMM_PERCENT_SIDE)?4:2);
      case PLF_CAP:       return DoubleToString(g_cfg.cap,1);
      case PLF_CONF_ABOVE:return DoubleToString(g_cfg.confirm_above,1);
      case PLF_ATR_MULT:  return PlTrimNum(g_cfg.atr_mult);
      case PLF_ATR_PERIOD:return IntegerToString(g_cfg.atr_period);
      case PLF_TP2_R:     return PlTrimNum(PlTpRShown(1,exec));
      case PLF_TP2_SHARE: return DoubleToString(g_cfg.tp_share2,0);
      case PLF_TP3_R:     return PlTrimNum(PlTpRShown(2,exec));
      case PLF_TP3_SHARE: return DoubleToString(g_cfg.tp_share3,0);
      case PLF_MAGIC:     return (string)g_cfg.magic;
      case PLF_COMMENT:   return g_cfg.comment;
      case PLF_EXP_HOURS: return IntegerToString(g_cfg.expiry_hours);
      case PLF_MAX_SPREAD:return DoubleToString(g_cfg.max_spread,0);
      case PLF_BE_R:      return PlTrimNum(g_cfg.be_r);
      case PLF_TRAIL_PIPS:return PlTrimNum(g_dr.trail_dist);
      case PLF_PART_PCT:  return DoubleToString(g_cfg.part_pct,0);
      case PLF_PORT_CAP:  return DoubleToString(g_lc.portfolio_cap_pct,1);
      case PLF_MAX_OPEN:  return IntegerToString(g_cfg.max_open);
      case PLF_MAX_DAY:   return IntegerToString(g_cfg.max_day);
      case PLF_MARGIN_USE:return DoubleToString(g_cfg.margin_use,0);
     }
   return "";
  }

//--- apply an entry: true when accepted ---------------------------------------------------------
bool PlFieldApply(const int id,const string text)
  {
   double v=0, v2=0; long iv=0;
   bool prof=false;
   g_fl_note="";
   switch(id)
     {
      case PLF_RISK:
         if(!PlParseNum(text,v) || v<=0.0 || v>(g_dr.unit_money?1.0e9:100.0)) return false;
         if(g_dr.unit_money) g_dr.risk_money=v; else g_dr.risk_pct=v;
         break;
      case PLF_LOT:
         if(!PlParseNum(text,v) || v<=0.0 || v>1.0e6) return false;
         g_cfg.lot_fixed=v;
         break;
      case PLF_ENTRY:
         if(!PlParseNum(text,v) || v<=0.0) return false;
         v2=PlTickRound(v);
         if(!PlPriceSane(v2)) return false;
         g_px.entry=v2;
         break;
      case PLF_LIMIT:
         if(!PlParseNum(text,v) || v<=0.0) return false;
         v2=PlTickRound(v);
         if(!PlPriceSane(v2)) return false;
         g_px.limit=v2;
         break;
      case PLF_SL_PRICE:
         if(!PlParseNum(text,v) || v<=0.0) return false;
         v2=PlTickRound(v);
         if(!PlPriceSane(v2)) return false;
         PlSlMovedTo(v2);
         break;
      case PLF_SL_PIPS:
        {
         if(!PlParseNum(text,v) || v<=0.0) return false;
         double ref=PlEstExec();
         int dir=PlEstDir();
         v2=PlTickRound(ref-dir*v*PlPipSize(g_sym));
         if(!PlPriceSane(v2)) return false;
         PlSlMovedTo(v2);
         break;
        }
      case PLF_TP_PRICE:
         if(!PlParseNum(text,v) || v<=0.0) return false;
         v2=PlTickRound(v);
         if(!PlPriceSane(v2)) return false;
         g_px.tp[0]=v2; g_dr.tp_price[0]=true;
         break;
      case PLF_TP_PIPS:
        {
         if(!PlParseNum(text,v) || v<=0.0) return false;
         double ref=PlEstExec();
         int dir=PlEstDir();
         v2=PlTickRound(ref+dir*v*PlPipSize(g_sym));
         if(!PlPriceSane(v2)) return false;
         g_px.tp[0]=v2; g_dr.tp_price[0]=true;
         break;
        }
      case PLF_TP_R:
         if(!PlParseNum(text,v) || v<=0.0 || v>1000.0) return false;
         g_dr.tp_r[0]=v; g_dr.tp_price[0]=false;
         break;
      case PLF_COMM_RATE:
         if(!PlParseNum(text,v) || v<0.0 || v>100000.0) return false;
         g_dr.comm.rate=v; g_dr.comm.source=PL_COMMSRC_USER;
         if(g_dr.comm.kind==PL_COMM_UNKNOWN) g_dr.comm.kind=PL_COMM_LOT_SIDE;
         break;
      case PLF_CAP:
         if(!PlParseNum(text,v) || v<=0.0 || v>100.0) return false;
         g_cfg.cap=v;
         break;
      case PLF_CONF_ABOVE:
         if(!PlParseNum(text,v) || v<=0.0 || v>100.0) return false;
         g_cfg.confirm_above=v;
         break;
      case PLF_ATR_MULT:
         if(!PlParseNum(text,v) || v<=0.0 || v>100.0) return false;
         g_cfg.atr_mult=v;
         break;
      case PLF_ATR_PERIOD:
         if(!PlParseInt(text,iv) || iv<1 || iv>500) return false;
         g_cfg.atr_period=(int)iv;
         break;
      case PLF_TP2_R:
         if(!PlParseNum(text,v) || v<=0.0 || v>1000.0) return false;
         g_dr.tp_r[1]=v; g_dr.tp_price[1]=false;
         break;
      case PLF_TP3_R:
         if(!PlParseNum(text,v) || v<=0.0 || v>1000.0) return false;
         g_dr.tp_r[2]=v; g_dr.tp_price[2]=false;
         break;
      case PLF_TP2_SHARE:
         if(!PlParseNum(text,v) || v<1.0 || v>98.0) return false;
         if(g_cfg.tp_count>=3 && v+g_cfg.tp_share3>99.0) return false;
         g_cfg.tp_share2=MathRound(v);
         break;
      case PLF_TP3_SHARE:
         if(!PlParseNum(text,v) || v<1.0 || v>98.0) return false;
         if(v+g_cfg.tp_share2>99.0) return false;
         g_cfg.tp_share3=MathRound(v);
         break;
      case PLF_MAGIC:
         if(!PlParseInt(text,iv) || iv<=0 || iv>2147483647) return false;       // 0 would make every manual trade "ours"
         g_cfg.magic=iv;
         break;
      case PLF_COMMENT:
        {
         string c=text;
         StringReplace(c,"\r",""); StringReplace(c,"\n","");
         //--- the tag ("abcde/1") is added to it and a comment holds 31 characters: 20 plain ASCII characters here
         if(StringLen(c)>20) return false;
         for(int ci=StringLen(c)-1;ci>=0;ci--)
           {
            ushort ch=StringGetCharacter(c,ci);
            if(ch<32 || ch>126) return false;
           }
         g_cfg.comment=c;
         break;
        }
      case PLF_EXP_HOURS:
         if(!PlParseInt(text,iv) || iv<1 || iv>9999) return false;
         g_cfg.expiry_hours=(int)iv;
         break;
      case PLF_MAX_SPREAD:
         if(!PlParseNum(text,v) || v<=0.0 || v>100.0) return false;
         g_cfg.max_spread=v;
         break;
      case PLF_BE_R:
         if(!PlParseNum(text,v) || v<=0.0 || v>100.0) return false;
         g_cfg.be_r=v;
         break;
      case PLF_TRAIL_PIPS:
         if(!PlParseNum(text,v) || v<0.0 || v>100000.0) return false;
         g_dr.trail_dist=v;
         break;
      case PLF_PART_PCT:
         if(!PlParseNum(text,v) || v<1.0 || v>99.0) return false;
         g_cfg.part_pct=MathRound(v);
         break;
      case PLF_PORT_CAP:
         if(!PlParseNum(text,v) || v<0.0 || v>1000.0) return false;
         g_lc.portfolio_cap_pct=v; prof=true;
         break;
      case PLF_MAX_OPEN:
         if(!PlParseInt(text,iv) || iv>1000) return false;
         g_cfg.max_open=(int)iv;
         break;
      case PLF_MAX_DAY:
         if(!PlParseInt(text,iv) || iv>10000) return false;
         g_cfg.max_day=(int)iv;
         break;
      case PLF_MARGIN_USE:
         if(!PlParseNum(text,v) || v<0.0 || v>1000.0) return false;
         g_cfg.margin_use=v;
         break;
      default: return false;
     }
   if(id==PLF_ENTRY || id==PLF_SL_PRICE || id==PLF_SL_PIPS) PlAutoKind(id==PLF_ENTRY,true,2.0*g_sym.tick_size);       // a typed price: the old two ticks, only a mouse needs the pixel zone
   if(prof) PlProfileSave(true);
   if(id==PLF_LOT || id==PLF_RISK || (id>=PLF_CAP && id!=PLF_TP2_R && id!=PLF_TP3_R)) PlSettingsSave();   // menu numbers are kept at once
   PlModelChanged();
   return true;
  }

#endif
