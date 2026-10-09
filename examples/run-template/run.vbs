Option Explicit

Dim shell, fso, root, batPath, iniPath, serverDir, cs2Path
Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

root = fso.GetParentFolderName(WScript.ScriptFullName)
batPath = fso.BuildPath(root, "run.bat")
iniPath = fso.BuildPath(root, "instance.ini")

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

serverDir = ReadSetting(iniPath, "SERVER_DIR")
If Len(serverDir) = 0 Then
    MsgBox "SERVER_DIR is empty in instance.ini.", vbExclamation, "CS2 Instance Runner"
    WScript.Quit 2
End If

If Not (Mid(serverDir, 2, 1) = ":" Or Left(serverDir, 2) = "\\") Then
    serverDir = fso.GetAbsolutePathName(fso.BuildPath(root, serverDir))
End If

cs2Path = fso.BuildPath(serverDir, "game\bin\win64\cs2.exe")
If Not fso.FileExists(cs2Path) Then
    MsgBox "CS2 was not found:" & vbCrLf & cs2Path & vbCrLf & _
        "Run the repository's install.bat first.", vbExclamation, "CS2 Instance Runner"
    WScript.Quit 2
End If

Do
    shell.Run Chr(34) & batPath & Chr(34), 0, True
    WScript.Sleep 5000
Loop

Function ReadSetting(ByVal path, ByVal wantedKey)
    Dim stream, line, position, keyName, value
    ReadSetting = ""
    Set stream = fso.OpenTextFile(path, 1, False)
    Do Until stream.AtEndOfStream
        line = Trim(stream.ReadLine)
        If Len(line) > 0 And Left(line, 1) <> ";" Then
            position = InStr(1, line, "=", vbBinaryCompare)
            If position > 0 Then
                keyName = UCase(Trim(Left(line, position - 1)))
                If keyName = UCase(wantedKey) Then
                    value = Trim(Mid(line, position + 1))
                    ReadSetting = value
                    Exit Do
                End If
            End If
        End If
    Loop
    stream.Close
End Function
