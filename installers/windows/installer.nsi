; =============================================================================
; VedaDB Server - Windows NSIS Installer
; =============================================================================
; Description:
;   Simpler one-file NSIS installer for VedaDB Server on Windows.
;   Provides install page, configuration page, and finish page.
;   Registers Windows Service, adds firewall rule, sets PATH, generates config.
;
; Build:
;   makensis installer.nsi
;
; Dependencies:
;   - NSIS 3.0+ (with nsProcess, LogicLib, FileAssoc plugins)
; =============================================================================

!include "MUI2.nsh"
!include "LogicLib.nsh"
!include "nsDialogs.nsh"
!include "FileFunc.nsh"

; =============================================================================
; Installer Metadata
; =============================================================================
!define PRODUCT_NAME "VedaDB Server"
!define PRODUCT_VERSION "1.0.0"
!define PRODUCT_PUBLISHER "VedaDB Inc."
!define PRODUCT_WEB_SITE "https://vedadb.io"
!define PRODUCT_DIR_REGKEY "Software\Microsoft\Windows\CurrentVersion\App Paths\vedadb-server.exe"
!define PRODUCT_UNINST_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\${PRODUCT_NAME}"
!define PRODUCT_UNINST_ROOT_KEY "HKLM"
!define SERVICE_NAME "VedaDBServer"
!define SERVICE_DISPLAY_NAME "VedaDB Server"

; Default configuration values
!define DEFAULT_PORT "7480"
!define DEFAULT_DATA_DIR "$PROGRAMDATA\VedaDB\data"
!define DEFAULT_LOG_DIR "$PROGRAMDATA\VedaDB\logs"

; =============================================================================
; Installer Settings
; =============================================================================
Name "${PRODUCT_NAME} ${PRODUCT_VERSION}"
OutFile "VedaDB-Setup-${PRODUCT_VERSION}-windows-x86_64.exe"
InstallDir "$PROGRAMFILES64\VedaDB"
InstallDirRegKey HKLM "${PRODUCT_DIR_REGKEY}" ""
RequestExecutionLevel admin
ShowInstDetails show

; =============================================================================
; MUI (Modern UI) Configuration
; =============================================================================
!define MUI_ABORTWARNING
!define MUI_ICON "assets\vedadb.ico"
!define MUI_UNICON "assets\vedadb.ico"
!define MUI_WELCOMEFINISHPAGE_BITMAP "assets\dialog-bg.bmp"
!define MUI_HEADERIMAGE
!define MUI_HEADERIMAGE_BITMAP "assets\banner.bmp"

; --- Welcome Page ---
!define MUI_WELCOMEPAGE_TITLE "Welcome to VedaDB Server Setup"
!define MUI_WELCOMEPAGE_TEXT "This wizard will guide you through the installation of VedaDB Server ${PRODUCT_VERSION}, a high-performance multi-model database.$\r$\n$\r$\nVedaDB supports document, key-value, graph, and vector data models.$\r$\n$\r$\nClick Next to continue."
!insertmacro MUI_PAGE_WELCOME

; --- License Page ---
!define MUI_LICENSEPAGE_RADIOBUTTONS
!insertmacro MUI_PAGE_LICENSE "assets\LICENSE.rtf"

; --- Directory Page ---
!define MUI_PAGE_HEADER_TEXT "Choose Install Location"
!define MUI_PAGE_HEADER_SUBTEXT "Select the folder where VedaDB Server should be installed."
!insertmacro MUI_PAGE_DIRECTORY

; --- Configuration Page (Custom) ---
Page custom ConfigPageShow ConfigPageLeave

; --- Install Page ---
!insertmacro MUI_PAGE_INSTFILES

; --- Finish Page ---
!define MUI_FINISHPAGE_TITLE "VedaDB Server Installation Complete"
!define MUI_FINISHPAGE_TEXT "VedaDB Server ${PRODUCT_VERSION} has been successfully installed on your computer.$\r$\n$\r$\nConnection Info:$\r$\n  Host: localhost$\r$\n  Port: $VedaDB_Port$\r$\n  CLI: vedadb-cli --host localhost --port $VedaDB_Port$\r$\n$\r$\nThe VedaDB Server service has been started automatically."
!define MUI_FINISHPAGE_RUN "$INSTDIR\bin\vedadb-cli.exe"
!define MUI_FINISHPAGE_RUN_PARAMETERS "--help"
!define MUI_FINISHPAGE_SHOWREADME "$INSTDIR\share\README.md"
!insertmacro MUI_PAGE_FINISH

; --- Uninstaller Pages ---
!insertmacro MUI_UNPAGE_WELCOME
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_UNPAGE_FINISH

; =============================================================================
; Language Settings
; =============================================================================
!insertmacro MUI_LANGUAGE "English"

