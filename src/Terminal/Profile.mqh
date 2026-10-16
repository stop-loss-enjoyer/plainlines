// Required Notice: Copyright 2026 stop-loss-enjoyer
// Plainlines is source-available under the PolyForm Shield License 1.0.0.
//
// The account profile: MQL5/Files/Plainlines/acct_<rid>.dat holds the portfolio cap (Max total risk)
// of one account, found again after a restart by a fingerprint that is NOT the account number and not a hash of it: the
// server name, the account currency, and the time and amount of the first balance deal of the whole history. The risk of the
// account (settings.dat, keys with @<rid>) is kept under the same id.
// The number of the account is never read in this file. The file name is a hash of those four values (the same on
// every chart of the account), the file ends with a checksum line, and a damaged file blocks (state BAD). A key this
// build does not know stays in the file when it is written again (another build may keep its own keys there).
#property strict

#ifndef PL_TERMINAL_PROFILE_MQH
#define PL_TERMINAL_PROFILE_MQH

enum PlProfState { PL_PS_LOADING=0, PL_PS_NONE, PL_PS_OK, PL_PS_BAD };

void PlMessage(const string t,const uint ms=3500,const int kind=0);


string     g_prof_rid="";            // 16 hex characters (hash of the fingerprint); empty without a fingerprint
int        g_prof_state=PL_PS_LOADING;
PlGuardCfg g_lc;                     // the portfolio cap of this account (the other guards come from g_cfg)
string     g_prof_note="";           // one phrase for the status after the account was found (shown once)
bool       g_prof_any_on=false;      // some profile on disk has a portfolio cap
string     g_prof_seen="";           // the keys of the file as last applied to this chart (see PlProfLimJoin)
bool       g_prof_dirty=false;       // settings changed while the account was not recognised yet
bool       g_prof_wait_said=false;   // the log line "waiting for the history" is written once per wait

PlGuardOut g_lo;                     // the last evaluation of the guards
string     g_guard_text="";          // the phrase for g_res.reason == PL_R_GUARD

//--- the history counts as loaded while it adds up to the balance of the account as last read; nothing else is stored
bool PlHistLoaded() { return PlHistAddsUp(g_acc); }

//--- the text of a reason; the guard's own phrase for PL_R_GUARD
string PlReasonTextG(const PlReason r)
  {
   if(r==PL_R_GUARD && g_guard_text!="") return g_guard_text;
   const int ld=PlStepDigits(g_sym.vol_step);
   if(r==PL_R_LOT_ABOVE_MAX && g_res.lot>g_sym.vol_max+PL_EPS)
      return PLS_LOT_WORD_UP+DoubleToString(g_res.lot,ld)+PLS_IS_ABOVE_THE_BROKER_MAX+DoubleToString(g_sym.vol_max,ld);
   if(r==PL_R_STALE_QUOTE) return PlStaleText(PlStaleSeconds(g_sym));
   if(r==PL_R_SPLIT_TOO_MANY)
      return PLS_SPLIT_WOULD_NEED+(string)g_res.split_need+PLS_ORDERS_THE_LIMIT_IS+(string)PL_MAX_PARTS;
   if(r==PL_R_SPLIT_ORDERS && g_res.split_n>1)
      return PLS_LOT_WORD_UP+DoubleToString(g_res.lot,ld)+PLS_GOES_OUT_IN+(string)MathMax(g_split_orders,g_res.split_n)+" "+PLS_ORDERS;
   if(r==PL_R_SPLIT_NETTING)
      return PLS_SPLIT_NEEDS_HEDGING;
   if(r==PL_R_LOT_BELOW_MIN && g_res.verdict==PL_BLOCK) return PLS_LOT_BELOW_BROKER_MIN+DoubleToString(g_sym.vol_min,ld);
   return PlReasonText(r);
  }

//--- the text of the grey button: the guard's own word for a block (the last evaluation g_lo), else as PlBlockedText
string PlBlockedTextG(const PlReason r)
  {
   if(r==PL_R_GUARD) return PLS_BLOCKED+": "+PlGuardShort(g_lo.why);
   return PlBlockedText(r);
  }

string PlProfFile(const string rid) { return PL_DIR+"\\acct_"+rid+".dat"; }

//--- nothing is preset: the start balance and the limits are typed or chosen by the user (a wrong preset would be a wrong limit)
void PlProfDefaults()
  {
   ZeroMemory(g_lc);
   g_lc.portfolio_cap_pct=0.0;
  }

//--- the settings from the key=value store that was just loaded
void PlProfTake()
  {
   g_lc.portfolio_cap_pct=PlKvD("port_cap",0.0);
  }

