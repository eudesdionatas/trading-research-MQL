//+------------------------------------------------------------------+
//|         Boleta_Acoes_Com_Painel_v1.67.mq5                        |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026"
#property version   "1.67"
#property strict

#include <Trade\Trade.mqh>
CTrade trade;

//--- Enumerador para a seleção da proporção percentual de risco/gain
enum ENUM_RISK_RATIO
{
   RATIO_1_1_PCT = 1, // 1% Loss / 1% Gain (1:1)
   RATIO_2_2_PCT = 2, // 2% Loss / 2% Gain (2:2)
   RATIO_3_3_PCT = 3, // 3% Loss / 3% Gain (3:3)
   RATIO_1_2_PCT = 4, // 1% Loss / 2% Gain (1:2)
   RATIO_1_3_PCT = 5  // 1% Loss / 3% Gain (1:3)
};

//--- Parâmetros de Entrada
input group "--- Configurações Operacionais (Ações) ---"
input int               InpLotSize         = 100;         // Tamanho do Lote (Ex: 100 para lote padrão, ou 1 para fracionário)
input ENUM_RISK_RATIO   InpRiskRewardRatio = RATIO_1_1_PCT; // Proporção Percentual de Risco/Gain
input int               InpMaxNegociosDia  = 3;           // Máximo de Negócios por Dia (Máx de Ordens = Negócios * 2)

const string PREFIX_OBJ = "Proj_";
const string PREFIX_TXT = "Painel_";
const string LABEL_PRECO_POSICAO = "LABEL_PRECO_POSICAO";

// Variáveis de controle de estado
bool operacaoPendente = false;
int  tipoOperacao = 0; // 1 = Compra, 2 = Venda
string globalMensagemStatus = "(C) Compra | (V) Venda | (Enter) Envia | (CTRL+Enter) Zera";
bool posicaoEstavaAberta = false; 

// Variáveis das métricas do dia
double maiorAmplitudeGlobal = 0.0; 
string horarioMaiorCandle = "";    
int    totalCandlesDoDia = 0;      

int OnInit()
{
   EventSetMillisecondTimer(50);

   for(int i=0; i<10; i++) ObjectDelete(0, PREFIX_TXT+IntegerToString(i));

   Print("==========================================================");
   Print("[SISTEMA PRONTO] Boleta de Ações carregada no ativo: ", _Symbol);
   Print("==========================================================");

   ProcessarRotinasDeAtualizacao();
   ChartRedraw(0);
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   ApagarLinhasProjecao();
   Comment("");
   
   ObjectDelete(0, LABEL_PRECO_POSICAO);
   for(int i=0; i<10; i++) ObjectDelete(0, PREFIX_TXT+IntegerToString(i));
   Print("[INFO] Robô descarregado do gráfico.");
}

void OnTick() 
{
   ProcessarRotinasDeAtualizacao();
}

void OnTimer()
{
   ProcessarRotinasDeAtualizacao();
}

void ProcessarRotinasDeAtualizacao()
{
   CalcularMetricasDoDia();

   if(operacaoPendente)
   {
      AtualizarLinhasCustomizadas();
   }

   AtualizarPainelVisualEmTempoReal();
}

void OnChartEvent(const int id, const long& lparam, const double& dparam, const string& sparam)
{
   if(id == CHARTEVENT_CHART_CHANGE)
   {
      AtualizarLabelGraficoPreco("", clrNONE, false);
      ProcessarRotinasDeAtualizacao(); 
   }
   
   if(id == CHARTEVENT_KEYDOWN)
   {
      int tecla = (int)lparam;
      int maxOrdensPermitidas = InpMaxNegociosDia * 2;
      int operacoesFeitasHoje = CalcularOperacoesDoDia();

      if(operacoesFeitasHoje >= maxOrdensPermitidas)
      {
         globalMensagemStatus = "Limite de ordens atingido! Basta por hoje.";
         ApagarLinhasProjecao();
         return;
      }

      if(tecla == 67 || tecla == 99) // Tecla 'C'
      {
         operacaoPendente = true;
         tipoOperacao = 1;
         AtualizarLinhasCustomizadas();
         globalMensagemStatus = "Modo compra ativo! (ENTER) Envia | (ESC) Cancela";
      }
      else if(tecla == 86 || tecla == 118) // Tecla 'V'
      {
         operacaoPendente = true;
         tipoOperacao = 2;
         AtualizarLinhasCustomizadas();
         globalMensagemStatus = "Modo venda ativo! (ENTER) Envia | (ESC) Cancela";
      }
      else if(tecla == 13) // Tecla 'ENTER'
      {
         if(operacaoPendente)
         {
            EnviarOrdemMercado();
         }
         else
         {
            bool ctrlPressionado = (TerminalInfoInteger(TERMINAL_KEYSTATE_CONTROL) < 0);
            if(ctrlPressionado)
            {
               FecharPosicaoAberta();
            }
         }
      }
      else if(tecla == 27) // Tecla 'ESC'
      {
         ApagarLinhasProjecao();
         globalMensagemStatus = "Cancelado. Pressione (C) Compra | (V) Venda";
      }
   }
}

