//+------------------------------------------------------------------+
//|         Boleta_Indice_Com_Painel_v3.07.mq5                       |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026"
#property version   "3.07"
#property strict

#include <Trade\Trade.mqh>
CTrade trade;

//--- Parâmetros de Entrada
input group "--- Configurações Operacionais ---"
input int               InpFaseInicial       = 1;           // Fase Inicial do Trader (1 a 10)
input int               InpNegociosDiaInicial = 3;           // Negócios (pares C/V) permitidos por dia - deve ser ímpar

const string PREFIX_OBJ = "Proj_";
const string PREFIX_TXT = "Painel_";
const string LABEL_PRECO_POSICAO = "LABEL_PRECO_POSICAO";

// Variáveis globais de controle de estado e fases
int  faseAtual = 1;
bool operacaoPendente = false;
int  tipoOperacao = 0; // 1 = Compra, 2 = Venda
string globalMensagemStatus = "(C) Compra | (V) Venda | (Enter) Envia | (CTRL+Enter) Zera";
bool posicaoEstavaAberta = false;

// Controle do som de saída (gain/stop): o fechamento de uma posição (manual ou por SL/TP)
// nem sempre aparece imediatamente em HistoryDealsTotal() no mesmo tick em que a posição
// já deixou de existir - por isso o som é tocado de forma assíncrona, com retentativas,
// e sempre casado com o ticket exato da posição (POSITION_IDENTIFIER), nunca com "o último
// deal do símbolo" (que poderia pertencer a outra operação).
ulong ultimoTicketPosicaoAberta = 0;
double ultimoLucroFlutuantePosicao = 0.0; // fallback: último P&L flutuante conhecido, caso o histórico não sincronize a tempo
bool  aguardandoSomSaida = false;
int   tentativasSomSaida = 0;
const int MAX_TENTATIVAS_SOM_SAIDA = 60; // ~60 * 50ms = 3 segundos antes de usar o fallback

// Variável de controle do canto do painel (Padrão: Superior Direito)
ENUM_BASE_CORNER cantoPainelAtual = CORNER_RIGHT_UPPER;

// Variáveis das métricas do dia
double maiorAmplitudeGlobal = 0.0;
string horarioMaiorCandle = "";
int    totalCandlesDoDia = 0;

// Controles de gestão de risco / fase
int  papeisPorOperacao   = 1;     // "V" - quantidade de papéis usada em cada envio de ordem (<= loteMax da fase)
int  baseNegociosDia     = 3;     // "E" - quantidade de negócios (pares C/V) configurada pelo usuário (sempre ímpar)
bool bonusConcedidoHoje  = false; // Controla se o bônus de +1 negócio (dia muito bom / LFT) já foi concedido hoje
datetime ultimoDiaVerificado = 0;

// Prefixo das variáveis globais do terminal usadas para persistir o estado configurado pelo
// usuário (fase, papéis, negócios/dia, canto do painel) através de trocas de timeframe/símbolo
// no gráfico, que forçam o MetaTrader a descarregar e recarregar o EA (OnDeinit -> OnInit).
// Variáveis globais do terminal (GlobalVariable) sobrevivem a esse ciclo, diferente das
// variáveis normais do EA, que voltariam ao valor dos inputs a cada reinício.
string PrefixoEstadoPersistente()
{
   return "GR_EstadoFases_" + _Symbol + "_" + IntegerToString(ChartID()) + "_";
}

void SalvarEstadoPersistente()
{
   string p = PrefixoEstadoPersistente();
   GlobalVariableSet(p + "fase", (double)faseAtual);
   GlobalVariableSet(p + "papeis", (double)papeisPorOperacao);
   GlobalVariableSet(p + "negocios", (double)baseNegociosDia);
   GlobalVariableSet(p + "canto", (double)cantoPainelAtual);
}

void CarregarEstadoPersistente()
{
   string p = PrefixoEstadoPersistente();

   if(GlobalVariableCheck(p + "fase"))
      faseAtual = (int)GlobalVariableGet(p + "fase");

   if(GlobalVariableCheck(p + "negocios"))
      baseNegociosDia = (int)GlobalVariableGet(p + "negocios");

   if(GlobalVariableCheck(p + "papeis"))
      papeisPorOperacao = (int)GlobalVariableGet(p + "papeis");

   if(GlobalVariableCheck(p + "canto"))
      cantoPainelAtual = (ENUM_BASE_CORNER)(int)GlobalVariableGet(p + "canto");
}

// Estrutura de dados para a tabela de Fases (agora em PONTOS por operação, não mais total financeiro diário)
struct StructFase
{
   double gainPontos;   // GAIN (pontos) - alvo de ganho em pontos por operação
   double lossPontos;   // LOSS (pontos) - alvo de perda em pontos por operação (valor negativo)
   int    loteMax;       // Lote Max - quantidade máxima de papéis negociáveis no dia (fixo da fase)
};

// Tabela de Fases baseada na imagem de referência
StructFase TabelaFases[11] =
{
   {   0.0,    0.0,  0 },   // Índice 0 (Não usado)
   {  50.0,  -50.0,  1 },   // Fase 1
   { 100.0, -100.0,  2 },   // Fase 2
   { 150.0, -150.0,  3 },   // Fase 3
   { 200.0, -150.0,  4 },   // Fase 4
   { 250.0, -200.0,  5 },   // Fase 5
   { 300.0, -250.0,  6 },   // Fase 6
   { 350.0, -250.0,  7 },   // Fase 7
   { 400.0, -300.0,  8 },   // Fase 8
   { 450.0, -350.0,  9 },   // Fase 9
   { 500.0, -400.0, 10 }    // Fase 10
};

