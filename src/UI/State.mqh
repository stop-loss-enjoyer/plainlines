// Required Notice: Copyright 2026 stop-loss-enjoyer
// Plainlines is source-available under the PolyForm Shield License 1.0.0.
//
// Shared state of the program (settings, draft, model globals) and its files in
// MQL5/Files/Plainlines/: settings.dat and sym_<PlStateKey>.dat, plain key=value text.
// No account number, no hash of it, anywhere.
#property strict

#ifndef PL_UI_STATE_MQH
#define PL_UI_STATE_MQH

// PL_DIR and the development log (PLDBG) come from Terminal/DevLog.mqh, included before this file
#define PL_SETTINGS_FILE  "Plainlines\\settings.dat"

//--- menu and look settings, saved in settings.dat
struct PlSettings
  {
   int               base;            // PlRiskBase
   double            lot_fixed;
   double            cap;             // hard cap percent
   double            confirm_above;
   bool              subtract_open;
   int               over_max;        // PlOverMax: lot above the broker max is blocked, trimmed or split
   bool              atr_on;
   double            atr_mult;
   int               atr_period;
   int               tp_count;        // 1..3
   double            tp_share2;       // percent of the lot at TP2 (tp_count>=2)
   double            tp_share3;       // percent of the lot at TP3 (tp_count==3)
   bool              no_sl;
   bool              no_tp;
   long              magic;
   string            comment;
   int               expiry_mode;     // 0 GTC, 1 today, 2 hours
   int               expiry_hours;
   double            max_spread;      // percent of the SL distance
   bool              confirm_on;
   bool              first_sent;      // a trade of this terminal has gone out: until then the first press asks once (a file that has no such key is an old one: true)
   bool              be_on;
   double            be_r;
   bool              trail_on;        // trailing stop in pips
   double            part_pct;        // the "Close 50%" button
   bool              close_btns;
   bool              sounds;           // trade sounds on open and close
   bool              lines;            // the lines of the draft on the chart; off keeps the prices, the fields set them
   int               max_open;        // 0 = off
   int               max_day;         // 0 = off
   double            margin_use;      // CONFIRM above this margin use after the trade, 0 = off
   int               theme;           // 0 Auto, 1 Light, 2 Dark
   int               scale;           // 0 Auto, 1 100, 2 125, 3 150
   bool              quick;           // the quick panel (risk, order type, open button) is shown; false: the full panel
   int               quick_style;     // the quick panel as a 0 strip (one row) or 1 card; the same for the terminal, like the theme
   int               line_thick;      // the lines on the chart: 0 Thin (1 px), 1 Thick (2 px, 3 above scale 100); the same for the terminal, like the theme
   bool              click_place;     // Advanced, Click to place: the Market and Limit buttons put the lines with the pointer, click by click; off by default, the same for the terminal
   int               px;              // panel position in chart pixels, -1 = default
   int               py;
  };

//--- what the user set per symbol, saved in sym_<key>.dat
struct PlDraft
  {
   PlKind            kind;
   bool              unit_money;      // risk entered in money (true) or percent (false)
   double            risk_pct;
   double            risk_money;
   double            tp_r[PL_MAX_TP];
   bool              tp_price[PL_MAX_TP]; // TP given as a price (R follows the price)
   double            sl_ticks;        // signed distance SL minus entry, in ticks (negative = below)
   double            tp_ticks;        // signed distance TP1 minus entry, in ticks, for price mode
   double            trail_dist;      // trailing distance in the SL field unit of this symbol (pips forex 3/5 digits, else points), 0 = the initial SL distance
   PlCommission      comm;
  };

//--- prices of the lines; the lines on the chart and these numbers are kept equal
struct PlPx
  {
   double            entry;
   double            limit;
   double            sl;
   double            tp[PL_MAX_TP];
  };