double ArredondarParaPassoDoPreco(double preco)
{
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickSize <= 0) return preco;
   return MathRound(preco / tickSize) * tickSize;
}

void ObterPercentuaisRisco(double &pctSL, double &pctTP)
{
   switch(InpRiskRewardRatio)
   {
      case RATIO_1_1_PCT: pctSL = 0.01; pctTP = 0.01; break;
      case RATIO_2_2_PCT: pctSL = 0.02; pctTP = 0.02; break;
      case RATIO_3_3_PCT: pctSL = 0.03; pctTP = 0.03; break;
      case RATIO_1_2_PCT: pctSL = 0.01; pctTP = 0.02; break;
      case RATIO_1_3_PCT: pctSL = 0.01; pctTP = 0.03; break;
      default:            pctSL = 0.01; pctTP = 0.02; break;
   }
}

string ObterTextoProporcaoRisco()
{
   switch(InpRiskRewardRatio)
   {
      case RATIO_1_1_PCT: return "1%:1%";
      case RATIO_2_2_PCT: return "2%:2%";
      case RATIO_3_3_PCT: return "3%:3%";
      case RATIO_1_2_PCT: return "1%:2%";
      case RATIO_1_3_PCT: return "1%:3%";
      default:            return "1%:2%";
   }
}

void EnviarOrdemMercado()
{
   int maxOrdensPermitidas = InpMaxNegociosDia * 2;
   if(CalcularOperacoesDoDia() >= maxOrdensPermitidas)
   {
      globalMensagemStatus = "Limite de ordens atingido! Basta por hoje.";
      ApagarLinhasProjecao();
      return;
   }

   double pctSL, pctTP;
   ObterPercentuaisRisco(pctSL, pctTP);

   if(tipoOperacao == 1) 
   {
      double precoCompra = NormalizeDouble(SymbolInfoDouble(_Symbol, SYMBOL_ASK), _Digits);
      double slCompra    = ArredondarParaPassoDoPreco(precoCompra * (1.0 - pctSL));
      double tpCompra    = ArredondarParaPassoDoPreco(precoCompra * (1.0 + pctTP));
      trade.Buy(InpLotSize, _Symbol, precoCompra, slCompra, tpCompra, "Compra % Dinâmica");
   }
   else if(tipoOperacao == 2) 
   {
      double precoVenda = NormalizeDouble(SymbolInfoDouble(_Symbol, SYMBOL_BID), _Digits);
      double slVenda    = ArredondarParaPassoDoPreco(precoVenda * (1.0 + pctSL));
      double tpVenda    = ArredondarParaPassoDoPreco(precoVenda * (1.0 - pctTP));
      trade.Sell(InpLotSize, _Symbol, precoVenda, slVenda, tpVenda, "Venda % Dinâmica");
   }

   ApagarLinhasProjecao();
   globalMensagemStatus = "Ordem enviada! Pressione (ESC) para cancelar";
}

