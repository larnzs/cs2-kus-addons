Option Explicit

Dim shell, fso, root, repoRoot, batPath, iniPath, serverDir, cs2Path
Dim gameUpdatePath, repoUpdatePath, runtimeAddonsPath, payloadAddonsPath, windowsAddonsPath
Dim tempFolderPath, logPath, comSpec, backupAddonsPath, processEnv
Dim backupOk, backupCount, restoreOk, backupRoot, cycleSucceeded, restoreSucceeded
Dim runnerExitCode, launchCommand, launchError

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
Else
    serverDir = fso.GetAbsolutePathName(serverDir)
End If

cs2Path = fso.GetAbsolutePathName(fso.BuildPath(serverDir, "game\bin\win64\cs2.exe"))
If Not fso.FileExists(cs2Path) Then
    MsgBox "CS2 was not found:" & vbCrLf & cs2Path & vbCrLf & _
        "Run the repository's install.bat first.", vbExclamation, "CS2 Instance Runner"
    WScript.Quit 2
End If

repoRoot = FindRepositoryRoot(serverDir, root)
If Len(repoRoot) = 0 Then
    MsgBox "Could not locate the repository that contains game-update.bat and update.bat." & vbCrLf & _
        "SERVER_DIR: " & serverDir & vbCrLf & _
        "Make sure SERVER_DIR points to the server folder inside the cs2-kus-addons repository.", _
        vbCritical, "CS2 Instance Runner"
    WScript.Quit 3
End If

gameUpdatePath = fso.BuildPath(repoRoot, "game-update.bat")
repoUpdatePath = fso.BuildPath(repoRoot, "update.bat")
If Not fso.FileExists(gameUpdatePath) Then
    MsgBox "The game updater is missing:" & vbCrLf & gameUpdatePath, vbCritical, "CS2 Instance Runner"
    WScript.Quit 4
End If
If Not fso.FileExists(repoUpdatePath) Then
    MsgBox "The repository updater is missing:" & vbCrLf & repoUpdatePath, vbCritical, "CS2 Instance Runner"
    WScript.Quit 5
End If

runtimeAddonsPath = fso.BuildPath(serverDir, "game\csgo\addons")
payloadAddonsPath = fso.BuildPath(repoRoot, "game\csgo\addons")
windowsAddonsPath = fso.BuildPath(payloadAddonsPath, "windows\addons")
tempFolderPath = fso.GetSpecialFolder(2).Path
logPath = fso.BuildPath(tempFolderPath, "CS2-KUS-runner-supervisor.log")
comSpec = shell.ExpandEnvironmentStrings("%ComSpec%")

Set processEnv = shell.Environment("PROCESS")
processEnv("CS2_REPO_ROOT") = repoRoot

WriteLog "Supervisor started. Server: " & cs2Path
WriteLog "Repository resolved from SERVER_DIR: " & repoRoot
WriteLog "run.bat will run one game process, then game-update.bat and update.bat will finish before restart."

