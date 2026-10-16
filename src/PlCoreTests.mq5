// Required Notice: Copyright 2026 stop-loss-enjoyer
// Plainlines is source-available under the PolyForm Shield License 1.0.0.
//
// Test script of the calculation core: runs every vector of CoreVectors.mqh through PlPrepare and
// PlCompute, compares the checked fields and writes MQL5/Files/PlCoreTests.json. The script
// trades nothing and reads nothing from the terminal except the clock.
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
#include "CoreVectors.mqh"

string g_checks;       // JSON of the checks of the current vector
bool   g_vec_ok;       // every check of the current vector passed
int    g_check_count;

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

string JsonNum(const double x)
  {
   return DoubleToString(x,8);
  }

void AddCheck(const string field,const string exp_txt,const string got_txt,const bool ok)
  {
   if(g_check_count>0)
      g_checks+=",";
   g_checks+="{\"field\":\""+field+"\",\"expected\":"+exp_txt+",\"got\":"+got_txt+",\"ok\":"+(ok?"true":"false")+"}";
   g_check_count++;
   if(!ok)
      g_vec_ok=false;
  }

//--- double: skipped when EMPTY_VALUE
void ChkD(const string field,const double exp,const double got,const double tol)
  {
   if(exp==EMPTY_VALUE)
      return;
   AddCheck(field,JsonNum(exp),JsonNum(got),MathAbs(got-exp)<=tol);
  }

//--- integer or enum: skipped when -1
void ChkI(const string field,const long exp,const long got)
  {
   if(exp==-1)
      return;
   AddCheck(field,IntegerToString(exp),IntegerToString(got),exp==got);
  }

void ChkB(const string field,const bool exp,const bool got)
  {
   AddCheck(field,exp?"true":"false",got?"true":"false",exp==got);
  }

//--- the session rows (PlSessionRowsOpen): each case is one more entry of the result file
int    g_sess_n=0;
int    g_sess_pass=0;
string g_sess_body="";

void SessCase(const string name,const long &fr[],const long &to[],const int n,const int sod,const bool exp_open)
  {
   const bool got=PlSessionRowsOpen(fr,to,n,sod);
   const bool ok=(got==exp_open);
   g_sess_n++;
   if(ok) g_sess_pass++;
   else PrintFormat("FAIL session %s sod=%d",name,sod);
   g_sess_body+=",\n{\"n\":"+IntegerToString(1000+g_sess_n)+",\"name\":\"session_"+JsonStr(name)+"_"+IntegerToString(sod)
                +"\",\"pass\":"+(ok?"true":"false")+",\"checks\":[{\"field\":\"open\",\"expected\":"+(exp_open?"true":"false")
                +",\"got\":"+(got?"true":"false")+",\"ok\":"+(ok?"true":"false")+"}]}";
  }

//--- the growth rule of a netting record (PlPosGrew): the volume against what the done TP parts leave
void GrowCase(const string name,const double vol,const double vol0,const double s1,const double s2,const bool d1,const bool d2,
              const double vmin,const double step,const bool exp_grew)
  {
   double sh[2]; bool dn[2];
   sh[0]=s1; sh[1]=s2; dn[0]=d1; dn[1]=d2;
   const bool got=PlPosGrew(vol,vol0,sh,dn,2,vmin,step);
   const bool ok=(got==exp_grew);
   g_sess_n++;
   if(ok) g_sess_pass++;
   else PrintFormat("FAIL grow %s vol=%.3f",name,vol);
   g_sess_body+=",\n{\"n\":"+IntegerToString(1000+g_sess_n)+",\"name\":\"grow_"+JsonStr(name)+"_"+DoubleToString(vol,3)
                +"\",\"pass\":"+(ok?"true":"false")+",\"checks\":[{\"field\":\"grew\",\"expected\":"+(exp_grew?"true":"false")
                +",\"got\":"+(got?"true":"false")+",\"ok\":"+(ok?"true":"false")+"}]}";
  }

