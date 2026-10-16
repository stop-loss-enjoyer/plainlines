// Required Notice: Copyright 2026 stop-loss-enjoyer
// Plainlines is source-available under the PolyForm Shield License 1.0.0.
//
// Test script on real symbol data (src/SymbolVectors.mqh, generated from
// read-only broker probes of 13.10.2026). Runs the pure core on every symbol of every set: the lot
// grid, the refusal without a quote, the loss per lot paths (a) and (c) against the probe's own
// OrderCalcProfit numbers, a full PlPrepare + PlCompute run and the final-volume margin check.
// A row of a set whose probe read SymbolInfoCommissions (the FTMO demo, all 166 symbols with the quotes the demo held at
// probe time) also carries the broker's commission rule and the session/tick-age state of the probe: the test then runs the
// pure PlBrokerCommRule on it, PlCompute with that commission, and PlCompute again with the probe's own session and tick age
// (a closed market must give exactly PL_R_MARKET_CLOSED, a stale quote on an open session exactly PL_R_STALE_QUOTE, and in
// both the same lot as the fresh run). Every BLOCK of those runs is listed with symbol, reason name, currencies and
// tick_value_loss. Quotes in the rows of a closed market are the LAST quotes, not live ones.
// Trades nothing and reads nothing from the terminal. Writes MQL5/Files/PlSymbolTests.json.
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
#include "SymbolVectors.mqh"

//--- per set counters
string g_set="";
string g_acct_ccy="";
int    g_acct_digits=2;
int    g_acct_margin_mode=0;
string g_fail_json="";
int    g_fail_count=0;
int    g_checks=0;
int    g_total, g_disabled, g_tradable, g_grid_ok, g_unquoted, g_unquoted_ok, g_quoted;
int    g_path_checks, g_path_tight_ok, g_path_core_ok;
double g_max_abs=0.0, g_max_rel=0.0;
string g_max_abs_sym="", g_max_abs_side="", g_max_rel_sym="";
int    g_runc_ok, g_runc_expected_block;
int    g_final_done, g_final_ok;
int    g_rel_profit, g_rel_base, g_rel_cross, g_rel_na;
bool   g_final_tested=false;
string g_out="";
//--- broker rule path (rows with 48 fields)
int    g_rule_min;
int    g_rule_rows, g_rule_accepted, g_rule_rejected, g_rule_zero, g_rule_percent, g_rule_lot_side, g_rule_lot_round;
int    g_runb_ok, g_runb_block_expl, g_runp_ok, g_runp_closed, g_runp_stale, g_runp_fresh;
int    g_key_no_conv;
int    g_sellx_n, g_sellx_a_lt_c;
double g_sellx_max_rel=0.0;
string g_key_no_conv_json="";
string g_rejected_json="";
string g_blocks_json="";
int    g_blocks_n=0, g_blocks_shown=0;
int    g_blocks_by_reason[];
string g_blocks_reason_name[];
string g_blocks_by_reason_run[];
//--- lot grids (vol_min|vol_step) seen, with the smallest lot that passes PlTpPartsFit for 70/30 and for 50/30/20
string g_grid_key[];
double g_grid_l2[];
double g_grid_l3[];
int    g_grid_n[];

double SmallestTpLot(const double vmin,const double vstep,const double s1,const double s2,const double s3)
  {
   PlInputs tin;
   InputsBase(tin);
   PlPlan tp;
   ZeroMemory(tp);
   tin.no_tp=false;
   tin.tp[0].on=true; tin.tp[0].share=s1; tp.tp[0]=1.0;
   tin.tp[1].on=true; tin.tp[1].share=s2; tp.tp[1]=2.0;
   if(s3>0.0) { tin.tp[2].on=true; tin.tp[2].share=s3; tp.tp[2]=3.0; }
   for(int i=0; i<2000; i++)
     {
      const double lot=PlRoundDigits(vmin+(double)i*vstep,PlStepDigits(vstep));
      if(PlTpPartsFit(lot,vmin,vstep,tin,tp))
         return lot;
     }
   return 0.0;
  }

void NoteGrid(const double vmin,const double vstep)
  {
   const string key=DoubleToString(vmin,8)+"|"+DoubleToString(vstep,8);
   for(int i=0; i<ArraySize(g_grid_key); i++)
      if(g_grid_key[i]==key)
        {
         g_grid_n[i]++;
         return;
        }
   const int n=ArraySize(g_grid_key);
   ArrayResize(g_grid_key,n+1); ArrayResize(g_grid_l2,n+1); ArrayResize(g_grid_l3,n+1); ArrayResize(g_grid_n,n+1);
   g_grid_key[n]=key; g_grid_n[n]=1;
   g_grid_l2[n]=SmallestTpLot(vmin,vstep,70.0,30.0,0.0);
   g_grid_l3[n]=SmallestTpLot(vmin,vstep,50.0,30.0,20.0);
  }
int    g_all_fail=0, g_all_checks=0;

string JsonStr(const string t)
  {
   string o="";
   const int n=StringLen(t);
   for(int i=0; i<n; i++)
     {
      const ushort c=StringGetCharacter(t,i);
      if(c=='"' || c=='\\')
        {
         o+="\\";
         o+=ShortToString(c);
        }
      else if(c<32)
         o+=" ";
      else
         o+=ShortToString(c);
     }
   return o;
  }

void Fail(const string sym,const string side,const string check,const string expected,const string got)
  {
   g_fail_count++;
   if(g_fail_count<=300)
     {
      if(g_fail_json!="")
         g_fail_json+=",";
      g_fail_json+="{\"set\":\""+JsonStr(g_set)+"\",\"symbol\":\""+JsonStr(sym)+"\",\"side\":\""+side+"\",\"check\":\""+check
                   +"\",\"expected\":\""+JsonStr(expected)+"\",\"got\":\""+JsonStr(got)+"\"}";
     }
  }

void Check(const bool ok,const string sym,const string side,const string check,const string expected,const string got)
  {
   g_checks++;
   if(!ok)
      Fail(sym,side,check,expected,got);
  }

string Dbl(const double x) { return DoubleToString(x,8); }

//--- enum name to value, searched over 0..63 (no numeric enum values guessed)
int TradeModeOf(const string nm)
  {
   for(int i=0; i<64; i++)
      if(EnumToString((ENUM_SYMBOL_TRADE_MODE)i)==nm)
         return i;
   return -1;
  }

int SwapModeOf(const string nm)
  {
   for(int i=0; i<64; i++)
      if(EnumToString((ENUM_SYMBOL_SWAP_MODE)i)==nm)
         return i;
   return -1;
  }

