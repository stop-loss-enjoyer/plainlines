// Required Notice: Copyright 2026 stop-loss-enjoyer
// Plainlines is source-available under the PolyForm Shield License 1.0.0.
//
// The panel: one OBJ_BITMAP_LABEL drawn with CCanvas, its own hit testing on CHARTEVENT_MOUSE_MOVE
// (an action fires on release over the same hit where the press began), OBJ_EDIT fields laid on top
// (see Fields.mqh). Layout is written in logical pixels (300 wide) and scaled once by the DPI.
// Each drawing pass runs twice: a dry pass measures the content and registers hits, the real pass
// paints. Nothing here sends orders or changes the model; actions go back as (act_id, act_arg).
#property strict
#include <Canvas/Canvas.mqh>
#include "Wordmark.mqh"

#ifndef PL_UI_CANVAS_MQH
#define PL_UI_CANVAS_MQH

#define PL_PANEL_NAME   "PL_Panel"
#define PL_W            280          // logical width
#define PL_PAD          10
#define PL_STATUS_H     22           // the pinned status row under the header
#define PL_HDR          34
#define PL_STRIP_W      530          // the quick strip: one row, its own width (with the risk field and its unit)
#define PL_STRIP_H      40           // controls 28 high, 6 above and below
#define PL_QUICK_H      150          // the quick panel: header 34, 8, risk 26, 6, type 26, 8, the button 34, 8
#define PL_MAIN_H       340          // the full panel at its smallest (the base the compact layout is measured from)
#define PL_MAX_HITS     200
#define PL_MAX_ROWS     512

//--- the sections of the settings menu, in the order of use
#define PL_SEC_TRADE       0
#define PL_SEC_POSITION    1
#define PL_SEC_CONFIRM     2
#define PL_SEC_COMMISSION  3
#define PL_SEC_LIMITS      4
#define PL_SEC_ADVANCED    5
#define PL_SEC_LOOK        6
#define PL_SEC_N           7

enum PlHit
  {
   H_NONE=0, H_HEADER, H_MENU, H_COLLAPSE, H_KIND, H_COSTS, H_COSTS_X, H_CHIP, H_UNIT, H_ACTION, H_SWAP,
   H_CANCEL, H_COMM_KIND, H_COMM_USE, H_COMM_GO, H_SEC, H_TOG, H_SEG, H_RESET,
   H_POS, H_POS_X, H_ROW_X, H_ROW_EXP, H_ROW_BTN, H_BULK, H_LINES, H_QKIND
  };      // ids are kept as they are: the development command act N and the notes name them (H_POS and H_POS_X are no longer drawn)

enum PlMenuKey
  {
   MK_BASE=0, MK_SUB_OPEN, MK_OVERMAX, MK_ATR, MK_TPCOUNT, MK_NO_SL, MK_NO_TP, MK_EXPIRY, MK_CONFIRM,
   MK_BE, MK_TRAIL, MK_CLOSEBTN,
   MK_RESERVED1, MK_RESERVED2,       // reserved ids: the numbers of the other keys stay as they are
   MK_THEME, MK_SCALE,
   MK_RESERVED3,
   MK_SOUNDS, MK_QSTYLE, MK_LINEW, MK_CLICKPLACE
  };

enum PlFont { FN_UI=0, FN_SB=1, FN_NUM=2, FN_BRAND=3 };

struct PlHitR { int id; int arg; int x1; int y1; int x2; int y2; };

//--- canvas with pixel access: anti-aliased rounded rectangles and discs ---------------------------
class CPlCv : public CCanvas
  {
public:
   void              Over(const int x,const int y,const uint c,const double cov)
     {
      if(x<0 || y<0 || x>=m_width || y>=m_height || cov<=0.0) return;
      int idx=y*m_width+x;
      uint sa8=(c>>24)&0xFF;
      if(sa8==255 && cov>=0.999) { m_pixels[idx]=c; return; }
      double sa=sa8/255.0*cov;
      uint d=m_pixels[idx];
      double da=((d>>24)&0xFF)/255.0;
      double oa=sa+da*(1.0-sa);
      if(oa<=0.0) return;
      double sr=(double)((c>>16)&0xFF), sg=(double)((c>>8)&0xFF), sb=(double)(c&0xFF);
      double dr=(double)((d>>16)&0xFF), dg=(double)((d>>8)&0xFF), db=(double)(d&0xFF);
      double k=da*(1.0-sa);
      uint r=(uint)MathRound((sr*sa+dr*k)/oa);
      uint g=(uint)MathRound((sg*sa+dg*k)/oa);
      uint b=(uint)MathRound((sb*sa+db*k)/oa);
      uint a=(uint)MathRound(oa*255.0);
      m_pixels[idx]=(a<<24)|(r<<16)|(g<<8)|b;
     }
   //--- is the whole pixel row y between x1 and x2 exactly the color c (a gap between two rows of the panel)
   bool              BlankRow(const int y,const uint c,const int x1,const int x2) const
     {
      if(y<0 || y>=m_height) return false;
      const int base=y*m_width;
      for(int x=x1;x<=x2 && x<m_width;x++) if(m_pixels[base+x]!=c) return false;
      return true;
     }
   void              Fill(int x1,int y1,int x2,int y2,const uint c)
     {
      if(x1<0) x1=0; if(y1<0) y1=0;
      if(x2>=m_width) x2=m_width-1; if(y2>=m_height) y2=m_height-1;
      if(x2<x1 || y2<y1) return;
      for(int y=y1;y<=y2;y++)
        {
         int base=y*m_width;
         for(int x=x1;x<=x2;x++) m_pixels[base+x]=c;
        }
     }
   void              RR(const int x1,const int y1,const int x2,const int y2,int r,const uint c)
     {
      if(x2<x1 || y2<y1) return;
      int w=x2-x1+1, h=y2-y1+1;
      if(r>w/2) r=w/2;
      if(r>h/2) r=h/2;
      if(r<=0) { Fill(x1,y1,x2,y2,c); return; }
      Fill(x1+r,y1,x2-r,y2,c);
      Fill(x1,y1+r,x1+r-1,y2-r,c);
      Fill(x2-r+1,y1+r,x2,y2-r,c);
      for(int j=0;j<r;j++)
         for(int i=0;i<r;i++)
           {
            double dx=r-(i+0.5), dy=r-(j+0.5);
            double cov=r-MathSqrt(dx*dx+dy*dy)+0.5;
            if(cov<=0.0) continue;
            if(cov>1.0) cov=1.0;
            Over(x1+i,y1+j,c,cov); Over(x2-i,y1+j,c,cov);
            Over(x1+i,y2-j,c,cov); Over(x2-i,y2-j,c,cov);
           }
     }
   void              Box(const int x1,const int y1,const int x2,const int y2,const int r,const uint fill,const uint border)
     {
      RR(x1,y1,x2,y2,r,border);
      RR(x1+1,y1+1,x2-1,y2-1,r-1,fill);
     }
   void              Disc(const double cx,const double cy,const double rad,const uint c)
     {
      int x1=(int)MathFloor(cx-rad-1), x2=(int)MathCeil(cx+rad+1);
      int y1=(int)MathFloor(cy-rad-1), y2=(int)MathCeil(cy+rad+1);
      for(int y=y1;y<=y2;y++)
         for(int x=x1;x<=x2;x++)
           {
            double dx=x+0.5-cx, dy=y+0.5-cy;
            double cov=rad-MathSqrt(dx*dx+dy*dy)+0.5;
            if(cov<=0.0) continue;
            if(cov>1.0) cov=1.0;
            Over(x,y,c,cov);
           }
     }
   //--- anti-aliased outline of an eye (a lens of two arcs) half a wide and b high around cx,cy (icons)
   void              Lens(const double cx,const double cy,const double a,const double b,const double wd,const uint c)
     {
      double r=(a*a+b*b)/(2.0*b), d=r-b;
      int x1=(int)MathFloor(cx-a-wd-1), x2=(int)MathCeil(cx+a+wd+1);
      int y1=(int)MathFloor(cy-b-wd-1), y2=(int)MathCeil(cy+b+wd+1);
      for(int y=y1;y<=y2;y++)
         for(int x=x1;x<=x2;x++)
           {
            double px=x+0.5-cx, py=y+0.5-cy;
            double sd=MathMax(MathSqrt(px*px+(py-d)*(py-d))-r,MathSqrt(px*px+(py+d)*(py+d))-r);
            double cov=wd/2.0-MathAbs(sd)+0.5;
            if(cov<=0.0) continue;
            if(cov>1.0) cov=1.0;
            Over(x,y,c,cov);
           }
     }
   //--- anti-aliased line of a given width (icons)
   void              Stroke(const double x1,const double y1,const double x2,const double y2,const double wd,const uint c)
     {
      double dx=x2-x1, dy=y2-y1;
      double len=MathSqrt(dx*dx+dy*dy);
      if(len<=0.0) { Disc(x1,y1,wd/2.0,c); return; }
      int bx1=(int)MathFloor(MathMin(x1,x2)-wd-1), bx2=(int)MathCeil(MathMax(x1,x2)+wd+1);
      int by1=(int)MathFloor(MathMin(y1,y2)-wd-1), by2=(int)MathCeil(MathMax(y1,y2)+wd+1);
      for(int y=by1;y<=by2;y++)
         for(int x=bx1;x<=bx2;x++)
           {
            double px=x+0.5-x1, py=y+0.5-y1;
            double t=(px*dx+py*dy)/(len*len);
            if(t<0.0) t=0.0;
            if(t>1.0) t=1.0;
            double qx=px-t*dx, qy=py-t*dy;
            double cov=wd/2.0-MathSqrt(qx*qx+qy*qy)+0.5;
            if(cov<=0.0) continue;
            if(cov>1.0) cov=1.0;
            Over(x,y,c,cov);
           }
     }
  };

//--- view helpers on the model ---------------------------------------------------------------------
string PlSideWord()
  {
   if(g_plan.side==PL_SIDE_BUY) return PLS_BUY_WORD;
   if(g_plan.side==PL_SIDE_SELL) return PLS_SELL_WORD;
   return "";
  }

string PlLotText()
  {
   if(!g_plan.ok || g_res.lot<=0.0) return "-";
   return DoubleToString(g_res.lot,PlLotDigits());
  }

//--- what stands in the status line when there is nothing to warn about: the swap of one night for the side and the lot of the
//--- draft ("Swap -$1.37/night", with "x3 Wed" on the day the triple swap is charged). Cents, so it does not tremble; empty
//--- when the swap is unknown or zero (then the line says Ready to trade)
string PlSwapStatus()
  {
   if(!g_plan.ok || g_plan.side==PL_SIDE_NONE || g_res.lot<=0.0 || !g_res.swap_ok) return "";
   const bool buy=(g_plan.side==PL_SIDE_BUY);
   const double sw=NormalizeDouble(buy?g_res.swap_long_night:g_res.swap_short_night,g_acc.currency_digits);
   if(MathAbs(sw)<0.005) return "";
   string t=PLS_SWAP_SP+PlMoney(sw,g_acc.currency,g_acc.currency_digits,true)+PLS_PER_NIGHT;
   const double raw=buy?g_sym.swap_long:g_sym.swap_short;
   if(g_sym.swap_3day>=0 && g_sym.swap_3day<=6 && raw!=0.0)
     {
      MqlDateTime d; TimeToStruct(TimeTradeServer(),d);
      if(d.day_of_week==g_sym.swap_3day) t+=PLS_X3_SP+PlDayName(g_sym.swap_3day);
     }
   return t;
  }

//--- status: text, text color, dot color, and the short form of the text when it has one (the quick card header and the status row
//--- fall back to it before they cut the long one)
void PlStatusText(string &text,color &tc,color &dot);
void PlStatus(string &text,color &tc,color &dot,string &alt)
  {
   PlStatusText(text,tc,dot);
   alt=PlAltOfPhrase(text);
  }

void PlStatus(string &text,color &tc,color &dot)
  {
   string alt;
   PlStatus(text,tc,dot,alt);
  }

void PlStatusText(string &text,color &tc,color &dot)
  {
   tc=g_th.text; dot=g_th.ok;
   if(g_msg!="" && GetTickCount64()<g_msg_until)
     {
      text=g_msg; tc=g_th.text;
      dot=(g_msg_kind==2)?g_th.sell:(g_msg_kind==1)?g_th.ok:g_th.accent;
      if(g_msg_kind==2) tc=g_th.sell;
      //--- the result of a closed position: the colour of its sign
      if(g_msg_kind==3) { tc=g_th.ok; dot=g_th.ok; }
      if(g_msg_kind==4) { tc=g_th.sell; dot=g_th.sell; }
      return;
     }
   for(int i=0;i<PLF_COUNT;i++)
      if(g_fl_bad[i])
        {
         text=(g_fl_note!="")?g_fl_note:(PLS_BAD_NUMBER+" "+PlFieldTitle(i));
         tc=g_th.sell; dot=g_th.sell; return;
        }
   if(g_flow==PL_FLOW_ARMED)
     {
      tc=g_th.text; dot=g_th.accent;
      if(g_snap.netting_ack && g_snap.verdict!=PL_CONFIRM)
        {
         //--- a netting add: the one confirmation says what an add is on this account, and its press is the acknowledgement
         text=PlReasonText(PL_R_NETTING_ADD);
        }
      else if(g_snap.verdict==PL_CONFIRM)
        {
         text=(g_snap.reason==PL_R_RISK_HIGH)?(PLS_RISK_SP+DoubleToString(g_snap.risk_pct,2)+PLS_PCT_CONFIRM):PlReasonTextG(g_snap.reason);
         tc=g_th.warn_text; dot=g_th.warn;
        }
      else if(g_snap.kind==PL_KIND_MARKET) text=PLS_PRESS_AGAIN_TO_SEND_AT_MARKET;
      else
        {
         string ex=(g_snap.expiry_mode==1)?PLS_EXPIRES_TODAY:(g_snap.expiry_mode==2)?(PLS_EXPIRES_IN+PlLeftText((long)g_snap.expiry_hours*3600)):PLS_GOOD_TILL_CANCELLED;
         text=PLS_ENTRY_SP+DoubleToString(g_snap.entry,g_sym.digits)+", "+ex;
        }
      return;
     }
   if(!g_plan.ok)
     {
      if(g_plan.reason==PL_R_NO_SL && g_cfg.no_sl) text=PLS_NO_SL_SIDE;          // there is no SL line to move: the side comes from a TP price
      else text=(g_plan.reason==PL_R_NO_SL)?PLS_SET_SL:PlReasonTextG(g_plan.reason);
      tc=g_th.text2; dot=(g_plan.reason==PL_R_NO_SL)?g_th.warn:g_th.sell;
      return;
     }
   switch(g_res.verdict)
     {
      case PL_OK:
         text=PLS_READY; tc=g_th.text; dot=g_th.ok;
         //--- a secondary note (commission not counted, cross rate) does not change the verdict
         if(g_res.note!=PL_R_NONE) { text=PlReasonText(g_res.note); tc=g_th.warn_text; dot=g_th.warn; }
         else if(g_ex_comm_zero>0) { text=PlReasonText(PL_R_COMM_UNKNOWN)+": "+g_ex_comm_zero_sym; tc=g_th.warn_text; dot=g_th.warn; }     // a pending order counted with no commission
         else { const string sw=PlSwapStatus(); if(sw!="") text=sw; }                                                                         // nothing to say: the swap of the night, a thing the screen does not show
         break;
      case PL_WARN:    text=PlReasonTextG(g_res.reason); tc=g_th.warn_text; dot=g_th.warn; break;
      case PL_CONFIRM: text=PlReasonTextG(g_res.reason); tc=g_th.warn_text; dot=g_th.warn; break;
      default:
         text=PlReasonTextG(g_res.reason);
         if(g_res.reason==PL_R_MARKET_CLOSED) { text=PLS_MARKET_CLOSED_SHORT; tc=g_th.text2; dot=g_th.text2; }      // the full sentence does not fit the status row and lost its end
         else { tc=g_th.sell; dot=g_th.sell; }
         if(g_res.reason==PL_R_EA_NOT_ALLOWED) text=PLS_EA_NOT_ALLOWED_SHORT;      // the full sentence is cut in the status row; F7 on the chart opens the properties with the box
     }
   if(g_res.reason==PL_R_RISK_HIGH && g_res.verdict==PL_CONFIRM)
      text=PLS_RISK_SP+DoubleToString(g_res.risk_percent,2)+PLS_PCT_CONFIRM;
  }

//--- the text of the open button; shortf drops "at market" and writes a split as "x3" (the strip, when the long form does not fit)
string PlActionText(const bool shortf=false)
  {
   if(!g_plan.ok || g_plan.side==PL_SIDE_NONE) return PLS_BUY_SELL;
   string sd=PlSideWord();
   string lot=(g_res.lot>0.0)?DoubleToString(g_res.lot,PlLotDigits()):"";
   string t="";
   switch(g_dr.kind)
     {
      case PL_KIND_MARKET:     t=sd+" "+lot+((g_res.split_n>1 || shortf)?"":PLS_AT_MARKET); break;
      case PL_KIND_LIMIT:      t=sd+PLS_LIMIT_CAPS+lot; break;
      case PL_KIND_STOP:       t=sd+PLS_STOP_CAPS+lot; break;
      default:                 t=sd+PLS_STOP_LIMIT_CAPS+lot; break;
     }
   if(g_res.split_n>1) t+=shortf?(PLS_PARTS_X+(string)MathMax(g_split_orders,g_res.split_n)):(PLS_IN+(string)MathMax(g_split_orders,g_res.split_n)+" "+PLS_ORDERS);
   StringTrimRight(t);
   return t;
  }

string PlSideTitle()
  {
   string sd=(g_plan.side==PL_SIDE_BUY)?PLS_BUY:PLS_SELL;
   switch(g_dr.kind)
     {
      case PL_KIND_MARKET:     return sd;
      case PL_KIND_LIMIT:      return sd+PLS_LIMIT_SUFFIX;
      case PL_KIND_STOP:       return sd+PLS_STOP_SUFFIX;
     }
   return sd+PLS_STOP_LIMIT_SUFFIX;
  }

//--- the title of the frozen plan on the confirmation button: "Buy Limit"
string PlSnapTitle()
  {
   string sd=(g_snap.side==PL_SIDE_BUY)?PLS_BUY:PLS_SELL;
   switch(g_snap.kind)
     {
      case PL_KIND_MARKET:     return sd;
      case PL_KIND_LIMIT:      return sd+PLS_LIMIT_SUFFIX;
      case PL_KIND_STOP:       return sd+PLS_STOP_SUFFIX;
     }
   return sd+PLS_STOP_LIMIT_SUFFIX;
  }