PlSettings g_cfg;
PlDraft    g_dr;
PlPx       g_px;
PlSymbol   g_sym;
PlAccount  g_acc;
PlInputs   g_in;
PlPlan     g_plan;
PlResult   g_res;
int        g_split_orders=0;         // Split: the number of orders the trade goes out as (parts times TP levels), 0 without Split
int        g_new_orders=1;           // orders the trade on the panel would put on the account (1 for a single order), for the trade counters of the guards
bool       g_hint_ok=false;
double     g_hint_in=0.0, g_hint_out=0.0;
bool       g_hint_closed=false;
double     g_atr=0.0;
string     g_msg="";            // transient status message
ulong      g_msg_until=0;
ulong      g_msg_at=0;          // when it was set (the quick strip shows a result for a few seconds only)
int        g_msg_kind=0;        // 0 plain, 1 done (green dot), 2 refused (red), 3 a closed position in profit (green text), 4 in loss (red text)
string     g_lines_hid="";      // the symbol of this chart whose lines were taken off after a fill (memory only; the eye or another symbol ends it)
bool       g_msg_sticky=false;  // the result of a closed position: stays until the trader acts (PlStickyClear) or another message replaces it

//--- the order flow: press, confirmation, send, check, cool-down
#define PL_ARM_PAUSE_MS    500      // a second press earlier than this is ignored
#define PL_ARM_WINDOW_MS   3000     // and later than this the confirmation has lapsed
#define PL_COOLDOWN_MS     1000     // presses are ignored for this long after every answer
enum PlFlow { PL_FLOW_IDLE=0, PL_FLOW_ARMED, PL_FLOW_SENDING, PL_FLOW_CHECKING, PL_FLOW_COOLDOWN };
int         g_flow=PL_FLOW_IDLE;
ulong       g_armed_at=0;           // GetTickCount64 of the first press
ulong       g_cool_until=0;
PlOrderSnap g_snap;                 // the frozen plan of the pending confirmation
PlSendRes   g_sres;                 // the last result

//--- are the lines of the plan on this chart: the saved switch (the terminal's) and not hidden after a fill
bool PlLinesOn() { return g_cfg.lines && g_lines_hid!=_Symbol; }

//--- key=value store ---------------------------------------------------------------------------
string g_kv_k[];
string g_kv_v[];

void PlKvClear() { ArrayResize(g_kv_k,0); ArrayResize(g_kv_v,0); }

void PlKvSet(const string k,const string v)
  {
   int n=ArraySize(g_kv_k);
   for(int i=0;i<n;i++) if(g_kv_k[i]==k) { g_kv_v[i]=v; return; }
   ArrayResize(g_kv_k,n+1); ArrayResize(g_kv_v,n+1);
   g_kv_k[n]=k; g_kv_v[n]=v;
  }

void PlKvDel(const string k)
  {
   int n=ArraySize(g_kv_k);
   for(int i=0;i<n;i++)
      if(g_kv_k[i]==k)
        {
         for(int j=i;j<n-1;j++) { g_kv_k[j]=g_kv_k[j+1]; g_kv_v[j]=g_kv_v[j+1]; }
         ArrayResize(g_kv_k,n-1); ArrayResize(g_kv_v,n-1);
         return;
        }
  }

void PlKvSetD(const string k,const double v) { PlKvSet(k,DoubleToString(v,8)); }
void PlKvSetI(const string k,const long v)   { PlKvSet(k,(string)v); }
void PlKvSetB(const string k,const bool v)   { PlKvSet(k,v?"1":"0"); }

bool PlKvHas(const string k)
  {
   for(int i=ArraySize(g_kv_k)-1;i>=0;i--) if(g_kv_k[i]==k) return true;
   return false;
  }

string PlKvGet(const string k,const string def)
  {
   for(int i=ArraySize(g_kv_k)-1;i>=0;i--) if(g_kv_k[i]==k) return g_kv_v[i];
   return def;
  }

double PlKvD(const string k,const double def) { return PlKvHas(k)?StringToDouble(PlKvGet(k,"")):def; }
long   PlKvI(const string k,const long def)   { return PlKvHas(k)?StringToInteger(PlKvGet(k,"")):def; }
bool   PlKvB(const string k,const bool def)   { return PlKvHas(k)?(StringToInteger(PlKvGet(k,"0"))!=0):def; }

//--- Every file ends with a line sum=<8 hex>, the FNV-1a checksum of all the k=v lines before it. A truncated file,
//--- an empty one, a half-flushed one and a read during another chart's write all fail the check, so a reader
//--- never takes a torn file for a real one (an atomic rename is not allowed by the audit). The sum key is never
//--- stored in the arrays: it ends the body.
bool   g_kv_valid=false;        // the last PlKvLoad found a correct sum line
string g_kv_sum="";             // its value (valid load) or the sum of the last save; "" otherwise

