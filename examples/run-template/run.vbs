Option Explicit

Dim shell, fso, root, batPath, iniPath
Dim launchCommand, runnerExitCode, launchError, logPath

Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

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

WriteLog "Launcher started. All maintenance and restart behavior is owned by run.bat."
Do
    launchCommand = Chr(34) & batPath & Chr(34) & " --no-pause"

    On Error Resume Next
    runnerExitCode = shell.Run(launchCommand, 0, True)
    launchError = Err.Number
    If launchError <> 0 Then
        WriteLog "ERROR: Could not start run.bat: " & Err.Description
        Err.Clear
    End If
    On Error GoTo 0

    If launchError <> 0 Then
        WScript.Sleep 10000
    ElseIf CLng(runnerExitCode) <> 0 Then
        WriteLog "run.bat exited with code " & runnerExitCode & "; retrying in 10 seconds."
        WScript.Sleep 10000
    Else
        WriteLog "run.bat exited normally; relaunching in 5 seconds."
        WScript.Sleep 5000
    End If
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