//=================================================================================================
class CPlPanel
  {
private:
   CPlCv             m_cv;
   bool              m_created;
   int               m_x,m_y,m_w,m_h;
   double            m_s;
   double            m_fs;            // font scale on top of the terminal DPI (when the menu scale is not Auto)
   bool              m_dry;
   uint              m_wm[];          // the wordmark atlas, read once from the resource
   int               m_wm_w;          // its width in px; 0 not read yet, -1 could not be read (the header then writes the name)
   int               m_off;           // vertical pixel offset of the body (scroll)
   int               m_vis_top;       // first pixel row where the body is visible
   int               m_vis_bot;       // last pixel row where the body is visible (above the pinned footer)
   int               m_foot_h;        // px, height of the pinned action row (main view only)
   int               m_maxscroll;     // px the body can still be scrolled
   int               m_trim;          // px the panel is made shorter than the window allows, so the scroll end falls between two rows
   int               m_band_top;      // px of the empty band the status line left over the top of the body (EdgeMask result), 0: none
   int               m_costs_top;     // px, top of the Costs block in the content (dry result)
   int               m_content_end;   // px, end of the content incl. bottom padding (dry result)
   int               m_scroll;
   PlHitR            m_hr[PL_MAX_HITS];
   int               m_nh;
   int               m_hover_id,m_hover_arg,m_down_id,m_down_arg;
   bool              m_btn_prev,m_dragging;
   int               m_drag_dx,m_drag_dy;
   bool              m_sec[PL_SEC_N];
   int               m_fcur_f,m_fcur_s;
   int               m_th_cache[4][40];
   long              m_draws;
   int               m_style_sig;
   ulong             m_exp_id;        // the expanded row of the Positions block
   ulong             m_row_id[PL_MAX_ROWS];   // the id behind each row as drawn last (a click is judged by it, not by the index)
   int               m_nrows;
   bool              m_pos_seen;      // the main view had positions or orders at the last build (the scroll goes back to the top when the last one leaves)
   ulong             m_down_tid;      // the id of the row under the pointer at the press
public:
   bool              menu;
   bool              costs;
   bool              positions;       // the Positions header row is shown (set by BuildMain: there are positions or orders and Costs is closed)
   bool              pos_open;        // its list is open (memory only; collapsed when the last position or order is gone)
   bool              confirm_view;
   int               act_id;
   int               act_arg;
   ulong             act_tid;         // the id of the row the action is for (0: none)
   bool              moved;           // the panel was dragged since the last Take
   bool              to_costs;        // scroll the Costs block into view on the next draw (just opened)

                     CPlPanel(): m_created(false),m_style_sig(-1),m_vis_bot(0),m_foot_h(0),m_maxscroll(0),m_costs_top(0),menu(false),costs(false),positions(false),pos_open(false),m_exp_id(0),confirm_view(false),act_id(0),act_arg(0),act_tid(0),m_nrows(0),m_pos_seen(false),m_down_tid(0),moved(false),to_costs(false) {}
   bool              Created() const { return m_created; }
   bool              Strip() const { return g_cfg.quick && g_cfg.quick_style==0; }          // the quick panel as one row
   void              SetY(const int y) { m_y=y; }
   int               X() const { return m_x; }
   int               Y() const { return m_y; }
   int               Width() const { return m_w; }
   int               Height() const { return m_h; }
   long              Draws() const { return m_draws; }
   bool              Create(const int x,const int y);
   void              Destroy();
   void              Redraw();
   void              Place();
   void              OnMouse(const int mx,const int my,const int flags);
   bool              OnWheel(const int mx,const int my,const double delta);
   bool              Inside(const int mx,const int my) const;
   bool              Dragging() const { return m_dragging; }
   void              Clamp();
   void              Rescale();
   void              Raise();
   void              Ensure() { if(m_created && ObjectFind(0,PL_PANEL_NAME)<0) Raise(); }
   void              LogGeom();
   void              OpenSection(const int idx,const bool only=false);
   void              ExpandRow(const ulong id) { m_exp_id=id; }

private:
   int               P(const double v) const { return (int)MathRound(v*m_s); }
   int               Y_(const double ly) const { return (int)MathRound(ly*m_s)+m_off; }
   int               X_(const double lx) const { return (int)MathRound(lx*m_s); }
   void              SetFont(const int f,const int size10);
   int               TextH(const int f,const int size10);
   double            TextW(const string t,const int f,const int size10);
   int               FitTail(string &t,const double maxw,const int f,const int s0,const string alt="");
   string            CutPhrase(const string t,const string tl,const double maxw,const int f,const int s);
   int               FitStep(const string t,const double maxw,const int f,const int s0);
   int               FitNumber(string &t,const double maxw,const int f,const int s0,const int smin,const bool drop_dec);
   int               FieldPt(const int fid,string &tx,const double maxw,const int pt0);
   int               FieldPtMin();
   double            FieldNeed(const string tx,const int pt);
   void              WidenPips(const double fx1,double &fx2,double &px1,const double px2,double &hx);
   void              Txt(const double lx,const double lymid,const string t,const color c,const int f,const int size10,const int align=0);
   void              FillL(const double lx1,const double ly1,const double lx2,const double ly2,const color c);
   void              RndL(const double lx1,const double ly1,const double lx2,const double ly2,const double r,const color c);
   void              BoxL(const double lx1,const double ly1,const double lx2,const double ly2,const double r,const color fill,const color border);
   void              Div(const double ly);
   void              Reg(const int id,const int arg,const double lx1,const double ly1,const double lx2,const double ly2);
   bool              IsHover(const int id,const int arg) const { return m_hover_id==id && m_hover_arg==arg; }
   //--- widgets
   void              Button(const int id,const int arg,const double x1,const double y1,const double x2,const double y2,const string t,const bool on=false,const int chev=0);
   void              Link(const int id,const int arg,const double x2,const double y1,const double y2,const string t,const bool open);
   void              Segments(const int id,const int argbase,const double x1,const double y1,const double x2,const double y2,const string &opts[],const int n,const int sel,const int fsize,const bool air=false);
   void              FieldBox(const int fid,const double x1,const double y1,const double x2,const double y2,const bool left=false);
   int               FitSize(string &t,const double maxw,const int f,const int s0);
   void              ValueBox(const double x1,const double y1,const double x2,const double y2,const string t,const bool drop_dec=false);
   void              Switch(const int key,const double x2,const double ymid,const bool on);
   //--- sections
   void              Build();
   void              DrawHeader();
   void              DrawMark(const double lx,const double lymid);
   double            DrawWordmark(const double lx,const double lymid,const color c);
   void              SpreadText(const double rx,const double ymid,const double room,const string unit);
   double            BuildMain(double y);
   double            BuildQuick(double y);
   void              RiskChips(const double x1,const double x2,const double y,const bool bare=false,const double h=26.0);
   void              RiskRow(const double y);
   double            BuildCosts(double y);
   string            CostMoney(const double v,const string mid,const bool sign);
   void              CostRow(const double y,const string label,const string mid,const color midc,const string val,const color valc);
   double            BuildPositions(double y);
   void              DrawFooter();
   void              ActionButton(const double x1,const double y1,const double x2,const double y2,const bool one_line);
   void              BuildStrip();
   void              StripResult(const double x1,const double y1,const double x2,const double y2);
   void              IconEye(const double cx0,const double c,const double hy1,const double hy2);
   void              IconCollapse(const double cx2,const double c,const double hy1,const double hy2);
   void              DrawPinned();
   void              ResLine(const double xl,const double rr,const double ymid,const string label,const string mny,const string mny_short,const string second,const bool grey=false);
   void              DrawScrollbar();
   void              EdgeMask();
   string            FitMoney(const double v,const double maxw,const int f,const int size10,const bool sign=false);
   double            BuildMenu(double y);
   void              Frame();
   //--- menu rows
   double            MToggle(const double y,const int key,const string label,const bool on,const bool danger=false);
   double            MSeg(const double y,const int key,const string label,const string opts,const int sel);
   double            MNum(const double y,const int fid,const string label,const string suffix="",const bool left=false,const double w=76);
   double            MText(const double y,const string label,const string value);
   double            MNote(const double y,const string text,const color c);
   double            MSection(const double y,const int idx,const string title,const string sub="",const color subc=clrNONE);
   int               HitAt(const int mx,const int my) const;
  };

void CPlPanel::SetFont(const int f,const int size10)
  {
   if(m_fcur_f==f && m_fcur_s==size10) return;
   string nm=(f==FN_BRAND)?"Consolas":(f==FN_SB)?"Segoe UI Semibold":"Segoe UI";
   //--- numbers are Segoe UI too: its digits share one width (0.539 em), so columns hold without a monospace face, and a plain
   //--- zero reads as money, not as code. Segoe UI Semibold is not tabular (its 1 is narrower), it never draws a changing number.
   //--- Consolas at weight 600 is only the fallback of the wordmark when its picture atlas cannot be read
   m_cv.FontSet(nm,-(int)MathRound(size10*m_fs),(f==FN_BRAND)?FW_SEMIBOLD:0);
   m_fcur_f=f; m_fcur_s=size10;
  }

int CPlPanel::TextH(const int f,const int size10)
  {
   int key=size10/5; if(key>39) key=39;
   if(m_th_cache[f][key]>0) return m_th_cache[f][key];
   SetFont(f,size10);
   int h=m_cv.TextHeight("Ag0");
   m_th_cache[f][key]=h;
   return h;
  }

//--- the biggest of s0, 80, 70 at which t fits maxw; at 70 a longer text is cut and ends in "..."
int CPlPanel::FitSize(string &t,const double maxw,const int f,const int s0)
  {
   int s=s0;
   if(TextW(t,f,s)<=maxw) return s;
   if(s>80) { s=80; if(TextW(t,f,s)<=maxw) return s; }
   if(s>70) { s=70; if(TextW(t,f,s)<=maxw) return s; }
   t=CutPhrase(t,"",maxw,f,s)+"...";
   return s;
  }

//--- t cut for "..." and the tail tl to fit maxw at size s, and the cut falls on a word: a phrase that is cut inside a word reads as
//--- another word ("No new quot..."). The head goes back to the end of the last whole word and loses the comma or colon that stood
//--- after it. A text with no space (a symbol, a number) is cut by the character as before, and so is a first word that is too long
string CPlPanel::CutPhrase(const string t,const string tl,const double maxw,const int f,const int s)
  {
   string h=t;
   while(StringLen(h)>4 && TextW(h+"..."+tl,f,s)>maxw) h=StringSubstr(h,0,StringLen(h)-1);
   const int n=StringLen(h);
   if(n<StringLen(t) && StringGetCharacter(t,n)!=' ')       // the cut stands inside a word
     {
      for(int i=n-1;i>=3;i--)
         if(StringGetCharacter(h,i)==' ') { h=StringSubstr(h,0,i); break; }
     }
   if(n<StringLen(t))
      while(StringLen(h)>4)
        {
         const ushort c=StringGetCharacter(h,StringLen(h)-1);
         if(c==' ' || c==',' || c==':' || c==';') h=StringSubstr(h,0,StringLen(h)-1);
         else break;
        }
   return h;
  }

//--- the biggest of s0, 80, 70 at which t fits maxw, 0 when none does
int CPlPanel::FitStep(const string t,const double maxw,const int f,const int s0)
  {
   if(TextW(t,f,s0)<=maxw) return s0;
   if(s0>80 && TextW(t,f,80)<=maxw) return 80;
   if(s0>70 && TextW(t,f,70)<=maxw) return 70;
   return 0;
  }

//--- a phrase that fits maxw: the font steps down 90, 80, 70 first; a phrase that is still too long loses the middle of its
//--- first part, never the tail after the last comma or middle dot ("Filled 3.28 in 3 ord... · risk $19.34": the risk is what counts).
//--- A result with a price ("Placed Buy Limit 2.70 at 1.32500 · risk $399.60") is the other way round: the price is what the trader
//--- checks against the chart and the risk stands in the card, so the risk goes first, then the words shorten, and the price is never cut
int CPlPanel::FitTail(string &t,const double maxw,const int f,const int s0,const string alt)
  {
   int s=s0;
   if(TextW(t,f,s)<=maxw) return s;
   if(s>80) { s=80; if(TextW(t,f,s)<=maxw) return s; }
   //--- a short form of the phrase (alt, from Strings.mqh): the long one stays while it fits at 90 or 80; then the short one at 90, 80, 70;
   //--- the long one at 70 comes after them only when there is no short one. What is still too long is cut as a short one
   if(alt!="" && alt!=t)
     {
      const int az[3]={s0,80,70};
      for(int i=0;i<3;i++)
         if(az[i]<=s0 && TextW(alt,f,az[i])<=maxw) { t=alt; return az[i]; }
      t=alt;
      s=MathMin(s0,70);
     }
   else if(s>70) { s=70; if(TextW(t,f,s)<=maxw) return s; }
   //--- the "(planned $480.00)" of a fill goes before any of the risk figure does, and what is left tries the bigger sizes again
   const int pln=StringFind(t,PLS_PLANNED_SP,0);
   if(pln>0)
     {
      t=StringSubstr(t,0,pln);
      if(TextW(t,f,s0)<=maxw) return s0;
      if(s0>80 && TextW(t,f,80)<=maxw) return 80;
      if(TextW(t,f,s)<=maxw) return s;
     }
   const int pat=StringFind(t,PLS_AT,0), prk=StringFind(t,PlDotSep()+PLS_RISK_SP_LC,0);
   if(pat>0 && prk>pat)
     {
      t=StringSubstr(t,0,prk);
      int fs=FitStep(t,maxw,f,s0);
      if(fs>0) return fs;
      StringReplace(t,PLS_STOP_LIMIT_SUFFIX,PLS_STOP_LIMIT_SHORT_SUFFIX);
      fs=FitStep(t,maxw,f,s0);
      if(fs>0) return fs;
      if(StringFind(t,PLS_PLACED_SP,0)==0) t=StringSubstr(t,StringLen(PLS_PLACED_SP));
      fs=FitStep(t,maxw,f,s0);
      if(fs>0) return fs;
      //--- the short type names of the strip (Lmt, Stp, S-L): "Buy Lmt 2.98 at 1.12105"
      StringReplace(t,PLS_STOP_LIMIT_SHORT_SUFFIX," "+PLS_KIND_SL_S);
      StringReplace(t,PLS_LIMIT_SUFFIX," "+PLS_KIND_LMT_S);
      StringReplace(t,PLS_STOP_SUFFIX," "+PLS_KIND_STP_S);
      fs=FitStep(t,maxw,f,s0);
      if(fs>0) return fs;
      //--- still too long: what stands before the price gives way, from its end
      const int pp=StringFind(t,PLS_AT,0);
      string hd=StringSubstr(t,0,pp);
      const string px=StringSubstr(t,pp);
      t=CutPhrase(hd,px,maxw,f,70)+"..."+px;
      return MathMin(s0,70);
     }
   int last=-1;                                   // the last separator of the phrase, a comma or the middle dot of a result
   for(int p=StringFind(t,", ",0);p>=0;p=StringFind(t,", ",p+1)) last=p;
   const string dot=PlDotSep();
   for(int p=StringFind(t,dot,0);p>=0;p=StringFind(t,dot,p+1)) last=MathMax(last,p);
   string head=(last>0)?StringSubstr(t,0,last):t;
   const string tail=(last>0)?StringSubstr(t,last):"";
   if(last>0 && TextW(tail,f,s)>maxw*0.6) { head=t; last=-1; }
   const string tl=(last>0)?tail:"";
   t=CutPhrase(head,tl,maxw,f,s)+"..."+tl;
   return s;
  }

double CPlPanel::TextW(const string t,const int f,const int size10)
  {
   SetFont(f,size10);
   return m_cv.TextWidth(t)/m_s;
  }

//--- a plain number that fits maxw logical px, leading digits never cut: first the decimal part goes
//--- (drop_dec only: distances in points; a price keeps every digit, a rounded price would read as another price),
//--- then the font shrinks by 5 tenths of a point down to smin; at smin it is kept whole and may touch the border.
//--- Not a plain number: s0, the text as is.
int CPlPanel::FitNumber(string &t,const double maxw,const int f,const int s0,const int smin,const bool drop_dec)
  {
   if(TextW(t,f,s0)<=maxw) return s0;
   const int n=StringLen(t);
   for(int i=0;i<n;i++)
     {
      ushort c=StringGetCharacter(t,i);
      if(!((c>='0' && c<='9') || c=='.' || c=='-' || c=='+')) return s0;
     }
   if(drop_dec && StringFind(t,".")>=0) t=DoubleToString(StringToDouble(t),0);
   int s=s0;
   while(TextW(t,f,s)>maxw && s>smin) s-=5;
   return s;
  }

//--- a money text that fits maxw logical px: the full form, else the short form ($12.5k)
string CPlPanel::FitMoney(const double v,const double maxw,const int f,const int size10,const bool sign)
  {
   string t=PlMoney(v,g_acc.currency,g_acc.currency_digits,sign);
   if(TextW(t,f,size10)<=maxw) return t;
   return PlMoneyShort(v,g_acc.currency,g_acc.currency_digits,sign);
  }

//--- align 0 left, 1 right, 2 center around lx; vertically centered on lymid
void CPlPanel::Txt(const double lx,const double lymid,const string t,const color c,const int f,const int size10,const int align)
  {
   if(m_dry || t=="") return;
   SetFont(f,size10);
   int h=TextH(f,size10);
   int y=Y_(lymid)-h/2;
   uint fl=TA_TOP|((align==1)?TA_RIGHT:(align==2)?TA_CENTER:TA_LEFT);
   m_cv.TextOut(X_(lx),y,t,PlArgb(c),fl);
  }

void CPlPanel::FillL(const double lx1,const double ly1,const double lx2,const double ly2,const color c)
  {
   if(m_dry) return;
   m_cv.Fill(X_(lx1),Y_(ly1),X_(lx2)-1,Y_(ly2)-1,PlArgb(c));
  }

void CPlPanel::RndL(const double lx1,const double ly1,const double lx2,const double ly2,const double r,const color c)
  {
   if(m_dry) return;
   m_cv.RR(X_(lx1),Y_(ly1),X_(lx2)-1,Y_(ly2)-1,P(r),PlArgb(c));
  }

void CPlPanel::BoxL(const double lx1,const double ly1,const double lx2,const double ly2,const double r,const color fill,const color border)
  {
   if(m_dry) return;
   m_cv.Box(X_(lx1),Y_(ly1),X_(lx2)-1,Y_(ly2)-1,P(r),PlArgb(fill),PlArgb(border));
  }

void CPlPanel::Div(const double ly)
  {
   if(m_dry) return;
   int y=Y_(ly);
   m_cv.Fill(1,y,m_w-2,y,PlArgb(g_th.line));
  }

//--- register a hit rectangle, clipped to the visible body
void CPlPanel::Reg(const int id,const int arg,const double lx1,const double ly1,const double lx2,const double ly2)
  {
   if(m_nh>=PL_MAX_HITS) return;
   int x1=X_(lx1), x2=X_(lx2)-1, y1=Y_(ly1), y2=Y_(ly2)-1;
   //--- the quick panel has no scrolling body: its type strip stands on the footer edge and is hit whole
   const bool fixed_hit=(id==H_QKIND);
   if(id!=H_HEADER && id!=H_MENU && id!=H_COLLAPSE && id!=H_LINES && id!=H_ACTION && id!=H_SWAP && id!=H_CANCEL && id!=H_COSTS && !fixed_hit)
     {
      if(y2<m_vis_top || y1>m_vis_bot) return;
      if(y1<m_vis_top) y1=m_vis_top;
      if(y2>m_vis_bot) y2=m_vis_bot;
     }
   m_hr[m_nh].id=id; m_hr[m_nh].arg=arg; m_hr[m_nh].x1=x1; m_hr[m_nh].y1=y1; m_hr[m_nh].x2=x2; m_hr[m_nh].y2=y2;
   m_nh++;
  }