Do
    WriteLog "Launching run.bat in supervised one-shot mode."
    launchCommand = Chr(34) & batPath & Chr(34) & " --no-pause --supervised"

    On Error Resume Next
    runnerExitCode = shell.Run(launchCommand, 0, True)
    launchError = Err.Number
    If launchError <> 0 Then
        WriteLog "ERROR: Could not run the instance runner: " & Err.Description
        Err.Clear
    End If
    On Error GoTo 0

    If launchError <> 0 Then
        WScript.Sleep 10000
    ElseIf CLng(runnerExitCode) <> 0 Then
        WriteLog "run.bat exited with code " & runnerExitCode & " before completing a supervised server run. Updates are skipped; retrying in 10 seconds."
        WScript.Sleep 10000
    Else
        WriteLog "CS2 exited; starting maintenance. run.bat has returned, so its internal restart loop cannot race the update."
        backupRoot = CreateRuntimeExtrasBackup()

        Do While backupRoot = "!BACKUP_ERROR!"
            WriteLog "Could not preserve unmanaged runtime add-on files. Updates are paused; retrying in 60 seconds."
            WScript.Sleep 60000
            backupRoot = CreateRuntimeExtrasBackup()
        Loop

        Do
            cycleSucceeded = RunMaintenanceCycle()
            restoreSucceeded = RestoreRuntimeExtras(backupRoot)

            If cycleSucceeded And restoreSucceeded Then
                CleanupBackup backupRoot
                WriteLog "Maintenance completed successfully. The instance runner will start again."
                Exit Do
            End If

            If Not restoreSucceeded Then
                WriteLog "WARNING: Some unmanaged add-on files could not be restored; the backup has been retained."
            End If
            WriteLog "Maintenance did not complete successfully. The server remains stopped; retrying in 60 seconds."
            WScript.Sleep 60000
        Loop
    End If
Loop

Function FindRepositoryRoot(serverPath, scriptPath)
    Dim found
    found = SearchRepositoryAncestors(serverPath)
    If Len(found) = 0 Then found = SearchRepositoryAncestors(scriptPath)
    FindRepositoryRoot = found
End Function

Function SearchRepositoryAncestors(startPath)
    Dim current, parentPath, i
    SearchRepositoryAncestors = ""
    current = fso.GetAbsolutePathName(startPath)

    For i = 1 To 12
        If fso.FileExists(fso.BuildPath(current, "game-update.bat")) And _
           fso.FileExists(fso.BuildPath(current, "update.bat")) And _
           fso.FileExists(fso.BuildPath(current, "DEPENDENCIES.json")) Then
            SearchRepositoryAncestors = current
            Exit Function
        End If

        parentPath = fso.GetParentFolderName(current)
        If Len(parentPath) = 0 Or LCase(parentPath) = LCase(current) Then Exit For
        current = parentPath
    Next
End Function

Function RunMaintenanceCycle()
    RunMaintenanceCycle = False

    WriteLog "Running game-update.bat and waiting for it to finish."
    If Not RunBatch(gameUpdatePath, "game-update.bat") Then
        WriteLog "game-update.bat failed; repository update will not run yet."
        Exit Function
    End If

    WriteLog "Running update.bat to pull the latest private-repository changes and deploy them into server/game/csgo."
    If Not RunBatch(repoUpdatePath, "update.bat") Then
        WriteLog "update.bat failed; the server will remain stopped until maintenance succeeds."
        Exit Function
    End If

    RunMaintenanceCycle = True
End Function

Function RunBatch(batchFile, label)
    Dim commandLine, exitCode
    RunBatch = False

    If Not fso.FileExists(batchFile) Then
        WriteLog "ERROR: Required batch file not found: " & batchFile
        Exit Function
    End If

    commandLine = Chr(34) & comSpec & Chr(34) & " /d /s /c " & _
        Chr(34) & Chr(34) & batchFile & Chr(34) & " --no-pause" & Chr(34)

    On Error Resume Next
    exitCode = shell.Run(commandLine, 0, True)
    If Err.Number <> 0 Then
        WriteLog "ERROR: Could not run " & label & ": " & Err.Description
        Err.Clear
        On Error GoTo 0
        Exit Function
    End If
    On Error GoTo 0

    WriteLog label & " exited with code " & exitCode
    RunBatch = (CLng(exitCode) = 0)
End Function

