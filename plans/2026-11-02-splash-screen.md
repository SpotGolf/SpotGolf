# Splash Screen

The phone app opens on a blank screen today. It gets an animated splash, "Ball flight": a ball flies in with a tracer, lands, and becomes the pin from the app icon, then the title shows and the splash fades into the app.

## 1. When it shows

| Case | Splash |
|---|---|
| Cold launch | Yes |
| Return from the background | No |
| UI tests (`--ui-testing`) | No. They run at machine speed |
| Reduce Motion on | No |
| Tap during the splash | Skips to the fade out |

It covers the app, which loads underneath (the permissions screen on a first launch, the round list after).

## 2. Look

- Background: the icon's gradient, `#2FBF5E` top left to `#0D5225` bottom right.
- Pin: the icon's pin, `#F4FAF5` with a `#95D9A9` dot, and a soft shadow under its tip.
- Tracer: `#FFD84D`, thin and faint at its tail, wider and strong at the ball, with a soft glow.
- Title: "SpotGolf" in white, under the pin. A brand name, so it is not in the string catalog.
- Drawn in a 200 × 420 design space with the pin's tip at (100, 258), scaled to fit the screen and centered.

## 3. Timeline

| Time (s) | What happens |
|---|---|
| 0 – 0.25 | The launch screen's plain green fades into the gradient |
| 0 – 0.85 | The ball fades in by 0.1 and flies from the bottom left, over the top, to the pin's spot. It shrinks as it goes away and slows as it comes down. The tracer follows it |
| 0.85 | It lands: a haptic tap (medium impact) and a ring spreads over the ground |
| 0.85 – 1.05 | The ball hops once. The tracer shrinks toward the pin and fades by 1.4 |
| 1.0 – 1.35 | The pin grows up out of the ball, overshooting a little, and the ball fades. A second ring spreads at 1.05 |
| 1.2 – 1.6 | The title rises into place and fades in |
| 1.6 – 3.0 | The finished splash holds |
| 3.0 – 3.3 | The splash fades out to the app |

The app's main thread is busy for about a second after launch and draws no frames. So the splash keeps its own clock, moved on by each frame drawn by at most 1/30 s. A busy launch pauses the animation on its first frame, the launch color, instead of skipping ahead. The haptic and the fade out follow this clock too.

## 4. Launch screen

iOS shows the launch screen (`UILaunchScreen`) before the app runs, and it can only be a plain color or image. It becomes `LaunchBackground`, a color asset `#1E8841` (the gradient's middle). The splash's first frame is that same color, so the change from launch screen to splash can't be seen.

## 5. Code

| Piece | Where | Does |
|---|---|---|
| `SplashTimeline` | `SpotGolf/Utilities` | Where everything is at a time, and whether the splash shows. Unit tested |
| `SplashView` | `SpotGolf/Views` | Draws the timeline with `TimelineView` and `Canvas`, plays the haptic, skips on tap |
| `SpotGolfApp` | | Puts `SplashView` over `PhoneRootView` on launch and fades it out |
