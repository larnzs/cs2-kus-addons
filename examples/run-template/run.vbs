Option Explicit

Dim shell, fso, root, batPath, iniPath, logPath

Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

' Each Instance keeps run.vbs, run.bat and instance.ini together outside the repository.
' Resolve the sibling batch path from this script's folder, not the current working directory.
root = fso.GetParentFolderName(WScript.ScriptFullName)
batPath = fso.BuildPath(root, "run.bat")
iniPath = fso.BuildPath(root, "instance.ini")
logPath = fso.BuildPath(shell.ExpandEnvironmentStrings("%TEMP%"), "CS2-KUS-runner-launcher.log")

If Not fso.FileExists(batPath) Then
    MsgBox "The runner batch file is missing:" & vbCrLf & batPath, vbCritical, "CS2 Instance Runner"
    WScript.Quit 1
End If

If Not fso.FileExists(iniPath) Then
    MsgBox "Missing instance.ini." & vbCrLf & _
        "Copy instance.example.ini to instance.ini, then edit SERVER_DIR and credentials.", _
        vbExclamation, "CS2 Instance Runner"
    WScript.Quit 2
End If

' The first run may perform maintenance. If another cs2.exe is active,
' run.bat skips maintenance and still attempts to launch this Instance.
shell.Environment("Process")("CS2_RUNNER_MAINTENANCE_DONE") = ""

WriteLog "Supervisor started. Repeating the same run.bat every time it returns."

Do
    WriteLog "Launching: " & batPath

    ' Preserve the user's proven WSH pattern: hide the batch window and wait for it to return.
    On Error Resume Next
    shell.Run Chr(34) & batPath & Chr(34), 0, True
    If Err.Number <> 0 Then
        WriteLog "ERROR: run.bat launch failed: " & Err.Description
        Err.Clear
    End If
    On Error GoTo 0

    ' Mark maintenance complete after the first attempt, regardless of CS2's exit code.
    ' The next invocation uses the same run.bat but skips Git/release/game-update maintenance.
    shell.Environment("Process")("CS2_RUNNER_MAINTENANCE_DONE") = "1"

    WScript.Sleep 5000
Loop

Sub WriteLog(message)
    Dim stream
    On Error Resume Next
    Set stream = fso.OpenTextFile(logPath, 8, True)
    If Err.Number = 0 Then
        stream.WriteLine Now & " " & message
        stream.Close
    End If
    Err.Clear
    On Error GoTo 0
End Sub