//--- the profile id: a hash of server, currency and the first deposit (time and amount), all of them already in the file
//--- in plain text; never the login. The same on every chart of one account. An integrity id, not security.
//--- Without a fingerprint (no balance deal in the history) the account has no identity: ""
string PlProfRidFor()
  {
   if(!g_fp_found) return "";
   return PlFnv64Hex(AccountInfoString(ACCOUNT_SERVER)+"|"+AccountInfoString(ACCOUNT_CURRENCY)+"|"+(string)(long)g_fp_t
                     +"|"+DoubleToString(g_fp_amount,2));
  }

//--- the settings keys of the store just loaded, as one string (a change another chart made shows as a different string)
string PlProfLimJoin()
  {
   return "port_cap="+PlKvGet("port_cap","")+"\n";
  }

//--- the store just loaded carries the fingerprint of this account
bool PlProfSameAccount()
  {
   return (PlKvGet("fp_server","")==AccountInfoString(ACCOUNT_SERVER) && PlKvGet("fp_cur","")==AccountInfoString(ACCOUNT_CURRENCY)
           && (long)PlKvI("fp_t",0)==(long)g_fp_t && MathAbs(PlKvD("fp_amount",0.0)-g_fp_amount)<0.005);
  }

//--- every acct_*.dat file name (without the folder)
int PlProfList(string &names[])
  {
   ArrayResize(names,0);
   string nm;
   long h=FileFindFirst(PL_DIR+"\\acct_*.dat",nm);
   if(h==INVALID_HANDLE) return 0;
   do
     {
      const int n=ArraySize(names);
      ArrayResize(names,n+1);
      names[n]=nm;
     }
   while(FileFindNext(h,nm));
   FileFindClose(h);
   return ArraySize(names);
  }

//--- is a portfolio cap on in some profile of THIS server on disk? (decides whether an entry waits for the history; a file of
//--- another server protects nothing here). A file that cannot be read counts as on, and so does every file while the
//--- server name is not known yet.
void PlProfScanAny()
  {
   g_prof_any_on=false;
   const string srv=AccountInfoString(ACCOUNT_SERVER);
   string names[];
   const int n=PlProfList(names);
   for(int i=0;i<n;i++)
     {
      if(!PlKvLoad(PL_DIR+"\\"+names[i])) { g_prof_any_on=true; break; }     // a file that cannot be opened is unknown, counts as on
      if(!g_kv_valid)
        {
         if(srv!="" && PlKvHas("fp_t") && PlKvGet("fp_server","")!=srv) continue;   // the cut file names another server
         g_prof_any_on=true; break;                                                // unknown counts as on
        }
      if(srv!="" && PlKvGet("fp_server","")!=srv) continue;
      if(PlKvD("port_cap",0.0)>PL_EPS) { g_prof_any_on=true; break; }
     }
  }

//--- writes the profile of this account. A key the file has and this build does not know stays as it is; a missing or
//--- damaged file is written clean
bool PlProfWrite()
  {
   if(g_prof_rid=="") return false;
   const string f=PlProfFile(g_prof_rid);
   if(!PlKvLoad(f) || !g_kv_valid) PlKvClear();
   PlKvSet("rid",g_prof_rid);
   PlKvSet("fp_server",AccountInfoString(ACCOUNT_SERVER));
   PlKvSet("fp_cur",AccountInfoString(ACCOUNT_CURRENCY));
   PlKvSetI("fp_t",(long)g_fp_t);
   PlKvSetD("fp_amount",g_fp_amount);
   PlKvSetD("port_cap",g_lc.portfolio_cap_pct);
   const bool ok=PlKvSave(f);
   if(ok) g_prof_seen=PlProfLimJoin();
   return ok;
  }

//--- the profile is still being read (a build with more checks also waits for its own file)
bool PlProfLoading()
  {
   return (g_prof_state==PL_PS_LOADING);
  }

//--- saves the settings. user=true: the user changed them (makes the profile of the account when there is none);
//--- user=false: only what a build with a counter to keep writes to an existing file (nothing in the free build)
bool PlProfileSave(const bool user)
  {
   //--- "none" decided before the history added up has no id yet: the first deposit it would be made of may still be missing
   if(PlProfLoading() || (g_prof_rid=="" && !PlHistLoaded())) { if(user) g_prof_dirty=true; return false; }
   if(!user)
     {
      if(g_prof_dirty) return false;     // a user write failed and is waiting: the retry goes first, a flush must not take the disk values over it
      return false;
     }
   if(!g_fp_found)
     {
      PlProfDefaults();
      PlMessage(PLS_PROF_NO_ID,6000,2);
      g_prof_dirty=false;
      return false;
     }
   if(g_prof_rid=="") g_prof_rid=PlProfRidFor();
   g_prof_state=PL_PS_OK;
   bool ok=PlProfWrite();
   g_prof_dirty=!ok;
   return ok;
  }