int MarginModeOf(const string nm)
  {
   for(int i=0; i<64; i++)
      if(EnumToString((ENUM_ACCOUNT_MARGIN_MODE)i)==nm)
         return i;
   return -1;
  }

void InputsBase(PlInputs &in)
  {
   in.kind=PL_KIND_MARKET;
   in.entry=0.0;
   in.limit=0.0;
   in.sl=0.0;
   in.no_sl=false;
   for(int k=0; k<PL_MAX_TP; k++)
     {
      in.tp[k].on=false;
      in.tp[k].mode=PL_TP_R;
      in.tp[k].r=0.0;
      in.tp[k].price=0.0;
      in.tp[k].share=0.0;
     }
   in.no_tp=true;
   in.risk_mode=PL_RISK_PERCENT;
   in.risk_percent=1.0;
   in.risk_money=0.0;
   in.lot_fixed=0.0;
   in.base=PL_BASE_BALANCE;
   in.subtract_open=false;
   in.cap_percent=5.0;
   in.confirm_above=2.0;
   in.over_max=PL_OVER_BLOCK;
   in.max_spread_share=0.0;
   in.comm.kind=PL_COMM_LOT_SIDE;
   in.comm.rate=0.0;
   in.comm.source=PL_COMMSRC_USER;
   in.comm.min_money=0.0;
   in.n_orders=0;
   in.atr_on=false;
   in.atr=0.0;
   in.atr_mult=0.0;
   in.calcprofit_ok=false;
   in.calcprofit_loss_1lot=0.0;
   in.net_calc_ok=false;
   in.net_loss_new=0.0;
   in.net_loss_old=0.0;
  }

void MakeAccount(PlAccount &a)
  {
   ZeroMemory(a);
   a.currency=g_acct_ccy;
   a.currency_digits=g_acct_digits;
   a.balance=10000.0;
   a.equity=10000.0;
   a.margin=0.0;
   a.margin_free=10000.0;
   a.so_mode=ACCOUNT_STOPOUT_MODE_PERCENT;
   a.so_call=100.0;
   a.so_so=0.0;                       // not in the probes: test fixture
   a.leverage=100;
   a.trade_mode=ACCOUNT_TRADE_MODE_DEMO;
   a.margin_mode=g_acct_margin_mode;
   a.trade_ok=true;
   a.term_trade=true;
   a.mql_trade=true;
   a.acct_trade=true;
   a.acct_expert=true;
   a.connected=true;
   a.open_risk_money=0.0;
   a.pending_risk_money=0.0;
  }

//--- the names the probe wrote for SYMBOL_COMMISSION_* modes, mapped by named constants (never raw numbers); -1: a name this
//--- build does not know, which no rule shape accepts
int CommChargeOf(const string nm)
  {
   if(nm=="SYMBOL_COMMISSION_CHARGE_INSTANT") return (int)SYMBOL_COMMISSION_CHARGE_INSTANT;
   if(nm=="SYMBOL_COMMISSION_CHARGE_DAILY") return (int)SYMBOL_COMMISSION_CHARGE_DAILY;
   if(nm=="SYMBOL_COMMISSION_CHARGE_MONTHLY") return (int)SYMBOL_COMMISSION_CHARGE_MONTHLY;
   return -1;
  }
int CommDirectionOf(const string nm)
  {
   if(nm=="SYMBOL_COMMISSION_DIRECTION_BOTH") return (int)SYMBOL_COMMISSION_DIRECTION_BOTH;
   if(nm=="SYMBOL_COMMISSION_DIRECTION_BUY") return (int)SYMBOL_COMMISSION_DIRECTION_BUY;
   if(nm=="SYMBOL_COMMISSION_DIRECTION_SELL") return (int)SYMBOL_COMMISSION_DIRECTION_SELL;
   return -1;
  }
int CommEntryOf(const string nm)
  {
   if(nm=="SYMBOL_COMMISSION_ENTRY_INOUT") return (int)SYMBOL_COMMISSION_ENTRY_INOUT;
   if(nm=="SYMBOL_COMMISSION_ENTRY_IN") return (int)SYMBOL_COMMISSION_ENTRY_IN;
   if(nm=="SYMBOL_COMMISSION_ENTRY_OUT") return (int)SYMBOL_COMMISSION_ENTRY_OUT;
   return -1;
  }
int CommProfitOf(const string nm)
  {
   if(nm=="SYMBOL_COMMISSION_PROFIT_ALL") return (int)SYMBOL_COMMISSION_PROFIT_ALL;
   if(nm=="SYMBOL_COMMISSION_PROFIT_PROFIT") return (int)SYMBOL_COMMISSION_PROFIT_PROFIT;
   if(nm=="SYMBOL_COMMISSION_PROFIT_LOSS") return (int)SYMBOL_COMMISSION_PROFIT_LOSS;
   return -1;
  }
int CommRangeOf(const string nm)
  {
   if(nm=="SYMBOL_COMMISSION_RANGE_VOLUME") return (int)SYMBOL_COMMISSION_RANGE_VOLUME;
   return -1;
  }
int CommTierModeOf(const string nm)
  {
   if(nm=="SYMBOL_COMMISSION_PERCENT") return (int)SYMBOL_COMMISSION_PERCENT;
   if(nm=="SYMBOL_COMMISSION_MONEY_SPECIFIED") return (int)SYMBOL_COMMISSION_MONEY_SPECIFIED;
   if(nm=="SYMBOL_COMMISSION_MONEY_DEPOSIT") return (int)SYMBOL_COMMISSION_MONEY_DEPOSIT;
   return -1;
  }
int CommVolTypeOf(const string nm)
  {
   if(nm=="SYMBOL_COMMISSION_VOLUME_TYPE_VOLUME") return (int)SYMBOL_COMMISSION_VOLUME_TYPE_VOLUME;
   return -1;
  }

