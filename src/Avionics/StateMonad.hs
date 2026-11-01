-- ============================================================================
-- SEÇÃO 2 — State Monad própria e composição de Kleisli
-- ----------------------------------------------------------------------------
-- A State Monad segue o padrão de Hutton (2016), cap. 12 (§12.3): uma
-- computação com estado é uma função `s -> (a, s)` embrulhada num newtype.
-- Aqui o tipo do estado é parâmetro (`ST s a`) em vez de fixo.
--
-- A composição de Kleisli `>=>` (Milewski, 2020, cap. 4; Wadler, 1992)
-- compõe funções do tipo `a -> ST s b`. Essa composição só é associativa e só
-- tem `pure` como identidade se a instância Monad cumprir as três leis da
-- mônada. O GHC não verifica essas leis. Por isso elas são provadas abaixo,
-- à mão, para esta instância.
-- ============================================================================
module Avionics.StateMonad
  ( ST (..)
  , (>=>)
  , avionicsStep
  , runEvents
  , composeAll
  , reaction
  , lawChecks
  ) where

import Avionics.Naive

-- | Computação com estado. `runST m s` devolve o valor e o novo estado.
newtype ST s a = ST {runST :: s -> (a, s)}

instance Functor (ST s) where
  fmap g st = ST $ \s ->
    let (x, s') = runST st s
     in (g x, s')

instance Applicative (ST s) where
  pure x = ST $ \s -> (x, s)
  stf <*> stx = ST $ \s ->
    let (f, s') = runST stf s
        (x, s'') = runST stx s'
     in (f x, s'')

instance Monad (ST s) where
  st >>= f = ST $ \s ->
    let (x, s') = runST st s
     in runST (f x) s'

-- | Composição de Kleisli (o "peixe"): primeiro `f`, depois `g`, com o
-- estado passando de uma para a outra.
infixr 1 >=>
(>=>) :: (a -> ST s b) -> (b -> ST s c) -> (a -> ST s c)
f >=> g = \x -> f x >>= g

-- ----------------------------------------------------------------------------
-- LEIS DA MÔNADA PARA `ST` — PROVAS EQUACIONAIS
-- ----------------------------------------------------------------------------
-- Fontes: as três leis estão enunciadas em Hutton (2016), §12.3 ("Monad
-- laws"); o método de raciocínio equacional é o de Hutton (2016), cap. 16
-- (§16.1), cujos exercícios (§16.9, itens 7 a 10) pedem justamente verificar
-- as leis de functor, applicative e monad para Maybe, Tree e listas.
-- Bocchino (2025), §4.4 a §4.6 e §6.4, deriva as mesmas leis a partir da
-- associatividade e das identidades da composição de Kleisli.
--
-- Convenções (hipóteses deste texto, não teoremas do GHC): sem `seq` nem
-- `$!`, como Hutton (2016), §12.4, pressupõe ao tratar de functores, e com
-- computações totais, isto é, sem ⊥:
--   (a) `runST (ST g) = g` e `ST (runST m) = m` (newtype).
--   (b) `let (x, s') = e in b` equivale a `b` com `x := fst e` e `s' := snd e`;
--       quando `e` é um par explícito `(u, v)`, é `b[x:=u, s':=v]`.
--   (c) `(fst p, snd p) = p` para todo par p (pareamento sobrejetor).
--   (d) Um `let` dentro do lado direito de outro `let` pode ser "achatado":
--       `let p = (let q = e1 in e2) in b  =  let q = e1 in let p = e2 in b`,
--       desde que as variáveis de `q` não ocorram livres em `b`.
--
-- LEI 1 — identidade à esquerda:  pure a >>= f  =  f a
--     pure a >>= f
--   = ST (\s -> let (x, s') = runST (pure a) s in runST (f x) s')   -- (>>=)
--   = ST (\s -> let (x, s') = (a, s) in runST (f x) s')             -- pure, (a)
--   = ST (\s -> runST (f a) s)                                      -- (b)
--   = ST (runST (f a))                                              -- eta
--   = f a                                                           -- (a)
--
-- LEI 2 — identidade à direita:  m >>= pure  =  m
--     m >>= pure
--   = ST (\s -> let (x, s') = runST m s in runST (pure x) s')       -- (>>=)
--   = ST (\s -> let (x, s') = runST m s in (x, s'))                 -- pure, (a)
--   = ST (\s -> (fst (runST m s), snd (runST m s)))                 -- (b)
--   = ST (\s -> runST m s)                                          -- (c)
--   = ST (runST m)  =  m                                            -- eta, (a)
--
-- LEI 3 — associatividade:  (m >>= f) >>= g  =  m >>= (\x -> f x >>= g)
-- Lado esquerdo, expandindo duas vezes `>>=`:
--     (m >>= f) >>= g
--   = ST (\s -> let (y, s2) = runST (m >>= f) s in runST (g y) s2)
--   = ST (\s -> let (y, s2) = (let (x, s1) = runST m s in runST (f x) s1)
--                in runST (g y) s2)
--   = ST (\s -> let (x, s1) = runST m s
--                in let (y, s2) = runST (f x) s1
--                    in runST (g y) s2)                              -- (d)
-- Lado direito:
--     m >>= (\x -> f x >>= g)
--   = ST (\s -> let (x, s1) = runST m s
--                in runST (f x >>= g) s1)
--   = ST (\s -> let (x, s1) = runST m s
--                in let (y, s2) = runST (f x) s1
--                    in runST (g y) s2)
-- Os dois lados coincidem. (Em (d), x e s1 não ocorrem livres em
-- `runST (g y) s2` porque g, y e s2 não dependem deles.)
--
-- CONSEQUÊNCIAS PARA A COMPOSIÇÃO DE KLEISLI (f >=> g = \x -> f x >>= g):
--   pure >=> f  =  \x -> pure x >>= f  =  \x -> f x  =  f          (lei 1)
--   f >=> pure  =  \x -> f x >>= pure  =  \x -> f x  =  f          (lei 2)
--   (f >=> g) >=> h
--     = \x -> (f x >>= g) >>= h
--     = \x -> f x >>= (\y -> g y >>= h)                             (lei 3)
--     = \x -> f x >>= (g >=> h)
--     = f >=> (g >=> h)
-- Logo, com objetos = tipos, morfismos = `a -> ST s b`, identidade = `pure`
-- e composição = `>=>`, tem-se uma categoria (a categoria de Kleisli de
-- `ST s`; Milewski, 2020, cap. 4; Bocchino, 2025, §7).
-- ----------------------------------------------------------------------------

-- | Um passo da FSM como computação com estado: consome um evento, emite a
-- saída e atualiza o estado, sem variável mutável.
avionicsStep :: AvEvent -> ST AvState Output
avionicsStep e = ST $ \q -> (outputOf q e, transition q e)

-- | Executa uma lista de eventos em sequência. O `do` é açúcar para `>>=`.
runEvents :: [AvEvent] -> ST AvState [Output]
runEvents [] = pure []
runEvents (e : es) = do
  o <- avionicsStep e
  os <- runEvents es
  pure (o : os)

-- | Compõe uma lista de setas de Kleisli com `>=>`, tendo `pure` como
-- elemento neutro (lei 2 garante que `f >=> pure = f`).
composeAll :: [a -> ST s a] -> a -> ST s a
composeAll = foldr (>=>) pure

-- | Uma política simples que, dada a última saída, escolhe o próximo
-- evento. Serve como seta intermediária `Output -> ST AvState AvEvent` nos
-- testes de associatividade.
reaction :: Output -> ST AvState AvEvent
reaction MsgTakeoff = pure CriticalBattery
reaction MsgEmergency = pure LandedSignal
reaction MsgLanded = pure SystemCutoff
reaction MsgShutdown = pure TakeoffSignal
reaction MsgIgnored = pure TakeoffSignal

-- ----------------------------------------------------------------------------
-- TESTES POR EXEMPLO
-- ----------------------------------------------------------------------------
-- O conjunto de estados e o de eventos são finitos, então a igualdade
-- extensional de duas computações é verificada para TODOS os 4 estados
-- iniciais e todos os 4 eventos. Isto confere os casos escolhidos; a prova
-- geral é a dedução equacional acima.

-- | Duas computações são iguais se, de cada estado inicial, produzem o mesmo
-- par (valor, estado final).
agree :: Eq b => ST AvState b -> ST AvState b -> Bool
agree m n = all (\q -> runST m q == runST n q) [minBound .. maxBound]

-- | Pares (descrição, resultado) das verificações.
lawChecks :: [(String, Bool)]
lawChecks =
  [ ( "identidade à esquerda: pure a >>= f == f a"
    , and [agree (pure a >>= avionicsStep) (avionicsStep a) | a <- evs]
    )
  , ( "identidade à direita: m >>= pure == m"
    , and [agree (avionicsStep e >>= pure) (avionicsStep e) | e <- evs]
    )
  , ( "associatividade de >>= (m, f, g do autopiloto)"
    , and
        [ agree
            ((avionicsStep e >>= reaction) >>= avionicsStep)
            (avionicsStep e >>= (\o -> reaction o >>= avionicsStep))
        | e <- evs
        ]
    )
  , ( "Kleisli: pure >=> f == f"
    , and [agree ((pure >=> avionicsStep) e) (avionicsStep e) | e <- evs]
    )
  , ( "Kleisli: f >=> pure == f"
    , and [agree ((avionicsStep >=> pure) e) (avionicsStep e) | e <- evs]
    )
  , ( "Kleisli: (f >=> g) >=> h == f >=> (g >=> h) (todas mudam o estado)"
    , and
        [ agree
            (((avionicsStep >=> reaction) >=> avionicsStep) e)
            ((avionicsStep >=> (reaction >=> avionicsStep)) e)
        | e <- evs
        ]
    )
  , ( "Kleisli: associatividade com setas que mudam o estado nas 3 posições"
    , and
        [ agree
            (((k SystemCutoff >=> k LandedSignal) >=> k TakeoffSignal) o)
            ((k SystemCutoff >=> (k LandedSignal >=> k TakeoffSignal)) o)
        | o <- outs
        ]
    )
  , ( "runEvents (State Monad) == runMealy (mapAccumL), sem mônada"
    , and
        [ let (outs', q') = runST (runEvents es) q
              (q'', outs'') = runMealy q es
           in outs' == outs'' && q' == q''
        | q <- [minBound .. maxBound]
        , es <- [[], [TakeoffSignal], [TakeoffSignal, CriticalBattery, LandedSignal, SystemCutoff], [SystemCutoff, TakeoffSignal]]
        ]
    )
  , ( "composeAll (foldr (>=>) pure) == último passo de runEvents"
    , and
        [ let es = [TakeoffSignal, CriticalBattery, LandedSignal, SystemCutoff]
              viaKleisli = runST (composeAll (map k es) MsgIgnored) q
              viaDo = let (os, q') = runST (runEvents es) q in (last os, q')
           in viaKleisli == viaDo
        | q <- [minBound .. maxBound]
        ]
    )
  ]
  where
    evs = [minBound .. maxBound] :: [AvEvent]
    outs = [MsgTakeoff, MsgEmergency, MsgLanded, MsgShutdown, MsgIgnored]
    -- seta de Kleisli que ignora a entrada e executa um evento fixo
    k :: AvEvent -> Output -> ST AvState Output
    k e = \_ -> avionicsStep e
