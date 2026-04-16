import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.extras as PlasmaExtras
import org.kde.plasma.plasma5support 2.0 as P5Support

PlasmoidItem {
    id: root

    property var tsInfo: ({})
    property bool hasData: false
    property bool tsConnected: hasData && (tsInfo.connected === true)
    property var sshUsers: ({})

    property string copiedText: ""

    ListModel { id: peerModel }

    // Run shell commands (clipboard, ssh, browser)
    P5Support.DataSource {
        id: cmdRunner
        engine: "executable"
    }
    function runCommand(cmd) {
        if (cmdRunner.connectedSources.indexOf(cmd) !== -1) {
            cmdRunner.connectedSources.splice(cmdRunner.connectedSources.indexOf(cmd), 1)
        }
        cmdRunner.connectedSources.push(cmd)
    }
    function copyToClipboard(text) {
        runCommand("echo -n '" + text.replace(/'/g, "'\\''") + "' | wl-copy")
        root.copiedText = text
        copiedTimer.restart()
    }
    readonly property string credentialsFile: {
        var url = Qt.resolvedUrl("../tools/credentials.json").toString()
        return url.replace("file://", "")
    }
    property var credentials: ({})

    // Load saved credentials
    P5Support.DataSource {
        id: credLoader
        engine: "executable"
        connectedSources: ["cat '" + root.credentialsFile + "' 2>/dev/null || echo '{}'"]
        onNewData: function(source, data) {
            if (data["exit code"] == 0 && data["stdout"].length > 0) {
                try {
                    root.credentials = JSON.parse(data["stdout"])
                } catch(e) {}
            }
        }
    }

    function getSavedCreds(service, dnsName) {
        var key = service + ":" + dnsName
        return root.credentials[key] || {}
    }

    function saveCreds(service, dnsName, creds) {
        var key = service + ":" + dnsName
        var all = root.credentials
        all[key] = creds
        root.credentials = all
        runCommand("echo '" + JSON.stringify(all).replace(/'/g, "'\\''") + "' > '" + credentialsFile + "'")
    }

    property string pendingService: ""
    property string pendingHost: ""
    property string pendingIp: ""
    property string pendingUsername: ""
    property string pendingPassword: ""

    function showConnectDialog(service, dnsName, ip) {
        var saved = getSavedCreds(service, dnsName)
        root.pendingService = service
        root.pendingHost = dnsName
        root.pendingIp = ip || ""
        root.pendingUsername = saved.username || ""
        root.pendingPassword = saved.password || ""
    }
    function cancelConnect() {
        root.pendingService = ""
    }

    function doConnect(service, dnsName, ip, username, password, remember) {
        if (remember) {
            var creds = {"username": username}
            if (password) creds.password = password
            saveCreds(service, dnsName, creds)
        }

        if (service === "ssh") {
            var target = username ? (username + "@" + dnsName) : dnsName
            runCommand("nohup konsole -e ssh " + target + " >/dev/null 2>&1 &")
        } else if (service === "rdp") {
            var profile = "/tmp/tailscale-rdp-" + dnsName.replace(/[^a-zA-Z0-9]/g, "_") + ".remmina"
            var cmd = "cat > " + profile + " << 'EOF'\n"
                + "[remmina]\n"
                + "name=" + dnsName + "\n"
                + "protocol=RDP\n"
                + "server=" + dnsName + "\n"
                + "username=" + username + "\n"
                + "password=" + password + "\n"
                + "colordepth=32\n"
                + "quality=2\n"
                + "glyph-cache=true\n"
                + "network=lan\n"
                + "gfx=false\n"
                + "rfx=false\n"
                + "disableautoreconnect=0\n"
                + "EOF\n"
                + "nohup remmina -c " + profile + " >/dev/null 2>&1 &"
            runCommand(cmd)
        } else if (service === "vnc") {
            var vncType = ""
            // Find vnc_type from peers
            for (var i = 0; i < peerModel.count; i++) {
                if (peerModel.get(i).pDnsName === dnsName) {
                    vncType = peerModel.get(i).pVncType
                    break
                }
            }
            if (vncType === "realvnc") {
                runCommand("nohup vncviewer " + dnsName + " >/dev/null 2>&1 &")
            } else {
                runCommand("nohup remmina -c vnc://" + (username ? (username + "@") : "") + dnsName + " >/dev/null 2>&1 &")
            }
        } else if (service === "nomachine") {
            var nxsFile = "/tmp/tailscale-nx-" + dnsName.replace(/[^a-zA-Z0-9]/g, "_") + ".nxs"
            var nxCmd = "cat > " + nxsFile + " << 'NXEOF'\n"
                + '<!DOCTYPE NXClientSettings>\n'
                + '<NXClientSettings version=\"2.3\" application=\"nxclient\" >\n'
                + ' <group name=\"General\" >\n'
                + '  <option key=\"Connection service\" value=\"nx\" />\n'
                + '  <option key=\"NoMachine daemon port\" value=\"4000\" />\n'
                + ' </group>\n'
                + ' <group name=\"Local Settings\" >\n'
                + '  <option key=\"Server name\" value=\"' + dnsName + '\" />\n'
                + '  <option key=\"List of hosts\" value=\"' + ip + '\" />\n'
                + '  <option key=\"List of ports\" value=\"4000\" />\n'
                + '  <option key=\"List of protocols\" value=\"nx\" />\n'
                + ' </group>\n'
                + ' <group name=\"Login\" >\n'
                + '  <option key=\"Server authentication method\" value=\"system\" />\n'
                + '  <option key=\"System login method\" value=\"password\" />\n'
                + '  <option key=\"User\" value=\"' + username + '\" />\n'
                + ' </group>\n'
                + '</NXClientSettings>\n'
                + "NXEOF\n"
                + "nohup /usr/NX/bin/nxplayer --session " + nxsFile + " >/dev/null 2>&1 &"
            runCommand(nxCmd)
        }
    }
    function openInBrowser(dnsName) {
        Qt.openUrlExternally("http://" + dnsName)
    }
    Timer {
        id: copiedTimer
        interval: 2000
        onTriggered: root.copiedText = ""
    }

    function updateModels() {
        peerModel.clear()
        if (tsConnected && tsInfo.peers) {
            for (var i = 0; i < tsInfo.peers.length; i++) {
                var p = tsInfo.peers[i]
                var svc = p.services || {}
                peerModel.append({
                    "pName": p.name || "?",
                    "pDnsName": p.dns_name || "",
                    "pHttpsUrl": p.https_url || "",
                    "pIp": p.ip || "",
                    "pOs": p.os || "",
                    "pOnline": p.online || false,
                    "pExitNode": p.exit_node || false,
                    "pRelay": p.relay || "",
                    "pHasSsh": svc.ssh || false,
                    "pHasVnc": svc.vnc || false,
                    "pVncType": p.vnc_type || "",
                    "pHasRdp": svc.rdp || false,
                    "pHasNomachine": svc.nomachine || false,
                    "pHasHttp": svc.http || false,
                    "pHasHttps": svc.https || false
                })
            }
        }
    }

    readonly property string helperPath: {
        var url = Qt.resolvedUrl("../tools/tailscale-status.py").toString()
        return url.replace("file://", "")
    }

    readonly property string connectedIcon: Qt.resolvedUrl("../icons/tailscale-connected.svg")
    readonly property string disconnectedIcon: Qt.resolvedUrl("../icons/tailscale-disconnected.svg")

    Plasmoid.status: PlasmaCore.Types.ActiveStatus

    switchWidth: Kirigami.Units.gridUnit * 18
    switchHeight: Kirigami.Units.gridUnit * 20

    toolTipMainText: "Tailscale"
    toolTipSubText: {
        if (!hasData) return "Checking..."
        if (!tsConnected) return "Disconnected"
        var ip = tsInfo.tailscale_ip || ""
        var online = tsInfo.online_peers || 0
        var total = tsInfo.total_peers || 0
        return ip + " \u2022 " + online + "/" + total + " peers online"
    }

    P5Support.DataSource {
        id: infoSource
        engine: "executable"
        connectedSources: ["python3 '" + root.helperPath + "'"]
        interval: 5000
        onNewData: function(source, data) {
            if (data["exit code"] == 0 && data["stdout"].length > 0) {
                try {
                    root.tsInfo = JSON.parse(data["stdout"])
                    root.hasData = true
                    root.updateModels()
                } catch(e) {}
            }
        }
    }

    compactRepresentation: MouseArea {
        implicitWidth: Kirigami.Units.iconSizes.medium
        implicitHeight: Kirigami.Units.iconSizes.medium

        Image {
            readonly property real iconSize: Math.min(parent.width, parent.height) * 0.7
            anchors.centerIn: parent
            width: iconSize
            height: iconSize
            source: root.tsConnected ? root.connectedIcon : root.disconnectedIcon
            sourceSize: Qt.size(iconSize, iconSize)
            smooth: true
            fillMode: Image.PreserveAspectFit
        }

        onClicked: root.expanded = !root.expanded
    }

    fullRepresentation: Item {
        id: fullRoot
        Layout.minimumWidth: Kirigami.Units.gridUnit * 18
        Layout.preferredWidth: Kirigami.Units.gridUnit * 18
        Layout.preferredHeight: Kirigami.Units.gridUnit * 22
        Layout.maximumHeight: Kirigami.Units.gridUnit * 30

        // Credentials overlay (shown when pendingService is set)
        Rectangle {
            anchors.fill: parent
            z: 10
            visible: root.pendingService !== ""
            color: Kirigami.Theme.backgroundColor

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Kirigami.Units.largeSpacing
                spacing: Kirigami.Units.largeSpacing

                PlasmaExtras.Heading {
                    level: 3
                    Layout.fillWidth: true
                    text: {
                        var labels = {"ssh": "SSH", "rdp": "RDP", "vnc": "VNC", "nomachine": "NoMachine"}
                        return (labels[root.pendingService] || root.pendingService) + " connect"
                    }
                }
                PlasmaComponents.Label {
                    Layout.fillWidth: true
                    text: root.pendingHost
                    elide: Text.ElideRight
                    opacity: 0.7
                }

                Kirigami.Separator { Layout.fillWidth: true }

                RowLayout {
                    Layout.fillWidth: true
                    PlasmaComponents.Label { text: "Username"; Layout.preferredWidth: Kirigami.Units.gridUnit * 5 }
                    QQC2.TextField {
                        id: userField
                        Layout.fillWidth: true
                        text: root.pendingUsername
                        placeholderText: "username"
                        onTextChanged: root.pendingUsername = text
                        Keys.onReturnPressed: {
                            var needsPass = root.pendingService === "rdp" || root.pendingService === "vnc"
                            if (needsPass && passField.text === "")
                                passField.forceActiveFocus()
                            else
                                connectBtn.clicked()
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    visible: root.pendingService === "rdp" || root.pendingService === "vnc"
                    PlasmaComponents.Label { text: "Password"; Layout.preferredWidth: Kirigami.Units.gridUnit * 5 }
                    QQC2.TextField {
                        id: passField
                        Layout.fillWidth: true
                        text: root.pendingPassword
                        echoMode: TextInput.Password
                        placeholderText: "password"
                        onTextChanged: root.pendingPassword = text
                        Keys.onReturnPressed: connectBtn.clicked()
                    }
                }

                QQC2.CheckBox {
                    id: rememberCheck
                    text: "Remember"
                    checked: true
                }

                Item { Layout.fillHeight: true }

                RowLayout {
                    Layout.fillWidth: true
                    QQC2.Button {
                        text: "Cancel"
                        Layout.fillWidth: true
                        onClicked: root.cancelConnect()
                    }
                    QQC2.Button {
                        id: connectBtn
                        text: "Connect"
                        Layout.fillWidth: true
                        highlighted: true
                        onClicked: {
                            var svc = root.pendingService
                            var host = root.pendingHost
                            var ip = root.pendingIp
                            var u = userField.text
                            var p = passField.text
                            var remember = rememberCheck.checked
                            root.cancelConnect()
                            root.doConnect(svc, host, ip, u, p, remember)
                        }
                    }
                }
            }

            onVisibleChanged: {
                if (visible) {
                    userField.forceActiveFocus()
                    userField.selectAll()
                }
            }
        }

        QQC2.ScrollView {
            id: scrollView
            anchors.fill: parent
            visible: root.pendingService === ""

            QQC2.ScrollBar.horizontal.policy: QQC2.ScrollBar.AlwaysOff

            ColumnLayout {
                width: scrollView.availableWidth
                spacing: Kirigami.Units.smallSpacing

            // Header
            PlasmaExtras.Heading {
                level: 3
                text: "Tailscale"
                Layout.fillWidth: true
                Layout.margins: Kirigami.Units.smallSpacing
            }

            Kirigami.Separator { Layout.fillWidth: true }

            // Status
            PlasmaExtras.Heading {
                level: 4
                text: "Status"
                Layout.leftMargin: Kirigami.Units.smallSpacing
            }
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.largeSpacing
                Layout.rightMargin: Kirigami.Units.smallSpacing
                PlasmaComponents.Label { text: "Connection"; Layout.fillWidth: true }
                PlasmaComponents.Label {
                    text: !root.hasData ? "Checking..." : (root.tsConnected ? "Connected" : "Disconnected")
                    color: !root.hasData
                        ? Kirigami.Theme.textColor
                        : (root.tsConnected ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.negativeTextColor)
                }
            }

            // ---------- Detail sections (only when connected) ----------

            Kirigami.Separator {
                Layout.fillWidth: true
                visible: root.tsConnected
            }

            // This Device
            PlasmaExtras.Heading {
                level: 4
                text: "This Device"
                Layout.leftMargin: Kirigami.Units.smallSpacing
                visible: root.tsConnected
            }
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.largeSpacing
                Layout.rightMargin: Kirigami.Units.smallSpacing
                visible: root.tsConnected
                PlasmaComponents.Label { text: "Hostname"; Layout.fillWidth: true }
                PlasmaComponents.Label {
                    text: root.tsInfo.hostname || "N/A"
                }
            }
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.largeSpacing
                Layout.rightMargin: Kirigami.Units.smallSpacing
                visible: root.tsConnected
                PlasmaComponents.Label { text: "Tailscale IP"; Layout.fillWidth: true }
                PlasmaComponents.Label {
                    text: root.tsInfo.tailscale_ip || "N/A"
                }
            }
            MouseArea {
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.largeSpacing
                Layout.rightMargin: Kirigami.Units.smallSpacing
                implicitHeight: dnsRow.implicitHeight
                visible: root.tsConnected
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    var name = root.tsInfo.dns_name || ""
                    if (name) root.copyToClipboard(name)
                }
                RowLayout {
                    id: dnsRow
                    anchors.fill: parent
                    PlasmaComponents.Label { text: "DNS Name"; Layout.fillWidth: true }
                    PlasmaComponents.Label {
                        text: root.copiedText === (root.tsInfo.dns_name || "")
                            ? "Copied!"
                            : (root.tsInfo.dns_name || "N/A")
                        font: Kirigami.Theme.smallFont
                        color: root.copiedText === (root.tsInfo.dns_name || "")
                            ? Kirigami.Theme.positiveTextColor
                            : Kirigami.Theme.textColor
                    }
                }
            }
            MouseArea {
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.largeSpacing
                Layout.rightMargin: Kirigami.Units.smallSpacing
                implicitHeight: httpsRow.implicitHeight
                visible: root.tsConnected && (root.tsInfo.https_url || "") !== ""
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    var url = root.tsInfo.https_url || ""
                    if (url) root.copyToClipboard(url)
                }
                RowLayout {
                    id: httpsRow
                    anchors.fill: parent
                    PlasmaComponents.Label { text: "HTTPS"; Layout.fillWidth: true }
                    PlasmaComponents.Label {
                        text: root.copiedText === (root.tsInfo.https_url || "")
                            ? "Copied!"
                            : (root.tsInfo.https_url || "N/A")
                        font: Kirigami.Theme.smallFont
                        color: root.copiedText === (root.tsInfo.https_url || "")
                            ? Kirigami.Theme.positiveTextColor
                            : Kirigami.Theme.textColor
                    }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.largeSpacing
                Layout.rightMargin: Kirigami.Units.smallSpacing
                visible: root.tsConnected
                PlasmaComponents.Label { text: "Relay"; Layout.fillWidth: true }
                PlasmaComponents.Label {
                    text: root.tsInfo.relay || "N/A"
                }
            }

            Kirigami.Separator {
                Layout.fillWidth: true
                visible: root.tsConnected
            }

            // Network
            PlasmaExtras.Heading {
                level: 4
                text: "Network"
                Layout.leftMargin: Kirigami.Units.smallSpacing
                visible: root.tsConnected
            }
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.largeSpacing
                Layout.rightMargin: Kirigami.Units.smallSpacing
                visible: root.tsConnected
                PlasmaComponents.Label { text: "Tailnet"; Layout.fillWidth: true }
                PlasmaComponents.Label {
                    text: root.tsInfo.tailnet || "N/A"
                }
            }
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.largeSpacing
                Layout.rightMargin: Kirigami.Units.smallSpacing
                visible: root.tsConnected
                PlasmaComponents.Label { text: "Exit Node"; Layout.fillWidth: true }
                PlasmaComponents.Label {
                    text: root.tsInfo.exit_node || "None"
                    color: root.tsInfo.exit_node
                        ? Kirigami.Theme.positiveTextColor
                        : Kirigami.Theme.textColor
                }
            }
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.largeSpacing
                Layout.rightMargin: Kirigami.Units.smallSpacing
                visible: root.tsConnected
                PlasmaComponents.Label { text: "Version"; Layout.fillWidth: true }
                PlasmaComponents.Label {
                    text: {
                        var v = root.tsInfo.version || "N/A"
                        // Truncate long version strings
                        var dash = v.indexOf("-")
                        return dash > 0 ? v.substring(0, dash) : v
                    }
                    font: Kirigami.Theme.smallFont
                }
            }

            Kirigami.Separator {
                Layout.fillWidth: true
                visible: root.tsConnected
            }

            // Peers
            PlasmaExtras.Heading {
                level: 4
                text: {
                    if (!root.tsConnected) return "Peers"
                    var online = root.tsInfo.online_peers || 0
                    var total = root.tsInfo.total_peers || 0
                    return "Peers (" + online + "/" + total + " online)"
                }
                Layout.leftMargin: Kirigami.Units.smallSpacing
                visible: root.tsConnected
            }
            PlasmaComponents.Label {
                text: "No peers"
                Layout.leftMargin: Kirigami.Units.largeSpacing
                opacity: 0.6
                visible: root.tsConnected && peerModel.count === 0
            }
            Repeater {
                model: peerModel
                delegate: RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: Kirigami.Units.largeSpacing
                    Layout.rightMargin: Kirigami.Units.smallSpacing
                    spacing: Kirigami.Units.smallSpacing

                    Rectangle {
                        width: Kirigami.Units.smallSpacing * 2
                        height: width
                        radius: width / 2
                        color: model.pOnline
                            ? Kirigami.Theme.positiveTextColor
                            : Kirigami.Theme.disabledTextColor
                        Layout.alignment: Qt.AlignVCenter
                    }

                    MouseArea {
                        Layout.fillWidth: true
                        implicitHeight: peerLabel.implicitHeight
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (model.pDnsName) root.copyToClipboard(model.pDnsName)
                        }
                        PlasmaComponents.Label {
                            id: peerLabel
                            anchors.fill: parent
                            text: root.copiedText === model.pDnsName
                                ? "Copied!"
                                : (model.pName + (model.pExitNode ? " \u2022 exit" : ""))
                            elide: Text.ElideRight
                            color: root.copiedText === model.pDnsName
                                ? Kirigami.Theme.positiveTextColor
                                : Kirigami.Theme.textColor
                        }
                    }

                    PlasmaComponents.Label {
                        text: model.pOs
                        opacity: 0.6
                        font: Kirigami.Theme.smallFont
                    }

                    // SSH
                    PlasmaComponents.ToolButton {
                        visible: model.pHasSsh
                        icon.name: "utilities-terminal"
                        icon.width: Kirigami.Units.iconSizes.smallMedium
                        icon.height: Kirigami.Units.iconSizes.smallMedium
                        implicitWidth: Kirigami.Units.iconSizes.medium
                        implicitHeight: Kirigami.Units.iconSizes.medium
                        PlasmaComponents.ToolTip { text: "SSH to " + model.pDnsName }
                        onClicked: root.showConnectDialog("ssh", model.pDnsName, model.pIp)
                    }

                    // VNC
                    PlasmaComponents.ToolButton {
                        visible: model.pHasVnc
                        icon.name: model.pVncType === "realvnc" ? "" : "krdc"
                        icon.source: model.pVncType === "realvnc" ? Qt.resolvedUrl("../icons/realvnc.png") : ""
                        icon.width: Kirigami.Units.iconSizes.smallMedium
                        icon.height: Kirigami.Units.iconSizes.smallMedium
                        implicitWidth: Kirigami.Units.iconSizes.medium
                        implicitHeight: Kirigami.Units.iconSizes.medium
                        PlasmaComponents.ToolTip {
                            text: (model.pVncType === "realvnc" ? "RealVNC to " : "VNC to ") + model.pDnsName
                        }
                        onClicked: root.showConnectDialog("vnc", model.pDnsName, model.pIp)
                    }

                    // RDP
                    PlasmaComponents.ToolButton {
                        visible: model.pHasRdp
                        icon.name: "krdc"
                        icon.width: Kirigami.Units.iconSizes.smallMedium
                        icon.height: Kirigami.Units.iconSizes.smallMedium
                        implicitWidth: Kirigami.Units.iconSizes.medium
                        implicitHeight: Kirigami.Units.iconSizes.medium
                        PlasmaComponents.ToolTip { text: "RDP to " + model.pDnsName }
                        onClicked: root.showConnectDialog("rdp", model.pDnsName, model.pIp)
                    }

                    // NoMachine
                    PlasmaComponents.ToolButton {
                        visible: model.pHasNomachine
                        icon.source: Qt.resolvedUrl("../icons/nomachine.png")
                        icon.width: Kirigami.Units.iconSizes.smallMedium
                        icon.height: Kirigami.Units.iconSizes.smallMedium
                        implicitWidth: Kirigami.Units.iconSizes.medium
                        implicitHeight: Kirigami.Units.iconSizes.medium
                        PlasmaComponents.ToolTip { text: "NoMachine to " + model.pDnsName }
                        onClicked: root.showConnectDialog("nomachine", model.pDnsName, model.pIp)
                    }

                    // HTTP/browser
                    PlasmaComponents.ToolButton {
                        visible: model.pHasHttp
                        icon.name: "internet-web-browser"
                        icon.width: Kirigami.Units.iconSizes.smallMedium
                        icon.height: Kirigami.Units.iconSizes.smallMedium
                        implicitWidth: Kirigami.Units.iconSizes.medium
                        implicitHeight: Kirigami.Units.iconSizes.medium
                        PlasmaComponents.ToolTip { text: "Open http://" + model.pDnsName }
                        onClicked: root.openInBrowser(model.pDnsName)
                    }

                    // Copy HTTPS URL
                    PlasmaComponents.ToolButton {
                        visible: model.pHasHttps
                        icon.name: root.copiedText === model.pHttpsUrl ? "checkmark" : "edit-copy"
                        icon.width: Kirigami.Units.iconSizes.smallMedium
                        icon.height: Kirigami.Units.iconSizes.smallMedium
                        implicitWidth: Kirigami.Units.iconSizes.medium
                        implicitHeight: Kirigami.Units.iconSizes.medium
                        PlasmaComponents.ToolTip { text: "Copy " + model.pHttpsUrl }
                        onClicked: root.copyToClipboard(model.pHttpsUrl)
                    }
                }
            }

                Item { Layout.fillHeight: true }
            }
        }
    }
}