//--- the commission part of a 51-field row as the core's plain data, shaped exactly as Terminal/Market.mqh PlCommRule does it
//--- (one rule only when n==1; tier fields only when a tier exists). 30, 31..: the fields written by the generator of the file
void BuildRule(const string &f[],int &n,PlBrokerRule &r[])
  {
   ArrayResize(r,0);
   n=(int)StringToInteger(f[30]);
   if(n!=1)
      return;
   ArrayResize(r,1);
   r[0].currency=f[31];
   r[0].mode_charge=CommChargeOf(f[32]);
   r[0].mode_direction=CommDirectionOf(f[33]);
   r[0].mode_entry=CommEntryOf(f[34]);
   r[0].mode_profit=CommProfitOf(f[35]);
   r[0].mode_range=CommRangeOf(f[36]);
   r[0].tier_count=(int)StringToInteger(f[37]);
   r[0].range_from=0.0; r[0].range_to=0.0; r[0].min_value=0.0; r[0].max_value=0.0; r[0].value=0.0;
   r[0].tier_mode=-1; r[0].volume_type=-1; r[0].tier_currency="";
   if(r[0].tier_count>=1)
     {
      r[0].range_from=StringToDouble(f[38]); r[0].range_to=StringToDouble(f[39]);
      r[0].min_value=StringToDouble(f[40]); r[0].max_value=StringToDouble(f[41]);
      r[0].value=StringToDouble(f[42]);
      r[0].tier_mode=CommTierModeOf(f[43]);
      r[0].volume_type=CommVolTypeOf(f[44]);
      r[0].tier_currency=f[45];
     }
  }

//--- the plain shape the core accepts, judged on the probe's NAMES (strings), not on the constants: an independent check of
//--- PlBrokerCommRule and of the name mapping. expect_kind/expect_rate/expect_min: what the accepted rule must become.
//--- A tier in a currency other than the account's (15.10.2026) is read here on the probe's own columns: MONEY_SPECIFIED only, the
//--- currency must be the symbol's profit currency (column 12) or, on a Forex calc mode (0 or 5), its base currency (column 11,
//--- at the mid of the probe's quote), and k = tick_value_loss / (tick_size * contract) of the probe's columns 8, 7, 10 must exist
//--- on a calc mode that is a price difference (0 FOREX, 2 CFD, 3 CFDINDEX, 4 CFDLEVERAGE, 5 FOREX_NO_LEVERAGE, 32 EXCH_STOCKS and 38 EXCH_STOCKS_MOEX).
bool PlainRuleByNames(const string &f[],const string acct,const double vol,PlCommKind &kind,double &rate,double &min_round)
  {
   kind=PL_COMM_UNKNOWN; rate=0.0; min_round=0.0;
   if((int)StringToInteger(f[30])!=1 || (int)StringToInteger(f[37])!=1)
      return false;
   if(f[32]!="SYMBOL_COMMISSION_CHARGE_INSTANT" || f[33]!="SYMBOL_COMMISSION_DIRECTION_BOTH"
      || f[35]!="SYMBOL_COMMISSION_PROFIT_ALL" || f[36]!="SYMBOL_COMMISSION_RANGE_VOLUME"
      || f[44]!="SYMBOL_COMMISSION_VOLUME_TYPE_VOLUME")
      return false;
   if(f[31]!=acct)
      return false;
   if(StringToDouble(f[41])!=0.0)
      return false;
   if(vol<StringToDouble(f[38])-PL_EPS || vol>StringToDouble(f[39])+PL_EPS)
      return false;
   const double v=StringToDouble(f[42]);
   const double mn=StringToDouble(f[40]);
   if(v<0.0 || mn<0.0)
      return false;
   const bool money=(f[43]=="SYMBOL_COMMISSION_MONEY_SPECIFIED" || f[43]=="SYMBOL_COMMISSION_MONEY_DEPOSIT");
   const bool pct=(f[43]=="SYMBOL_COMMISSION_PERCENT");
   double factor=1.0;
   if(f[45]!="" && f[45]!=acct)
     {
      if(f[43]!="SYMBOL_COMMISSION_MONEY_SPECIFIED")
         return false;
      const int cm=(int)StringToInteger(f[3]);
      const bool delta=(cm==0 || cm==2 || cm==3 || cm==4 || cm==5 || cm==32 || cm==38);
      const double ts=StringToDouble(f[7]), tv=StringToDouble(f[8]), ct=StringToDouble(f[10]);
      if(!delta || !(ts>0.0) || !(tv>0.0) || !(ct>0.0))
         return false;
      const double kk=tv/(ts*ct);
      if(f[45]==f[12])
         factor=kk;
      else if(f[45]==f[11] && (cm==0 || cm==5) && StringToDouble(f[25])>0.0 && StringToDouble(f[26])>0.0)
         factor=(StringToDouble(f[25])+StringToDouble(f[26]))/2.0*kk;
      else
         return false;
     }
   if(pct && f[34]=="SYMBOL_COMMISSION_ENTRY_INOUT" && mn==0.0)
      kind=PL_COMM_PERCENT_SIDE;
   else if(money && f[34]=="SYMBOL_COMMISSION_ENTRY_INOUT" && mn==0.0)
      kind=PL_COMM_LOT_SIDE;
   else if(money && f[34]=="SYMBOL_COMMISSION_ENTRY_IN")
      kind=PL_COMM_LOT_ROUND;
   else
      return false;
   rate=v*factor;
   min_round=mn*factor;
   if(v==0.0 && mn==0.0)
      kind=PL_COMM_LOT_SIDE;
   return true;
  }

void CountBlock(const string run,const PlReason reason)
  {
   const string nm=EnumToString(reason);
   for(int i=0; i<ArraySize(g_blocks_reason_name); i++)
      if(g_blocks_reason_name[i]==nm && g_blocks_by_reason_run[i]==run)
        {
         g_blocks_by_reason[i]++;
         return;
        }
   const int n=ArraySize(g_blocks_reason_name);
   ArrayResize(g_blocks_reason_name,n+1); ArrayResize(g_blocks_by_reason,n+1); ArrayResize(g_blocks_by_reason_run,n+1);
   g_blocks_reason_name[n]=nm; g_blocks_by_reason_run[n]=run; g_blocks_by_reason[n]=1;
  }

//--- every BLOCK of a run: symbol, the reason code name, the three currencies, tick_value_loss, and why it is true for the symbol
void NoteBlock(const string run,const PlSymbol &s,const PlReason reason,const string why,const bool detail,const bool open,const string age)
  {
   g_blocks_n++;
   CountBlock(run,reason);
   if(!detail || g_blocks_shown>=600)
      return;
   g_blocks_shown++;
   if(g_blocks_json!="")
      g_blocks_json+=",\n";
   g_blocks_json+="{\"run\":\""+run+"\",\"symbol\":\""+JsonStr(s.name)+"\",\"reason\":\""+EnumToString(reason)
                  +"\",\"profit\":\""+JsonStr(s.profit)+"\",\"margin\":\""+JsonStr(s.margin)+"\",\"base\":\""+JsonStr(s.base)
                  +"\",\"tick_value_loss\":"+Dbl(s.tick_value_loss)+",\"session_open\":"+(open?"true":"false")
                  +",\"tick_age_s\":"+(age==""?"null":age)+",\"why\":\""+JsonStr(why)+"\"}";
  }

