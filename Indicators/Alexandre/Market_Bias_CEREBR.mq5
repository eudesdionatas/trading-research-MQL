//+------------------------------------------------------------------+
//|                                         Market_Bias_CEREBR.mq5   |
//|                                  Copyright 2026, Gemini Adaptive |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Gemini Adaptive"
#property link      ""
#property version   "2.10"
#property indicator_chart_window
#property indicator_buffers 18
#property indicator_plots   3

// Plot 1: Nuvem Bullish (Alta)
// Se BufBull1 > BufBull2 (Forte) = Lime. Se BufBull1 < BufBull2 (Fraca) = DarkSeaGreen
#property indicator_label1  "Bullish Bias"
#property indicator_type1   DRAW_FILLING
#property indicator_color1  clrLawnGreen, clrPaleGreen

// Plot 2: Nuvem Bearish (Baixa)
// Se BufBear1 > BufBear2 (Forte) = Red. Se BufBear1 < BufBear2 (Fraca) = LightCoral
#property indicator_label2  "Bearish Bias"
#property indicator_type2   DRAW_FILLING
#property indicator_color2  clrLightPink, clrMistyRose

// Plot 3: Candles Customizados (Com atraso de 1 barra)
#property indicator_label3  "Bias Candles"
#property indicator_type3   DRAW_COLOR_CANDLES
#property indicator_color3  clrLime, clrDarkSeaGreen, clrRed, clrLightCoral

// INPUTS
input group "HA Market Bias Settings"
input int      InpLen         = 100;    // Period (First Smoothing)
input int      InpLen2        = 100;    // Smoothing (Second Smoothing)
input int      InpOscLen      = 7;      // Oscillator Period

// Buffers Gráficos para Preenchimento (4 Buffers)
double BufBull1[], BufBull2[];
double BufBear1[], BufBear2[];

// Buffers para o DRAW_COLOR_CANDLES (5 Buffers: OHLC + Cores)
double BufCandleOpen[];
double BufCandleHigh[];
double BufCandleLow[];
double BufCandleClose[];
double BufCandleColors[];

// Buffers de Cálculo Interno e Memória
double BufXHAOpen[], BufHAClose[];
double BufO2[], BufC2[], BufH2[], BufL2[];
double BufOscBias[], BufOscSmooth[];
double BufState[]; // Guarda o estado do canal para o delay

// Handles das EMAs Nativas
int handleEMA_O, handleEMA_C, handleEMA_H, handleEMA_L;