; =============================================================================
; Configuration Page Variables
; =============================================================================
Var VedaDB_Port
Var VedaDB_DataDir
Var VedaDB_LogDir
Var VedaDB_AuthEnabled
Var Dialog
Var PortLabel
Var PortText
Var DataDirLabel
Var DataDirText
Var AuthCheck

; =============================================================================
; Custom Configuration Page
; =============================================================================
Function ConfigPageShow
    nsDialogs::Create 1018
    Pop $Dialog

    ${If} $Dialog == error
        Abort
    ${EndIf}

    !insertmacro MUI_HEADER_TEXT "Configure VedaDB Server" "Set the server port, data directory, and authentication options."

    ; --- Port Configuration ---
    ${NSD_CreateLabel} 0 10u 100% 12u "Server Port (1024-65535):"
    Pop $PortLabel

    ${NSD_CreateNumber} 0 22u 100% 12u "${DEFAULT_PORT}"
    Pop $PortText
    ${NSD_SetText} $PortText $VedaDB_Port

    ; --- Data Directory ---
    ${NSD_CreateLabel} 0 45u 100% 12u "Data Directory:"
    Pop $DataDirLabel

    ${NSD_CreateDirRequest} 0 57u 80% 12u "${DEFAULT_DATA_DIR}"
    Pop $DataDirText
    ${NSD_SetText} $DataDirText $VedaDB_DataDir

    ${NSD_CreateBrowseButton} 85% 57u 15% 12u "Browse..."
    Pop $0
    ${NSD_OnClick} $0 OnBrowseDataDir

    ; --- Authentication ---
    ${NSD_CreateCheckbox} 0 85u 100% 12u "Enable authentication (recommended)"
    Pop $AuthCheck
    ${NSD_SetState} $AuthCheck ${BST_CHECKED}

    ; --- Firewall Note ---
    ${NSD_CreateLabel} 0 105u 100% 24u "A Windows Firewall exception will be added for the configured port to allow remote connections."

    nsDialogs::Show
FunctionEnd

Function OnBrowseDataDir
    ${NSD_GetText} $DataDirText $0
    nsDialogs::SelectFolderDialog "Select Data Directory" $0
    Pop $0
    ${If} $0 != error
        ${NSD_SetText} $DataDirText $0
    ${EndIf}
FunctionEnd

Function ConfigPageLeave
    ; Validate port
    ${NSD_GetText} $PortText $VedaDB_Port
    ${NSD_GetText} $DataDirText $VedaDB_DataDir

    ; Port must be numeric and in valid range
    IntCmp $VedaDB_Port 1024 port_ok port_too_low port_ok
    port_too_low:
        MessageBox MB_OK "Port must be between 1024 and 65535."
        Abort
    port_ok:
    IntCmp $VedaDB_Port 65535 port_ok2 port_ok2 port_too_high
    port_too_high:
        MessageBox MB_OK "Port must be between 1024 and 65535."
        Abort
    port_ok2:

    ; Set log dir based on data dir parent
    StrCpy $VedaDB_LogDir "$PROGRAMDATA\VedaDB\logs"

    ; Check auth
    ${NSD_GetState} $AuthCheck $0
    ${If} $0 == ${BST_CHECKED}
        StrCpy $VedaDB_AuthEnabled "1"
    ${Else}
        StrCpy $VedaDB_AuthEnabled "0"
    ${EndIf}
FunctionEnd