string RelName(const int r)
  {
   if(r==PL_CCY_PROFIT) return "profit";
   if(r==PL_CCY_BASE) return "base";
   if(r==PL_CCY_CROSS) return "cross";
   return "na";
  }

void RunSymbol(const string &f[],const int nf)
  {
   // f: 0 Y, 1 set, 2 name, 3 calc_mode_int, 4 trade_mode, 5 digits, 6 point, 7 tick_size, 8 tvl, 9 tvp, 10 contract,
   // 11 base, 12 profit, 13 margin, 14 vol_min, 15 vol_step, 16 vol_max, 17 vol_limit, 18 stops, 19 freeze,
   // 20 order_mode, 21 filling, 22 swap_mode, 23 swap_long, 24 swap_short, 25 bid, 26 ask, 27 margin1,
   // 28 profit_buy, 29 profit_sell; a 51-field row adds the broker rule and the probe-time state:
   // 30 comm_n, 31 rule currency, 32 charge, 33 direction, 34 entry, 35 profit, 36 range, 37 tier count, 38 range_from,
   // 39 range_to, 40 min_value, 41 max_value, 42 value, 43 tier mode, 44 volume type, 45 tier currency,
   // 46 session_open_now, 47 tick_age_s, 48 ref_ticks, 49 profit_1lot_buy_ref, 50 profit_1lot_sell_ref
   g_total++;
   PlSymbol s;
   ZeroMemory(s);
   s.name=f[2];
   s.calc_mode=(int)StringToInteger(f[3]);
   s.sym_trade_mode=TradeModeOf(f[4]);
   s.digits=(int)StringToInteger(f[5]);
   s.point=StringToDouble(f[6]);
   s.tick_size=StringToDouble(f[7]);
   s.tick_value_loss=StringToDouble(f[8]);
   s.tick_value_profit=StringToDouble(f[9]);
   s.contract=StringToDouble(f[10]);
   s.base=f[11];
   s.profit=f[12];
   s.margin=f[13];
   s.vol_min=StringToDouble(f[14]);
   s.vol_step=StringToDouble(f[15]);
   s.vol_max=StringToDouble(f[16]);
   s.vol_limit=StringToDouble(f[17]);
   s.vol_open_buy=0.0;
   s.vol_open_sell=0.0;
   s.stops_level=(int)StringToInteger(f[18]);
   s.freeze_level=(int)StringToInteger(f[19]);
   s.order_mode=(int)StringToInteger(f[20]);
   s.filling_mode=(int)StringToInteger(f[21]);
   s.exec_mode=SYMBOL_TRADE_EXECUTION_MARKET;
   s.expiration_mode=15;
   s.gtc_mode=SYMBOL_ORDERS_GTC;
   s.swap_mode=SwapModeOf(f[22]);
   s.swap_long=StringToDouble(f[23]);
   s.swap_short=StringToDouble(f[24]);
   s.swap_3day=3;
   s.bid=StringToDouble(f[25]);
   s.ask=StringToDouble(f[26]);
   s.tick_time=D'2026.10.13 12:00:00';
   s.server_now=D'2026.10.13 12:00:00';
   s.session_open=true;
   const bool has_pb=(f[28]!=""), has_ps=(f[29]!=""), has_m=(f[27]!="");
   const double m1=has_m?StringToDouble(f[27]):0.0;
   s.margin_buy_1lot=m1;
   s.margin_sell_1lot=m1;

   if(s.sym_trade_mode<0 || s.swap_mode<0)
      Fail(s.name,"","enum_names","known",f[4]+" "+f[22]);

   if(s.sym_trade_mode==SYMBOL_TRADE_MODE_DISABLED)
     {
      g_disabled++;
      return;
     }
   g_tradable++;
   const bool grid=PlVolumeGridOk(s);
   Check(grid,s.name,"","volume_grid","true",grid?"true":"false");
   if(grid)
     {
      g_grid_ok++;
      NoteGrid(s.vol_min,s.vol_step);
     }

   PlAccount a;
   MakeAccount(a);

   //--- the broker's commission rule through the pure PlBrokerCommRule, against an independent reading of the probe's names
   const bool has_rule=(nf==51);
   PlCommKind rk=PL_COMM_UNKNOWN;
   double rrate=0.0, rmin=0.0;
   bool rzero=false, racc=false;
   if(has_rule)
     {
      g_rule_rows++;
      int rn;
      PlBrokerRule rr[];
      BuildRule(f,rn,rr);
      double kr=0.0;
      const bool kr_ok=PlRateK(s,kr);
      racc=PlBrokerCommRule(rn,rr,g_acct_ccy,s.vol_min,s,kr_ok,kr,rk,rrate,rmin,rzero);
      PlCommKind ek;
      double er, emin;
      const bool eplain=PlainRuleByNames(f,g_acct_ccy,s.vol_min,ek,er,emin);
      Check(racc==eplain,s.name,"","broker_rule_accepted",eplain?"accepted":"rejected",racc?"accepted":"rejected");
      if(racc)
        {
         g_rule_accepted++;
         Check(rk==ek && MathAbs(rrate-er)<1e-12 && MathAbs(rmin-emin)<1e-12 && rzero==(er==0.0 && emin==0.0),s.name,"","broker_rule_kind",
               EnumToString(ek)+" "+Dbl(er)+" min "+Dbl(emin),EnumToString(rk)+" "+Dbl(rrate)+" min "+Dbl(rmin)+(rzero?" zero":""));
         if(rmin>0.0) g_rule_min++;
         if(rzero) g_rule_zero++;
         if(rk==PL_COMM_PERCENT_SIDE) g_rule_percent++;
         else if(rk==PL_COMM_LOT_ROUND) g_rule_lot_round++;
         else g_rule_lot_side++;
         //--- KEY CHECK: a PERCENT rule accepted while the conversion k is not there gives PL_R_NO_CONVERSION
         double kk=0.0;
         if(rk==PL_COMM_PERCENT_SIDE && !PlRateK(s,kk))
           {
            g_key_no_conv++;
            if(g_key_no_conv_json!="") g_key_no_conv_json+=",";
            g_key_no_conv_json+="{\"symbol\":\""+JsonStr(s.name)+"\",\"percent\":"+Dbl(rrate)+",\"calc_mode\":"+IntegerToString(s.calc_mode)
                                +",\"base\":\""+JsonStr(s.base)+"\",\"profit\":\""+JsonStr(s.profit)+"\",\"margin\":\""+JsonStr(s.margin)
                                +"\",\"tick_value_loss\":"+Dbl(s.tick_value_loss)+",\"tick_size\":"+Dbl(s.tick_size)+",\"contract\":"+Dbl(s.contract)+"}";
            Fail(s.name,"","KEYCHECK_percent_rule_without_k","PlRateK ok for an accepted PERCENT rule","tick_value_loss="+Dbl(s.tick_value_loss));
           }
        }
      else
        {
         g_rule_rejected++;
         if(g_rejected_json!="") g_rejected_json+=",";
         g_rejected_json+="\""+JsonStr(s.name)+"\"";
        }
     }

   const bool has_ref=(!has_rule || (f[48]!="" && f[49]!=""));
   const bool quoted=(s.bid>0.0 && s.ask>0.0 && has_pb && has_ps && has_m && has_ref);
   if(!quoted)
     {
      g_unquoted++;
      PlInputs in;
      InputsBase(in);
      in.sl=1.0;
      PlPlan p;
      PlResult r;
      const bool okp=PlPrepare(in,s,p);
      PlCompute(in,s,a,p,r);
      const bool ok=(!okp && !p.ok && r.verdict==PL_BLOCK && r.reason==PL_R_NO_QUOTE);
      Check(ok,s.name,"","unquoted_refused","BLOCK NO_QUOTE",EnumToString(r.verdict)+" "+IntegerToString(r.reason));
      if(ok)
        {
         g_unquoted_ok++;
         NoteBlock("unquoted",s,r.reason,"no bid or ask in the probe",has_rule,has_rule&&f[46]=="1",has_rule?f[47]:"");
        }
      return;
     }
   g_quoted++;
   const int rel=PlCcyRelation(s);
   if(rel==PL_CCY_PROFIT) g_rel_profit++;
   else if(rel==PL_CCY_BASE) g_rel_base++;
   else if(rel==PL_CCY_CROSS) g_rel_cross++;
   else g_rel_na++;

   const double half=0.5/PlPow10(g_acct_digits);
   //--- run A: path check, both sides, as the probe measured it (100 ticks against the quote)
   double c_buy=-StringToDouble(f[28]);
   double c_sell=-StringToDouble(f[29]);
   const double sl_buy=NormalizeDouble(s.ask-100.0*s.tick_size,s.digits);
   const double sl_sell=NormalizeDouble(s.bid+100.0*s.tick_size,s.digits);
   for(int side=0; side<2; side++)
     {
      const string sd=(side==0)?"buy":"sell";
      const double sl=(side==0)?sl_buy:sl_sell;
      const double c=(side==0)?c_buy:c_sell;
      const double av=PlLossA(s,sl,100);
      g_path_checks++;
      const double dif=MathAbs(av-c);
      const double rl=dif/MathMax(av,c);
      if(dif>g_max_abs)
        {
         g_max_abs=dif;
         g_max_abs_sym=s.name;
         g_max_abs_side=sd;
        }
      if(rl>g_max_rel)
        {
         g_max_rel=rl;
         g_max_rel_sym=s.name;
        }
      //--- found 14.10.2026 on the live FTMO demo crosses: path (a) and OrderCalcProfit of a SELL on a cross symbol differ by more than
      //--- the rounding of OrderCalcProfit. Hypothesis, measured on the FTMO demo crosses and checked here: OrderCalcProfit converts
      //--- the SELL loss on the PROFIT side of the conversion pair (tick value PROFIT), path (a) uses the LOSS side, so
      //--- c*(tvl/tvp) must agree with a to the rounding. A BUY stays tight with no correction. The core's own rule
      //--- (path_core_agree below) still decides, and a must not be below c (the lot takes max(a,c); a>=c is what keeps it safe).
      bool tight=(dif<=half+1e-6);
      if(!tight && side==1 && rel==PL_CCY_CROSS && s.tick_value_profit>0.0
         && MathAbs(av-c*s.tick_value_loss/s.tick_value_profit)<=half*s.tick_value_loss/s.tick_value_profit+1e-6)
        {
         tight=true;
         g_sellx_n++;
         g_sellx_max_rel=MathMax(g_sellx_max_rel,dif/MathMax(av,c));
        }
      if(side==1 && rel==PL_CCY_CROSS && av<c-half-1e-6)
        {
         g_sellx_a_lt_c++;
         Fail(s.name,sd,"sell_cross_a_below_c","a>=c","a="+Dbl(av)+" c="+Dbl(c));
        }
      Check(tight,s.name,sd,"path_tight","|a-c|<="+Dbl(half+1e-6),"a="+Dbl(av)+" c="+Dbl(c));
      if(tight)
         g_path_tight_ok++;
      const bool core=PlPathsAgree(av,c,g_acct_digits);
      Check(core,s.name,sd,"path_core_agree","true","a="+Dbl(av)+" c="+Dbl(c));
      if(core)
         g_path_core_ok++;
     }

   //--- run C: valid inputs, Buy, full PlPrepare + PlCompute
   const double spread=s.ask-s.bid;
   double dd=100.0;
   dd=MathMax(dd,MathCeil(4.0*spread/s.tick_size-1e-9));
   dd=MathMax(dd,MathCeil((double)s.stops_level*s.point/s.tick_size+spread/s.tick_size-1e-9)+10.0);
   const double slc=NormalizeDouble(s.ask-dd*s.tick_size,s.digits);
   if(slc<=0.0)
     {
      Fail(s.name,"buy","runC_sl_positive",">0",Dbl(slc));
      return;
     }
   double cc;
   if(has_rule)
     {
      //--- the loss measured by OrderCalcProfit AT this SL distance (the probe used the same formula for the distance):
      //--- no scaling of the coarse 100-tick value, whose 2-digit rounding grows with the factor
      Check(MathAbs(dd-StringToDouble(f[48]))<1e-9,s.name,"buy","ref_ticks_formula",Dbl(dd),f[48]);
      dd=StringToDouble(f[48]);
      cc=-StringToDouble(f[49]);
     }
   else if(rel==PL_CCY_BASE)
      cc=c_buy*sl_buy*dd/(100.0*slc);
   else
      cc=c_buy*dd/100.0;
   const double want_lot=s.vol_min+3.0*s.vol_step;
   PlInputs in2;
   InputsBase(in2);
   in2.sl=slc;
   in2.risk_mode=PL_RISK_MONEY;
   in2.risk_money=cc*(s.vol_min+3.4*s.vol_step);
   in2.cap_percent=100.0;
   in2.confirm_above=100.0;
   in2.calcprofit_ok=true;
   in2.calcprofit_loss_1lot=cc;
   PlPlan p2;
   PlResult r2;
   const bool okp2=PlPrepare(in2,s,p2);
   PlCompute(in2,s,a,p2,r2);
   const bool margin_pred=(want_lot*m1>a.margin_free+PL_EPS);
   const bool cap_pred=(in2.risk_money>a.balance);
   bool ok=okp2 && p2.ok;
   string why="";
   if(!ok)
      why="prepare reason "+IntegerToString(p2.reason);
   if(ok && r2.verdict==PL_BLOCK)
     {
      const bool expl=((margin_pred && r2.reason==PL_R_MARGIN) || (cap_pred && r2.reason==PL_R_RISK_ABOVE_CAP)
                       || (margin_pred && cap_pred));
      if(expl)
        {
         g_runc_expected_block++;
         NoteBlock("user_runC",s,r2.reason,margin_pred?"margin for the test lot above free margin":"test risk above the 100% cap",has_rule,true,"0");
        }
      else
        {
         ok=false;
         why="BLOCK reason "+IntegerToString(r2.reason)+" "+PlReasonText(r2.reason);
        }
     }
   if(ok && r2.verdict!=PL_BLOCK && margin_pred)
     {
      ok=false;
      why="margin predicate true but no BLOCK";
     }
   if(ok && (r2.reason==PL_R_NO_CALC || r2.reason==PL_R_PATHS_DISAGREE || r2.reason==PL_R_LOT_GRID || r2.reason==PL_R_CALC_MODE))
     {
      ok=false;
      why="forbidden reason "+IntegerToString(r2.reason);
     }
   if(ok && want_lot<=s.vol_max+PL_EPS)
     {
      if(MathAbs(r2.lot-want_lot)>1e-8)
        {
         ok=false;
         why="lot "+Dbl(r2.lot)+" want "+Dbl(want_lot);
        }
      else
        {
         const double q=(r2.lot-s.vol_min)/s.vol_step;
         if(MathAbs(q-MathRound(q))>1e-6)
           {
            ok=false;
            why="lot off the grid";
           }
        }
     }
   //--- netting group on a hedging account: nothing changes, the added risk is the whole risk, no netting field is used
   Check(r2.net_risk==0.0 && MathAbs(r2.risk_add-r2.risk_money)<1e-9,s.name,"buy","hedging_risk_add","risk_add==risk_money",Dbl(r2.risk_add)+" "+Dbl(r2.risk_money));
   Check(ok,s.name,"buy","runC","ok",why+" D="+Dbl(dd)+" c="+Dbl(cc)+" a="+Dbl(r2.lpl_a));
   if(ok)
      g_runc_ok++;


   //--- run B, the broker rule (rows with rule data): the commission from the rule, PlCompute against a lot worked out from the
   //--- vector alone; then the same inputs with the probe's own session state and tick age
   if(has_rule && racc)
     {
      const double per=(s.tick_size>0.0)?s.tick_value_loss/s.tick_size:0.0;       // account money per price unit per lot
      double ci=rrate, co=rrate;
      if(rk==PL_COMM_PERCENT_SIDE)
        {
         ci=s.ask*rrate/100.0*per;
         co=slc*rrate/100.0*per;
        }
      else if(rk==PL_COMM_LOT_ROUND)
        {
         ci=rrate/2.0;
         co=rrate/2.0;
        }
      PlInputs in3;
      InputsBase(in3);
      in3.sl=slc;
      in3.risk_mode=PL_RISK_MONEY;
      //--- the money of the test lot: its loss plus the commission, which is the broker minimum when that is more (a minimum is paid
      //--- once per order, here one order)
      const double lt=s.vol_min+3.4*s.vol_step;
      in3.risk_money=cc*lt+MathMax((ci+co)*lt,rmin);
      in3.cap_percent=100.0;
      in3.confirm_above=100.0;
      in3.calcprofit_ok=true;
      in3.calcprofit_loss_1lot=cc;
      in3.comm.kind=rk;
      in3.comm.rate=rrate;
      in3.comm.min_money=rmin;
      in3.comm.source=PL_COMMSRC_BROKER;
      PlPlan p3;
      PlResult r3;
      const bool okp3=PlPrepare(in3,s,p3);
      PlCompute(in3,s,a,p3,r3);
      const bool cap3=(in3.risk_money>a.balance);
      bool ok3=okp3 && p3.ok;
      string why3="";
      if(!ok3)
         why3="prepare reason "+IntegerToString(p3.reason);
      if(ok3 && r3.note==PL_R_COMM_UNKNOWN)
        {
         ok3=false;
         why3="commission not counted: the broker rule did not reach PlCompute";
        }
      if(ok3 && (MathAbs(r3.comm_in_1lot-ci)>1e-9*MathMax(1.0,MathAbs(ci)) || MathAbs(r3.comm_out_1lot-co)>1e-9*MathMax(1.0,MathAbs(co))))
        {
         ok3=false;
         why3="commission in "+Dbl(r3.comm_in_1lot)+" want "+Dbl(ci)+", out "+Dbl(r3.comm_out_1lot)+" want "+Dbl(co);
        }
      if(ok3 && r3.verdict==PL_BLOCK)
        {
         if((margin_pred && r3.reason==PL_R_MARGIN) || (cap3 && r3.reason==PL_R_RISK_ABOVE_CAP) || (margin_pred && cap3))
           {
            g_runb_block_expl++;
            NoteBlock("broker_fresh",s,r3.reason,margin_pred?"margin for the test lot above free margin":"test risk above the 100% cap",true,true,"0");
           }
         else
           {
            ok3=false;
            why3="BLOCK reason "+EnumToString(r3.reason)+" "+PlReasonText(r3.reason);
           }
        }
      if(ok3 && r3.verdict!=PL_BLOCK && margin_pred)
        {
         ok3=false;
         why3="margin predicate true but no BLOCK";
        }
      if(ok3 && (r3.reason==PL_R_NO_CALC || r3.reason==PL_R_PATHS_DISAGREE || r3.reason==PL_R_LOT_GRID || r3.reason==PL_R_CALC_MODE
                 || r3.reason==PL_R_NO_CONVERSION))
        {
         ok3=false;
         why3="forbidden reason "+EnumToString(r3.reason);
        }
      if(ok3 && want_lot<=s.vol_max+PL_EPS && MathAbs(r3.lot-want_lot)>1e-8)
        {
         ok3=false;
         why3="lot "+Dbl(r3.lot)+" want "+Dbl(want_lot);
        }
      Check(ok3,s.name,"buy","runB_broker_fresh","ok",why3+" kind="+EnumToString(rk)+" rate="+Dbl(rrate)+" ci="+Dbl(ci)+" co="+Dbl(co));
      if(ok3)
         g_runb_ok++;

      //--- the same inputs at the probe's own state: session from the table at probe time, tick age as the probe measured it
      if(ok3)
        {
         const datetime base=D'2026.10.14 02:00:00';
         const bool op=(f[46]=="1");
         const bool has_age=(f[47]!="");
         const long age=has_age?StringToInteger(f[47]):0;
         s.session_open=op;
         s.server_now=base;
         s.tick_time=has_age?(datetime)((long)base-age):(datetime)0;
         const bool stale=(!has_age || age>PlStaleSeconds(s));
         PlPlan p4;
         PlResult r4;
         const bool okp4=PlPrepare(in3,s,p4);
         PlCompute(in3,s,a,p4,r4);
         bool ok4=okp4 && p4.ok;
         string why4="";
         string exp4="";
         if(!ok4)
            why4="prepare reason "+IntegerToString(p4.reason);
         else if(!op)
           {
            exp4="BLOCK PL_R_MARKET_CLOSED";
            if(r4.verdict!=PL_BLOCK || r4.reason!=PL_R_MARKET_CLOSED)
              {
               ok4=false;
               why4="got "+EnumToString(r4.verdict)+" "+EnumToString(r4.reason);
              }
            else
              {
               g_runp_closed++;
               NoteBlock("probe_time",s,r4.reason,"session closed at probe time (session table); lot shown "+Dbl(r4.lot),true,false,f[47]);
              }
           }
         else if(stale)
           {
            exp4="BLOCK PL_R_STALE_QUOTE";
            if(r4.verdict!=PL_BLOCK || r4.reason!=PL_R_STALE_QUOTE)
              {
               ok4=false;
               why4="got "+EnumToString(r4.verdict)+" "+EnumToString(r4.reason);
              }
            else
              {
               g_runp_stale++;
               NoteBlock("probe_time",s,r4.reason,"session open but the last tick is older than "+IntegerToString(PlStaleSeconds(s))+" s; lot shown "+Dbl(r4.lot),true,true,f[47]);
              }
           }
         else
           {
            exp4=EnumToString(r3.verdict)+" "+EnumToString(r3.reason);
            if(r4.verdict!=r3.verdict || r4.reason!=r3.reason)
              {
               ok4=false;
               why4="got "+EnumToString(r4.verdict)+" "+EnumToString(r4.reason);
              }
            else
               g_runp_fresh++;
           }
         if(ok4 && MathAbs(r4.lot-r3.lot)>1e-9)
           {
            ok4=false;
            why4="lot "+Dbl(r4.lot)+" differs from the fresh run "+Dbl(r3.lot);
           }
         Check(ok4,s.name,"buy","runB_probe_time",exp4,why4+" open="+(op?"1":"0")+" age="+f[47]);
         if(ok4)
            g_runp_ok++;
         s.session_open=true;                         // back to the fixture
         s.server_now=D'2026.10.13 12:00:00';
         s.tick_time=D'2026.10.13 12:00:00';
        }
     }

   //--- final margin negatives, once per set, on the first quoted symbol (copies of its run C result)
   if(!g_final_tested && okp2 && p2.ok && r2.lot>PL_EPS)
     {
      g_final_tested=true;
      int good=0;
      PlResult x=r2;
      PlApplyFinalMargin(x,a,false,0.0);
      g_final_done++;
      if(x.verdict==PL_BLOCK && x.reason==PL_R_NO_SYMBOL_DATA) good++;
      else Fail(s.name,"","final_margin_unavailable","BLOCK NO_SYMBOL_DATA",IntegerToString(x.verdict)+" "+IntegerToString(x.reason));
      x=r2;
      PlApplyFinalMargin(x,a,true,2.0*a.margin_free);
      g_final_done++;
      if(x.verdict==PL_BLOCK && x.reason==PL_R_MARGIN && MathAbs(x.margin_needed-2.0*a.margin_free)<1e-6) good++;
      else Fail(s.name,"","final_margin_too_big","BLOCK MARGIN",IntegerToString(x.verdict)+" "+IntegerToString(x.reason));
      x=r2;
      PlApplyFinalMargin(x,a,true,r2.lot*m1);
      g_final_done++;
      if(x.verdict==r2.verdict && x.reason==r2.reason) good++;
      else Fail(s.name,"","final_margin_same","unchanged",IntegerToString(x.verdict)+" "+IntegerToString(x.reason));
      g_checks+=3;
      g_final_ok+=good;
     }
  }