void GrowBlock()
  {
   GrowCase("none_done",0.10,0.10,50,50,false,false,0.01,0.01,false);
   GrowCase("none_done",0.11,0.10,50,50,false,false,0.01,0.01,true);
   //--- after TP1 closed 0.05 an add of 0.01 stays under vol0: the old rule missed it
   GrowCase("tp1_done",0.05,0.10,50,50,true,false,0.01,0.01,false);
   GrowCase("tp1_done",0.06,0.10,50,50,true,false,0.01,0.01,true);
   GrowCase("tp1_done",0.04,0.10,50,50,true,false,0.01,0.01,false);        // a manual partial close is not growth
   //--- rounding left by the floor on the step (39 percent of 0.10 leaves 0.07, not 0.061)
   GrowCase("round_39",0.07,0.10,39,61,true,false,0.01,0.01,false);
   GrowCase("round_39",0.08,0.10,39,61,true,false,0.01,0.01,true);
   GrowCase("round_half",0.02,0.03,50,50,true,false,0.01,0.01,false);
   GrowCase("round_half",0.03,0.03,50,50,true,false,0.01,0.01,true);
   //--- both parts done
   GrowCase("both_done",0.02,0.10,50,30,true,true,0.01,0.01,false);
   GrowCase("both_done",0.03,0.10,50,30,true,true,0.01,0.01,true);
   //--- minimum above the step: an add is at least the minimum lot
   GrowCase("vmin_01",0.10,0.10,50,50,false,false,0.10,0.01,false);
   GrowCase("vmin_01",0.20,0.10,50,50,false,false,0.10,0.01,true);
  }

//--- the starting volume of a record: the found position wins, a zero never goes into a record with TP parts
void StartVolCase(const string name,const bool found,const double pv,const double pl,const double exp_v)
  {
   const double got=PlRecStartVol(found,pv,pl);
   const bool ok=(MathAbs(got-exp_v)<1e-9);
   g_sess_n++;
   if(ok) g_sess_pass++;
   else PrintFormat("FAIL startvol %s got=%.3f",name,got);
   g_sess_body+=",\n{\"n\":"+IntegerToString(1000+g_sess_n)+",\"name\":\"startvol_"+JsonStr(name)
                +"\",\"pass\":"+(ok?"true":"false")+",\"checks\":[{\"field\":\"vol0\",\"expected\":"+DoubleToString(exp_v,3)
                +",\"got\":"+DoubleToString(got,3)+",\"ok\":"+(ok?"true":"false")+"}]}";
  }

void StartVolBlock()
  {
   StartVolCase("found_wins",true,0.04,0.10,0.04);              // a partial fill: the position, not the plan
   StartVolCase("found_part_zero",true,0.10,0.0,0.10);          // part_lot 0 (an unknown fill) but the position is there
   StartVolCase("not_found_plan",false,0.0,0.10,0.10);
   StartVolCase("not_found_zero",false,0.0,0.0,0.0);            // nothing known: 0, the caller drops the parts
   StartVolCase("found_zero_vol",true,0.0,0.10,0.10);
  }

