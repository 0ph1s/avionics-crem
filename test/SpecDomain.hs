-- ============================================================================
-- Conformidade com a ESPECIFICAÇÃO DO DOMÍNIO (spec/domain_rules.txt).
-- Rodar com:   cabal test avionics-spec-tests
--
-- A especificação foi escrita a partir do texto dos requisitos, e não do código.
-- Aqui ela é comparada com três artefatos que antes só eram comparados entre si:
--   (A) o valor da topologia do CREM;
--   (B) a função de transição ingênua (Avionics.Naive.transition);
--   (C) o destino que a ação do CREM (avionicsAction) realmente devolve.
-- O domínio é finito (4 vértices x 4 eventos), então as verificações são EXAUSTIVAS.
-- A rejeição em tempo de compilação dos pares proibidos é testada à parte, por
-- scripts/negative_matrix.sh (não dá para testar falha de compilação dentro do
-- próprio executável compilado).
-- ============================================================================
module Main (main) where

import Avionics.Crem
import qualified Avionics.Naive as N
import Control.Monad (forM)
import Crem.BaseMachine (ActionResult (..))
import Crem.Render.RenderableVertices (vertices)
import Crem.Topology (Topology (..))
import Data.Functor.Identity (Identity (..))
import Data.List (nub, sort, (\\))
import Data.Singletons (fromSing)
import System.Exit (exitFailure)
import System.IO (hSetEncoding, stdout, utf8)

type Edge = (String, String)

data Spec = Spec {specAllow :: [(String, String, String)], specForbid :: [Edge]}

parseSpec :: String -> Spec
parseSpec txt = Spec [(a, b, e) | ["allow", a, b, e] <- rows] [(a, b) | ["forbid", a, b] <- rows]
  where
    rows = [words l | l <- lines txt, not (null (words l)), take 1 l /= "#"]

check :: String -> Bool -> IO Bool
check name ok = do
  putStrLn ((if ok then "  [ok]    " else "  [FALHA] ") ++ name)
  pure ok

-- | Vértice da aviônica ingênua -> singleton do CREM, sem tabela de tradução própria.
withSing :: N.AvState -> (forall v. SAvionicsVertex v -> r) -> r
withSing N.Grounded k = k SGrounded
withSing N.InFlight k = k SInFlight
withSing N.EmergencyLanding k = k SEmergencyLanding
withSing N.Shutdown k = k SShutdown

-- | Destino que a AÇÃO do CREM devolve (lido do singleton do ActionResult).
cremDestination :: SAvionicsVertex v -> AvEvent -> AvionicsVertex
cremDestination s e = case avionicsAction s e of
  ActionResult (Identity (_, s')) -> fromSing s'

one :: IO Bool -> IO [Bool]
one = fmap pure

main :: IO ()
main = do
  hSetEncoding stdout utf8
  spec <- parseSpec <$> readFile "spec/domain_rules.txt"
  let names = map show (vertices :: [AvionicsVertex])
      allPairs = [(a, b) | a <- names, b <- names]
      identity = [(a, a) | a <- names]
      rules = specAllow spec
      allowed = [(a, b) | (a, b, _) <- rules]
      -- proibidos por omissão (mundo fechado): tudo que não é permitido nem identidade
      forbiddenAll = allPairs \\ (allowed ++ identity)
      topoEdges = [(show a, show b) | (a, bs) <- edges avionicsTopology, b <- bs]
      evs = [minBound .. maxBound] :: [AvEvent]
      qs = [minBound .. maxBound] :: [N.AvState]
      naiveStepE = [(show q, show e, show (N.transition q e)) | q <- qs, e <- evs]
      naiveStep = [(a, b) | (a, _, b) <- naiveStepE]
      cremStepE = [(show q, show e, show (withSing q (\s -> cremDestination s e))) | q <- qs, e <- evs]
      cremStep = [(a, b) | (a, _, b) <- cremStepE]
      -- eventos que a especificação associa a alguma transição
      ruled = [(a, e) | (a, _, e) <- rules]
      -- pares sem regra: convenção do projeto = o estado não muda
      unruled xs = [(a, e, b) | (a, e, b) <- xs, (a, e) `notElem` ruled]
  rs <-
    concat <$> sequence
      [ putStrLn "=== Especificação lida ===" >> pure []
      , one $ check "a especificação tem as 4 arestas permitidas do texto" (sort allowed == sort
            [("Grounded", "InFlight"), ("InFlight", "EmergencyLanding"), ("EmergencyLanding", "Grounded"), ("Grounded", "Shutdown")])
      , one $ check "a especificação proíbe explicitamente InFlight -> Shutdown" (("InFlight", "Shutdown") `elem` specForbid spec)
      , one $ check "nenhuma aresta é ao mesmo tempo permitida e proibida" (null [e | e <- allowed, e `elem` specForbid spec])
      , one $ check "todo vértice da especificação existe no tipo de vértices"
          (all (`elem` names) (concat [[a, b] | (a, b) <- allowed ++ specForbid spec]))
      , putStrLn "\n=== (A) topologia do CREM x especificação ===" >> pure []
      , one $ check "arestas da topologia == arestas permitidas pela especificação" (sort (nub topoEdges) == sort allowed)
      , one $ check ("pares proibidos por omissão: " ++ show (length forbiddenAll) ++ " de 16 (esperado 8)") (length forbiddenAll == 8)
      , one $ check "InFlight -> Shutdown está entre os proibidos e fora da topologia"
          (("InFlight", "Shutdown") `elem` forbiddenAll && ("InFlight", "Shutdown") `notElem` topoEdges)
      , one $ check "toda proibição explícita da especificação está entre os proibidos"
          (all (`elem` forbiddenAll) (specForbid spec))
      , putStrLn "\n=== (B) FSM ingênua x especificação (16 pares estado x evento) ===" >> pure []
      , one $ check "toda mudança de estado da `transition` é permitida pela especificação"
          (and [(a, b) `elem` allowed | (a, b) <- naiveStep, a /= b])
      , one $ check "nenhuma aresta permitida fica sem um evento que a realize (sem aresta morta)"
          (all (`elem` naiveStep) allowed)
      , one $ check "nenhuma transição proibida é realizada por algum evento"
          (null [p | p <- forbiddenAll, p `elem` naiveStep])
      , putStrLn "\n=== (C) ação do CREM x ingênua e x especificação ===" >> pure []
      , one $ check "destino da `avionicsAction` == destino da `transition` nos 16 pares" (cremStep == naiveStep)
      , one $ check "todo destino da `avionicsAction` é aresta permitida ou identidade"
          (and [(a, b) `elem` (allowed ++ identity) | (a, b) <- cremStep])
      , putStrLn "\n=== (D) evento -> aresta, conforme o texto dos requisitos ===" >> pure []
      , one $ check "ingênua: cada evento do texto leva exatamente ao destino da especificação"
          (and [(a, e, b) `elem` naiveStepE | (a, b, e) <- rules])
      , one $ check "CREM: cada evento do texto leva exatamente ao destino da especificação"
          (and [(a, e, b) `elem` cremStepE | (a, b, e) <- rules])
      , one $ check "convenção do projeto (não está nos requisitos): pares sem regra não mudam o estado (ingênua e CREM)"
          (and [a == b | (a, _, b) <- unruled naiveStepE ++ unruled cremStepE])
      ]
  let failures = length (filter not rs)
  putStrLn ("\n" ++ show (length rs) ++ " verificações, " ++ show failures ++ " falhas.")
  _ <- forM [() | failures > 0] (const exitFailure)
  pure ()