void ResetSet()
  {
   g_fail_json=""; g_fail_count=0; g_checks=0;
   g_total=0; g_disabled=0; g_tradable=0; g_grid_ok=0; g_unquoted=0; g_unquoted_ok=0; g_quoted=0;
   g_path_checks=0; g_path_tight_ok=0; g_path_core_ok=0;
   g_max_abs=0.0; g_max_rel=0.0; g_max_abs_sym=""; g_max_abs_side=""; g_max_rel_sym="";
   g_runc_ok=0; g_runc_expected_block=0; g_final_done=0; g_final_ok=0;
   g_rel_profit=0; g_rel_base=0; g_rel_cross=0; g_rel_na=0;
   g_final_tested=false;
   g_rule_min=0; g_rule_rows=0; g_rule_accepted=0; g_rule_rejected=0; g_rule_zero=0; g_rule_percent=0; g_rule_lot_side=0; g_rule_lot_round=0;
   g_runb_ok=0; g_runb_block_expl=0; g_runp_ok=0; g_runp_closed=0; g_runp_stale=0; g_runp_fresh=0;
   g_sellx_n=0; g_sellx_a_lt_c=0; g_sellx_max_rel=0.0;
   g_key_no_conv=0; g_key_no_conv_json=""; g_rejected_json=""; g_blocks_json=""; g_blocks_n=0; g_blocks_shown=0;
   ArrayResize(g_blocks_by_reason,0); ArrayResize(g_blocks_reason_name,0); ArrayResize(g_blocks_by_reason_run,0);
  }