//--- the file of the profile that is the base among several: the newest valid one
int PlProfBase(const string &f[],const int n)
  {
   int best=-1; long bt=-1;
   for(int i=0;i<n;i++)
     {
      if(!PlKvLoad(f[i]) || !g_kv_valid) continue;     // a torn read is not a candidate (the caller looks again)
      const long t=FileGetInteger(f[i],FILE_MODIFY_DATE);
      if(best<0 || t>bt) { best=i; bt=t; }
     }
   return best;
  }

//--- find this account's profile (no questions, no buttons). Called once the history has been
//--- read, adding up to the balance or not. The rules, in this order:
//---  (a) a file with the same fingerprint (server, currency, time and amount of the first deposit, all four): that profile at
//---      once, the history need not add up (several: the newest);
//---  (b) no file at all with this server (a file that cannot be read may be one): the account is "none" at once, no file is
//---      written, there is nothing to protect on this server;
//---  (c) else (a file of this server, no exact match yet) the history must add up first, and until then the entry counts as
//---      waiting only if some profile of this server has a cap. Then: damaged file of this account or one that cannot be read:
//---      BAD, it blocks and is never replaced by the settings of other accounts; same server and currency but another first
//---      deposit (a new account at the same broker): a profile of its own with the cap of the profiles there; nothing
//---      alike: none, no file until the user sets something.
//--- While the history does not add up nothing but (a) and (b) may end the wait, and a wait changes and writes nothing.
//--- The number of the account is never read.
void PlProfBlank()
  {
   PlProfDefaults();
   g_prof_rid=""; g_prof_note=""; g_prof_seen="";
  }