void SessBlock()
  {
   //--- GER40 Bybit Monday [00:00-00:00, 00:00-00:00, 03:15-00:00]
   long a_f[]={0,0,11700}, a_t[]={0,0,0};
   SessCase("ger40",a_f,a_t,3,3600,false);
   SessCase("ger40",a_f,a_t,3,11760,true);
   SessCase("ger40",a_f,a_t,3,86399,true);
   //--- CORN.c FTMO [00:00-00:00, 03:05-15:45, 16:35-21:20]
   long b_f[]={0,11100,59700}, b_t[]={0,56700,76800};
   SessCase("corn",b_f,b_t,3,82800,false);
   SessCase("corn",b_f,b_t,3,40000,true);
   SessCase("corn",b_f,b_t,3,57600,false);
   //--- SPI200 [00:00-00:00, 01:00-08:30, 09:10-00:00]
   long c_f[]={0,3600,33000}, c_t[]={0,30600,0};
   SessCase("spi200",c_f,c_t,3,82800,true);
   SessCase("spi200",c_f,c_t,3,31000,false);
   //--- EURUSD+ [00:01-23:58]
   long d_f[]={60}, d_t[]={86280};
   SessCase("eurusd",d_f,d_t,1,30,false);
   SessCase("eurusd",d_f,d_t,1,600,true);
   //--- the other spellings of an empty slot
   long e_f[]={86400}, e_t[]={86400};
   SessCase("empty_86400",e_f,e_t,1,0,false);
   SessCase("empty_86400",e_f,e_t,1,43200,false);
   SessCase("empty_86400",e_f,e_t,1,86399,false);
   //--- one row 00:00 to 24:00 alone in the day is the whole day (MetaQuotes-Demo EURUSD, 15.10.2026)
   long g_f[]={0}, g_t[]={86400};
   SessCase("whole_day_0_86400",g_f,g_t,1,0,true);
   SessCase("whole_day_0_86400",g_f,g_t,1,43200,true);
   SessCase("whole_day_0_86400",g_f,g_t,1,86399,true);
   //--- the same row next to other rows stays an empty slot (Bybit GER40 shape, raw values unknown)
   long j_f[]={0,11700}, j_t[]={86400,0};
   SessCase("slot_0_86400_with_rows",j_f,j_t,2,3600,false);
   SessCase("slot_0_86400_with_rows",j_f,j_t,2,11760,true);
   //--- a single 00:00-00:00 row (raw 0, 0) stays empty
   long k_f[]={0}, k_t[]={0};
   SessCase("single_0_0",k_f,k_t,1,43200,false);
   //--- synthetic: past midnight with to>0 is counted as closed
   long h_f[]={79200}, h_t[]={3600};
   SessCase("past_midnight",h_f,h_t,1,82800,false);
   SessCase("past_midnight",h_f,h_t,1,1800,false);
   //--- no rows
   long z_f[]={0}, z_t[]={0};
   SessCase("none",z_f,z_t,0,43200,false);
  }

//--- the broker's commission rule (PlBrokerCommRule): each case is one more entry of the result file
void BrokerBase(PlBrokerRule &r,const int mode,const int entry,const double value)
  {
   r.currency="USD"; r.mode_charge=SYMBOL_COMMISSION_CHARGE_INSTANT; r.mode_direction=SYMBOL_COMMISSION_DIRECTION_BOTH;
   r.mode_entry=entry; r.mode_profit=SYMBOL_COMMISSION_PROFIT_ALL; r.mode_range=SYMBOL_COMMISSION_RANGE_VOLUME;
   r.tier_count=1; r.range_from=0.0; r.range_to=1000.0; r.min_value=0.0; r.max_value=0.0; r.value=value;
   r.tier_mode=mode; r.volume_type=SYMBOL_COMMISSION_VOLUME_TYPE_VOLUME; r.tier_currency="";
  }

//--- a symbol for the currency conversion of a tier: base, profit, the calc mode, k (profit currency rate, 0: none) and the quote
void BrokerSym(PlSymbol &s,const string base,const string profit,const int calc_mode,const double k,const double bid,const double ask)
  {
   ZeroMemory(s);
   s.base=base; s.profit=profit; s.margin=base; s.calc_mode=calc_mode;
   s.tick_size=0.00001; s.contract=100000.0; s.tick_value_loss=k*s.tick_size*s.contract; s.tick_value_profit=s.tick_value_loss;
   s.bid=bid; s.ask=ask;
  }

void BrokerCaseSym(const string name,const int n,PlBrokerRule &rule,const string acc_ccy,const double vol,PlSymbol &s,
                   const bool exp_ok,const PlCommKind exp_kind,const double exp_rate,const double exp_min,const bool exp_zero)
  {
   PlBrokerRule r[];
   ArrayResize(r,1);
   r[0]=rule;
   PlCommKind k; double rt, mn; bool z;
   double kk=0.0;
   const bool k_ok=PlRateK(s,kk);
   const bool ok=PlBrokerCommRule(n,r,acc_ccy,vol,s,k_ok,kk,k,rt,mn,z);
   bool pass=(ok==exp_ok);
   if(exp_ok && ok) pass=pass && k==exp_kind && MathAbs(rt-exp_rate)<1e-12 && MathAbs(mn-exp_min)<1e-12 && z==exp_zero;
   if(!ok) pass=pass && k==PL_COMM_UNKNOWN && rt==0.0 && mn==0.0 && !z;
   g_sess_n++;
   if(pass) g_sess_pass++;
   else PrintFormat("FAIL broker %s ok=%d kind=%d rate=%.8f min=%.8f zero=%d",name,ok,(int)k,rt,mn,z);
   g_sess_body+=",\n{\"n\":"+IntegerToString(1000+g_sess_n)+",\"name\":\"broker_"+JsonStr(name)
                +"\",\"pass\":"+(pass?"true":"false")+",\"checks\":[{\"field\":\"accepted_kind_rate\",\"expected\":"
                +IntegerToString(exp_ok?(int)exp_kind:-1)+",\"got\":"+IntegerToString(ok?(int)k:-1)+",\"ok\":"+(pass?"true":"false")+"}]}";
  }

