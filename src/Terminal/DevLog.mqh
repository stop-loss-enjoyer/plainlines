// Required Notice: Copyright 2026 stop-loss-enjoyer
// Plainlines is source-available under the PolyForm Shield License 1.0.0.
//
// Data folder and the development log. The log and the command channel exist only in a dev build
// (./build.sh --dev writes PL_DEV_LOG into the build copy of Build.mqh; the audit refuses it in sources). Never write an account
// number here.
#property strict

#ifndef PL_TERMINAL_DEVLOG_MQH
#define PL_TERMINAL_DEVLOG_MQH

#define PL_DIR            "Plainlines"

#ifdef PL_DEV_LOG
int g_dev_h=INVALID_HANDLE;

void PlDevOpen()
  {
   if(g_dev_h!=INVALID_HANDLE) return;
   FolderCreate(PL_DIR);
   g_dev_h=FileOpen(PL_DIR+"\\dev.log",FILE_READ|FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_SHARE_READ|FILE_SHARE_WRITE);
   if(g_dev_h!=INVALID_HANDLE)
     {
      //--- the log is trimmed at the start: a long session cannot grow it without limit
      if(FileSize(g_dev_h)>2000000) { FileClose(g_dev_h); FileDelete(PL_DIR+"\\dev.log"); g_dev_h=FileOpen(PL_DIR+"\\dev.log",FILE_READ|FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_SHARE_READ|FILE_SHARE_WRITE); }
      if(g_dev_h!=INVALID_HANDLE) FileSeek(g_dev_h,0,SEEK_END);
     }
  }

void PlDev(const string msg)
  {
   if(g_dev_h==INVALID_HANDLE) return;
   FileWriteString(g_dev_h,(string)GetTickCount64()+" ["+_Symbol+"] "+msg+"\r\n");   // several charts write one log: the symbol says which
   FileFlush(g_dev_h);
  }

void PlDevClose()
  {
   if(g_dev_h!=INVALID_HANDLE) { FileClose(g_dev_h); g_dev_h=INVALID_HANDLE; }
  }
#define PLDBG(m) PlDev(m)
#else
void PlDevOpen() {}
void PlDevClose() {}
#define PLDBG(m)
#endif


#endif
