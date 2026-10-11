Option Explicit
On Error Resume Next

' This script deliberately never waits for a batch or the CS2 process.
' It only watches the detached PowerShell supervisor, which owns the restart loop.
Dim shell, fso, root, supervisorPath, commandLine
Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

root = fso.GetParentFolderName(WScript.ScriptFullName)
supervisorPath = fso.BuildPath(root, "supervisor.ps1")
If Not fso.FileExists(supervisorPath) Then WScript.Quit 2

Function IsSupervisorRunning()
    On Error Resume Next
    Dim wmi, processes, proc, cmd, expected
    IsSupervisorRunning = False
    Err.Clear
    Set wmi = GetObject("winmgmts:\\.\root\cimv2")
    If Err.Number <> 0 Then
        Err.Clear
        Exit Function
    End If
    Set processes = wmi.ExecQuery("SELECT Name, CommandLine FROM Win32_Process WHERE Name='powershell.exe'")
    If Err.Number <> 0 Then
        Err.Clear
        Exit Function
    End If
    expected = LCase(supervisorPath)
    For Each proc In processes
        If Not IsNull(proc.CommandLine) Then
            cmd = LCase(CStr(proc.CommandLine))
            If InStr(1, cmd, expected, vbTextCompare) > 0 Then
                IsSupervisorRunning = True
                Exit Function
            End If
        End If
    Next
End Function

Do
    If Not IsSupervisorRunning() Then
        Err.Clear
        commandLine = "powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File " & Chr(34) & supervisorPath & Chr(34)
        shell.Run commandLine, 0, False
        If Err.Number <> 0 Then Err.Clear
    End If
    WScript.Sleep 1000
    If Err.Number <> 0 Then Err.Clear
Loop
