// Fixture: clean file. Comments mention WebRequest, SendMail, #import, OrderSend, __DATE__.
/* block comment: SocketCreate FILE_COMMON FileCopy
   still a comment: SendNotification SendFTP CTrade */
#property version "0.0.1"
#include <Controls\Dialog.mqh>
#include <Trade\SymbolInfo.mqh>
#include "local.mqh"

string note = "WebRequest and OrderSend are only words in this string";
int mySendMailFlag = 0;   // not the SendMail function
int OnInit() { return(INIT_SUCCEEDED); }
