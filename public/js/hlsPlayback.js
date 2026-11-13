// @license http://www.gnu.org/licenses/agpl-3.0.html AGPL-3.0
// SPDX-License-Identifier: AGPL-3.0-only
function playMedia(overlay, tagName) {
    const media = overlay.parentElement.querySelector(tagName);
    const url = media.getAttribute("data-url");
    const startTime = parseFloat(media.getAttribute("data-start") || "0");
    const isHls = media.getAttribute("data-type") === "hls" ||
                  /\.(m3u8|vmap)(\?|$)/.test(url);
    media.setAttribute("controls", "");
    overlay.style.display = "none";

    const start = function () {
        if (startTime > 0) media.currentTime = startTime;
        media.play();
    };

    if (!isHls) {
        media.addEventListener('loadedmetadata', start, {once: true});
        media.src = url;
        media.load();
        return;
    }

    if (typeof Hls !== "undefined" && Hls.isSupported()) {
        var hls = new Hls({autoStartLoad: false});
        hls.loadSource(url);
        hls.attachMedia(media);
        hls.on(Hls.Events.MANIFEST_PARSED, function () {
            hls.loadLevel = hls.levels.length - 1;
            hls.startLoad(startTime);
            media.play();
        });
    } else if (media.canPlayType('application/vnd.apple.mpegurl')) {
        media.src = url;
        media.addEventListener('canplay', start, {once: true});
    }
}

function playVideo(overlay) { playMedia(overlay, 'video'); }
function playAudio(overlay) { playMedia(overlay, 'audio'); }
// @license-end