//+------------------------------------------------------------------+
//| Layout do painel                                                 |
//+------------------------------------------------------------------+
int LINE_HEIGHT   = 16;
int BASE_MARGIN   = 20;
int MARGEM_DIREITA_TEXTO = 400;
int LARGURA_SEPARADOR = 368; // largura do separador em pixels (independe de fonte/caracteres)

// Retorna a coordenada Y da "linha lógica" i (0..10, onde 0 = linha 1 da especificação).
// Importante: o MetaTrader já mede o Y a partir do topo quando o canto é superior e a
// partir da base quando o canto é inferior - ou seja, usar a MESMA fórmula de distância
// para os dois cantos já produz o espelhamento visual (linha 0 fica perto do topo quando
// o painel está em cima, e perto da base quando está embaixo). Se invertêssemos a fórmula
// aqui também, as duas inversões se cancelariam e a ordem visual ficaria idêntica nos dois
// cantos - foi exatamente o bug reportado.
int GetLinhaY(int i)
{
   return BASE_MARGIN + i * LINE_HEIGHT;
}

// Converte um deslocamento "para baixo, na tela" em unidades de Y_DISTANCE, considerando
// que no canto inferior o Y_DISTANCE cresce para CIMA na tela (mede a partir da base) -
// logo o mesmo deslocamento precisa ter sinal invertido para continuar descendo visualmente.
int OffsetParaBaixo(int delta)
{
   return (cantoPainelAtual == CORNER_RIGHT_UPPER) ? delta : -delta;
}

void SetObjVisivel(string nome, bool visivel)
{
   if(ObjectFind(0, nome) >= 0)
      ObjectSetInteger(0, nome, OBJPROP_TIMEFRAMES, visivel ? OBJ_ALL_PERIODS : OBJ_NO_PERIODS);
}

//+------------------------------------------------------------------+
int OnInit()
{
   faseAtual = MathMin(10, MathMax(1, InpFaseInicial));

   // Detecta automaticamente o modo de preenchimento (Fill Policy) aceito pela corretora/ativo.
   // Sem isso, o CTrade usa FOK por padrão, que muitas corretoras/ativos rejeitam silenciosamente
   // (trade.Buy()/Sell() retorna false e nenhuma ordem é enviada, sem nenhum aviso visível).
   trade.SetTypeFillingBySymbol(_Symbol);
   trade.SetDeviationInPoints(10);

   baseNegociosDia = MathMax(1, InpNegociosDiaInicial);
   if(baseNegociosDia % 2 == 0) baseNegociosDia++; // garante número ímpar
   papeisPorOperacao = TabelaFases[faseAtual].loteMax;
   bonusConcedidoHoje = false;
   ultimoDiaVerificado = 0;

   // Restaura fase, papéis, negócios/dia e canto do painel de uma sessão anterior neste
   // mesmo gráfico, se existirem - assim uma troca de timeframe (que reinicia o EA) não
   // reseta o que o usuário configurou nos botões. Os valores acima servem só de padrão
   // para a primeira vez que o robô roda neste gráfico.
   CarregarEstadoPersistente();

   EventSetMillisecondTimer(50);

   for(int i=0; i<15; i++) ObjectDelete(0, PREFIX_TXT+IntegerToString(i));
   ObjectDelete(0, "Btn_FaseMenos");
   ObjectDelete(0, "Btn_FaseMais");
   ObjectDelete(0, "Btn_PapelMenos");
   ObjectDelete(0, "Btn_PapelMais");
   ObjectDelete(0, "Btn_NegMenos");
   ObjectDelete(0, "Btn_NegMais");
   ObjectDelete(0, "Btn_PainelCima");
   ObjectDelete(0, "Btn_PainelBaixo");

   Print("==========================================================");
   Print("[SISTEMA PRONTO] Boleta de Fases carregada. Fase atual: ", faseAtual);
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
   for(int i=0; i<15; i++) ObjectDelete(0, PREFIX_TXT+IntegerToString(i));
   ObjectDelete(0, "Btn_FaseMenos");
   ObjectDelete(0, "Btn_FaseMais");
   ObjectDelete(0, "Btn_PapelMenos");
   ObjectDelete(0, "Btn_PapelMais");
   ObjectDelete(0, "Btn_NegMenos");
   ObjectDelete(0, "Btn_NegMais");
   ObjectDelete(0, "Btn_PainelCima");
   ObjectDelete(0, "Btn_PainelBaixo");
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
   VerificarTrocaDeDia();
   CalcularMetricasDoDia();

   if(operacaoPendente)
   {
      AtualizarLinhasCustomizadas();
   }

   AtualizarPainelVisualEmTempoReal();
   ProcessarSomDeSaidaPendente();
}

void VerificarTrocaDeDia()
{
   datetime inicioHoje = iTime(_Symbol, PERIOD_D1, 0);
   if(inicioHoje != ultimoDiaVerificado)
   {
      bonusConcedidoHoje = false;
      ultimoDiaVerificado = inicioHoje;
   }
}

int NegociosDiaEfetivo()
{
   return baseNegociosDia + (bonusConcedidoHoje ? 1 : 0);
}

