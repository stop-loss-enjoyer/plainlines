// Required Notice: Copyright 2026 stop-loss-enjoyer
// Plainlines is source-available under the PolyForm Shield License 1.0.0.
//
// The lines on the chart: Entry, Limit (Stop-Limit only), SL, TP1..TP3 as OBJ_HLINE, plus a label
// at the right edge of each. The numbers in g_px and the lines are kept equal. Colors are those of
// the reference Position Sizer: Entry 16711680, SL 128, TP 32768, Limit 8388736.
#property strict

#ifndef PL_UI_LINES_MQH
#define PL_UI_LINES_MQH

bool g_lines_created=false;     // a line was created since the panel last went to the top
int  g_drag_w=-1;               // the line the pointer is moving right now (-1 none)
//--- Click to place (Advanced): in memory only, never saved. g_place_mode is the button that started it (0 Market: SL, TP1; 1 Limit: Entry, SL,
//--- TP1), -1 when no placing is going on. The lines are not selectable meanwhile: the line under the pointer would take the click as a drag
int    g_place_mode=-1;
bool   g_place_hold=false;      // the placing is over but the button of the last click is still down: the chart keeps still, the lines unlock at its release
#define PL_LN_COUNT 6          // 0 Entry, 1 Limit, 2 SL, 3..5 TP1..TP3

string PlLineName(const int w)
  {
   switch(w)
     {
      case 0: return "PL_Entry";
      case 1: return "PL_Limit";
      case 2: return "PL_SL";
      case 3: return "PL_TP1";
      case 4: return "PL_TP2";
      case 5: return "PL_TP3";
     }
   return "";
  }

string PlLabelName(const int w) { return "PL_Lb"+IntegerToString(w); }
string PlLabelBgName(const int w) { return "PL_Lr"+IntegerToString(w); }

//--- lines we delete ourselves: the terminal reports each one later as a delete by the user, ignore those
string g_sd_name[8];
ulong  g_sd_t[8];
int    g_sd_next=0;

void PlLineDel(const string nm)
  {
   if(ObjectFind(0,nm)<0) return;
   ObjectDelete(0,nm);
   g_sd_name[g_sd_next]=nm; g_sd_t[g_sd_next]=GetTickCount64();
   g_sd_next=(g_sd_next+1)%8;
  }

bool PlSelfDeleted(const string nm)
  {
   ulong now=GetTickCount64();
   for(int i=0;i<8;i++)
      if(g_sd_name[i]==nm && now-g_sd_t[i]<5000) { g_sd_name[i]=""; return true; }
   return false;
  }

void PlLabelDelete(const int w)
  {
   ObjectDelete(0,PlLabelName(w));
   ObjectDelete(0,PlLabelBgName(w));
  }

//--- the two sets of line colors: the plain one for a light background, a lightened one for a dark background, where the
//--- dark blue, purple and maroon were 2:1 and their price tags unreadable
color PlLineColorSet(const int w,const bool dark)
  {
   if(dark)
     {
      switch(w)
        {
         case 0: return C'96,160,255';
         case 1: return C'196,140,255';
         case 2: return C'255,110,120';
        }
      return C'70,200,100';
     }
   switch(w)
     {
      case 0: return (color)16711680;
      case 1: return (color)8388736;
      case 2: return (color)128;
     }
   return (color)32768;
  }

//--- WCAG relative luminance and contrast ratio of two colors
double PlRelLum(const color c)
  {
   double v[3];
   v[0]=(double)(c&0xFF)/255.0; v[1]=(double)((c>>8)&0xFF)/255.0; v[2]=(double)((c>>16)&0xFF)/255.0;
   for(int i=0;i<3;i++) v[i]=(v[i]<=0.03928)?v[i]/12.92:MathPow((v[i]+0.055)/1.055,2.4);
   return 0.2126*v[0]+0.7152*v[1]+0.0722*v[2];
  }

double PlContrast(const color a,const color b)
  {
   const double la=PlRelLum(a), lb=PlRelLum(b);
   return (MathMax(la,lb)+0.05)/(MathMin(la,lb)+0.05);
  }

