{-# LANGUAGE UnicodeSyntax #-}
module Main where

import Control.Monad.Loops (firstM)
import Data.ByteString     (ByteString, append, putStr, readFile, empty, getContents)
import Data.List           (delete, nub)
import Data.Maybe          (isJust, fromJust)
import Options.Applicative hiding (empty)
import Prelude             hiding (putStr, readFile, getContents)
import System.Posix hiding (append)
import System.Posix.Handle (hGetStatus)
import GHC.IO.Handle.FD    (stdout)


import Cat.Decorators as Decorators
import Cat.Parsers
import Cat.Types


main ∷ IO ()
main = do
    (filePaths, options) <- parseArguments
    ensureInputIsNotOutput filePaths
    concatenatedContent  <- if not (null filePaths)
                              then concatenateContent filePaths
                              else getContents
    putStr $ apply options concatenatedContent


parseArguments ∷ IO ([String], [Option])
parseArguments = merge <$> execParser argumentsParserWithInfo
    where merge (filePaths, options) = (filePaths, concat options)


argumentsParserWithInfo ∷ ParserInfo ([String], [[Option]])
argumentsParserWithInfo = info (helper <*> argumentsParser) description


description ∷ InfoMod ([String], [[Option]])
description = fullDesc <> progDesc "Print a greeting for TARGET"
                       <> header "hello - a test for optparse-applicative"


argumentsParser ∷ Parser ([String], [[Option]])
argumentsParser = (,) <$> filePathsParser <*> optionsParser


filePathsParser ∷ Parser [String]
filePathsParser = many (argument str (metavar "FILES"))


optionsParser ∷ Parser [[Option]]
optionsParser = many optionPa
    where optionPa = parser      'A'  "show-all"          "equivalent to -vET"                            [ShowNonprinting, ShowEnds, ShowTabs]
                 <|> parser      'b'  "number-nonblank"   "number nonempty output lines, overrides -n"    [NumberNonBlank]
                 <|> shortParser 'e'                      "equivalent to -vE"                             [ShowNonprinting, ShowEnds]
                 <|> parser      'E'  "show-ends"         "display $ at end of each line"                 [ShowEnds]
                 <|> parser      'n'  "number"            "number all output lines"                       [Number]
                 <|> parser      's'  "squeeze-blank"     "suppress repeated empty output lines"          [SqueezeBlank]
                 <|> shortParser 't'                      "equivalent to -vT"                             [ShowNonprinting, ShowTabs]
                 <|> parser      'T'  "show-tabs"         "display TAB characters as ^I"                  [ShowTabs]
                 <|> shortParser 'u'                      "(ignored)"                                     []
                 <|> parser      'v'  "show-nonprinting"  "use ^ and M- notation, except for LFD and TAB" [ShowNonprinting]


concatenateContent ∷ [FilePath] → IO ByteString
concatenateContent filePaths = do
    fileContent <- mapM readFile filePaths
    return $ foldl append empty fileContent


apply ∷ [Option] → ByteString → ByteString
apply opts content = foldl Decorators.decorate content (sanitize opts)


sanitize ∷ [Option] → [Option]
sanitize opts = foldl (\o f -> f o) opts functions
  where functions = [ nub,
                      \xs -> if ShowTabs `elem` xs then ShowTabs:delete ShowTabs xs else xs,
                      \xs -> if NumberNonBlank `elem` xs then delete Number xs else xs,
                      \xs -> if SqueezeBlank `elem` xs then SqueezeBlank:delete SqueezeBlank xs else xs,
                      \xs -> if ShowEnds `elem` xs then delete ShowEnds xs ++ [ShowEnds] else xs
                    ]

ensureInputIsNotOutput :: [FilePath] -> IO ()
ensureInputIsNotOutput paths = do
    stdoutFstats <- hGetStatus stdout
    let stdoutFileID = fileID stdoutFstats

    match <- (flip firstM) paths $ \path -> getFileStatus path >>= return . fileID >>= \fid -> return (fid == stdoutFileID)

    if isJust match
      then error $ fromJust match ++ ": input file is output file"
      else return ()
