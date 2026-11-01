-- ============================================================================
-- Demonstração do simulador: dois cenários em malha fechada.
-- IO só aqui (imprimir e gravar os diagramas); a simulação em si é pura.
--
--   cabal run avionics-sim              -- grava em ../../Obsidian/documentation
--   cabal run avionics-sim -- <pasta>   -- grava em <pasta>
--
-- Os arquivos novos têm prefixo `sim_trace_` e começam com uma linha de
-- marcação. O programa recusa sobrescrever um arquivo existente que não
-- tenha essa marcação, então nenhum .mmd anterior é tocado.
-- ============================================================================
module Main (main) where

import Avionics.Sim.Mermaid (marker, sequenceDiagram)
import Avionics.Sim.Scenario
import Avionics.Sim.Simulate (simulate, simulateClosed)
import Avionics.Sim.Trace
import Data.List (isPrefixOf)
import System.Directory (doesDirectoryExist, doesFileExist)
import System.Environment (getArgs)
import System.IO (IOMode (..), hGetContents', hPutStr, hSetEncoding, latin1, stdout, utf8, withFile)

scenarios :: [(String, String, Scenario)]
scenarios =
  [ ("nominal", "voo nominal: decola, a bateria cai a Low, sem emergência", nominalScenario)
  , ("emergencia", "emergência: decola e esgota a bateria; o ambiente encadeia emergência, pouso e corte", emergencyScenario)
  ]

outputDir :: [String] -> IO FilePath
outputDir (dir : _) = pure dir
outputDir [] = do
  exists <- doesDirectoryExist "../../Obsidian/documentation"
  pure (if exists then "../../Obsidian/documentation" else "output")

-- | Grava (sempre em UTF-8) só se o arquivo não existe ou foi gerado por este
-- programa. A marca é ASCII, então ler como latin1 serve para conferi-la
-- sem falhar diante de qualquer conteúdo alheio.
safeWrite :: FilePath -> String -> IO ()
safeWrite path content = do
  exists <- doesFileExist path
  mine <-
    if exists
      then withFile path ReadMode (\h -> hSetEncoding h latin1 >> (marker `isPrefixOf`) <$> hGetContents' h)
      else pure True
  if mine
    then do
      withFile path WriteMode (\h -> hSetEncoding h utf8 >> hPutStr h content)
      putStrLn ("  gravado: " ++ path)
    else putStrLn ("  RECUSADO (arquivo existente que não é meu): " ++ path)

main :: IO ()
main = do
  hSetEncoding stdout utf8
  dir <- getArgs >>= outputDir
  mapM_
    ( \(name, descr, scenario) -> do
        putStrLn ("=== Cenário: " ++ name ++ " ===")
        putStrLn descr
        putStrLn "--- malha fechada (Feedback + ambiente) ---"
        let closed = simulateClosed scenario defaultInit
        putStr (renderTrace closed)
        putStrLn "--- malha aberta, só para comparar (sem ambiente) ---"
        let open = simulate scenario defaultInit
        putStrLn
          ( "estado final: Av=" ++ show (finalAvVertex open)
              ++ " Pw=" ++ show (finalPowVertex open)
              ++ "   saídas: " ++ show (significantOutputs open)
          )
        safeWrite (dir ++ "/sim_trace_" ++ name ++ ".mmd") (sequenceDiagram name closed)
        putStrLn ""
    )
    scenarios
