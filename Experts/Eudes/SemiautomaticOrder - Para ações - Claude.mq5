//+------------------------------------------------------------------+
//|         Boleta_Acoes_Com_Painel_v3.11.mq5                        |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026"
#property version   "3.11"
#property strict

#include <Trade\Trade.mqh>
CTrade trade;

//--- Enumerador para a seleção da proporção de risco do Gain (agora escolhida por botões no painel)
enum ENUM_RISK_RATIO
{
   RATIO_1_1 = 1, // Gain 1:1 o Loss (1% Loss, 1% Gain)
   RATIO_2_2 = 2, // Gain 2:2 o Loss (2% Loss, 2% Gain)
   RATIO_3_3 = 3, // Gain 3:3 o Loss (3% Loss, 3% Gain)
   RATIO_2_1 = 4, // Gain 2x o Loss (1% Loss, 2% Gain)
   RATIO_3_1 = 5  // Gain 3x o Loss (1% Loss, 3% Gain)
};

//--- Parâmetros de Entrada
input group "--- Configurações Operacionais ---"
input int               InpQuantidadeInicial  = 100;         // Quantidade inicial (múltiplo de 100 | ou 1-99 se ticker terminar em "F")
input ENUM_RISK_RATIO   InpProporcaoInicial   = RATIO_2_1;    // Proporção inicial entre Loss e Gain (também trocável pelos botões)
input int               InpNegociosDiaInicial = 3;            // Negócios (pares C/V) permitidos por dia - deve ser ímpar

input group "--- Configuração do Risco Percentual ---"
input double            InpPercentualBase = 1.0;              // Percentual base do preço (%) usado no cálculo de SL/TP

const string PREFIX_OBJ = "Proj_";
const string PREFIX_TXT = "Painel_";
const string LABEL_PRECO_POSICAO = "LABEL_PRECO_POSICAO";

// Variáveis globais de controle de estado
ENUM_RISK_RATIO proporcaoAtual = RATIO_2_1;
bool operacaoPendente = false;
int  tipoOperacao = 0; // 1 = Compra, 2 = Venda
string globalMensagemStatus = "(C) Compra | (V) Venda | (Enter) Envia | (CTRL+Enter) Zera";
bool posicaoEstavaAberta = false;

// Quantidade / regras de lote do mercado brasileiro
int  papeisPorOperacao   = 100;    // Quantidade usada em cada envio de ordem
int  baseNegociosDia     = 3;      // Quantidade de negócios (pares C/V) configurada pelo usuário (sempre ímpar)
bool mercadoFracionario  = false;  // true se o ticker terminar em "F" (mercado fracionário: 1-99 unidades)

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

//+------------------------------------------------------------------+
//| Layout do painel                                                 |
//+------------------------------------------------------------------+
int LINE_HEIGHT   = 16;
int BASE_MARGIN   = 20;
int MARGEM_DIREITA_TEXTO = 400;
int LARGURA_SEPARADOR = 367; // largura do separador em pixels (independe de fonte/caracteres)

// Espaço extra (em pixels) inserido a partir da linha da "Proporção" (índice 3) em diante,
// para abrir um respiro um pouco maior entre a linha "Proporção" e a linha de botões (índice 2)
// logo acima/abaixo dela - o mesmo valor é usado para igualar o espaço entre os botões e o
// separador (índice 1), deixando a linha de botões visualmente centralizada entre os dois.
int GAP_EXTRA_PROPORCAO = 6;

