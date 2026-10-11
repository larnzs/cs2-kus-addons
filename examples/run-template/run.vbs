Option Explicit

Dim shell, fso, root, batPath, iniPath, logPath
Dim runnerExitCode, launchError

Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

' The VBS, run.bat and instance.ini are siblings in the external Instance directory.
' Always resolve run.bat relative to this script, not the current working directory.
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

' These are inherited by run.bat. Maintenance is allowed on the first attempt only;
' the batch runner itself skips maintenance if another CS2 instance is already active.
shell.Environment("Process")("CS2_RUNNER_NO_PAUSE") = "1"
shell.Environment("Process")("CS2_RUNNER_MAINTENANCE_DONE") = ""

WriteLog "Anti-crash supervisor started. Repeatedly launching the same run.bat; maintenance is attempted only on the first launch."

Do
    runnerExitCode = -1
    launchError = 0
    WriteLog "Launching: " & batPath

    ' Same simple, known-working pattern: hide the batch window and wait for it to return.
    On Error Resume Next
    runnerExitCode = shell.Run(Chr(34) & batPath & Chr(34), 0, True)
    launchError = Err.Number
    If launchError <> 0 Then
        WriteLog "ERROR: Could not launch run.bat: " & Err.Description
        Err.Clear
    End If
    On Error GoTo 0

    If launchError = 0 Then
        WriteLog "run.bat returned with exit code " & CStr(runnerExitCode)
    End If

    ' Mark maintenance complete regardless of the child's exit code. All subsequent
    ' loops execute the same run.bat, but it immediately skips Git/release/game updates.
    shell.Environment("Process")("CS2_RUNNER_MAINTENANCE_DONE") = "1"

    ' Poll/restart 100 ms after run.bat returns; do not depend on a specific exit code.
    WScript.Sleep 100
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