void VerificarResultadoETocarSomSaida()
{
   datetime inicioDoDia = iTime(_Symbol, PERIOD_D1, 0);
   HistorySelect(inicioDoDia, TimeCurrent());
   int totalDeals = HistoryDealsTotal();

   double ultimoLucro = 0.0;
   bool encontrouDealSaida = false;

   for(int i = totalDeals - 1; i >= 0; i--)
   {
      ulong ticketDeal = HistoryDealGetTicket(i);
      if(ticketDeal > 0)
      {
         if(HistoryDealGetString(ticketDeal, DEAL_SYMBOL) == _Symbol)
         {
            long entradaDeal = HistoryDealGetInteger(ticketDeal, DEAL_ENTRY);
            if(entradaDeal == DEAL_ENTRY_OUT || entradaDeal == DEAL_ENTRY_INOUT)
            {
               double lucro    = HistoryDealGetDouble(ticketDeal, DEAL_PROFIT);
               double swap     = HistoryDealGetDouble(ticketDeal, DEAL_SWAP);
               double comissao = HistoryDealGetDouble(ticketDeal, DEAL_COMMISSION);
               
               ultimoLucro = lucro + swap + comissao;
               encontrouDealSaida = true;
               break;
            }
         }
      }
   }

   if(encontrouDealSaida && ultimoLucro > 0.0)
   {
      if(!PlaySound("gain.wav")) PlaySound("\\Audio\\gain.wav");
   }
   else
   {
      if(!PlaySound("stops.wav")) PlaySound("\\Audio\\stops.wav");
   }
}

void FecharPosicaoAberta()
{
   if(PositionSelect(_Symbol)) 
   {
      if(trade.PositionClose(_Symbol))
      {
         VerificarResultadoETocarSomSaida();
         globalMensagemStatus = "(C) Compra | (V) Venda | (Enter) Envia | (CTRL+Enter) Zera";
         posicaoEstavaAberta = false;
      }
   }
   else
   {
      globalMensagemStatus = "Nenhuma posição aberta";
   }
}

void CalcularMetricasDoDia()
{
   datetime inicioDoDia = iTime(_Symbol, PERIOD_D1, 0);
   if(inicioDoDia == 0) return; 

   MqlRates barras[];
   ArraySetAsSeries(barras, false); 
   int barrasCopiadas = CopyRates(_Symbol, _Period, inicioDoDia, TimeCurrent(), barras);
   
   if(barrasCopiadas > 0)
   {
      totalCandlesDoDia = barrasCopiadas;
      double maiorAmplitude = 0.0;
      datetime dataHoraCandle = 0;
      
      for(int i = 0; i < barrasCopiadas; i++)
      {
         MqlDateTime dt;
         TimeToStruct(barras[i].time, dt);
         if(dt.hour == 10 && dt.min == 0) continue;
         
         double amplitude = barras[i].high - barras[i].low;
         if(amplitude > maiorAmplitude) 
         {
            maiorAmplitude = amplitude;
            dataHoraCandle = barras[i].time;
         }
      }
      
      maiorAmplitudeGlobal = NormalizeDouble(maiorAmplitude, 2);
      horarioMaiorCandle = TimeToString(dataHoraCandle, TIME_MINUTES);
   }
}

double CalcularResultadoFinanceiroDoDia()
{
   datetime inicioDoDia = iTime(_Symbol, PERIOD_D1, 0);
   double lucroTotalDia = 0.0;

   HistorySelect(inicioDoDia, TimeCurrent());
   int totalDeals = HistoryDealsTotal();

   for(int i = 0; i < totalDeals; i++)
   {
      ulong ticketDeal = HistoryDealGetTicket(i);
      if(ticketDeal > 0)
      {
         if(HistoryDealGetString(ticketDeal, DEAL_SYMBOL) == _Symbol)
         {
            lucroTotalDia += (HistoryDealGetDouble(ticketDeal, DEAL_PROFIT) + HistoryDealGetDouble(ticketDeal, DEAL_SWAP) + HistoryDealGetDouble(ticketDeal, DEAL_COMMISSION));
         }
      }
   }

   // ADICIONADO: Soma o PnL flutuante da posição aberta no cálculo diário em tempo real
   if(PositionSelect(_Symbol))
   {
      lucroTotalDia += (PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP) + PositionGetDouble(POSITION_COMMISSION));
   }

   return lucroTotalDia;
}

