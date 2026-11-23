# YTMusicAppleStyleEnhancer 🍏✨

An advanced, production-grade iOS Theos tweak that brings **Apple Music's signature experience** and **audiophile optimizations** to **YouTube Music** (`com.google.ios.youtubemusic`).

Designed for seamless sideloading alongside **YTMusicUltimate** using Sideloadly on Windows (no Mac required).

---

## 🌟 Key Features

### 1. Apple Music-Style Smooth Audio Crossfade
- **Equal-Power Taper Math:** Uses sinusoidal $\cos(t \cdot \frac{\pi}{2})$ fade-out and $\sin(t \cdot \frac{\pi}{2})$ fade-in curves to eliminate the dreaded -6dB volume dip inherent in standard linear fades.
- **`CADisplayLink` 120Hz/60Hz Interpolation:** Glitch-free, ultra-smooth volume gain adjustments synced to your device display refresh rate.
- **Configurable Overlap Duration:** Adjustable from **1.0 to 12.0 seconds** (default: 5.0 seconds).
- Seamlessly transitions to the upcoming track without abrupt interruptions or dead air.

### 2. Low-Network Range Audio Pre-Fetching & Aggressive Buffering
- **120-Second Read-Ahead Buffer:** Forces `AVPlayerItem`'s `preferredForwardBufferDuration` to 120 seconds ahead of playback.
- **Cellular Drop-Proof Optimization:** Hooks `NSURLSessionConfiguration` with extended request/resource timeouts (45s/300s), enables `waitsForConnectivity = YES`, and pre-fetches initial audio segments for upcoming tracks in the queue.
- Eliminates stuttering when traveling through tunnels, underground transit, or low cellular reception zones.

### 3. Dynamic Album-Art Ambient Glow
- **Real-Time Palette Extraction:** Analyzes the active song's album artwork and extracts the most vibrant dominant and secondary colors without UI thread hitching (via optimized bitmap subsampling).
- **Multi-Layer Radial Glow:** Overlays radial `CAGradientLayer`s with a subtle `UIBlurEffect` background that animates smoothly across track changes.
- **Adjustable Intensity:** Fine-tune glow brightness from 20% to 100%.

### 4. True OLED Pitch-Black (`#000000`) & Multi-Color Theme Engine
- **Pure `#000000` Dark Mode:** Overrides YouTube Music's washed-out dark gray background colors across the Now Playing screen, queue, menus, search, tab bar, and navigation bar.
- **OLED Cyber Yellow (`#FFD60A` / `#FACC15`):** Punchy, high-contrast yellow accent for scrubbers, toggles, play/pause buttons, and active tabs.
- **OLED Emerald Green (`#30D158` / `#22C55E`):** Crisp neon-emerald accent styling.
- **Custom Hex Color Picker:** Input any custom `#RRGGBB` hex code with a live color swatch preview.

### 5. In-App Settings Menu
- **Triple-Tap Gesture:** Simply **triple-tap** the YouTube Music navigation bar or logo to launch the settings dashboard.
- **Account Menu Integration:** Also accessible directly from your YouTube Music profile/avatar menu.
- Complete control over crossfade duration, buffer options, ambient glow intensity, and accent colors.

---

## 🚀 How to Build Free via GitHub Actions (No Mac Needed)

1. Fork or push this repository to your GitHub account.
2. Go to the **Actions** tab in your GitHub repository.
3. Select the **Build YTMusicAppleStyleEnhancer** workflow.
4. Click **Run workflow**:
   - Leave `ipa_url` blank if you only want the `.dylib` and `.deb` artifacts.
   - Or paste a direct download URL to a decrypted YouTube Music `.ipa` to automatically inject the tweak and build the final `.ipa`!
5. Once the run completes, download the **`YTMusicAppleStyleEnhancer-Dylib`** artifact from the workflow summary page. Extract the `.zip` to find `YTMusicAppleStyleEnhancer.dylib`.

---

## 💻 Compiling Locally on Windows

### Option A: Via WSL2 (Ubuntu / Debian)
1. Install WSL: `wsl --install`
2. Open Ubuntu in WSL and install dependencies:
   ```bash
   sudo apt-get update && sudo apt-get install -y build-essential git curl libssl-dev zlib1g-dev
   ```
3. Install Theos:
   ```bash
   git clone --recursive https://github.com/theos/theos.git ~/theos
   echo 'export THEOS=~/theos' >> ~/.bashrc
   source ~/.bashrc
   ```
4. Install an iOS arm64 toolchain and SDK (e.g., iPhoneOS16.5.sdk) into `~/theos/sdks/`.
5. Navigate to the project and run:
   ```bash
   cd /mnt/e/ytmu/YTMusicAppleStyleEnhancer
   make clean package FINALPACKAGE=1
   ```
   The compiled `.dylib` will be located in `.theos/obj/debug/arm64/` or `.theos/obj/arm64/`.

### Option B: Via TheosWin (MSYS2)
1. Install [TheosWin](https://github.com/theos/theos/wiki/Installation-Windows).
2. Open the TheosWin MSYS2 shell:
   ```bash
   cd /e/ytmu/YTMusicAppleStyleEnhancer
   make package FINALPACKAGE=1
   ```

---

## 📲 How to Inject with Sideloadly on Windows

To combine `YTMusicAppleStyleEnhancer.dylib` alongside `YTMusicUltimate` into your decrypted YouTube Music `.ipa`:

1. **Obtain Files:**
   - A decrypted YouTube Music `.ipa` (from decrypt tools like Decrypt.day, IPAOMTK, or ARMConverter).
   - `YTMusicUltimate.dylib` (from the YTMusicUltimate release or build).
   - `YTMusicAppleStyleEnhancer.dylib` (downloaded from GitHub Actions).
   - `CydiaSubstrate.framework` or `libsubstrate.dylib` (if not already embedded in your injector).
2. **Open Sideloadly:**
   - Connect your iPhone/iPad to Windows via USB (or Wi-Fi sync).
   - Drag and drop your decrypted YouTube Music `.ipa` into Sideloadly.
   - Enter your Apple ID.
3. **Inject Dylibs in Sideloadly:**
   - Click on **Advanced Options** in Sideloadly.
   - Scroll down to the **Tweak Injection** section.
   - Click **+ Add Dylib/Framework** and select:
     - `YTMusicUltimate.dylib`
     - `YTMusicAppleStyleEnhancer.dylib`
   - Select **Cydia Substrate** or **Substitute** as the injection backing method.
4. **Export or Install:**
   - Click **Start** to directly sign and install to your iOS device.
   - Or check **Export IPA** to save the pre-injected `.ipa` for AltStore, SideStore, or TrollStore!
