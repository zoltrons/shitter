# SPDX-License-Identifier: AGPL-3.0-only
import os, strutils, strformat
import karax/[karaxdsl, vdom]

# The version is read from git at compile time. It can optionally be overridden
# with -d:gitHash=... / -d:gitDate=... (e.g. when building without a .git dir).
const
  gitHash {.strdefine.} = ""
  gitDate {.strdefine.} = ""

proc gitMeta(cmd: string): string {.compileTime.} =
  let res = gorgeEx(cmd)
  if res.exitCode == 0: res.output.strip() else: "unknown"

when gitHash.len > 0:
  const hash = gitHash
else:
  const hash = gitMeta("git show -s --format=\"%h\"")

when gitDate.len > 0:
  const date = gitDate
else:
  const date = gitMeta("git show -s --format=\"%cd\" --date=format:\"%Y.%m.%d\"")

const
  link = "https://codeberg.org/shitter/shitter/commit/" & hash
  version = &"{date}-{hash}"

var aboutHtml: string

proc initAboutPage*(dir: string) =
  try:
    aboutHtml = readFile(dir/"md/about.html")
  except IOError:
    stderr.write (dir/"md/about.html") & " not found, please run `nimble md`\n"
    aboutHtml = "<h1>About page is missing</h1><br><br>"

proc renderAbout*(): VNode =
  buildHtml(tdiv(class="overlay-panel")):
    verbatim aboutHtml
    h2: text "Instance info"
    p:
      text "Version "
      a(href=link): text version