int CalcularOperacoesDoDia()
{
   datetime inicioDoDia = iTime(_Symbol, PERIOD_D1, 0);
   int totalOps = 0;

   HistorySelect(inicioDoDia, TimeCurrent());
   int totalDeals = HistoryDealsTotal();

   for(int i = 0; i < totalDeals; i++)
   {
      ulong ticketDeal = HistoryDealGetTicket(i);
      if(ticketDeal > 0)
      {
         if(HistoryDealGetString(ticketDeal, DEAL_SYMBOL) == _Symbol)
         {
            long entradaDeal = HistoryDealGetInteger(ticketDeal, DEAL_ENTRY);
            if(entradaDeal == DEAL_ENTRY_IN || entradaDeal == DEAL_ENTRY_OUT || entradaDeal == DEAL_ENTRY_INOUT)
               totalOps++;
         }
      }
   }
   return totalOps;
}

datetime ObterInicioDoMes()
{
   MqlDateTime dt;
   TimeCurrent(dt);
   dt.day = 1; dt.hour = 0; dt.min = 0; dt.sec = 0;
   return StructToTime(dt);
}

double CalcularResultadoFinanceiroDoMes()
{
   datetime inicioDoMes = ObterInicioDoMes();
   double lucroTotalMes = 0.0;

   HistorySelect(inicioDoMes, TimeCurrent());
   int totalDeals = HistoryDealsTotal();

   for(int i = 0; i < totalDeals; i++)
   {
      ulong ticketDeal = HistoryDealGetTicket(i);
      if(ticketDeal > 0)
      {
         if(HistoryDealGetString(ticketDeal, DEAL_SYMBOL) == _Symbol)
         {
            lucroTotalMes += (HistoryDealGetDouble(ticketDeal, DEAL_PROFIT) + HistoryDealGetDouble(ticketDeal, DEAL_SWAP) + HistoryDealGetDouble(ticketDeal, DEAL_COMMISSION));
         }
      }
   }

   // Opcional: Adiciona também no mensal caso deseje o reflexo em tempo real no mês
   if(PositionSelect(_Symbol))
   {
      lucroTotalMes += (PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP) + PositionGetDouble(POSITION_COMMISSION));
   }

   return lucroTotalMes;
}

int CalcularOperacoesDoMes()
{
   datetime inicioDoMes = ObterInicioDoMes();
   int totalOpsMes = 0;

   HistorySelect(inicioDoMes, TimeCurrent());
   int totalDeals = HistoryDealsTotal();

   for(int i = 0; i < totalDeals; i++)
   {
      ulong ticketDeal = HistoryDealGetTicket(i);
      if(ticketDeal > 0)
      {
         if(HistoryDealGetString(ticketDeal, DEAL_SYMBOL) == _Symbol)
         {
            long entradaDeal = HistoryDealGetInteger(ticketDeal, DEAL_ENTRY);
            if(entradaDeal == DEAL_ENTRY_IN || entradaDeal == DEAL_ENTRY_OUT || entradaDeal == DEAL_ENTRY_INOUT)
               totalOpsMes++;
         }
      }
   }
   return totalOpsMes;
}

void DefaultAtualizarLinhasCustomizadas()
{
   double pctSL, pctTP;
   ObterPercentuaisRisco(pctSL, pctTP);

   double precoReferencia = 0;
   double slProjetado = 0;
   double tpProjetado = 0;
   color corEntrada = clrNONE;

   if(tipoOperacao == 1) 
   {
      precoReferencia = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      slProjetado     = ArredondarParaPassoDoPreco(precoReferencia * (1.0 - pctSL));
      tpProjetado     = ArredondarParaPassoDoPreco(precoReferencia * (1.0 + pctTP));
      corEntrada      = clrDodgerBlue;
   }
   else if(tipoOperacao == 2) 
   {
      precoReferencia = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      slProjetado     = ArredondarParaPassoDoPreco(precoReferencia * (1.0 + pctSL));
      tpProjetado     = ArredondarParaPassoDoPreco(precoReferencia * (1.0 - pctTP));
      corEntrada      = clrCrimson;
   }

   if(precoReferencia <= 0) return;

   DesenharLinhaH(PREFIX_OBJ+"Entrada", precoReferencia, corEntrada, STYLE_SOLID, 2);
   DesenharLinhaH(PREFIX_OBJ+"Loss",    slProjetado, clrRed, STYLE_DOT, 1);
   DesenharLinhaH(PREFIX_OBJ+"Gain",    tpProjetado, clrLimeGreen, STYLE_DOT, 1);
   ChartRedraw(0);
}

void AtualizarLinhasCustomizadas() { DefaultAtualizarLinhasCustomizadas(); }