bool PlKvLoad(const string file)
  {
   PlKvClear();
   g_kv_valid=false; g_kv_sum="";
   if(!FileIsExist(file)) return false;
   int h=FileOpen(file,FILE_READ|FILE_TXT|FILE_ANSI|FILE_SHARE_READ|FILE_SHARE_WRITE);
   if(h==INVALID_HANDLE) return false;
   string body="", sumv="";
   bool seen=false, after=false;
   while(!FileIsEnding(h))
     {
      string ln=FileReadString(h);
      StringTrimRight(ln);
      int p=StringFind(ln,"=");
      if(p<=0) continue;
      const string k=StringSubstr(ln,0,p);
      if(k=="sum")
        {
         if(seen) after=true;      // a second sum line: not a file this program wrote
         seen=true; sumv=StringSubstr(ln,p+1);
         continue;
        }
      if(seen) after=true;
      const string v=StringSubstr(ln,p+1);
      body+=k+"="+v+"\n";
      PlKvSet(k,v);
     }
   FileClose(h);
   g_kv_valid=(seen && !after && sumv==PlFnv32Hex(body));
   g_kv_sum=g_kv_valid?sumv:"";
   return true;
  }

bool PlKvSave(const string file)
  {
   FolderCreate(PL_DIR);
   int h=FileOpen(file,FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_SHARE_READ);
   if(h==INVALID_HANDLE) return false;
   string body="";
   for(int i=0;i<ArraySize(g_kv_k);i++)
     {
      string ln=g_kv_k[i]+"="+g_kv_v[i];
      StringTrimRight(ln);                      // the reader trims the end of a line, so the sum is taken on the trimmed line
      FileWriteString(h,ln+"\r\n");
      body+=ln+"\n";
     }
   const string sum=PlFnv32Hex(body);
   FileWriteString(h,"sum="+sum+"\r\n");
   FileClose(h);
   g_kv_sum=sum;
   return true;
  }

//--- defaults ----------------------------------------------------------------------------------
void PlSettingsDefaults()
  {
   g_cfg.base=PL_BASE_BALANCE; g_cfg.lot_fixed=0.10;
   g_cfg.cap=5.0; g_cfg.confirm_above=2.0; g_cfg.subtract_open=false; g_cfg.over_max=PL_OVER_BLOCK;
   g_cfg.atr_on=false; g_cfg.atr_mult=1.5; g_cfg.atr_period=14;
   g_cfg.tp_count=1; g_cfg.tp_share2=30.0; g_cfg.tp_share3=20.0;
   g_cfg.no_sl=false; g_cfg.no_tp=false;
   g_cfg.magic=20261011; g_cfg.comment="Plainlines"; g_cfg.expiry_mode=0; g_cfg.expiry_hours=24; g_cfg.max_spread=30.0;
   g_cfg.first_sent=false;
   g_cfg.confirm_on=false;                  // one click on the action button sends; the second-press asks below stay
   g_cfg.be_on=false; g_cfg.be_r=1.0; g_cfg.trail_on=false; g_cfg.part_pct=50.0;
   g_cfg.close_btns=true; g_cfg.sounds=true; g_cfg.lines=true;
   g_cfg.max_open=0; g_cfg.max_day=0; g_cfg.margin_use=50.0;
   g_cfg.theme=0; g_cfg.scale=0;
   g_cfg.quick=true; g_cfg.quick_style=0; g_cfg.line_thick=1; g_cfg.click_place=false; g_cfg.px=-1; g_cfg.py=-1;
   //--- the risk is the last one typed or chosen on this terminal (one account), the same on every symbol
   g_dr.unit_money=false; g_dr.risk_pct=1.0; g_dr.risk_money=100.0;
  }

void PlDraftDefaults()
  {
   g_dr.kind=PL_KIND_MARKET;                 // the risk (unit, percent, money) lives in settings.dat, a symbol change keeps it
   for(int i=0;i<PL_MAX_TP;i++) { g_dr.tp_r[i]=2.0+i; g_dr.tp_price[i]=false; }
   g_dr.sl_ticks=0.0; g_dr.tp_ticks=0.0; g_dr.trail_dist=0.0;
   g_dr.comm.kind=PL_COMM_UNKNOWN; g_dr.comm.rate=0.0; g_dr.comm.source=PL_COMMSRC_NONE; g_dr.comm.min_money=0.0;
  }

