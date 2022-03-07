module Reach.Eval (evalBundle) where

import Control.Monad.Extra
import Control.Monad.Reader
import Data.IORef
import qualified Data.Map.Strict as M
import qualified Data.Set as S
import Language.JavaScript.Parser
import Reach.AST.Base
import Reach.AST.DL
import Reach.AST.DLBase
import Reach.AST.SL
import Reach.Connector
import Reach.Counter
import Reach.Eval.Core
import Reach.Eval.Error
import Reach.Eval.Module
import Reach.Eval.Types
import Reach.JSUtil
import Reach.Parser
import Reach.Util
import Reach.Warning

compileDApp :: DLStmts -> DLSExports -> SLVal -> App DLProg
compileDApp shared_lifts exports (SLV_Prim (SLPrim_App_Delay at top_s (top_env, top_use_strict))) = locAt (srcloc_lab "compileDApp" at) $ do
  let (JSBlock _ top_ss _) = jsStmtToBlock top_s
  setSt $
    SLState
      { st_mode = SLM_AppInit
      , st_live = False
      , st_pdvs = mempty
      , st_after_ctor = True
      , st_after_first = False
      , st_toks = mempty
      , st_toks_c = mempty
      , st_tok_pos = mempty
      }
  let sco =
        SLScope
          { sco_ret = Nothing
          , sco_must_ret = RS_CannotReturn
          , sco_while_vars = Nothing
          , sco_penvs = mempty
          , sco_cenv = top_env
          , sco_use_strict = top_use_strict
          , sco_use_unstrict = False
          }
  init_dlo <- readDlo id
  envr <- liftIO $ newIORef $ AppEnv mempty init_dlo mempty mempty
  resr <- liftIO $ newIORef $ AppRes mempty mempty mempty mempty mempty mempty
  appr <- liftIO $ newIORef $ AIS_Init envr resr
  mape <- liftIO $ makeMapEnv
  e_droppedAsserts' <- (liftIO . dupeCounter) =<< (e_droppedAsserts <$> ask)
  (these_lifts, final_dlo) <- captureLifts $
    locSco sco $
      local
        (\e ->
           e
             { e_appr = Right appr
             , e_mape = mape
             , e_droppedAsserts = e_droppedAsserts'
             })
        $ do
          void $ evalStmt top_ss
          flip when doExit =<< readSt st_live
          readDlo id
  fin_toks <- readSt st_toks
  didPublish <- readSt st_after_first
  unless (didPublish || null top_ss) $
    liftIO . emitWarning (Just at) $ W_NoPublish
  let final = shared_lifts <> these_lifts
  let final_dlo' =
        final_dlo
          { dlo_bals = 1 + length fin_toks
          , dlo_droppedAsserts = e_droppedAsserts'
          }
  AppRes {..} <- liftIO $ readIORef resr
  dli_maps <- liftIO $ readIORef $ me_ms mape
  let dli = DLInit {..}
  let sps_ies = ar_pie
  let sps_apis = ar_isAPI
  let sps = SLParts {..}
  final' <- pan final
  return $ DLProg at final_dlo' sps dli exports ar_views ar_apis ar_events final'
compileDApp _ _ _ = impossible "compileDApp called without a Reach.App"

class Pandemic a where
  pan :: a -> App a

instance Pandemic DLStmts where
  pan = mapM pan

