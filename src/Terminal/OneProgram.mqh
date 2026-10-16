// Required Notice: Copyright 2026 stop-loss-enjoyer
// Plainlines is source-available under the PolyForm Shield License 1.0.0.
//
// One Plainlines per terminal. The free Plainlines and Plainlines Pro share the data folder, settings.dat and the magic of the
// positions, so two of them on one terminal would both manage the same positions. A program that sees the other one on a
// chart of the terminal (CHART_EXPERT_NAME of every chart) does not trade and does not manage positions; the reason is
// PL_R_OTHER_PLAINLINES, a right of the program like Algo Trading being off (PlRightsReason). The builds of one kind (the
// release, the demo and the dev build of the same product) do not count as the other one: they were never exclusive.
// The charts are looked at at most once a second, and only when something asks for the rights.
#property strict

#ifndef PL_TERMINAL_ONEPROGRAM_MQH
#define PL_TERMINAL_ONEPROGRAM_MQH

bool  g_one_other=false;    // the other Plainlines was on a chart at the last look
ulong g_one_t=0;            // when the charts were last looked at

//--- the program name of a chart is the other Plainlines: the free one looks for Pro, Pro looks for the free one
bool PlNameIsOtherPlainlines(const string nm)
  {
   return (StringFind(nm,"PlainlinesPro",0)==0);
  }

//--- true while the other Plainlines is on a chart of this terminal. Only an expert advisor looks (a script such as the
//--- development flatten closes positions whatever stands on the charts), and not the strategy tester (it has one chart).
bool PlOtherPlainlines()
  {
   if(MQLInfoInteger(MQL_PROGRAM_TYPE)!=PROGRAM_EXPERT || MQLInfoInteger(MQL_TESTER)) return false;
   const ulong now=GetTickCount64();
   if(g_one_t!=0 && now-g_one_t<1000) return g_one_other;
   g_one_t=now;
   bool other=false;
   long id=ChartFirst();
   while(id>=0)
     {
      if(PlNameIsOtherPlainlines(ChartGetString(id,CHART_EXPERT_NAME))) { other=true; break; }
      id=ChartNext(id);
     }
   if(other!=g_one_other) { PLDBG(other?"ONE the other Plainlines is on a chart: this one does not trade":"ONE the other Plainlines is gone"); }
   g_one_other=other;
   return other;
  }

#endif