void PlProfFind()
  {
   const string srv=AccountInfoString(ACCOUNT_SERVER), cur=AccountInfoString(ACCOUNT_CURRENCY);
   string names[];
   const int n=PlProfList(names);
   string fulls[], parts[];
   bool bad=false;
   int srv_files=0;                     // valid files that name this server, whatever the currency
   for(int i=0;i<n;i++)
     {
      const string f=PL_DIR+"\\"+names[i];
      PlKvLoad(f);
      if(!g_kv_valid)
        {
         //--- PlProfWrite writes rid, fp_server, fp_cur, fp_t in this order: a file is taken for another account's only when
         //--- fp_t is there, which proves the fp_server and fp_cur lines were complete. A cut inside them proves nothing.
         if(PlProfSurelyOther(PlKvHas("fp_t"),PlKvGet("fp_server",""),PlKvGet("fp_cur",""),srv,cur)) continue;
         bad=true;
         continue;
        }
      if(PlKvGet("fp_server","")==srv) srv_files++;
      if(PlKvGet("fp_server","")!=srv || PlKvGet("fp_cur","")!=cur) continue;
      const bool same=(g_fp_found && (long)PlKvI("fp_t",0)==(long)g_fp_t && MathAbs(PlKvD("fp_amount",0.0)-g_fp_amount)<0.005);
      if(same) { const int k=ArraySize(fulls); ArrayResize(fulls,k+1); fulls[k]=f; }
      else     { const int k=ArraySize(parts); ArrayResize(parts,k+1); parts[k]=f; }
     }
   const bool was_bad=(g_prof_state==PL_PS_BAD);
   if(ArraySize(fulls)>0)
     {
      PlProfBlank();
      const int base=PlProfBase(fulls,ArraySize(fulls));
      if(base<0 || !PlKvLoad(fulls[base]) || !g_kv_valid)
        {
         // another chart was writing between the scan and this read: nothing is applied, the next lap looks again
         PlProfDefaults();
         g_prof_rid=""; g_prof_seen=""; g_prof_state=PL_PS_LOADING;
         g_prof_any_on=true;     // unknown counts as on: LOADING blocks
         PLDBG("PROFILE torn read, looking again");
         return;
        }
      g_prof_seen=PlProfLimJoin();
      g_prof_rid=PlKvGet("rid","");
      if(g_prof_rid=="") g_prof_rid=PlProfRidFor();
      PlProfTake();
      g_prof_state=PL_PS_OK;
      PLDBG("PROFILE recognised rid="+g_prof_rid+" cap="+DoubleToString(g_lc.portfolio_cap_pct,2)+" matches="+(string)ArraySize(fulls));
      return;
     }
   if(srv!="" && srv_files==0 && !bad)
     {
      //--- (b): the id is the hash of the first deposit, so it waits for a history that adds up (a partial one may lack the deposit)
      PlProfBlank();
      g_prof_state=PL_PS_NONE;
      g_prof_rid=PlHistLoaded()?PlProfRidFor():"";
      g_prof_wait_said=false;
      PLDBG("PROFILE none, no file of this server loaded="+(string)PlHistLoaded());
      return;
     }
   if(!PlHistLoaded())
     {
      if(!g_prof_wait_said) { g_prof_wait_said=true; PLDBG("PROFILE waiting for the history, a file of this server exists any_on="+(string)g_prof_any_on); }
      return;
     }
   g_prof_wait_said=false;
   PlProfBlank();
   if(bad)
     {
      g_prof_dirty=false;      // a waiting user write must never replace a damaged file of this account
      g_prof_rid=PlProfRidFor();
      g_prof_state=PL_PS_BAD;
      g_prof_seen="";
      if(!was_bad) { PLDBG("PROFILE damaged file, blocked"); }
      return;
     }
   if(!g_fp_found)
     {
      g_prof_state=PL_PS_NONE;
      g_prof_rid="";
      if(g_prof_any_on) g_prof_note=PLS_PROF_OFF;
      PLDBG("PROFILE none, no deposit in the history");
      return;
     }
   if(ArraySize(parts)>0)
     {
      const int base=PlProfBase(parts,ArraySize(parts));
      if(base<0 || !PlKvLoad(parts[base]) || !g_kv_valid)
        {
         PlProfDefaults();
         g_prof_rid=""; g_prof_seen=""; g_prof_state=PL_PS_LOADING;
         g_prof_any_on=true;     // unknown counts as on: LOADING blocks
         PLDBG("PROFILE torn read, looking again");
         return;
        }
      PlProfTake();
      g_prof_rid=PlProfRidFor();
      g_prof_state=PL_PS_OK;
      PlProfWrite();               // with the fingerprint of this account; the other profiles stay as they are
      PLDBG("PROFILE new rid="+g_prof_rid+" from "+(string)ArraySize(parts)+" at the same broker, cap="+DoubleToString(g_lc.portfolio_cap_pct,2));
      return;
     }
   g_prof_state=PL_PS_NONE;
   g_prof_rid=PlProfRidFor();
   if(g_prof_any_on) g_prof_note=PLS_PROF_OFF;
   PLDBG("PROFILE none");
  }

//--- the profile id has become known: this account's own risk (settings.dat, keys with @<id>) replaces the terminal's last one;
//--- an account seen for the first time keeps the current values and they are written under its id. Once per id.
void PlRiskForAccount()
  {
   if(g_prof_rid=="" || g_prof_rid==g_risk_rid) return;
   const bool have=PlKvLoad(PL_SETTINGS_FILE);
   if(have && !g_kv_valid) return;                   // mid-write or damaged: the next resolve or reread looks again
   const string sx="@"+g_prof_rid;
   const bool own=PlKvHas("risk_pct"+sx);
   if(own) PlRiskTake(sx);
   PlCapTake(sx);                                    // its own hard cap, if it has one; else the default stands (never another account's)
   g_risk_rid=g_prof_rid;
   if(own) { PlSnapTake(); PlSettingsBuild(); }     // the snapshot is the file as read (see PlSettingsLoad), the plain keys now differ
   else PlSettingsSave();
   PLDBG("RISK account "+(own?"has its own":"starts with the terminal's last")+": unit_money="+(string)g_dr.unit_money
         +" pct="+DoubleToString(g_dr.risk_pct,2)+" money="+DoubleToString(g_dr.risk_money,2));
  }

//--- the account profile itself is read again: it is BAD, still loading, or the account has no id yet
bool PlProfFreeNeedsFind()
  {
   return (g_prof_state==PL_PS_BAD || g_prof_state==PL_PS_LOADING || (g_prof_state==PL_PS_NONE && g_prof_rid=="" && g_fp_found));
  }

void PlProfResolve()
  {
   if(PlProfFreeNeedsFind()) PlProfFind();     // a build with a file of its own may resolve again for that file alone
   PlRiskForAccount();
  }

