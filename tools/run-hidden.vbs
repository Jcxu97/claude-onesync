' Run a command with no window. Used by the Windows scheduled task.
Set shell = CreateObject("WScript.Shell")
cmd = ""
For i = 0 To WScript.Arguments.Count - 1
  cmd = cmd & """" & WScript.Arguments(i) & """ "
Next
shell.Run cmd, 0, True
