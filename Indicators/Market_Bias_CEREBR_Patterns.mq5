//+------------------------------------------------------------------+
//|                                         Market_Bias_CEREBR.mq5   |
//|                                  Copyright 2026, Gemini Adaptive |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Gemini Adaptive"
#property link      ""
#property version   "5.02"
#property indicator_chart_window
#property indicator_buffers 29
#property indicator_plots   6

// Plot 1: Nuvem Bullish (Alta)
#property indicator_label1  "Bullish Bias"
#property indicator_type1   DRAW_FILLING
#property indicator_color1  clrLawnGreen, clrPaleGreen

// Plot 2: Nuvem Bearish (Baixa)
#property indicator_label2  "Bearish Bias"
#property indicator_type2   DRAW_FILLING
#property indicator_color2  clrLightPink, clrMistyRose

// Plot 3: Candles Base + Candles de Baixa (4 = Preto/Engolfo, 5 = DarkGoldenrod/Estrelas, 6 = RoyalBlue/Pinbars)
#property indicator_label3  "Bias & Bear Pattern Candles"
#property indicator_type3   DRAW_COLOR_CANDLES
#property indicator_color3  clrLime, clrDarkSeaGreen, clrRed, clrLightCoral, clrBlack, clrDarkGoldenrod, clrRoyalBlue

// Plot 4: Overlay Estrela de Alta (Borda/Pavio: DarkGoldenrod, Corpo: LightYellow)
#property indicator_label4  "Star Bull Candles"
#property indicator_type4   DRAW_CANDLES
#property indicator_color4  clrDarkGoldenrod, clrLightYellow, clrDarkGoldenrod

// Plot 5: Overlay Engolfo de Alta (Borda/Pavio: Preto, Corpo: Branco)
#property indicator_label5  "Engulfing Bull Candles"
#property indicator_type5   DRAW_CANDLES
#property indicator_color5  clrBlack, clrWhite, clrBlack

// Plot 6: Overlay Pinbar de Alta (Borda/Pavio: RoyalBlue, Corpo: AliceBlue)
#property indicator_label6  "Pinbar Bull Candles"
#property indicator_type6   DRAW_CANDLES
#property indicator_color6  clrRoyalBlue, clrAliceBlue, clrRoyalBlue

// INPUTS
input group "--- HA Market Bias Settings ---"
input int      InpLen              = 100;              // Period (First Smoothing)
input int      InpLen2             = 100;              // Smoothing (Second Smoothing)
input int      InpOscLen           = 7;                // Oscillator Period

input group "--- Configurações de Alerta ---"
input bool     InpPlaySound        = true;             // Emitir alerta sonoro ao confirmar padrão

input group "--- Padrões: Estrelas (Manhã / Tarde) ---"
input bool     InpUseStars         = true;             // Ativar Estrela da Manhã / Tarde
input double   InpMinGapPoints     = 50.0;             // Tamanho mín do gap de corpo em pontos (ex: 50 ou 100)

input group "--- Padrões: Engolfo (Alta / Baixa) ---"
input bool     InpUseEngulfing     = true;             // Ativar Engolfos (Bullish / Bearish)

input group "--- Padrões: Pinbars (Martelo / Estrela Cadente) ---"
input bool     InpUsePinbars       = true;             // Ativar Martelo / Estrela Cadente
input double   InpPinShadowRatio   = 2.0;              // Razão mínima do pavio em relação ao corpo
input bool     InpStrictNoOppShadow= false;            // Exigir zero sombra oposta (rigor total clássico)

// Buffers Gráficos - Nuvens (0 a 3)
double BufBull1[], BufBull2[];
double BufBear1[], BufBear2[];

// Buffers - Plot 3 (DRAW_COLOR_CANDLES: 4 a 8)
double BufCandleOpen[];
double BufCandleHigh[];
double BufCandleLow[];
double BufCandleClose[];
double BufCandleColors[];