//--- flat button: ghost with a thin outline, or filled when "on"
void CPlPanel::Button(const int id,const int arg,const double x1,const double y1,const double x2,const double y2,const string t,const bool on,const int chev)
  {
   Reg(id,arg,x1,y1,x2,y2);
   if(m_dry) return;
   bool hv=IsHover(id,arg);
   bool dn=(m_down_id==id && m_down_arg==arg && hv);
   color fill=on?g_th.accent_fill:(hv?g_th.hover:g_th.bg);
   color brd=on?g_th.accent_fill:g_th.border;
   color tc=on?g_th.on_accent:g_th.text;
   if(dn) fill=on?PlMix(g_th.accent_fill,g_th.text,0.15):PlMix(g_th.hover,g_th.text,0.06);
   BoxL(x1,y1,x2,y2,4,fill,brd);
   if(chev==0) Txt((x1+x2)/2.0,(y1+y2)/2.0,t,tc,FN_UI,90,2);
   else
     {
      //--- text and a small chevron as one group, centered
      double tw=TextW(t,FN_UI,90);
      double gx=(x1+x2)/2.0-(tw+16)/2.0;
      Txt(gx,(y1+y2)/2.0,t,tc,FN_UI,90,0);
      double cx=gx+tw+11, cy=(y1+y2)/2.0;
      double d=(chev==1)?1.0:-1.0;
      m_cv.Stroke(X_(cx-3.5),Y_(cy-1.8*d),X_(cx),Y_(cy+1.8*d),P(1.4),PlArgb(tc));
      m_cv.Stroke(X_(cx),Y_(cy+1.8*d),X_(cx+3.5),Y_(cy-1.8*d),P(1.4),PlArgb(tc));
     }
  }

//--- a link that opens something: grey text and a chevron at the right edge, no fill and no frame; the text lights up on hover
void CPlPanel::Link(const int id,const int arg,const double x2,const double y1,const double y2,const string t,const bool open)
  {
   const double w=TextW(t,FN_UI,90)+22;
   Reg(id,arg,x2-w-6,y1,x2+2,y2);
   if(m_dry) return;
   const bool hv=IsHover(id,arg);
   const color c=hv?g_th.text:g_th.text2;
   const double ym=(y1+y2)/2.0;
   Txt(x2-14,ym,t,c,FN_UI,90,1);
   const double cx=x2-5, d=open?-1.0:1.0;
   m_cv.Stroke(X_(cx-3.5),Y_(ym-1.8*d),X_(cx),Y_(ym+1.8*d),P(1.4),PlArgb(c));
   m_cv.Stroke(X_(cx),Y_(ym+1.8*d),X_(cx+3.5),Y_(ym-1.8*d),P(1.4),PlArgb(c));
  }

//--- flat segmented strip, the selected one filled
void CPlPanel::Segments(const int id,const int argbase,const double x1,const double y1,const double x2,const double y2,const string &opts[],const int n,const int sel,const int fsize,const bool air)
  {
   double w=(x2-x1)/n;
   if(!m_dry)
     {
      RndL(x1,y1,x2,y2,5,g_th.surface);
     }
   //--- air: the segments follow their labels. One size for the whole strip, the largest at which the bold widths plus
   //--- 8 px of air on each side fit the strip; every segment is its label plus that air, and what is left over is shared
   //--- equally, so the strip still spans x1..x2. The click areas and the selected pill use the same bounds.
   double bx[10];
   int sfs=fsize;
   if(air && n<=8)
     {
      double sum=0.0;
      for(;;)
        {
         sum=0.0;
         for(int i=0;i<n;i++) sum+=TextW(opts[i],FN_SB,sfs)+16.0;
         if(sum<=x2-x1 || sfs<=60) break;
         sfs-=10;
        }
      const double extra=MathMax(0.0,(x2-x1)-sum)/n;
      bx[0]=x1;
      for(int i=0;i<n;i++) bx[i+1]=(i==n-1)?x2:bx[i]+TextW(opts[i],FN_SB,sfs)+16.0+extra;
     }
   else
      for(int i=0;i<=n && i<10;i++) bx[i]=x1+w*i;
   for(int i=0;i<n;i++)
     {
      double a=bx[i], b=bx[i+1];
      Reg(id,argbase+i,a,y1,b,y2);
      if(m_dry) continue;
      bool hv=IsHover(id,argbase+i);
      int fs=air?sfs:fsize;                           // a long code shrinks to fit its segment, never overflows
      if(!air) while(fs>60 && TextW(opts[i],(i==sel)?FN_SB:FN_UI,fs)>w-6) fs-=10;
      if(i==sel)
        {
         RndL(a+2,y1+2,b-2,y2-2,4,g_th.accent_fill);
         Txt((a+b)/2.0,(y1+y2)/2.0,opts[i],g_th.on_accent,FN_SB,fs,2);
        }
      else
        {
         if(hv) RndL(a+2,y1+2,b-2,y2-2,4,g_th.hover);
         Txt((a+b)/2.0,(y1+y2)/2.0,opts[i],hv?g_th.text:g_th.text2,FN_UI,fs,2);
        }
     }
  }

#define MENU_GAP   14      // logical px between a menu caption and its field or strip
#define FLD_EDGE   12      // screen px the native edit keeps for itself left and right of its text: measured 4 + 6 at 96 and at 154 dpi, plus 2 spare
#define FLD_PT_MIN 6       // smallest edit font, points, at 96 dpi: 8 screen px of em; at a higher dpi the same em is fewer points (FieldPtMin)
#define FLD_PT_STEP 2      // the distance fields (pt) are widened until their digits fit at the panel font less this many points (not below the smallest)
//--- the smallest edit font in points: always the same 8 px of em (6 points at 96 dpi, 4 at 154), not 6 points on any screen
int CPlPanel::FieldPtMin()
  {
   return (int)MathMax(3.0,MathRound(FLD_PT_MIN*m_fs/m_s));
  }

//--- the text width (logical px) a native edit needs to show tx whole at pt points: the digits, the frame inset of FieldBox on both sides
//--- and the padding the edit keeps for itself, which is a fixed number of screen pixels, not a share of the font
double CPlPanel::FieldNeed(const string tx,const int pt)
  {
   return TextW(tx,FN_NUM,(int)MathRound(pt*10/m_fs))+10.0+FLD_EDGE/m_s;
  }

//--- the edit font (points) for the number of a field: its decimals drop first (pips), then the whole-point font steps down.
//--- The font is checked in whole points, the unit of the edit, so the digits never reach the padding of the edit
int CPlPanel::FieldPt(const int fid,string &tx,const double maxw,const int pt0)
  {
   if(TextW(tx,FN_NUM,(int)MathRound(pt0*10/m_fs))<=maxw) return pt0;
   const int tl=StringLen(tx);
   if(fid==PLF_RISK && tl>3 && StringSubstr(tx,tl-3)==".00") tx=StringSubstr(tx,0,tl-3);     // an even amount loses its cents first, nothing is rounded
   const int pmin=FieldPtMin();
   const int s=FitNumber(tx,maxw,FN_NUM,(int)MathRound(pt0*10/m_fs),(int)MathRound(pmin*10/m_fs),fid==PLF_SL_PIPS || fid==PLF_TP_PIPS);
   int pt=(int)MathRound(s*m_fs/10.0);
   if(pt>pt0) pt=pt0;
   while(pt>pmin && TextW(tx,FN_NUM,(int)MathRound(pt*10/m_fs))>maxw) pt--;
   if(pt<pmin) pt=MathMin(pmin,pt0);
   return pt;
  }

//--- the SL and TP distance fields take width from the price fields when their digits do not fit at the panel font less FLD_PT_STEP points in the
//--- 46 px they have (BTCUSD, indices and gold in points reach six digits). The width follows from the texts alone, no state; the
//--- price fields keep what is left (the Entry row follows) and step their font down by themselves. At most so far that the price
//--- fields still hold their own digits at that same font, so the price is never set smaller than the distance; the distance font
//--- then steps down as before.
void CPlPanel::WidenPips(const double fx1,double &fx2,double &px1,const double px2,double &hx)
  {
   const int ptw=MathMax(FieldPtMin(),g_fl_font10/10-FLD_PT_STEP);
   double need=0.0, pneed=0.0;
   const int pf[2]={PLF_SL_PIPS,PLF_TP_PIPS};
   const int pr[3]={PLF_SL_PRICE,PLF_TP_PRICE,PLF_ENTRY};
   for(int i=0;i<2;i++)
     {
      if(i==0 && (g_cfg.no_sl || g_cfg.atr_on)) continue;           // the SL distance is not typed
      string t=PlFieldText(pf[i]);
      if(StringFind(t,".")>=0 && FieldNeed(t,ptw)>px2-px1) t=DoubleToString(StringToDouble(t),0);     // as FieldPt drops them
      need=MathMax(need,FieldNeed(t,ptw));
     }
   if(need<=px2-px1) return;
   for(int i=0;i<3;i++) pneed=MathMax(pneed,FieldNeed(PlFieldText(pr[i]),ptw));
   double left=px2-need-0.5;                                      // half a logical px over: the font check of FieldBox must not fail on rounding
   left=MathMax(left,fx1+pneed+4.0);
   if(left>=px1) return;
   px1=left; fx2=px1-4.0; hx=fx2+6.0;
  }

//--- a field: canvas draws the frame, a native edit sits inside
void CPlPanel::FieldBox(const int fid,const double x1,const double y1,const double x2,const double y2,const bool left)
  {
   if(m_dry) return;
   bool bad=g_fl_bad[fid];
   BoxL(x1,y1,x2,y2,4,g_th.bg,bad?g_th.sell:g_th.field_border);
   int ex1=X_(x1)+P(5), ex2=X_(x2)-P(5);
   int ey1=Y_(y1)+P(3), ey2=Y_(y2)-P(3);
   if(ey1<m_vis_top || ey2>m_vis_bot) return;   // not fully visible: leave the edit hidden
   //--- a number wider than the edit drops its decimals, then uses a smaller whole-point font (the edit takes points)
   string tx=PlFieldText(fid);
   const int pt0=g_fl_font10/10;
   int pt=pt0;
   const double maxw=(x2-x1)-10.0-FLD_EDGE/m_s;     // the frame inset of the edit (5 px each side) and the padding of its text
   if(!left)
     {
      pt=FieldPt(fid,tx,maxw,pt0);
      //--- the SL and TP fields of one column (price, pips) share one font: the smaller of the two
      const int pf=(fid==PLF_SL_PRICE)?PLF_TP_PRICE:(fid==PLF_SL_PIPS)?PLF_TP_PIPS:(fid==PLF_TP_PRICE)?PLF_SL_PRICE:(fid==PLF_TP_PIPS)?PLF_SL_PIPS:-1;
      const bool pf_shown=(pf==PLF_TP_PRICE || pf==PLF_TP_PIPS) || (!g_cfg.no_sl && !g_cfg.atr_on);     // the SL fields are not typed with no SL or an ATR stop
      if(pf>=0 && pf_shown)
        {
         string px=PlFieldText(pf);
         pt=MathMin(pt,FieldPt(pf,px,maxw,pt0));
        }
     }
   PlFldReg(fid,ex1,ey1,ex2-ex1,ey2-ey1,tx,left,(pt==pt0)?0:pt);
  }

void CPlPanel::ValueBox(const double x1,const double y1,const double x2,const double y2,const string t,const bool drop_dec)
  {
   if(m_dry) return;
   BoxL(x1,y1,x2,y2,4,g_th.surface,g_th.surface);
   string tx=t;
   const int fs=FitNumber(tx,(x2-x1)-10,FN_NUM,90,60,drop_dec);
   Txt(x2-7,(y1+y2)/2.0,tx,g_th.text2,FN_NUM,fs,1);
  }

void CPlPanel::Switch(const int key,const double x2,const double ymid,const bool on)
  {
   double x1=x2-32;
   Reg(H_TOG,key,0,ymid-15,PL_W,ymid+15);            // the whole row of the menu is the click area, not the 36 x 24 switch
   if(m_dry) return;
   RndL(x1,ymid-9,x2,ymid+9,9,on?g_th.accent_fill:PlMix(g_th.bg,g_th.text2,g_th.dark?0.58:0.8));
   double kx=on?(x2-9):(x1+9);
   m_cv.Disc(X_(kx),Y_(ymid),P(6.5),PlArgb(clrWhite));
  }

//--- the sign of the brand: three neon trade lines, TP above, Entry, SL below (a 1:2 trade), on a dark rounded plate, the
//--- same plate as the icon of the Navigator. The plate keeps the lines neon in the light theme too and
//--- sets the sign apart from the plain three bars of the menu button next to it. 24 logical px in the 34 px header: at 100
//--- percent the lines are 2 px with a 3 px gap between Entry and SL, so three lines stay three lines at every scale.
void CPlPanel::DrawMark(const double lx,const double lymid)
  {
   if(m_dry) return;
   const int sz=P(24.0);
   const int x0=X_(lx), y0=Y_(lymid)-sz/2;
   const int r=(int)MathMax(3.0,MathRound(5.5*m_s));
   if(g_th.dark) m_cv.Box(x0,y0,x0+sz-1,y0+sz-1,r,PlArgb(C'31,34,42'),PlArgb(C'58,63,75'));
   else          m_cv.RR(x0,y0,x0+sz-1,y0+sz-1,r,PlArgb(C'22,24,29'));
   const double ys[3]={5.0,15.0,20.0};
   const int ids[3]={3,0,2};                          // TP1, Entry, SL
   const double t=MathMax(2.0,MathRound(2.0*m_s));
   //--- line ends on whole pixels, the line centred on the pixel grid, so a 2 or 3 px line is exactly 2 or 3 rows
   const double xa=x0+MathRound(5.0*m_s)+t/2.0, xb=x0+sz-MathRound(5.0*m_s)-t/2.0;
   for(int i=0;i<3;i++)
     {
      const color c=PlLineColorSet(ids[i],true);
      const double y=y0+MathRound(ys[i]*m_s)-MathFloor(t/2.0)+t/2.0;
      for(int j=3;j>=1;j--) m_cv.Stroke(xa,y,xb,y,t+1.4*m_s*j,PlArgb(c,26));
      m_cv.Stroke(xa,y,xb,y,t,PlArgb(c));
      if(t>=3.0) m_cv.Stroke(xa,y,xb,y,t*0.4,PlArgb(PlMix(c,clrWhite,0.7),150));
     }
  }

//--- the wordmark "plainlines" in JetBrains Mono Bold, as the Plainbook header writes its name. The picture of the nearest panel
//--- scale is blended in the text colour; if the atlas cannot be read, the name is written in Consolas. Returns the logical width.
double CPlPanel::DrawWordmark(const double lx,const double lymid,const color c)
  {
   if(m_wm_w==0)
     {
      uint w=0,h=0;
      m_wm_w=(ResourceReadImage("::Images\\PlWordmark.bmp",m_wm,w,h) && w>0 && h>0)?(int)w:-1;
     }
   if(m_wm_w<0)
     {
      if(!m_dry) Txt(lx,lymid,PLS_BRAND,c,FN_BRAND,100);
      return TextW(PLS_BRAND,FN_BRAND,100);
     }
   int k=0;
   for(int i=1;i<PL_WM_N;i++) if(MathAbs(PL_WM_S[i]-m_s)<MathAbs(PL_WM_S[k]-m_s)) k=i;
   const double adv=PL_WM_ADV[k]*PL_WM_S[k]/m_s;
   if(m_dry) return adv;
   const int x0=X_(lx)+PL_WM_DX[k], y0=Y_(lymid)+PL_WM_DY[k];
   const uint fg=PlArgb(c);
   const int n=ArraySize(m_wm);
   for(int j=0;j<PL_WM_H[k];j++)
      for(int i=0;i<PL_WM_W[k];i++)
        {
         const int idx=(PL_WM_Y[k]+j)*m_wm_w+i;
         if(idx>=n) continue;
         const uint v=m_wm[idx]&0xFF;
         if(v>0) m_cv.Over(x0+i,y0+j,fg,v/255.0);
        }
   return adv;
  }

//--- the lines switch: the eye centred on cx,c with the click area from hy1 to hy2 (the header height, or the strip row)
void CPlPanel::IconEye(const double cx0,const double c,const double hy1,const double hy2)
  {
   Reg(H_LINES,0,cx0-14,hy1,cx0+14,hy2);
   if(m_dry) return;
   bool hv=IsHover(H_LINES,0);
   if(hv || PlLinesOn()) RndL(cx0-12,c-12,cx0+12,c+12,5,g_th.hover);
   color ic=PlLinesOn()?g_th.accent:g_th.text2;
   m_cv.Lens(X_(cx0),Y_(c),P(7),P(4.5),P(1.5),PlArgb(ic));
   m_cv.Disc(X_(cx0),Y_(c),P(2.2),PlArgb(ic));
   if(!PlLinesOn())
     {
      //--- struck through: a gap in the plate color, then the slash
      m_cv.Stroke(X_(cx0-6),Y_(c+6),X_(cx0+6),Y_(c-6),P(3.6),PlArgb(hv?g_th.hover:g_th.bg));
      m_cv.Stroke(X_(cx0-6),Y_(c+6),X_(cx0+6),Y_(c-6),P(1.5),PlArgb(ic));
     }
  }

//--- the view switch: a chevron down on the quick panel (open the full one), a minus on the full panel (back to the quick one)
void CPlPanel::IconCollapse(const double cx2,const double c,const double hy1,const double hy2)
  {
   Reg(H_COLLAPSE,0,cx2-14,hy1,cx2+14,hy2);
   if(m_dry) return;
   bool hv=IsHover(H_COLLAPSE,0);
   if(hv) RndL(cx2-12,c-12,cx2+12,c+12,5,g_th.hover);
   if(g_cfg.quick)
     {
      m_cv.Stroke(X_(cx2-5),Y_(c-2.5),X_(cx2),Y_(c+2.5),P(1.6),PlArgb(g_th.text2));
      m_cv.Stroke(X_(cx2),Y_(c+2.5),X_(cx2+5),Y_(c-2.5),P(1.6),PlArgb(g_th.text2));
     }
   else
      m_cv.Fill(X_(cx2-5.5),Y_(c)-P(0.8),X_(cx2+5.5),Y_(c)+P(0.8)-1,PlArgb(g_th.text2));
  }

//-------------------------------------------------------------------------------------------------
bool PlEnteredRisk(double &money,double &pct);
string PlNumTrim(const double v,const int digits);