//--- the color of a line on the chart as it is: the set that matches the background, then the other set, and when neither
//--- reaches 3:1 (a grey chart) the color is darkened or lightened until it does. Not a brightness threshold: on a grey of
//--- 128 both sets were at 1.3 to 1.5:1.
color PlLineColor(const int w)
  {
   const color bg=(color)ChartGetInteger(0,CHART_COLOR_BACKGROUND);
   const bool dark=PlChartIsDark();
   const color c1=PlLineColorSet(w,dark);
   if(PlContrast(c1,bg)>=3.0) return c1;
   const color c2=PlLineColorSet(w,!dark);
   if(PlContrast(c2,bg)>=3.0) return c2;
   const color to=(PlContrast(clrBlack,bg)>=PlContrast(clrWhite,bg))?clrBlack:clrWhite;
   for(int i=1;i<=10;i++)
     {
      const color c=PlMix(c1,to,i/10.0);
      if(PlContrast(c,bg)>=3.0) return c;
     }
   return to;
  }

//--- Thick (the default): a line has to be easy to grab with the mouse, width 2, and 3 above scale 100 (one device pixel is thin
//--- on a scaled screen). Thin, the choice in Look: 1 px. A price tag grabs the line at any width.
int PlLineWidth()
  {
   if(g_cfg.line_thick==0) return 1;
   return (PlScaleGet(g_cfg.scale)<=1.0)?2:3;
  }

int g_ln_sig=-1;      // chart background and width the lines on the chart carry now (-1: not set yet)

//--- put the current colors and width on the lines that stand; true when they differ from before
bool PlLinesRestyle()
  {
   const int sig=(int)ChartGetInteger(0,CHART_COLOR_BACKGROUND)|(PlLineWidth()<<24);      // the background itself: a grey chart needs its own colors
   if(sig==g_ln_sig) return false;
   g_ln_sig=sig;
   for(int w=0;w<PL_LN_COUNT;w++)
     {
      string nm=PlLineName(w);
      if(ObjectFind(0,nm)<0) continue;
      ObjectSetInteger(0,nm,OBJPROP_COLOR,PlLineColor(w));
      ObjectSetInteger(0,nm,OBJPROP_WIDTH,PlLineWidth());
     }
   return true;
  }

//--- which line is it (-1 when the name is not ours)
int PlLineFromName(const string nm)
  {
   for(int w=0;w<PL_LN_COUNT;w++) if(PlLineName(w)==nm) return w;
   return -1;
  }

double PlPxGet(const int w)
  {
   if(w==0) return g_px.entry;
   if(w==1) return g_px.limit;
   if(w==2) return g_px.sl;
   return g_px.tp[w-3];
  }

void PlPxSet(const int w,const double p)
  {
   if(w==0) g_px.entry=p;
   else if(w==1) g_px.limit=p;
   else if(w==2) g_px.sl=p;
   else g_px.tp[w-3]=p;
  }

//--- should this line exist with the current kind and menu
bool PlLineWanted(const int w)
  {
   switch(w)
     {
      case 0: return true;
      case 1: return g_dr.kind==PL_KIND_STOP_LIMIT;
      case 2: return !g_cfg.no_sl;
     }
   if(g_cfg.no_tp) return false;
   return (w-3)<g_cfg.tp_count;
  }

//--- is this line on the chart: wanted and the lines are switched on in the menu
bool PlLineShown(const int w)
  {
   return PlLinesOn() && PlLineWanted(w);
  }

