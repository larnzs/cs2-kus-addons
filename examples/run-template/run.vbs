Option Explicit

Dim shell, fso, root, batPath, fastBatPath, fastMarkerPath, launchPath
Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

root = fso.GetParentFolderName(WScript.ScriptFullName)
batPath = fso.BuildPath(root, "run.bat")
fastBatPath = fso.BuildPath(root, "run_fast.bat")
fastMarkerPath = fso.BuildPath(shell.ExpandEnvironmentStrings("%TEMP%"), "CS2-KUS-FastLaunch.enabled")

Do
    If fso.FileExists(fastMarkerPath) And fso.FileExists(fastBatPath) Then
        launchPath = fastBatPath
    Else
        launchPath = batPath
    End If

    shell.Run Chr(34) & launchPath & Chr(34), 0, True
    WScript.Sleep 100
Loop
