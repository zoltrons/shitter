# SPDX-License-Identifier: AGPL-3.0-only
import karax/[karaxdsl, vdom]

proc renderFeature*(): VNode =
  buildHtml(tdiv(class="overlay-panel")):
    h1: text "Unsupported feature"
    p:
      text "Nitter doesn't support this feature yet, but it might in the future. "
      text "You can check for an issue and open one if needed here: "
      a(href="https://codeberg.org/mv12star/shitter/issues"):
        text "https://codeberg.org/mv12star/shitter/issues"
    p:
      text "To find out more about the Nitter project, see the "
      a(href="/about"): text "About page"