//-------------------------------------------------------------------------------------------------
void CPlPanel::DrawHeader()
  {
   m_off=0;
   m_vis_top=0;
   string sym=g_sym.name;
   //--- header surface over whatever the body drew
   if(!m_dry)
     {
      int hy=P(PL_HDR);
      int rr=P(6);
      m_cv.Fill(rr,1,m_w-1-rr,hy-1,PlArgb(g_th.bg));
      m_cv.Fill(1,rr,rr-1,hy-1,PlArgb(g_th.bg));
      m_cv.Fill(m_w-rr,rr,m_w-2,hy-1,PlArgb(g_th.bg));
     }
   Reg(H_HEADER,0,0,0,PL_W,PL_HDR);
   const double lim_x=g_cfg.quick?(PL_W-PL_PAD-12-28-12-6):(PL_W-PL_PAD-12-28-28-12-6);       // the text never runs under the icon buttons
   if(g_cfg.quick)
     {
      if(!m_dry)
        {
         //--- the quick panel has no status row, so its header says what the status line would when there is something to say (the dot
         //--- is the status color: ok, amber, red); otherwise the risk of the trade, which is what the three buttons below set
         string st,sta; color stc,dot;
         PlStatus(st,stc,dot,sta);
         m_cv.Disc(X_(PL_PAD+4),Y_(PL_HDR/2.0),P(4),PlArgb(dot));
         const double sx=PL_PAD+16;
         string sy=sym;
         const int sfs=FitSize(sy,lim_x-sx,FN_SB,100);
         Txt(sx,PL_HDR/2.0,sy,g_th.text,FN_SB,sfs);
         const double x=sx+TextW(sy,FN_SB,sfs)+10;
         const double room=lim_x-x;
         if((g_msg!="" && GetTickCount64()<g_msg_until) || dot!=g_th.ok)
           {
            const int fs=FitTail(st,room,FN_UI,90,sta);
            Txt(x,PL_HDR/2.0,st,stc,FN_UI,fs);
           }
         else
           {
            //--- the risk in money and percent, as the Risk line of the full panel writes it: short money, then no percent, then a smaller font
            string t="";
            color rc=g_th.text2;
            if(g_cfg.no_sl) t=PLS_Q_NO_SL;
            else
              {
               double mny=0.0, pct=0.0;
               if(g_plan.ok && g_res.lot>0.0 && g_res.risk_money>0.0) { mny=g_res.risk_money; pct=g_res.risk_percent; }
               else if(PlEnteredRisk(mny,pct)) rc=PlMix(g_th.text2,g_th.bg,0.3);                  // typed, not counted yet: quieter
               if(mny>0.0)
                 {
                  const string rm=PlMoney(mny,g_acc.currency,g_acc.currency_digits), rs=PlMoneyShort(mny,g_acc.currency,g_acc.currency_digits);
                  const string ps=" "+ShortToString(0xB7)+" "+PlPctText(pct);
                  t=rm+ps;
                  if(TextW(t,FN_NUM,90)>room) t=rs+ps;
                  if(TextW(t,FN_NUM,90)>room) t=rm;
                  if(TextW(t,FN_NUM,90)>room) t=rs;
                 }
              }
            if(t!="")
              {
               int fs=90;
               while(fs>80 && TextW(t,FN_NUM,fs)>room) fs-=5;
               Txt(x,PL_HDR/2.0,t,rc,FN_NUM,fs);
              }
           }
        }
     }
   else if(!m_dry)
     {
      //--- the sign and the wordmark lead; the symbol after them is quieter (text2) and fits what is left up to the menu button
      DrawMark(PL_PAD-2.0,PL_HDR/2.0);
      const double wx=PL_PAD+30.0;
      const double x=wx+DrawWordmark(wx,PL_HDR/2.0,g_th.text)+10;
      string sy=sym;
      const int sfs=FitSize(sy,lim_x-x,FN_UI,90);
      Txt(x,PL_HDR/2.0,sy,g_th.text2,FN_UI,sfs);
     }
   //--- icon buttons
   double cx2=PL_W-PL_PAD-12;        // collapse button centre
   double cx1=cx2-28;                // menu button centre
   //--- the lines switch: an eye left of the menu (left of the expand button on the quick panel), pressed while the lines are on the chart;
   //--- in the header because it is needed in the middle of a trade, when the lines hide the price, also on the quick panel
   double cx0=g_cfg.quick?cx1:(cx1-28);
   IconEye(cx0,PL_HDR/2.0,0,PL_HDR);
   if(!g_cfg.quick)
     {
      Reg(H_MENU,0,cx1-14,0,cx1+14,PL_HDR);               // the click area is the header height and 28 wide, the plate drawn on hover stays 24
      if(!m_dry)
        {
         bool hv=IsHover(H_MENU,0);
         if(hv || menu) RndL(cx1-12,PL_HDR/2.0-12,cx1+12,PL_HDR/2.0+12,5,g_th.hover);
         color ic=menu?g_th.accent:g_th.text2;
         if(menu)
           {
            // close glyph while the menu is open
            double c=PL_HDR/2.0;
            m_cv.Stroke(X_(cx1-5),Y_(c-5),X_(cx1+5),Y_(c+5),P(1.6),PlArgb(ic));
            m_cv.Stroke(X_(cx1-5),Y_(c+5),X_(cx1+5),Y_(c-5),P(1.6),PlArgb(ic));
           }
         else
           {
            for(int i=-1;i<=1;i++)
               m_cv.Fill(X_(cx1-6),Y_(PL_HDR/2.0+i*4.5)-P(0.8),X_(cx1+6),Y_(PL_HDR/2.0+i*4.5)+P(0.8)-1,PlArgb(ic));
           }
        }
     }
   IconCollapse(cx2,PL_HDR/2.0,0,PL_HDR);
   Div(PL_HDR);
  }

//-------------------------------------------------------------------------------------------------
//--- the pinned status area under the header: height of its rows (a build with more checks adds a row of its own)
//--- without a start balance and both limits there are no rooms to show: the status line says what is missing, and "Day left $0.00" would read as a spent day
bool PlLimRowOn()
  {
   return false;
  }

double PlPinH()
  {
   return PL_STATUS_H+(PlLimRowOn()?14.0:0.0);
  }

//--- one line of the result block: the label at xl, the money and the second value right-aligned at rr
//--- the risk the user typed, in both units: before a lot is counted the Risk line shows it in grey
bool PlEnteredRisk(double &money,double &pct)
  {
   money=0.0; pct=0.0;
   if(g_cfg.no_sl) return false;
   double base=(g_cfg.base==PL_BASE_EQUITY)?g_acc.equity:g_acc.balance;
   if(g_cfg.subtract_open) base-=g_acc.open_risk_money+g_acc.pending_risk_money;
   if(base<=PL_EPS) return false;
   if(g_dr.unit_money)
     {
      money=g_dr.risk_money;
      pct=money/base*100.0;
     }
   else
     {
      pct=g_dr.risk_pct;
      money=PlFloorDigits(base*pct/100.0,g_acc.currency_digits);
     }
   return (money>0.0);
  }

void CPlPanel::ResLine(const double xl,const double rr,const double ymid,const string label,const string mny,const string mny_short,const string second,const bool grey)
  {
   Txt(xl,ymid,label,g_th.text2,FN_UI,80);
   const double room=rr-(xl+TextW(label,FN_UI,80)+8);
   string m=mny;
   string sec=second;
   //--- "UST 1,793.00 · 1:1.90" is wider than "$1,793.00 · 1:1.90": the short money, then smaller fonts, the ratio goes last
   int fm=90, fsec=80;
   if(sec!="" && TextW(m,FN_NUM,fm)+TextW(sec,FN_NUM,fsec)>room) m=mny_short;
   while(sec!="" && fm>80 && TextW(m,FN_NUM,fm)+TextW(sec,FN_NUM,fsec)>room) { fm-=5; fsec=MathMin(fsec,fm-5); }
   if(sec!="" && TextW(m,FN_NUM,fm)+TextW(sec,FN_NUM,fsec)>room) { sec=""; fm=90; }
   double x=rr;
   if(sec!="") { Txt(x,ymid,sec,g_th.text2,FN_NUM,fsec,1); x-=TextW(sec,FN_NUM,fsec); }
   Txt(x,ymid,m,grey?g_th.text2:g_th.text,FN_NUM,fm,1);
  }

//--- the rhythm of the main screen: one height for every control, 4 inside a group, a wider gap between groups
#define LY_RH      26.0      // logical px, a control row: strips, fields, link rows are drawn on it
#define LY_IG      4.0       // inside a group
#define LY_GG      10.0      // between groups
#define LY_TOP     10.0      // under the status line
#define LY_CARD    50.0      // the result card
#define LY_LBL_X   44.0      // the label column ends here, every field and strip starts here

//--- the quick strip of the risk, 0.5% 1% 2%: always percents of the base; a sum of money is typed in the field.
//--- Selected only when exactly this percent is in the field in the percent mode
//--- the strip writes them without the sign (one grey % stands after the group) and 28 high
int PlRiskChipSel()
  {
   const double pc[3]={0.5,1.0,2.0};
   int qsel=-1;
   for(int i=0;i<3;i++) if(!g_dr.unit_money && MathAbs(g_dr.risk_pct-pc[i])<1e-9) qsel=i;
   return qsel;
  }

void CPlPanel::RiskChips(const double x1,const double x2,const double y,const bool bare,const double h)
  {
   string qs[3];
   if(bare) { qs[0]="0.5"; qs[1]="1"; qs[2]="2"; }
   else { qs[0]="0.5%"; qs[1]="1%"; qs[2]="2%"; }
   Segments(H_CHIP,0,x1,y,x2,y+h,qs,3,PlRiskChipSel(),90);
  }

//--- the strip has no status row: a result of a send, a close or a move (a done or refused message that is not waiting to be read) stands in the place of the
//--- open button for 4 s, as the status line shows it in the full panel. The button is not drawn then, so it cannot be pressed by a double click either
bool PlStripResult()
  {
   if(!(g_cfg.quick && g_cfg.quick_style==0) || g_msg=="" || g_msg_sticky || g_flow==PL_FLOW_ARMED) return false;
   if(g_msg_kind!=1 && g_msg_kind!=2) return false;
   const ulong now=GetTickCount64();
   return (now<g_msg_until && now-g_msg_at<4000);
  }

void CPlPanel::StripResult(const double x1,const double y1,const double x2,const double y2)
  {
   if(m_dry) return;
   RndL(x1,y1,x2,y2,6,g_th.surface);
   string t=g_msg;
   const int fs=FitTail(t,(x2-x1)-8,FN_UI,90,PlAltOfPhrase(t));
   Txt((x1+x2)/2.0,(y1+y2)/2.0,t,(g_msg_kind==2)?g_th.sell:g_th.text,FN_UI,fs,2);
  }

//--- the quick strip: the whole panel is one row of 40. From the left: the handle with the status dot (the drag zone), the risk (the three
//--- buttons and one grey %; a fourth, selected segment names a risk that is none of the three, so the row never hides what stands),
//--- the type (Market and the second segment; Cancel in its place while a confirmation waits), the open button on what is left, the
//--- eye and the chevron. No symbol (the chart title has it), no status phrase (the dot and the button's reason say it), no flip button
void CPlPanel::BuildStrip()
  {
   const double y1=6.0, y2=34.0, ym=PL_STRIP_H/2.0;
   const double xe=PL_STRIP_W-6.0-56.0-6.0;                 // the open button ends here
   Reg(H_HEADER,0,0,0,26,PL_STRIP_H);
   if(!m_dry)
     {
      string st; color stc,dot;
      PlStatus(st,stc,dot);
      m_cv.Disc(X_(16),Y_(ym),P(4),PlArgb(dot));
     }
   //--- the risk: the quick percents, the field to type any risk and its unit, percent or money, as in the full panel
   double x=32.0, gx=136.0;
   if(g_cfg.no_sl)
      Txt(x+2,ym,PLS_Q_NO_SL,g_th.text2,FN_UI,90);
   else
     {
      RiskChips(x,x+90,y1,true,y2-y1);
      FieldBox(PLF_RISK,x+94,y1,x+152,y2);
      string us[2]; us[0]="%"; us[1]=PlCurrencyMark(g_acc.currency);
      const double wu=22.0+MathMax(22.0,TextW(us[1],FN_UI,90)+12.0);
      Segments(H_UNIT,0,x+156,y1,x+156+wu,y2,us,2,g_dr.unit_money?1:0,90);
      gx=x+156+wu;
     }
   //--- the type, or Cancel while the confirmation waits
   const double tx=gx+6.0;
   if(confirm_view) Button(H_CANCEL,0,tx,y1,tx+68,y2,PLS_CANCEL);
   else
     {
      string ks[2];
      ks[0]=PLS_KIND_MKT_S;
      ks[1]=(g_dr.kind==PL_KIND_STOP)?PLS_KIND_STP_S:(g_dr.kind==PL_KIND_STOP_LIMIT)?PLS_KIND_SL_S:PLS_KIND_LMT_S;
      Segments(H_QKIND,0,tx,y1,tx+68,y2,ks,2,(g_dr.kind==PL_KIND_MARKET)?0:1,90);
     }
   if(PlStripResult()) StripResult(tx+68+6,y1,xe,y2);
   else ActionButton(tx+68+6,y1,xe,y2,true);
   IconEye(xe+6+14,ym,y1,y2);
   IconCollapse(xe+6+42,ym,y1,y2);
  }

//--- the quick panel, the first thing a trader sees: the risk row of the main view, then the order type as two wide segments, Market and a
//--- second one named by the type that stands (Limit, Stop, Stop-Limit; the type follows the Entry line, so it can be a Stop). The open
//--- button is the footer below them
double CPlPanel::BuildQuick(double y)
  {
   const double lx=PL_PAD, rx=PL_W-PL_PAD, rh=LY_RH;
   y+=8;
   RiskRow(y);
   y+=rh+6;
   string ks[2];
   ks[0]=PLS_KIND_MARKET;
   ks[1]=(g_dr.kind==PL_KIND_STOP)?PLS_KIND_STOP:(g_dr.kind==PL_KIND_STOP_LIMIT)?PLS_KIND_STOPLIMIT_SHORT:PLS_KIND_LIMIT;
   Segments(H_QKIND,0,lx,y,rx,y+rh,ks,2,(g_dr.kind==PL_KIND_MARKET)?0:1,90);
   return y+rh;
  }

//--- the risk row: the quick strip, the field and the unit strip (with no SL: the lot field), 26 high at y.
//--- The main view and the quick panel draw the same row
void CPlPanel::RiskRow(const double y)
  {
   const double lx=PL_PAD, rx=PL_W-PL_PAD, rh=LY_RH;
   const string cur=g_acc.currency;
   const double cx=LY_LBL_X;
   if(g_cfg.no_sl)       // no SL: the lot that goes out is the fixed one
     {
      Txt(lx,y+rh/2.0,PLS_LOT,g_th.text2,FN_UI,90);
      FieldBox(PLF_LOT,cx,y,cx+78,y+rh);
      Txt(cx+88,y+rh/2.0,PLS_RISK_UNDEFINED,g_th.text2,FN_UI,80);
     }
   else
     {
      Txt(lx,y+rh/2.0,PLS_RISK,g_th.text2,FN_UI,90);
      RiskChips(cx,cx+96,y);
      FieldBox(PLF_RISK,cx+100,y,cx+174,y+rh);
      string us[2]; us[0]="%"; us[1]=PlCurrencyMark(cur);
      Segments(H_UNIT,0,222,y,rx,y+rh,us,2,g_dr.unit_money?1:0,90);
     }
  }

