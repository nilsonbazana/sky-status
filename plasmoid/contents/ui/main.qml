import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.plasma5support as Plasma5Support

PlasmoidItem {
    id: root

    property var sky: ({})
    property string lastError: ""
    property bool refreshing: false
    property bool syncingLocation: false
    property string activeSyncCommand: ""

    readonly property string command: "/bin/sh -lc '$HOME/.local/bin/sky-status --json'"
    readonly property string refreshCommand: "/bin/sh -lc '$HOME/.local/bin/sky-status --json --refresh'"
    readonly property string locationSignature: [
        plasmoid.configuration.locationName,
        plasmoid.configuration.latitude,
        plasmoid.configuration.longitude,
        plasmoid.configuration.timezone
    ].join("|")

    preferredRepresentation: compactRepresentation
    activationTogglesExpanded: true
    hideOnWindowDeactivate: true
    toolTipMainText: qsTr("Sky Status")
    toolTipSubText: bestWindow()
                        ? qsTr("%1 · best %2 · cloud %3%")
                            .arg(locationName()).arg(bestWindow().label).arg(metricValue(bestWindow().cloud.total))
                        : locationName()

    function shellQuote(value) {
        return "'" + String(value).replace(/'/g, "'\"'\"'") + "'"
    }
    function locationName() {
        if (sky && sky.location && sky.location.name)
            return sky.location.name
        return plasmoid.configuration.locationName || qsTr("Location")
    }
    function bestWindow() {
        return sky && sky.forecast && sky.forecast.best_window ? sky.forecast.best_window : null
    }
    function eveningCloud() {
        return sky && sky.forecast && sky.forecast.evening_cloud ? sky.forecast.evening_cloud : ({})
    }
    function timeline() {
        return sky && sky.forecast && sky.forecast.hours ? sky.forecast.hours : []
    }
    function astro() { return sky && sky.astro ? sky.astro : ({}) }
    function moon() { return sky && sky.moon ? sky.moon : ({ icon: "🌙" }) }
    function weather() { return sky && sky.weather ? sky.weather : ({}) }
    function darkness() { return sky && sky.darkness ? sky.darkness : ({}) }

    function metricValue(metric) {
        return metric && metric.value !== null && metric.value !== undefined ? metric.value : "—"
    }
    function metricQuality(metric) {
        return metric && metric.quality !== null && metric.quality !== undefined ? Number(metric.quality) : NaN
    }

    // Backend scores are normalized: 100 = favorable, 0 = poor.
    // This gives a continuous, restrained red → amber → green progression.
    function qualityColor(score) {
        const n = Number(score)
        if (isNaN(n)) return Kirigami.Theme.textColor
        const s = Math.max(0, Math.min(100, n)) / 100.0
        return Qt.hsla(0.33 * s, 0.58, 0.50, 1.0)
    }
    function qualityWord(score) {
        const n = Number(score)
        if (isNaN(n)) return qsTr("Unavailable")
        if (n >= 85) return qsTr("Excellent")
        if (n >= 65) return qsTr("Good")
        if (n >= 40) return qsTr("Marginal")
        return qsTr("Poor")
    }
    function moonIllumination() {
        const value = moon().illumination
        return value !== null && value !== undefined ? value : "—"
    }

    function consume(data) {
        refreshing = false
        if (data["exit code"] !== 0) {
            lastError = data["stderr"] || qsTr("Backend command failed")
            return
        }
        try {
            sky = JSON.parse(String(data["stdout"]).trim())
            lastError = ""
        } catch (e) {
            lastError = qsTr("Could not parse sky-status JSON")
        }
    }

    function refresh() {
        refreshing = true
        executable.connectSource(refreshCommand)
    }

    function syncLocation() {
        if (syncingLocation)
            return
        const inner = "$HOME/.local/bin/sky-status --save-config" +
                      " --lat " + shellQuote(plasmoid.configuration.latitude) +
                      " --lon " + shellQuote(plasmoid.configuration.longitude) +
                      " --timezone " + shellQuote(plasmoid.configuration.timezone) +
                      " --location-name " + shellQuote(plasmoid.configuration.locationName)
        activeSyncCommand = "/bin/sh -lc " + shellQuote(inner)
        syncingLocation = true
        executable.connectSource(activeSyncCommand)
    }

    onLocationSignatureChanged: locationSyncTimer.restart()

    Component.onCompleted: locationSyncTimer.start()

    Timer {
        id: locationSyncTimer
        interval: 350
        repeat: false
        onTriggered: root.syncLocation()
    }

    Plasma5Support.DataSource {
        id: executable
        engine: "executable"
        connectedSources: [root.command]
        interval: 300000
        onNewData: function(sourceName, data) {
            if (sourceName === root.activeSyncCommand && root.activeSyncCommand.length > 0) {
                root.syncingLocation = false
                disconnectSource(sourceName)
                root.activeSyncCommand = ""
                if (data["exit code"] !== 0) {
                    root.lastError = data["stderr"] || qsTr("Could not save location settings")
                    return
                }
                root.refresh()
                return
            }
            if (sourceName === root.command || sourceName === root.refreshCommand)
                root.consume(data)
            if (sourceName === root.refreshCommand)
                disconnectSource(sourceName)
        }
    }

    component MetricCell: ColumnLayout {
        property string title: ""
        property string value: "—"
        property real score: NaN
        property bool showWord: false
        spacing: 0

        PlasmaComponents.Label {
            Layout.alignment: Qt.AlignHCenter
            text: parent.title
            color: Kirigami.Theme.disabledTextColor
            font: Kirigami.Theme.smallFont
        }
        PlasmaComponents.Label {
            Layout.alignment: Qt.AlignHCenter
            text: parent.value
            color: root.qualityColor(parent.score)
            font.bold: true
        }
        PlasmaComponents.Label {
            Layout.alignment: Qt.AlignHCenter
            visible: parent.showWord
            text: root.qualityWord(parent.score)
            color: Kirigami.Theme.disabledTextColor
            font: Kirigami.Theme.smallFont
        }
    }

    component Card: Rectangle {
        color: "transparent"
        radius: Kirigami.Units.smallSpacing
        border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g,
                              Kirigami.Theme.textColor.b, 0.10)
    }

    compactRepresentation: Item {
        id: compact
        Layout.preferredWidth: compactRow.implicitWidth + Kirigami.Units.smallSpacing * 2
        Layout.minimumWidth: Layout.preferredWidth
        Layout.fillHeight: true

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.expanded = !root.expanded
        }

        RowLayout {
            id: compactRow
            anchors.centerIn: parent
            spacing: Kirigami.Units.smallSpacing

            PlasmaComponents.Label { text: "☁"; font.pixelSize: Math.max(13, compact.height * 0.42) }
            PlasmaComponents.Label {
                readonly property var metric: root.bestWindow() ? root.bestWindow().cloud.total : null
                text: root.metricValue(metric) + "%"
                color: root.qualityColor(root.metricQuality(metric))
                font.bold: true
            }
            Rectangle {
                Layout.preferredWidth: 1
                Layout.preferredHeight: compact.height * 0.45
                color: Kirigami.Theme.disabledTextColor
                opacity: 0.5
            }
            PlasmaComponents.Label { text: root.moon().icon || "🌙"; font.pixelSize: Math.max(13, compact.height * 0.42) }
            PlasmaComponents.Label { text: root.moonIllumination() + "%"; font.bold: true }
        }
    }

    fullRepresentation: Item {
        Layout.minimumWidth: 480
        Layout.minimumHeight: 430
        Layout.preferredWidth: 560
        Layout.preferredHeight: 540

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Kirigami.Units.largeSpacing
            spacing: Kirigami.Units.largeSpacing

            RowLayout {
                Layout.fillWidth: true
                ColumnLayout {
                    spacing: 0
                    Kirigami.Heading { text: qsTr("Tonight"); level: 2 }
                    PlasmaComponents.Label {
                        text: root.locationName() + (root.sky && root.sky.stale ? qsTr(" · cached forecast") : "")
                        color: root.sky && root.sky.stale ? root.qualityColor(45) : Kirigami.Theme.disabledTextColor
                        font: Kirigami.Theme.smallFont
                    }
                }
                Item { Layout.fillWidth: true }
                PlasmaComponents.ToolButton {
                    icon.name: "view-refresh"
                    enabled: !root.refreshing
                    onClicked: root.refresh()
                }
            }

            Card {
                Layout.fillWidth: true
                Layout.preferredHeight: 88
                color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g,
                               Kirigami.Theme.textColor.b, 0.045)
                RowLayout {
                    anchors.fill: parent
                    anchors.margins: Kirigami.Units.largeSpacing
                    ColumnLayout {
                        spacing: 2
                        PlasmaComponents.Label { text: qsTr("BEST OBSERVING WINDOW"); color: Kirigami.Theme.disabledTextColor; font: Kirigami.Theme.smallFont }
                        PlasmaComponents.Label {
                            text: root.bestWindow() ? root.bestWindow().label : "—"
                            font.pixelSize: Math.round(Kirigami.Units.gridUnit * 1.25)
                            font.bold: true
                        }
                    }
                    Item { Layout.fillWidth: true }
                    RowLayout {
                        PlasmaComponents.Label { text: "☁"; font.pixelSize: 28 }
                        PlasmaComponents.Label {
                            readonly property var metric: root.bestWindow() ? root.bestWindow().cloud.total : null
                            text: root.metricValue(metric) + "%"
                            color: root.qualityColor(root.metricQuality(metric))
                            font.pixelSize: Math.round(Kirigami.Units.gridUnit * 1.45)
                            font.bold: true
                        }
                    }
                }
            }

            Card {
                Layout.fillWidth: true
                Layout.preferredHeight: 160
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Kirigami.Units.largeSpacing
                    spacing: Kirigami.Units.smallSpacing
                    PlasmaComponents.Label { text: qsTr("EVENING CLOUD"); color: Kirigami.Theme.disabledTextColor; font: Kirigami.Theme.smallFont }
                    RowLayout {
                        Layout.fillWidth: true
                        MetricCell { Layout.fillWidth: true; title: qsTr("Total"); value: root.metricValue(root.eveningCloud().total) + "%"; score: root.metricQuality(root.eveningCloud().total) }
                        MetricCell { Layout.fillWidth: true; title: qsTr("Low"); value: root.metricValue(root.eveningCloud().low) + "%"; score: root.metricQuality(root.eveningCloud().low) }
                        MetricCell { Layout.fillWidth: true; title: qsTr("Mid"); value: root.metricValue(root.eveningCloud().mid) + "%"; score: root.metricQuality(root.eveningCloud().mid) }
                        MetricCell { Layout.fillWidth: true; title: qsTr("High"); value: root.metricValue(root.eveningCloud().high) + "%"; score: root.metricQuality(root.eveningCloud().high) }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: Kirigami.Units.smallSpacing
                        Repeater {
                            model: root.timeline()
                            delegate: ColumnLayout {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                spacing: 1
                                Item {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    Layout.minimumHeight: 44
                                    Rectangle {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        anchors.bottom: parent.bottom
                                        width: Math.max(5, parent.width * 0.30)
                                        height: Math.max(3, (Number(modelData.cloud) / 100.0) * parent.height)
                                        radius: width / 2
                                        color: root.qualityColor(modelData.quality)
                                    }
                                }
                                PlasmaComponents.Label { Layout.alignment: Qt.AlignHCenter; text: modelData.time; font: Kirigami.Theme.smallFont; color: Kirigami.Theme.disabledTextColor }
                            }
                        }
                    }
                }
            }

            Card {
                Layout.fillWidth: true
                Layout.preferredHeight: 82
                RowLayout {
                    anchors.fill: parent
                    anchors.margins: Kirigami.Units.largeSpacing
                    MetricCell {
                        Layout.fillWidth: true
                        readonly property var metric: root.astro().seeing
                        title: qsTr("SEEING")
                        value: metric ? metric.label : "—"
                        score: metric ? metric.quality : NaN
                        showWord: true
                    }
                    MetricCell {
                        Layout.fillWidth: true
                        readonly property var metric: root.astro().transparency
                        title: qsTr("TRANSPARENCY")
                        value: metric ? metric.label : "—"
                        score: metric ? metric.quality : NaN
                        showWord: true
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    PlasmaComponents.Label { text: qsTr("DARKNESS"); color: Kirigami.Theme.disabledTextColor; font: Kirigami.Theme.smallFont }
                    PlasmaComponents.Label { text: qsTr("Dusk %1   Dawn %2").arg(root.darkness().dusk || "—").arg(root.darkness().dawn || "—") }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    PlasmaComponents.Label { text: qsTr("MOON"); color: Kirigami.Theme.disabledTextColor; font: Kirigami.Theme.smallFont }
                    PlasmaComponents.Label { text: (root.moon().icon || "🌙") + " " + root.moonIllumination() + "%  " + (root.moon().phase || "") }
                    PlasmaComponents.Label { text: qsTr("↑ %1   ↓ %2").arg(root.moon().rise || "—").arg(root.moon().set || "—"); color: Kirigami.Theme.disabledTextColor; font: Kirigami.Theme.smallFont }
                }
            }

            Card {
                Layout.fillWidth: true
                Layout.preferredHeight: 58
                color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g,
                               Kirigami.Theme.textColor.b, 0.035)
                RowLayout {
                    anchors.fill: parent
                    anchors.margins: Kirigami.Units.largeSpacing
                    PlasmaComponents.Label { text: qsTr("Temperature"); color: Kirigami.Theme.disabledTextColor }
                    PlasmaComponents.Label {
                        readonly property var metric: root.weather().temperature
                        text: metric && metric.value !== null && metric.value !== undefined ? metric.value + metric.unit : "—"
                        color: root.qualityColor(metric ? metric.quality : NaN)
                        font.bold: true
                    }
                    Item { Layout.fillWidth: true }
                    PlasmaComponents.Label { text: qsTr("Humidity"); color: Kirigami.Theme.disabledTextColor }
                    PlasmaComponents.Label {
                        readonly property var metric: root.weather().humidity
                        text: metric && metric.value !== null && metric.value !== undefined ? metric.value + metric.unit : "—"
                        color: root.qualityColor(metric ? metric.quality : NaN)
                        font.bold: true
                    }
                }
            }

            PlasmaComponents.Label {
                Layout.fillWidth: true
                visible: root.lastError.length > 0
                text: root.lastError
                color: root.qualityColor(0)
                wrapMode: Text.Wrap
                font: Kirigami.Theme.smallFont
            }
        }
    }
}
