// Required Notice: Copyright 2026 stop-loss-enjoyer
// Plainlines is source-available under the PolyForm Shield License 1.0.0.
//
// Account identity and the things that belong to one account only. ACCOUNT_LOGIN is read here and
// nowhere else (audit.sh), kept in memory only (never in a file, a log, a message or a hash) and
// used for a single thing: noticing that the account changed while the program runs (together with the
// server name, which is not the account number).
#property strict

#ifndef PL_TERMINAL_ACCOUNT_MQH
#define PL_TERMINAL_ACCOUNT_MQH

#define PL_CAP_DEFAULT 5.0

static long   g_pl_login_seen=0;
static bool   g_pl_login_known=false;
static string g_pl_server_seen="";

//--- true once when the account differs from the one seen before: another login or another server
//--- (account identity is login plus server). Compares only, prints nothing.
bool PlAccountChanged()
  {
   const long l=AccountInfoInteger(ACCOUNT_LOGIN);
   const string sv=AccountInfoString(ACCOUNT_SERVER);
   if(!g_pl_login_known) { g_pl_login_known=true; g_pl_login_seen=l; g_pl_server_seen=sv; return false; }
   if(l==g_pl_login_seen && sv==g_pl_server_seen) return false;
   g_pl_login_seen=l;
   g_pl_server_seen=sv;
   return true;
  }

//--- another account: in a build with more checks its counters and snapshots do not carry over (the hard cap is kept per account in settings.dat)
void PlAccountReset()
  {
  }

#endif