double CPlPanel::BuildMain(double y)
  {
   string cur=g_acc.currency;
   int cd=g_acc.currency_digits;
   const double lx=PL_PAD, rx=PL_W-PL_PAD;
   const double rh=LY_RH;
   y+=LY_TOP;
   //--- 2. order type
   string kinds[4]; kinds[0]=PLS_KIND_MARKET; kinds[1]=PLS_KIND_LIMIT; kinds[2]=PLS_KIND_STOP; kinds[3]=PLS_KIND_STOPLIMIT;
   if(TextW(PLS_KIND_MARKET,FN_SB,60)+TextW(PLS_KIND_LIMIT,FN_SB,60)+TextW(PLS_KIND_STOP,FN_SB,60)+TextW(PLS_KIND_STOPLIMIT,FN_SB,60)+64.0>rx-lx)
      kinds[3]=PLS_KIND_STOPLIMIT_SHORT;     // even proportional segments at size 60 cannot hold the full label: the short form
   Segments(H_KIND,0,lx,y,rx,y+rh,kinds,4,(int)g_dr.kind,90,true);
   y+=rh+LY_GG;
   //--- 3. risk: quick strip, the field, the unit strip
   const double cx=LY_LBL_X;
   RiskRow(y);
   y+=rh+LY_GG;

   //--- 4. prices: entry, SL, TP, the R field
   const double fx1=cx, px2=172, ux=177;
   double fx2=122, px1=126, hx=128;
   WidenPips(fx1,fx2,px1,px2,hx);
   const double rg=LY_IG;
   string unit=PlIsForex(g_sym)?PLS_PIP:PLS_PT;
   Txt(lx,y+rh/2.0,PLS_ENTRY,g_th.text2,FN_UI,90);
   if(g_dr.kind==PL_KIND_MARKET)
     {
      ValueBox(fx1,y,fx2,y+rh,DoubleToString((g_plan.ok&&g_plan.exec>0.0)?g_plan.exec:g_px.entry,g_sym.digits));
      string h=(g_plan.side==PL_SIDE_SELL)?PLS_BID:PLS_ASK;
      Txt(hx,y+rh/2.0,h,g_th.text2,FN_UI,80);
      SpreadText(rx,y+rh/2.0,rx-(hx+TextW(h,FN_UI,80)+10),unit);
     }
   else
     {
      FieldBox(PLF_ENTRY,fx1,y,fx2,y+rh);
      string h=g_plan.ok?PlSideTitle():"";
      if(g_dr.kind==PL_KIND_STOP_LIMIT) h=PLS_TRIGGER_BARE;
      Txt(hx,y+rh/2.0,h,g_th.text2,FN_UI,80);
      SpreadText(rx,y+rh/2.0,rx-(hx+TextW(h,FN_UI,80)+10),unit);
     }
   y+=rh+rg;
   if(g_dr.kind==PL_KIND_STOP_LIMIT)
     {
      Txt(lx,y+rh/2.0,PLS_LIMIT,g_th.text2,FN_UI,90);
      FieldBox(PLF_LIMIT,fx1,y,fx2,y+rh);
      Txt(hx,y+rh/2.0,PLS_LIMIT_PRICE,g_th.text2,FN_UI,80);
      y+=rh+rg;
     }
   //--- SL
   Txt(lx,y+rh/2.0,PLS_SL,g_th.text2,FN_UI,90);
   if(g_cfg.no_sl)
      ValueBox(fx1,y,px2,y+rh,PLS_NO_SL_ROW);           // no SL line and no SL in the order: nothing to type here
   else
     {
      if(g_cfg.atr_on)                                   // the ATR stop owns the SL: shown, not typed
        {
         const double ex=(g_plan.ok && g_plan.exec>0.0)?g_plan.exec:PlEstExec();
         ValueBox(fx1,y,fx2,y+rh,DoubleToString(g_px.sl,g_sym.digits));
         ValueBox(px1,y,px2,y+rh,PlFmtUnitField(PlToUnit(MathAbs(ex-g_px.sl))),true);
        }
      else
        {
         FieldBox(PLF_SL_PRICE,fx1,y,fx2,y+rh);
         FieldBox(PLF_SL_PIPS,px1,y,px2,y+rh);
        }
      Txt(ux,y+rh/2.0,unit,g_th.text2,FN_UI,80);
     }
   y+=rh+rg;
   //--- TP
   Txt(lx,y+rh/2.0,PLS_TP,g_th.text2,FN_UI,90);
   FieldBox(PLF_TP_PRICE,fx1,y,fx2,y+rh);
   FieldBox(PLF_TP_PIPS,px1,y,px2,y+rh);
   Txt(ux,y+rh/2.0,unit,g_th.text2,FN_UI,80);
   Txt(212,y+rh/2.0,PLS_R,g_th.text2,FN_UI,90,2);
   if(g_cfg.no_sl) ValueBox(222,y,rx,y+rh,"-");      // R has no meaning without an SL
   else FieldBox(PLF_TP_R,222,y,rx,y+rh);
   y+=rh+LY_GG;

   //--- 5. result card: the lot on the left, risk and reward on the right
   const bool subx=g_cfg.subtract_open;
   const double ch=LY_CARD;
   const double bh=subx?ch+14.0:ch;
   double by=y;
   RndL(lx,by,rx,by+bh,6,g_th.surface);
   if(!m_dry)
     {
      const double r1=by+ch*0.30, r2=by+ch*0.70;
      const string lot=PlLotText();
      const double xl=lx+10+TextW(lot,FN_SB,200)+14, rr=rx-10;
      const string dot=" "+ShortToString(0xB7)+" ";
      const bool has=g_plan.ok && g_res.lot>0.0;
      //--- a netting add: the risk is the whole position at the new SL (the number that can be lost), the reward counts the added lot
      //--- only, so each says its base and the ratio, which would divide one by the other, is not drawn. The lot above it is the added
      //--- lot, and its caption says so ("LOT · ADD", or "ADD" when the caption would run into the Risk label beside the lot)
      const bool nadd=(has && !g_cfg.no_sl && g_res.net_risk>PL_EPS);
      //--- with one TP the whole position closes there (a deal on netting sets the SL and TP of the position): the reward is the added
      //--- lot plus the open volume from its open price to that TP less its exit commission, on the same base as the risk, so the
      //--- ratio is drawn again. Several TP parts or an unknown value keep the reward of the added lot under its own label
      const bool nwhole=(nadd && g_net_gain_ok && g_cfg.tp_count<=1);
      const double rew=nwhole?(g_res.reward_total+g_net_gain-g_sym.net_vol*g_res.comm_out_1lot):g_res.reward_total;
      const double rrat=nwhole?((g_res.risk_money>0.0)?rew/g_res.risk_money:0.0):g_res.rr;
      string cap=PLS_LOT_CAPS;
      if(nadd)
        {
         cap=PLS_LOT_CAPS+dot+PLS_ADD_CAPS;
         if(TextW(cap,FN_UI,80)>xl-(lx+10)-6) cap=PLS_ADD_CAPS;
        }
      Txt(lx+10,by+ch*0.19,cap,g_th.text2,FN_UI,80);
      Txt(lx+10,by+ch*0.60,lot,g_th.text,FN_SB,200);
      if(has && g_cfg.no_sl)
        {
         Txt(xl,r1,PLS_RISK,g_th.text2,FN_UI,80);
         Txt(rr,r1,PLS_UNDEFINED,g_th.warn_text,FN_NUM,90,1);
        }
      else if(has && g_res.risk_money>0.0)
         ResLine(xl,rr,r1,(nadd && !nwhole)?PLS_RISK_POSITION:PLS_RISK,PlMoney(g_res.risk_money,cur,cd),PlMoneyShort(g_res.risk_money,cur,cd),dot+PlPctText(g_res.risk_percent));
      else
        {
         double em, ep;
         if(PlEnteredRisk(em,ep))
            ResLine(xl,rr,r1,PLS_RISK,PlMoney(em,cur,cd),PlMoneyShort(em,cur,cd),dot+PlPctText(ep),true);
         else
           {
            Txt(xl,r1,PLS_RISK,g_th.text2,FN_UI,80);
            Txt(rr,r1,"-",g_th.text2,FN_NUM,90,1);
           }
        }
      if(has && rew!=0.0)
         ResLine(xl,rr,r2,(nadd && !nwhole)?PLS_REWARD_ADD:PLS_REWARD,PlMoney(rew,cur,cd),PlMoneyShort(rew,cur,cd),(rrat>0.0 && (!nadd || nwhole))?dot+"1:"+DoubleToString(rrat,2):"");
      else
        {
         Txt(xl,r2,PLS_REWARD,g_th.text2,FN_UI,80);
         Txt(rr,r2,"-",g_th.text2,FN_NUM,90,1);
        }
      if(subx)
        {
         const double base=(g_cfg.base==PL_BASE_EQUITY)?g_acc.equity:g_acc.balance;
         const double sbase=MathMax(0.0,base-g_acc.open_risk_money-g_acc.pending_risk_money);
         Txt(lx+10,by+bh-9,PLS_NET_BASE+PlMoney(sbase,cur,cd),g_th.text2,FN_UI,80);
        }
     }
   y+=bh+LY_GG;
   //--- 6. the Costs or Positions block (the spread is in the Entry row, the Costs link in the status row)
   //--- the Positions header row stands here while Plainlines has positions or orders; a click opens the list (Costs open: Costs shows, one of the two at a time)
   const bool has_own=(g_own_pos+g_own_ord>0);
   if(m_pos_seen && !has_own) { m_scroll=0; pos_open=false; }       // the last position went: collapsed, and the main screen shows from its top again, not from where the block had scrolled it
   m_pos_seen=has_own;
   positions=(has_own && !costs);
   if(!costs && !positions) y+=2;                    // the body ends 12 above the footer divider
   if(costs)
     {
      m_costs_top=P(y);
      y=BuildCosts(y);
     }
   else if(positions)
     {
      m_costs_top=P(y);
      y=BuildPositions(y);
     }
   return y;
  }

//--- the spread of the symbol at the right end of the Entry row: "0.3 pip spread", only the number and unit when the word does not
//--- fit next to the hint, nothing when even that does not (the money of the spread is in Costs)
void CPlPanel::SpreadText(const double rx,const double ymid,const double room,const string unit)
  {
   if(m_dry) return;
   const string v=DoubleToString(PlToUnit(g_sym.ask-g_sym.bid),1)+" "+unit;
   const string w=" "+PLS_SPREAD;
   const double wv=TextW(v,FN_NUM,90), ww=TextW(w,FN_UI,80);
   if(wv+ww<=room) { Txt(rx,ymid,w,g_th.text2,FN_UI,80,1); Txt(rx-ww,ymid,v,g_th.text,FN_NUM,90,1); }
   else if(wv<=room) Txt(rx,ymid,v,g_th.text,FN_NUM,90,1);
   else if(TextW(v,FN_NUM,80)<=room) Txt(rx,ymid,v,g_th.text,FN_NUM,80,1);
  }

//--- the pinned status area: dot and phrase (or the outcome of a Positions action while it lasts), the rooms
void CPlPanel::DrawPinned()
  {
   if(m_dry) return;
   const int save_off=m_off;
   m_off=0;
   const double top=PL_HDR, h=PlPinH();
   m_cv.Fill(1,P(top),m_w-2,P(top+h)-1,PlArgb(g_th.bg));
   Div(top+h-1);
   string t,ta; color tc,dot;
   if(positions && pos_open && g_msg!="" && GetTickCount64()<g_msg_until)       // the outcome of a Positions action (closed, failed) while the list is on screen
     {
      t=g_msg; tc=(g_msg_kind==2 || g_msg_kind==4)?g_th.sell:(g_msg_kind==1 || g_msg_kind==3)?g_th.ok:g_th.text;
      dot=tc;
     }
   else PlStatus(t,tc,dot,ta);
   const double ym=top+PL_STATUS_H/2.0;
   m_cv.Disc(X_(PL_PAD+4),Y_(ym),P(4),PlArgb(dot));
   //--- the right end of the status row: the Costs link, fixed for every kind of order; the phrase gets what is left. A long phrase
   //--- steps down in size and loses its middle (FitTail)
   Link(H_COSTS,0,PL_W-PL_PAD,top,top+PL_STATUS_H,PLS_COSTS,costs);
   const double maxw=PL_W-PL_PAD-(PL_PAD+16)-(TextW(PLS_COSTS,FN_UI,90)+22.0)-8.0;
   const int fs=FitTail(t,maxw,FN_UI,90,ta);
   Txt(PL_PAD+16,ym,t,tc,FN_UI,fs);
   m_off=save_off;
  }

//--- the action row is pinned to the bottom of the panel: a tall body scrolls above it, never under it
#define PL_FOOT_H  44.0          // logical px: 5 gap, 34 button, 5 below
#define PL_QFOOT_H 50.0          // the quick panel: 8 gap, 34 button, 8 below, so the gaps of its three rows are one

void CPlPanel::DrawFooter()
  {
   const int save_off=m_off;
   m_off=0;
   double top=(m_h-m_foot_h)/m_s;           // logical y of the footer top
   if(!m_dry)
     {
      //--- cover whatever the scrolled body drew down here
      m_cv.Fill(1,m_h-m_foot_h,m_w-2,m_h-3,PlArgb(g_th.bg));
      m_cv.Fill(P(6),m_h-2,m_w-1-P(6),m_h-2,PlArgb(g_th.bg));   // the row above the outline, clear of the rounded corners
      if(!g_cfg.quick) Div(top);          // the quick panel's row above stands 8 px from the button: no line between
     }
   const double ay=top+(g_cfg.quick?8.0:5.0);
   //--- an orange button before the press: the reason stands once, in the status line above, not again on the button
   const double bx2=confirm_view?(PL_W-PL_PAD-70):(PL_W-PL_PAD-44);   // 10 px of air to the flip button: one click sends, a miss to the left must not
   ActionButton(PL_PAD,ay,bx2,ay+34,false);
   if(confirm_view)
      Button(H_CANCEL,0,PL_W-PL_PAD-64,ay,PL_W-PL_PAD,ay+34,PLS_CANCEL);
   else
     {
      double sx1=PL_W-PL_PAD-34;
      Reg(H_SWAP,0,sx1,ay,PL_W-PL_PAD,ay+34);
      if(!m_dry)
        {
         bool hv=IsHover(H_SWAP,0);
         BoxL(sx1,ay,PL_W-PL_PAD,ay+34,6,hv?g_th.hover:g_th.bg,g_th.border);
         double cx0=sx1+17, c=ay+17;
         color ic=g_th.text2;
         // two arrows: up on the left, down on the right
         m_cv.Stroke(X_(cx0-4.5),Y_(c+6),X_(cx0-4.5),Y_(c-6),P(1.5),PlArgb(ic));
         m_cv.Stroke(X_(cx0-8),Y_(c-2.5),X_(cx0-4.5),Y_(c-6.5),P(1.5),PlArgb(ic));
         m_cv.Stroke(X_(cx0-1),Y_(c-2.5),X_(cx0-4.5),Y_(c-6.5),P(1.5),PlArgb(ic));
         m_cv.Stroke(X_(cx0+4.5),Y_(c-6),X_(cx0+4.5),Y_(c+6),P(1.5),PlArgb(ic));
         m_cv.Stroke(X_(cx0+1),Y_(c+2.5),X_(cx0+4.5),Y_(c+6.5),P(1.5),PlArgb(ic));
         m_cv.Stroke(X_(cx0+8),Y_(c+2.5),X_(cx0+4.5),Y_(c+6.5),P(1.5),PlArgb(ic));
        }
     }
   m_off=save_off;
  }

//--- the open button in the box x1..y2: the side, the lot and the order (CONFIRM and the frozen plan when armed), a grey button with the
//--- reason when blocked, amber when the plan asks for a confirmation. Drawn by the footer (two lines when armed) and by the strip
//--- (one_line: one line, and the countdown runs along the bottom edge inside the button)
void CPlPanel::ActionButton(const double x1,const double y1,const double x2,const double y2,const bool one_line)
  {
   const string cur=g_acc.currency;
   const int cd=g_acc.currency_digits;
   string line1,line2="";
   color bg,fg;
   bool enabled=g_plan.ok && g_plan.side!=PL_SIDE_NONE && !PlAnyBadField();
   color sidec=(g_plan.side==PL_SIDE_SELL)?g_th.sell_fill:g_th.buy_fill;
   bool closed=(g_res.reason==PL_R_MARKET_CLOSED);
   string why="";                                    // the short reason on the grey button instead of the side and lot (the full phrase is in the status line)
   if(!enabled || g_res.verdict==PL_BLOCK || closed)
     {
      bg=g_th.dis_bg; fg=g_th.dis_text; enabled=false;
      if(PlAnyBadField()) why=PlBlockedText(PL_R_BAD_INPUT);
      else if(!g_plan.ok) why=(g_plan.reason!=PL_R_NONE)?PlBlockedTextG(g_plan.reason):"";
      else if(g_res.verdict==PL_BLOCK || closed) why=PlBlockedTextG(g_res.reason);
     }
   else if(g_res.verdict==PL_CONFIRM) { bg=g_th.warn; fg=g_th.dark?g_th.bg:g_th.text; }       // dark text: white on amber is hard to read
   else { bg=sidec; fg=clrWhite; }
   const double fitw=(x2-x1)-12;
   line1=(why!="")?why:PlActionText();
   //--- the strip is narrow: without room for "at market" the side and the lot stand alone
   if(one_line && why=="" && TextW(line1,FN_SB,80)>fitw) line1=PlActionText(true);
   bool armed=(confirm_view && g_flow==PL_FLOW_ARMED);
   bool pale=false;
   double rem=0.0;
   if(armed)
     {
      //--- the frozen plan, not the live one: this is what the second press sends
      enabled=true;
      color sc=(g_snap.side==PL_SIDE_SELL)?g_th.sell_fill:g_th.buy_fill;
      bg=(g_snap.verdict==PL_CONFIRM)?g_th.warn:sc; fg=(g_snap.verdict==PL_CONFIRM)?(g_th.dark?g_th.bg:g_th.text):clrWhite;
      ulong age=GetTickCount64()-g_armed_at;
      pale=(age<PL_ARM_PAUSE_MS);
      rem=1.0-(double)age/(double)PL_ARM_WINDOW_MS;
      if(rem<0.0) rem=0.0;
      if(pale)
        {
         //--- the pause before the second press: a dimmed button with a readable text (the old white mix left white text on a pale fill)
         if(g_th.dark) { fg=(g_snap.verdict==PL_CONFIRM)?g_th.text:clrWhite; bg=PlMix(bg,g_th.bg,0.55); }
         else { bg=PlMix(bg,clrWhite,0.55); fg=g_th.text; }
        }
      string tp=(g_snap.tp[0]>0.0)?PLS_TP_SEP+DoubleToString(g_snap.tp[0],g_sym.digits):"";
      line1=PLS_CONFIRM+" "+PlSnapTitle()+" "+DoubleToString(g_snap.lot,PlLotDigits());
      //--- "in 10 orders" never fitted next to "CONFIRM Buy Stop-Limit 0.46": the short "x10" does (the status line above says it in words)
      if(g_snap.parts>1) line1+=PLS_PARTS_X+(string)g_snap.parts;
      if(!one_line)
        {
         if(g_snap.in.no_sl) line2=PLS_NO_SL_ROW+tp+"  "+PLS_RISK_UNDEFINED;
         else line2=PLS_SL_SP+DoubleToString(g_snap.sl,g_sym.digits)+tp+PLS_RISK_SEP+PlMoney(g_snap.risk_money,cur,cd);
        }
     }
   Reg(H_ACTION,0,x1,y1,x2,y2);
   if(!m_dry)
     {
      bool hv=IsHover(H_ACTION,0);
      bool dn=(m_down_id==H_ACTION && hv);
      color f=bg;
      if(enabled && hv && !pale) f=PlMix(bg,clrBlack,0.10);
      if(enabled && dn && !pale) f=PlMix(bg,clrBlack,0.22);
      RndL(x1,y1,x2,y2,6,f);
      if(line2=="")
        {
         const int s1=FitSize(line1,fitw,FN_SB,100);
         Txt((x1+x2)/2.0,(y1+y2)/2.0,line1,fg,FN_SB,s1,2);
        }
      else
        {
         const int s1=FitSize(line1,fitw,FN_SB,confirm_view?90:100);
         const int s2=FitSize(line2,fitw,FN_UI,80);
         Txt((x1+x2)/2.0,y1+11,line1,fg,FN_SB,s1,2);
         Txt((x1+x2)/2.0,y1+24,line2,fg,FN_UI,s2,2);
        }
     }
   //--- the countdown: on the footer it runs along the top edge of the action row, over its divider, in the color of the button (under
   //--- the button it was squeezed between the button and the frame); in the strip it is 2 px along the bottom edge of the button, in the text color
   if(armed && !m_dry && rem>0.0)
     {
      if(one_line) RndL(x1+4,y2-3.5,x1+4+(x2-x1-8)*rem,y2-1.5,1,fg);
      else RndL(x1,y1-5,x1+(x2-x1)*rem,y1-2.5,1.2,(g_snap.verdict==PL_CONFIRM)?g_th.warn:((g_snap.side==PL_SIDE_SELL)?g_th.sell_fill:g_th.buy_fill));
     }
  }

#define COST_ROW_H   22      // logical px, one row of the Costs grid
#define COST_MID_X   100     // the grey detail column starts here for every row

//--- a money text of the Costs grid: full form when it fits right of the detail text, else the short form
string CPlPanel::CostMoney(const double v,const string mid,const bool sign)
  {
   const double room=PL_W-PL_PAD-COST_MID_X-TextW(mid,FN_UI,80)-8.0;
   return FitMoney(v,room,FN_NUM,90,sign);
  }

//--- one row of the Costs grid: label, grey detail, money (or a dash) on the right
void CPlPanel::CostRow(const double y,const string label,const string mid,const color midc,const string val,const color valc)
  {
   if(m_dry) return;
   const double ym=y+COST_ROW_H/2.0;
   Txt(PL_PAD,ym,label,g_th.text2,FN_UI,90);
   Txt(COST_MID_X,ym,mid,midc,FN_UI,80);
   Txt(PL_W-PL_PAD,ym,val,valc,FN_NUM,90,1);
  }