//--- settings.dat ------------------------------------------------------------------------------
string g_settings_sum="";      // the checksum of the settings.dat this chart last read or wrote ("" = unknown: read again)
bool   g_settings_bad=false;   // settings.dat was damaged when read
string g_risk_rid="";          // the profile id the risk is kept under besides the terminal's last one ("" until the account is known)
bool   g_risk_migrate=false;   // settings.dat had no risk_pct when read: the first draft that holds a risk hands it over (PlDraftLoad)

//--- another chart wrote settings.dat since we last read or wrote it (compared by content, not by the 1 s file date)
//--- the file as one read: a file that exists and fails its sum may be mid-write by another chart, so it is looked at up to
//--- three more times (15 ms apart) before it counts as torn. false: no file; g_kv_valid says whether the last look was whole
bool PlSettingsRead()
  {
   bool have=PlKvLoad(PL_SETTINGS_FILE);
   for(int t=0;t<3 && have && !g_kv_valid;t++)
     {
      Sleep(15);
      have=PlKvLoad(PL_SETTINGS_FILE);
     }
   return have;
  }

bool PlSettingsChangedByOther()
  {
   if(!PlKvLoad(PL_SETTINGS_FILE) || !g_kv_valid) return false;    // missing, mid-write or damaged: next second
   return g_kv_sum!=g_settings_sum;
  }

//--- settings.dat is shared by every chart: each instance writes only the keys it changed itself since it
//--- last read or wrote the file, so a second chart cannot roll back what the first one set
string g_snap_k[];
string g_snap_v[];

void PlSettingsBuild()
  {
   PlKvClear();
   PlKvSetI("base",g_cfg.base); PlKvSetD("lot_fixed",g_cfg.lot_fixed);
   PlKvSetD("confirm_above",g_cfg.confirm_above);
   PlKvSetB("subtract_open",g_cfg.subtract_open); PlKvSetI("over_max",g_cfg.over_max);
   PlKvSetB("atr_on",g_cfg.atr_on); PlKvSetD("atr_mult",g_cfg.atr_mult); PlKvSetI("atr_period",g_cfg.atr_period);
   PlKvSetI("tp_count",g_cfg.tp_count); PlKvSetD("tp_share2",g_cfg.tp_share2); PlKvSetD("tp_share3",g_cfg.tp_share3);
   PlKvSetB("no_sl",g_cfg.no_sl); PlKvSetB("no_tp",g_cfg.no_tp);
   PlKvSetI("magic",g_cfg.magic); PlKvSet("comment",g_cfg.comment);
   PlKvSetI("expiry_mode",g_cfg.expiry_mode); PlKvSetI("expiry_hours",g_cfg.expiry_hours); PlKvSetD("max_spread",g_cfg.max_spread);
   PlKvSetB("confirm_on",g_cfg.confirm_on); PlKvSetB("confirm_v2",true);
   PlKvSetB("first_sent",g_cfg.first_sent);
   PlKvSetB("be_on",g_cfg.be_on); PlKvSetD("be_r",g_cfg.be_r); PlKvSetB("trail_on",g_cfg.trail_on);
   PlKvSetD("part_pct",g_cfg.part_pct);
   PlKvSetB("close_btns",g_cfg.close_btns);
   PlKvSetB("sounds",g_cfg.sounds);
   PlKvSetB("lines",g_cfg.lines);
   PlKvSetI("max_open",g_cfg.max_open); PlKvSetI("max_day",g_cfg.max_day); PlKvSetD("margin_use",g_cfg.margin_use);
   PlKvSetI("theme",g_cfg.theme); PlKvSetI("scale",g_cfg.scale);
   PlKvSetB("quick",g_cfg.quick); PlKvSetI("quick_style",g_cfg.quick_style); PlKvSetI("line_thick",g_cfg.line_thick); PlKvSetB("click_place",g_cfg.click_place); PlKvSetI("px",g_cfg.px); PlKvSetI("py",g_cfg.py);
   //--- the risk: the plain keys are the last risk of this terminal (what an account seen for the first time starts with),
   //--- the keys with @<profile id> are the last risk of that account. Both live in this one file, so the
   //--- per-key merge of PlSettingsSave between charts covers them as well.
   PlKvSetB("unit_money",g_dr.unit_money); PlKvSetD("risk_pct",g_dr.risk_pct); PlKvSetD("risk_money",g_dr.risk_money);
   if(g_risk_rid!="")
     {
      const string sx="@"+g_risk_rid;
      PlKvSetB("unit_money"+sx,g_dr.unit_money); PlKvSetD("risk_pct"+sx,g_dr.risk_pct); PlKvSetD("risk_money"+sx,g_dr.risk_money);
      //--- the hard cap is kept for that account only: there is no plain key, so a new account never takes another's raised cap
      PlKvSetD("cap"+sx,g_cfg.cap);
     }
  }

