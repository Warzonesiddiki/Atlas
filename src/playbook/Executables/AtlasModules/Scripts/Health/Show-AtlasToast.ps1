# Show-AtlasToast.ps1
# Displays a WinRT toast notification after Atlas install finishes.
# Safe to invoke headless; fails silently if the WinRT API is unavailable
# (e.g. during OOBE before ShellExperienceHost is fully initialised).
param(
    [string]$Title = 'AtlasOS installed',
    [string]$Message = 'Installation finished. See the Atlas folder on your Desktop to start exploring.',
    [string]$HealthReportPath
)

$ErrorActionPreference = 'SilentlyContinue'

try {
    [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
    [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] | Out-Null

    $template = @"
<toast duration="long">
  <visual>
    <binding template="ToastGeneric">
      <text>$([System.Security.SecurityElement]::Escape($Title))</text>
      <text>$([System.Security.SecurityElement]::Escape($Message))</text>
    </binding>
  </visual>
  $(-not [string]::IsNullOrWhiteSpace($HealthReportPath) ? "<audio silent=""true""/>" : "")
</toast>
"@

    $xml = New-Object Windows.Data.Xml.Dom.XmlDocument
    $xml.LoadXml($template)
    $toast = New-Object Windows.UI.Notifications.ToastNotification $xml
    [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('AtlasOS').Show($toast)
} catch {
    # Toast not available (e.g. system account); write to log and exit cleanly.
    Write-Host "Toast unavailable: $($_.Exception.Message)"
}
