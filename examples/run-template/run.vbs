Option Explicit

Dim shell, fso, root, batPath, runnerCommand, maintenanceDone

Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

' run.vbs and run.bat are siblings in the external Instance directory.
' Resolve the batch path from this script, not the current working directory.
root = fso.GetParentFolderName(WScript.ScriptFullName)
batPath = fso.BuildPath(root, "run.bat")

If Not fso.FileExists(batPath) Then
    MsgBox "The runner batch file is missing:" & vbCrLf & batPath, vbCritical, "CS2 Instance Runner"
    WScript.Quit 1
End If

maintenanceDone = False

' Keep the supervisor deliberately simple: always run the same run.bat.
' The first attempt can perform maintenance; retries pass --no-update.
Do
    If maintenanceDone Then
        runnerCommand = Chr(34) & batPath & Chr(34) & " --no-update"
    Else
        runnerCommand = Chr(34) & batPath & Chr(34)
    End If

    ' Same proven WSH pattern: hide the batch window and wait until it returns.
    ' Ignore a launch-side VBScript error so a failed attempt does not end the loop.
    On Error Resume Next
    shell.Run runnerCommand, 0, True
    Err.Clear
    On Error GoTo 0

    maintenanceDone = True
    WScript.Sleep 5000
Loop
