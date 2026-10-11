Option Explicit

Dim shell, fso, root, batPath, cmdExe, commandLine, logPath
Dim runExitCode, runErrorNumber, runErrorDescription, failureKey, lastFailure

Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

root = fso.GetParentFolderName(WScript.ScriptFullName)
batPath = ResolveRunnerBatch(root)
cmdExe = shell.ExpandEnvironmentStrings("%ComSpec%")
logPath = shell.ExpandEnvironmentStrings("%TEMP%\CS2-KUS-Watchdog.log")
lastFailure = ""

Do
    If Len(batPath) = 0 Then
        failureKey = "No run.bat or unique *_run.bat was found in: " & root
        If failureKey <> lastFailure Then LogMessage failureKey
        lastFailure = failureKey
        WScript.Sleep 5000
        batPath = ResolveRunnerBatch(root)
    ElseIf Not fso.FileExists(batPath) Then
        failureKey = "Runner batch no longer exists: " & batPath
        If failureKey <> lastFailure Then LogMessage failureKey
        lastFailure = failureKey
        WScript.Sleep 5000
        batPath = ResolveRunnerBatch(root)
    Else
        ' Execute the batch through cmd.exe so quoting and its exit code are explicit.
        commandLine = Chr(34) & cmdExe & Chr(34) & " /d /s /c " & Chr(34) & Chr(34) & batPath & Chr(34) & Chr(34)

        On Error Resume Next
        Err.Clear
        runExitCode = shell.Run(commandLine, 0, True)
        runErrorNumber = Err.Number
        runErrorDescription = Err.Description
        Err.Clear
        On Error GoTo 0

        If runErrorNumber <> 0 Then
            failureKey = "Could not launch runner (VBScript error " & CStr(runErrorNumber) & "): " & runErrorDescription
            If failureKey <> lastFailure Then LogMessage failureKey
            lastFailure = failureKey
            WScript.Sleep 2000
        ElseIf runExitCode = 100 Then
            lastFailure = ""
            WScript.Sleep 100
        Else
            failureKey = "Runner returned unexpected exit code " & CStr(runExitCode) & "; retrying."
            If failureKey <> lastFailure Then LogMessage failureKey
            lastFailure = failureKey
            WScript.Sleep 2000
        End If
    End If
Loop

Function ResolveRunnerBatch(folderPath)
    Dim expectedPath, folder, item, candidatePath, candidateCount

    expectedPath = folderPath & "\run.bat"
    If fso.FileExists(expectedPath) Then
        ResolveRunnerBatch = expectedPath
        Exit Function
    End If

    candidateCount = 0
    candidatePath = ""
    Set folder = fso.GetFolder(folderPath)
    For Each item In folder.Files
        If LCase(fso.GetExtensionName(item.Name)) = "bat" Then
            If LCase(item.Name) Like "*_run.bat" Then
                candidateCount = candidateCount + 1
                candidatePath = item.Path
            End If
        End If
    Next

    If candidateCount = 1 Then
        ResolveRunnerBatch = candidatePath
    Else
        ResolveRunnerBatch = ""
    End If
End Function

Sub LogMessage(messageText)
    On Error Resume Next
    Dim logHandle
    Set logHandle = fso.OpenTextFile(logPath, 8, True, -1)
    logHandle.WriteLine Now & " " & messageText
    logHandle.Close
    Set logHandle = Nothing
    Err.Clear
End Sub
