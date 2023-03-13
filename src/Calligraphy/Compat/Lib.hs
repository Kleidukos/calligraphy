{-# LANGUAGE CPP #-}
{-# OPTIONS_GHC -Wno-redundant-constraints -Wno-unused-matches #-}

module Calligraphy.Compat.Lib
  ( sourceInfo,
    showContextInfo,
    readHieFileCompat,
    isInstanceNode,
    isTypeSignatureNode,
    isInlineNode,
    isMinimalNode,
    isDerivingNode,
    showAnns,
    mergeSpans,
    isPointSpan,
    getHieFiles,
  )
where

import qualified Calligraphy.Compat.GHC as GHC
import Calligraphy.Util.Lens
import Data.IORef
import qualified Data.Set as Set
import Control.Monad

#if MIN_VERSION_ghc(9,0,0)
import GHC.Iface.Ext.Binary
import GHC.Iface.Ext.Types
import GHC.Types.Name.Cache
import GHC.Types.SrcLoc
import GHC.Utils.Outputable (ppr, showSDocUnsafe)
import qualified Data.Map as Map
#else
import HieBin
import HieTypes
import NameCache
import SrcLoc
#endif

getHieFiles :: [FilePath] -> IO [HieFile]
#if MIN_VERSION_ghc(9,4,0)

getHieFiles filePaths = do
  ref <- newIORef =<< GHC.initNameCache 'z' []
  forM filePaths (readHieFileWithWarning ref)

#else

getHieFiles filePaths = do
    uniqSupply <- GHC.mkSplitUniqSupply 'z'
    ref <- newIORef (GHC.initNameCache uniqSupply [])
    forM filePaths (readHieFileWithWarning ref)

#endif

readHieFileWithWarning :: IORef GHC.NameCache -> FilePath -> IO GHC.HieFile
readHieFileWithWarning ref path = do
  GHC.HieFileResult fileHieVersion fileGHCVersion hie <- readHieFileCompat ref path
  when (GHC.hieVersion /= fileHieVersion) $ do
    putStrLn $ "WARNING: version mismatch in " <> path
    putStrLn $ "    The hie files in this project were generated with GHC version: " <> show fileGHCVersion
    putStrLn $ "    This version of calligraphy was compiled with GHC version: " <> show GHC.hieVersion
    putStrLn "    Optimistically continuing anyway..."
  pure hie

{-# INLINE sourceInfo #-}
sourceInfo :: Traversal' (HieAST a) (NodeInfo a)
showContextInfo :: ContextInfo -> String
readHieFileCompat :: IORef NameCache -> FilePath -> IO HieFileResult

#if MIN_VERSION_ghc(9,4,0)

sourceInfo f (Node (SourcedNodeInfo inf) sp children) = (\inf' -> Node (SourcedNodeInfo inf') sp children) <$> Map.alterF (maybe (pure Nothing) (fmap Just . f)) SourceInfo inf

showContextInfo = showSDocUnsafe . ppr

readHieFileCompat ref path = do
  nameCache <- readIORef ref
  readHieFile nameCache path

#elif MIN_VERSION_ghc(9,0,0)

sourceInfo f (Node (SourcedNodeInfo inf) sp children) = (\inf' -> Node (SourcedNodeInfo inf') sp children) <$> Map.alterF (maybe (pure Nothing) (fmap Just . f)) SourceInfo inf

showContextInfo = showSDocUnsafe . ppr

readHieFileCompat ref = readHieFile (NCU (atomicModifyIORef ref))

#else

sourceInfo f (Node inf sp children) = (\inf' -> Node inf' sp children) <$> f inf

showContextInfo = show

readHieFileCompat ref fp = do
  cache <- readIORef ref
  (res, cache') <- readHieFile cache fp
  writeIORef ref cache'
  pure res

#endif

isInstanceNode :: NodeInfo a -> Bool
isTypeSignatureNode :: NodeInfo a -> Bool
isInlineNode :: NodeInfo a -> Bool
isMinimalNode :: NodeInfo a -> Bool
isDerivingNode :: NodeInfo a -> Bool
showAnns :: NodeInfo a -> String
#if MIN_VERSION_ghc(9,2,0)

isInstanceNode (NodeInfo anns _ _) = any (flip Set.member anns) [NodeAnnotation "ClsInstD" "InstDecl", NodeAnnotation "DerivDecl" "DerivDecl"]

isTypeSignatureNode (NodeInfo anns _ _) = Set.member (NodeAnnotation "TypeSig" "Sig") anns

isInlineNode (NodeInfo anns _ _) = Set.member (NodeAnnotation "InlineSig" "Sig") anns

isMinimalNode (NodeInfo anns _ _) = Set.member (NodeAnnotation "MinimalSig" "Sig") anns

isDerivingNode (NodeInfo anns _ _) = Set.member (NodeAnnotation "HsDerivingClause" "HsDerivingClause") anns

showAnns (NodeInfo anns _ _) = unwords (show . unNodeAnnotation <$> Set.toList anns)
  where
    unNodeAnnotation (NodeAnnotation a b) = (a, b)

#else

isInstanceNode (NodeInfo anns _ _) = any (flip Set.member anns) [("ClsInstD", "InstDecl"), ("DerivDecl", "DerivDecl")]

isTypeSignatureNode (NodeInfo anns _ _) = Set.member ("TypeSig", "Sig") anns

isInlineNode (NodeInfo anns _ _) = Set.member ("InlineSig", "Sig") anns

isMinimalNode (NodeInfo anns _ _) = Set.member ("MinimalSig", "Sig") anns

isDerivingNode (NodeInfo anns _ _) = Set.member ("HsDerivingClause", "HsDerivingClause") anns

showAnns (NodeInfo anns _ _) = unwords (show <$> Set.toList anns)

#endif

mergeSpans :: Span -> Span -> Span
mergeSpans sp1 sp2 =
  mkRealSrcSpan
    ( min
        (realSrcSpanStart sp1)
        (realSrcSpanStart sp2)
    )
    ( max
        (realSrcSpanEnd sp1)
        (realSrcSpanEnd sp2)
    )

isPointSpan :: Span -> Bool
isPointSpan sp = realSrcSpanEnd sp <= realSrcSpanStart sp
