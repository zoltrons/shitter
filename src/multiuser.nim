# SPDX-License-Identifier: AGPL-3.0-only
import asyncdispatch, strutils, sequtils, algorithm, tables, sets, base64

import types, api, apiutils, redis_cache, utils

const
  pageSize = 20
  maxFetchRounds = 10

type
  MultiUserState = object
    name*: string
    userId*: string
    cursor*: string
    cut*: int64

proc itemId(thread: Tweets): int64 =
  for tweet in thread:
    if tweet.id > result:
      result = tweet.id

proc cmpThread(a, b: Tweets): int =
  cmp(itemId(b), itemId(a))

proc parseFromToken(token: string; result: var seq[string]) =
  for name in token.split(','):
    if result.len >= maxMultiUsers:
      return
    let clean = name.strip(chars = {'"', '\'', '@', '(', ')', '.', ';', '!'})
    if clean.len > 0 and ':' notin clean and clean notin result:
      result.add clean

proc parseFromUsers*(text: string): seq[string] =
  if text.len == 0:
    return
  for raw in text.splitWhitespace():
    if result.len >= maxMultiUsers:
      break
    let token = raw.strip(chars = {'(', ')', ',', '"', '\''})
    if token.len > 5 and token[0..4].toLowerAscii == "from:":
      parseFromToken(token[5..^1], result)

proc singleUsername*(text: string): string =
  let token = text.strip(chars = {' ', '(', ')', ',', '"', '\'', '@', '.', ';', '!'})
  if isProfileName(token):
    result = token

proc hasSymbolPrefix*(text: string): bool =
  let token = text.strip
  token.len > 0 and token[0] notin {'a'..'z', 'A'..'Z', '0'..'9', '_'}

proc timelineKindFor*(query: Query): TimelineKind =
  case query.kind
  of QueryKind.media: TimelineKind.media
  of replies: TimelineKind.replies
  of QueryKind.articles: TimelineKind.articles
  else: TimelineKind.tweets

proc encodeCursor(states: seq[MultiUserState]): string =
  var raw = ""
  for i, state in states:
    if i > 0:
      raw.add "\n"
    raw.add state.name & "\t" & state.cursor & "\t" & $state.cut
  result = base64.encode(raw)

proc decodeCursor(cursor: string): seq[(string, string, int64)] =
  if cursor.len == 0:
    return
  try:
    let bytes = base64.decode(cursor)
    var raw = newString(bytes.len)
    for i, b in bytes:
      raw[i] = char(b)
    for line in raw.split('\n'):
      let parts = line.split('\t')
      if parts.len >= 3:
        result.add (parts[0], parts[1], parseBiggestInt(parts[2]).int64)
  except CatchableError:
    result.setLen 0

proc dedupeThreads(threads: seq[(int, Tweets)]): seq[(int, Tweets)] =
  var seen = initHashSet[int64]()
  for item in threads:
    let id = itemId(item[1])
    if id > 0 and id notin seen:
      seen.incl id
      result.add item

proc getMultiUserTimeline*(query: Query; names: seq[string];
                           kind: TimelineKind; after = ""): Future[Timeline] {.async.} =
  result = Timeline(beginning: after.len == 0, query: query)

  var
    states: seq[MultiUserState]
    cursors = initTable[string, tuple[cursor: string, cut: int64]]()

  for (name, cursor, cut) in decodeCursor(after):
    cursors[name.toLowerAscii] = (cursor, cut)

  let limited = if names.len > maxMultiUsers: names[0..<maxMultiUsers] else: names
  for name in limited:
    let userId = await getUserId(name)
    if userId.len == 0 or userId == "suspended":
      continue
    if states.anyIt(it.userId == userId):
      continue
    let cached = cursors.getOrDefault(name.toLowerAscii,
                                      (cursor: "", cut: int64.high))
    states.add MultiUserState(
      name: name,
      userId: userId,
      cursor: cached.cursor,
      cut: cached.cut
    )

  if states.len == 0:
    return

  var
    displayed: seq[Tweets]
    truncated = false

  for _ in 0..<maxFetchRounds:
    var
      candidates: seq[(int, Tweets)]
      pages: seq[tuple[bottom: string, empty: bool]]
      counts = newSeq[int](states.len)

    for i, state in states:
      let profile = await getCachedUserTweets(state.userId, kind, state.cursor,
                                                cacheEmpty=true)
      let threads = profile.tweets.content
      for thread in threads:
        let id = itemId(thread)
        if id <= 0:
          continue
        if id < state.cut:
          candidates.add (i, thread)
          inc counts[i]
      pages.add (bottom: profile.tweets.bottom, empty: threads.len == 0)

    candidates = dedupeThreads(candidates)

    var
      shown = newSeq[int](states.len)
      shownMin = newSeq[int64](states.len)

    if candidates.len > 0:
      candidates.sort(proc(a, b: (int, Tweets)): int = cmpThread(a[1], b[1]))
      let remaining = pageSize - displayed.len
      let take = min(remaining, candidates.len)
      for j in 0..<take:
        let (idx, thread) = candidates[j]
        displayed.add thread
        inc shown[idx]
        let id = itemId(thread)
        if shownMin[idx] == 0 or id < shownMin[idx]:
          shownMin[idx] = id
      truncated = truncated or take < candidates.len

    var progressed = false
    for i in 0..<states.len:
      if shown[i] > 0:
        states[i].cut = min(states[i].cut, shownMin[i])
      if shown[i] == counts[i]:
        if states[i].cursor != pages[i].bottom:
          states[i].cursor = pages[i].bottom
          progressed = true

    if displayed.len >= pageSize:
      break
    if not progressed:
      break

  result.content = displayed
  result.beginning = after.len == 0

  var hasMore = truncated
  for state in states:
    if state.cursor.len > 0:
      hasMore = true

  if displayed.len > 0 and hasMore:
    result.bottom = encodeCursor(states)

proc bareUsername*(query: Query): string =
  if query.kind notin {tweets, top} or query.filters.len > 0 or
     query.excludes.len > 0 or query.includes.len > 0 or
     query.since.len > 0 or query.until.len > 0 or query.minLikes.len > 0:
    return
  result = singleUsername(query.text)

proc getTimelineTweets*(query: Query; after = "";
                        allowBareUsername = true): Future[Timeline] {.async.} =
  var
    names = parseFromUsers(query.text)
    kind = timelineKindFor(query)

  if names.len == 0:
    let name =
      if query.kind == QueryKind.media: singleUsername(query.text)
      elif allowBareUsername: bareUsername(query)
      else: ""
    if name.len > 0 and (await getUserId(name)) notin ["", "suspended"]:
      names = @[name]

  if names.len > 0:
    var q = query
    q.text = ""
    result = await getMultiUserTimeline(q, names, kind, after)
  elif searchAvailable():
    result = await getGraphTweetSearch(query, after)
  else:
    result = Timeline(beginning: after.len == 0, query: query)
