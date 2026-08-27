//+------------------------------------------------------------------+
//| RiscoConfigAtivos.mqh                                            |
//| Configuração por ativo da boleta de Gerenciamento de Risco.       |
//|                                                                    |
//| Este arquivo é o ÚNICO lugar que deve mudar quando você:          |
//|   - ajustar a tabela de fases de um ativo já suportado;           |
//|   - adicionar um novo ativo (basta uma nova entrada em             |
//|     ConfigsDisponiveis[] - o RiscoCore.mqh não muda).             |
//|                                                                    |
//| IMPORTANTE: as fórmulas de Acúmulo/LFT e a conversão de SL/TP são |
//| DIFERENTES por ativo por decisão testada e confirmada (não é bug):|
//|   WDO -> FORMULA_LOTE_MAX_FASE + CONV_DIRETA           (10,0 R$/pt)|
//|   CCM -> FORMULA_LOTE_MAX_FASE + CONV_MULTIPLICA_POINT (4,5 R$/pt)|
//|   WIN -> FORMULA_PAPEIS_USUARIO + CONV_MULTIPLICA_POINT           |
//| O multiplicador financeiro de FORMULA_LOTE_MAX_FASE vem sempre de |
//| valorPorPontoPorLote - por isso WDO e CCM usam a mesma fórmula no |
//| RiscoCore.mqh mesmo tendo constantes diferentes (10,0 vs 4,5).    |
//| Ao adicionar um ativo novo, valide com testes reais qual dos dois |
//| modos (ou um novo modo) corresponde ao comportamento correto      |
//| antes de ligar o EA em conta real.                                |
//+------------------------------------------------------------------+
#property strict

// Modo de conversão de "pontos" (como usados na tabela de fases) para a unidade de
// preço do símbolo:
//   CONV_DIRETA           -> usa o valor em pontos diretamente na conta de preço
//                             (validado para o WDO)
//   CONV_MULTIPLICA_POINT -> multiplica por _Point antes de somar/subtrair do preço
//                             (validado para o WIN)
enum ModoConversaoSLTP
{
   CONV_DIRETA,
   CONV_MULTIPLICA_POINT
};

// Modo das fórmulas de Acúmulo progressivo/regressivo e LFT:
//   FORMULA_LOTE_MAX_FASE  -> usa o Lote Max FIXO da fase (TabelaFases[fase].loteMax)
//                             (validado para o WDO)
//   FORMULA_PAPEIS_USUARIO -> usa a quantidade de papéis (V) escolhida pelo usuário,
//                             dividido por 50 (validado para o WIN)
enum ModoFormulaRisco
{
   FORMULA_LOTE_MAX_FASE,
   FORMULA_PAPEIS_USUARIO
};

// Uma linha da tabela de fases (em PONTOS por operação, não total financeiro diário).
struct StructFase
{
   double gainPontos;   // GAIN (pontos) - alvo de ganho em pontos por operação
   double lossPontos;   // LOSS (pontos) - alvo de perda em pontos por operação (valor negativo)
   int    loteMax;      // Lote Max - quantidade máxima de papéis negociáveis no dia (fixo da fase)
};

// Configuração completa de um ativo - tudo que o RiscoCore.mqh precisa para operar
// corretamente naquele símbolo, sem nenhum "if" espalhado pelo código.
struct ConfigAtivo
{
   string             nomeAtivo;             // rótulo legível (ex.: "WDO - Minidólar")
   string             prefixoSimbolo;        // prefixo esperado do _Symbol (ex.: "WDO"); casado com StringFind(_Symbol, prefixo)==0
   StructFase         tabelaFases[11];       // índice 0 não usado; fases 1..10
   double             valorPorPontoPorLote;  // R$ por ponto por papel (usado no travamento de SL pelo LFT)
   ModoConversaoSLTP  modoConversaoSLTP;
   ModoFormulaRisco   modoFormulaRisco;
   int                casasDecimaisFase;     // casas decimais ao exibir SL/TP da fase no painel (WDO=1, WIN=0, CCM=1)
   string             unidadePontosLabel;    // rótulo exibido no painel para "pontos" (WDO/WIN="pts", CCM="centavos")
};

//+------------------------------------------------------------------+
//| Tabela de fases - WDO (Minidólar)                                 |
//+------------------------------------------------------------------+
StructFase TabelaFasesWDO[11] =
{
   { 0.0, 0.0,  0 },   // Índice 0 (Não usado)
   { 2.5, -2.5,  1 },   // Fase 1
   { 3.0, -3.0,  2 },   // Fase 2
   { 3.5, -3.5,  3 },   // Fase 3
   { 4.0, -3.5,  4 },   // Fase 4
   { 4.5, -4.0,  5 },   // Fase 5
   { 5.0, -4.5,  6 },   // Fase 6
   { 5.5, -5.0,  7 },   // Fase 7
   { 6.0, -5.0,  8 },   // Fase 8
   { 6.5, -5.5,  9 },   // Fase 9
   { 7.0, -6.0, 10 }    // Fase 10
};

