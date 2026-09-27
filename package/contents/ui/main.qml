/*
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Window
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid
import org.kde.plasma.plasma5support as Plasma5Support

WallpaperItem {
    id: root

    property string currentPath: configuration.Image || ""
    property string screenName: Screen.name || ("screen-" + Math.round(Screen.desktopAvailableWidth) + "x" + Math.round(Screen.desktopAvailableHeight))
    property bool pickInFlight: false

    function folderList() {
        const raw = root.configuration.SlidePaths;
        if (!raw) {
            return [];
        }
        if (Array.isArray(raw)) {
            return raw.filter((item) => item && item.length);
        }
        if (typeof raw === "string" && raw.length) {
            return raw.split(",").map((item) => item.trim()).filter((item) => item.length);
        }
        const out = [];
        for (let i = 0; i < raw.length; ++i) {
            if (raw[i]) {
                out.push(raw[i]);
            }
        }
        return out;
    }

    function connectedScreenNames() {
        const screens = Qt.application.screens;
        const names = [];
        for (let i = 0; i < screens.length; ++i) {
            names.push(screens[i].name);
        }
        return names;
    }

    function localPathFromUrl(urlString) {
        let text = urlString.toString();
        if (text.startsWith("file://")) {
            text = decodeURIComponent(text.substring(7));
            if (text.startsWith("//localhost/")) {
                text = text.substring(11);
            }
        }
        return text;
    }

    function pickNext() {
        const folders = folderList();
        if (folders.length === 0 || pickInFlight) {
            if (folders.length === 0) {
                root.loading = false;
            }
            return;
        }

        const bin = localPathFromUrl(Qt.resolvedUrl("../code/pick"));
        const script = localPathFromUrl(Qt.resolvedUrl("../code/pick.py"));
        let args = " --screen " + shellQuote(root.screenName)
                 + " --screens " + shellQuote(connectedScreenNames().join(","));
        if (root.currentPath) {
            args += " --avoid " + shellQuote(localPathFromUrl(root.currentPath));
        }
        for (let i = 0; i < folders.length; ++i) {
            args += " --folder " + shellQuote(localPathFromUrl(folders[i]));
        }
        // Prefer the Nim binary; fall back to pick.py.
        let command = "if [ -x " + shellQuote(bin) + " ]; then "
                    + shellQuote(bin) + args
                    + "; else python3 " + shellQuote(script) + args
                    + "; fi";

        pickInFlight = true;
        runner.connectSource(command);
    }

    function shellQuote(value) {
        return "'" + value.toString().replace(/'/g, "'\\''") + "'";
    }

    onOpenUrlRequested: (url) => {
        const path = localPathFromUrl(url);
        const next = folderList().slice();
        if (next.indexOf(path) === -1) {
            next.push(path);
            root.configuration.SlidePaths = next;
            root.configuration.writeConfig();
            pickNext();
        }
    }

    contextualActions: [
        PlasmaCore.Action {
            text: i18n("Next Wallpaper")
            icon.name: "user-desktop"
            onTriggered: pickNext()
        },
        PlasmaCore.Action {
            text: i18n("Open Current Wallpaper")
            icon.name: "document-open"
            enabled: root.currentPath.length > 0
            onTriggered: Qt.openUrlExternally(root.currentPath)
        }
    ]

    Component {
        id: slideComponent
        Rectangle {
            id: slide
            color: root.configuration.Color
            property alias status: foreground.status
            property url source

            Image {
                anchors.fill: parent
                visible: root.configuration.Blur
                         && (root.configuration.FillMode === Image.PreserveAspectFit
                             || root.configuration.FillMode === Image.Pad)
                source: foreground.source
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: false
                opacity: 0.35
            }

            Image {
                id: foreground
                anchors.fill: parent
                fillMode: root.configuration.FillMode
                asynchronous: true
                cache: false
                autoTransform: true
                source: slide.source
                sourceSize: Qt.size(root.width * Screen.devicePixelRatio,
                                    root.height * Screen.devicePixelRatio)
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        color: root.configuration.Color
    }

    QQC2.StackView {
        id: stack
        anchors.fill: parent

        property Item pendingImage
        property bool skipAnimation: true

        replaceEnter: Transition {
            OpacityAnimator {
                id: enterFade
                from: 0
                to: 1
                // Match org.kde.slideshow: ~1s fade; 1ms skip avoids first-load flicker (QTBUG-106797)
                duration: stack.skipAnimation ? 1 : Math.round(Kirigami.Units.veryLongDuration * 2.5)
            }
        }
        // Keep the old image until the new one has faded in so the solid
        // background does not flash through.
        replaceExit: Transition {
            PauseAnimation {
                duration: enterFade.duration + 500
            }
        }

        function showPath(url) {
            if (pendingImage) {
                pendingImage.statusChanged.disconnect(replaceWhenLoaded);
                pendingImage.destroy();
                pendingImage = null;
            }
            skipAnimation = currentItem === null;
            pendingImage = slideComponent.createObject(stack, {
                source: url,
                opacity: 0,
                parent: stack
            });
            pendingImage.statusChanged.connect(replaceWhenLoaded);
            replaceWhenLoaded();
        }

        function replaceWhenLoaded() {
            if (!pendingImage || pendingImage.status === Image.Loading) {
                return;
            }
            pendingImage.statusChanged.disconnect(replaceWhenLoaded);
            pendingImage.QQC2.StackView.onActivated.connect(() => {
                root.accentColorChanged();
            });
            pendingImage.QQC2.StackView.onDeactivated.connect(pendingImage.destroy);
            pendingImage.QQC2.StackView.onRemoved.connect(pendingImage.destroy);
            replace(pendingImage, {}, QQC2.StackView.Transition);
            root.loading = false;
            pendingImage = null;
        }
    }

    onCurrentPathChanged: {
        if (currentPath.length) {
            stack.showPath(currentPath);
        }
    }

    Plasma5Support.DataSource {
        id: runner
        engine: "executable"
        connectedSources: []

        onNewData: function (sourceName, data) {
            disconnectSource(sourceName);
            pickInFlight = false;
            const stdout = (data.stdout || "").trim();
            if (!stdout.length) {
                root.loading = false;
                console.warn("org.grey.simpleslideshow: empty picker output", data.stderr);
                return;
            }
            let result;
            try {
                result = JSON.parse(stdout.split("\n").pop());
            } catch (error) {
                root.loading = false;
                console.warn("org.grey.simpleslideshow: bad picker JSON", stdout, error);
                return;
            }
            if (result.path) {
                const url = result.path.startsWith("file:") ? result.path : ("file://" + result.path);
                root.currentPath = url;
                root.configuration.Image = url;
            } else {
                root.loading = false;
                console.warn("org.grey.simpleslideshow:", result.error || "no path");
            }
        }
    }

    Timer {
        id: intervalTimer
        interval: Math.max(0, root.configuration.SlideInterval) * 1000
        running: root.configuration.SlideInterval > 0
        repeat: true
        onTriggered: pickNext()
    }

    Connections {
        target: root.configuration
        function onSlidePathsChanged() { pickNext(); }
        function onSlideIntervalChanged() {
            intervalTimer.restart();
        }
    }

    Component.onCompleted: {
        root.loading = true;
        pickNext();
    }
}