// Retorna a coordenada Y da "linha lógica" i (0..9, onde 0 = linha 1 da especificação).
// Importante: o MetaTrader já mede o Y a partir do topo quando o canto é superior e a
// partir da base quando o canto é inferior - ou seja, usar a MESMA fórmula de distância
// para os dois cantos já produz o espelhamento visual (linha 0 fica perto do topo quando
// o painel está em cima, e perto da base quando está embaixo). Se invertêssemos a fórmula
// aqui também, as duas inversões se cancelariam e a ordem visual ficaria idêntica nos dois
// cantos - foi exatamente o bug reportado.
int GetLinhaY(int i)
{
   int y = BASE_MARGIN + i * LINE_HEIGHT;
   if(i >= 3) y += GAP_EXTRA_PROPORCAO; // abre o respiro extra a partir da linha "Proporção"
   return y;
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

// Alguns tipos de objeto do MetaTrader (em especial OBJ_RECTANGLE_LABEL, usado nos
// separadores) não se re-ancoram corretamente quando apenas a propriedade OBJPROP_CORNER
// é alterada num objeto já existente - o MT5 pode manter a posição antiga em memória e
// só recalculá-la de fato quando o objeto é recriado do zero. Isso fazia o separador
// "herdar" a posição de outro objeto (os botões de proporção) ao trocar o painel para o
// canto inferior. A correção é apagar todos os objetos do painel antes de trocar de canto,
// forçando a recriação (com o canto novo já correto) no próximo refresh.
void LimparObjetosPainel()
{
   for(int i=0; i<15; i++) ObjectDelete(0, PREFIX_TXT+IntegerToString(i));
   ObjectDelete(0, "Btn_PapelMenos");
   ObjectDelete(0, "Btn_PapelMais");
   ObjectDelete(0, "Btn_NegMenos");
   ObjectDelete(0, "Btn_NegMais");
   ObjectDelete(0, "Btn_PainelCima");
   ObjectDelete(0, "Btn_PainelBaixo");
   ObjectDelete(0, "Btn_R11");
   ObjectDelete(0, "Btn_R22");
   ObjectDelete(0, "Btn_R33");
   ObjectDelete(0, "Btn_R21");
   ObjectDelete(0, "Btn_R31");
}

//+------------------------------------------------------------------+
// Trocar o timeframe do gráfico (ou o símbolo, ou recompilar) faz o MT5 descarregar e
// recarregar o EA (OnDeinit seguido de OnInit) - sem isso, tudo que foi ajustado pelos
// botões (negócios/dia, quantidade, proporção, canto do painel) voltaria ao valor padrão
// dos inputs a cada troca de timeframe. Para persistir esses ajustes entre um OnInit e
// outro (mesmo gráfico), eles são salvos em Variáveis Globais do terminal, amarradas ao
// ChartID() - assim cada gráfico/instância mantém o próprio estado, sem conflitar com
// outra instância do robô rodando em outro gráfico.
string ChaveGlobal(string sufixo)
{
   return "BoletaAcoes_" + IntegerToString((long)ChartID()) + "_" + sufixo;
}

int OnInit()
{
   // Detecta automaticamente o modo de preenchimento (Fill Policy) aceito pela corretora/ativo.
   // Sem isso, o CTrade usa FOK por padrão, que muitas corretoras/ativos rejeitam silenciosamente
   // (trade.Buy()/Sell() retorna false e nenhuma ordem é enviada, sem nenhum aviso visível).
   trade.SetTypeFillingBySymbol(_Symbol);
   trade.SetDeviationInPoints(10);

   mercadoFracionario = EhMercadoFracionario();

   // Restaura os ajustes feitos pelos botões na sessão anterior (se existirem); caso
   // contrário, usa os valores padrão dos inputs (primeira vez que o robô é carregado).
   if(GlobalVariableCheck(ChaveGlobal("Papeis")))
      papeisPorOperacao = ValidarQuantidade((int)GlobalVariableGet(ChaveGlobal("Papeis")));
   else
      papeisPorOperacao = ValidarQuantidade(InpQuantidadeInicial);

   if(GlobalVariableCheck(ChaveGlobal("NegDia")))
      baseNegociosDia = (int)GlobalVariableGet(ChaveGlobal("NegDia"));
   else
   {
      baseNegociosDia = MathMax(1, InpNegociosDiaInicial);
      if(baseNegociosDia % 2 == 0) baseNegociosDia++; // garante número ímpar
   }

   if(GlobalVariableCheck(ChaveGlobal("Proporcao")))
      proporcaoAtual = (ENUM_RISK_RATIO)(int)GlobalVariableGet(ChaveGlobal("Proporcao"));
   else
      proporcaoAtual = InpProporcaoInicial;

   if(GlobalVariableCheck(ChaveGlobal("Canto")))
      cantoPainelAtual = ((int)GlobalVariableGet(ChaveGlobal("Canto")) == 1) ? CORNER_RIGHT_LOWER : CORNER_RIGHT_UPPER;

   EventSetMillisecondTimer(50);

   for(int i=0; i<15; i++) ObjectDelete(0, PREFIX_TXT+IntegerToString(i));
   ObjectDelete(0, "Btn_PapelMenos");
   ObjectDelete(0, "Btn_PapelMais");
   ObjectDelete(0, "Btn_NegMenos");
   ObjectDelete(0, "Btn_NegMais");
   ObjectDelete(0, "Btn_PainelCima");
   ObjectDelete(0, "Btn_PainelBaixo");
   ObjectDelete(0, "Btn_R11");
   ObjectDelete(0, "Btn_R22");
   ObjectDelete(0, "Btn_R33");
   ObjectDelete(0, "Btn_R21");
   ObjectDelete(0, "Btn_R31");

   Print("==========================================================");
   Print("[SISTEMA PRONTO] Boleta carregada com sucesso no ativo: ", _Symbol);
   Print("[MERCADO] ", (mercadoFracionario ? "Fracionário (unidades 1-99)" : "Lote padrão (múltiplos de 100)"));
   Print("[QUANTIDADE] Solicitada: ", InpQuantidadeInicial, " | Validada/Ajustada: ", papeisPorOperacao);
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
   ObjectDelete(0, "Btn_PapelMenos");
   ObjectDelete(0, "Btn_PapelMais");
   ObjectDelete(0, "Btn_NegMenos");
   ObjectDelete(0, "Btn_NegMais");
   ObjectDelete(0, "Btn_PainelCima");
   ObjectDelete(0, "Btn_PainelBaixo");
   ObjectDelete(0, "Btn_R11");
   ObjectDelete(0, "Btn_R22");
   ObjectDelete(0, "Btn_R33");
   ObjectDelete(0, "Btn_R21");
   ObjectDelete(0, "Btn_R31");
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
   if(operacaoPendente)
   {
      AtualizarLinhasCustomizadas();
   }

   AtualizarPainelVisualEmTempoReal();
   ProcessarSomDeSaidaPendente();
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
      if(sparam == "Btn_R11")
      {
         proporcaoAtual = RATIO_1_1;
         GlobalVariableSet(ChaveGlobal("Proporcao"), (double)proporcaoAtual);
         ChartRedraw(0);
      }
      else if(sparam == "Btn_R22")
      {
         proporcaoAtual = RATIO_2_2;
         GlobalVariableSet(ChaveGlobal("Proporcao"), (double)proporcaoAtual);
         ChartRedraw(0);
      }
      else if(sparam == "Btn_R33")
      {
         proporcaoAtual = RATIO_3_3;
         GlobalVariableSet(ChaveGlobal("Proporcao"), (double)proporcaoAtual);
         ChartRedraw(0);
      }
      else if(sparam == "Btn_R21")
      {
         proporcaoAtual = RATIO_2_1;
         GlobalVariableSet(ChaveGlobal("Proporcao"), (double)proporcaoAtual);
         ChartRedraw(0);
      }
      else if(sparam == "Btn_R31")
      {
         proporcaoAtual = RATIO_3_1;
         GlobalVariableSet(ChaveGlobal("Proporcao"), (double)proporcaoAtual);
         ChartRedraw(0);
      }
      else if(sparam == "Btn_PapelMenos")
      {
         if(mercadoFracionario)
            papeisPorOperacao = (int)MathMax(1, papeisPorOperacao - 1);
         else
            papeisPorOperacao = (int)MathMax(100, papeisPorOperacao - 100);
         GlobalVariableSet(ChaveGlobal("Papeis"), (double)papeisPorOperacao);
         ChartRedraw(0);
      }
      else if(sparam == "Btn_PapelMais")
      {
         if(mercadoFracionario)
            papeisPorOperacao = (int)MathMin(99, papeisPorOperacao + 1);
         else
            papeisPorOperacao = papeisPorOperacao + 100;
         GlobalVariableSet(ChaveGlobal("Papeis"), (double)papeisPorOperacao);
         ChartRedraw(0);
      }
      else if(sparam == "Btn_NegMenos")
      {
         baseNegociosDia = MathMax(1, baseNegociosDia - 2);
         GlobalVariableSet(ChaveGlobal("NegDia"), (double)baseNegociosDia);
         ChartRedraw(0);
      }
      else if(sparam == "Btn_NegMais")
      {
         baseNegociosDia = baseNegociosDia + 2;
         GlobalVariableSet(ChaveGlobal("NegDia"), (double)baseNegociosDia);
         ChartRedraw(0);
      }
      else if(sparam == "Btn_PainelCima")
      {
         LimparObjetosPainel();
         cantoPainelAtual = CORNER_RIGHT_UPPER;
         GlobalVariableSet(ChaveGlobal("Canto"), 0.0);
         AtualizarPainelVisualEmTempoReal();
         ChartRedraw(0);
      }
      else if(sparam == "Btn_PainelBaixo")
      {
         LimparObjetosPainel();
         cantoPainelAtual = CORNER_RIGHT_LOWER;
         GlobalVariableSet(ChaveGlobal("Canto"), 1.0);
         AtualizarPainelVisualEmTempoReal();
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

      int maxOrdensPermitidas = baseNegociosDia * 2;
      int operacoesFeitasHoje = CalcularOperacoesDoDia();

      if(operacoesFeitasHoje >= maxOrdensPermitidas)
      {
         globalMensagemStatus = "Limite de ordens atingido! Já deu por hoje.";
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

//--- Detecta se o ticker é do mercado fracionário (termina com "F")
bool EhMercadoFracionario()
{
   int len = StringLen(_Symbol);
   if(len == 0) return false;
   ushort ultimoChar = StringGetCharacter(_Symbol, len - 1);
   return (ultimoChar == 'F' || ultimoChar == 'f');
}

//--- Ajusta a quantidade informada às regras de lote do mercado brasileiro:
//--- Lote padrão = múltiplos de 100 | Mercado fracionário (ticker + "F") = unidades de 1 a 99
int ValidarQuantidade(int quantidadeDesejada)
{
   int quantidadeFinal = quantidadeDesejada;

   if(mercadoFracionario)
   {
      if(quantidadeFinal < 1)  quantidadeFinal = 1;
      if(quantidadeFinal > 99) quantidadeFinal = 99;
   }
   else
   {
      if(quantidadeFinal < 100)
         quantidadeFinal = 100;
      else
         quantidadeFinal = (int)MathRound(quantidadeFinal / 100.0) * 100;
   }

   return quantidadeFinal;
}

double ArredondarParaPassoDoPreco(double valorReais)
{
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickSize <= 0) return NormalizeDouble(valorReais, _Digits);
   return NormalizeDouble(MathRound(valorReais / tickSize) * tickSize, _Digits);
}

//--- Retorna o preço de referência atual (meio do spread) usado para estimar os alvos no painel
double ObterPrecoReferenciaAtual()
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(bid <= 0 || ask <= 0) return 0.0;
   return (bid + ask) / 2.0;
}

// Retorna o multiplicador do percentual base para o SL, de acordo com a proporção escolhida
double ObterMultiplicadorSL()
{
   switch(proporcaoAtual)
   {
      case RATIO_1_1: return 1.0; // 1%
      case RATIO_2_2: return 2.0; // 2%
      case RATIO_3_3: return 3.0; // 3%
      case RATIO_2_1: return 1.0; // 1%
      case RATIO_3_1: return 1.0; // 1%
      default:        return 1.0;
   }
}

// Retorna o fator multiplicador para o cálculo do Gain em relação ao Loss configurado
double ObterFatorMultiplicadorGain()
{
   switch(proporcaoAtual)
   {
      case RATIO_1_1: return 1.0;
      case RATIO_2_2: return 1.0; // Mantém proporção 1:1, mas com amplitude 2% maior
      case RATIO_3_3: return 1.0; // Mantém proporção 1:1, mas com amplitude 3% maior
      case RATIO_2_1: return 2.0; // Gain = 2x Loss (1% para 2%)
      case RATIO_3_1: return 3.0; // Gain = 3x Loss (1% para 3%)
      default:        return 2.0;
   }
}

// Retorna a string legível da proporção para exibição no painel
string ObterTextoProporcaoRisco()
{
   switch(proporcaoAtual)
   {
      case RATIO_1_1: return "1:1";
      case RATIO_2_2: return "2:2";
      case RATIO_3_3: return "3:3";
      case RATIO_2_1: return "1:2";
      case RATIO_3_1: return "1:3";
      default:        return "1:2";
   }
}

// Calcula o valor de SL e TP em R$, com base no percentual do preço de referência informado
void CalcularValoresSLTP(double precoReferencia, double &valorSL, double &valorTP, double &pctSL, double &pctTP)
{
   double baseP = InpPercentualBase / 100.0; // percentual base (ex.: 1.0% -> 0.01)

   pctSL = baseP * ObterMultiplicadorSL();
   pctTP = pctSL * ObterFatorMultiplicadorGain();

   valorSL = ArredondarParaPassoDoPreco(precoReferencia * pctSL);
   valorTP = ArredondarParaPassoDoPreco(precoReferencia * pctTP);
}

void EnviarOrdemMercado()
{
   int maxOrdensPermitidas = baseNegociosDia * 2;
   int operacoesFeitasHoje = CalcularOperacoesDoDia();

   if(operacoesFeitasHoje >= maxOrdensPermitidas)
   {
      globalMensagemStatus = "Limite de ordens atingido! Já deu por hoje.";
      ApagarLinhasProjecao();
      return;
   }

   int loteParaEnviar = papeisPorOperacao;
   bool ordemOk = false;

   // A ordem é enviada SEM SL/TP - eles são calculados e aplicados logo abaixo, com base
   // no preço real de EXECUÇÃO da posição (POSITION_PRICE_OPEN), e não no preço de mercado
   // no instante em que a ordem foi enviada (que pode divergir por slippage/requote).
   if(tipoOperacao == 1)
   {
      ordemOk = trade.Buy(loteParaEnviar, _Symbol, 0.0, 0.0, 0.0, "Compra " + ObterTextoProporcaoRisco());
   }
   else if(tipoOperacao == 2)
   {
      ordemOk = trade.Sell(loteParaEnviar, _Symbol, 0.0, 0.0, 0.0, "Venda " + ObterTextoProporcaoRisco());
   }

   if(ordemOk)
   {
      if(PositionSelect(_Symbol))
      {
         double precoExecucao = PositionGetDouble(POSITION_PRICE_OPEN);
         long   tipoPosAberta = PositionGetInteger(POSITION_TYPE);

         double valorSL, valorTP, pctSL, pctTP;
         CalcularValoresSLTP(precoExecucao, valorSL, valorTP, pctSL, pctTP);

         double slFinal = 0, tpFinal = 0;
         if(tipoPosAberta == POSITION_TYPE_BUY)
         {
            slFinal = NormalizeDouble(precoExecucao - valorSL, _Digits);
            tpFinal = NormalizeDouble(precoExecucao + valorTP, _Digits);
         }
         else
         {
            slFinal = NormalizeDouble(precoExecucao + valorSL, _Digits);
            tpFinal = NormalizeDouble(precoExecucao - valorTP, _Digits);
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
   double precoReferencia = 0;
   double slProjetado = 0;
   double tpProjetado = 0;
   color corEntrada = clrNONE;

   double valorSL, valorTP, pctSL, pctTP;

   if(tipoOperacao == 1)
   {
      precoReferencia = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      CalcularValoresSLTP(precoReferencia, valorSL, valorTP, pctSL, pctTP);
      slProjetado     = precoReferencia - valorSL;
      tpProjetado     = precoReferencia + valorTP;
      corEntrada      = clrDodgerBlue;
   }
   else if(tipoOperacao == 2)
   {
      precoReferencia = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      CalcularValoresSLTP(precoReferencia, valorSL, valorTP, pctSL, pctTP);
      slProjetado     = precoReferencia + valorSL;
      tpProjetado     = precoReferencia - valorTP;
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

void CriarBotao(string nome, string texto, int x, int y, int largura, int altura, bool destacado = false)
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
   ObjectSetInteger(0, nome, OBJPROP_BGCOLOR, destacado ? clrSeaGreen : clrDarkSlateGray);
   ObjectSetInteger(0, nome, OBJPROP_FONTSIZE, 9);
}

//+------------------------------------------------------------------+
//| Painel principal - 10 linhas, ordem espelhada conforme o canto    |
//| (linha 2 é dedicada aos botões de proporção, sem texto próprio)   |
//+------------------------------------------------------------------+
void AtualizarPainelVisualEmTempoReal()
{
   int maxOrdensPermitidas = baseNegociosDia * 2;
   int operacoesFeitasHoje = CalcularOperacoesDoDia();
   bool limiteOrdensAtingido = (operacoesFeitasHoje >= maxOrdensPermitidas);

   if(limiteOrdensAtingido)
   {
      globalMensagemStatus = "Basta por hoje! (Limite de " + IntegerToString(maxOrdensPermitidas) + " ordens atingido)";
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
   color corPosicao = clrDarkGray;

   if(PositionSelect(_Symbol))
   {
      posicaoEstavaAberta = true;
      ultimoTicketPosicaoAberta = PositionGetInteger(POSITION_IDENTIFIER);
      if(!limiteOrdensAtingido)
         globalMensagemStatus = "Ordem executada! (CTRL + Enter) para Zerar";

      long tipoPos = PositionGetInteger(POSITION_TYPE);
      double lucroFinanceiro = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
      ultimoLucroFlutuantePosicao = lucroFinanceiro;

      string tipoStr = (tipoPos == POSITION_TYPE_BUY) ? "Compra" : "Venda";
      int volumePos = (int)PositionGetDouble(POSITION_VOLUME);
      int volumePosSinal = (tipoPos == POSITION_TYPE_BUY) ? volumePos : -volumePos;

      string valorFormatado = DoubleToString(lucroFinanceiro, 2);
      StringReplace(valorFormatado, ".", ",");

      textoPosicao = StringFormat("Posição (%d %s)", volumePosSinal, _Symbol);
      corPosicao = (volumePosSinal > 0) ? clrLimeGreen : (volumePosSinal < 0 ? clrRed : clrDarkGray);

      color corPnLGrafico = (lucroFinanceiro > 0.0) ? clrLimeGreen : (lucroFinanceiro < 0.0 ? clrRed : clrDarkGray);
      AtualizarLabelGraficoPreco(StringFormat("R$ %s", valorFormatado), corPnLGrafico, true);
   }
   else
   {
      if(posicaoEstavaAberta)
      {
         aguardandoSomSaida = true;
         tentativasSomSaida = 0;
         if(!limiteOrdensAtingido)
            globalMensagemStatus = "(C) Compra | (V) Venda | (Enter) Envia | (CTRL+Enter) Zera";
         posicaoEstavaAberta = false;
      }
      ObjectDelete(0, LABEL_PRECO_POSICAO);
   }

   // ---- PnL diário ----
   double totalDoDia = CalcularResultadoFinanceiroDoDia();
   string strTotalDia = DoubleToString(totalDoDia, 2); StringReplace(strTotalDia, ".", ",");
   string textoPnLDiario = StringFormat("PnL diário: R$ %s | Operações: %d", strTotalDia, operacoesFeitasHoje);
   color corPnLDiario = (totalDoDia > 0.0) ? clrLimeGreen : (totalDoDia < 0.0 ? clrRed : clrDarkGray);

   // ---- PnL mensal ----
   double totalDoMes = CalcularResultadoFinanceiroDoMes();
   string strTotalMes = DoubleToString(totalDoMes, 2); StringReplace(strTotalMes, ".", ",");
   string textoPnLMensal = StringFormat("PnL mensal: R$ %s | Operações: %d", strTotalMes, CalcularOperacoesDoMes());
   color corPnLMensal = (totalDoMes > 0.0) ? clrLimeGreen : (totalDoMes < 0.0 ? clrRed : clrDarkGray);

   // ---- Proporção / SL / TP ----
   double precoRefPainel = ObterPrecoReferenciaAtual();
   double exSL = 0, exTP = 0, exPctSL = 0, exPctTP = 0;
   if(precoRefPainel > 0)
      CalcularValoresSLTP(precoRefPainel, exSL, exTP, exPctSL, exPctTP);

   string textoProporcao = StringFormat("Proporção (%s): SL = R$ %s (%.1f%%) | TP = R$ %s (%.1f%%)",
                                         ObterTextoProporcaoRisco(),
                                         FormatarReais(exSL), exPctSL*100.0,
                                         FormatarReais(exTP), exPctTP*100.0);

   // ---- Papéis por operação ----
   string textoPapeis = StringFormat("Quantidade: %d %s", papeisPorOperacao, (mercadoFracionario ? "(Fracionário)" : "(Lote Padrão)"));

   // ---- Negócios por dia ----
   string textoNegocios = StringFormat("Negócios por dia: %d", baseNegociosDia);

   // ---- Status (última linha) ----
   string textoStatus = globalMensagemStatus;
   color corStatus = limiteOrdensAtingido ? clrRed : clrBlack;

   // Índices 0..8 correspondem às linhas 1..9 da especificação, na ordem do painel "em cima".
   // Quando o painel está embaixo, o próprio canto (CORNER_RIGHT_LOWER) já inverte a
   // direção em que o Y cresce, espelhando a ordem visual das linhas automaticamente.
   CriarTextoLabel(PREFIX_TXT+"0", textoPnLMensal,  MARGEM_DIREITA_TEXTO, GetLinhaY(0), 10, corPnLMensal, cantoPainelAtual);
   // O separador fica a GAP_PROPORCAO_BOTOES pixels dos botões (índice 2) - o mesmo espaço
   // usado entre os botões e a linha "Proporção" (índice 3) - por isso o cálculo é feito
   // diretamente a partir de GetLinhaY(2), em vez de OffsetParaBaixo, que produziria um
   // espaço diferente em cada canto.
   int gapProporcaoBotoes = LINE_HEIGHT + GAP_EXTRA_PROPORCAO;
   int extraSeparador1 = (cantoPainelAtual == CORNER_RIGHT_UPPER) ? 16 : 0; // só soma no canto superior
   CriarSeparador(PREFIX_TXT+"1", MARGEM_DIREITA_TEXTO, GetLinhaY(2) - gapProporcaoBotoes + extraSeparador1, LARGURA_SEPARADOR, clrSilver, cantoPainelAtual);
   // Índice 2 é uma linha dedicada só para os botões de proporção (ver abaixo) - sem texto próprio,
   // para não sobrepor o texto da linha 3 (Proporção/SL/TP).
   CriarTextoLabel(PREFIX_TXT+"3", textoProporcao,  MARGEM_DIREITA_TEXTO, GetLinhaY(3), 10, clrDodgerBlue, cantoPainelAtual);
   CriarTextoLabel(PREFIX_TXT+"4", textoPapeis,     MARGEM_DIREITA_TEXTO, GetLinhaY(4), 10, clrSteelBlue, cantoPainelAtual);
   CriarTextoLabel(PREFIX_TXT+"5", textoNegocios,   MARGEM_DIREITA_TEXTO, GetLinhaY(5), 10, clrSteelBlue, cantoPainelAtual);
   CriarSeparador(PREFIX_TXT+"6", MARGEM_DIREITA_TEXTO, GetLinhaY(6)+OffsetParaBaixo(8), LARGURA_SEPARADOR, clrSilver, cantoPainelAtual);
   CriarTextoLabel(PREFIX_TXT+"7", textoPnLDiario,  MARGEM_DIREITA_TEXTO, GetLinhaY(7), 10, corPnLDiario, cantoPainelAtual);
   CriarTextoLabel(PREFIX_TXT+"8", textoPosicao,    MARGEM_DIREITA_TEXTO, GetLinhaY(8), 10, corPosicao, cantoPainelAtual);
   CriarTextoLabel(PREFIX_TXT+"9", textoStatus,     MARGEM_DIREITA_TEXTO, GetLinhaY(9), 10, corStatus, cantoPainelAtual);

   // Botões da linha 2 - 5 botões de proporção Loss:Gain, em linha própria (imediatamente abaixo
   // do texto "Proporção"), alinhados à direita como os demais pares de botões (x=60 é a borda
   // direita comum a todas as linhas de botão do painel).
   CriarBotao("Btn_R11", "1:1", 200, GetLinhaY(2)+2, 32, 16, proporcaoAtual == RATIO_1_1);
   CriarBotao("Btn_R22", "2:2", 166, GetLinhaY(2)+2, 32, 16, proporcaoAtual == RATIO_2_2);
   CriarBotao("Btn_R33", "3:3", 132, GetLinhaY(2)+2, 32, 16, proporcaoAtual == RATIO_3_3);
   CriarBotao("Btn_R21", "1:2", 98,  GetLinhaY(2)+2, 32, 16, proporcaoAtual == RATIO_2_1);
   CriarBotao("Btn_R31", "1:3", 64,  GetLinhaY(2)+2, 32, 16, proporcaoAtual == RATIO_3_1);

   // Botões da linha 4 - quantidade (papéis por operação)
   CriarBotao("Btn_PapelMenos", "-", 89, GetLinhaY(4)+2, 28, 16);
   CriarBotao("Btn_PapelMais",  "+", 60,  GetLinhaY(4)+2, 28, 16);

   // Botões da linha 5 - negócios por dia (+2/-2)
   CriarBotao("Btn_NegMenos", "-2", 89, GetLinhaY(5)+3, 28, 16);
   CriarBotao("Btn_NegMais",  "+2", 60,  GetLinhaY(5)+3, 28, 16);

   // Botões da linha 7 - mover painel para cima/baixo (apenas um visível por vez)
   CriarBotao("Btn_PainelBaixo", "▼", 60, GetLinhaY(7), 28, 16);
   CriarBotao("Btn_PainelCima",  "▲", 60, GetLinhaY(7), 28, 16);
   SetObjVisivel("Btn_PainelBaixo", cantoPainelAtual == CORNER_RIGHT_UPPER);
   SetObjVisivel("Btn_PainelCima",  cantoPainelAtual == CORNER_RIGHT_LOWER);

   ChartRedraw(0);
}

//--- Formata um valor double em formato monetário brasileiro (vírgula decimal)
string FormatarReais(double valor)
{
   string s = DoubleToString(valor, 2);
   StringReplace(s, ".", ",");
   return s;
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