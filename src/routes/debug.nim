# SPDX-License-Identifier: AGPL-3.0-only
import jester
import router_utils
import ".."/[auth, apiutils, types]

proc createDebugRouter*(cfg: Config) =
  router debug:
    get "/.health":
      respJson getSessionPoolHealth(isGuestAuth() or isPartialAuth())

    get "/.sessions":
      cond cfg.enableDebug
      respJson getSessionPoolDebug()
