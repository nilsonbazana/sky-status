# sky-status

`sky-status` is an astronomy-oriented status backend and native KDE Plasma 6 widget for answering a practical question: **is tonight worth observing?**

The panel view is intentionally tiny:

```text
☁ 8%   🌔 91%
```

Clicking it opens a larger dashboard with the best observing window, evening cloud layers, an hourly cloud timeline, astronomical dusk/dawn, seeing, transparency, Moon data, temperature and humidity.

## Data sources

- **Open-Meteo** — current temperature/humidity plus hourly total, low, mid and high cloud cover.
- **7Timer ASTRO** — astronomical seeing and atmospheric transparency.
- **PyEphem (local)** — astronomical dusk/dawn, Moon phase, illumination, moonrise and moonset.

The network sources are cached locally, while the ephemeris calculations are local.

## What changed in v0.2

The project is no longer built around a generic command-output Plasma widget. It now contains its own Plasma 6 plasmoid with separate compact and full representations.

The backend also gained structured JSON output:

```bash
sky-status --json
```

That keeps the data layer independent of Plasma and makes it reusable later with Waybar, Niri or other frontends.

## Panel view

The compact panel representation shows only:

- tonight's best two-hour cloud-cover value
- Moon phase icon and illumination

Cloud cover is color-coded from **green (favorable)** through **amber** to **red (poor)**.

## Click-open dashboard

The full Plasma popup uses more screen space for:

- best remaining two-hour observing window
- total / low / mid / high evening cloud
- up to eight hourly cloud bars
- seeing estimate
- transparency estimate
- astronomical dusk and dawn
- Moon phase, illumination, next rise and set
- current temperature and humidity
- manual refresh

### Color scale

The widget uses a restrained continuous red → amber → green text scale.

The backend normalizes each metric to a 0–100 quality score, so **higher always means more favorable** before it reaches the QML frontend:

- cloud: lower cloud cover = better
- seeing: smaller 7Timer seeing category = better
- transparency: smaller extinction category = better
- humidity: lower humidity = better
- temperature: a comfort-oriented scale, not an astronomy-quality measurement

Moon illumination and dusk/dawn are left neutral because whether they are favorable depends on what you intend to observe.

## Best-window calculation

For the coming/current astronomical night, `sky-status` examines the Open-Meteo hourly forecast between astronomical dusk and dawn. If the night has already begun, elapsed hours are ignored.

It then finds the best remaining two-hour block by minimizing mean total cloud cover, with a small penalty for a cloudy spike inside the block.

The dashboard separately reports median cloud cover for the first five hours after astronomical dusk as the **evening cloud** summary.

## Dependencies

Ubuntu/Kubuntu:

```bash
sudo apt install python3-ephem
```

Python's standard library handles HTTP and JSON, so `curl` and `jq` are no longer required by `sky-status` itself.

## Location

Defaults are currently set for Maringá, Paraná, Brazil:

```text
Latitude:  -23.42
Longitude: -51.93
Timezone:  America/Sao_Paulo
```

Override them with environment variables:

```bash
SKY_LAT=51.5074 \
SKY_LON=-0.1278 \
SKY_TZ=Europe/London \
~/.local/bin/sky-status --json
```

## Install the backend

```bash
git clone https://github.com/nilsonbazana/sky-status.git
cd sky-status

install -Dm755 sky-status ~/.local/bin/sky-status
```

Test the compact output:

```bash
~/.local/bin/sky-status
```

Test the JSON consumed by the Plasma widget:

```bash
~/.local/bin/sky-status --json | python3 -m json.tool
```

Force a fresh network fetch:

```bash
~/.local/bin/sky-status --json --refresh
```

## Install the Plasma 6 widget

From the repository directory:

```bash
kpackagetool6 --type Plasma/Applet --install plasmoid
```

For a later update:

```bash
kpackagetool6 --type Plasma/Applet --upgrade plasmoid
```

The widget ID is:

```text
io.github.nilsonbazana.skystatus
```

### Test it safely before adding it to the panel

Do this first:

```bash
plasmawindowed io.github.nilsonbazana.skystatus
```

Only after the windowed test behaves correctly should you add **Sky Status** to the Plasma panel from **Add Widgets**.

This avoids using the live panel as the development/test environment.

## Cache

Network responses are stored in:

```text
~/.cache/sky-status/
```

Current defaults:

- Open-Meteo: 10 minutes
- 7Timer ASTRO: 30 minutes

If a source is temporarily unavailable, a previous cached response can still be used and the dashboard marks the forecast as cached.

## Text modes

The backend remains useful without Plasma.

Compact:

```bash
sky-status
```

Example:

```text
☁8%  🌔91%
```

Long:

```bash
sky-status --long
```

Example structure:

```text
Best 20:00–22:00 · cloud 8% · seeing 1.0–1.25″ · transparency 0.4–0.5 · 🌔 91%
```

## Repository layout

```text
sky-status
├── sky-status
├── plasmoid
│   ├── metadata.json
│   └── contents
│       └── ui
│           └── main.qml
└── README.md
```

## License

No license has been added yet.