//--- what this draft pays: spread, commission, swap of its side. One grid, three columns.
double CPlPanel::BuildCosts(double y)
  {
   string cur=g_acc.currency;
   int cd=g_acc.currency_digits;
   bool has=g_plan.ok && g_res.lot>0.0;
   string lotS=has?DoubleToString(g_res.lot,PlLotDigits()):"-";
   Div(y); y+=12;
   const bool has_side=has && g_plan.side!=PL_SIDE_NONE;
   const bool buy_side=has_side && g_plan.side==PL_SIDE_BUY;
   if(!m_dry)
     {
      Txt(PL_PAD,y+10,PLS_COSTS,g_th.text,FN_SB,100);
      //--- the side and lot of the current draft, to the right of the title: the numbers below are for this trade
      if(has_side)
         Txt(PL_PAD+TextW(PLS_COSTS,FN_SB,100)+10,y+10,(buy_side?PLS_BUY:PLS_SELL)+" "+lotS+PLS_LOT_WORD,buy_side?g_th.buy:g_th.sell,FN_UI,80);
     }
   {
      Reg(H_COSTS_X,0,PL_W-PL_PAD-24,y-2,PL_W-PL_PAD+2,y+22);
      if(!m_dry)
        {
         if(IsHover(H_COSTS_X,0)) RndL(PL_W-PL_PAD-24,y-2,PL_W-PL_PAD+2,y+22,5,g_th.hover);
         double cx=PL_W-PL_PAD-11, c=y+10;
         m_cv.Stroke(X_(cx-4),Y_(c-4),X_(cx+4),Y_(c+4),P(1.5),PlArgb(g_th.text2));
         m_cv.Stroke(X_(cx-4),Y_(c+4),X_(cx+4),Y_(c-4),P(1.5),PlArgb(g_th.text2));
        }
   }
   y+=26;
   const double rr=PL_W-PL_PAD;
   const string dash="-";
   //--- spread
   {
      const string mid=DoubleToString(PlToUnit(g_sym.ask-g_sym.bid),1)+" "+(PlIsForex(g_sym)?PLS_PIP:PLS_PT);
      CostRow(y,PLS_C_SPREAD,mid,g_th.text2,has?CostMoney(g_res.spread_money,mid,false):dash,g_th.text);
      y+=COST_ROW_H;
   }
   //--- commission: the source in a word; "not counted" and a link to the menu when no rule is known
   {
      const bool by_broker=(g_in.comm.source==PL_COMMSRC_BROKER);     // the broker's rule wins over a typed rate (PlBuildInputs)
      if(!by_broker && g_dr.comm.kind==PL_COMM_UNKNOWN)
        {
         if(!m_dry)
           {
            const double ym=y+COST_ROW_H/2.0;
            Txt(PL_PAD,ym,PLS_C_COMM,g_th.text2,FN_UI,90);
            Txt(COST_MID_X,ym,PLS_C_NOT_COUNTED,g_th.warn_text,FN_UI,80);
           }
         const double lw=TextW(PLS_C_SET_IN_MENU,FN_UI,80);
         Reg(H_COMM_GO,0,rr-lw-6,y,rr+2,y+COST_ROW_H);
         if(!m_dry)
           {
            const bool hv=IsHover(H_COMM_GO,0);
            Txt(rr,y+COST_ROW_H/2.0,PLS_C_SET_IN_MENU,hv?g_th.text:g_th.accent,FN_UI,80,1);
            m_cv.Fill(X_(rr-lw),Y_(y+COST_ROW_H/2.0+7),X_(rr)-1,Y_(y+COST_ROW_H/2.0+7),PlArgb(hv?g_th.text:g_th.accent));
           }
        }
      else
        {
         //--- the word beside the money: the source; "broker, none" when the broker's rule charges nothing (not the same as "not counted");
         //--- "min $0.20" when the broker minimum of an order, not the rate, is the commission of this trade
         string mid=by_broker?PLS_C_BROKER_SHORT:(g_dr.comm.source==PL_COMMSRC_HINT?PLS_C_SRC_DEALS:PLS_C_SRC_USER);
         if(by_broker && g_in.comm.rate<=0.0 && g_in.comm.min_money<=0.0) mid=PLS_C_BROKER_NONE;
         if(by_broker && has && g_res.comm_min_on) mid=PLS_C_MIN+" "+PlMoney(g_in.comm.min_money,g_acc.currency,2);
         CostRow(y,PLS_C_COMM,mid,g_th.text2,has?CostMoney(g_res.comm_money,mid,false):dash,g_th.text);
        }
      y+=COST_ROW_H;
   }
   //--- swap of the side of this draft, one night
   {
      string mid="";
      string val=dash;
      color vc=g_th.text;
      if(has_side)
        {
         mid=(buy_side?PLS_BUY:PLS_SELL)+PLS_NIGHT;
         if(g_res.swap_ok)
           {
            const double sw=buy_side?g_res.swap_long_night:g_res.swap_short_night;
            val=CostMoney(sw,mid,true);
            vc=(sw<-1e-9)?g_th.sell:(sw>1e-9)?g_th.ok:g_th.text;
           }
         else val=PLS_NA;
        }
      CostRow(y,PLS_C_SWAP,mid,g_th.text2,val,vc);
      y+=COST_ROW_H;
      //--- the triple-swap day: a small note under the row
      const double sw_raw=buy_side?g_sym.swap_long:g_sym.swap_short;
      if(has_side && g_sym.swap_3day>=0 && g_sym.swap_3day<=6 && sw_raw!=0.0)
        {
         if(!m_dry) Txt(rr,y+1,PLS_X3_ON+PlDayName(g_sym.swap_3day),g_th.text2,FN_UI,80,1);
         y+=14;
        }
   }
   return y+8;
  }

//--- the Positions block: one two-line row per position or pending order of Plainlines
double CPlPanel::BuildPositions(double y)
  {
   const string cur=g_acc.currency;
   const int cd=g_acc.currency_digits;
   Div(y); y+=12;
   //--- the header row: the title, the count and the profit of what is open at the right, a chevron; the whole row opens and closes the list
   Reg(H_POS,0,PL_PAD,y-2,PL_W-PL_PAD,y+22);
   if(!m_dry)
     {
      const bool hv=IsHover(H_POS,0);
      if(hv) RndL(PL_PAD,y-2,PL_W-PL_PAD,y+22,5,g_th.hover);
      Txt(PL_PAD+4,y+10,PLS_POSITIONS,g_th.text,FN_SB,100);
      const double cx=PL_W-PL_PAD-11, c=y+10, d=pos_open?-1.0:1.0;
      m_cv.Stroke(X_(cx-3.5),Y_(c-1.8*d),X_(cx),Y_(c+1.8*d),P(1.5),PlArgb(g_th.text2));
      m_cv.Stroke(X_(cx),Y_(c+1.8*d),X_(cx+3.5),Y_(c-1.8*d),P(1.5),PlArgb(g_th.text2));
      //--- the count names both kinds when both stand: "1 pos · 1 order", not "1 pos" over a row of an order
      const string cp=(string)g_own_pos+" "+PLS_POS_WORD, co=(string)g_own_ord+" "+((g_own_ord==1)?PLS_ORDER_ONE:PLS_ORDER_MANY);
      string ct1=(g_own_pos>0)?((g_own_ord>0)?(cp+" "+ShortToString(0xB7)+" "+co):cp):co;
      string ct2=(g_own_pos>0)?PlMoneyShort(g_own_pl,cur,cd,true):"";
      //--- the profit goes first when the title leaves no room for the whole group
      const double room=(cx-10)-(PL_PAD+4+TextW(PLS_POSITIONS,FN_SB,100)+10);
      if(ct2!="" && TextW(ct1,FN_UI,80)+5.0+TextW(ct2,FN_NUM,80)>room) ct2="";
      double x=cx-10;
      if(ct2!="") { Txt(x,y+10,ct2,(g_own_pl>=0.0)?g_th.ok:g_th.sell,FN_NUM,80,1); x-=TextW(ct2,FN_NUM,80)+5.0; }
      Txt(x,y+10,ct1,g_th.text2,FN_UI,80,1);
     }
   y+=22;
   m_nrows=0;
   if(!pos_open) return y+8;
   y+=6;
   const int n=ArraySize(g_own);
   const int shown=MathMin(n,PL_MAX_ROWS);
   m_nrows=shown;
   const string dot=" "+ShortToString(0xB7)+" ";
   for(int i=0;i<shown;i++)
     {
      const PlOwn o=g_own[i];
      m_row_id[i]=o.id;
      const int rk=PlRecIndex(o.id);           // never o.rec: the list is rebuilt once a second, the records change at once
      const bool exp=(m_exp_id==o.id);
      const int dg=(int)SymbolInfoInteger(o.sym,SYMBOL_DIGITS);
      string side=o.buy?PLS_BUY_WORD:PLS_SELL_WORD;
      if(o.pending)
        {
         const ENUM_ORDER_TYPE ot=(ENUM_ORDER_TYPE)o.type;
         if(ot==ORDER_TYPE_BUY_LIMIT || ot==ORDER_TYPE_SELL_LIMIT) side+=" "+PLS_LIMIT_WORD;
         else if(ot==ORDER_TYPE_BUY_STOP || ot==ORDER_TYPE_SELL_STOP) side+=" "+PLS_STOP_WORD;
         else side+=" "+PLS_STOP_LIMIT_WORD;
        }
      const int lotdg=(int)MathMax(2,MathMin(4,PlStepDigits(SymbolInfoDouble(o.sym,SYMBOL_VOLUME_STEP))));
      const string name=o.sym+"  "+side+" "+DoubleToString(o.vol,lotdg);
      //--- the row (a click opens its buttons), then the close box
      Reg(H_ROW_EXP,i,PL_PAD,y,PL_W-PL_PAD-30,y+36);
      const bool armed=PlCbArmed(1,o.id);
      Reg(H_ROW_X,i,PL_W-PL_PAD-26,y+4,PL_W-PL_PAD,y+30);
      //--- the breakeven chip at the right of the second line: one click moves the SL to the breakeven level (PlBreakevenSl: the open plus
      //--- the commission in and out, the negative swap paid and a tick, then on tick by tick until closing at it gives zero or more by the
      //--- measure of the Open risk line, PlPlAtSl). Hidden for an order and once closing at the SL of the position already gives zero or more
      //--- by that same measure (be_safe, so the chip and the Open risk line never disagree, whoever set the SL); shown while it would still
      //--- lose money. Live (bright) only when the price is past the level; else muted, and the click then says why. A level not known yet
      //--- (the entry deal is not in the history, the money cannot be valued) makes it muted and promises nothing. Registered after
      //--- the row, so it takes the click; the hit area is taller than the chip
      bool chip=false, chip_live=false;
      double chx1=0.0;
      const double chx2=PL_W-PL_PAD-34;
      if(!o.pending && !o.be_safe)
        {
         const double tk=PlTickOf(o.sym);
         chip=true;
         const double cpx=SymbolInfoDouble(o.sym,o.buy?SYMBOL_BID:SYMBOL_ASK);
         chip_live=(o.be>0.0 && cpx>0.0 && (o.buy?(cpx>o.be+tk*0.999):(cpx<o.be-tk*0.999)));
         chx1=chx2-(TextW(PLS_BE_NOW,FN_UI,80)+18);
         Reg(H_ROW_BTN,i*8+0,chx1,y+15,chx2,y+39);
        }
      if(!m_dry)
        {
         if(IsHover(H_ROW_EXP,i) || exp) RndL(PL_PAD,y,PL_W-PL_PAD-30,y+36,5,g_th.surface);
         Txt(PL_PAD+6,y+11,name,g_th.text,FN_SB,90);
         string right;
         color rc=g_th.text;
         if(o.pending) { right=DoubleToString(o.open,dg); rc=g_th.text2; }
         else { right=PlMoney(o.pl,cur,cd,true); rc=(o.pl>=0.0)?g_th.ok:g_th.sell; }
         Txt(PL_W-PL_PAD-34,y+11,right,rc,FN_NUM,90,1);
         //--- second line
         string l2="";
         if(o.pending)
           {
            if(o.sl>0.0) l2=PLS_SL+" "+DoubleToString(o.sl,dg);
            if(o.tp>0.0) l2+=(l2!=""?"  ":"")+PLS_TP+" "+DoubleToString(o.tp,dg);
            if(o.expire>0)
              {
               const long left=(long)o.expire-(long)TimeTradeServer();
               l2+=(l2!=""?dot:"")+PlLeftText(left);
              }
           }
         else
           {
            const double dsl=o.sl, dtp=o.tp;
            if(dsl>0.0) l2=PLS_SL+" "+DoubleToString(dsl,dg); else l2=PLS_NO_SL_ROW;
            if(dtp>0.0) l2+="  "+PLS_TP+" "+DoubleToString(dtp,dg);
            if(rk>=0)
              {
               if(g_rec[rk].be_on) l2+=dot+(g_rec[rk].be_done?PLS_BE_DONE:PLS_BE);
               if(g_rec[rk].trail>0) l2+=dot+PLS_TRAIL;
               if(g_rec[rk].pt_n>0) l2+=dot+PLS_PARTS_WORD;
              }
           }
         //--- a Stop-Limit order: the first price above is the trigger, the limit price stands on the right of the second line
         string lim="";
         if(o.pending && o.lim>0.0) lim=PLS_LIMIT_SP+DoubleToString(o.lim,dg);
         int l2fs=80;
         while(lim!="" && l2fs>70 && TextW(l2,FN_UI,l2fs)+TextW(lim,FN_UI,l2fs)+8>(PL_W-PL_PAD-34)-(PL_PAD+6)) l2fs-=5;
         while(chip && l2fs>70 && TextW(l2,FN_UI,l2fs)+8>chx1-(PL_PAD+6)) l2fs-=5;
         Txt(PL_PAD+6,y+27,l2,g_th.text2,FN_UI,l2fs);
         if(lim!="") Txt(PL_W-PL_PAD-34,y+27,lim,g_th.text2,FN_UI,l2fs,1);
         if(chip)
           {
            const bool chv=IsHover(H_ROW_BTN,i*8+0);
            const color cf=chip_live?(chv?PlMix(g_th.accent_fill,g_th.text,0.15):g_th.accent_fill):(chv?g_th.hover:g_th.bg);
            BoxL(chx1,y+19,chx2-6,y+35,4,cf,chip_live?cf:g_th.border);
            Txt((chx1+chx2-6)/2.0,y+27,PLS_BE_NOW,chip_live?g_th.on_accent:g_th.text2,FN_UI,80,2);
           }
         //--- the close box
         const bool hx=IsHover(H_ROW_X,i);
         BoxL(PL_W-PL_PAD-26,y+4,PL_W-PL_PAD,y+30,4,armed?g_th.sell_fill:(hx?g_th.hover:g_th.bg),armed?g_th.sell_fill:g_th.border);
         const double cx=PL_W-PL_PAD-13, cy=y+17;
         const color ic=armed?clrWhite:g_th.text2;
         m_cv.Stroke(X_(cx-4),Y_(cy-4),X_(cx+4),Y_(cy+4),P(1.5),PlArgb(ic));
         m_cv.Stroke(X_(cx-4),Y_(cy+4),X_(cx+4),Y_(cy-4),P(1.5),PlArgb(ic));
        }
      y+=40;
      if(exp && !o.pending)
        {
         const double bw=(PL_W-2*PL_PAD-2*4)/3.0;      // breakeven now is the chip of the row
         const bool hasrec=(rk>=0);
         const bool be_on=hasrec && g_rec[rk].be_on;
         const bool tr_on=hasrec && g_rec[rk].trail>0;
         const bool partarm=PlCbArmed(3,o.id);
         string pt=PLS_CLOSE_WORD+" "+DoubleToString(g_cfg.part_pct,0)+"%";
         if(partarm) pt=PLS_SURE;
         Button(H_ROW_BTN,i*8+1,PL_PAD,y,PL_PAD+bw,y+26,pt,partarm);
         Button(H_ROW_BTN,i*8+2,PL_PAD+(bw+4),y,PL_PAD+bw*2+4,y+26,PLS_BE,be_on);
         Button(H_ROW_BTN,i*8+3,PL_PAD+(bw+4)*2,y,PL_W-PL_PAD,y+26,PLS_TRAIL,tr_on);
         y+=32;
        }
      else if(exp && o.pending) { y+=2; }
     }
   if(n>shown)
     {
      if(!m_dry) Txt(PL_PAD+6,y+8,"+"+(string)(n-shown)+" "+PLS_MORE,g_th.text2,FN_UI,80);
      y+=18;
     }
   if(!m_dry)
     {
      const double risk=g_acc.open_risk_money+g_acc.pending_risk_money;
      const double base=(g_cfg.base==PL_BASE_EQUITY)?g_acc.equity:g_acc.balance;
      const double mu=(g_acc.equity>PL_EPS)?g_acc.margin/g_acc.equity*100.0:0.0;
      //--- a position or order without a known risk makes the sum unknown: never show it as a number (facts rule 7)
      const int unk_n=g_acc.open_no_sl+g_ex_unknown;
      string t=PLS_OPEN_RISK+" ";
      if(unk_n>0) t+=PLS_UNDEFINED+" ("+(string)unk_n+" "+PLS_UNKNOWN_WORD+")";
      else t+=PlMoneyShort(risk,cur,cd)+" ("+PlPctText((base>PL_EPS)?risk/base*100.0:0.0)+")";
      //--- the share was computed with a new risk of 0 when the trade has no SL, and without the unknown open risk
      //--- with an unknown open risk the share with this trade is unknown too: the first part already says so
      if(g_plan.ok && g_res.lot>0.0 && unk_n==0)
         t+=dot+PLS_WITH_TRADE+" "+(g_cfg.no_sl?PLS_UNDEFINED:PlPctText(g_lo.portfolio_pct));
      const double fitw=PL_W-2*PL_PAD;
      string t2=PLS_MARGIN_USED+" "+DoubleToString(mu,1)+"%"+((g_plan.ok && g_res.lot>0.0)?(dot+PLS_AFTER_TRADE+" "+DoubleToString(g_lo.margin_use_pct,1)+"%"):"");
      const int fs1=FitSize(t,fitw,FN_UI,80);
      const int fs2=FitSize(t2,fitw,FN_UI,80);
      Txt(PL_PAD,y+8,t,g_th.text2,FN_UI,fs1);
      Txt(PL_PAD,y+26,t2,g_th.text2,FN_UI,fs2);
     }
   y+=40;
   if(g_cfg.close_btns)
     {
      const string chart_sym=g_sym.name;
      const double hw=(PL_W-2*PL_PAD-4)/2.0;
      string lab[2];
      lab[0]=PLS_CLOSE_ALL; lab[1]=PLS_CLOSE_WORD+" "+chart_sym;
      for(int b=0;b<2;b++)
        {
         const double x1=PL_PAD+b*(hw+4);
         const bool a=PlCbArmed(2,(ulong)b);
         Button(H_BULK,b,x1,y,x1+hw,y+26,a?(PLS_SURE+" "+lab[b]):lab[b],a);
        }
      y+=30;
     }
   y+=6;
   return y;
  }

