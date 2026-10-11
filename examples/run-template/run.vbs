Option Explicit

Dim shell, fso, root, batPath
Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

root = fso.GetParentFolderName(WScript.ScriptFullName)
batPath = root & "\\run.bat"

Do
    shell.Run Chr(34) & batPath & Chr(34), 0, True
    WScript.Sleep 100
Loop
