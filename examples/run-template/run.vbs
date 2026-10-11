Option Explicit
On Error Resume Next

Dim shell, fso, root, updatePath, batPath, updateResult
Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

root = fso.GetParentFolderName(WScript.ScriptFullName)
updatePath = fso.BuildPath(root, "update.bat")
batPath = fso.BuildPath(root, "run.bat")

' Run shared maintenance exactly once when this watchdog starts.
' The anti-crash loop below never calls the updater.
If Not fso.FileExists(updatePath) Then
    WScript.Echo "Missing instance updater: " & updatePath
    WScript.Quit 2
End If
If Not fso.FileExists(batPath) Then
    WScript.Echo "Missing server runner: " & batPath
    WScript.Quit 2
End If

Err.Clear
updateResult = shell.Run(Chr(34) & updatePath & Chr(34), 1, True)
If Err.Number <> 0 Then
    WScript.Echo "Could not execute update.bat: " & Err.Description
    WScript.Quit 2
End If
If updateResult <> 0 Then
    WScript.Echo "Startup maintenance failed with exit code " & updateResult & ". Fix the update error, then restart run.vbs."
    WScript.Quit updateResult
End If

' Classic watchdog: wait for one run.bat/CS2 lifetime, then immediately retry.
' A transient WSH automation error must not permanently terminate this loop.
Do
    Err.Clear
    shell.Run(Chr(34) & batPath & Chr(34), 0, True)
    If Err.Number <> 0 Then
        Err.Clear
        WScript.Sleep 1000
    Else
        WScript.Sleep 100
    End If
Loop