Function CreateRuntimeExtrasBackup()
    Dim managed, candidateRoot
    CreateRuntimeExtrasBackup = "!BACKUP_ERROR!"
    backupCount = 0
    backupOk = True

    If Not fso.FolderExists(runtimeAddonsPath) Then
        CreateRuntimeExtrasBackup = ""
        Exit Function
    End If

    candidateRoot = fso.BuildPath(tempFolderPath, "CS2-KUS-AddonBackup-" & fso.GetTempName())
    backupAddonsPath = fso.BuildPath(candidateRoot, "addons")

    Set managed = BuildManagedAddonPaths()
    BackupUnmanagedRuntimeFiles runtimeAddonsPath, managed

    If Not backupOk Then
        WriteLog "ERROR: Failed while backing up unmanaged files from " & runtimeAddonsPath
        CleanupBackup candidateRoot
        backupAddonsPath = ""
        Exit Function
    End If

    If backupCount = 0 Then
        CleanupBackup candidateRoot
        backupAddonsPath = ""
        CreateRuntimeExtrasBackup = ""
        WriteLog "No unmanaged runtime add-on files need a backup."
        Exit Function
    End If

    CreateRuntimeExtrasBackup = candidateRoot
    WriteLog "Backed up " & backupCount & " unmanaged runtime add-on file(s) outside the repository."
End Function

Function BuildManagedAddonPaths()
    Dim paths
    Set paths = CreateObject("Scripting.Dictionary")
    paths.CompareMode = vbTextCompare

    ' The shared payload excludes addons\windows; that directory is flattened separately.
    AddPayloadFiles payloadAddonsPath, "", paths, True
    AddPayloadFiles windowsAddonsPath, "", paths, False

    Set BuildManagedAddonPaths = paths
End Function

Sub AddPayloadFiles(folderPath, relativePrefix, paths, skipWindowsAtRoot)
    Dim folder, file, child, relativePath
    If Not fso.FolderExists(folderPath) Then Exit Sub
    Set folder = fso.GetFolder(folderPath)

    For Each file In folder.Files
        relativePath = relativePrefix & file.Name
        If Not paths.Exists(relativePath) Then paths.Add relativePath, True
    Next

    For Each child In folder.SubFolders
        If Not (skipWindowsAtRoot And Len(relativePrefix) = 0 And LCase(child.Name) = "windows") Then
            AddPayloadFiles child.Path, relativePrefix & child.Name & "\", paths, False
        End If
    Next
End Sub

Sub BackupUnmanagedRuntimeFiles(folderPath, managed)
    Dim folder, file, child, relativePath, destination
    On Error Resume Next
    Set folder = fso.GetFolder(folderPath)
    If Err.Number <> 0 Then
        backupOk = False
        WriteLog "ERROR: Could not enumerate runtime add-ons: " & Err.Description
        Err.Clear
        On Error GoTo 0
        Exit Sub
    End If
    On Error GoTo 0

    For Each file In folder.Files
        relativePath = Mid(file.Path, Len(runtimeAddonsPath) + 2)
        If Not IsCssConfigRelative(relativePath) And Not managed.Exists(relativePath) Then
            destination = fso.BuildPath(backupAddonsPath, relativePath)
            If Not EnsureFolderTree(fso.GetParentFolderName(destination)) Then
                backupOk = False
                Exit Sub
            End If

            On Error Resume Next
            fso.CopyFile file.Path, destination, True
            If Err.Number <> 0 Then
                backupOk = False
                WriteLog "ERROR: Could not back up runtime-only file " & file.Path & ": " & Err.Description
                Err.Clear
            Else
                backupCount = backupCount + 1
            End If
            On Error GoTo 0
            If Not backupOk Then Exit Sub
        End If
    Next

    For Each child In folder.SubFolders
        BackupUnmanagedRuntimeFiles child.Path, managed
        If Not backupOk Then Exit Sub
    Next
End Sub

Function RestoreRuntimeExtras(candidateRoot)
    Dim managed, savedAddons
    RestoreRuntimeExtras = False

    If Len(candidateRoot) = 0 Then
        RestoreRuntimeExtras = True
        Exit Function
    End If

    savedAddons = fso.BuildPath(candidateRoot, "addons")
    If Not fso.FolderExists(savedAddons) Then
        RestoreRuntimeExtras = True
        Exit Function
    End If

    restoreOk = True
    Set managed = BuildManagedAddonPaths()
    RestoreSavedFiles savedAddons, managed
    RestoreRuntimeExtras = restoreOk