; =============================================================================
; Installer Section
; =============================================================================
Section "VedaDB Server" SEC_SERVER
    SectionIn RO
    SetOutPath "$INSTDIR\bin"
    SetOverwrite on

    DetailPrint "Installing VedaDB Server binaries..."

    ; --- Install server binaries ---
    File "..\..\bin\windows-amd64\vedadb-server.exe"
    File "..\..\bin\windows-amd64\vedadb-cli.exe"
    File "..\..\bin\windows-amd64\vedadb-bench.exe"
    File "..\..\bin\windows-amd64\vedadb-backup.exe"

    ; --- Install supporting files ---
    SetOutPath "$INSTDIR\share"
    File "..\..\LICENSE"
    File "..\..\README.md"

    ; --- Install icons ---
    SetOutPath "$INSTDIR\icons"
    File "assets\vedadb.ico"

    ; --- Create data directories ---
    DetailPrint "Creating data directories..."
    CreateDirectory "$PROGRAMDATA\VedaDB\data"
    CreateDirectory "$PROGRAMDATA\VedaDB\logs"

    ; Grant Network Service access to data directories
    nsExec::ExecToLog 'icacls "$PROGRAMDATA\VedaDB" /grant "NT AUTHORITY\Network Service":(OI)(CI)F'
    nsExec::ExecToLog 'icacls "$PROGRAMDATA\VedaDB\data" /grant "NT AUTHORITY\Network Service":(OI)(CI)F'
    nsExec::ExecToLog 'icacls "$PROGRAMDATA\VedaDB\logs" /grant "NT AUTHORITY\Network Service":(OI)(CI)F'

    ; --- Generate configuration file ---
    DetailPrint "Generating configuration..."
    Call GenerateConfig

    ; --- Register Windows Service ---
    DetailPrint "Registering Windows Service..."
    nsExec::ExecToLog '"$INSTDIR\bin\vedadb-server.exe" --service-install --config "$PROGRAMDATA\VedaDB\config.yaml" --service-name "${SERVICE_NAME}"'
    nsExec::ExecToLog 'sc config ${SERVICE_NAME} start= auto obj= "NT AUTHORITY\Network Service" displayname= "${SERVICE_DISPLAY_NAME}"'
    nsExec::ExecToLog 'sc failure ${SERVICE_NAME} reset= 86400 actions= restart/10000/restart/30000/none/0'

    ; --- Start the service ---
    DetailPrint "Starting VedaDB Server service..."
    nsExec::ExecToLog 'sc start ${SERVICE_NAME}'

    ; --- Add to PATH ---
    DetailPrint "Adding to system PATH..."
    nsExec::ExecToLog 'setx /M PATH "%PATH%;$INSTDIR\bin"'

    ; --- Add Windows Firewall rule ---
    DetailPrint "Adding Windows Firewall exception..."
    nsExec::ExecToLog 'netsh advfirewall firewall add rule name="VedaDB Server (Port $VedaDB_Port)" dir=in action=allow protocol=tcp localport=$VedaDB_Port program="$INSTDIR\bin\vedadb-server.exe" profile=any enable=yes'

    ; --- Create Start Menu shortcuts ---
    DetailPrint "Creating shortcuts..."
    CreateDirectory "$SMPROGRAMS\VedaDB"
    CreateShortcut "$SMPROGRAMS\VedaDB\VedaDB CLI.lnk" "$SYSDIR\cmd.exe" '/k "vedadb-cli --help"' "$INSTDIR\icons\vedadb.ico"
    CreateShortcut "$SMPROGRAMS\VedaDB\VedaDB Documentation.lnk" "https://docs.vedadb.io" "" "$INSTDIR\icons\vedadb.ico"
    CreateShortcut "$SMPROGRAMS\VedaDB\Uninstall VedaDB.lnk" "$INSTDIR\uninstall.exe"

    ; --- Registry entries ---
    WriteRegStr HKLM "${PRODUCT_DIR_REGKEY}" "" "$INSTDIR\bin\vedadb-server.exe"
    WriteRegStr HKLM "${PRODUCT_UNINST_KEY}" "DisplayName" "${PRODUCT_NAME}"
    WriteRegStr HKLM "${PRODUCT_UNINST_KEY}" "UninstallString" "$INSTDIR\uninstall.exe"
    WriteRegStr HKLM "${PRODUCT_UNINST_KEY}" "DisplayIcon" "$INSTDIR\icons\vedadb.ico"
    WriteRegStr HKLM "${PRODUCT_UNINST_KEY}" "DisplayVersion" "${PRODUCT_VERSION}"
    WriteRegStr HKLM "${PRODUCT_UNINST_KEY}" "URLInfoAbout" "${PRODUCT_WEB_SITE}"
    WriteRegStr HKLM "${PRODUCT_UNINST_KEY}" "Publisher" "${PRODUCT_PUBLISHER}"
    WriteRegStr HKLM "${PRODUCT_UNINST_KEY}" "InstallLocation" "$INSTDIR"
    WriteRegDWORD HKLM "${PRODUCT_UNINST_KEY}" "EstimatedSize" 50000

    ; --- Create uninstaller ---
    WriteUninstaller "$INSTDIR\uninstall.exe"

    DetailPrint "Installation complete!"
SectionEnd

; =============================================================================
; Config File Generator Function
; =============================================================================
Function GenerateConfig
    ; Build the config.yaml content
    Push $R0

    FileOpen $R0 "$PROGRAMDATA\VedaDB\config.yaml" w

    FileWrite $R0 "# ============================================================================$
"
    FileWrite $R0 "# VedaDB Server Configuration$
"
    FileWrite $R0 "# Auto-generated by VedaDB Installer v${PRODUCT_VERSION}$
"
    FileWrite $R0 "# ============================================================================$
"
    FileWrite $R0 "$
"
    FileWrite $R0 "server:$
"
    FileWrite $R0 "  port: $VedaDB_Port$
"
    FileWrite $R0 "  host: 0.0.0.0$
"
    FileWrite $R0 "  data_dir: $VedaDB_DataDir$
"
    FileWrite $R0 "  max_connections: 1000$