void OnChartEvent(const int id, const long& lparam, const double& dparam, const string& sparam)
{
   if(id == CHARTEVENT_CHART_CHANGE)
   {
      AtualizarLabelGraficoPreco("", clrNONE, false);
      ProcessarRotinasDeAtualizacao();
   }

   if(id == CHARTEVENT_OBJECT_CLICK)
   {
      if(sparam == "Btn_FaseMenos")
      {
         if(faseAtual > 1) faseAtual--;
         papeisPorOperacao = TabelaFases[faseAtual].loteMax;
         SalvarEstadoPersistente();
         ChartRedraw(0);
      }
      else if(sparam == "Btn_FaseMais")
      {
         if(faseAtual < 10) faseAtual++;
         papeisPorOperacao = TabelaFases[faseAtual].loteMax;
         SalvarEstadoPersistente();
         ChartRedraw(0);
      }
      else if(sparam == "Btn_PapelMenos")
      {
         papeisPorOperacao = (int)MathMax(1, papeisPorOperacao - 1);
         SalvarEstadoPersistente();
         ChartRedraw(0);
      }
      else if(sparam == "Btn_PapelMais")
      {
         papeisPorOperacao = (int)MathMin(TabelaFases[faseAtual].loteMax, papeisPorOperacao + 1);
         SalvarEstadoPersistente();
         ChartRedraw(0);
      }
      else if(sparam == "Btn_NegMenos")
      {
         baseNegociosDia = MathMax(1, baseNegociosDia - 2);
         SalvarEstadoPersistente();
         ChartRedraw(0);
      }
      else if(sparam == "Btn_NegMais")
      {
         baseNegociosDia = baseNegociosDia + 2;
         SalvarEstadoPersistente();
         ChartRedraw(0);
      }
      else if(sparam == "Btn_PainelCima")
      {
         cantoPainelAtual = CORNER_RIGHT_UPPER;
         SalvarEstadoPersistente();
         ChartRedraw(0);
      }
      else if(sparam == "Btn_PainelBaixo")
      {
         cantoPainelAtual = CORNER_RIGHT_LOWER;
         SalvarEstadoPersistente();
         ChartRedraw(0);
      }
   }

   if(id == CHARTEVENT_KEYDOWN)
   {
      int tecla = (int)lparam;

      // Zerar posição (CTRL+ENTER) e cancelar (ESC) precisam sempre funcionar,
      // mesmo que os limites diários já tenham sido atingidos - por isso são
      // tratados aqui, antes de qualquer verificação de limite.
      if(tecla == 13 && !operacaoPendente) // Tecla 'ENTER'
      {
         bool ctrlPressionado = (TerminalInfoInteger(TERMINAL_KEYSTATE_CONTROL) < 0);
         if(ctrlPressionado)
         {
            FecharPosicaoAberta();
            return;
         }
      }
      else if(tecla == 27) // Tecla 'ESC'
      {
         ApagarLinhasProjecao();
         globalMensagemStatus = "Cancelado. Pressione (C) Compra | (V) Venda";
         return;
      }

      int E = NegociosDiaEfetivo();
      int maxOrdensPermitidas = E * 2;
      int operacoesFeitasHoje = CalcularOperacoesDoDia();
      double pnlDiarioAtual = CalcularResultadoFinanceiroDoDia();

      double acumProgAtual = CalcularAcumProg(faseAtual, E, papeisPorOperacao);
      double acumRegAtual  = CalcularAcumReg(faseAtual, E, papeisPorOperacao);
      double lftAtual      = CalcularLFT(faseAtual, E, papeisPorOperacao);
      bool   todosGanhosHoje = TodosTradesForamGain();

      double limiteLossEfetivo = todosGanhosHoje ? (pnlDiarioAtual - lftAtual) : acumRegAtual;

      bool limiteOrdensAtingido = (operacoesFeitasHoje >= maxOrdensPermitidas);
      bool limiteLossAtingido    = (pnlDiarioAtual <= limiteLossEfetivo);
      bool limiteGainAtingido    = (pnlDiarioAtual >= acumProgAtual);

      if(limiteOrdensAtingido || limiteLossAtingido || limiteGainAtingido)
      {
         globalMensagemStatus = "Basta por hoje! (Limite diário atingido)";
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
      else if(tecla == 13) // Tecla 'ENTER' (só chega aqui se operacaoPendente == true)
      {
         EnviarOrdemMercado();
      }
   }
}

double ArredondarParaPassoDoPreco(double pontos)
{
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickSize <= 0) return pontos;
   return MathRound(pontos / tickSize) * tickSize;
}

// Agora os alvos já são dados diretamente em pontos por operação pela tabela de fases
double ObterPontosAlvosFase(double &slOut, double &tpOut)
{
   slOut = ArredondarParaPassoDoPreco(MathAbs(TabelaFases[faseAtual].lossPontos));
   tpOut = ArredondarParaPassoDoPreco(MathAbs(TabelaFases[faseAtual].gainPontos));
   return slOut;
}

//+------------------------------------------------------------------+
//| Fórmulas de LFT / Acúmulos - dependem da fase, da quantidade de   |
//| negócios (E) configurada/permitida para o dia, e da quantidade de |
//| papéis por operação (V) escolhida pelo usuário - NÃO do Lote Max  |
//| fixo da fase, que é apenas o teto permitido para V.               |
//+------------------------------------------------------------------+

// Acúmulo progressivo = (quantidade de negócios determinada pelo usuário) * (papéis) * 10 * (GAIN da fase / 50)
double CalcularAcumProg(int fase, int negociosDia, int papeis)
{
   return negociosDia * papeis * 10.0 * (TabelaFases[fase].gainPontos / 50.0);
}

// Acúmulo regressivo = (quantidade de negócios determinada pelo usuário) * (papéis) * 10 * (LOSS da fase / 50)
double CalcularAcumReg(int fase, int negociosDia, int papeis)
{
   return negociosDia * papeis * 10.0 * (TabelaFases[fase].lossPontos / 50.0);
}

// LFT = ((quantidade de negócios do dia / 2) arredondado para BAIXO) * papéis * 20 * ((LOSS da fase * -1) / 2 / 50)
double CalcularLFT(int fase, int negociosDia, int papeis)
{
   int floorOrdens2 = (int)MathFloor(negociosDia / 2.0);
   return floorOrdens2 * papeis * 20.0 * ((TabelaFases[fase].lossPontos * -1.0) / 2.0 / 50.0);
}