//--- the cases that do not touch the tier currency: a symbol that shares no currency with anything
void BrokerCase(const string name,const int n,PlBrokerRule &rule,const string acc_ccy,const double vol,
                const bool exp_ok,const PlCommKind exp_kind,const double exp_rate,const bool exp_zero)
  {
   PlSymbol s;
   BrokerSym(s,"BBB","PPP",SYMBOL_CALC_MODE_FOREX,1.0,1.1,1.2);
   BrokerCaseSym(name,n,rule,acc_ccy,vol,s,exp_ok,exp_kind,exp_rate,0.0,exp_zero);
  }

void BrokerBlock()
  {
   PlBrokerRule r;
   const int P=SYMBOL_COMMISSION_PERCENT, MS=SYMBOL_COMMISSION_MONEY_SPECIFIED, MD=SYMBOL_COMMISSION_MONEY_DEPOSIT;
   const int IO=SYMBOL_COMMISSION_ENTRY_INOUT, IN=SYMBOL_COMMISSION_ENTRY_IN;
   BrokerBase(r,P,IO,0.0007);   BrokerCase("percent_inout",1,r,"USD",0.01,true,PL_COMM_PERCENT_SIDE,0.0007,false);
   BrokerBase(r,MS,IO,2.5);     BrokerCase("money_specified_inout",1,r,"USD",0.01,true,PL_COMM_LOT_SIDE,2.5,false);
   BrokerBase(r,MD,IN,6.0);     BrokerCase("money_deposit_in_round",1,r,"USD",0.01,true,PL_COMM_LOT_ROUND,6.0,false);
   BrokerBase(r,MS,IN,3.0);     BrokerCase("money_specified_in_round",1,r,"USD",0.01,true,PL_COMM_LOT_ROUND,3.0,false);
   BrokerBase(r,P,IO,0.0);      BrokerCase("zero_known",1,r,"USD",0.01,true,PL_COMM_LOT_SIDE,0.0,true);
   BrokerBase(r,P,IO,0.0007);   BrokerCase("two_rules",2,r,"USD",0.01,false,PL_COMM_UNKNOWN,0.0,false);
   BrokerBase(r,P,IO,0.0007);   BrokerCase("count_minus1",-1,r,"USD",0.01,false,PL_COMM_UNKNOWN,0.0,false);
   BrokerBase(r,P,IO,0.0007);   BrokerCase("count_zero",0,r,"USD",0.01,false,PL_COMM_UNKNOWN,0.0,false);
   BrokerBase(r,P,IO,0.0007);   r.tier_count=2;
                                BrokerCase("two_tiers",1,r,"USD",0.01,false,PL_COMM_UNKNOWN,0.0,false);
   BrokerBase(r,MS,SYMBOL_COMMISSION_ENTRY_OUT,2.5);
                                BrokerCase("entry_out",1,r,"USD",0.01,false,PL_COMM_UNKNOWN,0.0,false);
   BrokerBase(r,MS,IO,2.5);     r.mode_charge=SYMBOL_COMMISSION_CHARGE_DAILY;
                                BrokerCase("charge_daily",1,r,"USD",0.01,false,PL_COMM_UNKNOWN,0.0,false);
   BrokerBase(r,MS,IO,2.5);     r.mode_charge=SYMBOL_COMMISSION_CHARGE_MONTHLY;
                                BrokerCase("charge_monthly",1,r,"USD",0.01,false,PL_COMM_UNKNOWN,0.0,false);
   BrokerBase(r,P,IO,0.0007);   BrokerCase("currency_usd_vs_ust",1,r,"UST",0.01,false,PL_COMM_UNKNOWN,0.0,false);
   BrokerBase(r,P,IO,0.0007);   r.tier_currency="EUR";
                                BrokerCase("tier_currency_mismatch",1,r,"USD",0.01,false,PL_COMM_UNKNOWN,0.0,false);
   BrokerBase(r,P,IO,0.0007);   r.tier_currency="USD";
                                BrokerCase("tier_currency_same",1,r,"USD",0.01,true,PL_COMM_PERCENT_SIDE,0.0007,false);
   BrokerBase(r,MS,IO,2.5);     BrokerCase("volume_above_range",1,r,"USD",1000.5,false,PL_COMM_UNKNOWN,0.0,false);
   BrokerBase(r,MS,IO,2.5);     r.range_from=0.1;
                                BrokerCase("volume_below_range",1,r,"USD",0.01,false,PL_COMM_UNKNOWN,0.0,false);
   BrokerBase(r,MS,IO,2.5);     r.min_value=1.0;
                                BrokerCase("min_value_inout",1,r,"USD",0.01,false,PL_COMM_UNKNOWN,0.0,false);
   BrokerBase(r,P,IO,0.0007);   r.min_value=1.0;
                                BrokerCase("min_value_percent",1,r,"USD",0.01,false,PL_COMM_UNKNOWN,0.0,false);
   BrokerBase(r,MS,IO,2.5);     r.max_value=10.0;
                                BrokerCase("max_value",1,r,"USD",0.01,false,PL_COMM_UNKNOWN,0.0,false);
   BrokerBase(r,MS,IN,0.02);    r.max_value=10.0; r.min_value=0.2;
                                BrokerCase("max_value_with_min_in",1,r,"USD",0.01,false,PL_COMM_UNKNOWN,0.0,false);
   BrokerBase(r,P,IN,0.0007);   BrokerCase("percent_in",1,r,"USD",0.01,false,PL_COMM_UNKNOWN,0.0,false);
   BrokerBase(r,MS,IO,-1.0);    BrokerCase("negative_value",1,r,"USD",0.01,false,PL_COMM_UNKNOWN,0.0,false);
   BrokerBase(r,MS,IN,0.02);    r.min_value=-0.2;
                                BrokerCase("negative_min",1,r,"USD",0.01,false,PL_COMM_UNKNOWN,0.0,false);
   BrokerBase(r,MS,IO,2.5);     r.mode_direction=SYMBOL_COMMISSION_DIRECTION_BUY;
                                BrokerCase("direction_buy",1,r,"USD",0.01,false,PL_COMM_UNKNOWN,0.0,false);
   BrokerBase(r,MS,IO,2.5);     r.currency="";
                                BrokerCase("empty_currency",1,r,"",0.01,false,PL_COMM_UNKNOWN,0.0,false);
   //--- 15.10.2026: the minimum (MONEY + ENTRY_IN) and the tier in a currency of the symbol (Bybit shares: rule UST, tier USD, 0.02 and min 0.2)
   PlSymbol s;
   BrokerBase(r,MS,IN,0.02);    r.min_value=0.2;
   BrokerSym(s,"BBB","PPP",SYMBOL_CALC_MODE_FOREX,1.0,1.1,1.2);
                                BrokerCaseSym("min_in_same_currency",1,r,"USD",0.1,s,true,PL_COMM_LOT_ROUND,0.02,0.2,false);
   BrokerBase(r,MS,IN,0.02);    r.min_value=0.2; r.currency="UST"; r.tier_currency="USD";
   BrokerSym(s,"USD","USD",SYMBOL_CALC_MODE_CFD,1.0,100.0,100.05);
                                BrokerCaseSym("bybit_share_k1",1,r,"UST",0.1,s,true,PL_COMM_LOT_ROUND,0.02,0.2,false);
   BrokerSym(s,"USD","USD",SYMBOL_CALC_MODE_CFD,0.5,100.0,100.05);
                                BrokerCaseSym("bybit_share_k_half",1,r,"UST",0.1,s,true,PL_COMM_LOT_ROUND,0.01,0.1,false);
   BrokerSym(s,"USD","USD",SYMBOL_CALC_MODE_CFD,1.25,100.0,100.05);
                                BrokerCaseSym("bybit_share_k_125",1,r,"UST",0.1,s,true,PL_COMM_LOT_ROUND,0.025,0.25,false);
   BrokerSym(s,"GBP","EUR",SYMBOL_CALC_MODE_CFD,1.1,100.0,100.05);
                                BrokerCaseSym("tier_usd_no_path",1,r,"UST",0.1,s,false,PL_COMM_UNKNOWN,0.0,0.0,false);
   BrokerSym(s,"USD","USD",SYMBOL_CALC_MODE_CFD,0.0,100.0,100.05);
                                BrokerCaseSym("tier_usd_no_k",1,r,"UST",0.1,s,false,PL_COMM_UNKNOWN,0.0,0.0,false);
   BrokerSym(s,"USD","USD",SYMBOL_CALC_MODE_FUTURES,1.0,100.0,100.05);
                                BrokerCaseSym("tier_usd_no_delta_mode",1,r,"UST",0.1,s,false,PL_COMM_UNKNOWN,0.0,0.0,false);
   //--- the tier in the base currency: only on Forex modes, at the mid price times k
   BrokerBase(r,MS,IN,1.0);     r.min_value=2.0; r.currency="USD"; r.tier_currency="EUR";
   BrokerSym(s,"EUR","GBP",SYMBOL_CALC_MODE_FOREX,1.3,1.10,1.12);
                                BrokerCaseSym("tier_base_forex",1,r,"USD",0.1,s,true,PL_COMM_LOT_ROUND,1.11*1.3,2.22*1.3,false);
   BrokerSym(s,"EUR","GBP",SYMBOL_CALC_MODE_CFD,1.3,1.10,1.12);
                                BrokerCaseSym("tier_base_not_forex",1,r,"USD",0.1,s,false,PL_COMM_UNKNOWN,0.0,0.0,false);
   //--- a foreign tier currency on PERCENT and MONEY_DEPOSIT has nothing to convert: refused, and USD is never UST by string
   BrokerBase(r,P,IO,0.0007);   r.currency="UST"; r.tier_currency="USD";
   BrokerSym(s,"USD","USD",SYMBOL_CALC_MODE_CFD,1.0,100.0,100.05);
                                BrokerCaseSym("tier_usd_percent",1,r,"UST",0.1,s,false,PL_COMM_UNKNOWN,0.0,0.0,false);
   BrokerBase(r,MD,IN,6.0);     r.currency="UST"; r.tier_currency="USD";
                                BrokerCaseSym("tier_usd_money_deposit",1,r,"UST",0.1,s,false,PL_COMM_UNKNOWN,0.0,0.0,false);
   BrokerBase(r,MS,IN,0.02);    r.currency="USD"; r.tier_currency="USD";
                                BrokerCaseSym("rule_usd_account_ust",1,r,"UST",0.1,s,false,PL_COMM_UNKNOWN,0.0,0.0,false);
   //--- a zero rate with a minimum is not a zero: LOT_ROUND 0 with the minimum, not the known zero
   BrokerBase(r,MS,IN,0.0);     r.min_value=0.2;
                                BrokerCaseSym("zero_rate_with_min",1,r,"USD",0.1,s,true,PL_COMM_LOT_ROUND,0.0,0.2,false);
   BrokerBase(r,MS,IN,0.0);     BrokerCaseSym("zero_rate_in_known_zero",1,r,"USD",0.1,s,true,PL_COMM_LOT_SIDE,0.0,0.0,true);
   //--- the rules of vectors 147 and 148 are what the pure function gives for the demo rules
   PlVector v;
   BrokerBase(r,P,IO,0.0325);   PlVec147(v);
                                BrokerCase("vec147_pct",1,r,"USD",0.01,true,v.in.comm.kind,v.in.comm.rate,false);
   BrokerBase(r,MS,IO,2.5);     PlVec148(v);
                                BrokerCase("vec148_money",1,r,"USD",0.01,true,v.in.comm.kind,v.in.comm.rate,false);
  }

