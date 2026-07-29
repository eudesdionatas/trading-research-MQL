//+------------------------------------------------------------------+
//|                                           Stochastic_Alert_15M.mq5|
//|                                  Copyright 2026, Personal AI     |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026"
#property link      "https://www.mql5.com"
#property version   "3.00"

#property indicator_chart_window
#property indicator_buffers 5
#property indicator_plots   1

// Configuração da Plotagem de Candles Coloridos
#property indicator_label1  "Stoch Candles"
#property indicator_type1   DRAW_COLOR_CANDLES

// Paleta de Cores:
// [0] = Cor padrão/neutra da plataforma (sem alteração)
// [1] = Sobrevenda (< 20): Borda clrLimeGreen / Corpo de alta clrHoneydew ou baixa clrLimeGreen
// [2] = Sobrecompra (> 80): Borda C'0,82,130' / Corpo de alta C'158,210,253' ou baixa C'0,82,130'
#property indicator_color1  clrNONE,clrLimeGreen,C'0,82,130'

// --- Parâmetros de Entrada ---
input group "=== Configurações do Estocástico (M15) ==="
input int    InpKPeriod     = 5;     
input int    InpDPeriod     = 3;     
input int    InpSlowing     = 3;     
input ENUM_MA_METHOD InpMAMethod = MODE_SMA; 
input ENUM_STO_PRICE InpPriceField = STO_LOWHIGH; 

// --- Buffers Globais ---
double OpenBuffer[];
double HighBuffer[];
double LowBuffer[];
double CloseBuffer[];
double ColorBuffer[];

// --- Variáveis Globais ---
int    stochHandle;
datetime lastAlertTime;

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
{
   SetIndexBuffer(0, OpenBuffer, INDICATOR_DATA);
   SetIndexBuffer(1, HighBuffer, INDICATOR_DATA);
   SetIndexBuffer(2, LowBuffer, INDICATOR_DATA);
   SetIndexBuffer(3, CloseBuffer, INDICATOR_DATA);
   SetIndexBuffer(4, ColorBuffer, INDICATOR_COLOR_INDEX);

   PlotIndexSetInteger(0, PLOT_DRAW_BEGIN, 0);
   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, 0);

   stochHandle = iStochastic(_Symbol, PERIOD_M15, InpKPeriod, InpDPeriod, InpSlowing, InpMAMethod, InpPriceField);
   if(stochHandle == INVALID_HANDLE)
   {
      Print("Erro ao criar o handle do indicador iStochastic.");
      return(INIT_FAILED);
   }

   lastAlertTime = 0;
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Custom indicator iteration function                              |
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
   if(rates_total < MathMax(InpKPeriod, InpDPeriod) + 10)
      return(0);

   int start = (prev_calculated > 0) ? prev_calculated - 1 : 0;
   
   double k_values[];
   double d_values[];
   
   ArraySetAsSeries(k_values, true);
   ArraySetAsSeries(d_values, true);
   
   int copied = CopyBuffer(stochHandle, 0, 0, rates_total - start, k_values);
   int copied2 = CopyBuffer(stochHandle, 1, 0, rates_total - start, d_values);
   
   if(copied <= 0 || copied2 <= 0)
      return(prev_calculated);

   for(int i = rates_total - 1 - start; i >= 0; i--)
   {
      // Copia os preços de forma obrigatória para desenhar todos os candles normalmente
      OpenBuffer[i]  = open[i];
      HighBuffer[i]  = high[i];
      LowBuffer[i]   = low[i];
      CloseBuffer[i] = close[i];

      double k = k_values[i];
      double d = d_values[i];
      
      double k_prev = (i + 1 < rates_total) ? k_values[i + 1] : k;
      double d_prev = (i + 1 < rates_total) ? d_values[i + 1] : d;
      
      // Por padrão, o candle fica neutro (sem sobrescrever a cor padrão do terminal)
      ColorBuffer[i] = 0; 

      // Condição 1: Acima de 80 (%D cruza abaixo de %K)
      if(k > 80 && d > 80)
      {
         if(d_prev >= k_prev && d < k)
         {
            ColorBuffer[i] = 2; // Aciona o índice de sobrecompra
            
            if(i == 0 && time[0] != lastAlertTime)
            {
               PlaySound("alert.wav");
               lastAlertTime = time[0];
            }
         }
      }
      // Condição 2: Abaixo de 20 (%D cruza acima de %K)
      else if(k < 20 && d < 20)
      {
         if(d_prev <= k_prev && d > k)
         {
            ColorBuffer[i] = 1; // Aciona o índice de sobrevenda
            
            if(i == 0 && time[0] != lastAlertTime)
            {
               PlaySound("alert.wav");
               lastAlertTime = time[0];
            }
         }
      }
   }

   return(rates_total);
}
//+------------------------------------------------------------------+