// Verifica se todas as operações (pares de entrada/saída) já finalizadas hoje terminaram com ganho
bool TodosTradesForamGain()
{
   datetime inicioDoDia = iTime(_Symbol, PERIOD_D1, 0);
   HistorySelect(inicioDoDia, TimeCurrent());
   int totalDeals = HistoryDealsTotal();

   long   posIds[];
   double posLucro[];
   ArrayResize(posIds, 0);
   ArrayResize(posLucro, 0);

   for(int i = 0; i < totalDeals; i++)
   {
      ulong ticketDeal = HistoryDealGetTicket(i);
      if(ticketDeal <= 0) continue;
      if(HistoryDealGetString(ticketDeal, DEAL_SYMBOL) != _Symbol) continue;

      long entradaDeal = HistoryDealGetInteger(ticketDeal, DEAL_ENTRY);
      if(entradaDeal != DEAL_ENTRY_OUT && entradaDeal != DEAL_ENTRY_INOUT) continue;

      long posId = HistoryDealGetInteger(ticketDeal, DEAL_POSITION_ID);
      double resultado = HistoryDealGetDouble(ticketDeal, DEAL_PROFIT)
                        + HistoryDealGetDouble(ticketDeal, DEAL_SWAP)
                        + HistoryDealGetDouble(ticketDeal, DEAL_COMMISSION);

      int idx = -1;
      for(int j = 0; j < ArraySize(posIds); j++)
      {
         if(posIds[j] == posId) { idx = j; break; }
      }
      if(idx < 0)
      {
         ArrayResize(posIds, ArraySize(posIds) + 1);
         ArrayResize(posLucro, ArraySize(posLucro) + 1);
         idx = ArraySize(posIds) - 1;
         posIds[idx] = posId;
         posLucro[idx] = 0.0;
      }
      posLucro[idx] += resultado;
   }

   int total = ArraySize(posIds);
   if(total == 0) return false;

   for(int i = 0; i < total; i++)
      if(posLucro[i] <= 0.0) return false;

   return true;
}

void EnviarOrdemMercado()
{
   int E = NegociosDiaEfetivo();
   int maxOrdensPermitidas = E * 2;
   int operacoesFeitasHoje = CalcularOperacoesDoDia();
   double pnlDiarioAtual = CalcularResultadoFinanceiroDoDia();

   double acumProgAtual = CalcularAcumProg(faseAtual, E, papeisPorOperacao);
   double acumRegAtual  = CalcularAcumReg(faseAtual, E, papeisPorOperacao);
   double lftAtual      = CalcularLFT(faseAtual, E, papeisPorOperacao);
   bool   todosGanhosHoje = TodosTradesForamGain();
   double limiteLossEfetivo = todosGanhosHoje ? (pnlDiarioAtual - lftAtual) : acumRegAtual;

   if(operacoesFeitasHoje >= maxOrdensPermitidas ||
      pnlDiarioAtual <= limiteLossEfetivo ||
      pnlDiarioAtual >= acumProgAtual)
   {
      globalMensagemStatus = "Basta por hoje! (Limites diários atingidos)";
      ApagarLinhasProjecao();
      return;
   }

   double pontosSL = 0, pontosTP = 0;
   ObterPontosAlvosFase(pontosSL, pontosTP);

   int loteParaEnviar = papeisPorOperacao;
   bool ordemOk = false;

   // A ordem é enviada SEM SL/TP - eles são calculados e aplicados logo abaixo, com base
   // no preço real de EXECUÇÃO da posição (POSITION_PRICE_OPEN), e não no preço de mercado
   // no instante em que a ordem foi enviada (que pode divergir por slippage/requote).
   if(tipoOperacao == 1)
   {
      ordemOk = trade.Buy(loteParaEnviar, _Symbol, 0.0, 0.0, 0.0, "Compra Fase " + IntegerToString(faseAtual));
   }
   else if(tipoOperacao == 2)
   {
      ordemOk = trade.Sell(loteParaEnviar, _Symbol, 0.0, 0.0, 0.0, "Venda Fase " + IntegerToString(faseAtual));
   }

   if(ordemOk)
   {
      if(PositionSelect(_Symbol))
      {
         double precoExecucao = PositionGetDouble(POSITION_PRICE_OPEN);
         long   tipoPosAberta = PositionGetInteger(POSITION_TYPE);
         double slFinal = 0, tpFinal = 0;

         if(tipoPosAberta == POSITION_TYPE_BUY)
         {
            slFinal = NormalizeDouble(precoExecucao - (pontosSL * _Point), _Digits);
            tpFinal = NormalizeDouble(precoExecucao + (pontosTP * _Point), _Digits);
         }
         else
         {
            slFinal = NormalizeDouble(precoExecucao + (pontosSL * _Point), _Digits);
            tpFinal = NormalizeDouble(precoExecucao - (pontosTP * _Point), _Digits);
         }

         if(!trade.PositionModify(_Symbol, slFinal, tpFinal))
         {
            Print("[ERRO] Ordem executada, mas falhou ao definir SL/TP. Retcode: ", trade.ResultRetcode(),
                  " - ", trade.ResultRetcodeDescription());
            globalMensagemStatus = StringFormat("Ordem sem SL/TP! (retcode %d) Verifique manualmente.", trade.ResultRetcode());
            ApagarLinhasProjecao();
            return;
         }
      }

      ApagarLinhasProjecao();
      globalMensagemStatus = "Ordem enviada! Pressione (ESC)";
   }
   else
   {
      Print("[ERRO] Falha ao enviar ordem. Retcode: ", trade.ResultRetcode(),
            " - ", trade.ResultRetcodeDescription(), " | GetLastError: ", GetLastError());
      globalMensagemStatus = StringFormat("Falha ao enviar ordem! (retcode %d)", trade.ResultRetcode());
      ApagarLinhasProjecao();
   }
}