string PlSnapGet(const string k,bool &found)
  {
   for(int i=ArraySize(g_snap_k)-1;i>=0;i--) if(g_snap_k[i]==k) { found=true; return g_snap_v[i]; }
   found=false;
   return "";
  }

void PlSnapTake()
  {
   int n=ArraySize(g_kv_k);
   ArrayResize(g_snap_k,n); ArrayResize(g_snap_v,n);
   for(int i=0;i<n;i++) { g_snap_k[i]=g_kv_k[i]; g_snap_v[i]=g_kv_v[i]; }
  }

bool g_settings_retry=false;        // the last save did not reach the disk: the one-second lap saves again
int  g_settings_torn=0;             // saves in a row that found the file torn after the looks
int  g_settings_fails=0;            // writes in a row that did not reach the disk
bool g_settings_fail_said=false;    // the note "Settings not saved" was asked for once in this session
bool g_settings_fail_say=false;     // ... and waits for the timer lap of the program to show it (the message lives after this file)

void PlSettingsSave()
  {
   PlSettingsBuild();
   int n=ArraySize(g_kv_k);
   string ok_[]; string ov_[];
   ArrayResize(ok_,n); ArrayResize(ov_,n);
   for(int i=0;i<n;i++) { ok_[i]=g_kv_k[i]; ov_[i]=g_kv_v[i]; }
   g_settings_retry=false;
   const bool have=PlSettingsRead();
   if(have && !g_kv_valid && g_settings_torn<3)
     {
      //--- torn: another chart is writing it, or it is damaged. Nothing is written (the keys of the other accounts live only
      //--- there); the lap saves again. A file that stays bad for three laps is merged as empty, so a damaged one heals.
      g_settings_torn++; g_settings_retry=true;
      ArrayResize(g_kv_k,n); ArrayResize(g_kv_v,n);
      for(int i=0;i<n;i++) { g_kv_k[i]=ok_[i]; g_kv_v[i]=ov_[i]; }
      return;
     }
   g_settings_torn=0;
   if(!have || !g_kv_valid) PlKvClear();   // what is on disk now (a damaged file merges as empty)
   //--- keys no build reads any more (a black list: a key that a newer build writes on another chart is not ours to drop)
   PlKvDel("risk_lot"); PlKvDel("collapsed"); PlKvDel("cap");
   bool foreign=false;
   for(int i=0;i<n;i++)
     {
      bool found;
      string sv=PlSnapGet(ok_[i],found);
      if(!found || sv!=ov_[i] || !PlKvHas(ok_[i])) PlKvSet(ok_[i],ov_[i]);
      else if(PlKvGet(ok_[i],"")!=ov_[i]) foreign=true;           // another chart changed this key
     }
   if(!PlKvSave(PL_SETTINGS_FILE))
     {
      //--- not written (the file is open in another program): the snapshot stays where it was, so the keys are written next time
      g_settings_retry=true;
      //--- the same write failing on three laps in a row is not a moment of lock: once per session the status line says so (trading is not blocked)
      g_settings_fails++;
      if(g_settings_fails>=3 && !g_settings_fail_said) { g_settings_fail_said=true; g_settings_fail_say=true; }
      ArrayResize(g_kv_k,n); ArrayResize(g_kv_v,n);
      for(int i=0;i<n;i++) { g_kv_k[i]=ok_[i]; g_kv_v[i]=ov_[i]; }
      return;
     }
   g_settings_fails=0;
   g_risk_migrate=false;                       // the file now holds a risk: a draft of the earlier version no longer overrides it
   g_settings_sum=foreign?"":g_kv_sum;        // foreign: the next lap reads the file through the normal path
   //--- the snapshot is what this instance holds, not what the disk has
   ArrayResize(g_kv_k,n); ArrayResize(g_kv_v,n);
   for(int i=0;i<n;i++) { g_kv_k[i]=ok_[i]; g_kv_v[i]=ov_[i]; }
   PlSnapTake();
  }