void AtualizarLabelGraficoPreco(string texto = "", color cor = clrNONE, bool atualizarTexto = false)
{
   if(!PositionSelect(_Symbol))
   {
      ObjectDelete(0, LABEL_PRECO_POSICAO);
      return;
   }

   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(_Symbol, _Period, 0, 1, rates) < 1) return;

   int x = 0, y = 0;
   if(ChartTimePriceToXY(ChartID(), 0, rates[0].time, rates[0].close, x, y))
   {
      string textoFinal = texto;
      color corFinal = cor;

      if(!atualizarTexto && ObjectFind(0, LABEL_PRECO_POSICAO) >= 0)
      {
         textoFinal = ObjectGetString(0, LABEL_PRECO_POSICAO, OBJPROP_TEXT);
         corFinal = (color)ObjectGetInteger(0, LABEL_PRECO_POSICAO, OBJPROP_COLOR);
      }

      long larguraGrafico = ChartGetInteger(ChartID(), CHART_WIDTH_IN_PIXELS);
      int margemEscalaPrecos = 75; 
      int posXDesejada = (int)(larguraGrafico - margemEscalaPrecos);
      int posXFinal = (x < posXDesejada) ? x + 40 : posXDesejada;
      int posYFinal = y - 18; 

      CriarTextoLabelGrafico(LABEL_PRECO_POSICAO, textoFinal, posXFinal, posYFinal, 9, corFinal);
   }
}

void CriarTextoLabelGrafico(string nome, string texto, int x, int y, int tamanhoFonte, color cor)
{
   if(ObjectFind(0, nome) < 0)
   {
      ObjectCreate(0, nome, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, nome, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, nome, OBJPROP_SELECTABLE, false);
   }
   
   ObjectSetString(0, nome, OBJPROP_TEXT, texto);
   ObjectSetInteger(0, nome, OBJPROP_XDISTANCE, x); 
   ObjectSetInteger(0, nome, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, nome, OBJPROP_FONTSIZE, tamanhoFonte);
   ObjectSetInteger(0, nome, OBJPROP_COLOR, cor);
   ObjectSetString(0, nome, OBJPROP_FONT, "Arial Black");
}

ENUM_BASE_CORNER ObterMelhorCantoPainel()
{
   double precoMaximoVisivel = ChartGetDouble(ChartID(), CHART_PRICE_MAX);
   double precoMinimoVisivel = ChartGetDouble(ChartID(), CHART_PRICE_MIN);
   
   if(precoMaximoVisivel <= precoMinimoVisivel) return CORNER_RIGHT_UPPER;

   double amplitude = precoMaximoVisivel - precoMinimoVisivel;
   double linhaCorteTopo = precoMaximoVisivel - (amplitude * 0.30);
   int totalVisiveis = (int)ChartGetInteger(ChartID(), CHART_VISIBLE_BARS);
   if(totalVisiveis <= 0) return CORNER_RIGHT_UPPER;

   int limiteAvaliacao = (int)MathMax(1, totalVisiveis * 0.35);
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   
   int copied = CopyRates(_Symbol, _Period, 0, limiteAvaliacao, rates);
   if(copied > 0)
   {
      for(int i = 0; i < copied; i++)
      {
         if(rates[i].high >= linhaCorteTopo) return CORNER_RIGHT_LOWER; 
      }
   }
   return CORNER_RIGHT_UPPER; 
}