string BlocksSummary()
  {
   string r="[";
   for(int i=0; i<ArraySize(g_blocks_reason_name); i++)
      r+=(i>0?",":"")+"{\"run\":\""+g_blocks_by_reason_run[i]+"\",\"reason\":\""+g_blocks_reason_name[i]+"\",\"count\":"+IntegerToString(g_blocks_by_reason[i])+"}";
   return r+"]";
  }

void FlushSet()
  {
   if(g_set=="")
      return;
   if(g_out!="")
      g_out+=",\n";
   g_out+="{\"set\":\""+JsonStr(g_set)+"\",\"account_currency\":\""+JsonStr(g_acct_ccy)+"\",\"total\":"+IntegerToString(g_total)
          +",\"disabled\":"+IntegerToString(g_disabled)+",\"tradable\":"+IntegerToString(g_tradable)
          +",\"grid_ok\":"+IntegerToString(g_grid_ok)+",\"unquoted\":"+IntegerToString(g_unquoted)
          +",\"unquoted_refused_ok\":"+IntegerToString(g_unquoted_ok)+",\"quoted\":"+IntegerToString(g_quoted)
          +",\"path_checks\":"+IntegerToString(g_path_checks)+",\"path_tight_ok\":"+IntegerToString(g_path_tight_ok)
          +",\"path_core_ok\":"+IntegerToString(g_path_core_ok)
          +",\"sell_cross_wider_than_half_unit\":"+IntegerToString(g_sellx_n)+",\"sell_cross_max_rel\":"+Dbl(g_sellx_max_rel)
          +",\"sell_cross_a_below_c\":"+IntegerToString(g_sellx_a_lt_c)
          +",\"max_abs_diff\":"+Dbl(g_max_abs)+",\"max_abs_symbol\":\""+JsonStr(g_max_abs_sym)+"\",\"max_abs_side\":\""+g_max_abs_side+"\""
          +",\"max_rel_diff\":"+Dbl(g_max_rel)+",\"max_rel_symbol\":\""+JsonStr(g_max_rel_sym)+"\""
          +",\"runC_ok\":"+IntegerToString(g_runc_ok)+",\"runC_margin_or_cap\":"+IntegerToString(g_runc_expected_block)
          +",\"final_margin_ok\":"+IntegerToString(g_final_ok)+",\"final_margin_checks\":"+IntegerToString(g_final_done)
          +",\"relations\":{\"profit\":"+IntegerToString(g_rel_profit)+",\"base\":"+IntegerToString(g_rel_base)
          +",\"cross\":"+IntegerToString(g_rel_cross)+",\"na\":"+IntegerToString(g_rel_na)+"}"
          +",\"broker_rule\":{\"rows\":"+IntegerToString(g_rule_rows)+",\"accepted\":"+IntegerToString(g_rule_accepted)
          +",\"rejected\":"+IntegerToString(g_rule_rejected)+",\"rejected_symbols\":["+g_rejected_json+"]"
          +",\"percent_side\":"+IntegerToString(g_rule_percent)+",\"lot_side\":"+IntegerToString(g_rule_lot_side)
          +",\"lot_round\":"+IntegerToString(g_rule_lot_round)+",\"with_minimum\":"+IntegerToString(g_rule_min)+",\"known_zero\":"+IntegerToString(g_rule_zero)
          +",\"fresh_run_ok\":"+IntegerToString(g_runb_ok)+",\"fresh_run_margin_or_cap_block\":"+IntegerToString(g_runb_block_expl)
          +",\"probe_time_ok\":"+IntegerToString(g_runp_ok)+",\"probe_time_market_closed\":"+IntegerToString(g_runp_closed)
          +",\"probe_time_stale_quote\":"+IntegerToString(g_runp_stale)+",\"probe_time_same_as_fresh\":"+IntegerToString(g_runp_fresh)
          +",\"key_check_percent_no_conversion\":{\"count\":"+IntegerToString(g_key_no_conv)+",\"symbols\":["+g_key_no_conv_json+"]}}"
          +",\"blocks_total\":"+IntegerToString(g_blocks_n)+",\"blocks_by_run_and_reason\":"+BlocksSummary()
          +",\"blocks\":[\n"+g_blocks_json+"\n]"
          +",\"checks\":"+IntegerToString(g_checks)+",\"failure_count\":"+IntegerToString(g_fail_count)
          +",\"failures\":["+g_fail_json+"]}";
   g_all_fail+=g_fail_count;
   g_all_checks+=g_checks;
  }

