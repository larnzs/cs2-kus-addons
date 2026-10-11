Option Explicit

Dim shell, fso, root, batPath, fastBatPath, iniPath
Dim launchCommand, runnerExitCode, launchError, logPath, fastMode

Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

root = fso.GetParentFolderName(WScript.ScriptFullName)
batPath = fso.BuildPath(root, "run.bat")
fastBatPath = fso.BuildPath(root, "run-fast.bat")
iniPath = fso.BuildPath(root, "instance.ini")
fastMode = False
logPath = fso.BuildPath(shell.ExpandEnvironmentStrings("%TEMP%"), "CS2-KUS-runner-launcher.log")

If Not fso.FileExists(batPath) Then
    MsgBox "The maintenance runner batch file is missing:" & vbCrLf & batPath, vbCritical, "CS2 Instance Runner"
    WScript.Quit 1
End If

If Not fso.FileExists(fastBatPath) Then
    MsgBox "The fast runner batch file is missing:" & vbCrLf & fastBatPath, vbCritical, "CS2 Instance Runner"
    WScript.Quit 1
End If

If Not fso.FileExists(iniPath) Then
    MsgBox "Missing instance.ini." & vbCrLf & _
        "Copy instance.example.ini to instance.ini, then edit SERVER_DIR and credentials.", _
        vbExclamation, "CS2 Instance Runner"
    WScript.Quit 2
End If

WriteLog "Supervisor started. First attempt uses run.bat (maintenance); after a CS2 exit it switches to run-fast.bat."
Do
    If fastMode Then
        batPath = fastBatPath
    Else
        batPath = fso.BuildPath(root, "run.bat")
    End If
    ' Explicitly invoke batch files through cmd.exe so arguments and exit codes are preserved.
    ' /s /c requires the doubled opening quote around the full command string.
    launchCommand = Chr(34) & shell.ExpandEnvironmentStrings("%ComSpec%") & Chr(34) & _
        " /d /s /c " & Chr(34) & Chr(34) & batPath & Chr(34) & " --no-pause" & Chr(34)

    On Error Resume Next
    runnerExitCode = shell.Run(launchCommand, 0, True)
    launchError = Err.Number
    If launchError <> 0 Then
        WriteLog "ERROR: Could not start " & batPath & ": " & Err.Description
        Err.Clear
    End If
    On Error GoTo 0

    If launchError <> 0 Then
        WScript.Sleep 10000
    ElseIf CLng(runnerExitCode) = 100 Then
        If Not fastMode Then
            WriteLog "CS2 process exited; switching to run-fast.bat. The next restart bypasses all updates."
        Else
            WriteLog "Fast runner reports CS2 exited; immediately restarting without delay or maintenance."
        End If
        fastMode = True
        'No sleep here: relaunch as soon as the previous CS2 process has ended.
    ElseIf CLng(runnerExitCode) = 101 Then
        WriteLog "Maintenance failed before server launch; switching to run-fast.bat immediately so an update problem cannot block recovery."
        fastMode = True
    ElseIf CLng(runnerExitCode) <> 0 Then
        WriteLog "Runner exited with error code " & runnerExitCode & "; retrying in 10 seconds."
        WScript.Sleep 10000
    Else
        WriteLog "Runner returned without the CS2 exit signal; retrying in 1 second."
        WScript.Sleep 1000
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