//+------------------------------------------------------------------+
int OnInit()
{
   // Vinculação de Buffers de Plotagem das Nuvens (0 a 3)
   SetIndexBuffer(0, BufBull1, INDICATOR_DATA);
   SetIndexBuffer(1, BufBull2, INDICATOR_DATA);
   SetIndexBuffer(2, BufBear1, INDICATOR_DATA);
   SetIndexBuffer(3, BufBear2, INDICATOR_DATA);
   
   // Vinculação de Buffers de Plotagem dos Candles (4 a 8)
   SetIndexBuffer(4, BufCandleOpen,   INDICATOR_DATA);
   SetIndexBuffer(5, BufCandleHigh,   INDICATOR_DATA);
   SetIndexBuffer(6, BufCandleLow,    INDICATOR_DATA);
   SetIndexBuffer(7, BufCandleClose,  INDICATOR_DATA);
   SetIndexBuffer(8, BufCandleColors, INDICATOR_COLOR_INDEX);
   
   // Vinculação de Buffers de Cálculo Interno (9 a 17)
   SetIndexBuffer(9,  BufXHAOpen,   INDICATOR_CALCULATIONS);
   SetIndexBuffer(10, BufHAClose,   INDICATOR_CALCULATIONS);
   SetIndexBuffer(11, BufO2,        INDICATOR_CALCULATIONS);
   SetIndexBuffer(12, BufC2,        INDICATOR_CALCULATIONS);
   SetIndexBuffer(13, BufH2,        INDICATOR_CALCULATIONS);
   SetIndexBuffer(14, BufL2,        INDICATOR_CALCULATIONS);
   SetIndexBuffer(15, BufOscBias,   INDICATOR_CALCULATIONS);
   SetIndexBuffer(16, BufOscSmooth, INDICATOR_CALCULATIONS);
   SetIndexBuffer(17, BufState,     INDICATOR_CALCULATIONS);

   // Configuração de Series (Passado -> Presente)
   ArraySetAsSeries(BufBull1, false);        ArraySetAsSeries(BufBull2, false);
   ArraySetAsSeries(BufBear1, false);        ArraySetAsSeries(BufBear2, false);
   ArraySetAsSeries(BufCandleOpen, false);   ArraySetAsSeries(BufCandleHigh, false);
   ArraySetAsSeries(BufCandleLow, false);    ArraySetAsSeries(BufCandleClose, false);
   ArraySetAsSeries(BufCandleColors, false);
   
   ArraySetAsSeries(BufXHAOpen, false);      ArraySetAsSeries(BufHAClose, false);
   ArraySetAsSeries(BufO2, false);           ArraySetAsSeries(BufC2, false);
   ArraySetAsSeries(BufH2, false);           ArraySetAsSeries(BufL2, false);
   ArraySetAsSeries(BufOscBias, false);      ArraySetAsSeries(BufOscSmooth, false);
   ArraySetAsSeries(BufState, false);

   // EMAs Base
   handleEMA_O = iMA(_Symbol, _Period, InpLen, 0, MODE_EMA, PRICE_OPEN);
   handleEMA_C = iMA(_Symbol, _Period, InpLen, 0, MODE_EMA, PRICE_CLOSE);
   handleEMA_H = iMA(_Symbol, _Period, InpLen, 0, MODE_EMA, PRICE_HIGH);
   handleEMA_L = iMA(_Symbol, _Period, InpLen, 0, MODE_EMA, PRICE_LOW);

   if(handleEMA_O == INVALID_HANDLE || handleEMA_C == INVALID_HANDLE) return(INIT_FAILED);

   IndicatorSetString(INDICATOR_SHORTNAME, "Market Bias Channel & Candles");
   return(INIT_SUCCEEDED);
}

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
   if(rates_total < InpLen + 5) return(0);

   double emaO[], emaC[], emaH[], emaL[];
   if(CopyBuffer(handleEMA_O, 0, 0, rates_total, emaO) <= 0) return(0);
   if(CopyBuffer(handleEMA_C, 0, 0, rates_total, emaC) <= 0) return(0);
   if(CopyBuffer(handleEMA_H, 0, 0, rates_total, emaH) <= 0) return(0);
   if(CopyBuffer(handleEMA_L, 0, 0, rates_total, emaL) <= 0) return(0);

   int limit = prev_calculated - 1;
   if(limit < InpLen) limit = InpLen;
   if(prev_calculated > 0) limit = prev_calculated - 2;

   double alpha2   = 2.0 / (InpLen2 + 1.0);
   double alphaOsc = 2.0 / (InpOscLen + 1.0);

   for(int i = limit; i < rates_total; i++)
   {
      // --- 1. CONSTRUÇÃO DO HEIKIN ASHI BASE ---
      double haClose = (emaO[i] + emaH[i] + emaL[i] + emaC[i]) / 4.0;
      double xhaOpen = (emaO[i] + emaC[i]) / 2.0;
      
      BufHAClose[i] = haClose;
      BufXHAOpen[i] = xhaOpen;

      double haOpen = 0;
      if(i == InpLen) haOpen = xhaOpen;
      else            haOpen = (BufXHAOpen[i-1] + BufHAClose[i-1]) / 2.0;

      double haHigh = MathMax(emaH[i], MathMax(haOpen, haClose));
      double haLow  = MathMin(emaL[i], MathMin(haOpen, haClose));

      // --- 2. SEGUNDA SUAVIZAÇÃO (EMA DOS CANDLES HA) ---
      if(i == InpLen)
      {
         BufO2[i] = haOpen;
         BufC2[i] = haClose;
         BufH2[i] = haHigh;
         BufL2[i] = haLow;
      }
      else
      {
         BufO2[i] = (haOpen - BufO2[i-1]) * alpha2 + BufO2[i-1];
         BufC2[i] = (haClose - BufC2[i-1]) * alpha2 + BufC2[i-1];
         BufH2[i] = (haHigh - BufH2[i-1]) * alpha2 + BufH2[i-1];
         BufL2[i] = (haLow - BufL2[i-1]) * alpha2 + BufL2[i-1];
      }

      // --- 3. CÁLCULO DO OSCILADOR E ESTADOS DE VIÉS ---
      double oscBias = 100.0 * (BufC2[i] - BufO2[i]);
      BufOscBias[i] = oscBias;

      if(i == InpLen) BufOscSmooth[i] = oscBias;
      else            BufOscSmooth[i] = (oscBias - BufOscSmooth[i-1]) * alphaOsc + BufOscSmooth[i-1];

      double oscSmooth = BufOscSmooth[i];
      
      // Estado de viés (0 = Bull Strong, 1 = Bull Weak, 2 = Bear Strong, 3 = Bear Weak)
      int state = -1;
      if(oscBias > 0 && oscBias >= oscSmooth)       state = 0; 
      else if(oscBias > 0 && oscBias < oscSmooth)   state = 1; 
      else if(oscBias < 0 && oscBias <= oscSmooth)  state = 2; 
      else if(oscBias < 0 && oscBias > oscSmooth)   state = 3; 

      BufState[i] = state; // Guarda o estado atual na memória

      // --- 4. PREENCHIMENTO DO CANAL (DRAW_FILLING) ---
      BufBull1[i] = EMPTY_VALUE; BufBull2[i] = EMPTY_VALUE;
      BufBear1[i] = EMPTY_VALUE; BufBear2[i] = EMPTY_VALUE;

      double h2 = BufH2[i];
      double l2 = BufL2[i];

      if(state == 0 || state == 1)
      {
         BufBull1[i] = (state == 0) ? h2 : l2;
         BufBull2[i] = (state == 0) ? l2 : h2;
         
         if(i > InpLen && BufBull1[i-1] == EMPTY_VALUE)
         {
            BufBull1[i-1] = (state == 0) ? BufH2[i-1] : BufL2[i-1];
            BufBull2[i-1] = (state == 0) ? BufL2[i-1] : BufH2[i-1];
         }
      }
      else if(state == 2 || state == 3)
      {
         BufBear1[i] = (state == 2) ? h2 : l2;
         BufBear2[i] = (state == 2) ? l2 : h2;
         
         if(i > InpLen && BufBear1[i-1] == EMPTY_VALUE)
         {
            BufBear1[i-1] = (state == 2) ? BufH2[i-1] : BufL2[i-1];
            BufBear2[i-1] = (state == 2) ? BufL2[i-1] : BufH2[i-1];
         }
      }

      // --- 5. COLORIZAÇÃO DOS CANDLES (COM ATRASO DE 1 BARRA) ---
      if(i > InpLen + 1)
      {
         BufCandleOpen[i]   = open[i];
         BufCandleHigh[i]   = high[i];
         BufCandleLow[i]    = low[i];
         BufCandleClose[i]  = close[i];
         
         // Aplica a cor equivalente ao estado do canal na barra anterior (i-1)
         BufCandleColors[i] = BufState[i-1]; 
      }
      else
      {
         // Mantém invisível durante o aquecimento das médias
         BufCandleOpen[i]   = EMPTY_VALUE;
         BufCandleHigh[i]   = EMPTY_VALUE;
         BufCandleLow[i]    = EMPTY_VALUE;
         BufCandleClose[i]  = EMPTY_VALUE;
         BufCandleColors[i] = EMPTY_VALUE;
      }
   }

   return(rates_total);
}