void OnStart()
  {
   g_out="";
   const int n=ArraySize(g_pl_sym_rows);
   for(int i=0; i<n; i++)
     {
      string f[];
      const int k=StringSplit(g_pl_sym_rows[i],'|',f);
      if(k>=2 && f[0]=="S")
        {
         FlushSet();
         ResetSet();
         g_set=f[1];
         g_acct_ccy=f[2];
         g_acct_digits=(int)StringToInteger(f[3]);
         g_acct_margin_mode=MarginModeOf(f[4]);
         if(g_acct_margin_mode<0)
            Fail("","","margin_mode_name","known",f[4]);
         Check(g_acct_margin_mode==ACCOUNT_MARGIN_MODE_RETAIL_HEDGING,"","","margin_mode_hedging","RETAIL_HEDGING",f[4]);
        }
      else if((k==30 || k==51) && f[0]=="Y")
         RunSymbol(f,k);
      else
         Fail("","","row_format","30 or 51 fields",IntegerToString(k)+" fields in row "+IntegerToString(i));
     }
   FlushSet();
   string gj="";
   for(int q=0; q<ArraySize(g_grid_key); q++)
     {
      if(gj!="") gj+=",";
      gj+="{\"grid\":\""+g_grid_key[q]+"\",\"symbols\":"+IntegerToString(g_grid_n[q])+",\"smallest_lot_70_30\":"+Dbl(g_grid_l2[q])+",\"smallest_lot_50_30_20\":"+Dbl(g_grid_l3[q])+"}";
     }
   const string json="{\"failures\":"+IntegerToString(g_all_fail)+",\"checks\":"+IntegerToString(g_all_checks)+",\"tp_grids\":["+gj+"],\"sets\":[\n"+g_out+"\n]}\n";
   const int h=FileOpen("PlSymbolTests.json",FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(h==INVALID_HANDLE)
     {
      Print("PlSymbolTests: cannot write the result file");
      return;
     }
   FileWriteString(h,json);
   FileClose(h);
   PrintFormat("PlSymbolTests: %d failures, %d checks",g_all_fail,g_all_checks);
  }
