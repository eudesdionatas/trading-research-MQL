//+------------------------------------------------------------------+
//|         GerenciamentoRisco.mq5                                    |
//|         Boleta de Gerenciamento de Risco - multi-ativo            |
//|         (detecta WDO/WIN automaticamente pelo símbolo do gráfico) |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026"
#property version   "1.0"
#property strict
#property description "Boleta de gerenciamento de risco por fases. Tabelas específicas e validadas para o ETF GOLD11 e os futuros WIN, WDO e CCM; qualquer outro papel da B3 (Ações, ETFs, FIIs) usa uma tabela genérica, com o valor por ponto lido automaticamente do símbolo."

// A ordem dos includes importa: RiscoConfigAtivos.mqh define StructFase/ConfigAtivo,
// que RiscoCore.mqh usa. Para adicionar um novo ativo, edite só o primeiro arquivo.
#include <GerenciamentoRisco/RiscoConfigAtivos.mqh>
#include <GerenciamentoRisco/RiscoCore.mqh>

// OnInit, OnDeinit, OnTick, OnTimer e OnChartEvent estão definidos dentro de
// RiscoCore.mqh - não precisam ser repetidos aqui.