void PlLineCreate(const int w)
  {
   string nm=PlLineName(w);
   PlLineDel(nm);
   if(!ObjectCreate(0,nm,OBJ_HLINE,0,0,PlPxGet(w))) return;
   ObjectSetInteger(0,nm,OBJPROP_COLOR,PlLineColor(w));
   ObjectSetInteger(0,nm,OBJPROP_STYLE,(w>=4)?STYLE_DASH:STYLE_SOLID);
   ObjectSetInteger(0,nm,OBJPROP_WIDTH,PlLineWidth());
   ObjectSetInteger(0,nm,OBJPROP_BACK,false);
   ObjectSetInteger(0,nm,OBJPROP_SELECTABLE,g_place_mode<0 && !g_place_hold);
   ObjectSetInteger(0,nm,OBJPROP_SELECTED,g_place_mode<0 && !g_place_hold);   // selected from the start, else a drag moves the chart
   ObjectSetInteger(0,nm,OBJPROP_HIDDEN,false);
   ObjectSetInteger(0,nm,OBJPROP_TIMEFRAMES,OBJ_ALL_PERIODS);
   ObjectSetString(0,nm,OBJPROP_TOOLTIP,"\n");       // no pop-up with the object name
   g_lines_created=true;
   ObjectSetString(0,nm,OBJPROP_TEXT,g_sym.name);   // lets a restart tell whose lines these are
  }

//--- create missing, delete unwanted, move those that differ from g_px
void PlLinesSync()
  {
   PlLinesRestyle();
   double tol=(g_sym.tick_size>0.0)?g_sym.tick_size/4.0:1e-9;
   for(int w=0;w<PL_LN_COUNT;w++)
     {
      string nm=PlLineName(w);
      bool want=PlLineShown(w);
      bool have=(ObjectFind(0,nm)>=0);
      if(!want)
        {
         if(have) PlLineDel(nm);
         PlLabelDelete(w);
         continue;
        }
      double p=PlPxGet(w);
      if(p<=0.0) continue;
      if(!have) { PlLineCreate(w); continue; }
      if(MathAbs(ObjectGetDouble(0,nm,OBJPROP_PRICE)-p)>tol) ObjectSetDouble(0,nm,OBJPROP_PRICE,p);
     }
  }

//--- read the lines into g_px; true when any moved
bool PlLinesPull()
  {
   bool ch=false, sl_moved=false;
   double tol=(g_sym.tick_size>0.0)?g_sym.tick_size/4.0:1e-9;
   for(int w=0;w<PL_LN_COUNT;w++)
     {
      if(!PlLineShown(w)) continue;
      if(w==2 && g_cfg.atr_on) continue;      // the ATR stop owns the SL: a dragged SL line is never read
      if(w>=3 && sl_moved) continue;           // PlSlMovedTo has just set the TPs (mirrored through the entry): their lines still stand at the old prices
      string nm=PlLineName(w);
      if(ObjectFind(0,nm)<0) continue;
      double p=ObjectGetDouble(0,nm,OBJPROP_PRICE);
      if(p>0.0 && MathAbs(p-PlPxGet(w))>tol)
        {
         if(w==2) { PlSlMovedTo(p); sl_moved=true; }
         else PlPxSet(w,p);
         ch=true; g_drag_w=w;
        }
     }
   return ch;
  }

//--- put the lines on the tick grid after a drag
void PlLinesSnap()
  {
   for(int w=0;w<PL_LN_COUNT;w++)
     {
      if(!PlLineWanted(w)) continue;
      double p=PlPxGet(w);
      if(p>0.0) PlPxSet(w,PlTickRound(p));
     }
  }

void PlLinesDeleteAll()
  {
   for(int w=0;w<PL_LN_COUNT;w++) { PlLineDel(PlLineName(w)); PlLabelDelete(w); }
  }

//--- do lines of this symbol already stand on the chart (restart, timeframe change)
bool PlLinesAdopt()
  {
   if(!PlLinesOn()) return false;
   string nm=PlLineName(0);
   if(ObjectFind(0,nm)<0) return false;
   if(ObjectGetString(0,nm,OBJPROP_TEXT)!=g_sym.name) return false;
   for(int w=0;w<PL_LN_COUNT;w++)
     {
      string n2=PlLineName(w);
      if(ObjectFind(0,n2)>=0) PlPxSet(w,ObjectGetDouble(0,n2,OBJPROP_PRICE));
     }
   return true;
  }

