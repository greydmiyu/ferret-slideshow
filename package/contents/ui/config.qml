/*
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import QtQuick.Dialogs
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM
import org.kde.kquickcontrols as KQuickControls

ColumnLayout {
    id: root

    property var configDialog
    property var wallpaperConfiguration: wallpaper.configuration
    property var parentLayout

    property alias cfg_Color: colorButton.color
    property color cfg_ColorDefault
    property int cfg_FillMode
    property int cfg_FillModeDefault
    property alias cfg_Blur: blurRadioButton.checked
    property bool cfg_BlurDefault
    property var cfg_SlidePaths: []
    property var cfg_SlidePathsDefault: []
    property int cfg_SlideInterval: 0
    property int cfg_SlideIntervalDefault: 0
    property var cfg_UncheckedSlides: []
    property var cfg_UncheckedSlidesDefault: []
    property string cfg_Image: ""

    property int hoursIntervalValue: Math.floor(cfg_SlideInterval / 3600)
    property int minutesIntervalValue: Math.floor((cfg_SlideInterval % 3600) / 60)
    property int secondsIntervalValue: cfg_SlideInterval % 60

    signal configurationChanged()

    function saveConfig() {}

    function folderToPath(urlString) {
        let text = urlString.toString();
        if (text.startsWith("file://")) {
            text = decodeURIComponent(text.substring(7));
            if (text.startsWith("//localhost/")) {
                text = text.substring(11);
            }
        }
        while (text.endsWith("/") && text !== "/") {
            text = text.slice(0, -1);
        }
        return text;
    }

    function addFolder(urlString) {
        const path = folderToPath(urlString);
        if (!path.length) {
            return;
        }
        const next = (cfg_SlidePaths || []).slice();
        if (next.indexOf(path) === -1) {
            next.push(path);
            cfg_SlidePaths = next;
            root.configurationChanged();
        }
    }

    spacing: Kirigami.Units.largeSpacing

    Kirigami.FormLayout {
        id: formLayout
        Layout.fillWidth: true

        Component.onCompleted: {
            if (typeof appearanceRoot !== "undefined") {
                twinFormLayouts.push(appearanceRoot.parentLayout);
            }
        }

        QQC2.ComboBox {
            id: resizeComboBox
            Kirigami.FormData.label: i18n("Positioning:")
            model: [
                { label: i18n("Scaled and cropped"), fillMode: Image.PreserveAspectCrop },
                { label: i18n("Scaled"), fillMode: Image.Stretch },
                { label: i18n("Scaled, keep proportions"), fillMode: Image.PreserveAspectFit },
                { label: i18n("Centered"), fillMode: Image.Pad },
                { label: i18n("Tiled"), fillMode: Image.Tile }
            ]
            textRole: "label"
            onActivated: cfg_FillMode = model[currentIndex].fillMode
            Component.onCompleted: setMethod()

            function setMethod() {
                for (let i = 0; i < model.length; i++) {
                    if (model[i].fillMode === root.cfg_FillMode) {
                        currentIndex = i;
                        break;
                    }
                }
            }

            KCM.SettingHighlighter {
                highlight: cfg_FillMode !== cfg_FillModeDefault
            }
        }

        QQC2.ButtonGroup { id: backgroundGroup }

        QQC2.RadioButton {
            id: blurRadioButton
            visible: cfg_FillMode === Image.PreserveAspectFit || cfg_FillMode === Image.Pad
            Kirigami.FormData.label: i18n("Background:")
            text: i18n("Blur")
            QQC2.ButtonGroup.group: backgroundGroup
        }

        RowLayout {
            visible: cfg_FillMode === Image.PreserveAspectFit || cfg_FillMode === Image.Pad
            QQC2.RadioButton {
                text: i18n("Solid color")
                checked: !cfg_Blur
                QQC2.ButtonGroup.group: backgroundGroup
            }
            KQuickControls.ColorButton {
                id: colorButton
                dialogTitle: i18n("Select Background Color")
            }
        }

        RowLayout {
            Kirigami.FormData.label: i18n("Change every:")
            QQC2.SpinBox {
                id: hoursInterval
                from: 0
                to: 24
                editable: true
                value: root.hoursIntervalValue
                onValueChanged: cfg_SlideInterval = hoursInterval.value * 3600
                                + minutesInterval.value * 60
                                + secondsInterval.value
                textFromValue: (value) => i18np("%1 hour", "%1 hours", value)
                valueFromText: (text) => parseInt(text, 10)
            }
            QQC2.SpinBox {
                id: minutesInterval
                from: 0
                to: 59
                editable: true
                value: root.minutesIntervalValue
                onValueChanged: cfg_SlideInterval = hoursInterval.value * 3600
                                + minutesInterval.value * 60
                                + secondsInterval.value
                textFromValue: (value) => i18np("%1 minute", "%1 minutes", value)
                valueFromText: (text) => parseInt(text, 10)
            }
            QQC2.SpinBox {
                id: secondsInterval
                from: 0
                to: 59
                editable: true
                value: root.secondsIntervalValue
                onValueChanged: cfg_SlideInterval = hoursInterval.value * 3600
                                + minutesInterval.value * 60
                                + secondsInterval.value
                textFromValue: (value) => i18np("%1 second", "%1 seconds", value)
                valueFromText: (text) => parseInt(text, 10)
            }
        }

        QQC2.Label {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: i18n("All zeros: pick when this screen loads, then only from Next Wallpaper.")
            font: Kirigami.Theme.smallFont
            opacity: 0.8
        }
    }

    RowLayout {
        Layout.fillWidth: true
        QQC2.Label {
            text: i18n("Folders")
            font.bold: true
            Layout.fillWidth: true
        }
        QQC2.Button {
            icon.name: "list-add"
            text: i18n("Add Folder…")
            onClicked: folderDialog.open()
        }
    }

    QQC2.Label {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        text: i18n("Folders are scanned recursively. Screens pull a unique image from that pool.")
        font: Kirigami.Theme.smallFont
        opacity: 0.8
    }

    QQC2.ScrollView {
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.minimumHeight: Kirigami.Units.gridUnit * 8
        clip: true

        ListView {
            id: folderList
            model: cfg_SlidePaths
            delegate: Kirigami.SwipeListItem {
                width: ListView.view.width
                contentItem: Item {
                    implicitHeight: label.implicitHeight
                    QQC2.Label {
                        id: label
                        anchors.fill: parent
                        anchors.rightMargin: Kirigami.Units.iconSizes.small + Kirigami.Units.largeSpacing * 2
                        text: modelData
                        elide: Text.ElideMiddle
                        verticalAlignment: Text.AlignVCenter
                    }
                }
                actions: [
                    Kirigami.Action {
                        icon.name: "list-remove"
                        text: i18n("Remove")
                        onTriggered: {
                            const next = cfg_SlidePaths.slice();
                            next.splice(index, 1);
                            cfg_SlidePaths = next;
                            root.configurationChanged();
                        }
                    }
                ]
            }

            QQC2.Label {
                anchors.centerIn: parent
                visible: folderList.count === 0
                opacity: 0.6
                text: i18n("Add every directory that should feed the pool.")
            }
        }
    }

    FolderDialog {
        id: folderDialog
        title: i18n("Choose wallpaper folder")
        onAccepted: root.addFolder(selectedFolder)
    }
}