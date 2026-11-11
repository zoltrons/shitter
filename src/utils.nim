# SPDX-License-Identifier: AGPL-3.0-only
import sequtils, strutils, strformat, uri, tables, base64
import nimcrypto

var
  hmacKey: string
  base64Media = false
  proxyVideos* = false

const
  https* = "https://"
  twimg* = "pbs.twimg.com/"
  nitterParams* = ["name", "tab", "id", "list", "referer", "scroll", "prefs"]
  twimgDomains* = @[
    "twimg.com",
    "abs.twimg.com",
    "pbs.twimg.com",
    "video.twimg.com"
  ]
  twitterDomains = @[
    "twitter.com",
    "pic.twitter.com",
    "twimg.com",
    "abs.twimg.com",
    "pbs.twimg.com",
    "video.twimg.com",
    "x.com",
    "pscp.tv",
    "video.pscp.tv"
  ]

proc isTwimgUrl*(uri: Uri): bool =
  uri.hostname in twimgDomains or uri.hostname.endsWith(".twimg.com")

proc isTwimgUrl*(url: string): bool =
  isTwimgUrl(parseUri(url))

proc setHmacKey*(key: string) =
  hmacKey = key

proc setProxyEncoding*(state: bool) =
  base64Media = state

proc setProxyVideos*(state: bool) =
  proxyVideos = state

proc getHmac*(data: string): string =
  ($hmac(sha256, hmacKey, data))[0 .. 12]

proc directMediaUrl*(link: string): string =
  ## Returns the direct twimg URL for a media link. Internal media URLs have
  ## the `https://pbs.twimg.com/` prefix stripped, so it has to be restored.
  if link.len == 0: return
  if link.startsWith(https): return link
  if link.startsWith("twimg.com/") or link.startsWith("abs.twimg.com/") or
     link.startsWith("pbs.twimg.com/") or link.startsWith("video.twimg.com/"):
    return https & link
  https & twimg & link

proc getVidUrl*(link: string; proxy: bool): string =
  if link.len == 0: return
  if not proxy: return directMediaUrl(link)
  let sig = getHmac(link)
  if base64Media:
    &"/video/enc/{sig}/{encode(link, safe=true)}"
  else:
    &"/video/{sig}/{encodeUrl(link)}"

proc getVidUrl*(link: string): string =
  getVidUrl(link, proxyVideos)

proc getPicUrl*(link: string; proxy: bool): string =
  if link.len == 0: return
  if not proxy: return directMediaUrl(link)
  if base64Media:
    &"/pic/enc/{encode(link, safe=true)}"
  else:
    &"/pic/{encodeUrl(link)}"

proc getPicUrl*(link: string): string =
  getPicUrl(link, proxyVideos)

proc getOrigPicUrl*(link: string; proxy: bool): string =
  if link.len == 0: return
  if not proxy:
    result = directMediaUrl(link)
    if result.isTwimgUrl:
      result &= (if "?" in result: "&name=orig" else: "?name=orig")
    return
  if base64Media:
    &"/pic/orig/enc/{encode(link, safe=true)}"
  else:
    &"/pic/orig/{encodeUrl(link)}"

proc getOrigPicUrl*(link: string): string =
  getOrigPicUrl(link, proxyVideos)

proc mediaUrl*(url: string; proxy: bool; urlPrefix = ""): string =
  ## Returns the media URL, prefixing it with `urlPrefix` only when it is
  ## relative (i.e. when media is proxied through this instance).
  let pic = getPicUrl(url, proxy)
  if pic.startsWith("http"): pic else: urlPrefix & pic

proc filterParams*(params: Table): seq[(string, string)] =
  for p in params.pairs():
    if p[1].len > 0 and p[0] notin nitterParams:
      result.add p

proc isTwitterUrl*(uri: Uri): bool =
  uri.scheme in ["http", "https"] and
    (uri.hostname in twitterDomains or uri.hostname.endsWith(".video.pscp.tv"))

proc isTwitterUrl*(url: string): bool =
  isTwitterUrl(parseUri(url))

proc isProfileName*(name: string): bool =
  name.len in 1..15 and name.allCharsInSet(Letters + Digits + {'_'})

proc isStatusId*(id: string): bool =
  id.len > 0 and id.allCharsInSet(Digits)

const xDomains = [
  "x.com", "www.x.com", "mobile.x.com",
  "twitter.com", "www.twitter.com", "mobile.twitter.com"
]

const twitterAppPages = [
  "home", "explore", "search", "notifications", "messages", "settings",
  "compose", "intent", "share", "login", "logout", "signup", "tos", "privacy"
]

proc parseUserMention*(input: string): string =
  let text = input.strip
  if text.len < 2 or text[0] != '@' or text.anyIt(it.isSpaceAscii):
    return
  let name = text[1..^1]
  if not name.isProfileName:
    return
  "/" & name

proc parseTwitterLink*(input: string): string =
  let text = input.strip
  if text.len == 0 or text.anyIt(it.isSpaceAscii):
    return

  let url = try:
      parseUri(if "://" in text: text else: https & text)
    except ValueError:
      return

  if url.scheme.toLowerAscii notin ["http", "https"] or
     url.hostname.toLowerAscii notin xDomains or
     url.username.len > 0 or url.password.len > 0 or url.port.len > 0:
    return

  let parts = url.path.strip(chars={'/'}).split('/')
  if parts.len == 0:
    return

  let name = parts[0]
  if name.toLowerAscii == "i":
    return "/" & parts.join("/")

  if not name.isProfileName:
    return

  if parts.len == 1:
    if name.toLowerAscii in twitterAppPages:
      return
    return "/" & name

  if parts.len >= 3 and parts[1] in ["status", "statuses"] and
     parts[2].isStatusId:
    if parts.len == 3 or
       (parts.len == 5 and parts[3] in ["photo", "video"] and
        parts[4].isStatusId):
      return "/" & name & "/status/" & parts[2]

proc validateNumber*(value: string): string =
  if value.anyIt(not it.isDigit):
    return ""
  return value