//--- labels at the right edge -------------------------------------------------------------------
//--- each label is placed against its line, then labels that would overlap are pushed apart
string g_lb_text[PL_LN_COUNT];
int    g_lb_top[PL_LN_COUNT];
bool   g_lb_on[PL_LN_COUNT];
string g_lb_sig[PL_LN_COUNT];     // what the label objects were last given (text, place, colors); "" = hidden or not drawn
int    g_lb_x0[PL_LN_COUNT], g_lb_y0[PL_LN_COUNT], g_lb_x1[PL_LN_COUNT], g_lb_y1[PL_LN_COUNT];   // the backing box as drawn (valid while g_lb_sig is not "")
int    g_lab_w=-1;                // the price tag the left button holds right now (-1 none): the tag drags its line
int    g_lab_dy=0;                // pointer y minus line y at the press, so the line does not jump to the pointer
bool   g_lab_moved=false;         // the held tag has moved its line

int PlLabelHeight()
  {
   int dpi=(int)TerminalInfoInteger(TERMINAL_SCREEN_DPI);
   if(dpi<=0) dpi=96;
   return (int)MathRound(9.0*dpi/72.0*1.45);
  }

void PlLabelPut(const int w,const string text,const double price,const bool above)
  {
   int x=0,y=0;
   bool vis=ChartTimePriceToXY(0,0,TimeCurrent(),price,x,y);
   int ch=(int)ChartGetInteger(0,CHART_HEIGHT_IN_PIXELS);
   if(vis && (y<0 || y>ch)) vis=false;
   g_lb_on[w]=vis;
   g_lb_text[w]=text;
   g_lb_top[w]=above?(y-2-PlLabelHeight()):(y+3);
  }

