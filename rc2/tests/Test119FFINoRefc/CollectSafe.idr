module Test119FFINoRefc.CollectSafe

-- This module was licensed by BSD3.

-- `C__collect_safe:` (Chez's tag for a C call that may block) is the same
-- call as `C:` in rc2, which has no collector to let run
-- (rc2/doc/ffi-cexpr.md's "Priority"). `C:` wins when both are given.
-- Real RefC reads neither this tag nor a declaration without `C:`.

-- Only this tag, as posix's `read`/`write` and linux's `epoll_wait` are
-- declared: a pure call, and an IO call taking a String.
%foreign "C__collect_safe:idris2rc2_testcs_add,libc,CollectSafe.h"
prim__add : Int -> Int -> Int

%foreign "C__collect_safe:idris2rc2_testcs_len,libc,CollectSafe.h"
prim__len : String -> PrimIO Int

-- Both tags, the collect-safe string first: `C:` is called.
%foreign "C__collect_safe:idris2rc2_testcs_wrong,libc,CollectSafe.h"
         "C:idris2rc2_testcs_right,libc,CollectSafe.h"
prim__both : Int

export
run : IO ()
run = do
  printLn (prim__add 40 2)
  n <- primIO (prim__len "collect-safe")
  printLn n
  printLn prim__both