void AtualizarPainelVisualEmTempoReal()
{
   double pctSL, pctTP;
   ObterPercentuaisRisco(pctSL, pctTP);
   
   double precoReferenciaAtual = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double exSL = ArredondarParaPassoDoPreco(precoReferenciaAtual * pctSL);
   double exTP = ArredondarParaPassoDoPreco(precoReferenciaAtual * pctTP);
   
   int margemDireita = 400;  
   ENUM_BASE_CORNER cantoPainel = ObterMelhorCantoPainel();

   string textoPnLPainel = StringFormat("Posição (0 %s)", _Symbol);
   color corPnL = clrSilver;

   int maxOrdensPermitidas = InpMaxNegociosDia * 2;
   int operacoesFeitasHoje = CalcularOperacoesDoDia();
   color corStatus = clrDarkSlateGray;

   if(operacoesFeitasHoje >= maxOrdensPermitidas)
   {
      globalMensagemStatus = "Basta por hoje";
      corStatus = clrBlack;
      ApagarLinhasProjecao();
   }
   else
   {
      if(globalMensagemStatus == "Basta por hoje" && !PositionSelect(_Symbol))
      {
         globalMensagemStatus = "(C) Compra | (V) Venda | (Enter) Envia | (CTRL+Enter) Zera";
      }
   }

   if(PositionSelect(_Symbol))
   {
      posicaoEstavaAberta = true; 
      if(operacoesFeitasHoje < maxOrdensPermitidas)
         globalMensagemStatus = "Ordem executada! (CTRL + Enter) para Zerar";

      long tipoPos = PositionGetInteger(POSITION_TYPE);
      double precoAberturaPos = PositionGetDouble(POSITION_PRICE_OPEN);
      double lucroFinanceiro = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP) + PositionGetDouble(POSITION_COMMISSION);
      
      string tipoStr = (tipoPos == POSITION_TYPE_BUY) ? "Compra" : "Venda";
      int volumePos = (int)PositionGetDouble(POSITION_VOLUME);
      
      string valorFormatado = DoubleToString(lucroFinanceiro, 2);
      StringReplace(valorFormatado, ".", ",");
      
      textoPnLPainel = StringFormat("(%s: %d %s) | PnL: R$ %s", tipoStr, volumePos, _Symbol, valorFormatado);
      
      if(lucroFinanceiro > 0.0) corPnL = clrLimeGreen;
      else if(lucroFinanceiro < 0.0) corPnL = clrRed;
      else corPnL = clrSilver;
   
      string textoLabel = StringFormat("R$ %s", valorFormatado);
      AtualizarLabelGraficoPreco(textoLabel, corPnL, true);
   }
   else
   {
      if(posicaoEstavaAberta)
      {
         VerificarResultadoETocarSomSaida();
         if(operacoesFeitasHoje < maxOrdensPermitidas)
            globalMensagemStatus = "(C) Compra | (V) Venda | (Enter) Envia | (CTRL+Enter) Zera";
         posicaoEstavaAberta = false;
      }
      ObjectDelete(0, LABEL_PRECO_POSICAO);
   }

   double totalDoDia = CalcularResultadoFinanceiroDoDia();
   string strTotalDia = DoubleToString(totalDoDia, 2);
   StringReplace(strTotalDia, ".", ",");

   string textoTotalDia = StringFormat("PnL Diário: R$ %s | Operações: %d/%d", strTotalDia, operacoesFeitasHoje, maxOrdensPermitidas);
   color corTotalDia = (totalDoDia > 0.0) ? clrLimeGreen : ((totalDoDia < 0.0) ? clrRed : clrSilver);

   double totalDoMes = CalcularResultadoFinanceiroDoMes();
   int totalOperacoesMes = CalcularOperacoesDoMes();
   string strTotalMes = DoubleToString(totalDoMes, 2);
   StringReplace(strTotalMes, ".", ",");

   string textoTotalMes = StringFormat("PnL Mensal: R$ %s | Operações: %d", strTotalMes, totalOperacoesMes);
   color corTotalMes = (totalDoMes > 0.0) ? clrLimeGreen : ((totalDoMes < 0.0) ? clrRed : clrSilver);

   if(cantoPainel == CORNER_RIGHT_LOWER)
   {
      CriarTextoLabel(PREFIX_TXT+"0", textoPnLPainel, margemDireita, 130, 9, corPnL, cantoPainel);
      CriarTextoLabel(PREFIX_TXT+"1", "-----------------------------------------------------------------------------------------", margemDireita, 117, 9, clrSilver, cantoPainel);
      CriarTextoLabel(PREFIX_TXT+"2", "Maior candle do dia (Var): R$ " + DoubleToString(maiorAmplitudeGlobal, 2) + " | Horário: " + horarioMaiorCandle, margemDireita, 103, 9, clrOrangeRed, cantoPainel); 
      CriarTextoLabel(PREFIX_TXT+"3", "Total de candles do dia: " + IntegerToString(totalCandlesDoDia), margemDireita, 88, 9, clrSteelBlue, cantoPainel);
      CriarTextoLabel(PREFIX_TXT+"4", "Alvos (" + ObterTextoProporcaoRisco() + "): SL = R$ " + DoubleToString(exSL, 2) + " | TP = R$ " + DoubleToString(exTP, 2), margemDireita, 73, 9, clrSteelBlue, cantoPainel);
      CriarTextoLabel(PREFIX_TXT+"7", textoTotalMes, margemDireita, 58, 9, corTotalMes, cantoPainel);
      CriarTextoLabel(PREFIX_TXT+"6", textoTotalDia, margemDireita, 43, 9, corTotalDia, cantoPainel);
      CriarTextoLabel(PREFIX_TXT+"5", globalMensagemStatus, margemDireita, 28, 9, corStatus, cantoPainel);
   }
   else
   {
      CriarTextoLabel(PREFIX_TXT+"5", globalMensagemStatus, margemDireita, 20, 9, corStatus, cantoPainel);
      CriarTextoLabel(PREFIX_TXT+"6", textoTotalDia, margemDireita, 35, 9, corTotalDia, cantoPainel);
      CriarTextoLabel(PREFIX_TXT+"7", textoTotalMes, margemDireita, 50, 9, corTotalMes, cantoPainel);
      CriarTextoLabel(PREFIX_TXT+"2", "Maior candle do dia (Var): R$ " + DoubleToString(maiorAmplitudeGlobal, 2) + " | Horário: " + horarioMaiorCandle, margemDireita, 65, 9, clrOrangeRed, cantoPainel); 
      CriarTextoLabel(PREFIX_TXT+"3", "Total de candles do dia: " + IntegerToString(totalCandlesDoDia), margemDireita, 80, 9, clrSteelBlue, cantoPainel);
      CriarTextoLabel(PREFIX_TXT+"4", "Alvos (" + ObterTextoProporcaoRisco() + "): SL = R$ " + DoubleToString(exSL, 2) + " | TP = R$ " + DoubleToString(exTP, 2), margemDireita, 95, 9, clrSteelBlue, cantoPainel);
      CriarTextoLabel(PREFIX_TXT+"1", "-----------------------------------------------------------------------------------------", margemDireita, 108, 9, clrSilver, cantoPainel);
      CriarTextoLabel(PREFIX_TXT+"0", textoPnLPainel, margemDireita, 121, 9, corPnL, cantoPainel);
   }
   
   ChartRedraw(0);
}