void PlLabelsFlush()
  {
   int h=PlLabelHeight()+4;      // room for the backing box
   //--- order by position, push down what overlaps its upper neighbour
   int idx[PL_LN_COUNT]; int n=0;
   for(int w=0;w<PL_LN_COUNT;w++) if(g_lb_on[w]) { idx[n]=w; n++; }
   for(int i=1;i<n;i++)
     {
      int k=idx[i], j=i-1;
      while(j>=0 && g_lb_top[idx[j]]>g_lb_top[k]) { idx[j+1]=idx[j]; j--; }
      idx[j+1]=k;
     }
   for(int i=1;i<n;i++)
      if(g_lb_top[idx[i]]<g_lb_top[idx[i-1]]+h) g_lb_top[idx[i]]=g_lb_top[idx[i-1]]+h;
   int cw=(int)ChartGetInteger(0,CHART_WIDTH_IN_PIXELS);
   color cbg=(color)ChartGetInteger(0,CHART_COLOR_BACKGROUND);
   //--- text size is measured the way the label draws it (9 pt, scaled by the terminal like the label itself)
   TextSetFont("Segoe UI Semibold",-90);
   for(int w=0;w<PL_LN_COUNT;w++)
     {
      string nm=PlLabelName(w);
      string bg=PlLabelBgName(w);
      if(!g_lb_on[w])
        {
         if(ObjectFind(0,nm)>=0) ObjectSetInteger(0,nm,OBJPROP_TIMEFRAMES,OBJ_NO_PERIODS);
         if(ObjectFind(0,bg)>=0) ObjectSetInteger(0,bg,OBJPROP_TIMEFRAMES,OBJ_NO_PERIODS);
         g_lb_sig[w]="";
         continue;
        }
      bool have_l=(ObjectFind(0,nm)>=0), have_b=(ObjectFind(0,bg)>=0);
      const color lc=PlLineColor(w);          // the same color as the line: lightened on a dark chart
      //--- the same text in the same place and colors: nothing to set (a recalculation or a scroll of the chart asks for this all the time)
      const string sig=g_lb_text[w]+"|"+IntegerToString(g_lb_top[w])+"|"+IntegerToString(cw)+"|"+IntegerToString((int)lc)+"|"+IntegerToString((int)cbg);
      if(have_l && have_b && sig==g_lb_sig[w]) continue;
      //--- the backing is created first so that the text lies above it
      if(have_l && !have_b) { ObjectDelete(0,nm); have_l=false; }
      if(!have_b)
        {
         ObjectCreate(0,bg,OBJ_RECTANGLE_LABEL,0,0,0);
         ObjectSetInteger(0,bg,OBJPROP_CORNER,CORNER_LEFT_UPPER);
         ObjectSetInteger(0,bg,OBJPROP_BORDER_TYPE,BORDER_FLAT);
         ObjectSetInteger(0,bg,OBJPROP_SELECTABLE,false);
         ObjectSetInteger(0,bg,OBJPROP_HIDDEN,true);
         ObjectSetInteger(0,bg,OBJPROP_BACK,false);
         ObjectSetString(0,bg,OBJPROP_TOOLTIP,"\n");
         g_lines_created=true;
        }
      if(!have_l)
        {
         ObjectCreate(0,nm,OBJ_LABEL,0,0,0);
         ObjectSetInteger(0,nm,OBJPROP_CORNER,CORNER_LEFT_UPPER);
         ObjectSetInteger(0,nm,OBJPROP_ANCHOR,ANCHOR_RIGHT_UPPER);
         ObjectSetInteger(0,nm,OBJPROP_SELECTABLE,false);
         ObjectSetInteger(0,nm,OBJPROP_HIDDEN,true);
         ObjectSetInteger(0,nm,OBJPROP_BACK,false);
         ObjectSetString(0,nm,OBJPROP_FONT,"Segoe UI Semibold");
         ObjectSetString(0,nm,OBJPROP_TOOLTIP,"\n");
        }
      uint tw=0, th=0;
      TextGetSize(g_lb_text[w],tw,th);
      int padx=5, pady=2;
      ObjectSetInteger(0,bg,OBJPROP_BGCOLOR,cbg);
      ObjectSetInteger(0,bg,OBJPROP_COLOR,lc);
      ObjectSetInteger(0,bg,OBJPROP_XSIZE,(int)tw+2*padx);
      ObjectSetInteger(0,bg,OBJPROP_YSIZE,(int)th+2*pady);
      ObjectSetInteger(0,bg,OBJPROP_XDISTANCE,cw-8-(int)tw-padx);
      ObjectSetInteger(0,bg,OBJPROP_YDISTANCE,g_lb_top[w]-pady);
      g_lb_x0[w]=cw-8-(int)tw-padx; g_lb_y0[w]=g_lb_top[w]-pady;
      g_lb_x1[w]=g_lb_x0[w]+(int)tw+2*padx; g_lb_y1[w]=g_lb_y0[w]+(int)th+2*pady;
      ObjectSetInteger(0,bg,OBJPROP_TIMEFRAMES,OBJ_ALL_PERIODS);
      ObjectSetInteger(0,nm,OBJPROP_COLOR,lc);
      ObjectSetInteger(0,nm,OBJPROP_FONTSIZE,9);
      ObjectSetString(0,nm,OBJPROP_TEXT,g_lb_text[w]);
      ObjectSetInteger(0,nm,OBJPROP_XDISTANCE,cw-8);
      ObjectSetInteger(0,nm,OBJPROP_YDISTANCE,g_lb_top[w]);
      ObjectSetInteger(0,nm,OBJPROP_TIMEFRAMES,OBJ_ALL_PERIODS);
      g_lb_sig[w]=sig;
     }
  }

//--- a price tag holds its line: the left button down on the tag and moving up or down moves the line, through the
//--- same path as a drag of the line itself (the caller does the live step and the end of the drag). The chart
//--- does not scroll meanwhile: PlScrollGuard keeps CHART_MOUSE_SCROLL off over a tag and while one is held.

//--- the tag under the pointer (-1 none)
int PlLabelAt(const int mx,const int my)
  {
   for(int w=0;w<PL_LN_COUNT;w++)
     {
      if(!g_lb_on[w] || g_lb_sig[w]=="") continue;
      if(mx>=g_lb_x0[w] && mx<g_lb_x1[w] && my>=g_lb_y0[w] && my<g_lb_y1[w]) return w;
     }
   return -1;
  }

