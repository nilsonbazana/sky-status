import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasma5support as Plasma5Support

Item {
    id: page

    implicitWidth: 520
    implicitHeight: form.implicitHeight

    property alias cfg_locationName: locationName.text
    property alias cfg_latitude: latitude.text
    property alias cfg_longitude: longitude.text
    property alias cfg_timezone: timezone.text

    property string searchError: ""
    property bool searching: false
    property string activeSearchCommand: ""

    function shellQuote(value) {
        return "'" + String(value).replace(/'/g, "'\"'\"'") + "'"
    }

    function search() {
        const query = searchField.text.trim()
        if (!query.length || searching)
            return
        resultsModel.clear()
        searchError = ""
        searching = true
        const inner = "$HOME/.local/bin/sky-status --search-location " + shellQuote(query)
        activeSearchCommand = "/bin/sh -lc " + shellQuote(inner)
        searchRunner.connectSource(activeSearchCommand)
    }

    function useSelected() {
        if (results.currentIndex < 0 || results.currentIndex >= resultsModel.count)
            return
        const item = resultsModel.get(results.currentIndex)
        locationName.text = item.display_name
        latitude.text = String(item.latitude)
        longitude.text = String(item.longitude)
        timezone.text = item.timezone
    }

    ListModel { id: resultsModel }

    Plasma5Support.DataSource {
        id: searchRunner
        engine: "executable"
        onNewData: function(sourceName, data) {
            if (sourceName !== page.activeSearchCommand)
                return
            page.searching = false
            disconnectSource(sourceName)
            if (data["exit code"] !== 0) {
                page.searchError = data["stderr"] || i18n("Location search failed")
                return
            }
            try {
                const payload = JSON.parse(String(data["stdout"]).trim())
                const found = payload.results || []
                for (let i = 0; i < found.length; ++i) {
                    const r = found[i]
                    resultsModel.append({
                        "display_name": String(r.display_name || r.name || ""),
                        "latitude": Number(r.latitude),
                        "longitude": Number(r.longitude),
                        "timezone": String(r.timezone || "")
                    })
                }
                if (!found.length)
                    page.searchError = i18n("No matching locations found")
            } catch (e) {
                page.searchError = i18n("Could not read location search results")
            }
        }
    }

    Kirigami.FormLayout {
        id: form
        anchors.left: parent.left
        anchors.right: parent.right

        RowLayout {
            Kirigami.FormData.label: i18n("Find a place:")
            QQC2.TextField {
                id: searchField
                Layout.fillWidth: true
                placeholderText: i18n("City or town, e.g. London")
                onAccepted: page.search()
            }
            QQC2.Button {
                text: page.searching ? i18n("Searching…") : i18n("Search")
                enabled: searchField.text.trim().length > 0 && !page.searching
                onClicked: page.search()
            }
        }

        RowLayout {
            Kirigami.FormData.label: i18n("Matches:")
            QQC2.ComboBox {
                id: results
                Layout.fillWidth: true
                model: resultsModel
                textRole: "display_name"
                enabled: resultsModel.count > 0
            }
            QQC2.Button {
                text: i18n("Use")
                enabled: resultsModel.count > 0 && results.currentIndex >= 0
                onClicked: page.useSelected()
            }
        }

        Kirigami.InlineMessage {
            Kirigami.FormData.isSection: true
            Layout.fillWidth: true
            visible: page.searchError.length > 0
            text: page.searchError
            type: Kirigami.MessageType.Error
        }

        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Layout.fillWidth: true
        }

        QQC2.TextField {
            id: locationName
            Kirigami.FormData.label: i18n("Location name:")
            placeholderText: i18n("Maringá, Paraná, Brazil")
        }

        QQC2.TextField {
            id: latitude
            Kirigami.FormData.label: i18n("Latitude:")
            inputMethodHints: Qt.ImhFormattedNumbersOnly
            placeholderText: "-23.42"
        }

        QQC2.TextField {
            id: longitude
            Kirigami.FormData.label: i18n("Longitude:")
            inputMethodHints: Qt.ImhFormattedNumbersOnly
            placeholderText: "-51.93"
        }

        QQC2.TextField {
            id: timezone
            Kirigami.FormData.label: i18n("Timezone:")
            placeholderText: "America/Sao_Paulo"
        }

        Kirigami.InlineMessage {
            Kirigami.FormData.isSection: true
            Layout.fillWidth: true
            visible: true
            text: i18n("Search uses Open-Meteo geocoding. You can also enter coordinates and an IANA timezone manually. Applying these settings also updates sky-status's shared config file.")
            type: Kirigami.MessageType.Information
        }
    }
}
