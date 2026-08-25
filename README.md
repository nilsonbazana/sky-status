# sky-status

Compact weather and Moon status output for Linux desktop panels.

`sky-status` combines current weather from Open-Meteo with locally calculated lunar data from PyEphem. It is designed for lightweight panel widgets such as KDE Plasma command-output widgets and can also be reused in Waybar or similar bars.

## Example output

Compact mode:

```text
20°C · 58% | 🌔 91% ↑16:05 ↓05:04
```

Long mode:

```text
20°C · feels 20°C · RH 58% | 🌔 Waxing Gibbous · 91% · rise 16:05 · set 05:04
```

## Features

- Current temperature
- Relative humidity
- Apparent temperature in long mode
- Moon phase icon
- Moon illumination
- Moon phase name in long mode
- Next moonrise
- Next moonset
- Five-minute weather cache
- Graceful fallback to stale cached weather if Open-Meteo is temporarily unavailable
- Local lunar calculations, so Moon data continues working without network access

## Dependencies

On Ubuntu/Kubuntu:

```bash
sudo apt install curl jq python3-ephem
```

Python 3.9+ is recommended because the script uses `zoneinfo` from the standard library.

## Installation

Clone the repository:

```bash
git clone https://github.com/nilsonbazana/sky-status.git
cd sky-status
```

Install the script into your local executable path:

```bash
mkdir -p ~/.local/bin
cp sky-status ~/.local/bin/sky-status
chmod +x ~/.local/bin/sky-status
```

Test it:

```bash
~/.local/bin/sky-status
```

For the expanded output:

```bash
~/.local/bin/sky-status --long
```

## Location and timezone

The defaults are set for Maringá, Paraná, Brazil:

```text
Latitude:  -23.42
Longitude: -51.93
Timezone:  America/Sao_Paulo
```

You can override them without editing the script:

```bash
SKY_LAT=-23.42 SKY_LON=-51.93 SKY_TZ=America/Sao_Paulo ~/.local/bin/sky-status
```

For another location:

```bash
SKY_LAT=51.5074 SKY_LON=-0.1278 SKY_TZ=Europe/London ~/.local/bin/sky-status
```

## Weather source

Weather data comes from [Open-Meteo](https://open-meteo.com/).

The script requests:

- `temperature_2m`
- `apparent_temperature`
- `relative_humidity_2m`

To avoid unnecessary API calls, weather is cached for five minutes in:

```text
~/.cache/sky-status/weather.json
```

If Open-Meteo cannot be reached but an older valid cache exists, the output is prefixed with `~`:

```text
~20°C · 58% | 🌔 91% ↑16:05 ↓05:04
```

The tilde indicates stale cached weather.

## Moon calculations

Lunar data is calculated locally with PyEphem.

The script determines:

- lunar phase
- illuminated fraction
- next moonrise
- next moonset

The phase icons are standard Unicode Moon symbols:

```text
🌑 New Moon
🌒 Waxing Crescent
🌓 First Quarter
🌔 Waxing Gibbous
🌕 Full Moon
🌖 Waning Gibbous
🌗 Last Quarter
🌘 Waning Crescent
```

## KDE Plasma panel

A convenient approach is to use a Plasma widget that displays command output.

Set its command to the full executable path, for example:

```text
/home/your-user/.local/bin/sky-status
```

A refresh interval of around 60 seconds works well. The script's internal cache ensures Open-Meteo is still contacted no more than once every five minutes.

If the widget supports a separate tooltip command, use:

```text
/home/your-user/.local/bin/sky-status --long
```

This keeps the panel compact while exposing more detail on hover.

## Reusing with other bars

Because `sky-status` simply writes one line to stdout, it can be used with:

- KDE Plasma command-output widgets
- Waybar custom modules
- Polybar scripts
- shell prompts
- desktop monitoring tools

## License

No license has been added yet.
