// Required Notice: Copyright 2026 stop-loss-enjoyer
// Plainlines is source-available under the PolyForm Shield License 1.0.0.
//
// Colors (light and dark), automatic theme from the chart background, scale from the DPI.
#property strict

#ifndef PL_UI_THEME_MQH
#define PL_UI_THEME_MQH

struct PlTheme
  {
   bool              dark;
   color             bg;          // panel body
   color             surface;     // fields, result block, segments
   color             hover;       // hovered flat button
   color             text;
   color             text2;       // secondary text
   color             line;        // dividers
   color             border;      // dividers of buttons and boxes, ghost buttons
   color             field_border; // the outline of an input field: clearer than border, a field is where the trader types
   color             frame;       // the outline of the panel itself
   color             accent;      // one accent: text links, dots and icons
   color             accent_fill; // selected segment, switches, "on" button: white text stays at 4.5:1
   color             on_accent;
   color             buy;
   color             buy_fill;    // the Buy button
   color             sell;
   color             sell_fill;   // the Sell button and the armed close box
   color             warn;        // the amber button and dot
   color             warn_text;   // amber text on the panel
   color             ok;
   color             dis_bg;      // disabled action button
   color             dis_text;
  };

PlTheme g_th;

bool PlChartIsDark()
  {
   color c=(color)ChartGetInteger(0,CHART_COLOR_BACKGROUND);
   int r=(int)(c&0xFF), g=(int)((c>>8)&0xFF), b=(int)((c>>16)&0xFF);
   double lum=(0.299*r+0.587*g+0.114*b)/255.0;
   return (lum<0.5);
  }

//--- mode 0 Auto, 1 Light, 2 Dark
void PlThemeApply(const int mode)
  {
   bool dark=(mode==2) || (mode==0 && PlChartIsDark());
   g_th.dark=dark;
   if(!dark)
     {
      g_th.bg=C'255,255,255';       g_th.surface=C'246,247,249';  g_th.hover=C'236,239,243';
      g_th.text=C'31,35,40';        g_th.text2=C'107,114,128';
      g_th.line=C'229,231,235';     g_th.border=C'208,213,220';
      g_th.field_border=C'136,145,158'; g_th.frame=C'176,184,196';
      g_th.accent=C'31,111,235';    g_th.accent_fill=C'31,111,235';    g_th.on_accent=C'255,255,255';
      g_th.buy=C'31,111,235';       g_th.buy_fill=C'31,111,235';
      g_th.sell=C'209,36,47';       g_th.sell_fill=C'209,36,47';
      g_th.warn=C'191,135,0';       g_th.warn_text=C'154,103,0';       g_th.ok=C'26,127,55';
      g_th.dis_bg=C'209,214,222';   g_th.dis_text=C'51,60,76';
     }
   else
     {
      g_th.bg=C'22,24,29';          g_th.surface=C'31,34,41';     g_th.hover=C'44,48,57';
      g_th.text=C'230,232,235';     g_th.text2=C'154,161,172';
      g_th.line=C'45,49,58';        g_th.border=C'58,63,74';
      g_th.field_border=C'100,108,122'; g_th.frame=C'58,63,74';
      g_th.accent=C'76,141,246';    g_th.accent_fill=C'52,110,214';    g_th.on_accent=C'255,255,255';
      g_th.buy=C'76,141,246';       g_th.buy_fill=C'52,110,214';
      g_th.sell=C'240,97,109';      g_th.sell_fill=C'200,52,64';
      g_th.warn=C'212,167,44';      g_th.warn_text=C'212,167,44';      g_th.ok=C'63,185,80';
      g_th.dis_bg=C'58,63,75';      g_th.dis_text=C'196,202,211';
     }
  }

//--- mode 0 Auto (DPI), 1 100, 2 125, 3 150
double PlScaleGet(const int mode)
  {
   if(mode==1) return 1.0;
   if(mode==2) return 1.25;
   if(mode==3) return 1.5;
   int dpi=(int)TerminalInfoInteger(TERMINAL_SCREEN_DPI);
   if(dpi<=0) dpi=96;
   double s=dpi/96.0;
   if(s<0.75) s=0.75;
   if(s>3.0) s=3.0;
   return s;
  }

uint PlArgb(const color c,const int alpha=255)
  {
   return ColorToARGB(c,(uchar)alpha);
  }

//--- mix two colors, t=0 gives a, t=1 gives b
color PlMix(const color a,const color b,const double t)
  {
   int ar=(int)(a&0xFF), ag=(int)((a>>8)&0xFF), ab=(int)((a>>16)&0xFF);
   int br=(int)(b&0xFF), bg=(int)((b>>8)&0xFF), bb=(int)((b>>16)&0xFF);
   int r=(int)MathRound(ar+(br-ar)*t), g=(int)MathRound(ag+(bg-ag)*t), bl=(int)MathRound(ab+(bb-ab)*t);
   return (color)(r|(g<<8)|(bl<<16));
  }

#endif