//+------------------------------------------------------------------+
//| Tabela de fases - WIN (Miniíndice)                                |
//+------------------------------------------------------------------+
StructFase TabelaFasesWIN[11] =
{
   {   0.0,    0.0,  0 },   // Índice 0 (Não usado)
   { 150.0, -150.0,  1 },   // Fase 1
   { 200.0, -200.0,  2 },   // Fase 2
   { 250.0, -250.0,  3 },   // Fase 3
   { 300.0, -250.0,  4 },   // Fase 4
   { 350.0, -300.0,  5 },   // Fase 5
   { 400.0, -350.0,  6 },   // Fase 6
   { 450.0, -400.0,  7 },   // Fase 7
   { 500.0, -400.0,  8 },   // Fase 8
   { 550.0, -450.0,  9 },   // Fase 9
   { 600.0, -500.0, 10 }    // Fase 10
};

//+------------------------------------------------------------------+
//| Tabela de fases - CCM (Milho)                                     |
//| "Pontos" aqui equivalem a CENTAVOS (R$ 0,01) - por isso o ativo   |
//| usa CONV_MULTIPLICA_POINT: o _Point do CCM (0,01) já É o centavo. |
//+------------------------------------------------------------------+
StructFase TabelaFasesCCM[11] =
{
   { 0.0,  0.0,  0 },   // Índice 0 (Não usado)
   { 10.0, -10.0,  1 },   // Fase 1
   { 12.0, -12.0,  2 },   // Fase 2
   { 14.0, -14.0,  3 },   // Fase 3
   { 16.0, -14.0,  4 },   // Fase 4
   { 18.0, -16.0,  5 },   // Fase 5
   { 20.0, -18.0,  6 },   // Fase 6
   { 22.0,-20.0,  7 },   // Fase 7
   { 24.0,-20.0,  8 },   // Fase 8
   { 26.0,-22.0,  9 },   // Fase 9
   { 28.0,-24.0, 10 }    // Fase 10
};

//+------------------------------------------------------------------+
//| Registro central de ativos suportados.                            |
//| Para adicionar um novo ativo: crie sua StructFase[11] acima e     |
//| adicione uma linha aqui - nenhum outro arquivo precisa mudar.     |
//+------------------------------------------------------------------+
ConfigAtivo ConfigsDisponiveis[] =
{
   { "WDO - Minidólar",   "WDO", {}, 10.00, CONV_DIRETA,           FORMULA_LOTE_MAX_FASE,   1, "pts"      },
   { "WIN - Miniíndice",  "WIN", {},  0.20, CONV_MULTIPLICA_POINT, FORMULA_PAPEIS_USUARIO,  0, "pts"      },
   { "CCM - Milho",       "CCM", {},  4.50, CONV_MULTIPLICA_POINT, FORMULA_LOTE_MAX_FASE,   1, "centavos" }
};

// Copia a tabela de fases correta para dentro de cada ConfigAtivo. Feito em uma função
// (chamada uma vez, do DetectarConfigAtivo) em vez de inicializar o array de structs
// diretamente, porque o MQL5 não permite inicializar um membro array-de-struct dentro
// de um inicializador de array de structs.
void PrepararTabelasDosAtivos()
{
   ArrayCopy(ConfigsDisponiveis[0].tabelaFases, TabelaFasesWDO);
   ArrayCopy(ConfigsDisponiveis[1].tabelaFases, TabelaFasesWIN);
   ArrayCopy(ConfigsDisponiveis[2].tabelaFases, TabelaFasesCCM);
}

// Detecta a config correta a partir do símbolo do gráfico atual. Usa StringFind(...)==0
// (casa pelo início do nome) para que contratos futuros com sufixo de vencimento
// (ex.: "WDOF26", "WINZ25") continuem sendo reconhecidos sem precisar atualizar esta
// lista a cada troca de mês.
// Retorna false se nenhum ativo da lista bater com o símbolo - o chamador (OnInit) deve
// tratar isso como falha de inicialização, nunca como "usar uma config qualquer".
bool DetectarConfigAtivo(string simbolo, ConfigAtivo &configOut)
{
   PrepararTabelasDosAtivos();

   for(int i = 0; i < ArraySize(ConfigsDisponiveis); i++)
   {
      if(StringFind(simbolo, ConfigsDisponiveis[i].prefixoSimbolo) == 0)
      {
         configOut = ConfigsDisponiveis[i];
         return true;
      }
   }
   return false;
}