//+------------------------------------------------------------------+
//|                                  IndicadorEstocasticoM15.mq5     |
//|                                  Copyright 2026, Seu Nome        |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026"
#property link      "https://www.mql5.com"
#property version   "4.02"
#property indicator_chart_window
#property indicator_buffers 5
#property indicator_plots   1

// Definição do Plot de Candles Coloridos
#property indicator_type1   DRAW_COLOR_CANDLES
#property indicator_color1  C'0,82,130',C'158,210,253',clrLimeGreen,C'180,255,180'
#property indicator_width1  2

double BufferOpen[];
double BufferHigh[];
double BufferLow[];
double BufferClose[];
double BufferColors[];

input group "Configurações do Estocástico (M15)"
input int    InpKPeriod = 5;       
input int    InpDPeriod = 3;       
input int    InpSlowing = 3;       
input ENUM_MA_METHOD InpMAMethod = MODE_SMA; 
input ENUM_STO_PRICE InpPriceField = STO_LOWHIGH; 

int handle_m15;
datetime last_alert_time = 0;

//+------------------------------------------------------------------+
//| Initialization                                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   SetIndexBuffer(0, BufferOpen, INDICATOR_DATA);
   SetIndexBuffer(1, BufferHigh, INDICATOR_DATA);
   SetIndexBuffer(2, BufferLow, INDICATOR_DATA);
   SetIndexBuffer(3, BufferClose, INDICATOR_DATA);
   SetIndexBuffer(4, BufferColors, INDICATOR_COLOR_INDEX);

   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetString(0, PLOT_LABEL, "Open;High;Low;Close");

   handle_m15 = iStochastic(_Symbol, PERIOD_M15, InpKPeriod, InpDPeriod, InpSlowing, InpMAMethod, InpPriceField);

   if(handle_m15 == INVALID_HANDLE)
   {
      Print("Erro ao criar handle do indicador Estocástico M15.");
      return(INIT_FAILED);
   }

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Iteration                                                        |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
   if(rates_total < 50) return(0);

   int limit = prev_calculated - 1;
   if(limit < 0) limit = 0;
   int start = rates_total - 1 - limit;
   if(start >= rates_total - 1) start = rates_total - 2;

   // Pega a quantidade total de barras disponíveis no M15 para dimensionar os arrays com segurança
   int m15_bars = Bars(_Symbol, PERIOD_M15);
   if(m15_bars <= 0) return(0);

   double k_m15[], d_m15[];
   datetime time_m15[];
   ArraySetAsSeries(k_m15, true); 
   ArraySetAsSeries(d_m15, true);
   ArraySetAsSeries(time_m15, true);

   CopyBuffer(handle_m15, 0, 0, m15_bars, k_m15);
   CopyBuffer(handle_m15, 1, 0, m15_bars, d_m15);
   CopyTime(_Symbol, PERIOD_M15, 0, m15_bars, time_m15);

   // Preenche o histórico base de preços no gráfico atual
   for(int i = start; i >= 0 && !IsStopped(); i--)
   {
      BufferOpen[i]   = open[i];
      BufferHigh[i]   = high[i];
      BufferLow[i]    = low[i];
      BufferClose[i]  = close[i];
      BufferColors[i] = EMPTY_VALUE; 
   }

   // --- VERIFICAÇÃO E PROPAGAÇÃO DE SINAIS PARA QUALQUER TIMEFRAME (M1, M5, M10, M15) ---
   for(int i = start; i >= 0 && !IsStopped(); i--)
   {
      // Descobre qual é o índice do M15 correspondente ao tempo do candle atual do gráfico aberto
      int idx_m15 = iBarShift(_Symbol, PERIOD_M15, time[i]);

      if(idx_m15 < 0 || idx_m15 + 1 >= m15_bars) continue;

      // Regras de sinal baseadas estritamente no timeframe de 15 minutos
      bool acima_80_m15     = (k_m15[idx_m15] > 80 && d_m15[idx_m15] > 80);
      bool cruzou_baixo_m15 = (k_m15[idx_m15+1] >= d_m15[idx_m15+1] && k_m15[idx_m15] < d_m15[idx_m15]);

      bool abaixo_20_m15    = (k_m15[idx_m15] < 20 && d_m15[idx_m15] < 20);
      bool cruzou_cima_m15  = (k_m15[idx_m15+1] <= d_m15[idx_m15+1] && k_m15[idx_m15] > d_m15[idx_m15]);

      bool sinal_venda  = (acima_80_m15 && cruzou_baixo_m15);
      bool sinal_compra = (abaixo_20_m15 && cruzou_cima_m15);

      if(sinal_venda)
      {
         // Aplica a cor de venda para o candle atual do gráfico (independente se é M1, M5, M10 ou M15)
         BufferColors[i] = (close[i] >= open[i]) ? 1.0 : 0.0; 

         // Dispara o alerta sonoro apenas se estivermos na barra mais recente do M15
         datetime m15_bar_time = iTime(_Symbol, PERIOD_M15, 0);
         if(time[i] >= m15_bar_time && TimeCurrent() != last_alert_time)
         {
            PlaySound("alert.wav");
            last_alert_time = TimeCurrent();
         }
      }
      else if(sinal_compra)
      {
         // Aplica a cor de compra para o candle atual do gráfico
         BufferColors[i] = (close[i] >= open[i]) ? 3.0 : 2.0; 

         datetime m15_bar_time = iTime(_Symbol, PERIOD_M15, 0);
         if(time[i] >= m15_bar_time && TimeCurrent() != last_alert_time)
         {
            PlaySound("alert.wav");
            last_alert_time = TimeCurrent();
         }
      }
   }

   return(rates_total);
}
//+------------------------------------------------------------------+