void CriarTextoLabel(string nome, string texto, int x, int y, int tamanhoFonte, color cor, ENUM_BASE_CORNER canto = CORNER_RIGHT_UPPER)
{
   if(ObjectFind(0, nome) < 0)
   {
      ObjectCreate(0, nome, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, nome, OBJPROP_SELECTABLE, false);
   }
   
   ObjectSetInteger(0, nome, OBJPROP_CORNER, canto);
   ObjectSetString(0, nome, OBJPROP_TEXT, texto);
   ObjectSetInteger(0, nome, OBJPROP_XDISTANCE, x); 
   ObjectSetInteger(0, nome, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, nome, OBJPROP_FONTSIZE, tamanhoFonte);
   ObjectSetInteger(0, nome, OBJPROP_COLOR, cor);
   ObjectSetString(0, nome, OBJPROP_FONT, "Arial Black");
   ObjectSetInteger(0, nome, OBJPROP_BACK, true);
}

void DesenharLinhaH(string nome, double preco, color cor, ENUM_LINE_STYLE estilo, int largura)
{
   if(ObjectFind(0, nome) >= 0) ObjectDelete(0, nome);

   ObjectCreate(0, nome, OBJ_HLINE, 0, 0, preco);
   ObjectSetInteger(0, nome, OBJPROP_COLOR, cor);
   ObjectSetInteger(0, nome, OBJPROP_STYLE, estilo);
   ObjectSetInteger(0, nome, OBJPROP_WIDTH, largura);
   ObjectSetInteger(0, nome, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, nome, OBJPROP_BACK, true);
}

void ApagarLinhasProjecao()
{
   operacaoPendente = false;
   tipoOperacao = 0;
   ObjectDelete(0, PREFIX_OBJ+"Entrada");
   ObjectDelete(0, PREFIX_OBJ+"Loss");
   ObjectDelete(0, PREFIX_OBJ+"Gain");
   ChartRedraw(0);
}