// Tenta localizar o deal de saída da posição informada (por POSITION_IDENTIFIER) e tocar
// o som correspondente ao resultado. Retorna true se encontrou (e já tocou o som), ou
// false se o deal ainda não apareceu no histórico (para tentar de novo no próximo tick).
// IMPORTANTE: se não encontrar, NÃO toca nenhum som - evita o bug de tocar "stops.wav"
// por padrão quando o histórico ainda não sincronizou o deal de um TP recém-executado.
bool TentarTocarSomSaida(ulong ticketPosicao)
{
   datetime inicioDoDia = iTime(_Symbol, PERIOD_D1, 0);
   HistorySelect(inicioDoDia, TimeCurrent());
   int totalDeals = HistoryDealsTotal();

   for(int i = totalDeals - 1; i >= 0; i--)
   {
      ulong ticketDeal = HistoryDealGetTicket(i);
      if(ticketDeal <= 0) continue;
      if(HistoryDealGetString(ticketDeal, DEAL_SYMBOL) != _Symbol) continue;

      long entradaDeal = HistoryDealGetInteger(ticketDeal, DEAL_ENTRY);
      if(entradaDeal != DEAL_ENTRY_OUT && entradaDeal != DEAL_ENTRY_INOUT) continue;

      if(ticketPosicao != 0 && (ulong)HistoryDealGetInteger(ticketDeal, DEAL_POSITION_ID) != ticketPosicao)
         continue;

      double lucro    = HistoryDealGetDouble(ticketDeal, DEAL_PROFIT);
      double swap     = HistoryDealGetDouble(ticketDeal, DEAL_SWAP);
      double comissao = HistoryDealGetDouble(ticketDeal, DEAL_COMMISSION);
      double resultado = lucro + swap + comissao;

      if(resultado > 0.0)
      {
         if(!PlaySound("gain.wav")) PlaySound("\\Audio\\gain.wav");
      }
      else
      {
         if(!PlaySound("stops.wav")) PlaySound("\\Audio\\stops.wav");
      }
      return true;
   }

   return false;
}

// Chama esta função a cada tick/timer enquanto aguardandoSomSaida estiver ativo,
// até localizar o deal (ou desistir após MAX_TENTATIVAS_SOM_SAIDA tentativas).
void ProcessarSomDeSaidaPendente()
{
   if(!aguardandoSomSaida) return;

   if(TentarTocarSomSaida(ultimoTicketPosicaoAberta))
   {
      aguardandoSomSaida = false;
      return;
   }

   tentativasSomSaida++;
   if(tentativasSomSaida >= MAX_TENTATIVAS_SOM_SAIDA)
   {
      Print("[AVISO] Deal de saída da posição ", ultimoTicketPosicaoAberta,
            " não sincronizou a tempo no histórico - usando o último P&L flutuante conhecido (R$ ",
            DoubleToString(ultimoLucroFlutuantePosicao, 2), ") como referência para o som.");

      if(ultimoLucroFlutuantePosicao > 0.0)
      {
         if(!PlaySound("gain.wav")) PlaySound("\\Audio\\gain.wav");
      }
      else
      {
         if(!PlaySound("stops.wav")) PlaySound("\\Audio\\stops.wav");
      }
      aguardandoSomSaida = false;
   }
}

void FecharPosicaoAberta()
{
   if(PositionSelect(_Symbol))
   {
      ulong ticketAntesDeFechar = PositionGetInteger(POSITION_IDENTIFIER);
      if(trade.PositionClose(_Symbol))
      {
         ultimoTicketPosicaoAberta = ticketAntesDeFechar;
         aguardandoSomSaida = true;
         tentativasSomSaida = 0;
         globalMensagemStatus = "(C) Compra | (V) Venda | (Enter) Envia | (CTRL+Enter) Zera";
         posicaoEstavaAberta = false;
      }
   }
   else
   {
      globalMensagemStatus = "(C) Compra | (V) Venda | (Enter) Envia | (CTRL+Enter) Zera";
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
         if(dt.hour == 9 && dt.min == 0) continue;

         double amplitude = barras[i].high - barras[i].low;
         if(amplitude > maiorAmplitude)
         {
            maiorAmplitude = amplitude;
            dataHoraCandle = barras[i].time;
         }
      }

      maiorAmplitudeGlobal = NormalizeDouble(maiorAmplitude / _Point, 0);
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
         string ativoDeal = HistoryDealGetString(ticketDeal, DEAL_SYMBOL);
         if(ativoDeal == _Symbol)
         {
            double lucroDeal    = HistoryDealGetDouble(ticketDeal, DEAL_PROFIT);
            double swapDeal     = HistoryDealGetDouble(ticketDeal, DEAL_SWAP);
            double comissaoDeal = HistoryDealGetDouble(ticketDeal, DEAL_COMMISSION);

            lucroTotalDia += (lucroDeal + swapDeal + comissaoDeal);
         }
      }
   }

   return lucroTotalDia;
}

double CalcularPontosDoPeriodo(datetime tempoInicio)
{
   HistorySelect(tempoInicio, TimeCurrent());
   int totalDeals = HistoryDealsTotal();
   double totalPontos = 0.0;

   for(int i = 0; i < totalDeals; i++)
   {
      ulong ticketDeal = HistoryDealGetTicket(i);
      if(ticketDeal > 0 && HistoryDealGetString(ticketDeal, DEAL_SYMBOL) == _Symbol)
      {
         long tipoEntrada = HistoryDealGetInteger(ticketDeal, DEAL_ENTRY);
         if(tipoEntrada == DEAL_ENTRY_OUT || tipoEntrada == DEAL_ENTRY_INOUT)
         {
            double precoSaida = HistoryDealGetDouble(ticketDeal, DEAL_PRICE);
            long posicaoID = HistoryDealGetInteger(ticketDeal, DEAL_POSITION_ID);

            for(int j = 0; j < totalDeals; j++)
            {
               ulong ticketEntrada = HistoryDealGetTicket(j);
               if(ticketEntrada > 0 && HistoryDealGetString(ticketEntrada, DEAL_SYMBOL) == _Symbol)
               {
                  if(HistoryDealGetInteger(ticketEntrada, DEAL_POSITION_ID) == posicaoID &&
                     HistoryDealGetInteger(ticketEntrada, DEAL_ENTRY) == DEAL_ENTRY_IN)
                  {
                     double precoEntrada = HistoryDealGetDouble(ticketEntrada, DEAL_PRICE);
                     long tipoPos = HistoryDealGetInteger(ticketEntrada, DEAL_TYPE);

                     if(tipoPos == 0)
                        totalPontos += (precoSaida - precoEntrada) / _Point;
                     else
                        totalPontos += (precoEntrada - precoSaida) / _Point;

                     break;
                  }
               }
            }
         }
      }
   }
   return totalPontos;
}