instance Pandemic DLExpr where
  pan = \case
    DLE_Arg at arg -> return $ DLE_Arg at arg
    DLE_LArg at larg  -> return $ DLE_LArg at larg
    DLE_Impossible at i err -> return $ DLE_Impossible at i err
    DLE_VerifyMuldiv at cxt ct argl err -> return $ DLE_VerifyMuldiv at cxt ct argl err
    DLE_PrimOp at primop argl -> return $ DLE_PrimOp at primop argl
    DLE_ArrayRef at arg1 arg2 -> return $ DLE_ArrayRef at arg1 arg2
    DLE_ArraySet at arg1 arg2 arg3 -> return $ DLE_ArraySet at arg1 arg2 arg3
    DLE_ArrayConcat at arg1 arg2 -> return $ DLE_ArrayConcat at arg1 arg2
    DLE_ArrayZip at arg1 arg2 -> return $ DLE_ArrayZip at arg1 arg2
    DLE_TupleRef at arg1 i -> return $ DLE_TupleRef at arg1 i
    DLE_ObjectRef at arg s -> return $ DLE_ObjectRef at arg s
    DLE_Interact at cxt slp s ty argl -> return $ DLE_Interact at cxt slp s ty argl
    DLE_Digest at argl -> return $ DLE_Digest at argl
    DLE_Claim at cxt ct arg mbbs -> return $ DLE_Claim at cxt ct arg mbbs
    DLE_Transfer at arg1 arg2 marg -> return $ DLE_Transfer at arg1 arg2 marg
    DLE_TokenInit at arg -> return $ DLE_TokenInit at arg
    DLE_CheckPay at cxt arg marg -> return $ DLE_CheckPay at cxt arg marg
    DLE_Wait at targ -> return $ DLE_Wait at targ
    DLE_PartSet at slp arg -> return $ DLE_PartSet at slp arg
    DLE_MapRef at dlm arg -> return $ DLE_MapRef at dlm arg
    DLE_MapSet at dlm arg marg -> return $ DLE_MapSet at dlm arg marg
    DLE_Remote at cxt arg ty s amt argl bill -> return $ DLE_Remote at cxt arg ty s amt argl bill
    DLE_TokenNew at tknew -> return $ DLE_TokenNew at tknew
    DLE_TokenBurn at arg1 arg2 -> return $ DLE_TokenBurn at arg1 arg2
    DLE_TokenDestroy at arg -> return $ DLE_TokenDestroy at arg
    DLE_TimeOrder at margs_vars -> return $ DLE_TimeOrder at margs_vars
    DLE_GetContract at -> return $ DLE_GetContract at
    DLE_GetAddress at -> return $ DLE_GetAddress at
    DLE_EmitLog at lk vars -> return $ DLE_EmitLog at lk vars
    DLE_setApiDetails at who dom mc info -> return $ DLE_setApiDetails at who dom mc info
    DLE_GetUntrackedFunds at marg arg -> return $ DLE_GetUntrackedFunds at marg arg
    DLE_FromSome at arg1 arg2 -> return $ DLE_FromSome at arg1 arg2

instance Pandemic DLVar where
  pan = undefined

instance Pandemic DLLetVar where
  pan = \case
    DLV_Eff -> return DLV_Eff
    DLV_Let vc v -> return $ DLV_Let vc v

instance Pandemic DLSBlock where
  pan = undefined

instance Pandemic DLArg where
  pan = undefined

instance Pandemic (SwitchCases DLStmts) where
  pan = undefined

instance Pandemic (Maybe (DLTimeArg, DLStmts)) where
  pan = undefined

instance Pandemic DLAssignment where
  pan = undefined

instance Pandemic (M.Map SLPart DLSend) where
  pan = undefined

instance Pandemic (DLRecv DLStmts) where
  pan = undefined

instance Pandemic DLSStmt where
  pan = \case
    DLS_Let at v e -> DLS_Let at <$> pan v <*> pan e
    DLS_ArrayMap at v1 a1 v2 v3 bl -> DLS_ArrayMap at <$> pan v1 <*> pan a1 <*> pan v2 <*> pan v3 <*> pan bl
    DLS_ArrayReduce at v1 a1 a2 v2 v3 v4 bl -> DLS_ArrayReduce at <$> pan v1 <*> pan a1 <*> pan a2 <*> pan v2 <*> pan v3 <*> pan v4 <*> pan bl
    DLS_If at arg ann sts1 sts2 -> do
      r1 <- pan arg
      r2 <- pan sts1
      r3 <- pan sts2
      return $ DLS_If at r1 ann r2 r3
    DLS_Switch at v sa sw -> do
      r1 <- pan v
      DLS_Switch at r1 sa <$> pan sw
    DLS_Return at i arg -> do
      DLS_Return at i <$> pan arg
    DLS_Prompt at v ann sts -> do
      DLS_Prompt at v ann <$> pan sts
    DLS_Stop at -> return $ DLS_Stop at
    DLS_Unreachable at ctx s -> return $ DLS_Unreachable at ctx s
    DLS_Only at sl sts -> DLS_Only at sl <$> pan sts
    DLS_ToConsensus at send recv mtime -> do
      r1 <- pan send
      r2 <- pan recv
      r3 <- pan mtime
      return $ DLS_ToConsensus at r1 r2 r3
    DLS_FromConsensus at cxt sts -> DLS_FromConsensus at cxt <$> pan sts
    DLS_While at agn bl1 bl2 sts -> do
      r1 <- pan agn
      r2 <- pan bl1
      r3 <- pan bl2
      r4 <- pan sts
      return $ DLS_While at r1 r2 r3 r4
    DLS_Continue at agn -> DLS_Continue at <$> pan agn
    DLS_FluidSet at flv arg -> DLS_FluidSet at flv <$> pan arg
    DLS_FluidRef at v flv -> do
      r1 <- pan v
      return $ DLS_FluidRef at r1 flv
    DLS_MapReduce at i v1 dlmv arg v2 v3 bl -> do
      r1 <- pan v1
      r2 <- pan arg
      r3 <- pan v2
      r4 <- pan v3
      r5 <- pan bl
      return $ DLS_MapReduce at i r1 dlmv r2 r3 r4 r5
    DLS_Throw at arg b -> do
      r1 <- pan arg
      return $ DLS_Throw at r1 b
    DLS_Try at sts1 v sts2 -> do
      r1 <- pan sts1
      r2 <- pan v
      r3 <- pan sts2
      return $ DLS_Try at r1 r2 r3
    DLS_ViewIs at sl1 sl2 expo -> return $ DLS_ViewIs at sl1 sl2 expo
    DLS_TokenMetaGet tm at v a i -> do
      r1 <- pan v
      r2 <- pan a
      return $ DLS_TokenMetaGet tm at r1 r2 i
    DLS_TokenMetaSet tm at a1 a2 i b -> do
      r1 <- pan a1
      r2 <- pan a2
      return $ DLS_TokenMetaSet tm at r1 r2 i b

