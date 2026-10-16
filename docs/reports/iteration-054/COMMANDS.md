# COMMANDS — iteration 054

После самостоятельной распаковки полного архива в `E:\ai\Strata-Q4-Fork`:

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
Set-Location "E:\ai\Strata-Q4-Fork"

& ".\tools\TEST-MODEL-LAUNCHERS.ps1"
Get-PSDrive R | Format-List Name,Used,Free
```

Если `R:` всё ещё является старым 64-GiB RAM-диском, он намеренно не уменьшается автоматически. Один раз отключите его вашим обычным способом, затем запустите профиль:

```powershell
& ".\START-Q8-RAM.ps1"
```

После READY в другом PowerShell:

```powershell
Get-Volume -DriveLetter R | Format-List DriveLetter,FileSystem,FileSystemLabel,Size,SizeRemaining
Get-PSDrive R | Format-List Name,Used,Free
```