// Buffers - Plot 4 (DRAW_CANDLES Estrela Alta: 9 a 12)
double BufStarOverlayOpen[];
double BufStarOverlayHigh[];
double BufStarOverlayLow[];
double BufStarOverlayClose[];

// Buffers - Plot 5 (DRAW_CANDLES Engolfo Alta: 13 a 16)
double BufEngulfOverlayOpen[];
double BufEngulfOverlayHigh[];
double BufEngulfOverlayLow[];
double BufEngulfOverlayClose[];

// Buffers - Plot 6 (DRAW_CANDLES Pinbar Alta: 17 a 20)
double BufPinOverlayOpen[];
double BufPinOverlayHigh[];
double BufPinOverlayLow[];
double BufPinOverlayClose[];

// Buffers de Cálculo Interno (21 a 28)
double BufXHAOpen[], BufHAClose[];
double BufO2[], BufC2[], BufH2[], BufL2[];
double BufOscBias[], BufOscSmooth[];

// Handles das EMAs
int handleEMA_O, handleEMA_C, handleEMA_H, handleEMA_L;

// Prefixos e Variáveis de Controle
string TextPrefix = "MBC_Pattern_Text_";
datetime lastAlertTime = 0;

//+------------------------------------------------------------------+
int OnInit()
{
   SetIndexBuffer(0, BufBull1, INDICATOR_DATA);
   SetIndexBuffer(1, BufBull2, INDICATOR_DATA);
   SetIndexBuffer(2, BufBear1, INDICATOR_DATA);
   SetIndexBuffer(3, BufBear2, INDICATOR_DATA);
   
   SetIndexBuffer(4, BufCandleOpen,   INDICATOR_DATA);
   SetIndexBuffer(5, BufCandleHigh,   INDICATOR_DATA);
   SetIndexBuffer(6, BufCandleLow,    INDICATOR_DATA);
   SetIndexBuffer(7, BufCandleClose,  INDICATOR_DATA);
   SetIndexBuffer(8, BufCandleColors, INDICATOR_COLOR_INDEX);

   SetIndexBuffer(9,  BufStarOverlayOpen,  INDICATOR_DATA);
   SetIndexBuffer(10, BufStarOverlayHigh,  INDICATOR_DATA);
   SetIndexBuffer(11, BufStarOverlayLow,   INDICATOR_DATA);
   SetIndexBuffer(12, BufStarOverlayClose, INDICATOR_DATA);

   SetIndexBuffer(13, BufEngulfOverlayOpen,  INDICATOR_DATA);
   SetIndexBuffer(14, BufEngulfOverlayHigh,  INDICATOR_DATA);
   SetIndexBuffer(15, BufEngulfOverlayLow,   INDICATOR_DATA);
   SetIndexBuffer(16, BufEngulfOverlayClose, INDICATOR_DATA);

   SetIndexBuffer(17, BufPinOverlayOpen,  INDICATOR_DATA);
   SetIndexBuffer(18, BufPinOverlayHigh,  INDICATOR_DATA);
   SetIndexBuffer(19, BufPinOverlayLow,   INDICATOR_DATA);
   SetIndexBuffer(20, BufPinOverlayClose, INDICATOR_DATA);

   SetIndexBuffer(21, BufXHAOpen,   INDICATOR_CALCULATIONS);
   SetIndexBuffer(22, BufHAClose,   INDICATOR_CALCULATIONS);
   SetIndexBuffer(23, BufO2,        INDICATOR_CALCULATIONS);
   SetIndexBuffer(24, BufC2,        INDICATOR_CALCULATIONS);
   SetIndexBuffer(25, BufH2,        INDICATOR_CALCULATIONS);
   SetIndexBuffer(26, BufL2,        INDICATOR_CALCULATIONS);
   SetIndexBuffer(27, BufOscBias,   INDICATOR_CALCULATIONS);
   SetIndexBuffer(28, BufOscSmooth, INDICATOR_CALCULATIONS);

   ArraySetAsSeries(BufBull1, false);               ArraySetAsSeries(BufBull2, false);
   ArraySetAsSeries(BufBear1, false);               ArraySetAsSeries(BufBear2, false);
   ArraySetAsSeries(BufCandleOpen, false);          ArraySetAsSeries(BufCandleHigh, false);
   ArraySetAsSeries(BufCandleLow, false);           ArraySetAsSeries(BufCandleClose, false);
   ArraySetAsSeries(BufCandleColors, false);
   ArraySetAsSeries(BufStarOverlayOpen, false);     ArraySetAsSeries(BufStarOverlayHigh, false);
   ArraySetAsSeries(BufStarOverlayLow, false);      ArraySetAsSeries(BufStarOverlayClose, false);
   ArraySetAsSeries(BufEngulfOverlayOpen, false);   ArraySetAsSeries(BufEngulfOverlayHigh, false);
   ArraySetAsSeries(BufEngulfOverlayLow, false);    ArraySetAsSeries(BufEngulfOverlayClose, false);
   ArraySetAsSeries(BufPinOverlayOpen, false);      ArraySetAsSeries(BufPinOverlayHigh, false);
   ArraySetAsSeries(BufPinOverlayLow, false);       ArraySetAsSeries(BufPinOverlayClose, false);
   
   ArraySetAsSeries(BufXHAOpen, false);             ArraySetAsSeries(BufHAClose, false);
   ArraySetAsSeries(BufO2, false);                  ArraySetAsSeries(BufC2, false);
   ArraySetAsSeries(BufH2, false);                  ArraySetAsSeries(BufL2, false);
   ArraySetAsSeries(BufOscBias, false);             ArraySetAsSeries(BufOscSmooth, false);

   handleEMA_O = iMA(_Symbol, _Period, InpLen, 0, MODE_EMA, PRICE_OPEN);
   handleEMA_C = iMA(_Symbol, _Period, InpLen, 0, MODE_EMA, PRICE_CLOSE);
   handleEMA_H = iMA(_Symbol, _Period, InpLen, 0, MODE_EMA, PRICE_HIGH);
   handleEMA_L = iMA(_Symbol, _Period, InpLen, 0, MODE_EMA, PRICE_LOW);

   if(handleEMA_O == INVALID_HANDLE || handleEMA_C == INVALID_HANDLE) return(INIT_FAILED);

   IndicatorSetString(INDICATOR_SHORTNAME, "Market Bias & Candlestick Patterns");
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   ObjectsDeleteAll(0, TextPrefix);
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
   if(prev_calculated > 0) limit = prev_calculated - 3;

   double alpha2   = 2.0 / (InpLen2 + 1.0);
   double alphaOsc = 2.0 / (InpOscLen + 1.0);

   for(int i = limit; i < rates_total; i++)
   {
      // --- 1. HEIKIN ASHI BASE ---
      double haClose = (emaO[i] + emaH[i] + emaL[i] + emaC[i]) / 4.0;
      double xhaOpen = (emaO[i] + emaC[i]) / 2.0;
      
      BufHAClose[i] = haClose;
      BufXHAOpen[i] = xhaOpen;

      double haOpen = 0;
      if(i == InpLen) haOpen = xhaOpen;
      else            haOpen = (BufXHAOpen[i-1] + BufHAClose[i-1]) / 2.0;

      double haHigh = MathMax(emaH[i], MathMax(haOpen, haClose));
      double haLow  = MathMin(emaL[i], MathMin(haOpen, haClose));

      // --- 2. SEGUNDA SUAVIZAÇÃO ---
      if(i == InpLen)
      {
         BufO2[i] = haOpen;  BufC2[i] = haClose;
         BufH2[i] = haHigh;  BufL2[i] = haLow;
      }
      else
      {
         BufO2[i] = (haOpen - BufO2[i-1]) * alpha2 + BufO2[i-1];
         BufC2[i] = (haClose - BufC2[i-1]) * alpha2 + BufC2[i-1];
         BufH2[i] = (haHigh - BufH2[i-1]) * alpha2 + BufH2[i-1];
         BufL2[i] = (haLow - BufL2[i-1]) * alpha2 + BufL2[i-1];
      }

      // --- 3. OSCILADOR E ESTADOS ---
      double oscBias = 100.0 * (BufC2[i] - BufO2[i]);
      BufOscBias[i] = oscBias;

      if(i == InpLen) BufOscSmooth[i] = oscBias;
      else            BufOscSmooth[i] = (oscBias - BufOscSmooth[i-1]) * alphaOsc + BufOscSmooth[i-1];

      double oscSmooth = BufOscSmooth[i];
      
      int state = -1;
      if(oscBias > 0 && oscBias >= oscSmooth)       state = 0; 
      else if(oscBias > 0 && oscBias < oscSmooth)   state = 1; 
      else if(oscBias < 0 && oscBias <= oscSmooth)  state = 2; 
      else if(oscBias < 0 && oscBias > oscSmooth)   state = 3; 

      // --- 4. PREENCHIMENTO DO CANAL ---
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

      // --- 5. DETECÇÃO E HIGHLIGHT DE PADRÕES ---
      if(i > InpLen + 3)
      {
         // Reset Padrão da Barra Atual
         BufCandleOpen[i]   = open[i];
         BufCandleHigh[i]   = high[i];
         BufCandleLow[i]    = low[i];
         BufCandleClose[i]  = close[i];
         BufCandleColors[i] = state; 

         BufStarOverlayOpen[i]   = EMPTY_VALUE; BufStarOverlayHigh[i]   = EMPTY_VALUE;
         BufStarOverlayLow[i]    = EMPTY_VALUE; BufStarOverlayClose[i]  = EMPTY_VALUE;
         
         BufEngulfOverlayOpen[i] = EMPTY_VALUE; BufEngulfOverlayHigh[i] = EMPTY_VALUE;
         BufEngulfOverlayLow[i]  = EMPTY_VALUE; BufEngulfOverlayClose[i]= EMPTY_VALUE;

         BufPinOverlayOpen[i]    = EMPTY_VALUE; BufPinOverlayHigh[i]    = EMPTY_VALUE;
         BufPinOverlayLow[i]     = EMPTY_VALUE; BufPinOverlayClose[i]   = EMPTY_VALUE;

         bool isStarPattern   = false;
         bool isEngulfPattern = false;
         bool isPinPattern    = false;
         bool isBull          = false;
         string labelText     = "";
         int patternBarsCount = 1;

         // A) PADRÕES DE ESTRELA (MANHÃ / TARDE) - FOCO EXCLUSIVO NO GAP EM PONTOS
         if(InpUseStars)
         {
            // Estrela da Manhã (Alta)
            if(state >= 2)
            {
               bool isCandle2Bear = (close[i-2] < open[i-2]);
               bool isCandle0Bull = (close[i] > open[i]);
               
               bool gapPrev       = (MathMax(open[i-1], close[i-1]) <= MathMin(open[i-2], close[i-2]) - (InpMinGapPoints * _Point));
               bool gapNext       = (MathMin(open[i], close[i]) >= MathMax(open[i-1], close[i-1]) + (InpMinGapPoints * _Point));

               if(isCandle2Bear && isCandle0Bull && gapPrev && gapNext)
               {
                  isStarPattern = true;
                  isBull = true;
                  labelText = "Estrela da Manhã ↑";
                  patternBarsCount = 3;
               }
            }

            // Estrela da Tarde (Baixa)
            if(state <= 1 && !isStarPattern)
            {
               bool isCandle2Bull = (close[i-2] > open[i-2]);
               bool isCandle0Bear = (close[i] < open[i]);
               
               bool gapPrev       = (MathMin(open[i-1], close[i-1]) >= MathMax(open[i-2], close[i-2]) + (InpMinGapPoints * _Point));
               bool gapNext       = (MathMax(open[i], close[i]) <= MathMin(open[i-1], close[i-1]) - (InpMinGapPoints * _Point));

               if(isCandle2Bull && isCandle0Bear && gapPrev && gapNext)
               {
                  isStarPattern = true;
                  isBull = false;
                  labelText = "Estrela da Tarde ↓";
                  patternBarsCount = 3;
               }
            }
         }
         
         // B) PADRÕES DE ENGOLFO (ALTA / BAIXA) - REVISADO CONFORME DIRETRIZES
         if(InpUseEngulfing && !isStarPattern)
         {
            // Engolfo de Alta (Ocorre após fundo / tendência de baixa: state >= 2)
            if(state >= 2)
            {
               // 1º candle: pequeno corpo negro (baixa) -> close[i-1] < open[i-1]
               bool candle1Neg = (close[i-1] < open[i-1]);
               // 2º candle: corpo branco (alta) bem maior -> close[i] > open[i]
               bool candle2Pos = (close[i] > open[i]);
               
               // O corpo do segundo engolfa completamente o primeiro, com mínimas/máximas ajustadas
               bool engulfsBody = (open[i] <= close[i-1] && close[i] >= open[i-1]);
               bool strictRange = (close[i] > open[i-1] && open[i] < close[i-1]); // corpo engolfando estritamente

               if(candle1Neg && candle2Pos && (engulfsBody || strictRange))
               {
                  isEngulfPattern = true;
                  isBull = true;
                  labelText = "Engolfo de Alta ↑";
                  patternBarsCount = 2;
               }
            }

            // Engolfo de Baixa (Ocorre após topo / tendência de alta: state <= 1)
            if(state <= 1 && !isStarPattern && !isEngulfPattern)
            {
               // 1º candle: corpo de alta e pequeno -> close[i-1] > open[i-1]
               bool candle1Pos = (close[i-1] > open[i-1]);
               // 2º candle: de baixa e mais alongado -> close[i] < open[i]
               bool candle2Neg = (close[i] < open[i]);
               
               // Abre com preço acima e fecha com preço abaixo do anterior, cobrindo-o
               bool engulfsBody = (open[i] >= close[i-1] && close[i] <= open[i-1]);
               bool strictRange = (close[i] < open[i-1] && open[i] > close[i-1]);

               if(candle1Pos && candle2Neg && (engulfsBody || strictRange))
               {
                  isEngulfPattern = true;
                  isBull = false;
                  labelText = "Engolfo de Baixa ↓";
                  patternBarsCount = 2;
               }
            }
         }

         // C) PADRÕES DE PINBAR (MARTELO / ESTRELA CADENTE / ENFORCADO)
         if(InpUsePinbars && !isStarPattern && !isEngulfPattern)
         {
            double body = MathAbs(close[i] - open[i]);
            if(body == 0) body = _Point; 

            double upperShadow = high[i] - MathMax(open[i], close[i]);
            double lowerShadow = MathMin(open[i], close[i]) - low[i];

            if(state >= 2)
            {
               bool validLowerShadow = InpStrictNoOppShadow ? (upperShadow <= _Point * 2) : (upperShadow < lowerShadow);
               bool validUpperShadow = InpStrictNoOppShadow ? (lowerShadow <= _Point * 2) : (lowerShadow < upperShadow);

               if(lowerShadow >= body * InpPinShadowRatio && validLowerShadow)
               {
                  isPinPattern = true;
                  isBull = true;
                  labelText = "Martelo ↑";
                  patternBarsCount = 1;
               }
               else if(upperShadow >= body * InpPinShadowRatio && validUpperShadow)
               {
                  isPinPattern = true;
                  isBull = true;
                  labelText = "Martelo Invertido ↑";
                  patternBarsCount = 1;
               }
            }

            if(state <= 1 && !isPinPattern)
            {
               bool hasInsignificantLower = InpStrictNoOppShadow ? (lowerShadow <= 0.0) : (lowerShadow <= body * 0.3);

               if(upperShadow >= body * InpPinShadowRatio && hasInsignificantLower)
               {
                  isPinPattern = true;
                  isBull = false;
                  labelText = "Estrela Cadente ↓";
                  patternBarsCount = 1;
               }
               else if(lowerShadow >= body * InpPinShadowRatio && lowerShadow > upperShadow)
               {
                  isPinPattern = true;
                  isBull = false;
                  labelText = "Enforcado ↓";
                  patternBarsCount = 1;
               }
            }
         }
         
         // D) RENDERING DE CORES E TEXTOS
         if(isStarPattern || isEngulfPattern || isPinPattern)
         {
            color labelColor = clrBlack;
            if(isStarPattern) labelColor = clrDarkGoldenrod;
            if(isPinPattern)  labelColor = clrRoyalBlue;

            for(int k = i - (patternBarsCount - 1); k <= i; k++)
            {
               BufStarOverlayOpen[k]   = EMPTY_VALUE; BufStarOverlayHigh[k]   = EMPTY_VALUE;
               BufStarOverlayLow[k]    = EMPTY_VALUE; BufStarOverlayClose[k]  = EMPTY_VALUE;
               BufEngulfOverlayOpen[k] = EMPTY_VALUE; BufEngulfOverlayHigh[k] = EMPTY_VALUE;
               BufEngulfOverlayLow[k]  = EMPTY_VALUE; BufEngulfOverlayClose[k]= EMPTY_VALUE;
               BufPinOverlayOpen[k]    = EMPTY_VALUE; BufPinOverlayHigh[k]    = EMPTY_VALUE;
               BufPinOverlayLow[k]     = EMPTY_VALUE; BufPinOverlayClose[k]   = EMPTY_VALUE;

               if(isStarPattern)
               {
                  if(close[k] >= open[k])
                  {
                     BufStarOverlayOpen[k]  = open[k];
                     BufStarOverlayHigh[k]  = high[k];
                     BufStarOverlayLow[k]   = low[k];
                     BufStarOverlayClose[k] = close[k];

                     BufCandleOpen[k]       = EMPTY_VALUE;
                     BufCandleHigh[k]       = EMPTY_VALUE;
                     BufCandleLow[k]        = EMPTY_VALUE;
                     BufCandleClose[k]      = EMPTY_VALUE;
                  }
                  else
                  {
                     BufCandleColors[k]     = 5;
                     BufCandleOpen[k]       = open[k];
                     BufCandleHigh[k]       = high[k];
                     BufCandleLow[k]        = low[k];
                     BufCandleClose[k]      = close[k];
                  }
               }
               else if(isEngulfPattern)
               {
                  if(close[k] >= open[k])
                  {
                     BufEngulfOverlayOpen[k]  = open[k];
                     BufEngulfOverlayHigh[k]  = high[k];
                     BufEngulfOverlayLow[k]   = low[k];
                     BufEngulfOverlayClose[k] = close[k];

                     BufCandleOpen[k]         = EMPTY_VALUE;
                     BufCandleHigh[k]         = EMPTY_VALUE;
                     BufCandleLow[k]          = EMPTY_VALUE;
                     BufCandleClose[k]        = EMPTY_VALUE;
                  }
                  else
                  {
                     BufCandleColors[k]       = 4;
                     BufCandleOpen[k]         = open[k];
                     BufCandleHigh[k]         = high[k];
                     BufCandleLow[k]          = low[k];
                     BufCandleClose[k]        = close[k];
                  }
               }
               else if(isPinPattern)
               {
                  if(close[k] >= open[k])
                  {
                     BufPinOverlayOpen[k]   = open[k];
                     BufPinOverlayHigh[k]   = high[k];
                     BufPinOverlayLow[k]    = low[k];
                     BufPinOverlayClose[k]  = close[k];

                     BufCandleOpen[k]       = EMPTY_VALUE;
                     BufCandleHigh[k]       = EMPTY_VALUE;
                     BufCandleLow[k]        = EMPTY_VALUE;
                     BufCandleClose[k]      = EMPTY_VALUE;
                  }
                  else
                  {
                     BufCandleColors[k]     = 6;
                     BufCandleOpen[k]       = open[k];
                     BufCandleHigh[k]       = high[k];
                     BufCandleLow[k]        = low[k];
                     BufCandleClose[k]      = close[k];
                  }
               }
            }

            // CRIAÇÃO DO TEXTO DO RÓTULO COM SETAS
            string objName = TextPrefix + IntegerToString(time[i]);
            double range = (high[i] - low[i]);
            if(range == 0) range = _Point * 20;

            if(isBull)
            {
               double textPrice = low[i] - (range * 0.4);
               if(ObjectFind(0, objName) < 0)
               {
                  ObjectCreate(0, objName, OBJ_TEXT, 0, time[i], textPrice);
                  ObjectSetString(0, objName, OBJPROP_TEXT, labelText);
                  ObjectSetInteger(0, objName, OBJPROP_COLOR, labelColor);
                  ObjectSetInteger(0, objName, OBJPROP_FONTSIZE, 9);
                  ObjectSetString(0, objName, OBJPROP_FONT, "Arial");
                  ObjectSetInteger(0, objName, OBJPROP_ANCHOR, ANCHOR_UPPER);
               }
            }
            else
            {
               double textPrice = high[i] + (range * 0.4);
               if(ObjectFind(0, objName) < 0)
               {
                  ObjectCreate(0, objName, OBJ_TEXT, 0, time[i], textPrice);
                  ObjectSetString(0, objName, OBJPROP_TEXT, labelText);
                  ObjectSetInteger(0, objName, OBJPROP_COLOR, labelColor);
                  ObjectSetInteger(0, objName, OBJPROP_FONTSIZE, 9);
                  ObjectSetString(0, objName, OBJPROP_FONT, "Arial");
                  ObjectSetInteger(0, objName, OBJPROP_ANCHOR, ANCHOR_LOWER);
               }
            }

            // ALERTA SONORO
            if(InpPlaySound && i < rates_total - 1)
            {
               ENUM_SYMBOL_TRADE_MODE tradeMode = (ENUM_SYMBOL_TRADE_MODE)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE);
               if(tradeMode == SYMBOL_TRADE_MODE_FULL && time[i] > lastAlertTime && i == rates_total - 2)
               {
                  PlaySound("alert.wav");
                  lastAlertTime = time[i];
               }
            }
         }
      }
      else
      {
         BufCandleOpen[i]   = EMPTY_VALUE; BufCandleHigh[i]   = EMPTY_VALUE;
         BufCandleLow[i]    = EMPTY_VALUE; BufCandleClose[i]  = EMPTY_VALUE;
         BufCandleColors[i] = EMPTY_VALUE;

         BufStarOverlayOpen[i]   = EMPTY_VALUE; BufStarOverlayHigh[i]   = EMPTY_VALUE;
         BufStarOverlayLow[i]    = EMPTY_VALUE; BufStarOverlayClose[i]  = EMPTY_VALUE;

         BufEngulfOverlayOpen[i] = EMPTY_VALUE; BufEngulfOverlayHigh[i] = EMPTY_VALUE;
         BufEngulfOverlayLow[i]  = EMPTY_VALUE; BufEngulfOverlayClose[i]= EMPTY_VALUE;

         BufPinOverlayOpen[i]    = EMPTY_VALUE; BufPinOverlayHigh[i]    = EMPTY_VALUE;
         BufPinOverlayLow[i]     = EMPTY_VALUE; BufPinOverlayClose[i]   = EMPTY_VALUE;
      }
   }

   return(rates_total);
}


