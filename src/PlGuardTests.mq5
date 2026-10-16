// Required Notice: Copyright 2026 stop-loss-enjoyer
// Plainlines is source-available under the PolyForm Shield License 1.0.0.
//
// Test script of the guards: runs every vector of GuardVectors.mqh through Core/Guard.mqh, compares the checked fields and
// writes MQL5/Files/PlGuardTests.json. The script trades nothing and reads nothing from the terminal (the core is
// pure). Same JSON shape as PlCoreTests.json: total, passed, failed, vectors[{n,name,pass,checks[]}].
#property copyright "stop-loss-enjoyer"
#include "Version.mqh"
#property version   PLAINLINES_VERSION
#property strict
#property script_show_inputs

#include "Build.mqh"
#include "Core/Types.mqh"
#include "Core/Num.mqh"
#include "Core/Guard.mqh"
#include "GuardVectors.mqh"

string g_checks;       // JSON of the checks of the current vector
bool   g_vec_ok;       // every check of the current vector passed
int    g_check_count;
string g_body;         // JSON of all vectors so far
int    g_total;
int    g_passed;

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

string JsonTime(const datetime t)
  {
   return "\""+TimeToString(t,TIME_DATE|TIME_SECONDS)+"\"";
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

//--- datetime: skipped when 0
void ChkT(const string field,const datetime exp,const datetime got)
  {
   if(exp==0)
      return;
   AddCheck(field,JsonTime(exp),JsonTime(got),exp==got);
  }

void ChkB(const string field,const bool exp,const bool got)
  {
   AddCheck(field,exp?"true":"false",got?"true":"false",exp==got);
  }

void BeginVec()
  {
   g_checks="";
   g_vec_ok=true;
   g_check_count=0;
  }

void EndVec(const string name)
  {
   g_total++;
   if(g_vec_ok)
      g_passed++;
   else
      PrintFormat("FAIL %02d %s",g_total,name);
   if(g_total>1)
      g_body+=",\n";
   g_body+="{\"n\":"+IntegerToString(g_total)+",\"name\":\""+JsonStr(name)+"\",\"pass\":"+(g_vec_ok?"true":"false")
           +",\"checks\":["+g_checks+"]}";
  }

//--- split "a|b|c" into parts
int Split(const string row,string &p[])
  {
   return StringSplit(row,'|',p);
  }

//+------------------------------------------------------------------+
//| the guards |
//+------------------------------------------------------------------+
void RunGuard()
  {
   const int count=PlGuardVecCount();
   for(int i=0; i<count; i++)
     {
      PlGuardVec v;
      if(!PlGuardVecGet(i,v))
        {
         BeginVec();
         AddCheck("vector_exists","true","false",false);
         EndVec("guard vector "+IntegerToString(i)+" missing");
         continue;
        }
      PlExpo ex[];
      ArrayResize(ex,v.ne);
      for(int k=0; k<v.ne; k++)
         ex[k]=v.ex[k];
      PlGuardOut o;
      PlGuardRun(v.c,v.in,ex,o);

      BeginVec();
      const double mt=1e-6;
      const double pt=1e-4;
      ChkD("max_new_risk",v.exp_max_new,o.max_new_risk,mt);
      ChkD("open_risk",v.exp_open_risk,o.open_risk,mt);
      ChkD("pending_risk",v.exp_pending_risk,o.pending_risk,mt);
      ChkD("portfolio_pct",v.exp_portfolio_pct,o.portfolio_pct,pt);
      ChkD("margin_use_pct",v.exp_margin_pct,o.margin_use_pct,pt);
      ChkI("no_sl",v.exp_no_sl,o.no_sl);
      ChkI("unknown",v.exp_unknown,o.unknown);
      ChkI("verdict",v.exp_verdict,o.verdict);
      ChkI("why",v.exp_why,o.why);
      EndVec(v.name);
     }
  }

//--- Max trades a day counts from the midnight of the server clock
void RunServerDay()
  {
   int n=ArraySize(g_pl_srvday_rows);
   for(int i=0; i<n; i++)
     {
      string p[];
      Split(g_pl_srvday_rows[i],p);
      BeginVec();
      ChkT("day_start",StringToTime(p[1]),PlServerDayStart(StringToTime(p[0])));
      EndVec("server day start of "+p[0]);
     }
   n=ArraySize(g_pl_srvcount_rows);
   for(int i=0; i<n; i++)
     {
      string p[];
      Split(g_pl_srvcount_rows[i],p);
      const datetime now=StringToTime(p[1]);
      string e[];
      const int ne=StringSplit(p[2],',',e);
      datetime t[];
      ArrayResize(t,ne);
      for(int k=0; k<ne; k++)
         t[k]=StringToTime(e[k]);
      const int today=PlCountSince(t,ne,PlServerDayStart(now));
      PlGuardVec v;
      LvOff(v,p[0]);
      v.c.max_day=(int)StringToInteger(p[3]);
      v.in.trades_today=today;
      PlExpo ex[];
      PlGuardOut o;
      PlGuardRun(v.c,v.in,ex,o);
      BeginVec();
      ChkI("trades_today",StringToInteger(p[4]),today);
      ChkI("verdict",StringToInteger(p[5]),o.verdict);
      EndVec(p[0]);
     }
  }

//--- the verdict class of a reason of the free core
void RunWhyFree()
  {
   const int n=ArraySize(g_pl_free_why_rows);
   for(int i=0; i<n; i++)
     {
      string p[];
      Split(g_pl_free_why_rows[i],p);
      BeginVec();
      ChkI("verdict",StringToInteger(p[1]),PlGuardWhyVerdict((PlGuardWhy)StringToInteger(p[0])));
      EndVec("PlGuardWhyVerdict "+p[0]);
     }
   //--- the order of the checks: the ranks rise along the list
   int order[]={PL_LW_PROFILE_BAD,PL_LW_NO_HISTORY,PL_LW_NEW_NO_SL,PL_LW_RISK_UNKNOWN,PL_LW_PORTFOLIO_UNKNOWN,PL_LW_PORTFOLIO_CAP,
                PL_LW_TRADES_OPEN,PL_LW_TRADES_DAY,PL_LW_MARGIN_USE};
   int bad=0;
   for(int i=1; i<ArraySize(order); i++)
      if(PlWhyRank((PlGuardWhy)order[i])<=PlWhyRank((PlGuardWhy)order[i-1]))
         bad++;
   BeginVec();
   ChkI("rank_order_breaks",0,bad);
   EndVec("the ranks of the reasons of the free core rise in the order of the checks");
  }

void RunFnv()
  {
   int n;
   n=ArraySize(g_pl_fnv_rows);
   for(int i=0; i<n; i++)
     {
      string p[];
      StringSplit(g_pl_fnv_rows[i],'|',p);
      BeginVec();
      AddCheck("fnv32","\""+p[1]+"\"","\""+PlFnv32Hex(p[0])+"\"",PlFnv32Hex(p[0])==p[1]);
      AddCheck("fnv64","\""+p[2]+"\"","\""+PlFnv64Hex(p[0])+"\"",PlFnv64Hex(p[0])==p[2]);
      EndVec("FNV of '"+p[0]+"'");
     }
   BeginVec();
   AddCheck("fnv32","\"bb4273b8\"","\""+PlFnv32Hex("rid=x\nsum")+"\"",PlFnv32Hex("rid=x\nsum")=="bb4273b8");
   EndVec("FNV32 of a body with a newline");
   BeginVec();
   AddCheck("fnv64","\"7b3ec8e44fbb3c84\"","\""+PlFnv64Hex("FTMO-Demo|USD|1760000000|100000.00")+"\"",
            PlFnv64Hex("FTMO-Demo|USD|1760000000|100000.00")=="7b3ec8e44fbb3c84");
   EndVec("FNV64 of a profile id source");
  }


//--- a damaged profile file: skipped only when its later lines prove the fingerprint lines were complete
void ProfCase(const string name,const bool has_t,const string fs,const string fc,const bool exp_other)
  {
   BeginVec();
   ChkB("surely_other",exp_other,PlProfSurelyOther(has_t,fs,fc,"FTMO-Demo","USD"));
   EndVec("damaged profile file: "+name);
  }

void RunProfScan()
  {
   ProfCase("complete, other server",true,"Bybit-Live","USD",true);
   ProfCase("complete, other currency",true,"FTMO-Demo","EUR",true);
   ProfCase("complete, same account (BAD)",true,"FTMO-Demo","USD",false);
   ProfCase("torn inside fp_server (BAD)",false,"FTMO-De","",false);
   ProfCase("torn inside fp_server, other prefix (BAD)",false,"Bybit","",false);
   ProfCase("torn inside fp_cur (BAD)",false,"FTMO-Demo","US",false);
   ProfCase("torn before fp_server (BAD)",false,"","",false);
  }


void OnStart()
  {
   g_total=0;
   g_passed=0;
   g_body="";
   RunGuard();
   RunServerDay();
   RunWhyFree();
   RunFnv();
   RunProfScan();

   const string json="{\"total\":"+IntegerToString(g_total)+",\"passed\":"+IntegerToString(g_passed)
                     +",\"failed\":"+IntegerToString(g_total-g_passed)+",\"vectors\":[\n"+g_body+"\n]}\n";
   const string out_name="PlGuardTests.json";
   const int h=FileOpen(out_name,FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(h==INVALID_HANDLE)
     {
      Print("PlGuardTests: cannot write the result file");
      return;
     }
   FileWriteString(h,json);
   FileClose(h);
   PrintFormat("PlGuardTests: %d of %d vectors passed",g_passed,g_total);
  }