double PlClampD(const double v,const double lo,const double hi) { return MathMax(lo,MathMin(hi,v)); }

//--- the risk from the key store (settings.dat now, or an old draft once): a bad value keeps the current one. sx is "" for the
//--- terminal's last risk or "@<profile id>" for that account's; keys that are not there change nothing.
void PlRiskTake(const string sx="")
  {
   g_dr.unit_money=PlKvB("unit_money"+sx,g_dr.unit_money);
   const double rp=PlKvD("risk_pct"+sx,g_dr.risk_pct), rm=PlKvD("risk_money"+sx,g_dr.risk_money);
   if(rp>0.0 && rp<=100.0) g_dr.risk_pct=rp;
   if(rm>0.0 && rm<=1.0e9) g_dr.risk_money=rm;
  }

//--- the hard cap of one account ("cap@<profile id>"); a key that is not there changes nothing (the default 5 percent stands)
void PlCapTake(const string sx)
  {
   g_cfg.cap=PlClampD(PlKvD("cap"+sx,g_cfg.cap),0.1,100.0);
  }

void PlSettingsLoad()
  {
   PlSettingsDefaults();
   g_settings_sum=""; g_settings_bad=false;
   g_risk_migrate=true;                        // until a valid file with risk_pct says otherwise
   if(!PlSettingsRead()) { PlSettingsBuild(); PlSnapTake(); return; }
   if(!g_kv_valid)
     {
      g_settings_bad=true;
      g_cfg.first_sent=true;                  // a damaged file is most likely an old one: no extra press
      PlKvClear();
      PlSettingsBuild();
      PlSnapTake();
      return;
     }
   //--- one time: a file written before the default turned off (no confirm_v2) stores confirm_on=1 for everyone, so it is
   //--- set to off here and written at once; after that the user's choice stands
   if(!PlKvHas("confirm_v2"))
     {
      PlKvSetB("confirm_on",false); PlKvSetB("confirm_v2",true);
      PlKvSave(PL_SETTINGS_FILE);
     }
   g_settings_sum=g_kv_sum;
   g_cfg.base=(int)PlClampD((double)PlKvI("base",g_cfg.base),0,1);
   g_cfg.lot_fixed=PlKvD("lot_fixed",g_cfg.lot_fixed);
   g_cfg.confirm_above=PlKvD("confirm_above",g_cfg.confirm_above);
   g_cfg.subtract_open=PlKvB("subtract_open",g_cfg.subtract_open); 
   //--- the earlier version kept trim_max (true: trim to the broker max): it reads as Trim
   g_cfg.over_max=(int)PlClampD((double)PlKvI("over_max",PlKvB("trim_max",false)?PL_OVER_TRIM:PL_OVER_BLOCK),0,2);
   g_cfg.atr_on=PlKvB("atr_on",g_cfg.atr_on); g_cfg.atr_mult=PlKvD("atr_mult",g_cfg.atr_mult);
   g_cfg.atr_period=(int)PlClampD((double)PlKvI("atr_period",g_cfg.atr_period),1,500);
   g_cfg.tp_count=(int)PlClampD((double)PlKvI("tp_count",g_cfg.tp_count),1,PL_MAX_TP);
   g_cfg.tp_share2=PlKvD("tp_share2",g_cfg.tp_share2); g_cfg.tp_share3=PlKvD("tp_share3",g_cfg.tp_share3);
   g_cfg.no_sl=PlKvB("no_sl",g_cfg.no_sl); g_cfg.no_tp=PlKvB("no_tp",g_cfg.no_tp);
   g_cfg.magic=PlKvI("magic",g_cfg.magic); if(g_cfg.magic<=0 || g_cfg.magic>2147483647) g_cfg.magic=20261011; g_cfg.comment=PlKvGet("comment",g_cfg.comment);
   g_cfg.expiry_mode=(int)PlClampD((double)PlKvI("expiry_mode",g_cfg.expiry_mode),0,2);
   g_cfg.expiry_hours=(int)PlClampD((double)PlKvI("expiry_hours",g_cfg.expiry_hours),1,9999);
   g_cfg.max_spread=PlKvD("max_spread",g_cfg.max_spread);
   g_cfg.confirm_on=PlKvB("confirm_on",g_cfg.confirm_on);
   g_cfg.first_sent=PlKvB("first_sent",true);          // a settings file of an earlier build has no such key: that terminal has traded
   g_cfg.be_on=PlKvB("be_on",g_cfg.be_on); g_cfg.be_r=PlKvD("be_r",g_cfg.be_r);
   //--- the earlier version kept trail_mode (0 off, 1 ATR, 2 pips): ATR becomes pips with the distance of the initial SL
   g_cfg.trail_on=PlKvB("trail_on",PlKvI("trail_mode",0)>0);
   g_cfg.part_pct=PlClampD(PlKvD("part_pct",g_cfg.part_pct),1.0,99.0);
   g_cfg.close_btns=PlKvB("close_btns",g_cfg.close_btns);
   g_cfg.sounds=PlKvB("sounds",g_cfg.sounds);
   g_cfg.lines=PlKvB("lines",g_cfg.lines);
   g_cfg.max_open=(int)PlClampD((double)PlKvI("max_open",g_cfg.max_open),0,1000); g_cfg.max_day=(int)PlClampD((double)PlKvI("max_day",g_cfg.max_day),0,10000);
   g_cfg.margin_use=PlClampD(PlKvD("margin_use",g_cfg.margin_use),0.0,1000.0);
   g_cfg.theme=(int)PlClampD((double)PlKvI("theme",g_cfg.theme),0,2);
   g_cfg.scale=(int)PlClampD((double)PlKvI("scale",g_cfg.scale),0,3);
   g_cfg.quick=PlKvB("quick",g_cfg.quick); g_cfg.quick_style=(int)PlClampD((double)PlKvI("quick_style",g_cfg.quick_style),0,1);
   g_cfg.line_thick=(int)PlClampD((double)PlKvI("line_thick",g_cfg.line_thick),0,1);      // a settings file of an earlier build has no such key: Thick
   g_cfg.click_place=PlKvB("click_place",false);      // a settings file of an earlier build has no such key: off
   g_cfg.px=(int)PlKvI("px",g_cfg.px); g_cfg.py=(int)PlKvI("py",g_cfg.py);
   g_risk_migrate=!PlKvHas("risk_pct");
   PlRiskTake();
   if(g_risk_rid!="")                                   // the account is known: its own risk goes over the terminal's last one, and its own cap is there
     {
      PlRiskTake("@"+g_risk_rid);
      PlCapTake("@"+g_risk_rid);
     }
   //--- the snapshot is the file as read, not what this instance now holds: a key held differently (the account's own risk
   //--- in the terminal's plain keys, a clamped value) counts as changed here and is written by the next save. A snapshot of
   //--- the memory made every save of a second account with another risk look like a change by another chart (a reread that
   //--- dropped an armed confirmation, demo stand 15.10.2026).
   PlSnapTake();
   PlSettingsBuild();
  }