double CalcularPontosDoDia()
{
   return CalcularPontosDoPeriodo(iTime(_Symbol, PERIOD_D1, 0));
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
         string ativoDeal = HistoryDealGetString(ticketDeal, DEAL_SYMBOL);
         if(ativoDeal == _Symbol)
         {
            long entradaDeal = HistoryDealGetInteger(ticketDeal, DEAL_ENTRY);
            if(entradaDeal == DEAL_ENTRY_IN || entradaDeal == DEAL_ENTRY_OUT || entradaDeal == DEAL_ENTRY_INOUT)
            {
               totalOps++;
            }
         }
      }
   }

   return totalOps;
}

datetime ObterInicioDoMes()
{
   MqlDateTime dt;
   TimeCurrent(dt);
   dt.day = 1;
   dt.hour = 0;
   dt.min = 0;
   dt.sec = 0;
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
         string ativoDeal = HistoryDealGetString(ticketDeal, DEAL_SYMBOL);
         if(ativoDeal == _Symbol)
         {
            double lucroDeal    = HistoryDealGetDouble(ticketDeal, DEAL_PROFIT);
            double swapDeal     = HistoryDealGetDouble(ticketDeal, DEAL_SWAP);
            double comissaoDeal = HistoryDealGetDouble(ticketDeal, DEAL_COMMISSION);

            lucroTotalMes += (lucroDeal + swapDeal + comissaoDeal);
         }
      }
   }

   return lucroTotalMes;
}

double CalcularPontosDoMes()
{
   return CalcularPontosDoPeriodo(ObterInicioDoMes());
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
         string ativoDeal = HistoryDealGetString(ticketDeal, DEAL_SYMBOL);
         if(ativoDeal == _Symbol)
         {
            long entradaDeal = HistoryDealGetInteger(ticketDeal, DEAL_ENTRY);
            if(entradaDeal == DEAL_ENTRY_IN || entradaDeal == DEAL_ENTRY_OUT || entradaDeal == DEAL_ENTRY_INOUT)
            {
               totalOpsMes++;
            }
         }
      }
   }

   return totalOpsMes;
}