void OnStart()
  {
   const int total_vec=PlVectorCount();
   const int total=total_vec;
   int passed=0;
   string body="";
   for(int i=0; i<total; i++)
     {
      PlVector v;
      if(!PlVectorGet(i,v))
         continue;
      PlPlan p;
      PlResult r;
      ZeroMemory(p);
      ZeroMemory(r);
      const bool ok=PlPrepare(v.in,v.s,p);
      PlCompute(v.in,v.s,v.a,p,r);

      g_checks="";
      g_vec_ok=true;
      g_check_count=0;
      const double ptol=v.s.tick_size/100.0;
      const double lt=1e-8;
      const double mt=v.tol_money;
      const double pt=1e-4;

      if(v.chk_prepare_ok)
        {
         ChkB("prepare_ok",v.exp_prepare_ok,ok);
         ChkB("plan_ok",v.exp_prepare_ok,p.ok);
        }
      ChkI("plan_reason",v.exp_plan_reason,p.reason);
      ChkI("side",v.exp_side,p.side);
      ChkI("order_type",v.exp_order_type,p.order_type);
      ChkD("exec",v.exp_exec,p.exec,ptol);
      ChkD("sl",v.exp_sl,p.sl,ptol);
      ChkD("tp",v.exp_tp,p.tp[0],ptol);
      ChkI("ticks",v.exp_ticks,p.ticks);
      ChkD("lpl_a",v.exp_lpl_a,r.lpl_a,mt);
      ChkD("lpl_c",v.exp_lpl_c,r.lpl_c,mt);
      ChkD("lpl_price",v.exp_lpl_price,r.lpl_price,mt);
      ChkD("comm_in",v.exp_comm_in,r.comm_in_1lot,mt);
      ChkD("comm_out",v.exp_comm_out,r.comm_out_1lot,mt);
      ChkD("loss_per_lot",v.exp_loss_per_lot,r.loss_per_lot,mt);
      ChkD("lot",v.exp_lot,r.lot,lt);
      ChkD("risk_money",v.exp_risk_money,r.risk_money,mt);
      ChkD("net_risk",v.exp_net_risk,r.net_risk,mt);
      ChkD("risk_add",v.exp_risk_add,r.risk_add,mt);
      ChkD("risk_percent",v.exp_risk_percent,r.risk_percent,pt);
      ChkD("reward_total",v.exp_reward_total,r.reward_total,mt);
      ChkD("rr",v.exp_rr,r.rr,pt);
      ChkD("margin_needed",v.exp_margin_needed,r.margin_needed,mt);
      ChkD("comm_money",v.exp_comm_money,r.comm_money,mt);
      ChkI("comm_min_on",v.exp_comm_min_on,r.comm_min_on?1:0);
      ChkD("spread_points",v.exp_spread_points,r.spread_points,pt);
      ChkD("spread_money",v.exp_spread_money,r.spread_money,mt);
      ChkD("swap_long",v.exp_swap_long,r.swap_long_night,mt);
      ChkD("swap_short",v.exp_swap_short,r.swap_short_night,mt);
      ChkI("swap_ok",v.exp_swap_ok,r.swap_ok?1:0);
      ChkI("verdict",v.exp_verdict,r.verdict);
      ChkI("reason",v.exp_reason,r.reason);
      ChkI("note",v.exp_note,r.note);
      ChkI("split_n",v.exp_split_n,r.split_n);
      ChkI("split_need",v.exp_split_need,r.split_need);
      for(int q=0; q<PL_MAX_PARTS; q++)
         ChkD("split_lot"+IntegerToString(q+1),v.exp_split[q],r.split_lot[q],lt);

      if(g_vec_ok)
         passed++;
      else
         PrintFormat("FAIL %02d %s",i+1,v.name);
      if(i>0)
         body+=",\n";
      body+="{\"n\":"+IntegerToString(i+1)+",\"name\":\""+JsonStr(v.name)+"\",\"pass\":"+(g_vec_ok?"true":"false")
            +",\"checks\":["+g_checks+"]}";
     }

   SessBlock();
   GrowBlock();
   StartVolBlock();
   BrokerBlock();
   body+=g_sess_body;
   passed+=g_sess_pass;
   const int all=total+g_sess_n;
   const string json="{\"total\":"+IntegerToString(all)+",\"passed\":"+IntegerToString(passed)
                     +",\"failed\":"+IntegerToString(all-passed)+",\"vectors\":[\n"+body+"\n]}\n";
   const int h=FileOpen("PlCoreTests.json",FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(h==INVALID_HANDLE)
     {
      Print("PlCoreTests: cannot write the result file");
      return;
     }
   FileWriteString(h,json);
   FileClose(h);
   PrintFormat("PlCoreTests: %d of %d vectors passed",passed,all);
  }
