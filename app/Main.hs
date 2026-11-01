module Main (main) where

import Avionics.Compose
import Avionics.Crem
import Avionics.Diagram
import Avionics.Power
import qualified Avionics.Naive as N
import Avionics.StateMonad
import Control.Monad (forM_, unless)
import Crem.StateMachine
import Data.Functor.Identity (Identity (..))
import qualified Data.Text as T
import qualified Data.Text.IO as T
import System.Directory (createDirectoryIfMissing)
import System.IO (hSetEncoding, stdout, utf8)

-- | Executa uma lista de entradas e devolve as saídas, descartando a máquina final.
runAll :: Monad m => StateMachineT m a b -> [a] -> m [b]
runAll _ [] = pure []
runAll m (i : is) = do
  (o, m') <- run m i
  os <- runAll m' is
  pure (o : os)

-- | Todas as sequências de eventos com até n eventos.
sequencesUpTo :: Int -> [[AvEvent]]
sequencesUpTo 0 = [[]]
sequencesUpTo n = [] : [e : es | e <- [minBound' ..], es <- sequencesUpTo (n - 1)]
  where
    minBound' = TakeoffSignal

main :: IO ()
main = do
  hSetEncoding stdout utf8
  let events = [TakeoffSignal, CriticalBattery, LandedSignal, SystemCutoff]

  putStrLn "=== Seção 1: FSM ingênua (pattern matching exaustivo) ==="
  let (qFinal, outsNaive) = N.runMealy N.Grounded events
  putStrLn $ "Eventos:      " ++ show events
  putStrLn $ "Saídas:       " ++ show outsNaive
  putStrLn $ "Estado final: " ++ show qFinal

  putStrLn ""
  putStrLn "=== Seção 2: State Monad e composição de Kleisli ==="
  let (outsST, qST) = runST (runEvents events) N.Grounded
  putStrLn $ "Saídas:       " ++ show outsST
  putStrLn $ "Estado final: " ++ show qST
  forM_ lawChecks $ \(name, ok) ->
    putStrLn $ (if ok then "  [ok]   " else "  [FALHA] ") ++ name
  unless (all snd lawChecks) $ putStrLn "ATENÇÃO: alguma verificação falhou."

  putStrLn ""
  putStrLn "=== Seção 3: CREM (topologia verificada em tempo de compilação) ==="
  outsCrem <- runAll (avionicsMachine SGrounded) events
  putStrLn $ "Saídas CREM:  " ++ show outsCrem
  putStrLn $ "Igual à versão ingênua e à State Monad? " ++ show (outsCrem == outsNaive && outsNaive == outsST)
  let allSeqs = sequencesUpTo 3
      same es =
        runIdentity (runAll (avionicsMachine SGrounded) es) == snd (N.runMealy N.Grounded es)
  putStrLn $
    "CREM == ingênua em todas as " ++ show (length allSeqs)
      ++ " sequências de até 3 eventos a partir de Grounded? " ++ show (all same allSeqs)

  putStrLn ""
  putStrLn "=== Seção 4a: Parallel (aviônica || energia), estados independentes ==="
  let parInputs =
        [ (TakeoffSignal, Drain)
        , (TakeoffSignal, Drain)
        , (CriticalBattery, Recharge)
        , (LandedSignal, Recharge)
        ]
  outsPar <- runAll (uavSystem SGrounded SCharged) parInputs
  forM_ (zip parInputs outsPar) $ \(i, o) -> putStrLn $ "  " ++ show i ++ " -> " ++ show o

  putStrLn ""
  putStrLn "=== Seção 4b: Sequential (energia -> tradução -> aviônica) ==="
  putStrLn "Aviônica começa em InFlight e energia em Charged; cada uma guarda o seu estado."
  let powerInputs = [Drain, Drain, Drain, Recharge, Recharge, Drain]
  outsSeq <- runAll (powerDrivesAvionics SInFlight SCharged) powerInputs
  forM_ (zip powerInputs outsSeq) $ \(i, o) -> putStrLn $ "  " ++ show i ++ " -> " ++ show o
  putStrLn "(Right () = sem evento para a aviônica; Left o = saída da aviônica)"

  putStrLn ""
  putStrLn "=== Diagramas (módulo Render do CREM) ==="
  createDirectoryIfMissing True "output"
  T.writeFile "output/avionics_topology.mmd" avionicsDiagram
  T.writeFile "output/power_topology.mmd" powerDiagram
  T.writeFile "output/uav_product.mmd" uavProductDiagram
  case coupledFlowDiagram of
    Left err -> putStrLn $ "renderFlow falhou: " ++ err
    Right t -> do
      T.writeFile "output/coupled_flow.mmd" (T.append (T.pack "stateDiagram-v2\n") t)
      putStrLn "  gravado: output/coupled_flow.mmd"
  putStrLn "  gravado: output/avionics_topology.mmd, power_topology.mmd, uav_product.mmd"
  putStrLn "--- avionics_topology.mmd ---"
  T.putStrLn avionicsDiagram