End Function

Sub RestoreSavedFiles(folderPath, managed)
    Dim folder, file, child, relativePath, destination
    On Error Resume Next
    Set folder = fso.GetFolder(folderPath)
    If Err.Number <> 0 Then
        restoreOk = False
        WriteLog "ERROR: Could not read add-on backup: " & Err.Description
        Err.Clear
        On Error GoTo 0
        Exit Sub
    End If
    On Error GoTo 0

    For Each file In folder.Files
        relativePath = Mid(file.Path, Len(backupAddonsPath) + 2)

        ' A newly tracked file from the updated repository wins over an old runtime-only file.
        ' CounterStrikeSharp configs are managed separately and are intentionally excluded.
        If Not IsCssConfigRelative(relativePath) And Not managed.Exists(relativePath) Then
            destination = fso.BuildPath(runtimeAddonsPath, relativePath)
            If Not EnsureFolderTree(fso.GetParentFolderName(destination)) Then
                restoreOk = False
                Exit Sub
            End If

            On Error Resume Next
            fso.CopyFile file.Path, destination, True
            If Err.Number <> 0 Then
                restoreOk = False
                WriteLog "ERROR: Could not restore runtime-only file " & file.Path & ": " & Err.Description
                Err.Clear
            End If
            On Error GoTo 0
            If Not restoreOk Then Exit Sub
        End If
    Next

    For Each child In folder.SubFolders
        RestoreSavedFiles child.Path, managed
        If Not restoreOk Then Exit Sub
    Next
End Sub

Function EnsureFolderTree(folderPath)
    Dim parentPath
    EnsureFolderTree = False
    If Len(folderPath) = 0 Then Exit Function

    If fso.FolderExists(folderPath) Then
        EnsureFolderTree = True
        Exit Function
    End If

    parentPath = fso.GetParentFolderName(folderPath)
    If Len(parentPath) = 0 Or parentPath = folderPath Then Exit Function
    If Not EnsureFolderTree(parentPath) Then Exit Function

    On Error Resume Next
    fso.CreateFolder folderPath
    If Err.Number <> 0 And Not fso.FolderExists(folderPath) Then
        WriteLog "ERROR: Could not create directory " & folderPath & ": " & Err.Description
        Err.Clear
        On Error GoTo 0
        Exit Function
    End If
    On Error GoTo 0

    EnsureFolderTree = fso.FolderExists(folderPath)
End Function

Function IsCssConfigRelative(relativePath)
    Dim normalized, protectedPrefix
    normalized = LCase(Replace(relativePath, "/", "\"))
    protectedPrefix = "counterstrikesharp\configs\"
    IsCssConfigRelative = (Left(normalized, Len(protectedPrefix)) = protectedPrefix)
End Function

Function SamePath(pathA, pathB)
    Dim a, b
    a = LCase(Replace(fso.GetAbsolutePathName(pathA), "/", "\"))
    b = LCase(Replace(fso.GetAbsolutePathName(pathB), "/", "\"))
    If Right(a, 1) = "\" Then a = Left(a, Len(a) - 1)
    If Right(b, 1) = "\" Then b = Left(b, Len(b) - 1)
    SamePath = (a = b)
End Function

Sub CleanupBackup(candidateRoot)
    If Len(candidateRoot) = 0 Then Exit Sub
    On Error Resume Next
    If fso.FolderExists(candidateRoot) Then fso.DeleteFolder candidateRoot, True
    If Err.Number <> 0 Then
        WriteLog "WARNING: Could not remove temporary add-on backup " & candidateRoot & ": " & Err.Description
        Err.Clear
    End If
    On Error GoTo 0
End Sub

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