void DefaultAtualizarLinhasCustomizadas()
{
   double pontosSL = 0, pontosTP = 0;
   ObterPontosAlvosFase(pontosSL, pontosTP);

   double precoReferencia = 0;
   double slProjetado = 0;
   double tpProjetado = 0;
   color corEntrada = clrNONE;

   if(tipoOperacao == 1)
   {
      precoReferencia = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      slProjetado     = precoReferencia - (pontosSL * _Point);
      tpProjetado     = precoReferencia + (pontosTP * _Point);
      corEntrada      = clrDodgerBlue;
   }
   else if(tipoOperacao == 2)
   {
      precoReferencia = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      slProjetado     = precoReferencia + (pontosSL * _Point);
      tpProjetado     = precoReferencia - (pontosTP * _Point);
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
      int posXDesejada = (int)(larguraGrafico - 75);
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

void CriarBotaoFase(string nome, string texto, int x, int y, int largura, int altura)
{
   if(ObjectFind(0, nome) < 0)
   {
      ObjectCreate(0, nome, OBJ_BUTTON, 0, 0, 0);
      ObjectSetInteger(0, nome, OBJPROP_SELECTABLE, false);
   }
   ObjectSetInteger(0, nome, OBJPROP_CORNER, cantoPainelAtual);
   ObjectSetString(0, nome, OBJPROP_TEXT, texto);
   ObjectSetInteger(0, nome, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, nome, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, nome, OBJPROP_XSIZE, largura);
   ObjectSetInteger(0, nome, OBJPROP_YSIZE, altura);
   ObjectSetInteger(0, nome, OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, nome, OBJPROP_BGCOLOR, clrDarkSlateGray);
   ObjectSetInteger(0, nome, OBJPROP_FONTSIZE, 9);
}

//+------------------------------------------------------------------+
//| Painel principal - 11 linhas, ordem espelhada conforme o canto   |
//+------------------------------------------------------------------+
void AtualizarPainelVisualEmTempoReal()
{
   int E = NegociosDiaEfetivo();
   int maxOrdensPermitidas = E * 2;
   int operacoesFeitasHoje = CalcularOperacoesDoDia();
   double pnlDiarioAtual = CalcularResultadoFinanceiroDoDia();

   double acumProgAtual = CalcularAcumProg(faseAtual, E, papeisPorOperacao);
   double acumRegAtual  = CalcularAcumReg(faseAtual, E, papeisPorOperacao);
   double lftAtual       = CalcularLFT(faseAtual, E, papeisPorOperacao);
   bool   todosGanhosHoje = TodosTradesForamGain();

   // Concede o bônus de +1 negócio uma única vez por dia quando todas as operações forem gain
   if(todosGanhosHoje && !bonusConcedidoHoje)
   {
      bonusConcedidoHoje = true;
      E = NegociosDiaEfetivo();
      maxOrdensPermitidas = E * 2;
   }

   double limiteLossEfetivo = todosGanhosHoje ? (pnlDiarioAtual - lftAtual) : acumRegAtual;

   bool limiteOrdensAtingido = (operacoesFeitasHoje >= maxOrdensPermitidas);
   bool limiteLossAtingido    = (pnlDiarioAtual <= limiteLossEfetivo);
   bool limiteGainAtingido    = (pnlDiarioAtual >= acumProgAtual);
   bool algumLimiteAtingido   = (limiteOrdensAtingido || limiteLossAtingido || limiteGainAtingido);

   if(algumLimiteAtingido)
   {
      string motivo = limiteOrdensAtingido ? IntegerToString(maxOrdensPermitidas) + " ordens" :
                       (limiteGainAtingido ? "ganho" : "perda");
      globalMensagemStatus = "Basta por hoje! (Limite de " + motivo + " atingido)";
      ApagarLinhasProjecao();
   }
   else
   {
      if(globalMensagemStatus.Find("Basta por hoje") >= 0 && !PositionSelect(_Symbol))
      {
         globalMensagemStatus = "(C) Compra | (V) Venda | (Enter) Envia | (CTRL+Enter) Zera";
      }
   }

   // ---- Posição / status do preço na tela ----
   string textoPosicao = StringFormat("Posição (0 %s)", _Symbol);
   color corPosicao = clrLightGray;

   if(PositionSelect(_Symbol))
   {
      posicaoEstavaAberta = true;
      ultimoTicketPosicaoAberta = PositionGetInteger(POSITION_IDENTIFIER);
      if(!algumLimiteAtingido)
         globalMensagemStatus = "Ordem executada! (CTRL + Enter) para Zerar";

      long tipoPos = PositionGetInteger(POSITION_TYPE);
      double precoAberturaPos = PositionGetDouble(POSITION_PRICE_OPEN);
      double precoAtual = (tipoPos == POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double lucroFinanceiro = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
      ultimoLucroFlutuantePosicao = lucroFinanceiro;

      string tipoStr = (tipoPos == POSITION_TYPE_BUY) ? "Compra" : "Venda";
      int volumePos = (int)PositionGetDouble(POSITION_VOLUME);
      int volumePosSinal = (tipoPos == POSITION_TYPE_BUY) ? volumePos : -volumePos;

      string valorFormatado = DoubleToString(lucroFinanceiro, 2);
      StringReplace(valorFormatado, ".", ",");

      textoPosicao = StringFormat("Posição (%d %s)", volumePosSinal, _Symbol);
      corPosicao = (volumePosSinal > 0) ? clrLimeGreen : (volumePosSinal < 0 ? clrRed : clrLightGray);

      color corPnLGrafico = (lucroFinanceiro > 0.0) ? clrLimeGreen : (lucroFinanceiro < 0.0 ? clrRed : clrLightGray);
      AtualizarLabelGraficoPreco(StringFormat("R$ %s", valorFormatado), corPnLGrafico, true);
   }
   else
   {
      if(posicaoEstavaAberta)
      {
         aguardandoSomSaida = true;
         tentativasSomSaida = 0;
         if(!algumLimiteAtingido)
            globalMensagemStatus = "(C) Compra | (V) Venda | (Enter) Envia | (CTRL+Enter) Zera";
         posicaoEstavaAberta = false;
      }
      ObjectDelete(0, LABEL_PRECO_POSICAO);
   }

   // ---- PnL diário ----
   double totalDoDia = pnlDiarioAtual;
   double totalPontosDia = CalcularPontosDoDia();
   int operacoesDiaCount = operacoesFeitasHoje;
   string strTotalDia = DoubleToString(totalDoDia, 2); StringReplace(strTotalDia, ".", ",");
   string strPontosDia = DoubleToString(totalPontosDia, 0); StringReplace(strPontosDia, ".", ",");
   string textoPnLDiario = StringFormat("PnL diário: R$ %s | %s pts | Operações: %d", strTotalDia, strPontosDia, operacoesDiaCount);
   color corPnLDiario = (totalDoDia > 0.0) ? clrLimeGreen : (totalDoDia < 0.0 ? clrRed : clrLightGray);

   // ---- PnL mensal ----
   double totalDoMes = CalcularResultadoFinanceiroDoMes();
   double totalPontosMes = CalcularPontosDoMes();
   string strTotalMes = DoubleToString(totalDoMes, 2); StringReplace(strTotalMes, ".", ",");
   string strPontosMes = DoubleToString(totalPontosMes, 0); StringReplace(strPontosMes, ".", ",");
   string textoPnLMensal = StringFormat("PnL mensal: R$ %s | %s pts | Operações: %d", strTotalMes, strPontosMes, CalcularOperacoesDoMes());
   color corPnLMensal = (totalDoMes > 0.0) ? clrLimeGreen : (totalDoMes < 0.0 ? clrRed : clrLightGray);

   // ---- Fase / SL / TP ----
   double exSL = 0, exTP = 0;
   ObterPontosAlvosFase(exSL, exTP);
   string textoFase = StringFormat("Fase %d - SL: %.0f pts | TP: %.0f pts", faseAtual, exSL, exTP);

   // ---- Papéis por operação ----
   string textoPapeis = StringFormat("Máx papéis por operação: %d", papeisPorOperacao);

   // ---- LFT ----
   string strLFT = DoubleToString(lftAtual, 2); StringReplace(strLFT, ".", ",");
   string textoLFT = StringFormat("Loss from top: R$ %s", strLFT);
   color corLFT = todosGanhosHoje ? clrLimeGreen : clrLightGray;

   // ---- Acúmulos ----
   string strAcumReg  = DoubleToString(acumRegAtual, 2);  StringReplace(strAcumReg, ".", ",");
   string strAcumProg = DoubleToString(acumProgAtual, 2); StringReplace(strAcumProg, ".", ",");
   string textoAcumulos = StringFormat("Máx loss: R$ %s | Máx gain: R$ %s", strAcumReg, strAcumProg);

   // ---- Negócios por dia ----
   string textoNegocios = StringFormat("Negócios por dia: %d", E);

   // Separadores agora são desenhados como retângulos finos (ver CriarSeparador), com
   // largura controlada por LARGURA_SEPARADOR - veja mais abaixo.

   // ---- Status (linha 11) ----
   string textoStatus = globalMensagemStatus;
   color corStatus = algumLimiteAtingido ? clrRed : clrBlack;

   // Índices 0..10 correspondem às linhas 1..11 da especificação, na ordem do painel "em cima".
   // Quando o painel está embaixo, o próprio canto (CORNER_RIGHT_LOWER) já inverte a
   // direção em que o Y cresce, espelhando a ordem visual das linhas automaticamente.
   CriarTextoLabel(PREFIX_TXT+"0",  textoPnLMensal, MARGEM_DIREITA_TEXTO, GetLinhaY(0), 10, corPnLMensal, cantoPainelAtual);
   CriarSeparador(PREFIX_TXT+"1",   MARGEM_DIREITA_TEXTO, GetLinhaY(1)+OffsetParaBaixo(7), LARGURA_SEPARADOR, clrSilver, cantoPainelAtual);
   CriarTextoLabel(PREFIX_TXT+"2",  textoFase,       MARGEM_DIREITA_TEXTO, GetLinhaY(2), 10, clrDodgerBlue, cantoPainelAtual);
   CriarTextoLabel(PREFIX_TXT+"3",  textoPapeis,     MARGEM_DIREITA_TEXTO, GetLinhaY(3), 10, clrDodgerBlue, cantoPainelAtual);
   CriarTextoLabel(PREFIX_TXT+"4",  textoLFT,        MARGEM_DIREITA_TEXTO, GetLinhaY(4), 10, corLFT, cantoPainelAtual);
   CriarTextoLabel(PREFIX_TXT+"5",  textoAcumulos,   MARGEM_DIREITA_TEXTO, GetLinhaY(5), 10, clrSteelBlue, cantoPainelAtual);
   CriarTextoLabel(PREFIX_TXT+"6",  textoNegocios,   MARGEM_DIREITA_TEXTO, GetLinhaY(6), 10, clrSteelBlue, cantoPainelAtual);
   CriarSeparador(PREFIX_TXT+"7",   MARGEM_DIREITA_TEXTO, GetLinhaY(7)+OffsetParaBaixo(7), LARGURA_SEPARADOR, clrSilver, cantoPainelAtual);
   CriarTextoLabel(PREFIX_TXT+"8",  textoPnLDiario,  MARGEM_DIREITA_TEXTO, GetLinhaY(8), 10, corPnLDiario, cantoPainelAtual);
   CriarTextoLabel(PREFIX_TXT+"9",  textoPosicao,    MARGEM_DIREITA_TEXTO, GetLinhaY(9), 10, corPosicao, cantoPainelAtual);
   CriarTextoLabel(PREFIX_TXT+"10", textoStatus,     MARGEM_DIREITA_TEXTO, GetLinhaY(10), 10, corStatus, cantoPainelAtual);

   // Botões da linha 3 (índice 2) - troca de fase
   CriarBotaoFase("Btn_FaseMenos", "-", 89, GetLinhaY(2)-1, 28, 16);
   CriarBotaoFase("Btn_FaseMais",  "+", 60,  GetLinhaY(2)-1, 28, 16);

   // Botões da linha 4 (índice 3) - papéis por operação
   CriarBotaoFase("Btn_PapelMenos", "-", 89, GetLinhaY(3), 28, 16);
   CriarBotaoFase("Btn_PapelMais",  "+", 60,  GetLinhaY(3), 28, 16);

   // Botões da linha 7 (índice 6) - negócios por dia (+2/-2)
   CriarBotaoFase("Btn_NegMenos", "-2", 89, GetLinhaY(6), 28, 16);
   CriarBotaoFase("Btn_NegMais",  "+2", 60,  GetLinhaY(6), 28, 16);

   // Botões da linha 9 (índice 8) - mover painel para cima/baixo (apenas um visível por vez)
   CriarBotaoFase("Btn_PainelBaixo", "▼", 60, GetLinhaY(8), 28, 16);
   CriarBotaoFase("Btn_PainelCima",  "▲", 60, GetLinhaY(8), 28, 16);
   SetObjVisivel("Btn_PainelBaixo", cantoPainelAtual == CORNER_RIGHT_UPPER);
   SetObjVisivel("Btn_PainelCima",  cantoPainelAtual == CORNER_RIGHT_LOWER);

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
   ObjectSetString(0, nome, OBJPROP_FONT, "Arial");
   ObjectSetInteger(0, nome, OBJPROP_BACK, true);
}

// Separador desenhado como um retângulo fino (OBJ_RECTANGLE_LABEL), com largura em pixels
// controlada diretamente pelo parâmetro "largura" - não depende de fonte nem de caracteres,
// e por isso não sofre o corte (clipping) que acontecia com a string de traços.
void CriarSeparador(string nome, int x, int y, int largura, color cor, ENUM_BASE_CORNER canto)
{
   if(ObjectFind(0, nome) < 0)
   {
      ObjectCreate(0, nome, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, nome, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, nome, OBJPROP_BACK, false);
      ObjectSetInteger(0, nome, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   }

   ObjectSetInteger(0, nome, OBJPROP_CORNER, canto);
   ObjectSetInteger(0, nome, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, nome, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, nome, OBJPROP_XSIZE, largura);
   ObjectSetInteger(0, nome, OBJPROP_YSIZE, 1);
   ObjectSetInteger(0, nome, OBJPROP_BGCOLOR, cor);
   ObjectSetInteger(0, nome, OBJPROP_COLOR, cor);
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