"
    FileWrite $R0 "  query_timeout: 30s$
"
    FileWrite $R0 "$
"
    FileWrite $R0 "auth:$
"
    FileWrite $R0 "  enabled: $VedaDB_AuthEnabled$
"
    FileWrite $R0 "  method: password$
"
    FileWrite $R0 "  admin_user: admin$
"
    FileWrite $R0 "$
"
    FileWrite $R0 "logging:$
"
    FileWrite $R0 "  level: info$
"
    FileWrite $R0 "  file: $VedaDB_LogDir\vedadb-server.log$
"
    FileWrite $R0 "  max_size: 100MB$
"
    FileWrite $R0 "  max_files: 5$
"
    FileWrite $R0 "  format: json$
"
    FileWrite $R0 "$
"
    FileWrite $R0 "engines:$
"
    FileWrite $R0 "  document:$
"
    FileWrite $R0 "    enabled: true$
"
    FileWrite $R0 "  keyvalue:$
"
    FileWrite $R0 "    enabled: true$
"
    FileWrite $R0 "  graph:$
"
    FileWrite $R0 "    enabled: true$
"
    FileWrite $R0 "  vector:$
"
    FileWrite $R0 "    enabled: true$
"
    FileWrite $R0 "  timeseries:$
"
    FileWrite $R0 "    enabled: true$
"

    FileClose $R0

    ; Secure config file permissions
    nsExec::ExecToLog 'icacls "$PROGRAMDATA\VedaDB\config.yaml" /grant "NT AUTHORITY\Network Service":(R)'

    Pop $R0
FunctionEnd

; =============================================================================
; Uninstaller Section
; =============================================================================
Section "Uninstall"
    DetailPrint "Stopping VedaDB Server service..."

    ; --- Stop the service ---
    nsExec::ExecToLog 'net stop ${SERVICE_NAME}'
    Sleep 2000

    ; --- Remove the service ---
    DetailPrint "Removing Windows Service..."
    nsExec::ExecToLog '"$INSTDIR\bin\vedadb-server.exe" --service-uninstall --service-name "${SERVICE_NAME}"'
    nsExec::ExecToLog 'sc delete ${SERVICE_NAME}'

    ; --- Remove firewall rule ---
    DetailPrint "Removing firewall exception..."
    nsExec::ExecToLog 'netsh advfirewall firewall delete rule name="VedaDB Server (Port $VedaDB_Port)"'

    ; --- Ask about data cleanup ---
    MessageBox MB_YESNOCANCEL|MB_ICONQUESTION \
        "Do you want to remove all database data and configuration files?$
$
Data location: $PROGRAMDATA\VedaDB$
$
Click Yes to remove everything.$
Click No to keep data (only remove program files).$
Click Cancel to abort uninstallation." \
        IDYES cleanup_all IDNO cleanup_partial

    ; Cancel was clicked
    DetailPrint "Uninstallation cancelled."
    Abort

    cleanup_all:
        DetailPrint "Removing data and configuration..."
        RMDir /r "$PROGRAMDATA\VedaDB"
        Goto shortcuts

    cleanup_partial:
        DetailPrint "Keeping data at $PROGRAMDATA\VedaDB"
        ; Only remove config, keep data
        Delete "$PROGRAMDATA\VedaDB\config.yaml"

    shortcuts:
    ; --- Remove Start Menu shortcuts ---
    DetailPrint "Removing shortcuts..."
    Delete "$SMPROGRAMS\VedaDB\VedaDB CLI.lnk"
    Delete "$SMPROGRAMS\VedaDB\VedaDB Documentation.lnk"
    Delete "$SMPROGRAMS\VedaDB\Uninstall VedaDB.lnk"
    RMDir "$SMPROGRAMS\VedaDB"

    ; --- Remove program files ---
    DetailPrint "Removing program files..."
    Delete "$INSTDIR\bin\vedadb-server.exe"
    Delete "$INSTDIR\bin\vedadb-cli.exe"
    Delete "$INSTDIR\bin\vedadb-bench.exe"
    Delete "$INSTDIR\bin\vedadb-backup.exe"
    Delete "$INSTDIR\share\LICENSE"
    Delete "$INSTDIR\share\README.md"
    Delete "$INSTDIR\icons\vedadb.ico"
    Delete "$INSTDIR\uninstall.exe"
    RMDir "$INSTDIR\bin"
    RMDir "$INSTDIR\share"
    RMDir "$INSTDIR\icons"
    RMDir "$INSTDIR"

    ; --- Remove registry entries ---
    DeleteRegKey HKLM "${PRODUCT_DIR_REGKEY}"
    DeleteRegKey HKLM "${PRODUCT_UNINST_KEY}"

    DetailPrint "VedaDB Server has been uninstalled."
SectionEnd
