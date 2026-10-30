const frame = document.querySelector("#product-video");
const toggle = document.querySelector("#video-toggle");
const sound = document.querySelector("#video-sound");
const fullscreen = document.querySelector("#video-fullscreen");
let muted = true;
const reducedMotion = matchMedia("(prefers-reduced-motion: reduce)");
let player;
let ready = false;
let visible = false;
let wantsPlayback = !reducedMotion.matches;
let automaticPause = false;

function syncPlayback() {
  if (!ready) return;
  if (wantsPlayback && visible && !document.hidden) {
    player.playVideo();
  } else if (
    player.getPlayerState() === YT.PlayerState.PLAYING ||
    player.getPlayerState() === YT.PlayerState.BUFFERING
  ) {
    automaticPause = true;
    player.pauseVideo();
  }
}

function updateControls() {
  const playing = ready && player.getPlayerState() === YT.PlayerState.PLAYING;
  toggle.textContent = playing ? "Pause" : "Play";
  toggle.setAttribute("aria-label", playing ? "Pause demo" : "Play demo");
  sound.textContent = muted ? "Sound on" : "Sound off";
  sound.setAttribute("aria-label", muted ? "Turn sound on" : "Turn sound off");
  sound.setAttribute("aria-pressed", String(!muted));
}
toggle.addEventListener("click", () => {
  if (!ready) return;
  wantsPlayback = player.getPlayerState() !== YT.PlayerState.PLAYING;
  syncPlayback();
});
sound.addEventListener("click", () => {
  if (!ready) return;
  muted = !muted;
  if (muted) player.mute();
  else player.unMute();
  updateControls();
});
fullscreen.addEventListener("click", () => {
  if (frame.requestFullscreen) frame.requestFullscreen().catch(() => {});
});

// Controls stay below the video; the watch link is available if the API fails.
window.onYouTubeIframeAPIReady = () => {
  player = new YT.Player(frame, {
    events: {
      onReady(event) {
        ready = true;
        event.target.mute();
        toggle.disabled = false;
        sound.disabled = false;
        syncPlayback();
        updateControls();
      },
      onStateChange(event) {
        if (event.data === YT.PlayerState.PAUSED) {
          if (automaticPause) automaticPause = false;
          else wantsPlayback = false;
        } else if (event.data === YT.PlayerState.PLAYING) {
          automaticPause = false;
          wantsPlayback = true;
          if (!visible || document.hidden) syncPlayback();
        }
        updateControls();
      },
    },
  });
};

new IntersectionObserver(
  ([entry]) => {
    visible = entry.isIntersecting;
    syncPlayback();
  },
  { threshold: 0.15 },
).observe(frame);
document.addEventListener("visibilitychange", syncPlayback);
reducedMotion.addEventListener("change", () => {
  wantsPlayback = !reducedMotion.matches;
  syncPlayback();
});

const api = document.createElement("script");
api.src = "https://www.youtube.com/iframe_api";
api.async = true;
document.head.append(api);
