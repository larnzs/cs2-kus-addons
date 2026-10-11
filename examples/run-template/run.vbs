Option Explicit

Dim shell, fso, root, normalBatPath, fastBatPath, iniPath
Dim batPath, runnerExitCode, launchError, logPath, fastMode

Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

' All Instance runner files live beside this VBS, outside the repository.
' Resolve paths from this script's own folder, never from the current working directory.
root = fso.GetParentFolderName(WScript.ScriptFullName)
normalBatPath = fso.BuildPath(root, "run.bat")
fastBatPath = fso.BuildPath(root, "run-fast.bat")
iniPath = fso.BuildPath(root, "instance.ini")
logPath = fso.BuildPath(shell.ExpandEnvironmentStrings("%TEMP%"), "CS2-KUS-runner-launcher.log")

' Tell child batch files not to wait for keyboard input when launched by this supervisor.
shell.Environment("Process")("CS2_RUNNER_NO_PAUSE") = "1"

If Not fso.FileExists(normalBatPath) Then
    MsgBox "The maintenance runner batch file is missing:" & vbCrLf & normalBatPath, vbCritical, "CS2 Instance Runner"
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

fastMode = False
WriteLog "Supervisor started. First launch uses run.bat; after CS2 exits it uses run-fast.bat."

Do
    If fastMode Then
        batPath = fastBatPath
    Else
        batPath = normalBatPath
    End If

    ' Match the known-working WSH pattern: directly run the sibling .bat,
    ' hide its window, and wait for it to finish so its exit code is available.
    runnerExitCode = -1
    launchError = 0
    WriteLog "Launching: " & batPath

    On Error Resume Next
    runnerExitCode = shell.Run(Chr(34) & batPath & Chr(34), 0, True)
    launchError = Err.Number
    If launchError <> 0 Then
        WriteLog "ERROR: Could not launch " & batPath & ": " & Err.Description
        Err.Clear
    End If
    On Error GoTo 0

    If launchError = 0 Then
        WriteLog "Runner returned exit code " & CStr(runnerExitCode) & " from " & batPath
        If Not fastMode Then
            ' Never make anti-crash recovery depend on the exact child exit code.
            ' Once the first maintenance runner returns, every retry uses the fast runner.
            fastMode = True
            WriteLog "Initial runner returned; all subsequent restarts use run-fast.bat, regardless of the reported exit code."
        Else
            WriteLog "Fast runner returned; another fast restart will be attempted."
        End If
    Else
        ' If launch itself fails, avoid repeatedly entering the update path.
        fastMode = True
        WriteLog "Launch failed; subsequent attempts will use run-fast.bat."
    End If

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