//--- the left button went down at mx,my: hold the tag there, if any
bool PlLabelPress(const int mx,const int my)
  {
   g_lab_w=-1; g_lab_moved=false;
   const int w=PlLabelAt(mx,my);
   if(w<0 || !PlLineShown(w) || ObjectFind(0,PlLineName(w))<0) return false;
   int x=0,y=0;
   if(!ChartTimePriceToXY(0,0,TimeCurrent(),PlPxGet(w),x,y)) return false;
   g_lab_w=w; g_lab_dy=my-y;
   return true;
  }

//--- the pointer moved with the button down: put the held line at the pointer
void PlLabelFollow(const int mx,const int my)
  {
   if(g_lab_w<0) return;
   const string nm=PlLineName(g_lab_w);
   if(ObjectFind(0,nm)<0) { g_lab_w=-1; return; }
   int y=my-g_lab_dy;
   const int ch=(int)ChartGetInteger(0,CHART_HEIGHT_IN_PIXELS);
   if(y<0) y=0;
   if(y>ch-1) y=ch-1;
   datetime t=0; double p=0.0; int sw=0;
   if(!ChartXYToTimePrice(0,mx,y,sw,t,p) || p<=0.0) return;
   const double tol=(g_sym.tick_size>0.0)?g_sym.tick_size/4.0:1e-9;
   if(MathAbs(ObjectGetDouble(0,nm,OBJPROP_PRICE)-p)<=tol) return;
   ObjectSetDouble(0,nm,OBJPROP_PRICE,p);
   g_lab_moved=true;
  }

//--- text of the labels from the latest result
void PlLinesLabels()
  {
   PlLinesRestyle();                 // every re-theme path ends here
   string cur=g_acc.currency;
   int cd=g_acc.currency_digits;
   double exec=(g_plan.ok && g_plan.exec>0.0)?g_plan.exec:PlEstExec();
   bool ok=g_plan.ok && g_res.lot>0.0;
   string unit=PlIsForex(g_sym)?PLS_PIP:PLS_PT;
   string t;
   for(int w=0;w<PL_LN_COUNT;w++) g_lb_on[w]=false;
   if(!PlLinesOn()) { PlLabelsFlush(); return; }     // lines off: the labels hide with them
   //--- Entry
   t=PLS_ENTRY;
   if(ok) t+=" "+DoubleToString(g_res.lot,PlLotDigits())+PLS_LOT_WORD;
   PlLabelPut(0,t,g_px.entry,(g_dr.kind==PL_KIND_STOP_LIMIT)?(g_px.entry>=g_px.limit):true);
   //--- Limit
   if(PlLineWanted(1)) PlLabelPut(1,PLS_KIND_LIMIT,g_px.limit,(g_px.limit>g_px.entry));
   //--- SL
   if(PlLineWanted(2))
     {
      t=PLS_SL_SP+PlFmtUnitField(PlToUnit(MathAbs(exec-g_px.sl)))+" "+unit;
      if(ok && g_res.risk_money>0.0) t+="  -"+PlMoney(g_res.risk_money,cur,cd);
      bool above=(g_px.sl>=exec);
      PlLabelPut(2,t,g_px.sl,above);
     }
   //--- TPs
   for(int i=0;i<PL_MAX_TP;i++)
     {
      int w=3+i;
      if(!PlLineWanted(w)) continue;
      double d=MathAbs(exec-g_px.sl);
      double r=(d>PL_EPS)?MathAbs(g_px.tp[i]-exec)/d:0.0;
      t=(g_cfg.tp_count>1)?(PLS_TP+IntegerToString(i+1)):PLS_TP;
      t+=" "+PlFmtUnitField(PlToUnit(MathAbs(g_px.tp[i]-exec)))+" "+unit;
      if(ok && g_res.reward[i]!=0.0) t+="  +"+PlMoney(g_res.reward[i],cur,cd);
      if(r>0.0 && !g_cfg.no_sl) t+="  "+DoubleToString(r,1)+"R";
      bool above=(g_px.tp[i]>=exec);
      PlLabelPut(w,t,g_px.tp[i],above);
     }
   PlLabelsFlush();
  }

#endif
