import std/[strutils, json]
import jsony
import ../types/session
from ../../types import Session, SessionKind

proc isSuspended(node: JsonNode): bool =
  if node.isNil: return false
  case node.kind
  of JBool: node.getBool
  of JString: node.getStr.cmpIgnoreCase("true") == 0
  else: false

proc parseSession*(raw: string): Session =
  let session = raw.fromJson(RawSession)
  let kind = if session.kind == "": "oauth" else: session.kind
  let suspended = session.suspended.isSuspended

  case kind
  of "oauth":
    let id = session.oauthToken[0 ..< session.oauthToken.find('-')]
    result = Session(
      kind: SessionKind.oauth,
      id: parseBiggestInt(id),
      username: session.username,
      suspended: suspended,
      oauthToken: session.oauthToken,
      oauthSecret: session.oauthTokenSecret
    )
  of "cookie":
    let id = if session.id.len > 0: parseBiggestInt(session.id) else: 0
    result = Session(
      kind: SessionKind.cookie,
      id: id,
      username: session.username,
      suspended: suspended,
      authToken: session.authToken,
      ct0: session.ct0
    )
  else:
    raise newException(ValueError, "Unknown session kind: " & kind)