//--- the settings another chart wrote, compared by content (the file date has a resolution of one second)
bool PlProfChangedByOther()
  {
   bool ch=false;
   if(g_prof_rid!="" && (g_prof_state==PL_PS_OK || g_prof_state==PL_PS_NONE)
      && PlKvLoad(PlProfFile(g_prof_rid)) && g_kv_valid && PlProfSameAccount())   // missing, mid-write or damaged: next second
     {
      const string j=PlProfLimJoin();
      if(j!=g_prof_seen)
        {
         PlProfTake();
         g_prof_seen=j;
         g_prof_state=PL_PS_OK;
         ch=true;
        }
     }
   return ch;
  }

//--- the time for the first reading and for a new account
void PlProfReset()
  {
   g_prof_state=PL_PS_LOADING; g_prof_rid=""; g_prof_note=""; g_prof_seen="";
   g_prof_wait_said=false;
   PlProfDefaults();
   PlProfScanAny();
   PlExposureReset();
  }

//--- the profile is read again while it waits (BAD, LOADING, no id yet) or its state changed: one number for what a caller compares
int PlProfSig()
  {
   return g_prof_state;
  }

//--- the profile must be looked at again once the history adds up: it is BAD, still loading, or the account has no id yet
bool PlProfNeedsResolve()
  {
   if(PlProfFreeNeedsFind()) return true;
   return false;
  }

//--- the wait for the history says why it is a wait (the status line)
string PlWaitPhrase(const PlGuardOut &o,const string text)
  {
   return text;
  }

//--- the configuration the guards evaluate
void PlGuardCfgBuild(PlGuardCfg &c)
  {
   c=g_lc;
   c.subtract_open=g_cfg.subtract_open;
   c.max_open=g_cfg.max_open; c.max_day=g_cfg.max_day; c.margin_use_pct=g_cfg.margin_use;
  }

void PlGuardInBuild(PlGuardIn &in,const PlAccount &a,const double new_risk,const double new_margin,const int new_open,const int new_entries)
  {
   ZeroMemory(in);
   in.profile_bad=(g_prof_state==PL_PS_BAD);
   in.profile_wait=(g_prof_state==PL_PS_LOADING && g_prof_any_on);
   in.deals_loaded=PlHistAddsUp(a);
   in.balance=a.balance; in.equity=a.equity; in.margin=a.margin;
   in.new_risk=new_risk; in.new_margin=new_margin;
   in.new_no_sl=g_cfg.no_sl;
   in.open_count=g_ex_open_count;
   in.new_open=new_open; in.new_entries=new_entries;
   in.trades_today=PlTradesToday(PlServerDayStart(TimeTradeServer()));
  }

void PlGuardRunAll(const PlAccount &a,const double new_risk,const double new_margin,const int new_open,const int new_entries,PlGuardOut &o)
  {
   PlGuardCfg c; PlGuardCfgBuild(c);
   PlGuardIn in; PlGuardInBuild(in,a,new_risk,new_margin,new_open,new_entries);
   PlGuardRun(c,in,g_ex,o);
  }

//--- the phrase of a result of PlGuardRunAll, with the settings of this moment
string PlGuardPhraseNow(const PlGuardOut &o,const double new_risk,const double lpl,const double step,const string cur,const int cd)
  {
   PlGuardCfg c; PlGuardCfgBuild(c);
   return PlGuardPhrase(o,c,new_risk,lpl,step,cur,cd);
  }

//--- the guard handed to the send: recounted from the positions of this moment
void PlGuardBuild(PlGuard &g,const PlAccount &a)
  {
   PlGuardNeutral(g);
   PlGuardCfg c; PlGuardCfgBuild(c);
   PlGuardOut o0;
   PlGuardRunAll(a,0.0,0.0,1,0,o0);     // any trade adds an order; whether it is a market entry is judged at the send
   g.balance=a.balance; g.port_used=o0.open_risk+o0.pending_risk; g.port_cap_pct=c.portfolio_cap_pct;
   if(o0.verdict==PL_BLOCK)
     {
      g.verdict=PL_BLOCK; g.reason=PL_R_GUARD; g.why=(int)o0.why;
      g.text=PlWaitPhrase(o0,PlGuardPhrase(o0,c,0.0,0.0,0.01,a.currency,a.currency_digits));
      return;
     }
   double mx=-1.0;
   if(o0.max_new_risk>=0.0)
     {
      mx=o0.max_new_risk;
     }
   if(c.portfolio_cap_pct>PL_EPS)
     {
      g.room_port=MathMax(0.0,a.balance*c.portfolio_cap_pct/100.0-g.port_used);
      if(mx<0.0 || g.room_port<mx) mx=g.room_port;
     }
   g.max_new_risk=mx;
  }

#endif