//--- menu rows -----------------------------------------------------------------------------------
double CPlPanel::MToggle(const double y,const int key,const string label,const bool on,const bool danger)
  {
   if(!m_dry)
     {
      if(IsHover(H_TOG,key)) m_cv.Fill(1,Y_(y),m_w-2,Y_(y+30)-1,PlArgb(g_th.surface));
      Txt(PL_PAD,y+15,label,g_th.text,FN_UI,90);
      if(danger)
        {
         double x=PL_PAD+TextW(label,FN_UI,90)+8;
         Txt(x,y+15,PLS_DANGER,g_th.warn_text,FN_UI,75);
        }
     }
   Switch(key,PL_W-PL_PAD,y+15,on);
   return y+30;
  }

double CPlPanel::MSeg(const double y,const int key,const string label,const string opts,const int sel)
  {
   string o[];
   int n=StringSplit(opts,'|',o);
   double total=0;
   double w[8];
   for(int i=0;i<n && i<8;i++) { w[i]=MathMax(40.0,TextW(o[i],FN_UI,80)+18); total+=w[i]; }
   //--- the caption keeps a gap (MENU_GAP) to the strip: a long caption steps its font down before the strip is squeezed
   int lfs=90;
   while(lfs>80 && PL_W-2*PL_PAD-TextW(label,FN_UI,lfs)-MENU_GAP<total) lfs-=5;
   if(!m_dry) Txt(PL_PAD,y+15,label,g_th.text,FN_UI,lfs);
   const double room=PL_W-2*PL_PAD-TextW(label,FN_UI,lfs)-MENU_GAP;
   if(total>room && total>0.0) { const double k=room/total; for(int i=0;i<n && i<8;i++) w[i]*=k; total=room; }
   double x2=PL_W-PL_PAD, x1=x2-total;
   if(!m_dry) RndL(x1,y+3,x2,y+27,5,g_th.surface);
   double a=x1;
   for(int i=0;i<n && i<8;i++)
     {
      double b=a+w[i];
      Reg(H_SEG,key*8+i,a,y+3,b,y+27);
      if(!m_dry)
        {
         bool hv=IsHover(H_SEG,key*8+i);
         if(i==sel) { RndL(a+2,y+5,b-2,y+25,4,g_th.accent_fill); Txt((a+b)/2.0,y+15,o[i],g_th.on_accent,FN_SB,80,2); }
         else
           {
            if(hv) RndL(a+2,y+5,b-2,y+25,4,g_th.hover);
            Txt((a+b)/2.0,y+15,o[i],hv?g_th.text:g_th.text2,FN_UI,80,2);
           }
        }
      a=b;
     }
   return y+30;
  }

double CPlPanel::MNum(const double y,const int fid,const string label,const string suffix,const bool left,const double w)
  {
   double x2=PL_W-PL_PAD;
   if(w<=80.0)
     {
      //--- numeric fields end on one column, the unit hangs to the right of it
      if(!m_dry && suffix!="") Txt(x2,y+15,suffix,g_th.text2,FN_UI,80,1);
      x2-=44;
     }
   //--- the caption keeps a gap (MENU_GAP) to the field: a long caption steps its font down
   int lfs=90;
   while(lfs>75 && TextW(label,FN_UI,lfs)>(x2-w)-PL_PAD-MENU_GAP) lfs-=5;
   if(!m_dry) Txt(PL_PAD,y+15,label,g_th.text,FN_UI,lfs);
   FieldBox(fid,x2-w,y+3,x2,y+27,left);
   return y+30;
  }

double CPlPanel::MText(const double y,const string label,const string value)
  {
   if(!m_dry)
     {
      Txt(PL_PAD,y+15,label,g_th.text,FN_UI,90);
      Txt(PL_W-PL_PAD,y+15,value,g_th.text2,FN_NUM,90,1);
     }
   return y+30;
  }

double CPlPanel::MNote(const double y,const string text,const color c)
  {
   if(!m_dry)
     {
      int fs=80;
      if(TextW(text,FN_UI,fs)>PL_W-2*PL_PAD) fs=75;
      string t=text;
      if(TextW(t,FN_UI,fs)>PL_W-2*PL_PAD)
        {
         t=CutPhrase(t,"",PL_W-2*PL_PAD,FN_UI,fs)+"...";
        }
      Txt(PL_PAD,y+11,t,c,FN_UI,fs);
     }
   return y+22;
  }

double CPlPanel::MSection(const double y,const int idx,const string title,const string sub,const color subc)
  {
   bool open=m_sec[idx];
   Reg(H_SEC,idx,0,y,PL_W,y+34);
   if(!m_dry)
     {
      bool hv=IsHover(H_SEC,idx);
      if(hv) m_cv.Fill(1,Y_(y),m_w-2,Y_(y+34)-1,PlArgb(g_th.surface));
      // chevron
      double cx=PL_PAD+4, cy=y+17;
      if(open)
        {
         m_cv.Stroke(X_(cx-4),Y_(cy-2),X_(cx),Y_(cy+2.5),P(1.5),PlArgb(g_th.text2));
         m_cv.Stroke(X_(cx),Y_(cy+2.5),X_(cx+4),Y_(cy-2),P(1.5),PlArgb(g_th.text2));
        }
      else
        {
         m_cv.Stroke(X_(cx-2),Y_(cy-4),X_(cx+2.5),Y_(cy),P(1.5),PlArgb(g_th.text2));
         m_cv.Stroke(X_(cx+2.5),Y_(cy),X_(cx-2),Y_(cy+4),P(1.5),PlArgb(g_th.text2));
        }
      Txt(PL_PAD+20,y+17,title,g_th.text,FN_SB,100);
      if(sub!="")
        {
         //--- the state never touches the title: a long one steps down, then loses its tail
         string st=sub;
         const double room=PL_W-PL_PAD-(PL_PAD+20+TextW(title,FN_SB,100)+12);
         const int sfs=FitSize(st,room,FN_UI,80);
         Txt(PL_W-PL_PAD,y+17,st,(subc==clrNONE)?g_th.text2:subc,FN_UI,sfs,1);
        }
     }
   return y+34;
  }

//--- a number without trailing zeros: 2.0 -> "2", 1.50 -> "1.5"
string PlNumTrim(const double v,const int digits)
  {
   string t=DoubleToString(v,digits);
   if(StringFind(t,".")<0) return t;
   while(StringLen(t)>1 && StringGetCharacter(t,StringLen(t)-1)=='0') t=StringSubstr(t,0,StringLen(t)-1);
   if(StringGetCharacter(t,StringLen(t)-1)=='.') t=StringSubstr(t,0,StringLen(t)-1);
   return t;
  }

//--- the state of a menu section, short, for the grey text at the right of its title (the section need not be open)
string PlSecSub(const int idx,color &c)
  {
   c=g_th.text2;
   const string dt=" "+ShortToString(0xB7)+" ";
   string o[];
   switch(idx)
     {
      case PL_SEC_TRADE:
        {
         StringSplit(PLS_BALANCE_EQUITY,'|',o);
         string t=(g_cfg.base>=0 && g_cfg.base<ArraySize(o))?o[g_cfg.base]:"";
         t+=dt+(g_cfg.no_tp?PLS_NO_TP:((string)g_cfg.tp_count+" "+(g_cfg.tp_count==1?PLS_SUB_TP:PLS_SUB_TPS)));
         t+=dt+((g_cfg.expiry_mode==1)?PLS_SUB_TODAY:(g_cfg.expiry_mode==2)?((string)g_cfg.expiry_hours+PLS_SUB_HOURS):PLS_SUB_GTC);
         return t;
        }
      case PL_SEC_POSITION:
        {
         string t="";
         if(g_cfg.be_on) t=PLS_SUB_BE+PlNumTrim(g_cfg.be_r,1)+"R";
         if(g_cfg.trail_on) t+=(t!=""?dt:"")+PLS_SUB_TRAIL;
         return (t!="")?t:PLS_SUB_OFF;
        }
      case PL_SEC_CONFIRM:
         return (g_cfg.confirm_on?PLS_SUB_ON:PLS_SUB_OFF)+((g_cfg.confirm_on && g_cfg.confirm_above>0.0)?dt+PLS_SUB_ABOVE+PlNumTrim(g_cfg.confirm_above,1)+"%":"");
      case PL_SEC_COMMISSION:
        {
         //--- the same conditions as the Commission row of Costs
         const bool by_broker=(g_in.comm.source==PL_COMMSRC_BROKER);
         if(by_broker) return PLS_SUB_BROKER;
         if(g_dr.comm.kind==PL_COMM_UNKNOWN) return PLS_SUB_NOT_COUNTED;
         if(g_dr.comm.kind==PL_COMM_PERCENT_SIDE) return DoubleToString(g_dr.comm.rate,4)+"%";
         return DoubleToString(g_dr.comm.rate,2)+PLS_SUB_PER_LOT;
        }
      case PL_SEC_LIMITS:
        {
         return (g_lc.portfolio_cap_pct>0.0 || g_cfg.max_open>0 || g_cfg.max_day>0)?PLS_SUB_SET:PLS_SUB_OFF;
        }
      case PL_SEC_ADVANCED:
        {
         if(g_cfg.no_sl || g_cfg.over_max!=PL_OVER_BLOCK || g_cfg.cap>5.0+1e-9) { c=g_th.warn_text; return PLS_SUB_CHANGED; }
         string t="";
         if(g_cfg.atr_on) t=PLS_SUB_ATR+PlNumTrim(g_cfg.atr_mult,2)+"x";
         if(g_cfg.subtract_open) t+=(t!=""?dt:"")+PLS_SUB_SUB_OPEN;
         if(g_cfg.no_tp) t+=(t!=""?dt:"")+PLS_NO_TP;
         if(g_cfg.click_place) t+=(t!=""?dt:"")+PLS_SUB_CLICK_PLACE;
         return (t!="")?t:PLS_SUB_RARELY;
        }
      case PL_SEC_LOOK:
        {
         StringSplit(PLS_AUTO_LIGHT_DARK,'|',o);
         string t=(g_cfg.theme>=0 && g_cfg.theme<ArraySize(o))?o[g_cfg.theme]:"";
         if(g_cfg.scale>=1 && g_cfg.scale<=3) t+=dt+((g_cfg.scale==1)?"100":(g_cfg.scale==2)?"125":"150")+"%";
         return t;
        }
     }
   return "";
  }

double CPlPanel::BuildMenu(double y)
  {
   color sc=clrNONE;
   string ss="";
   //--- Trade: what every trade uses (the risk base, the take profits, how long a pending order lives)
   ss=PlSecSub(PL_SEC_TRADE,sc); y=MSection(y,PL_SEC_TRADE,PLS_M_TRADE,ss,sc);
   if(m_sec[PL_SEC_TRADE])
     {
      y=MSeg(y,MK_BASE,PLS_RISK_BASE,PLS_BALANCE_EQUITY,g_cfg.base);
      y=MSeg(y,MK_TPCOUNT,PLS_TAKE_PROFITS,"1|2|3",g_cfg.tp_count-1);
      if(g_cfg.tp_count>=2)
        {
         double s1=100.0-g_cfg.tp_share2-((g_cfg.tp_count>=3)?g_cfg.tp_share3:0.0);
         y=MText(y,PLS_TP1_SHARE,DoubleToString(s1,0)+" %");
         y=MNum(y,PLF_TP2_R,PLS_TP2_TARGET,"R");
         y=MNum(y,PLF_TP2_SHARE,PLS_TP2_SHARE,"%");
        }
      if(g_cfg.tp_count>=3)
        {
         y=MNum(y,PLF_TP3_R,PLS_TP3_TARGET,"R");
         y=MNum(y,PLF_TP3_SHARE,PLS_TP3_SHARE,"%");
        }
      y=MSeg(y,MK_EXPIRY,PLS_PENDING_EXPIRY,PLS_GTC_TODAY_HOURS,g_cfg.expiry_mode);
      if(g_cfg.expiry_mode==2) y=MNum(y,PLF_EXP_HOURS,PLS_EXPIRE_AFTER,"h");
      y+=6;
     }
   Div(y);
   //--- Position
   ss=PlSecSub(PL_SEC_POSITION,sc); y=MSection(y,PL_SEC_POSITION,PLS_M_POSITION,ss,sc);
   if(m_sec[PL_SEC_POSITION])
     {
      y=MToggle(y,MK_BE,PLS_MOVE_SL_TO_BREAKEVEN,g_cfg.be_on);
      y=MNum(y,PLF_BE_R,PLS_BREAKEVEN_AT,"R");
      y=MToggle(y,MK_TRAIL,PLS_TRAILING,g_cfg.trail_on);
      if(g_cfg.trail_on)
        {
         y=MNum(y,PLF_TRAIL_PIPS,PLS_TRAIL_DISTANCE,PlIsForex(g_sym)?PLS_PIPS:PLS_PT);
         y=MNote(y,PLS_TRAIL_ZERO_NOTE,g_th.text2);
        }
      y=MNum(y,PLF_PART_PCT,PLS_PARTIAL_CLOSE,"%");
      y=MToggle(y,MK_CLOSEBTN,PLS_CLOSE_BUTTONS,g_cfg.close_btns);
      y+=6;
     }
   Div(y);
   //--- Confirm
   ss=PlSecSub(PL_SEC_CONFIRM,sc); y=MSection(y,PL_SEC_CONFIRM,PLS_M_CONFIRM,ss,sc);
   if(m_sec[PL_SEC_CONFIRM])
     {
      y=MToggle(y,MK_CONFIRM,PLS_CONFIRMATION,g_cfg.confirm_on);
      y=MNum(y,PLF_CONF_ABOVE,PLS_CONFIRM_ABOVE,"%");
      y=MNote(y,PLS_HOTKEY_NOTE,g_th.text2);
      y+=6;
     }
   Div(y);
   //--- Commission: the rate is kept per symbol (in the draft), unlike the settings above
   ss=PlSecSub(PL_SEC_COMMISSION,sc); y=MSection(y,PL_SEC_COMMISSION,PLS_M_COMMISSION,ss,sc);
   if(m_sec[PL_SEC_COMMISSION])
     {
      const bool by_broker=(g_in.comm.source==PL_COMMSRC_BROKER);   // the broker's rule is in use: it wins over a typed rate, so no editor
      string kn=PLS_NONE;
      switch(by_broker?g_in.comm.kind:g_dr.comm.kind)
        {
         case PL_COMM_LOT_SIDE:      kn=PLS_PER_LOT_SIDE; break;
         case PL_COMM_LOT_ROUND:     kn=PLS_PER_LOT_ROUND; break;
         case PL_COMM_PERCENT_SIDE:  kn=PLS_PCT_NOTIONAL_SIDE; break;
         default: kn=PLS_NONE;
        }
      if(by_broker)
        {
         const string rv=(g_in.comm.kind==PL_COMM_PERCENT_SIDE)?DoubleToString(g_in.comm.rate,4)+"%":PlMoney(g_in.comm.rate,g_acc.currency,2);
         y=MText(y,PLS_C_KIND,kn);
         y=MText(y,PLS_C_RATE,rv+"  "+PLS_C_BROKER);
        }
      else
        {
         if(!m_dry) Txt(PL_PAD,y+15,PLS_C_KIND,g_th.text,FN_UI,90);
         Button(H_COMM_KIND,0,100,y+3,PL_W-PL_PAD,y+27,kn,false,1);
         y+=30;
         if(g_dr.comm.kind!=PL_COMM_UNKNOWN)
            y=MNum(y,PLF_COMM_RATE,PLS_C_RATE,(g_dr.comm.kind==PL_COMM_PERCENT_SIDE)?"%":"");
        }
      if(g_hint_ok && !by_broker)
        {
         if(!m_dry)
           {
            PlCommKind hk; double hrt;
            PlHintToComm(g_hint_in,g_hint_out,g_hint_closed,hk,hrt);
            const int hd=(hrt>0.0 && hrt<0.1)?4:2;          // a few cents per lot (a share): "$0.0067", not a rounded "$0.01"
            string ht=PLS_C_HINT+" "+g_sym.name+": "+PlMoney(hrt,g_acc.currency,hd)+((hk==PL_COMM_LOT_ROUND)?PLS_ROUND:PLS_SIDE);
            int hs=80;
            const double hroom=PL_W-2*PL_PAD-34-8;
            while(TextW(ht,FN_UI,hs)>hroom && hs>70) hs-=5;
            Txt(PL_PAD,y+13,ht,g_th.text2,FN_UI,hs);
           }
         Button(H_COMM_USE,0,PL_W-PL_PAD-34,y+1,PL_W-PL_PAD,y+25,PLS_USE);
         y+=28;
        }
      y=MNote(y,by_broker?PLS_C_SET_BY_BROKER:PLS_C_NOTE_NO_RULE,g_th.text2);
      y+=6;
     }
   Div(y);
   Div(y);
   //--- Limits: the ceilings first, then the limits of a build with more checks
   ss=PlSecSub(PL_SEC_LIMITS,sc); y=MSection(y,PL_SEC_LIMITS,PLS_M_LIMITS,ss,sc);
   if(m_sec[PL_SEC_LIMITS])
     {
      y=MNum(y,PLF_PORT_CAP,PLS_MAX_TOTAL_RISK,"%");
      y=MNum(y,PLF_MAX_OPEN,PLS_MAX_OPEN_TRADES);
      y=MNum(y,PLF_MAX_DAY,PLS_MAX_TRADES_A_DAY);
      if(g_cfg.max_open>0 || g_cfg.max_day>0) y=MNote(y,PLS_COUNTS_EACH_ORDER,g_th.text2);
      y+=6;
     }
   Div(y);
   //--- Advanced: the risky options first, then the rare ones
   ss=PlSecSub(PL_SEC_ADVANCED,sc); y=MSection(y,PL_SEC_ADVANCED,PLS_M_ADVANCED,ss,sc);
   if(m_sec[PL_SEC_ADVANCED])
     {
      y=MSeg(y,MK_OVERMAX,PLS_ABOVE_BROKER_MAX_LOT,PLS_BLOCK_TRIM_SPLIT,g_cfg.over_max);
      y=MNum(y,PLF_CAP,PLS_HARD_CAP,"%");
      y=MToggle(y,MK_NO_SL,PLS_TRADE_WITHOUT_SL,g_cfg.no_sl,true);
      y=MNum(y,PLF_MAGIC,PLS_MAGIC,"",false,76);
      y=MNote(y,PLS_MAGIC_NOTE,g_th.text2);
      y=MNum(y,PLF_MAX_SPREAD,PLS_MAX_SPREAD_PCT_OF_SL,"%");
      y=MNum(y,PLF_MARGIN_USE,PLS_MARGIN_USE_CONFIRM_ABOVE,"%");
      y=MToggle(y,MK_SUB_OPEN,PLS_SUBTRACT_OPEN_RISK,g_cfg.subtract_open);
      y=MToggle(y,MK_ATR,PLS_ATR_STOP,g_cfg.atr_on);
      if(g_cfg.atr_on)
        {
         y=MNum(y,PLF_ATR_MULT,PLS_ATR_MULTIPLIER,"x");
         y=MNum(y,PLF_ATR_PERIOD,PLS_ATR_PERIOD);
        }
      y=MToggle(y,MK_NO_TP,PLS_NO_TP,g_cfg.no_tp);
      y=MToggle(y,MK_CLICKPLACE,PLS_CLICK_PLACE,g_cfg.click_place);
      y=MNum(y,PLF_COMMENT,PLS_COMMENT,"",true,120);
      y+=6;
     }
   Div(y);
   //--- Look
   ss=PlSecSub(PL_SEC_LOOK,sc); y=MSection(y,PL_SEC_LOOK,PLS_M_LOOK,ss,sc);
   if(m_sec[PL_SEC_LOOK])
     {
      y=MSeg(y,MK_THEME,PLS_THEME,PLS_AUTO_LIGHT_DARK,g_cfg.theme);
      y=MSeg(y,MK_SCALE,PLS_SCALE,PLS_AUTO_100_125_150,g_cfg.scale);
      y=MSeg(y,MK_QSTYLE,PLS_QUICK_PANEL,PLS_STRIP_CARD,g_cfg.quick_style);
      y=MSeg(y,MK_LINEW,PLS_LINES_WIDTH,PLS_THIN_THICK,g_cfg.line_thick);
      y=MToggle(y,MK_SOUNDS,PLS_SOUNDS,g_cfg.sounds);
      y=MText(y,PLS_VERSION_WORD,PLAINLINES_VERSION+PL_BUILD_TAG);
      y+=6;
     }
   Div(y);
   y+=12;
   Button(H_RESET,0,PL_PAD,y,PL_W-PL_PAD,y+30,PLS_M_RESET);
   y+=30+12;
   return y;
  }

