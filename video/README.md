# Hajar — code-rendered pitch video (Remotion)

A self-contained [Remotion](https://www.remotion.dev) project that renders the Hajar pitch as an
animated **8bitcn-style** MP4 — matching the web. ~96 seconds, 1920×1080. Captions are burned in
(the word-for-word narration from `../VIDEO_SCRIPT.md` Part B). **No voiceover** — add VO/TTS in any
editor, or read it live.

## Render

```bash
cd video
npm install            # first time (also downloads a headless Chrome on first render)
npm run render         # -> out/hajar-pitch.mp4
# or preview/edit live:
npm run dev            # opens Remotion Studio
```

Requirements: Node 18+. First render downloads Chrome Headless Shell (~150 MB, one-time) and uses
the bundled ffmpeg — no extra installs.

## Customize
- Slide content + captions: `src/slides.tsx` (one entry per slide; `seconds` sets its duration).
- Look / animation / fonts: `src/HajarPitch.tsx` (8bitcn palette, Press Start 2P + Pixelify Sans,
  pixel borders, fade-up springs, scanlines).
- Size / fps: `src/Root.tsx`.

## Add voiceover (optional)
1. Render the silent MP4 above.
2. Generate VO from `../VIDEO_SCRIPT.md` Part B with any TTS (e.g. ElevenLabs).
3. Lay the audio under the video in CapCut / DaVinci / `ffmpeg -i video.mp4 -i vo.mp3 -c:v copy -shortest out.mp4`.
