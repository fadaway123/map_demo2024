# map_demo2024

A desktop map annotation tool powered by **Qt 6 + AMap (高德地图) JS API + WebView2**.

Mark locations, draw paths, add notes and images on an interactive map — all data persisted locally as JSON.

## Features

- Click to place annotations with custom labels and tags
- Path drawing with multi-segment lines
- Image attachment per annotation / path point
- Tag-based filtering and clean-up
- Weather query, geocoding, place search, route planning
- Configurable AMap API keys via external JSON file

## Dependencies

| Component | Version | Notes |
|---|---|---|
| Qt | 6.9.3 | Core, Quick, Network (MinGW 64-bit) |
| MinGW | 13.1.0 | Bundled with Qt installer |
| WebView2 Runtime | Any | Ships with Windows 11 / Edge; or [download](https://developer.microsoft.com/en-us/microsoft-edge/webview2/) |
| AMap API Key | — | Free tier at [AMap Console](https://console.amap.com/) |

## Build

```bash
cmake -B build/release -DCMAKE_BUILD_TYPE=Release
cmake --build build/release --parallel
```

## Setup

1. Go to [AMap Console](https://console.amap.com/) → 应用管理 → 我的应用 → 创建新应用
2. Add two API types:
   - **JS API** (Web端) — for the map view
   - **Web Service API** — for geocoding / search / weather / routing
3. Launch the application once — it auto-creates `config.json` at:
   - Windows: `%APPDATA%/map_demo2024/config.json`
4. Open `config.json` and fill in your keys:
   ```json
   {
       "amapJsKey": "your_js_api_key_here",
       "amapWebKey": "your_web_service_key_here"
   }
   ```
5. Restart the application.

> Your API keys stay on your machine. The project uses placeholders in source code;
> keys are read from the local config file only.

## License

MIT