//-------------------------------------------------------------------------------------------------
void CPlPanel::Frame()
  {
   if(m_dry) return;
   //--- outline: straight edges redrawn over anything the body painted
   uint b=PlArgb(g_th.frame);
   int r=P(6);
   m_cv.Fill(r,0,m_w-1-r,0,b);
   m_cv.Fill(r,m_h-1,m_w-1-r,m_h-1,b);
   m_cv.Fill(0,r,0,m_h-1-r,b);
   m_cv.Fill(m_w-1,r,m_w-1,m_h-1-r,b);
  }

void CPlPanel::Build()
  {
   m_nh=0;
   PlFldBegin();
   m_off=-m_scroll;
   if(Strip())
     {
      //--- one row, no body, no footer, nothing to scroll
      m_off=0; m_scroll=0; m_vis_top=0; m_vis_bot=m_h-2; m_foot_h=0;
      BuildStrip();
      m_content_end=P(PL_STRIP_H);
      if(!m_dry) Frame();
      return;
     }
   const bool quick=g_cfg.quick;
   const bool main_view=(!quick && !menu);
   const double ytop=PL_HDR+(main_view?PlPinH():0.0);
   m_vis_top=P(ytop);
   m_foot_h=quick?P(PL_QFOOT_H):main_view?P(PL_FOOT_H):0;
   m_vis_bot=m_h-2-m_foot_h;
   double y=ytop;
   if(quick) y=BuildQuick(y);
   else if(menu) y=BuildMenu(y);
   else y=BuildMain(y);
   m_content_end=(int)MathRound(y*m_s)+m_foot_h;
   if(m_dry) return;
   EdgeMask();
   if(quick) DrawFooter();
   else if(main_view) { DrawFooter(); DrawPinned(); }
   DrawScrollbar();
   DrawHeader();
   Frame();
  }

//--- a scrolled body is cut by the pinned status and the action row. A row that crosses such an edge is wiped whole
//--- (down to the first blank pixel row, the gap between two rows), so no cut-off box or half a number shows under
//--- the status line; fields and hit areas inside the wiped part are dropped too. The rows are one scroll away.
void CPlPanel::EdgeMask()
  {
   if(m_dry || m_maxscroll<=0) return;
   const uint bg=PlArgb(g_th.bg);
   const int x1=P(8), x2=m_w-1-P(8), lim=P(120);
   //--- the last body row is the one right above the footer: m_vis_bot+1 (the footer fill starts at m_h-m_foot_h)
   const int bot=m_vis_bot+1;
   int top_end=m_vis_top-1, bot_start=bot+1;
   m_band_top=0;
   if(m_scroll>0 && !m_cv.BlankRow(m_vis_top,bg,x1,x2))
     {
      int y=m_vis_top;
      while(y<bot && y<m_vis_top+lim && !m_cv.BlankRow(y,bg,x1,x2)) y++;
      if(y<bot && y<m_vis_top+lim) { m_cv.Fill(1,m_vis_top,m_w-2,y,bg); top_end=y; m_band_top=y-m_vis_top; }
     }
   if(m_scroll<m_maxscroll && !m_cv.BlankRow(bot,bg,x1,x2))
     {
      int y=bot;
      while(y>top_end && y>bot-lim && !m_cv.BlankRow(y,bg,x1,x2)) y--;
      if(y>top_end && y>bot-lim) { m_cv.Fill(1,y,m_w-2,bot,bg); bot_start=y; }
     }
   if(top_end<m_vis_top && bot_start>bot) return;
   for(int i=0;i<PLF_COUNT;i++)
      if(g_fl_used[i] && (g_fl_y[i]<=top_end || g_fl_y[i]+g_fl_h[i]>=bot_start)) g_fl_used[i]=false;
   for(int i=0;i<m_nh;i++)
     {
      const int id=m_hr[i].id;
      if(id==H_HEADER || id==H_MENU || id==H_COLLAPSE || id==H_LINES || id==H_ACTION || id==H_SWAP || id==H_CANCEL || id==H_COSTS || id==H_QKIND) continue;
      if(m_hr[i].y2<=top_end || m_hr[i].y1>=bot_start) { m_hr[i].y1=-1000; m_hr[i].y2=-1000; continue; }
      if(m_hr[i].y1<=top_end) m_hr[i].y1=top_end+1;
      if(m_hr[i].y2>=bot_start) m_hr[i].y2=bot_start-1;
     }
  }

//--- a thin thumb at the right edge when the body is longer than the window
void CPlPanel::DrawScrollbar()
  {
   if(m_dry || m_maxscroll<=0) return;
   int top=m_vis_top+P(4), bot=m_h-m_foot_h-P(4);
   int region=bot-top;
   if(region<P(24)) return;
   int viewport=m_h-m_vis_top-m_foot_h;
   int total=viewport+m_maxscroll;
   int th=(int)MathRound((double)region*viewport/total);
   if(th<P(18)) th=P(18);
   int ty=top+(int)MathRound((double)(region-th)*m_scroll/m_maxscroll);
   int w=P(3);
   color c=PlMix(g_th.text2,g_th.bg,0.45);
   m_cv.RR(m_w-2-w-P(1),ty,m_w-3-P(1),ty+th,w/2,PlArgb(c));
  }

void CPlPanel::Redraw()
  {
   if(!m_created) return;
   m_draws++;
   //--- font scale: menu scale on top of the DPI the terminal applies by itself
   m_s=PlScaleGet(g_cfg.scale);
   int dpi=(int)TerminalInfoInteger(TERMINAL_SCREEN_DPI);
   if(dpi<=0) dpi=96;
   m_fs=m_s/(dpi/96.0);
   m_fcur_f=-1; m_fcur_s=-1;
   for(int a=0;a<4;a++) for(int b=0;b<40;b++) m_th_cache[a][b]=0;
   int fsz=(int)MathRound(90*m_fs);
   if(fsz!=g_fl_font10 || (int)g_th.bg!=m_style_sig) { g_fl_font10=fsz; m_style_sig=(int)g_th.bg; PlFldRestyleAll(); }
   int newW=P(Strip()?PL_STRIP_W:PL_W);
   int old_h=m_h;
   int old_w=m_w;
   m_trim=0;
   //--- a second and third turn only when the scroll ends in the middle of a row (see below)
   for(int turn=0;turn<3;turn++)
     {
      //--- dry pass: measure
      m_dry=true;
      Build();
      int chart_h=(int)ChartGetInteger(0,CHART_HEIGHT_IN_PIXELS);
      int avail=chart_h-m_y-6-m_trim;
      if(avail<P(PL_HDR)+P(120)) avail=P(PL_HDR)+P(120);
      int want=m_content_end;
      int h=MathMin(want,avail);
      if(h<P(PL_HDR)) h=P(PL_HDR);
      int maxscroll=MathMax(0,want-h);
      if(to_costs)
        {
         //--- Costs just opened: bring its top into the window, the pinned action row stays at the bottom
         m_scroll=m_costs_top-m_vis_top;
         if(m_scroll<0) m_scroll=0;
         to_costs=false;
        }
      if(turn>0) m_scroll=maxscroll;                    // the scroll was at its end and the window got shorter: stay at the new end
      if(m_scroll>maxscroll) { m_scroll=maxscroll; }
      m_maxscroll=maxscroll;
      m_h=h; m_w=newW;
      if(m_cv.Width()!=m_w || m_cv.Height()!=m_h) m_cv.Resize(m_w,m_h);
      m_cv.Erase(0);
      //--- panel body
      m_cv.Box(0,0,m_w-1,m_h-1,P(6),PlArgb(g_th.bg),PlArgb(g_th.frame));
      m_dry=false;
      m_band_top=0;
      Build();
      //--- the scroll is at its end and the row under the status line was wiped (a row cut by an edge is wiped whole):
      //--- an empty band stays there for good. Make the panel that much shorter: the end of the scroll moves down by the band
      //--- and lands on the gap between two rows.
      if(m_scroll>0 && m_scroll>=m_maxscroll && m_band_top>0 && turn<2) { m_trim+=m_band_top; continue; }
      break;
     }
   PlFldCommit(m_x,m_y);
   m_cv.Update(true);
   if(old_w!=m_w) Clamp();
   if(old_h!=m_h || old_w!=m_w) Place();
  }

bool CPlPanel::Create(const int x,const int y)
  {
   m_x=x; m_y=y; m_scroll=0; m_hover_id=0; m_hover_arg=0; m_down_id=0; m_down_arg=0;
   m_btn_prev=false; m_dragging=false; m_nh=0; m_draws=0; m_dry=false; m_wm_w=0; m_off=0; m_vis_top=0;
   m_vis_bot=0; m_foot_h=0; m_maxscroll=0; m_costs_top=0; m_trim=0; m_band_top=0; confirm_view=false; to_costs=false;
   for(int i=0;i<PL_SEC_N;i++) m_sec[i]=(i==PL_SEC_TRADE);
   m_s=PlScaleGet(g_cfg.scale);
   m_w=P(PL_W); m_h=P(300);
   ObjectDelete(0,PL_PANEL_NAME);        // a panel object left by a template or a crash would make the creation fail without a word
   if(!m_cv.CreateBitmapLabel(PL_PANEL_NAME,m_x,m_y,m_w,m_h,COLOR_FORMAT_ARGB_NORMALIZE)) return false;
   ObjectSetInteger(0,PL_PANEL_NAME,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,PL_PANEL_NAME,OBJPROP_HIDDEN,true);
   ObjectSetInteger(0,PL_PANEL_NAME,OBJPROP_ZORDER,0);
   m_created=true;
   return true;
  }

void CPlPanel::Destroy()
  {
   if(!m_created) return;
   m_cv.Destroy();
   PlFldDeleteAll();
   m_created=false;
  }

void CPlPanel::Place()
  {
   if(!m_created) return;
   ObjectSetInteger(0,PL_PANEL_NAME,OBJPROP_XDISTANCE,m_x);
   ObjectSetInteger(0,PL_PANEL_NAME,OBJPROP_YDISTANCE,m_y);
   PlFldMove(m_x,m_y);
  }

//--- keep the panel inside the chart
void CPlPanel::Clamp()
  {
   int cw=(int)ChartGetInteger(0,CHART_WIDTH_IN_PIXELS);
   int ch=(int)ChartGetInteger(0,CHART_HEIGHT_IN_PIXELS);
   if(cw<=0 || ch<=0) return;      // terminal start: the size is not known yet, keep the saved place (CHART_CHANGE clamps on the first real size)
   if(m_x+m_w>cw) m_x=cw-m_w;
   if(m_x<0) m_x=0;
   if(m_y+P(PL_HDR)>ch) m_y=ch-P(PL_HDR);
   if(m_y<0) m_y=0;
  }

bool CPlPanel::Inside(const int mx,const int my) const
  {
   if(!m_created) return false;
   return (mx>=m_x && my>=m_y && mx<m_x+m_w && my<m_y+m_h);
  }

int CPlPanel::HitAt(const int mx,const int my) const
  {
   int lx=mx-m_x, ly=my-m_y;
   for(int i=m_nh-1;i>=0;i--)
      if(lx>=m_hr[i].x1 && lx<=m_hr[i].x2 && ly>=m_hr[i].y1 && ly<=m_hr[i].y2) return i;
   return -1;
  }

//--- CHARTEVENT_MOUSE_MOVE: hover, press, release, header drag
void CPlPanel::OnMouse(const int mx,const int my,const int flags)
  {
   if(!m_created) return;
   act_id=0; act_arg=0; act_tid=0;
   bool left=((flags&1)!=0);
   if(m_dragging)
     {
      if(!left)
        {
         m_dragging=false; moved=true;
         m_btn_prev=false; m_down_id=0; m_down_arg=0;   // the release is handled here: a press at the same spot right after must start a new drag
         Redraw();             // the window height depends on the place: size it for the new place now, not on the next mouse move
         ChartRedraw();
         return;
        }
      m_x=mx-m_drag_dx; m_y=my-m_drag_dy;
      Clamp();
      Place();
      ChartRedraw();
      m_btn_prev=left;
      return;
     }
   int hi=HitAt(mx,my);
   int hid=(hi>=0 && m_hr[hi].id!=H_HEADER)?m_hr[hi].id:0;
   int harg=(hi>=0 && hid!=0)?m_hr[hi].arg:0;
   bool changed=false;
   if(hid!=m_hover_id || harg!=m_hover_arg) { m_hover_id=hid; m_hover_arg=harg; changed=true; }
   if(left && !m_btn_prev)
     {
      if(hi>=0)
        {
         m_down_id=m_hr[hi].id; m_down_arg=m_hr[hi].arg; changed=true;
         m_down_tid=0;
         if(m_down_id==H_ROW_X || m_down_id==H_ROW_EXP || m_down_id==H_ROW_BTN)
           {
            const int row=(m_down_id==H_ROW_BTN)?m_down_arg/8:m_down_arg;
            if(row>=0 && row<m_nrows) m_down_tid=m_row_id[row];       // the row is remembered by its id at the press
           }
         if(m_down_id==H_HEADER) { m_dragging=true; m_drag_dx=mx-m_x; m_drag_dy=my-m_y; }
        }
      else { m_down_id=0; m_down_arg=0; }
     }
   if(!left && m_btn_prev)
     {
      int did=m_down_id, darg=m_down_arg;
      const ulong dtid=m_down_tid;
      m_down_id=0; m_down_arg=0; m_down_tid=0; changed=true;
      if(did!=0 && did!=H_HEADER && did==hid && darg==harg)
        {
         //--- panel-internal actions
         bool internal=true;
         switch(did)
           {
            case H_MENU:      menu=!menu; m_scroll=0; PlFldClearBad(); act_id=H_MENU; break;
            case H_COLLAPSE:  g_cfg.quick=!g_cfg.quick; menu=false; m_scroll=0; PlFldClearBad(); act_id=H_COLLAPSE; break;
            case H_COSTS:     costs=!costs; to_costs=costs; PlFldClearBad(); break;
            case H_POS:       pos_open=!pos_open; to_costs=pos_open; PlFldClearBad(); break;
            case H_COSTS_X:   costs=false; PlFldClearBad(); break;
            case H_COMM_GO:   OpenSection(PL_SEC_COMMISSION,true); PlFldClearBad(); break;
            case H_ROW_EXP:
               if(dtid!=0) m_exp_id=(m_exp_id==dtid)?0:dtid;
               break;
            case H_SEC:       m_sec[darg]=!m_sec[darg]; PlFldClearBad(); break;
            default:          internal=false;
           }
         if(!internal) { act_id=did; act_arg=darg; act_tid=dtid; }
         m_btn_prev=left;
         Redraw();
         ChartRedraw();
         return;
        }
     }
   m_btn_prev=left;
   if(changed) { Redraw(); ChartRedraw(); }
  }

bool CPlPanel::OnWheel(const int mx,const int my,const double delta)
  {
   if(!m_created || !Inside(mx,my)) return false;
   int step=P(48);
   int old=m_scroll;
   if(delta>0) m_scroll-=step; else if(delta<0) m_scroll+=step;
   if(m_scroll<0) m_scroll=0;
   Redraw();           // clamps the upper bound
   ChartRedraw();
   return (old!=m_scroll);
  }

//--- chart objects are drawn in creation order: recreate the panel and its edits so they sit above
//--- lines that were created after them
void CPlPanel::Raise()
  {
   if(!m_created) return;
   m_cv.Destroy();
   PlFldDeleteAll();
   if(!m_cv.CreateBitmapLabel(PL_PANEL_NAME,m_x,m_y,m_w,m_h,COLOR_FORMAT_ARGB_NORMALIZE)) { m_created=false; return; }
   ObjectSetInteger(0,PL_PANEL_NAME,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,PL_PANEL_NAME,OBJPROP_HIDDEN,true);
   ObjectSetInteger(0,PL_PANEL_NAME,OBJPROP_ZORDER,0);
   Redraw();
   Place();
  }

//--- opens one section of the menu (and shows the menu); only=true closes the others
void CPlPanel::OpenSection(const int idx,const bool only)
  {
   if(idx<0 || idx>=PL_SEC_N) return;
   if(only) for(int i=0;i<PL_SEC_N;i++) m_sec[i]=false;
   m_sec[idx]=true; menu=true; m_scroll=0;
  }

void CPlPanel::Rescale()
  {
   if(!m_created) return;
   Redraw();
   Place();
  }

//--- every hit and field rectangle in chart pixels, for the development driver
void CPlPanel::LogGeom()
  {
#ifdef PL_DEV_LOG
   PLDBG("GEOM panel x="+(string)m_x+" y="+(string)m_y+" w="+(string)m_w+" h="+(string)m_h+" scale="+DoubleToString(m_s,3)+" scroll="+(string)m_scroll);
   for(int i=0;i<m_nh;i++)
      PLDBG("GEOM H"+(string)m_hr[i].id+":"+(string)m_hr[i].arg+" "+(string)(m_x+m_hr[i].x1)+" "+(string)(m_y+m_hr[i].y1)
            +" "+(string)(m_x+m_hr[i].x2)+" "+(string)(m_y+m_hr[i].y2));
   for(int i=0;i<PLF_COUNT;i++)
      if(g_fl_used[i] && g_fl_vis[i])
         PLDBG("GEOM F"+(string)i+" "+(string)(m_x+g_fl_x[i])+" "+(string)(m_y+g_fl_y[i])+" "+(string)(m_x+g_fl_x[i]+g_fl_w[i])
               +" "+(string)(m_y+g_fl_y[i]+g_fl_h[i]));
#endif
  }

#endif