//--- sym_<key>.dat -----------------------------------------------------------------------------
string PlDraftFile(const PlSymbol &s) { return PL_DIR+"\\sym_"+PlStateKey(s)+".dat"; }

bool g_draft_ok=false;     // the symbol key is ready: the draft may be read and written (never under a key made of empty fields)

void PlDraftSave(const PlSymbol &s)
  {
   if(!g_draft_ok) return;
   PlKvClear();
   PlKvSetI("kind",g_dr.kind);
   for(int i=0;i<PL_MAX_TP;i++)
     {
      PlKvSetD("tp_r"+IntegerToString(i+1),g_dr.tp_r[i]);
      PlKvSetB("tp_price"+IntegerToString(i+1),g_dr.tp_price[i]);
     }
   PlKvSetD("sl_ticks",g_dr.sl_ticks); PlKvSetD("tp_ticks",g_dr.tp_ticks); PlKvSetD("trail_dist",g_dr.trail_dist);
   PlKvSetI("comm_kind",g_dr.comm.kind); PlKvSetD("comm_rate",g_dr.comm.rate); PlKvSetI("comm_src",g_dr.comm.source);
   PlKvSave(PlDraftFile(s));
  }

bool PlDraftLoad(const PlSymbol &s)
  {
   PlDraftDefaults();
   if(!PlKvLoad(PlDraftFile(s)) || !g_kv_valid) return false;       // a torn draft is not taken in part
   g_dr.kind=(PlKind)(int)PlClampD((double)PlKvI("kind",0),0,3);
   for(int i=0;i<PL_MAX_TP;i++)
     {
      g_dr.tp_r[i]=PlKvD("tp_r"+IntegerToString(i+1),g_dr.tp_r[i]);
      g_dr.tp_price[i]=PlKvB("tp_price"+IntegerToString(i+1),false);
     }
   g_dr.sl_ticks=PlKvD("sl_ticks",0.0); g_dr.tp_ticks=PlKvD("tp_ticks",0.0); g_dr.trail_dist=MathMax(0.0,PlKvD("trail_dist",0.0));
   g_dr.comm.kind=(PlCommKind)(int)PlClampD((double)PlKvI("comm_kind",0),0,3);
   g_dr.comm.rate=PlKvD("comm_rate",0.0);
   g_dr.comm.source=(PlCommSource)(int)PlClampD((double)PlKvI("comm_src",0),0,2);
   //--- one time, from the earlier version: the risk lived in the draft. settings.dat had none, so this draft's risk
   //--- becomes the terminal's (last: PlSettingsSave rebuilds the key store). The draft file itself is left as it is.
   if(g_risk_migrate && PlKvHas("risk_pct"))
     {
      PlRiskTake();
      g_risk_migrate=false;
      PlSettingsSave();
     }
   return true;
  }