mmapMaybeM :: Monad m => (a -> m (Maybe b)) -> M.Map k a -> m (M.Map k b)
mmapMaybeM f m = M.mapMaybe id <$> mapM f m

getExports :: SLEnv -> App DLSExports
getExports = mmapMaybeM (slToDLExportVal . sss_val)

makeMapEnv :: IO MapEnv
makeMapEnv = do
  me_id <- newCounter 0
  me_ms <- newIORef mempty
  return $ MapEnv {..}

makeEnv :: Connectors -> IO Env
makeEnv cns = do
  e_id <- newCounter 0
  let e_who = Nothing
  let e_stack = []
  let e_stv =
        SLState
          { st_mode = SLM_Module
          , st_live = False
          , st_pdvs = mempty
          , st_after_first = False
          , st_after_ctor = False
          , st_toks = mempty
          , st_toks_c = mempty
          , st_tok_pos = mempty
          }
  let e_sco =
        SLScope
          { sco_ret = Nothing
          , sco_must_ret = RS_CannotReturn
          , sco_while_vars = Nothing
          , -- FIXME change this type to (Either SLEnv (M.Map SLPart SLEnv) and use the left case here so we can remove base_penvs
            sco_penvs = mempty
          , sco_cenv = mempty
          , sco_use_strict = False
          , sco_use_unstrict = False
          }
  let e_depth = recursionDepthLimit
  let e_while_invariant = False
  e_st <- newIORef e_stv
  let e_at = srcloc_top
  e_lifts <- newIORef mempty
  e_vars_tracked <- newIORef mempty
  e_vars_used <- newIORef mempty
  e_infections <- newIORef mempty
  -- XXX revise
  e_exn <- newIORef $ ExnEnv False Nothing Nothing SLM_Module
  e_mape <- makeMapEnv
  e_droppedAsserts <- newCounter 0
  let e_appr = Left $ app_default_opts e_id e_droppedAsserts $ M.keys cns
  return (Env {..})

checkUnusedVars :: App a -> App a
checkUnusedVars m = do
  vt <- liftIO $ newIORef mempty
  vu <- liftIO $ newIORef mempty
  a <- local (\e -> e { e_vars_tracked = vt, e_vars_used = vu }) m
  tracked <- liftIO $ readIORef vt
  used <- liftIO $ readIORef vu
  let unused = S.difference tracked used
  let l = S.toList unused
  case l of
    [] -> return ()
    (at, _) : _ ->
      expect_throw Nothing at $ Err_Unused_Variables l
  return a

evalBundle :: Connectors -> JSBundle -> IO (S.Set SLVar, (SLVar -> IO DLProg))
evalBundle cns (JSBundle mods) = do
  evalEnv <- makeEnv cns
  let run = flip runReaderT evalEnv
  let exe = fst $ hdDie mods
  (shared_lifts, libm) <-
    run $
      captureLifts $
        evalLibs cns mods
  let exe_ex = libm M.! exe
  let tops =
        M.keysSet $
          flip M.filter exe_ex $
            \v ->
              case sss_val v of
                SLV_Prim SLPrim_App_Delay {} -> True
                _ -> False
  let go getdapp = run $ checkUnusedVars $ do
        exports <- getExports exe_ex
        topv <- ensure_public . sss_sls =<< getdapp
        compileDApp shared_lifts exports topv
  case S.null tops of
    True -> do
      return (S.singleton "default", const $ go $ return defaultApp)
    False -> do
      let go' which = go $ env_lookup LC_CompilerRequired which exe_ex
      return (tops, go')
