// Required Notice: Copyright 2026 stop-loss-enjoyer
// Plainlines is source-available under the PolyForm Shield License 1.0.0.
//
// Trade sounds: a short soft sound when a position of Plainlines opens and another one when it
// closes (by SL, TP, the terminal's own button or the panel), told apart by the sign of the result. The WAV
// files live in src/Sounds/ and are built into the .ex5 with #resource in the
// main file, so nothing is read from disk at run time. The sound is one recorded key press of a mechanical
// keyboard (a CC0 recording, named under Credits in the README): open as recorded, a win a little lower, a loss
// lowest. Each file starts with 450 ms of silence, because a laptop sound card asleep after a quiet spell wakes
// too late for a click and the first one was lost. The synthesised clicks before it were not heard (too short and
// quiet), sounded like a note, a cartoon bonk or plastic. The sound is switched off
// in the menu, Look, Sounds. The terminal's own trade sound (Tools, Options, Events) cannot be read from MQL5
// and is not ours to switch off: it plays on its own.
#property strict

#ifndef PL_UI_SOUND_MQH
#define PL_UI_SOUND_MQH

#define PL_SND_OPEN        "::Sounds\\PlOpen.wav"
#define PL_SND_CLOSE_WIN   "::Sounds\\PlCloseWin.wav"
#define PL_SND_CLOSE_LOSS  "::Sounds\\PlCloseLoss.wav"
#define PL_SND_GAP_MS      300            // several parts of one trade, several deals at once: one sound

ulong g_snd_last=0;                       // GetTickCount64() of the last sound of this chart

//--- is the position behind this deal one of ours: the deal's magic, a record of the position, or the magic of its opening deal
bool PlSoundMine(const ulong deal,const ulong pos_id)
  {
   if(HistoryDealGetInteger(deal,DEAL_MAGIC)==g_cfg.magic) return true;
   if(pos_id==0) return false;
   if(PlRecIndex(pos_id)>=0) return true;
   if(!HistorySelectByPosition(pos_id)) return false;
   for(int i=0;i<HistoryDealsTotal();i++)
     {
      const ulong tk=HistoryDealGetTicket(i);
      if(tk==0) continue;
      if(HistoryDealGetInteger(tk,DEAL_ENTRY)==DEAL_ENTRY_IN && HistoryDealGetInteger(tk,DEAL_MAGIC)==g_cfg.magic) return true;
     }
   return false;
  }

//--- several charts with the panel hear one sound: the deal ticket is claimed in a terminal-wide temporary variable
bool PlSoundClaim(const ulong deal)
  {
   const string k="PL.snd.deal";
   if(!GlobalVariableCheck(k)) GlobalVariableTemp(k);          // created with 0; a second Set here could overwrite another chart's claim
   const double old=GlobalVariableGet(k);
   if(old==(double)deal) return false;
   return GlobalVariableSetOnCondition(k,(double)deal,old);
  }

//--- called for every new deal (TRADE_TRANSACTION_DEAL_ADD)
void PlSoundDeal(const ulong deal)
  {
   if(!g_cfg.sounds || deal==0) return;
   if(!HistoryDealSelect(deal))
     {
      if(!HistorySelect(TimeCurrent()-3600,TimeCurrent()+86400) || !HistoryDealSelect(deal)) return;
     }
   const long dtype=HistoryDealGetInteger(deal,DEAL_TYPE);
   if(dtype!=DEAL_TYPE_BUY && dtype!=DEAL_TYPE_SELL) return;                     // balance, credit, charges
   const long entry=HistoryDealGetInteger(deal,DEAL_ENTRY);
   const bool opens=(entry==DEAL_ENTRY_IN || entry==DEAL_ENTRY_INOUT);
   const bool closes=(entry==DEAL_ENTRY_OUT || entry==DEAL_ENTRY_OUT_BY);
   if(!opens && !closes) return;
   const ulong pos_id=(ulong)HistoryDealGetInteger(deal,DEAL_POSITION_ID);
   const double result=HistoryDealGetDouble(deal,DEAL_PROFIT)+HistoryDealGetDouble(deal,DEAL_SWAP)
                       +HistoryDealGetDouble(deal,DEAL_COMMISSION)+HistoryDealGetDouble(deal,DEAL_FEE);
   if(!PlSoundMine(deal,pos_id)) return;
   const ulong now=GetTickCount64();
   if(g_snd_last!=0 && now-g_snd_last<PL_SND_GAP_MS) return;
   if(!PlSoundClaim(deal)) return;
   g_snd_last=now;
   const string snd=opens?PL_SND_OPEN:(result>=0.0?PL_SND_CLOSE_WIN:PL_SND_CLOSE_LOSS);
   const bool ok=PlaySound(snd);
   PLDBG("SOUND "+(opens?"open":(result>=0.0?"close win":"close loss"))+" deal="+(string)deal+" pos="+(string)pos_id+" result="+DoubleToString(result,2)+" played="+(string)ok);
  }

#endif