//--- the user's commission setting of a symbol (the chart symbol's draft in memory, another symbol's draft file).
//--- false: none set. The draft keeps only what the user chose (or took from the hint), never the broker's rule.
bool PlUserComm(const string sym,PlCommKind &kind,double &rate)
  {
   PlCommission c;
   c.kind=PL_COMM_UNKNOWN; c.rate=0.0; c.source=PL_COMMSRC_NONE; c.min_money=0.0;
   kind=PL_COMM_UNKNOWN; rate=0.0;
   if(sym==g_sym.name && g_draft_ok) c=g_dr.comm;
   else
     {
      PlSymbol s;
      if(!PlReadSymbol(sym,s)) return false;
      string sk[], sv[];                       // the store is shared: put it back as it was
      ArrayCopy(sk,g_kv_k); ArrayCopy(sv,g_kv_v);
      const bool sval=g_kv_valid; const string ssum=g_kv_sum;
      const bool ok=(PlKvLoad(PlDraftFile(s)) && g_kv_valid);
      if(ok)
        {
         c.kind=(PlCommKind)(int)PlClampD((double)PlKvI("comm_kind",0),0,3);
         c.rate=PlKvD("comm_rate",0.0);
        }
      ArrayResize(g_kv_k,ArraySize(sk)); ArrayResize(g_kv_v,ArraySize(sv)); ArrayCopy(g_kv_k,sk); ArrayCopy(g_kv_v,sv); g_kv_valid=sval; g_kv_sum=ssum;
      if(!ok) return false;
     }
   if(c.rate<0.0 || c.kind==PL_COMM_UNKNOWN) return false;
   kind=c.kind; rate=c.rate;
   return true;
  }

//--- a commission setting (kind, rate) as money for the round trip of a volume from ex to sl, for a pending order of another chart.
//--- A percent setting is valued with OrderCalcProfit for a 1 percent move (the broker's own conversion). false: cannot be valued.
bool PlCommMoneyOf(const PlCommKind kind,const double rate,const string sym,const ENUM_ORDER_TYPE ot,const double vol,const double ex,const double sl,double &money,const double min_round)
  {
   money=0.0;
   switch(kind)
     {
      case PL_COMM_LOT_SIDE:  money=2.0*rate*vol; return true;
      case PL_COMM_LOT_ROUND: money=MathMax(rate*vol,min_round); return true;      // the broker minimum of the one order
      case PL_COMM_PERCENT_SIDE:
        {
         double p1=0.0;
         if(ex<=0.0 || sl<=0.0 || !OrderCalcProfit(ot,sym,vol,ex,ex*1.01,p1) || p1==0.0) return false;
         money=MathAbs(p1)*rate*(1.0+sl/ex);      // notional in money = |p1| * 100, per side rate percent, the exit at the SL price
         return true;
        }
     }
   return false;
  }

bool PlUserCommMoney(const string sym,const ENUM_ORDER_TYPE ot,const double vol,const double ex,const double sl,double &money)
  {
   money=0.0;
   PlCommKind k; double rt;
   if(!PlUserComm(sym,k,rt)) return false;
   return PlCommMoneyOf(k,rt,sym,ot,vol,ex,sl,money);
  }

#endif
